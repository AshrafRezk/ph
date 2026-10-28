/**
 * Admin Console import/export for Organizations Final Master List and Target List (All Team) sheets.
 */
public with sharing class TargetMasterListService {
    @TestVisible
    private static Map<Id, Id> territoryOverrideByUser;
    @TestVisible
    private static Map<String, Account> accountOverrideByExt;
    @TestVisible
    private static Map<String, Id> territoryOverrideByProfile;

    private static final Set<String> WORKPLACE_TYPES = new Set<String>{ 'Hospital', 'Contract', 'Polyclinic' };

    public class Stats {
        @AuraEnabled public Long accountCount;
        @AuraEnabled public Long atfCount;
        @AuraEnabled public Long callPlanAtfCount;
    }

    public class ChunkResult {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer errorCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public List<String> errors;
    }

    public class TargetRow {
        @AuraEnabled public Boolean target;
        @AuraEnabled public String code;
        @AuraEnabled public String doctorCode;
        @AuraEnabled public String doctorClinicId;
        @AuraEnabled public String customerName;
        @AuraEnabled public String customerType;
        @AuraEnabled public String specialty;
        @AuraEnabled public String area;
        @AuraEnabled public Decimal defaultFrequency;
        @AuraEnabled public Decimal newFrequency;
        @AuraEnabled public String address;
        @AuraEnabled public String newClass;
        @AuraEnabled public String employeeCode;
        @AuraEnabled public String employeeName;
        @AuraEnabled public String profileCode;
        @AuraEnabled public String profileName;
        @AuraEnabled public String teamCode;
        @AuraEnabled public String teamName;
        @AuraEnabled public String managerName;
        @AuraEnabled public String jobTitle;
    }

    public class ExportPage {
        @AuraEnabled public List<Map<String, Object>> rows;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public String nextId;
    }

    @AuraEnabled
    public static Stats getStats() {
        Stats s = new Stats();
        s.accountCount = [SELECT COUNT() FROM Account];
        s.atfCount = [SELECT COUNT() FROM Account_Territory_Fields__c];
        s.callPlanAtfCount = [
            SELECT COUNT()
            FROM Account_Territory_Fields__c
            WHERE Call_Plan_Visits_Per_Month__c != NULL
        ];
        return s;
    }

    /**
     * Upsert Target List rows onto Account_Territory_Fields__c.
     * Territory = the row's Profile (Territory2.Name), so vacant seats and employees without a
     * Salesforce user still load onto their territory; else the employee's own seat (EmployeeNumber).
     * Matches Account by External_ID__c (Code, CLINIC-*, DOC-*).
     * The class goes on the ATF only: Account.Customer_Class__c belongs to the Master List.
     */
    @AuraEnabled
    public static ChunkResult upsertTargetChunk(List<TargetRow> rows) {
        ChunkResult result = emptyResult();
        if (rows == null || rows.isEmpty()) {
            return result;
        }

        Set<String> employeeCodes = new Set<String>();
        Set<String> accountExtIds = new Set<String>();
        Set<String> profileNames = new Set<String>();
        for (TargetRow row : rows) {
            String emp = normalize(row.employeeCode);
            if (String.isNotBlank(emp) && !emp.toLowerCase().startsWith('vac')) {
                employeeCodes.add(emp);
            }
            if (String.isNotBlank(row.profileName)) {
                profileNames.add(row.profileName.trim());
            }
            accountExtIds.addAll(candidateExternalIds(row));
        }

        Map<String, Id> territoryByProfile = new Map<String, Id>();
        if (territoryOverrideByProfile != null) {
            territoryByProfile.putAll(territoryOverrideByProfile);
        } else if (!profileNames.isEmpty()) {
            for (Territory2 t : [SELECT Id, Name FROM Territory2 WHERE Name IN :profileNames]) {
                territoryByProfile.put(t.Name.trim().toLowerCase(), t.Id);
            }
        }

        Map<String, User> userByEmp = new Map<String, User>();
        if (!employeeCodes.isEmpty()) {
            for (User u : [
                SELECT Id, Name, EmployeeNumber, IsActive
                FROM User
                WHERE EmployeeNumber IN :employeeCodes
            ]) {
                if (String.isNotBlank(u.EmployeeNumber)) {
                    userByEmp.put(u.EmployeeNumber.trim(), u);
                }
            }
        }

        Map<Id, Id> territoryByUser = territoryOverrideByUser != null
            ? territoryOverrideByUser
            : resolvePrimaryTerritories(userByEmp.values());

        Map<String, Account> accountByExt = new Map<String, Account>();
        if (accountOverrideByExt != null) {
            accountByExt.putAll(accountOverrideByExt);
        } else if (!accountExtIds.isEmpty()) {
            for (Account acc : [
                SELECT Id, Name, External_ID__c, Customer_Class__c, Tier__c
                FROM Account
                WHERE External_ID__c IN :accountExtIds
            ]) {
                if (String.isNotBlank(acc.External_ID__c)) {
                    accountByExt.put(acc.External_ID__c, acc);
                }
            }
            // Doctors merged by the Doctor specialty merger keep their old code on the kept doctor.
            Set<String> missing = new Set<String>(accountExtIds);
            missing.removeAll(accountByExt.keySet());
            Map<String, Id> merged = DoctorSpecialtyMergeService.survivorsForMergedCodes(missing);
            if (!merged.isEmpty()) {
                Map<Id, Account> survivors = new Map<Id, Account>([
                    SELECT Id, Name, External_ID__c, Customer_Class__c, Tier__c
                    FROM Account
                    WHERE Id IN :merged.values()
                ]);
                for (String code : merged.keySet()) {
                    accountByExt.put(code, survivors.get(merged.get(code)));
                }
            }
        }

        Set<String> atfKeys = new Set<String>();
        List<Account_Territory_Fields__c> pendingAtf = new List<Account_Territory_Fields__c>();

        for (TargetRow row : rows) {
            String emp = normalize(row.employeeCode);
            String profile = normalize(row.profileName).toLowerCase();
            Id territoryId = String.isBlank(profile) ? null : territoryByProfile.get(profile);
            if (territoryId == null) {
                if (String.isBlank(emp) || emp.toLowerCase().startsWith('vac')) {
                    result.skippedCount++;
                    if (String.isNotBlank(emp)) {
                        result.errors.add('No territory named "' + normalize(row.profileName) + '" for vacant ' + emp);
                    }
                    continue;
                }
                User u = userByEmp.get(emp);
                if (u == null) {
                    result.skippedCount++;
                    result.errors.add('No user for Employee Code ' + emp + ' and no territory named "' + normalize(row.profileName) + '"');
                    continue;
                }
                territoryId = territoryByUser.get(u.Id);
                if (territoryId == null) {
                    result.skippedCount++;
                    result.errors.add('No territory for ' + emp + ' (' + u.Name + ')');
                    continue;
                }
            }

            Account acc = resolveAccount(row, accountByExt);
            if (acc == null) {
                result.skippedCount++;
                result.errors.add('No account for Code ' + normalize(row.code));
                continue;
            }

            String key = String.valueOf(acc.Id) + '_' + String.valueOf(territoryId);
            if (key.length() > 40) {
                key = key.left(40);
            }
            if (atfKeys.contains(key)) {
                result.skippedCount++;
                continue;
            }
            atfKeys.add(key);

            Decimal visits = row.newFrequency != null ? row.newFrequency : row.defaultFrequency;
            Boolean isTarget = row.target != false;
            String cls = normalize(row.newClass);
            String tier = AccountMasterImportUtil.mapTierFromClass(cls);

            Account_Territory_Fields__c atf = new Account_Territory_Fields__c(
                Account__c = acc.Id,
                Territory2_Id__c = String.valueOf(territoryId),
                Unique_Key__c = key,
                Is_Active__c = isTarget,
                // Classification__c is length 1 (A/B/C); full A1–C3 goes on HCP_Classification__c.
                Classification__c = tier,
                HCP_Classification__c = String.isBlank(cls) ? null : cls.left(10),
                Potential__c = tier,
                Call_Plan_Visits_Per_Month__c = visits
            );
            pendingAtf.add(atf);
        }

        if (!pendingAtf.isEmpty()) {
            upsertAtf(pendingAtf, result);
        }

        trimErrors(result);
        return result;
    }

    @AuraEnabled
    public static ExportPage exportMasterPage(String afterId, Integer pageSize) {
        Integer size = pageSize == null || pageSize < 1 ? 2000 : Math.min(pageSize, 2000);
        ExportPage page = new ExportPage();
        page.rows = new List<Map<String, Object>>();

        String soql =
            'SELECT Id, External_ID__c, Name, RecordType.DeveloperName, Institution_Type__c, Specialty_1__c, ' +
            'BillingStreet, BillingCity, Customer_Class__c, Account_Status__c, Phone, Pharmacy_Code__c ' +
            'FROM Account ';
        if (String.isNotBlank(afterId)) {
            soql += 'WHERE Id > :afterId ';
        }
        soql += 'ORDER BY Id LIMIT :size';
        List<Account> accounts = Database.query(soql);

        // Practice links for this page: doctor (primary) works at clinic/hospital (related).
        Set<Id> pageIds = new Map<Id, Account>(accounts).keySet();
        Map<Id, Account_Affiliation__c> doctorByWorkplace = new Map<Id, Account_Affiliation__c>();
        Map<Id, Account_Affiliation__c> workplaceByDoctor = new Map<Id, Account_Affiliation__c>();
        Map<Id, Integer> doctorCountByWorkplace = new Map<Id, Integer>();
        Set<Id> doctorsWithClinic = new Set<Id>();
        Set<Id> clinicDoctorIds = new Set<Id>();
        if (!pageIds.isEmpty()) {
            for (Account_Affiliation__c aff : [
                SELECT
                    Primary_Account__c,
                    Primary_Account__r.External_ID__c,
                    Primary_Account__r.Name,
                    Primary_Account__r.Specialty_1__c,
                    Related_Account__c,
                    Related_Account__r.External_ID__c,
                    Related_Account__r.Name,
                    Related_Account__r.Institution_Type__c
                FROM Account_Affiliation__c
                WHERE
                    Is_Active__c = TRUE
                    AND (Primary_Account__c IN :pageIds
                    OR Related_Account__c IN :pageIds)
                ORDER BY CreatedDate
            ]) {
                if (pageIds.contains(aff.Primary_Account__c) && aff.Related_Account__r?.Institution_Type__c == 'Clinic') {
                    doctorsWithClinic.add(aff.Primary_Account__c);
                }
                if (pageIds.contains(aff.Related_Account__c) && aff.Related_Account__r?.Institution_Type__c == 'Clinic') {
                    clinicDoctorIds.add(aff.Primary_Account__c);
                }
                if (pageIds.contains(aff.Related_Account__c)) {
                    if (!doctorByWorkplace.containsKey(aff.Related_Account__c)) {
                        doctorByWorkplace.put(aff.Related_Account__c, aff);
                    }
                    Integer n = doctorCountByWorkplace.get(aff.Related_Account__c);
                    doctorCountByWorkplace.put(aff.Related_Account__c, n == null ? 1 : n + 1);
                }
                if (pageIds.contains(aff.Primary_Account__c) && !workplaceByDoctor.containsKey(aff.Primary_Account__c)) {
                    workplaceByDoctor.put(aff.Primary_Account__c, aff);
                }
            }
        }
        Map<Id, Account_Affiliation__c> polyclinicByDoctor = workplaceAffiliations(clinicDoctorIds);

        for (Account acc : accounts) {
            page.nextId = acc.Id;
            String orgType = mapOrgType(acc);
            Boolean isDoctor = acc.RecordType?.DeveloperName == 'PersonAccount';
            Boolean isClinic = acc.Institution_Type__c == 'Clinic';
            // Zeta's master list has one row per doctor clinic; a doctor with a clinic is already
            // exported on that clinic row, so only doctors without any clinic get a row of their own.
            if (isDoctor && doctorsWithClinic.contains(acc.Id)) {
                continue;
            }
            Account_Affiliation__c clinicDoctor = isClinic ? doctorByWorkplace.get(acc.Id) : null;
            Account_Affiliation__c doctorWorkplace = isDoctor ? workplaceByDoctor.get(acc.Id) : null;
            Account_Affiliation__c firstDoctor = isClinic ? null : doctorByWorkplace.get(acc.Id);

            String doctorCode = null;
            String clinicId = null;
            String specialty = null;
            String name = acc.Name;
            String code = acc.External_ID__c;
            if (isDoctor) {
                doctorCode = stripPrefix(acc.External_ID__c, AccountMasterImportUtil.EXT_DOC_PREFIX);
                clinicId = stripPrefix(doctorWorkplace?.Related_Account__r?.External_ID__c, AccountMasterImportUtil.EXT_CLINIC_PREFIX);
                specialty = acc.Specialty_1__c;
            } else if (isClinic) {
                // Same shape as the Zeta master list: "{Doctor Code} - {Clinic ID}", doctor name, doctor specialty.
                clinicId = stripPrefix(acc.External_ID__c, AccountMasterImportUtil.EXT_CLINIC_PREFIX);
                doctorCode = stripPrefix(clinicDoctor?.Primary_Account__r?.External_ID__c, AccountMasterImportUtil.EXT_DOC_PREFIX);
                specialty = clinicDoctor?.Primary_Account__r?.Specialty_1__c;
                if (clinicDoctor != null) {
                    name = clinicDoctor.Primary_Account__r.Name;
                    code = String.isBlank(doctorCode) ? code : doctorCode + ' - ' + clinicId;
                }
            } else if (orgType == 'Pharmacy') {
                name = AccountMasterImportUtil.pharmacyMasterName(acc.Pharmacy_Code__c, acc.Name);
            }
            // "Account" = polyclinic / hospital the doctor works in (master-list column).
            String workplace = isDoctor
                ? doctorWorkplace?.Related_Account__r?.Name
                : (clinicDoctor == null ? null : polyclinicByDoctor.get(clinicDoctor.Primary_Account__c)?.Related_Account__r?.Name);

            Map<String, Object> row = new Map<String, Object>();
            row.put('Code', code);
            row.put('Doctor Code', doctorCode);
            row.put('Doctor Clinic ID', clinicId);
            row.put('Name', name);
            row.put('Account', workplace);
            row.put('Organization Type Name', orgType);
            row.put('Organization Type Code', orgType);
            row.put('Type', null);
            row.put('Clinic Group Type Name', null);
            row.put('Specialty', specialtyForExport(specialty));
            row.put('Area', acc.BillingCity);
            row.put('Address', acc.BillingStreet);
            row.put('Class', acc.Customer_Class__c);
            row.put('Doctors', isDoctor ? null : doctorCountByWorkplace.get(acc.Id));
            row.put(
                'Organization Doctor Code',
                firstDoctor == null
                    ? null
                    : stripPrefix(firstDoctor.Primary_Account__r.External_ID__c, AccountMasterImportUtil.EXT_DOC_PREFIX)
            );
            row.put('Organization Doctor Name', firstDoctor?.Primary_Account__r?.Name);
            row.put('HasLocation', false);
            row.put('Active', acc.Account_Status__c != 'Inactive');
            row.put('Telephone', acc.Phone);
            row.put('Email', null);
            page.rows.add(row);
        }
        page.hasMore = accounts.size() == size;
        return page;
    }

    @AuraEnabled
    public static ExportPage exportTargetPage(String afterId, Integer pageSize) {
        Integer size = pageSize == null || pageSize < 1 ? 2000 : Math.min(pageSize, 2000);
        ExportPage page = new ExportPage();
        page.rows = new List<Map<String, Object>>();

        String soql =
            'SELECT Id, Account__c, Account__r.External_ID__c, Account__r.Name, Account__r.RecordType.DeveloperName, ' +
            'Account__r.Institution_Type__c, Account__r.Specialty_1__c, Account__r.Pharmacy_Code__c, ' +
            'Account__r.BillingStreet, Account__r.BillingCity, Account__r.Customer_Class__c, ' +
            'Territory2_Id__c, Classification__c, HCP_Classification__c, Call_Plan_Visits_Per_Month__c, Is_Active__c ' +
            'FROM Account_Territory_Fields__c ' +
            'WHERE (Call_Plan_Visits_Per_Month__c != NULL OR Is_Active__c = TRUE) ';
        if (String.isNotBlank(afterId)) {
            soql += 'AND Id > :afterId ';
        }
        soql += 'ORDER BY Id LIMIT :size';
        List<Account_Territory_Fields__c> atfs = Database.query(soql);

        Set<Id> doctorIds = new Set<Id>();
        for (Account_Territory_Fields__c atf : atfs) {
            if (atf.Account__r?.RecordType?.DeveloperName == 'PersonAccount') {
                doctorIds.add(atf.Account__c);
            }
        }
        Map<Id, Account_Affiliation__c> clinicByDoctor = new Map<Id, Account_Affiliation__c>();
        if (!doctorIds.isEmpty()) {
            for (Account_Affiliation__c aff : [
                SELECT Primary_Account__c, Related_Account__r.External_ID__c
                FROM Account_Affiliation__c
                WHERE Is_Active__c = TRUE AND Primary_Account__c IN :doctorIds AND Related_Account__r.Institution_Type__c = 'Clinic'
                ORDER BY CreatedDate
            ]) {
                if (!clinicByDoctor.containsKey(aff.Primary_Account__c)) {
                    clinicByDoctor.put(aff.Primary_Account__c, aff);
                }
            }
        }
        Map<Id, Account_Affiliation__c> polyclinicByDoctor = workplaceAffiliations(doctorIds);

        // Whole territory tree (~1,000 rows): Profile = position, Team = its Line, Manager = seat above.
        Map<Id, Territory2> territories = new Map<Id, Territory2>(
            [SELECT Id, Name, ParentTerritory2Id, Territory_Type__c FROM Territory2]
        );
        Map<Id, UserTerritory2Association> utaByTerritory = new Map<Id, UserTerritory2Association>();
        for (UserTerritory2Association uta : [
            SELECT Territory2Id, UserId, User.Name, User.EmployeeNumber, User.Title, User.Manager.Name, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE User.IsActive = TRUE
        ]) {
            UserTerritory2Association existing = utaByTerritory.get(uta.Territory2Id);
            if (existing == null || preferRep(uta.RoleInTerritory2, existing.RoleInTerritory2)) {
                utaByTerritory.put(uta.Territory2Id, uta);
            }
        }

        for (Account_Territory_Fields__c atf : atfs) {
            Account acc = atf.Account__r;
            String customerType = mapCustomerType(acc);
            Boolean isDoctor = acc?.RecordType?.DeveloperName == 'PersonAccount';
            String doctorCode = isDoctor ? stripPrefix(acc.External_ID__c, AccountMasterImportUtil.EXT_DOC_PREFIX) : null;
            String clinicId = null;
            String code = acc?.External_ID__c;
            if (isDoctor) {
                clinicId = stripPrefix(
                    clinicByDoctor.get(atf.Account__c)?.Related_Account__r?.External_ID__c,
                    AccountMasterImportUtil.EXT_CLINIC_PREFIX
                );
                code = String.isBlank(clinicId) ? doctorCode : doctorCode + ' - ' + clinicId;
            } else if (acc?.Institution_Type__c == 'Clinic') {
                clinicId = stripPrefix(acc.External_ID__c, AccountMasterImportUtil.EXT_CLINIC_PREFIX);
            }
            String customerName = customerType == 'Pharmacy'
                ? AccountMasterImportUtil.pharmacyMasterName(acc.Pharmacy_Code__c, acc.Name)
                : acc?.Name;

            Id terrId = null;
            try {
                terrId = String.isBlank(atf.Territory2_Id__c) ? null : (Id) atf.Territory2_Id__c;
            } catch (Exception e) {
                terrId = null;
            }
            Territory2 terr = terrId == null ? null : territories.get(terrId);
            UserTerritory2Association uta = terrId == null ? null : utaByTerritory.get(terrId);
            Territory2 line = ancestorOfType(terr, 'Line', territories);
            String manager = uta?.User?.Manager?.Name;
            if (String.isBlank(manager) && terr != null) {
                manager = utaByTerritory.get(terr.ParentTerritory2Id)?.User?.Name;
            }

            Map<String, Object> row = new Map<String, Object>();
            row.put('Target', atf.Is_Active__c == true);
            row.put('Code', code);
            row.put('Doctor Code', doctorCode);
            row.put('Doctor Clinic ID', clinicId);
            row.put('Customer Name', customerName);
            row.put('Clinic Group', isDoctor ? polyclinicByDoctor.get(atf.Account__c)?.Related_Account__r?.Name : null);
            row.put('Customer Type', customerType);
            row.put('Specialty', isDoctor ? specialtyForExport(acc.Specialty_1__c) : null);
            row.put('Geographical Area Name', acc?.BillingCity);
            row.put('Default Frequency', atf.Call_Plan_Visits_Per_Month__c);
            row.put('New Frequency', atf.Call_Plan_Visits_Per_Month__c);
            row.put('Address', acc?.BillingStreet);
            row.put('Doctors', null);
            row.put(
                'New Class',
                String.isNotBlank(atf.HCP_Classification__c)
                    ? atf.HCP_Classification__c
                    : (String.isNotBlank(atf.Classification__c) ? atf.Classification__c : acc?.Customer_Class__c)
            );
            row.put('Employee Code', uta?.User?.EmployeeNumber);
            row.put('Employee Name', uta == null ? (terr == null ? null : 'VACANT') : uta.User.Name);
            // Zeta's own profile / team codes (e.g. CH13, CH01) are not stored in Salesforce.
            row.put('Profile Code', null);
            row.put('Profile', terr?.Name);
            row.put('Team Code', null);
            row.put('Team Name', line?.Name);
            row.put('Manager Name', manager);
            row.put('Job Title', String.isNotBlank(uta?.User?.Title) ? uta.User.Title : uta?.RoleInTerritory2);
            page.rows.add(row);
            page.nextId = atf.Id;
        }
        page.hasMore = atfs.size() == size;
        return page;
    }

    private static Territory2 ancestorOfType(Territory2 start, String territoryType, Map<Id, Territory2> territories) {
        Territory2 cur = start;
        Integer guard = 0;
        while (cur != null && guard < 10) {
            if (cur.Territory_Type__c == territoryType) {
                return cur;
            }
            cur = cur.ParentTerritory2Id == null ? null : territories.get(cur.ParentTerritory2Id);
            guard++;
        }
        return null;
    }

    /** First active link from each doctor to a hospital / contract / polyclinic (master "Account" column). */
    private static Map<Id, Account_Affiliation__c> workplaceAffiliations(Set<Id> doctorIds) {
        Map<Id, Account_Affiliation__c> byDoctor = new Map<Id, Account_Affiliation__c>();
        if (doctorIds == null || doctorIds.isEmpty()) {
            return byDoctor;
        }
        for (Account_Affiliation__c aff : [
            SELECT Primary_Account__c, Related_Account__r.Name
            FROM Account_Affiliation__c
            WHERE
                Is_Active__c = TRUE
                AND Primary_Account__c IN :doctorIds
                AND Related_Account__r.Institution_Type__c IN :WORKPLACE_TYPES
            ORDER BY CreatedDate
        ]) {
            if (!byDoctor.containsKey(aff.Primary_Account__c)) {
                byDoctor.put(aff.Primary_Account__c, aff);
            }
        }
        return byDoctor;
    }

    private static String specialtyForExport(String picklistValue) {
        String excel = AccountMasterImportUtil.excelSpecialty(picklistValue);
        return excel == null ? picklistValue : excel;
    }

    private static Boolean preferRep(String candidateRole, String existingRole) {
        Boolean candRep = candidateRole != null && candidateRole.toLowerCase().contains('rep');
        Boolean existRep = existingRole != null && existingRole.toLowerCase().contains('rep');
        return candRep && !existRep;
    }

    private static Map<Id, Id> resolvePrimaryTerritories(List<User> users) {
        Map<Id, Id> territoryByUser = new Map<Id, Id>();
        if (users == null || users.isEmpty()) {
            return territoryByUser;
        }
        Set<Id> userIds = new Set<Id>();
        for (User u : users) {
            userIds.add(u.Id);
        }
        Map<Id, String> roleByUser = new Map<Id, String>();
        for (UserTerritory2Association uta : [
            SELECT UserId, Territory2Id, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId IN :userIds
            ORDER BY UserId
        ]) {
            if (!territoryByUser.containsKey(uta.UserId)) {
                territoryByUser.put(uta.UserId, uta.Territory2Id);
                roleByUser.put(uta.UserId, uta.RoleInTerritory2);
            } else if (preferRep(uta.RoleInTerritory2, roleByUser.get(uta.UserId))) {
                territoryByUser.put(uta.UserId, uta.Territory2Id);
                roleByUser.put(uta.UserId, uta.RoleInTerritory2);
            }
        }
        return territoryByUser;
    }

    /**
     * External ids to query for a target row. Order is not a match priority —
     * resolveAccount applies the deterministic customer-type rule.
     *
     * Doctor rows never include bare clinic/doctor numbers (those collide with pharmacy codes).
     * Org rows match Code only.
     */
    private static Set<String> candidateExternalIds(TargetRow row) {
        Set<String> ids = new Set<String>();
        String customerType = normalize(row.customerType).toLowerCase();
        String code = AccountMasterImportUtil.normalizeCode(row.code);
        String doctorCode = AccountMasterImportUtil.normalizeCode(row.doctorCode);
        String clinicId = AccountMasterImportUtil.normalizeCode(row.doctorClinicId);

        if (customerType == 'doctor') {
            if (String.isNotBlank(doctorCode)) {
                ids.add(AccountMasterImportUtil.doctorExternalId(doctorCode));
            }
            if (String.isNotBlank(clinicId)) {
                ids.add(AccountMasterImportUtil.clinicExternalId(clinicId));
            }
            return ids;
        }

        // Pharmacy, Hospital, Contract, Distributor (and blank type): Code as External_ID__c.
        if (String.isNotBlank(code)) {
            ids.add(code);
        }
        return ids;
    }

    /**
     * Pharmacy / Hospital / Contract / Distributor → Code only.
     * Doctor → DOC-{Doctor Code}, else CLINIC-{Doctor Clinic ID}. Never bare numbers.
     */
    @TestVisible
    private static Account resolveAccount(TargetRow row, Map<String, Account> byExt) {
        if (byExt == null || byExt.isEmpty()) {
            return null;
        }
        String customerType = normalize(row.customerType).toLowerCase();
        String code = AccountMasterImportUtil.normalizeCode(row.code);
        String doctorCode = AccountMasterImportUtil.normalizeCode(row.doctorCode);
        String clinicId = AccountMasterImportUtil.normalizeCode(row.doctorClinicId);

        if (customerType == 'doctor') {
            if (String.isNotBlank(doctorCode)) {
                Account hcp = byExt.get(AccountMasterImportUtil.doctorExternalId(doctorCode));
                if (hcp != null) {
                    return hcp;
                }
            }
            if (String.isNotBlank(clinicId)) {
                return byExt.get(AccountMasterImportUtil.clinicExternalId(clinicId));
            }
            return null;
        }

        if (String.isBlank(code)) {
            return null;
        }
        return byExt.get(code);
    }

    private static void upsertAtf(List<Account_Territory_Fields__c> rows, ChunkResult result) {
        Set<String> keys = new Set<String>();
        Set<Id> accountIds = new Set<Id>();
        Set<String> territoryIds = new Set<String>();
        for (Account_Territory_Fields__c row : rows) {
            keys.add(row.Unique_Key__c);
            accountIds.add(row.Account__c);
            territoryIds.add(row.Territory2_Id__c);
        }
        Map<String, Id> existingIds = new Map<String, Id>();
        for (Account_Territory_Fields__c existing : [
            SELECT Id, Unique_Key__c, Account__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE
                Unique_Key__c IN :keys
                OR (Account__c IN :accountIds AND Territory2_Id__c IN :territoryIds)
        ]) {
            if (String.isNotBlank(existing.Unique_Key__c)) {
                existingIds.put(existing.Unique_Key__c, existing.Id);
            }
            String pairKey = String.valueOf(existing.Account__c) + '_' + existing.Territory2_Id__c;
            if (pairKey.length() > 40) {
                pairKey = pairKey.left(40);
            }
            if (!existingIds.containsKey(pairKey)) {
                existingIds.put(pairKey, existing.Id);
            }
        }
        for (Account_Territory_Fields__c row : rows) {
            if (existingIds.containsKey(row.Unique_Key__c)) {
                row.Id = existingIds.get(row.Unique_Key__c);
            }
        }
        Database.UpsertResult[] upserts = Database.upsert(rows, false);
        for (Database.UpsertResult ur : upserts) {
            if (ur.isSuccess()) {
                result.successCount++;
            } else {
                result.errorCount++;
                result.errors.add(joinErrors(ur.getErrors()));
            }
        }
    }

    private static String stripPrefix(String externalId, String prefix) {
        if (String.isBlank(externalId)) {
            return null;
        }
        return externalId.startsWith(prefix) ? externalId.substring(prefix.length()) : externalId;
    }

    private static String mapOrgType(Account acc) {
        String rt = acc.RecordType?.DeveloperName;
        if (rt == 'Pharmacy') {
            return 'Pharmacy';
        }
        if (rt == 'Distributor') {
            return 'Distributor';
        }
        if (acc.Institution_Type__c == 'Hospital') {
            return 'Hospital';
        }
        if (acc.Institution_Type__c == 'Contract') {
            return 'Contract';
        }
        if (acc.Institution_Type__c == 'Clinic' || acc.Institution_Type__c == 'Doctor') {
            return 'Doctor';
        }
        if (rt == 'Institution_HCO') {
            return 'Hospital';
        }
        return rt;
    }

    /** Target-list Customer Type: Doctor / Pharmacy / Hospital / Contract / Distributor. */
    private static String mapCustomerType(Account acc) {
        String rt = acc?.RecordType?.DeveloperName;
        if (rt == 'Pharmacy' || rt == 'Distributor') {
            return rt;
        }
        String it = acc?.Institution_Type__c;
        if (
            rt == 'HCP' || rt == 'PersonAccount' || rt == 'Clinic_HCP' ||
            it == 'Doctor' || it == 'Clinic'
        ) {
            return 'Doctor';
        }
        if (it == 'Contract') {
            return 'Contract';
        }
        return 'Hospital';
    }

    private static ChunkResult emptyResult() {
        ChunkResult result = new ChunkResult();
        result.successCount = 0;
        result.errorCount = 0;
        result.skippedCount = 0;
        result.errors = new List<String>();
        return result;
    }

    private static String normalize(String value) {
        return value == null ? '' : value.trim();
    }

    private static String joinErrors(Database.Error[] errors) {
        List<String> parts = new List<String>();
        if (errors == null) {
            return 'Unknown error';
        }
        for (Database.Error err : errors) {
            parts.add(err.getMessage());
        }
        return String.join(parts, '; ');
    }

    private static void trimErrors(ChunkResult result) {
        if (result.errors != null && result.errors.size() > 40) {
            List<String> keep = new List<String>();
            for (Integer i = 0; i < 40; i++) {
                keep.add(result.errors[i]);
            }
            keep.add('… ' + (result.errors.size() - 40) + ' more');
            result.errors = keep;
        }
    }
}
