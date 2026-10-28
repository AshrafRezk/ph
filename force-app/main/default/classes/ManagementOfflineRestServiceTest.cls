@IsTest
private class ManagementOfflineRestServiceTest {
    @IsTest
    static void readsFilters() {
        assertOk('business-units');
        assertOk('lines');
        assertOk('districts');
        assertOk('lines?businessUnitTerritoryId=not-an-id');
    }

    @IsTest
    static void readsTeamKpis() {
        assertOk('team-kpis?buTerritoryId=ALL&lineTerritoryId=ALL&districtTerritoryId=ALL');
    }

    @IsTest
    static void readsRosterAndProducts() {
        assertOk('workforce-roster?workforceType=reps');
        assertOk('product-performance');
        assertOk('rep-accounts');
    }

    @IsTest
    static void readsMyTeamQueues() {
        assertOk('my-team');
        assertOk('pending-meetings');
        assertOk('pending-time-off');
    }

    @IsTest
    static void unknownPath_returns404() {
        RestContext.request = new RestRequest();
        RestContext.request.requestURI = '/services/apexrest/management/v1/missing';
        RestContext.request.httpMethod = 'GET';
        RestContext.response = new RestResponse();

        ManagementOfflineRestService.doGet();

        System.assertEquals(404, RestContext.response.statusCode);
    }

    private static void assertOk(String pathAndQuery) {
        RestContext.request = new RestRequest();
        RestContext.request.requestURI = '/services/apexrest/management/v1/' + pathAndQuery;
        RestContext.request.httpMethod = 'GET';
        RestContext.response = new RestResponse();
        if (pathAndQuery.contains('?')) {
            RestContext.request.params.put('buTerritoryId', 'ALL');
            RestContext.request.params.put('lineTerritoryId', 'ALL');
            RestContext.request.params.put('districtTerritoryId', 'ALL');
        }

        ManagementOfflineRestService.doGet();

        System.assertEquals(200, RestContext.response.statusCode, pathAndQuery);
        System.assertNotEquals(null, RestContext.response.responseBody);
    }
}