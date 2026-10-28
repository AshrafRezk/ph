/**
 * Plan assistant for a draft meeting, built only from this org's own meeting history (no AI model):
 * which HCPs to invite, which services and vendors similar meetings used, and the usual budget.
 * Without sharing so the history covers every past meeting; it only returns rankings and aggregates
 * to the meeting owner.
 */
public without sharing class MeetingPlanAssistant {
    @TestVisible static final Integer MAX_INVITEES = 15;
    @TestVisible static final Integer SIMILAR_LIMIT = 20;
    static final Integer MIN_SIMILAR = 3;
    static final Set<String> PAST_STATUSES = new Set<String>{ 'Approved', 'Concluded', 'Closed', 'Incomplete' };

    public class Suggestions {
        @AuraEnabled public List<InviteeSuggestion> invitees = new List<InviteeSuggestion>();
        @AuraEnabled public List<ServiceSuggestion> services = new List<ServiceSuggestion>();
        @AuraEnabled public BudgetSuggestion budget;
        @AuraEnabled public Integer similarCount = 0;
        @AuraEnabled public String basis;
    }

    public class InviteeSuggestion {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String name;
        @AuraEnabled public String specialty;
        @AuraEnabled public String tier;
        @AuraEnabled public Integer score;
        @AuraEnabled public String reason;
        @AuraEnabled public Boolean onTargetList;
    }

    public class ServiceSuggestion {
        @AuraEnabled public Id serviceId;
        @AuraEnabled public String serviceName;
        @AuraEnabled public Id vendorId;
        @AuraEnabled public String vendorName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitCost;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Integer usedIn;
        @AuraEnabled public String reason;
    }

    public class BudgetSuggestion {
        @AuraEnabled public Decimal participants;
        @AuraEnabled public Decimal perAttendeeLow;
        @AuraEnabled public Decimal perAttendeeTypical;
        @AuraEnabled public Decimal perAttendeeHigh;
        @AuraEnabled public Decimal low;
        @AuraEnabled public Decimal typical;
        @AuraEnabled public Decimal high;
        @AuraEnabled public Decimal planned;
        @AuraEnabled public String verdict;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static Suggestions suggest(Id meetingId) {
        try {
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
            if (meeting.OwnerId != UserInfo.getUserId() && !MeetingApprovalChainService.isSuperUser()) {
                throw auraError('Only the meeting owner can see planning suggestions.');
            }
            Suggestions result = new Suggestions();
            List<Meeting__c> similar = similarMeetings(meeting);
            result.similarCount = similar.size();
            result.basis = basis(meeting, similar);
            result.invitees = invitees(meeting);
            result.services = services(meeting, similar);
            result.budget = budget(meeting, similar);
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (AssistantException e) {
            throw e;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    public class AssistantException extends Exception {}

    /** AuraHandledException cannot be thrown under @RestResource (the field app), so REST gets a plain one. */
    private static Exception auraError(String message) {
        if (RestContext.request != null) {
            return new AssistantException(message);
        }
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }

    // ---------------------------------------------------------------- similar meetings

    /** The most recent past meetings of the same type, preferring the same brand. */
    @TestVisible
    static List<Meeting__c> similarMeetings(Meeting__c meeting) {
        String recordType = meeting.RecordType?.DeveloperName;
        DateTime now = System.now();
        List<Meeting__c> rows = new List<Meeting__c>();
        if (meeting.Brand__c != null) {
            rows = [
                SELECT Id, Estimated_Participants__c, Final_Participants__c, Total_Actual_Attendees__c,
                    Actual_Cost__c, Approved_Planned_Cost__c, Planned_Cost__c
                FROM Meeting__c
                WHERE Id != :meeting.Id AND Brand__c = :meeting.Brand__c AND RecordType.DeveloperName = :recordType
                    AND Status__c IN :PAST_STATUSES AND Start_Date_Time__c < :now
                ORDER BY Start_Date_Time__c DESC
                LIMIT :SIMILAR_LIMIT
            ];
        }
        if (rows.size() < MIN_SIMILAR) {
            rows = [
                SELECT Id, Estimated_Participants__c, Final_Participants__c, Total_Actual_Attendees__c,
                    Actual_Cost__c, Approved_Planned_Cost__c, Planned_Cost__c
                FROM Meeting__c
                WHERE Id != :meeting.Id AND RecordType.DeveloperName = :recordType
                    AND Status__c IN :PAST_STATUSES AND Start_Date_Time__c < :now
                ORDER BY Start_Date_Time__c DESC
                LIMIT :SIMILAR_LIMIT
            ];
        }
        return rows;
    }

    static String basis(Meeting__c meeting, List<Meeting__c> similar) {
        String kind = meeting.RecordType?.Name == null ? 'meetings' : meeting.RecordType.Name + ' meetings';
        if (similar.isEmpty()) {
            return 'No past ' + kind + ' to compare with yet.';
        }
        return 'Based on ' + similar.size() + ' past ' + kind
            + (meeting.Brand__r?.Name == null ? '' : ' (' + meeting.Brand__r.Name + ' first)') + '.';
    }

    // ---------------------------------------------------------------- invitees

    @TestVisible
    static List<InviteeSuggestion> invitees(Meeting__c meeting) {
        Set<Id> targets = MeetingHcpAttendeeService.loadTargetHcpAccountIds(
            meeting.OwnerId, MeetingHcpAttendeeService.resolveTargetMonth(meeting.Start_Date_Time__c));
        Boolean targetsOnly = MeetingHcpAttendeeService.requiresHcpAttendees(meeting);

        Set<Id> candidates = new Set<Id>(targets);
        if (!targetsOnly) {
            for (Meeting_Member__c past : [
                SELECT Customer__c FROM Meeting_Member__c
                WHERE Customer__c != NULL AND Meeting__r.OwnerId = :meeting.OwnerId AND Meeting__c != :meeting.Id
                ORDER BY Meeting__r.Start_Date_Time__c DESC
                LIMIT 300
            ]) {
                candidates.add(past.Customer__c);
            }
        }
        for (Meeting_Member__c existing : [SELECT Customer__c FROM Meeting_Member__c WHERE Meeting__c = :meeting.Id AND Customer__c != NULL]) {
            candidates.remove(existing.Customer__c);
        }
        if (candidates.isEmpty()) {
            return new List<InviteeSuggestion>();
        }

        Map<String, Integer> brandSpecialties = brandSpecialties(meeting);
        Integer topSpecialty = 0;
        for (Integer count : brandSpecialties.values()) {
            topSpecialty = Math.max(topSpecialty, count);
        }

        Map<Id, Integer> invited = new Map<Id, Integer>();
        Map<Id, Integer> attended = new Map<Id, Integer>();
        Map<Id, DateTime> lastInvited = new Map<Id, DateTime>();
        DateTime now = System.now();
        for (Meeting_Member__c row : [
            SELECT Customer__c, Attendance_Status__c, Meeting__r.Start_Date_Time__c
            FROM Meeting_Member__c
            WHERE Customer__c IN :candidates AND Meeting__c != :meeting.Id
            ORDER BY Meeting__r.Start_Date_Time__c DESC
            LIMIT 5000
        ]) {
            DateTime start = row.Meeting__r.Start_Date_Time__c;
            if (!lastInvited.containsKey(row.Customer__c) && start != null) {
                lastInvited.put(row.Customer__c, start);
            }
            if (start == null || start >= now) {
                continue;
            }
            invited.put(row.Customer__c, (invited.containsKey(row.Customer__c) ? invited.get(row.Customer__c) : 0) + 1);
            if (row.Attendance_Status__c != null && row.Attendance_Status__c.startsWith('Attended')) {
                attended.put(row.Customer__c, (attended.containsKey(row.Customer__c) ? attended.get(row.Customer__c) : 0) + 1);
            }
        }

        List<InviteeSuggestion> rows = new List<InviteeSuggestion>();
        for (Account account : [
            SELECT Id, Name, Specialty_1__c, Tier__c FROM Account WHERE Id IN :candidates LIMIT 1000
        ]) {
            Integer timesInvited = invited.containsKey(account.Id) ? invited.get(account.Id) : 0;
            Integer timesAttended = attended.containsKey(account.Id) ? attended.get(account.Id) : 0;
            Integer specialtyHits = account.Specialty_1__c != null && brandSpecialties.containsKey(account.Specialty_1__c)
                ? brandSpecialties.get(account.Specialty_1__c) : 0;
            DateTime recent = lastInvited.get(account.Id);
            Boolean invitedRecently = recent != null && recent > now.addDays(-30) && recent < now.addDays(30);

            Decimal score = 0;
            List<String> why = new List<String>();
            if (specialtyHits > 0 && topSpecialty > 0) {
                score += 40.0 * specialtyHits / topSpecialty;
                why.add(account.Specialty_1__c + ' is a usual audience for these meetings');
            } else if (account.Specialty_1__c != null) {
                why.add(account.Specialty_1__c);
            }
            if (timesInvited > 0) {
                score += 30.0 * timesAttended / timesInvited;
                why.add('attended ' + timesAttended + ' of ' + timesInvited + ' Zeta events');
            } else {
                score += 12;
                why.add('not invited before');
            }
            if (account.Tier__c == 'A') {
                score += 10;
                why.add('tier A');
            } else if (account.Tier__c == 'B') {
                score += 5;
            }
            if (targets.contains(account.Id)) {
                score += 10;
                why.add('on your target list');
            }
            if (invitedRecently) {
                score -= 20;
                why.add('already invited to another meeting this month');
            }

            InviteeSuggestion row = new InviteeSuggestion();
            row.accountId = account.Id;
            row.name = account.Name;
            row.specialty = account.Specialty_1__c;
            row.tier = account.Tier__c;
            row.onTargetList = targets.contains(account.Id);
            row.score = Math.max(0, Math.min(100, score.round(System.RoundingMode.HALF_UP).intValue()));
            row.reason = capitalize(String.join(why, ', ')) + '.';
            rows.add(row);
        }
        return topInvitees(rows);
    }

    /** How often each specialty attended past meetings for the same brand (or the same type when there is no brand). */
    static Map<String, Integer> brandSpecialties(Meeting__c meeting) {
        Map<String, Integer> counts = new Map<String, Integer>();
        String recordType = meeting.RecordType?.DeveloperName;
        List<Meeting_Member__c> rows = meeting.Brand__c != null
            ? [
                SELECT Customer__r.Specialty_1__c FROM Meeting_Member__c
                WHERE Meeting__r.Brand__c = :meeting.Brand__c AND Meeting__c != :meeting.Id
                    AND Customer__c != NULL AND Attendance_Status__c LIKE 'Attended%'
                LIMIT 3000
            ]
            : [
                SELECT Customer__r.Specialty_1__c FROM Meeting_Member__c
                WHERE Meeting__r.RecordType.DeveloperName = :recordType AND Meeting__c != :meeting.Id
                    AND Customer__c != NULL AND Attendance_Status__c LIKE 'Attended%'
                LIMIT 3000
            ];
        for (Meeting_Member__c row : rows) {
            String specialty = row.Customer__r.Specialty_1__c;
            if (specialty != null) {
                counts.put(specialty, (counts.containsKey(specialty) ? counts.get(specialty) : 0) + 1);
            }
        }
        return counts;
    }

    static List<InviteeSuggestion> topInvitees(List<InviteeSuggestion> rows) {
        List<InviteeSuggestion> remaining = new List<InviteeSuggestion>(rows);
        List<InviteeSuggestion> top = new List<InviteeSuggestion>();
        while (!remaining.isEmpty() && top.size() < MAX_INVITEES) {
            Integer best = 0;
            for (Integer i = 1; i < remaining.size(); i++) {
                InviteeSuggestion a = remaining[i];
                InviteeSuggestion b = remaining[best];
                if (a.score > b.score || (a.score == b.score && a.name < b.name)) {
                    best = i;
                }
            }
            top.add(remaining.remove(best));
        }
        return top;
    }

    // ---------------------------------------------------------------- services

    @TestVisible
    static List<ServiceSuggestion> services(Meeting__c meeting, List<Meeting__c> similar) {
        List<ServiceSuggestion> rows = new List<ServiceSuggestion>();
        if (similar.isEmpty()) {
            return rows;
        }
        Map<Id, Decimal> participantsByMeeting = new Map<Id, Decimal>();
        for (Meeting__c past : similar) {
            participantsByMeeting.put(past.Id, participants(past));
        }
        Set<Id> already = new Set<Id>();
        for (Meeting_Service_Item__c item : [SELECT Service__c FROM Meeting_Service_Item__c WHERE Meeting__c = :meeting.Id]) {
            already.add(item.Service__c);
        }

        Map<Id, Set<Id>> meetingsByService = new Map<Id, Set<Id>>();
        Map<Id, String> serviceNames = new Map<Id, String>();
        Map<Id, Map<Id, Integer>> vendorCounts = new Map<Id, Map<Id, Integer>>();
        Map<Id, String> vendorNames = new Map<Id, String>();
        Map<Id, List<Decimal>> unitCosts = new Map<Id, List<Decimal>>();
        Map<Id, List<Decimal>> perHead = new Map<Id, List<Decimal>>();
        Map<Id, List<Decimal>> quantities = new Map<Id, List<Decimal>>();
        for (Meeting_Service_Item__c item : [
            SELECT Meeting__c, Service__c, Service__r.Name, Service__r.Is_Active__c, Vendor__c, Vendor__r.Name,
                Vendor__r.Is_Active__c, Quantity__c, Unit_Cost__c
            FROM Meeting_Service_Item__c
            WHERE Meeting__c IN :participantsByMeeting.keySet() AND Service__c != NULL
            LIMIT 2000
        ]) {
            if (already.contains(item.Service__c) || item.Service__r.Is_Active__c == false) {
                continue;
            }
            Id service = item.Service__c;
            serviceNames.put(service, item.Service__r.Name);
            if (!meetingsByService.containsKey(service)) {
                meetingsByService.put(service, new Set<Id>());
                vendorCounts.put(service, new Map<Id, Integer>());
                unitCosts.put(service, new List<Decimal>());
                perHead.put(service, new List<Decimal>());
                quantities.put(service, new List<Decimal>());
            }
            meetingsByService.get(service).add(item.Meeting__c);
            if (item.Vendor__c != null && item.Vendor__r.Is_Active__c != false) {
                Map<Id, Integer> counts = vendorCounts.get(service);
                counts.put(item.Vendor__c, (counts.containsKey(item.Vendor__c) ? counts.get(item.Vendor__c) : 0) + 1);
                vendorNames.put(item.Vendor__c, item.Vendor__r.Name);
            }
            if (item.Unit_Cost__c != null) {
                unitCosts.get(service).add(item.Unit_Cost__c);
            }
            Decimal quantity = item.Quantity__c == null ? 1 : item.Quantity__c;
            quantities.get(service).add(quantity);
            Decimal heads = participantsByMeeting.get(item.Meeting__c);
            if (heads != null && heads > 0 && quantity > 1) {
                perHead.get(service).add(quantity / heads);
            }
        }

        Decimal heads = plannedParticipants(meeting, similar);
        Integer threshold = Math.max(1, Math.ceil(similar.size() * 0.3).intValue());
        for (Id service : meetingsByService.keySet()) {
            Integer usedIn = meetingsByService.get(service).size();
            if (usedIn < threshold) {
                continue;
            }
            ServiceSuggestion row = new ServiceSuggestion();
            row.serviceId = service;
            row.serviceName = serviceNames.get(service);
            row.usedIn = usedIn;
            row.unitCost = round(percentile(unitCosts.get(service), 0.5));
            Decimal perHeadMedian = percentile(perHead.get(service), 0.5);
            row.quantity = perHeadMedian != null && heads != null && heads > 0
                ? Math.max(1, (perHeadMedian * heads).setScale(0, System.RoundingMode.HALF_UP))
                : percentile(quantities.get(service), 0.5);
            if (row.quantity == null || row.quantity <= 0) {
                row.quantity = 1;
            }
            row.amount = row.unitCost == null ? null : round(row.unitCost * row.quantity);
            Integer bestCount = 0;
            for (Id vendor : vendorCounts.get(service).keySet()) {
                Integer count = vendorCounts.get(service).get(vendor);
                if (count > bestCount) {
                    bestCount = count;
                    row.vendorId = vendor;
                    row.vendorName = vendorNames.get(vendor);
                }
            }
            row.reason = 'Used in ' + usedIn + ' of ' + similar.size() + ' similar meetings'
                + (row.vendorName == null ? '' : ', usually from ' + row.vendorName)
                + (perHeadMedian == null ? '' : ', scaled to ' + heads.setScale(0) + ' guests') + '.';
            rows.add(row);
        }
        return sortServices(rows);
    }

    static List<ServiceSuggestion> sortServices(List<ServiceSuggestion> rows) {
        List<ServiceSuggestion> remaining = new List<ServiceSuggestion>(rows);
        List<ServiceSuggestion> sorted = new List<ServiceSuggestion>();
        while (!remaining.isEmpty()) {
            Integer best = 0;
            for (Integer i = 1; i < remaining.size(); i++) {
                if (remaining[i].usedIn > remaining[best].usedIn
                    || (remaining[i].usedIn == remaining[best].usedIn && remaining[i].serviceName < remaining[best].serviceName)) {
                    best = i;
                }
            }
            sorted.add(remaining.remove(best));
        }
        return sorted;
    }

    // ---------------------------------------------------------------- budget

    @TestVisible
    static BudgetSuggestion budget(Meeting__c meeting, List<Meeting__c> similar) {
        List<Decimal> perAttendee = new List<Decimal>();
        for (Meeting__c past : similar) {
            Decimal cost = cost(past);
            Decimal heads = participants(past);
            if (cost != null && cost > 0 && heads != null && heads > 0) {
                perAttendee.add(cost / heads);
            }
        }
        if (perAttendee.isEmpty()) {
            return null;
        }
        BudgetSuggestion result = new BudgetSuggestion();
        result.participants = plannedParticipants(meeting, similar);
        result.perAttendeeLow = round(percentile(perAttendee, 0.25));
        result.perAttendeeTypical = round(percentile(perAttendee, 0.5));
        result.perAttendeeHigh = round(percentile(perAttendee, 0.75));
        result.planned = meeting.Planned_Cost__c;
        if (result.participants == null || result.participants <= 0) {
            result.message = 'Usually ' + money(result.perAttendeeLow) + ' to ' + money(result.perAttendeeHigh)
                + ' per guest. Add the expected number of guests to see a total.';
            return result;
        }
        result.low = round(result.perAttendeeLow * result.participants);
        result.typical = round(result.perAttendeeTypical * result.participants);
        result.high = round(result.perAttendeeHigh * result.participants);
        String range = money(result.low) + ' to ' + money(result.high) + ' for ' + result.participants.setScale(0) + ' guests';
        if (result.planned == null || result.planned == 0) {
            result.verdict = 'none';
            result.message = 'Similar meetings usually cost ' + range + '.';
        } else if (result.planned > result.high * 1.1) {
            result.verdict = 'above';
            result.message = 'Your planned ' + money(result.planned) + ' is above the usual ' + range + '.';
        } else if (result.planned < result.low * 0.9) {
            result.verdict = 'below';
            result.message = 'Your planned ' + money(result.planned) + ' is below the usual ' + range + '. Check nothing is missing.';
        } else {
            result.verdict = 'within';
            result.message = 'Your planned ' + money(result.planned) + ' is within the usual ' + range + '.';
        }
        return result;
    }

    // ---------------------------------------------------------------- helpers

    static Decimal cost(Meeting__c m) {
        if (m.Actual_Cost__c != null && m.Actual_Cost__c > 0) {
            return m.Actual_Cost__c;
        }
        if (m.Approved_Planned_Cost__c != null && m.Approved_Planned_Cost__c > 0) {
            return m.Approved_Planned_Cost__c;
        }
        return m.Planned_Cost__c;
    }

    static Decimal participants(Meeting__c m) {
        if (m.Total_Actual_Attendees__c != null && m.Total_Actual_Attendees__c > 0) {
            return m.Total_Actual_Attendees__c;
        }
        if (m.Final_Participants__c != null && m.Final_Participants__c > 0) {
            return m.Final_Participants__c;
        }
        return m.Estimated_Participants__c;
    }

    /** The guests this meeting plans for: its estimate, else people already on it, else the usual size. */
    static Decimal plannedParticipants(Meeting__c meeting, List<Meeting__c> similar) {
        if (meeting.Estimated_Participants__c != null && meeting.Estimated_Participants__c > 0) {
            return meeting.Estimated_Participants__c;
        }
        Integer members = [SELECT COUNT() FROM Meeting_Member__c WHERE Meeting__c = :meeting.Id];
        if (members > 0) {
            return members;
        }
        List<Decimal> sizes = new List<Decimal>();
        for (Meeting__c past : similar) {
            Decimal heads = participants(past);
            if (heads != null && heads > 0) {
                sizes.add(heads);
            }
        }
        Decimal usual = percentile(sizes, 0.5);
        return usual == null ? null : usual.round(System.RoundingMode.HALF_UP);
    }

    /** Linear-interpolated percentile (0..1) of the values; null when there are none. */
    @TestVisible
    static Decimal percentile(List<Decimal> values, Decimal p) {
        if (values == null || values.isEmpty()) {
            return null;
        }
        List<Decimal> sorted = new List<Decimal>(values);
        sorted.sort();
        Decimal position = (sorted.size() - 1) * p;
        Integer lower = Math.floor(position).intValue();
        Integer upper = Math.ceil(position).intValue();
        if (lower == upper) {
            return sorted[lower];
        }
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
    }

    static Decimal round(Decimal value) {
        return value == null ? null : value.setScale(0, System.RoundingMode.HALF_UP);
    }

    static String money(Decimal value) {
        return value == null ? '' : 'EGP ' + value.setScale(0).format();
    }

    static String capitalize(String text) {
        return String.isBlank(text) ? text : text.left(1).toUpperCase() + text.substring(1);
    }
}
