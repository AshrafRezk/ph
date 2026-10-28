@IsTest
private class WorkingCalendarUtilTest {
    @IsTest
    static void workingDays_matchSatThroughWed() {
        System.assertEquals(true, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 22))); // Sat
        System.assertEquals(true, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 23))); // Sun
        System.assertEquals(true, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 24))); // Mon
        System.assertEquals(true, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 25))); // Tue
        System.assertEquals(true, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 26))); // Wed
        System.assertEquals(false, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 27))); // Thu
        System.assertEquals(false, WorkingCalendarUtil.isWorkingDay(Date.newInstance(2026, 8, 28))); // Fri
    }

    @IsTest
    static void addWorkingDays_skipsThuFri() {
        Date result = WorkingCalendarUtil.addWorkingDays(Date.newInstance(2026, 8, 26), 1); // Wed +1 => Sat
        System.assertEquals(Date.newInstance(2026, 8, 29), result);
    }

    @IsTest
    static void assertWorkingDay_allowsWhenWeekendPolicyAllow() {
        PlannerRulesService.Rule input = new PlannerRulesService.Rule();
        input.workingDays = 'SAT,SUN,MON,TUE,WED';
        input.weekendPlanning = PlannerRulesService.ALLOW;
        input.visitHolidayOverlap = PlannerRulesService.ALLOW;
        input.visitTotOverlap = PlannerRulesService.BLOCK;
        input.visitVisitOverlap = PlannerRulesService.BLOCK;
        input.visitMeetingOverlap = PlannerRulesService.BLOCK;
        input.totMeetingOverlap = PlannerRulesService.WARN;
        input.meetingHolidayOverlap = PlannerRulesService.WARN;
        PlannerRulesService.saveRule(input);
        WorkingCalendarUtil.clearWorkingDayCache();

        Date thursday = Date.newInstance(2026, 8, 27);
        System.assertEquals(true, WorkingCalendarUtil.isNonWorkingDay(thursday));
        System.assertEquals(false, WorkingCalendarUtil.isBlockedDay(Date.newInstance(2026, 8, 22)));

        WorkingCalendarUtil.setAcknowledgeWarnings(false);
        WorkingCalendarUtil.assertWorkingDay(
            Datetime.newInstance(thursday, Time.newInstance(10, 0, 0, 0))
        );
        WorkingCalendarUtil.setAcknowledgeWarnings(true);
        WorkingCalendarUtil.assertWorkingDay(
            Datetime.newInstance(thursday, Time.newInstance(10, 0, 0, 0))
        );
        WorkingCalendarUtil.setAcknowledgeWarnings(false);
        System.assertEquals(null, WorkingCalendarUtil.addWorkingDays(null, 1));
        System.assertEquals(
            Date.newInstance(2026, 8, 22),
            WorkingCalendarUtil.addWorkingDays(Date.newInstance(2026, 8, 22), 0)
        );
    }
}