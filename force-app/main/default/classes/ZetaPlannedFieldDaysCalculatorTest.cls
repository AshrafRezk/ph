@IsTest
private class ZetaPlannedFieldDaysCalculatorTest {
    @IsTest
    static void plannedFieldDaysByRole() {
        System.assertEquals(12, ZetaPlannedFieldDaysCalculator.plannedFieldDays('ASM', 20));
        System.assertEquals(6, ZetaPlannedFieldDaysCalculator.plannedFieldDays('NSM', 20));
        System.assertEquals(18, ZetaPlannedFieldDaysCalculator.plannedFieldDays('CHC_SUPERVISOR', 20));
        System.assertEquals(4, ZetaPlannedFieldDaysCalculator.plannedFieldDays('BM', 20));
        // DSM planned field days = 80% of available working days (20 * 0.8 = 16).
        System.assertEquals(16, ZetaPlannedFieldDaysCalculator.plannedFieldDays('DSM', 20));
        System.assertEquals(0, ZetaPlannedFieldDaysCalculator.plannedFieldDays('DSM', 0));
        System.assertEquals(0, ZetaPlannedFieldDaysCalculator.plannedFieldDays('DSM', null));
        System.assertEquals(17, ZetaPlannedFieldDaysCalculator.availableWorkingDays(20, 2, 1));
        System.assertEquals(0, ZetaPlannedFieldDaysCalculator.availableWorkingDays(2, 5, 0));
        System.assertEquals(
            16,
            ZetaPlannedFieldDaysCalculator.plannedFieldDaysAfterReductions('DSM', 22, 1, 1)
        );
        System.assertEquals(50, ZetaPlannedFieldDaysCalculator.fieldWorkingDaysPercent(10, 20));
        System.assertEquals(null, ZetaPlannedFieldDaysCalculator.fieldWorkingDaysPercent(10, 0));
        System.assertEquals(null, ZetaPlannedFieldDaysCalculator.fieldWorkingDaysPercent(10, null));
    }
}
