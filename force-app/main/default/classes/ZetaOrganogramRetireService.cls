/**
 * Retire step for the organogram loader.
 * The loader upserts what is in the resource and never removes what was dropped from it.
 * This service finds districts, positions and lines that are no longer in the resource
 * (training and demo seats are left alone), and retires them only when that is safe:
 *   - nobody is seated on them, no active account targets or object associations sit on them,
 *     and no node outside the stale set hangs below them;
 *   - active product alignments on them are switched off first;
 *   - a stale line (NEUROSCIENCE) is retired only after its products are remapped to a current line.
 * It also applies the HR Business Unit names from the resource (Cluster, GIT, Diabetes).
 * dryRun = true changes nothing and reports what would happen.
 * Territory2 is a setup object, so each real run does one phase (its own transaction):
 *   PRODUCTS    remap products off the stale line (Product2)
 *   ALIGNMENTS  switch off product alignments on stale seats
 *   TERRITORIES rename Business Units and retire the stale seats and lines (Territory2)
 * Run PRODUCTS, then ALIGNMENTS, then TERRITORIES.
 */
public without sharing class ZetaOrganogramRetireService {
    public static final String STALE_LINE_NAME = 'NEUROSCIENCE';
    public static final String PHASE_PRODUCTS = 'PRODUCTS';
    public static final String PHASE_ALIGNMENTS = 'ALIGNMENTS';
    public static final String PHASE_TERRITORIES = 'TERRITORIES';
    private static final Set<String> NEURO_TARGET_LINES = new Set<String>{ 'NEUROSCIENCE-I', 'NEUROSCIENCE-II' };
    private static final String TERRITORIES_RESOURCE = 'ZetaOrganogramTerritories';
    /** When set (tests only), only these External_ID__c values are evaluated for retirement. */
    @TestVisible private static Set<String> testOnlyExternalIds;
    /** Injected organogram JSON for tests (avoids a TerritoryLoader deploy dependency). */
    @TestVisible private static String testTerritoriesJson;

    private class TerritoryNode {
        public String externalId;
        public String name;
    }

    private class TerritoriesPayload {
        public TerritoryNode headOffice;
        public List<TerritoryNode> businessUnits;
        public List<TerritoryNode> lines;
        public List<TerritoryNode> districts;
        public List<TerritoryNode> positions;
    }

    public class Report {
        @AuraEnabled public Boolean dryRun;
        @AuraEnabled public List<String> staleDistricts = new List<String>();
        @AuraEnabled public List<String> stalePositions = new List<String>();
        @AuraEnabled public List<String> staleLines = new List<String>();
        @AuraEnabled public List<String> blockers = new List<String>();
        @AuraEnabled public List<String> errors = new List<String>();
        @AuraEnabled public List<String> renamedBusinessUnits = new List<String>();
        @AuraEnabled public List<String> productsRemapped = new List<String>();
        @AuraEnabled public List<String> productsUnmapped = new List<String>();
        @AuraEnabled public Integer productAlignmentsDeactivated = 0;
        @AuraEnabled public Integer territoriesRetired = 0;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static Report retireStale(Boolean dryRun, String phase) {
        Report report = new Report();
        report.dryRun = dryRun != false;
        String step = String.isBlank(phase) ? '' : phase.trim().toUpperCase();
        if (!report.dryRun && step != PHASE_PRODUCTS && step != PHASE_ALIGNMENTS && step != PHASE_TERRITORIES) {
            throw new AuraHandledException('Pick a phase: PRODUCTS, ALIGNMENTS or TERRITORIES.');
        }
        Boolean doProducts = !report.dryRun && step == PHASE_PRODUCTS;
        Boolean doAlignments = !report.dryRun && step == PHASE_ALIGNMENTS;
        Boolean doTerritories = !report.dryRun && step == PHASE_TERRITORIES;
        planBusinessUnitNames(report, doTerritories);

        Set<String> current = organogramExternalIds();
        List<Territory2> staleDistricts = new List<Territory2>();
        List<Territory2> stalePositions = new List<Territory2>();
        List<Territory2> staleLines = new List<Territory2>();
        for (Territory2 node : [
            SELECT Id, Name, External_ID__c, Territory_Type__c, ParentTerritory2Id
            FROM Territory2
            WHERE Territory_Type__c IN ('District', 'Position', 'Line')
                AND External_ID__c LIKE 'TERR_%'
            WITH SYSTEM_MODE
            LIMIT 5000
        ]) {
            String ext = node.External_ID__c;
            if (testOnlyExternalIds != null && !testOnlyExternalIds.contains(ext)) {
                continue;
            }
            if (current.contains(ext) || isTrainingOrDemo(ext)) {
                continue;
            }
            if (node.Territory_Type__c == 'District') {
                staleDistricts.add(node);
                report.staleDistricts.add(ext);
            } else if (node.Territory_Type__c == 'Position') {
                stalePositions.add(node);
                report.stalePositions.add(ext);
            } else {
                staleLines.add(node);
                report.staleLines.add(ext);
            }
        }

        Set<Id> staleSeatIds = new Set<Id>();
        for (Territory2 node : staleDistricts) {
            staleSeatIds.add(node.Id);
        }
        for (Territory2 node : stalePositions) {
            staleSeatIds.add(node.Id);
        }

        remapStaleLineProducts(staleLines, report, doProducts);
        checkSeatBlockers(staleSeatIds, report);
        List<Territory2> retirableLines = checkLineBlockers(staleLines, staleSeatIds, report);

        Boolean seatsSafe = true;
        for (String blocker : report.blockers) {
            if (blocker.startsWith('SEAT:')) {
                seatsSafe = false;
            }
        }

        if (doAlignments && seatsSafe && !staleSeatIds.isEmpty()) {
            report.productAlignmentsDeactivated = deactivateProductAlignments(staleSeatIds);
        }
        if (doTerritories) {
            if (seatsSafe && !staleSeatIds.isEmpty()) {
                retire(stalePositions, report);
                retire(staleDistricts, report);
            }
            if (!retirableLines.isEmpty()) {
                retire(retirableLines, report);
            }
        }
        report.message =
            (report.dryRun ? 'Dry run. ' : 'Applied. ')
            + report.staleDistricts.size() + ' stale districts, '
            + report.stalePositions.size() + ' stale positions, '
            + report.staleLines.size() + ' stale lines; '
            + report.blockers.size() + ' blockers; '
            + report.territoriesRetired + ' territories retired.';
        return report;
    }

    @TestVisible
    private static Boolean isTrainingOrDemo(String externalId) {
        return externalId == null
            || externalId.contains('TRAINING')
            || externalId.contains('DEMO');
    }

    @TestVisible
    private static Set<String> organogramExternalIds() {
        TerritoriesPayload payload = parseTerritoriesPayload();
        Set<String> out = new Set<String>();
        for (List<TerritoryNode> level : new List<List<TerritoryNode>>{
            payload.businessUnits, payload.lines, payload.districts, payload.positions
        }) {
            if (level == null) {
                continue;
            }
            for (TerritoryNode node : level) {
                if (node != null && String.isNotBlank(node.externalId)) {
                    out.add(node.externalId);
                }
            }
        }
        if (payload.headOffice != null && String.isNotBlank(payload.headOffice.externalId)) {
            out.add(payload.headOffice.externalId);
        }
        return out;
    }

    @TestVisible
    private static Map<String, String> businessUnitNames() {
        Map<String, String> out = new Map<String, String>();
        TerritoriesPayload payload = parseTerritoriesPayload();
        if (payload.businessUnits != null) {
            for (TerritoryNode node : payload.businessUnits) {
                if (node != null && String.isNotBlank(node.externalId) && String.isNotBlank(node.name)) {
                    out.put(node.externalId, node.name);
                }
            }
        }
        return out;
    }

    private static TerritoriesPayload parseTerritoriesPayload() {
        String body = testTerritoriesJson;
        if (String.isBlank(body)) {
            StaticResource resource = [
                SELECT Body
                FROM StaticResource
                WHERE Name = :TERRITORIES_RESOURCE
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            body = resource.Body.toString();
        }
        return (TerritoriesPayload) JSON.deserialize(body, TerritoriesPayload.class);
    }

    private static void planBusinessUnitNames(Report report, Boolean apply) {
        Map<String, String> wanted = businessUnitNames();
        if (wanted.isEmpty()) {
            return;
        }
        List<Territory2> updates = new List<Territory2>();
        for (Territory2 bu : [
            SELECT Id, Name, External_ID__c
            FROM Territory2
            WHERE External_ID__c IN :wanted.keySet()
            WITH SYSTEM_MODE
        ]) {
            String name = wanted.get(bu.External_ID__c);
            if (name != null && bu.Name != name) {
                report.renamedBusinessUnits.add(bu.External_ID__c + ': ' + bu.Name + ' -> ' + name);
                updates.add(new Territory2(Id = bu.Id, Name = name));
            }
        }
        if (apply && !updates.isEmpty()) {
            for (Database.SaveResult result : Database.update(updates, false)) {
                if (!result.isSuccess()) {
                    report.errors.add('Rename BU: ' + result.getErrors()[0].getMessage());
                }
            }
        }
    }

    private static void checkSeatBlockers(Set<Id> staleSeatIds, Report report) {
        if (staleSeatIds.isEmpty()) {
            return;
        }
        Integer seated = [
            SELECT COUNT()
            FROM UserTerritory2Association
            WHERE Territory2Id IN :staleSeatIds
            WITH SYSTEM_MODE
        ];
        if (seated > 0) {
            report.blockers.add('SEAT: ' + seated + ' user(s) are still seated on stale districts or positions.');
        }
        Set<String> idStrings = new Set<String>();
        for (Id seatId : staleSeatIds) {
            idStrings.add(String.valueOf(seatId));
        }
        Integer targets = [
            SELECT COUNT()
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :idStrings AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
        ];
        if (targets > 0) {
            report.blockers.add('SEAT: ' + targets + ' active account target row(s) sit on stale seats.');
        }
        Integer associations = [
            SELECT COUNT()
            FROM ObjectTerritory2Association
            WHERE Territory2Id IN :staleSeatIds
            WITH SYSTEM_MODE
        ];
        if (associations > 0) {
            report.blockers.add('SEAT: ' + associations + ' account association(s) sit on stale seats.');
        }
        Integer outsideChildren = [
            SELECT COUNT()
            FROM Territory2
            WHERE ParentTerritory2Id IN :staleSeatIds AND Id NOT IN :staleSeatIds
            WITH SYSTEM_MODE
        ];
        if (outsideChildren > 0) {
            report.blockers.add('SEAT: ' + outsideChildren + ' current territory(ies) still hang below a stale seat.');
        }
    }

    private static List<Territory2> checkLineBlockers(
        List<Territory2> staleLines,
        Set<Id> staleSeatIds,
        Report report
    ) {
        List<Territory2> retirable = new List<Territory2>();
        if (staleLines.isEmpty()) {
            return retirable;
        }
        Set<Id> lineIds = new Set<Id>();
        Set<String> lineNames = new Set<String>();
        for (Territory2 line : staleLines) {
            lineIds.add(line.Id);
            if (String.isNotBlank(line.Name)) {
                lineNames.add(line.Name);
            }
        }
        Map<Id, Integer> seatedByLine = new Map<Id, Integer>();
        for (AggregateResult row : [
            SELECT Territory2Id terrId, COUNT(Id) cnt
            FROM UserTerritory2Association
            WHERE Territory2Id IN :lineIds
            WITH SYSTEM_MODE
            GROUP BY Territory2Id
        ]) {
            seatedByLine.put((Id) row.get('terrId'), (Integer) row.get('cnt'));
        }
        Map<Id, Integer> outsideChildrenByLine = new Map<Id, Integer>();
        for (AggregateResult row : [
            SELECT ParentTerritory2Id parentId, COUNT(Id) cnt
            FROM Territory2
            WHERE ParentTerritory2Id IN :lineIds AND Id NOT IN :staleSeatIds
            WITH SYSTEM_MODE
            GROUP BY ParentTerritory2Id
        ]) {
            outsideChildrenByLine.put((Id) row.get('parentId'), (Integer) row.get('cnt'));
        }
        Map<String, Integer> productsByLineName = new Map<String, Integer>();
        if (!lineNames.isEmpty()) {
            for (AggregateResult row : [
                SELECT Sales_Line__c lineName, COUNT(Id) cnt
                FROM Product2
                WHERE Sales_Line__c IN :lineNames
                WITH SYSTEM_MODE
                GROUP BY Sales_Line__c
            ]) {
                productsByLineName.put((String) row.get('lineName'), (Integer) row.get('cnt'));
            }
        }
        for (Territory2 line : staleLines) {
            List<String> lineBlockers = new List<String>();
            Integer seated = seatedByLine.containsKey(line.Id) ? seatedByLine.get(line.Id) : 0;
            if (seated > 0) {
                lineBlockers.add(seated + ' user(s) seated on the line');
            }
            Integer outsideChildren = outsideChildrenByLine.containsKey(line.Id)
                ? outsideChildrenByLine.get(line.Id)
                : 0;
            if (outsideChildren > 0) {
                lineBlockers.add(outsideChildren + ' current district(s) below the line');
            }
            Integer products = productsByLineName.containsKey(line.Name)
                ? productsByLineName.get(line.Name)
                : 0;
            if (products > 0) {
                lineBlockers.add(products + ' product(s) still on this line');
            }
            if (lineBlockers.isEmpty()) {
                retirable.add(line);
            } else {
                report.blockers.add('LINE ' + line.External_ID__c + ': ' + String.join(lineBlockers, '; '));
            }
        }
        return retirable;
    }

    /**
     * Products on the stale line move to NEUROSCIENCE-I or II only when every product of the same
     * family (brand or first word of the name) that already sits on a current line agrees.
     * Anything without that evidence is listed, not guessed.
     */
    private static void remapStaleLineProducts(List<Territory2> staleLines, Report report, Boolean apply) {
        Set<String> staleNames = new Set<String>();
        for (Territory2 line : staleLines) {
            staleNames.add(line.Name);
        }
        if (staleNames.isEmpty()) {
            return;
        }
        List<Product2> stuck = [
            SELECT Id, Name, ProductCode, Sales_Line__c, Primary_Brand__c
            FROM Product2
            WHERE Sales_Line__c IN :staleNames
            WITH SYSTEM_MODE
            LIMIT 2000
        ];
        if (stuck.isEmpty()) {
            return;
        }
        Map<String, Set<String>> linesByFamily = new Map<String, Set<String>>();
        for (Product2 sibling : [
            SELECT Name, Primary_Brand__c, Sales_Line__c
            FROM Product2
            WHERE Sales_Line__c IN :NEURO_TARGET_LINES
            WITH SYSTEM_MODE
            LIMIT 2000
        ]) {
            String family = familyKey(sibling);
            if (!linesByFamily.containsKey(family)) {
                linesByFamily.put(family, new Set<String>());
            }
            linesByFamily.get(family).add(sibling.Sales_Line__c);
        }
        List<Product2> updates = new List<Product2>();
        for (Product2 product : stuck) {
            Set<String> lines = linesByFamily.get(familyKey(product));
            if (lines != null && lines.size() == 1) {
                String target = new List<String>(lines)[0];
                report.productsRemapped.add(product.ProductCode + ' ' + product.Name + ' -> ' + target);
                updates.add(new Product2(Id = product.Id, Sales_Line__c = target));
            } else {
                report.productsUnmapped.add(product.ProductCode + ' ' + product.Name);
            }
        }
        if (apply && !updates.isEmpty()) {
            for (Database.SaveResult result : Database.update(updates, false)) {
                if (!result.isSuccess()) {
                    report.errors.add('Remap product: ' + result.getErrors()[0].getMessage());
                }
            }
        }
    }

    @TestVisible
    private static String familyKey(Product2 product) {
        String brand = String.isBlank(product.Primary_Brand__c) ? product.Name : product.Primary_Brand__c;
        if (String.isBlank(brand)) {
            return '';
        }
        return brand.trim().toUpperCase().split('[ \\-_/]+')[0];
    }

    private static Integer deactivateProductAlignments(Set<Id> staleSeatIds) {
        Set<String> idStrings = new Set<String>();
        for (Id seatId : staleSeatIds) {
            idStrings.add(String.valueOf(seatId));
        }
        List<Product_Territory_Alignment__c> active = [
            SELECT Id
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c IN :idStrings AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
        for (Product_Territory_Alignment__c row : active) {
            row.Is_Active__c = false;
        }
        if (!active.isEmpty()) {
            update as system active;
        }
        return active.size();
    }

    private static void retire(List<Territory2> nodes, Report report) {
        if (nodes.isEmpty()) {
            return;
        }
        for (Database.DeleteResult result : Database.delete(nodes, false)) {
            if (result.isSuccess()) {
                report.territoriesRetired++;
            } else {
                report.errors.add('Delete ' + result.getId() + ': ' + result.getErrors()[0].getMessage());
            }
        }
    }
}
