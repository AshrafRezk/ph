public without sharing class TerritoryModuleCleanup {

    public static final String PHARMA_EXTERNAL_ID_PREFIX = 'TERR_';

    public class CleanupResult {
        public Integer associationsDeleted;
        public Integer userAssociationsDeleted;
        public Integer legacyTerritoriesDeleted;
        public String message;
    }

    /**
     * Clears territory associations and removes legacy SDO territories
     * (AMER, EMEA, JAPAC, Overlays and their descendants).
     */
    public static CleanupResult run() {
        CleanupResult result = new CleanupResult();

        List<ObjectTerritory2Association> otas = [
            SELECT Id FROM ObjectTerritory2Association WITH SYSTEM_MODE
        ];
        if (!otas.isEmpty()) {
            Database.delete(otas, AccessLevel.SYSTEM_MODE);
        }
        result.associationsDeleted = otas.size();

        List<UserTerritory2Association> utas = [
            SELECT Id FROM UserTerritory2Association WITH SYSTEM_MODE
        ];
        if (!utas.isEmpty()) {
            Database.delete(utas, AccessLevel.SYSTEM_MODE);
        }
        result.userAssociationsDeleted = utas.size();

        result.legacyTerritoriesDeleted = purgeLegacySdoTerritories();
        result.message = 'Territory associations cleared and ' + result.legacyTerritoriesDeleted
            + ' legacy SDO territories removed.';
        return result;
    }

    /**
     * Deletes AMER, EMEA, JAPAC, Overlays and all descendant territories
     * from the Current_FY model, preserving pharma territories (TERR_* external IDs).
     */
    public static Integer purgeLegacySdoTerritories() {
        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (models.isEmpty()) {
            return 0;
        }

        List<Territory2> territoriesInModel = [
            SELECT Id, ParentTerritory2Id, DeveloperName, External_ID__c
            FROM Territory2
            WHERE Territory2ModelId = :models[0].Id
            WITH SYSTEM_MODE
        ];
        List<Territory2> legacyTerritories = new List<Territory2>();
        for (Territory2 territory : territoriesInModel) {
            if (String.isBlank(territory.External_ID__c)
                || !territory.External_ID__c.startsWith(PHARMA_EXTERNAL_ID_PREFIX)) {
                legacyTerritories.add(territory);
            }
        }
        if (legacyTerritories.isEmpty()) {
            return 0;
        }

        Set<Id> legacyIds = new Map<Id, Territory2>(legacyTerritories).keySet();
        Set<String> legacyIdStrings = new Set<String>();
        for (Id territoryId : legacyIds) {
            legacyIdStrings.add(String.valueOf(territoryId));
        }

        deleteRelatedAlignmentRecords(legacyIdStrings);
        deleteRemainingAssociations(legacyIds);

        return deleteTerritoriesBottomUp(legacyTerritories, legacyIds);
    }

    private static void deleteRelatedAlignmentRecords(Set<String> legacyIdStrings) {
        List<Product_Territory_Alignment__c> productAlignments = [
            SELECT Id
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c IN :legacyIdStrings
            WITH SYSTEM_MODE
        ];
        if (!productAlignments.isEmpty()) {
            Database.delete(productAlignments, AccessLevel.SYSTEM_MODE);
        }

        List<Account_Territory_Fields__c> atfRows = [
            SELECT Id
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :legacyIdStrings
            WITH SYSTEM_MODE
        ];
        if (!atfRows.isEmpty()) {
            Database.delete(atfRows, AccessLevel.SYSTEM_MODE);
        }

        List<Account_Territory_Product_Fields__c> atpfRows = [
            SELECT Id
            FROM Account_Territory_Product_Fields__c
            WHERE Territory2_Id__c IN :legacyIdStrings
            WITH SYSTEM_MODE
        ];
        if (!atpfRows.isEmpty()) {
            Database.delete(atpfRows, AccessLevel.SYSTEM_MODE);
        }

        List<Account_Rating_Layout__c> ratingLayouts = [
            SELECT Id
            FROM Account_Rating_Layout__c
            WHERE Territory2_Id__c IN :legacyIdStrings
            WITH SYSTEM_MODE
        ];
        if (!ratingLayouts.isEmpty()) {
            Database.delete(ratingLayouts, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void deleteRemainingAssociations(Set<Id> legacyIds) {
        List<UserTerritory2Association> userAssociations = [
            SELECT Id
            FROM UserTerritory2Association
            WHERE Territory2Id IN :legacyIds
            WITH SYSTEM_MODE
        ];
        if (!userAssociations.isEmpty()) {
            Database.delete(userAssociations, AccessLevel.SYSTEM_MODE);
        }

        List<ObjectTerritory2Association> objectAssociations = [
            SELECT Id
            FROM ObjectTerritory2Association
            WHERE Territory2Id IN :legacyIds
            WITH SYSTEM_MODE
        ];
        if (!objectAssociations.isEmpty()) {
            Database.delete(objectAssociations, AccessLevel.SYSTEM_MODE);
        }
    }

    private static Integer deleteTerritoriesBottomUp(
        List<Territory2> legacyTerritories,
        Set<Id> remaining
    ) {
        Integer deleted = 0;
        Integer safetyCounter = 0;

        while (!remaining.isEmpty() && safetyCounter < 100) {
            safetyCounter++;
            Set<Id> parentIdsWithChildren = new Set<Id>();
            for (Territory2 territory : legacyTerritories) {
                if (territory.ParentTerritory2Id != null && remaining.contains(territory.Id)) {
                    parentIdsWithChildren.add(territory.ParentTerritory2Id);
                }
            }

            List<Territory2> leaves = new List<Territory2>();
            for (Id territoryId : remaining) {
                if (!parentIdsWithChildren.contains(territoryId)) {
                    leaves.add(new Territory2(Id = territoryId));
                }
            }
            if (leaves.isEmpty()) {
                break;
            }

            Database.DeleteResult[] results = Database.delete(leaves, false, AccessLevel.SYSTEM_MODE);
            for (Integer index = 0; index < results.size(); index++) {
                if (results[index].isSuccess()) {
                    remaining.remove(leaves[index].Id);
                    deleted++;
                }
            }
        }
        return deleted;
    }
}
