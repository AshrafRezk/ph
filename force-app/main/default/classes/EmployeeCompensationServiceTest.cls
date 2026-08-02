@IsTest
private class EmployeeCompensationServiceTest {

    @IsTest
    static void evaluateEligibility_nullCardNotEligible() {
        EmployeeCompensationService.EligibilityEvaluation result =
            EmployeeCompensationService.evaluateEligibility(null, EmployeeCompensationService.ROLE_MEDICAL_REP);

        System.assertEquals(false, result.suggestedBonusEligible);
        System.assertEquals(false, result.effectiveBonusEligible);
    }

    @IsTest
    static void evaluateEligibility_managerUsesCoachingDays() {
        Employee_Time_Card__c card = new Employee_Time_Card__c(Coaching_Days_Total__c = 5);

        EmployeeCompensationService.EligibilityEvaluation result =
            EmployeeCompensationService.evaluateEligibility(
                card,
                EmployeeCompensationService.ROLE_DISTRICT_MANAGER
            );

        System.assertEquals(2, result.criteria.size());
        System.assertEquals(true, result.criteria[0].passed);
    }

    @IsTest
    static void resolveEffectiveEligibility_honorsOverride() {
        System.assertEquals(
            true,
            EmployeeCompensationService.resolveEffectiveEligibility(
                EmployeeCompensationService.OVERRIDE_FORCE_ELIGIBLE,
                false
            )
        );
        System.assertEquals(
            false,
            EmployeeCompensationService.resolveEffectiveEligibility(
                EmployeeCompensationService.OVERRIDE_FORCE_INELIGIBLE,
                true
            )
        );
        System.assertEquals(
            true,
            EmployeeCompensationService.resolveEffectiveEligibility(
                EmployeeCompensationService.OVERRIDE_USE_SUGGESTED,
                true
            )
        );
    }

    @IsTest
    static void buildCompensationBlock_appliesForceEligibleOverride() {
        Employee_Time_Card__c card = new Employee_Time_Card__c(
            Base_Salary__c = 18000,
            Bonus_Eligibility_Override__c = EmployeeCompensationService.OVERRIDE_FORCE_ELIGIBLE,
            Commission_Eligibility_Override__c = EmployeeCompensationService.OVERRIDE_FORCE_INELIGIBLE
        );

        EmployeeCompensationService.CompensationBlock block =
            EmployeeCompensationService.buildCompensationBlock(
                card,
                EmployeeCompensationService.ROLE_MEDICAL_REP
            );

        System.assertEquals(true, block.bonus.effectiveBonusEligible);
        System.assertEquals(false, block.commission.effectiveCommissionEligible);
    }
}
