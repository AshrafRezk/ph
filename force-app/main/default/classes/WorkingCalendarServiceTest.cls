@IsTest
private class WorkingCalendarServiceTest {

    private static Working_Calendar__mdt fieldCal() {
        return new Working_Calendar__mdt(
            DeveloperName = 'Field',
            Label = 'Field',
            Working_Days__c = 'Sat,Sun,Mon,Tue,Wed',
            Week_Start_Day__c = 'Sat',
            Day_Start_Hour__c = 9,
            Day_End_Hour__c = 17,
            Is_Default__c = true
        );
    }

    private static Working_Calendar__mdt marketingCal() {
        return new Working_Calendar__mdt(
            DeveloperName = 'Marketing',
            Label = 'Marketing',
            Working_Days__c = 'Sun,Mon,Tue,Wed,Thu',
            Week_Start_Day__c = 'Sun',
            Day_Start_Hour__c = 8,
            Day_End_Hour__c = 16,
            Is_Default__c = false
        );
    }

    private static Map<String, Working_Calendar__mdt> calMap() {
        return new Map<String, Working_Calendar__mdt>{
            'Field' => fieldCal(),
            'Marketing' => marketingCal()
        };
    }

    @IsTest
    static void integrationResolvesForCurrentUser() {
        Test.startTest();
        WorkingCalendarService.WorkingCalendar wc = WorkingCalendarService.getForCurrentUser();
        Test.stopTest();
        System.assertNotEquals(null, wc);
        System.assert(!wc.workingDays.isEmpty());
        System.assertNotEquals(null, wc.dayStartHour);
        System.assertNotEquals(null, wc.dayEndHour);
        System.assertNotEquals(null, wc.weekStartDay);
    }

    @IsTest
    static void buildParsesMarketingCalendar() {
        WorkingCalendarService.WorkingCalendar wc = WorkingCalendarService.build(marketingCal());
        System.assertEquals('Marketing', wc.name);
        System.assertEquals(0, wc.weekStartDay, 'Sun week start');
        System.assertEquals(8, wc.dayStartHour);
        System.assertEquals(16, wc.dayEndHour);
        System.assert(wc.workingDays.contains(4), 'Thu working for Marketing');
        System.assert(!wc.workingDays.contains(6), 'Sat not working for Marketing');
    }

    @IsTest
    static void buildNullReturnsDefault() {
        WorkingCalendarService.WorkingCalendar wc = WorkingCalendarService.build(null);
        System.assertEquals('Field', wc.name);
        System.assertEquals(6, wc.weekStartDay);
        System.assertEquals(5, wc.workingDays.size());
    }

    @IsTest
    static void pickCalendarMatchesRoleByPriority() {
        List<Working_Calendar_Assignment__mdt> asgs = new List<Working_Calendar_Assignment__mdt>{
            new Working_Calendar_Assignment__mdt(
                Match_Type__c = 'Role', Match_Value__c = 'Marketing_Role',
                Calendar__c = 'Marketing', Priority__c = 5
            ),
            new Working_Calendar_Assignment__mdt(
                Match_Type__c = 'Role', Match_Value__c = 'Marketing_Role',
                Calendar__c = 'Field', Priority__c = 1
            )
        };
        Working_Calendar__mdt picked = WorkingCalendarService.pickCalendar(
            asgs, new Set<String>{ 'Marketing_Role' }, new Set<String>(), calMap()
        );
        System.assertEquals('Field', picked.DeveloperName, 'Lowest priority wins');
    }

    @IsTest
    static void pickCalendarMatchesTerritory() {
        List<Working_Calendar_Assignment__mdt> asgs = new List<Working_Calendar_Assignment__mdt>{
            new Working_Calendar_Assignment__mdt(
                Match_Type__c = 'Territory', Match_Value__c = 'T_North',
                Calendar__c = 'Marketing', Priority__c = 1
            )
        };
        Working_Calendar__mdt picked = WorkingCalendarService.pickCalendar(
            asgs, new Set<String>(), new Set<String>{ 'T_North' }, calMap()
        );
        System.assertEquals('Marketing', picked.DeveloperName);
    }

    @IsTest
    static void pickCalendarFallsBackToDefault() {
        Working_Calendar__mdt picked = WorkingCalendarService.pickCalendar(
            new List<Working_Calendar_Assignment__mdt>(),
            new Set<String>{ 'Nobody' }, new Set<String>(), calMap()
        );
        System.assertEquals('Field', picked.DeveloperName, 'Default calendar');
    }

    @IsTest
    static void workingCalendarUtilRespectsDays() {
        // 2026-09-05 is a Saturday (working); 2026-09-03 a Thursday (non-working) by default.
        Date sat = Date.newInstance(2026, 9, 5);
        Date thu = Date.newInstance(2026, 9, 3);
        System.assert(WorkingCalendarUtil.isWorkingDay(sat), 'Sat is working');
        System.assert(WorkingCalendarUtil.isNonWorkingDay(thu), 'Thu is non-working');
        System.assertEquals(false, WorkingCalendarUtil.isWorkingDay(null));

        Boolean threw = false;
        try {
            WorkingCalendarUtil.assertWorkingDay(
                Datetime.newInstance(thu, Time.newInstance(10, 0, 0, 0))
            );
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Non-working day should throw');
        WorkingCalendarUtil.assertWorkingDay(Datetime.newInstance(sat, Time.newInstance(10, 0, 0, 0)));
        WorkingCalendarUtil.assertWorkingDay(null);

        Date added = WorkingCalendarUtil.addWorkingDays(sat, 3);
        System.assert(WorkingCalendarUtil.isWorkingDay(added), 'Result lands on a working day');
        System.assertEquals(sat, WorkingCalendarUtil.addWorkingDays(sat, 0));
    }
}