/**
 * Role-specific planned field days per Zeta Pharma KPI framework.
 * Denominator is working days after public holidays, TOT, and leave reductions.
 */
public with sharing class ZetaPlannedFieldDaysCalculator {
    public static Decimal plannedFieldDays(String roleKey, Decimal calendarWorkingDays) {
        Decimal cal = calendarWorkingDays == null ? 0 : calendarWorkingDays;
        if (cal <= 0) {
            return 0;
        }
        if (roleKey == 'ASM') {
            return 12;
        }
        if (roleKey == 'NSM') {
            return (cal * 0.30).setScale(0, System.RoundingMode.HALF_UP);
        }
        if (roleKey == 'CHC_SUPERVISOR') {
            return 18;
        }
        if (roleKey == 'BM') {
            return (cal * 0.20).setScale(0, System.RoundingMode.HALF_UP);
        }
        // DSM: 80% of available working days after holidays / TOT / leave (dry-run rule).
        return (cal * 0.80).setScale(0, System.RoundingMode.HALF_UP);
    }

    /**
     * Available days = calendar weekdays minus holidays minus counted TOT/leave days.
     */
    public static Decimal availableWorkingDays(
        Decimal calendarWorkingDays,
        Decimal holidayDays,
        Decimal totAndLeaveDays
    ) {
        Decimal cal = calendarWorkingDays == null ? 0 : calendarWorkingDays;
        Decimal holidays = holidayDays == null ? 0 : holidayDays;
        Decimal reductions = totAndLeaveDays == null ? 0 : totAndLeaveDays;
        Decimal available = cal - holidays - reductions;
        return available < 0 ? 0 : available;
    }

    public static Decimal plannedFieldDaysAfterReductions(
        String roleKey,
        Decimal calendarWorkingDays,
        Decimal holidayDays,
        Decimal totAndLeaveDays
    ) {
        return plannedFieldDays(
            roleKey,
            availableWorkingDays(calendarWorkingDays, holidayDays, totAndLeaveDays)
        );
    }

    public static Decimal fieldWorkingDaysPercent(
        Decimal daysWithActivities,
        Decimal plannedDays
    ) {
        if (plannedDays == null || plannedDays <= 0) {
            return null;
        }
        Decimal actual = daysWithActivities == null ? 0 : daysWithActivities;
        return (actual / plannedDays) * 100;
    }
}
