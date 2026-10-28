public with sharing class KamManagementService {
    private static final String ALL = 'All';
    private static final Integer METRIC_ACCOUNT_LIMIT = 120;
    private static final Integer TOP_ACCOUNT_LIMIT = 10;
    private static final Integer RECENT_VISIT_LIMIT = 8;
    private static final Integer ALERT_LIMIT = 5;
    private static final Integer STALE_VISIT_DAYS = 90;
    private static final String STATUS_STRONG = 'Strong coverage';
    private static final String STATUS_IN_PROGRESS = 'In progress';
    private static final String FALLBACK_PLAN_NAME = 'Stakeholder coverage plan';
    private static final String BUCKET_ON_TRACK = 'On track';
    private static final String BUCKET_AT_RISK = 'At risk';
    private static final String BUCKET_BEHIND = 'Behind';

    public class FilterOptions {
        @AuraEnabled public List<FilterOption> planStatuses;
    }

    public class FilterOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class PortfolioSummary {
        @AuraEnabled public Integer accountsTracked;
        @AuraEnabled public Integer accountsOnTrack;
        @AuraEnabled public Integer accountsWithStakeholders;
        @AuraEnabled public Integer totalStakeholderLinks;
        @AuraEnabled public Integer formalAccountPlans;
        @AuraEnabled public Decimal planExecutionPercent;
        @AuraEnabled public Decimal stakeholderCoveragePercent;
        @AuraEnabled public Decimal objectiveCompletionRate;
        @AuraEnabled public Integer completedObjectives;
        @AuraEnabled public Integer totalObjectives;
        @AuraEnabled public Integer upcomingVisitsCount;
        @AuraEnabled public Boolean usesFormalAccountPlans;
        @AuraEnabled public String dataSourceLabel;
    }

    public class PlanBucket {
        @AuraEnabled public String bucket;
        @AuraEnabled public Integer count;
        @AuraEnabled public Decimal percent;
    }

    public class StakeholderRoleSegment {
        @AuraEnabled public String roleLabel;
        @AuraEnabled public Integer count;
        @AuraEnabled public Decimal percent;
    }

    public class ObjectiveStateSegment {
        @AuraEnabled public String stateLabel;
        @AuraEnabled public Integer count;
        @AuraEnabled public Decimal percent;
    }

    public class AccountTableRow {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountTypeLabel;
        @AuraEnabled public String planStatus;
        @AuraEnabled public Decimal objectivePercent;
        @AuraEnabled public String lastEngagementLabel;
    }

    public class ActivityRow {
        @AuraEnabled public Id visitId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String visitDateLabel;
        @AuraEnabled public String visitType;
        @AuraEnabled public String status;
        @AuraEnabled public String ownerName;
    }

    public class AlertRow {
        @AuraEnabled public String alertKey;
        @AuraEnabled public String severity;
        @AuraEnabled public String message;
        @AuraEnabled public Id accountId;
    }

    public class DashboardPayload {
        @AuraEnabled public PortfolioSummary portfolio;
        @AuraEnabled public List<PlanBucket> planBuckets;
        @AuraEnabled public List<StakeholderRoleSegment> stakeholderRoles;
        @AuraEnabled public List<ObjectiveStateSegment> objectiveStates;
        @AuraEnabled public List<AccountTableRow> topAccounts;
        @AuraEnabled public List<ActivityRow> recentActivities;
        @AuraEnabled public List<AlertRow> alerts;
    }

    private class AccountMetric {
        public Id accountId;
        public String accountName;
        public String accountTypeLabel;
        public Id planId;
        public String planName;
        public String status;
        public Integer stakeholderCount;
        public Boolean formalPlan;
        public Date lastVisitDate;
        public List<ObjectiveRow> objectives = new List<ObjectiveRow>();
    }

    private class ObjectiveRow {
        public Id objectiveId;
        public String objectiveName;
        public String status;
        public String sourceLabel;
    }

    public static Boolean isAccountPlanEnabled() {
        return Schema.sObjectType.AccountPlan != null && Schema.sObjectType.AccountPlan.isAccessible();
    }

    public static FilterOptions buildFilterOptions() {
        FilterOptions options = new FilterOptions();
        options.planStatuses = new List<FilterOption>{ option(ALL, ALL) };
        if (!isAccountPlanEnabled()) {
            addAffiliationStatusFilters(options);
            return options;
        }
        Set<String> statuses = new Set<String>();
        for (AggregateResult ar : [
            SELECT Status status
            FROM AccountPlan
            WHERE Status != NULL
            WITH USER_MODE
            GROUP BY Status
            ORDER BY Status
            LIMIT 50
        ]) {
            statuses.add((String) ar.get('status'));
        }
        for (String status : statuses) {
            options.planStatuses.add(option(status, status));
        }
        if (options.planStatuses.size() == 1) {
            addAffiliationStatusFilters(options);
        }
        return options;
    }

    public static DashboardPayload buildDashboard(String planStatusFilter) {
        DashboardPayload payload = new DashboardPayload();
        payload.portfolio = new PortfolioSummary();
        payload.planBuckets = new List<PlanBucket>();
        payload.stakeholderRoles = new List<StakeholderRoleSegment>();
        payload.objectiveStates = new List<ObjectiveStateSegment>();
        payload.topAccounts = new List<AccountTableRow>();
        payload.recentActivities = new List<ActivityRow>();
        payload.alerts = new List<AlertRow>();

        String statusFilter = String.isBlank(planStatusFilter) || planStatusFilter == ALL ? null : planStatusFilter;
        List<AccountMetric> metrics = loadAccountMetrics(statusFilter);
        if (metrics.isEmpty()) {
            payload.portfolio.dataSourceLabel = 'No key accounts in scope';
            return payload;
        }

        Set<Id> accountIds = new Set<Id>();
        for (AccountMetric metric : metrics) {
            accountIds.add(metric.accountId);
        }
        enrichLastVisits(metrics, accountIds);

        payload.portfolio = buildPortfolioSummary(metrics, accountIds);
        payload.planBuckets = buildPlanBuckets(metrics);
        payload.stakeholderRoles = buildStakeholderRoleSegments(accountIds);
        payload.objectiveStates = buildObjectiveStateSegments(metrics);
        payload.topAccounts = buildTopAccountRows(metrics);
        payload.recentActivities = loadRecentActivities(accountIds);
        payload.alerts = buildAlerts(metrics);
        return payload;
    }

    private static void addAffiliationStatusFilters(FilterOptions options) {
        options.planStatuses.add(option(STATUS_STRONG, STATUS_STRONG));
        options.planStatuses.add(option(STATUS_IN_PROGRESS, STATUS_IN_PROGRESS));
    }

    private static List<AccountMetric> loadAccountMetrics(String statusFilter) {
        List<AccountMetric> fromPlans = loadMetricsFromAccountPlans(statusFilter);
        if (!fromPlans.isEmpty()) {
            enrichStakeholders(fromPlans);
            enrichFormalObjectives(fromPlans);
            enrichAccountTypes(fromPlans);
            return fromPlans;
        }
        return loadMetricsFromAffiliations(statusFilter);
    }

    private static List<AccountMetric> loadMetricsFromAccountPlans(String statusFilter) {
        List<AccountMetric> metrics = new List<AccountMetric>();
        if (!isAccountPlanEnabled()) {
            return metrics;
        }
        List<AccountPlan> plans = queryPlans(statusFilter);
        for (AccountPlan plan : plans) {
            if (plan.AccountId == null) {
                continue;
            }
            AccountMetric metric = new AccountMetric();
            metric.accountId = plan.AccountId;
            metric.accountName = plan.Account != null ? plan.Account.Name : '';
            metric.accountTypeLabel = 'Account';
            metric.planId = plan.Id;
            metric.planName = plan.Name;
            metric.status = plan.Status;
            metric.formalPlan = true;
            metrics.add(metric);
        }
        return metrics;
    }

    private static List<AccountMetric> loadMetricsFromAffiliations(String statusFilter) {
        List<AccountMetric> metrics = new List<AccountMetric>();
        if (!Schema.sObjectType.Account_Affiliation__c.isAccessible()) {
            return metrics;
        }
        List<AggregateResult> aggregates = [
            SELECT Primary_Account__c accountId, COUNT(Id) stakeholderTotal
            FROM Account_Affiliation__c
            WHERE Primary_Account__c != NULL AND Is_Active__c = TRUE
            WITH USER_MODE
            GROUP BY Primary_Account__c
            ORDER BY COUNT(Id) DESC
            LIMIT :METRIC_ACCOUNT_LIMIT
        ];
        if (aggregates.isEmpty()) {
            return metrics;
        }

        Map<Id, Integer> counts = new Map<Id, Integer>();
        Set<Id> accountIds = new Set<Id>();
        for (AggregateResult aggregate : aggregates) {
            Id accountId = (Id) aggregate.get('accountId');
            Integer total = Integer.valueOf(String.valueOf(aggregate.get('stakeholderTotal')));
            counts.put(accountId, total);
            accountIds.add(accountId);
        }

        Map<Id, Account> accountsById = queryAccounts(accountIds);
        Map<Id, List<ObjectiveRow>> goalsByAccount = loadProjectGoals(accountIds);

        for (Id accountId : accountIds) {
            Integer stakeholderCount = counts.get(accountId);
            String derivedStatus = deriveAffiliationPlanStatus(stakeholderCount);
            if (statusFilter != null && derivedStatus != statusFilter) {
                continue;
            }
            Account account = accountsById.get(accountId);
            if (account == null) {
                continue;
            }
            AccountMetric metric = new AccountMetric();
            metric.accountId = accountId;
            metric.accountName = account.Name;
            metric.accountTypeLabel = resolveAccountType(account);
            metric.planName = FALLBACK_PLAN_NAME;
            metric.status = derivedStatus;
            metric.stakeholderCount = stakeholderCount;
            metric.formalPlan = false;
            metric.objectives = goalsByAccount.containsKey(accountId)
                ? goalsByAccount.get(accountId)
                : new List<ObjectiveRow>();
            metrics.add(metric);
        }
        metrics.sort(new MetricByStakeholdersSorter());
        return metrics;
    }

    private static Map<Id, Account> queryAccounts(Set<Id> accountIds) {
        if (accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }
        String soql = 'SELECT Id, Name';
        if (Schema.sObjectType.Account.fields.RecordTypeId.isAccessible()) {
            soql += ', RecordType.Name';
        }
        soql += ' FROM Account WHERE Id IN :accountIds WITH USER_MODE';
        return new Map<Id, Account>((List<Account>) Database.query(soql));
    }

    private static void enrichAccountTypes(List<AccountMetric> metrics) {
        Set<Id> accountIds = new Set<Id>();
        for (AccountMetric metric : metrics) {
            accountIds.add(metric.accountId);
        }
        Map<Id, Account> accountsById = queryAccounts(accountIds);
        for (AccountMetric metric : metrics) {
            Account account = accountsById.get(metric.accountId);
            metric.accountTypeLabel = account == null ? '' : resolveAccountType(account);
        }
    }

    private static String resolveAccountType(Account account) {
        if (account == null) {
            return 'Account';
        }
        if (account.getPopulatedFieldsAsMap().containsKey('RecordType')) {
            SObject recordType = account.getSObject('RecordType');
            if (recordType != null && recordType.get('Name') != null) {
                return (String) recordType.get('Name');
            }
        }
        return 'Account';
    }

    private static void enrichStakeholders(List<AccountMetric> metrics) {
        Set<Id> accountIds = new Set<Id>();
        for (AccountMetric metric : metrics) {
            accountIds.add(metric.accountId);
        }
        Map<Id, Integer> counts = loadStakeholderCounts(accountIds);
        for (AccountMetric metric : metrics) {
            metric.stakeholderCount = counts.containsKey(metric.accountId) ? counts.get(metric.accountId) : 0;
        }
    }

    private static void enrichFormalObjectives(List<AccountMetric> metrics) {
        Set<Id> planIds = new Set<Id>();
        for (AccountMetric metric : metrics) {
            if (metric.planId != null) {
                planIds.add(metric.planId);
            }
        }
        Map<Id, List<SObject>> byPlan = loadFormalObjectives(planIds);
        for (AccountMetric metric : metrics) {
            metric.objectives = new List<ObjectiveRow>();
            if (!byPlan.containsKey(metric.planId)) {
                continue;
            }
            for (SObject objective : byPlan.get(metric.planId)) {
                ObjectiveRow row = new ObjectiveRow();
                row.objectiveId = (Id) objective.get('Id');
                row.objectiveName = (String) objective.get('Name');
                row.status = (String) objective.get('Status');
                row.sourceLabel = 'Account plan';
                metric.objectives.add(row);
            }
        }
    }

    private static Map<Id, List<SObject>> loadFormalObjectives(Set<Id> planIds) {
        Map<Id, List<SObject>> byPlan = new Map<Id, List<SObject>>();
        if (planIds.isEmpty() || !Schema.sObjectType.AccountPlanObjective.isAccessible()) {
            return byPlan;
        }
        for (AccountPlanObjective objective : [
            SELECT Id, Name, Status, AccountPlanId
            FROM AccountPlanObjective
            WHERE AccountPlanId IN :planIds
            WITH USER_MODE
            LIMIT 5000
        ]) {
            if (!byPlan.containsKey(objective.AccountPlanId)) {
                byPlan.put(objective.AccountPlanId, new List<SObject>());
            }
            byPlan.get(objective.AccountPlanId).add(objective);
        }
        return byPlan;
    }

    private static Map<Id, List<ObjectiveRow>> loadProjectGoals(Set<Id> accountIds) {
        Map<Id, List<ObjectiveRow>> byAccount = new Map<Id, List<ObjectiveRow>>();
        if (accountIds.isEmpty() || !Schema.sObjectType.Pharma_Project_Account_Goal__c.isAccessible()) {
            return byAccount;
        }
        if (!Schema.sObjectType.Pharma_Project_Account_Goal__c.fields.Account__c.isAccessible()) {
            return byAccount;
        }
        List<Id> accountIdList = new List<Id>(accountIds);
        try {
            for (Pharma_Project_Account_Goal__c goal : [
                SELECT Id, Account__c, Goal_Description__c, Status__c
                FROM Pharma_Project_Account_Goal__c
                WHERE Account__c IN :accountIdList
                LIMIT 500
            ]) {
                if (!byAccount.containsKey(goal.Account__c)) {
                    byAccount.put(goal.Account__c, new List<ObjectiveRow>());
                }
                ObjectiveRow row = new ObjectiveRow();
                row.objectiveId = goal.Id;
                row.objectiveName = String.isNotBlank(goal.Goal_Description__c)
                    ? goal.Goal_Description__c
                    : 'Account goal';
                row.status = goal.Status__c;
                row.sourceLabel = 'Project goal';
                byAccount.get(goal.Account__c).add(row);
            }
        } catch (Exception ex) {
            return byAccount;
        }
        return byAccount;
    }

    private static void enrichLastVisits(List<AccountMetric> metrics, Set<Id> accountIds) {
        Map<Id, Date> lastVisitByAccount = loadLastCompletedVisitDates(accountIds);
        for (AccountMetric metric : metrics) {
            metric.lastVisitDate = lastVisitByAccount.get(metric.accountId);
        }
    }

    private static Map<Id, Date> loadLastCompletedVisitDates(Set<Id> accountIds) {
        Map<Id, Date> result = new Map<Id, Date>();
        if (accountIds.isEmpty() || !Schema.sObjectType.Visit__c.isAccessible()) {
            return result;
        }
        for (AggregateResult ar : [
            SELECT Account__c accountId, MAX(Visit_Date__c) lastVisit
            FROM Visit__c
            WHERE Account__c IN :accountIds AND Status__c = 'Completed'
            WITH USER_MODE
            GROUP BY Account__c
        ]) {
            result.put((Id) ar.get('accountId'), toVisitDate((Datetime) ar.get('lastVisit')));
        }
        return result;
    }

    private static PortfolioSummary buildPortfolioSummary(List<AccountMetric> metrics, Set<Id> accountIds) {
        PortfolioSummary summary = new PortfolioSummary();
        summary.accountsTracked = metrics.size();
        summary.formalAccountPlans = 0;
        Integer onTrack = 0;
        Integer withStakeholders = 0;
        Integer stakeholderLinks = 0;
        Integer completedObjectives = 0;
        Integer totalObjectives = 0;
        Boolean formal = false;

        for (AccountMetric metric : metrics) {
            if (metric.formalPlan) {
                formal = true;
                summary.formalAccountPlans++;
            }
            if (isOnTrackStatus(metric.status, metric.stakeholderCount)) {
                onTrack++;
            }
            if (metric.stakeholderCount > 0) {
                withStakeholders++;
            }
            stakeholderLinks += metric.stakeholderCount == null ? 0 : metric.stakeholderCount;
            for (ObjectiveRow objective : metric.objectives) {
                totalObjectives++;
                if (isCompletedObjectiveStatus(objective.status)) {
                    completedObjectives++;
                }
            }
        }

        summary.accountsOnTrack = onTrack;
        summary.accountsWithStakeholders = withStakeholders;
        summary.totalStakeholderLinks = stakeholderLinks;
        summary.usesFormalAccountPlans = formal;
        summary.planExecutionPercent = safeRate(onTrack, metrics.size());
        summary.stakeholderCoveragePercent = safeRate(withStakeholders, metrics.size());
        summary.completedObjectives = completedObjectives;
        summary.totalObjectives = totalObjectives;
        summary.objectiveCompletionRate = safeRate(completedObjectives, totalObjectives);
        summary.upcomingVisitsCount = countUpcomingVisits(accountIds);
        summary.dataSourceLabel = formal
            ? 'Account Plans in Salesforce'
            : 'Top accounts by affiliation depth';
        return summary;
    }

    private static Integer countUpcomingVisits(Set<Id> accountIds) {
        if (accountIds.isEmpty() || !Schema.sObjectType.Visit__c.isAccessible()) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM Visit__c
            WHERE
                Account__c IN :accountIds
                AND Visit_Date__c >= TODAY
                AND Visit_Date__c <= NEXT_N_DAYS:30
                AND Status__c IN ('Scheduled', 'Draft', 'Rescheduled')
            WITH USER_MODE
        ];
    }

    private static List<PlanBucket> buildPlanBuckets(List<AccountMetric> metrics) {
        Map<String, Integer> counts = new Map<String, Integer>{
            BUCKET_ON_TRACK => 0,
            BUCKET_AT_RISK => 0,
            BUCKET_BEHIND => 0
        };
        for (AccountMetric metric : metrics) {
            String bucket = classifyPlanBucket(metric.status, metric.stakeholderCount);
            counts.put(bucket, counts.get(bucket) + 1);
        }
        List<PlanBucket> buckets = new List<PlanBucket>();
        for (String bucketName : new List<String>{ BUCKET_ON_TRACK, BUCKET_AT_RISK, BUCKET_BEHIND }) {
            PlanBucket bucket = new PlanBucket();
            bucket.bucket = bucketName;
            bucket.count = counts.get(bucketName);
            bucket.percent = safeRate(bucket.count, metrics.size());
            buckets.add(bucket);
        }
        return buckets;
    }

    private static List<StakeholderRoleSegment> buildStakeholderRoleSegments(Set<Id> accountIds) {
        List<StakeholderRoleSegment> segments = new List<StakeholderRoleSegment>();
        if (accountIds.isEmpty() || !Schema.sObjectType.Account_Affiliation__c.isAccessible()) {
            return segments;
        }
        Map<String, Integer> counts = new Map<String, Integer>();
        Integer total = 0;
        for (AggregateResult ar : [
            SELECT Role__c roleName, COUNT(Id) total
            FROM Account_Affiliation__c
            WHERE Primary_Account__c IN :accountIds AND Is_Active__c = TRUE
            WITH USER_MODE
            GROUP BY Role__c
            ORDER BY COUNT(Id) DESC
            LIMIT 8
        ]) {
            String role = (String) ar.get('roleName');
            Integer count = Integer.valueOf(String.valueOf(ar.get('total')));
            String label = String.isBlank(role) ? 'Unspecified' : role;
            counts.put(label, count);
            total += count;
        }
        for (String roleLabel : counts.keySet()) {
            StakeholderRoleSegment segment = new StakeholderRoleSegment();
            segment.roleLabel = roleLabel;
            segment.count = counts.get(roleLabel);
            segment.percent = safeRate(segment.count, total);
            segments.add(segment);
        }
        return segments;
    }

    private static List<ObjectiveStateSegment> buildObjectiveStateSegments(List<AccountMetric> metrics) {
        Integer completed = 0;
        Integer inProgress = 0;
        Integer notStarted = 0;
        for (AccountMetric metric : metrics) {
            for (ObjectiveRow objective : metric.objectives) {
                if (isCompletedObjectiveStatus(objective.status)) {
                    completed++;
                } else if (isInProgressObjectiveStatus(objective.status)) {
                    inProgress++;
                } else {
                    notStarted++;
                }
            }
        }
        Integer total = completed + inProgress + notStarted;
        List<ObjectiveStateSegment> segments = new List<ObjectiveStateSegment>();
        segments.add(stateSegment('Achieved', completed, total));
        segments.add(stateSegment('In progress', inProgress, total));
        segments.add(stateSegment('Not started', notStarted, total));
        return segments;
    }

    private static ObjectiveStateSegment stateSegment(String label, Integer count, Integer total) {
        ObjectiveStateSegment segment = new ObjectiveStateSegment();
        segment.stateLabel = label;
        segment.count = count;
        segment.percent = safeRate(count, total);
        return segment;
    }

    private static List<AccountTableRow> buildTopAccountRows(List<AccountMetric> metrics) {
        List<AccountTableRow> rows = new List<AccountTableRow>();
        Integer added = 0;
        for (AccountMetric metric : metrics) {
            if (added >= TOP_ACCOUNT_LIMIT) {
                break;
            }
            AccountTableRow row = new AccountTableRow();
            row.accountId = metric.accountId;
            row.accountName = metric.accountName;
            row.accountTypeLabel = metric.accountTypeLabel;
            row.planStatus = metric.status;
            row.objectivePercent = objectivePercentForMetric(metric);
            row.lastEngagementLabel = formatEngagementDate(metric.lastVisitDate);
            rows.add(row);
            added++;
        }
        return rows;
    }

    private static Decimal objectivePercentForMetric(AccountMetric metric) {
        if (metric.objectives.isEmpty()) {
            return 0;
        }
        Integer completed = 0;
        for (ObjectiveRow objective : metric.objectives) {
            if (isCompletedObjectiveStatus(objective.status)) {
                completed++;
            }
        }
        return safeRate(completed, metric.objectives.size());
    }

    private static String formatEngagementDate(Date visitDate) {
        if (visitDate == null) {
            return 'No completed visit';
        }
        return visitDate.format();
    }

    private static List<ActivityRow> loadRecentActivities(Set<Id> accountIds) {
        List<ActivityRow> rows = new List<ActivityRow>();
        if (accountIds.isEmpty() || !Schema.sObjectType.Visit__c.isAccessible()) {
            return rows;
        }
        for (Visit__c visit : [
            SELECT
                Id,
                Account__c,
                Account__r.Name,
                Visit_Date__c,
                Visit_Type__c,
                Status__c,
                Assigned_To__r.Name
            FROM Visit__c
            WHERE Account__c IN :accountIds AND Status__c = 'Completed'
            WITH USER_MODE
            ORDER BY Visit_Date__c DESC, LastModifiedDate DESC
            LIMIT :RECENT_VISIT_LIMIT
        ]) {
            ActivityRow row = new ActivityRow();
            row.visitId = visit.Id;
            row.accountId = visit.Account__c;
            row.accountName = visit.Account__r != null ? visit.Account__r.Name : '';
            row.visitDateLabel = formatVisitDateTime(visit.Visit_Date__c);
            row.visitType = visit.Visit_Type__c;
            row.status = visit.Status__c;
            row.ownerName = visit.Assigned_To__r != null ? visit.Assigned_To__r.Name : '';
            rows.add(row);
        }
        return rows;
    }

    private static List<AlertRow> buildAlerts(List<AccountMetric> metrics) {
        List<AlertRow> alerts = new List<AlertRow>();
        Date staleThreshold = Date.today().addDays(-STALE_VISIT_DAYS);
        for (AccountMetric metric : metrics) {
            if (alerts.size() >= ALERT_LIMIT) {
                break;
            }
            if (STATUS_IN_PROGRESS.equals(metric.status) && (metric.stakeholderCount == null || metric.stakeholderCount < 5)) {
                AlertRow alert = new AlertRow();
                alert.alertKey = 'coverage-' + metric.accountId;
                alert.severity = 'warning';
                alert.message = metric.accountName + ' — expand stakeholder map (under 5 contacts)';
                alert.accountId = metric.accountId;
                alerts.add(alert);
            }
        }
        for (AccountMetric metric : metrics) {
            if (alerts.size() >= ALERT_LIMIT) {
                break;
            }
            if (metric.lastVisitDate == null || metric.lastVisitDate < staleThreshold) {
                AlertRow alert = new AlertRow();
                alert.alertKey = 'stale-' + metric.accountId;
                alert.severity = 'info';
                alert.message = metric.accountName + ' — no recent completed visit (90+ days)';
                alert.accountId = metric.accountId;
                alerts.add(alert);
            }
        }
        return alerts;
    }

    private static List<AccountPlan> queryPlans(String statusFilter) {
        String soql = 'SELECT Id, Name, AccountId, Account.Name, Status, StartDate, EndDate FROM AccountPlan';
        if (String.isNotBlank(statusFilter)) {
            soql += ' WHERE Status = :statusFilter';
        }
        soql += ' WITH USER_MODE ORDER BY LastModifiedDate DESC LIMIT 500';
        return Database.query(soql);
    }

    private static Map<Id, Integer> loadStakeholderCounts(Set<Id> accountIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (accountIds.isEmpty() || !Schema.sObjectType.Account_Affiliation__c.isAccessible()) {
            return counts;
        }
        for (AggregateResult ar : [
            SELECT Primary_Account__c accountId, COUNT(Id) total
            FROM Account_Affiliation__c
            WHERE Primary_Account__c IN :accountIds AND Is_Active__c = TRUE
            WITH USER_MODE
            GROUP BY Primary_Account__c
        ]) {
            counts.put((Id) ar.get('accountId'), Integer.valueOf(String.valueOf(ar.get('total'))));
        }
        return counts;
    }

    private static String deriveAffiliationPlanStatus(Integer stakeholderCount) {
        if (stakeholderCount == null || stakeholderCount < 1) {
            return STATUS_IN_PROGRESS;
        }
        return stakeholderCount >= 5 ? STATUS_STRONG : STATUS_IN_PROGRESS;
    }

    private static String classifyPlanBucket(String status, Integer stakeholderCount) {
        if (isOnTrackStatus(status, stakeholderCount)) {
            return BUCKET_ON_TRACK;
        }
        if (stakeholderCount == null || stakeholderCount < 2) {
            return BUCKET_BEHIND;
        }
        return BUCKET_AT_RISK;
    }

    private static Boolean isOnTrackStatus(String status, Integer stakeholderCount) {
        if (STATUS_STRONG.equals(status)) {
            return true;
        }
        if (String.isBlank(status)) {
            return false;
        }
        String normalized = status.toLowerCase();
        if (normalized.contains('complete') || normalized.contains('on track')) {
            return true;
        }
        if (normalized.contains('progress') || normalized.contains('active')) {
            return stakeholderCount != null && stakeholderCount >= 5;
        }
        return false;
    }

    private static Boolean isCompletedObjectiveStatus(String status) {
        if (String.isBlank(status)) {
            return false;
        }
        String normalized = status.toLowerCase();
        return normalized.contains('complete') || normalized.contains('done') || normalized.contains('achiev');
    }

    private static Boolean isInProgressObjectiveStatus(String status) {
        if (String.isBlank(status)) {
            return false;
        }
        String normalized = status.toLowerCase();
        return normalized.contains('progress') || normalized.contains('open') || normalized.contains('active');
    }

    private static Decimal safeRate(Integer numerator, Integer denominator) {
        if (denominator == null || denominator <= 0) {
            return 0;
        }
        Integer num = numerator == null ? 0 : numerator;
        return (Decimal.valueOf(num) / Decimal.valueOf(denominator)) * 100;
    }

    private static Date toVisitDate(Datetime value) {
        return value == null ? null : value.date();
    }

    private static String formatVisitDateTime(Datetime value) {
        return value == null ? '' : value.format('dd MMM yyyy');
    }

    private static FilterOption option(String label, String value) {
        FilterOption opt = new FilterOption();
        opt.label = label;
        opt.value = value;
        return opt;
    }

    private class MetricByStakeholdersSorter implements Comparator<AccountMetric> {
        public Integer compare(AccountMetric left, AccountMetric right) {
            Integer lv = left.stakeholderCount == null ? 0 : left.stakeholderCount;
            Integer rv = right.stakeholderCount == null ? 0 : right.stakeholderCount;
            if (lv == rv) {
                return 0;
            }
            return lv > rv ? -1 : 1;
        }
    }
}