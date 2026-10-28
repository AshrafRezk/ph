@IsTest
private class SalesPolicyServiceTest {
    @IsTest
    static void getOrgPolicy_neverWrites() {
        Integer dmlBefore = Limits.getDmlStatements();
        SalesPolicyService.Policy policy = SalesPolicyService.getOrgPolicy();
        System.assertEquals(dmlBefore, Limits.getDmlStatements(), 'Reads must not run DML');
        System.assertEquals(0, [SELECT COUNT() FROM Sales_Policy__c], 'Reads must not seed the Org Default');
        System.assertEquals(200, policy.ceilingCap, 'Framework default is returned');
        System.assertEquals(true, SalesPolicyService.isTenderExceptionBrand('Zeta Colest'));
        System.assertEquals(10, SalesPolicyService.resolveAchievementUnitPrice(false, 'Other', 10, 7));
        System.assertEquals(
            dmlBefore,
            Limits.getDmlStatements(),
            'Price helpers read the policy and must not run DML either'
        );
    }

    @IsTest
    static void seedAndSave_createTheOrgDefault() {
        SalesPolicyService.Policy seeded = SalesPolicyService.seedOrgPolicy();
        System.assertNotEquals(null, seeded.id);
        System.assertEquals(1, [SELECT COUNT() FROM Sales_Policy__c WHERE Is_Org_Default__c = TRUE]);

        seeded.ceilingCap = 150;
        SalesPolicyService.Policy saved = SalesPolicyService.saveOrgPolicy(seeded);
        System.assertEquals(150, saved.ceilingCap);
        System.assertEquals(1, [SELECT COUNT() FROM Sales_Policy__c WHERE Is_Org_Default__c = TRUE]);
    }

    @IsTest
    static void save_withoutSeed_createsRow() {
        SalesPolicyService.Policy payload = new SalesPolicyService.Policy();
        payload.ceilingCap = 120;
        payload.actualSharePct = 100;
        payload.targetSharePct = 50;
        SalesPolicyService.Policy saved = SalesPolicyService.saveOrgPolicy(payload);
        System.assertEquals(120, saved.ceilingCap);
        System.assertNotEquals(null, saved.id);
    }
}
