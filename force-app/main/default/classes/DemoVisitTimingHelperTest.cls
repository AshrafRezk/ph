@IsTest
private class DemoVisitTimingHelperTest {

    @IsTest
    static void buildSlot_spacesVisitsAcrossDaysAndTime() {
        List<Date> days = new List<Date>{
            Date.newInstance(2026, 2, 2),
            Date.newInstance(2026, 2, 3)
        };

        DemoVisitTimingHelper.VisitSlot first = DemoVisitTimingHelper.buildSlot(days, 0);
        DemoVisitTimingHelper.VisitSlot second = DemoVisitTimingHelper.buildSlot(days, 1);
        DemoVisitTimingHelper.VisitSlot third = DemoVisitTimingHelper.buildSlot(days, 2);

        System.assertNotEquals(first.visitDay, second.visitDay);
        System.assertEquals(first.visitDay, third.visitDay);
        System.assert(first.startDateTime < first.endDateTime);
        System.assert(third.startDateTime >= first.endDateTime.addMinutes(20));
    }

    @IsTest
    static void buildSlotOnDay_stacksWithGapOnSameDay() {
        Date day = Date.newInstance(2026, 2, 10);
        DemoVisitTimingHelper.VisitSlot a = DemoVisitTimingHelper.buildSlotOnDay(day, 0, 0);
        DemoVisitTimingHelper.VisitSlot b = DemoVisitTimingHelper.buildSlotOnDay(day, 1, 1);

        System.assertEquals(day, a.visitDay);
        System.assertEquals(day, b.visitDay);
        System.assert(b.startDateTime >= a.endDateTime.addMinutes(20));
    }

    @IsTest
    static void buildSeedSlot_fitsHighVolumeMonths() {
        List<Date> days = new List<Date>();
        for (Integer i = 0; i < 20; i++) {
            days.add(Date.newInstance(2026, 2, 2 + i));
        }

        DemoVisitTimingHelper.VisitSlot slot = DemoVisitTimingHelper.buildSeedSlot(days, 168, 169);
        System.assertNotEquals(null, slot);
        System.assertNotEquals(null, slot.startDateTime);
    }
}
