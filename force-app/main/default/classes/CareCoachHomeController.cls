/**
 * Home page data for Care Coach Co-pilot: patient status KPIs, status board, call outcomes,
 * monthly enrolment trend, today's work and AI alerts.
 */
public with sharing class CareCoachHomeController {
    public class Kpi {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
        @AuraEnabled public String description;
        @AuraEnabled public Integer changeThisMonth;
        @AuraEnabled public String reportName;
    }

    public class BoardColumn {
        @AuraEnabled public String status;
        @AuraEnabled public Integer count;
        @AuraEnabled public List<CareCoachPatientService.PatientRow> patients = new List<CareCoachPatientService.PatientRow>();
    }

    public class CallBucket {
        @AuraEnabled public String direction;
        @AuraEnabled public String status;
        @AuraEnabled public Integer count;
        @AuraEnabled public Decimal pctOfDirection;
    }

    public class MonthPoint {
        @AuraEnabled public String monthKey;
        @AuraEnabled public String label;
        @AuraEnabled public Map<String, Integer> byProduct = new Map<String, Integer>();
        @AuraEnabled public Integer total = 0;
    }

    public class WorkItem {
        @AuraEnabled public Id interactionId;
        @AuraEnabled public Id patientId;
        @AuraEnabled public String patientName;
        @AuraEnabled public String reason;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public String productName;
        @AuraEnabled public String risk;
        @AuraEnabled public Integer riskScore;
        @AuraEnabled public String detail;
    }

    public class CoachRow {
        @AuraEnabled public Id coachId;
        @AuraEnabled public String coachName;
        @AuraEnabled public Integer ongoing = 0;
        @AuraEnabled public Integer pending = 0;
        @AuraEnabled public Integer dropped = 0;
        @AuraEnabled public Integer unknown = 0;
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Integer reachedThisMonth = 0;
    }

    public class HomeData {
        @AuraEnabled public Boolean masked;
        @AuraEnabled public String scope;
        @AuraEnabled public List<Kpi> kpis = new List<Kpi>();
        @AuraEnabled public Integer totalPatients = 0;
        @AuraEnabled public Integer newThisMonth = 0;
        @AuraEnabled public Integer newLastMonth = 0;
        @AuraEnabled public Decimal retentionRate;
        @AuraEnabled public Decimal reachRate;
        @AuraEnabled public List<BoardColumn> board = new List<BoardColumn>();
        @AuraEnabled public List<CallBucket> calls = new List<CallBucket>();
        @AuraEnabled public Map<String, Integer> callTotals = new Map<String, Integer>();
        @AuraEnabled public List<MonthPoint> months = new List<MonthPoint>();
        @AuraEnabled public List<String> products = new List<String>();
        @AuraEnabled public List<WorkItem> today = new List<WorkItem>();
        @AuraEnabled public List<WorkItem> overdue = new List<WorkItem>();
        @AuraEnabled public List<WorkItem> aiAlerts = new List<WorkItem>();
        @AuraEnabled public List<CoachRow> coaches = new List<CoachRow>();
        @AuraEnabled public Map<String, Id> reportIds = new Map<String, Id>();
        @AuraEnabled public Id dashboardId;
    }

    @AuraEnabled
    public static HomeData getHomeData(String mode, String scope, String coachId) {
        HomeData data = new HomeData();
        data.masked = CareCoachAccess.isMasked(mode);
        data.scope = CareCoachAccess.resolveScope(scope);

        Map<String, Object> binds = new Map<String, Object>();
        String patientScope = scopeClause('Care_Coach__c', data.scope, coachId, binds);
        String callScope = scopeClause('Patient__r.Care_Coach__c', data.scope, coachId, binds);

        loadStatusKpis(data, patientScope, binds);
        loadBoard(data, patientScope, binds);
        loadCalls(data, callScope, binds);
        loadMonths(data, patientScope, binds);
        loadWork(data, callScope, binds);
        if (data.scope == CareCoachAccess.SCOPE_ALL) {
            loadCoaches(data, patientScope, callScope, binds);
        }
        for (Report r : [
            SELECT Id, DeveloperName FROM Report WHERE FolderName = 'PSP Reports' WITH USER_MODE
        ]) {
            data.reportIds.put(r.DeveloperName, r.Id);
        }
        for (Dashboard d : [
            SELECT Id FROM Dashboard WHERE DeveloperName = 'PSP_Performance' WITH USER_MODE LIMIT 1
        ]) {
            data.dashboardId = d.Id;
        }
        return data;
    }

    private static String scopeClause(String field, String scope, String coachId, Map<String, Object> binds) {
        if (scope == CareCoachAccess.SCOPE_MINE) {
            binds.put('me', UserInfo.getUserId());
            return field + ' = :me';
        }
        if (String.isNotBlank(coachId)) {
            binds.put('coachId', coachId);
            return field + ' = :coachId';
        }
        return null;
    }

    private static String whereOf(List<String> clauses) {
        List<String> parts = new List<String>();
        for (String c : clauses) {
            if (String.isNotBlank(c)) {
                parts.add(c);
            }
        }
        return parts.isEmpty() ? '' : ' WHERE ' + String.join(parts, ' AND ');
    }

    private static List<AggregateResult> agg(String sql, Map<String, Object> binds) {
        return (List<AggregateResult>) Database.queryWithBinds(sql, binds, AccessLevel.USER_MODE);
    }

    private static void loadStatusKpis(HomeData data, String patientScope, Map<String, Object> binds) {
        Map<String, Integer> groups = new Map<String, Integer>{ 'Ongoing' => 0, 'Pending' => 0, 'Dropped' => 0, 'Unknown' => 0 };
        Map<String, Integer> newGroups = new Map<String, Integer>{ 'Ongoing' => 0, 'Pending' => 0, 'Dropped' => 0, 'Unknown' => 0 };
        for (AggregateResult ar : agg(
            'SELECT Status__c s, COUNT(Id) c FROM Patient__c' + whereOf(new List<String>{ patientScope }) + ' GROUP BY Status__c',
            binds
        )) {
            String g = groupOf((String) ar.get('s'));
            groups.put(g, groups.get(g) + (Integer) ar.get('c'));
            data.totalPatients += (Integer) ar.get('c');
        }
        for (AggregateResult ar : agg(
            'SELECT Status__c s, COUNT(Id) c FROM Patient__c' +
            whereOf(new List<String>{ patientScope, 'Enrollment_Date__c = THIS_MONTH' }) + ' GROUP BY Status__c',
            binds
        )) {
            String g = groupOf((String) ar.get('s'));
            newGroups.put(g, newGroups.get(g) + (Integer) ar.get('c'));
            data.newThisMonth += (Integer) ar.get('c');
        }
        data.newLastMonth = Database.countQueryWithBinds(
            'SELECT COUNT() FROM Patient__c' + whereOf(new List<String>{ patientScope, 'Enrollment_Date__c = LAST_MONTH' }),
            binds,
            AccessLevel.USER_MODE
        );
        Integer droppedThisMonth = Database.countQueryWithBinds(
            'SELECT COUNT() FROM Patient__c' +
            whereOf(new List<String>{ patientScope, 'Status_Group__c = \'Dropped\'', 'LastModifiedDate = THIS_MONTH' }),
            binds,
            AccessLevel.USER_MODE
        );

        data.kpis.add(buildKpi('ongoing', 'Ongoing Patients', groups.get('Ongoing'), 'On therapy and engaged with their coach', newGroups.get('Ongoing'), 'PSP_Ongoing_Patients'));
        data.kpis.add(buildKpi('pending', 'Pending Patients', groups.get('Pending'), 'Enrolled, waiting for first dose / welcome call', newGroups.get('Pending'), 'PSP_Pending_Patients'));
        data.kpis.add(buildKpi('dropped', 'Dropped Patients', groups.get('Dropped'), 'Switched or stopped therapy', droppedThisMonth, 'PSP_Dropped_Patients'));
        data.kpis.add(buildKpi('unknown', 'Unknown (Failed calls)', groups.get('Unknown'), 'Unreachable after repeated attempts', newGroups.get('Unknown'), 'PSP_Patients_by_Status'));

        Integer denom = groups.get('Ongoing') + groups.get('Dropped');
        data.retentionRate = denom == 0 ? null : (Decimal.valueOf(groups.get('Ongoing')) * 100 / denom).setScale(1);
    }

    private static Kpi buildKpi(String id, String label, Integer value, String description, Integer change, String reportName) {
        Kpi k = new Kpi();
        k.id = id;
        k.label = label;
        k.value = value;
        k.description = description;
        k.changeThisMonth = change;
        k.reportName = reportName;
        return k;
    }

    public static String groupOf(String status) {
        if (status == 'Ongoing' || status == 'Pending') {
            return status;
        }
        if (status != null && status.startsWith('Dropped')) {
            return 'Dropped';
        }
        return 'Unknown';
    }

    private static void loadBoard(HomeData data, String patientScope, Map<String, Object> binds) {
        Map<String, BoardColumn> cols = new Map<String, BoardColumn>();
        for (String s : CareCoachPatientService.STATUSES) {
            BoardColumn c = new BoardColumn();
            c.status = s;
            c.count = 0;
            cols.put(s, c);
            data.board.add(c);
        }
        for (AggregateResult ar : agg(
            'SELECT Status__c s, COUNT(Id) c FROM Patient__c' + whereOf(new List<String>{ patientScope }) + ' GROUP BY Status__c',
            binds
        )) {
            BoardColumn c = cols.get((String) ar.get('s'));
            if (c != null) {
                c.count = (Integer) ar.get('c');
            }
        }
        List<String> fields = CareCoachPatientService.fieldList(data.masked, false);
        for (String s : CareCoachPatientService.STATUSES) {
            Map<String, Object> b = binds.clone();
            b.put('boardStatus', s);
            List<Patient__c> rows = (List<Patient__c>) Database.queryWithBinds(
                'SELECT ' + String.join(fields, ', ') + ' FROM Patient__c' +
                whereOf(new List<String>{ patientScope, 'Status__c = :boardStatus' }) +
                ' ORDER BY LastModifiedDate DESC LIMIT 6',
                b,
                AccessLevel.USER_MODE
            );
            for (Patient__c p : rows) {
                cols.get(s).patients.add(CareCoachPatientService.toRow(p, data.masked));
            }
        }
    }

    private static void loadCalls(HomeData data, String callScope, Map<String, Object> binds) {
        Map<String, Integer> totals = new Map<String, Integer>();
        List<CallBucket> buckets = new List<CallBucket>();
        Integer reached = 0;
        Integer attempted = 0;
        for (AggregateResult ar : agg(
            'SELECT Direction__c d, Status__c s, COUNT(Id) c FROM Patient_Interaction__c' +
            whereOf(new List<String>{ callScope, 'Status__c != \'Planned\'', 'Type__c = \'Call\'', 'Start__c = LAST_N_DAYS:30' }) +
            ' GROUP BY Direction__c, Status__c',
            binds
        )) {
            CallBucket b = new CallBucket();
            b.direction = (String) ar.get('d');
            b.status = (String) ar.get('s');
            b.count = (Integer) ar.get('c');
            buckets.add(b);
            Integer t = totals.containsKey(b.direction) ? totals.get(b.direction) : 0;
            totals.put(b.direction, t + b.count);
            attempted += b.count;
            if (b.status == 'Reached') {
                reached += b.count;
            }
        }
        for (CallBucket b : buckets) {
            Integer t = totals.get(b.direction);
            b.pctOfDirection = t == 0 ? 0 : (Decimal.valueOf(b.count) * 100 / t).setScale(2);
        }
        data.calls = buckets;
        data.callTotals = totals;
        data.reachRate = attempted == 0 ? null : (Decimal.valueOf(reached) * 100 / attempted).setScale(1);
    }

    private static void loadMonths(HomeData data, String patientScope, Map<String, Object> binds) {
        Date start = Date.today().toStartOfMonth().addMonths(-5);
        Map<String, Object> b = binds.clone();
        b.put('monthStart', start);
        Map<String, MonthPoint> byKey = new Map<String, MonthPoint>();
        for (Integer i = 0; i < 6; i++) {
            Date m = start.addMonths(i);
            MonthPoint mp = new MonthPoint();
            mp.monthKey = m.year() + '-' + String.valueOf(m.month()).leftPad(2, '0');
            mp.label = Datetime.newInstance(m.year(), m.month(), 1).format('MMM yy');
            byKey.put(mp.monthKey, mp);
            data.months.add(mp);
        }
        Set<String> products = new Set<String>();
        for (AggregateResult ar : agg(
            'SELECT CALENDAR_YEAR(Enrollment_Date__c) y, CALENDAR_MONTH(Enrollment_Date__c) m, Primary_Product__r.Name p, COUNT(Id) c' +
            ' FROM Patient__c' + whereOf(new List<String>{ patientScope, 'Enrollment_Date__c >= :monthStart' }) +
            ' GROUP BY CALENDAR_YEAR(Enrollment_Date__c), CALENDAR_MONTH(Enrollment_Date__c), Primary_Product__r.Name',
            b
        )) {
            String key = ar.get('y') + '-' + String.valueOf(ar.get('m')).leftPad(2, '0');
            MonthPoint mp = byKey.get(key);
            if (mp == null) {
                continue;
            }
            String p = (String) ar.get('p');
            p = p == null ? 'Other' : p;
            products.add(p);
            mp.byProduct.put(p, (Integer) ar.get('c'));
            mp.total += (Integer) ar.get('c');
        }
        data.products = new List<String>(products);
        data.products.sort();
    }

    private static void loadWork(HomeData data, String callScope, Map<String, Object> binds) {
        String baseSql =
            'SELECT Id, Patient__c, Patient__r.Name, Patient__r.Initials__c, Interaction_Reason__c, Status__c, Start__c,' +
            ' Product__r.Name, AI_Adherence_Risk__c, AI_Risk_Score__c, AI_Side_Effects_Flagged__c, AI_Next_Best_Action__c' +
            (data.masked ? '' : ', Patient__r.Full_Name__c') +
            ' FROM Patient_Interaction__c';
        for (Patient_Interaction__c i : (List<Patient_Interaction__c>) Database.queryWithBinds(
            baseSql + whereOf(new List<String>{ callScope, 'Status__c = \'Planned\'', 'Start__c = TODAY' }) + ' ORDER BY Start__c LIMIT 20',
            binds, AccessLevel.USER_MODE
        )) {
            data.today.add(work(i, data.masked, null));
        }
        for (Patient_Interaction__c i : (List<Patient_Interaction__c>) Database.queryWithBinds(
            baseSql + whereOf(new List<String>{ callScope, 'Status__c = \'Planned\'', 'Start__c < TODAY' }) + ' ORDER BY Start__c DESC LIMIT 10',
            binds, AccessLevel.USER_MODE
        )) {
            data.overdue.add(work(i, data.masked, null));
        }
        for (Patient_Interaction__c i : (List<Patient_Interaction__c>) Database.queryWithBinds(
            baseSql + whereOf(new List<String>{ callScope, 'Start__c = LAST_N_DAYS:14', '(AI_Adherence_Risk__c = \'High\' OR Adverse_Event_Reported__c = true)' }) +
            ' ORDER BY AI_Risk_Score__c DESC NULLS LAST, Start__c DESC LIMIT 8',
            binds, AccessLevel.USER_MODE
        )) {
            String detail = String.isNotBlank(i.AI_Side_Effects_Flagged__c) ? i.AI_Side_Effects_Flagged__c : i.AI_Next_Best_Action__c;
            data.aiAlerts.add(work(i, data.masked, detail));
        }
    }

    private static WorkItem work(Patient_Interaction__c i, Boolean masked, String detail) {
        WorkItem w = new WorkItem();
        w.interactionId = i.Id;
        w.patientId = i.Patient__c;
        w.patientName = masked
            ? (i.Patient__r.Initials__c + ' · ' + i.Patient__r.Name)
            : (String.isBlank(i.Patient__r.Full_Name__c) ? i.Patient__r.Name : i.Patient__r.Full_Name__c);
        w.reason = i.Interaction_Reason__c;
        w.status = i.Status__c;
        w.startTime = i.Start__c;
        w.productName = i.Product__r?.Name;
        w.risk = i.AI_Adherence_Risk__c;
        w.riskScore = i.AI_Risk_Score__c == null ? null : i.AI_Risk_Score__c.intValue();
        w.detail = detail;
        return w;
    }

    private static void loadCoaches(HomeData data, String patientScope, String callScope, Map<String, Object> binds) {
        Map<Id, CoachRow> rows = new Map<Id, CoachRow>();
        for (AggregateResult ar : agg(
            'SELECT Care_Coach__c u, Care_Coach__r.Name n, Status__c s, COUNT(Id) c FROM Patient__c' +
            whereOf(new List<String>{ patientScope, 'Care_Coach__c != NULL' }) +
            ' GROUP BY Care_Coach__c, Care_Coach__r.Name, Status__c',
            binds
        )) {
            Id uid = (Id) ar.get('u');
            CoachRow r = rows.get(uid);
            if (r == null) {
                r = new CoachRow();
                r.coachId = uid;
                r.coachName = (String) ar.get('n');
                rows.put(uid, r);
            }
            Integer c = (Integer) ar.get('c');
            String g = groupOf((String) ar.get('s'));
            if (g == 'Ongoing') r.ongoing += c;
            else if (g == 'Pending') r.pending += c;
            else if (g == 'Dropped') r.dropped += c;
            else r.unknown += c;
            r.total += c;
        }
        for (AggregateResult ar : agg(
            'SELECT Care_Coach__c u, COUNT(Id) c FROM Patient_Interaction__c' +
            whereOf(new List<String>{ callScope, 'Status__c = \'Reached\'', 'Start__c = THIS_MONTH', 'Care_Coach__c != NULL' }) +
            ' GROUP BY Care_Coach__c',
            binds
        )) {
            CoachRow r = rows.get((Id) ar.get('u'));
            if (r != null) {
                r.reachedThisMonth = (Integer) ar.get('c');
            }
        }
        data.coaches = rows.values();
    }
}