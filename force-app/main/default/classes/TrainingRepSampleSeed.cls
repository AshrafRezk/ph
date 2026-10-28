/**
 * Training-list sample data for the Training Rep position.
 *
 * Run in two transactions (UserTerritory2Association is setup DML):
 *   TrainingRepSampleSeed.assignUsersToTrainingRep();
 *   TrainingRepSampleSeed.seedTrainingList();
 *   TrainingRepSampleSeed.seedTrainingPlannerActivity();
 *
 * assignUsersToTrainingRep also queues seedTrainingList when not in tests.
 * seedTrainingList queues planner visits and leaves when not in tests.
 */
public without sharing class TrainingRepSampleSeed {
    public static final String ACCOUNT_EXT_PREFIX = 'TRAIN_HCP_';
    public static final String HCO_EXT_PREFIX = 'TRAIN_HCO_';
    public static final String PHARMACY_EXT_PREFIX = 'TRAIN_PHARM_';
    public static final String PRODUCT_EXT_PREFIX = 'TRAIN_PROD_';
    public static final String VISIT_KEY_PREFIX = 'TRAINACT_';
    public static final String LEAVE_COMMENT = 'Training list leave';
    public static final String ROLE_MEDICAL_REP = 'Medical Rep';
    public static final String ROLE_DISTRICT_MANAGER = 'District Manager';

    private static final Integer HCP_COUNT = 180;
    private static final Integer HCO_COUNT = 12;
    private static final Integer PHARMACY_COUNT = 16;
    private static final Integer PRODUCT_COUNT = 2;
    private static final Integer BATCH_SIZE = 200;
    private static final Integer ACTIVITY_USERS_PER_JOB = 1;
    private static final Integer ACCOUNTS_PER_CLASS = 8;
    /** Field users / Today's Plan are Egypt-local; seed runner may be US Pacific. */
    private static final String TRAINING_TZ = 'Africa/Cairo';

    @TestVisible
    private static List<String> lastDmlErrors = new List<String>();

    @TestVisible
    private static Date trainingLocalToday() {
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', TRAINING_TZ));
    }

    /** Wall-clock time in Africa/Cairo for the given local calendar day. */
    @TestVisible
    private static Datetime trainingLocalDateTime(Date localDay, Integer hour, Integer minute) {
        Datetime asGmt = Datetime.newInstanceGmt(
            localDay.year(),
            localDay.month(),
            localDay.day(),
            hour,
            minute,
            0
        );
        Integer offsetMs = TimeZone.getTimeZone(TRAINING_TZ).getOffset(asGmt);
        return asGmt.addSeconds(-offsetMs / 1000);
    }

    private static final List<String> SPECIALTIES = new List<String>{
        'Cardiology',
        'Endocrinology',
        'Neurology',
        'Internal_Medicine',
        'Orthopaedics',
        'Paediatrics'
    };

    private static final List<String> CLASS_CODES = new List<String>{
        'A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'C3'
    };

    private static final List<String> FIRST_NAMES = new List<String>{
        'Ahmed', 'Mohamed', 'Omar', 'Hassan', 'Youssef', 'Karim', 'Tarek', 'Mostafa',
        'Sara', 'Nour', 'Mona', 'Hala', 'Dina', 'Yasmin', 'Layla', 'Fatma',
        'Amr', 'Sherif', 'Hany', 'Walid', 'Rania', 'Heba', 'Nada', 'Salma'
    };

    private static final List<String> LAST_NAMES = new List<String>{
        'Hassan', 'Ibrahim', 'Ali', 'Mahmoud', 'Farouk', 'Nasser', 'Saleh', 'Osman',
        'Kamal', 'Zaki', 'Fouad', 'Mansour', 'Rashad', 'Shawky', 'Helmy', 'Sami'
    };

    public class AssignResult {
        public Id trainingRepId;
        public Integer usersAssigned = 0;
        public Integer otherAssignmentsRemoved = 0;
        public Integer namedUsersCreated = 0;
        public Integer namedUsersActivated = 0;
        public Integer namedUsersAssigned = 0;
        public String message;
        public List<String> errors = new List<String>();
    }

    public class SeedResult {
        public Integer accountCount = 0;
        public Integer hcoCount = 0;
        public Integer pharmacyCount = 0;
        public Integer otaCount = 0;
        public Integer atfCount = 0;
        public Integer atpfCount = 0;
        public Integer productCount = 0;
        public Integer productAlignmentCount = 0;
        public Integer promoWeightCount = 0;
        public Integer promoSpecialtyCount = 0;
        public Integer promoClassCount = 0;
        public Integer planCycleUsers = 0;
        public Integer targetCount = 0;
        public Integer visitCount = 0;
        public Integer totCount = 0;
        public Integer clmCount = 0;
        public String message;
        public List<String> errors = new List<String>();
    }

    private class ProductSpec {
        String productCode;
        String name;
        String therapyArea;
        String primaryBrand;
        ProductSpec(String productCode, String name, String therapyArea, String primaryBrand) {
            this.productCode = productCode;
            this.name = name;
            this.therapyArea = therapyArea;
            this.primaryBrand = primaryBrand;
        }
    }

    private class SpecialtyShare {
        String specialty;
        Decimal percentage;
        SpecialtyShare(String specialty, Decimal percentage) {
            this.specialty = specialty;
            this.percentage = percentage;
        }
    }

    /**
     * Ensures the training hierarchy exists, assigns named line users to Cairo
     * positions, and keeps remaining users on Training Rep.
     */
    public static AssignResult assignUsersToTrainingRep() {
        AssignResult result = new AssignResult();
        ZetaOrganogramTerritoryLoader.LoadResult hierarchy =
            ZetaOrganogramTerritoryLoader.seedTrainingHierarchy();
        if (hierarchy != null && hierarchy.errors != null) {
            result.errors.addAll(hierarchy.errors);
        }

        Id trainingRepId = getTerritoryId(ZetaOrganogramTerritoryLoader.TRAINING_REP_EXT);
        if (trainingRepId == null) {
            result.message = 'Training Rep territory was not found. Load organogram territories first.';
            result.errors.add(result.message);
            return result;
        }
        result.trainingRepId = trainingRepId;

        assignNamedTrainingLineUsers(result);
        assignDemoDiabUsers(result);

        Set<String> reservedUsernames = ZetaOrganogramTerritoryLoader.reservedTrainingUsernames();
        List<User> remainingUsers = new List<User>();
        for (User person : loadAssignableUsers()) {
            if (reservedUsernames.contains(person.Username == null ? null : person.Username.toLowerCase())) {
                continue;
            }
            remainingUsers.add(person);
        }
        Set<Id> remainingIds = new Map<Id, User>(remainingUsers).keySet();

        List<UserTerritory2Association> existing = remainingIds.isEmpty()
            ? new List<UserTerritory2Association>()
            : [
                  SELECT Id, UserId, Territory2Id, RoleInTerritory2
                  FROM UserTerritory2Association
                  WHERE UserId IN :remainingIds
                  WITH SYSTEM_MODE
              ];

        List<UserTerritory2Association> toDelete = new List<UserTerritory2Association>();
        Set<Id> alreadyOnTraining = new Set<Id>();
        for (UserTerritory2Association row : existing) {
            if (row.Territory2Id == trainingRepId) {
                alreadyOnTraining.add(row.UserId);
                if (row.RoleInTerritory2 != ROLE_MEDICAL_REP) {
                    row.RoleInTerritory2 = ROLE_MEDICAL_REP;
                }
            } else {
                toDelete.add(row);
            }
        }
        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, false, AccessLevel.SYSTEM_MODE);
            result.otherAssignmentsRemoved = toDelete.size();
        }

        List<UserTerritory2Association> toInsert = new List<UserTerritory2Association>();
        for (User person : remainingUsers) {
            if (alreadyOnTraining.contains(person.Id)) {
                continue;
            }
            toInsert.add(
                new UserTerritory2Association(
                    UserId = person.Id,
                    Territory2Id = trainingRepId,
                    RoleInTerritory2 = ROLE_MEDICAL_REP
                )
            );
        }
        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
            result.usersAssigned = toInsert.size();
        }

        result.message =
            'Training assignments: named=' +
            result.namedUsersAssigned +
            ' (created=' +
            result.namedUsersCreated +
            ', activated=' +
            result.namedUsersActivated +
            '), Training Rep=' +
            result.usersAssigned +
            ', removed other=' +
            result.otherAssignmentsRemoved +
            '. Demo FieldRep -> Diab T Cairo, Demo DM -> Diab T DM.';

        if (!Test.isRunningTest()) {
            System.enqueueJob(new TrainingRepDataQueueable());
            result.message += ' Training list seed queued.';
        }
        return result;
    }

    public static SeedResult seedTrainingList() {
        SeedResult result = new SeedResult();
        Id trainingRepId = getTerritoryId(ZetaOrganogramTerritoryLoader.TRAINING_REP_EXT);
        Id trainingLineId = getTerritoryId(ZetaOrganogramTerritoryLoader.TRAINING_LINE_EXT);
        if (trainingRepId == null) {
            result.message = 'Training Rep territory was not found. Run assignUsersToTrainingRep first.';
            result.errors.add(result.message);
            return result;
        }

        RecordTypeIds rts = resolveRecordTypes();
        if (rts.personRtId == null) {
            result.message = 'HCP person account record type was not found.';
            result.errors.add(result.message);
            return result;
        }

        List<Product2> defaultProducts = ensureProductsForLine(null);
        List<Product2> alignedProducts = expandWithDispenseProducts(defaultProducts);
        result.productCount = defaultProducts.size();
        result.productAlignmentCount =
            ensureProductTerritoryAlignments(trainingLineId, alignedProducts) +
            ensureProductTerritoryAlignments(trainingRepId, alignedProducts);
        deactivateExtraProductAlignments(trainingLineId, alignedProducts);
        deactivateExtraProductAlignments(trainingRepId, alignedProducts);
        seedPromoGrid(trainingLineId, defaultProducts, promoSpecialtiesForLine(null), result);

        Map<String, Account> hcosByExt = upsertHcos(rts.hcoRtId);
        result.hcoCount = hcosByExt.size();
        Map<String, Account> pharmaciesByExt = upsertPharmacies(rts.pharmacyRtId);
        result.pharmacyCount = pharmaciesByExt.size();
        Map<String, Account> hcpsByExt = upsertHcps(rts.personRtId);
        result.accountCount = hcpsByExt.size();

        Map<String, Account> alignedByExt = mergeAccountMaps(
            mergeAccountMaps(hcosByExt, pharmaciesByExt),
            hcpsByExt
        );
        List<Account> allAccounts = alignedByExt.values();
        Set<Id> alignmentTerritoryIds = collectTrainingAlignmentTerritoryIds(trainingRepId);
        alignAccountsToTerritories(allAccounts, alignedByExt, defaultProducts, alignmentTerritoryIds, result);
        if (trainingRepId != null) {
            removeExtraAccountProductFields(String.valueOf(trainingRepId), defaultProducts);
        }
        if (trainingLineId != null) {
            removeExtraAccountProductFields(String.valueOf(trainingLineId), defaultProducts);
        }

        Set<String> reservedUsernames = ZetaOrganogramTerritoryLoader.reservedTrainingUsernames();
        Set<Id> trainingRepUserIds = new Set<Id>();
        for (User person : loadAssignableUsers()) {
            if (reservedUsernames.contains(person.Username == null ? null : person.Username.toLowerCase())) {
                continue;
            }
            trainingRepUserIds.add(person.Id);
        }
        pinTerritoryContext(trainingRepUserIds, trainingRepId);

        ensureAffiliations(hcpsByExt, hcosByExt);
        ensurePharmacyAffiliations(hcpsByExt, pharmaciesByExt);

        seedPlanCycleTargets(trainingRepId, result);
        if (!Test.isRunningTest()) {
            seedNamedTrainingLineLists(alignedByExt, result);
            System.enqueueJob(new TrainingRepActivityQueueable());
        }
        result.clmCount = linkPresentationsToTrainingTerritories();

        result.message =
            'Training list: ' +
            result.accountCount +
            ' doctors, ' +
            result.hcoCount +
            ' clinics, ' +
            result.pharmacyCount +
            ' pharmacies, ' +
            result.productCount +
            ' products, promo grid classes=' +
            result.promoClassCount +
            ', plan-cycle users=' +
            result.planCycleUsers +
            ', targets=' +
            result.targetCount +
            ', CLMs=' +
            result.clmCount +
            '.';
        if (!Test.isRunningTest()) {
            result.message += ' Planner activity seed queued.';
        }
        return result;
    }

    /**
     * Refreshes 2-product alignments and promo grids on named training lines,
     * then queues visits/leaves for training users.
     */
    public static SeedResult seedTrainingLineProductsAndActivity() {
        SeedResult result = new SeedResult();
        seedNamedTrainingLineLists(null, result);
        result.clmCount = linkPresentationsToTrainingTerritories();
        if (!Test.isRunningTest()) {
            System.enqueueJob(new TrainingRepActivityQueueable());
            result.message =
                'Named-line products/promo grids updated. Planner activity seed queued. ' +
                'promo classes=' +
                result.promoClassCount +
                ', product alignments=' +
                result.productAlignmentCount +
                ', CLMs=' +
                result.clmCount +
                '.';
        } else {
            result.message = 'Named-line products/promo grids updated.';
        }
        return result;
    }

    public class TrainingRepDataQueueable implements Queueable {
        public void execute(QueueableContext context) {
            seedTrainingList();
        }
    }

    public class TrainingRepActivityQueueable implements Queueable {
        private List<Id> remainingUserIds;

        public TrainingRepActivityQueueable() {
            this.remainingUserIds = null;
        }

        public TrainingRepActivityQueueable(List<Id> remainingUserIds) {
            this.remainingUserIds = remainingUserIds;
        }

        public void execute(QueueableContext context) {
            seedTrainingPlannerActivity(remainingUserIds);
        }
    }

    public class RecordTypeIds {
        public Id personRtId;
        public Id hcoRtId;
        public Id pharmacyRtId;
    }

    @TestVisible
    private static RecordTypeIds resolveRecordTypes() {
        RecordTypeIds ids = new RecordTypeIds();
        Map<String, Id> byDevName = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName, IsPersonType
            FROM RecordType
            WHERE SobjectType = 'Account' AND IsActive = true
            WITH SYSTEM_MODE
        ]) {
            byDevName.put(rt.DeveloperName, rt.Id);
            if (rt.IsPersonType == true && ids.personRtId == null) {
                ids.personRtId = rt.Id;
            }
        }
        if (ids.personRtId == null) {
            ids.personRtId = firstPresent(
                byDevName,
                new List<String>{ 'SDO_PersonAccounts', 'PersonAccount', 'Medical_Professional_HCP' }
            );
        }
        ids.hcoRtId = firstPresent(
            byDevName,
            new List<String>{ 'Institution_HCO', 'Business_Account' }
        );
        ids.pharmacyRtId = firstPresent(
            byDevName,
            new List<String>{ 'Pharmacy', 'Business_Account' }
        );
        return ids;
    }

    private static Id firstPresent(Map<String, Id> byDevName, List<String> names) {
        for (String name : names) {
            if (byDevName.containsKey(name)) {
                return byDevName.get(name);
            }
        }
        return null;
    }

    private static Id getTerritoryId(String externalId) {
        List<Territory2> rows = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :externalId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static List<User> loadAssignableUsers() {
        return [
            SELECT Id, Name, Username
            FROM User
            WHERE IsActive = true
            AND UserType = 'Standard'
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ];
    }

    private static void assignNamedTrainingLineUsers(AssignResult result) {
        List<ZetaOrganogramTerritoryLoader.TrainingLineSpec> specs =
            ZetaOrganogramTerritoryLoader.trainingLineSpecs();
        Set<String> usernames = new Set<String>();
        Set<String> positionExts = new Set<String>();
        for (ZetaOrganogramTerritoryLoader.TrainingLineSpec spec : specs) {
            usernames.add(spec.username);
            positionExts.add(spec.positionExternalId);
        }

        Map<String, User> usersByUsername = new Map<String, User>();
        for (User person : [
            SELECT Id, Username, Email, IsActive, FirstName, LastName, ProfileId
            FROM User
            WHERE Username IN :usernames
            WITH SYSTEM_MODE
        ]) {
            usersByUsername.put(person.Username.toLowerCase(), person);
        }

        Map<String, Id> positionIds = new Map<String, Id>();
        for (Territory2 territory : [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c IN :positionExts
            WITH SYSTEM_MODE
        ]) {
            positionIds.put(territory.External_ID__c, territory.Id);
        }

        Id profileId = resolveStandardUserProfileId();
        List<User> toInsert = new List<User>();
        List<ZetaOrganogramTerritoryLoader.TrainingLineSpec> insertSpecs =
            new List<ZetaOrganogramTerritoryLoader.TrainingLineSpec>();
        List<User> toActivate = new List<User>();
        for (ZetaOrganogramTerritoryLoader.TrainingLineSpec spec : specs) {
            User existing = usersByUsername.get(spec.username.toLowerCase());
            if (existing == null) {
                if (profileId == null) {
                    result.errors.add('Standard User profile not found for ' + spec.username);
                    continue;
                }
                toInsert.add(newTrainingUser(spec, profileId));
                insertSpecs.add(spec);
                continue;
            }
            if (!existing.IsActive) {
                existing.IsActive = true;
                toActivate.add(existing);
            }
        }
        if (!toActivate.isEmpty()) {
            Database.SaveResult[] activated = Database.update(toActivate, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < activated.size(); i++) {
                if (activated[i].isSuccess()) {
                    result.namedUsersActivated++;
                } else {
                    result.errors.add(toActivate[i].Username + ': ' + activated[i].getErrors()[0].getMessage());
                }
            }
            unfreezeUsers(new Map<Id, User>(toActivate).keySet(), result);
        }
        if (!toInsert.isEmpty()) {
            Database.SaveResult[] created = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < created.size(); i++) {
                if (created[i].isSuccess()) {
                    result.namedUsersCreated++;
                    User createdUser = toInsert[i];
                    createdUser.Id = created[i].getId();
                    usersByUsername.put(insertSpecs[i].username.toLowerCase(), createdUser);
                    if (!Test.isRunningTest()) {
                        try {
                            System.resetPassword(createdUser.Id, true);
                        } catch (Exception resetEx) {
                            result.errors.add(insertSpecs[i].username + ' password reset: ' + resetEx.getMessage());
                        }
                    }
                } else {
                    result.errors.add(insertSpecs[i].username + ': ' + created[i].getErrors()[0].getMessage());
                }
            }
        }

        Id psgId = resolveFieldRepGroupId();
        Set<Id> namedUserIds = new Set<Id>();
        Map<Id, Id> desiredTerritoryByUser = new Map<Id, Id>();
        for (ZetaOrganogramTerritoryLoader.TrainingLineSpec spec : specs) {
            User person = usersByUsername.get(spec.username.toLowerCase());
            Id positionId = positionIds.get(spec.positionExternalId);
            if (person == null || person.Id == null || positionId == null) {
                if (person == null) {
                    result.errors.add('User not found: ' + spec.username);
                }
                if (positionId == null) {
                    result.errors.add('Territory not found: ' + spec.positionName);
                }
                continue;
            }
            namedUserIds.add(person.Id);
            desiredTerritoryByUser.put(person.Id, positionId);
            assignFieldRepGroup(person.Id, psgId, result);
        }
        if (namedUserIds.isEmpty()) {
            return;
        }

        List<UserTerritory2Association> existing = [
            SELECT Id, UserId, Territory2Id, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId IN :namedUserIds
            WITH SYSTEM_MODE
        ];
        List<UserTerritory2Association> toDelete = new List<UserTerritory2Association>();
        Set<Id> alreadyAssigned = new Set<Id>();
        for (UserTerritory2Association row : existing) {
            Id desired = desiredTerritoryByUser.get(row.UserId);
            if (desired != null && row.Territory2Id == desired) {
                alreadyAssigned.add(row.UserId);
            } else {
                toDelete.add(row);
            }
        }
        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, false, AccessLevel.SYSTEM_MODE);
        }

        List<UserTerritory2Association> toAssign = new List<UserTerritory2Association>();
        for (Id userId : desiredTerritoryByUser.keySet()) {
            if (alreadyAssigned.contains(userId)) {
                result.namedUsersAssigned++;
                continue;
            }
            toAssign.add(
                new UserTerritory2Association(
                    UserId = userId,
                    Territory2Id = desiredTerritoryByUser.get(userId),
                    RoleInTerritory2 = ROLE_MEDICAL_REP
                )
            );
        }
        if (!toAssign.isEmpty()) {
            Database.SaveResult[] assigned = Database.insert(toAssign, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < assigned.size(); i++) {
                if (assigned[i].isSuccess()) {
                    result.namedUsersAssigned++;
                } else {
                    result.errors.add(
                        String.valueOf(toAssign[i].UserId) + ': ' + assigned[i].getErrors()[0].getMessage()
                    );
                }
            }
        }
    }

    private static void assignDemoDiabUsers(AssignResult result) {
        ZetaOrganogramTerritoryLoader.TrainingLineSpec diab =
            ZetaOrganogramTerritoryLoader.diabTrainingLineSpec();
        if (diab == null || String.isBlank(diab.districtExternalId)) {
            result.errors.add('Diab T DM territory spec was not found.');
            return;
        }

        Map<String, Id> territoryIds = new Map<String, Id>();
        Set<String> territoryExtIds = new Set<String>{ diab.positionExternalId, diab.districtExternalId };
        for (Territory2 territory : [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c IN :territoryExtIds
            WITH SYSTEM_MODE
        ]) {
            territoryIds.put(territory.External_ID__c, territory.Id);
        }
        Id cairoId = territoryIds.get(diab.positionExternalId);
        Id dmId = territoryIds.get(diab.districtExternalId);
        if (cairoId == null || dmId == null) {
            result.errors.add('Diab T Cairo or Diab T DM territory was not found.');
            return;
        }

        Map<String, User> usersByUsername = new Map<String, User>();
        Set<String> demoUsernames = new Set<String>{
            ZetaOrganogramTerritoryLoader.DEMO_FIELD_REP_USERNAME,
            ZetaOrganogramTerritoryLoader.DEMO_DM_USERNAME
        };
        for (User person : [
            SELECT Id, Username, ManagerId, IsActive
            FROM User
            WHERE Username IN :demoUsernames
            WITH SYSTEM_MODE
        ]) {
            usersByUsername.put(person.Username.toLowerCase(), person);
        }
        User demoRep = usersByUsername.get(ZetaOrganogramTerritoryLoader.DEMO_FIELD_REP_USERNAME);
        User demoDm = usersByUsername.get(ZetaOrganogramTerritoryLoader.DEMO_DM_USERNAME);
        if (demoRep == null) {
            result.errors.add('Demo FieldRep was not found.');
        }
        if (demoDm == null) {
            result.errors.add('Demo DistrictManager was not found.');
        }
        if (demoRep == null || demoDm == null) {
            return;
        }

        alignUserToTerritory(demoRep.Id, cairoId, ROLE_MEDICAL_REP, result);
        alignUserToTerritory(demoDm.Id, dmId, ROLE_DISTRICT_MANAGER, result);
        assignFieldRepGroup(demoRep.Id, resolveFieldRepGroupId(), result);
        assignPermissionSetGroup(demoDm.Id, resolveDistrictManagerGroupId(), result);
        if (demoRep.ManagerId != demoDm.Id) {
            Database.update(
                new List<User>{ new User(Id = demoRep.Id, ManagerId = demoDm.Id) },
                false,
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    private static void alignUserToTerritory(Id userId, Id territoryId, String role, AssignResult result) {
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
        Database.SaveResult[] inserted = Database.insert(
            new List<UserTerritory2Association>{
                new UserTerritory2Association(
                    UserId = userId,
                    Territory2Id = territoryId,
                    RoleInTerritory2 = role
                )
            },
            false,
            AccessLevel.SYSTEM_MODE
        );
        if (!inserted[0].isSuccess()) {
            result.errors.add(String.valueOf(userId) + ': ' + inserted[0].getErrors()[0].getMessage());
        }
    }

    private static User newTrainingUser(
        ZetaOrganogramTerritoryLoader.TrainingLineSpec spec,
        Id profileId
    ) {
        String aliasSource = spec.firstName + spec.lastName;
        return new User(
            Username = spec.username,
            Email = spec.username,
            FirstName = spec.firstName,
            LastName = spec.lastName,
            Alias = aliasSource.replaceAll('[^A-Za-z0-9]', '').left(8).toLowerCase(),
            CommunityNickname = (spec.firstName + spec.key + String.valueOf(Math.abs(Crypto.getRandomInteger())))
                .left(40),
            Title = 'Medical Rep',
            Department = spec.lineName,
            TimeZoneSidKey = 'Africa/Cairo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
    }

    private static Id resolveStandardUserProfileId() {
        List<Profile> profiles = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return profiles.isEmpty() ? null : profiles[0].Id;
    }

    private static Id resolveFieldRepGroupId() {
        List<PermissionSetGroup> groups = [
            SELECT Id
            FROM PermissionSetGroup
            WHERE DeveloperName = 'Pharma_Field_Rep_PSG'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return groups.isEmpty() ? null : groups[0].Id;
    }

    private static Id resolveDistrictManagerGroupId() {
        List<PermissionSetGroup> groups = [
            SELECT Id
            FROM PermissionSetGroup
            WHERE DeveloperName = 'Pharma_District_Manager_PSG'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return groups.isEmpty() ? null : groups[0].Id;
    }

    private static void assignFieldRepGroup(Id userId, Id groupId, AssignResult result) {
        assignPermissionSetGroup(userId, groupId, result);
    }

    private static void assignPermissionSetGroup(Id userId, Id groupId, AssignResult result) {
        if (userId == null || groupId == null) {
            return;
        }
        List<PermissionSetAssignment> existing = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetGroupId = :groupId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return;
        }
        Database.SaveResult[] inserted = Database.insert(
            new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = userId, PermissionSetGroupId = groupId)
            },
            false,
            AccessLevel.SYSTEM_MODE
        );
        if (!inserted[0].isSuccess()) {
            result.errors.add(
                'Permission set for ' + userId + ': ' + inserted[0].getErrors()[0].getMessage()
            );
        }
    }

    private static void unfreezeUsers(Set<Id> userIds, AssignResult result) {
        if (userIds == null || userIds.isEmpty()) {
            return;
        }
        List<UserLogin> frozen = [
            SELECT Id, UserId, IsFrozen
            FROM UserLogin
            WHERE UserId IN :userIds AND IsFrozen = true
            WITH SYSTEM_MODE
        ];
        if (frozen.isEmpty()) {
            return;
        }
        for (UserLogin login : frozen) {
            login.IsFrozen = false;
        }
        Database.update(frozen, false, AccessLevel.SYSTEM_MODE);
    }

    private static void seedNamedTrainingLineLists(
        Map<String, Account> alignedByExt,
        SeedResult result
    ) {
        if (alignedByExt == null) {
            alignedByExt = mergeAccountMaps(
                mergeAccountMaps(
                    queryAccountsByPrefix(ACCOUNT_EXT_PREFIX),
                    queryAccountsByPrefix(HCO_EXT_PREFIX)
                ),
                queryAccountsByPrefix(PHARMACY_EXT_PREFIX)
            );
        }
        List<ZetaOrganogramTerritoryLoader.TrainingLineSpec> specs =
            ZetaOrganogramTerritoryLoader.trainingLineSpecs();
        Set<String> extIds = new Set<String>();
        Set<String> usernames = new Set<String>();
        for (ZetaOrganogramTerritoryLoader.TrainingLineSpec spec : specs) {
            extIds.add(spec.lineExternalId);
            extIds.add(spec.positionExternalId);
            if (String.isNotBlank(spec.districtExternalId)) {
                extIds.add(spec.districtExternalId);
            }
            usernames.add(spec.username);
        }
        usernames.add(ZetaOrganogramTerritoryLoader.DEMO_FIELD_REP_USERNAME);
        usernames.add(ZetaOrganogramTerritoryLoader.DEMO_DM_USERNAME);
        Map<String, Id> territoryIds = new Map<String, Id>();
        for (Territory2 territory : [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c IN :extIds
            WITH SYSTEM_MODE
        ]) {
            territoryIds.put(territory.External_ID__c, territory.Id);
        }
        Map<String, Id> userIdsByUsername = new Map<String, Id>();
        for (User person : [
            SELECT Id, Username
            FROM User
            WHERE Username IN :usernames
            WITH SYSTEM_MODE
        ]) {
            userIdsByUsername.put(person.Username.toLowerCase(), person.Id);
        }

        for (ZetaOrganogramTerritoryLoader.TrainingLineSpec spec : specs) {
            Id lineId = territoryIds.get(spec.lineExternalId);
            Id positionId = territoryIds.get(spec.positionExternalId);
            if (positionId == null) {
                continue;
            }
            List<Product2> lineProducts = ensureProductsForLine(spec.key);
            List<Product2> alignedProducts = expandWithDispenseProducts(lineProducts);
            result.productAlignmentCount +=
                ensureProductTerritoryAlignments(lineId, alignedProducts) +
                ensureProductTerritoryAlignments(positionId, alignedProducts);
            if (!Test.isRunningTest()) {
                deactivateExtraProductAlignments(lineId, alignedProducts);
                deactivateExtraProductAlignments(positionId, alignedProducts);
                seedPromoGrid(lineId, lineProducts, promoSpecialtiesForLine(spec.key), result);
                if (alignedByExt != null && !alignedByExt.isEmpty() && Limits.getQueries() < 85) {
                    result.atpfCount += ensureAccountTerritoryProductFields(
                        alignedByExt,
                        String.valueOf(positionId),
                        lineProducts
                    );
                    removeExtraAccountProductFields(String.valueOf(positionId), lineProducts);
                    if (lineId != null) {
                        result.atpfCount += ensureAccountTerritoryProductFields(
                            alignedByExt,
                            String.valueOf(lineId),
                            lineProducts
                        );
                        removeExtraAccountProductFields(String.valueOf(lineId), lineProducts);
                    }
                }
            }
            Id userId = userIdsByUsername.get(spec.username.toLowerCase());
            if (userId != null && Limits.getQueries() < 95) {
                pinTerritoryContext(new Set<Id>{ userId }, positionId);
            }
            if (!Test.isRunningTest() && Limits.getQueries() < 90) {
                seedPlanCycleTargets(positionId, result);
            }
        }

        ZetaOrganogramTerritoryLoader.TrainingLineSpec diab =
            ZetaOrganogramTerritoryLoader.diabTrainingLineSpec();
        if (diab != null) {
            Id cairoId = territoryIds.get(diab.positionExternalId);
            Id dmTerritoryId = territoryIds.get(diab.districtExternalId);
            Id demoRepId = userIdsByUsername.get(ZetaOrganogramTerritoryLoader.DEMO_FIELD_REP_USERNAME);
            Id demoDmId = userIdsByUsername.get(ZetaOrganogramTerritoryLoader.DEMO_DM_USERNAME);
            if (cairoId != null && demoRepId != null) {
                pinTerritoryContext(new Set<Id>{ demoRepId }, cairoId);
            }
            if (dmTerritoryId != null && demoDmId != null) {
                pinTerritoryContext(new Set<Id>{ demoDmId }, dmTerritoryId);
            }
        }
    }

    private static Integer pinTerritoryContext(Set<Id> userIds, Id territoryId) {
        Map<Id, User_Territory_Context__c> existingByOwner = new Map<Id, User_Territory_Context__c>();
        for (User_Territory_Context__c row : [
            SELECT Id, SetupOwnerId, Territory2_Id__c
            FROM User_Territory_Context__c
            WHERE SetupOwnerId IN :userIds
            WITH SYSTEM_MODE
        ]) {
            existingByOwner.put(row.SetupOwnerId, row);
        }
        List<User_Territory_Context__c> toUpsert = new List<User_Territory_Context__c>();
        String territoryKey = String.valueOf(territoryId);
        for (Id userId : userIds) {
            User_Territory_Context__c row = existingByOwner.containsKey(userId)
                ? existingByOwner.get(userId)
                : new User_Territory_Context__c(SetupOwnerId = userId);
            row.Territory2_Id__c = territoryKey;
            toUpsert.add(row);
        }
        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
        return toUpsert.size();
    }

    @TestVisible
    private static List<Product2> ensureTrainingProducts() {
        return ensureProductsForLine(null);
    }

    @TestVisible
    private static List<Product2> ensureProductsForLine(String lineKey) {
        List<ProductSpec> specs = productSpecsForLine(lineKey);
        Integer needed = Test.isRunningTest() ? Math.min(2, specs.size()) : specs.size();
        Map<String, Product2> byCode = new Map<String, Product2>();
        Set<String> codes = new Set<String>();
        for (Integer i = 0; i < needed; i++) {
            codes.add(specs[i].productCode);
        }
        for (Product2 product : [
            SELECT Id, Name, External_ID__c, ProductCode, Product_Type__c, Parent_Product__c, IsActive
            FROM Product2
            WHERE ProductCode IN :codes OR External_ID__c IN :codes
            WITH SYSTEM_MODE
        ]) {
            if (String.isNotBlank(product.ProductCode)) {
                byCode.put(product.ProductCode, product);
            }
            if (String.isNotBlank(product.External_ID__c) && !byCode.containsKey(product.External_ID__c)) {
                byCode.put(product.External_ID__c, product);
            }
        }

        List<Product2> toUpsert = new List<Product2>();
        for (Integer i = 0; i < needed; i++) {
            ProductSpec spec = specs[i];
            Product2 product = byCode.containsKey(spec.productCode)
                ? byCode.get(spec.productCode)
                : new Product2(External_ID__c = spec.productCode);
            product.Name = spec.name;
            product.ProductCode = spec.productCode;
            product.External_ID__c = spec.productCode;
            product.IsActive = true;
            product.Primary_Brand__c = spec.primaryBrand;
            if (String.isBlank(product.Product_Type__c)) {
                product.Product_Type__c = 'Detail';
            }
            if (String.isNotBlank(spec.therapyArea)) {
                product.Therapy_Area__c = spec.therapyArea;
            }
            toUpsert.add(product);
        }
        if (!toUpsert.isEmpty()) {
            upsert as system toUpsert Product2.External_ID__c;
        }

        List<Product2> selected = new List<Product2>();
        Map<Id, Product2> seen = new Map<Id, Product2>();
        for (Product2 product : [
            SELECT Id, Name, External_ID__c, ProductCode
            FROM Product2
            WHERE (ProductCode IN :codes OR External_ID__c IN :codes) AND IsActive = true
            WITH SYSTEM_MODE
        ]) {
            if (!seen.containsKey(product.Id)) {
                seen.put(product.Id, product);
            }
        }
        for (Integer i = 0; i < needed; i++) {
            Product2 match = null;
            for (Product2 product : seen.values()) {
                if (product.ProductCode == specs[i].productCode || product.External_ID__c == specs[i].productCode) {
                    match = product;
                    break;
                }
            }
            if (match == null && byCode.containsKey(specs[i].productCode) && byCode.get(specs[i].productCode).Id != null) {
                match = byCode.get(specs[i].productCode);
            }
            if (match != null) {
                selected.add(match);
            }
        }
        if (selected.size() >= needed) {
            return selected;
        }
        selected.addAll([
            SELECT Id, Name, External_ID__c, ProductCode
            FROM Product2
            WHERE IsActive = true AND Id NOT IN :selected
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT :(needed - selected.size())
        ]);
        return selected;
    }

    /**
     * Ensures Sample and Brand Reminder children exist for each detail product
     * so visit dispensing can offer items related to the selected details.
     */
    @TestVisible
    private static List<Product2> expandWithDispenseProducts(List<Product2> detailProducts) {
        Map<Id, Product2> byId = new Map<Id, Product2>();
        if (detailProducts == null || detailProducts.isEmpty()) {
            return new List<Product2>();
        }
        Set<Id> detailIds = new Set<Id>();
        for (Product2 product : detailProducts) {
            if (product != null && product.Id != null) {
                detailIds.add(product.Id);
                byId.put(product.Id, product);
            }
        }
        if (detailIds.isEmpty()) {
            return new List<Product2>(byId.values());
        }

        Map<Id, Product2> loaded = new Map<Id, Product2>([
            SELECT Id, Name, ProductCode, External_ID__c, Product_Type__c, Parent_Product__c, Primary_Brand__c
            FROM Product2
            WHERE Id IN :detailIds
            WITH SYSTEM_MODE
        ]);
        Set<Id> parentIds = new Set<Id>();
        for (Product2 product : loaded.values()) {
            byId.put(product.Id, product);
            parentIds.add(product.Id);
            if (product.Parent_Product__c != null) {
                parentIds.add(product.Parent_Product__c);
            }
        }

        Map<String, Product2> childByKey = new Map<String, Product2>();
        for (Product2 child : [
            SELECT Id, Name, ProductCode, External_ID__c, Product_Type__c, Parent_Product__c, Primary_Brand__c
            FROM Product2
            WHERE Parent_Product__c IN :parentIds
                AND Product_Type__c IN ('Sample', 'Brand Reminder')
                AND IsActive = true
            WITH SYSTEM_MODE
        ]) {
            byId.put(child.Id, child);
            childByKey.put(String.valueOf(child.Parent_Product__c) + ':' + child.Product_Type__c, child);
        }

        List<Product2> toInsert = new List<Product2>();
        for (Product2 detail : loaded.values()) {
            Id parentId = detail.Parent_Product__c != null ? detail.Parent_Product__c : detail.Id;
            String baseExt = String.isNotBlank(detail.External_ID__c)
                ? detail.External_ID__c
                : (String.isNotBlank(detail.ProductCode) ? detail.ProductCode : String.valueOf(detail.Id));
            String brandName = String.isNotBlank(detail.Primary_Brand__c) ? detail.Primary_Brand__c : detail.Name;
            if (!childByKey.containsKey(String.valueOf(parentId) + ':Sample')) {
                toInsert.add(
                    new Product2(
                        Name = detail.Name + ' Sample',
                        ProductCode = (String.isNotBlank(detail.ProductCode) ? detail.ProductCode : baseExt) + '_SAMP',
                        External_ID__c = baseExt + '_SAMP',
                        Product_Type__c = 'Sample',
                        Parent_Product__c = parentId,
                        Primary_Brand__c = brandName,
                        IsActive = true
                    )
                );
            }
            if (!childByKey.containsKey(String.valueOf(parentId) + ':Brand Reminder')) {
                toInsert.add(
                    new Product2(
                        Name = detail.Name + ' Brand Reminder',
                        ProductCode = (String.isNotBlank(detail.ProductCode) ? detail.ProductCode : baseExt) + '_REM',
                        External_ID__c = baseExt + '_REM',
                        Product_Type__c = 'Brand Reminder',
                        Parent_Product__c = parentId,
                        Primary_Brand__c = brandName,
                        IsActive = true
                    )
                );
            }
        }
        if (!toInsert.isEmpty()) {
            Database.upsert(toInsert, Product2.External_ID__c, false, AccessLevel.SYSTEM_MODE);
            for (Product2 created : toInsert) {
                if (created.Id != null) {
                    byId.put(created.Id, created);
                }
            }
        }
        return new List<Product2>(byId.values());
    }

    /**
     * Links CLM presentations to detail products aligned to training territories
     * and targets those presentations at every training territory.
     */
    public static Integer linkPresentationsToTrainingTerritories() {
        Id trainingRepId = getTerritoryId(ZetaOrganogramTerritoryLoader.TRAINING_REP_EXT);
        Set<Id> territoryIds = collectTrainingAlignmentTerritoryIds(trainingRepId);
        if (territoryIds.isEmpty()) {
            return 0;
        }
        Set<String> territoryKeys = new Set<String>();
        for (Id territoryId : territoryIds) {
            territoryKeys.add(String.valueOf(territoryId));
        }

        Set<Id> productIds = new Set<Id>();
        for (Product_Territory_Alignment__c pta : [
            SELECT Product2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c IN :territoryKeys AND Is_Active__c = true
            WITH SYSTEM_MODE
        ]) {
            try {
                productIds.add((Id) pta.Product2_Id__c);
            } catch (Exception ex) {
                // Skip invalid ids.
            }
        }
        if (productIds.isEmpty()) {
            return 0;
        }

        List<Product2> details = [
            SELECT Id, Name, Product_Type__c
            FROM Product2
            WHERE Id IN :productIds
                AND IsActive = true
                AND (Product_Type__c = 'Detail' OR Product_Type__c = NULL)
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ];
        if (details.isEmpty()) {
            details = [
                SELECT Id, Name, Product_Type__c
                FROM Product2
                WHERE Id IN :productIds AND IsActive = true
                WITH SYSTEM_MODE
                ORDER BY Name ASC
            ];
        }
        return upsertTrainingClmPresentations(territoryIds, details);
    }

    private static Integer upsertTrainingClmPresentations(Set<Id> territoryIds, List<Product2> products) {
        if (products == null || products.isEmpty() || territoryIds == null || territoryIds.isEmpty()) {
            return 0;
        }
        Set<Id> productIds = new Set<Id>();
        for (Product2 product : products) {
            productIds.add(product.Id);
        }
        List<String> territoryIdList = new List<String>();
        for (Id territoryId : territoryIds) {
            territoryIdList.add(String.valueOf(territoryId));
        }

        Map<Id, CLM_Presentation__c> byProduct = new Map<Id, CLM_Presentation__c>();
        for (CLM_Presentation__c existing : [
            SELECT Id, Product__c, Products__c, Territory_Ids__c, Status__c
            FROM CLM_Presentation__c
            WHERE Product__c IN :productIds
            WITH SYSTEM_MODE
        ]) {
            byProduct.put(existing.Product__c, existing);
        }

        List<CLM_Presentation__c> toInsert = new List<CLM_Presentation__c>();
        List<CLM_Presentation__c> toUpdate = new List<CLM_Presentation__c>();
        Integer changed = 0;
        for (Product2 product : products) {
            CLM_Presentation__c presentation = byProduct.get(product.Id);
            if (presentation == null) {
                toInsert.add(
                    new CLM_Presentation__c(
                        Name = product.Name + ' Deck',
                        Status__c = 'Available',
                        Format__c = 'HTML',
                        Product__c = product.Id,
                        Products__c = JSON.serialize(
                            new Map<String, Object>{
                                'productIds' => new List<String>{ String.valueOf(product.Id) },
                                'productNames' => new List<String>{ product.Name }
                            }
                        ),
                        Territory_Ids__c = JSON.serialize(territoryIdList),
                        Allow_Unaligned__c = false,
                        Slide_Count__c = 2
                    )
                );
                continue;
            }
            Boolean dirty = false;
            if (presentation.Product__c != product.Id) {
                presentation.Product__c = product.Id;
                dirty = true;
            }
            if (presentation.Status__c != 'Available') {
                presentation.Status__c = 'Available';
                dirty = true;
            }
            String mergedTerritories = mergeTerritoryIdsJson(presentation.Territory_Ids__c, territoryIdList);
            if (mergedTerritories != presentation.Territory_Ids__c) {
                presentation.Territory_Ids__c = mergedTerritories;
                dirty = true;
            }
            if (dirty) {
                toUpdate.add(presentation);
            }
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
            changed += toInsert.size();
            List<CLM_Sequence__c> sequences = new List<CLM_Sequence__c>();
            for (CLM_Presentation__c pres : toInsert) {
                sequences.add(
                    new CLM_Sequence__c(
                        CLM_Presentation__c = pres.Id,
                        Sequence_Order__c = 1,
                        Sequence_Name__c = 'Introduction',
                        File_Name__c = 'slide-1.html'
                    )
                );
                sequences.add(
                    new CLM_Sequence__c(
                        CLM_Presentation__c = pres.Id,
                        Sequence_Order__c = 2,
                        Sequence_Name__c = 'Product Detail',
                        File_Name__c = 'slide-2.html'
                    )
                );
            }
            insert as system sequences;
        }
        if (!toUpdate.isEmpty()) {
            update as system toUpdate;
            changed += toUpdate.size();
        }
        return changed;
    }

    private static String mergeTerritoryIdsJson(String existingJson, List<String> addIds) {
        Set<String> merged = new Set<String>();
        if (String.isNotBlank(existingJson)) {
            try {
                List<Object> parsed = (List<Object>) JSON.deserializeUntyped(existingJson);
                for (Object item : parsed) {
                    if (item != null) {
                        merged.add(String.valueOf(item));
                    }
                }
            } catch (Exception ex) {
                for (String part : existingJson.split('[;,]')) {
                    if (String.isNotBlank(part)) {
                        merged.add(part.trim());
                    }
                }
            }
        }
        if (addIds != null) {
            merged.addAll(addIds);
        }
        return JSON.serialize(new List<String>(merged));
    }

    @TestVisible
    private static List<ProductSpec> productSpecsForLine(String lineKey) {
        if (lineKey == 'DIAB') {
            return new List<ProductSpec>{
                new ProductSpec('Ec25', 'EMPACOZA 25 MG 30 TAB', 'Cardiovascular', 'EMPACOZA'),
                new ProductSpec('SW100', 'SITASWAY 100 MG 30 TAB', 'Cardiovascular', 'SITASWAY')
            };
        }
        if (lineKey == 'CHC') {
            return new List<ProductSpec>{
                new ProductSpec('DA60030', 'DOZOVA ASHWAGANDA 600 MG 30 CAP', 'Consumer Health', 'DOZOVA'),
                new ProductSpec('DX1', 'DOZOVA MAN MAX 30 TAB', 'Consumer Health', 'DOZOVA')
            };
        }
        if (lineKey == 'GIT') {
            return new List<ProductSpec>{
                new ProductSpec('N40', 'NEXICURE 40 MG 20 TAB', 'Gastroenterology', 'NEXICURE'),
                new ProductSpec('V10', 'VONSECA 10 MG 20 TAB', 'Gastroenterology', 'VONSECA')
            };
        }
        if (lineKey == 'PEDIA') {
            return new List<ProductSpec>{
                new ProductSpec('NX200', 'NEXIBRONCH SYRUP 200ML', 'Consumer Health', 'NEXIBRONCH'),
                new ProductSpec('B2', 'BILASTIGEC SYRUP 120 ML', 'Consumer Health', 'BILASTIGEC')
            };
        }
        return new List<ProductSpec>{
            new ProductSpec(PRODUCT_EXT_PREFIX + '01', 'Zetagliptin Training', 'Cardiovascular', 'Zetagliptin'),
            new ProductSpec(PRODUCT_EXT_PREFIX + '02', 'Zetaneuro Training', 'Neurology', 'Zetaneuro')
        };
    }

    @TestVisible
    private static List<SpecialtyShare> promoSpecialtiesForLine(String lineKey) {
        if (lineKey == 'DIAB') {
            return new List<SpecialtyShare>{
                new SpecialtyShare('Endocrinology', 50),
                new SpecialtyShare('Internal_Medicine', 30),
                new SpecialtyShare('Cardiology', 20)
            };
        }
        if (lineKey == 'CHC') {
            return new List<SpecialtyShare>{
                new SpecialtyShare('General_Practice', 45),
                new SpecialtyShare('Internal_Medicine', 35),
                new SpecialtyShare('Dermatology', 20)
            };
        }
        if (lineKey == 'GIT') {
            return new List<SpecialtyShare>{
                new SpecialtyShare('Gastroenterology', 55),
                new SpecialtyShare('Internal_Medicine', 30),
                new SpecialtyShare('General_Practice', 15)
            };
        }
        if (lineKey == 'PEDIA') {
            return new List<SpecialtyShare>{
                new SpecialtyShare('Paediatrics', 60),
                new SpecialtyShare('Child_Surgery', 25),
                new SpecialtyShare('Child_Orthopaedics', 15)
            };
        }
        List<SpecialtyShare> mixed = new List<SpecialtyShare>();
        List<Decimal> specialtyPct = new List<Decimal>{ 22, 18, 16, 16, 14, 14 };
        for (Integer i = 0; i < SPECIALTIES.size(); i++) {
            mixed.add(new SpecialtyShare(SPECIALTIES[i], specialtyPct[i]));
        }
        return mixed;
    }

    private static Integer ensureProductTerritoryAlignments(Id territoryId, List<Product2> products) {
        if (territoryId == null || products == null || products.isEmpty()) {
            return 0;
        }
        String territoryKey = String.valueOf(territoryId);
        Set<String> existing = new Set<String>();
        for (Product_Territory_Alignment__c pta : [
            SELECT Product2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c = :territoryKey AND Is_Active__c = true
            WITH SYSTEM_MODE
        ]) {
            existing.add(pta.Product2_Id__c);
        }
        List<Product_Territory_Alignment__c> toInsert = new List<Product_Territory_Alignment__c>();
        for (Product2 product : products) {
            String productKey = String.valueOf(product.Id);
            if (existing.contains(productKey)) {
                continue;
            }
            toInsert.add(
                new Product_Territory_Alignment__c(
                    Product2_Id__c = productKey,
                    Territory2_Id__c = territoryKey,
                    Is_Active__c = true,
                    Effective_Start_Date__c = Date.today().addMonths(-1)
                )
            );
            existing.add(productKey);
        }
        insertInBatches(toInsert);
        return toInsert.size();
    }

    private static void deactivateExtraProductAlignments(Id territoryId, List<Product2> keepProducts) {
        if (territoryId == null || keepProducts == null || keepProducts.isEmpty()) {
            return;
        }
        Set<String> keepKeys = new Set<String>();
        for (Product2 product : keepProducts) {
            keepKeys.add(String.valueOf(product.Id));
        }
        String territoryKey = String.valueOf(territoryId);
        List<Product_Territory_Alignment__c> extras = [
            SELECT Id, Is_Active__c, Product2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c = :territoryKey AND Is_Active__c = true
            WITH SYSTEM_MODE
        ];
        List<Product_Territory_Alignment__c> toUpdate = new List<Product_Territory_Alignment__c>();
        for (Product_Territory_Alignment__c pta : extras) {
            if (!keepKeys.contains(pta.Product2_Id__c)) {
                pta.Is_Active__c = false;
                toUpdate.add(pta);
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void removeExtraAccountProductFields(String territoryKey, List<Product2> keepProducts) {
        if (String.isBlank(territoryKey) || keepProducts == null || keepProducts.isEmpty()) {
            return;
        }
        Set<String> keepKeys = new Set<String>();
        for (Product2 product : keepProducts) {
            keepKeys.add(String.valueOf(product.Id));
        }
        List<Account_Territory_Product_Fields__c> extras = [
            SELECT Id, Product2_Id__c
            FROM Account_Territory_Product_Fields__c
            WHERE Territory2_Id__c = :territoryKey
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
        List<Account_Territory_Product_Fields__c> toDelete = new List<Account_Territory_Product_Fields__c>();
        for (Account_Territory_Product_Fields__c row : extras) {
            if (!keepKeys.contains(row.Product2_Id__c)) {
                toDelete.add(row);
            }
        }
        if (toDelete.isEmpty()) {
            return;
        }
        for (Integer i = 0; i < toDelete.size(); i += BATCH_SIZE) {
            Integer last = Math.min(i + BATCH_SIZE, toDelete.size());
            List<Account_Territory_Product_Fields__c> slice = new List<Account_Territory_Product_Fields__c>();
            for (Integer j = i; j < last; j++) {
                slice.add(toDelete[j]);
            }
            Database.delete(slice, false, AccessLevel.SYSTEM_MODE);
        }
    }

    @TestVisible
    private static void seedPromoGrid(Id lineTerritoryId, List<Product2> products, SeedResult result) {
        seedPromoGrid(lineTerritoryId, products, promoSpecialtiesForLine(null), result);
    }

    @TestVisible
    private static void seedPromoGrid(
        Id lineTerritoryId,
        List<Product2> products,
        List<SpecialtyShare> specialties,
        SeedResult result
    ) {
        if (lineTerritoryId == null) {
            return;
        }
        String lineKey = String.valueOf(lineTerritoryId);
        delete as system [
            SELECT Id FROM Promo_Grid_Product_Weight__c WHERE Territory2_Id__c = :lineKey WITH SYSTEM_MODE
        ];
        delete as system [
            SELECT Id FROM Promo_Grid_Specialty_Focus__c WHERE Territory2_Id__c = :lineKey WITH SYSTEM_MODE
        ];
        delete as system [
            SELECT Id FROM Promo_Grid_Class_Targeting__c WHERE Territory2_Id__c = :lineKey WITH SYSTEM_MODE
        ];

        List<Decimal> weights = weightSharesFor(products == null ? 0 : products.size());
        List<Promo_Grid_Product_Weight__c> weightRows = new List<Promo_Grid_Product_Weight__c>();
        Integer productLimit = products == null ? 0 : Math.min(products.size(), weights.size());
        for (Integer i = 0; i < productLimit; i++) {
            weightRows.add(
                new Promo_Grid_Product_Weight__c(
                    Territory2_Id__c = lineKey,
                    Product2__c = products[i].Id,
                    Weight_Percentage__c = weights[i],
                    Unique_Key__c = (lineKey + ':' + String.valueOf(products[i].Id)).left(80)
                )
            );
        }
        if (!weightRows.isEmpty()) {
            insert as system weightRows;
        }
        result.promoWeightCount = weightRows.size();

        List<SpecialtyShare> focus = specialties == null || specialties.isEmpty()
            ? promoSpecialtiesForLine(null)
            : specialties;
        List<Promo_Grid_Specialty_Focus__c> specialtyRows = new List<Promo_Grid_Specialty_Focus__c>();
        for (SpecialtyShare share : focus) {
            specialtyRows.add(
                new Promo_Grid_Specialty_Focus__c(
                    Territory2_Id__c = lineKey,
                    Specialty__c = share.specialty,
                    List_Percentage__c = share.percentage,
                    Unique_Key__c = (lineKey + ':' + share.specialty).left(80)
                )
            );
        }
        if (!specialtyRows.isEmpty()) {
            insert as system specialtyRows;
        }
        result.promoSpecialtyCount = specialtyRows.size();

        List<Decimal> classPct = new List<Decimal>{ 18, 16, 16, 14, 14, 12, 10 };
        List<Decimal> monthlyVisits = new List<Decimal>{ 12, 10, 8, 6, 4, 2, 1 };
        List<Promo_Grid_Class_Targeting__c> classes = new List<Promo_Grid_Class_Targeting__c>();
        for (Integer i = 0; i < CLASS_CODES.size(); i++) {
            classes.add(
                new Promo_Grid_Class_Targeting__c(
                    Territory2_Id__c = lineKey,
                    Class__c = CLASS_CODES[i],
                    List_Percentage__c = classPct[i],
                    Target_Monthly_Visits__c = monthlyVisits[i],
                    Unique_Key__c = (lineKey + ':' + CLASS_CODES[i]).left(40)
                )
            );
        }
        insert as system classes;
        result.promoClassCount = classes.size();
    }

    private static List<Decimal> weightSharesFor(Integer productCount) {
        if (productCount >= 4) {
            return new List<Decimal>{ 40, 30, 20, 10 };
        }
        if (productCount == 3) {
            return new List<Decimal>{ 45, 35, 20 };
        }
        if (productCount == 2) {
            return new List<Decimal>{ 60, 40 };
        }
        if (productCount == 1) {
            return new List<Decimal>{ 100 };
        }
        return new List<Decimal>();
    }

    @TestVisible
    private static Map<String, Account> upsertHcos(Id recordTypeId) {
        Integer count = Test.isRunningTest() ? 2 : HCO_COUNT;
        List<Account> rows = new List<Account>();
        List<String> clinicNames = new List<String>{
            'Training Heart Clinic',
            'Training Endocrine Center',
            'Training Neuro Institute',
            'Training Internal Medicine Hospital',
            'Training Ortho Clinic',
            'Training Pediatrics Hospital',
            'Training Cairo Specialty Clinic',
            'Training Heliopolis Medical Center',
            'Training Nasr City Hospital',
            'Training Maadi Care Clinic',
            'Training Dokki Wellness Center',
            'Training Giza Teaching Hospital'
        };
        for (Integer i = 0; i < count; i++) {
            String ext = HCO_EXT_PREFIX + String.valueOf(i + 1).leftPad(3, '0');
            Account acct = new Account(
                RecordTypeId = recordTypeId,
                Name = clinicNames[Math.mod(i, clinicNames.size())] + ' ' + (i + 1),
                Type = 'Hospital',
                External_ID__c = ext,
                BillingStreet = (12 + i) + ' Training Street',
                BillingCity = 'Cairo',
                BillingState = 'Cairo',
                BillingCountry = 'Egypt',
                BillingPostalCode = '11341',
                BillingLatitude = 30.0444 + (i * 0.004),
                BillingLongitude = 31.2357 + (i * 0.003),
                Account_Status__c = 'Active',
                Institution_Type__c = 'Hospital',
                Tier__c = 'B',
                Phone = '+201204680466'
            );
            rows.add(acct);
        }
        Database.upsert(rows, Account.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        return queryAccountsByPrefix(HCO_EXT_PREFIX);
    }

    @TestVisible
    private static Map<String, Account> upsertPharmacies(Id recordTypeId) {
        if (recordTypeId == null) {
            return new Map<String, Account>();
        }
        Integer count = Test.isRunningTest() ? 2 : PHARMACY_COUNT;
        List<String> pharmacyNames = new List<String>{
            'Training Elezaby Pharmacy',
            'Training Seif Pharmacy',
            'Training 19011 Pharmacy',
            'Training Cairo Care Pharmacy',
            'Training Heliopolis Pharmacy',
            'Training Nasr City Pharmacy',
            'Training Maadi Pharmacy',
            'Training Dokki Pharmacy',
            'Training Giza Pharmacy',
            'Training Mohandessin Pharmacy',
            'Training Zamalek Pharmacy',
            'Training Shubra Pharmacy',
            'Training New Cairo Pharmacy',
            'Training 6th October Pharmacy',
            'Training Hospital Pharmacy',
            'Training Specialty Pharmacy'
        };
        List<String> pharmacyTypes = new List<String>{ 'Retail', 'Chain', 'Hospital', 'Specialty' };
        List<Account> rows = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            String ext = PHARMACY_EXT_PREFIX + String.valueOf(i + 1).leftPad(3, '0');
            Account acct = new Account(
                RecordTypeId = recordTypeId,
                Name = pharmacyNames[Math.mod(i, pharmacyNames.size())] + ' ' + (i + 1),
                Type = 'Pharmacy',
                External_ID__c = ext,
                BillingStreet = (40 + i) + ' Pharmacy Street',
                BillingCity = 'Cairo',
                BillingState = 'Cairo',
                BillingCountry = 'Egypt',
                BillingPostalCode = '11351',
                BillingLatitude = 30.0500 + (i * 0.0035),
                BillingLongitude = 31.2400 + (i * 0.0028),
                Account_Status__c = 'Active',
                Pharmacy_Type__c = pharmacyTypes[Math.mod(i, pharmacyTypes.size())],
                Tier__c = CLASS_CODES[Math.mod(i, CLASS_CODES.size())].substring(0, 1),
                Phone = '+201204680466'
            );
            rows.add(acct);
        }
        Database.upsert(rows, Account.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        return queryAccountsByPrefix(PHARMACY_EXT_PREFIX);
    }

    @TestVisible
    private static Map<String, Account> upsertHcps(Id recordTypeId) {
        Integer count = Test.isRunningTest() ? 6 : HCP_COUNT;
        List<Account> rows = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            String ext = ACCOUNT_EXT_PREFIX + String.valueOf(i + 1).leftPad(3, '0');
            String specialty = SPECIALTIES[Math.mod(i, SPECIALTIES.size())];
            String classCode = CLASS_CODES[Math.mod(i, CLASS_CODES.size())];
            Account acct = new Account(
                RecordTypeId = recordTypeId,
                Salutation = 'Dr.',
                FirstName = FIRST_NAMES[Math.mod(i, FIRST_NAMES.size())],
                LastName = LAST_NAMES[Math.mod(i / FIRST_NAMES.size(), LAST_NAMES.size())] + ' ' + (i + 1),
                PersonEmail = 'training.hcp' + String.valueOf(i + 1) + '@hcp.eg',
                Type = 'Healthcare Provider',
                External_ID__c = ext,
                BillingStreet = (20 + Math.mod(i, 80)) + ' El Merghany St',
                BillingCity = 'Cairo',
                BillingState = 'Cairo',
                BillingCountry = 'Egypt',
                BillingPostalCode = '11361',
                BillingLatitude = 30.087 + ((Math.mod(i, 15) - 7) * 0.006),
                BillingLongitude = 31.324 + ((Math.mod(i, 12) - 6) * 0.005),
                Account_Status__c = 'Active',
                Tier__c = classCode.substring(0, 1),
                Specialty_1__c = specialty,
                Phone = '+201204680466'
            );
            rows.add(acct);
        }
        collectUpsertErrors(
            Database.upsert(rows, Account.External_ID__c, false, AccessLevel.SYSTEM_MODE)
        );
        return queryAccountsByPrefix(ACCOUNT_EXT_PREFIX);
    }

    private static Map<String, Account> queryAccountsByPrefix(String prefix) {
        Map<String, Account> byExt = new Map<String, Account>();
        for (Account acct : [
            SELECT Id, Name, External_ID__c, Type
            FROM Account
            WHERE External_ID__c LIKE :(prefix + '%')
            WITH SYSTEM_MODE
        ]) {
            byExt.put(acct.External_ID__c, acct);
        }
        return byExt;
    }

    private static Map<String, Account> mergeAccountMaps(Map<String, Account> left, Map<String, Account> right) {
        Map<String, Account> merged = new Map<String, Account>();
        if (left != null) {
            merged.putAll(left);
        }
        if (right != null) {
            merged.putAll(right);
        }
        return merged;
    }

    private static Set<Id> collectTrainingAlignmentTerritoryIds(Id trainingRepId) {
        Set<String> extIds = new Set<String>{
            ZetaOrganogramTerritoryLoader.TRAINING_REP_EXT,
            ZetaOrganogramTerritoryLoader.TRAINING_LINE_EXT
        };
        if (trainingRepId != null) {
            extIds.add(String.valueOf(trainingRepId));
        }
        for (ZetaOrganogramTerritoryLoader.TrainingLineSpec spec : ZetaOrganogramTerritoryLoader.trainingLineSpecs()) {
            if (String.isNotBlank(spec.lineExternalId)) {
                extIds.add(spec.lineExternalId);
            }
            if (String.isNotBlank(spec.positionExternalId)) {
                extIds.add(spec.positionExternalId);
            }
            if (String.isNotBlank(spec.districtExternalId)) {
                extIds.add(spec.districtExternalId);
            }
        }
        Set<Id> ids = new Set<Id>();
        if (trainingRepId != null) {
            ids.add(trainingRepId);
        }
        for (Territory2 territory : [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c IN :extIds
            WITH SYSTEM_MODE
        ]) {
            ids.add(territory.Id);
        }
        return ids;
    }

    private static void alignAccountsToTerritories(
        List<Account> allAccounts,
        Map<String, Account> alignedByExt,
        List<Product2> products,
        Set<Id> territoryIds,
        SeedResult result
    ) {
        if (allAccounts == null || allAccounts.isEmpty() || territoryIds == null || territoryIds.isEmpty()) {
            return;
        }
        Set<Id> namedTerritoryIds = loadNamedTrainingTerritoryIds();
        for (Id territoryId : territoryIds) {
            if (territoryId == null || Limits.getQueries() > 85) {
                continue;
            }
            result.otaCount += ensureObjectTerritoryAssociations(allAccounts, territoryId);
            String territoryKey = String.valueOf(territoryId);
            result.atfCount += ensureAccountTerritoryFields(alignedByExt, territoryKey);
            if (!namedTerritoryIds.contains(territoryId)) {
                result.atpfCount += ensureAccountTerritoryProductFields(alignedByExt, territoryKey, products);
            }
        }
    }

    private static Set<Id> loadNamedTrainingTerritoryIds() {
        Set<String> extIds = new Set<String>();
        for (ZetaOrganogramTerritoryLoader.TrainingLineSpec spec : ZetaOrganogramTerritoryLoader.trainingLineSpecs()) {
            if (String.isNotBlank(spec.lineExternalId)) {
                extIds.add(spec.lineExternalId);
            }
            if (String.isNotBlank(spec.positionExternalId)) {
                extIds.add(spec.positionExternalId);
            }
            if (String.isNotBlank(spec.districtExternalId)) {
                extIds.add(spec.districtExternalId);
            }
        }
        Set<Id> ids = new Set<Id>();
        if (extIds.isEmpty()) {
            return ids;
        }
        for (Territory2 territory : [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c IN :extIds
            WITH SYSTEM_MODE
        ]) {
            ids.add(territory.Id);
        }
        return ids;
    }

    private static Integer ensureObjectTerritoryAssociations(List<Account> accounts, Id territoryId) {
        Set<Id> accountIds = new Map<Id, Account>(accounts).keySet();
        Set<Id> alreadyAligned = new Set<Id>();
        for (ObjectTerritory2Association ota : [
            SELECT ObjectId
            FROM ObjectTerritory2Association
            WHERE Territory2Id = :territoryId AND ObjectId IN :accountIds
            WITH SYSTEM_MODE
        ]) {
            alreadyAligned.add(ota.ObjectId);
        }
        List<ObjectTerritory2Association> toInsert = new List<ObjectTerritory2Association>();
        for (Account acct : accounts) {
            if (alreadyAligned.contains(acct.Id)) {
                continue;
            }
            toInsert.add(
                new ObjectTerritory2Association(
                    ObjectId = acct.Id,
                    Territory2Id = territoryId,
                    AssociationCause = 'Territory2Manual'
                )
            );
        }
        insertInBatches(toInsert);
        return toInsert.size();
    }

    @TestVisible
    private static Integer ensureAccountTerritoryFields(Map<String, Account> accountsByExt, String territoryKey) {
        Map<String, Account_Territory_Fields__c> existingByKey = new Map<String, Account_Territory_Fields__c>();
        Set<Id> accountIds = new Map<Id, Account>(accountsByExt.values()).keySet();
        for (Account_Territory_Fields__c atf : [
            SELECT Id, Account__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Account__c IN :accountIds AND Territory2_Id__c = :territoryKey
            WITH SYSTEM_MODE
        ]) {
            existingByKey.put(atf.Account__c + ':' + atf.Territory2_Id__c, atf);
        }

        List<Account_Territory_Fields__c> toUpsert = new List<Account_Territory_Fields__c>();
        List<String> extIds = new List<String>(accountsByExt.keySet());
        extIds.sort();
        Integer index = 0;
        for (String ext : extIds) {
            Account acct = accountsByExt.get(ext);
            String classCode = CLASS_CODES[Math.mod(index, CLASS_CODES.size())];
            String key = acct.Id + ':' + territoryKey;
            Account_Territory_Fields__c atf = existingByKey.containsKey(key)
                ? existingByKey.get(key)
                : new Account_Territory_Fields__c(
                    Account__c = acct.Id,
                    Territory2_Id__c = territoryKey
                );
            atf.Potential__c = classCode.substring(0, 1);
            atf.Penetration__c = classCode.substring(1, 2);
            atf.HCP_Classification__c = classCode;
            atf.Is_Active__c = true;
            atf.Is_KOL__c = Math.mod(index, 9) == 0;
            toUpsert.add(atf);
            index++;
        }
        upsertInBatches(toUpsert);
        return toUpsert.size();
    }

    @TestVisible
    private static Integer ensureAccountTerritoryProductFields(
        Map<String, Account> accountsByExt,
        String territoryKey,
        List<Product2> products
    ) {
        if (products == null || products.isEmpty()) {
            return 0;
        }
        Set<Id> accountIds = new Map<Id, Account>(accountsByExt.values()).keySet();
        Set<String> existingKeys = new Set<String>();
        for (Account_Territory_Product_Fields__c atpf : [
            SELECT Account__c, Territory2_Id__c, Product2_Id__c
            FROM Account_Territory_Product_Fields__c
            WHERE Account__c IN :accountIds AND Territory2_Id__c = :territoryKey
            WITH SYSTEM_MODE
        ]) {
            existingKeys.add(atpf.Account__c + ':' + atpf.Territory2_Id__c + ':' + atpf.Product2_Id__c);
        }

        Map<String, String> frequencyByClass = new Map<String, String>{
            'A1' => 'Weekly',
            'A2' => 'Bi-Weekly',
            'B1' => 'Monthly',
            'B2' => 'Monthly',
            'C1' => 'Quarterly',
            'C2' => 'Quarterly',
            'C3' => 'Quarterly'
        };
        List<String> adoptions = new List<String>{ 'H', 'M', 'L' };
        List<String> loyalties = new List<String>{ 'H', 'M', 'L' };
        List<Account_Territory_Product_Fields__c> toInsert = new List<Account_Territory_Product_Fields__c>();
        List<String> extIds = new List<String>(accountsByExt.keySet());
        extIds.sort();
        Integer index = 0;
        Integer productsPerAccount = Test.isRunningTest() ? 1 : 2;
        for (String ext : extIds) {
            Account acct = accountsByExt.get(ext);
            String classCode = CLASS_CODES[Math.mod(index, CLASS_CODES.size())];
            String frequency = frequencyByClass.containsKey(classCode) ? frequencyByClass.get(classCode) : 'Monthly';
            for (Integer p = 0; p < productsPerAccount && p < products.size(); p++) {
                Product2 product = products[Math.mod(index + p, products.size())];
                String key = acct.Id + ':' + territoryKey + ':' + String.valueOf(product.Id);
                if (existingKeys.contains(key)) {
                    continue;
                }
                toInsert.add(
                    new Account_Territory_Product_Fields__c(
                        Account__c = acct.Id,
                        Territory2_Id__c = territoryKey,
                        Product2_Id__c = String.valueOf(product.Id),
                        Potential__c = Decimal.valueOf(40 - (Math.mod(index, 7) * 4)),
                        Penetration__c = Decimal.valueOf(20 - (Math.mod(index, 7) * 2)),
                        Target_Visit_Frequency__c = frequency,
                        Adoption__c = adoptions[Math.mod(index, adoptions.size())],
                        Loyalty__c = loyalties[Math.mod(index + 1, loyalties.size())],
                        Rx_Per_Week__c = Decimal.valueOf(Math.mod(index + 3, 10) + 1),
                        Is_Active__c = true
                    )
                );
                existingKeys.add(key);
            }
            index++;
        }
        insertInBatches(toInsert);
        return toInsert.size();
    }

    @TestVisible
    private static void ensureAffiliations(Map<String, Account> hcpsByExt, Map<String, Account> hcosByExt) {
        if (hcpsByExt.isEmpty() || hcosByExt.isEmpty()) {
            return;
        }
        List<Account> hcps = hcpsByExt.values();
        List<Account> hcos = hcosByExt.values();
        Set<String> existing = new Set<String>();
        Set<Id> hcpIds = new Map<Id, Account>(hcps).keySet();
        for (Account_Affiliation__c row : [
            SELECT Primary_Account__c, Related_Account__c
            FROM Account_Affiliation__c
            WHERE Primary_Account__c IN :hcpIds
            WITH SYSTEM_MODE
        ]) {
            existing.add(String.valueOf(row.Primary_Account__c) + ':' + String.valueOf(row.Related_Account__c));
        }
        List<Account_Affiliation__c> toInsert = new List<Account_Affiliation__c>();
        for (Integer i = 0; i < hcps.size(); i++) {
            Account hco = hcos[Math.mod(i, hcos.size())];
            String key = String.valueOf(hcps[i].Id) + ':' + String.valueOf(hco.Id);
            if (existing.contains(key)) {
                continue;
            }
            toInsert.add(
                new Account_Affiliation__c(
                    Primary_Account__c = hcps[i].Id,
                    Related_Account__c = hco.Id,
                    Affiliation_Type__c = 'Practice',
                    Role__c = 'Physician',
                    Strength__c = 'Strong',
                    Influence__c = 'High',
                    Is_Active__c = true,
                    Outside_Territory__c = false,
                    Description__c = 'Training list practice affiliation.'
                )
            );
            existing.add(key);
        }
        insertInBatches(toInsert);
    }

    @TestVisible
    private static void ensurePharmacyAffiliations(
        Map<String, Account> hcpsByExt,
        Map<String, Account> pharmaciesByExt
    ) {
        if (hcpsByExt == null || pharmaciesByExt == null || hcpsByExt.isEmpty() || pharmaciesByExt.isEmpty()) {
            return;
        }
        List<Account> hcps = hcpsByExt.values();
        List<Account> pharmacies = pharmaciesByExt.values();
        Set<String> existing = new Set<String>();
        Set<Id> hcpIds = new Map<Id, Account>(hcps).keySet();
        for (Account_Affiliation__c row : [
            SELECT Primary_Account__c, Related_Account__c
            FROM Account_Affiliation__c
            WHERE Primary_Account__c IN :hcpIds
            WITH SYSTEM_MODE
        ]) {
            existing.add(String.valueOf(row.Primary_Account__c) + ':' + String.valueOf(row.Related_Account__c));
        }
        List<Account_Affiliation__c> toInsert = new List<Account_Affiliation__c>();
        for (Integer i = 0; i < hcps.size(); i++) {
            Account pharmacy = pharmacies[Math.mod(i, pharmacies.size())];
            String key = String.valueOf(hcps[i].Id) + ':' + String.valueOf(pharmacy.Id);
            if (existing.contains(key)) {
                continue;
            }
            toInsert.add(
                new Account_Affiliation__c(
                    Primary_Account__c = hcps[i].Id,
                    Related_Account__c = pharmacy.Id,
                    Affiliation_Type__c = 'Affiliate',
                    Role__c = 'Physician',
                    Strength__c = 'Medium',
                    Influence__c = 'Medium',
                    Is_Active__c = true,
                    Outside_Territory__c = false,
                    Description__c = 'Training list pharmacy affiliation.'
                )
            );
            existing.add(key);
        }
        insertInBatches(toInsert);
    }

    private static void seedPlanCycleTargets(Id trainingRepId, SeedResult result) {
        List<UserTerritory2Association> assignments = [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE Territory2Id = :trainingRepId
            WITH SYSTEM_MODE
        ];
        Date monthStart = trainingLocalToday().toStartOfMonth();
        Set<Id> processed = new Set<Id>();
        for (UserTerritory2Association assignment : assignments) {
            if (processed.contains(assignment.UserId)) {
                continue;
            }
            if (Test.isRunningTest() && processed.size() >= 1) {
                break;
            }
            if (Limits.getCpuTime() > 9000 || Limits.getQueries() > 80) {
                break;
            }
            Employee_Time_Card__c timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(
                assignment.UserId,
                monthStart,
                true,
                true
            );
            if (timeCard != null) {
                EmployeeTimeCardService.syncAccountTargets(timeCard.Id);
                result.planCycleUsers++;
            }
            processed.add(assignment.UserId);
        }
        result.targetCount = [
            SELECT COUNT()
            FROM Employee_Time_Card_Account_Target__c
            WHERE Rep__c IN :processed
            AND Employee_Time_Card__r.Time_Card_Month_Start_Date__c = :monthStart
            WITH SYSTEM_MODE
        ];
    }

    /**
     * Seeds completed/planned visits and leaves for training users so home/planner
     * show visit achievement, customer coverage, RF, remaining calls, and TOT.
     */
    public static SeedResult seedTrainingPlannerActivity() {
        return seedTrainingPlannerActivity(null);
    }

    public static SeedResult seedTrainingPlannerActivity(List<Id> remainingUserIds) {
        SeedResult result = new SeedResult();
        List<Id> userIds = remainingUserIds;
        if (userIds == null || userIds.isEmpty()) {
            userIds = loadTrainingActivityUserIds();
        }
        if (userIds.isEmpty()) {
            result.message = 'No training users found for planner activity seed.';
            return result;
        }

        Integer batchSize = Test.isRunningTest() ? 1 : ACTIVITY_USERS_PER_JOB;
        List<Id> batch = new List<Id>();
        List<Id> leftover = new List<Id>();
        for (Integer i = 0; i < userIds.size(); i++) {
            if (batch.size() < batchSize) {
                batch.add(userIds[i]);
            } else {
                leftover.add(userIds[i]);
            }
        }

        Date monthStart = trainingLocalToday().toStartOfMonth();
        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(true);
        try {
            for (Id userId : batch) {
                if (Limits.getCpuTime() > 8000 || Limits.getQueries() > 70) {
                    leftover.add(userId);
                    continue;
                }
                seedUserPlannerActivity(userId, monthStart, result);
            }
        } finally {
            EmployeeTimeCardMetricsService.setSuppressVisitProcessing(false);
        }

        if (!leftover.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new TrainingRepActivityQueueable(leftover));
        }

        result.message =
            'Training activity: visits=' +
            result.visitCount +
            ', leaves=' +
            result.totCount +
            ', users this job=' +
            batch.size() +
            ', remaining=' +
            leftover.size() +
            '.';
        return result;
    }

    private static List<Id> loadTrainingActivityUserIds() {
        Set<Id> userIds = new Set<Id>();
        Set<String> usernames = ZetaOrganogramTerritoryLoader.trainingLineUsernames();
        usernames.add(ZetaOrganogramTerritoryLoader.DEMO_FIELD_REP_USERNAME);
        usernames.add(ZetaOrganogramTerritoryLoader.DEMO_DM_USERNAME);
        for (User person : [
            SELECT Id
            FROM User
            WHERE Username IN :usernames AND IsActive = true
            WITH SYSTEM_MODE
        ]) {
            userIds.add(person.Id);
        }

        Set<Id> trainingTerritoryIds = new Set<Id>();
        Id trainingRepId = getTerritoryId(ZetaOrganogramTerritoryLoader.TRAINING_REP_EXT);
        if (trainingRepId != null) {
            trainingTerritoryIds.add(trainingRepId);
        }
        Id trainingLineId = getTerritoryId(ZetaOrganogramTerritoryLoader.TRAINING_LINE_EXT);
        if (trainingLineId != null) {
            trainingTerritoryIds.add(trainingLineId);
        }
        for (ZetaOrganogramTerritoryLoader.TrainingLineSpec spec : ZetaOrganogramTerritoryLoader.trainingLineSpecs()) {
            Id positionId = getTerritoryId(spec.positionExternalId);
            if (positionId != null) {
                trainingTerritoryIds.add(positionId);
            }
            if (String.isNotBlank(spec.districtExternalId)) {
                Id districtId = getTerritoryId(spec.districtExternalId);
                if (districtId != null) {
                    trainingTerritoryIds.add(districtId);
                }
            }
            Id lineId = getTerritoryId(spec.lineExternalId);
            if (lineId != null) {
                trainingTerritoryIds.add(lineId);
            }
        }

        if (!trainingTerritoryIds.isEmpty()) {
            for (UserTerritory2Association row : [
                SELECT UserId
                FROM UserTerritory2Association
                WHERE Territory2Id IN :trainingTerritoryIds
                AND User.IsActive = true
                WITH SYSTEM_MODE
            ]) {
                userIds.add(row.UserId);
            }
        }
        return new List<Id>(userIds);
    }

    private static void seedUserPlannerActivity(Id userId, Date monthStart, SeedResult result) {
        Employee_Time_Card__c timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(
            userId,
            monthStart,
            true,
            true
        );
        if (timeCard == null) {
            return;
        }
        EmployeeTimeCardService.syncAccountTargets(timeCard.Id);

        Map<String, List<Employee_Time_Card_Account_Target__c>> targetsByClass = loadTargetsByClass(timeCard.Id);
        if (targetsByClass.isEmpty()) {
            result.totCount += seedUserLeaves(userId, monthStart, new Set<Date>());
            return;
        }

        List<Date> workingDays = listWorkingDaysInMonth(monthStart, userId);
        Set<Date> leaveDays = pickLeaveDays(workingDays, userId);
        Date localToday = trainingLocalToday();
        List<Date> visitDays = new List<Date>();
        for (Date workingDay : workingDays) {
            if (workingDay < localToday && !leaveDays.contains(workingDay)) {
                visitDays.add(workingDay);
            }
        }
        if (visitDays.isEmpty() && !workingDays.isEmpty()) {
            for (Date workingDay : workingDays) {
                if (workingDay < localToday) {
                    visitDays.add(workingDay);
                }
            }
        }

        deleteExistingTrainingVisits(userId, monthStart);
        List<Visit__c> visits = buildUserVisits(userId, targetsByClass, visitDays, workingDays, leaveDays);
        if (!visits.isEmpty()) {
            insertInBatches(visits);
            result.visitCount += visits.size();
        }
        EmployeeTimeCardMetricsService.reconcileTimeCard(timeCard.Id);
        result.totCount += seedUserLeaves(userId, monthStart, leaveDays);
    }

    private static Map<String, List<Employee_Time_Card_Account_Target__c>> loadTargetsByClass(Id timeCardId) {
        Map<String, List<Employee_Time_Card_Account_Target__c>> result =
            new Map<String, List<Employee_Time_Card_Account_Target__c>>{
                'A' => new List<Employee_Time_Card_Account_Target__c>(),
                'B' => new List<Employee_Time_Card_Account_Target__c>(),
                'C' => new List<Employee_Time_Card_Account_Target__c>()
            };
        for (Employee_Time_Card_Account_Target__c target : [
            SELECT Id, Account__c, Potentiality__c, Target_Visit_Frequency__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCardId AND Account__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Potentiality__c ASC, Target_Visit_Frequency__c DESC, Id ASC
        ]) {
            String clazz = normalizeClass(target.Potentiality__c);
            if (!result.containsKey(clazz)) {
                continue;
            }
            result.get(clazz).add(target);
        }
        return result;
    }

    @TestVisible
    private static List<Visit__c> buildUserVisits(
        Id userId,
        Map<String, List<Employee_Time_Card_Account_Target__c>> targetsByClass,
        List<Date> visitDays,
        List<Date> workingDays,
        Set<Date> leaveDays
    ) {
        List<Visit__c> visits = new List<Visit__c>();
        List<Date> completedDays = new List<Date>();
        if (visitDays != null) {
            completedDays.addAll(visitDays);
        }
        // Guarantee at least a few past completed days so Actual_Visits / RF are never all-zero.
        if (completedDays.isEmpty()) {
            Date monthStart = trainingLocalToday().toStartOfMonth();
            Date cursor = trainingLocalToday().addDays(-1);
            String department = EmployeeTimeCardFlowHelper.getEmployeeDepartment(userId);
            while (completedDays.size() < 3 && cursor >= monthStart) {
                if (!EmployeeTimeCardFlowHelper.isWeekendDay(cursor, department)) {
                    completedDays.add(cursor);
                }
                cursor = cursor.addDays(-1);
            }
            // Month start edge case: allow completed visits on today so reconcile still fills Actuals.
            if (completedDays.isEmpty()) {
                completedDays.add(trainingLocalToday());
            }
        }

        Integer globalSlot = 0;
        Map<Date, Integer> visitsOnDay = new Map<Date, Integer>();
        Integer accountsPerClass = Test.isRunningTest() ? 2 : ACCOUNTS_PER_CLASS;
        if (!completedDays.isEmpty()) {
            for (String clazz : new List<String>{ 'A', 'B', 'C' }) {
                List<Employee_Time_Card_Account_Target__c> classTargets = targetsByClass.get(clazz);
                if (classTargets == null || classTargets.isEmpty()) {
                    continue;
                }
                Integer limitSize = Math.min(accountsPerClass, classTargets.size());
                for (Integer index = 0; index < limitSize; index++) {
                    Employee_Time_Card_Account_Target__c target = classTargets[index];
                    Integer visitCount = resolveTrainingVisitCount(index, target);
                    for (Integer visitIndex = 0; visitIndex < visitCount; visitIndex++) {
                        Date visitDay = completedDays[Math.mod(globalSlot, completedDays.size())];
                        Integer visitOnDay = visitsOnDay.containsKey(visitDay) ? visitsOnDay.get(visitDay) : 0;
                        visitsOnDay.put(visitDay, visitOnDay + 1);
                        DateTime startDt = trainingLocalDateTime(visitDay, 8, 30).addMinutes(visitOnDay * 70);
                        DateTime endDt = startDt.addMinutes(45);
                        visits.add(
                            new Visit__c(
                                Account__c = target.Account__c,
                                Assigned_To__c = userId,
                                OwnerId = userId,
                                Visit_Date__c = startDt,
                                Start_Date__c = startDt,
                                End_Date__c = endDt,
                                Status__c = 'Completed',
                                Visit_Type__c = 'Planned (Automatically)',
                                Visit_Objective__c = 'Training list call — class ' + clazz + '.',
                                Visit_Notes__c = 'Completed training visit.',
                                Client_Visit_Key__c = (VISIT_KEY_PREFIX +
                                    String.valueOf(userId) +
                                    '_' +
                                    String.valueOf(visitDay.year()) +
                                    String.valueOf(visitDay.month()).leftPad(2, '0') +
                                    String.valueOf(visitDay.day()).leftPad(2, '0') +
                                    '_' +
                                    String.valueOf(globalSlot)).left(80)
                            )
                        );
                        globalSlot++;
                    }
                }
            }
        }

        // Today's Plan: Scheduled stops starting at 11:00 (then ~50 min apart).
        Date planDay = resolveTodayPlanDay(workingDays, leaveDays);
        List<Employee_Time_Card_Account_Target__c> todayAccounts = pickAccountsForTodayPlan(targetsByClass);
        Integer todaySlot = 0;
        for (Employee_Time_Card_Account_Target__c target : todayAccounts) {
            DateTime startDt = trainingLocalDateTime(planDay, 11, 0).addMinutes(todaySlot * 50);
            visits.add(
                new Visit__c(
                    Account__c = target.Account__c,
                    Assigned_To__c = userId,
                    OwnerId = userId,
                    Visit_Date__c = startDt,
                    Start_Date__c = startDt,
                    End_Date__c = startDt.addMinutes(40),
                    Status__c = 'Scheduled',
                    Visit_Type__c = 'Planned (Automatically)',
                    Visit_Objective__c = 'Today\'s plan training stop starting 11:00.',
                    Client_Visit_Key__c = (VISIT_KEY_PREFIX +
                        String.valueOf(userId) +
                        '_TODAY_' +
                        String.valueOf(todaySlot)).left(80)
                )
            );
            todaySlot++;
            globalSlot++;
        }

        // Draft visits (potential activities) for planner / home KPIs.
        Integer draftSlot = 0;
        for (String clazz : new List<String>{ 'A', 'B', 'C' }) {
            List<Employee_Time_Card_Account_Target__c> classTargets = targetsByClass.get(clazz);
            if (classTargets == null || classTargets.size() < 2) {
                continue;
            }
            // Prefer a later account so we don't collide with completed/today slots when possible.
            Integer accountIndex = Math.min(classTargets.size() - 1, Test.isRunningTest() ? 1 : 3);
            Employee_Time_Card_Account_Target__c draftTarget = classTargets[accountIndex];
            Date draftDay = planDay.addDays(1);
            String department = EmployeeTimeCardFlowHelper.getEmployeeDepartment(userId);
            Integer draftGuard = 0;
            while (EmployeeTimeCardFlowHelper.isWeekendDay(draftDay, department) && draftGuard < 7) {
                draftDay = draftDay.addDays(1);
                draftGuard++;
            }
            DateTime startDt = trainingLocalDateTime(draftDay, 10, 0).addMinutes(draftSlot * 60);
            visits.add(
                new Visit__c(
                    Account__c = draftTarget.Account__c,
                    Assigned_To__c = userId,
                    OwnerId = userId,
                    Visit_Date__c = startDt,
                    Start_Date__c = startDt,
                    End_Date__c = startDt.addMinutes(45),
                    Status__c = 'Draft',
                    Visit_Type__c = 'Planned (Automatically)',
                    Visit_Objective__c = 'Draft training visit — class ' + clazz + '.',
                    Client_Visit_Key__c = (VISIT_KEY_PREFIX +
                        String.valueOf(userId) +
                        '_DRAFT_' +
                        String.valueOf(draftSlot)).left(80)
                )
            );
            draftSlot++;
            globalSlot++;
        }

        // One extra future Scheduled beyond today (if available).
        List<Date> futureDays = new List<Date>();
        for (Date workingDay : workingDays) {
            if (
                workingDay > planDay &&
                (leaveDays == null || !leaveDays.contains(workingDay)) &&
                futureDays.size() < 1
            ) {
                futureDays.add(workingDay);
            }
        }
        if (!futureDays.isEmpty()) {
            for (String clazz : new List<String>{ 'A', 'B', 'C' }) {
                List<Employee_Time_Card_Account_Target__c> classTargets = targetsByClass.get(clazz);
                if (classTargets == null || classTargets.isEmpty()) {
                    continue;
                }
                Date visitDay = futureDays[0];
                DateTime startDt = trainingLocalDateTime(visitDay, 9, 0);
                visits.add(
                    new Visit__c(
                        Account__c = classTargets[0].Account__c,
                        Assigned_To__c = userId,
                        OwnerId = userId,
                        Visit_Date__c = startDt,
                        Start_Date__c = startDt,
                        End_Date__c = startDt.addMinutes(45),
                        Status__c = 'Scheduled',
                        Visit_Type__c = 'Planned (Automatically)',
                        Visit_Objective__c = 'Scheduled training follow-up — class ' + clazz + '.',
                        Client_Visit_Key__c = (VISIT_KEY_PREFIX +
                            String.valueOf(userId) +
                            '_FUT_' +
                            clazz).left(80)
                    )
                );
                globalSlot++;
                break;
            }
        }
        return visits;
    }

    @TestVisible
    private static Date resolveTodayPlanDay(List<Date> workingDays, Set<Date> leaveDays) {
        Date today = trainingLocalToday();
        if (
            workingDays != null &&
            workingDays.contains(today) &&
            (leaveDays == null || !leaveDays.contains(today))
        ) {
            return today;
        }
        if (workingDays != null) {
            for (Date workingDay : workingDays) {
                if (workingDay >= today && (leaveDays == null || !leaveDays.contains(workingDay))) {
                    return workingDay;
                }
            }
        }
        return today;
    }

    @TestVisible
    private static List<Employee_Time_Card_Account_Target__c> pickAccountsForTodayPlan(
        Map<String, List<Employee_Time_Card_Account_Target__c>> targetsByClass
    ) {
        List<Employee_Time_Card_Account_Target__c> picks = new List<Employee_Time_Card_Account_Target__c>();
        Integer maxStops = Test.isRunningTest() ? 2 : 3;
        for (String clazz : new List<String>{ 'A', 'B', 'C' }) {
            if (picks.size() >= maxStops) {
                break;
            }
            List<Employee_Time_Card_Account_Target__c> classTargets = targetsByClass.get(clazz);
            if (classTargets == null || classTargets.isEmpty()) {
                continue;
            }
            picks.add(classTargets[0]);
        }
        return picks;
    }

    @TestVisible
    private static Integer resolveTrainingVisitCount(Integer index, Employee_Time_Card_Account_Target__c target) {
        Integer targetFrequency = Integer.valueOf(
            Math.max(1, Math.round(target.Target_Visit_Frequency__c == null ? 1 : target.Target_Visit_Frequency__c))
        );
        if (Test.isRunningTest()) {
            return index == 0 ? 0 : 1;
        }
        if (index == 0) {
            return 0;
        }
        if (index == 1) {
            return 1;
        }
        if (index == 2 || index == 3) {
            return Math.max(1, targetFrequency - 1);
        }
        if (index == 4 || index == 5) {
            return targetFrequency;
        }
        return targetFrequency + 1;
    }

    private static void deleteExistingTrainingVisits(Id userId, Date monthStart) {
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        delete as system [
            SELECT Id
            FROM Visit__c
            WHERE Assigned_To__c = :userId
            AND Client_Visit_Key__c LIKE :(VISIT_KEY_PREFIX + '%')
            AND Start_Date__c >= :trainingLocalDateTime(monthStart, 0, 0)
            AND Start_Date__c < :trainingLocalDateTime(monthEnd.addDays(1), 0, 0)
            WITH SYSTEM_MODE
        ];
    }

    private static Integer seedUserLeaves(Id userId, Date monthStart, Set<Date> leaveDays) {
        delete as system [
            SELECT Id
            FROM Time_Off_Request__c
            WHERE OwnerId = :userId AND Comments__c = :LEAVE_COMMENT
            WITH SYSTEM_MODE
        ];
        Set<Date> days = leaveDays;
        if (days == null || days.isEmpty()) {
            days = pickLeaveDays(listWorkingDaysInMonth(monthStart, userId), userId);
        }
        if (days.isEmpty()) {
            return 0;
        }
        List<Date> ordered = new List<Date>(days);
        ordered.sort();
        List<Time_Off_Request__c> requests = new List<Time_Off_Request__c>();
        List<String> leaveTypes = new List<String>{ 'Annual Vacation', 'Sick Leave' };
        Integer userHash = Math.mod(String.valueOf(userId).hashCode(), 1000);
        if (userHash < 0) {
            userHash += 1000;
        }
        for (Integer i = 0; i < ordered.size(); i++) {
            Date leaveDay = ordered[i];
            Time_Off_Request__c request = new Time_Off_Request__c();
            request.OwnerId = userId;
            request.Type__c = leaveTypes[Math.mod(userHash + i, leaveTypes.size())];
            request.Comments__c = LEAVE_COMMENT;
            request.Stage__c = 'Draft';
            if (i == 0) {
                request.Span_Type__c = 'Full_Day';
                request.Start_Date_Time__c = trainingLocalDateTime(leaveDay, 9, 0);
                request.End_Date_Time__c = trainingLocalDateTime(leaveDay, 17, 0);
                request.Span_Duration__c = 1;
            } else {
                request.Span_Type__c = 'Hours';
                DateTime startDt = trainingLocalDateTime(leaveDay, 13, 0);
                request.Start_Date_Time__c = startDt;
                request.End_Date_Time__c = startDt.addHours(2);
                request.Span_Duration__c = 2;
                request.Span_Duration_Select__c = '2';
            }
            requests.add(request);
        }
        if (requests.isEmpty()) {
            return 0;
        }
        insert as system requests;
        for (Time_Off_Request__c request : requests) {
            request.Stage__c = 'Approved';
        }
        update as system requests;
        return requests.size();
    }

    private static Set<Date> pickLeaveDays(List<Date> workingDays, Id userId) {
        Set<Date> leaveDays = new Set<Date>();
        if (workingDays == null || workingDays.isEmpty()) {
            return leaveDays;
        }
        Integer userHash = Math.mod(String.valueOf(userId).hashCode(), 1000);
        if (userHash < 0) {
            userHash += 1000;
        }
        Date pastLeave = null;
        Date futureLeave = null;
        Date localToday = trainingLocalToday();
        for (Date workingDay : workingDays) {
            if (workingDay < localToday) {
                pastLeave = workingDay;
            } else if (futureLeave == null && workingDay > localToday) {
                futureLeave = workingDay;
            }
        }
        if (pastLeave != null) {
            Integer pastIndex = Math.mod(userHash, Math.max(1, countPastWorkingDays(workingDays)));
            Integer seen = 0;
            for (Date workingDay : workingDays) {
                if (workingDay < localToday) {
                    if (seen == pastIndex) {
                        leaveDays.add(workingDay);
                        break;
                    }
                    seen++;
                }
            }
        }
        if (futureLeave != null && Math.mod(userHash, 2) == 0) {
            leaveDays.add(futureLeave);
        }
        if (leaveDays.isEmpty() && pastLeave != null) {
            leaveDays.add(pastLeave);
        }
        return leaveDays;
    }

    private static Integer countPastWorkingDays(List<Date> workingDays) {
        Integer count = 0;
        Date localToday = trainingLocalToday();
        for (Date workingDay : workingDays) {
            if (workingDay < localToday) {
                count++;
            }
        }
        return count;
    }

    private static List<Date> listWorkingDaysInMonth(Date monthStart, Id employeeId) {
        String department = EmployeeTimeCardFlowHelper.getEmployeeDepartment(employeeId);
        List<Date> workingDays = new List<Date>();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        for (Date cursor = monthStart; cursor <= monthEnd; cursor = cursor.addDays(1)) {
            if (!EmployeeTimeCardFlowHelper.isWeekendDay(cursor, department)) {
                workingDays.add(cursor);
            }
        }
        return workingDays;
    }

    private static String normalizeClass(String value) {
        if (String.isBlank(value)) {
            return 'C';
        }
        String letter = value.trim().toUpperCase().left(1);
        if (letter == 'A' || letter == 'B' || letter == 'C') {
            return letter;
        }
        return 'C';
    }

    private static void insertInBatches(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        for (Integer i = 0; i < records.size(); i += BATCH_SIZE) {
            Integer last = Math.min(i + BATCH_SIZE, records.size());
            List<SObject> slice = new List<SObject>();
            for (Integer j = i; j < last; j++) {
                slice.add(records[j]);
            }
            Database.insert(slice, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void upsertInBatches(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        for (Integer i = 0; i < records.size(); i += BATCH_SIZE) {
            Integer last = Math.min(i + BATCH_SIZE, records.size());
            List<SObject> slice = new List<SObject>();
            for (Integer j = i; j < last; j++) {
                slice.add(records[j]);
            }
            Database.upsert(slice, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void collectUpsertErrors(Database.UpsertResult[] results) {
        lastDmlErrors = new List<String>();
        if (results == null) {
            return;
        }
        for (Database.UpsertResult result : results) {
            if (result != null && !result.isSuccess()) {
                for (Database.Error err : result.getErrors()) {
                    lastDmlErrors.add(err.getStatusCode() + ': ' + err.getMessage());
                }
            }
        }
    }
}