/**
 * @description Tests for HubRecordModalUtil (layout extraction, modal payload).
 */
@IsTest
private class HubRecordModalUtilTest {

    @IsTest
    static void testFetchRecordModalDataBlankId() {
        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData('');
        System.assert(res.containsKey('error'));
    }

    @IsTest
    static void testFetchRecordModalDataWithLayoutOverride() {
        Account acc = new Account(Name = 'Modal Layout Acc');
        insert acc;

        HubRecordModalUtil.testLayoutOverride = buildTestLayout();

        Test.startTest();
        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData(acc.Id);
        Test.stopTest();

        HubRecordModalUtil.testLayoutOverride = null;

        System.assertEquals(null, res.get('error'), 'Should load modal data: ' + res.get('error'));
        System.assertEquals('Account', res.get('objectApi'));
        System.assertEquals('Modal Layout Acc', res.get('recordName'));
        Map<String, Object> values = (Map<String, Object>) res.get('values');
        System.assertEquals('Modal Layout Acc', values.get('Name'));
        System.assert(res.containsKey('fieldMeta'), 'Should include field metadata');
        System.assert(res.containsKey('relatedListData'), 'Should include related list data key');
        System.assert(res.containsKey('tabs'), 'Should include tabs');
        List<Object> tabs = (List<Object>) res.get('tabs');
        System.assert(!tabs.isEmpty(), 'Should have at least Details tab');
    }

    @IsTest
    static void testExtractLayoutFieldApis() {
        Set<String> fields = HubRecordModalUtil.extractLayoutFieldApis(buildTestLayout(), 'Account');
        System.assert(fields.contains('Name'));
        System.assert(fields.contains('Type'));
    }

    @IsTest
    static void testControllerRemoteAction() {
        Account acc = new Account(Name = 'Remote Modal Acc');
        insert acc;
        HubRecordModalUtil.testLayoutOverride = buildTestLayout();

        Map<String, Object> res = CrmHubListController.fetchRecordModalData(acc.Id);
        HubRecordModalUtil.testLayoutOverride = null;

        System.assertEquals(null, res.get('error'), 'unexpected error: ' + res);
        System.assertEquals('Remote Modal Acc', res.get('recordName'));
    }


    @IsTest
    static void testResolveRecordTypeIdForAccount() {
        Account acc = new Account(Name = 'RT Acc');
        insert acc;
        Schema.DescribeSObjectResult accountDescribe = Account.SObjectType.getDescribe();
        Id rtId = HubRecordModalUtil.resolveRecordTypeId(acc.Id, 'Account', accountDescribe);
        System.assertNotEquals(null, rtId);
    }

    @IsTest
    static void testFilterQueryableFieldsReference() {
        List<String> fields = HubRecordModalUtil.filterQueryableFields(
            'Contact',
            new Set<String>{ 'Account.Name', 'BadField', 'Name' }
        );
        System.assert(fields.contains('Name'));
        System.assert(fields.contains('Account.Name'));
    }

    @IsTest
    static void testFilterQueryableFieldsCustomRelationship() {
        List<String> fields = HubRecordModalUtil.filterQueryableFields(
            'Job_Application__c',
            new Set<String>{ 'Position__r.Name', 'Lead__r.Name', 'Name', 'Bogus__r.Name' }
        );
        System.assert(fields.contains('Position__r.Name'));
        System.assert(fields.contains('Lead__r.Name'));
        System.assert(!fields.contains('Bogus__r.Name'));
    }

    @IsTest
    static void testFetchRecordModalDetailsShowsLookupName() {
        Test.setMock(HttpCalloutMock.class, new HubModalOkHttpMock());
        Position__c pos = new Position__c(
            Name = 'Lookup Display Pos',
            Years_Of_Experience__c = 2,
            Min_Pay__c = 5000,
            Max_Pay__c = 8000,
            Status__c = 'New Position'
        );
        insert pos;
        Lead ld = new Lead(
            LastName = 'LookupDisplayLead',
            Company = 'Lookup Display Co',
            Status = 'Open - Not Contacted',
            Position__c = pos.Id
        );
        insert ld;
        Job_Application__c ja = new Job_Application__c(
            Position__c = pos.Id,
            Lead__c = ld.Id,
            Status__c = 'Screening',
            NextStep__c = 'Got any feedback?'
        );
        insert ja;

        Map<String, Object> details = HubRecordModalUtil.fetchRecordModalDetails(ja.Id);
        System.assertEquals(null, details.get('error'), 'unexpected: ' + details);
        Map<String, Object> values = (Map<String, Object>) details.get('values');
        System.assertNotEquals(null, values);
        System.assertEquals('Lookup Display Pos', values.get('Position__r.Name'));
        System.assertNotEquals(null, values.get('Lead__r.Name'));
        System.assert(String.valueOf(values.get('Lead__r.Name')).contains('LookupDisplayLead'));
    }

    @IsTest
    static void testRecordToValueMapRelationship() {
        Account acc = new Account(Name = 'Value Map Acc');
        insert acc;
        insert new Opportunity(
            Name = 'Value Map Open Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Type = 'Existing Business',
            Type_of_Service__c = 'Other'
        );
        Contact con = new Contact(LastName = 'ValueMap', AccountId = acc.Id);
        insert con;
        Contact loaded = [
            SELECT Id, Name, Account.Name
            FROM Contact
            WHERE Id = :con.Id
        ];
        Map<String, Object> values = HubRecordModalUtil.recordToValueMap(
            loaded,
            new List<String>{ 'Name', 'Account.Name' },
            'Contact',
            new Set<String>{ 'Name', 'AccountId' }
        );
        System.assertEquals('Value Map Acc', values.get('Account.Name'));
    }

    @IsTest
    static void testExtractLayoutFieldApisReference() {
        Map<String, Object> layout = new Map<String, Object>{
            'detailLayoutSections' => new List<Object>{
                new Map<String, Object>{
                    'layoutRows' => new List<Object>{
                        new Map<String, Object>{
                            'layoutItems' => new List<Object>{
                                new Map<String, Object>{
                                    'placeholder' => false,
                                    'layoutComponents' => new List<Object>{
                                        new Map<String, Object>{
                                            'type' => 'Field',
                                            'value' => 'AccountId',
                                            'details' => new Map<String, Object>{
                                                'type' => 'reference',
                                                'relationshipName' => 'Account'
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        };
        Set<String> fields = HubRecordModalUtil.extractLayoutFieldApis(layout, 'Contact');
        System.assert(fields.contains('AccountId'));
        System.assert(fields.contains('Account.Name'));
    }

    @IsTest
    static void testFetchRecordModalDataRecordNotFound() {
        Account acc = new Account(Name = 'Delete Me');
        insert acc;
        Id missingId = acc.Id;
        HubRecordModalUtil.testLayoutOverride = buildTestLayout();
        delete acc;
        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData(missingId);
        HubRecordModalUtil.testLayoutOverride = null;
        System.assertEquals('Record not found.', res.get('error'));
    }

    @IsTest
    static void testFetchRecordModalDataPlaceholderOnlyLayoutStillQueriesName() {
        Account acc = new Account(Name = 'Empty Layout Acc');
        insert acc;
        HubRecordModalUtil.testLayoutOverride = new Map<String, Object>{
            'detailLayoutSections' => new List<Object>{
                new Map<String, Object>{
                    'layoutRows' => new List<Object>{
                        new Map<String, Object>{
                            'layoutItems' => new List<Object>{
                                new Map<String, Object>{
                                    'placeholder' => true,
                                    'layoutComponents' => new List<Object>()
                                }
                            }
                        }
                    }
                }
            }
        };
        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData(acc.Id);
        HubRecordModalUtil.testLayoutOverride = null;
        System.assertEquals(null, res.get('error'), 'unexpected error: ' + res);
        Map<String, Object> values = (Map<String, Object>) res.get('values');
        System.assertEquals('Empty Layout Acc', values.get('Name'));
    }

    @IsTest
    static void testRelatedListColumnParsing() {
        String fieldApi = HubRecordModalUtil.relatedListColumnToFieldApi('CONTACT.FULL_NAME');
        System.assertEquals('Name', fieldApi);
        System.assertEquals('Custom__c', HubRecordModalUtil.relatedListColumnToFieldApi('OPPORTUNITY.Custom__c'));
    }

    @IsTest
    static void testBuildTabsFromLayout() {
        Map<String, Object> layout = buildTestLayout();
        List<Map<String, Object>> tabs = HubRecordModalUtil.buildTabsFromLayout(layout);
        System.assertEquals('Details', tabs[0].get('label'));
        System.assertEquals('details', tabs[0].get('type'));
        System.assert(tabs.size() >= 2, 'Should include related list tabs from layout');
    }

    @IsTest
    static void testResolveTabLabel() {
        System.assertEquals('Details', HubRecordModalUtil.resolveTabLabel('Standard.Tab.detail'));
        System.assertEquals('Leads', HubRecordModalUtil.resolveTabLabel('Leads'));
    }

    @IsTest
    static void testParseFlexiPageMetadata() {
        Map<String, Object> metadata = new Map<String, Object>{
            'flexiPageRegions' => new List<Object>{
                new Map<String, Object>{
                    'name' => 'maintabs',
                    'itemInstances' => new List<Object>{
                        new Map<String, Object>{
                            'componentInstance' => new Map<String, Object>{
                                'componentName' => 'flexipage:tab',
                                'componentInstanceProperties' => new List<Object>{
                                    new Map<String, Object>{ 'name' => 'active', 'value' => 'true' },
                                    new Map<String, Object>{ 'name' => 'body', 'value' => 'detailFacet' },
                                    new Map<String, Object>{ 'name' => 'title', 'value' => 'Standard.Tab.detail' }
                                }
                            }
                        },
                        new Map<String, Object>{
                            'componentInstance' => new Map<String, Object>{
                                'componentName' => 'flexipage:tab',
                                'componentInstanceProperties' => new List<Object>{
                                    new Map<String, Object>{ 'name' => 'body', 'value' => 'leadsFacet' },
                                    new Map<String, Object>{ 'name' => 'title', 'value' => 'Leads' }
                                }
                            }
                        }
                    }
                },
                new Map<String, Object>{
                    'name' => 'header',
                    'itemInstances' => new List<Object>{
                        new Map<String, Object>{
                            'componentInstance' => new Map<String, Object>{
                                'componentName' => 'flexipage:tabset',
                                'componentInstanceProperties' => new List<Object>{
                                    new Map<String, Object>{ 'name' => 'tabs', 'value' => 'maintabs' }
                                }
                            }
                        }
                    }
                },
                new Map<String, Object>{
                    'name' => 'detailFacet',
                    'itemInstances' => new List<Object>{
                        new Map<String, Object>{
                            'componentInstance' => new Map<String, Object>{
                                'componentName' => 'force:detailPanel',
                                'componentInstanceProperties' => new List<Object>()
                            }
                        }
                    }
                },
                new Map<String, Object>{
                    'name' => 'leadsFacet',
                    'itemInstances' => new List<Object>{
                        new Map<String, Object>{
                            'componentInstance' => new Map<String, Object>{
                                'componentName' => 'lst:dynamicRelatedList',
                                'componentInstanceProperties' => new List<Object>{
                                    new Map<String, Object>{ 'name' => 'relatedListApiName', 'value' => 'Leads__r' },
                                    new Map<String, Object>{ 'name' => 'relatedListLabel', 'value' => 'Leads' }
                                }
                            }
                        }
                    }
                }
            }
        };
        Map<String, Object> layout = buildTestLayout();
        List<Map<String, Object>> tabs = HubRecordModalUtil.parseFlexiPageMetadata(metadata, layout);
        System.assertEquals(2, tabs.size());
        System.assertEquals('Details', tabs[0].get('label'));
        System.assertEquals('Leads', tabs[1].get('label'));
        System.assertEquals('related', tabs[1].get('type'));
    }

    @IsTest
    static void testFormatFieldValueForModalDate() {
        Account acc = new Account(Name = 'Date Acc');
        insert acc;
        acc = [SELECT Id, CreatedDate FROM Account WHERE Id = :acc.Id];
        Map<String, Schema.SObjectField> fieldMap = Account.SObjectType.getDescribe().fields.getMap();
        Object formatted = HubRecordModalUtil.formatFieldValueForModal(
            'CreatedDate',
            acc.CreatedDate,
            fieldMap
        );
        System.assertNotEquals(null, formatted);
        System.assert(String.valueOf(formatted).length() > 0);
    }

    @IsTest
    static void testFetchRelatedListDataWithTabsOverride() {
        Account acc = new Account(Name = 'Tab RL Acc');
        insert acc;
        Task t = new Task(Subject = 'Tab Child', WhatId = acc.Id, Status = 'Not Started', Priority = 'Normal');
        insert t;
        HubRecordModalUtil.testLayoutOverride = buildTestLayout();
        HubRecordModalUtil.testTabsOverride = new List<Map<String, Object>>{
            new Map<String, Object>{ 'id' => 'details', 'label' => 'Details', 'type' => 'details' },
            new Map<String, Object>{
                'id' => 'rl_0',
                'label' => 'Tasks',
                'type' => 'related',
                'relatedListName' => 'Tasks',
                'relatedListLabel' => 'Tasks',
                'relatedListMeta' => new Map<String, Object>{
                    'label' => 'Tasks',
                    'name' => 'Tasks',
                    'columns' => new List<Object>{ 'TASK.SUBJECT' }
                }
            }
        };
        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData(acc.Id);
        HubRecordModalUtil.testLayoutOverride = null;
        HubRecordModalUtil.testTabsOverride = null;
        List<Object> rlData = (List<Object>) res.get('relatedListData');
        System.assertEquals(1, rlData.size());
        Map<String, Object> block = (Map<String, Object>) rlData[0];
        System.assertEquals('rl_0', block.get('tabId'));
        List<Object> rows = (List<Object>) block.get('rows');
        System.assertEquals(1, rows.size());
    }

    @IsTest
    static void testFetchRelatedListDataViaSoql() {
        Account acc = new Account(Name = 'RL Parent Acc');
        insert acc;
        Task t = new Task(Subject = 'RL Child', WhatId = acc.Id, Status = 'Not Started', Priority = 'Normal');
        insert t;

        Map<String, Object> block = HubRecordModalUtil.fetchOneRelatedList(
            'Account',
            acc.Id,
            new Map<String, Object>{
                'label' => 'Tasks',
                'relatedList' => 'RelatedActivityList',
                'columns' => new List<Object>{ 'TASK.SUBJECT', 'TASK.STATUS' }
            },
            'Tasks',
            5
        );

        System.assertNotEquals(null, block);
        List<Object> rows = (List<Object>) block.get('rows');
        System.assertEquals(1, rows.size());
        Map<String, Object> row = (Map<String, Object>) rows[0];
        System.assertEquals(String.valueOf(t.Id), String.valueOf(row.get('id')));
        Map<String, Object> cells = (Map<String, Object>) row.get('cells');
        System.assertEquals('RL Child', cells.get('Subject'));
    }

    @IsTest
    static void testFetchRelatedListDataSkipsActivityLists() {
        Account acc = new Account(Name = 'Skip RL Acc');
        insert acc;
        HubRecordModalUtil.testLayoutOverride = new Map<String, Object>{
            'detailLayoutSections' => new List<Object>(),
            'relatedLists' => new List<Object>{
                new Map<String, Object>{
                    'label' => 'Activity History',
                    'name' => 'ActivityHistories',
                    'relatedList' => 'RelatedHistoryList',
                    'columns' => new List<Object>{ 'SUBJECT' }
                }
            }
        };
        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData(acc.Id);
        HubRecordModalUtil.testLayoutOverride = null;
        List<Object> rlData = (List<Object>) res.get('relatedListData');
        System.assertEquals(0, rlData.size());
    }

    @IsTest
    static void testRelatedListHelpers() {
        Map<String, Object> rec = new Map<String, Object>{ 'Id' => '001000000000001', 'Name' => 'Acme' };
        System.assertEquals('Acme', HubRecordModalUtil.relatedRowDisplayName(rec));
        System.assertEquals('Acme', HubRecordModalUtil.readRelatedRecordField(rec, 'Name'));
        System.assertEquals('FULL NAME', HubRecordModalUtil.relatedListColumnLabel('CONTACT.FULL_NAME', 'Name'));
        List<Map<String, Object>> cols = HubRecordModalUtil.parseRelatedListColumns(
            new Map<String, Object>{ 'columns' => new List<Object>() }
        );
        System.assertEquals(1, cols.size());
        System.assertEquals('Name', cols[0].get('field'));
        System.assertEquals('Name', cols[0].get('fieldApiName'));
    }

    @IsTest
    static void testFetchRelatedListDataEmptyWhenHttpFails() {
        Account acc = new Account(Name = 'RL Fail Acc');
        insert acc;
        HubRecordModalUtil.testLayoutOverride = new Map<String, Object>{
            'detailLayoutSections' => new List<Object>(),
            'relatedLists' => new List<Object>{
                new Map<String, Object>{
                    'label' => 'Contacts',
                    'name' => 'Contacts',
                    'relatedList' => 'RelatedContactList',
                    'columns' => new List<Object>{ 'CONTACT.FULL_NAME' }
                }
            }
        };
        Test.setMock(HttpCalloutMock.class, new HubModalBadHttpMock());
        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData(acc.Id);
        HubRecordModalUtil.testLayoutOverride = null;
        List<Object> rlData = (List<Object>) res.get('relatedListData');
        System.assertEquals(1, rlData.size());
        Map<String, Object> block = (Map<String, Object>) rlData[0];
        System.assertEquals(0, ((List<Object>) block.get('rows')).size());
    }

    @IsTest
    static void testMapModalFieldTypes() {
        System.assertEquals('boolean', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.BOOLEAN));
        System.assertEquals('currency', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.CURRENCY));
        System.assertEquals('double', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.DOUBLE));
        System.assertEquals('percent', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.PERCENT));
        System.assertEquals('date', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.DATE));
        System.assertEquals('datetime', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.DATETIME));
        System.assertEquals('email', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.EMAIL));
        System.assertEquals('phone', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.PHONE));
        System.assertEquals('url', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.URL));
        System.assertEquals('reference', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.REFERENCE));
        System.assertEquals('picklist', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.PICKLIST));
        System.assertEquals('textarea', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.TEXTAREA));
        System.assertEquals('string', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.STRING));
    }

    @IsTest
    static void testFetchRelatedListDataNoLayoutRelatedLists() {
        Account acc = new Account(Name = 'No RL Acc');
        insert acc;
        HubRecordModalUtil.testLayoutOverride = new Map<String, Object>{
            'detailLayoutSections' => new List<Object>()
        };
        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData(acc.Id);
        HubRecordModalUtil.testLayoutOverride = null;
        List<Object> rlData = (List<Object>) res.get('relatedListData');
        System.assertEquals(0, rlData.size());
    }

    @IsTest
    static void testBuildFieldMetaCoversFieldTypes() {
        Map<String, Object> meta = HubRecordModalUtil.buildFieldMeta(
            'Account',
            new List<String>{
                'Name',
                'Type',
                'Phone',
                'Website',
                'AnnualRevenue',
                'NumberOfEmployees',
                'CreatedDate',
                'Description',
                'Id',
                'BadField',
                'Account.Name'
            }
        );
        System.assertEquals('url', ((Map<String, Object>) meta.get('Website')).get('type'));
        System.assertEquals('phone', ((Map<String, Object>) meta.get('Phone')).get('type'));
        System.assertEquals('textarea', ((Map<String, Object>) meta.get('Description')).get('type'));
        System.assertEquals(true, ((Map<String, Object>) meta.get('Description')).get('htmlCapable'));
        System.assert(!meta.containsKey('BadField'));
        System.assert(!meta.containsKey('Account.Name'));
    }

    @IsTest
    static void testRelatedListHelperBranches() {
        System.assertEquals('Type', HubRecordModalUtil.relatedListColumnToFieldApi('CONTACT.TYPE'));
        System.assertEquals('Status', HubRecordModalUtil.relatedListColumnToFieldApi('Status'));
        System.assertEquals('Custom__c', HubRecordModalUtil.relatedListColumnToFieldApi('Custom__c'));
        System.assertEquals('', HubRecordModalUtil.relatedListColumnToFieldApi(''));

        Map<String, Object> rec = new Map<String, Object>{ 'title' => 'Mgr', 'Id' => '001xx' };
        System.assertEquals('Mgr', HubRecordModalUtil.readRelatedRecordField(rec, 'Title'));

        Map<String, Object> rec2 = new Map<String, Object>{ 'Id' => '001xx' };
        System.assertEquals('001xx', HubRecordModalUtil.relatedRowDisplayName(rec2));

        List<Map<String, Object>> cols = HubRecordModalUtil.parseRelatedListColumns(
            new Map<String, Object>{ 'columns' => new List<Object>() }
        );
        System.assertEquals(1, cols.size());
        System.assertEquals('Name', cols[0].get('field'));
        System.assertEquals('Name', cols[0].get('fieldApiName'));

        System.assert(
            HubRecordModalUtil.relatedListColumnLabel('CONTACT.FULL_NAME', 'Name').contains('FULL')
        );
    }

    @IsTest
    static void testFetchRelatedListDataSkipsUnsupportedLists() {
        Account acc = new Account(Name = 'Skip RL');
        insert acc;
        HubRecordModalUtil.testLayoutOverride = new Map<String, Object>{
            'detailLayoutSections' => new List<Object>(),
            'relatedLists' => new List<Object>{
                new Map<String, Object>{
                    'label' => 'Activity',
                    'name' => 'ActivityHistories',
                    'relatedList' => 'RelatedActivityList',
                    'columns' => new List<Object>{ 'SUBJECT' }
                },
                new Map<String, Object>{
                    'label' => 'Blank',
                    'relatedList' => 'RelatedContactList'
                }
            }
        };
        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData(acc.Id);
        HubRecordModalUtil.testLayoutOverride = null;
        List<Object> rl = (List<Object>) res.get('relatedListData');
        System.assert(rl.isEmpty());
    }

    @IsTest
    static void testFetchOneRelatedListEmptyRecords() {
        Account acc = new Account(Name = 'Empty RL');
        insert acc;
        Map<String, Object> block = HubRecordModalUtil.fetchOneRelatedList(
            'Account',
            acc.Id,
            new Map<String, Object>{ 'label' => 'Contacts', 'columns' => new List<Object>{ 'CONTACT.FULL_NAME' } },
            'Contacts',
            5
        );
        System.assertNotEquals(null, block);
        System.assertEquals(0, ((List<Object>) block.get('rows')).size());
    }

    @IsTest
    static void testRecordDisplayNameFallsBackToId() {
        Task t = new Task(Subject = 'Coverage Task', Status = 'Not Started', Priority = 'Normal');
        insert t;
        Task loaded = [SELECT Id, Subject FROM Task WHERE Id = :t.Id];
        System.assertEquals(String.valueOf(loaded.Id), HubRecordModalUtil.recordDisplayName(loaded, 'Task'));
    }

    private class HubModalEmptyRlMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"records":[]}');
            return res;
        }
    }

    private class HubModalRelatedListMock implements HttpCalloutMock {
        private Id contactId;
        private String contactName;

        HubModalRelatedListMock(Id contactId, String contactName) {
            this.contactId = contactId;
            this.contactName = contactName;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String endpoint = req.getEndpoint();
            if (endpoint.contains('/describe/layouts/')) {
                res.setBody(
                    '{"detailLayoutSections":[],"relatedLists":[{"label":"Contacts","name":"Contacts","relatedList":"RelatedContactList","columns":["CONTACT.FULL_NAME"]}]}'
                );
            } else if (endpoint.contains('/Contacts')) {
                res.setBody(
                    '{"records":[{"attributes":{"type":"Contact"},"Id":"' +
                    contactId +
                    '","Name":"' +
                    contactName +
                    '","Title":"Mgr"}]}'
                );
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    @IsTest
    static void testResolveLayoutViaHttpMock() {
        Id recordTypeId = Account.SObjectType.getDescribe().getRecordTypeInfos()[0].getRecordTypeId();
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HubModalLayoutMock());
        Map<String, Object> layout = HubRecordModalUtil.resolveLayout('Account', recordTypeId);
        Test.stopTest();
        System.assertNotEquals(null, layout);
        System.assert(layout.containsKey('detailLayoutSections'));
    }

    @IsTest
    static void testHttpGetJsonNon200() {
        Test.setMock(HttpCalloutMock.class, new HubModalBadHttpMock());
        Map<String, Object> body = HubRecordModalUtil.httpGetJson('https://example.com/services/data/v60.0/sobjects/Account/describe/layouts/012000000000000AAA');
        System.assertEquals(null, body);
    }

    private class HubModalLayoutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"detailLayoutSections":[{"heading":"Info","layoutRows":[{"layoutItems":[{"placeholder":false,"layoutComponents":[{"type":"Field","value":"Name","details":{"type":"string","name":"Name"}}]}]}]}]}'
            );
            return res;
        }
    }

    private class HubModalBadHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('');
            return res;
        }
    }

    @IsTest
    static void testFetchRecordModalDataIncludesFieldMeta() {
        Account acc = new Account(Name = 'Field Meta Acc', Website = 'https://example.com');
        insert acc;
        HubRecordModalUtil.testLayoutOverride = buildTestLayout();

        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData(acc.Id);
        HubRecordModalUtil.testLayoutOverride = null;

        System.assertEquals(null, res.get('error'), 'unexpected error: ' + res);
        Map<String, Object> fieldMeta = (Map<String, Object>) res.get('fieldMeta');
        System.assertNotEquals(null, fieldMeta);
        System.assert(fieldMeta.containsKey('Name'));
    }

    @IsTest
    static void testBuildPathSteps() {
        Schema.DescribeFieldResult stageDesc = Opportunity.StageName.getDescribe();
        List<String> ordered = new List<String>{ 'Prospecting', 'Qualification', 'Closed Won' };
        Map<String, String> guidance = new Map<String, String>{
            'Qualification' => 'Confirm budget and timeline.'
        };
        List<Map<String, Object>> steps = HubRecordModalUtil.buildPathSteps(
            ordered,
            'Qualification',
            guidance,
            stageDesc
        );
        System.assertEquals(3, steps.size());
        System.assertEquals('complete', steps[0].get('status'));
        System.assertEquals('current', steps[1].get('status'));
        System.assertEquals('upcoming', steps[2].get('status'));
        System.assertEquals('Confirm budget and timeline.', steps[1].get('guidanceText'));
    }

    @IsTest
    static void testResolvePathFieldApiMappings() {
        Map<String, Object> config = new Map<String, Object>{
            'sobjectProcessField' => 'OpportunityStage',
            'metadata' => new Map<String, Object>{ 'fieldName' => 'StageName' }
        };
        System.assertEquals('StageName', HubRecordModalUtil.resolvePathFieldApi(config, 'Opportunity'));
        System.assertEquals(
            'Status',
            HubRecordModalUtil.resolvePathFieldApi(
                new Map<String, Object>{ 'sobjectProcessField' => 'LeadStatus' },
                'Lead'
            )
        );
        System.assertEquals('StageName', HubRecordModalUtil.defaultPathFieldForObject('Opportunity'));
        System.assertEquals(null, HubRecordModalUtil.defaultPathFieldForObject('Account'));
    }

    @IsTest
    static void testParsePathGuidanceByValue() {
        Map<String, Object> config = new Map<String, Object>{
            'metadata' => new Map<String, Object>{
                'pathAssistantSteps' => new List<Object>{
                    new Map<String, Object>{
                        'picklistValueName' => 'Prospecting',
                        'info' => 'Research the account.'
                    },
                    new Map<String, Object>{ 'picklistValueName' => 'Qualification', 'info' => '' }
                }
            }
        };
        Map<String, String> guidance = HubRecordModalUtil.parsePathGuidanceByValue(config);
        System.assertEquals('Research the account.', guidance.get('Prospecting'));
        System.assert(guidance.containsKey('Qualification'));
    }

    @IsTest
    static void testFilterPathStepValues() {
        List<String> ordered = new List<String>{ 'A', 'B', 'C', 'D' };
        Set<String> configured = new Set<String>{ 'B', 'D' };
        List<String> filtered = HubRecordModalUtil.filterPathStepValues(ordered, configured, null);
        System.assertEquals(2, filtered.size());
        System.assertEquals('B', filtered[0]);
        System.assertEquals('D', filtered[1]);
    }

    @IsTest
    static void testFetchRecordModalDataIncludesPathOverride() {
        Account acc = new Account(Name = 'Path Acc');
        insert acc;
        HubRecordModalUtil.testLayoutOverride = buildTestLayout();
        HubRecordModalUtil.testPathOverride = new Map<String, Object>{
            'fieldApiName' => 'Type',
            'fieldLabel' => 'Type',
            'currentValue' => 'Prospect',
            'pathLabel' => 'Account Path',
            'guidanceText' => 'Verify account details.',
            'steps' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'value' => 'Prospect',
                    'label' => 'Prospect',
                    'status' => 'current'
                }
            }
        };

        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData(acc.Id);
        HubRecordModalUtil.testLayoutOverride = null;
        HubRecordModalUtil.testPathOverride = null;

        System.assertEquals(null, res.get('error'), 'unexpected error: ' + res);
        Map<String, Object> path = (Map<String, Object>) res.get('path');
        System.assertNotEquals(null, path);
        System.assertEquals('Account Path', path.get('pathLabel'));
        System.assertEquals('Verify account details.', path.get('guidanceText'));
        List<Object> steps = (List<Object>) path.get('steps');
        System.assertEquals(1, steps.size());
    }

    @IsTest
    static void testResolvePathDataReturnsNullWithoutConfig() {
        Account acc = new Account(Name = 'No Path Acc');
        insert acc;
        Map<String, Object> path = HubRecordModalUtil.resolvePathData(
            'Account',
            HubRecordModalUtil.resolveRecordTypeId(
                acc.Id,
                'Account',
                Account.SObjectType.getDescribe()
            ),
            acc,
            null,
            null
        );
        System.assertEquals(null, path);
    }

    @IsTest
    static void testParsePathAssistantQueryResult() {
        Test.setMock(HttpCalloutMock.class, new HubModalPathAssistantMock());
        Map<String, Object> config = HubRecordModalUtil.queryPathAssistant(
            'Opportunity',
            Opportunity.SObjectType.getDescribe().getRecordTypeInfos()[0].getRecordTypeId()
        );
        System.assertNotEquals(null, config);
        System.assertEquals('Opportunity Stage', config.get('masterLabel'));
        System.assertEquals('OpportunityStage', config.get('sobjectProcessField'));
    }

    @IsTest
    static void testPicklistValuesFromDescribe() {
        List<String> values = HubRecordModalUtil.picklistValuesFromDescribe(Opportunity.StageName.getDescribe());
        System.assert(!values.isEmpty());
    }

    @IsTest
    static void testResolvePathDataWithOpportunityMock() {
        Account acc = new Account(Name = 'Path Opp Acc');
        insert acc;
        Opportunity opp = new Opportunity(
            Name = 'Path Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Type = 'Existing Business',
            Type_of_Service__c = 'Other'
        );
        insert opp;

        HubRecordModalUtil.testLayoutOverride = buildTestLayout();
        Test.setMock(HttpCalloutMock.class, new HubModalPathAndLayoutMock());

        Test.startTest();
        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData(opp.Id);
        Test.stopTest();

        HubRecordModalUtil.testLayoutOverride = null;

        System.assertEquals(null, res.get('error'), 'Should load: ' + res.get('error'));
        Map<String, Object> path = (Map<String, Object>) res.get('path');
        System.assertNotEquals(null, path, 'Should include path for Opportunity');
        System.assertEquals('StageName', path.get('fieldApiName'));
        System.assertEquals('Prospecting', path.get('currentValue'));
        List<Object> steps = (List<Object>) path.get('steps');
        System.assert(steps != null && !steps.isEmpty());
    }

    @IsTest
    static void testResolveOrderedPicklistValuesAndBusinessProcess() {
        Id rtId = Opportunity.SObjectType.getDescribe().getRecordTypeInfos()[0].getRecordTypeId();
        Test.setMock(HttpCalloutMock.class, new HubModalPathAssistantMock());
        List<String> values = HubRecordModalUtil.resolveOrderedPicklistValues('Opportunity', rtId, 'StageName');
        System.assert(!values.isEmpty());
    }

    @IsTest
    static void testQueryPathAssistantMasterFallback() {
        Id rtId = Lead.SObjectType.getDescribe().getRecordTypeInfos()[0].getRecordTypeId();
        Test.setMock(HttpCalloutMock.class, new HubModalPathMasterMock());
        Map<String, Object> config = HubRecordModalUtil.fetchPathAssistantConfig('Lead', rtId);
        System.assertNotEquals(null, config);
        System.assertEquals('Lead Status', config.get('masterLabel'));
    }

    @IsTest
    static void testResolvePathFieldApiCustomFieldOnObject() {
        Map<String, Object> config = new Map<String, Object>{
            'sobjectProcessField' => 'Type_of_Service__c',
            'metadata' => new Map<String, Object>()
        };
        System.assertEquals('Type_of_Service__c', HubRecordModalUtil.resolvePathFieldApi(config, 'Opportunity'));
        System.assert(HubRecordModalUtil.fieldExistsOnObject('Opportunity', 'StageName'));
        System.assertEquals(false, HubRecordModalUtil.fieldExistsOnObject('Opportunity', 'NotAField__c'));
    }

    @IsTest
    static void testPicklistLabelMap() {
        Map<String, String> labels = HubRecordModalUtil.picklistLabelMap(Opportunity.StageName.getDescribe());
        System.assert(labels.containsKey('Prospecting'));
    }

    private class HubModalPathAndLayoutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String endpoint = req.getEndpoint();
            if (endpoint.contains('/describe/layouts/')) {
                res.setBody(
                    '{"detailLayoutSections":[{"heading":"Info","layoutRows":[{"layoutItems":[{"placeholder":false,"layoutComponents":[{"type":"Field","value":"Name","details":{"type":"string","name":"Name"}}]}]}]}]}'
                );
            } else if (endpoint.contains('PathAssistant')) {
                res.setBody(
                    '{"records":[{"MasterLabel":"Opportunity Stage","SobjectProcessField":"OpportunityStage","Metadata":{"fieldName":"StageName","pathAssistantSteps":[{"picklistValueName":"Prospecting","info":"Research the account."},{"picklistValueName":"Qualification","info":"Qualify budget."}]}}]}'
                );
            } else if (endpoint.contains('BusinessProcess')) {
                res.setBody(
                    '{"records":[{"Metadata":{"values":[{"fullName":"Prospecting"},{"fullName":"Qualification"},{"fullName":"Closed Won"}]}}]}'
                );
            } else {
                res.setBody('{"records":[]}');
            }
            return res;
        }
    }

    private class HubModalPathMasterMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getEndpoint().contains('IsMasterRecordType')) {
                res.setBody(
                    '{"records":[{"MasterLabel":"Lead Status","SobjectProcessField":"LeadStatus","Metadata":{"fieldName":"Status","pathAssistantSteps":[{"picklistValueName":"Open","info":"Work the lead."}]}}]}'
                );
            } else {
                res.setBody('{"records":[]}');
            }
            return res;
        }
    }

    private class HubModalPathAssistantMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String endpoint = req.getEndpoint();
            if (endpoint.contains('PathAssistant')) {
                res.setBody(
                    '{"records":[{"MasterLabel":"Opportunity Stage","SobjectProcessField":"OpportunityStage","Metadata":{"fieldName":"StageName","pathAssistantSteps":[{"picklistValueName":"Prospecting","info":"Research"}]}}]}'
                );
            } else if (endpoint.contains('BusinessProcess')) {
                res.setBody(
                    '{"records":[{"Metadata":{"values":[{"fullName":"Prospecting"},{"fullName":"Qualification"}]}}]}'
                );
            } else {
                res.setBody('{"records":[]}');
            }
            return res;
        }
    }

    @IsTest
    static void testDecodeHtmlEntities() {
        System.assertEquals(
            'EDUCATION & OTHER INFORMATION',
            HubRecordModalUtil.decodeHtmlEntities('EDUCATION &AMP; OTHER INFORMATION')
        );
        System.assertEquals(
            'Contracts & Order Management',
            HubRecordModalUtil.decodeHtmlEntities('Contracts &amp; Order Management')
        );
        System.assertEquals(
            'A & B',
            HubRecordModalUtil.decodeHtmlEntities('A &amp;amp; B')
        );
    }

    @IsTest
    static void testNormalizeLayoutLabels() {
        Map<String, Object> layout = new Map<String, Object>{
            'detailLayoutSections' => new List<Object>{
                new Map<String, Object>{
                    'heading' => 'EDUCATION &AMP; OTHER INFORMATION',
                    'useHeading' => true,
                    'layoutRows' => new List<Object>{
                        new Map<String, Object>{
                            'layoutItems' => new List<Object>{
                                new Map<String, Object>{
                                    'label' => 'Field &amp; Label',
                                    'placeholder' => false
                                }
                            }
                        }
                    }
                }
            },
            'relatedLists' => new List<Object>{
                new Map<String, Object>{ 'label' => 'Contacts &amp; Partners', 'name' => 'Contacts' }
            }
        };
        Map<String, Object> normalized = HubRecordModalUtil.normalizeLayoutLabels(layout);
        List<Object> sections = (List<Object>) normalized.get('detailLayoutSections');
        Map<String, Object> section = (Map<String, Object>) sections[0];
        System.assertEquals('EDUCATION & OTHER INFORMATION', section.get('heading'));
        List<Object> related = (List<Object>) normalized.get('relatedLists');
        System.assertEquals('Contacts & Partners', ((Map<String, Object>) related[0]).get('label'));
    }

    @IsTest
    static void testFormatAddressCompound() {
        Account acc = new Account(
            Name = 'Address Acc',
            BillingStreet = '123 Main St',
            BillingCity = 'Cairo',
            BillingState = 'Cairo',
            BillingPostalCode = '11511',
            BillingCountry = 'Egypt'
        );
        insert acc;
        acc = [
            SELECT BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
            FROM Account
            WHERE Id = :acc.Id
        ];
        Schema.DescribeFieldResult billingDesc = Account.BillingAddress.getDescribe();
        String formatted = HubRecordModalUtil.formatAddressCompound(acc, billingDesc);
        System.assert(formatted.contains('123 Main St'));
        System.assert(formatted.contains('Cairo'));
        System.assert(formatted.contains('Egypt'));
    }

    @IsTest
    static void testFilterQueryableFieldsCompoundAddress() {
        List<String> fields = HubRecordModalUtil.filterQueryableFields(
            'Account',
            new Set<String>{ 'BillingAddress', 'Name' }
        );
        System.assert(fields.contains('Name'));
        System.assert(fields.contains('BillingStreet'));
        System.assert(fields.contains('BillingCity'));
        System.assert(!fields.contains('BillingAddress'));
    }

    @IsTest
    static void testMapModalFieldTypesAddressAndLocation() {
        System.assertEquals('address', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.ADDRESS));
        System.assertEquals('location', HubRecordModalUtil.mapModalFieldType(Schema.DisplayType.LOCATION));
    }

    @IsTest
    static void testResolveTabLabelSalesNavigator() {
        System.assertEquals('Sales Navigator', HubRecordModalUtil.resolveTabLabel('Standard.Tab.salesNavigator'));
    }

    @IsTest
    static void testFetchRecordModalDataWithEncodedLayoutHeading() {
        Account acc = new Account(
            Name = 'Encoded Layout Acc',
            BillingStreet = '1 Test Way',
            BillingCity = 'Alexandria',
            BillingCountry = 'Egypt'
        );
        insert acc;
        Map<String, Object> layout = buildTestLayout();
        List<Object> sections = (List<Object>) layout.get('detailLayoutSections');
        Map<String, Object> section = (Map<String, Object>) sections[0];
        section.put('heading', 'Account &amp; Details');
        List<Object> rows = (List<Object>) section.get('layoutRows');
        Map<String, Object> row = (Map<String, Object>) rows[0];
        List<Object> items = (List<Object>) row.get('layoutItems');
        items.add(
            new Map<String, Object>{
                'label' => 'Billing Address',
                'placeholder' => false,
                'layoutComponents' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'Field',
                        'value' => 'BillingAddress',
                        'details' => new Map<String, Object>{ 'type' => 'address', 'name' => 'BillingAddress' }
                    }
                }
            }
        );
        HubRecordModalUtil.testLayoutOverride = layout;

        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalData(acc.Id);
        HubRecordModalUtil.testLayoutOverride = null;

        System.assertEquals(null, res.get('error'), 'unexpected error: ' + res);
        Map<String, Object> returnedLayout = (Map<String, Object>) res.get('layout');
        List<Object> returnedSections = (List<Object>) returnedLayout.get('detailLayoutSections');
        Map<String, Object> returnedSection = (Map<String, Object>) returnedSections[0];
        System.assertEquals('Account & Details', returnedSection.get('heading'));
        Map<String, Object> values = (Map<String, Object>) res.get('values');
        System.assertNotEquals(null, values.get('BillingAddress'));
        System.assert(String.valueOf(values.get('BillingAddress')).contains('Alexandria'));
    }

    @IsTest
    static void testFetchRecordModalShell() {
        Account acc = new Account(Name = 'Shell Acc');
        insert acc;

        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalShell(acc.Id);

        System.assertEquals(null, res.get('error'), 'unexpected error: ' + res);
        System.assertEquals('Account', res.get('objectApi'));
        System.assertEquals('Shell Acc', res.get('recordName'));
        System.assertNotEquals(null, res.get('recordTypeId'));
        System.assertEquals(false, res.containsKey('layout'));
    }

    @IsTest
    static void testFetchRecordModalDetailsOnly() {
        Account acc = new Account(Name = 'Details Only Acc', Type = 'Customer');
        insert acc;
        HubRecordModalUtil.testLayoutOverride = buildTestLayout();

        Test.startTest();
        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalDetails(acc.Id);
        Test.stopTest();

        HubRecordModalUtil.testLayoutOverride = null;

        System.assertEquals(null, res.get('error'), 'unexpected error: ' + res);
        System.assertNotEquals(null, res.get('layout'));
        System.assertNotEquals(null, res.get('values'));
        System.assertNotEquals(null, res.get('fieldMeta'));
        System.assertEquals(false, res.containsKey('tabs'));
        System.assertEquals(false, res.containsKey('relatedListData'));
        System.assertEquals(false, res.containsKey('path'));
    }

    @IsTest
    static void testFetchRecordModalTabsOnly() {
        Account acc = new Account(Name = 'Tabs Only Acc');
        insert acc;
        HubRecordModalUtil.testLayoutOverride = buildTestLayout();
        HubRecordModalUtil.testTabsOverride = new List<Map<String, Object>>{
            new Map<String, Object>{
                'id' => 'details',
                'label' => 'Details',
                'type' => 'details',
                'active' => true
            },
            new Map<String, Object>{
                'id' => 'rl_0',
                'label' => 'Contacts',
                'type' => 'related',
                'relatedListName' => 'Contacts',
                'relatedListLabel' => 'Contacts'
            }
        };

        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalTabs(acc.Id);

        HubRecordModalUtil.testLayoutOverride = null;
        HubRecordModalUtil.testTabsOverride = null;

        System.assertEquals(null, res.get('error'), 'unexpected error: ' + res);
        List<Object> tabs = (List<Object>) res.get('tabs');
        // Account tabs include Potential Duplicates when supported.
        System.assert(tabs.size() >= 2, 'Expected at least details + related; got ' + tabs.size());
        System.assertEquals(false, res.containsKey('values'));
    }

    @IsTest
    static void testFetchRecordModalPathOnly() {
        Account acc = new Account(Name = 'Path Only Acc');
        insert acc;

        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalPath(acc.Id);

        System.assertEquals(null, res.get('error'), 'unexpected error: ' + res);
        System.assertEquals(false, res.containsKey('layout'));
    }

    @IsTest
    static void testParseRelatedListColumnsFromObjects() {
        List<Map<String, Object>> cols = HubRecordModalUtil.parseRelatedListColumns(
            new Map<String, Object>{
                'columns' => new List<Object>{
                    new Map<String, Object>{
                        'fieldApiName' => 'Name',
                        'label' => 'Opportunity Name',
                        'name' => 'Name',
                        'sortable' => true
                    },
                    new Map<String, Object>{
                        'fieldApiName' => 'StageName',
                        'label' => 'Stage',
                        'name' => 'StageName'
                    }
                }
            }
        );
        System.assertEquals(2, cols.size());
        System.assertEquals('Name', cols[0].get('fieldApiName'));
        System.assertEquals('Opportunity Name', cols[0].get('label'));
        System.assertEquals('StageName', cols[1].get('fieldApiName'));
    }

    @IsTest
    static void testBuildRelatedBlocksFromLayout() {
        Map<String, Object> layout = buildTestLayout();
        List<Map<String, Object>> blocks = HubRecordModalUtil.buildRelatedBlocksFromLayout(layout);
        System.assertEquals(1, blocks.size());
        System.assertEquals('Contacts', blocks[0].get('relatedListName'));
    }

    @IsTest
    static void testFetchRecordModalRelatedListOnly() {
        Account acc = new Account(Name = 'Related Only Acc');
        insert acc;
        Task t = new Task(Subject = 'Related Child', WhatId = acc.Id, Status = 'Not Started', Priority = 'Normal');
        insert t;
        HubRecordModalUtil.testLayoutOverride = buildTestLayout();

        Map<String, Object> res = HubRecordModalUtil.fetchRecordModalRelatedList(acc.Id, 'Tasks', 'rl_0', 5);

        HubRecordModalUtil.testLayoutOverride = null;

        System.assertEquals(null, res.get('error'), 'unexpected error: ' + res);
        System.assert(res.containsKey('relatedList'));
        Map<String, Object> block = (Map<String, Object>) res.get('relatedList');
        System.assertEquals('rl_0', block.get('tabId'));
        System.assertEquals(1, ((List<Object>) block.get('rows')).size());
    }

    @IsTest
    static void testControllerProgressiveRemoteActions() {
        Account acc = new Account(Name = 'Progressive Remote Acc');
        insert acc;
        HubRecordModalUtil.testLayoutOverride = buildTestLayout();

        System.assertEquals('Progressive Remote Acc', CrmHubListController.fetchRecordModalShell(acc.Id).get('recordName'));
        System.assertEquals(null, CrmHubListController.fetchRecordModalDetails(acc.Id).get('error'));
        System.assertNotEquals(null, CrmHubListController.fetchRecordModalTabs(acc.Id).get('tabs'));

        HubRecordModalUtil.testLayoutOverride = null;
    }

    @IsTest
    static void testUpdateRecordFieldsHappyPath() {
        Account acc = new Account(Name = 'Edit Acc', Phone = '111');
        insert acc;

        Map<String, Object> res = HubRecordModalUtil.updateRecordFields(
            acc.Id,
            new Map<String, Object>{ 'Phone' => '555-0100' }
        );

        System.assertEquals(true, res.get('success'), 'unexpected: ' + res);
        Account refreshed = [SELECT Phone FROM Account WHERE Id = :acc.Id];
        System.assertEquals('555-0100', refreshed.Phone);
        Map<String, Object> values = (Map<String, Object>) res.get('values');
        System.assertEquals('555-0100', values.get('Phone'));
    }

    @IsTest
    static void testUpdateRecordFieldsValidation() {
        System.assert(HubRecordModalUtil.updateRecordFields('', new Map<String, Object>{ 'Phone' => 'x' }).containsKey('error'));
        System.assert(
            HubRecordModalUtil.updateRecordFields('001000000000000', new Map<String, Object>()).containsKey('error')
        );

        Account acc = new Account(Name = 'Reject Acc');
        insert acc;

        Map<String, Object> badField = HubRecordModalUtil.updateRecordFields(
            acc.Id,
            new Map<String, Object>{ 'NotAField__c' => 'x' }
        );
        System.assert(badField.containsKey('error'));

        Map<String, Object> badId = HubRecordModalUtil.updateRecordFields(
            acc.Id,
            new Map<String, Object>{ 'Id' => '001xx' }
        );
        System.assert(badId.containsKey('error'));
    }

    @IsTest
    static void testUpdateRecordFieldsTypeCoercion() {
        Contact con = new Contact(LastName = 'Coerce', HasOptedOutOfEmail = false);
        insert con;

        Map<String, Object> res = HubRecordModalUtil.updateRecordFields(
            con.Id,
            new Map<String, Object>{
                'HasOptedOutOfEmail' => 'true',
                'Title' => 'Engineer'
            }
        );

        System.assertEquals(true, res.get('success'), 'unexpected: ' + res);
        Contact refreshed = [SELECT HasOptedOutOfEmail, Title FROM Contact WHERE Id = :con.Id];
        System.assertEquals(true, refreshed.HasOptedOutOfEmail);
        System.assertEquals('Engineer', refreshed.Title);
    }

    @IsTest
    static void testBuildFieldMetaIncludesEditFlags() {
        Map<String, Object> meta = HubRecordModalUtil.buildFieldMeta(
            'Account',
            new List<String>{ 'Name', 'Phone', 'Type', 'Description' }
        );
        System.assertEquals(true, ((Map<String, Object>) meta.get('Phone')).get('updateable'));
        System.assertEquals(false, ((Map<String, Object>) meta.get('Phone')).get('readOnly'));
        System.assert(((Map<String, Object>) meta.get('Type')).containsKey('picklistValues'));
    }

    @IsTest
    static void testGetAllObjectFieldApisAndAugmentLayout() {
        Set<String> allApis = HubRecordModalUtil.getAllObjectFieldApis('Account');
        System.assert(allApis.contains('Name'));
        System.assert(allApis.contains('Phone'));

        Map<String, Object> layout = buildTestLayout();
        Set<String> layoutApis = HubRecordModalUtil.extractLayoutFieldApis(layout, 'Account');
        Map<String, Object> augmented = HubRecordModalUtil.augmentLayoutWithAllFields(
            layout,
            layoutApis,
            allApis,
            'Account'
        );
        List<Object> sections = (List<Object>) augmented.get('detailLayoutSections');
        System.assert(sections.size() >= 2, 'Should append All Fields section');
        Boolean foundAllFields = false;
        for (Object secObj : sections) {
            Map<String, Object> sec = (Map<String, Object>) secObj;
            if ('All Fields'.equals(sec.get('heading'))) {
                foundAllFields = true;
            }
        }
        System.assertEquals(true, foundAllFields);
    }

    @IsTest
    static void testControllerUpdateRecordFieldsRemoteAction() {
        Account acc = new Account(Name = 'Remote Edit Acc', Phone = '999');
        insert acc;

        Map<String, Object> res = CrmHubListController.updateRecordFields(
            acc.Id,
            new Map<String, Object>{ 'Phone' => '555-0300' }
        );

        System.assertEquals(true, res.get('success'), 'unexpected: ' + res);
        System.assertEquals('555-0300', [SELECT Phone FROM Account WHERE Id = :acc.Id].Phone);
    }

    private static Map<String, Object> buildTestLayout() {
        return new Map<String, Object>{
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
                                },
                                new Map<String, Object>{
                                    'label' => 'Type',
                                    'placeholder' => false,
                                    'layoutComponents' => new List<Object>{
                                        new Map<String, Object>{
                                            'type' => 'Field',
                                            'value' => 'Type',
                                            'details' => new Map<String, Object>{ 'type' => 'picklist', 'name' => 'Type' }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            },
            'relatedLists' => new List<Object>{
                new Map<String, Object>{
                    'label' => 'Contacts',
                    'name' => 'Contacts',
                    'relatedList' => 'RelatedContactList',
                    'columns' => new List<Object>{ 'CONTACT.FULL_NAME' }
                }
            }
        };
    }

    @IsTest
    static void testEnsureSalesforcePowerTabForOpportunity() {
        List<Map<String, Object>> base = new List<Map<String, Object>>{
            new Map<String, Object>{
                'id' => 'details',
                'label' => 'Details',
                'type' => 'details',
                'active' => true
            },
            new Map<String, Object>{
                'id' => 'activity',
                'label' => 'Activity',
                'type' => 'activity'
            }
        };
        List<Map<String, Object>> tabs = HubRecordModalUtil.ensureSalesforcePowerTab('Opportunity', base);
        System.assertEquals(3, tabs.size());
        System.assertEquals('salesforce_power', tabs[1].get('id'));
        System.assertEquals('salesforcePower', tabs[1].get('type'));
    }

    @IsTest
    static void testEnsureOpportunityHubTabsAddsCommunicationsContactsAndInsights() {
        List<Map<String, Object>> base = new List<Map<String, Object>>{
            new Map<String, Object>{
                'id' => 'details',
                'label' => 'Details',
                'type' => 'details',
                'active' => true
            }
        };
        Map<String, Object> layout = new Map<String, Object>{
            'relatedLists' => new List<Object>{
                new Map<String, Object>{
                    'label' => 'Contact Roles',
                    'name' => 'OpportunityContactRoles',
                    'relatedList' => 'RelatedContactRoleList',
                    'columns' => new List<Object>{ 'ContactName', 'Role' }
                }
            }
        };
        List<Map<String, Object>> tabs = HubRecordModalUtil.ensureOpportunityHubTabs(
            'Opportunity',
            base,
            layout
        );
        Boolean hasActivity = false;
        Boolean hasContacts = false;
        Boolean hasInsights = false;
        Boolean hasPower = false;
        for (Map<String, Object> tab : tabs) {
            if ('activity'.equals(tab.get('type'))) {
                hasActivity = true;
            }
            if ('relatedMulti'.equals(tab.get('type')) || 'related'.equals(tab.get('type'))) {
                String label = tab.get('label') == null ? '' : String.valueOf(tab.get('label')).toLowerCase();
                if (label.contains('contact') || tab.get('relatedBlocks') != null) {
                    hasContacts = true;
                }
            }
            if ('intentInsights'.equals(tab.get('type'))) {
                hasInsights = true;
            }
            if ('salesforcePower'.equals(tab.get('type'))) {
                hasPower = true;
            }
        }
        System.assertEquals(true, hasActivity, 'Communications/activity tab required: ' + tabs);
        System.assertEquals(true, hasContacts, 'Contacts related tab required: ' + tabs);
        System.assertEquals(true, hasInsights, 'Intent Insights tab required: ' + tabs);
        System.assertEquals(true, hasPower, 'Salesforce Power tab required: ' + tabs);
    }

    @IsTest
    static void testRecordModalActivitiesLifecycle() {
        Account acc = new Account(Name = 'Hub Act Acc');
        insert acc;
        Opportunity opp = new Opportunity(
            Name = 'Hub Act Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id,
            Type_of_Service__c = 'Other'
        );
        insert opp;

        Test.startTest();
        Map<String, Object> empty = HubRecordModalUtil.fetchRecordModalActivities(opp.Id);
        System.assertEquals(true, empty.containsKey('activities'));
        System.assertEquals(0, ((List<Object>) empty.get('activities')).size());

        Map<String, Object> created = HubRecordModalUtil.createRecordModalActivity(
            opp.Id,
            'Task',
            new Map<String, Object>{
                'Subject' => 'Follow up',
                'Description' => 'Call next week',
                'ActivityDate' => String.valueOf(Date.today().addDays(2)),
                'Priority' => 'High'
            }
        );
        System.assertEquals(true, created.get('success'), 'create: ' + created);
        List<Object> acts = (List<Object>) created.get('activities');
        System.assertEquals(1, acts.size());
        Map<String, Object> first = (Map<String, Object>) acts[0];
        System.assertEquals(true, first.get('isOpen'));
        String taskId = String.valueOf(first.get('id'));

        Map<String, Object> completed = HubRecordModalUtil.completeRecordModalActivity(opp.Id, taskId);
        System.assertEquals(true, completed.get('success'), 'complete: ' + completed);
        Map<String, Object> done = (Map<String, Object>) ((List<Object>) completed.get('activities'))[0];
        System.assertEquals(false, done.get('isOpen'));
        Test.stopTest();
    }

    @IsTest
    static void testFetchParentAccountContacts() {
        Account acc = new Account(Name = 'Hub Parent Acc');
        insert acc;
        Contact c1 = new Contact(LastName = 'ParentOne', AccountId = acc.Id, Title = 'Manager');
        Contact c2 = new Contact(LastName = 'ParentTwo', AccountId = acc.Id);
        insert new List<Contact>{ c1, c2 };
        Opportunity opp = new Opportunity(
            Name = 'Hub Parent Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10),
            AccountId = acc.Id,
            Type_of_Service__c = 'Other'
        );
        insert opp;

        Test.startTest();
        Map<String, Object> block = HubRecordModalUtil.fetchParentAccountContacts(
            opp.Id,
            new Map<String, Object>{
                'label' => 'Contacts for Parent Account',
                'name' => 'ParentAccountContacts',
                'columns' => new List<Object>{ 'CONTACT.FULL_NAME', 'CONTACT.TITLE' }
            },
            5
        );
        Test.stopTest();
        System.assertEquals(2, block.get('totalSize'));
        System.assertEquals(2, ((List<Object>) block.get('rows')).size());
    }

    @IsTest
    static void testCreateJobApplicationFromLead() {
        Test.setMock(HttpCalloutMock.class, new HubModalOkHttpMock());
        Position__c pos = new Position__c(
            Name = 'Hub JA Pos',
            Years_Of_Experience__c = 2,
            Min_Pay__c = 5000,
            Max_Pay__c = 8000,
            Status__c = 'New Position'
        );
        insert pos;
        Lead ld = new Lead(
            LastName = 'HubJALead',
            Company = 'Hub JA Co',
            Status = 'Open - Not Contacted',
            Position__c = pos.Id
        );

        Test.startTest();
        insert ld;
        Map<String, Object> form = HubRecordModalUtil.getCreateJobApplicationForm(ld.Id);
        System.assertEquals(true, form.get('success'), 'form: ' + form);
        System.assertEquals('Lead', form.get('parentObjectApi'));
        System.assertEquals(String.valueOf(pos.Id), form.get('positionId'));
        System.assertEquals('Got any feedback?', form.get('nextStep'));
        System.assertEquals('New', form.get('status'));

        Map<String, Object> res = HubRecordModalUtil.createJobApplicationFromForm(
            ld.Id,
            new Map<String, Object>{
                'NextStep__c' => 'Edited feedback',
                'Status__c' => 'New',
                'Position__c' => pos.Id
            }
        );
        System.assertEquals(true, res.get('success'), 'unexpected: ' + res);
        System.assertNotEquals(null, res.get('jobApplicationId'));
        Map<String, Object> legacy = HubRecordModalUtil.createJobApplicationFromParent(ld.Id);
        System.assertEquals(true, legacy.get('success'), 'legacy: ' + legacy);
        Test.stopTest();

        Job_Application__c ja = [
            SELECT Lead__c, Position__c, Status__c, NextStep__c
            FROM Job_Application__c
            WHERE Id = :(Id) res.get('jobApplicationId')
        ];
        System.assertEquals(ld.Id, ja.Lead__c);
        System.assertEquals(pos.Id, ja.Position__c);
        System.assertEquals('New', ja.Status__c);
        System.assertEquals('Edited feedback', ja.NextStep__c);
    }

    @IsTest
    static void testCreateJobApplicationFromContactAndValidation() {
        Test.setMock(HttpCalloutMock.class, new HubModalOkHttpMock());
        Contact con = new Contact(LastName = 'HubJAContact');
        insert con;

        Test.startTest();
        Map<String, Object> form = HubRecordModalUtil.getCreateJobApplicationForm(con.Id);
        System.assertEquals(true, form.get('success'), 'contact form: ' + form);
        System.assertEquals(null, form.get('positionId'));
        System.assertEquals('Got a response?', form.get('nextStep'));
        Map<String, Object> res = HubRecordModalUtil.createJobApplicationFromParent(con.Id);
        Map<String, Object> lookup = HubRecordModalUtil.searchLookupRecords(
            'Account',
            'NoMatchZZZ',
            5
        );
        Test.stopTest();

        System.assertEquals(true, res.get('success'), 'unexpected: ' + res);
        Job_Application__c ja = [
            SELECT Contact__c, NextStep__c, Status__c, Position__c
            FROM Job_Application__c
            WHERE Id = :(Id) res.get('jobApplicationId')
        ];
        System.assertEquals(con.Id, ja.Contact__c);
        System.assertEquals('Got a response?', ja.NextStep__c);
        System.assertEquals('New', ja.Status__c);
        System.assertEquals(null, ja.Position__c);

        System.assert(
            HubRecordModalUtil.createJobApplicationFromParent('').containsKey('error')
        );
        Account acc = new Account(Name = 'No JA Acc');
        insert acc;
        System.assert(
            HubRecordModalUtil.createJobApplicationFromParent(acc.Id).containsKey('error')
        );
        System.assertEquals(true, lookup.get('success'), 'lookup: ' + lookup);
        System.assertEquals(
            true,
            HubRecordModalUtil.getCreateJobApplicationForm(con.Id).get('success')
        );
        System.assert(
            HubRecordModalUtil.searchLookupRecords('Position__c', 'Hub', 10).containsKey(
                'records'
            ) ||
            HubRecordModalUtil.searchLookupRecords('Position__c', 'Hub', 10).containsKey(
                'error'
            )
        );
    }

    @IsTest
    static void testOwnerIdIsEditableAndUserLookupAllowed() {
        Schema.DescribeFieldResult ownerFd = Opportunity.OwnerId.getDescribe();
        System.assertEquals(
            true,
            HubRecordModalUtil.isFieldEditable(ownerFd),
            'OwnerId should be editable in CRM Hub modal'
        );
        Schema.DescribeFieldResult accountFd = Opportunity.AccountId.getDescribe();
        System.assertEquals(
            true,
            HubRecordModalUtil.isFieldEditable(accountFd),
            'Updateable reference fields should be editable'
        );
        Schema.DescribeFieldResult createdByFd = Opportunity.CreatedById.getDescribe();
        System.assertEquals(
            false,
            HubRecordModalUtil.isFieldEditable(createdByFd),
            'Non-updateable reference fields stay read-only'
        );

        if (Schema.sObjectType.Opportunity.fields.getMap().containsKey('Primary_AE__c')) {
            System.assertEquals(
                true,
                HubRecordModalUtil.isFieldEditable(
                    Schema.sObjectType.Opportunity.fields.getMap().get('Primary_AE__c').getDescribe()
                ),
                'Primary AE lookup should be editable'
            );
        }
        if (Schema.sObjectType.Opportunity.fields.getMap().containsKey('Primary_Contact__c')) {
            System.assertEquals(
                true,
                HubRecordModalUtil.isFieldEditable(
                    Schema.sObjectType.Opportunity.fields
                        .getMap()
                        .get('Primary_Contact__c')
                        .getDescribe()
                ),
                'Primary Contact lookup should be editable'
            );
        }

        Map<String, Object> lookup = HubRecordModalUtil.searchLookupRecords('User', 'a', 5);
        System.assertEquals(null, lookup.get('error'), 'User lookup search should be allowed');
        System.assert(lookup.containsKey('records'));

        Map<String, Object> contactLookup = HubRecordModalUtil.searchLookupRecords('Contact', 'a', 5);
        System.assertEquals(null, contactLookup.get('error'), 'Contact lookup search should be allowed');
        System.assert(contactLookup.containsKey('records'));
    }

    @IsTest
    static void testVisualforceAndRssTabBuilders() {
        Map<String, Object> teamTab = HubRecordModalUtil.tryBuildVisualforceTab(
            'tab_team',
            'Team Builder',
            'flexipage:visualforcePage',
            null
        );
        System.assertNotEquals(null, teamTab);
        System.assertEquals('visualforce', teamTab.get('type'));
        System.assertEquals('OpportunityTeam', teamTab.get('pageName'));

        Map<String, Object> newsTab = HubRecordModalUtil.tryBuildRssFeedTab(
            'tab_news',
            'Agentforce News',
            'c:cloudastickRssFeedViewer',
            new Map<String, Object>{ 'rssUrlFieldName' => 'Google_Alert_URL__c' }
        );
        System.assertNotEquals(null, newsTab);
        System.assertEquals('rssFeed', newsTab.get('type'));
        System.assertEquals('Google_Alert_URL__c', newsTab.get('rssUrlFieldName'));
    }

    @IsTest
    static void testAgentforceConsultantMapsToSalesforcePower() {
        System.assertEquals(
            true,
            HubRecordModalUtil.isSalesforcePowerTab(
                new Map<String, Object>{ 'label' => 'Agentforce Consultant' }
            )
        );
    }

    @IsTest
    static void testUpdateOwnerIdAndDecodeRecordName() {
        Account acc = new Account(Name = 'Owner Change Acc');
        insert acc;
        Opportunity opp = new Opportunity(
            Name = 'CRM &amp; Commerce Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(20),
            AccountId = acc.Id,
            Type_of_Service__c = 'Other'
        );
        insert opp;

        Map<String, Object> shell = HubRecordModalUtil.fetchRecordModalShell(opp.Id);
        System.assertEquals(
            'CRM & Commerce Opp',
            shell.get('recordName'),
            'Record name should decode HTML entities'
        );

        User running = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        Map<String, Object> updated = HubRecordModalUtil.updateRecordFields(
            opp.Id,
            new Map<String, Object>{ 'OwnerId' => running.Id }
        );
        System.assertEquals(true, updated.get('success'), 'owner update: ' + updated);
        Map<String, Object> values = (Map<String, Object>) updated.get('values');
        System.assertEquals(String.valueOf(running.Id), String.valueOf(values.get('OwnerId')));
        System.assert(values.containsKey('Owner.Name'));

        System.assertEquals(
            'OpportunityTeam',
            HubRecordModalUtil.extractVisualforcePageName(
                new Map<String, Object>{ 'pageName' => 'OpportunityTeam' }
            )
        );
        System.assertEquals(
            null,
            HubRecordModalUtil.tryBuildVisualforceTab('x', 'Other', 'c:something', null)
        );
        System.assertEquals(
            null,
            HubRecordModalUtil.tryBuildRssFeedTab('x', 'Other', 'c:something', null)
        );
    }

    private class HubModalOkHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{}');
            return res;
        }
    }

}