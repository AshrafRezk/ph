/**
 * Demo data for training district managers and their reps.
 *
 * Usage (Execute Anonymous, two separate runs because User updates cannot share a transaction with data DML):
 *   TrainingManagerDemoSeed.alignUsers();
 *   TrainingManagerDemoSeed.run();
 *
 * Per training line: a line book on the district and Cairo positions (HCPs with KOLs, HCOs, pharmacies)
 * with product ratings, a Draft class-engine cycle for the manager, a Submitted cycle per rep for the
 * manager to amend and approve, submitted rep visits, Pending DM accounts, and pending expenses.
 * Idempotent: accounts upsert by External_ID__c, visits by Client_Visit_Key__c.
 */
public without sharing class TrainingManagerDemoSeed {
    public static final String EXT_PREFIX = 'MGR_DEMO_';
    public static final String EXPENSE_PREFIX = 'Training demo';
    private static final String ROLE_MEDICAL_REP = 'Medical Rep';
    private static final String TRAINING_BU_OWNER_USERNAME = 'omar.bazid@zeta-pharma.com';
    private static final List<String> RANKED_CLASSES = new List<String>{
        'A1', 'A1', 'A2', 'A2', 'B1', 'B1', 'B2', 'B2', 'C1', 'C1', 'C2', 'C2', 'C3', 'C3'
    };
    private static final List<String> FIRST_NAMES = new List<String>{
        'Ahmed', 'Mona', 'Karim', 'Heba', 'Tarek', 'Rania', 'Sherif', 'Dina',
        'Hossam', 'Nermine', 'Amr', 'Yasmine', 'Walid', 'Salma', 'Hany', 'Lamia'
    };
    private static final List<String> LAST_NAMES = new List<String>{
        'El Sayed', 'Mostafa', 'Abdelaziz', 'Fouad', 'Hamdy', 'Soliman', 'Ragab', 'Zaki',
        'Nabil', 'Farouk', 'Kamel', 'Shawky', 'Lotfy', 'Hegazy', 'Mansour', 'Ghoneim'
    };

    @TestVisible static Map<String, Id> testManagerIdByKey;
    @TestVisible static Map<String, List<Id>> testRepIdsByKey;

    public class SeedResult {
        public Integer bookAccounts = 0;
        public Integer atfs = 0;
        public Integer atpfs = 0;
        public Integer managerCycles = 0;
        public Integer repCycles = 0;
        public Integer cycleAccounts = 0;
        public Integer visits = 0;
        public Integer pendingAccounts = 0;
        public Integer expenses = 0;
        public List<String> messages = new List<String>();

        public String summary() {
            return 'book=' + bookAccounts + ' atf=' + atfs + ' atpf=' + atpfs +
                ' managerCycles=' + managerCycles + ' repCycles=' + repCycles +
                ' cycleAccounts=' + cycleAccounts + ' visits=' + visits +
                ' pendingAccounts=' + pendingAccounts + ' expenses=' + expenses +
                (messages.isEmpty() ? '' : ' | ' + String.join(messages, ' | '));
        }
    }

    private class LineContext {
        ZetaOrganogramTerritoryLoader.TrainingLineSpec spec;
        Id lineId;
        Id districtId;
        Id positionId;
        Id managerId;
        List<Id> repIds = new List<Id>();
        List<Id> productIds = new List<Id>();
        Map<Id, Decimal> weightByProduct = new Map<Id, Decimal>();
        List<String> specialties = new List<String>();
        Map<String, Decimal> visitsByClass = new Map<String, Decimal>();
        List<Account> book = new List<Account>();
    }

    /** Managers report to the Training BU owner; Cairo reps report to their line manager. */
    public static List<String> alignUsers() {
        List<String> messages = new List<String>();
        List<LineContext> lines = loadLines(messages);
        List<User> owners = [
            SELECT Id FROM User WHERE Username = :TRAINING_BU_OWNER_USERNAME WITH SYSTEM_MODE LIMIT 1
        ];
        Id ownerId = owners.isEmpty() ? null : owners[0].Id;
        Map<Id, User> updates = new Map<Id, User>();
        for (LineContext line : lines) {
            if (line.managerId == null) {
                continue;
            }
            if (ownerId != null && ownerId != line.managerId) {
                updates.put(line.managerId, new User(Id = line.managerId, ManagerId = ownerId));
            }
            for (Id repId : line.repIds) {
                if (repId != line.managerId) {
                    updates.put(repId, new User(Id = repId, ManagerId = line.managerId));
                }
            }
        }
        if (!updates.isEmpty()) {
            Database.SaveResult[] saved = Database.update(updates.values(), false, AccessLevel.SYSTEM_MODE);
            for (Database.SaveResult sr : saved) {
                if (!sr.isSuccess()) {
                    messages.add('User: ' + sr.getErrors()[0].getMessage());
                }
            }
        }
        messages.add('Aligned ' + updates.size() + ' users.');
        return messages;
    }

    public static SeedResult run() {
        return run(null);
    }

    /**
     * phase: books, cycles, visits, completed, approvals, or blank for all. Append ':LINEKEY' (e.g. 'visits:CHC')
     * to limit a phase to one line; visit triggers exceed the SOQL limit when every line runs in one transaction.
     */
    public static SeedResult run(String requested) {
        SeedResult result = new SeedResult();
        String phase = String.isBlank(requested) ? null : requested.substringBefore(':');
        String lineKey = String.isBlank(requested) ? null : requested.substringAfter(':');
        List<LineContext> lines = new List<LineContext>();
        for (LineContext line : loadLines(result.messages)) {
            if (String.isBlank(lineKey) || line.spec.key == lineKey) {
                lines.add(line);
            }
        }
        if (lines.isEmpty()) {
            result.messages.add('No training lines with a manager were found.');
            return result;
        }
        Boolean all = String.isBlank(phase);
        loadPromoGrids(lines);
        if (all || phase == 'books') {
            upsertBooks(lines, result);
        }
        loadBooks(lines, result);
        if (all || phase == 'books') {
            alignBooks(lines, result);
            deactivateSharedDistrictLists(lines);
        }
        if (all || phase == 'cycles') {
            seedCycles(lines, result);
        }
        if (all || phase == 'visits') {
            seedVisits(lines, result, all);
        }
        if (phase == 'completed') {
            seedCompletedVisits(lines, result);
        }
        if (all || phase == 'approvals') {
            seedPendingAccounts(lines, result);
            seedExpenses(lines, result);
        }
        return result;
    }

    private static List<LineContext> loadLines(List<String> messages) {
        List<ZetaOrganogramTerritoryLoader.TrainingLineSpec> specs =
            ZetaOrganogramTerritoryLoader.trainingLineSpecs();
        Set<String> extIds = new Set<String>();
        Set<String> managerUsernames = new Set<String>();
        for (ZetaOrganogramTerritoryLoader.TrainingLineSpec spec : specs) {
            extIds.add(spec.lineExternalId);
            extIds.add(spec.districtExternalId);
            extIds.add(spec.positionExternalId);
            if (String.isNotBlank(spec.managerUsername)) {
                managerUsernames.add(spec.managerUsername.toLowerCase());
            }
        }
        Map<String, Id> territoryIds = new Map<String, Id>();
        for (Territory2 territory : [
            SELECT Id, External_ID__c FROM Territory2 WHERE External_ID__c IN :extIds WITH SYSTEM_MODE
        ]) {
            territoryIds.put(territory.External_ID__c, territory.Id);
        }
        Map<String, Id> managerIds = new Map<String, Id>();
        for (User person : [
            SELECT Id, Username FROM User WHERE Username IN :managerUsernames AND IsActive = TRUE WITH SYSTEM_MODE
        ]) {
            managerIds.put(person.Username.toLowerCase(), person.Id);
        }

        List<LineContext> lines = new List<LineContext>();
        Map<Id, LineContext> byPosition = new Map<Id, LineContext>();
        for (ZetaOrganogramTerritoryLoader.TrainingLineSpec spec : specs) {
            LineContext line = new LineContext();
            line.spec = spec;
            line.lineId = territoryIds.get(spec.lineExternalId);
            line.districtId = territoryIds.get(spec.districtExternalId);
            line.positionId = territoryIds.get(spec.positionExternalId);
            line.managerId = testManagerIdByKey != null
                ? testManagerIdByKey.get(spec.key)
                : managerIds.get(spec.managerUsername == null ? null : spec.managerUsername.toLowerCase());
            if (line.lineId == null || line.districtId == null || line.positionId == null || line.managerId == null) {
                messages.add(spec.key + ': territory or manager missing.');
                continue;
            }
            lines.add(line);
            byPosition.put(line.positionId, line);
        }

        if (testRepIdsByKey != null) {
            for (LineContext line : lines) {
                if (testRepIdsByKey.containsKey(line.spec.key)) {
                    line.repIds.addAll(testRepIdsByKey.get(line.spec.key));
                }
            }
            return lines;
        }
        for (UserTerritory2Association uta : [
            SELECT UserId, Territory2Id
            FROM UserTerritory2Association
            WHERE Territory2Id IN :byPosition.keySet()
                AND RoleInTerritory2 = :ROLE_MEDICAL_REP
                AND User.IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY User.Name
        ]) {
            LineContext line = byPosition.get(uta.Territory2Id);
            if (uta.UserId != line.managerId) {
                line.repIds.add(uta.UserId);
            }
        }
        return lines;
    }

    private static void loadPromoGrids(List<LineContext> lines) {
        Map<String, LineContext> byLineKey = new Map<String, LineContext>();
        for (LineContext line : lines) {
            byLineKey.put(String.valueOf(line.lineId), line);
        }
        for (Promo_Grid_Product_Weight__c weight : [
            SELECT Territory2_Id__c, Product2__c, Weight_Percentage__c
            FROM Promo_Grid_Product_Weight__c
            WHERE Territory2_Id__c IN :byLineKey.keySet() AND Product2__c != NULL AND Weight_Percentage__c > 0
            WITH SYSTEM_MODE
            ORDER BY Weight_Percentage__c DESC
        ]) {
            LineContext line = byLineKey.get(weight.Territory2_Id__c);
            line.productIds.add(weight.Product2__c);
            line.weightByProduct.put(weight.Product2__c, weight.Weight_Percentage__c);
        }
        for (Promo_Grid_Specialty_Focus__c focus : [
            SELECT Territory2_Id__c, Specialty__c
            FROM Promo_Grid_Specialty_Focus__c
            WHERE Territory2_Id__c IN :byLineKey.keySet()
            WITH SYSTEM_MODE
            ORDER BY List_Percentage__c DESC
        ]) {
            byLineKey.get(focus.Territory2_Id__c).specialties.add(focus.Specialty__c);
        }
        for (Promo_Grid_Class_Targeting__c target : [
            SELECT Territory2_Id__c, Class__c, Target_Monthly_Visits__c
            FROM Promo_Grid_Class_Targeting__c
            WHERE Territory2_Id__c IN :byLineKey.keySet()
            WITH SYSTEM_MODE
        ]) {
            byLineKey.get(target.Territory2_Id__c).visitsByClass.put(target.Class__c, target.Target_Monthly_Visits__c);
        }
        for (LineContext line : lines) {
            if (line.specialties.isEmpty()) {
                line.specialties.add('General_Practice');
            }
        }
    }

    // ---------------------------------------------------------------- accounts

    private static void upsertBooks(List<LineContext> lines, SeedResult result) {
        RecordTypes rts = resolveRecordTypes();
        List<Account> rows = new List<Account>();
        Integer lineIndex = 0;
        for (LineContext line : lines) {
            String key = line.spec.key;
            String label = line.spec.lineName.replace(' T', '');
            for (Integer i = 0; i < 8; i++) {
                Integer nameIndex = lineIndex * 4 + i;
                String specialty = specialtyFor(line.specialties, i);
                specialty = hcpSpecialty(specialty);
                rows.add(new Account(
                    RecordTypeId = rts.personRtId,
                    Salutation = 'Dr.',
                    FirstName = FIRST_NAMES[Math.mod(nameIndex, FIRST_NAMES.size())],
                    LastName = LAST_NAMES[Math.mod(nameIndex + 3, LAST_NAMES.size())] + ' (' + label + ')',
                    PersonEmail = ('mgr.demo.' + key + '.hcp' + (i + 1) + '@hcp.eg').toLowerCase(),
                    Type = 'Healthcare Provider',
                    External_ID__c = EXT_PREFIX + key + '_HCP_' + String.valueOf(i + 1).leftPad(2, '0'),
                    Specialty_1__c = specialty,
                    Tier__c = RANKED_CLASSES[i].substring(0, 1),
                    Account_Status__c = 'Active',
                    Account_Stage__c = 'Active',
                    BillingStreet = (10 + i) + ' Abbas El Akkad St',
                    BillingCity = 'Cairo',
                    BillingState = 'Cairo',
                    BillingCountry = 'Egypt',
                    BillingPostalCode = '11371',
                    BillingLatitude = 30.056 + (lineIndex * 0.01) + (i * 0.002),
                    BillingLongitude = 31.338 + (i * 0.002),
                    Phone = '+201204680466'
                ));
            }
            List<String> hcoNames = new List<String>{ ' Specialty Hospital', ' Medical Center', ' Polyclinic' };
            for (Integer i = 0; i < 3; i++) {
                rows.add(new Account(
                    RecordTypeId = rts.hcoRtId,
                    Name = 'Nasr City ' + label + hcoNames[i],
                    Type = 'Hospital',
                    Institution_Type__c = 'Hospital',
                    External_ID__c = EXT_PREFIX + key + '_HCO_' + String.valueOf(i + 1).leftPad(2, '0'),
                    Tier__c = RANKED_CLASSES[8 + i].substring(0, 1),
                    Account_Status__c = 'Active',
                    Account_Stage__c = 'Active',
                    BillingStreet = (50 + i) + ' Makram Ebeid St',
                    BillingCity = 'Cairo',
                    BillingState = 'Cairo',
                    BillingCountry = 'Egypt',
                    BillingPostalCode = '11371',
                    BillingLatitude = 30.060 + (lineIndex * 0.01) + (i * 0.003),
                    BillingLongitude = 31.345 + (i * 0.003),
                    Phone = '+201204680466'
                ));
            }
            List<String> pharmacyNames = new List<String>{ 'El Ezaby ', 'Seif ', 'Misr ' };
            for (Integer i = 0; i < 3; i++) {
                rows.add(new Account(
                    RecordTypeId = rts.pharmacyRtId,
                    Name = pharmacyNames[i] + label + ' Pharmacy Nasr City',
                    Type = 'Pharmacy',
                    Pharmacy_Type__c = i == 0 ? 'Chain' : 'Retail',
                    External_ID__c = EXT_PREFIX + key + '_PH_' + String.valueOf(i + 1).leftPad(2, '0'),
                    Tier__c = RANKED_CLASSES[11 + i].substring(0, 1),
                    Account_Status__c = 'Active',
                    Account_Stage__c = 'Active',
                    BillingStreet = (80 + i) + ' Mostafa El Nahas St',
                    BillingCity = 'Cairo',
                    BillingState = 'Cairo',
                    BillingCountry = 'Egypt',
                    BillingPostalCode = '11371',
                    BillingLatitude = 30.052 + (lineIndex * 0.01) + (i * 0.003),
                    BillingLongitude = 31.350 + (i * 0.003),
                    Phone = '+201204680466'
                ));
            }
            lineIndex++;
        }
        List<Account> personRows = new List<Account>();
        List<Account> businessRows = new List<Account>();
        for (Account row : rows) {
            if (row.RecordTypeId == rts.personRtId) {
                personRows.add(row);
            } else {
                businessRows.add(row);
            }
        }
        collectErrors(Database.upsert(personRows, Account.External_ID__c, false, AccessLevel.SYSTEM_MODE), result, 'HCP');
        collectErrors(Database.upsert(businessRows, Account.External_ID__c, false, AccessLevel.SYSTEM_MODE), result, 'Business');
    }

    private static void loadBooks(List<LineContext> lines, SeedResult result) {
        Map<String, Account> byExt = new Map<String, Account>();
        for (Account acct : [
            SELECT Id, Name, External_ID__c, Specialty_1__c
            FROM Account
            WHERE External_ID__c LIKE :(EXT_PREFIX + '%')
            WITH SYSTEM_MODE
            ORDER BY External_ID__c
        ]) {
            byExt.put(acct.External_ID__c, acct);
        }
        for (LineContext line : lines) {
            String prefix = EXT_PREFIX + line.spec.key + '_';
            for (String accountGroup : new List<String>{ 'HCP_', 'HCO_', 'PH_' }) {
                for (Integer i = 1; i <= 8; i++) {
                    Account acct = byExt.get(prefix + accountGroup + String.valueOf(i).leftPad(2, '0'));
                    if (acct != null) {
                        line.book.add(acct);
                    }
                }
            }
            result.bookAccounts += line.book.size();
        }
    }

    /** The person-account record type restricts Specialty_1__c to a subset of the global value set. */
    private static final Map<String, String> PERSON_RT_SPECIALTY = new Map<String, String>{
        'Endocrinology' => 'Diabetology',
        'Internal_Medicine' => 'Geriatrics',
        'General_Practice' => 'Miscellaneous',
        'Dermatology' => 'Esthetics_and_Cosmetology',
        'Gastroenterology' => 'Gastroenterological_Surgery',
        'Hepatology' => 'Gastroenterological_Surgery',
        'Neurology' => 'Pain_Management',
        'Rheumatology' => 'Orthopaedics'
    };

    private static String hcpSpecialty(String label) {
        if (String.isBlank(label)) {
            return null;
        }
        String value = label.trim().replace(' ', '_');
        return PERSON_RT_SPECIALTY.containsKey(value) ? PERSON_RT_SPECIALTY.get(value) : value;
    }

    private static String specialtyFor(List<String> specialties, Integer index) {
        // Spread 8 HCPs roughly by the promo grid share: 4 / 2 / 2.
        List<Integer> slots = new List<Integer>{ 0, 0, 1, 0, 2, 1, 0, 2 };
        Integer slot = slots[Math.mod(index, slots.size())];
        return specialties[Math.min(slot, specialties.size() - 1)];
    }

    private static Boolean isKol(Integer rank) {
        return rank == 0 || rank == 4;
    }

    private static void alignBooks(List<LineContext> lines, SeedResult result) {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> territoryIds = new Set<Id>();
        Set<String> territoryKeys = new Set<String>();
        for (LineContext line : lines) {
            accountIds.addAll(new Map<Id, Account>(line.book).keySet());
            territoryIds.add(line.districtId);
            territoryIds.add(line.positionId);
        }
        for (Id territoryId : territoryIds) {
            territoryKeys.add(String.valueOf(territoryId));
        }

        Set<String> otaKeys = new Set<String>();
        for (ObjectTerritory2Association ota : [
            SELECT ObjectId, Territory2Id
            FROM ObjectTerritory2Association
            WHERE ObjectId IN :accountIds AND Territory2Id IN :territoryIds
            WITH SYSTEM_MODE
        ]) {
            otaKeys.add(ota.ObjectId + ':' + ota.Territory2Id);
        }
        Map<String, Account_Territory_Fields__c> atfByKey = new Map<String, Account_Territory_Fields__c>();
        for (Account_Territory_Fields__c atf : [
            SELECT Id, Account__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Account__c IN :accountIds AND Territory2_Id__c IN :territoryKeys
            WITH SYSTEM_MODE
        ]) {
            atfByKey.put(atf.Account__c + ':' + atf.Territory2_Id__c, atf);
        }
        Map<String, Account_Territory_Product_Fields__c> atpfByKey =
            new Map<String, Account_Territory_Product_Fields__c>();
        for (Account_Territory_Product_Fields__c atpf : [
            SELECT Id, Account__c, Territory2_Id__c, Product2_Id__c
            FROM Account_Territory_Product_Fields__c
            WHERE Account__c IN :accountIds AND Territory2_Id__c IN :territoryKeys
            WITH SYSTEM_MODE
        ]) {
            atpfByKey.put(atpf.Account__c + ':' + atpf.Territory2_Id__c + ':' + atpf.Product2_Id__c, atpf);
        }

        List<ObjectTerritory2Association> otas = new List<ObjectTerritory2Association>();
        List<Account_Territory_Fields__c> atfs = new List<Account_Territory_Fields__c>();
        List<Account_Territory_Product_Fields__c> atpfs = new List<Account_Territory_Product_Fields__c>();
        for (LineContext line : lines) {
            for (Id territoryId : new List<Id>{ line.districtId, line.positionId }) {
                String territoryKey = String.valueOf(territoryId);
                for (Integer rank = 0; rank < line.book.size(); rank++) {
                    Account acct = line.book[rank];
                    String classCode = RANKED_CLASSES[Math.min(rank, RANKED_CLASSES.size() - 1)];
                    if (!otaKeys.contains(acct.Id + ':' + territoryId)) {
                        otas.add(new ObjectTerritory2Association(
                            ObjectId = acct.Id,
                            Territory2Id = territoryId,
                            AssociationCause = 'Territory2Manual'
                        ));
                    }
                    String atfKey = acct.Id + ':' + territoryKey;
                    Account_Territory_Fields__c atf = atfByKey.containsKey(atfKey)
                        ? atfByKey.get(atfKey)
                        : new Account_Territory_Fields__c(Account__c = acct.Id, Territory2_Id__c = territoryKey);
                    atf.Is_Active__c = true;
                    atf.Is_KOL__c = isKol(rank);
                    atf.HCP_Classification__c = classCode;
                    atf.Potential__c = classCode.substring(0, 1);
                    atf.Penetration__c = classCode.substring(1, 2);
                    atfs.add(atf);

                    Decimal potential = 100 - (rank * 6);
                    Decimal share = 0.72 - (rank * 0.04);
                    for (Integer p = 0; p < line.productIds.size(); p++) {
                        String productKey = String.valueOf(line.productIds[p]);
                        String atpfKey = atfKey + ':' + productKey;
                        Account_Territory_Product_Fields__c atpf = atpfByKey.containsKey(atpfKey)
                            ? atpfByKey.get(atpfKey)
                            : new Account_Territory_Product_Fields__c(
                                Account__c = acct.Id,
                                Territory2_Id__c = territoryKey,
                                Product2_Id__c = productKey,
                                Unique_Key__c = atpfKey.left(80)
                            );
                        Decimal productPotential = potential - (p * 5);
                        atpf.Potential__c = productPotential;
                        atpf.Penetration__c = (productPotential * share).setScale(1);
                        atpf.Geo_Share_Volume_UOM__c = 480 - (rank * 30) - (p * 20);
                        atpf.Sales_Order_Volume_UOM__c = 300 - (rank * 20) - (p * 15);
                        atpf.Is_Active__c = true;
                        atpfs.add(atpf);
                    }
                }
            }
        }
        if (!otas.isEmpty()) {
            Database.insert(otas, false, AccessLevel.SYSTEM_MODE);
        }
        collectErrors(Database.upsert(atfs, false, AccessLevel.SYSTEM_MODE), result, 'ATF');
        collectErrors(Database.upsert(atpfs, false, AccessLevel.SYSTEM_MODE), result, 'ATPF');
        result.atfs = atfs.size();
        result.atpfs = atpfs.size();
    }

    /** The manager's page shows their district list; drop the shared training list left on Diab T DM. */
    private static void deactivateSharedDistrictLists(List<LineContext> lines) {
        Set<String> districtKeys = new Set<String>();
        Set<Id> bookIds = new Set<Id>();
        for (LineContext line : lines) {
            districtKeys.add(String.valueOf(line.districtId));
            bookIds.addAll(new Map<Id, Account>(line.book).keySet());
        }
        List<Account_Territory_Fields__c> stale = [
            SELECT Id
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :districtKeys AND Is_Active__c = TRUE AND Account__c NOT IN :bookIds
            WITH SYSTEM_MODE
            LIMIT 5000
        ];
        for (Account_Territory_Fields__c atf : stale) {
            atf.Is_Active__c = false;
        }
        if (!stale.isEmpty()) {
            Database.update(stale, false, AccessLevel.SYSTEM_MODE);
        }
    }

    // ---------------------------------------------------------------- class engine

    private static void seedCycles(List<LineContext> lines, SeedResult result) {
        String quarter = currentQuarter();
        Set<Id> employeeIds = new Set<Id>();
        for (LineContext line : lines) {
            employeeIds.add(line.managerId);
            employeeIds.addAll(line.repIds);
        }
        // Past-quarter demo cycles with no accounts stay out of the reviewers' pending list.
        rejectEmptyPastCycles(employeeIds);
        Map<Id, Classification_Cycle__c> openByEmployee = new Map<Id, Classification_Cycle__c>();
        for (Classification_Cycle__c cycle : [
            SELECT Id, Employee__c, Status__c
            FROM Classification_Cycle__c
            WHERE Employee__c IN :employeeIds
                AND Quarter__c = :quarter
                AND Status__c IN ('Draft', 'Submitted', 'Rejected')
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate ASC
        ]) {
            openByEmployee.put(cycle.Employee__c, cycle);
        }

        List<Classification_Cycle__c> cycles = new List<Classification_Cycle__c>();
        Map<Id, LineContext> repLine = new Map<Id, LineContext>();
        for (LineContext line : lines) {
            if (!openByEmployee.containsKey(line.managerId)) {
                cycles.add(new Classification_Cycle__c(
                    Employee__c = line.managerId,
                    Territory2_Id__c = String.valueOf(line.districtId),
                    Line_Territory2_Id__c = String.valueOf(line.lineId),
                    Quarter__c = quarter,
                    Status__c = 'Draft'
                ));
                result.managerCycles++;
            }
            for (Id repId : line.repIds) {
                Classification_Cycle__c cycle = openByEmployee.containsKey(repId)
                    ? openByEmployee.get(repId)
                    : new Classification_Cycle__c(Employee__c = repId, Quarter__c = quarter);
                cycle.Territory2_Id__c = String.valueOf(line.positionId);
                cycle.Line_Territory2_Id__c = String.valueOf(line.lineId);
                cycle.Status__c = 'Submitted';
                cycle.Approver__c = line.managerId;
                cycle.Submitted_At__c = System.now().addHours(-2 - line.repIds.indexOf(repId));
                cycle.Planned_Visits__c = plannedVisits(line);
                cycles.add(cycle);
                repLine.put(repId, line);
                result.repCycles++;
            }
        }
        collectErrors(Database.upsert(cycles, false, AccessLevel.SYSTEM_MODE), result, 'Cycle');

        Map<Id, Id> cycleByRep = new Map<Id, Id>();
        for (Classification_Cycle__c cycle : cycles) {
            if (cycle.Id != null && repLine.containsKey(cycle.Employee__c)) {
                cycleByRep.put(cycle.Employee__c, cycle.Id);
            }
        }
        if (cycleByRep.isEmpty()) {
            return;
        }
        List<Classification_Cycle_Account__c> oldRows = [
            SELECT Id FROM Classification_Cycle_Account__c
            WHERE Classification_Cycle__c IN :cycleByRep.values()
            WITH SYSTEM_MODE
        ];
        if (!oldRows.isEmpty()) {
            Database.delete(oldRows, false, AccessLevel.SYSTEM_MODE);
        }

        Set<String> positionKeys = new Set<String>();
        for (LineContext line : repLine.values()) {
            positionKeys.add(String.valueOf(line.positionId));
        }
        Map<String, Id> atfIdByKey = new Map<String, Id>();
        for (Account_Territory_Fields__c atf : [
            SELECT Id, Account__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :positionKeys AND Account__r.External_ID__c LIKE :(EXT_PREFIX + '%')
            WITH SYSTEM_MODE
        ]) {
            atfIdByKey.put(atf.Account__c + ':' + atf.Territory2_Id__c, atf.Id);
        }

        List<Classification_Cycle_Account__c> rows = new List<Classification_Cycle_Account__c>();
        for (Id repId : cycleByRep.keySet()) {
            LineContext line = repLine.get(repId);
            String positionKey = String.valueOf(line.positionId);
            for (Integer rank = 0; rank < line.book.size(); rank++) {
                Account acct = line.book[rank];
                String rxClass = RANKED_CLASSES[Math.min(rank, RANKED_CLASSES.size() - 1)];
                String salesClass = RANKED_CLASSES[Math.min(rank + 1, RANKED_CLASSES.size() - 1)];
                rows.add(new Classification_Cycle_Account__c(
                    Classification_Cycle__c = cycleByRep.get(repId),
                    Account__c = acct.Id,
                    Account_Territory_Fields__c = atfIdByKey.get(acct.Id + ':' + positionKey),
                    Rx_Class__c = rxClass,
                    Sales_Class__c = salesClass,
                    Chosen_Class__c = rxClass,
                    Rx_Score__c = rxScore(line, rank),
                    Sales_Score__c = 300 - (rank * 20),
                    Grid_Frequency__c = line.visitsByClass.containsKey(rxClass) ? line.visitsByClass.get(rxClass) : 1,
                    Sort_Order__c = rank + 1,
                    Specialty_Bucket__c = acct.Specialty_1__c
                ));
            }
        }
        collectErrors(Database.insert(rows, false, AccessLevel.SYSTEM_MODE), result, 'CycleAccount');
        result.cycleAccounts = rows.size();
    }

    private static Decimal rxScore(LineContext line, Integer rank) {
        Decimal potential = 100 - (rank * 6);
        Decimal share = 0.72 - (rank * 0.04);
        Decimal total = 0;
        for (Integer p = 0; p < line.productIds.size(); p++) {
            Decimal weight = line.weightByProduct.get(line.productIds[p]);
            total += (weight == null ? 0 : weight / 100) * (potential - (p * 5)) * share;
        }
        return total.setScale(2);
    }

    private static Decimal plannedVisits(LineContext line) {
        Decimal total = 0;
        for (Integer rank = 0; rank < line.book.size(); rank++) {
            String classCode = RANKED_CLASSES[Math.min(rank, RANKED_CLASSES.size() - 1)];
            total += line.visitsByClass.containsKey(classCode) ? line.visitsByClass.get(classCode) : 1;
        }
        return total;
    }

    /**
     * Rejects Submitted cycles for a past quarter that have no cycle accounts (empty demo cycles such as
     * the old Q3 seed rows). They only clutter reviewers' pending lists. Employee scope is optional.
     * Returns how many cycles were rejected.
     */
    public static Integer rejectEmptyPastCycles(Set<Id> employeeIds) {
        Integer current = quarterRank(currentQuarter());
        List<Classification_Cycle__c> submitted = [
            SELECT Id, Quarter__c, Employee__c
            FROM Classification_Cycle__c
            WHERE Status__c = 'Submitted'
            WITH SYSTEM_MODE
            LIMIT 2000
        ];
        Set<Id> candidateIds = new Set<Id>();
        for (Classification_Cycle__c cycle : submitted) {
            if (employeeIds != null && !employeeIds.contains(cycle.Employee__c)) {
                continue;
            }
            Integer rank = quarterRank(cycle.Quarter__c);
            if (rank != null && rank < current) {
                candidateIds.add(cycle.Id);
            }
        }
        if (candidateIds.isEmpty()) {
            return 0;
        }
        Set<Id> withAccounts = new Set<Id>();
        for (AggregateResult row : [
            SELECT Classification_Cycle__c cycleId
            FROM Classification_Cycle_Account__c
            WHERE Classification_Cycle__c IN :candidateIds
            WITH SYSTEM_MODE
            GROUP BY Classification_Cycle__c
        ]) {
            withAccounts.add((Id) row.get('cycleId'));
        }
        List<Classification_Cycle__c> toReject = new List<Classification_Cycle__c>();
        for (Id cycleId : candidateIds) {
            if (!withAccounts.contains(cycleId)) {
                toReject.add(new Classification_Cycle__c(Id = cycleId, Status__c = 'Rejected'));
            }
        }
        if (!toReject.isEmpty()) {
            Database.update(toReject, false, AccessLevel.SYSTEM_MODE);
        }
        return toReject.size();
    }

    private static Integer quarterRank(String quarter) {
        if (String.isBlank(quarter) || !quarter.startsWith('Q') || quarter.length() < 7) {
            return null;
        }
        String[] parts = quarter.substring(1).split('-');
        if (parts.size() != 2 || !parts[0].isNumeric() || !parts[1].isNumeric()) {
            return null;
        }
        return Integer.valueOf(parts[1]) * 10 + Integer.valueOf(parts[0]);
    }

    private static String currentQuarter() {
        Date today = Date.today();
        return 'Q' + (((today.month() - 1) / 3) + 1) + '-' + today.year();
    }

    // ---------------------------------------------------------------- visits

    /** Completed visits fire heavy completion triggers (~18 queries each), so they run one line per transaction. */
    private static void seedCompletedVisits(List<LineContext> lines, SeedResult result) {
        List<Date> past = pastWorkingDaysThisMonth(4);
        List<Visit__c> visits = new List<Visit__c>();
        for (LineContext line : lines) {
            List<Account> hcps = hcpsOf(line);
            if (hcps.isEmpty()) {
                continue;
            }
            for (Integer n = 0; n < past.size(); n++) {
                Account acct = hcps[Math.mod(n, hcps.size())];
                visits.add(visit(
                    acct.Id, line.managerId, cairo(past[n], 9, 30), 'Completed',
                    'Manager call on own list.',
                    EXT_PREFIX + 'MGR_' + line.managerId + '_C' + n
                ));
            }
        }
        collectErrors(
            Database.upsert(visits, Visit__c.Client_Visit_Key__c, false, AccessLevel.SYSTEM_MODE),
            result,
            'Visit'
        );
        result.visits += visits.size();
    }

    private static List<Account> hcpsOf(LineContext line) {
        List<Account> hcps = new List<Account>();
        for (Account acct : line.book) {
            if (acct.External_ID__c.contains('_HCP_')) {
                hcps.add(acct);
            }
        }
        return hcps;
    }

    private static void seedVisits(List<LineContext> lines, SeedResult result, Boolean includeCompleted) {
        List<Date> upcoming = workingDays(Date.today().addDays(1), 1, 3);
        List<Date> past = includeCompleted ? pastWorkingDaysThisMonth(4) : new List<Date>();
        Date planDay = WorkingCalendarUtil.isWorkingDay(Date.today())
            ? Date.today()
            : workingDays(Date.today().addDays(1), 1, 1)[0];

        List<Visit__c> visits = new List<Visit__c>();
        for (LineContext line : lines) {
            List<Account> hcps = hcpsOf(line);
            if (hcps.isEmpty()) {
                continue;
            }
            for (Integer r = 0; r < line.repIds.size(); r++) {
                Id repId = line.repIds[r];
                for (Integer n = 0; n < upcoming.size(); n++) {
                    Account acct = hcps[Math.mod(r * 3 + n, hcps.size())];
                    visits.add(visit(
                        acct.Id, repId, cairo(upcoming[n], 10 + n, 0), 'Submitted',
                        'Plan submitted for manager approval.',
                        EXT_PREFIX + 'SUB_' + repId + '_' + n
                    ));
                }
            }
            for (Integer n = 0; n < past.size(); n++) {
                Account acct = hcps[Math.mod(n, hcps.size())];
                visits.add(visit(
                    acct.Id, line.managerId, cairo(past[n], 9, 30), 'Completed',
                    'Manager call on own list.',
                    EXT_PREFIX + 'MGR_' + line.managerId + '_C' + n
                ));
            }
            for (Integer n = 0; n < 3; n++) {
                Account acct = line.book[Math.mod(n + 4, line.book.size())];
                visits.add(visit(
                    acct.Id, line.managerId, cairo(planDay, 11, 0).addMinutes(n * 50), 'Scheduled',
                    'Today\'s plan.',
                    EXT_PREFIX + 'MGR_' + line.managerId + '_T' + n
                ));
            }
        }
        collectErrors(
            Database.upsert(visits, Visit__c.Client_Visit_Key__c, false, AccessLevel.SYSTEM_MODE),
            result,
            'Visit'
        );
        result.visits = visits.size();
    }

    private static Visit__c visit(Id accountId, Id userId, Datetime startDt, String status, String objective, String key) {
        Visit__c row = new Visit__c(
            Account__c = accountId,
            Assigned_To__c = userId,
            OwnerId = userId,
            Visit_Date__c = startDt,
            Start_Date__c = startDt,
            End_Date__c = startDt.addMinutes(40),
            Status__c = status,
            Visit_Type__c = 'Planned (Automatically)',
            Visit_Objective__c = objective,
            First_Cycle_Exception_Approved__c = true,
            Client_Visit_Key__c = key.left(80)
        );
        if (status == 'Completed') {
            row.Visit_Notes__c = 'Discussed line brands and follow-up samples.';
        }
        return row;
    }

    /** Cairo wall-clock time (UTC+3). */
    private static Datetime cairo(Date day, Integer hour, Integer minute) {
        return Datetime.newInstanceGmt(day, Time.newInstance(hour, minute, 0, 0)).addHours(-3);
    }

    private static List<Date> workingDays(Date start, Integer step, Integer count) {
        List<Date> days = new List<Date>();
        Date cursor = start;
        Integer guard = 0;
        while (days.size() < count && guard < 40) {
            if (WorkingCalendarUtil.isWorkingDay(cursor)) {
                days.add(cursor);
            }
            cursor = cursor.addDays(step);
            guard++;
        }
        return days;
    }

    private static List<Date> pastWorkingDaysThisMonth(Integer count) {
        List<Date> days = new List<Date>();
        Date monthStart = Date.today().toStartOfMonth();
        for (Date cursor = Date.today().addDays(-1); cursor >= monthStart && days.size() < count; cursor = cursor.addDays(-1)) {
            if (WorkingCalendarUtil.isWorkingDay(cursor)) {
                days.add(cursor);
            }
        }
        return days;
    }

    // ---------------------------------------------------------------- approvals

    private static void seedPendingAccounts(List<LineContext> lines, SeedResult result) {
        RecordTypes rts = resolveRecordTypes();
        Set<Id> repIds = new Set<Id>();
        for (LineContext line : lines) {
            repIds.addAll(line.repIds);
        }
        Map<Id, User> reps = new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :repIds WITH SYSTEM_MODE]);
        List<Account> rows = new List<Account>();
        for (LineContext line : lines) {
            for (Id repId : line.repIds) {
                String repName = reps.containsKey(repId) ? reps.get(repId).Name : 'Rep';
                rows.add(new Account(
                    RecordTypeId = rts.hcoRtId,
                    Name = 'DEMO Pending Approval — ' + repName + ' — Heliopolis Clinic',
                    Type = 'Hospital',
                    Institution_Type__c = 'Hospital',
                    External_ID__c = EXT_PREFIX + 'PEND_' + repId + '_1',
                    OwnerId = repId,
                    Account_Stage__c = 'Pending DM',
                    BillingStreet = '14 El Hegaz St',
                    BillingCity = 'Cairo',
                    BillingCountry = 'Egypt',
                    Phone = '+201204680466'
                ));
                rows.add(new Account(
                    RecordTypeId = rts.pharmacyRtId,
                    Name = 'DEMO Pending Approval — ' + repName + ' — Roxy Pharmacy',
                    Type = 'Pharmacy',
                    Pharmacy_Type__c = 'Retail',
                    External_ID__c = EXT_PREFIX + 'PEND_' + repId + '_2',
                    OwnerId = repId,
                    Account_Stage__c = 'Pending DM',
                    BillingStreet = '3 Ibrahim El Laqqany St',
                    BillingCity = 'Cairo',
                    BillingCountry = 'Egypt',
                    Phone = '+201204680466'
                ));
            }
        }
        collectErrors(Database.upsert(rows, Account.External_ID__c, false, AccessLevel.SYSTEM_MODE), result, 'Pending');
        result.pendingAccounts = rows.size();
    }

    private static void seedExpenses(List<LineContext> lines, SeedResult result) {
        Set<Id> managerIds = new Set<Id>();
        Set<Id> repIds = new Set<Id>();
        for (LineContext line : lines) {
            managerIds.add(line.managerId);
            repIds.addAll(line.repIds);
        }
        List<Employee_Expense__c> old = [
            SELECT Id
            FROM Employee_Expense__c
            WHERE Manager__c IN :managerIds
                AND Status__c IN ('Pending', 'Submitted')
                AND Description__c LIKE :(EXPENSE_PREFIX + '%')
            WITH SYSTEM_MODE
        ];
        if (!old.isEmpty()) {
            Database.delete(old, false, AccessLevel.SYSTEM_MODE);
        }

        Map<Id, User> reps = new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :repIds WITH SYSTEM_MODE]);
        List<Date> days = pastWorkingDaysThisMonth(2);
        if (days.isEmpty()) {
            days.add(Date.today());
        }
        List<Employee_Expense__c> rows = new List<Employee_Expense__c>();
        for (LineContext line : lines) {
            for (Integer r = 0; r < line.repIds.size(); r++) {
                Id repId = line.repIds[r];
                String repName = reps.containsKey(repId) ? reps.get(repId).Name : 'Rep';
                rows.add(new Employee_Expense__c(
                    OwnerId = repId,
                    Manager__c = line.managerId,
                    Type__c = 'Transportation',
                    Amount__c = 320 + (r * 45),
                    Expense_Date__c = days[0],
                    Status__c = 'Submitted',
                    Description__c = EXPENSE_PREFIX + ' — ' + repName + ': taxi between Nasr City clinics'
                ));
                rows.add(new Employee_Expense__c(
                    OwnerId = repId,
                    Manager__c = line.managerId,
                    Type__c = 'Meal',
                    Amount__c = 180 + (r * 30),
                    Expense_Date__c = days[days.size() - 1],
                    Status__c = 'Submitted',
                    Description__c = EXPENSE_PREFIX + ' — ' + repName + ': HCP lunch meeting (' + line.spec.lineName + ')'
                ));
            }
        }
        collectErrors(Database.insert(rows, false, AccessLevel.SYSTEM_MODE), result, 'Expense');
        result.expenses = rows.size();

        List<Employee_Expense__Share> shares = new List<Employee_Expense__Share>();
        for (Employee_Expense__c row : rows) {
            if (row.Id != null) {
                shares.add(new Employee_Expense__Share(
                    ParentId = row.Id,
                    UserOrGroupId = row.Manager__c,
                    AccessLevel = 'Edit',
                    RowCause = Schema.Employee_Expense__Share.RowCause.Manual
                ));
            }
        }
        if (!shares.isEmpty()) {
            Database.insert(shares, false, AccessLevel.SYSTEM_MODE);
        }
    }

    // ---------------------------------------------------------------- helpers

    private class RecordTypes {
        Id personRtId;
        Id hcoRtId;
        Id pharmacyRtId;
    }

    private static RecordTypes resolveRecordTypes() {
        RecordTypes ids = new RecordTypes();
        Map<String, Id> byDevName = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName, IsPersonType
            FROM RecordType
            WHERE SobjectType = 'Account' AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            if (rt.IsPersonType == true) {
                ids.personRtId = rt.Id;
            } else {
                byDevName.put(rt.DeveloperName, rt.Id);
            }
        }
        ids.personRtId = ids.personRtId != null ? ids.personRtId : firstPresent(byDevName, new List<String>{ 'SDO_PersonAccounts', 'PersonAccount', 'Medical_Professional_HCP' });
        ids.hcoRtId = firstPresent(byDevName, new List<String>{ 'Institution_HCO', 'Business_Account' });
        ids.pharmacyRtId = firstPresent(byDevName, new List<String>{ 'Pharmacy', 'Business_Account' });
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

    private static void collectErrors(List<Database.UpsertResult> results, SeedResult result, String label) {
        for (Database.UpsertResult ur : results) {
            if (!ur.isSuccess() && result.messages.size() < 20) {
                result.messages.add(label + ': ' + ur.getErrors()[0].getMessage());
            }
        }
    }

    private static void collectErrors(List<Database.SaveResult> results, SeedResult result, String label) {
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess() && result.messages.size() < 20) {
                result.messages.add(label + ': ' + sr.getErrors()[0].getMessage());
            }
        }
    }
}