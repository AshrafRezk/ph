/**
 * Company public holidays from Public_Holiday__c, plus Salesforce standard Holiday rows.
 * Used by Class Engine capacity, time cards, and the Field planner calendar.
 */
public with sharing class PublicHolidayService {
    @TestVisible
    static List<Public_Holiday__c> testHolidays;
    private static List<Public_Holiday__c> cachedCustomHolidays;

    public class HolidayRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Date holidayDate;
        @AuraEnabled public Boolean recursYearly;
        @AuraEnabled public Boolean isActive;
    }

    @AuraEnabled
    public static List<HolidayRow> listHolidays() {
        List<HolidayRow> rows = new List<HolidayRow>();
        for (Public_Holiday__c record : [
            SELECT Id, Name, Holiday_Date__c, Recurs_Yearly__c, Is_Active__c
            FROM Public_Holiday__c
            WITH SYSTEM_MODE
            ORDER BY Holiday_Date__c ASC
            LIMIT 500
        ]) {
            rows.add(toRow(record));
        }
        return rows;
    }

    /**
     * Admin Console save. Takes plain values (no wrapper object) so nothing is lost between the
     * screen and the server, and accepts the date as yyyy-mm-dd or dd/mm/yyyy.
     */
    @AuraEnabled
    public static HolidayRow saveHolidayFields(
        Id holidayId,
        String name,
        String holidayDate,
        Boolean recursYearly,
        Boolean isActive
    ) {
        HolidayRow input = new HolidayRow();
        input.id = holidayId;
        input.name = name;
        input.holidayDate = parseHolidayDate(holidayDate);
        input.recursYearly = recursYearly == true;
        input.isActive = isActive != false;
        if (String.isBlank(name) && input.holidayDate == null) {
            throw PlannerUserMessage.aura('Enter the holiday name and pick its date.');
        }
        if (String.isBlank(name)) {
            throw PlannerUserMessage.aura('Enter the holiday name.');
        }
        if (input.holidayDate == null) {
            throw PlannerUserMessage.aura('Pick the holiday date from the calendar.');
        }
        return saveHoliday(input);
    }

    @TestVisible
    private static Date parseHolidayDate(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String value = raw.trim();
        try {
            if (Pattern.matches('\\d{4}-\\d{1,2}-\\d{1,2}.*', value)) {
                List<String> parts = value.left(10).split('-');
                return Date.newInstance(
                    Integer.valueOf(parts[0]),
                    Integer.valueOf(parts[1]),
                    Integer.valueOf(parts[2].left(2))
                );
            }
            if (Pattern.matches('\\d{1,2}[/.]\\d{1,2}[/.]\\d{4}', value)) {
                List<String> parts = value.split('[/.]');
                return Date.newInstance(
                    Integer.valueOf(parts[2]),
                    Integer.valueOf(parts[1]),
                    Integer.valueOf(parts[0])
                );
            }
        } catch (Exception ex) {
            return null;
        }
        return null;
    }

    @AuraEnabled
    public static HolidayRow saveHoliday(HolidayRow input) {
        if (input == null || input.holidayDate == null || String.isBlank(input.name)) {
            throw PlannerUserMessage.aura('Holiday name and date are required.');
        }
        Public_Holiday__c record;
        if (input.id == null) {
            record = new Public_Holiday__c();
        } else {
            List<Public_Holiday__c> existing = [
                SELECT Id
                FROM Public_Holiday__c
                WHERE Id = :input.id
                WITH USER_MODE
                LIMIT 1
            ];
            if (existing.isEmpty()) {
                throw PlannerUserMessage.aura('Holiday not found.');
            }
            record = existing[0];
        }
        // One holiday per date: block a second record on the same day (double click or re-entry).
        if (input.holidayDate != null) {
            Id selfId = input.id;
            List<Public_Holiday__c> sameDay = [
                SELECT Id, Name
                FROM Public_Holiday__c
                WHERE Holiday_Date__c = :input.holidayDate AND Id != :selfId
                LIMIT 1
            ];
            if (!sameDay.isEmpty()) {
                throw PlannerUserMessage.aura(sameDay[0].Name + ' is already set for that date.');
            }
            // A yearly holiday on the same day and month already covers this date.
            for (Public_Holiday__c yearly : [
                SELECT Id, Name, Holiday_Date__c
                FROM Public_Holiday__c
                WHERE Recurs_Yearly__c = TRUE AND Is_Active__c = TRUE AND Id != :selfId
                WITH SYSTEM_MODE
                LIMIT 500
            ]) {
                if (
                    yearly.Holiday_Date__c != null &&
                    yearly.Holiday_Date__c.month() == input.holidayDate.month() &&
                    yearly.Holiday_Date__c.day() == input.holidayDate.day()
                ) {
                    throw PlannerUserMessage.aura(
                        yearly.Name + ' already repeats every year on that date.'
                    );
                }
            }
        }
        record.Name = input.name.trim();
        record.Holiday_Date__c = input.holidayDate;
        record.Recurs_Yearly__c = input.recursYearly == true;
        record.Is_Active__c = input.isActive != false;
        cachedCustomHolidays = null;
        if (input.id == null) {
            insert as system record;
        } else {
            update as system record;
        }
        input.id = record.Id;
        return input;
    }

    @AuraEnabled
    public static void deleteHoliday(Id holidayId) {
        if (holidayId == null) {
            throw PlannerUserMessage.aura('Holiday Id is required.');
        }
        cachedCustomHolidays = null;
        delete as system [SELECT Id FROM Public_Holiday__c WHERE Id = :holidayId WITH SYSTEM_MODE];
    }

    private static List<HolidaySeed> egypt2026Seeds() {
        return new List<HolidaySeed>{
            new HolidaySeed(Date.newInstance(2026, 1, 7), 'Coptic Christmas'),
            new HolidaySeed(Date.newInstance(2026, 1, 25), 'Revolution Day'),
            new HolidaySeed(Date.newInstance(2026, 4, 25), 'Sinai Liberation Day'),
            new HolidaySeed(Date.newInstance(2026, 5, 1), 'Labour Day'),
            new HolidaySeed(Date.newInstance(2026, 6, 30), 'June 30 Revolution'),
            new HolidaySeed(Date.newInstance(2026, 10, 6), 'Armed Forces Day'),
            new HolidaySeed(Date.newInstance(2026, 12, 24), 'Christmas Eve')
        };
    }

    private static List<HolidaySeed> missingEgypt2026Seeds() {
        List<HolidaySeed> seeds = egypt2026Seeds();
        Set<Date> seedDates = new Set<Date>();
        for (HolidaySeed seed : seeds) {
            seedDates.add(seed.holidayDate);
        }
        Set<Date> existing = new Set<Date>();
        for (Public_Holiday__c row : [
            SELECT Holiday_Date__c
            FROM Public_Holiday__c
            WHERE Holiday_Date__c IN :seedDates
            WITH SYSTEM_MODE
        ]) {
            if (row.Holiday_Date__c != null) {
                existing.add(row.Holiday_Date__c);
            }
        }
        List<HolidaySeed> missing = new List<HolidaySeed>();
        for (HolidaySeed seed : seeds) {
            if (!existing.contains(seed.holidayDate)) {
                missing.add(seed);
            }
        }
        return missing;
    }

    /**
     * What "Load 2026 holidays" would add right now, so the screen can ask before inserting.
     */
    @AuraEnabled
    public static List<HolidayRow> previewEgypt2026Holidays() {
        List<HolidayRow> rows = new List<HolidayRow>();
        for (HolidaySeed seed : missingEgypt2026Seeds()) {
            HolidayRow row = new HolidayRow();
            row.name = seed.name;
            row.holidayDate = seed.holidayDate;
            row.recursYearly = false;
            row.isActive = true;
            rows.add(row);
        }
        return rows;
    }

    /**
     * Inserts fixed Egypt 2026 national holidays when that date is missing.
     * Movable religious dates are left for SFE to add on the same screen.
     */
    @AuraEnabled
    public static Integer loadEgypt2026Holidays() {
        List<Public_Holiday__c> toInsert = new List<Public_Holiday__c>();
        for (HolidaySeed seed : missingEgypt2026Seeds()) {
            toInsert.add(
                new Public_Holiday__c(
                    Name = seed.name,
                    Holiday_Date__c = seed.holidayDate,
                    Recurs_Yearly__c = false,
                    Is_Active__c = true
                )
            );
        }

        if (!toInsert.isEmpty()) {
            cachedCustomHolidays = null;
            insert as system toInsert;
        }
        return toInsert.size();
    }

    private class HolidaySeed {
        public Date holidayDate;
        public String name;

        public HolidaySeed(Date holidayDate, String name) {
            this.holidayDate = holidayDate;
            this.name = name;
        }
    }

    public static Set<Date> datesInRange(Date startDate, Date endDate) {
        Set<Date> dates = new Set<Date>();
        if (startDate == null || endDate == null || startDate > endDate) {
            return dates;
        }
        dates.addAll(standardHolidayDates(startDate, endDate));
        dates.addAll(customHolidayDates(startDate, endDate));
        return dates;
    }

    public static List<String> dateKeysInRange(Date startDate, Date endDate) {
        List<String> keys = new List<String>();
        List<Date> ordered = new List<Date>(datesInRange(startDate, endDate));
        ordered.sort();
        for (Date day : ordered) {
            keys.add(String.valueOf(day));
        }
        return keys;
    }

    public static Boolean isPublicHoliday(Date day) {
        if (day == null) {
            return false;
        }
        return datesInRange(day, day).contains(day);
    }

    public static Integer countAvailableWorkingDays(
        Date startDate,
        Date endDate,
        Set<Date> leaveDates
    ) {
        if (startDate == null || endDate == null || startDate > endDate) {
            return 0;
        }
        Set<Date> holidays = datesInRange(startDate, endDate);
        Integer count = 0;
        for (Date cursor = startDate; cursor <= endDate; cursor = cursor.addDays(1)) {
            if (!WorkingCalendarUtil.isWorkingDay(cursor)) {
                continue;
            }
            if (holidays.contains(cursor)) {
                continue;
            }
            if (leaveDates != null && leaveDates.contains(cursor)) {
                continue;
            }
            count++;
        }
        return count;
    }

    private static List<Public_Holiday__c> loadCustomHolidayRecords() {
        if (testHolidays != null) {
            return testHolidays;
        }
        if (cachedCustomHolidays == null) {
            cachedCustomHolidays = [
                SELECT Id, Name, Holiday_Date__c, Recurs_Yearly__c, Is_Active__c
                FROM Public_Holiday__c
                WHERE Holiday_Date__c != NULL
                WITH SYSTEM_MODE
                LIMIT 1000
            ];
        }
        return cachedCustomHolidays;
    }

    private static Set<Date> customHolidayDates(Date startDate, Date endDate) {
        Set<Date> dates = new Set<Date>();
        List<Public_Holiday__c> records = loadCustomHolidayRecords();
        for (Public_Holiday__c record : records) {
            if (record.Is_Active__c == false || record.Holiday_Date__c == null) {
                continue;
            }
            if (record.Recurs_Yearly__c == true) {
                for (Integer year = startDate.year(); year <= endDate.year(); year++) {
                    Date occurrence = Date.newInstance(
                        year,
                        record.Holiday_Date__c.month(),
                        record.Holiday_Date__c.day()
                    );
                    if (occurrence >= startDate && occurrence <= endDate) {
                        dates.add(occurrence);
                    }
                }
            } else if (record.Holiday_Date__c >= startDate && record.Holiday_Date__c <= endDate) {
                dates.add(record.Holiday_Date__c);
            }
        }
        return dates;
    }

    private static Set<Date> standardHolidayDates(Date startDate, Date endDate) {
        try {
            return EmployeeTimeCardFlowHelper.standardHolidayDatesInRange(startDate, endDate);
        } catch (Exception ex) {
            return new Set<Date>();
        }
    }

    private static HolidayRow toRow(Public_Holiday__c record) {
        HolidayRow row = new HolidayRow();
        row.id = record.Id;
        row.name = record.Name;
        row.holidayDate = record.Holiday_Date__c;
        row.recursYearly = record.Recurs_Yearly__c == true;
        row.isActive = record.Is_Active__c != false;
        return row;
    }
}