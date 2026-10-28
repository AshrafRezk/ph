@IsTest
private class ClmTargetingServiceTest {
    private static CLM_Presentation__c deck(String terrJson, String rolesJson, Boolean unaligned) {
        return new CLM_Presentation__c(
            Name = 'Deck',
            Status__c = 'Available',
            Format__c = 'PDF',
            Territory_Ids__c = terrJson,
            Target_Roles__c = rolesJson,
            Allow_Unaligned__c = unaligned
        );
    }

    @IsTest
    static void untargetedAndUnaligned_areBroadcast() {
        ClmTargetingService.testTerritoryScope = new Set<String>();
        ClmTargetingService.testRoles = new Set<String>();

        System.assertEquals(true, ClmTargetingService.matchesTargeting(deck(null, null, false)), 'Untargeted is visible');
        System.assertEquals(true, ClmTargetingService.matchesTargeting(deck('["0MIxxx"]', null, true)), 'Allow unaligned overrides');
    }

    @IsTest
    static void territoryTargeting_matchesOnlyScopedUsers() {
        CLM_Presentation__c targeted = deck('["0MI000000000001","0MI000000000002"]', null, false);

        ClmTargetingService.testTerritoryScope = new Set<String>{ '0MI000000000002' };
        ClmTargetingService.testRoles = new Set<String>();
        System.assertEquals(true, ClmTargetingService.matchesTargeting(targeted), 'User in a targeted territory sees it');

        ClmTargetingService.testTerritoryScope = new Set<String>{ '0MI000000000009' };
        System.assertEquals(false, ClmTargetingService.matchesTargeting(targeted), 'User outside targeted territories does not');
    }

    @IsTest
    static void roleTargeting_matchesOnlyTargetedRoles() {
        CLM_Presentation__c targeted = deck(null, '["District Manager"]', false);

        ClmTargetingService.testTerritoryScope = new Set<String>();
        ClmTargetingService.testRoles = new Set<String>{ 'District Manager' };
        System.assertEquals(true, ClmTargetingService.matchesTargeting(targeted));

        ClmTargetingService.testRoles = new Set<String>{ 'Medical Rep' };
        System.assertEquals(false, ClmTargetingService.matchesTargeting(targeted));
    }

    @IsTest
    static void dateWindow_boundsVisibility() {
        Date today = Date.today();
        CLM_Presentation__c future = deck(null, null, true);
        future.Start_Date__c = today.addDays(1);
        System.assertEquals(false, ClmTargetingService.isInDateWindow(future, today), 'Not yet published');

        CLM_Presentation__c expired = deck(null, null, true);
        expired.End_Date__c = today.addDays(-1);
        System.assertEquals(false, ClmTargetingService.isInDateWindow(expired, today), 'Already expired');

        CLM_Presentation__c live = deck(null, null, true);
        live.Start_Date__c = today.addDays(-1);
        live.End_Date__c = today.addDays(1);
        System.assertEquals(true, ClmTargetingService.isInDateWindow(live, today));
    }

    @IsTest
    static void filterVisible_and_parsing() {
        ClmTargetingService.testTerritoryScope = new Set<String>{ '0MI000000000002' };
        ClmTargetingService.testRoles = new Set<String>();
        CLM_Presentation__c visible = deck('["0MI000000000002"]', null, false);
        CLM_Presentation__c hidden = deck('["0MI000000000009"]', null, false);
        CLM_Presentation__c expired = deck(null, null, true);
        expired.End_Date__c = Date.today().addDays(-1);

        List<CLM_Presentation__c> result = ClmTargetingService.filterVisible(
            new List<CLM_Presentation__c>{ visible, hidden, expired }
        );
        System.assertEquals(1, result.size(), 'Only the scoped, in-window deck is visible');

        // Legacy delimited parsing fallback.
        System.assertEquals(2, ClmTargetingService.parseJsonStrings('a; b').size());
        System.assertEquals(0, ClmTargetingService.parseJsonStrings(null).size());
        System.assert(ClmTargetingService.parseJsonStrings('["x","y","z"]').contains('y'));
    }

    @IsTest
    static void resolvesRealScopeForRunningUser() {
        // No injected scope -> exercises the SYSTEM_MODE resolution path (running user has no
        // territory in test context, so a targeted deck is hidden).
        Test.startTest();
        Boolean visible = ClmTargetingService.matchesTargeting(deck('["0MI000000000002"]', null, false));
        Test.stopTest();
        System.assertEquals(false, visible);
    }

    @IsTest
    static void adminLifecycle_targetPublishExpire() {
        CLM_Presentation__c pres = new CLM_Presentation__c(Name = 'Admin Deck', Status__c = 'Draft', Format__c = 'HTML');
        insert pres;

        Test.startTest();
        ClmPresentationAdminController.updateTargeting(pres.Id, '["0MI000000000002"]', '["Medical Rep"]', false);
        ClmPresentationAdminController.publish(pres.Id, Date.today(), Date.today().addDays(30));
        Test.stopTest();

        CLM_Presentation__c published = [
            SELECT Status__c, Start_Date__c, End_Date__c, Territory_Ids__c, Target_Roles__c, Allow_Unaligned__c
            FROM CLM_Presentation__c
            WHERE Id = :pres.Id
        ];
        System.assertEquals('Available', published.Status__c);
        System.assertEquals(Date.today(), published.Start_Date__c);
        System.assert(published.Territory_Ids__c.contains('0MI000000000002'));
        System.assert(published.Target_Roles__c.contains('Medical Rep'));

        ClmPresentationAdminController.expire(pres.Id);
        CLM_Presentation__c expired = [SELECT Status__c, End_Date__c FROM CLM_Presentation__c WHERE Id = :pres.Id];
        System.assertEquals('Unavailable', expired.Status__c);
        System.assertEquals(Date.today(), expired.End_Date__c);
    }

    @IsTest
    static void adminGuardrails() {
        try {
            ClmPresentationAdminController.publish(null, null, null);
            System.assert(false, 'Expected id validation');
        } catch (Exception ex) {
            System.assert(true);
        }
        CLM_Presentation__c pres = new CLM_Presentation__c(Name = 'G', Status__c = 'Draft', Format__c = 'ZIP');
        insert pres;
        try {
            ClmPresentationAdminController.publish(pres.Id, Date.today(), Date.today().addDays(-1));
            System.assert(false, 'Expected date validation');
        } catch (Exception ex) {
            System.assert(true);
        }
    }
}