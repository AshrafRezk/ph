/**
 * @description Test class for CrmHubListController (list view JSON, modal, cognitive search).
 */
@IsTest
private class CrmHubListControllerTest {

    private static Opportunity newHubTestOpportunity(String name, Id accountId) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Type = 'Existing Business',
            Type_of_Service__c = 'Other'
        );
    }


    @IsTest
    static void testConstructorSerializesListViewOptions() {
        Test.startTest();
        CrmHubListController c = new CrmHubListController();
        Test.stopTest();

        System.assertEquals(null, c.errorMessage, 'Constructor should not set errorMessage');
        System.assertNotEquals(null, c.leadListViewsJson);
        System.assertNotEquals(null, c.opportunityListViewsJson);
        System.assertNotEquals(null, c.accountListViewsJson);
        System.assertNotEquals(null, c.contactListViewsJson);
        System.assertNotEquals(null, c.jobApplicationListViewsJson);
        System.assertNotEquals(null, c.positionListViewsJson);
        System.assertNotEquals(null, c.employmentContractListViewsJson);
        System.assertNotEquals(null, c.listViewPrefsJson);

        List<Object> oppOpts = (List<Object>) JSON.deserializeUntyped(c.opportunityListViewsJson);
        System.assertNotEquals(null, oppOpts, 'Opportunity list views should deserialize');
        Map<String, Object> prefs = (Map<String, Object>) JSON.deserializeUntyped(c.listViewPrefsJson);
        System.assertNotEquals(null, prefs);
    }

    @IsTest
    static void testListViewPrefRemoteActions() {
        String lvId = '00B000000000010AAA';

        Test.startTest();
        Map<String, Object> pinned = CrmHubListController.setPinnedListView('Opportunity', lvId);
        Map<String, Object> fav = CrmHubListController.toggleFavoriteListView('Opportunity', lvId);
        Map<String, Object> all = CrmHubListController.getListViewPrefs();
        Map<String, Object> cleared = CrmHubListController.setPinnedListView('Opportunity', '');
        Test.stopTest();

        System.assertEquals(true, pinned.get('success'));
        System.assertEquals(true, fav.get('success'));
        System.assertEquals(true, all.get('success'));
        System.assertEquals(true, cleared.get('success'));

        Map<String, Object> pref = (Map<String, Object>) fav.get('pref');
        List<Object> favoriteIds = (List<Object>) pref.get('favoriteIds');
        System.assert(favoriteIds.contains(lvId));

        Map<String, Object> prefsMap = (Map<String, Object>) all.get('prefs');
        System.assert(prefsMap.containsKey('Opportunity'));
    }

    @IsTest
    static void testFetchRecordModalRelatedListRemoteAction() {
        Account acc = new Account(Name = 'Related Remote Acc');
        insert acc;
        Task t = new Task(Subject = 'Remote Child', WhatId = acc.Id, Status = 'Not Started', Priority = 'Normal');
        insert t;
        HubRecordModalUtil.testLayoutOverride = new Map<String, Object>{
            'detailLayoutSections' => new List<Object>(),
            'relatedLists' => new List<Object>{
                new Map<String, Object>{
                    'label' => 'Tasks',
                    'name' => 'Tasks',
                    'columns' => new List<Object>{ 'TASK.SUBJECT' }
                }
            }
        };

        Map<String, Object> res = CrmHubListController.fetchRecordModalRelatedList(acc.Id, 'Tasks', 'rl_tasks', 5);

        HubRecordModalUtil.testLayoutOverride = null;

        System.assertEquals(null, res.get('error'), 'unexpected error: ' + res);
        System.assertNotEquals(null, res.get('relatedList'));
        Map<String, Object> block = (Map<String, Object>) res.get('relatedList');
        System.assertEquals(1, ((List<Object>) block.get('rows')).size());
    }

    @IsTest
    static void testFetchRecordModalData() {
        Account acc = new Account(Name = 'Modal Account');
        insert acc;

        HubRecordModalUtil.testLayoutOverride = new Map<String, Object>{
            'detailLayoutSections' => new List<Object>{
                new Map<String, Object>{
                    'heading' => 'Account Information',
                    'useHeading' => true,
                    'layoutRows' => new List<Object>{
                        new Map<String, Object>{
                            'layoutItems' => new List<Object>{
                                new Map<String, Object>{
                                    'label' => 'Account Name',
                                    'placeholder' => false,
                                    'layoutComponents' => new List<Object>{
                                        new Map<String, Object>{
                                            'type' => 'Field',
                                            'value' => 'Name',
                                            'details' => new Map<String, Object>{ 'type' => 'string', 'name' => 'Name' }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        };

        Test.startTest();
        Map<String, Object> res = CrmHubListController.fetchRecordModalData(acc.Id);
        Test.stopTest();

        HubRecordModalUtil.testLayoutOverride = null;

        System.assertEquals(null, res.get('error'), 'unexpected error: ' + String.valueOf(res.get('error')));
        System.assertEquals('Account', res.get('objectApi'));
        System.assertNotEquals(null, res.get('layout'));
        System.assertNotEquals(null, res.get('values'));
    }

    @IsTest
    static void testFetchRecordModalDataBlankId() {
        Map<String, Object> res = CrmHubListController.fetchRecordModalData('');
        System.assert(res.containsKey('error'));
    }

    @IsTest
    static void testFetchListViewResultsAndDescribe() {
        Account acc = new Account(Name = 'HubListFetchAcc');
        insert acc;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }

        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name',
                    'label' => 'Account Name',
                    'type' => 'string',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Type',
                    'label' => 'Type',
                    'type' => 'picklist',
                    'hidden' => false
                }
            }
        };

        Test.startTest();
        Map<String, Object> page = CrmHubListController.fetchListViewResults('Account', lvs[0].Id, 25, 0, null);
        Map<String, Object> meta = CrmHubListController.describeListView('Account', lvs[0].Id);
        Map<String, Object> bad = CrmHubListController.fetchListViewResults('BadObject', lvs[0].Id, 25, 0, null);
        Map<String, Object> badDesc = CrmHubListController.describeListView('', '');
        Test.stopTest();

        HubListViewUtil.testListViewDescribeOverride = null;

        List<Object> cols = (List<Object>) page.get('columns');
        System.assertNotEquals(null, cols);
        System.assert(cols.size() > 1, 'Should expose list view columns beyond Id');
        System.assertNotEquals(null, page.get('records'));
        List<Object> records = (List<Object>) page.get('records');
        if (!records.isEmpty()) {
            Map<String, Object> row = (Map<String, Object>) records[0];
            System.assertNotEquals(null, row.get('id'), 'Controller should stamp record id on rows');
        }
        System.assertNotEquals(null, meta.get('label'));
        System.assert(bad.containsKey('error'));
        System.assert(badDesc.containsKey('error'));
    }

    @IsTest
    static void testFetchKanbanBoardRemote() {
        Account a1 = new Account(Name = 'HubKanban Acc A', Type = 'Customer');
        Account a2 = new Account(Name = 'HubKanban Acc B', Type = 'Customer');
        insert new List<Account>{ a1, a2 };
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }

        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'query' => 'SELECT Id, Name, Type FROM Account WHERE Name LIKE \'HubKanban Acc%\'',
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name',
                    'label' => 'Account Name',
                    'type' => 'string',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Type',
                    'label' => 'Type',
                    'type' => 'picklist',
                    'hidden' => false
                }
            }
        };

        Test.startTest();
        Map<String, Object> board = CrmHubListController.fetchKanbanBoard(
            'Account',
            lvs[0].Id,
            'Type',
            10,
            null
        );
        Map<String, Object> more = CrmHubListController.fetchKanbanLaneMore(
            'Account',
            lvs[0].Id,
            'Type',
            'Customer',
            10,
            0,
            null
        );
        Map<String, Object> denied = CrmHubListController.fetchKanbanBoard(
            'BadObject',
            lvs[0].Id,
            'Type',
            10,
            null
        );
        Test.stopTest();
        HubListViewUtil.testListViewDescribeOverride = null;

        System.assertEquals(null, board.get('error'), 'unexpected error: ' + String.valueOf(board.get('error')));
        System.assertEquals('Type', board.get('laneField'));
        System.assertEquals(null, more.get('error'));
        System.assert(denied.containsKey('error'));
    }

    @IsTest
    static void testFetchListViewResultsOpportunity() {
        Account oppAcc = new Account(Name = 'HubListFetchOpp Acc');
        insert oppAcc;
        Opportunity opp = newHubTestOpportunity('HubListFetchOpp', oppAcc.Id);
        insert opp;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Opportunity' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }

        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name',
                    'label' => 'Opportunity Name',
                    'type' => 'string',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'StageName',
                    'label' => 'Stage',
                    'type' => 'picklist',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Amount',
                    'label' => 'Amount',
                    'type' => 'currency',
                    'hidden' => false
                }
            }
        };

        Map<String, Object> page = CrmHubListController.fetchListViewResults('Opportunity', lvs[0].Id, 10, 0, null);
        HubListViewUtil.testListViewDescribeOverride = null;

        List<Object> cols = (List<Object>) page.get('columns');
        System.assertNotEquals(null, cols);
        System.assert(cols.size() >= 3, 'Opportunity list view should include Name, Stage, Amount columns');
        System.assertNotEquals(null, page.get('records'));
        List<Object> records = (List<Object>) page.get('records');
        if (!records.isEmpty()) {
            Map<String, Object> row = (Map<String, Object>) records[0];
            System.assertNotEquals(null, row.get('id'), 'Rows should include record id for open actions');
        }
    }

    @IsTest
    static void testStampRecordIdsOnRowsByName() {
        Account acc = new Account(Name = 'HubStampId Acc');
        insert acc;
        Map<String, Object> res = new Map<String, Object>{
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name',
                    'label' => 'Account Name',
                    'type' => 'string',
                    'hidden' => false
                }
            },
            'records' => new List<Object>{
                new Map<String, Object>{
                    'columns' => new List<Object>{
                        new Map<String, Object>{
                            'fieldNameOrPath' => 'Name',
                            'value' => 'HubStampId Acc'
                        }
                    }
                }
            }
        };
        CrmHubListController.stampRecordIdsOnRows('Account', res);
        Map<String, Object> row = (Map<String, Object>) ((List<Object>) res.get('records'))[0];
        System.assertEquals(String.valueOf(acc.Id), row.get('id'));
    }

    @IsTest
    static void testStampRecordIdsSkipsWhenIdPresent() {
        Map<String, Object> row = new Map<String, Object>{
            'id' => '001000000000001AAA',
            'columns' => new List<Object>()
        };
        System.assertEquals(true, CrmHubListController.hasRecordId(row));
    }

    @IsTest
    static void testFetchListViewResultsContactAccountColumn() {
        Account acc = new Account(Name = 'HubList Contact Acc');
        insert acc;
        insert newHubTestOpportunity('HubList Contact Open Opp', acc.Id);
        Contact con = new Contact(LastName = 'HubListCon', AccountId = acc.Id);
        insert con;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Contact' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }

        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'query' => 'SELECT Id, Name, Account.Name FROM Contact WHERE Id = \'' + String.valueOf(con.Id) + '\'',
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name',
                    'label' => 'Name',
                    'type' => 'string',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Account.Name',
                    'label' => 'Account Name',
                    'type' => 'string',
                    'hidden' => false
                }
            }
        };

        Map<String, Object> page = CrmHubListController.fetchListViewResults('Contact', lvs[0].Id, 10, 0, null);
        HubListViewUtil.testListViewDescribeOverride = null;

        System.assertEquals(null, page.get('error'), 'Contact Account.Name should not error: ' + page.get('error'));
        List<Object> records = (List<Object>) page.get('records');
        System.assert(!records.isEmpty(), 'Should return contact rows');
        Map<String, Object> row = (Map<String, Object>) records[0];
        List<Object> cells = (List<Object>) row.get('columns');
        Boolean sawAccountName = false;
        for (Object cellObj : cells) {
            Map<String, Object> cell = (Map<String, Object>) cellObj;
            if ('Account.Name'.equals(cell.get('fieldNameOrPath')) && 'HubList Contact Acc'.equals(cell.get('value'))) {
                sawAccountName = true;
                break;
            }
        }
        System.assert(sawAccountName, 'Account.Name should render for Contact list rows');
    }

    @IsTest
    static void testFirstListViewPrefersAll() {
        String json = '[{"id":"001","label":"My Accounts","developerName":"MyAccounts"},{"id":"002","label":"All Accounts","developerName":"AllAccounts"}]';
        System.assertEquals('002', HubListViewUtil.firstListViewId(json));
    }

    @IsTest
    static void testPreferredListViewId() {
        String json = '[{"id":"001","label":"HR","developerName":"HR"},{"id":"002","label":"All Contracts","developerName":"All"}]';
        System.assertEquals('001', HubListViewUtil.preferredListViewId(json, 'HR'));
        System.assertEquals('002', HubListViewUtil.preferredListViewId(json, 'Missing'));
    }

    @IsTest
    static void testCognitiveSearchShortTerm() {
        Map<String, Object> res = CrmHubListController.cognitiveSearch(' ');
        System.assert(res.containsKey('message'), 'Should prompt for longer term');
        System.assertEquals(0, ((List<Object>) res.get('leads')).size());
        System.assert(res.containsKey('jobApplications'), 'HR buckets always present');
        System.assert(res.containsKey('positions'));
        System.assert(res.containsKey('contracts'));
        System.assertEquals(0, ((List<Object>) res.get('jobApplications')).size());
        System.assertEquals(0, ((List<Object>) res.get('positions')).size());
        System.assertEquals(0, ((List<Object>) res.get('contracts')).size());
    }

    @IsTest
    static void testCognitiveSearchWithFixedResults() {
        Account acc = new Account(Name = 'UniqueCognitiveHubAcc987');
        insert acc;

        CrmHubListController.hubAccessModeOverride = CrmHubListController.HUB_ACCESS_PARTIAL;
        try {
            Test.setFixedSearchResults(new List<Id>{ acc.Id });
            Test.startTest();
            Map<String, Object> res = CrmHubListController.cognitiveSearch('UniqueCognitive');
            Test.stopTest();

            System.assertEquals(null, res.get('error'), 'SOSL cognitive search should not set error');
            List<Object> accounts = (List<Object>) res.get('accounts');
            System.assertNotEquals(null, accounts);
            Boolean saw = false;
            for (Object row : accounts) {
                Map<String, Object> m = (Map<String, Object>) row;
                if (acc.Id != null && String.valueOf(acc.Id).equals(String.valueOf(m.get('id')))) {
                    saw = true;
                    break;
                }
            }
            System.assert(saw, 'Fixed search should return inserted account in accounts bucket');
            System.assertEquals(0, ((List<Object>) res.get('jobApplications')).size());
            System.assertEquals(0, ((List<Object>) res.get('positions')).size());
            System.assertEquals(0, ((List<Object>) res.get('contracts')).size());
        } finally {
            CrmHubListController.hubAccessModeOverride = null;
        }
    }

    @IsTest
    static void testFullCognitiveSearchIncludesHrObjects() {
        Position__c pos = new Position__c(
            Name = 'UniqueCogPosHub987',
            Years_Of_Experience__c = 3,
            Max_Pay__c = 10000,
            Min_Pay__c = 8000,
            Status__c = 'New Position'
        );
        insert pos;
        Job_Application__c ja = new Job_Application__c(
            Position__c = pos.Id,
            Status__c = 'New'
        );
        insert ja;
        Account acc = new Account(Name = 'UniqueCogContractAcc');
        insert acc;
        Contact emp = new Contact(LastName = 'UniqueCogContractEmp', AccountId = acc.Id);
        insert emp;
        Employment_Contract__c contract = new Employment_Contract__c(
            Employee__c = emp.Id,
            Start_Date__c = Date.today().addDays(-30),
            End_Date__c = Date.today().addDays(335),
            Total_Work_From_Home_Days_Allowed__c = 12,
            Total_Vacation_Days_Allowed__c = 21
        );
        insert contract;

        CrmHubListController.hubAccessModeOverride = CrmHubListController.HUB_ACCESS_FULL;
        try {
            Test.setFixedSearchResults(new List<Id>{ pos.Id, ja.Id, contract.Id });
            Test.startTest();
            Map<String, Object> res = CrmHubListController.cognitiveSearch('UniqueCog');
            Test.stopTest();

            System.assertEquals(null, res.get('error'), 'Full cognitive search error: ' + res.get('error'));
            System.assert(res.containsKey('jobApplications'));
            System.assert(res.containsKey('positions'));
            System.assert(res.containsKey('contracts'));

            Set<String> posIds = new Set<String>();
            for (Object row : (List<Object>) res.get('positions')) {
                posIds.add(String.valueOf(((Map<String, Object>) row).get('id')));
            }
            Set<String> jaIds = new Set<String>();
            for (Object row : (List<Object>) res.get('jobApplications')) {
                jaIds.add(String.valueOf(((Map<String, Object>) row).get('id')));
            }
            Set<String> conIds = new Set<String>();
            for (Object row : (List<Object>) res.get('contracts')) {
                conIds.add(String.valueOf(((Map<String, Object>) row).get('id')));
            }
            System.assert(posIds.contains(String.valueOf(pos.Id)), 'Position should appear for Full access');
            System.assert(jaIds.contains(String.valueOf(ja.Id)), 'Job Application should appear for Full access');
            System.assert(conIds.contains(String.valueOf(contract.Id)), 'Contract should appear for Full access');
        } finally {
            CrmHubListController.hubAccessModeOverride = null;
        }
    }

    @IsTest
    static void testGetCommandCenterConfig() {
        Test.startTest();
        Map<String, Object> cfg = CrmHubListController.getCommandCenterConfig();
        Test.stopTest();

        System.assertNotEquals(null, cfg.get('lightningHost'), 'lightningHost should be set');
        System.assertNotEquals(null, cfg.get('commandCenterUrl'), 'commandCenterUrl should be set');
        System.assertEquals('businesscard', cfg.get('defaultSectionId'));
        System.assertEquals('mixed', cfg.get('embedMode'));
        List<Object> sections = (List<Object>) cfg.get('sections');
        System.assertNotEquals(null, sections);
        System.assert(sections.size() >= 8, 'Expected core Command Center sections including Sonic');

        Map<String, Object> quickCreate = (Map<String, Object>) sections[0];
        System.assertEquals('quickcreate', quickCreate.get('id'));
        System.assertEquals('/flow/Quick_Create_Account_and_Contact', quickCreate.get('path'));

        Boolean foundBizCard = false;
        Boolean foundSonic = false;
        Boolean foundCleanLists = false;
        Boolean foundOverdue = false;
        Integer bizCardIdx = -1;
        Integer sonicIdx = -1;
        for (Integer i = 0; i < sections.size(); i++) {
            Map<String, Object> sec = (Map<String, Object>) sections[i];
            String sid = (String) sec.get('id');
            if ('businesscard'.equals(sid)) {
                foundBizCard = true;
                bizCardIdx = i;
                System.assertEquals('vfComponent', sec.get('embedType'));
            }
            if ('sonic'.equals(sid)) {
                foundSonic = true;
                sonicIdx = i;
                System.assertEquals('vfComponent', sec.get('embedType'));
                System.assertEquals('Cloudastick Sonic', sec.get('label'));
            }
            if ('cleanlists'.equals(sid)) {
                foundCleanLists = true;
                System.assertEquals('vfComponent', sec.get('embedType'));
                System.assertEquals('Clean Lists', sec.get('label'));
            }
            if ('overdue'.equals(sid)) {
                foundOverdue = true;
            }
        }
        System.assert(foundBizCard, 'Business card section should be configured');
        System.assert(foundSonic, 'Cloudastick Sonic section should be configured');
        System.assert(!foundOverdue, 'Overdue Opps should be removed from Command Center');
        System.assert(sonicIdx == bizCardIdx + 1, 'Sonic should sit next to Business Card');
        if (cfg.get('isSystemAdmin') == true) {
            System.assert(foundCleanLists, 'Clean Lists should be available for System Admins');
        }
    }

    @IsTest
    static void testSonicRemoteProxies() {
        CloudastickSonicController.ListViewOption opt = new CloudastickSonicController.ListViewOption();
        opt.id = '00B000000000001';
        opt.label = 'Sonic Proxy View';
        opt.developerName = 'Sonic_Proxy_View';
        CloudastickSonicController.testListViewOptionsOverride =
            new List<CloudastickSonicController.ListViewOption>{ opt };

        CloudastickSonicController.OpportunityQueueResult queue =
            new CloudastickSonicController.OpportunityQueueResult();
        queue.opportunities = new List<CloudastickSonicController.OpportunityCard>();
        queue.totalInListView = 0;
        queue.truncated = false;
        queue.listViewLabel = 'Sonic Proxy View';
        CloudastickSonicController.testQueueResultOverride = queue;

        Account acc = new Account(
            Name = 'Sonic Proxy Account',
            Website = 'https://example.com'
        );
        insert acc;
        Opportunity opp = new Opportunity(
            Name = 'Sonic Proxy Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(14),
            AccountId = acc.Id,
            Type_of_Service__c = 'Other'
        );
        insert opp;

        Test.startTest();
        List<CloudastickSonicController.ListViewOption> views =
            CrmHubListController.sonicGetOpportunityListViews();
        CloudastickSonicController.OpportunityQueueResult result =
            CrmHubListController.sonicGetOpportunityQueue(opt.id);
        List<CloudastickSonicController.StageOption> stages =
            CrmHubListController.sonicGetOpportunityStageOptions();
        CrmHubListController.sonicSaveOpportunityUpdate(
            opp.Id,
            null,
            null,
            'Proxy next step',
            false,
            false,
            true,
            null,
            false
        );
        Test.stopTest();

        System.assertEquals(1, views.size());
        System.assertEquals('Sonic Proxy View', views[0].label);
        System.assertEquals(0, result.totalInListView);
        System.assertEquals('Sonic Proxy View', result.listViewLabel);
        System.assertNotEquals(null, stages);
        Opportunity updated = [
            SELECT NextStep
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
        System.assertEquals('Proxy next step', updated.NextStep);
    }



    @IsTest
    static void testCommandCenterRemoteActions() {
        Test.startTest();
        Map<String, Object> eventsRes = CrmHubListController.fetchMeetingEvents(String.valueOf(Date.today()));
        Map<String, Object> reqRes = CrmHubListController.fetchRequirementBoardData();
        Map<String, Object> salesRes = CrmHubListController.fetchSalesTalkData();
        Map<String, Object> minutesRes = CrmHubListController.generateMeetingMinutesPreview('Notes here', null);
        Map<String, Object> blogRes = CrmHubListController.createHubBlogPost('Hub Ctrl Blog', 'Header', 'Body text');
        Test.stopTest();

        System.assertEquals(true, eventsRes.get('success'));
        System.assertEquals(true, reqRes.get('success'));
        System.assertEquals(true, salesRes.get('success'));
        System.assertEquals(true, minutesRes.get('success'));
        System.assertEquals(true, blogRes.get('success'));
    }

    @IsTest
    static void testCleanListsRemoteActions() {
        ListViewCleanupController.forceAdminForTest = true;
        ListViewCleanupController.listMetadataOverride =
            new List<MetadataService.FileProperties>();

        MetadataService.DeleteResult ok = new MetadataService.DeleteResult();
        ok.fullName = 'Account.Remote_Cleanup_View';
        ok.success = true;
        ListViewCleanupController.deleteResultsOverride =
            new List<MetadataService.DeleteResult>{ ok };

        Test.startTest();
        Map<String, Object> objectsRes = CrmHubListController.cleanListsGetObjects();
        Map<String, Object> searchRes = CrmHubListController.cleanListsSearchObjects('Account');
        Map<String, Object> viewsRes = CrmHubListController.cleanListsGetViews('Account');
        Map<String, Object> deleteRes = CrmHubListController.cleanListsDelete(
            new List<String>{ 'Account.Remote_Cleanup_View' }
        );
        Test.stopTest();

        System.assertEquals(true, objectsRes.get('success'));
        System.assertEquals(true, searchRes.get('success'));
        System.assertEquals(true, viewsRes.get('success'));
        System.assertEquals(true, deleteRes.get('success'));
        System.assertNotEquals(null, objectsRes.get('objects'));
        System.assertNotEquals(null, searchRes.get('objects'));
        System.assertEquals(0, viewsRes.get('hiddenCount'));
    }

    @IsTest
    static void testCommandCenterUpdateAndSend() {
        Event evt = new Event(
            Subject = 'Hub CC Send',
            StartDateTime = Datetime.now(),
            EndDateTime = Datetime.now().addHours(1),
            DurationInMinutes = 60
        );
        insert evt;

        Test.startTest();
        Map<String, Object> sendRes = CrmHubListController.sendMeetingMinutes(
            evt.Id,
            '<p>Hub minutes</p>',
            '[]',
            true
        );
        Map<String, Object> badReq = CrmHubListController.updateRequirementBoard(
            UserInfo.getUserId(),
            null,
            1,
            UserInfo.getUserId()
        );
        Map<String, Object> blogErr = CrmHubListController.generateHubBlogPost('');
        Test.stopTest();

        System.assertEquals(true, sendRes.get('success'));
        System.assertNotEquals(null, badReq.get('success'));
        System.assertEquals(false, blogErr.get('success'));
    }

    @IsTest
    static void testUpdateRecordFieldsRemoteAction() {
        Account acc = new Account(Name = 'Ctrl Edit Acc', Phone = '111');
        insert acc;
        Map<String, Object> res = CrmHubListController.updateRecordFields(
            acc.Id,
            new Map<String, Object>{ 'Phone' => '555-9999' }
        );
        System.assertEquals(true, res.get('success'), 'unexpected: ' + res);
        System.assertEquals('555-9999', [SELECT Phone FROM Account WHERE Id = :acc.Id].Phone);

        Map<String, Object> blank = CrmHubListController.updateRecordFields('', null);
        System.assert(blank.containsKey('error'));

        Map<String, Object> details = CrmHubListController.fetchRecordModalDetails(acc.Id);
        System.assertEquals(null, details.get('error'), 'details: ' + details.get('error'));
        System.assertNotEquals(null, details.get('values'));
        System.assertNotEquals(null, details.get('fieldMeta'));

        Integer marked = CrmHubListController.markNotificationsRead('[]', false);
        System.assert(marked >= 0);
    }

    @IsTest
    static void testGetHubAccessConfigDefaultsToPartial() {
        CrmHubListController.hubAccessModeOverride = null;
        // Running user in tests is not on the Full allowlist unless username matches.
        Map<String, Object> cfg = CrmHubListController.getHubAccessConfig();
        String mode = String.valueOf(cfg.get('mode'));
        System.assert(
            mode == CrmHubListController.HUB_ACCESS_PARTIAL ||
                mode == CrmHubListController.HUB_ACCESS_FULL,
            'Mode should resolve to Partial or Full'
        );
        if (mode == CrmHubListController.HUB_ACCESS_PARTIAL) {
            List<Object> tabs = (List<Object>) cfg.get('allowedTabs');
            System.assert(tabs.contains('leads'));
            System.assert(tabs.contains('commandcenter'));
            System.assert(!tabs.contains('jobapps'), 'Unset Hub Access defaults to Partial (no Job Apps)');
            System.assert(!tabs.contains('contracts'), 'Unset Hub Access defaults to Partial (no Contracts)');
            List<Object> objects = (List<Object>) cfg.get('allowedObjects');
            System.assert(!objects.contains('Employment_Contract__c'));
        }
    }

    @IsTest
    static void testSeedHubAccessAssignmentsRuns() {
        Map<String, Object> res = CrmHubListController.seedHubAccessAssignments();
        System.assertNotEquals(null, res.get('updated'));
        System.assertNotEquals(null, res.get('scanned'));
        System.assertNotEquals(null, res.get('confirm'));
    }

    @IsTest
    static void testGetHubAccessConfigFull() {
        CrmHubListController.hubAccessModeOverride = CrmHubListController.HUB_ACCESS_FULL;
        try {
            Map<String, Object> cfg = CrmHubListController.getHubAccessConfig();
            System.assertEquals(CrmHubListController.HUB_ACCESS_FULL, cfg.get('mode'));
            List<Object> tabs = (List<Object>) cfg.get('allowedTabs');
            System.assert(tabs.contains('jobapps'), 'Full access should include Job Apps tab');
            System.assert(tabs.contains('contracts'), 'Full access should include Contracts tab');
            List<Object> objects = (List<Object>) cfg.get('allowedObjects');
            System.assert(objects.contains('Employment_Contract__c'));
        } finally {
            CrmHubListController.hubAccessModeOverride = null;
        }
    }

    @IsTest
    static void testGetHubAccessConfigPartial() {
        CrmHubListController.hubAccessModeOverride = CrmHubListController.HUB_ACCESS_PARTIAL;
        try {
            Map<String, Object> cfg = CrmHubListController.getHubAccessConfig();
            System.assertEquals(CrmHubListController.HUB_ACCESS_PARTIAL, cfg.get('mode'));
            List<Object> tabs = (List<Object>) cfg.get('allowedTabs');
            System.assert(tabs.contains('leads'));
            System.assert(tabs.contains('opps'));
            System.assert(tabs.contains('accounts'));
            System.assert(tabs.contains('contacts'));
            System.assert(tabs.contains('commandcenter'));
            System.assert(!tabs.contains('jobapps'), 'Partial should hide Job Apps');
            System.assert(!tabs.contains('positions'), 'Partial should hide Positions');
            System.assert(!tabs.contains('contracts'), 'Partial should hide Contracts');
            List<Object> objects = (List<Object>) cfg.get('allowedObjects');
            System.assert(objects.contains('Contact'));
            System.assert(!objects.contains('Job_Application__c'));
            System.assert(!objects.contains('Position__c'));
            System.assert(!objects.contains('Employment_Contract__c'));
        } finally {
            CrmHubListController.hubAccessModeOverride = null;
        }
    }

    @IsTest
    static void testPartialBlocksHrObjectsAndEmployedContacts() {
        Account acc = new Account(Name = 'Hub Access Acc');
        insert acc;
        Contact employed = new Contact(LastName = 'EmployedHub', AccountId = acc.Id);
        Contact openCon = new Contact(LastName = 'OpenHub', AccountId = acc.Id);
        insert new List<Contact>{ employed, openCon };

        CrmHubListController.hubAccessModeOverride = CrmHubListController.HUB_ACCESS_PARTIAL;
        CrmHubListController.testEmployedContactIds = new Set<Id>{ employed.Id };
        try {
            Map<String, Object> blocked = CrmHubListController.fetchListViewResults(
                'Job_Application__c',
                '00B000000000001',
                10,
                0,
                null
            );
            System.assert(String.valueOf(blocked.get('error')).contains('Partial Hub Access'));

            Map<String, Object> posBlocked = CrmHubListController.describeListView(
                'Position__c',
                '00B000000000001'
            );
            System.assert(String.valueOf(posBlocked.get('error')).contains('Partial Hub Access'));

            Map<String, Object> employedModal = CrmHubListController.fetchRecordModalShell(employed.Id);
            System.assert(
                String.valueOf(employedModal.get('error')).contains('Employed contacts'),
                'Employed contact modal should be denied: ' + employedModal
            );

            Map<String, Object> openModal = CrmHubListController.fetchRecordModalShell(openCon.Id);
            System.assertEquals(
                null,
                openModal.get('error'),
                'Non-employed contact should open: ' + openModal
            );

            Map<String, Object> listRes = new Map<String, Object>{
                'records' => new List<Object>{
                    new Map<String, Object>{ 'id' => String.valueOf(employed.Id) },
                    new Map<String, Object>{ 'id' => String.valueOf(openCon.Id) }
                }
            };
            CrmHubListController.filterPartialContactRecords('Contact', listRes);
            List<Object> kept = (List<Object>) listRes.get('records');
            System.assertEquals(1, kept.size(), 'Employed contact should be filtered from list');
            System.assertEquals(String.valueOf(openCon.Id), ((Map<String, Object>) kept[0]).get('id'));
        } finally {
            CrmHubListController.hubAccessModeOverride = null;
            CrmHubListController.testEmployedContactIds = null;
        }
    }

    @IsTest
    static void testPartialCognitiveSearchDropsEmployedContacts() {
        Account acc = new Account(Name = 'HubCog Acc');
        insert acc;
        Contact employed = new Contact(LastName = 'UniqueCogEmployedHub', AccountId = acc.Id);
        Contact openCon = new Contact(LastName = 'UniqueCogOpenHub', AccountId = acc.Id);
        insert new List<Contact>{ employed, openCon };

        CrmHubListController.hubAccessModeOverride = CrmHubListController.HUB_ACCESS_PARTIAL;
        CrmHubListController.testEmployedContactIds = new Set<Id>{ employed.Id };
        try {
            Test.setFixedSearchResults(new List<Id>{ employed.Id, openCon.Id });
            Test.startTest();
            Map<String, Object> res = CrmHubListController.cognitiveSearch('UniqueCog');
            Test.stopTest();

            System.assertEquals(null, res.get('error'), 'cognitive search error: ' + res.get('error'));
            List<Object> contacts = (List<Object>) res.get('contacts');
            Set<String> ids = new Set<String>();
            for (Object row : contacts) {
                ids.add(String.valueOf(((Map<String, Object>) row).get('id')));
            }
            System.assert(!ids.contains(String.valueOf(employed.Id)), 'Employed contact should be omitted');
            System.assert(ids.contains(String.valueOf(openCon.Id)), 'Non-employed contact should remain');
            System.assertEquals(
                0,
                ((List<Object>) res.get('jobApplications')).size(),
                'Partial access must not return Job Apps'
            );
            System.assertEquals(
                0,
                ((List<Object>) res.get('positions')).size(),
                'Partial access must not return Positions'
            );
            System.assertEquals(
                0,
                ((List<Object>) res.get('contracts')).size(),
                'Partial access must not return Contracts'
            );
        } finally {
            CrmHubListController.hubAccessModeOverride = null;
            CrmHubListController.testEmployedContactIds = null;
        }
    }

    @IsTest
    static void testFetchHubBriefingAggregatesAndActions() {
        // Org automation on Lead/Opp/Task DML may enqueue callouts flushed by Test.stopTest().
        Test.setMock(HttpCalloutMock.class, new BriefingHttpCalloutMock());
        Test.setMock(WebServiceMock.class, new BriefingWebServiceMock());

        Account acc = new Account(Name = 'Briefing Acc');
        insert acc;
        Opportunity opp = newHubTestOpportunity('Briefing Opp Closing', acc.Id);
        opp.CloseDate = Date.today();
        insert opp;
        Lead ld = new Lead(LastName = 'BriefingLead', Company = 'Briefing Co', Status = 'Open - Not Contacted');
        insert ld;
        Task overdue = new Task(
            Subject = 'Briefing Overdue Task',
            Status = 'Not Started',
            Priority = 'Normal',
            ActivityDate = Date.today().addDays(-2),
            OwnerId = UserInfo.getUserId()
        );
        Task dueToday = new Task(
            Subject = 'Briefing Due Today',
            Status = 'Not Started',
            Priority = 'Normal',
            ActivityDate = Date.today(),
            OwnerId = UserInfo.getUserId()
        );
        insert new List<Task>{ overdue, dueToday };

        String startIso = String.valueOf(Date.today().addDays(-7));
        String endIso = String.valueOf(Date.today());
        String tabsJson = JSON.serialize(new List<String>{ 'leads', 'opps', 'accounts', 'contacts' });

        CrmHubListController.hubAccessModeOverride = CrmHubListController.HUB_ACCESS_PARTIAL;
        try {
            Test.startTest();
            Map<String, Object> res = CrmHubListController.fetchHubBriefing(
                startIso,
                endIso,
                tabsJson,
                'everything',
                'sales'
            );
            Test.stopTest();

            System.assertEquals(true, res.get('success'), 'Briefing error: ' + res.get('error'));
            List<Object> objects = (List<Object>) res.get('objects');
            System.assertNotEquals(null, objects);
            System.assert(objects.size() >= 2, 'Expected Lead and Opportunity rows');

            Set<String> apis = new Set<String>();
            for (Object rowObj : objects) {
                Map<String, Object> row = (Map<String, Object>) rowObj;
                apis.add(String.valueOf(row.get('api')));
            }
            System.assert(apis.contains('Lead'));
            System.assert(apis.contains('Opportunity'));
            System.assert(!apis.contains('Job_Application__c'), 'Partial must not include Job Applications');

            Map<String, Object> actions = (Map<String, Object>) res.get('actions');
            System.assertNotEquals(null, actions);
            List<Object> overdueTasks = (List<Object>) actions.get('overdueTasks');
            List<Object> dueTodayTasks = (List<Object>) actions.get('dueTodayTasks');
            List<Object> oppsClosing = (List<Object>) actions.get('oppsClosingToday');
            System.assert(overdueTasks.size() >= 1, 'Expected overdue task');
            System.assert(dueTodayTasks.size() >= 1, 'Expected due-today task');
            System.assert(oppsClosing.size() >= 1, 'Expected opp closing today');

            Map<String, Object> insights = (Map<String, Object>) res.get('insights');
            System.assertNotEquals(null, insights, 'Expected business insights payload');
            System.assertNotEquals(null, insights.get('opportunityStages'));
            System.assertNotEquals(null, insights.get('topDeals'));
            System.assertNotEquals(null, res.get('businessContext'));
        } finally {
            CrmHubListController.hubAccessModeOverride = null;
        }
    }

    @IsTest
    static void testFetchHubBriefingBlocksHrTabsForPartial() {
        String startIso = String.valueOf(Date.today().addDays(-3));
        String endIso = String.valueOf(Date.today());
        String tabsJson = JSON.serialize(new List<String>{ 'jobapps', 'positions', 'contracts', 'leads' });

        CrmHubListController.hubAccessModeOverride = CrmHubListController.HUB_ACCESS_PARTIAL;
        try {
            Test.startTest();
            Map<String, Object> res = CrmHubListController.fetchHubBriefing(
                startIso,
                endIso,
                tabsJson,
                'headlines',
                'hr'
            );
            Test.stopTest();

            System.assertEquals(true, res.get('success'), 'Briefing error: ' + res.get('error'));
            List<Object> objects = (List<Object>) res.get('objects');
            Set<String> apis = new Set<String>();
            for (Object rowObj : objects) {
                Map<String, Object> row = (Map<String, Object>) rowObj;
                apis.add(String.valueOf(row.get('api')));
            }
            System.assert(apis.contains('Lead'));
            System.assert(!apis.contains('Job_Application__c'));
            System.assert(!apis.contains('Position__c'));
            System.assert(!apis.contains('Employment_Contract__c'));
            Map<String, Object> actions = (Map<String, Object>) res.get('actions');
            System.assertEquals(0, ((List<Object>) actions.get('overdueTasks')).size());
        } finally {
            CrmHubListController.hubAccessModeOverride = null;
        }
    }

    @IsTest
    static void testFetchHubBriefingRequiresDates() {
        Test.startTest();
        Map<String, Object> res = CrmHubListController.fetchHubBriefing('', '', '[]', 'everything', 'sales');
        Test.stopTest();
        System.assertEquals(false, res.get('success'));
        System.assertNotEquals(null, res.get('error'));
    }

    @IsTest
    static void testSynthesizeHubSpeechFallsBackWithoutSmart() {
        CrmHubTtsService.apiKeyOverride = '';
        Test.startTest();
        Map<String, Object> res = CrmHubListController.synthesizeHubSpeech('Hello from Hub.', true);
        Test.stopTest();
        System.assertEquals(false, res.get('success'));
        System.assertEquals('browser', res.get('fallback'));
        System.assertEquals('webspeech', res.get('engine'));
    }

    @IsTest
    static void testSynthesizeHubSpeechReturnsElevenLabsAudio() {
        CrmHubTtsService.apiKeyOverride = 'test-key';
        CrmHubTtsService.skipCallout = true;
        CrmHubTtsService.testSpeechBodyOverride = Blob.valueOf('fake-mp3-bytes');
        Test.startTest();
        Map<String, Object> res = CrmHubListController.synthesizeHubSpeech('Briefing text.', true);
        Test.stopTest();
        System.assertEquals(true, res.get('success'), 'ElevenLabs synth error: ' + res.get('error'));
        System.assertEquals('elevenlabs', res.get('engine'));
        System.assertNotEquals(null, res.get('audioBase64'));
        System.assertEquals(0, (Integer) res.get('smartCreditsRemaining'));
    }

    @IsTest
    static void testGetHubAccessConfigIncludesSmartVoiceFlags() {
        CrmHubTtsService.apiKeyOverride = '';
        Test.startTest();
        Map<String, Object> cfg = CrmHubListController.getHubAccessConfig();
        Test.stopTest();
        System.assertEquals(false, cfg.get('elevenLabsConfigured'));
        System.assertEquals(1, (Integer) cfg.get('smartCreditsRemaining'));
        CrmHubTtsService.apiKeyOverride = 'test-key';
        cfg = CrmHubListController.getHubAccessConfig();
        System.assertEquals(true, cfg.get('elevenLabsConfigured'));
    }

    @IsTest
    static void testGetHubBriefingVoiceStatus() {
        CrmHubTtsService.apiKeyOverride = 'test-key';
        Test.startTest();
        Map<String, Object> status = CrmHubListController.getHubBriefingVoiceStatus();
        Test.stopTest();
        System.assertEquals(true, status.get('success'));
        System.assertEquals(true, status.get('elevenLabsConfigured'));
        System.assertEquals(1, (Integer) status.get('smartCreditsRemaining'));
    }

    @IsTest
    static void testSynthesizeHubSpeechEmptyText() {
        Test.startTest();
        Map<String, Object> res = CrmHubListController.synthesizeHubSpeech('   ', false);
        Test.stopTest();
        System.assertEquals(false, res.get('success'));
        System.assertEquals('browser', res.get('fallback'));
    }

    @IsTest
    static void testSynthesizeHubSpeechHttpFailureFallsBack() {
        CrmHubTtsService.apiKeyOverride = 'test-key';
        CrmHubTtsService.skipCallout = false;
        CrmHubTtsService.testSpeechBodyOverride = null;
        Test.setMock(HttpCalloutMock.class, new ElevenLabsFailHttpMock());
        Test.startTest();
        Map<String, Object> res = CrmHubListController.synthesizeHubSpeech('Speak this.', true);
        Test.stopTest();
        System.assertEquals(false, res.get('success'));
        System.assertEquals('browser', res.get('fallback'));
        System.assertEquals('webspeech', res.get('engine'));
    }

    @IsTest
    static void testFetchHubBriefingInsightsAndHighlights() {
        Test.setMock(HttpCalloutMock.class, new BriefingHttpCalloutMock());
        Test.setMock(WebServiceMock.class, new BriefingWebServiceMock());

        Account acc = new Account(Name = 'Insight Acc', Industry = 'Technology', Type = 'Customer');
        insert acc;
        Opportunity big = newHubTestOpportunity('Insight Big Deal', acc.Id);
        big.Amount = 50000;
        big.CloseDate = Date.today().addDays(3);
        big.NextStep = 'Send proposal';
        insert big;
        Lead ld = new Lead(
            LastName = 'InsightLead',
            Company = 'Insight Co',
            Status = 'Open - Not Contacted',
            Title = 'CTO'
        );
        insert ld;
        Contact con = new Contact(LastName = 'InsightContact', AccountId = acc.Id, Title = 'Manager');
        insert con;

        String startIso = String.valueOf(Date.today().addDays(-1));
        String endIso = String.valueOf(Date.today());
        String tabsJson = JSON.serialize(new List<String>{ 'leads', 'opps', 'accounts', 'contacts' });

        CrmHubListController.hubAccessModeOverride = CrmHubListController.HUB_ACCESS_PARTIAL;
        try {
            Test.startTest();
            Map<String, Object> res = CrmHubListController.fetchHubBriefing(
                startIso,
                endIso,
                tabsJson,
                'everything',
                'sales'
            );
            Test.stopTest();
            System.assertEquals(true, res.get('success'), 'Briefing error: ' + res.get('error'));
            System.assert(String.isNotBlank((String) res.get('scriptText')), 'Expected dense spoken scriptText');
            System.assert(String.isNotBlank((String) res.get('digestText')), 'Expected digestText');
            System.assertEquals('sales', res.get('audience'));
            System.assert(
                String.valueOf(res.get('scriptText')).length() <= CrmHubBriefingNarrative.MAX_SPEECH_CHARS,
                'Spoken script must stay within speech budget cap'
            );
            System.assert(
                String.valueOf(res.get('digestText')).length() <= CrmHubBriefingNarrative.MAX_DIGEST_CHARS,
                'Digest must stay within digest budget cap'
            );
            Map<String, Object> insights = (Map<String, Object>) res.get('insights');
            System.assertNotEquals(null, insights);
            System.assert(((List<Object>) insights.get('topDeals')).size() >= 1, 'Expected top deal');
            System.assert(((List<Object>) insights.get('closingThisWeek')).size() >= 1, 'Expected closing soon');

            List<Object> objects = (List<Object>) res.get('objects');
            Boolean sawOppHighlights = false;
            for (Object rowObj : objects) {
                Map<String, Object> row = (Map<String, Object>) rowObj;
                if (String.valueOf(row.get('api')) == 'Opportunity') {
                    List<Object> highlights = (List<Object>) row.get('highlights');
                    if (highlights != null && !highlights.isEmpty()) {
                        sawOppHighlights = true;
                    }
                }
            }
            System.assert(sawOppHighlights, 'Expected opportunity highlights');

            Map<String, Object> actions = (Map<String, Object>) res.get('actions');
            System.assertNotEquals(null, actions.get('oppsNextActionDue'));
            System.assertNotEquals(null, actions.get('staleOpps'));
        } finally {
            CrmHubListController.hubAccessModeOverride = null;
        }
    }

    @IsTest
    static void testFetchHubBriefingHrFocusTodayScreeningGaps() {
        Test.setMock(HttpCalloutMock.class, new BriefingHttpCalloutMock());
        Test.setMock(WebServiceMock.class, new BriefingWebServiceMock());

        Position__c pos = new Position__c(
            Name = 'FocusToday Consultant',
            Years_Of_Experience__c = 3,
            Max_Pay__c = 10000,
            Min_Pay__c = 8000,
            Status__c = 'Open - Approved',
            Hire_By__c = Date.today().addDays(5)
        );
        insert pos;
        Job_Application__c ja = new Job_Application__c(
            Position__c = pos.Id,
            Status__c = 'New'
        );
        insert ja;
        Lead applicantLead = new Lead(
            LastName = 'FocusTodayLeadApplicant',
            Company = 'FocusToday Co',
            Status = 'Open - Not Contacted',
            Position__c = pos.Id
        );
        insert applicantLead;

        String startIso = String.valueOf(Date.today().addDays(-7));
        String endIso = String.valueOf(Date.today());
        String tabsJson = JSON.serialize(new List<String>{ 'jobapps', 'positions', 'leads' });

        CrmHubListController.hubAccessModeOverride = CrmHubListController.HUB_ACCESS_FULL;
        try {
            Test.startTest();
            Map<String, Object> res = CrmHubListController.fetchHubBriefing(
                startIso,
                endIso,
                tabsJson,
                'everything',
                'hr'
            );
            Test.stopTest();

            System.assertEquals(true, res.get('success'), 'Briefing error: ' + res.get('error'));
            System.assertEquals('hr', res.get('audience'));
            Map<String, Object> actions = (Map<String, Object>) res.get('actions');
            List<Object> focus = (List<Object>) actions.get('focusToday');
            System.assertNotEquals(null, focus, 'Expected focusToday list');
            System.assert(focus.size() >= 1, 'Expected at least one HR focus item');

            Boolean sawScreening = false;
            Boolean sawCreateApp = false;
            for (Object raw : focus) {
                Map<String, Object> item = (Map<String, Object>) raw;
                String reason = String.valueOf(item.get('reason'));
                String kind = String.valueOf(item.get('kind'));
                if (reason != null && reason.toLowerCase().contains('screening')) {
                    sawScreening = true;
                }
                if (
                    kind == 'hr_create_job_app' ||
                    (reason != null && reason.toLowerCase().contains('create job application'))
                ) {
                    sawCreateApp = true;
                }
            }
            System.assert(sawScreening, 'Expected screening schedule focus: ' + JSON.serialize(focus));
            System.assert(
                sawCreateApp,
                'Expected Create Job Application for Lead focus: ' + JSON.serialize(focus)
            );

            String digest = String.valueOf(res.get('digestText'));
            System.assert(digest.contains('Focus today'), 'Digest should include Focus today: ' + digest);
            System.assert(
                digest.toLowerCase().contains('screening') ||
                    digest.toLowerCase().contains('job application'),
                'Digest should mention screening or create job app: ' + digest
            );
            System.assert(
                CrmHubBriefingNarrative.audienceGuidance('hr').toLowerCase().contains('lead'),
                'HR guidance should mention Leads → Job Application'
            );
        } finally {
            CrmHubListController.hubAccessModeOverride = null;
        }
    }

    @IsTest
    static void testEnrichFocusTodaySalesOpsCeoPackaging() {
        Map<String, Object> actions = new Map<String, Object>{
            'overdueTasks' => new List<Object>{
                new Map<String, Object>{ 'id' => null, 'name' => 'Overdue A' }
            },
            'dueTodayTasks' => new List<Object>{
                new Map<String, Object>{ 'name' => 'Due B' }
            },
            'eventsToday' => new List<Object>{
                new Map<String, Object>{ 'name' => 'Orphan Meet', 'related' => null, 'who' => null }
            },
            'oppsClosingToday' => new List<Object>{
                new Map<String, Object>{
                    'name' => 'Close Deal',
                    'amount' => 1500000,
                    'nextStep' => 'Sign'
                }
            },
            'oppsNextActionDue' => new List<Object>{
                new Map<String, Object>{
                    'name' => 'Next Deal',
                    'amount' => 25000,
                    'nextStep' => 'Call AE'
                }
            },
            'staleOpps' => new List<Object>{
                new Map<String, Object>{ 'name' => 'Stale Deal', 'amount' => 800 }
            }
        };

        CrmHubListController.enrichFocusToday(actions, 'sales', new List<String>{ 'Opportunity' });
        System.assert(
            ((List<Object>) actions.get('focusToday')).size() >= 2,
            'Sales focus should package deal queues'
        );

        CrmHubListController.enrichFocusToday(actions, 'ops', new List<String>());
        List<Object> opsFocus = (List<Object>) actions.get('focusToday');
        System.assert(opsFocus.size() >= 2, 'Ops focus should package tasks/meetings');

        CrmHubListController.enrichFocusToday(actions, 'ceo', new List<String>{ 'Opportunity' });
        System.assert(
            ((List<Object>) actions.get('focusToday')).size() >= 1,
            'CEO focus should include sales leverage'
        );
    }

    /** @description Absorbs async HTTP callouts flushed by Test.stopTest after Hub briefing DML. */
    private class BriefingHttpCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{}');
            return res;
        }
    }

    private class ElevenLabsFailHttpMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setStatus('Service Unavailable');
            res.setBody('down');
            return res;
        }
    }

    @IsTest
    static void testFetchHubHomeStatsPartial() {
        Account acc = new Account(Name = 'Home Remote Acc');
        insert acc;

        CrmHubListController.hubAccessModeOverride = CrmHubListController.HUB_ACCESS_PARTIAL;
        try {
            Test.startTest();
            Map<String, Object> res = CrmHubListController.fetchHubHomeStats();
            Test.stopTest();
            System.assertEquals(true, res.get('success'), 'error: ' + res.get('error'));
            System.assertEquals(false, res.get('isFullAccess'));
            List<Object> tabs = (List<Object>) CrmHubListController.getHubAccessConfig().get('allowedTabs');
            System.assert(tabs.contains('home'), 'Partial tabs should include home');
            System.assert(!tabs.contains('jobapps'));
        } finally {
            CrmHubListController.hubAccessModeOverride = null;
        }
    }

    @IsTest
    static void testFetchHubHomeStatsFull() {
        Position__c pos = new Position__c(
            Name = 'Home Remote Pos',
            Years_Of_Experience__c = 2,
            Max_Pay__c = 9000,
            Min_Pay__c = 7000,
            Status__c = 'New Position'
        );
        insert pos;
        insert new Job_Application__c(Position__c = pos.Id, Status__c = 'New');

        CrmHubListController.hubAccessModeOverride = CrmHubListController.HUB_ACCESS_FULL;
        try {
            Test.startTest();
            Map<String, Object> res = CrmHubListController.fetchHubHomeStats();
            Test.stopTest();
            System.assertEquals(true, res.get('success'), 'error: ' + res.get('error'));
            System.assertEquals(true, res.get('isFullAccess'));
            Map<String, Object> me = (Map<String, Object>) res.get('me');
            Map<String, Object> tw = (Map<String, Object>) me.get('thisWeek');
            System.assert(tw.containsKey('applicantsNew'));
            List<Object> tabs = (List<Object>) CrmHubListController.getHubAccessConfig().get('allowedTabs');
            System.assert(tabs.contains('home'));
            System.assert(tabs.contains('jobapps'));
        } finally {
            CrmHubListController.hubAccessModeOverride = null;
        }
    }

    /** @description Absorbs SOAP/Metadata callouts that may run with Lead/Opp automation. */
    private class BriefingWebServiceMock implements WebServiceMock {
        public void doInvoke(
            Object stub,
            Object request,
            Map<String, Object> response,
            String endpoint,
            String soapAction,
            String requestName,
            String responseNS,
            String responseName,
            String responseType
        ) {
            response.put('response_x', null);
        }
    }
}