@IsTest
private class IntegrationsStatusServiceTest {
    @IsTest
    static void getStatuses_orgSnapshot_oneKeyNeverConfigured() {
        clearOverrides();
        Test.startTest();
        List<IntegrationsStatusService.IntegrationStatus> rows = IntegrationsStatusService.getStatuses();
        Test.stopTest();

        Map<String, IntegrationsStatusService.IntegrationStatus> byId = index(rows);
        System.assertEquals('Not configured', byId.get('onekey').status);
        System.assertNotEquals('Connected', byId.get('ims-health').status);
        System.assertEquals('Planned', byId.get('veeva-network').status);
        System.assertEquals('Planned', byId.get('outlook').status);
        System.assertEquals('Planned', byId.get('sap-erp').status);
    }

    @IsTest
    static void getStatuses_coversImsMapsMendixWholesalerBranches() {
        clearOverrides();

        // IMS: catalog only
        IntegrationsStatusService.brickCountOverride = 10;
        IntegrationsStatusService.pharmacyLinksOverride = 0;
        IntegrationsStatusService.accountsWithBrickOverride = 0;
        IntegrationsStatusService.selloutAliasOverride = 0;
        IntegrationsStatusService.namedCredentialOverride = new Set<String>();
        Map<String, IntegrationsStatusService.IntegrationStatus> emptyCreds = index(
            IntegrationsStatusService.getStatuses()
        );
        System.assertEquals('Not connected', emptyCreds.get('ims-health').status);
        System.assertEquals('Not configured', emptyCreds.get('maps').status);
        System.assertEquals('Not configured', emptyCreds.get('mendix').status);
        System.assertEquals('Not connected', emptyCreds.get('ibnsina-pharmaoverseas').status);

        // IMS: not configured (no bricks)
        IntegrationsStatusService.brickCountOverride = 0;
        Map<String, IntegrationsStatusService.IntegrationStatus> noBricks = index(
            IntegrationsStatusService.getStatuses()
        );
        System.assertEquals('Not configured', noBricks.get('ims-health').status);

        // IMS: partial links; maps/mendix/wholesaler positive paths
        IntegrationsStatusService.brickCountOverride = 5;
        IntegrationsStatusService.pharmacyLinksOverride = 2;
        IntegrationsStatusService.accountsWithBrickOverride = 1;
        IntegrationsStatusService.selloutAliasOverride = 3;
        IntegrationsStatusService.namedCredentialOverride = new Set<String>{
            'Google_Geocoding',
            'OpenStreetMap_Nominatim',
            'Mendix_API',
            'Mendix_Requests'
        };
        Map<String, IntegrationsStatusService.IntegrationStatus> linked = index(
            IntegrationsStatusService.getStatuses()
        );
        System.assertEquals('Partial', linked.get('ims-health').status);
        System.assertEquals('Connected', linked.get('maps').status);
        System.assert(linked.get('maps').detail.contains('Google Places'));
        System.assert(linked.get('maps').detail.contains('OpenStreetMap'));
        System.assertEquals('Pending Setup', linked.get('mendix').status);
        System.assertEquals('Partial', linked.get('ibnsina-pharmaoverseas').status);
        System.assert(linked.get('ibnsina-pharmaoverseas').metaValue.contains('3'));

        // Single-cred branches
        IntegrationsStatusService.namedCredentialOverride = new Set<String>{ 'Google_Geocoding' };
        System.assertEquals('Connected', index(IntegrationsStatusService.getStatuses()).get('maps').status);
        IntegrationsStatusService.namedCredentialOverride = new Set<String>{ 'Mendix_Requests' };
        System.assertEquals(
            'Pending Setup',
            index(IntegrationsStatusService.getStatuses()).get('mendix').status
        );

        clearOverrides();
    }

    private static void clearOverrides() {
        IntegrationsStatusService.namedCredentialOverride = null;
        IntegrationsStatusService.brickCountOverride = null;
        IntegrationsStatusService.pharmacyLinksOverride = null;
        IntegrationsStatusService.accountsWithBrickOverride = null;
        IntegrationsStatusService.selloutAliasOverride = null;
    }

    private static Map<String, IntegrationsStatusService.IntegrationStatus> index(
        List<IntegrationsStatusService.IntegrationStatus> rows
    ) {
        System.assert(rows != null && rows.size() >= 8);
        Map<String, IntegrationsStatusService.IntegrationStatus> byId = new Map<String, IntegrationsStatusService.IntegrationStatus>();
        for (IntegrationsStatusService.IntegrationStatus row : rows) {
            byId.put(row.id, row);
        }
        return byId;
    }
}
