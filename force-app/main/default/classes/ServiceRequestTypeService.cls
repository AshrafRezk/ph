/**
 * Admin-configurable service request types/subtypes with title gates.
 *
 * Read methods (listTypes, listAllTypes, typesForCurrentUser) are cacheable and never run DML.
 * Seed data goes in through seedDefaults() (admin button / one-time load) only.
 */
public with sharing class ServiceRequestTypeService {
    public static final String SERVICE_SUBTYPE = 'Service';

    /** Mendix Service_Marketing.xlsx (19 rows). */
    @TestVisible
    private static final List<String> MARKETING_SERVICES = new List<String>{
        'Brand Reminder', 'Branding', 'CME', 'Conference Contribution', 'Data Analysis',
        'Digital Marketing', 'Honorarium', 'Hospitality', 'Marketing Research', 'Medical Book',
        'Medical Devices', 'Offline', 'Online', 'Registration / Membershing', 'Screening',
        'Transportation', 'Visa Cost', 'Website Registration', 'Branding items'
    };

    /** Mendix Service_Medical.xlsx (15 rows). */
    @TestVisible
    private static final List<String> MEDICAL_SERVICES = new List<String>{
        'Brand Reminder', 'Branding', 'Accreditation', 'Honorarium', 'Accomodation',
        'Hospitality', 'Medical Book', 'Website Registration', 'EDA Online Submission',
        'EDA Offline Submission', 'Screening', 'Transportation', 'Visa Cost', 'Printing', 'CRO'
    };

    public class SeedResult {
        @AuraEnabled public Integer marketingInserted;
        @AuraEnabled public Integer medicalInserted;
        @AuraEnabled public Integer skipped;
        @AuraEnabled public Integer total;
    }

    public class TypeRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public String subtype;
        @AuraEnabled public String creatorTitles;
        @AuraEnabled public Boolean isActive;
    }

    @AuraEnabled(cacheable=true)
    public static List<TypeRow> listTypes(String category) {
        return queryTypes(category, true);
    }

    /** Admin console: active and inactive types. */
    @AuraEnabled
    public static List<TypeRow> listAllTypes(String category) {
        return queryTypes(category, false);
    }

    private static List<TypeRow> queryTypes(String category, Boolean activeOnly) {
        String soql =
            'SELECT Id, Name, Category__c, Subtype__c, Creator_Titles__c, Is_Active__c'
            + ' FROM Service_Request_Type__c WHERE Id != null';
        if (activeOnly) {
            soql += ' AND Is_Active__c = TRUE';
        }
        if (String.isNotBlank(category)) {
            soql += ' AND Category__c = :category';
        }
        soql += ' WITH SYSTEM_MODE ORDER BY Category__c, Name, Subtype__c LIMIT 500';
        List<TypeRow> rows = new List<TypeRow>();
        for (Service_Request_Type__c rec : Database.query(soql)) {
            rows.add(toRow(rec));
        }
        return rows;
    }

    @AuraEnabled
    public static TypeRow saveType(TypeRow input) {
        if (input == null || String.isBlank(input.name)) {
            throw new AuraHandledException('Name is required.');
        }
        Service_Request_Type__c row = input.id == null
            ? new Service_Request_Type__c()
            : [
                  SELECT Id
                  FROM Service_Request_Type__c
                  WHERE Id = :input.id
                  WITH SYSTEM_MODE
                  LIMIT 1
              ];
        row.Name = input.name.trim();
        row.Category__c = input.category;
        row.Subtype__c = input.subtype;
        row.Creator_Titles__c = input.creatorTitles;
        row.Is_Active__c = input.isActive != false;
        upsert as system row;
        input.id = row.Id;
        return input;
    }

    @AuraEnabled(cacheable=true)
    public static List<TypeRow> typesForCurrentUser(String category) {
        Map<String, List<TypeRow>> grouped = typesForCurrentUserByCategory(
            String.isBlank(category) ? null : new List<String>{ category }
        );
        List<TypeRow> allowed = new List<TypeRow>();
        for (List<TypeRow> rows : grouped.values()) {
            allowed.addAll(rows);
        }
        return allowed;
    }

    /**
     * Title-gated active types grouped by category using two queries total (user title and types).
     * Null or empty categories returns every category. Never runs DML.
     */
    public static Map<String, List<TypeRow>> typesForCurrentUserByCategory(List<String> categories) {
        List<User> me = [
            SELECT Title
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        String title = me.isEmpty() || me[0].Title == null ? '' : me[0].Title.trim().toLowerCase();
        Map<String, List<TypeRow>> grouped = new Map<String, List<TypeRow>>();
        if (categories != null) {
            for (String category : categories) {
                grouped.put(category, new List<TypeRow>());
            }
        }
        List<Service_Request_Type__c> recs = categories == null || categories.isEmpty()
            ? [
                  SELECT Id, Name, Category__c, Subtype__c, Creator_Titles__c, Is_Active__c
                  FROM Service_Request_Type__c
                  WHERE Is_Active__c = TRUE
                  WITH SYSTEM_MODE
                  ORDER BY Category__c, Name, Subtype__c
                  LIMIT 500
              ]
            : [
                  SELECT Id, Name, Category__c, Subtype__c, Creator_Titles__c, Is_Active__c
                  FROM Service_Request_Type__c
                  WHERE Is_Active__c = TRUE AND Category__c IN :categories
                  WITH SYSTEM_MODE
                  ORDER BY Category__c, Name, Subtype__c
                  LIMIT 500
              ];
        for (Service_Request_Type__c rec : recs) {
            TypeRow row = toRow(rec);
            Boolean allowed = String.isBlank(row.creatorTitles);
            if (!allowed) {
                for (String part : row.creatorTitles.split(';')) {
                    if (part != null && part.trim().toLowerCase() == title) {
                        allowed = true;
                        break;
                    }
                }
            }
            if (allowed) {
                if (!grouped.containsKey(rec.Category__c)) {
                    grouped.put(rec.Category__c, new List<TypeRow>());
                }
                grouped.get(rec.Category__c).add(row);
            }
        }
        return grouped;
    }

    /**
     * Idempotent seed of Marketing and Medical service types (Mendix Service_Marketing / Service_Medical).
     * Not cacheable: safe to call from an admin button or anonymous Apex. Existing Category + Name
     * rows are left untouched.
     */
    @AuraEnabled
    public static SeedResult seedDefaults() {
        if (!Schema.sObjectType.Service_Request_Type__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to create service request types.');
        }
        Set<String> existing = new Set<String>();
        for (Service_Request_Type__c rec : [
            SELECT Name, Category__c
            FROM Service_Request_Type__c
            WHERE Category__c IN ('Marketing', 'Medical')
            WITH SYSTEM_MODE
            LIMIT 2000
        ]) {
            existing.add(keyFor(rec.Category__c, rec.Name));
        }
        List<Service_Request_Type__c> toInsert = new List<Service_Request_Type__c>();
        SeedResult result = new SeedResult();
        result.marketingInserted = 0;
        result.medicalInserted = 0;
        result.skipped = 0;
        for (String name : MARKETING_SERVICES) {
            if (existing.add(keyFor('Marketing', name))) {
                toInsert.add(seed(name, 'Marketing', SERVICE_SUBTYPE, null));
                result.marketingInserted++;
            } else {
                result.skipped++;
            }
        }
        for (String name : MEDICAL_SERVICES) {
            if (existing.add(keyFor('Medical', name))) {
                toInsert.add(seed(name, 'Medical', SERVICE_SUBTYPE, null));
                result.medicalInserted++;
            } else {
                result.skipped++;
            }
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }
        result.total = [SELECT COUNT() FROM Service_Request_Type__c WITH SYSTEM_MODE];
        return result;
    }

    private static String keyFor(String category, String name) {
        return (category + '|' + name).toLowerCase();
    }

    private static Service_Request_Type__c seed(
        String name,
        String category,
        String subtype,
        String titles
    ) {
        return new Service_Request_Type__c(
            Name = name,
            Category__c = category,
            Subtype__c = subtype,
            Creator_Titles__c = titles,
            Is_Active__c = true
        );
    }

    private static TypeRow toRow(Service_Request_Type__c rec) {
        TypeRow row = new TypeRow();
        row.id = rec.Id;
        row.name = rec.Name;
        row.category = rec.Category__c;
        row.subtype = rec.Subtype__c;
        row.creatorTitles = rec.Creator_Titles__c;
        row.isActive = rec.Is_Active__c == true;
        return row;
    }
}
