/**
 * @description CRM Hub Home KPIs: this week vs last week (Sun–Sat), Me + Company, score, leaderboard.
 */
public without sharing class CrmHubHomeStatsService {
    private static final Set<String> CONTACT_IMPROVE_FIELDS = new Set<String>{
        'Email',
        'Phone',
        'MobilePhone'
    };

    private static final Set<String> INTERVIEW_STATUSES = new Set<String>{
        'Interview',
        'Interviewed'
    };

    /** @description Test override for "today" when computing week bounds. */
    @TestVisible
    private static Date todayOverride;

    public class WeekWindow {
        public Date weekStart;
        public Date weekEnd;
        public Datetime rangeStart;
        public Datetime rangeEndExclusive;
    }

    public class MetricCounts {
        public Integer accountsCreated = 0;
        public Integer contactsCreated = 0;
        public Integer oppsActedOn = 0;
        public Integer activitiesTotal = 0;
        public Integer activitiesCall = 0;
        public Integer activitiesEmail = 0;
        public Integer activitiesMeeting = 0;
        public Integer activitiesOther = 0;
        public Integer contactImproved = 0;
        public Integer applicantsNew = 0;
        public Integer applicantsProcessed = 0;
        public Integer screeningsFinished = 0;
        public Integer interviewsDone = 0;

        public Map<String, Object> toMap(Boolean includeHr) {
            Map<String, Object> m = new Map<String, Object>{
                'accountsCreated' => accountsCreated,
                'contactsCreated' => contactsCreated,
                'oppsActedOn' => oppsActedOn,
                'activitiesTotal' => activitiesTotal,
                'activitiesByType' => new Map<String, Object>{
                    'Call' => activitiesCall,
                    'Email' => activitiesEmail,
                    'Meeting' => activitiesMeeting,
                    'Other' => activitiesOther
                },
                'contactImproved' => contactImproved
            };
            if (includeHr) {
                m.put('applicantsNew', applicantsNew);
                m.put('applicantsProcessed', applicantsProcessed);
                m.put('screeningsFinished', screeningsFinished);
                m.put('interviewsDone', interviewsDone);
            }
            return m;
        }
    }

    /**
     * @description Build Home payload for the running user.
     * @param isFullAccess true when Hub Full Access (include HR metrics)
     */
    public static Map<String, Object> buildHomeStats(Boolean isFullAccess) {
        Boolean full = isFullAccess == true;
        WeekWindow thisWeek = weekWindowFor(today());
        WeekWindow lastWeek = weekWindowFor(thisWeek.weekStart.addDays(-1));

        Id meId = UserInfo.getUserId();
        Boolean excludeEmployedContacts = hasCurrentlyEmployedField();
        Boolean historyAvailable = isContactHistoryQueryable();

        Map<Id, MetricCounts> thisByUser = new Map<Id, MetricCounts>();
        Map<Id, MetricCounts> lastByUser = new Map<Id, MetricCounts>();
        MetricCounts companyThis = new MetricCounts();
        MetricCounts companyLast = new MetricCounts();

        accumulateCreatedAccounts(thisWeek, thisByUser, companyThis);
        accumulateCreatedAccounts(lastWeek, lastByUser, companyLast);

        accumulateCreatedContacts(thisWeek, thisByUser, companyThis, excludeEmployedContacts);
        accumulateCreatedContacts(lastWeek, lastByUser, companyLast, excludeEmployedContacts);

        accumulateOppsActedOn(thisWeek, thisByUser, companyThis);
        accumulateOppsActedOn(lastWeek, lastByUser, companyLast);

        accumulateOppActivities(thisWeek, thisByUser, companyThis);
        accumulateOppActivities(lastWeek, lastByUser, companyLast);

        if (historyAvailable) {
            accumulateContactImprovements(thisWeek, thisByUser, companyThis);
            accumulateContactImprovements(lastWeek, lastByUser, companyLast);
        }

        if (full) {
            accumulateHrMetrics(thisWeek, thisByUser, companyThis);
            accumulateHrMetrics(lastWeek, lastByUser, companyLast);
        }

        MetricCounts meThis = ensure(thisByUser, meId);
        MetricCounts meLast = ensure(lastByUser, meId);

        Integer meScore = computeScore(meThis, meLast, full);
        Integer companyScore = computeScore(companyThis, companyLast, full);

        Set<Id> userIds = new Set<Id>();
        userIds.addAll(thisByUser.keySet());
        userIds.addAll(lastByUser.keySet());
        userIds.add(meId);

        Map<Id, String> namesById = loadUserNames(userIds);
        List<Map<String, Object>> leaderboard = new List<Map<String, Object>>();
        for (Id uid : userIds) {
            MetricCounts tw = ensure(thisByUser, uid);
            MetricCounts lw = ensure(lastByUser, uid);
            Integer sc = computeScore(tw, lw, full);
            // Skip users with zero activity both weeks (except always include self)
            if (uid != meId && rawPoints(tw, full) == 0 && rawPoints(lw, full) == 0) {
                continue;
            }
            leaderboard.add(
                new Map<String, Object>{
                    'userId' => String.valueOf(uid),
                    'name' => namesById.containsKey(uid) ? namesById.get(uid) : 'User',
                    'isMe' => uid == meId,
                    'score' => sc,
                    'thisWeek' => tw.toMap(full),
                    'lastWeek' => lw.toMap(full)
                }
            );
        }
        leaderboard.sort(new LeaderboardComparator());

        return new Map<String, Object>{
            'success' => true,
            'weekStart' => String.valueOf(thisWeek.weekStart),
            'weekEnd' => String.valueOf(thisWeek.weekEnd),
            'lastWeekStart' => String.valueOf(lastWeek.weekStart),
            'lastWeekEnd' => String.valueOf(lastWeek.weekEnd),
            'historyAvailable' => historyAvailable,
            'isFullAccess' => full,
            'me' => new Map<String, Object>{
                'score' => meScore,
                'thisWeek' => meThis.toMap(full),
                'lastWeek' => meLast.toMap(full)
            },
            'company' => new Map<String, Object>{
                'score' => companyScore,
                'thisWeek' => companyThis.toMap(full),
                'lastWeek' => companyLast.toMap(full)
            },
            'leaderboard' => leaderboard
        };
    }

    @TestVisible
    static Date today() {
        return todayOverride != null ? todayOverride : Date.today();
    }

    /**
     * @description Sunday–Saturday calendar week containing the given date.
     */
    @TestVisible
    static WeekWindow weekWindowFor(Date d) {
        Date sunday = sundayOnOrBefore(d);
        Date saturday = sunday.addDays(6);
        WeekWindow w = new WeekWindow();
        w.weekStart = sunday;
        w.weekEnd = saturday;
        w.rangeStart = Datetime.newInstance(sunday, Time.newInstance(0, 0, 0, 0));
        w.rangeEndExclusive = Datetime.newInstance(saturday.addDays(1), Time.newInstance(0, 0, 0, 0));
        return w;
    }

    /**
     * @description ISO day-of-week: 1=Mon … 7=Sun. Days back to Sunday = isoDow % 7.
     */
    @TestVisible
    static Date sundayOnOrBefore(Date d) {
        Datetime noon = Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0));
        Integer isoDow = Integer.valueOf(noon.format('u'));
        Integer daysBack = Math.mod(isoDow, 7);
        return d.addDays(-daysBack);
    }

    @TestVisible
    static Integer computeScore(MetricCounts thisWeek, MetricCounts lastWeek, Boolean includeHr) {
        Decimal rawThis = rawPoints(thisWeek, includeHr);
        Decimal rawLast = rawPoints(lastWeek, includeHr);
        Decimal wow = (rawThis == 0 && rawLast == 0) ? 1 : (rawThis / Math.max(rawLast, 1));
        Decimal volumeBonus = Math.min(rawThis, 40) * 0.5;
        Integer score = Integer.valueOf(Math.round(50 + 25 * (wow - 1) + volumeBonus));
        if (score < 0) {
            return 0;
        }
        if (score > 100) {
            return 100;
        }
        return score;
    }

    @TestVisible
    static Decimal rawPoints(MetricCounts c, Boolean includeHr) {
        if (c == null) {
            return 0;
        }
        Decimal pts =
            c.accountsCreated * 3 +
            c.contactsCreated * 3 +
            c.oppsActedOn * 5 +
            c.activitiesTotal * 2 +
            c.contactImproved * 4;
        if (includeHr) {
            pts +=
                c.applicantsNew * 3 +
                c.applicantsProcessed * 4 +
                c.screeningsFinished * 5 +
                c.interviewsDone * 6;
        }
        return pts;
    }

    private static MetricCounts ensure(Map<Id, MetricCounts> byUser, Id uid) {
        if (!byUser.containsKey(uid)) {
            byUser.put(uid, new MetricCounts());
        }
        return byUser.get(uid);
    }

    private static void addInt(MetricCounts c, String field, Integer n) {
        if (n == null || n == 0) {
            return;
        }
        if (field == 'accountsCreated') {
            c.accountsCreated += n;
        } else if (field == 'contactsCreated') {
            c.contactsCreated += n;
        } else if (field == 'contactImproved') {
            c.contactImproved += n;
        } else if (field == 'applicantsNew') {
            c.applicantsNew += n;
        } else if (field == 'applicantsProcessed') {
            c.applicantsProcessed += n;
        } else if (field == 'screeningsFinished') {
            c.screeningsFinished += n;
        } else if (field == 'interviewsDone') {
            c.interviewsDone += n;
        }
    }

    private static void accumulateCreatedAccounts(
        WeekWindow w,
        Map<Id, MetricCounts> byUser,
        MetricCounts company
    ) {
        for (AggregateResult ar : [
            SELECT CreatedById uid, COUNT(Id) cnt
            FROM Account
            WHERE CreatedDate >= :w.rangeStart AND CreatedDate < :w.rangeEndExclusive
            GROUP BY CreatedById
        ]) {
            Id uid = (Id) ar.get('uid');
            Integer cnt = (Integer) ar.get('cnt');
            addInt(ensure(byUser, uid), 'accountsCreated', cnt);
            company.accountsCreated += cnt;
        }
    }

    private static void accumulateCreatedContacts(
        WeekWindow w,
        Map<Id, MetricCounts> byUser,
        MetricCounts company,
        Boolean excludeEmployed
    ) {
        String soql =
            'SELECT CreatedById uid, COUNT(Id) cnt FROM Contact ' +
            'WHERE CreatedDate >= :rangeStart AND CreatedDate < :rangeEndExclusive ';
        if (excludeEmployed) {
            soql += 'AND (CurrentlyEmployed__c = false OR CurrentlyEmployed__c = null) ';
        }
        soql += 'GROUP BY CreatedById';
        Datetime rangeStart = w.rangeStart;
        Datetime rangeEndExclusive = w.rangeEndExclusive;
        for (AggregateResult ar : Database.query(soql)) {
            Id uid = (Id) ar.get('uid');
            Integer cnt = (Integer) ar.get('cnt');
            addInt(ensure(byUser, uid), 'contactsCreated', cnt);
            company.contactsCreated += cnt;
        }
    }

    private static void accumulateOppsActedOn(
        WeekWindow w,
        Map<Id, MetricCounts> byUser,
        MetricCounts company
    ) {
        Map<Id, Set<Id>> oppIdsByUser = new Map<Id, Set<Id>>();
        Set<Id> companyOppIds = new Set<Id>();

        for (Opportunity o : [
            SELECT Id, LastModifiedById
            FROM Opportunity
            WHERE LastModifiedDate >= :w.rangeStart AND LastModifiedDate < :w.rangeEndExclusive
        ]) {
            companyOppIds.add(o.Id);
            if (!oppIdsByUser.containsKey(o.LastModifiedById)) {
                oppIdsByUser.put(o.LastModifiedById, new Set<Id>());
            }
            oppIdsByUser.get(o.LastModifiedById).add(o.Id);
        }

        for (Task t : [
            SELECT WhatId, CreatedById
            FROM Task
            WHERE
                CreatedDate >= :w.rangeStart
                AND CreatedDate < :w.rangeEndExclusive
                AND WhatId IN (SELECT Id FROM Opportunity)
        ]) {
            companyOppIds.add(t.WhatId);
            if (!oppIdsByUser.containsKey(t.CreatedById)) {
                oppIdsByUser.put(t.CreatedById, new Set<Id>());
            }
            oppIdsByUser.get(t.CreatedById).add(t.WhatId);
        }

        for (Event e : [
            SELECT WhatId, CreatedById
            FROM Event
            WHERE
                CreatedDate >= :w.rangeStart
                AND CreatedDate < :w.rangeEndExclusive
                AND WhatId IN (SELECT Id FROM Opportunity)
        ]) {
            companyOppIds.add(e.WhatId);
            if (!oppIdsByUser.containsKey(e.CreatedById)) {
                oppIdsByUser.put(e.CreatedById, new Set<Id>());
            }
            oppIdsByUser.get(e.CreatedById).add(e.WhatId);
        }

        company.oppsActedOn += companyOppIds.size();
        for (Id uid : oppIdsByUser.keySet()) {
            ensure(byUser, uid).oppsActedOn += oppIdsByUser.get(uid).size();
        }
    }

    private static void accumulateOppActivities(
        WeekWindow w,
        Map<Id, MetricCounts> byUser,
        MetricCounts company
    ) {
        for (Task t : [
            SELECT CreatedById, TaskSubtype, Type
            FROM Task
            WHERE
                CreatedDate >= :w.rangeStart
                AND CreatedDate < :w.rangeEndExclusive
                AND WhatId IN (SELECT Id FROM Opportunity)
        ]) {
            String bucket = bucketTask(t.TaskSubtype, t.Type);
            bumpActivity(ensure(byUser, t.CreatedById), bucket);
            bumpActivity(company, bucket);
        }
        for (Event e : [
            SELECT CreatedById
            FROM Event
            WHERE
                CreatedDate >= :w.rangeStart
                AND CreatedDate < :w.rangeEndExclusive
                AND WhatId IN (SELECT Id FROM Opportunity)
        ]) {
            bumpActivity(ensure(byUser, e.CreatedById), 'Meeting');
            bumpActivity(company, 'Meeting');
        }
    }

    @TestVisible
    static String bucketTask(String subtype, String typeVal) {
        String st = subtype == null ? '' : subtype.trim();
        String ty = typeVal == null ? '' : typeVal.trim();
        if (st.equalsIgnoreCase('Call') || ty.equalsIgnoreCase('Call')) {
            return 'Call';
        }
        if (st.equalsIgnoreCase('Email') || ty.equalsIgnoreCase('Email')) {
            return 'Email';
        }
        return 'Other';
    }

    private static void bumpActivity(MetricCounts c, String bucket) {
        c.activitiesTotal++;
        if (bucket == 'Call') {
            c.activitiesCall++;
        } else if (bucket == 'Email') {
            c.activitiesEmail++;
        } else if (bucket == 'Meeting') {
            c.activitiesMeeting++;
        } else {
            c.activitiesOther++;
        }
    }

    private static void accumulateContactImprovements(
        WeekWindow w,
        Map<Id, MetricCounts> byUser,
        MetricCounts company
    ) {
        try {
            for (ContactHistory h : [
                SELECT CreatedById, OldValue, NewValue, Field
                FROM ContactHistory
                WHERE
                    Field IN :CONTACT_IMPROVE_FIELDS
                    AND CreatedDate >= :w.rangeStart
                    AND CreatedDate < :w.rangeEndExclusive
            ]) {
                if (!isBlankToValue(h.OldValue, h.NewValue)) {
                    continue;
                }
                addInt(ensure(byUser, h.CreatedById), 'contactImproved', 1);
                company.contactImproved++;
            }
        } catch (Exception e) {
            // History may be unavailable in some contexts
        }
        try {
            Datetime rangeStart = w.rangeStart;
            Datetime rangeEndExclusive = w.rangeEndExclusive;
            List<SObject> leadHist = Database.query(
                'SELECT CreatedById, OldValue, NewValue FROM LeadHistory ' +
                    'WHERE Field IN (\'Email\',\'Phone\',\'MobilePhone\') ' +
                    'AND CreatedDate >= :rangeStart AND CreatedDate < :rangeEndExclusive'
            );
            for (SObject h : leadHist) {
                if (!isBlankToValue(h.get('OldValue'), h.get('NewValue'))) {
                    continue;
                }
                Id uid = (Id) h.get('CreatedById');
                addInt(ensure(byUser, uid), 'contactImproved', 1);
                company.contactImproved++;
            }
        } catch (Exception e) {
            // Lead history optional
        }
    }

    @TestVisible
    static Boolean isBlankToValue(Object oldVal, Object newVal) {
        String oldS = oldVal == null ? '' : String.valueOf(oldVal).trim();
        String newS = newVal == null ? '' : String.valueOf(newVal).trim();
        return String.isBlank(oldS) && String.isNotBlank(newS);
    }

    private static void accumulateHrMetrics(
        WeekWindow w,
        Map<Id, MetricCounts> byUser,
        MetricCounts company
    ) {
        for (AggregateResult ar : [
            SELECT CreatedById uid, COUNT(Id) cnt
            FROM Job_Application__c
            WHERE CreatedDate >= :w.rangeStart AND CreatedDate < :w.rangeEndExclusive
            GROUP BY CreatedById
        ]) {
            Id uid = (Id) ar.get('uid');
            Integer cnt = (Integer) ar.get('cnt');
            addInt(ensure(byUser, uid), 'applicantsNew', cnt);
            company.applicantsNew += cnt;
        }

        for (AggregateResult ar : [
            SELECT LastModifiedById uid, COUNT(Id) cnt
            FROM Job_Application__c
            WHERE
                LastModifiedDate >= :w.rangeStart
                AND LastModifiedDate < :w.rangeEndExclusive
                AND Status__c != 'New'
                AND CreatedDate < :w.rangeStart
            GROUP BY LastModifiedById
        ]) {
            Id uid = (Id) ar.get('uid');
            Integer cnt = (Integer) ar.get('cnt');
            addInt(ensure(byUser, uid), 'applicantsProcessed', cnt);
            company.applicantsProcessed += cnt;
        }

        Date dStart = w.weekStart;
        Date dEnd = w.weekEnd;
        for (AggregateResult ar : [
            SELECT LastModifiedById uid, COUNT(Id) cnt
            FROM Job_Application__c
            WHERE Screening_Date__c >= :dStart AND Screening_Date__c <= :dEnd
            GROUP BY LastModifiedById
        ]) {
            Id uid = (Id) ar.get('uid');
            Integer cnt = (Integer) ar.get('cnt');
            addInt(ensure(byUser, uid), 'screeningsFinished', cnt);
            company.screeningsFinished += cnt;
        }

        // Prefer InterviewDateTime__c in range; also count status moves into Interview/Interviewed
        Map<Id, Set<Id>> interviewIdsByUser = new Map<Id, Set<Id>>();
        Set<Id> companyInterviewIds = new Set<Id>();
        for (Job_Application__c ja : [
            SELECT Id, LastModifiedById, InterviewDateTime__c, Status__c, LastModifiedDate
            FROM Job_Application__c
            WHERE
                (InterviewDateTime__c >= :w.rangeStart AND InterviewDateTime__c < :w.rangeEndExclusive)
                OR (
                    Status__c IN :INTERVIEW_STATUSES
                    AND LastModifiedDate >= :w.rangeStart
                    AND LastModifiedDate < :w.rangeEndExclusive
                    AND InterviewDateTime__c = NULL
                )
        ]) {
            companyInterviewIds.add(ja.Id);
            if (!interviewIdsByUser.containsKey(ja.LastModifiedById)) {
                interviewIdsByUser.put(ja.LastModifiedById, new Set<Id>());
            }
            interviewIdsByUser.get(ja.LastModifiedById).add(ja.Id);
        }
        company.interviewsDone += companyInterviewIds.size();
        for (Id uid : interviewIdsByUser.keySet()) {
            ensure(byUser, uid).interviewsDone += interviewIdsByUser.get(uid).size();
        }
    }

    private static Map<Id, String> loadUserNames(Set<Id> userIds) {
        Map<Id, String> out = new Map<Id, String>();
        if (userIds == null || userIds.isEmpty()) {
            return out;
        }
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :userIds]) {
            out.put(u.Id, u.Name);
        }
        return out;
    }

    private static Boolean hasCurrentlyEmployedField() {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Contact.fields.getMap();
        return fields.containsKey('CurrentlyEmployed__c');
    }

    @TestVisible
    static Boolean isContactHistoryQueryable() {
        try {
            List<ContactHistory> probe = [
                SELECT Id
                FROM ContactHistory
                LIMIT 1
            ];
            return probe != null;
        } catch (Exception e) {
            return false;
        }
    }

    private class LeaderboardComparator implements System.Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> a, Map<String, Object> b) {
            Integer sa = (Integer) a.get('score');
            Integer sb = (Integer) b.get('score');
            if (sa == sb) {
                String na = String.valueOf(a.get('name'));
                String nb = String.valueOf(b.get('name'));
                return na.toLowerCase().compareTo(nb.toLowerCase());
            }
            return sb < sa ? -1 : 1;
        }
    }
}
