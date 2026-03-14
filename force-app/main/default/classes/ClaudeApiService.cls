/**
 * AI Service for Voice-to-CRM
 * Supports both Claude (Anthropic) and OpenAI — switchable via Custom Metadata
 *
 * Setup → Custom Metadata Types → Voice CRM Settings → Default:
 *   - AI_Provider__c: "OpenAI" or "Claude"
 *   - OpenAI_API_Key__c: your OpenAI key (sk-...)
 *   - Claude_API_Key__c: your Anthropic key (sk-ant-...)
 */
public with sharing class ClaudeApiService {

    // Claude config
    private static final String CLAUDE_ENDPOINT = 'https://api.anthropic.com/v1/messages';
    private static final String CLAUDE_MODEL = 'claude-sonnet-4-20250514';
    private static final String CLAUDE_API_VERSION = '2023-06-01';

    // OpenAI config
    private static final String OPENAI_ENDPOINT = 'https://api.openai.com/v1/chat/completions';
    private static final String OPENAI_MODEL = 'gpt-4o-mini';

    private static final Integer MAX_TOKENS = 2048;

    /**
     * Send a message to the configured AI provider and return the text response
     */
    public static String sendMessage(String userMessage) {
        Voice_CRM_Settings__mdt settings = getSettings();
        String provider = settings.AI_Provider__c;

        if (provider == 'OpenAI') {
            return sendToOpenAI(userMessage, settings.OpenAI_API_Key__c);
        } else {
            return sendToClaude(userMessage, settings.Claude_API_Key__c);
        }
    }

    // ─── OpenAI ───
    private static String sendToOpenAI(String userMessage, String apiKey) {
        if (String.isBlank(apiKey)) {
            throw new AuraHandledException('OpenAI API key not configured. Go to Setup → Custom Metadata Types → Voice CRM Settings → Default.');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(OPENAI_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + apiKey);
        req.setTimeout(60000);

        Map<String, Object> body = new Map<String, Object>{
            'model' => OPENAI_MODEL,
            'max_tokens' => MAX_TOKENS,
            'temperature' => 0.1,
            'messages' => new List<Map<String, String>>{
                new Map<String, String>{
                    'role' => 'user',
                    'content' => userMessage
                }
            }
        };

        req.setBody(JSON.serialize(body));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            System.debug('OpenAI API full response: ' + res.getBody());
            throw new AuraHandledException('OpenAI API error (' + res.getStatusCode() + '): ' + res.getBody().left(500));
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> choices = (List<Object>) responseMap.get('choices');

        if (choices != null && !choices.isEmpty()) {
            Map<String, Object> firstChoice = (Map<String, Object>) choices[0];
            Map<String, Object> message = (Map<String, Object>) firstChoice.get('message');
            return (String) message.get('content');
        }

        throw new AuraHandledException('Empty response from OpenAI API');
    }

    // ─── Claude ───
    private static String sendToClaude(String userMessage, String apiKey) {
        if (String.isBlank(apiKey)) {
            throw new AuraHandledException('Claude API key not configured. Go to Setup → Custom Metadata Types → Voice CRM Settings → Default.');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(CLAUDE_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', apiKey);
        req.setHeader('anthropic-version', CLAUDE_API_VERSION);
        req.setTimeout(60000);

        Map<String, Object> body = new Map<String, Object>{
            'model' => CLAUDE_MODEL,
            'max_tokens' => MAX_TOKENS,
            'messages' => new List<Map<String, String>>{
                new Map<String, String>{
                    'role' => 'user',
                    'content' => userMessage
                }
            }
        };

        req.setBody(JSON.serialize(body));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            System.debug('Claude API full response: ' + res.getBody());
            throw new AuraHandledException('Claude API error (' + res.getStatusCode() + '): ' + res.getBody().left(500));
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> content = (List<Object>) responseMap.get('content');

        if (content != null && !content.isEmpty()) {
            Map<String, Object> firstBlock = (Map<String, Object>) content[0];
            return (String) firstBlock.get('text');
        }

        throw new AuraHandledException('Empty response from Claude API');
    }

    // ─── Settings ───
    private static Voice_CRM_Settings__mdt getSettings() {
        try {
            List<Voice_CRM_Settings__mdt> settings = [
                SELECT AI_Provider__c, Claude_API_Key__c, OpenAI_API_Key__c
                FROM Voice_CRM_Settings__mdt
                WHERE DeveloperName = 'Default'
                LIMIT 1
            ];
            if (!settings.isEmpty()) {
                return settings[0];
            }
        } catch (Exception e) {
            System.debug('Error retrieving settings: ' + e.getMessage());
        }
        throw new AuraHandledException('Voice CRM Settings not found. Please create a "Default" record in Voice_CRM_Settings__mdt.');
    }
}
