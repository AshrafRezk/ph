/**
 * @description Test class for HubListViewUtil.
 */
@IsTest
private class HubListViewUtilTest {

    @IsTest
    static void testBuildAndSerializeListViewOptions() {
        Test.startTest();
        List<Map<String, String>> leads = HubListViewUtil.buildListViewOptions('Lead');
        String json = HubListViewUtil.serializeListViewOptions('Contact');
        Test.stopTest();

        System.assertNotEquals(null, leads);
        String firstId = HubListViewUtil.firstListViewId(json);
        if (!leads.isEmpty()) {
            System.assertNotEquals(null, leads[0].get('id'));
        }
        if (firstId != null) {
            System.assert(firstId.length() > 0);
        }
    }

    @IsTest
    static void testFirstListViewIdEmpty() {
        System.assertEquals(null, HubListViewUtil.firstListViewId('[]'));
    }

    @IsTest
    static void testFetchListViewResults() {
        Account acc = new Account(Name = 'HubUtilFetchAcc');
        insert acc;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }

        HubListViewUtil.testListViewDescribeOverride = buildAccountDescribeFixture();

        Test.startTest();
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 10, 0);
        Map<String, Object> meta = HubListViewUtil.describeListView('Account', lvs[0].Id);
        Test.stopTest();

        HubListViewUtil.testListViewDescribeOverride = null;

        System.assertEquals(null, page.get('error'), 'unexpected error: ' + String.valueOf(page.get('error')));
        System.assertNotEquals(null, page.get('records'));
        System.assertNotEquals(null, meta.get('label'));
        assertColumnsIncludeField((List<Object>) page.get('columns'), 'Name');
    }

    @IsTest
    static void testFetchListViewResultsWithClientDescribeJson() {
        Account acc = new Account(Name = 'HubUtilColumnAcc', Type = 'Customer');
        insert acc;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }

        String describeJson = JSON.serialize(buildAccountDescribeFixture());

        Test.startTest();
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 10, 0, describeJson);
        Test.stopTest();

        System.assertEquals(null, page.get('error'), 'unexpected error: ' + String.valueOf(page.get('error')));
        assertColumnsIncludeField((List<Object>) page.get('columns'), 'Name');
        assertColumnsIncludeField((List<Object>) page.get('columns'), 'Type');
        List<Object> records = (List<Object>) page.get('records');
        System.assert(!records.isEmpty(), 'Should return at least one record');
        Map<String, Object> row = (Map<String, Object>) records[0];
        System.assertNotEquals(null, row.get('id'), 'Row payload should include record id');
        System.assertEquals(acc.Id, row.get('id'));
    }

    private static Map<String, Object> buildAccountDescribeFixture() {
        return new Map<String, Object>{
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
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Id',
                    'label' => 'Account ID',
                    'type' => 'id',
                    'hidden' => true
                }
            }
        };
    }
    private static Map<String, Object> buildAccountDescribeExtendedFixture() {
        Map<String, Object> fixture = buildAccountDescribeFixture();
        List<Object> cols = (List<Object>) fixture.get('columns');
        cols.add(
            new Map<String, Object>{
                'fieldNameOrPath' => 'Phone',
                'label' => 'Phone',
                'type' => 'phone',
                'hidden' => false
            }
        );
        cols.add(
            new Map<String, Object>{
                'fieldNameOrPath' => 'Website',
                'label' => 'Website',
                'type' => 'url',
                'hidden' => false
            }
        );
        cols.add(
            new Map<String, Object>{
                'fieldNameOrPath' => 'AnnualRevenue',
                'label' => 'Revenue',
                'type' => 'currency',
                'hidden' => false
            }
        );
        cols.add(
            new Map<String, Object>{
                'fieldNameOrPath' => 'NumberOfEmployees',
                'label' => 'Employees',
                'type' => 'double',
                'hidden' => false
            }
        );
        return fixture;
    }


    private static void assertColumnsIncludeField(List<Object> cols, String fieldApi) {
        System.assertNotEquals(null, cols, 'columns should not be null');
        System.assert(cols.size() > 1, 'Should return more than Id-only columns');
        Boolean found = false;
        for (Object colObj : cols) {
            Map<String, Object> col = (Map<String, Object>) colObj;
            if (fieldApi.equals(col.get('fieldNameOrPath'))) {
                found = true;
                break;
            }
        }
        System.assert(found, 'Expected column ' + fieldApi);
    }

    @IsTest
    static void testRequeryWithFieldOrderSystemMode() {
        Account acc = new Account(Name = 'HubUtilRequeryAcc');
        insert acc;
        List<SObject> filtered = [SELECT Id FROM Account WHERE Id = :acc.Id];
        List<String> fieldOrder = new List<String>{ 'Name' };

        Test.startTest();
        List<SObject> recs = HubListViewUtil.requeryWithFieldOrder('Account', fieldOrder, filtered);
        Test.stopTest();

        System.assertEquals(1, recs.size());
        System.assertEquals('HubUtilRequeryAcc', recs[0].get('Name'));
    }

    @IsTest
    static void testConvertUiApiListInfo() {
        Map<String, Object> uiApi = new Map<String, Object>{
            'displayColumns' => new List<Object>{
                new Map<String, Object>{
                    'fieldApiName' => 'Name',
                    'label' => 'Account Name',
                    'dataType' => 'String'
                },
                new Map<String, Object>{
                    'fieldApiName' => 'Type',
                    'label' => 'Type',
                    'dataType' => 'Picklist'
                }
            },
            'query' => 'SELECT Name, Type FROM Account'
        };
        Map<String, Object> converted = HubListViewUtil.convertUiApiListInfo(uiApi);
        List<Object> cols = (List<Object>) converted.get('columns');
        System.assertEquals(2, cols.size());
        Map<String, Object> first = (Map<String, Object>) cols[0];
        System.assertEquals('Name', first.get('fieldNameOrPath'));
    }

    @IsTest
    static void testFilterQueryableFieldPaths() {
        List<String> filtered = HubListViewUtil.filterQueryableFieldPaths(
            'Account',
            new List<String>{ 'Name', 'Type', 'NotARealField__xyz', 'Owner.Alias' }
        );
        System.assert(filtered.contains('Name'));
        System.assert(filtered.contains('Type'));
        System.assert(!filtered.contains('NotARealField__xyz'));
        List<String> contactFields = HubListViewUtil.filterQueryableFieldPaths(
            'Contact',
            new List<String>{ 'Account.Name', 'Owner.Alias' }
        );
        System.assert(contactFields.contains('Account.Name'), 'Should resolve Account relationship name');
    }

    @IsTest
    static void testNormalizeNameFirstNameFromOwnerColumn() {
        // List-view describe returns OWNER.FIRST_NAME as Name.FirstName
        System.assertEquals(
            'Owner.FirstName',
            HubListViewUtil.normalizeListViewFieldPath('Position__c', 'Name.FirstName')
        );
        System.assertEquals(
            'Owner.LastName',
            HubListViewUtil.normalizeListViewFieldPath('Account', 'Name.LastName')
        );
        System.assertEquals(
            'FirstName',
            HubListViewUtil.normalizeListViewFieldPath('Contact', 'Name.FirstName')
        );
        List<String> positionFields = HubListViewUtil.filterQueryableFieldPaths(
            'Position__c',
            new List<String>{ 'Name', 'Name.FirstName', 'Hire_By__c' }
        );
        System.assert(positionFields.contains('Owner.FirstName'), 'Should query Owner.FirstName: ' + positionFields);
        System.assert(!positionFields.contains('Name.FirstName'));
    }

    @IsTest
    static void testFetchListViewResultsWithNameFirstNameColumn() {
        Position__c pos = new Position__c(
            Name = 'HubUtil Name.FirstName Pos',
            Years_Of_Experience__c = 1,
            Max_Pay__c = 10000,
            Min_Pay__c = 8000,
            Status__c = 'New Position'
        );
        insert pos;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Position__c' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        Map<String, Object> fixture = new Map<String, Object>{
            'query' =>
                'SELECT Id, Name, Owner.FirstName FROM Position__c WHERE Id = \'' +
                String.valueOf(pos.Id) +
                '\'',
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name',
                    'label' => 'Position Name',
                    'type' => 'string',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name.FirstName',
                    'label' => 'Owner First Name',
                    'type' => 'string',
                    'hidden' => false
                }
            }
        };
        Map<String, Object> page = HubListViewUtil.fetchListViewResults(
            'Position__c',
            lvs[0].Id,
            10,
            0,
            JSON.serialize(fixture)
        );
        System.assertEquals(
            null,
            page.get('error'),
            'Name.FirstName owner column should load: ' + page.get('error')
        );
        List<Object> records = (List<Object>) page.get('records');
        System.assertEquals(1, records.size());
        List<Object> columns = (List<Object>) page.get('columns');
        Boolean sawOwnerFirstName = false;
        for (Object colObj : columns) {
            Map<String, Object> col = (Map<String, Object>) colObj;
            if ('Owner.FirstName'.equals(col.get('fieldNameOrPath'))) {
                sawOwnerFirstName = true;
            }
        }
        System.assert(sawOwnerFirstName, 'Column path should normalize to Owner.FirstName');
    }

    @IsTest
    static void testParseDescribeColumns() {
        Map<String, Object> describe = new Map<String, Object>{
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name',
                    'label' => 'Account Name',
                    'type' => 'string',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Hidden__c',
                    'label' => 'Hidden',
                    'type' => 'string',
                    'hidden' => true
                }
            }
        };
        List<Map<String, Object>> cols = HubListViewUtil.parseDescribeColumns(describe);
        System.assertEquals(2, cols.size());
        Map<String, Object> firstCol = (Map<String, Object>) cols[0];
        System.assertEquals('Name', firstCol.get('fieldNameOrPath'));
    }

    @IsTest
    static void testUnsupportedObject() {
        Boolean threw = false;
        try {
            HubListViewUtil.buildListViewOptions('InvalidObject__x');
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        System.assert(threw, 'Should reject unsupported object');
    }
    @IsTest
    static void testPreferredListViewId() {
        String json =
            '[{"id":"001","label":"All Accounts","developerName":"AllAccounts"},{"id":"002","label":"My Accounts","developerName":"MyAccounts"}]';
        System.assertEquals('002', HubListViewUtil.preferredListViewId(json, 'MyAccounts'));
        System.assertEquals('001', HubListViewUtil.preferredListViewId(json, 'MissingDevName'));
    }

    @IsTest
    static void testFetchListViewResultsInvalid() {
        Map<String, Object> bad = HubListViewUtil.fetchListViewResults('NotSupported', '00B000000000000', 10, 0);
        System.assertNotEquals(null, bad.get('error'));
        Map<String, Object> blank = HubListViewUtil.fetchListViewResults('Account', '', 10, 0);
        System.assertNotEquals(null, blank.get('error'));
    }

    @IsTest
    static void testDescribeListViewInvalidAndFound() {
        Map<String, Object> bad = HubListViewUtil.describeListView('Account', '');
        System.assertNotEquals(null, bad.get('error'));
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'query' => 'SELECT Id, Name FROM Account',
            'columns' => buildAccountDescribeFixture().get('columns')
        };
        Map<String, Object> meta = HubListViewUtil.describeListView('Account', lvs[0].Id);
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertNotEquals(null, meta.get('label'));
        System.assert(meta.get('query') != null);
    }

    @IsTest
    static void testBuildListViewOptionsMultipleObjects() {
        Test.startTest();
        System.assertNotEquals(null, HubListViewUtil.buildListViewOptions('Opportunity'));
        System.assertNotEquals(null, HubListViewUtil.buildListViewOptions('Lead'));
        System.assertNotEquals(null, HubListViewUtil.buildListViewOptions('Contact'));
        Test.stopTest();
    }

    @IsTest
    static void testFetchListViewResultsRelationshipAndTypes() {
        Account acc = new Account(
            Name = 'HubUtil Rel Acc',
            Type = 'Customer',
            Phone = '555-0100',
            Website = 'https://example.com',
            AnnualRevenue = 1000,
            NumberOfEmployees = 5
        );
        insert acc;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        String describeJson = JSON.serialize(buildAccountDescribeExtendedFixture());
        Test.startTest();
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 1, 0, describeJson);
        Test.stopTest();
        System.assertEquals(null, page.get('error'), 'unexpected error: ' + String.valueOf(page.get('error')));
        List<Object> records = (List<Object>) page.get('records');
        System.assert(!records.isEmpty());
    }

    @IsTest
    static void testFetchListViewResultsHiddenColumnsOnly() {
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        Account acc = new Account(Name = 'Hidden Only Acc');
        insert acc;
        Map<String, Object> fixture = new Map<String, Object>{
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Id',
                    'label' => 'Id',
                    'type' => 'id',
                    'hidden' => true
                }
            },
            'query' =>
                'SELECT Id FROM Account WHERE Id = \'' +
                String.valueOf(acc.Id) +
                '\''
        };
        Map<String, Object> page = HubListViewUtil.fetchListViewResults(
            'Account',
            lvs[0].Id,
            10,
            0,
            JSON.serialize(fixture)
        );
        System.assertEquals(null, page.get('error'), 'hidden-only columns should load: ' + page.get('error'));
        List<Object> records = (List<Object>) page.get('records');
        System.assertEquals(1, records.size());
    }

    @IsTest
    static void testFetchListViewResultsIncludesHiddenColumns() {
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        Account acc = new Account(Name = 'Hidden Col Acc');
        insert acc;
        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name',
                    'label' => 'Account Name',
                    'type' => 'string',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Id',
                    'label' => 'Id',
                    'type' => 'id',
                    'hidden' => true
                }
            },
            'query' =>
                'SELECT Id, Name FROM Account WHERE Id = \'' +
                String.valueOf(acc.Id) +
                '\''
        };
        Map<String, Object> page = HubListViewUtil.fetchListViewResults(
            'Account',
            lvs[0].Id,
            10,
            0,
            JSON.serialize(HubListViewUtil.testListViewDescribeOverride)
        );
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertEquals(null, page.get('error'), 'hidden columns should load: ' + page.get('error'));
        List<Object> columns = (List<Object>) page.get('columns');
        System.assertEquals(2, columns.size());
    }

    @IsTest
    static void testRequeryEmptyFiltered() {
        List<SObject> empty = HubListViewUtil.requeryWithFieldOrder('Account', new List<String>{ 'Name' }, new List<SObject>());
        System.assertEquals(0, empty.size());
    }

    @IsTest
    static void testMalformedDescribeJsonFallsBackToOverride() {
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = buildAccountDescribeFixture();
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 10, 0, '{not-json');
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertEquals(null, page.get('error'), 'unexpected error: ' + String.valueOf(page.get('error')));
    }

    private class HubListViewRestDescribeMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"columns":[{"fieldNameOrPath":"Name","label":"Account Name","type":"string","hidden":false},{"fieldNameOrPath":"Type","label":"Type","type":"picklist","hidden":false}]}'
            );
            return res;
        }
    }

    private class HubListViewUiApiMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('/ui-api/list-info/')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody(
                    '{"query":"SELECT Id, Name FROM Account","displayColumns":[{"fieldApiName":"Name","label":"Account Name","dataType":"String"}]}'
                );
            } else {
                res.setStatusCode(404);
                res.setBody('');
            }
            return res;
        }
    }

    @IsTest
    static void testFetchListViewDescribeRestCallout() {
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        Test.setMock(HttpCalloutMock.class, new HubListViewRestDescribeMock());
        Test.startTest();
        Map<String, Object> body = HubListViewUtil.fetchListViewDescribeRest('Account', lvs[0].Id);
        Test.stopTest();
        System.assertNotEquals(null, body);
        System.assert(body.containsKey('columns'));
    }

    @IsTest
    static void testFetchListViewDescribeUiApiCallout() {
        List<ListView> lvs = [SELECT Id, DeveloperName FROM ListView WHERE SobjectType = 'Account' AND DeveloperName != null LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        Test.setMock(HttpCalloutMock.class, new HubListViewUiApiMock());
        Test.startTest();
        Map<String, Object> body = HubListViewUtil.fetchListViewDescribeUiApi('Account', lvs[0].Id);
        Test.stopTest();
        System.assertNotEquals(null, body);
        System.assert(body.containsKey('columns'));
    }

    @IsTest
    static void testFetchListViewResultsServerDescribeCallout() {
        Account acc = new Account(Name = 'HubUtil Callout Acc', Type = 'Customer');
        insert acc;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = null;
        Test.setMock(HttpCalloutMock.class, new HubListViewRestDescribeMock());
        Test.startTest();
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 10, 0, null);
        Test.stopTest();
        System.assertEquals(null, page.get('error'), 'unexpected error: ' + String.valueOf(page.get('error')));
        assertColumnsIncludeField((List<Object>) page.get('columns'), 'Name');
    }

    private class HubListViewHttpErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('error');
            return res;
        }
    }

    @IsTest
    static void testFetchListViewDescribeRestHttpError() {
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        Test.setMock(HttpCalloutMock.class, new HubListViewHttpErrorMock());
        System.assertEquals(null, HubListViewUtil.fetchListViewDescribeRest('Account', lvs[0].Id));
    }

    @IsTest
    static void testParseDescribeColumnsSkipsBlankField() {
        Map<String, Object> describe = new Map<String, Object>{
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => '',
                    'label' => 'X',
                    'type' => 'string',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name',
                    'label' => 'Name',
                    'type' => 'string',
                    'hidden' => false
                }
            }
        };
        List<Map<String, Object>> cols = HubListViewUtil.parseDescribeColumns(describe);
        System.assertEquals(1, cols.size());
    }

    @IsTest
    static void testFetchListViewResultsDefaultPaging() {
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = buildAccountDescribeFixture();
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, null, null);
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertEquals(null, page.get('error'), 'unexpected error: ' + String.valueOf(page.get('error')));
    }

    @IsTest
    static void testConvertUiApiListInfoSkipsBlankFieldApi() {
        Map<String, Object> uiApi = new Map<String, Object>{
            'displayColumns' => new List<Object>{
                new Map<String, Object>{
                    'fieldApiName' => '',
                    'label' => 'Blank',
                    'dataType' => 'String'
                },
                new Map<String, Object>{
                    'fieldApiName' => 'Name',
                    'label' => 'Name',
                    'dataType' => 'String'
                }
            }
        };
        Map<String, Object> converted = HubListViewUtil.convertUiApiListInfo(uiApi);
        System.assertEquals(1, ((List<Object>) converted.get('columns')).size());
    }

    @IsTest
    static void testDescribeListViewMissingListView() {
        Map<String, Object> meta = HubListViewUtil.describeListView('Account', '00B000000000000AAA');
        System.assertNotEquals(null, meta.get('error'));
    }

    @IsTest
    static void testFilterQueryableFieldPathsEmptyInput() {
        System.assertEquals(0, HubListViewUtil.filterQueryableFieldPaths('Account', null).size());
        System.assertEquals(0, HubListViewUtil.filterQueryableFieldPaths('Account', new List<String>()).size());
    }

    @IsTest
    static void testFetchListViewResultsSetsNextUrl() {
        Account a1 = new Account(Name = 'HubUtil Next A');
        Account a2 = new Account(Name = 'HubUtil Next B');
        insert new List<Account>{ a1, a2 };
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = buildAccountDescribeFixture();
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 1, 0);
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertNotEquals(null, page.get('nextRecordsUrl'));
    }

    @IsTest
    static void testFetchListViewResultsPageSizeCap() {
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = buildAccountDescribeFixture();
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 5000, 0, null);
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertEquals(null, page.get('error'), 'unexpected error: ' + String.valueOf(page.get('error')));
    }

    @IsTest
    static void testAppendLimitOffsetStripsExistingLimit() {
        String base = 'SELECT Id, Name FROM Account ORDER BY Name LIMIT 10 OFFSET 5';
        String paged = HubListViewUtil.appendLimitOffset(base, 25, 0);
        System.assert(paged.endsWith('LIMIT 25 OFFSET 0'), 'Expected new limit: ' + paged);
        System.assert(!paged.toLowerCase().contains('limit 10'), 'Should remove old limit: ' + paged);
    }

    @IsTest
    static void testRequeryContactAccountRelationshipField() {
        List<Contact> existing = [
            SELECT Id, Name, AccountId, Account.Name
            FROM Contact
            WHERE AccountId != NULL
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            return;
        }
        Contact con = existing[0];
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

        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Contact', lvs[0].Id, 10, 0, null);
        HubListViewUtil.testListViewDescribeOverride = null;

        System.assertEquals(null, page.get('error'), 'Unexpected error: ' + page.get('error'));
        List<Object> records = (List<Object>) page.get('records');
        System.assertEquals(1, records.size());
        Map<String, Object> row = (Map<String, Object>) records[0];
        System.assertNotEquals(null, row.get('id'), 'Each row should include record id for open actions');
        List<Object> cells = (List<Object>) row.get('columns');
        Boolean sawAccountName = false;
        for (Object cellObj : cells) {
            Map<String, Object> cell = (Map<String, Object>) cellObj;
            if (
                'Account.Name'.equals(cell.get('fieldNameOrPath')) &&
                cell.get('value') != null &&
                String.valueOf(cell.get('value')).length() > 0
            ) {
                sawAccountName = true;
                break;
            }
        }
        System.assert(sawAccountName, 'Account.Name should format without relationship SOQL error');
    }

    @IsTest
    static void testFetchListViewPageSystemModeInvalidQuery() {
        System.assertEquals(null, HubListViewUtil.fetchListViewPageSystemMode(null, 10, 0));
        System.assertEquals(
            null,
            HubListViewUtil.fetchListViewPageSystemMode(new Map<String, Object>{ 'query' => 'not soql' }, 10, 0)
        );
    }

    @IsTest
    static void testFetchListViewResultsUsesSystemModeDescribeQuery() {
        Account acc = new Account(Name = 'HubUtil System List Acc');
        insert acc;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'query' => 'SELECT Id, Name, Type FROM Account WHERE Name = \'HubUtil System List Acc\'',
            'columns' => buildAccountDescribeFixture().get('columns')
        };
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 10, 0, null);
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertEquals(null, page.get('error'), 'System-mode list view query should load rows');
        System.assert(!((List<Object>) page.get('records')).isEmpty());
    }

    @IsTest
    static void testFetchListViewPageSystemModeUsesDescribeQuery() {
        Account acc = new Account(Name = 'HubUtil System Mode Acc');
        insert acc;
        Map<String, Object> describe = new Map<String, Object>{
            'query' => 'SELECT Id, Name FROM Account WHERE Name = \'HubUtil System Mode Acc\''
        };

        List<SObject> rows = HubListViewUtil.fetchListViewPageSystemMode(describe, 10, 0);

        System.assertEquals(1, rows.size());
        System.assertEquals('HubUtil System Mode Acc', rows[0].get('Name'));
        System.assert(
            HubListViewUtil.appendLimitOffset(String.valueOf(describe.get('query')), null, null).contains('LIMIT 25')
        );
    }

    @IsTest
    static void testRequeryContactAccountReferenceColumn() {
        List<Contact> existing = [SELECT Id, Name, AccountId FROM Contact WHERE AccountId != NULL LIMIT 1];
        if (existing.isEmpty()) {
            return;
        }
        Contact con = existing[0];
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
                    'fieldNameOrPath' => 'Account',
                    'label' => 'Account',
                    'type' => 'reference',
                    'hidden' => false
                }
            }
        };
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Contact', lvs[0].Id, 10, 0, null);
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertEquals(null, page.get('error'), 'Unexpected error: ' + page.get('error'));
        List<Object> records = (List<Object>) page.get('records');
        System.assertEquals(1, records.size());
    }

    @IsTest
    static void testFetchListViewResultsThreeArgOverload() {
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = buildAccountDescribeFixture();
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 10, 0);
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertEquals(null, page.get('error'));
    }

    @IsTest
    static void testFetchListViewResultsStandardSetFallback() {
        Account acc = new Account(Name = 'HubUtil SSC Acc');
        insert acc;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'columns' => buildAccountDescribeFixture().get('columns')
        };
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 10, 0);
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertEquals(null, page.get('error'), 'SSC fallback: ' + page.get('error'));
        System.assert(!((List<Object>) page.get('records')).isEmpty());
    }

    @IsTest
    static void testFetchListViewResultsSetsNextRecordsUrl() {
        Account a1 = new Account(Name = 'HubUtil Page A');
        Account a2 = new Account(Name = 'HubUtil Page B');
        insert new List<Account>{ a1, a2 };
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'query' =>
                'SELECT Id, Name FROM Account WHERE Name IN (\'HubUtil Page A\', \'HubUtil Page B\') ORDER BY Name',
            'columns' => buildAccountDescribeFixture().get('columns')
        };
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 1, 0);
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertEquals(null, page.get('error'));
        System.assertNotEquals(null, page.get('nextRecordsUrl'));
    }

    @IsTest
    static void testFetchListViewResultsFormatsTypedColumns() {
        Account acc = new Account(
            Name = 'HubUtil Typed Acc',
            Type = 'Customer',
            Phone = '555-0100',
            Website = 'https://example.com',
            AnnualRevenue = 5000
        );
        insert acc;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'query' =>
                'SELECT Id, Name, Type, Phone, Website, AnnualRevenue, CreatedDate FROM Account WHERE Id = \'' +
                String.valueOf(acc.Id) +
                '\'',
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name',
                    'label' => 'Name',
                    'type' => 'string',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Type',
                    'label' => 'Type',
                    'type' => 'picklist',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Phone',
                    'label' => 'Phone',
                    'type' => 'phone',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Website',
                    'label' => 'Website',
                    'type' => 'url',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'AnnualRevenue',
                    'label' => 'Revenue',
                    'type' => 'currency',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'CreatedDate',
                    'label' => 'Created',
                    'type' => 'datetime',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Id',
                    'label' => 'Id',
                    'type' => 'id',
                    'hidden' => true
                }
            }
        };
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 10, 0);
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertEquals(null, page.get('error'), 'typed cols: ' + page.get('error'));
        List<Object> records = (List<Object>) page.get('records');
        System.assertEquals(1, records.size());
        Map<String, Object> row = (Map<String, Object>) records[0];
        System.assertEquals(String.valueOf(acc.Id), row.get('id'));
    }

    @IsTest
    static void testParseDescribeColumnsSkipsBlankPaths() {
        Map<String, Object> describe = new Map<String, Object>{
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => '',
                    'label' => 'Blank',
                    'type' => 'string',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name',
                    'label' => 'Name',
                    'type' => 'string',
                    'hidden' => false
                }
            }
        };
        List<Map<String, Object>> cols = HubListViewUtil.parseDescribeColumns(describe);
        System.assertEquals(1, cols.size());
    }

    @IsTest
    static void testFirstListViewIdPrefersAllPrefix() {
        String json =
            '[{"id":"001","label":"Mine","developerName":"Mine"},{"id":"002","label":"All Accounts","developerName":"AllAccounts"}]';
        System.assertEquals('002', HubListViewUtil.firstListViewId(json));
    }

    @IsTest
    static void testColumnMetadataMarksDescriptionHtmlCapable() {
        Account acc = new Account(Name = 'Desc Acc', Description = 'Notes');
        insert acc;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'query' =>
                'SELECT Id, Name, Description FROM Account WHERE Id = \'' +
                String.valueOf(acc.Id) +
                '\'',
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Name',
                    'label' => 'Name',
                    'type' => 'string',
                    'hidden' => false
                },
                new Map<String, Object>{
                    'fieldNameOrPath' => 'Description',
                    'label' => 'Description',
                    'type' => 'textarea',
                    'hidden' => false
                }
            }
        };
        Map<String, Object> page = HubListViewUtil.fetchListViewResults('Account', lvs[0].Id, 10, 0);
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertEquals(null, page.get('error'));
        List<Object> pageCols = (List<Object>) page.get('columns');
        System.assert(!pageCols.isEmpty(), 'Should return column metadata');
    }

    @IsTest
    static void testBuildColumnMetadataIncludesCalculatedFlag() {
        List<Map<String, Object>> cols = HubListViewUtil.buildColumnMetadata(
            'Account',
            new List<String>{ 'Name', 'CreatedDate' }
        );
        System.assertEquals(2, cols.size());
        for (Map<String, Object> col : cols) {
            System.assert(col.containsKey('calculated'), 'Each column should expose calculated flag');
        }
    }

    @IsTest
    static void testBuildColumnMetadataDescriptionField() {
        List<Map<String, Object>> cols = HubListViewUtil.buildColumnMetadata('Account', new List<String>{ 'Description' });
        System.assertEquals(1, cols.size());
        Map<String, Object> descCol = cols[0];
        System.assertEquals('Description', descCol.get('fieldNameOrPath'));
        if (descCol.get('type') == 'textarea') {
            System.assertEquals(true, descCol.get('htmlCapable'));
        }
    }

    @IsTest
    static void testBuildColumnMetadataIncludesPicklistOrder() {
        List<Map<String, Object>> cols = HubListViewUtil.buildColumnMetadata(
            'Job_Application__c',
            new List<String>{ 'Status__c' }
        );
        System.assertEquals(1, cols.size());
        Map<String, Object> statusCol = cols[0];
        System.assertEquals('picklist', statusCol.get('type'));
        System.assert(statusCol.containsKey('picklistValues'), 'Kanban needs ordered picklist values');
        List<Object> vals = (List<Object>) statusCol.get('picklistValues');
        System.assert(!vals.isEmpty(), 'Status__c should expose active picklist values');
        String first = String.valueOf(vals[0]);
        System.assert(
            first.contains('New'),
            'Status picklist should start with New (got: ' + first + ')'
        );
        System.assert(statusCol.containsKey('picklistLabels'));
    }

    @IsTest
    static void testMergePathOrderedPicklistValues() {
        List<String> merged = HubListViewUtil.mergePathOrderedPicklistValues(
            new List<String>{ 'Screening', 'New' },
            new List<String>{ 'New', 'Screening', 'Case Study', 'Offer Sent' }
        );
        System.assertEquals(4, merged.size());
        System.assertEquals('Screening', merged[0]);
        System.assertEquals('New', merged[1]);
        System.assertEquals('Case Study', merged[2]);
        System.assertEquals('Offer Sent', merged[3]);
    }

    @IsTest
    static void testOpportunityStageNameUsesSortOrder() {
        List<OpportunityStage> stages = [
            SELECT ApiName, MasterLabel, SortOrder
            FROM OpportunityStage
            WHERE IsActive = TRUE
            ORDER BY SortOrder ASC NULLS LAST, MasterLabel ASC
        ];
        System.assert(!stages.isEmpty(), 'Org needs active Opportunity stages');

        Map<String, String> labels = new Map<String, String>();
        List<String> direct = HubListViewUtil.opportunityStageOrderedValues(labels);
        System.assertEquals(stages.size(), direct.size(), 'Helper should return all active stages');
        for (Integer i = 0; i < stages.size(); i++) {
            String expected = String.isBlank(stages[i].ApiName)
                ? stages[i].MasterLabel
                : stages[i].ApiName;
            System.assertEquals(expected, direct[i], 'Stage ' + i + ' must follow SortOrder');
        }

        List<Map<String, Object>> cols = HubListViewUtil.buildColumnMetadata(
            'Opportunity',
            new List<String>{ 'StageName' }
        );
        System.assertEquals(1, cols.size());
        List<Object> vals = (List<Object>) cols[0].get('picklistValues');
        System.assert(!vals.isEmpty(), 'StageName needs picklist values for Kanban lanes');
        for (Integer i = 0; i < Math.min(stages.size(), vals.size()); i++) {
            String expected = String.isBlank(stages[i].ApiName)
                ? stages[i].MasterLabel
                : stages[i].ApiName;
            System.assertEquals(
                expected,
                String.valueOf(vals[i]),
                'Kanban StageName lanes must follow OpportunityStage.SortOrder'
            );
        }
        // Regression: closed stages belong after open ones (SortOrder), not A–Z first.
        Integer closedLostIdx = vals.indexOf('Closed Lost');
        Integer prospectingIdx = vals.indexOf('Prospecting');
        if (closedLostIdx >= 0 && prospectingIdx >= 0) {
            System.assert(
                prospectingIdx < closedLostIdx,
                'Prospecting should appear before Closed Lost (got indices ' +
                    prospectingIdx +
                    '/' +
                    closedLostIdx +
                    ')'
            );
        }
    }

    @IsTest
    static void testKanbanSoqlHelpers() {
        String base = 'SELECT Id, Name, Type FROM Account WHERE Name != null ORDER BY Name LIMIT 50';
        System.assert(HubListViewUtil.extractFromWhere(base).toLowerCase().startsWith('from account'));
        System.assert(HubListViewUtil.extractOrderBy(base).toLowerCase().startsWith('order by'));
        System.assertEquals(
            true,
            HubListViewUtil.isSimpleQueryableField('Account', 'Type')
        );
        System.assertEquals(
            false,
            HubListViewUtil.isSimpleQueryableField('Account', 'Owner.Name')
        );
        Map<String, Integer> counts = HubListViewUtil.queryKanbanLaneCounts(
            'SELECT Id, Type FROM Account WHERE Name = \'__no_such_kanban_account__\'',
            'Type'
        );
        System.assertEquals(0, counts.size());
    }

    @IsTest
    static void testApplyLanePredicateAvoidsWhereAnd() {
        System.assertEquals(
            'FROM Account WHERE Type = :kanbanLaneVal',
            HubListViewUtil.applyLanePredicate('FROM Account', 'Type', 'Customer')
        );
        System.assertEquals(
            'FROM Account WHERE Type = :kanbanLaneVal',
            HubListViewUtil.applyLanePredicate('FROM Account WHERE', 'Type', 'Customer')
        );
        System.assert(
            HubListViewUtil.applyLanePredicate('FROM Account WHERE Name != null', 'Type', 'Customer')
                .contains(') AND (Type = :kanbanLaneVal)')
        );
        System.assert(
            HubListViewUtil.applyLanePredicate('FROM Account\nWHERE Name != null', 'Type', 'Customer')
                .contains(') AND (Type = :kanbanLaneVal)')
        );
    }

    @IsTest
    static void testFetchKanbanBoardAndLaneMore() {
        Account a1 = new Account(Name = 'Kanban Acc A', Type = 'Customer');
        Account a2 = new Account(Name = 'Kanban Acc B', Type = 'Customer');
        Account a3 = new Account(Name = 'Kanban Acc C', Type = 'Partner');
        insert new List<Account>{ a1, a2, a3 };

        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }

        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'query' => 'SELECT Id, Name, Type FROM Account WHERE Name LIKE \'Kanban Acc%\'',
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
        Map<String, Object> board = HubListViewUtil.fetchKanbanBoard('Account', lvs[0].Id, 'Type', 1, null);
        Map<String, Object> more = HubListViewUtil.fetchKanbanLaneMore(
            'Account',
            lvs[0].Id,
            'Type',
            'Customer',
            1,
            1,
            null
        );
        Map<String, Object> bad = HubListViewUtil.fetchKanbanBoard('BadObject', lvs[0].Id, 'Type', 10, null);
        Test.stopTest();
        HubListViewUtil.testListViewDescribeOverride = null;

        System.assertEquals(null, board.get('error'), 'unexpected error: ' + String.valueOf(board.get('error')));
        System.assertEquals('Type', board.get('laneField'));
        Map<String, Object> counts = (Map<String, Object>) board.get('laneCounts');
        System.assert(counts != null && counts.containsKey('Customer'), 'Customer lane count expected');
        System.assertEquals(2, Integer.valueOf(String.valueOf(counts.get('Customer'))));
        Map<String, Object> laneRecords = (Map<String, Object>) board.get('laneRecords');
        System.assertEquals(1, ((List<Object>) laneRecords.get('Customer')).size());
        System.assertEquals(null, more.get('error'), 'unexpected more error: ' + String.valueOf(more.get('error')));
        System.assertEquals(1, ((List<Object>) more.get('records')).size());
        System.assert(bad.containsKey('error'));
    }

    @IsTest
    static void testResolveKanbanLaneFieldPrefersStageNotCurrency() {
        List<Map<String, Object>> colsCurrencyFirst = new List<Map<String, Object>>{
            new Map<String, Object>{
                'fieldNameOrPath' => 'CurrencyIsoCode',
                'label' => 'Currency',
                'type' => 'picklist'
            },
            new Map<String, Object>{
                'fieldNameOrPath' => 'Name',
                'label' => 'Opportunity Name',
                'type' => 'string'
            }
        };
        System.assertEquals(
            'StageName',
            HubListViewUtil.resolveKanbanLaneField('Opportunity', colsCurrencyFirst, null),
            'Opportunity Kanban must default to StageName even when Currency is on the list view'
        );
        System.assertEquals(
            'StageName',
            HubListViewUtil.resolveKanbanLaneField('Opportunity', new List<Map<String, Object>>(), null),
            'Opportunity Kanban defaults to StageName with empty columns'
        );
        System.assertEquals(
            'CurrencyIsoCode',
            HubListViewUtil.resolveKanbanLaneField('Opportunity', colsCurrencyFirst, 'CurrencyIsoCode'),
            'Explicit Group-by Currency remains available'
        );
        System.assertEquals(
            'Status__c',
            HubListViewUtil.resolveKanbanLaneField('Position__c', colsCurrencyFirst, null)
        );
        System.assertEquals(true, HubListViewUtil.isWeakKanbanLaneField('CurrencyIsoCode'));
        System.assertEquals(false, HubListViewUtil.isWeakKanbanLaneField('StageName'));
    }

    @IsTest
    static void testEnsureKanbanLaneColumnInjectsStageMeta() {
        List<Map<String, Object>> columns = new List<Map<String, Object>>{
            new Map<String, Object>{
                'fieldNameOrPath' => 'Name',
                'label' => 'Opportunity Name',
                'type' => 'string'
            }
        };
        HubListViewUtil.ensureKanbanLaneColumn('Opportunity', columns, 'StageName');
        Boolean found = false;
        for (Map<String, Object> col : columns) {
            if ('StageName'.equals(String.valueOf(col.get('fieldNameOrPath')))) {
                found = true;
                System.assert(col.containsKey('picklistValues'), 'StageName needs picklist values for lanes');
                break;
            }
        }
        System.assert(found, 'StageName column should be injected for Kanban');
    }

    @IsTest
    static void testAttachJobApplicationRedFlags() {
        Test.setMock(HttpCalloutMock.class, new HubListViewRestDescribeMock());

        List<Map<String, Object>> accountRows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'id' => UserInfo.getUserId() }
        };
        HubListViewUtil.attachJobApplicationRedFlags('Account', accountRows);
        System.assertEquals(null, accountRows[0].get('_chMissingName'));

        Position__c pos = new Position__c(
            Name = 'RedFlag Pos',
            Years_Of_Experience__c = 1,
            Max_Pay__c = 5000,
            Min_Pay__c = 4000,
            Status__c = 'New Position'
        );
        insert pos;
        Contact named = new Contact(FirstName = 'Ada', LastName = 'Lovelace');
        insert named;

        Test.startTest();
        Job_Application__c jaNoPerson = new Job_Application__c(
            Position__c = pos.Id,
            Status__c = 'New'
        );
        Job_Application__c jaNamedNoLinks = new Job_Application__c(
            Position__c = pos.Id,
            Status__c = 'New',
            Contact__c = named.Id
        );
        insert new List<Job_Application__c>{ jaNoPerson, jaNamedNoLinks };

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'id' => jaNoPerson.Id },
            new Map<String, Object>{ 'id' => jaNamedNoLinks.Id }
        };
        HubListViewUtil.attachJobApplicationRedFlags('Job_Application__c', rows);
        Test.stopTest();

        System.assertEquals(true, rows[0].get('_chMissingName'));
        System.assertEquals(true, rows[0].get('_chMissingTrailhead'));
        System.assertEquals(true, rows[0].get('_chMissingResume'));
        System.assertEquals(false, rows[1].get('_chMissingName'));
        System.assertEquals(true, rows[1].get('_chMissingTrailhead'));
        System.assertEquals(true, rows[1].get('_chMissingResume'));
        System.assertNotEquals(null, rows[1].get('_chApplicantName'));

        System.assertNotEquals(null, rows[0].get('_chScore'));
        System.assertNotEquals(null, rows[0].get('_chScoreBand'));
        System.assertNotEquals(null, rows[0].get('_chScoreFactors'));
        System.assertNotEquals(null, rows[1].get('_chScore'));
        System.assert(Integer.valueOf(String.valueOf(rows[0].get('_chScore'))) <= 100);
        System.assert(Integer.valueOf(String.valueOf(rows[1].get('_chScore'))) >= 0);
    }

    @IsTest
    static void testAttachOpportunityHubScores() {
        Account acc = new Account(Name = 'Opp Score Acc');
        insert acc;
        Opportunity opp = new Opportunity(
            Name = 'Hub Score Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Type = 'Existing Business',
            Type_of_Service__c = 'Other'
        );
        insert opp;

        List<Map<String, Object>> nonOppRows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'id' => acc.Id }
        };
        HubListViewUtil.attachOpportunityHubScores('Account', nonOppRows);
        System.assertEquals(null, nonOppRows[0].get('_chScore'));

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'id' => opp.Id }
        };
        Test.startTest();
        HubListViewUtil.attachOpportunityHubScores('Opportunity', rows);
        Test.stopTest();

        System.assertNotEquals(null, rows[0].get('_chScore'));
        System.assertNotEquals(null, rows[0].get('_chScoreBand'));
        System.assertNotEquals(null, rows[0].get('_chScoreFactors'));
        Integer score = Integer.valueOf(String.valueOf(rows[0].get('_chScore')));
        System.assert(score >= 0 && score <= 100, 'Score in range: ' + score);
    }

    @IsTest
    static void testListViewSearchHelpers() {
        String base = 'SELECT Id, Name, Type FROM Account ORDER BY Name LIMIT 50';
        String withWhere = 'SELECT Id, Name FROM Account WHERE Type = \'Customer\' ORDER BY Name';
        String clause = '(Name LIKE \'%Acme%\' OR Type LIKE \'%Acme%\')';
        System.assertEquals(
            'SELECT Id, Name, Type FROM Account WHERE ' +
                clause +
                ' ORDER BY Name LIMIT 50',
            HubListViewUtil.applySearchToListViewQuery(base, clause)
        );
        System.assertEquals(
            'SELECT Id, Name FROM Account WHERE (Type = \'Customer\') AND ' +
                clause +
                ' ORDER BY Name',
            HubListViewUtil.applySearchToListViewQuery(withWhere, clause)
        );

        List<Map<String, Object>> cols = new List<Map<String, Object>>{
            new Map<String, Object>{ 'fieldNameOrPath' => 'Name', 'type' => 'string' },
            new Map<String, Object>{ 'fieldNameOrPath' => 'Type', 'type' => 'picklist' }
        };
        String built = HubListViewUtil.buildListViewSearchOrClause('Account', cols, 'Acme');
        System.assertNotEquals(null, built);
        System.assert(built.contains('Name LIKE'), built);
        System.assert(built.contains('Type LIKE'), built);
    }

    @IsTest
    static void testFetchListViewResultsWithSearchTerm() {
        Account acc = new Account(Name = 'UniqueHubSearchAcc', Type = 'Customer');
        insert acc;
        List<ListView> lvs = [SELECT Id FROM ListView WHERE SobjectType = 'Account' LIMIT 1];
        if (lvs.isEmpty()) {
            return;
        }
        HubListViewUtil.testListViewDescribeOverride = new Map<String, Object>{
            'query' =>
                'SELECT Id, Name, Type FROM Account WHERE Name = \'UniqueHubSearchAcc\' ORDER BY Name',
            'columns' => buildAccountDescribeFixture().get('columns')
        };
        Test.startTest();
        Map<String, Object> res = HubListViewUtil.fetchListViewResults(
            'Account',
            lvs[0].Id,
            25,
            0,
            null,
            'UniqueHubSearchAcc'
        );
        Test.stopTest();
        HubListViewUtil.testListViewDescribeOverride = null;
        System.assertEquals(true, res.get('searchActive'));
        List<Object> rows = (List<Object>) res.get('records');
        System.assertEquals(1, rows.size(), 'Search should find the seeded account');
    }

    @IsTest
    static void testFilterRecordsByListSearch() {
        Account acc = new Account(Name = 'FilterSearchAcc', Type = 'Partner');
        insert acc;
        List<Map<String, Object>> cols = new List<Map<String, Object>>{
            new Map<String, Object>{ 'fieldNameOrPath' => 'Name', 'type' => 'string' },
            new Map<String, Object>{ 'fieldNameOrPath' => 'Type', 'type' => 'picklist' }
        };
        List<SObject> filtered = HubListViewUtil.filterRecordsByListSearch(
            new List<SObject>{ acc },
            'Account',
            cols,
            'FilterSearch'
        );
        System.assertEquals(1, filtered.size());
        System.assertEquals(
            0,
            HubListViewUtil.filterRecordsByListSearch(
                new List<SObject>{ acc },
                'Account',
                cols,
                'NoSuchValue'
            ).size()
        );
    }

    @IsTest
    static void testLookupColumnsResolveNameAndReferenceId() {
        Account acc = new Account(Name = 'Lookup Name Acc');
        insert acc;
        Contact con = new Contact(LastName = 'LookupPerson', AccountId = acc.Id);
        insert con;

        List<String> paths = HubListViewUtil.appendReferenceNamePaths(
            'Contact',
            new List<String>{ 'Id', 'Name', 'AccountId' }
        );
        System.assert(paths.contains('Account.Name'), 'Should expand AccountId to Account.Name: ' + paths);

        Contact loaded = [
            SELECT Id, Name, AccountId, Account.Name
            FROM Contact
            WHERE Id = :con.Id
        ];
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Contact.fields.getMap();
        Map<String, Object> cell = HubListViewUtil.buildRecordCell(loaded, 'AccountId', fieldMap);
        System.assertEquals('Lookup Name Acc', cell.get('value'), 'Lookup cell shows Name: ' + cell);
        System.assertEquals(String.valueOf(acc.Id), cell.get('referenceId'));
    }
}
