/**
 * Invocable helper for Employee Time Card flows (dates in month).
 * Shared TOT recalc for day entries (TimeOffRequestTOTRecalc / TimeOffRequestTOTRecalcByRange).
 * Span Type Partial (Hours) (API Hours): adds Span_Duration__c/8 on the start date only.
 * Span Type Full Day (API Full_Day): adds 1 per working day from start, based on Span_Duration__c.
 * Legacy Days: adds 1 per calendar day in [start..end] inclusive.
 * Legacy records (no Span_Type__c): falls back to date-range overlap with +1 per day.
 */
public with sharing class EmployeeTimeCardFlowHelper {

    public static void recalcTOTForEmployeeAndRange(Id employeeId, Date startDate, Date endDate) {
        if (employeeId == null || startDate == null || endDate == null || startDate > endDate) {
            return;
        }
        List<Employee_Time_Card_Day_Entry__c> entries = [
            SELECT Id, Date__c, Employee_Time_Card__c, Employee_Time_Card__r.Employee__c,
                TOT_Days__c, TOT_Days_Excluding_Weekends__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__r.Employee__c = :employeeId
            AND Date__c >= :startDate
            AND Date__c <= :endDate
        ];
        DateTime rangeStartDt = DateTime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
        DateTime rangeEndDt = DateTime.newInstance(endDate, Time.newInstance(23, 59, 59, 0));
        List<Time_Off_Request__c> approved = [
            SELECT Id, CreatedById, OwnerId, Start_Date_Time__c, End_Date_Time__c, Span_Type__c, Span_Duration__c
            FROM Time_Off_Request__c
            WHERE Stage__c = 'Approved'
            AND Start_Date_Time__c <= :rangeEndDt
            AND End_Date_Time__c >= :rangeStartDt
            AND (CreatedById = :employeeId OR OwnerId = :employeeId)
        ];
        Map<Date, Decimal> totByDate = new Map<Date, Decimal>();
        Map<Date, Decimal> totWeekdayByDate = new Map<Date, Decimal>();
        for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
            totByDate.put(d, 0);
            totWeekdayByDate.put(d, 0);
        }
        String department = getEmployeeDepartment(employeeId);
        accumulateFromApprovedRequests(approved, startDate, endDate, totByDate, totWeekdayByDate, department);
        Set<Id> affectedTimeCards = new Set<Id>();
        for (Employee_Time_Card_Day_Entry__c e : entries) {
            Decimal tot = totByDate.get(e.Date__c);
            Decimal totW = totWeekdayByDate.get(e.Date__c);
            if (tot != null && e.TOT_Days__c != tot) {
                e.TOT_Days__c = tot;
            }
            if (totW != null && e.TOT_Days_Excluding_Weekends__c != totW) {
                e.TOT_Days_Excluding_Weekends__c = totW;
            }
            if (e.Employee_Time_Card__c != null) {
                affectedTimeCards.add(e.Employee_Time_Card__c);
            }
        }
        if (!entries.isEmpty()) {
            update entries;
        }
        if (!affectedTimeCards.isEmpty()) {
            EmployeeTimeCardService.reapplyCallTargets(affectedTimeCards);
            EmployeeTimeCardMetricsService.recalcTimeCardRollups(affectedTimeCards);
        }
        Set<Date> monthStarts = new Set<Date>();
        Date cursor = startDate.toStartOfMonth();
        Date lastMonth = endDate.toStartOfMonth();
        while (cursor <= lastMonth) {
            monthStarts.add(cursor);
            cursor = cursor.addMonths(1);
        }
        for (Date monthStart : monthStarts) {
            EmployeeTimeCardMetricsService.recalcMonthlyKpis(new Set<Id>{ employeeId }, monthStart);
        }
    }

    /**
     * Leave-type TOT weekday portions by date plus rounded total.
     * Leave types: Sick Leave, Annual Vacation, Holiday, Conference.
     */
    public static LeaveTotals calculateLeaveTotals(
        Id employeeId,
        Date monthStart,
        Date monthEnd,
        String department
    ) {
        LeaveTotals result = new LeaveTotals();
        if (employeeId == null || monthStart == null || monthEnd == null || monthStart > monthEnd) {
            return result;
        }
        Set<Date> weekdays = weekdaysInRange(monthStart, monthEnd, department);
        for (Date day : weekdays) {
            result.leaveByDate.put(day, 0);
        }

        DateTime startDt = DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
        List<Time_Off_Request__c> approved = [
            SELECT Type__c, Span_Duration__c, Span_Type__c, Start_Date_Time__c, End_Date_Time__c
            FROM Time_Off_Request__c
            WHERE Stage__c = 'Approved'
            AND Start_Date_Time__c <= :endDt
            AND End_Date_Time__c >= :startDt
            AND (CreatedById = :employeeId OR OwnerId = :employeeId)
        ];

        Decimal total = 0;
        for (Time_Off_Request__c tot : approved) {
            if (!isLeaveTotType(tot.Type__c)) {
                continue;
            }
            Map<Date, Decimal> totByDate = new Map<Date, Decimal>();
            Map<Date, Decimal> totWeekdayByDate = new Map<Date, Decimal>();
            for (Date day = monthStart; day <= monthEnd; day = day.addDays(1)) {
                totByDate.put(day, 0);
                totWeekdayByDate.put(day, 0);
            }
            accumulateFromApprovedRequests(
                new List<Time_Off_Request__c>{ tot },
                monthStart,
                monthEnd,
                totByDate,
                totWeekdayByDate,
                department
            );
            for (Date day : weekdays) {
                Decimal amount = totWeekdayByDate.get(day);
                if (amount == null || amount <= 0) {
                    continue;
                }
                result.leaveByDate.put(day, result.leaveByDate.get(day) + amount);
                total += amount;
            }
        }
        result.totalLeaveDays = total.setScale(1, System.RoundingMode.HALF_UP);
        return result;
    }

    public class LeaveTotals {
        public Decimal totalLeaveDays = 0;
        public Map<Date, Decimal> leaveByDate = new Map<Date, Decimal>();
    }

    public static void recalcDayDefinitionsForEmployeeAndRange(Id employeeId, Date startDate, Date endDate) {
        if (employeeId == null || startDate == null || endDate == null || startDate > endDate) {
            return;
        }
        String department = getEmployeeDepartment(employeeId);
        List<Employee_Time_Card_Day_Entry__c> entries = [
            SELECT Id, Date__c, Day_Definition__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__r.Employee__c = :employeeId
            AND Date__c >= :startDate
            AND Date__c <= :endDate
        ];
        for (Employee_Time_Card_Day_Entry__c e : entries) {
            String definition = getDayDefinition(e.Date__c, department);
            if (e.Day_Definition__c != definition) {
                e.Day_Definition__c = definition;
            }
        }
        if (!entries.isEmpty()) {
            update entries;
        }
    }

    public static String getDayDefinition(Date d, String department) {
        return isWeekendDay(d, department) ? 'Weekend Day' : 'Weekday';
    }

    public static String getEmployeeDepartment(Id employeeId) {
        List<User> users = [SELECT Department FROM User WHERE Id = :employeeId LIMIT 1];
        return users.isEmpty() ? null : users[0].Department;
    }

    public static void accumulateFromApprovedRequests(
        List<Time_Off_Request__c> approved,
        Date startDate,
        Date endDate,
        Map<Date, Decimal> totByDate,
        Map<Date, Decimal> totWeekdayByDate,
        String department
    ) {
        if (approved == null) {
            return;
        }
        for (Time_Off_Request__c req : approved) {
            if (req.Start_Date_Time__c == null || req.End_Date_Time__c == null) {
                continue;
            }
            Date reqStartDate = req.Start_Date_Time__c.date();
            Date reqEndDate = req.End_Date_Time__c.date();
            if (req.Span_Type__c == 'Hours' && req.Span_Duration__c != null) {
                Decimal inc = req.Span_Duration__c / 8.0;
                for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
                    if (d == reqStartDate) {
                        totByDate.put(d, totByDate.get(d) + inc);
                        if (!isWeekendDay(d, department)) {
                            totWeekdayByDate.put(d, totWeekdayByDate.get(d) + inc);
                        }
                    }
                }
            } else if (req.Span_Type__c == 'Full_Day') {
                Integer remaining = req.Span_Duration__c == null ? 0 : req.Span_Duration__c.intValue();
                Date cursor = reqStartDate;
                while (remaining > 0) {
                    if (!isWeekendDay(cursor, department)) {
                        if (cursor >= startDate && cursor <= endDate) {
                            totByDate.put(cursor, totByDate.get(cursor) + 1);
                            totWeekdayByDate.put(cursor, totWeekdayByDate.get(cursor) + 1);
                        }
                        remaining--;
                    }
                    cursor = cursor.addDays(1);
                }
            } else if (req.Span_Type__c == 'Days') {
                for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
                    if (d >= reqStartDate && d <= reqEndDate) {
                        totByDate.put(d, totByDate.get(d) + 1);
                        if (!isWeekendDay(d, department)) {
                            totWeekdayByDate.put(d, totWeekdayByDate.get(d) + 1);
                        }
                    }
                }
            } else {
                for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
                    if (req.Start_Date_Time__c.date() <= d && req.End_Date_Time__c.date() >= d) {
                        totByDate.put(d, totByDate.get(d) + 1);
                        if (!isWeekendDay(d, department)) {
                            totWeekdayByDate.put(d, totWeekdayByDate.get(d) + 1);
                        }
                    }
                }
            }
        }
    }

    /**
     * Weekend days come from Planner Rules, the same source the planner uses:
     * AM = Fri+Sat, PM = Thu+Fri, otherwise the Org planner rule (Thu+Fri unless SFE changed it).
     */
    public static Boolean isWeekendDay(Date d, String department) {
        return PlannerRulesService.isWeekendDay(d, department);
    }

    public static Boolean isLeaveTotType(String typeValue) {
        return typeValue == 'Sick Leave'
            || typeValue == 'Annual Vacation'
            || typeValue == 'Holiday'
            || typeValue == 'Conference';
    }

    public static Set<Date> weekdaysInRange(Date startDate, Date endDate, String department) {
        Set<Date> days = new Set<Date>();
        if (startDate == null || endDate == null || startDate > endDate) {
            return days;
        }
        for (Date cursor = startDate; cursor <= endDate; cursor = cursor.addDays(1)) {
            if (!isWeekendDay(cursor, department)) {
                days.add(cursor);
            }
        }
        return days;
    }

    public static Set<Date> publicHolidayDatesInRange(Date startDate, Date endDate) {
        return PublicHolidayService.datesInRange(startDate, endDate);
    }

    public static Set<Date> standardHolidayDatesInRange(Date startDate, Date endDate) {
        Set<Date> dates = new Set<Date>();
        if (startDate == null || endDate == null || startDate > endDate) {
            return dates;
        }
        for (Holiday holiday : loadCompanyHolidays()) {
            dates.addAll(expandHoliday(holiday, startDate, endDate));
        }
        return dates;
    }

    public static Integer countFieldDays(
        Date startDate,
        Date endDate,
        String department,
        Map<Date, Decimal> leaveByDate
    ) {
        Set<Date> weekdays = weekdaysInRange(startDate, endDate, department);
        Set<Date> holidays = publicHolidayDatesInRange(startDate, endDate);
        Decimal remaining = 0;
        for (Date day : weekdays) {
            if (holidays.contains(day)) {
                continue;
            }
            Decimal leave = 0;
            if (leaveByDate != null && leaveByDate.containsKey(day) && leaveByDate.get(day) != null) {
                leave = leaveByDate.get(day);
            }
            remaining += Math.max(0, 1 - leave);
        }
        return remaining.setScale(0, System.RoundingMode.HALF_UP).intValue();
    }

    private static List<Holiday> cachedCompanyHolidays;

    private static List<Holiday> loadCompanyHolidays() {
        if (cachedCompanyHolidays == null) {
            cachedCompanyHolidays = [
                SELECT
                    ActivityDate,
                    IsRecurrence,
                    RecurrenceType,
                    RecurrenceStartDate,
                    RecurrenceEndDateOnly,
                    RecurrenceInterval,
                    RecurrenceDayOfWeekMask,
                    RecurrenceDayOfMonth,
                    RecurrenceInstance,
                    RecurrenceMonthOfYear
                FROM Holiday
            ];
        }
        return cachedCompanyHolidays;
    }

    @TestVisible
    static Set<Date> expandHoliday(Holiday holiday, Date startDate, Date endDate) {
        Set<Date> dates = new Set<Date>();
        if (holiday == null) {
            return dates;
        }
        if (holiday.IsRecurrence != true) {
            if (holiday.ActivityDate != null && holiday.ActivityDate >= startDate && holiday.ActivityDate <= endDate) {
                dates.add(holiday.ActivityDate);
            }
            return dates;
        }
        Date recurStart = holiday.RecurrenceStartDate != null ? holiday.RecurrenceStartDate : startDate;
        Date recurEnd = holiday.RecurrenceEndDateOnly != null ? holiday.RecurrenceEndDateOnly : endDate;
        Date windowStart = startDate > recurStart ? startDate : recurStart;
        Date windowEnd = endDate < recurEnd ? endDate : recurEnd;
        if (windowStart > windowEnd) {
            return dates;
        }
        String recurType = holiday.RecurrenceType;
        if (recurType == 'RecursYearly' || recurType == 'RecursYearlyNth') {
            for (Integer year = windowStart.year(); year <= windowEnd.year(); year++) {
                Date occurrence = yearlyHolidayDate(holiday, year);
                if (occurrence != null && occurrence >= windowStart && occurrence <= windowEnd) {
                    dates.add(occurrence);
                }
            }
        } else if (recurType == 'RecursMonthly' || recurType == 'RecursMonthlyNth') {
            Date cursor = Date.newInstance(windowStart.year(), windowStart.month(), 1);
            Date lastMonth = Date.newInstance(windowEnd.year(), windowEnd.month(), 1);
            while (cursor <= lastMonth) {
                Date occurrence = monthlyHolidayDate(holiday, cursor.year(), cursor.month());
                if (occurrence != null && occurrence >= windowStart && occurrence <= windowEnd) {
                    dates.add(occurrence);
                }
                cursor = cursor.addMonths(1);
            }
        } else {
            Integer interval = holiday.RecurrenceInterval == null || holiday.RecurrenceInterval < 1
                ? 1
                : holiday.RecurrenceInterval;
            for (Date cursor = recurStart; cursor <= windowEnd; cursor = cursor.addDays(interval)) {
                if (cursor >= windowStart && matchesRecurrenceMask(holiday, cursor)) {
                    dates.add(cursor);
                }
            }
        }
        return dates;
    }

    private static Date yearlyHolidayDate(Holiday holiday, Integer year) {
        Integer month = monthFromName(holiday.RecurrenceMonthOfYear);
        if (month == null) {
            month = holiday.RecurrenceStartDate != null ? holiday.RecurrenceStartDate.month() : null;
        }
        if (month == null) {
            return null;
        }
        if (holiday.RecurrenceType == 'RecursYearlyNth') {
            return nthWeekdayInMonth(year, month, holiday.RecurrenceInstance, holiday.RecurrenceDayOfWeekMask);
        }
        Integer day = holiday.RecurrenceDayOfMonth;
        if (day == null && holiday.RecurrenceStartDate != null) {
            day = holiday.RecurrenceStartDate.day();
        }
        if (day == null) {
            return null;
        }
        Integer lastDay = Date.newInstance(year, month, 1).addMonths(1).addDays(-1).day();
        return Date.newInstance(year, month, Math.min(day, lastDay));
    }

    private static Date monthlyHolidayDate(Holiday holiday, Integer year, Integer month) {
        if (holiday.RecurrenceType == 'RecursMonthlyNth') {
            return nthWeekdayInMonth(year, month, holiday.RecurrenceInstance, holiday.RecurrenceDayOfWeekMask);
        }
        Integer day = holiday.RecurrenceDayOfMonth;
        if (day == null) {
            return null;
        }
        Integer lastDay = Date.newInstance(year, month, 1).addMonths(1).addDays(-1).day();
        return Date.newInstance(year, month, Math.min(day, lastDay));
    }

    private static Date nthWeekdayInMonth(Integer year, Integer month, String instance, Integer dayOfWeekMask) {
        Date first = Date.newInstance(year, month, 1);
        Date last = first.addMonths(1).addDays(-1);
        List<Date> matches = new List<Date>();
        for (Date cursor = first; cursor <= last; cursor = cursor.addDays(1)) {
            if (matchesDayOfWeekMask(cursor, dayOfWeekMask)) {
                matches.add(cursor);
            }
        }
        if (matches.isEmpty()) {
            return null;
        }
        if (instance == 'Last') {
            return matches[matches.size() - 1];
        }
        Integer index = instance == 'Second' ? 1 : instance == 'Third' ? 2 : instance == 'Fourth' ? 3 : 0;
        return index < matches.size() ? matches[index] : null;
    }

    private static Boolean matchesRecurrenceMask(Holiday holiday, Date day) {
        if (holiday.RecurrenceDayOfWeekMask == null) {
            return true;
        }
        return matchesDayOfWeekMask(day, holiday.RecurrenceDayOfWeekMask);
    }

    private static Boolean matchesDayOfWeekMask(Date day, Integer mask) {
        if (mask == null) {
            return false;
        }
        return (mask & (1 << dayOfWeekIndex(day))) != 0;
    }

    private static Integer dayOfWeekIndex(Date d) {
        Integer dayOfWeek = Math.mod(Date.newInstance(2000, 1, 2).daysBetween(d), 7);
        if (dayOfWeek < 0) {
            dayOfWeek += 7;
        }
        return dayOfWeek;
    }

    private static Integer monthFromName(String monthName) {
        if (String.isBlank(monthName)) {
            return null;
        }
        Map<String, Integer> months = new Map<String, Integer>{
            'January' => 1,
            'February' => 2,
            'March' => 3,
            'April' => 4,
            'May' => 5,
            'June' => 6,
            'July' => 7,
            'August' => 8,
            'September' => 9,
            'October' => 10,
            'November' => 11,
            'December' => 12
        };
        return months.get(monthName);
    }

    public class GetDatesInMonthRequest {
        @InvocableVariable(required=true label='Target Year')
        public Integer targetYear;
        @InvocableVariable(required=true label='Target Month')
        public Integer targetMonth;
    }

    public class GetDatesInMonthResult {
        @InvocableVariable(label='Date')
        public Date dateValue;
    }

    @InvocableMethod(label='Get Dates In Month' description='Returns all dates in the given month for time card day entry creation.')
    public static List<List<GetDatesInMonthResult>> getDatesInMonth(List<GetDatesInMonthRequest> requests) {
        List<List<GetDatesInMonthResult>> results = new List<List<GetDatesInMonthResult>>();
        for (GetDatesInMonthRequest req : requests) {
            List<GetDatesInMonthResult> listResult = new List<GetDatesInMonthResult>();
            if (req.targetYear == null || req.targetMonth == null) {
                results.add(listResult);
                continue;
            }
            Date firstDay = Date.newInstance(req.targetYear, req.targetMonth, 1);
            Integer daysInMonth = firstDay.addMonths(1).addDays(-1).day();
            for (Integer d = 1; d <= daysInMonth; d++) {
                GetDatesInMonthResult r = new GetDatesInMonthResult();
                r.dateValue = Date.newInstance(req.targetYear, req.targetMonth, d);
                listResult.add(r);
            }
            results.add(listResult);
        }
        return results;
    }
}