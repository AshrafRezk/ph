/**
 * New account approval queue (bypasses sharing for queue actions): territory managers act on their
 * team's Pending DM accounts, and SFE approvers (Admin Console > SFE Approvers) act on Pending SFE
 * accounts from the lines they cover.
 */
public without sharing class AccountApprovalAccess {
    public class ApprovalRow {
        @AuraEnabled
        public Id accountId;
        @AuraEnabled
        public String accountName;
        @AuraEnabled
        public String repName;
        @AuraEnabled
        public String specialty;
        @AuraEnabled
        public String city;
        @AuraEnabled
        public String stageLabel;
        @AuraEnabled
        public Boolean createdByMe;
        @AuraEnabled
        public Datetime submittedDate;
        @AuraEnabled
        public String recordTypeName;
        @AuraEnabled
        public String recordTypeDeveloperName;
        @AuraEnabled
        public Boolean canAct;
        /** DM or SFE when the signed-in user can act on the row. */
        @AuraEnabled
        public String reviewStep;
    }

    public static final String STEP_DM = 'DM';
    public static final String STEP_SFE = 'SFE';

    @TestVisible
    private static Set<Id> testTeamRepIds;

    /** Matches AccountApprovalDemoSeed seeded rows (admin-created, rep-owned). */
    private static final String DEMO_SEED_NAME_PREFIX = 'DEMO Pending Approval ';

    /** In-flight stages for accounts the signed-in user created. Active accounts have left nurturing. */
    private static final Set<String> OWN_NURTURE_STAGES = new Set<String>{
        AccountStageService.STAGE_DRAFT,
        AccountStageService.STAGE_DM,
        AccountStageService.STAGE_SFE,
        AccountStageService.STAGE_FI,
        AccountStageService.STAGE_BU
    };

    /** Roles that can approve account submissions (includes Trainer for demo / training territories). */
    private static Set<String> accountApprovalManagerRoles() {
        return new Set<String>{
            'District Manager',
            'Region Manager',
            'Line Manager',
            'NSM',
            'National Sales Manager',
            'Area Manager',
            'Business Unit Manager',
            'Brand Manager',
            'Trainer'
        };
    }

    public static Boolean isTerritoryManager() {
        // Tests opt in through VisitActorAccess. Production approval is the territory role only,
        // so a System Administrator who is a medical rep cannot approve their own submissions.
        if (Test.isRunningTest() && VisitActorAccess.canViewServiceRequests()) {
            return true;
        }
        return isTerritoryManagerForUserId(UserInfo.getUserId());
    }

    public static Boolean isTerritoryManager(Id userId) {
        if (userId == null || userId != UserInfo.getUserId()) {
            return isTerritoryManagerForUserId(userId);
        }
        return isTerritoryManager();
    }

    public static Set<Id> resolveTeamRepIds() {
        if (Test.isRunningTest() && testTeamRepIds != null) {
            return new Set<Id>(testTeamRepIds);
        }
        return TerritoryHierarchyService.resolveScopedEmployeeIds(null, null, null);
    }

    public static Set<Id> loadPendingTeamAccountIds() {
        Set<Id> teamRepIds = resolveTeamRepIds();
        if (teamRepIds.isEmpty()) {
            return new Set<Id>();
        }
        Set<Id> accountIds = new Set<Id>();
        String demoLike = DEMO_SEED_NAME_PREFIX + '%';
        for (Account acct : [
            SELECT Id
            FROM Account
            WHERE
                Account_Stage__c = :AccountStageService.STAGE_DM
                AND (
                    CreatedById IN :teamRepIds
                    OR (OwnerId IN :teamRepIds AND Name LIKE :demoLike)
                )
            WITH SYSTEM_MODE
            LIMIT 5000
        ]) {
            accountIds.add(acct.Id);
        }
        return accountIds;
    }

    public static List<ApprovalRow> getPendingApprovals() {
        Boolean manager = isTerritoryManager();
        Id userId = UserInfo.getUserId();
        List<Account> ordered = new List<Account>();
        Set<Id> seen = new Set<Id>();
        if (manager) {
            for (Account acct : queryTeamPending()) {
                if (acct.Id == null || seen.contains(acct.Id) || createdByUser(acct, userId)) {
                    continue;
                }
                seen.add(acct.Id);
                ordered.add(acct);
            }
        }
        Set<Id> sfeReviewIds = new Set<Id>();
        for (Account acct : querySfePending(userId)) {
            if (acct.Id == null || seen.contains(acct.Id) || createdByUser(acct, userId)) {
                continue;
            }
            seen.add(acct.Id);
            sfeReviewIds.add(acct.Id);
            ordered.add(acct);
        }
        for (Account acct : queryOwnNurture(userId)) {
            if (acct.Id == null || seen.contains(acct.Id)) {
                continue;
            }
            seen.add(acct.Id);
            ordered.add(acct);
        }
        return toApprovalRows(ordered, manager, sfeReviewIds);
    }

    public static Integer getPendingApprovalCount() {
        return getPendingApprovals().size();
    }

    private static List<Account> queryTeamPending() {
        Set<Id> teamRepIds = resolveTeamRepIds();
        if (teamRepIds.isEmpty()) {
            return new List<Account>();
        }
        String demoLike = DEMO_SEED_NAME_PREFIX + '%';
        return [
            SELECT
                Id,
                Name,
                Specialty_1__c,
                BillingCity,
                Account_Stage__c,
                CreatedById,
                OwnerId,
                CreatedDate,
                RecordType.Name,
                RecordType.DeveloperName
            FROM Account
            WHERE
                Account_Stage__c = :AccountStageService.STAGE_DM
                AND (
                    CreatedById IN :teamRepIds
                    OR (OwnerId IN :teamRepIds AND Name LIKE :demoLike)
                )
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }

    /** Pending SFE accounts submitted from the lines this user approves. */
    private static List<Account> querySfePending(Id userId) {
        String purpose = SfeApproverService.NEW_ACCOUNTS;
        if (!SfeApproverService.isApprover(userId, purpose)) {
            return new List<Account>();
        }
        if (SfeApproverService.coversAllLines(userId, purpose)) {
            return [
                SELECT
                    Id,
                    Name,
                    Specialty_1__c,
                    BillingCity,
                    Account_Stage__c,
                    CreatedById,
                    OwnerId,
                    CreatedDate,
                    RecordType.Name,
                    RecordType.DeveloperName
                FROM Account
                WHERE Account_Stage__c = :AccountStageService.STAGE_SFE
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        }
        Set<Id> repIds = SfeApproverService.seatedUserIdsFor(userId, purpose);
        if (repIds.isEmpty()) {
            return new List<Account>();
        }
        String demoLike = DEMO_SEED_NAME_PREFIX + '%';
        return [
            SELECT
                Id,
                Name,
                Specialty_1__c,
                BillingCity,
                Account_Stage__c,
                CreatedById,
                OwnerId,
                CreatedDate,
                RecordType.Name,
                RecordType.DeveloperName
            FROM Account
            WHERE
                Account_Stage__c = :AccountStageService.STAGE_SFE
                AND (
                    CreatedById IN :repIds
                    OR (OwnerId IN :repIds AND Name LIKE :demoLike)
                )
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }

    private static List<Account> queryOwnNurture(Id userId) {
        String demoLike = DEMO_SEED_NAME_PREFIX + '%';
        return [
            SELECT
                Id,
                Name,
                Specialty_1__c,
                BillingCity,
                Account_Stage__c,
                CreatedById,
                OwnerId,
                CreatedDate,
                RecordType.Name,
                RecordType.DeveloperName
            FROM Account
            WHERE
                Account_Stage__c IN :OWN_NURTURE_STAGES
                AND (
                    CreatedById = :userId
                    OR (OwnerId = :userId AND Name LIKE :demoLike)
                )
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }

    private static List<ApprovalRow> toApprovalRows(List<Account> pending, Boolean manager, Set<Id> sfeReviewIds) {
        if (pending == null || pending.isEmpty()) {
            return new List<ApprovalRow>();
        }
        Set<Id> creatorIds = new Set<Id>();
        for (Account acct : pending) {
            Id submitterId = resolveSubmitterUserId(acct);
            if (submitterId != null) {
                creatorIds.add(submitterId);
            }
        }
        Map<Id, User> creatorsById = new Map<Id, User>(
            [SELECT Id, Name FROM User WHERE Id IN :creatorIds WITH SYSTEM_MODE]
        );

        List<ApprovalRow> rows = new List<ApprovalRow>();
        for (Account acct : pending) {
            ApprovalRow row = new ApprovalRow();
            row.accountId = acct.Id;
            row.accountName = acct.Name;
            row.repName = creatorsById.get(resolveSubmitterUserId(acct))?.Name;
            row.specialty = MedicalSpecialtyPicklist.getLabel(acct.Specialty_1__c);
            row.city = acct.BillingCity;
            row.stageLabel = stageStatusLabel(acct.Account_Stage__c);
            row.createdByMe = createdByUser(acct, UserInfo.getUserId());
            if (row.createdByMe != true && sfeReviewIds.contains(acct.Id)) {
                row.reviewStep = STEP_SFE;
            } else if (
                manager &&
                row.createdByMe != true &&
                AccountStageService.STAGE_DM.equals(acct.Account_Stage__c)
            ) {
                row.reviewStep = STEP_DM;
            }
            row.canAct = row.reviewStep != null;
            row.submittedDate = acct.CreatedDate;
            row.recordTypeName = acct.RecordType == null ? null : acct.RecordType.Name;
            row.recordTypeDeveloperName = acct.RecordType == null ? null : acct.RecordType.DeveloperName;
            rows.add(row);
        }
        return rows;
    }

    public static void approveAccount(Id accountId) {
        assertReviewer(accountId);
        // DM approval hands the account to SFE; SFE approval hands it to FI validation. Neither activates it.
        AccountStageService.advance(accountId);
    }

    public static void rejectAccount(Id accountId, String rejectionReason) {
        assertReviewer(accountId);
        AccountStageService.sendBack(accountId, rejectionReason);
    }

    private static void assertReviewer(Id accountId) {
        List<Account> accounts = accountId == null
            ? new List<Account>()
            : [
                  SELECT Id, Account_Stage__c, CreatedById, OwnerId, Name
                  FROM Account
                  WHERE Id = :accountId
                  WITH SYSTEM_MODE
                  LIMIT 1
              ];
        if (accounts.isEmpty() || !AccountStageService.STAGE_SFE.equals(accounts[0].Account_Stage__c)) {
            assertManagerForAccount(accountId);
            return;
        }
        if (
            !SfeApproverService.coversUser(
                UserInfo.getUserId(),
                resolveSubmitterUserId(accounts[0]),
                SfeApproverService.NEW_ACCOUNTS
            )
        ) {
            throw RestSafeError.make('Only the SFE approvers for this rep\'s line can approve or reject this account.');
        }
    }

    public static void submitNewAccountForApproval(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account is required.');
        }
        List<Account> accounts = [
            SELECT Id, Account_Stage__c
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new AuraHandledException('Account not found.');
        }
        String stage = String.isBlank(accounts[0].Account_Stage__c)
            ? AccountStageService.STAGE_DRAFT
            : accounts[0].Account_Stage__c;
        if (!AccountStageService.STAGE_DRAFT.equals(stage)) {
            return;
        }
        AccountStageService.advance(accountId);
    }

    private static void assertManagerForAccount(Id accountId) {
        if (!isTerritoryManager()) {
            throw new AuraHandledException('Only territory managers can approve or reject account submissions.');
        }
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }
        List<Account> accounts = [
            SELECT Id, Account_Stage__c, CreatedById, OwnerId, Name
            FROM Account
            WHERE Id = :accountId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new AuraHandledException('Account not found.');
        }
        Account acct = accounts[0];
        if (!AccountStageService.STAGE_DM.equals(acct.Account_Stage__c)) {
            throw new AuraHandledException('Only accounts pending DM approval can be actioned here.');
        }
        Set<Id> teamRepIds = resolveTeamRepIds();
        if (!teamRepIds.contains(resolveSubmitterUserId(acct))) {
            throw new AuraHandledException('This account was not submitted by your team.');
        }
    }

    private static Boolean createdByUser(Account acct, Id userId) {
        return userId != null && resolveSubmitterUserId(acct) == userId;
    }

    private static String stageStatusLabel(String stage) {
        if (String.isBlank(stage) || AccountStageService.STAGE_DRAFT.equals(stage)) {
            return 'Draft';
        }
        if (AccountStageService.STAGE_DM.equals(stage)) {
            return 'Pending DM';
        }
        if (AccountStageService.STAGE_SFE.equals(stage)) {
            return 'Pending SFE';
        }
        if (AccountStageService.STAGE_BU.equals(stage)) {
            return 'Pending BU';
        }
        if (AccountStageService.STAGE_FI.equals(stage)) {
            return 'FI Validation';
        }
        if (AccountStageService.STAGE_ACTIVE.equals(stage)) {
            return 'Active';
        }
        return stage;
    }

    public static Id resolveSubmitterUserId(Account acct) {
        if (acct == null) {
            return null;
        }
        if (
            acct.OwnerId != null &&
            acct.Name != null &&
            acct.Name.startsWith(DEMO_SEED_NAME_PREFIX)
        ) {
            return acct.OwnerId;
        }
        return acct.CreatedById;
    }

    public static Boolean isPendingSubmissionFromTeam(Account acct, Set<Id> teamRepIds) {
        if (acct == null || teamRepIds == null || teamRepIds.isEmpty()) {
            return false;
        }
        if (!AccountStageService.STAGE_DM.equals(acct.Account_Stage__c)) {
            return false;
        }
        Id submitterId = resolveSubmitterUserId(acct);
        return submitterId != null && teamRepIds.contains(submitterId);
    }

    public static final String LANE_NEEDS_YOU = 'needsYou';
    public static final String LANE_WITH_MANAGER = 'withManager';
    public static final String LANE_WITH_SFE = 'withSfe';

    public class NurtureSummary {
        @AuraEnabled
        public Integer needsYou = 0;
        @AuraEnabled
        public Integer withManager = 0;
        @AuraEnabled
        public Integer withSfe = 0;
        @AuraEnabled
        public Integer total = 0;
    }

    public class NurtureIndex {
        public Set<Id> needsYou = new Set<Id>();
        public Set<Id> withManager = new Set<Id>();
        public Set<Id> withSfe = new Set<Id>();
        public Set<Id> sfeAdvancedByMe = new Set<Id>();

        public Set<Id> idsFor(String lane) {
            if (LANE_NEEDS_YOU.equalsIgnoreCase(lane)) {
                return new Set<Id>(needsYou);
            }
            if (LANE_WITH_MANAGER.equalsIgnoreCase(lane)) {
                return new Set<Id>(withManager);
            }
            if (LANE_WITH_SFE.equalsIgnoreCase(lane)) {
                return new Set<Id>(withSfe);
            }
            Set<Id> allIds = new Set<Id>();
            allIds.addAll(needsYou);
            allIds.addAll(withManager);
            allIds.addAll(withSfe);
            return allIds;
        }

        public String laneOf(Id accountId) {
            if (accountId == null) {
                return null;
            }
            if (needsYou.contains(accountId)) {
                return LANE_NEEDS_YOU;
            }
            if (withManager.contains(accountId)) {
                return LANE_WITH_MANAGER;
            }
            if (withSfe.contains(accountId)) {
                return LANE_WITH_SFE;
            }
            return null;
        }
    }

    public static NurtureSummary summarizeNurture() {
        NurtureIndex index = loadNurtureIndex();
        NurtureSummary summary = new NurtureSummary();
        summary.needsYou = index.needsYou.size();
        summary.withManager = index.withManager.size();
        summary.withSfe = index.withSfe.size();
        summary.total = summary.needsYou + summary.withManager + summary.withSfe;
        return summary;
    }

    /**
     * In-flight accounts for the signed-in manager, split by who acts next.
     * Own submissions wait on the manager. Team submissions at Pending DM need this user.
     * Pending SFE is the step after this user (or their manager) has already approved.
     */
    public static NurtureIndex loadNurtureIndex() {
        NurtureIndex index = new NurtureIndex();
        Id userId = UserInfo.getUserId();
        Set<Id> subordinateIds = new Set<Id>(resolveTeamRepIds());
        subordinateIds.remove(userId);
        String demoLike = DEMO_SEED_NAME_PREFIX + '%';

        if (!subordinateIds.isEmpty()) {
            for (Account acct : [
                SELECT Id
                FROM Account
                WHERE
                    Account_Stage__c = :AccountStageService.STAGE_DM
                    AND (
                        CreatedById IN :subordinateIds
                        OR (OwnerId IN :subordinateIds AND Name LIKE :demoLike)
                    )
                WITH SYSTEM_MODE
                LIMIT 200
            ]) {
                index.needsYou.add(acct.Id);
            }
        }

        for (Account acct : [
            SELECT Id
            FROM Account
            WHERE
                Account_Stage__c = :AccountStageService.STAGE_DM
                AND (
                    CreatedById = :userId
                    OR (OwnerId = :userId AND Name LIKE :demoLike)
                )
            WITH SYSTEM_MODE
            LIMIT 200
        ]) {
            index.withManager.add(acct.Id);
            index.needsYou.remove(acct.Id);
        }

        Set<Id> watchIds = new Set<Id>(subordinateIds);
        watchIds.add(userId);
        String userName = UserInfo.getName();
        for (Account acct : [
            SELECT Id, CreatedById, OwnerId, Name, LastModifiedById, Stage_History__c
            FROM Account
            WHERE
                Account_Stage__c = :AccountStageService.STAGE_SFE
                AND (
                    CreatedById IN :watchIds
                    OR LastModifiedById = :userId
                    OR (OwnerId IN :watchIds AND Name LIKE :demoLike)
                )
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ]) {
            Id submitterId = resolveSubmitterUserId(acct);
            Boolean createdByMe = submitterId == userId;
            Boolean advancedByMe = advancedByUser(acct, userId, userName);
            if (!createdByMe && !advancedByMe) {
                continue;
            }
            index.withSfe.add(acct.Id);
            if (advancedByMe) {
                index.sfeAdvancedByMe.add(acct.Id);
            }
        }
        return index;
    }

    private static Boolean advancedByUser(Account acct, Id userId, String userName) {
        if (acct == null) {
            return false;
        }
        if (String.isBlank(acct.Stage_History__c)) {
            return acct.LastModifiedById == userId;
        }
        if (String.isBlank(userName)) {
            return false;
        }
        for (String line : acct.Stage_History__c.split('\n')) {
            if (line.contains(userName) && line.contains('SFE')) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isTerritoryManagerForUserId(Id userId) {
        if (userId == null) {
            return false;
        }
        List<UserTerritory2Association> assignments = [
            SELECT RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId = :userId AND RoleInTerritory2 != NULL
            WITH SYSTEM_MODE
        ];
        Set<String> managerRoles = accountApprovalManagerRoles();
        for (UserTerritory2Association assignment : assignments) {
            if (managerRoles.contains(assignment.RoleInTerritory2)) {
                return true;
            }
        }
        return false;
    }
}