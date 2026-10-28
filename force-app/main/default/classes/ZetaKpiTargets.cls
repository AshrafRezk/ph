/**
 * Zeta Pharma KPI framework targets by manager role.
 * Reads editable KPI_Target__c rows via KpiTargetService; constants remain as compile-time fallbacks.
 */
public with sharing class ZetaKpiTargets {
    public static final Decimal SALES_ACHIEVEMENT_TARGET = 100;
    public static final Decimal REPS_AT_90_TARGET_DSM = 70;
    public static final Decimal REPS_AT_90_TARGET_ASM = 70;
    public static final Decimal REPS_AT_90_TARGET_NSM = 70;
    public static final Decimal COVERAGE_TARGET_DSM = 100;
    public static final Decimal COVERAGE_TARGET_ASM = 80;
    public static final Decimal COVERAGE_TARGET_NSM = 80;
    public static final Decimal RIGHT_FREQUENCY_TARGET = 80;
    public static final Decimal KOL_COVERAGE_TARGET = 90;
    public static final Decimal QUIZ_TARGET_DSM = 80;
    public static final Decimal QUIZ_TARGET_ASM = 80;
    public static final Decimal QUIZ_TARGET_NSM = 90;
    public static final Decimal QUIZ_TARGET_MSR = 85;

    public static String resolveManagerRoleKey(String roleInTerritory) {
        if (roleInTerritory == 'Region Manager') {
            return 'NSM';
        }
        if (roleInTerritory == 'Area Manager' || roleInTerritory == 'ASM') {
            return 'ASM';
        }
        if (roleInTerritory == 'District Manager') {
            return 'DSM';
        }
        if (roleInTerritory == 'Brand Manager') {
            return 'BM';
        }
        return 'DSM';
    }

    public static Decimal coverageTargetForRole(String roleKey) {
        return KpiTargetService.targetFor(roleKey, 'Coverage');
    }

    public static Decimal repsAt90TargetForRole(String roleKey) {
        return KpiTargetService.targetFor(roleKey, 'Reps_At_90');
    }

    public static Decimal quizTargetForRole(String roleKey) {
        if (roleKey == 'MSR' || roleKey == 'CHC_MSR') {
            return KpiTargetService.targetFor(roleKey, 'Quiz');
        }
        return KpiTargetService.targetFor(roleKey, 'Quiz');
    }

    public static Decimal rightFrequencyTargetForRole(String roleKey) {
        return KpiTargetService.targetFor(roleKey, 'Right_Frequency');
    }

    public static Decimal salesAchievementTargetForRole(String roleKey) {
        return KpiTargetService.targetFor(roleKey, 'Sales_Achievement');
    }

    public static Decimal kolCoverageTargetForRole(String roleKey) {
        return KpiTargetService.targetFor(roleKey, 'KOL_Coverage');
    }

    public static Decimal dailyCallRateTargetForRole(String roleKey) {
        return KpiTargetService.targetFor(roleKey, 'Daily_Call_Rate');
    }

    public static Decimal fieldWorkingDaysTargetForRole(String roleKey) {
        return KpiTargetService.targetFor(roleKey, 'Field_Working_Days');
    }
}
