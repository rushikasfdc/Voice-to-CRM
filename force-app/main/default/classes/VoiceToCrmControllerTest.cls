@IsTest
private class VoiceToCrmControllerTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Acme Corp');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Deal',
            AccountId = acc.Id,
            StageName = 'Negotiation',
            CloseDate = Date.today().addDays(30),
            Amount = 100000
        );
        insert opp;
    }

    @IsTest
    static void testExecuteActions_UpdateOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        List<Map<String, String>> actions = new List<Map<String, String>>{
            new Map<String, String>{
                'type' => 'update',
                'label' => 'Update Stage',
                'detail' => 'Negotiation to Closed Won',
                'field' => 'StageName',
                'value' => 'Closed Won'
            },
            new Map<String, String>{
                'type' => 'update',
                'label' => 'Update Close Date',
                'detail' => 'New close date',
                'field' => 'CloseDate',
                'value' => String.valueOf(Date.today())
            }
        };

        Test.startTest();
        VoiceToCrmController.executeActions(JSON.serialize(actions), opp.Id);
        Test.stopTest();

        Opportunity updated = [SELECT StageName, CloseDate FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Closed Won', updated.StageName);
        System.assertEquals(Date.today(), updated.CloseDate);
    }

    @IsTest
    static void testExecuteActions_CreateTask() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        List<Map<String, String>> actions = new List<Map<String, String>>{
            new Map<String, String>{
                'type' => 'task',
                'label' => 'Create Task',
                'detail' => 'Send SOW',
                'subject' => 'Send SOW',
                'dueDate' => String.valueOf(Date.today().addDays(5)),
                'description' => 'Send statement of work to client'
            }
        };

        Test.startTest();
        VoiceToCrmController.executeActions(JSON.serialize(actions), opp.Id);
        Test.stopTest();

        List<Task> tasks = [SELECT Subject, ActivityDate, Status FROM Task WHERE WhatId = :opp.Id AND Subject = 'Send SOW'];
        System.assertEquals(1, tasks.size());
        System.assertEquals('Not Started', tasks[0].Status);
    }

    @IsTest
    static void testExecuteActions_LogActivity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        List<Map<String, String>> actions = new List<Map<String, String>>{
            new Map<String, String>{
                'type' => 'activity',
                'label' => 'Log Activity',
                'detail' => 'Call with client',
                'subject' => 'Call with Sarah',
                'description' => 'Discussed timeline'
            }
        };

        Test.startTest();
        VoiceToCrmController.executeActions(JSON.serialize(actions), opp.Id);
        Test.stopTest();

        List<Task> activities = [SELECT Subject, Status FROM Task WHERE WhatId = :opp.Id AND Subject = 'Call with Sarah'];
        System.assertEquals(1, activities.size());
        System.assertEquals('Completed', activities[0].Status);
    }

    @IsTest
    static void testExecuteActions_CreateContact() {
        Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];

        List<Map<String, String>> actions = new List<Map<String, String>>{
            new Map<String, String>{
                'type' => 'contact',
                'label' => 'Create Contact',
                'detail' => 'Mike - CTO',
                'firstName' => 'Mike',
                'lastName' => 'Johnson',
                'title' => 'CTO',
                'role' => 'Decision Maker'
            }
        };

        Test.startTest();
        VoiceToCrmController.executeActions(JSON.serialize(actions), opp.Id);
        Test.stopTest();

        List<Contact> contacts = [SELECT FirstName, LastName, Title FROM Contact WHERE AccountId = :opp.AccountId AND LastName = 'Johnson'];
        System.assertEquals(1, contacts.size());
        System.assertEquals('Mike', contacts[0].FirstName);
        System.assertEquals('CTO', contacts[0].Title);
    }

    @IsTest
    static void testExecuteActions_MultipleActions() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        List<Map<String, String>> actions = new List<Map<String, String>>{
            new Map<String, String>{
                'type' => 'update',
                'label' => 'Update Stage',
                'detail' => 'Update',
                'field' => 'NextStep',
                'value' => 'Send contract'
            },
            new Map<String, String>{
                'type' => 'task',
                'label' => 'Create Task',
                'detail' => 'Follow up',
                'subject' => 'Follow up call',
                'dueDate' => String.valueOf(Date.today().addDays(3)),
                'description' => 'Follow up'
            },
            new Map<String, String>{
                'type' => 'activity',
                'label' => 'Log Activity',
                'detail' => 'Meeting',
                'subject' => 'Initial meeting',
                'description' => 'Went well'
            }
        };

        Test.startTest();
        VoiceToCrmController.executeActions(JSON.serialize(actions), opp.Id);
        Test.stopTest();

        Opportunity updated = [SELECT NextStep FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Send contract', updated.NextStep);

        Integer taskCount = [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id];
        System.assertEquals(2, taskCount);
    }

    // Mock for Claude API callout
    private class ClaudeApiMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"content":[{"type":"text","text":"[{\\"type\\":\\"update\\",\\"label\\":\\"Update Stage\\",\\"detail\\":\\"Negotiation → Legal Review\\",\\"field\\":\\"StageName\\",\\"value\\":\\"Prospecting\\"}]"}]}');
            return res;
        }
    }

    @IsTest
    static void testParseVoiceInput() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new ClaudeApiMock());

        Test.startTest();
        String result = VoiceToCrmController.parseVoiceInput(
            'Move stage to prospecting',
            opp.Id,
            'Negotiation',
            'Test Acme Corp'
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        List<Object> actions = (List<Object>) JSON.deserializeUntyped(result);
        System.assertEquals(1, actions.size());
    }
}
