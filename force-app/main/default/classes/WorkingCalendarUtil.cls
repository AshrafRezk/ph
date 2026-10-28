public with sharing class WorkingCalendarUtil {
    // Working days for the current user. Prefer Admin Console Planner Rules;
    // else Working Calendar metadata; else Egypt Sat–Wed.
    private static Set<Integer> workingDaySet;
    @TestVisible
    private static Boolean acknowledgeWarnings = false;

    public static void clearWorkingDayCache() {
        workingDaySet = null;
    }

    public static void setAcknowledgeWarnings(Boolean value) {
        acknowledgeWarnings = value == true;
    }

    private static Set<Integer> getWorkingDaySet() {
        if (workingDaySet == null) {
            workingDaySet = new Set<Integer>();
            try {
                Set<Integer> fromRules = PlannerRulesService.workingDaySet();
                if (fromRules != null && !fromRules.isEmpty()) {
                    workingDaySet.addAll(fromRules);
                }
            } catch (Exception e) {
                // Planner rules unavailable — try metadata.
            }
            if (workingDaySet.isEmpty()) {
                try {
                    for (Integer d : WorkingCalendarService.getForCurrentUser().workingDays) {
                        workingDaySet.add(d);
                    }
                } catch (Exception e) {
                    // Metadata unavailable — fall back to the default below.
                }
            }
            if (workingDaySet.isEmpty()) {
                workingDaySet = new Set<Integer>{ 6, 0, 1, 2, 3 };
            }
        }
        return workingDaySet;
    }

    public static Boolean isWorkingDay(Date day) {
        if (day == null) {
            return false;
        }
        Datetime dt = Datetime.newInstance(day, Time.newInstance(12, 0, 0, 0));
        Integer isoDow = Integer.valueOf(dt.format('u')); // ISO: 1=Mon..7=Sun
        Integer jsDay = Math.mod(isoDow, 7); // Mon(1)->1 .. Sat(6)->6, Sun(7)->0
        return getWorkingDaySet().contains(jsDay);
    }

    public static Boolean isNonWorkingDay(Date day) {
        return !isWorkingDay(day);
    }

    public static Boolean isBlockedDay(Date day) {
        return isNonWorkingDay(day) || PublicHolidayService.isPublicHoliday(day);
    }

    public static void assertWorkingDay(DateTime startDateTime) {
        assertWorkingDayForUser(startDateTime, UserInfo.getUserId());
    }

    /**
     * Weekend and holiday rules of the given user (the visit's assigned rep), so a manager
     * planning for a rep is checked against the rep's Planner Rules, not their own.
     */
    public static void assertWorkingDayForUser(DateTime startDateTime, Id userId) {
        if (startDateTime == null) {
            return;
        }
        Id ruleUserId = userId == null ? UserInfo.getUserId() : userId;
        Date day = startDateTime.date();
        Boolean nonWorking = ruleUserId == UserInfo.getUserId()
            ? isNonWorkingDay(day)
            : !PlannerRulesService.isWorkingDayForUser(day, ruleUserId);
        if (nonWorking) {
            PlannerRulesService.enforceForUser(
                'Weekend',
                'Visits can only be scheduled on working days. Change the day or ask SFE to adjust Planner Rules weekends.',
                acknowledgeWarnings,
                ruleUserId
            );
        }
        if (PublicHolidayService.isPublicHoliday(day)) {
            PlannerRulesService.enforceForUser(
                'Visit_Holiday',
                'Visits cannot be scheduled on a public holiday. Choose another working day.',
                acknowledgeWarnings,
                ruleUserId
            );
        }
    }

    public static Date addWorkingDays(Date startDate, Integer workingDaysToAdd) {
        if (startDate == null || workingDaysToAdd == null || workingDaysToAdd <= 0) {
            return startDate;
        }
        Date cursor = startDate;
        Integer added = 0;
        while (added < workingDaysToAdd) {
            cursor = cursor.addDays(1);
            if (isWorkingDay(cursor)) {
                added++;
            }
        }
        return cursor;
    }

    public static final Integer DEFAULT_VALIDATION_DUE_WORKING_DAYS = 3;
}
