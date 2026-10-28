@IsTest
private class FieldAppFeatureControllerTest {
    @IsTest
    static void catalogAndSaveRoundTrip() {
        Test.startTest();
        List<FieldAppFeatureController.FeatureRow> rows =
            FieldAppFeatureController.getFeatureCatalog();
        System.assert(!rows.isEmpty(), 'Catalog should seed defaults');

        Map<String, Boolean> enabled = FieldAppFeatureController.getEnabledFeatureMap();
        System.assertEquals(true, enabled.get('home.yourPerformance'));

        List<FieldAppFeatureController.FeatureRow> homeRows =
            FieldAppFeatureController.getCatalogByCategories(new List<String>{ 'Home', 'HCP' });
        System.assert(!homeRows.isEmpty());

        FieldAppFeatureController.FeatureRow updated =
            FieldAppFeatureController.setFeatureEnabled('home.beInTheKnow', false);
        System.assertEquals(false, updated.enabled);

        Map<String, Boolean> after = FieldAppFeatureController.getEnabledFeatureMap();
        System.assertEquals(false, after.get('home.beInTheKnow'));

        FieldAppFeatureController.saveFeatureMap(
            new Map<String, Boolean>{ 'classEngine' => false, 'agentforce' => false }
        );
        Map<String, Boolean> toggled = FieldAppFeatureController.getEnabledFeatureMap();
        System.assertEquals(false, toggled.get('classEngine'));
        System.assertEquals(false, toggled.get('agentforce'));

        List<FieldAppFeatureController.NavApp> nav = FieldAppFeatureController.getCopilotNavigation();
        System.assert(!nav.isEmpty());
        for (FieldAppFeatureController.NavApp app : nav) {
            if (app.key == 'LightningSales' || app.key == 'Pharma_SFE') {
                for (FieldAppFeatureController.NavTab tab : app.tabs) {
                    if (tab.key == 'Class_Engine') {
                        System.assertEquals(false, tab.enabled);
                    }
                }
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void performanceRuleRequiresOneRing() {
        FieldAppFeatureController.getFeatureCatalog();
        Boolean threw = false;
        try {
            FieldAppFeatureController.saveFeatureMap(
                new Map<String, Boolean>{
                    'home.yourPerformance' => true,
                    'metric.visit' => false,
                    'metric.customer' => false,
                    'metric.rf' => false,
                    'metric.remaining' => false,
                    'metric.am' => false,
                    'metric.pm' => false
                }
            );
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Saving with every performance ring off should fail');
    }
}
