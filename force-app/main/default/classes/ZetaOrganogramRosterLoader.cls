/**
 * Assigns organogram seats from ZetaOrganogramRoster.
 * People on the roster lose organogram seats that are not in the new file.
 * Training territories and users who are not on the roster are left alone.
 * Vacant seats are simply absent from the roster, so nobody is placed on them.
 */
public without sharing class ZetaOrganogramRosterLoader implements Queueable {
    public static final String RESOURCE_NAME = 'ZetaOrganogramRoster';
    public static final Integer USER_CHUNK = 80;

    @TestVisible private static String testRosterJson;
    @TestVisible private static Boolean skipChain = false;

    private Integer codeIndex;

    public ZetaOrganogramRosterLoader() {
        this(0);
    }

    private ZetaOrganogramRosterLoader(Integer codeIndex) {
        this.codeIndex = codeIndex == null ? 0 : codeIndex;
    }

    public static Id start() {
        return System.enqueueJob(new ZetaOrganogramRosterLoader());
    }

    public void execute(QueueableContext context) {
        Map<String, Map<Id, String>> desiredByCode = desiredByCode();
        List<String> codes = new List<String>(desiredByCode.keySet());
        codes.sort();
        if (codeIndex >= codes.size()) {
            return;
        }
        Integer endIndex = Math.min(codeIndex + USER_CHUNK, codes.size());
        Set<String> chunkCodes = new Set<String>();
        for (Integer i = codeIndex; i < endIndex; i++) {
            chunkCodes.add(codes[i]);
        }

        Map<String, Id> userIdByCode = new Map<String, Id>();
        for (User person : [
            SELECT Id, EmployeeNumber
            FROM User
            WHERE EmployeeNumber IN :chunkCodes AND IsActive = TRUE
        ]) {
            if (!userIdByCode.containsKey(person.EmployeeNumber)) {
                userIdByCode.put(person.EmployeeNumber, person.Id);
            }
        }

        Set<Id> userIds = new Set<Id>(userIdByCode.values());
        Map<String, UserTerritory2Association> existing = new Map<String, UserTerritory2Association>();
        if (!userIds.isEmpty()) {
            for (UserTerritory2Association row : [
                SELECT Id, UserId, Territory2Id, RoleInTerritory2, Territory2.External_ID__c
                FROM UserTerritory2Association
                WHERE UserId IN :userIds
            ]) {
                existing.put(key(row.UserId, row.Territory2Id), row);
            }
        }

        List<UserTerritory2Association> toInsert = new List<UserTerritory2Association>();
        List<UserTerritory2Association> toUpdate = new List<UserTerritory2Association>();
        List<UserTerritory2Association> toDelete = new List<UserTerritory2Association>();
        Set<String> keep = new Set<String>();

        for (String code : chunkCodes) {
            Id userId = userIdByCode.get(code);
            if (userId == null) {
                continue;
            }
            for (Id territoryId : desiredByCode.get(code).keySet()) {
                String pair = key(userId, territoryId);
                keep.add(pair);
                String role = desiredByCode.get(code).get(territoryId);
                UserTerritory2Association current = existing.get(pair);
                if (current == null) {
                    toInsert.add(
                        new UserTerritory2Association(
                            UserId = userId,
                            Territory2Id = territoryId,
                            RoleInTerritory2 = role
                        )
                    );
                } else if (current.RoleInTerritory2 != role) {
                    toUpdate.add(new UserTerritory2Association(Id = current.Id, RoleInTerritory2 = role));
                }
            }
        }

        for (UserTerritory2Association row : existing.values()) {
            String pair = key(row.UserId, row.Territory2Id);
            if (keep.contains(pair) || !isOrganogramSeat(row.Territory2.External_ID__c)) {
                continue;
            }
            toDelete.add(row);
        }

        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, false);
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
        }

        if (endIndex < codes.size() && !skipChain) {
            System.enqueueJob(new ZetaOrganogramRosterLoader(endIndex));
        }
    }

    private static Boolean isOrganogramSeat(String externalId) {
        if (String.isBlank(externalId) || !externalId.startsWith('TERR_')) {
            return false;
        }
        return !externalId.contains('TRAINING');
    }

    private Map<String, Map<Id, String>> desiredByCode() {
        Map<String, Map<String, String>> roleByCodeAndTerritory = new Map<String, Map<String, String>>();
        Set<String> territoryExternalIds = new Set<String>();
        for (Object raw : assignments()) {
            Map<String, Object> row = (Map<String, Object>) raw;
            String code = text(row.get('code'));
            String territoryExternalId = text(row.get('territoryExternalId'));
            String role = text(row.get('role'));
            if (String.isBlank(code) || String.isBlank(territoryExternalId)) {
                continue;
            }
            if (!roleByCodeAndTerritory.containsKey(code)) {
                roleByCodeAndTerritory.put(code, new Map<String, String>());
            }
            String current = roleByCodeAndTerritory.get(code).get(territoryExternalId);
            if (current == null || rank(role) > rank(current)) {
                roleByCodeAndTerritory.get(code).put(territoryExternalId, role);
            }
            territoryExternalIds.add(territoryExternalId);
        }

        Map<String, Id> territoryIdByExternal = new Map<String, Id>();
        if (!territoryExternalIds.isEmpty()) {
            for (Territory2 territory : [
                SELECT Id, External_ID__c
                FROM Territory2
                WHERE External_ID__c IN :territoryExternalIds
            ]) {
                territoryIdByExternal.put(territory.External_ID__c, territory.Id);
            }
        }

        Map<String, Map<Id, String>> desired = new Map<String, Map<Id, String>>();
        for (String code : roleByCodeAndTerritory.keySet()) {
            Map<Id, String> seats = new Map<Id, String>();
            for (String territoryExternalId : roleByCodeAndTerritory.get(code).keySet()) {
                Id territoryId = territoryIdByExternal.get(territoryExternalId);
                if (territoryId != null) {
                    seats.put(territoryId, roleByCodeAndTerritory.get(code).get(territoryExternalId));
                }
            }
            if (!seats.isEmpty()) {
                desired.put(code, seats);
            }
        }
        return desired;
    }

    private List<Object> assignments() {
        String body = testRosterJson;
        if (body == null) {
            body = [SELECT Body FROM StaticResource WHERE Name = :RESOURCE_NAME LIMIT 1].Body.toString();
        }
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);
        Object rows = payload.get('assignments');
        return rows == null ? new List<Object>() : (List<Object>) rows;
    }

    private static Integer rank(String role) {
        if (role == 'Business Unit Manager') {
            return 5;
        }
        if (role == 'National Sales Manager') {
            return 4;
        }
        if (role == 'Area Manager') {
            return 3;
        }
        if (role == 'District Manager') {
            return 2;
        }
        return 1;
    }

    private static String key(Id userId, Id territoryId) {
        return String.valueOf(userId) + ':' + String.valueOf(territoryId);
    }

    private static String text(Object value) {
        return value == null ? '' : String.valueOf(value).trim();
    }
}
