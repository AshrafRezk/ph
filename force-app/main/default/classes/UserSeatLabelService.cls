/**
 * Line and territory names for the users shown in Territory Management.
 */
public without sharing class UserSeatLabelService {
    public class SeatLabel {
        @AuraEnabled public Id userId;
        @AuraEnabled public String lineName;
        @AuraEnabled public String territoryName;
        @AuraEnabled public String businessUnitName;
    }

    @AuraEnabled
    public static List<SeatLabel> getSeatLabels(List<Id> userIds) {
        List<SeatLabel> labels = new List<SeatLabel>();
        if (userIds == null || userIds.isEmpty()) {
            return labels;
        }
        Map<Id, List<Id>> territoryIdsByUser = new Map<Id, List<Id>>();
        Map<Id, Territory2> territoryById = new Map<Id, Territory2>();
        for (UserTerritory2Association link : [
            SELECT UserId, Territory2Id
            FROM UserTerritory2Association
            WHERE UserId IN :userIds AND IsActive = true
            WITH SYSTEM_MODE
        ]) {
            if (!territoryIdsByUser.containsKey(link.UserId)) {
                territoryIdsByUser.put(link.UserId, new List<Id>());
            }
            territoryIdsByUser.get(link.UserId).add(link.Territory2Id);
            territoryById.put(link.Territory2Id, null);
        }
        loadParents(territoryById);
        for (Id userId : userIds) {
            SeatLabel label = new SeatLabel();
            label.userId = userId;
            label.lineName = '';
            label.territoryName = '';
            label.businessUnitName = '';
            List<Id> territoryIds = territoryIdsByUser.get(userId);
            if (territoryIds != null) {
                List<String> territoryNames = new List<String>();
                Set<String> lineNames = new Set<String>();
                Set<String> buNames = new Set<String>();
                for (Id territoryId : territoryIds) {
                    Territory2 territory = territoryById.get(territoryId);
                    if (territory == null) {
                        continue;
                    }
                    territoryNames.add(territory.Name);
                    String lineName = lineNameFor(territory, territoryById);
                    if (String.isNotBlank(lineName)) {
                        lineNames.add(lineName);
                    }
                    String buName = businessUnitNameFor(territory, territoryById);
                    if (String.isNotBlank(buName)) {
                        buNames.add(buName);
                    }
                }
                label.territoryName = String.join(territoryNames, ', ');
                label.lineName = String.join(new List<String>(lineNames), ', ');
                label.businessUnitName = String.join(new List<String>(buNames), ', ');
            }
            labels.add(label);
        }
        return labels;
    }

    private static void loadParents(Map<Id, Territory2> territoryById) {
        Set<Id> pending = new Set<Id>(territoryById.keySet());
        for (Integer depth = 0; depth < 6 && !pending.isEmpty(); depth++) {
            for (Territory2 territory : [
                SELECT Id, Name, External_ID__c, ParentTerritory2Id, Territory_Type__c
                FROM Territory2
                WHERE Id IN :pending
                WITH SYSTEM_MODE
            ]) {
                territoryById.put(territory.Id, territory);
            }
            Set<Id> nextPending = new Set<Id>();
            for (Id territoryId : pending) {
                Territory2 territory = territoryById.get(territoryId);
                if (
                    territory != null &&
                    territory.ParentTerritory2Id != null &&
                    territoryById.get(territory.ParentTerritory2Id) == null
                ) {
                    nextPending.add(territory.ParentTerritory2Id);
                }
            }
            pending = nextPending;
        }
    }

    private static String lineNameFor(Territory2 start, Map<Id, Territory2> territoryById) {
        Territory2 cursor = start;
        Integer guard = 0;
        while (cursor != null && guard < 6) {
            Boolean isLine =
                cursor.Territory_Type__c == 'Line' ||
                (cursor.External_ID__c != null && cursor.External_ID__c.startsWith('TERR_LINE_'));
            if (isLine) {
                return cursor.Name;
            }
            cursor = cursor.ParentTerritory2Id == null ? null : territoryById.get(cursor.ParentTerritory2Id);
            guard++;
        }
        return null;
    }

    private static String businessUnitNameFor(Territory2 start, Map<Id, Territory2> territoryById) {
        Territory2 cursor = start;
        Integer guard = 0;
        while (cursor != null && guard < 6) {
            Boolean isBu =
                cursor.Territory_Type__c == 'Business_Unit' ||
                cursor.Territory_Type__c == 'Business Unit' ||
                (cursor.External_ID__c != null && cursor.External_ID__c.startsWith('TERR_BU_'));
            if (isBu) {
                return cursor.Name;
            }
            cursor = cursor.ParentTerritory2Id == null ? null : territoryById.get(cursor.ParentTerritory2Id);
            guard++;
        }
        return null;
    }
}
