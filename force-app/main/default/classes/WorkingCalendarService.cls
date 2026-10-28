/**
 * Resolves the working calendar (working days, week start, working hours) for the
 * current user based on Working Calendar Assignment metadata (by Role or
 * Territory), falling back to the default calendar. Admin-configurable via the
 * Working_Calendar__mdt / Working_Calendar_Assignment__mdt custom metadata.
 */
public with sharing class WorkingCalendarService {
    private static final Map<String, Integer> DAY_TOKENS = new Map<String, Integer>{
        'SUN' => 0, 'MON' => 1, 'TUE' => 2, 'WED' => 3, 'THU' => 4, 'FRI' => 5, 'SAT' => 6
    };

    public class WorkingCalendar {
        @AuraEnabled public String name;
        @AuraEnabled public List<Integer> workingDays; // getDay(): Sun=0..Sat=6
        @AuraEnabled public Integer weekStartDay;
        @AuraEnabled public Integer dayStartHour;
        @AuraEnabled public Integer dayEndHour;
    }

    @AuraEnabled(cacheable=true)
    public static WorkingCalendar getForCurrentUser() {
        return build(resolveCalendar());
    }

    private static Working_Calendar__mdt resolveCalendar() {
        Set<String> roleValues = new Set<String>();
        Set<String> territoryValues = new Set<String>();

        for (User u : [
            SELECT UserRole.DeveloperName FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ]) {
            if (u.UserRole != null && u.UserRole.DeveloperName != null) {
                roleValues.add(u.UserRole.DeveloperName);
            }
        }
        try {
            for (UserTerritory2Association a : [
                SELECT Territory2.DeveloperName FROM UserTerritory2Association
                WHERE UserId = :UserInfo.getUserId()
            ]) {
                if (a.Territory2 != null && a.Territory2.DeveloperName != null) {
                    territoryValues.add(a.Territory2.DeveloperName);
                }
            }
        } catch (Exception e) {
            // Territory management may be disabled — role/default still apply.
        }

        return pickCalendar(
            Working_Calendar_Assignment__mdt.getAll().values(),
            roleValues,
            territoryValues,
            Working_Calendar__mdt.getAll()
        );
    }

    // Pure resolution logic (testable): first matching assignment by Role/Territory
    // (lowest Priority wins), else the default calendar, else the first available.
    @TestVisible
    private static Working_Calendar__mdt pickCalendar(
        List<Working_Calendar_Assignment__mdt> assignments,
        Set<String> roleValues,
        Set<String> territoryValues,
        Map<String, Working_Calendar__mdt> calendars
    ) {
        Working_Calendar_Assignment__mdt best;
        for (Working_Calendar_Assignment__mdt asg : assignments) {
            Boolean matches =
                (asg.Match_Type__c == 'Role' && roleValues.contains(asg.Match_Value__c)) ||
                (asg.Match_Type__c == 'Territory' && territoryValues.contains(asg.Match_Value__c));
            if (!matches) {
                continue;
            }
            if (best == null) {
                best = asg;
            } else {
                Decimal a = asg.Priority__c == null ? 999 : asg.Priority__c;
                Decimal b = best.Priority__c == null ? 999 : best.Priority__c;
                if (a < b) {
                    best = asg;
                }
            }
        }

        if (best != null) {
            for (Working_Calendar__mdt c : calendars.values()) {
                if (c.DeveloperName == best.Calendar__c) {
                    return c;
                }
            }
        }
        for (Working_Calendar__mdt c : calendars.values()) {
            if (c.Is_Default__c == true) {
                return c;
            }
        }
        return calendars.isEmpty() ? null : calendars.values()[0];
    }

    @TestVisible
    private static WorkingCalendar build(Working_Calendar__mdt c) {
        WorkingCalendar wc = new WorkingCalendar();
        // Safe default: BRD field week (Sat–Wed, 9–17).
        wc.name = 'Field';
        wc.workingDays = new List<Integer>{ 6, 0, 1, 2, 3 };
        wc.weekStartDay = 6;
        wc.dayStartHour = 9;
        wc.dayEndHour = 17;
        if (c == null) {
            return wc;
        }
        wc.name = c.Label;
        List<Integer> days = new List<Integer>();
        if (c.Working_Days__c != null) {
            for (String token : c.Working_Days__c.split(',')) {
                Integer d = DAY_TOKENS.get(token.trim().toUpperCase().left(3));
                if (d != null) {
                    days.add(d);
                }
            }
        }
        if (!days.isEmpty()) {
            wc.workingDays = days;
        }
        if (c.Week_Start_Day__c != null) {
            Integer w = DAY_TOKENS.get(c.Week_Start_Day__c.trim().toUpperCase().left(3));
            if (w != null) {
                wc.weekStartDay = w;
            }
        }
        if (c.Day_Start_Hour__c != null) {
            wc.dayStartHour = Integer.valueOf(c.Day_Start_Hour__c);
        }
        if (c.Day_End_Hour__c != null) {
            wc.dayEndHour = Integer.valueOf(c.Day_End_Hour__c);
        }
        return wc;
    }
}