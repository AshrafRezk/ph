public without sharing class EmployeeCompensationService {

    public static final String OVERRIDE_USE_SUGGESTED = 'Use Suggested';
    public static final String OVERRIDE_FORCE_ELIGIBLE = 'Force Eligible';
    public static final String OVERRIDE_FORCE_INELIGIBLE = 'Force Ineligible';

    public static final String ROLE_MEDICAL_REP = 'Medical Rep';
    public static final String ROLE_DISTRICT_MANAGER = 'District Manager';
    public static final String ROLE_REGION_MANAGER = 'Region Manager';

    private static final Decimal REP_COVERAGE_THRESHOLD = 0.80;
    private static final Decimal REP_CALL_ACHIEVEMENT_THRESHOLD = 0.85;
    private static final Decimal REP_MAX_NOT_REPORTED_DAYS = 2;
    private static final Decimal MANAGER_COACHING_DAYS_THRESHOLD = 4;
    private static final Decimal MANAGER_COVERAGE_THRESHOLD = 0.75;

    public class EligibilityCriterion {
        @AuraEnabled public String label;
        @AuraEnabled public String detail;
        @AuraEnabled public Boolean passed;
    }

    public class EligibilityEvaluation {
        @AuraEnabled public Boolean suggestedBonusEligible;
        @AuraEnabled public Boolean suggestedCommissionEligible;
        @AuraEnabled public Boolean effectiveBonusEligible;
        @AuraEnabled public Boolean effectiveCommissionEligible;
        @AuraEnabled public String bonusOverride;
        @AuraEnabled public String commissionOverride;
        @AuraEnabled public List<EligibilityCriterion> criteria;
    }

    public class CompensationBlock {
        @AuraEnabled public Decimal baseSalary;
        @AuraEnabled public Boolean canViewSalary;
        @AuraEnabled public EligibilityEvaluation bonus;
        @AuraEnabled public EligibilityEvaluation commission;
    }

    public static Boolean canViewCompensation() {
        return FeatureManagement.checkPermission('View_Employee_Compensation');
    }

    public static Boolean resolveEffectiveEligibility(String overrideValue, Boolean suggestedEligible) {
        if (String.isBlank(overrideValue) || overrideValue == OVERRIDE_USE_SUGGESTED) {
            return suggestedEligible == true;
        }
        if (overrideValue == OVERRIDE_FORCE_ELIGIBLE) {
            return true;
        }
        if (overrideValue == OVERRIDE_FORCE_INELIGIBLE) {
            return false;
        }
        return suggestedEligible == true;
    }

    public static EligibilityEvaluation evaluateEligibility(Employee_Time_Card__c card, String roleInTerritory) {
        EligibilityEvaluation result = new EligibilityEvaluation();
        result.criteria = new List<EligibilityCriterion>();
        result.bonusOverride = card == null ? null : card.Bonus_Eligibility_Override__c;
        result.commissionOverride = card == null ? null : card.Commission_Eligibility_Override__c;

        Boolean isManager = isManagerRole(roleInTerritory);
        Boolean suggestedEligible = isManager
            ? evaluateManagerSuggested(card, result.criteria)
            : evaluateRepSuggested(card, result.criteria);

        result.suggestedBonusEligible = suggestedEligible;
        result.suggestedCommissionEligible = suggestedEligible;
        result.effectiveBonusEligible = resolveEffectiveEligibility(result.bonusOverride, suggestedEligible);
        result.effectiveCommissionEligible = resolveEffectiveEligibility(
            result.commissionOverride,
            suggestedEligible
        );
        return result;
    }

    public static CompensationBlock buildCompensationBlock(
        Employee_Time_Card__c card,
        String roleInTerritory
    ) {
        return buildCompensationBlock(card, roleInTerritory, card == null ? null : card.Employee__c);
    }

    public static CompensationBlock buildCompensationBlock(
        Employee_Time_Card__c card,
        String roleInTerritory,
        Id employeeId
    ) {
        CompensationBlock block = new CompensationBlock();
        block.canViewSalary = canViewCompensation();
        if (block.canViewSalary) {
            if (card != null && card.Base_Salary__c != null) {
                block.baseSalary = card.Base_Salary__c;
            } else {
                block.baseSalary = ExecutiveCompensationSeed.resolveSalaryForUser(employeeId, roleInTerritory);
            }
        }

        EligibilityEvaluation evaluation = evaluateEligibility(card, roleInTerritory);
        block.bonus = evaluation;
        block.commission = evaluation;
        return block;
    }

    private static Boolean isManagerRole(String roleInTerritory) {
        return roleInTerritory == ROLE_DISTRICT_MANAGER || roleInTerritory == ROLE_REGION_MANAGER;
    }

    private static Boolean evaluateRepSuggested(
        Employee_Time_Card__c card,
        List<EligibilityCriterion> criteria
    ) {
        if (card == null) {
            addCriterion(criteria, 'Time card', 'No active monthly time card', false);
            return false;
        }

        Decimal coverage = normalizePercent(card.Coverage_Percent__c);
        Boolean coveragePass = coverage >= REP_COVERAGE_THRESHOLD;
        addCriterion(
            criteria,
            'Coverage',
            formatPercent(coverage) + ' (target ≥ ' + formatPercent(REP_COVERAGE_THRESHOLD) + ')',
            coveragePass
        );

        Boolean callRatePass = evaluateRepCallAchievement(card);
        addCriterion(
            criteria,
            'Call achievement',
            buildCallAchievementDetail(card),
            callRatePass
        );

        Decimal notReported = card.Not_Reported_Days__c == null ? 0 : card.Not_Reported_Days__c;
        Boolean notReportedPass = notReported <= REP_MAX_NOT_REPORTED_DAYS;
        addCriterion(
            criteria,
            'Not-reported days',
            String.valueOf(notReported.intValue()) + ' (max ' + String.valueOf(REP_MAX_NOT_REPORTED_DAYS.intValue()) + ')',
            notReportedPass
        );

        return coveragePass && callRatePass && notReportedPass;
    }

    private static Boolean evaluateManagerSuggested(
        Employee_Time_Card__c card,
        List<EligibilityCriterion> criteria
    ) {
        if (card == null) {
            addCriterion(criteria, 'Time card', 'No active monthly time card', false);
            return false;
        }

        Decimal coachingDays = card.Coaching_Days_Total__c == null ? 0 : card.Coaching_Days_Total__c;
        Boolean coachingPass = coachingDays >= MANAGER_COACHING_DAYS_THRESHOLD;
        addCriterion(
            criteria,
            'Coaching days',
            String.valueOf(coachingDays.intValue()) + ' (target ≥ ' + String.valueOf(MANAGER_COACHING_DAYS_THRESHOLD.intValue()) + ')',
            coachingPass
        );

        Decimal coverage = normalizePercent(card.Coverage_Percent__c);
        Boolean coveragePass = coverage >= MANAGER_COVERAGE_THRESHOLD;
        addCriterion(
            criteria,
            'Coverage',
            formatPercent(coverage) + ' (target ≥ ' + formatPercent(MANAGER_COVERAGE_THRESHOLD) + ')',
            coveragePass
        );

        return coachingPass && coveragePass;
    }

    private static Boolean evaluateRepCallAchievement(Employee_Time_Card__c card) {
        Decimal visitTarget = card.Visit_Target__c == null ? 0 : card.Visit_Target__c;
        Decimal submitted = card.Submitted_Calls__c == null ? 0 : card.Submitted_Calls__c;
        if (visitTarget > 0) {
            return (submitted / visitTarget) >= REP_CALL_ACHIEVEMENT_THRESHOLD;
        }
        Decimal actualRate = card.Actual_Visit_Rate__c == null ? 0 : card.Actual_Visit_Rate__c;
        return actualRate >= 8.5;
    }

    private static String buildCallAchievementDetail(Employee_Time_Card__c card) {
        Decimal visitTarget = card.Visit_Target__c == null ? 0 : card.Visit_Target__c;
        Decimal submitted = card.Submitted_Calls__c == null ? 0 : card.Submitted_Calls__c;
        if (visitTarget > 0) {
            Decimal achievement = submitted / visitTarget;
            return formatPercent(achievement) + ' of visit target (' + submitted.intValue() + ' / ' + visitTarget.intValue() + ')';
        }
        Decimal actualRate = card.Actual_Visit_Rate__c == null ? 0 : card.Actual_Visit_Rate__c;
        return actualRate.setScale(1) + ' calls per active day (target ≥ 8.5 when no visit target)';
    }

    private static Decimal normalizePercent(Decimal value) {
        if (value == null) {
            return 0;
        }
        return value <= 1 ? value : value / 100;
    }

    private static String formatPercent(Decimal ratio) {
        Decimal normalized = normalizePercent(ratio);
        return String.valueOf((normalized * 100).setScale(0)) + '%';
    }

    private static void addCriterion(
        List<EligibilityCriterion> criteria,
        String label,
        String detail,
        Boolean passed
    ) {
        EligibilityCriterion row = new EligibilityCriterion();
        row.label = label;
        row.detail = detail;
        row.passed = passed;
        criteria.add(row);
    }
}
