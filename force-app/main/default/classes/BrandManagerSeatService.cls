/**
 * Seats Brand Managers on their commercial Line and Group Brand Leads on the BU.
 * Division text is mapped onto organogram line names.
 */
public without sharing class BrandManagerSeatService {
    public class SeatResult {
        @AuraEnabled public Integer brandManagersSeated;
        @AuraEnabled public Integer groupBrandLeadsSeated;
        @AuraEnabled public Integer skipped;
        @AuraEnabled public List<String> messages;
    }

    /**
     * Division text (normalized: lower case, letters and digits only) to the organogram line name.
     * Diabetes I-IV map to DIAB-I..DIAB-IV. Plain Diabetes keeps the first Diabetes line for Brand Managers.
     */
    private static final Map<String, String> DIVISION_TO_LINE = new Map<String, String>{
        'chc' => 'CHC',
        'chcsales' => 'CHC_Sales',
        'giti' => 'GIT-I',
        'gitii' => 'GIT-II',
        'gitiii' => 'GIT-III',
        'gitsales' => 'GIT-SALES',
        'cvmi' => 'CVM-I',
        'cvmii' => 'CVM-II',
        'cns' => 'NEUROSCIENCE-I',
        'neuroscience' => 'NEUROSCIENCE-I',
        'neurosciencei' => 'NEUROSCIENCE-I',
        'neuroscienceii' => 'NEUROSCIENCE-II',
        'pediagyn' => 'PEDIA',
        'pedia' => 'PEDIA',
        'gyn' => 'GYN',
        'derma' => 'DERMA',
        'ortho' => 'ORTHO-I',
        'orthoi' => 'ORTHO-I',
        'orthoii' => 'ORTHO-II',
        'diabetes' => 'DIAB-I',
        'diab' => 'DIAB-I',
        'diabetesi' => 'DIAB-I',
        'diabi' => 'DIAB-I',
        'diabetesii' => 'DIAB-II',
        'diabii' => 'DIAB-II',
        'diabetesiii' => 'DIAB-III',
        'diabiii' => 'DIAB-III',
        'diabetesiv' => 'DIAB-IV',
        'diabiv' => 'DIAB-IV'
    };

    /** Division values that cover the whole Diabetes business unit (Group Brand Lead seats). */
    private static final Set<String> DIABETES_BU_DIVISIONS = new Set<String>{
        'diabetes',
        'diab',
        'diabetesiiv',
        'diabetesitoiv',
        'diabetesiiiv',
        'diabiiv',
        'diabitoiv'
    };

    @AuraEnabled
    public static SeatResult seatMarketingOnOrganogram() {
        SeatResult result = new SeatResult();
        result.brandManagersSeated = 0;
        result.groupBrandLeadsSeated = 0;
        result.skipped = 0;
        result.messages = new List<String>();

        Map<String, Id> lineIdByKey = new Map<String, Id>();
        Map<String, Id> buIdByKey = new Map<String, Id>();
        for (Territory2 territory : [
            SELECT Id, Name, Territory_Type__c, External_ID__c, ParentTerritory2Id
            FROM Territory2
            WHERE External_ID__c LIKE 'TERR_%'
                AND Territory_Type__c IN ('Line', 'Business_Unit')
            WITH SYSTEM_MODE
        ]) {
            String key = normalize(territory.Name);
            if (territory.Territory_Type__c == 'Line') {
                lineIdByKey.put(key, territory.Id);
            } else {
                buIdByKey.put(key, territory.Id);
            }
        }

        List<User> marketing = [
            SELECT Id, Name, Title, Division, Department, ManagerId
            FROM User
            WHERE IsActive = TRUE
                AND (
                    Title LIKE '%Brand Manager%'
                    OR Title LIKE '%Group Brand Lead%'
                    OR Title LIKE '%Group Brand Manager%'
                )
            WITH SYSTEM_MODE
            LIMIT 500
        ];

        Set<String> existing = new Set<String>();
        Set<Id> marketingIds = new Map<Id, User>(marketing).keySet();
        if (!marketingIds.isEmpty()) {
            for (UserTerritory2Association link : [
                SELECT UserId, Territory2Id
                FROM UserTerritory2Association
                WHERE UserId IN :marketingIds AND IsActive = TRUE
                WITH SYSTEM_MODE
            ]) {
                existing.add(compositeKey(link.UserId, link.Territory2Id));
            }
        }

        List<UserTerritory2Association> toInsert = new List<UserTerritory2Association>();
        for (User person : marketing) {
            String title = person.Title == null ? '' : person.Title.toLowerCase();
            Boolean isGroupLead = title.contains('group brand');
            if (isGroupLead) {
                Id buId = resolveBu(person, buIdByKey, lineIdByKey);
                if (buId == null) {
                    result.skipped++;
                    result.messages.add(person.Name + ': no BU match (Division=' + person.Division + ').');
                    continue;
                }
                if (existing.contains(compositeKey(person.Id, buId))) {
                    continue;
                }
                toInsert.add(
                    new UserTerritory2Association(
                        UserId = person.Id,
                        Territory2Id = buId,
                        RoleInTerritory2 = 'Group Brand Lead'
                    )
                );
                result.groupBrandLeadsSeated++;
            } else {
                Id lineId = resolveLine(person.Division, lineIdByKey);
                if (lineId == null) {
                    result.skipped++;
                    result.messages.add(person.Name + ': no Line match (Division=' + person.Division + ').');
                    continue;
                }
                if (existing.contains(compositeKey(person.Id, lineId))) {
                    continue;
                }
                toInsert.add(
                    new UserTerritory2Association(
                        UserId = person.Id,
                        Territory2Id = lineId,
                        RoleInTerritory2 = 'Brand Manager'
                    )
                );
                result.brandManagersSeated++;
            }
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }
        result.messages.add(
            'Seated '
                + result.brandManagersSeated
                + ' Brand Manager(s) and '
                + result.groupBrandLeadsSeated
                + ' Group Brand Lead(s). Skipped '
                + result.skipped
                + '.'
        );
        return result;
    }

    @TestVisible
    private static String lineNameForDivision(String division) {
        if (String.isBlank(division)) {
            return null;
        }
        String key = divisionKey(division);
        return DIVISION_TO_LINE.get(key);
    }

    private static Id resolveLine(String division, Map<String, Id> lineIdByKey) {
        if (String.isBlank(division)) {
            return null;
        }
        String mapped = lineNameForDivision(division);
        String key = normalize(mapped != null ? mapped : division);
        return lineIdByKey.get(key);
    }

    private static String divisionKey(String division) {
        if (division == null) {
            return '';
        }
        return division.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    private static Id resolveBu(User person, Map<String, Id> buIdByKey, Map<String, Id> lineIdByKey) {
        if (String.isNotBlank(person.Division) && DIABETES_BU_DIVISIONS.contains(divisionKey(person.Division))) {
            Id diabetesBu = buIdByKey.get('diabetes');
            if (diabetesBu != null) {
                return diabetesBu;
            }
        }
        Id lineId = resolveLine(person.Division, lineIdByKey);
        if (lineId != null) {
            List<Territory2> lines = [
                SELECT ParentTerritory2Id
                FROM Territory2
                WHERE Id = :lineId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!lines.isEmpty()) {
                return lines[0].ParentTerritory2Id;
            }
        }
        if (String.isNotBlank(person.Department)) {
            return buIdByKey.get(normalize(person.Department));
        }
        return null;
    }

    private static String normalize(String value) {
        if (value == null) {
            return '';
        }
        return value.trim().toLowerCase().replace(' ', '').replace('_', '').replace('-', '');
    }

    private static String compositeKey(Id userId, Id territoryId) {
        return String.valueOf(userId) + ':' + String.valueOf(territoryId);
    }
}
