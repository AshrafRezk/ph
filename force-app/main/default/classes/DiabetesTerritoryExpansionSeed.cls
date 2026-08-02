/**
 * Expands the Diabetes BU with additional product lines and districts
 * sourced from Plan/Zeta Demo Data (Diab III Feb 2026 CRM + sales exports).
 */
public without sharing class DiabetesTerritoryExpansionSeed {

    private static final String PREFIX = TerritoryModuleCleanup.PHARMA_EXTERNAL_ID_PREFIX;

    public class SeedResult {
        public Integer territoriesCreated = 0;
        public Integer territoriesUpdated = 0;
        public Map<String, Id> territoryIdsByExtId = new Map<String, Id>();
        public String message;
    }

    private class TerritorySpec {
        public String externalId;
        public String name;
        public String developerName;
        public String parentExtId;
    }

    /**
     * Retired for Chemipharm portfolio (GIT / CNS / Rheumatology / Cardiovascular).
     * Kept as a no-op so older scripts/tests do not create Diabetes territories.
     */
    public static SeedResult seedDiabetesLinesAndDistricts() {
        SeedResult result = new SeedResult();
        result.message = 'Skipped: Diabetes territory expansion retired for Chemipharm BUs.';
        return result;
    }

    private static SeedResult seedDiabetesLinesAndDistrictsLegacy() {
        SeedResult result = new SeedResult();
        Id diabetesBuId = TerritoryModuleSeed.getTerritoryId('TERR_DIABETES');
        if (diabetesBuId == null) {
            result.message = 'Diabetes BU (TERR_DIABETES) not found. Run territory seed first.';
            return result;
        }

        Territory2Type territoryType = resolveTerritoryType();
        Territory2Model model = resolveModel();
        List<TerritorySpec> specs = buildExpansionSpecs();
        Map<String, Id> extIdToTerritoryId = loadExistingPharmaTerritoryIds();

        for (TerritorySpec spec : specs) {
            Id parentId = spec.parentExtId == null ? null : extIdToTerritoryId.get(spec.parentExtId);
            if (parentId == null && spec.parentExtId != null) {
                continue;
            }
            Boolean existed = extIdToTerritoryId.containsKey(spec.externalId);
            Territory2 territory = upsertTerritory(spec, model.Id, territoryType.Id, parentId);
            extIdToTerritoryId.put(spec.externalId, territory.Id);
            if (existed) {
                result.territoriesUpdated++;
            } else {
                result.territoriesCreated++;
            }
        }

        result.territoryIdsByExtId = extIdToTerritoryId;
        result.message = 'Diabetes expansion: ' + result.territoriesCreated + ' created, '
            + result.territoriesUpdated + ' updated.';
        return result;
    }

    private static List<TerritorySpec> buildExpansionSpecs() {
        List<TerritorySpec> specs = new List<TerritorySpec>();

        addLine(specs, 'TERR_DIABETES_LINE1', 'DIAB I', 'Diabetes_Line1', 'TERR_DIABETES');
        addLine(specs, 'TERR_DIABETES_LINE2', 'DIAB II', 'Diabetes_Line2', 'TERR_DIABETES');
        addLine(specs, 'TERR_DIABETES_LINE4', 'DIAB IV', 'Diabetes_Line4', 'TERR_DIABETES');

        addDistricts(specs, 'TERR_DIABETES_LINE1', new List<String>{
            'ASWAN', 'QENA-A', 'MENIA-A', 'SOHAG I-A', 'ASSUIT-B'
        });
        addDistricts(specs, 'TERR_DIABETES_LINE2', new List<String>{
            'BEHIRA-A', 'BEHIRA-B', 'BEHIRA-C'
        });
        addDistricts(specs, 'TERR_DIABETES_DM_1', new List<String>{
            'HELWAN', 'CAIRO WEST', 'CAIRO EAST', 'MAADI', 'CAIRO CENTER', 'CAIRO SOUTH',
            'DM CAIRO A', 'ABBASEIA-KOBBAH', 'NEW CAIRO', 'QALUBIA-A', 'DAKAHLIA-C',
            'HELIOPOLIS-A', 'FAISAL', 'SHARKIA-A', 'MOHANDSEEN', 'ISMAILIA-SUIZ'
        });
        addDistricts(specs, 'TERR_DIABETES_LINE4', new List<String>{
            'ALEX WEST', 'ALEX EAST-A', 'ALEX CENTER-B', 'DM ALEX-BEHIR'
        });

        return specs;
    }

    private static void addLine(
        List<TerritorySpec> specs,
        String externalId,
        String name,
        String developerName,
        String parentExtId
    ) {
        TerritorySpec spec = new TerritorySpec();
        spec.externalId = externalId;
        spec.name = name;
        spec.developerName = developerName;
        spec.parentExtId = parentExtId;
        specs.add(spec);
    }

    private static void addDistricts(
        List<TerritorySpec> specs,
        String lineExtId,
        List<String> districtNames
    ) {
        Integer index = 1;
        for (String districtName : districtNames) {
            String suffix = toDistrictSuffix(districtName);
            String externalId = lineExtId + '_MR_' + index;
            if (lineExtId == 'TERR_DIABETES_DM_1' && index == 1) {
                externalId = 'TERR_DIABETES_DM_1_MR_1';
            }
            TerritorySpec spec = new TerritorySpec();
            spec.externalId = externalId;
            spec.name = districtName;
            spec.developerName = lineExtId.replace(PREFIX, '') + '_MR_' + suffix;
            if (spec.developerName.length() > 80) {
                spec.developerName = spec.developerName.left(80);
            }
            spec.parentExtId = lineExtId;
            specs.add(spec);
            index++;
        }
    }

    private static String toDistrictSuffix(String districtName) {
        return districtName.trim()
            .toUpperCase()
            .replaceAll('[^A-Z0-9]+', '_')
            .replaceAll('^_+|_+$', '');
    }

    private static Map<String, Id> loadExistingPharmaTerritoryIds() {
        Map<String, Id> result = new Map<String, Id>();
        String pharmaLike = PREFIX + '%';
        for (Territory2 territory : [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c LIKE :pharmaLike
            WITH SYSTEM_MODE
        ]) {
            result.put(territory.External_ID__c, territory.Id);
        }
        return result;
    }

    private static Territory2Type resolveTerritoryType() {
        List<Territory2Type> types = [
            SELECT Id
            FROM Territory2Type
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (types.isEmpty()) {
            throw new AuraHandledException('No Territory2Type found. Enable Enterprise Territory Management first.');
        }
        return types[0];
    }

    private static Territory2Model resolveModel() {
        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (models.isEmpty()) {
            throw new AuraHandledException('Current_FY territory model not found.');
        }
        return models[0];
    }

    private static Territory2 upsertTerritory(
        TerritorySpec spec,
        Id modelId,
        Id typeId,
        Id parentId
    ) {
        List<Territory2> existing = [
            SELECT Id, Name, ParentTerritory2Id, DeveloperName
            FROM Territory2
            WHERE External_ID__c = :spec.externalId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            Territory2 territory = existing[0];
            territory.Name = spec.name;
            territory.ParentTerritory2Id = parentId;
            update as system territory;
            return territory;
        }
        Territory2 territory = new Territory2(
            Name = spec.name,
            DeveloperName = spec.developerName,
            Territory2ModelId = modelId,
            Territory2TypeId = typeId,
            ParentTerritory2Id = parentId,
            External_ID__c = spec.externalId
        );
        insert as system territory;
        return territory;
    }
}
