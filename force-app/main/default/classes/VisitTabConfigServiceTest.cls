@IsTest
private class VisitTabConfigServiceTest {
    @IsTest
    static void defaultsIncludeOrdersAndRequests() {
        List<String> hcp = VisitTabConfigService.tabsFor('Medical_Professional_HCP', 'HCP');
        System.assert(hcp.contains('orders'), 'HCP visits include Orders');
        System.assert(hcp.contains('requests'), 'HCP visits include Requests');
        System.assert(!hcp.contains('storeCheck'), 'HCP visits omit Store Check until an admin turns it on');
        System.assert(hcp.contains('details'));

        List<String> pharmacy = VisitTabConfigService.tabsFor('Pharmacy', 'Pharmacy');
        System.assert(pharmacy.contains('orders'), 'Pharmacy visits include Orders');
        System.assert(pharmacy.contains('requests'), 'Pharmacy visits include Requests');
        System.assert(pharmacy.contains('storeCheck'));
        System.assert(!pharmacy.contains('attendees'));
    }

    @IsTest
    static void saveThenReadRecordTypeTabs() {
        List<RecordType> types = [
            SELECT DeveloperName, Name
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsActive = TRUE
            LIMIT 1
        ];
        System.assert(!types.isEmpty(), 'Account record types should exist');
        String developerName = types[0].DeveloperName;

        String payload = JSON.serialize(
            new List<Object>{
                new Map<String, Object>{
                    'developerName' => developerName,
                    'tabs' => new List<String>{ 'orders', 'requests', 'presentations' }
                }
            }
        );

        Test.startTest();
        VisitTabConfigService.Matrix loaded = VisitTabConfigController.getMatrix();
        System.assert(loaded.rows != null && !loaded.rows.isEmpty());
        VisitTabConfigService.Matrix saved = VisitTabConfigController.saveMatrix(payload);
        List<String> tabs = VisitTabConfigController.getVisitTabs(developerName, types[0].Name);
        List<String> viaCall = VisitCallReportController.getVisitTabs(developerName, types[0].Name);
        System.assertEquals(tabs, viaCall);
        Test.stopTest();

        System.assert(tabs.contains('orders'));
        System.assert(tabs.contains('requests'));
        System.assert(tabs.contains('presentations'));
        System.assert(tabs.contains('details'));
        System.assertEquals(4, tabs.size());

        VisitTabConfigService.RecordTypeRow match;
        for (VisitTabConfigService.RecordTypeRow row : saved.rows) {
            if (row.developerName == developerName) {
                match = row;
            }
        }
        System.assertNotEquals(null, match);
        for (VisitTabConfigService.TabCell cell : match.cells) {
            if (cell.key == 'orders') {
                System.assertEquals(true, cell.enabled);
            }
            if (cell.key == 'attendees') {
                System.assertEquals(false, cell.enabled);
            }
            if (cell.key == 'details') {
                System.assertEquals(true, cell.locked);
            }
        }
    }

    @IsTest
    static void saveRejectsEmptyPayload() {
        Boolean blankFailed = false;
        try {
            VisitTabConfigController.saveMatrix('');
        } catch (AuraHandledException ex) {
            blankFailed = true;
        }
        System.assertEquals(true, blankFailed);

        Boolean shapeFailed = false;
        try {
            VisitTabConfigController.saveMatrix('{}');
        } catch (AuraHandledException ex) {
            shapeFailed = true;
        }
        System.assertEquals(true, shapeFailed);
    }

    @IsTest
    static void detailsCannotBeRemoved() {
        List<String> tabs = VisitTabConfigService.tabsFor(null, null);
        System.assert(tabs.contains('details'));
        System.assert(tabs.contains('orders'));
        System.assert(tabs.contains('requests'));
    }

    private static User standardUser() {
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
        return new User(
            Alias = 'vtab' + suffix.left(4),
            Email = 'visittab' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'VisitTab',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = 'visittab' + suffix + '@example.com.zeta'
        );
    }

    @IsTest
    static void nonAdminCannotSaveButStillReadsSavedTabs() {
        List<RecordType> types = [
            SELECT DeveloperName, Name
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsActive = TRUE
            LIMIT 1
        ];
        System.assert(!types.isEmpty(), 'Account record types should exist');
        String developerName = types[0].DeveloperName;
        String payload = JSON.serialize(
            new List<Object>{
                new Map<String, Object>{
                    'developerName' => developerName,
                    'tabs' => new List<String>{ 'requests' }
                }
            }
        );
        VisitTabConfigService.saveMatrix(payload);

        User field = standardUser();
        insert field;
        List<String> tabs;
        Boolean blocked = false;
        System.runAs(field) {
            tabs = VisitTabConfigService.tabsFor(developerName, types[0].Name);
            try {
                VisitTabConfigService.saveMatrix(payload);
            } catch (AuraHandledException ex) {
                blocked = true;
            }
        }
        System.assertEquals(true, blocked, 'Users without Field App Feature edit access cannot save');
        System.assertEquals(new List<String>{ 'details', 'requests' }, tabs, 'Saved tabs apply to every user');
    }

    @IsTest
    static void matrixRowsCarryRecordTypeIds() {
        VisitTabConfigService.Matrix matrix = VisitTabConfigService.getMatrix();
        for (VisitTabConfigService.RecordTypeRow row : matrix.rows) {
            System.assertNotEquals(null, row.recordTypeId);
        }
    }
}
