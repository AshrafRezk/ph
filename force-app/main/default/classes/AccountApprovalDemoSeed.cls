/**
 * Seeds Pending DM accounts as demo.rep for manager approval testing on Home / Accounts.
 *
 * Developer Console (Execute Anonymous):
 *   AccountApprovalDemoSeed.SeedResult r = AccountApprovalDemoSeed.run(5);
 *   System.debug(r.message);
 */
public without sharing class AccountApprovalDemoSeed {
    public static final String ACCOUNT_NAME_PREFIX = 'DEMO Pending Approval ';

    public class SeedResult {
        @AuraEnabled
        public Integer accountsCreated = 0;
        @AuraEnabled
        public Integer pendingVisibleToRunner = 0;
        @AuraEnabled
        public Boolean runnerIsManager = false;
        @AuraEnabled
        public Boolean demoRepInRunnerTeam = false;
        @AuraEnabled
        public String demoRepUsername;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public List<String> errors = new List<String>();
    }

    public class DiagnoseResult {
        @AuraEnabled
        public Boolean isManager;
        @AuraEnabled
        public Id primaryTerritoryId;
        @AuraEnabled
        public String primaryTerritoryName;
        @AuraEnabled
        public List<String> managerRoles = new List<String>();
        @AuraEnabled
        public Id demoRepId;
        @AuraEnabled
        public Boolean demoRepInTeam;
        @AuraEnabled
        public Integer pendingCount;
        @AuraEnabled
        public String guidance;
    }

    @AuraEnabled
    public static SeedResult run(Integer accountCount) {
        Integer count = accountCount == null || accountCount < 1 ? 5 : Math.min(accountCount, 20);
        SeedResult result = new SeedResult();
        result.demoRepUsername = ZetaOrganogramTerritoryLoader.DEMO_FIELD_REP_USERNAME;

        alignDemoDiabTerritoryUsers(result.errors);

        User demoRep = findDemoRep();
        if (demoRep == null) {
            result.errors.add('User not found: ' + result.demoRepUsername);
            result.message = joinErrors(result);
            return result;
        }

        Id cairoTerritoryId = resolveDiabCairoTerritoryId();
        Id hcpRecordTypeId = resolveHcpRecordTypeId();
        List<Account> toInsert = new List<Account>();
        for (Integer i = 1; i <= count; i++) {
            String suffix = String.valueOf(i) + ' — ' + Datetime.now().format('yyyyMMdd-HHmm');
            Account acct = new Account(
                Account_Stage__c = AccountStageService.STAGE_DRAFT,
                BillingCity = 'Cairo',
                Specialty_1__c = 'Cardiology',
                OwnerId = demoRep.Id
            );
            acct.Name = ACCOUNT_NAME_PREFIX + suffix;
            if (hcpRecordTypeId != null) {
                acct.RecordTypeId = hcpRecordTypeId;
            }
            toInsert.add(acct);
        }
        if (Test.isRunningTest()) {
            System.runAs(demoRep) {
                insertAccountsPendingApproval(toInsert, cairoTerritoryId);
            }
        } else {
            insertAccountsPendingApproval(toInsert, cairoTerritoryId);
        }
        result.accountsCreated = toInsert.size();

        Set<Id> teamRepIds = AccountApprovalAccess.resolveTeamRepIds();
        result.runnerIsManager = AccountApprovalAccess.isTerritoryManager();
        result.demoRepInRunnerTeam = teamRepIds.contains(demoRep.Id);
        result.pendingVisibleToRunner = AccountApprovalAccess.getPendingApprovalCount();

        result.message =
            'Created ' +
            result.accountsCreated +
            ' Pending DM account(s) as ' +
            result.demoRepUsername +
            '.';
        if (result.runnerIsManager) {
            result.message +=
                ' As you (' +
                UserInfo.getUserName() +
                '), pending in queue: ' +
                result.pendingVisibleToRunner +
                '.';
            if (!result.demoRepInRunnerTeam) {
                result.message +=
                    ' Demo rep is NOT in your territory span — use demo.dm@… or assign Trainer/District Manager on Diab T DM (without a Medical Rep role on another territory as your primary assignment).';
            }
        } else {
            result.message +=
                ' Log in as a territory manager (District Manager, Trainer, etc. on Diab T DM) to approve.';
        }
        if (!result.errors.isEmpty()) {
            result.message += ' Warnings: ' + String.join(result.errors, '; ');
        }
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static DiagnoseResult diagnoseForCurrentUser() {
        DiagnoseResult d = new DiagnoseResult();
        d.isManager = AccountApprovalAccess.isTerritoryManager();
        d.primaryTerritoryId = TerritoryHierarchyService.getUserTerritoryId(UserInfo.getUserId());
        if (d.primaryTerritoryId != null) {
            Map<Id, String> names = TerritoryHierarchyService.getTerritoryNames(
                new Set<Id>{ d.primaryTerritoryId }
            );
            d.primaryTerritoryName = names.get(d.primaryTerritoryId);
        }
        for (UserTerritory2Association row : [
            SELECT RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId = :UserInfo.getUserId() AND RoleInTerritory2 != NULL
            WITH SYSTEM_MODE
        ]) {
            if (
                row.RoleInTerritory2 == 'District Manager' ||
                row.RoleInTerritory2 == 'Trainer' ||
                row.RoleInTerritory2 == 'Region Manager' ||
                row.RoleInTerritory2 == 'Line Manager'
            ) {
                d.managerRoles.add(row.RoleInTerritory2);
            }
        }
        User demoRep = findDemoRep();
        d.demoRepId = demoRep == null ? null : demoRep.Id;
        Set<Id> teamIds = AccountApprovalAccess.resolveTeamRepIds();
        d.demoRepInTeam = demoRep != null && teamIds.contains(demoRep.Id);
        d.pendingCount = AccountApprovalAccess.getPendingApprovalCount();
        if (!d.isManager) {
            d.guidance = 'Add District Manager or Trainer on Diab T DM (Territory Management), or use demo.dm user.';
        } else if (!d.demoRepInTeam) {
            d.guidance =
                'Your primary territory (' +
                d.primaryTerritoryName +
                ') does not span demo rep. Prefer manager role on Diab T DM only, or log in as demo.dm.';
        } else if (d.pendingCount == 0) {
            d.guidance = 'Run AccountApprovalDemoSeed.run(5) to create pending submissions from demo.rep.';
        } else {
            d.guidance = 'Open Field Rep Home — Accounts awaiting approval should list ' + d.pendingCount + ' row(s).';
        }
        return d;
    }

    private static User findDemoRep() {
        List<User> users = [
            SELECT Id, Username
            FROM User
            WHERE Username = :ZetaOrganogramTerritoryLoader.DEMO_FIELD_REP_USERNAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    private static Id resolveDiabCairoTerritoryId() {
        ZetaOrganogramTerritoryLoader.TrainingLineSpec diab =
            ZetaOrganogramTerritoryLoader.diabTrainingLineSpec();
        if (diab == null || String.isBlank(diab.positionExternalId)) {
            return null;
        }
        List<Territory2> rows = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :diab.positionExternalId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static void insertAccountsPendingApproval(
        List<Account> toInsert,
        Id cairoTerritoryId
    ) {
        insert toInsert;
        for (Account acct : toInsert) {
            AccountApprovalAccess.submitNewAccountForApproval(acct.Id);
            if (cairoTerritoryId != null) {
                insert new Account_Territory_Fields__c(
                    Account__c = acct.Id,
                    Territory2_Id__c = String.valueOf(cairoTerritoryId),
                    Is_Active__c = true
                );
            }
        }
    }

    private static void alignDemoDiabTerritoryUsers(List<String> errors) {
        ZetaOrganogramTerritoryLoader.TrainingLineSpec diab =
            ZetaOrganogramTerritoryLoader.diabTrainingLineSpec();
        if (diab == null || String.isBlank(diab.districtExternalId)) {
            errors.add('Diab T DM territory spec was not found.');
            return;
        }
        Map<String, Id> territoryIds = new Map<String, Id>();
        for (Territory2 territory : [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c IN :new Set<String>{ diab.positionExternalId, diab.districtExternalId }
            WITH SYSTEM_MODE
        ]) {
            territoryIds.put(territory.External_ID__c, territory.Id);
        }
        Id cairoId = territoryIds.get(diab.positionExternalId);
        Id dmId = territoryIds.get(diab.districtExternalId);
        if (cairoId == null || dmId == null) {
            errors.add('Diab T Cairo or Diab T DM territory was not found.');
            return;
        }
        Map<String, User> usersByUsername = new Map<String, User>();
        for (User person : [
            SELECT Id, Username, ManagerId
            FROM User
            WHERE
                Username IN :new Set<String>{
                    ZetaOrganogramTerritoryLoader.DEMO_FIELD_REP_USERNAME,
                    ZetaOrganogramTerritoryLoader.DEMO_DM_USERNAME
                }
            WITH SYSTEM_MODE
        ]) {
            usersByUsername.put(person.Username.toLowerCase(), person);
        }
        User demoRep = usersByUsername.get(ZetaOrganogramTerritoryLoader.DEMO_FIELD_REP_USERNAME);
        User demoDm = usersByUsername.get(ZetaOrganogramTerritoryLoader.DEMO_DM_USERNAME);
        if (demoRep == null) {
            errors.add('Demo FieldRep was not found.');
            return;
        }
        if (demoDm == null) {
            errors.add('Demo DistrictManager was not found.');
            return;
        }
        upsertTerritoryRole(demoRep.Id, cairoId, TrainingRepSampleSeed.ROLE_MEDICAL_REP, errors);
        upsertTerritoryRole(demoDm.Id, dmId, TrainingRepSampleSeed.ROLE_DISTRICT_MANAGER, errors);
        if (demoRep.ManagerId != demoDm.Id) {
            Database.update(
                new List<User>{ new User(Id = demoRep.Id, ManagerId = demoDm.Id) },
                false,
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    private static void upsertTerritoryRole(Id userId, Id territoryId, String role, List<String> errors) {
        List<UserTerritory2Association> existing = [
            SELECT Id, Territory2Id, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId = :userId
            WITH SYSTEM_MODE
        ];
        List<UserTerritory2Association> toDelete = new List<UserTerritory2Association>();
        Boolean alreadyAssigned = false;
        for (UserTerritory2Association row : existing) {
            if (row.Territory2Id == territoryId) {
                alreadyAssigned = true;
                if (row.RoleInTerritory2 != role) {
                    row.RoleInTerritory2 = role;
                    Database.update(new List<UserTerritory2Association>{ row }, false, AccessLevel.SYSTEM_MODE);
                }
            } else {
                toDelete.add(row);
            }
        }
        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, false, AccessLevel.SYSTEM_MODE);
        }
        if (alreadyAssigned) {
            return;
        }
        Database.SaveResult sr = Database.insert(
            new UserTerritory2Association(
                UserId = userId,
                Territory2Id = territoryId,
                RoleInTerritory2 = role
            ),
            false,
            AccessLevel.SYSTEM_MODE
        );
        if (!sr.isSuccess()) {
            errors.add(String.valueOf(userId) + ': ' + sr.getErrors()[0].getMessage());
        }
    }

    private static Id resolveHcpRecordTypeId() {
        List<RecordType> types = [
            SELECT Id
            FROM RecordType
            WHERE
                SobjectType = 'Account'
                AND DeveloperName IN (
                    'Medical_Professional_HCP',
                    'PersonAccount',
                    'SDO_PersonAccounts'
                )
            WITH SYSTEM_MODE
            ORDER BY DeveloperName ASC
            LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }

    private static String joinErrors(SeedResult result) {
        return result.errors.isEmpty() ? 'Seed failed.' : String.join(result.errors, '; ');
    }
}