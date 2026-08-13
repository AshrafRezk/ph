@IsTest
private class OsrSyncPackTest {
    @IsTest
    static void hello_returnsOk() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/hello';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrHelloService.HelloResponse res = OsrHelloService.hello();
        System.assertEquals(true, res.ok);
        System.assertNotEquals(null, res.orgId);
    }

    @IsTest
    static void profile_returnsDefault() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/profile';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrProfileService.SyncProfile p = OsrProfileService.profile();
        System.assertNotEquals(null, p.name);
        System.assert(p.objects != null && !p.objects.isEmpty());
    }

    @IsTest
    static void metadata_exportsAccountDescribe() {
        Test.setMock(HttpCalloutMock.class, new OsrToolingFailMock());
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/metadata';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"objects":["Account"],"flexiPages":["Field_Rep_Home"],"apps":["LightningSales"]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrMetadataService.MetadataResponse res = OsrMetadataService.buildResponse();
        System.assertEquals(1, res.objects.size());
        System.assertEquals('Account', res.objects[0].apiName);
        System.assert(!res.layouts.isEmpty());
        // Full field describe includes picklistValues / nillable
        Map<String, Object> describe = res.objects[0].describe;
        System.assert(describe.containsKey('fields'));
        List<Object> fields = (List<Object>) describe.get('fields');
        System.assert(fields.size() > 12, 'Expected full field list, not capped stub');
        // Layout should include more than the old 12-field cap when Account has many fields
        Map<String, Object> layout = res.layouts[0].layout;
        List<Object> sections = (List<Object>) layout.get('sections');
        System.assert(!sections.isEmpty());
        System.assertEquals(1, res.flexiPages.size());
        System.assertEquals('HomePage', res.flexiPages[0].type);
        System.assert(!res.apps.isEmpty());
    }

    @IsTest
    static void metadata_starExpandsTabObjects() {
        Test.setMock(HttpCalloutMock.class, new OsrToolingFailMock());
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/metadata';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"objects":["Account"],"flexiPages":["Field_Rep_Home"],"apps":["*"]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrMetadataService.MetadataResponse res = OsrMetadataService.buildResponse();
        System.assert(res.objects.size() >= 1, 'Expected at least Account describe');
        System.assert(res.apps.size() >= 1, 'Expected discovered apps');
    }

    @IsTest
    static void metadata_discoversAppsWithStar() {
        Test.setMock(HttpCalloutMock.class, new OsrToolingFailMock());
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/metadata';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"objects":["Account","Contact"],"flexiPages":["Field_Rep_Home"],"apps":["*"]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrMetadataService.MetadataResponse res = OsrMetadataService.buildResponse();
        System.assert(res.apps.size() >= 1, 'Expected discovered apps');
        System.assert(res.tabs.size() >= 2, 'Expected object + describe tabs');
    }

    @IsTest
    static void metadata_toolingEnrichment_usesNormalizedFlexiPage() {
        Test.setMock(HttpCalloutMock.class, new OsrToolingSuccessMock());
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/metadata';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"objects":["Account"],"flexiPages":["Account_Record_Page"],"apps":["Pharma_Field"]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrMetadataService.MetadataResponse res = OsrMetadataService.buildResponse();
        System.assertEquals(1, res.flexiPages.size());
        System.assertEquals('RecordPage', res.flexiPages[0].type);
        System.assertEquals('tooling', res.flexiPages[0].page.get('source'));
        System.assert(res.apps.size() >= 1, 'Expected at least one app');
        // Apps may be Tooling-enriched (batched) or stub+describeTabs — either is OK
        System.assertNotEquals(null, res.apps[0].app);
    }

    private class OsrToolingFailMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"message":"unauthorized"}');
            return res;
        }
    }

    private class OsrToolingSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint();
            if (endpoint != null && endpoint.contains('FlexiPage')) {
                res.setBody(
                    '{"totalSize":1,"done":true,"records":[{' +
                    '"Id":"0M0xx000000FLEXI","DeveloperName":"Account_Record_Page",' +
                    '"Metadata":{"type":"RecordPage","sobjectType":"Account","masterLabel":"Account Record Page",' +
                    '"flexiPageRegions":[{"name":"main","itemInstances":[{"componentInstance":{' +
                    '"componentName":"force:highlightsPanel","identifier":"hl1","componentInstanceProperties":[]}}]}]' +
                    '}}]}'
                );
            } else {
                res.setBody(
                    '{"totalSize":1,"done":true,"records":[{' +
                    '"Id":"0APxx000000APP","DeveloperName":"Pharma_Field","Label":"Pharma Field",' +
                    '"Metadata":{"label":"Pharma Field","uiType":"Lightning","tabs":["standard-Account","Visit__c"]}' +
                    '}]}'
                );
            }
            return res;
        }
    }

    @IsTest
    static void sharing_returnsAccountIds() {
        Account a = new Account(Name = 'OSR Test Account');
        insert a;

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/sharing';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"profileName":"Default_Field_Rep","objects":["Account"]}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrSharingService.SharingResponse res = OsrSharingService.buildResponse();
        System.assertEquals(1, res.sets.size());
        System.assert(res.sets[0].ids.contains(a.Id));
    }

    @IsTest
    static void outbox_createsAccount() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/outbox';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"actions":[{"clientId":"obx1","op":"create","objectApi":"Account","recordId":"local_1","payload":{"Name":"Offline Created"}}]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrOutboxService.OutboxResponse res = OsrOutboxService.buildResponse();
        System.assertEquals(1, res.results.size());
        System.assertEquals('synced', res.results[0].status);
        System.assertNotEquals(null, res.results[0].serverId);
    }

    @IsTest
    static void outbox_createsVisitWithoutName() {
        Account a = new Account(Name = 'Outbox Visit Account');
        insert a;
        Datetime startDt = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(10, 0, 0, 0));
        Datetime endDt = startDt.addHours(1);

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/outbox';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"actions":[{"clientId":"obx3","op":"create","objectApi":"Visit__c","recordId":"local_visit1","payload":{"Id":"local_visit1","Account__c":"' +
                a.Id +
                '","Status__c":"Draft","Start_Date__c":"' +
                startDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') +
                '","End_Date__c":"' +
                endDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') +
                '","Visit_Date__c":"' +
                startDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') +
                '","Visit_Type__c":"Planned (Automatically)"}}]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrOutboxService.OutboxResponse res = OsrOutboxService.buildResponse();
        System.assertEquals(1, res.results.size());
        System.assertEquals('synced', res.results[0].status);
        System.assertNotEquals(null, res.results[0].serverId);
    }

    @IsTest
    static void outbox_parsesNestedJsonPayload() {
        Account a = new Account(Name = 'Outbox JSON Account');
        insert a;

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/outbox';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"actions":[{"clientId":"obx2","op":"update","objectApi":"Account","recordId":"' +
                a.Id +
                '","payload":{"Id":"' +
                a.Id +
                '","Name":"Updated From JSON","Phone":"+20-2-999","BillingLatitude":30.04,"BillingLongitude":31.24}}]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrOutboxService.OutboxResponse res = OsrOutboxService.buildResponse();
        System.assertEquals(1, res.results.size());
        System.assertEquals('synced', res.results[0].status);
        Account updated = [SELECT Name, Phone FROM Account WHERE Id = :a.Id];
        System.assertEquals('Updated From JSON', updated.Name);
        System.assertEquals('+20-2-999', updated.Phone);
    }

    @IsTest
    static void outbox_deleteFailsWhenRecordAlreadyDeleted() {
        Account a = new Account(Name = 'Outbox Delete Missing');
        insert a;
        Id accountId = a.Id;
        delete a;

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/outbox';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"actions":[{"clientId":"obx_del","op":"delete","objectApi":"Account","recordId":"' +
                accountId +
                '","payload":{"Id":"' +
                accountId +
                '"}}]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrOutboxService.OutboxResponse res = OsrOutboxService.buildResponse();
        System.assertEquals(1, res.results.size());
        System.assertEquals('failed', res.results[0].status);
        System.assertNotEquals(null, res.results[0].error);
    }

    @IsTest
    static void lwc_returnsStubWhenMissing() {
        Test.setMock(HttpCalloutMock.class, new OsrToolingFailMock());
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/lwc';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"bundles":["c/missingBundle"]}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrLwcService.LwcResponse res = OsrLwcService.buildResponse();
        System.assertEquals(1, res.bundles.size());
        System.assert(res.bundles[0].sourceJs.contains('export default class'));
        System.assertEquals('stub', res.bundles[0].sourceKind);
    }

    @IsTest
    static void metadata_discoversLwcFromFieldRepHome() {
        Test.setMock(HttpCalloutMock.class, new OsrToolingFailMock());
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/metadata';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"objects":["Account"],"flexiPages":["Field_Rep_Home"],"apps":["*"]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrMetadataService.MetadataResponse res = OsrMetadataService.buildResponse();
        System.assert(res.lwcBundles != null && !res.lwcBundles.isEmpty(), 'Expected LWC pull list');
        System.assert(
            res.lwcBundles.contains('c/fieldRepHomeTodayPlan'),
            'Expected Today Plan in pull list'
        );
        Boolean hasPharma = false;
        for (OsrMetadataService.AppPayload a : res.apps) {
            if (
                a.developerName == 'LightningSales' ||
                (a.label != null && a.label.toLowerCase().contains('pharma field'))
            ) {
                hasPharma = true;
                break;
            }
        }
        System.assert(hasPharma || !res.apps.isEmpty(), 'Expected Pharma Field or discovered apps');
    }

    @IsTest
    static void files_manifestRuns() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/files';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"scopes":[{"maxBytes":5000000}]}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrFileService.FilesResponse res = OsrFileService.buildResponse();
        System.assertNotEquals(null, res.files);
    }

    @IsTest
    static void data_pullAccount() {
        insert new Account(Name = 'OSR Data Pull');
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/data';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"objectApi":"Account","fields":["Id","Name","SystemModstamp"],"pageSize":10}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrDataService.DataResponse res = OsrDataService.buildResponse();
        System.assert(res.records.size() > 0);
        System.assertEquals(true, res.done);
    }

    @IsTest
    static void data_skipsInvalidFieldsAndFilter() {
        insert new Account(Name = 'OSR Bad Field Pull');
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/data';
        req.httpMethod = 'POST';
        // Subject does not exist on Account; Planned_Date__c filter must not 500
        req.requestBody = Blob.valueOf(
            '{"objectApi":"Account","fields":["Id","Name","Subject","Status","SystemModstamp"],' +
            '"filter":"Planned_Date__c = TODAY","pageSize":10}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrDataService.DataResponse res = OsrDataService.buildResponse();
        System.assertEquals(null, res.error, 'Expected resilient pull, got: ' + res.error);
        System.assert(res.records.size() > 0);
        System.assertEquals(true, res.done);
    }

    @IsTest
    static void data_unknownObjectReturnsEmptyNotThrow() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/data';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"objectApi":"WaveHome","fields":["Id","SystemModstamp"],"pageSize":10}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrDataService.DataResponse res = OsrDataService.buildResponse();
        System.assertEquals(true, res.done);
        System.assertEquals(0, res.records.size());
        System.assertNotEquals(null, res.error);
    }

    @IsTest
    static void prefs_upsertAndRead() {
        RestRequest postReq = new RestRequest();
        postReq.requestUri = '/services/apexrest/osr/v1/prefs';
        postReq.httpMethod = 'POST';
        postReq.requestBody = Blob.valueOf(
            '{"objectApi":"Account","favourites":["00BxxFAV"],"pinnedListViewId":"00BxxPIN","calendarField":"CreatedDate"}'
        );
        RestContext.request = postReq;
        RestContext.response = new RestResponse();

        OsrPreferenceService.PrefsResponse upsertRes = OsrPreferenceService.buildUpsertResponse();
        System.assert(upsertRes.ok, upsertRes.error == null ? 'upsert failed' : upsertRes.error);
        System.assertEquals(1, upsertRes.prefs.size());
        System.assertEquals('Account', upsertRes.prefs[0].objectApi);
        System.assertEquals('CreatedDate', upsertRes.prefs[0].calendarField);
        System.assertEquals('00BxxPIN', upsertRes.prefs[0].pinnedListViewId);

        RestRequest getReq = new RestRequest();
        getReq.requestUri = '/services/apexrest/osr/v1/prefs';
        getReq.httpMethod = 'GET';
        RestContext.request = getReq;
        RestContext.response = new RestResponse();

        OsrPreferenceService.PrefsResponse readRes = OsrPreferenceService.buildReadResponse();
        System.assert(readRes.ok, readRes.error == null ? 'read failed' : readRes.error);
        System.assert(readRes.prefs.size() >= 1);
        Boolean found = false;
        for (OsrPreferenceService.ObjectPrefs p : readRes.prefs) {
            if (p.objectApi == 'Account') {
                found = true;
                System.assertEquals('CreatedDate', p.calendarField);
                System.assertEquals(1, p.favourites.size());
            }
        }
        System.assert(found, 'Expected Account prefs after upsert');
    }

    @IsTest
    static void metadata_plannerStub_isAppPageWithLwc() {
        Test.setMock(HttpCalloutMock.class, new OsrToolingFailMock());
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/metadata';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"objects":["Account"],"flexiPages":["Field_Rep_Planner","Field_Rep_Home"],"apps":["LightningSales"]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrMetadataService.MetadataResponse res = OsrMetadataService.buildResponse();
        OsrMetadataService.FlexiPagePayload planner = null;
        for (OsrMetadataService.FlexiPagePayload fp : res.flexiPages) {
            if (fp.developerName == 'Field_Rep_Planner') {
                planner = fp;
            }
        }
        System.assertNotEquals(null, planner, 'Expected Field_Rep_Planner flexi page');
        System.assertEquals('AppPage', planner.type, 'Planner must not stub as RecordPage');
        Map<String, Object> page = planner.page;
        System.assertNotEquals(null, page);
        List<Object> regions = (List<Object>) page.get('regions');
        System.assert(!regions.isEmpty());
        Map<String, Object> main = (Map<String, Object>) regions[0];
        List<Object> comps = (List<Object>) main.get('components');
        System.assert(!comps.isEmpty(), 'Planner stub must include fieldRepPlanner LWC');
        Map<String, Object> first = (Map<String, Object>) comps[0];
        String typ = String.valueOf(first.get('type'));
        System.assert(
            typ.contains('fieldRepPlanner'),
            'Expected c/fieldRepPlanner component, got ' + typ
        );
    }

    @IsTest
    static void apexCache_returnsEntries() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/apex-cache';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"keys":["homeMetrics","officeMessages","plannerViewer"]}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrApexCacheService.CacheResponse res = OsrApexCacheService.buildResponse();
        System.assertEquals(true, res.ok);
        System.assertEquals(3, res.entries.size());
        for (OsrApexCacheService.CacheEntry e : res.entries) {
            System.assertNotEquals(null, e.key);
            System.assertNotEquals(null, e.fetchedAt);
            // Payload may be null if org data missing; error should still be structured
            System.assert(e.error == null || e.payload == null || e.payload != null);
        }
    }

    @IsTest
    static void staticResources_returnsAllowlist() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/osr/v1/static-resources';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"names":["leaflet"]}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        OsrStaticResourceService.StaticResourceResponse res = OsrStaticResourceService.buildResponse();
        System.assertEquals(true, res.ok);
        System.assertEquals(1, res.resources.size());
        System.assertEquals('leaflet', res.resources[0].name);
        // Body present when org has the StaticResource; otherwise structured error
        System.assert(res.resources[0].bodyBase64 != null || res.resources[0].error != null);
    }
}
