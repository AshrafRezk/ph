@IsTest
private class ImsBrickOutlineServiceTest {
    class NominatimMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.assert(req.getEndpoint().contains('nominatim'), req.getEndpoint());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '[{"display_name":"Abbasiya, Cairo, Egypt","geojson":{"type":"Polygon","coordinates":' +
                    '[[[31.26,30.06],[31.29,30.06],[31.29,30.08],[31.26,30.08],[31.26,30.06]]]}}]'
            );
            return res;
        }
    }

    @IsTest
    static void suggestUsesTheImsNameOnOpenStreetMap() {
        BrickMapTestData d = BrickMapTestData.create();
        Test.setMock(HttpCalloutMock.class, new NominatimMock());
        Test.startTest();
        ImsBrickOutlineService.Suggestion suggestion = ImsBrickOutlineService.suggest(d.bare702.Id);
        Test.stopTest();
        System.assertNotEquals(null, suggestion.geometry);
        System.assert(suggestion.query.contains('Egypt'), suggestion.query);
        BrickGeometry.parse(suggestion.geometry);
    }

    @IsTest
    static void applyPackWritesImportedRegions() {
        BrickMapTestData d = BrickMapTestData.create();
        ImsBrickOutlineService.packOverride = new Map<String, String>{
            d.bare702.External_ID__c => BrickMapTestData.square(30.4, 31.4, 0.01)
        };
        Test.startTest();
        Integer n = ImsBrickOutlineService.applyPack(false);
        Test.stopTest();
        System.assertEquals(1, n);
        Brick__c saved = [
            SELECT Boundary_Source__c, Min_Latitude__c
            FROM Brick__c
            WHERE Id = :d.bare702.Id
        ];
        System.assertEquals('Imported', saved.Boundary_Source__c);
        System.assertNotEquals(null, saved.Min_Latitude__c);
    }

    @IsTest
    static void hayBricksSearchInSixthOfOctober() {
        System.assertEquals(
            'Hay 4, 6th of October, Egypt',
            ImsBrickOutlineService.searchQuery('Hay 4')
        );
        System.assertEquals('Dokki, Egypt', ImsBrickOutlineService.searchQuery('Dokki'));
    }

    @IsTest
    static void suggestUsesTheScrapedPackWhenPresent() {
        BrickMapTestData d = BrickMapTestData.create();
        ImsBrickOutlineService.packOverride = new Map<String, String>{
            d.bare702.External_ID__c => BrickMapTestData.square(30.4, 31.4, 0.01)
        };
        ImsBrickOutlineService.Suggestion suggestion = ImsBrickOutlineService.suggest(d.bare702.Id);
        System.assertEquals('Imported', suggestion.source);
        System.assertEquals('IMS outline pack', suggestion.query);
        BrickGeometry.parse(suggestion.geometry);
    }

    @IsTest
    static void a148NeedsIts702OutlinesFirst() {
        BrickMapTestData d = BrickMapTestData.create();
        ImsBrickOutlineService.packOverride = new Map<String, String>();
        try {
            ImsBrickOutlineService.suggest(d.south148.Id);
            System.assert(false, 'expected an error');
        } catch (ImsBrickOutlineService.OutlineException e) {
            System.assert(e.getMessage().contains('148'), e.getMessage());
        }
    }

    @IsTest
    static void applyPackSkipsBricksThatAlreadyHaveARegion() {
        BrickMapTestData d = BrickMapTestData.create();
        ImsBrickOutlineService.packOverride = new Map<String, String>{
            d.a702.External_ID__c => BrickMapTestData.square(30.4, 31.4, 0.01)
        };
        System.assertEquals(0, ImsBrickOutlineService.applyPack(false), 'already drawn');
        System.assertEquals(1, ImsBrickOutlineService.applyPack(true), 'overwrite');
    }

    @IsTest
    static void applyPackFailsWhenThePackIsEmpty() {
        ImsBrickOutlineService.packOverride = new Map<String, String>();
        try {
            ImsBrickOutlineService.applyPack(false);
            System.assert(false, 'expected an error');
        } catch (ImsBrickOutlineService.OutlineException e) {
            System.assert(e.getMessage().contains('scraped'));
        }
    }

    class PointMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('[{"display_name":"Abees, Alexandria, Egypt","geojson":{"type":"Point","coordinates":[29.95,31.20]}}]');
            return res;
        }
    }

    @IsTest
    static void aPointBecomesAStartingBox() {
        Test.setMock(HttpCalloutMock.class, new PointMock());
        Test.startTest();
        ImsBrickOutlineService.Suggestion suggestion = ImsBrickOutlineService.fromNominatim('Abees');
        Test.stopTest();
        BrickGeometry.Shape shape = BrickGeometry.parse(suggestion.geometry);
        System.assert(shape.vertexCount >= 4);
    }

    class EmptyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('[]');
            return res;
        }
    }

    @IsTest
    static void nominatimWithNoHitTellsTheUserToDraw() {
        Test.setMock(HttpCalloutMock.class, new EmptyMock());
        Test.startTest();
        try {
            ImsBrickOutlineService.fromNominatim('Unknown Hamlet');
            System.assert(false, 'expected an error');
        } catch (ImsBrickOutlineService.OutlineException e) {
            System.assert(e.getMessage().contains('Draw'));
        }
        Test.stopTest();
    }

    @IsTest
    static void loadPackReadsTheStaticResource() {
        ImsBrickOutlineService.packOverride = null;
        Map<String, String> pack = ImsBrickOutlineService.loadPack();
        System.assertNotEquals(null, pack);
    }

    @IsTest
    static void controllerSurfacesTheSuggestion() {
        BrickMapTestData d = BrickMapTestData.create();
        ImsBrickOutlineService.packOverride = new Map<String, String>{
            d.bare702.External_ID__c => BrickMapTestData.square(30.4, 31.4, 0.01)
        };
        BricksManagementController.RegionSuggestion suggestion = BricksManagementController.suggestRegionFromName(
            d.bare702.Id
        );
        System.assertNotEquals(null, suggestion.geometry);
        try {
            BricksManagementController.suggestRegionFromName(null);
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('brick'));
        }
    }
}
