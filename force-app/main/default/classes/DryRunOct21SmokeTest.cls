@IsTest
private class DryRunOct21SmokeTest {
    @IsTest
    static void salesPolicyDistributorsAndServiceRequests() {
        Test.startTest();
        SalesPolicyService.Policy policy = SalesPolicyService.getOrgPolicy();
        System.assertNotEquals(null, policy);
        System.assertEquals(true, SalesPolicyService.isTenderExceptionBrand('Zeta Colest'));
        System.assertEquals(7, SalesPolicyService.resolveAchievementUnitPrice(true, 'Other', 10, 7));
        System.assertEquals(10, SalesPolicyService.resolveAchievementUnitPrice(true, 'Zeta Colest', 10, 7));
        System.assertEquals(10, SalesPolicyService.resolveAchievementUnitPrice(false, 'Other', 10, 7));
        policy.name = 'Org Default';
        policy.ceilingCap = 200;
        policy.actualSharePct = 100;
        policy.targetSharePct = 50;
        policy.excludeTenderFromAchievements = true;
        policy.usePublicPriceForNonTender = true;
        policy.tenderPriceExceptionBrands = 'Zeta Colest';
        System.assertNotEquals(null, SalesPolicyService.saveOrgPolicy(policy));

        SalesDistributorRegistry.ensureDefaults();
        System.assert(SalesDistributorRegistry.listDistributors(true).size() > 0);
        System.assertEquals(
            true,
            SalesDistributorRegistry.upsertDistributor('Direct', 'Zeta Direct', true, 'Direct', true).isDirect
        );

        ServiceRequestTypeService.seedDefaults();
        System.assert(ServiceRequestTypeService.listTypes(null).size() > 0);
        ServiceRequestTypeService.TypeRow created = new ServiceRequestTypeService.TypeRow();
        created.name = 'Smoke Device';
        created.category = 'Field';
        created.creatorTitles = 'Medical Rep';
        created.isActive = true;
        System.assertNotEquals(null, ServiceRequestTypeService.saveType(created).id);
        System.assertNotEquals(null, ServiceRequestTypeService.typesForCurrentUser('Field'));

        BrandManagerSeatService.SeatResult seat = BrandManagerSeatService.seatMarketingOnOrganogram();
        System.assertNotEquals(null, seat);
        System.assertEquals(16, ZetaPlannedFieldDaysCalculator.plannedFieldDays('DSM', 20));
        System.assertEquals(17, ZetaPlannedFieldDaysCalculator.availableWorkingDays(20, 2, 1));

        TargetGovernanceService.RuleSettings rule = TargetGovernanceService.getRuleForLine(null);
        System.assertEquals(10, rule.frequencyDeviationPct);
        rule.frequencyDeviationPct = 10;
        rule.listChurnDeviationPct = 10;
        System.assertNotEquals(null, TargetGovernanceService.saveOrgRule(rule));
        System.assert(PlannerRulesService.listTitleOptions() != null);
        System.assert(PlannerRulesService.listProfileOptions() != null);
        ServiceRequestTypeService.seedDefaults();
        System.assert(ServiceRequestTypeService.listAllTypes(null).size() > 0);
        Test.stopTest();
    }
}
