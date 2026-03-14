/**
 * Controller for Voice-to-CRM LWC
 * Handles AI parsing of voice transcripts and executing parsed actions
 */
public with sharing class VoiceToCrmController {

    /**
     * Sends the voice transcript to Claude API for parsing into structured Salesforce actions
     */
    @AuraEnabled
    public static String parseVoiceInput(String transcript, Id opportunityId, String currentStage, String accountName) {
        // Gather org metadata for AI context
        String stageValues = getPicklistValues('Opportunity', 'StageName');
        String contactRoleValues = getPicklistValues('OpportunityContactRole', 'Role');

        // Build the prompt
        String prompt = buildParsingPrompt(transcript, opportunityId, currentStage, accountName, stageValues, contactRoleValues);

        // Call Claude API
        String aiResponse = ClaudeApiService.sendMessage(prompt);

        // Extract JSON array from response
        String jsonActions = extractJsonFromResponse(aiResponse);

        return jsonActions;
    }

    /**
     * Executes the parsed actions against Salesforce
     */
    @AuraEnabled
    public static void executeActions(String actionsJson, Id opportunityId) {
        List<Object> actions = (List<Object>) JSON.deserializeUntyped(actionsJson);

        List<Task> tasksToInsert = new List<Task>();
        List<Contact> contactsToInsert = new List<Contact>();
        Opportunity opp = [SELECT Id, StageName, CloseDate, Probability, NextStep, AccountId FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
        Boolean oppUpdated = false;

        for (Object actionObj : actions) {
            Map<String, Object> action = (Map<String, Object>) actionObj;
            String actionType = (String) action.get('type');

            if (actionType == 'update') {
                oppUpdated = applyOppUpdate(opp, action) || oppUpdated;
            } else if (actionType == 'activity') {
                tasksToInsert.add(createActivityRecord(opp, action));
            } else if (actionType == 'contact') {
                contactsToInsert.add(createContactRecord(opp, action));
            } else if (actionType == 'task') {
                tasksToInsert.add(createTaskRecord(opp, action));
            }
        }

        // DML operations
        if (oppUpdated) {
            update opp;
        }

        if (!contactsToInsert.isEmpty()) {
            insert contactsToInsert;

            // Create contact roles for newly created contacts
            List<OpportunityContactRole> roles = new List<OpportunityContactRole>();
            for (Object actionObj : actions) {
                Map<String, Object> action = (Map<String, Object>) actionObj;
                if ((String) action.get('type') == 'role' || (String) action.get('type') == 'contact') {
                    String contactName = (String) action.get('name');
                    String roleName = (String) action.get('role');
                    if (String.isNotBlank(roleName)) {
                        // Find the matching inserted contact
                        for (Contact c : contactsToInsert) {
                            String fullName = c.FirstName != null ? c.FirstName + ' ' + c.LastName : c.LastName;
                            if (fullName.containsIgnoreCase(contactName != null ? contactName : '')) {
                                roles.add(new OpportunityContactRole(
                                    OpportunityId = opportunityId,
                                    ContactId = c.Id,
                                    Role = roleName
                                ));
                                break;
                            }
                        }
                    }
                }
            }
            if (!roles.isEmpty()) {
                insert roles;
            }
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

    // ─── Private Helpers ───

    private static String buildParsingPrompt(String transcript, Id opportunityId, String currentStage, String accountName, String stageValues, String contactRoleValues) {
        return 'You are a Salesforce CRM assistant. Parse the following voice transcript into structured actions.\n\n'
            + 'Context:\n'
            + '- Opportunity ID: ' + opportunityId + '\n'
            + '- Current Stage: ' + currentStage + '\n'
            + '- Account: ' + accountName + '\n'
            + '- Valid Stages: ' + stageValues + '\n'
            + '- Valid Contact Roles: ' + contactRoleValues + '\n\n'
            + 'Transcript: "' + transcript + '"\n\n'
            + 'Return ONLY a JSON array of action objects. Each object must have:\n'
            + '- "type": one of "update", "activity", "contact", "role", "task"\n'
            + '- "label": short description (e.g., "Update Stage")\n'
            + '- "detail": human-readable detail (e.g., "Negotiation → Legal Review")\n\n'
            + 'For "update" type, also include: "field" (API field name like StageName, CloseDate, Probability, NextStep), "value" (new value)\n'
            + 'For "contact" type, include: "firstName", "lastName", "title", "role" (contact role on opportunity)\n'
            + 'For "role" type, include: "name" (contact name), "role" (role value)\n'
            + 'For "task" type, include: "subject", "dueDate" (YYYY-MM-DD format), "description"\n'
            + 'For "activity" type, include: "subject", "description"\n\n'
            + 'Use the valid stage/role values provided. Map close dates to YYYY-MM-DD format.\n'
            + 'Return ONLY the JSON array, no markdown, no explanation.';
    }

    private static Boolean applyOppUpdate(Opportunity opp, Map<String, Object> action) {
        String field = (String) action.get('field');
        String value = (String) action.get('value');
        if (String.isBlank(field) || String.isBlank(value)) return false;

        if (field == 'StageName') {
            opp.StageName = value;
        } else if (field == 'CloseDate') {
            opp.CloseDate = Date.valueOf(value);
        } else if (field == 'Probability') {
            opp.Probability = Decimal.valueOf(value.replace('%', ''));
        } else if (field == 'NextStep') {
            opp.NextStep = value;
        } else {
            return false;
        }
        return true;
    }

    private static Task createActivityRecord(Opportunity opp, Map<String, Object> action) {
        return new Task(
            WhatId = opp.Id,
            Subject = (String) action.get('subject'),
            Description = (String) action.get('description'),
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today(),
            TaskSubtype = 'Call'
        );
    }

    private static Contact createContactRecord(Opportunity opp, Map<String, Object> action) {
        return new Contact(
            FirstName = (String) action.get('firstName'),
            LastName = (String) action.get('lastName'),
            Title = (String) action.get('title'),
            AccountId = opp.AccountId
        );
    }

    private static Task createTaskRecord(Opportunity opp, Map<String, Object> action) {
        String dueDateStr = (String) action.get('dueDate');
        Date dueDate = String.isNotBlank(dueDateStr) ? Date.valueOf(dueDateStr) : Date.today().addDays(7);

        return new Task(
            WhatId = opp.Id,
            Subject = (String) action.get('subject'),
            Description = (String) action.get('description'),
            Status = 'Not Started',
            Priority = 'Normal',
            ActivityDate = dueDate
        );
    }

    private static String getPicklistValues(String objectName, String fieldName) {
        List<String> values = new List<String>();
        Schema.DescribeFieldResult fieldResult = Schema.getGlobalDescribe()
            .get(objectName)
            .getDescribe()
            .fields.getMap()
            .get(fieldName)
            .getDescribe();

        for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return String.join(values, ', ');
    }

    private static String extractJsonFromResponse(String response) {
        // Find the JSON array in the response
        Integer startIdx = response.indexOf('[');
        Integer endIdx = response.lastIndexOf(']');
        if (startIdx >= 0 && endIdx > startIdx) {
            return response.substring(startIdx, endIdx + 1);
        }
        throw new AuraHandledException('AI response did not contain valid JSON actions. Response: ' + response.left(200));
    }
}
