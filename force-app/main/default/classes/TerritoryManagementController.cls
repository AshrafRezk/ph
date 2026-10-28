public without sharing class TerritoryManagementController {

    public class TerritoryAssignment {
        @AuraEnabled public Id associationId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String role;
        @AuraEnabled public String userTitle;
        @AuraEnabled public String userLogin;
        @AuraEnabled public String employeeNumber;
    }

    public class TerritoryTreeNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public String level;
        @AuraEnabled public Id parentId;
        @AuraEnabled public Boolean hasChildren;
        @AuraEnabled public Boolean isVacant;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public Boolean canDelete;
        @AuraEnabled public Boolean canAddChild;
        @AuraEnabled public List<TerritoryAssignment> assignments;
        @AuraEnabled public List<TerritoryTreeNode> children;
        @AuraEnabled public Decimal callRate;
        @AuraEnabled public Decimal amCallRate;
        @AuraEnabled public Decimal pmCallRate;
        @AuraEnabled public String businessUnitName;
        @AuraEnabled public String descendantAssignmentLabel;
        @AuraEnabled public Integer descendantUserCount;
        /** True when this node itself has no assigned user (never hidden by the rollup). */
        @AuraEnabled public Boolean seatVacant;
        /** Count of vacant District (DM) seats at or below this node. Separate from descendantUserCount. */
        @AuraEnabled public Integer vacantDmSeatCount;
    }

    public class UserOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String username;
        @AuraEnabled public String title;
        @AuraEnabled public String businessUnit;
        @AuraEnabled public String profileName;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isSystemAdmin;
        @AuraEnabled public Boolean canDeactivate;
        @AuraEnabled public String label;
        @AuraEnabled public String lineName;
        @AuraEnabled public String territoryName;
        @AuraEnabled public Date hireDate;
        @AuraEnabled public Date resignationDate;
        @AuraEnabled public Date lastWorkDay;
    }

    public class ManagedUsersPage {
        @AuraEnabled public List<UserOption> users;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer activeCount;
        @AuraEnabled public Integer inactiveCount;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public List<String> titleOptions;
        @AuraEnabled public List<String> lineOptions;
        @AuraEnabled public List<String> businessUnitOptions;
        /** Echo of the search text this page was built from, so a stale response can be ignored. */
        @AuraEnabled public String appliedSearchTerm;
        /** False for managers: Edit, OTP and activate/deactivate are refused for them. */
        @AuraEnabled public Boolean canManageUsers;
        /** True when the list is limited to the caller's own team. */
        @AuraEnabled public Boolean teamScoped;
    }

    public class UserQueryRequest {
        @AuraEnabled public String searchTerm;
        @AuraEnabled public Boolean includeInactive;
        @AuraEnabled public String titleFilter;
        @AuraEnabled public String lineFilter;
        @AuraEnabled public String territoryFilter;
        @AuraEnabled public String businessUnitFilter;
        @AuraEnabled public String activeFilter;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
    }

    public class UserProfileForm {
        @AuraEnabled public Id userId;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String username;
        @AuraEnabled public String title;
        @AuraEnabled public String department;
    }

    public class PasswordSetResult {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer failureCount;
        @AuraEnabled public Integer emailSentCount;
        @AuraEnabled public Integer emailFailureCount;
        @AuraEnabled public String passwordUsed;
        @AuraEnabled public List<String> messages;
    }

    public class UserStatusResult {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public Integer failureCount;
        @AuraEnabled public List<String> messages;
    }

    public class LineSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public String businessUnitName;
        @AuraEnabled public Integer districtCount;
        @AuraEnabled public Integer repCount;
        @AuraEnabled public Integer assignedUserCount;
        @AuraEnabled public Integer productCount;
        @AuraEnabled public Integer brandCount;
        @AuraEnabled public Integer detailCount;
        @AuraEnabled public Integer sampleCount;
        @AuraEnabled public Integer reminderCount;
        @AuraEnabled public Boolean isProtected;
        @AuraEnabled public Decimal callRate;
    }

    public class LineProductRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productType;
        @AuraEnabled public String primaryBrand;
        @AuraEnabled public String salesLine;
        @AuraEnabled public String mirrorLine;
        @AuraEnabled public String salesUnit;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String parentName;
        @AuraEnabled public Boolean matchedViaMirror;
        @AuraEnabled public Date effectiveFrom;
        @AuraEnabled public Id alignmentId;
    }

    public class ProductRemoveRow {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    public class BulkRemoveResult {
        @AuraEnabled public Integer requested = 0;
        @AuraEnabled public Integer removed = 0;
        @AuraEnabled public Integer unchanged = 0;
        @AuraEnabled public Integer failed = 0;
        @AuraEnabled public List<ProductRemoveRow> rows = new List<ProductRemoveRow>();
    }

    public class MirrorResult {
        @AuraEnabled public Integer updated = 0;
        @AuraEnabled public Integer failed = 0;
        @AuraEnabled public List<String> messages = new List<String>();
    }

    public class ParentOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String level;
    }

    public class TerritoryForm {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public Id parentId;
        @AuraEnabled public String level;
        @AuraEnabled public Decimal callRate;
        @AuraEnabled public Decimal amCallRate;
        @AuraEnabled public Decimal pmCallRate;
    }

    /**
     * Legacy stub retained so older org tests (S_TerritoryManagementControllerTest) compile.
     * Prefer getTerritoryTree / getProductLines for the live console.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getConsoleData() {
        return new Map<String, Object>{
            'territories' => getTerritoryTree(),
            'productLines' => getProductLines()
        };
    }

    public class CreatedUserResult {
        @AuraEnabled public Id userId;
        @AuraEnabled public String username;
        @AuraEnabled public String message;
    }

    @AuraEnabled(cacheable=true)
    public static List<LineSummary> getProductLines() {
        String pharmaPrefix = 'TERR_%';
        List<Territory2> lines = [
            SELECT Id, Name, External_ID__c, Territory_Type__c, ParentTerritory2Id, ParentTerritory2.Name
            FROM Territory2
            WHERE External_ID__c LIKE :pharmaPrefix
                AND Territory_Type__c = 'Line'
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 500
        ];
        // Managers only get the line cards of their own team.
        Set<Id> scopedLineIds = TerritoryConsoleScope.getScopedLineIds();
        if (scopedLineIds != null) {
            List<Territory2> kept = new List<Territory2>();
            for (Territory2 line : lines) {
                if (scopedLineIds.contains(line.Id)) {
                    kept.add(line);
                }
            }
            lines = kept;
        }

        Map<Id, Integer> districtCountByLine = new Map<Id, Integer>();
        Map<Id, Integer> repCountByLine = new Map<Id, Integer>();
        Map<Id, Set<Id>> assignedUsersByLine = new Map<Id, Set<Id>>();
        Map<Id, Set<Id>> territoryIdsByLine = new Map<Id, Set<Id>>();
        if (!lines.isEmpty()) {
            Set<Id> lineIds = new Map<Id, Territory2>(lines).keySet();
            for (Id lineId : lineIds) {
                territoryIdsByLine.put(lineId, new Set<Id>{ lineId });
                assignedUsersByLine.put(lineId, new Set<Id>());
            }
            List<Territory2> districts = [
                SELECT Id, ParentTerritory2Id
                FROM Territory2
                WHERE ParentTerritory2Id IN :lineIds
                    AND Territory_Type__c = 'District'
                WITH SYSTEM_MODE
            ];
            Set<Id> districtIds = new Set<Id>();
            Map<Id, Id> lineByDistrict = new Map<Id, Id>();
            for (Territory2 district : districts) {
                Integer current = districtCountByLine.containsKey(district.ParentTerritory2Id)
                    ? districtCountByLine.get(district.ParentTerritory2Id)
                    : 0;
                districtCountByLine.put(district.ParentTerritory2Id, current + 1);
                districtIds.add(district.Id);
                lineByDistrict.put(district.Id, district.ParentTerritory2Id);
                territoryIdsByLine.get(district.ParentTerritory2Id).add(district.Id);
            }
            if (!districtIds.isEmpty()) {
                for (Territory2 position : [
                    SELECT Id, ParentTerritory2Id
                    FROM Territory2
                    WHERE ParentTerritory2Id IN :districtIds
                        AND Territory_Type__c = 'Position'
                    WITH SYSTEM_MODE
                ]) {
                    Id lineId = lineByDistrict.get(position.ParentTerritory2Id);
                    if (lineId == null) {
                        continue;
                    }
                    Integer current = repCountByLine.containsKey(lineId) ? repCountByLine.get(lineId) : 0;
                    repCountByLine.put(lineId, current + 1);
                    territoryIdsByLine.get(lineId).add(position.Id);
                }
            }
            Set<Id> allScopedTerritoryIds = new Set<Id>();
            for (Set<Id> scoped : territoryIdsByLine.values()) {
                allScopedTerritoryIds.addAll(scoped);
            }
            if (!allScopedTerritoryIds.isEmpty()) {
                for (UserTerritory2Association link : [
                    SELECT UserId, Territory2Id
                    FROM UserTerritory2Association
                    WHERE Territory2Id IN :allScopedTerritoryIds AND IsActive = TRUE
                    WITH SYSTEM_MODE
                ]) {
                    for (Id lineId : territoryIdsByLine.keySet()) {
                        if (territoryIdsByLine.get(lineId).contains(link.Territory2Id)) {
                            assignedUsersByLine.get(lineId).add(link.UserId);
                        }
                    }
                }
            }
        }

        Map<String, List<Id>> lineIdsByKey = new Map<String, List<Id>>();
        for (Territory2 line : lines) {
            Set<String> keys = buildLineMatchKeys(line.Name, line.External_ID__c);
            for (String key : keys) {
                if (!lineIdsByKey.containsKey(key)) {
                    lineIdsByKey.put(key, new List<Id>());
                }
                lineIdsByKey.get(key).add(line.Id);
            }
        }

        Map<Id, Integer> productCountByLine = new Map<Id, Integer>();
        Map<Id, Integer> brandCountByLine = new Map<Id, Integer>();
        Map<Id, Integer> detailCountByLine = new Map<Id, Integer>();
        Map<Id, Integer> sampleCountByLine = new Map<Id, Integer>();
        Map<Id, Integer> reminderCountByLine = new Map<Id, Integer>();
        Map<Id, Map<String, Integer>> unitVotesByLine = new Map<Id, Map<String, Integer>>();

        if (!lines.isEmpty()) {
            for (Product2 product : [
                SELECT Id, Product_Type__c, Sales_Line__c, Mirror_Line__c, Sales_Unit__c, IsActive
                FROM Product2
                WHERE IsActive = TRUE
                    AND (
                        (Sales_Line__c != NULL AND Sales_Line__c != '')
                        OR (Mirror_Line__c != NULL AND Mirror_Line__c != '')
                    )
                WITH SYSTEM_MODE
                LIMIT 10000
            ]) {
                String salesKey = normalizeLineKey(product.Sales_Line__c);
                Boolean salesNonPromoted = isNonPromotedKey(salesKey);
                Boolean allMirrorsNonPromoted = true;
                for (String mirrorLabel : splitMirrorLabels(product.Mirror_Line__c)) {
                    if (!isNonPromotedKey(normalizeLineKey(mirrorLabel))) {
                        allMirrorsNonPromoted = false;
                        break;
                    }
                }
                if (salesNonPromoted && (allMirrorsNonPromoted || String.isBlank(product.Mirror_Line__c))) {
                    continue;
                }
                Set<Id> matchedLineIds = new Set<Id>();
                if (String.isNotBlank(salesKey) && lineIdsByKey.containsKey(salesKey)) {
                    matchedLineIds.addAll(lineIdsByKey.get(salesKey));
                }
                for (String mirrorLabel : splitMirrorLabels(product.Mirror_Line__c)) {
                    String mirrorKey = normalizeLineKey(mirrorLabel);
                    if (String.isNotBlank(mirrorKey) && lineIdsByKey.containsKey(mirrorKey)) {
                        matchedLineIds.addAll(lineIdsByKey.get(mirrorKey));
                    }
                }
                for (Id lineId : matchedLineIds) {
                    incrementCount(productCountByLine, lineId);
                    String productType = product.Product_Type__c;
                    if (productType == 'Brand') {
                        incrementCount(brandCountByLine, lineId);
                    } else if (productType == 'Detail') {
                        incrementCount(detailCountByLine, lineId);
                    } else if (productType == 'Sample') {
                        incrementCount(sampleCountByLine, lineId);
                    } else if (productType == 'Brand Reminder') {
                        incrementCount(reminderCountByLine, lineId);
                    }
                    if (String.isNotBlank(product.Sales_Unit__c)
                        && !isNonPromotedKey(normalizeLineKey(product.Sales_Unit__c))) {
                        if (!unitVotesByLine.containsKey(lineId)) {
                            unitVotesByLine.put(lineId, new Map<String, Integer>());
                        }
                        Map<String, Integer> votes = unitVotesByLine.get(lineId);
                        String unit = product.Sales_Unit__c.trim();
                        votes.put(unit, (votes.containsKey(unit) ? votes.get(unit) : 0) + 1);
                    }
                }
            }
        }

        List<LineSummary> summaries = new List<LineSummary>();
        for (Territory2 line : lines) {
            LineSummary summary = new LineSummary();
            summary.id = line.Id;
            summary.name = line.Name;
            summary.externalId = line.External_ID__c;
            summary.businessUnitName = line.ParentTerritory2 != null ? line.ParentTerritory2.Name : null;
            summary.therapyArea = dominantUnit(unitVotesByLine.get(line.Id));
            summary.districtCount = districtCountByLine.containsKey(line.Id)
                ? districtCountByLine.get(line.Id)
                : 0;
            summary.repCount = repCountByLine.containsKey(line.Id) ? repCountByLine.get(line.Id) : 0;
            summary.assignedUserCount = assignedUsersByLine.containsKey(line.Id)
                ? assignedUsersByLine.get(line.Id).size()
                : 0;
            summary.productCount = productCountByLine.containsKey(line.Id)
                ? productCountByLine.get(line.Id)
                : 0;
            summary.brandCount = brandCountByLine.containsKey(line.Id) ? brandCountByLine.get(line.Id) : 0;
            summary.detailCount = detailCountByLine.containsKey(line.Id) ? detailCountByLine.get(line.Id) : 0;
            summary.sampleCount = sampleCountByLine.containsKey(line.Id) ? sampleCountByLine.get(line.Id) : 0;
            summary.reminderCount = reminderCountByLine.containsKey(line.Id)
                ? reminderCountByLine.get(line.Id)
                : 0;
            summary.isProtected = false;
            summaries.add(summary);
        }
        return summaries;
    }

    @AuraEnabled(cacheable=true)
    public static List<LineProductRow> getProductsForLine(Id lineTerritoryId) {
        Territory2 line = requireLineTerritory(lineTerritoryId);
        Set<String> keys = buildLineMatchKeys(line.Name, line.External_ID__c);
        String lineKey = String.valueOf(line.Id);
        Map<Id, Product_Territory_Alignment__c> alignmentByProduct = new Map<Id, Product_Territory_Alignment__c>();
        for (Product_Territory_Alignment__c alignment : [
            SELECT Id, Product2_Id__c, Effective_Start_Date__c, Is_Active__c
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c = :lineKey AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
            LIMIT 5000
        ]) {
            if (String.isNotBlank(alignment.Product2_Id__c)) {
                try {
                    alignmentByProduct.put(Id.valueOf(alignment.Product2_Id__c), alignment);
                } catch (Exception ignore) {
                    // Skip malformed product id text.
                }
            }
        }
        List<LineProductRow> rows = new List<LineProductRow>();
        for (Product2 product : [
            SELECT
                Id,
                Name,
                ProductCode,
                Product_Type__c,
                Primary_Brand__c,
                Sales_Line__c,
                Mirror_Line__c,
                Sales_Unit__c,
                IsActive,
                Parent_Product__r.Name
            FROM Product2
            WHERE
                (Sales_Line__c != NULL AND Sales_Line__c != '')
                OR (Mirror_Line__c != NULL AND Mirror_Line__c != '')
            WITH SYSTEM_MODE
            ORDER BY Product_Type__c ASC, Name ASC
            LIMIT 5000
        ]) {
            String salesKey = normalizeLineKey(product.Sales_Line__c);
            Boolean matchedSales = String.isNotBlank(salesKey) && keys.contains(salesKey);
            Boolean matchedMirror = mirrorKeysContain(product.Mirror_Line__c, keys);
            if (!matchedSales && !matchedMirror) {
                continue;
            }
            LineProductRow row = toLineProductRow(product, matchedMirror && !matchedSales);
            Product_Territory_Alignment__c alignment = alignmentByProduct.get(product.Id);
            if (alignment != null) {
                row.alignmentId = alignment.Id;
                row.effectiveFrom = alignment.Effective_Start_Date__c;
            }
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static LineProductRow setProductEffectiveFrom(Id alignmentId, Id productId, Id lineTerritoryId, Date effectiveFrom) {
        Territory2 line = requireLineTerritory(lineTerritoryId);
        String lineKey = String.valueOf(line.Id);
        String productKey = productId == null ? null : String.valueOf(productId);
        Product_Territory_Alignment__c alignment;
        if (alignmentId != null) {
            List<Product_Territory_Alignment__c> existing = [
                SELECT Id, Product2_Id__c, Territory2_Id__c, Effective_Start_Date__c, Is_Active__c
                FROM Product_Territory_Alignment__c
                WHERE Id = :alignmentId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (existing.isEmpty()) {
                throw new AuraHandledException('Product alignment not found.');
            }
            alignment = existing[0];
        } else if (String.isNotBlank(productKey)) {
            List<Product_Territory_Alignment__c> existing = [
                SELECT Id, Product2_Id__c, Territory2_Id__c, Effective_Start_Date__c, Is_Active__c
                FROM Product_Territory_Alignment__c
                WHERE Product2_Id__c = :productKey AND Territory2_Id__c = :lineKey AND Is_Active__c = TRUE
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (existing.isEmpty()) {
                alignment = new Product_Territory_Alignment__c(
                    Product2_Id__c = productKey,
                    Territory2_Id__c = lineKey,
                    Is_Active__c = true,
                    Unique_Key__c = (lineKey + ':' + productKey).left(80)
                );
            } else {
                alignment = existing[0];
            }
        } else {
            throw new AuraHandledException('Product is required.');
        }
        alignment.Effective_Start_Date__c = effectiveFrom;
        upsert as system alignment;
        Id resolvedProductId = Id.valueOf(alignment.Product2_Id__c);
        Product2 product = [
            SELECT
                Id,
                Name,
                ProductCode,
                Product_Type__c,
                Primary_Brand__c,
                Sales_Line__c,
                Mirror_Line__c,
                Sales_Unit__c,
                IsActive,
                Parent_Product__r.Name
            FROM Product2
            WHERE Id = :resolvedProductId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        LineProductRow row = toLineProductRow(product, false);
        row.alignmentId = alignment.Id;
        row.effectiveFrom = alignment.Effective_Start_Date__c;
        return row;
    }

    @AuraEnabled(cacheable=true)
    public static List<LineProductRow> searchAssignableProducts(Id lineTerritoryId, String searchTerm) {
        Territory2 line = requireLineTerritory(lineTerritoryId);
        Set<String> keys = buildLineMatchKeys(line.Name, line.External_ID__c);
        String term = String.isBlank(searchTerm) ? null : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';

        String soql =
            'SELECT Id, Name, ProductCode, Product_Type__c, Primary_Brand__c, Sales_Line__c,'
            + ' Mirror_Line__c, Sales_Unit__c, IsActive, Parent_Product__r.Name'
            + ' FROM Product2 WHERE IsActive = TRUE';
        if (term != null) {
            soql +=
                ' AND (Name LIKE :term OR ProductCode LIKE :term OR Primary_Brand__c LIKE :term'
                + ' OR Sales_Line__c LIKE :term OR Mirror_Line__c LIKE :term)';
        }
        soql += ' WITH SYSTEM_MODE ORDER BY Name ASC LIMIT 100';

        List<LineProductRow> rows = new List<LineProductRow>();
        for (Product2 product : Database.query(soql)) {
            String salesKey = normalizeLineKey(product.Sales_Line__c);
            if ((String.isNotBlank(salesKey) && keys.contains(salesKey))
                || mirrorKeysContain(product.Mirror_Line__c, keys)) {
                continue;
            }
            rows.add(toLineProductRow(product, false));
        }
        return rows;
    }

    @AuraEnabled
    public static void setProductLineAssignment(Id productId, Id lineTerritoryId, Boolean asMirror) {
        if (productId == null) {
            throw new AuraHandledException('Product is required.');
        }
        Territory2 line = requireLineTerritory(lineTerritoryId);
        String lineLabel = preferredLineLabel(line);
        Product2 product = [
            SELECT Id, Sales_Line__c, Mirror_Line__c
            FROM Product2
            WHERE Id = :productId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        // Append, never overwrite: a product can sit on many lines. Adding a mirror keeps the
        // existing mirrors; moving the primary sales line demotes the old primary to a mirror so the
        // product stays on the line it was already on.
        if (asMirror == true) {
            product.Mirror_Line__c = appendMirrorLabel(product.Mirror_Line__c, lineLabel);
        } else {
            String currentSalesKey = normalizeLineKey(product.Sales_Line__c);
            if (String.isNotBlank(currentSalesKey)
                && currentSalesKey != normalizeLineKey(lineLabel)
                && !isNonPromotedKey(currentSalesKey)) {
                product.Mirror_Line__c = appendMirrorLabel(product.Mirror_Line__c, product.Sales_Line__c);
            }
            product.Sales_Line__c = lineLabel;
        }
        try {
            update as system product;
        } catch (DmlException ex) {
            throw new AuraHandledException(ex.getDmlMessage(0));
        }
        syncLineProductAlignments(line.Id);
    }

    @AuraEnabled
    public static Integer clearProductLineAssignments(List<Id> productIds, Id lineTerritoryId) {
        if (productIds == null || productIds.isEmpty() || lineTerritoryId == null) {
            throw new AuraHandledException('Products and line are required.');
        }
        BulkRemoveResult result = removeProductsFromLine(productIds, lineTerritoryId);
        if (result.failed > 0 && result.removed == 0) {
            throw new AuraHandledException(firstRemoveError(result));
        }
        return result.removed;
    }

    /**
     * Bulk unlink: one query, one DML (partial success), one alignment re-sync. Every product gets its
     * own row so the console can show which ones failed instead of aborting on the first error.
     */
    @AuraEnabled
    public static BulkRemoveResult removeProductsFromLine(List<Id> productIds, Id lineTerritoryId) {
        if (productIds == null || productIds.isEmpty() || lineTerritoryId == null) {
            throw new AuraHandledException('Products and line are required.');
        }
        Territory2 line = requireLineTerritory(lineTerritoryId);
        Set<String> keys = buildLineMatchKeys(line.Name, line.External_ID__c);
        Set<Id> requestedIds = new Set<Id>();
        for (Id productId : productIds) {
            if (productId != null) {
                requestedIds.add(productId);
            }
        }
        BulkRemoveResult result = new BulkRemoveResult();
        result.requested = requestedIds.size();

        Map<Id, Product2> found = new Map<Id, Product2>(
            [
                SELECT Id, Name, Sales_Line__c, Mirror_Line__c
                FROM Product2
                WHERE Id IN :requestedIds
                WITH SYSTEM_MODE
            ]
        );
        List<Product2> toUpdate = new List<Product2>();
        for (Id productId : requestedIds) {
            Product2 product = found.get(productId);
            if (product == null) {
                result.rows.add(removeRow(productId, null, false, 'Product not found.'));
                result.failed++;
                continue;
            }
            Boolean changed = false;
            if (keys.contains(normalizeLineKey(product.Sales_Line__c))) {
                product.Sales_Line__c = null;
                changed = true;
            }
            List<String> keptMirrors = new List<String>();
            for (String mirrorLabel : splitMirrorLabels(product.Mirror_Line__c)) {
                if (keys.contains(normalizeLineKey(mirrorLabel))) {
                    changed = true;
                } else {
                    keptMirrors.add(mirrorLabel);
                }
            }
            if (!changed) {
                result.rows.add(removeRow(productId, product.Name, true, 'Was not on this line.'));
                result.unchanged++;
                continue;
            }
            product.Mirror_Line__c = keptMirrors.isEmpty() ? null : String.join(keptMirrors, ';');
            toUpdate.add(product);
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saved = Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < saved.size(); i++) {
                Product2 product = toUpdate[i];
                if (saved[i].isSuccess()) {
                    result.rows.add(removeRow(product.Id, product.Name, true, 'Removed from line.'));
                    result.removed++;
                } else {
                    String message = saved[i].getErrors().isEmpty()
                        ? 'Update failed.'
                        : saved[i].getErrors()[0].getMessage();
                    result.rows.add(removeRow(product.Id, product.Name, false, message));
                    result.failed++;
                }
            }
        }
        if (result.removed > 0) {
            syncLineProductAlignments(line.Id);
        }
        return result;
    }

    private static ProductRemoveRow removeRow(Id productId, String name, Boolean success, String message) {
        ProductRemoveRow row = new ProductRemoveRow();
        row.productId = productId;
        row.productName = name;
        row.success = success;
        row.message = message;
        return row;
    }

    private static String firstRemoveError(BulkRemoveResult result) {
        for (ProductRemoveRow row : result.rows) {
            if (row.success != true) {
                return (row.productName == null ? String.valueOf(row.productId) : row.productName)
                    + ': ' + row.message;
            }
        }
        return 'Remove failed.';
    }

    @AuraEnabled
    public static void clearProductLineAssignment(Id productId, Id lineTerritoryId) {
        if (productId == null || lineTerritoryId == null) {
            throw new AuraHandledException('Product and line are required.');
        }
        Territory2 line = requireLineTerritory(lineTerritoryId);
        Set<String> keys = buildLineMatchKeys(line.Name, line.External_ID__c);
        Product2 product = [
            SELECT Id, Sales_Line__c, Mirror_Line__c
            FROM Product2
            WHERE Id = :productId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Boolean changed = false;
        if (keys.contains(normalizeLineKey(product.Sales_Line__c))) {
            product.Sales_Line__c = null;
            changed = true;
        }
        List<String> keptMirrors = new List<String>();
        for (String mirrorLabel : splitMirrorLabels(product.Mirror_Line__c)) {
            if (keys.contains(normalizeLineKey(mirrorLabel))) {
                changed = true;
            } else {
                keptMirrors.add(mirrorLabel);
            }
        }
        if (changed) {
            product.Mirror_Line__c = keptMirrors.isEmpty() ? null : String.join(keptMirrors, ';');
        }
        if (!changed) {
            return;
        }
        try {
            update as system product;
        } catch (DmlException ex) {
            throw new AuraHandledException(ex.getDmlMessage(0));
        }
        syncLineProductAlignments(line.Id);
    }

    private static Territory2 requireLineTerritory(Id lineTerritoryId) {
        if (lineTerritoryId == null) {
            throw new AuraHandledException('Line territory is required.');
        }
        List<Territory2> lines = [
            SELECT Id, Name, External_ID__c, Territory_Type__c
            FROM Territory2
            WHERE Id = :lineTerritoryId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (lines.isEmpty()) {
            throw new AuraHandledException('Line territory not found.');
        }
        Territory2 line = lines[0];
        if (line.Territory_Type__c != 'Line') {
            throw new AuraHandledException('Selected territory is not a product line.');
        }
        Set<Id> scopedLineIds = TerritoryConsoleScope.getScopedLineIds();
        if (scopedLineIds != null && !scopedLineIds.contains(line.Id)) {
            throw new AuraHandledException(TerritoryConsoleScope.OUT_OF_SCOPE_MESSAGE);
        }
        return line;
    }

    private static LineProductRow toLineProductRow(Product2 product, Boolean matchedViaMirror) {
        LineProductRow row = new LineProductRow();
        row.id = product.Id;
        row.name = product.Name;
        row.productCode = product.ProductCode;
        row.productType = product.Product_Type__c;
        row.primaryBrand = product.Primary_Brand__c;
        row.salesLine = product.Sales_Line__c;
        row.mirrorLine = product.Mirror_Line__c;
        row.salesUnit = product.Sales_Unit__c;
        row.isActive = product.IsActive;
        row.parentName = product.Parent_Product__r != null ? product.Parent_Product__r.Name : null;
        row.matchedViaMirror = matchedViaMirror;
        return row;
    }

    private static Set<String> buildLineMatchKeys(String name, String externalId) {
        Set<String> keys = new Set<String>();
        addNormalizedKey(keys, name);
        if (String.isNotBlank(externalId)) {
            String ext = externalId.trim();
            if (ext.toUpperCase().startsWith('TERR_LINE_')) {
                addNormalizedKey(keys, ext.substring('TERR_LINE_'.length()));
            }
            addNormalizedKey(keys, ext);
        }
        return keys;
    }

    private static void addNormalizedKey(Set<String> keys, String raw) {
        String normalized = normalizeLineKey(raw);
        if (String.isNotBlank(normalized) && !isNonPromotedKey(normalized)) {
            keys.add(normalized);
        }
    }

    private static String normalizeLineKey(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String value = raw.trim().toUpperCase();
        value = value.replaceAll('[\\s\\-]+', '_');
        value = value.replaceAll('_+', '_');
        return value;
    }

    private static Boolean isNonPromotedKey(String key) {
        return key == 'NON_PROMOTED' || key == 'NONPROMOTED';
    }

    private static String preferredLineLabel(Territory2 line) {
        if (String.isNotBlank(line.Name)) {
            return line.Name.trim();
        }
        if (String.isNotBlank(line.External_ID__c)
            && line.External_ID__c.toUpperCase().startsWith('TERR_LINE_')) {
            return line.External_ID__c.substring('TERR_LINE_'.length()).replace('_', '-');
        }
        return line.External_ID__c;
    }

    private static void incrementCount(Map<Id, Integer> counts, Id key) {
        counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
    }

    private static String dominantUnit(Map<String, Integer> votes) {
        if (votes == null || votes.isEmpty()) {
            return null;
        }
        String best = null;
        Integer bestCount = -1;
        for (String unit : votes.keySet()) {
            Integer count = votes.get(unit);
            if (count > bestCount || (count == bestCount && (best == null || unit < best))) {
                best = unit;
                bestCount = count;
            }
        }
        return best;
    }

    @AuraEnabled(cacheable=true)
    public static List<ParentOption> getParentOptions(String childLevel) {
        String pharmaPrefix = 'TERR_%';
        List<ParentOption> options = new List<ParentOption>();
        String parentType;
        String parentLevelLabel;
        if (childLevel == 'Business Unit' || childLevel == 'Business_Unit') {
            parentType = 'Head_Office';
            parentLevelLabel = 'Head Office';
        } else if (childLevel == 'Line') {
            parentType = 'Business_Unit';
            parentLevelLabel = 'Business Unit';
        } else if (childLevel == 'District') {
            parentType = 'Line';
            parentLevelLabel = 'Line';
        } else if (childLevel == 'MR' || childLevel == 'Position') {
            parentType = 'District';
            parentLevelLabel = 'District';
        } else {
            return options;
        }

        for (Territory2 territory : [
            SELECT Id, Name
            FROM Territory2
            WHERE Territory_Type__c = :parentType
                AND External_ID__c LIKE :pharmaPrefix
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 2000
        ]) {
            ParentOption option = new ParentOption();
            option.id = territory.Id;
            option.label = territory.Name;
            option.level = parentLevelLabel;
            options.add(option);
        }
        return options;
    }

    /**
     * LWC sends the form as JSON. Passed as an object, Aura left the TerritoryForm fields empty,
     * so every edit failed with "Territory name is required." (same cause as queryManagedUsersJson).
     */
    @AuraEnabled
    public static Id saveTerritoryJson(String formJson) {
        TerritoryForm form;
        try {
            form = String.isBlank(formJson) ? null : (TerritoryForm) JSON.deserialize(formJson, TerritoryForm.class);
        } catch (JSONException ex) {
            throw new AuraHandledException('Territory details could not be read: ' + ex.getMessage());
        }
        return saveTerritory(form);
    }

    @AuraEnabled
    public static Id saveTerritory(TerritoryForm form) {
        if (form == null || String.isBlank(form.name)) {
            throw new AuraHandledException('Territory name is required.');
        }
        if (form.recordId != null) {
            TerritoryConsoleScope.requireInScope(form.recordId);
            List<Territory2> found = [
                SELECT Id, Name, External_ID__c
                FROM Territory2
                WHERE Id = :form.recordId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (found.isEmpty()) {
                throw new AuraHandledException('Territory not found. Refresh the page and try again.');
            }
            Territory2 territory = found[0];
            if (territory.External_ID__c == 'TERR_HEAD_OFFICE') {
                throw new AuraHandledException('Head Office cannot be edited.');
            }
            territory.Name = form.name.trim();
            if (form.parentId != null) {
                territory.ParentTerritory2Id = form.parentId;
            }
            Map<String, Schema.SObjectField> territoryFields = Schema.SObjectType.Territory2.fields.getMap();
            if (territoryFields.containsKey('Daily_Visit_Rate__c')) {
                territory.put('Daily_Visit_Rate__c', form.callRate);
            }
            if (territoryFields.containsKey('AM_Call_Rate__c')) {
                territory.put('AM_Call_Rate__c', form.amCallRate);
            }
            if (territoryFields.containsKey('PM_Call_Rate__c')) {
                territory.put('PM_Call_Rate__c', form.pmCallRate);
            }
            try {
                update as system territory;
            } catch (DmlException ex) {
                throw new AuraHandledException(ex.getDmlMessage(0));
            }
            return territory.Id;
        }
        throw new AuraHandledException(
            'Create new territories from Setup > Territory Models, or re-run the organogram loader.'
        );
    }

    @AuraEnabled
    public static Id createProductLine(String name, String code, String therapyArea) {
        throw new AuraHandledException(
            'Product lines are managed from the organogram load. Use Setup > Territory Models to add nodes.'
        );
    }

    @AuraEnabled
    public static void deleteTerritory(Id territoryId) {
        if (territoryId == null) {
            throw new AuraHandledException('Territory Id is required.');
        }
        Territory2 territory = [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE Id = :territoryId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (territory.External_ID__c == 'TERR_HEAD_OFFICE') {
            throw new AuraHandledException('Head Office cannot be deleted.');
        }
        Integer childCount = [
            SELECT COUNT()
            FROM Territory2
            WHERE ParentTerritory2Id = :territoryId
            WITH SYSTEM_MODE
        ];
        if (childCount > 0) {
            throw new AuraHandledException('Remove child territories before deleting this node.');
        }
        delete as system [
            SELECT Id
            FROM UserTerritory2Association
            WHERE Territory2Id = :territoryId
            WITH SYSTEM_MODE
        ];
        throw new AuraHandledException(
            'Assignments cleared. Delete the territory node in Setup > Territory Models.'
        );
    }

    @AuraEnabled
    public static CreatedUserResult createPharmaUser(
        String firstName,
        String lastName,
        String teamCode,
        String roleKey,
        Id territoryId,
        String roleInTerritory
    ) {
        throw new AuraHandledException(
            'Create users in Setup, then assign them from the Territories tab.'
        );
    }

    @AuraEnabled
    public static void syncDefaultLineProductAlignments() {
        String pharmaPrefix = 'TERR_%';
        List<Territory2> lines = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c LIKE :pharmaPrefix
                AND Territory_Type__c = 'Line'
            WITH SYSTEM_MODE
            LIMIT 500
        ];
        for (Territory2 line : lines) {
            syncLineProductAlignments(line.Id);
        }
    }

    @TestVisible
    private static void syncLineProductAlignments(Id lineTerritoryId) {
        if (lineTerritoryId == null) {
            return;
        }
        requireLineTerritory(lineTerritoryId);
        Set<Id> territoryIds = TerritoryHierarchyService.expandTerritoryHierarchy(
            new Set<Id>{ lineTerritoryId }
        );
        Set<Id> productIds = collectLineProductIds(lineTerritoryId);
        productIds.addAll(expandDispenseProductIds(productIds));
        Set<String> keepProductKeys = new Set<String>();
        for (Id productId : productIds) {
            keepProductKeys.add(String.valueOf(productId));
        }
        syncProductTerritoryAlignments(territoryIds, keepProductKeys);
    }

    private static void syncProductTerritoryAlignments(Set<Id> territoryIds, Set<String> keepProductKeys) {
        if (territoryIds == null || territoryIds.isEmpty()) {
            return;
        }
        Set<String> keepKeys = keepProductKeys == null ? new Set<String>() : keepProductKeys;
        Set<String> territoryKeys = new Set<String>();
        for (Id territoryId : territoryIds) {
            territoryKeys.add(String.valueOf(territoryId));
        }

        Map<String, Set<String>> existingByTerritory = new Map<String, Set<String>>();
        List<Product_Territory_Alignment__c> activeAlignments = [
            SELECT Id, Territory2_Id__c, Product2_Id__c, Is_Active__c
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c IN :territoryKeys AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
        ];
        for (Product_Territory_Alignment__c alignment : activeAlignments) {
            if (!existingByTerritory.containsKey(alignment.Territory2_Id__c)) {
                existingByTerritory.put(alignment.Territory2_Id__c, new Set<String>());
            }
            existingByTerritory.get(alignment.Territory2_Id__c).add(alignment.Product2_Id__c);
        }

        List<Product_Territory_Alignment__c> toInsert = new List<Product_Territory_Alignment__c>();
        for (String territoryKey : territoryKeys) {
            Set<String> existing = existingByTerritory.containsKey(territoryKey)
                ? existingByTerritory.get(territoryKey)
                : new Set<String>();
            for (String productKey : keepKeys) {
                if (String.isBlank(productKey) || existing.contains(productKey)) {
                    continue;
                }
                toInsert.add(
                    new Product_Territory_Alignment__c(
                        Product2_Id__c = productKey,
                        Territory2_Id__c = territoryKey,
                        Is_Active__c = true,
                        Effective_Start_Date__c = Date.today()
                    )
                );
            }
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }

        List<Product_Territory_Alignment__c> toUpdate = new List<Product_Territory_Alignment__c>();
        for (Product_Territory_Alignment__c alignment : activeAlignments) {
            if (!keepKeys.contains(alignment.Product2_Id__c)) {
                alignment.Is_Active__c = false;
                toUpdate.add(alignment);
            }
        }
        if (!toUpdate.isEmpty()) {
            update as system toUpdate;
        }
    }

    private static Set<Id> collectLineProductIds(Id lineTerritoryId) {
        Territory2 line = requireLineTerritory(lineTerritoryId);
        Set<String> keys = buildLineMatchKeys(line.Name, line.External_ID__c);
        Set<Id> productIds = new Set<Id>();
        for (Product2 product : [
            SELECT Id, Sales_Line__c, Mirror_Line__c
            FROM Product2
            WHERE
                IsActive = TRUE
                AND (
                    (Sales_Line__c != NULL AND Sales_Line__c != '')
                    OR (Mirror_Line__c != NULL AND Mirror_Line__c != '')
                )
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            String salesKey = normalizeLineKey(product.Sales_Line__c);
            if ((String.isNotBlank(salesKey) && keys.contains(salesKey))
                || mirrorKeysContain(product.Mirror_Line__c, keys)) {
                productIds.add(product.Id);
            }
        }
        return productIds;
    }

    private static Set<Id> expandDispenseProductIds(Set<Id> productIds) {
        Set<Id> expanded = new Set<Id>();
        if (productIds == null || productIds.isEmpty()) {
            return expanded;
        }
        Map<String, Schema.SObjectField> productFields = Product2.SObjectType.getDescribe().fields.getMap();
        if (!productFields.containsKey('Product_Type__c') || !productFields.containsKey('Parent_Product__c')) {
            return expanded;
        }
        Set<Id> parentIds = new Set<Id>();
        for (Product2 product : [
            SELECT Id, Parent_Product__c
            FROM Product2
            WHERE Id IN :productIds
            WITH SYSTEM_MODE
        ]) {
            parentIds.add(product.Id);
            if (product.Parent_Product__c != null) {
                parentIds.add(product.Parent_Product__c);
            }
        }
        if (parentIds.isEmpty()) {
            return expanded;
        }
        for (Product2 sibling : [
            SELECT Id
            FROM Product2
            WHERE
                IsActive = TRUE
                AND Product_Type__c IN ('Sample', 'Brand Reminder')
                AND Parent_Product__c IN :parentIds
            WITH SYSTEM_MODE
        ]) {
            expanded.add(sibling.Id);
        }
        return expanded;
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryTreeNode> getTerritoryTree() {
        String pharmaPrefix = 'TERR_%';
        Map<String, Schema.SObjectField> territoryFields = Schema.SObjectType.Territory2.fields.getMap();
        Boolean hasCallRate = territoryFields.containsKey('Daily_Visit_Rate__c');
        Boolean hasAmCallRate = territoryFields.containsKey('AM_Call_Rate__c');
        Boolean hasPmCallRate = territoryFields.containsKey('PM_Call_Rate__c');
        String selectFields =
            'Id, Name, ParentTerritory2Id, External_ID__c, Territory_Type__c'
            + (hasCallRate ? ', Daily_Visit_Rate__c' : '')
            + (hasAmCallRate ? ', AM_Call_Rate__c' : '')
            + (hasPmCallRate ? ', PM_Call_Rate__c' : '');
        List<Territory2> territories = Database.query(
            'SELECT '
            + selectFields
            + ' FROM Territory2 WHERE External_ID__c LIKE :pharmaPrefix WITH SYSTEM_MODE ORDER BY Name ASC LIMIT 5000'
        );
        // Managers see only their own team: their seats, everything below, and the chain above
        // (read-only) so the Line and Business Unit names still show.
        Set<Id> scope = TerritoryConsoleScope.getScopedTerritoryIds();
        Set<Id> contextOnlyIds = new Set<Id>();
        if (scope != null) {
            Set<Id> visible = TerritoryConsoleScope.withAncestors(scope);
            List<Territory2> kept = new List<Territory2>();
            for (Territory2 territory : territories) {
                if (visible.contains(territory.Id)) {
                    kept.add(territory);
                    if (!scope.contains(territory.Id)) {
                        contextOnlyIds.add(territory.Id);
                    }
                }
            }
            territories = kept;
        }
        if (territories.isEmpty()) {
            return new List<TerritoryTreeNode>();
        }

        Set<Id> territoryIds = new Map<Id, Territory2>(territories).keySet();
        Map<Id, List<TerritoryAssignment>> assignmentsByTerritory = loadAssignments(territoryIds);
        Map<Id, List<TerritoryTreeNode>> childrenByParent = new Map<Id, List<TerritoryTreeNode>>();
        Map<Id, TerritoryTreeNode> nodesById = new Map<Id, TerritoryTreeNode>();

        for (Territory2 territory : territories) {
            TerritoryTreeNode node = buildNode(territory, assignmentsByTerritory.get(territory.Id));
            if (contextOnlyIds.contains(territory.Id)) {
                node.canEdit = false;
                node.canDelete = false;
                node.canAddChild = false;
            }
            if (hasCallRate) {
                Object rate = territory.get('Daily_Visit_Rate__c');
                node.callRate = rate == null ? null : (Decimal) rate;
            }
            if (hasAmCallRate) {
                Object amRate = territory.get('AM_Call_Rate__c');
                node.amCallRate = amRate == null ? null : (Decimal) amRate;
            }
            if (hasPmCallRate) {
                Object pmRate = territory.get('PM_Call_Rate__c');
                node.pmCallRate = pmRate == null ? null : (Decimal) pmRate;
            }
            nodesById.put(territory.Id, node);
            if (territory.ParentTerritory2Id != null) {
                if (!childrenByParent.containsKey(territory.ParentTerritory2Id)) {
                    childrenByParent.put(territory.ParentTerritory2Id, new List<TerritoryTreeNode>());
                }
                childrenByParent.get(territory.ParentTerritory2Id).add(node);
            }
        }

        for (Id parentId : childrenByParent.keySet()) {
            if (nodesById.containsKey(parentId)) {
                nodesById.get(parentId).children = childrenByParent.get(parentId);
                nodesById.get(parentId).hasChildren = !childrenByParent.get(parentId).isEmpty();
            }
        }

        List<TerritoryTreeNode> roots = new List<TerritoryTreeNode>();
        for (Territory2 territory : territories) {
            TerritoryTreeNode node = nodesById.get(territory.Id);
            if (node.hasChildren == null) {
                node.hasChildren = false;
                node.children = new List<TerritoryTreeNode>();
            }
            if (territory.ParentTerritory2Id == null || !nodesById.containsKey(territory.ParentTerritory2Id)) {
                roots.add(node);
            }
        }

        roots.sort(new TerritoryNodeNameComparator());
        sortChildrenRecursively(roots);
        annotateBusinessUnitsAndDescendants(roots, null);
        return roots;
    }

    private static void annotateBusinessUnitsAndDescendants(List<TerritoryTreeNode> nodes, String businessUnitName) {
        if (nodes == null) {
            return;
        }
        for (TerritoryTreeNode node : nodes) {
            String currentBu = businessUnitName;
            if (node.level == 'Business Unit') {
                currentBu = node.name;
            }
            node.businessUnitName = currentBu;
            annotateBusinessUnitsAndDescendants(node.children, currentBu);
            Set<String> labels = new Set<String>();
            Set<Id> userIds = new Set<Id>();
            if (node.assignments != null) {
                for (TerritoryAssignment assignment : node.assignments) {
                    if (assignment.userId != null) {
                        userIds.add(assignment.userId);
                    }
                    String role = String.isBlank(assignment.role) ? '' : ' (' + assignment.role + ')';
                    labels.add(assignment.userName + role);
                }
            }
            if (node.children != null) {
                for (TerritoryTreeNode child : node.children) {
                    if (child.descendantUserCount != null) {
                        // child already rolled up
                    }
                    if (String.isNotBlank(child.descendantAssignmentLabel) && child.descendantAssignmentLabel != 'Vacant') {
                        for (String part : child.descendantAssignmentLabel.split(', ')) {
                            labels.add(part);
                        }
                    }
                    if (child.assignments != null) {
                        for (TerritoryAssignment assignment : child.assignments) {
                            if (assignment.userId != null) {
                                userIds.add(assignment.userId);
                            }
                        }
                    }
                    // Pull unique users from child rollup via parsing is fragile; recount from children.
                    collectDescendantUserIds(child, userIds);
                }
            }
            node.descendantUserCount = userIds.size();
            if (labels.isEmpty()) {
                node.descendantAssignmentLabel = 'Vacant';
            } else {
                List<String> sorted = new List<String>(labels);
                sorted.sort();
                // Cap label length for the tree; full count is in descendantUserCount.
                Integer maxShow = Math.min(8, sorted.size());
                List<String> shown = new List<String>();
                for (Integer i = 0; i < maxShow; i++) {
                    shown.add(sorted[i]);
                }
                String suffix = sorted.size() > maxShow ? ' (+' + String.valueOf(sorted.size() - maxShow) + ' more)' : '';
                node.descendantAssignmentLabel = String.join(shown, ', ') + suffix;
            }
            // The seat itself is vacant when nobody is assigned to it directly. The rollup count is
            // reported separately so a vacant DM seat never looks filled because reps sit below it.
            node.seatVacant = node.assignments == null || node.assignments.isEmpty();
            Integer vacantDm = (node.level == 'District' && node.seatVacant == true) ? 1 : 0;
            if (node.children != null) {
                for (TerritoryTreeNode child : node.children) {
                    vacantDm += child.vacantDmSeatCount == null ? 0 : child.vacantDmSeatCount;
                }
            }
            node.vacantDmSeatCount = vacantDm;
            // Line and Business Unit rows show the descendant rollup in the Assigned User column.
            // District rows keep their own vacancy; their rollup is a separate count.
            if ((node.level == 'Line' || node.level == 'Business Unit')
                && node.descendantUserCount != null
                && node.descendantUserCount > 0) {
                if (node.assignments == null || node.assignments.isEmpty()) {
                    node.isVacant = false;
                }
            }
        }
    }

    private static void collectDescendantUserIds(TerritoryTreeNode node, Set<Id> userIds) {
        if (node == null) {
            return;
        }
        if (node.assignments != null) {
            for (TerritoryAssignment assignment : node.assignments) {
                if (assignment.userId != null) {
                    userIds.add(assignment.userId);
                }
            }
        }
        if (node.children != null) {
            for (TerritoryTreeNode child : node.children) {
                collectDescendantUserIds(child, userIds);
            }
        }
    }

    /**
     * Mirrors primary Sales_Line products onto a mirror line (e.g. CHC → CHC_Sales, then CHC_Sales → CVM).
     * Mirror_Line__c may hold multiple labels separated by ";" so a second mirror is not skipped.
     */
    @AuraEnabled
    public static Integer mirrorLineProducts(String sourceLineName, String mirrorLineName) {
        if (String.isBlank(sourceLineName) || String.isBlank(mirrorLineName)) {
            throw new AuraHandledException('Source and mirror line names are required.');
        }
        Set<String> sourceKeys = buildLineMatchKeys(sourceLineName, null);
        String mirrorLabel = mirrorLineName.trim();
        Integer updated = 0;
        List<Product2> toUpdate = new List<Product2>();
        for (Product2 product : [
            SELECT Id, Sales_Line__c, Mirror_Line__c, Product_Type__c
            FROM Product2
            WHERE
                IsActive = TRUE
                AND (
                    (Sales_Line__c != NULL AND Sales_Line__c != '')
                    OR (Mirror_Line__c != NULL AND Mirror_Line__c != '')
                )
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            Boolean onSourceSales = sourceKeys.contains(normalizeLineKey(product.Sales_Line__c));
            Boolean onSourceMirror = mirrorKeysContain(product.Mirror_Line__c, sourceKeys);
            if (!onSourceSales && !onSourceMirror) {
                continue;
            }
            if (product.Product_Type__c != null
                && product.Product_Type__c != 'Detail'
                && product.Product_Type__c != 'Brand'
                && product.Product_Type__c != 'Sample'
                && product.Product_Type__c != 'Brand Reminder') {
                continue;
            }
            if (mirrorKeysContain(product.Mirror_Line__c, new Set<String>{ normalizeLineKey(mirrorLabel) })) {
                continue;
            }
            String nextMirror = appendMirrorLabel(product.Mirror_Line__c, mirrorLabel);
            if (nextMirror == product.Mirror_Line__c) {
                continue;
            }
            product.Mirror_Line__c = nextMirror;
            toUpdate.add(product);
        }
        if (!toUpdate.isEmpty()) {
            update as system toUpdate;
            updated = toUpdate.size();
            // Alignment sync is cartesian (territories × products) and exceeds 10k DML inline.
            enqueueAlignmentSync(mirrorLabel);
        }
        return updated;
    }

    /**
     * CHC_Sales mirrors every promoted line, not just CHC: each active product that sits on any promoted
     * line (primary or mirror) gets the mirror label appended. Partial success; alignments for the mirror
     * line are re-synced afterwards so Product_Territory_Alignment__c matches the new Mirror_Line__c values.
     *
     * CVM-I / CVM-II do NOT inherit from CHC_Sales any more (that would pull every line onto CVM); they
     * mirror from CHC directly via mirrorLineProducts('CHC', 'CVM-I' | 'CVM-II').
     */
    @AuraEnabled
    public static MirrorResult mirrorAllPromotedLines(String mirrorLineName) {
        if (String.isBlank(mirrorLineName)) {
            throw new AuraHandledException('Mirror line name is required.');
        }
        String mirrorLabel = mirrorLineName.trim();
        String mirrorKey = normalizeLineKey(mirrorLabel);
        Set<String> mirrorKeys = new Set<String>{ mirrorKey };
        MirrorResult result = new MirrorResult();
        List<Product2> toUpdate = new List<Product2>();
        for (Product2 product : [
            SELECT Id, Sales_Line__c, Mirror_Line__c, Product_Type__c
            FROM Product2
            WHERE
                IsActive = TRUE
                AND (
                    (Sales_Line__c != NULL AND Sales_Line__c != '')
                    OR (Mirror_Line__c != NULL AND Mirror_Line__c != '')
                )
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            if (product.Product_Type__c != null
                && product.Product_Type__c != 'Detail'
                && product.Product_Type__c != 'Brand'
                && product.Product_Type__c != 'Sample'
                && product.Product_Type__c != 'Brand Reminder') {
                continue;
            }
            String salesKey = normalizeLineKey(product.Sales_Line__c);
            if (salesKey == mirrorKey || mirrorKeysContain(product.Mirror_Line__c, mirrorKeys)) {
                continue;
            }
            Boolean onPromotedLine = String.isNotBlank(salesKey) && !isNonPromotedKey(salesKey);
            if (!onPromotedLine) {
                for (String label : splitMirrorLabels(product.Mirror_Line__c)) {
                    String key = normalizeLineKey(label);
                    if (String.isNotBlank(key) && !isNonPromotedKey(key)) {
                        onPromotedLine = true;
                        break;
                    }
                }
            }
            if (!onPromotedLine) {
                continue;
            }
            product.Mirror_Line__c = appendMirrorLabel(product.Mirror_Line__c, mirrorLabel);
            toUpdate.add(product);
        }
        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saved = Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < saved.size(); i++) {
                if (saved[i].isSuccess()) {
                    result.updated++;
                } else {
                    result.failed++;
                    if (result.messages.size() < 10) {
                        result.messages.add(
                            toUpdate[i].Id + ': ' + (saved[i].getErrors().isEmpty() ? 'Update failed.' : saved[i].getErrors()[0].getMessage())
                        );
                    }
                }
            }
            if (result.updated > 0) {
                enqueueAlignmentSync(mirrorLabel);
            }
        }
        return result;
    }

    /** Public for LineProductAlignmentSyncBatch — same keys as buildLineMatchKeys. */
    public static Set<String> buildLineMatchKeysPublic(String name, String externalId) {
        return buildLineMatchKeys(name, externalId);
    }

    /** Public for LineProductAlignmentSyncBatch — keys for a single label string. */
    public static Set<String> matchKeysForLineLabel(String lineLabel) {
        return buildLineMatchKeys(lineLabel, null);
    }

    public static Set<Id> collectLineProductIdsPublic(Id lineTerritoryId) {
        return collectLineProductIds(lineTerritoryId);
    }

    public static Set<Id> expandDispenseProductIdsPublic(Set<Id> productIds) {
        return expandDispenseProductIds(productIds);
    }

    private static void enqueueAlignmentSync(String lineLabel) {
        if (String.isBlank(lineLabel)) {
            return;
        }
        // Tests still sync inline (small data). In the org, CHC_Sales-scale
        // territory×product DML exceeds the 10k row limit in one transaction, so
        // Mirror_Line__c is updated here and alignments are synced via
        // LineProductAlignmentSyncBatch (run separately / from Admin Console).
        if (Test.isRunningTest()) {
            syncAlignmentsForLineLabel(lineLabel);
            return;
        }
        Database.executeBatch(new LineProductAlignmentSyncBatch(lineLabel.trim()), 1);
    }

    /** Sync alignments for a single territory Id against the keep-product set (chunked DML). */
    public static Integer syncOneTerritoryAlignments(Id territoryId, Set<String> keepProductKeys) {
        if (territoryId == null) {
            return 0;
        }
        Set<String> keepKeys = keepProductKeys == null ? new Set<String>() : keepProductKeys;
        String territoryKey = String.valueOf(territoryId);
        Integer written = 0;
        List<Product_Territory_Alignment__c> activeAlignments = [
            SELECT Id, Territory2_Id__c, Product2_Id__c, Is_Active__c
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c = :territoryKey AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
        ];
        Set<String> existing = new Set<String>();
        for (Product_Territory_Alignment__c alignment : activeAlignments) {
            existing.add(alignment.Product2_Id__c);
        }
        List<Product_Territory_Alignment__c> toInsert = new List<Product_Territory_Alignment__c>();
        for (String productKey : keepKeys) {
            if (String.isBlank(productKey) || existing.contains(productKey)) {
                continue;
            }
            toInsert.add(
                new Product_Territory_Alignment__c(
                    Product2_Id__c = productKey,
                    Territory2_Id__c = territoryKey,
                    Is_Active__c = true,
                    Effective_Start_Date__c = Date.today()
                )
            );
            if (toInsert.size() >= 2000) {
                insert as system toInsert;
                written += toInsert.size();
                toInsert.clear();
            }
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
            written += toInsert.size();
        }
        List<Product_Territory_Alignment__c> toUpdate = new List<Product_Territory_Alignment__c>();
        for (Product_Territory_Alignment__c alignment : activeAlignments) {
            if (!keepKeys.contains(alignment.Product2_Id__c)) {
                alignment.Is_Active__c = false;
                toUpdate.add(alignment);
                if (toUpdate.size() >= 2000) {
                    update as system toUpdate;
                    written += toUpdate.size();
                    toUpdate.clear();
                }
            }
        }
        if (!toUpdate.isEmpty()) {
            update as system toUpdate;
            written += toUpdate.size();
        }
        return written;
    }

    /** Re-syncs Product_Territory_Alignment__c for every Line territory whose name/external id matches the label. */
    @TestVisible
    private static Integer syncAlignmentsForLineLabel(String lineLabel) {
        Set<String> wanted = buildLineMatchKeys(lineLabel, null);
        if (wanted.isEmpty()) {
            return 0;
        }
        Integer synced = 0;
        for (Territory2 line : [
            SELECT Id, Name, External_ID__c
            FROM Territory2
            WHERE Territory_Type__c = 'Line'
            WITH SYSTEM_MODE
            LIMIT 500
        ]) {
            Set<String> lineKeys = buildLineMatchKeys(line.Name, line.External_ID__c);
            Boolean hit = false;
            for (String key : lineKeys) {
                if (wanted.contains(key)) {
                    hit = true;
                    break;
                }
            }
            if (hit) {
                syncLineProductAlignments(line.Id);
                synced++;
            }
        }
        return synced;
    }

    private static List<String> splitMirrorLabels(String raw) {
        List<String> labels = new List<String>();
        if (String.isBlank(raw)) {
            return labels;
        }
        for (String part : raw.split('[;,]')) {
            if (String.isNotBlank(part)) {
                labels.add(part.trim());
            }
        }
        return labels;
    }

    private static Boolean mirrorKeysContain(String raw, Set<String> keys) {
        if (keys == null || keys.isEmpty()) {
            return false;
        }
        for (String label : splitMirrorLabels(raw)) {
            String key = normalizeLineKey(label);
            if (String.isNotBlank(key) && keys.contains(key)) {
                return true;
            }
        }
        return false;
    }

    private static String appendMirrorLabel(String existing, String label) {
        if (String.isBlank(label)) {
            return existing;
        }
        List<String> labels = splitMirrorLabels(existing);
        String needle = normalizeLineKey(label);
        for (String current : labels) {
            if (normalizeLineKey(current) == needle) {
                return existing;
            }
        }
        labels.add(label.trim());
        return String.join(labels, ';');
    }

    @AuraEnabled(cacheable=true)
    public static List<UserOption> getAssignableUsers(String searchTerm) {
        UserQueryRequest request = new UserQueryRequest();
        request.searchTerm = searchTerm;
        request.includeInactive = false;
        request.pageNumber = 1;
        request.pageSize = 200;
        return queryManagedUsers(request).users;
    }

    @AuraEnabled(cacheable=true)
    public static List<UserOption> getManagedUsers(String searchTerm, Boolean includeInactive) {
        UserQueryRequest request = new UserQueryRequest();
        request.searchTerm = searchTerm;
        request.includeInactive = includeInactive;
        request.pageNumber = 1;
        request.pageSize = 500;
        return queryManagedUsers(request).users;
    }

    /**
     * LWC sends the filters as JSON. Aura leaves the fields on UserQueryRequest empty when the
     * object is passed directly, so search and page number never arrived.
     */
    @AuraEnabled
    public static ManagedUsersPage queryManagedUsersJson(String requestJson) {
        UserQueryRequest request = String.isBlank(requestJson)
            ? new UserQueryRequest()
            : (UserQueryRequest) JSON.deserialize(requestJson, UserQueryRequest.class);
        return queryManagedUsers(request);
    }

    @AuraEnabled
    public static ManagedUsersPage queryManagedUsers(UserQueryRequest request) {
        if (request == null) {
            request = new UserQueryRequest();
        }
        Integer pageSize = request.pageSize == null || request.pageSize <= 0 ? 25 : Math.min(request.pageSize, 500);
        Integer pageNumber = request.pageNumber == null || request.pageNumber <= 0 ? 1 : request.pageNumber;
        Boolean showInactive = request.includeInactive == true
            || (request.activeFilter != null && request.activeFilter.toLowerCase() == 'all');
        String activeOnly = request.activeFilter == null ? null : request.activeFilter.trim().toLowerCase();
        if (String.isBlank(activeOnly) || activeOnly == 'all') {
            activeOnly = null;
        }

        // Text search runs in memory so line and territory names match, and dropdowns stay complete.
        List<String> searchTokens = searchTokens(request.searchTerm);
        String titleFilter = filterOrNull(request.titleFilter);
        String lineFilter = filterOrNull(request.lineFilter);
        String territoryFilter = String.isBlank(request.territoryFilter) ? null : request.territoryFilter.trim();
        String buFilter = filterOrNull(request.businessUnitFilter);

        // Commercial field users: email usernames, pharma demo, or any seat in the organogram.
        Set<Id> seatedUserIds = new Set<Id>();
        for (UserTerritory2Association link : [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE IsActive = TRUE AND Territory2.External_ID__c LIKE 'TERR_%'
            WITH SYSTEM_MODE
        ]) {
            seatedUserIds.add(link.UserId);
        }
        // Managers (no Manage Users / View All Data) only see the people seated in their own team.
        Set<Id> scopedTerritoryIds = TerritoryConsoleScope.getScopedTerritoryIds();
        Set<Id> scopedUserIds = TerritoryConsoleScope.getScopedUserIds();
        Boolean scoped = scopedUserIds != null;
        if (scoped) {
            seatedUserIds = scopedUserIds;
        }

        Map<String, Schema.SObjectField> userFields = User.SObjectType.getDescribe().fields.getMap();
        List<String> optionalUserDates = new List<String>();
        for (String api : new List<String>{ 'Hire_Date__c', 'Resignation_Date__c', 'Last_Work_Day__c' }) {
            if (userFields.containsKey(api)) {
                optionalUserDates.add(api);
            }
        }
        String soql =
            'SELECT Id, Name, FirstName, LastName, Email, Username, Title, Department, Division,'
            + ' IsActive, Profile.Name'
            + (optionalUserDates.isEmpty() ? '' : ', ' + String.join(optionalUserDates, ', '))
            + (scoped
                ? ' FROM User WHERE (Id IN :seatedUserIds)'
                : ' FROM User WHERE (Id IN :seatedUserIds'
                    + ' OR Username LIKE \'%pharma%\''
                    + ' OR Email LIKE \'%@zeta-pharma.com\''
                    + ' OR Email LIKE \'%@cloudastick.%\''
                    + ' OR Title LIKE \'%Field Intelligence%\''
                    + ' OR Title LIKE \'%Sales Force Excellence%\''
                    + ' OR Title LIKE \'%SFE%\')');
        if (!showInactive) {
            soql += ' AND IsActive = TRUE';
        }
        // Title, line, territory, business unit, status, and text search apply after seat labels load
        // so the dropdowns stay complete and BU matches the organogram, not User.Department ("Sales").
        soql += ' WITH SYSTEM_MODE ORDER BY IsActive DESC, Name ASC LIMIT 5000';

        List<User> matched = Database.query(soql);
        List<Id> matchedIds = new List<Id>();
        for (User row : matched) {
            matchedIds.add(row.Id);
        }
        Map<Id, UserSeatLabelService.SeatLabel> seatsByUser = new Map<Id, UserSeatLabelService.SeatLabel>();
        for (UserSeatLabelService.SeatLabel seat : UserSeatLabelService.getSeatLabels(matchedIds)) {
            seatsByUser.put(seat.userId, seat);
        }

        List<UserOption> filtered = new List<UserOption>();
        Integer activeCount = 0;
        Integer inactiveCount = 0;
        Set<String> titleOptions = new Set<String>();
        Set<String> lineOptions = new Set<String>();
        Set<String> buOptions = new Set<String>();

        String territoryNeedle = String.isBlank(territoryFilter) ? null : territoryFilter.toLowerCase();

        for (User userRecord : matched) {
            UserOption option = toUserOption(userRecord);
            UserSeatLabelService.SeatLabel seat = seatsByUser.get(userRecord.Id);
            option.lineName = seat != null ? seat.lineName : '';
            option.territoryName = seat != null ? seat.territoryName : '';
            if (seat != null && String.isNotBlank(seat.businessUnitName)) {
                // Prefer every organogram BU over HR Department ("Sales").
                option.businessUnit = seat.businessUnitName;
            }

            if (String.isNotBlank(option.title)) {
                titleOptions.add(option.title.trim());
            }
            for (String buName : splitCsv(option.businessUnit)) {
                if (String.isNotBlank(buName) && !buName.equalsIgnoreCase('Sales')) {
                    buOptions.add(buName);
                }
            }
            for (String lineName : splitCsv(option.lineName)) {
                lineOptions.add(lineName);
            }

            if (activeOnly == 'active' && option.isActive != true) {
                continue;
            }
            if (activeOnly == 'inactive' && option.isActive == true) {
                continue;
            }
            if (titleFilter != null && !equalsIgnore(option.title, titleFilter)) {
                continue;
            }
            if (lineFilter != null && !listContainsIgnore(splitCsv(option.lineName), lineFilter)) {
                continue;
            }
            if (buFilter != null && !listContainsIgnore(splitCsv(option.businessUnit), buFilter)) {
                continue;
            }
            if (territoryNeedle != null) {
                String hay = option.territoryName == null ? '' : option.territoryName.toLowerCase();
                if (!hay.contains(territoryNeedle)) {
                    continue;
                }
            }
            if (!matchesSearch(option, userRecord, searchTokens)) {
                continue;
            }

            if (option.isActive == true) {
                activeCount++;
            } else {
                inactiveCount++;
            }
            filtered.add(option);
        }

        // Also expose every organogram line name so filters are complete even when page is empty.
        // A manager only gets the lines and BUs of their own team.
        Set<Id> optionScope = scopedTerritoryIds == null ? null : TerritoryConsoleScope.withAncestors(scopedTerritoryIds);
        for (Territory2 line : [
            SELECT Id, Name
            FROM Territory2
            WHERE Territory_Type__c = 'Line' AND External_ID__c LIKE 'TERR_%'
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ]) {
            if (optionScope == null || optionScope.contains(line.Id)) {
                lineOptions.add(line.Name);
            }
        }
        for (Territory2 bu : [
            SELECT Id, Name, External_ID__c
            FROM Territory2
            WHERE Territory_Type__c = 'Business_Unit' AND External_ID__c LIKE 'TERR_%'
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ]) {
            if (bu.External_ID__c != null && bu.External_ID__c.contains('TRAINING')) {
                continue;
            }
            if (optionScope == null || optionScope.contains(bu.Id)) {
                buOptions.add(bu.Name);
            }
        }

        Integer total = filtered.size();
        Integer maxPage = total == 0 ? 1 : (total + pageSize - 1) / pageSize;
        if (pageNumber > maxPage) {
            pageNumber = maxPage;
        }
        Integer startIdx = (pageNumber - 1) * pageSize;
        List<UserOption> page = new List<UserOption>();
        for (Integer i = startIdx; i < total && page.size() < pageSize; i++) {
            page.add(filtered[i]);
        }

        ManagedUsersPage result = new ManagedUsersPage();
        result.users = page;
        result.totalCount = total;
        result.activeCount = activeCount;
        result.inactiveCount = inactiveCount;
        result.pageSize = pageSize;
        result.pageNumber = pageNumber;
        result.hasMore = startIdx + page.size() < total;
        result.appliedSearchTerm = request.searchTerm == null ? '' : request.searchTerm.trim();
        result.titleOptions = sortedStrings(titleOptions);
        result.lineOptions = sortedStrings(lineOptions);
        result.businessUnitOptions = sortedStrings(buOptions);
        result.canManageUsers = callerCanManageUsers();
        result.teamScoped = scoped;
        return result;
    }

    private static String blankToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String filterOrNull(String value) {
        if (String.isBlank(value) || value.trim().equalsIgnoreCase('All')) {
            return null;
        }
        return value.trim();
    }

    private static Boolean equalsIgnore(String left, String right) {
        return left != null && right != null && left.trim().equalsIgnoreCase(right.trim());
    }

    private static Boolean listContainsIgnore(List<String> values, String needle) {
        if (values == null || String.isBlank(needle)) {
            return false;
        }
        for (String value : values) {
            if (equalsIgnore(value, needle)) {
                return true;
            }
        }
        return false;
    }

    private static List<String> searchTokens(String raw) {
        List<String> tokens = new List<String>();
        if (String.isBlank(raw)) {
            return tokens;
        }
        for (String part : raw.trim().toLowerCase().split('\\s+')) {
            if (String.isNotBlank(part)) {
                tokens.add(part);
            }
        }
        return tokens;
    }

    private static Boolean matchesSearch(UserOption option, User userRecord, List<String> tokens) {
        if (tokens == null || tokens.isEmpty()) {
            return true;
        }
        String hay = joinLower(
            new List<String>{
                option.name,
                option.firstName,
                option.lastName,
                option.username,
                option.email,
                option.title,
                option.businessUnit,
                option.profileName,
                option.lineName,
                option.territoryName,
                userRecord == null ? null : userRecord.Department,
                userRecord == null ? null : userRecord.Division
            }
        );
        for (String token : tokens) {
            if (!hay.contains(token)) {
                return false;
            }
        }
        return true;
    }

    private static String joinLower(List<String> parts) {
        List<String> kept = new List<String>();
        for (String part : parts) {
            if (String.isNotBlank(part)) {
                kept.add(part);
            }
        }
        return String.join(kept, ' ').toLowerCase();
    }

    private static List<String> splitCsv(String value) {
        List<String> parts = new List<String>();
        if (String.isBlank(value)) {
            return parts;
        }
        for (String part : value.split(',')) {
            String trimmed = part == null ? null : part.trim();
            if (String.isNotBlank(trimmed)) {
                parts.add(trimmed);
            }
        }
        return parts;
    }

    private static List<String> sortedStrings(Set<String> values) {
        List<String> listValues = new List<String>(values);
        listValues.sort();
        return listValues;
    }

    /**
     * Changing another user's email, username, password or active status needs the standard
     * "Manage Users" permission (from the profile or a permission set). Without it the caller
     * could take over an account by changing its email and then resetting the password.
     */
    @TestVisible
    private static Boolean callerCanManageUsers() {
        return ![
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.PermissionsManageUsers = true
            LIMIT 1
        ].isEmpty();
    }

    @TestVisible
    private static void requireManageUsers() {
        List<PermissionSetAssignment> grants = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.PermissionsManageUsers = true
            LIMIT 1
        ];
        if (grants.isEmpty()) {
            throw new AuraHandledException('You need the Manage Users permission to change user logins.');
        }
    }

    @AuraEnabled
    public static void updateUserProfile(UserProfileForm form) {
        requireManageUsers();
        if (form == null || form.userId == null) {
            throw new AuraHandledException('User is required.');
        }
        if (String.isBlank(form.lastName)) {
            throw new AuraHandledException('Last name is required.');
        }
        if (String.isBlank(form.email)) {
            throw new AuraHandledException('Email is required.');
        }
        if (String.isBlank(form.username)) {
            throw new AuraHandledException('Username is required.');
        }

        User target = [
            SELECT Id, FirstName, LastName, Email, Username, Title, Department, Profile.Name
            FROM User
            WHERE Id = :form.userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        target.FirstName = String.isBlank(form.firstName) ? null : form.firstName.trim();
        target.LastName = form.lastName.trim();
        target.Email = form.email.trim();
        target.Username = form.username.trim();
        target.Title = String.isBlank(form.title) ? null : form.title.trim();
        target.Department = String.isBlank(form.department) ? null : form.department.trim();

        try {
            update as system target;
        } catch (DmlException ex) {
            throw new AuraHandledException(ex.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static PasswordSetResult setOneTimePasswords(List<Id> userIds, String password) {
        requireManageUsers();
        if (userIds == null || userIds.isEmpty()) {
            throw new AuraHandledException('Select at least one user.');
        }

        String resolvedPassword = String.isBlank(password) ? generateOneTimePassword() : password.trim();
        if (resolvedPassword.length() < 8) {
            throw new AuraHandledException('Password must be at least 8 characters.');
        }

        assertPasswordMeetsPolicy(resolvedPassword);

        PasswordSetResult result = new PasswordSetResult();
        result.successCount = 0;
        result.failureCount = 0;
        result.emailSentCount = 0;
        result.emailFailureCount = 0;
        result.passwordUsed = resolvedPassword;
        result.messages = new List<String>();

        Set<Id> uniqueIds = new Set<Id>(userIds);
        Map<Id, User> usersById = new Map<Id, User>([
            SELECT Id, Name, Username, Email, IsActive
            FROM User
            WHERE Id IN :uniqueIds
            WITH SYSTEM_MODE
        ]);

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        List<String> mailedNames = new List<String>();
        List<String> mailedAddresses = new List<String>();
        List<Boolean> mailedReactivated = new List<Boolean>();

        for (Id userId : uniqueIds) {
            User target = usersById.get(userId);
            if (target == null) {
                result.failureCount++;
                result.messages.add('User not found: ' + String.valueOf(userId));
                continue;
            }
            // setPassword on an inactive user throws an uncatchable INACTIVE_OWNER_OR_USER.
            // Activate first so the password can be set and the person can sign in.
            Boolean reactivated = false;
            if (target.IsActive != true) {
                try {
                    target.IsActive = true;
                    update as system target;
                    reactivated = true;
                } catch (Exception ex) {
                    result.failureCount++;
                    result.messages.add(target.Name + ': ' + exceptionMessage(ex));
                    continue;
                }
            }
            try {
                System.setPassword(userId, resolvedPassword);
                result.successCount++;
                String toAddress = loginEmailAddress(target);
                if (String.isBlank(toAddress)) {
                    result.emailFailureCount++;
                    result.messages.add(target.Name + ': password set, but this user has no email address.');
                    continue;
                }
                mails.add(loginMail(target, resolvedPassword, toAddress));
                mailedNames.add(target.Name);
                mailedAddresses.add(toAddress);
                mailedReactivated.add(reactivated);
            } catch (Exception ex) {
                result.failureCount++;
                result.messages.add(target.Name + ': ' + exceptionMessage(ex));
            }
        }
        deliverLoginEmails(mails, mailedNames, mailedAddresses, mailedReactivated, result);
        return result;
    }

    @AuraEnabled
    public static UserStatusResult setUsersActive(List<Id> userIds, Boolean isActive) {
        requireManageUsers();
        if (userIds == null || userIds.isEmpty()) {
            throw new AuraHandledException('Select at least one user.');
        }
        if (isActive == null) {
            throw new AuraHandledException('Active flag is required.');
        }

        UserStatusResult result = new UserStatusResult();
        result.successCount = 0;
        result.skippedCount = 0;
        result.failureCount = 0;
        result.messages = new List<String>();

        Set<Id> uniqueIds = new Set<Id>(userIds);
        List<User> targets = [
            SELECT Id, Name, IsActive, Profile.Name
            FROM User
            WHERE Id IN :uniqueIds
            WITH SYSTEM_MODE
        ];

        List<User> toUpdate = new List<User>();
        for (User target : targets) {
            if (!isActive && isSystemAdministrator(target.Profile?.Name)) {
                result.skippedCount++;
                result.messages.add(target.Name + ': System Administrators cannot be deactivated here.');
                continue;
            }
            if (!isActive && target.Id == UserInfo.getUserId()) {
                result.skippedCount++;
                result.messages.add(target.Name + ': you cannot deactivate your own user.');
                continue;
            }
            if (target.IsActive == isActive) {
                result.skippedCount++;
                result.messages.add(
                    target.Name + ': already ' + (isActive ? 'active' : 'inactive') + '.'
                );
                continue;
            }
            target.IsActive = isActive;
            toUpdate.add(target);
        }

        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] saveResults = Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult saveResult = saveResults[i];
                User target = toUpdate[i];
                if (saveResult.isSuccess()) {
                    result.successCount++;
                    result.messages.add(
                        target.Name + ': ' + (isActive ? 'activated' : 'deactivated') + '.'
                    );
                } else {
                    result.failureCount++;
                    result.messages.add(target.Name + ': ' + saveResult.getErrors()[0].getMessage());
                }
            }
        }
        return result;
    }

    private static UserOption toUserOption(User userRecord) {
        UserOption option = new UserOption();
        option.id = userRecord.Id;
        option.name = userRecord.Name;
        option.firstName = userRecord.FirstName;
        option.lastName = userRecord.LastName;
        option.email = userRecord.Email;
        option.username = userRecord.Username;
        option.title = resolveTitle(userRecord);
        option.businessUnit = resolveBusinessUnit(userRecord);
        option.profileName = userRecord.Profile != null ? userRecord.Profile.Name : null;
        option.isActive = userRecord.IsActive;
        option.isSystemAdmin = isSystemAdministrator(option.profileName);
        option.canDeactivate = userRecord.IsActive == true
            && option.isSystemAdmin != true
            && userRecord.Id != UserInfo.getUserId();
        option.label = buildUserDisplayLabel(userRecord, option.title, option.businessUnit);
        // HR date fields are org-optional; isSet/get throw when the field is not in the schema.
        Map<String, Schema.SObjectField> userFields = User.SObjectType.getDescribe().fields.getMap();
        if (userFields.containsKey('Hire_Date__c') && userRecord.isSet('Hire_Date__c')) {
            option.hireDate = (Date) userRecord.get('Hire_Date__c');
        }
        if (userFields.containsKey('Resignation_Date__c') && userRecord.isSet('Resignation_Date__c')) {
            option.resignationDate = (Date) userRecord.get('Resignation_Date__c');
        }
        if (userFields.containsKey('Last_Work_Day__c') && userRecord.isSet('Last_Work_Day__c')) {
            option.lastWorkDay = (Date) userRecord.get('Last_Work_Day__c');
        }
        return option;
    }

    private static Boolean isSystemAdministrator(String profileName) {
        return String.isNotBlank(profileName) && profileName == 'System Administrator';
    }

    private static void assertPasswordMeetsPolicy(String password) {
        Boolean hasLetter = password != null && Pattern.matches('(?s).*[A-Za-z].*', password);
        Boolean hasDigit = password != null && Pattern.matches('(?s).*\\d.*', password);
        if (password == null || password.length() < 8 || !hasLetter || !hasDigit) {
            throw new AuraHandledException(
                'Password must be at least 8 characters and include letters and numbers.'
            );
        }
    }

    private static String loginEmailAddress(User target) {
        if (String.isNotBlank(target.Email)) {
            return target.Email.trim();
        }
        if (String.isNotBlank(target.Username) && target.Username.contains('@')) {
            return target.Username.trim();
        }
        return null;
    }

    @TestVisible
    private static Messaging.SingleEmailMessage loginMail(User target, String password, String toAddress) {
        String username = target.Username == null ? '' : target.Username;
        String textBody =
            'Here is your username:\n' + username + '\n\n' +
            'Here is your password:\n' + password + '\n\n' +
            'Access the app from:\n' +
            'salesforceoffline.com\n';
        if (target.IsActive != true) {
            textBody += '\nThis account is inactive. An administrator must activate it before sign-in works.\n';
        }
        String htmlBody =
            '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#181818;line-height:1.5">'
            + '<p>Here is your username:</p>'
            + '<p style="font-family:Consolas,Menlo,monospace;font-size:16px;margin:0 0 16px">'
            + username.escapeHtml4() + '</p>'
            + '<p>Here is your password:</p>'
            + '<p style="font-family:Consolas,Menlo,monospace;font-size:16px;margin:0 0 16px">'
            + password.escapeHtml4() + '</p>'
            + '<p>Access the app from:</p>'
            + '<p style="margin:0"><a href="https://salesforceoffline.com">salesforceoffline.com</a></p>'
            + (target.IsActive == true
                ? ''
                : '<p>This account is inactive. An administrator must activate it before sign-in works.</p>')
            + '</div>';
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toAddress });
        mail.setSubject('Your Zeta Pharma login');
        mail.setPlainTextBody(textBody);
        mail.setHtmlBody(htmlBody);
        mail.setSaveAsActivity(false);
        mail.setUseSignature(false);
        mail.setSenderDisplayName('Zeta Pharma');
        return mail;
    }

    private static void deliverLoginEmails(
        List<Messaging.SingleEmailMessage> mails,
        List<String> mailedNames,
        List<String> mailedAddresses,
        List<Boolean> mailedReactivated,
        PasswordSetResult result
    ) {
        if (mails.isEmpty()) {
            return;
        }
        try {
            Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(mails, false);
            for (Integer i = 0; i < sendResults.size(); i++) {
                if (sendResults[i].isSuccess()) {
                    result.emailSentCount++;
                    String note = mailedReactivated[i] == true
                        ? mailedNames[i] + ': activated, password set and emailed to ' + mailedAddresses[i] + '.'
                        : mailedNames[i] + ': password set and emailed to ' + mailedAddresses[i] + '.';
                    result.messages.add(note);
                } else {
                    result.emailFailureCount++;
                    String reason = 'email was not accepted';
                    if (!sendResults[i].getErrors().isEmpty()) {
                        reason = sendResults[i].getErrors()[0].getMessage();
                    }
                    String prefix = mailedReactivated[i] == true
                        ? 'activated, password set'
                        : 'password set';
                    result.messages.add(mailedNames[i] + ': ' + prefix + ', but the email failed. ' + reason);
                }
            }
        } catch (Exception ex) {
            result.emailFailureCount += mails.size();
            result.messages.add('Password was set, but the email failed. ' + exceptionMessage(ex));
        }
    }

    private static String exceptionMessage(Exception ex) {
        if (ex instanceof DmlException) {
            DmlException dmlEx = (DmlException) ex;
            if (dmlEx.getNumDml() > 0 && String.isNotBlank(dmlEx.getDmlMessage(0))) {
                return dmlEx.getDmlMessage(0);
            }
        }
        return ex.getMessage();
    }

    private static String generateOneTimePassword() {
        String letters = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
        String digits = '23456789';
        String alphabet = letters + digits;
        String randomPart = '';
        while (randomPart.length() < 9) {
            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), alphabet.length());
            randomPart += alphabet.substring(idx, idx + 1);
        }
        Integer digitIdx = Math.mod(Math.abs(Crypto.getRandomInteger()), digits.length());
        randomPart += digits.substring(digitIdx, digitIdx + 1);
        return 'Zeta!' + randomPart;
    }

    private static String resolveTitle(User userRecord) {
        if (String.isNotBlank(userRecord.Title)) {
            return userRecord.Title;
        }
        String username = userRecord.Username == null ? '' : userRecord.Username.toLowerCase();
        if (username.endsWith('.bum@pharma.demo') || username.endsWith('.bum@pharma.eg')) {
            return 'Business Unit Manager';
        }
        if (username.endsWith('.nsm@pharma.demo') || username.endsWith('.nsm@pharma.eg')) {
            return 'National Sales Manager';
        }
        if (username.endsWith('.am@pharma.demo') || username.endsWith('.am@pharma.eg')) {
            return 'Area Manager';
        }
        if (username.endsWith('.dm@pharma.demo') || username.endsWith('.dm@pharma.eg')) {
            return 'District Manager';
        }
        if (username.endsWith('.brand@pharma.demo') || username.endsWith('.brand@pharma.eg')) {
            return 'Brand Manager';
        }
        if (username.endsWith('.trainer@pharma.demo') || username.endsWith('.trainer@pharma.eg')) {
            return 'Trainer';
        }
        if (username.endsWith('.mr@pharma.demo') || username.endsWith('.mr@pharma.eg')) {
            return 'Medical Rep';
        }
        return null;
    }

    private static String resolveBusinessUnit(User userRecord) {
        if (String.isNotBlank(userRecord.Department)) {
            return userRecord.Department;
        }
        if (String.isNotBlank(userRecord.Division)) {
            return userRecord.Division;
        }
        String username = userRecord.Username == null ? '' : userRecord.Username.toLowerCase();
        if (!username.endsWith('@pharma.demo')) {
            return null;
        }
        String localPart = username.substringBefore('@');
        if (!localPart.contains('.')) {
            return null;
        }
        return localPart.substringBefore('.').toUpperCase();
    }

    private static String buildUserDisplayLabel(User userRecord, String title, String businessUnit) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(userRecord.Name)) {
            parts.add(userRecord.Name);
        }
        if (String.isNotBlank(title)) {
            parts.add(title);
        }
        if (String.isNotBlank(businessUnit)) {
            parts.add(businessUnit);
        }
        if (String.isNotBlank(userRecord.Username)) {
            parts.add(userRecord.Username);
        }
        return String.join(parts, ' · ');
    }

    @AuraEnabled(cacheable=true)
    public static String resolveAssignmentRole(Id userId) {
        if (userId == null) {
            return 'Medical Rep';
        }
        List<User> users = [
            SELECT Username, Title
            FROM User
            WHERE Id = :userId
            WITH USER_MODE
            LIMIT 1
        ];
        if (users.isEmpty()) {
            return 'Medical Rep';
        }
        return mapAssignmentRole(users[0].Title, users[0].Username);
    }

    @TestVisible
    static String mapAssignmentRole(String title, String username) {
        String normalizedTitle = title == null ? '' : title.trim();
        if (String.isNotBlank(normalizedTitle)) {
            String titleLower = normalizedTitle.toLowerCase();
            if (titleLower == 'business unit manager' || titleLower == 'bum') {
                return 'Business Unit Manager';
            }
            if (titleLower == 'national sales manager' || titleLower == 'nsm') {
                return 'National Sales Manager';
            }
            if (titleLower == 'area manager' || titleLower == 'am' || titleLower == 'brand manager' || titleLower == 'brand') {
                return titleLower.contains('brand') ? 'Brand Manager' : 'Area Manager';
            }
            if (titleLower == 'district manager' || titleLower == 'dm') {
                return 'District Manager';
            }
            if (titleLower == 'trainer' || titleLower == 'field trainer') {
                return 'Trainer';
            }
            if (titleLower == 'sales force excellence' || titleLower == 'sfe') {
                return 'SFE';
            }
            if (titleLower == 'medical rep' || titleLower == 'medical representative' || titleLower == 'mr') {
                return 'Medical Rep';
            }
            return normalizedTitle;
        }
        String userNameLower = username == null ? '' : username.toLowerCase();
        if (userNameLower == 'admin@pharma.eg') {
            return 'SFE';
        }
        if (userNameLower.endsWith('.bum@pharma.demo') || userNameLower.endsWith('.bum@pharma.eg')) {
            return 'Business Unit Manager';
        }
        if (userNameLower.endsWith('.nsm@pharma.demo') || userNameLower.endsWith('.nsm@pharma.eg')) {
            return 'National Sales Manager';
        }
        if (userNameLower.endsWith('.am@pharma.demo') || userNameLower.endsWith('.am@pharma.eg')) {
            return 'Area Manager';
        }
        if (userNameLower.endsWith('.brand@pharma.demo') || userNameLower.endsWith('.brand@pharma.eg')) {
            return 'Brand Manager';
        }
        if (userNameLower.endsWith('.trainer@pharma.demo') || userNameLower.endsWith('.trainer@pharma.eg')) {
            return 'Trainer';
        }
        if (userNameLower.endsWith('.dm@pharma.demo') || userNameLower.endsWith('.dm@pharma.eg')) {
            return 'District Manager';
        }
        if (userNameLower.endsWith('.mr@pharma.demo') || userNameLower.endsWith('.mr@pharma.eg')) {
            return 'Medical Rep';
        }
        return 'Medical Rep';
    }

    /**
     * Assigns a user to a territory. Vacating/reassigning a Position never deletes
     * Brick_Territory_Alignment__c or Promo_Grid_* rows — those stay on Territory2.
     */
    @AuraEnabled
    public static void assignUserToTerritory(Id territoryId, Id userId, String role) {
        if (territoryId == null || userId == null) {
            throw new AuraHandledException('Territory and user are required.');
        }
        TerritoryConsoleScope.requireInScope(territoryId);

        Boolean isLeaf = isLeafTerritory(territoryId);
        if (isLeaf) {
            delete as user [
                SELECT Id
                FROM UserTerritory2Association
                WHERE Territory2Id = :territoryId
                WITH USER_MODE
            ];
        }

        insert as user new UserTerritory2Association(
            UserId = userId,
            Territory2Id = territoryId,
            RoleInTerritory2 = String.isBlank(role) ? 'Medical Rep' : role
        );
    }

    /**
     * Clears user-territory associations only. Brick alignments and promo-grid
     * targets remain on the vacant Position so it can still hold targets.
     */
    @AuraEnabled
    public static void clearTerritoryAssignments(Id territoryId) {
        if (territoryId == null) {
            throw new AuraHandledException('Territory Id is required.');
        }
        TerritoryConsoleScope.requireInScope(territoryId);
        delete as user [
            SELECT Id
            FROM UserTerritory2Association
            WHERE Territory2Id = :territoryId
            WITH USER_MODE
        ];
    }

    private static Map<Id, List<TerritoryAssignment>> loadAssignments(Set<Id> territoryIds) {
        Map<Id, List<TerritoryAssignment>> assignmentsByTerritory = new Map<Id, List<TerritoryAssignment>>();
        for (UserTerritory2Association association : [
            SELECT Id, Territory2Id, UserId, RoleInTerritory2, User.Name, User.Title, User.Username, User.EmployeeNumber
            FROM UserTerritory2Association
            WHERE Territory2Id IN :territoryIds
            WITH SYSTEM_MODE
            ORDER BY User.Name ASC
        ]) {
            if (!assignmentsByTerritory.containsKey(association.Territory2Id)) {
                assignmentsByTerritory.put(association.Territory2Id, new List<TerritoryAssignment>());
            }
            TerritoryAssignment assignment = new TerritoryAssignment();
            assignment.associationId = association.Id;
            assignment.userId = association.UserId;
            assignment.userName = association.User?.Name;
            assignment.role = association.RoleInTerritory2;
            assignment.userTitle = association.User?.Title;
            assignment.userLogin = association.User?.Username;
            assignment.employeeNumber = association.User?.EmployeeNumber;
            assignmentsByTerritory.get(association.Territory2Id).add(assignment);
        }
        return assignmentsByTerritory;
    }

    private static TerritoryTreeNode buildNode(Territory2 territory, List<TerritoryAssignment> assignments) {
        TerritoryTreeNode node = new TerritoryTreeNode();
        node.id = territory.Id;
        node.name = territory.Name;
        node.externalId = territory.External_ID__c;
        String territoryType = null;
        if (Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')) {
            territoryType = (String) territory.get('Territory_Type__c');
        }
        node.level = resolveNodeLevel(territory.External_ID__c, territoryType);
        node.parentId = territory.ParentTerritory2Id;
        node.assignments = assignments == null ? new List<TerritoryAssignment>() : assignments;
        node.isVacant = node.assignments.isEmpty();
        node.children = new List<TerritoryTreeNode>();
        node.hasChildren = false;
        node.canEdit = territory.External_ID__c != 'TERR_HEAD_OFFICE';
        node.canDelete = node.canEdit;
        node.canAddChild = node.level != 'MR' && node.level != 'Position' && node.level != 'Marketing Seat';
        return node;
    }

    private static String resolveNodeLevel(String externalId, String territoryType) {
        if (String.isNotBlank(territoryType)) {
            if (territoryType == 'Head_Office') {
                return 'Head Office';
            }
            if (territoryType == 'Business_Unit') {
                return 'Business Unit';
            }
            if (territoryType == 'Line') {
                return 'Line';
            }
            if (territoryType == 'District') {
                return 'District';
            }
            if (territoryType == 'Position') {
                return 'Position';
            }
        }
        // Brand Manager / Group Brand Lead boxes (Territory_Type__c = Other) used to fall through to
        // "Line", so they looked like product lines in the tree, filters and download.
        if (String.isNotBlank(externalId) && externalId.startsWith('TERR_BM_')) {
            return 'Marketing Seat';
        }
        if (String.isBlank(externalId)) {
            return 'Unknown';
        }
        if (externalId == 'TERR_HEAD_OFFICE') {
            return 'Head Office';
        }
        if (externalId.startsWith('TERR_BU_')) {
            return 'Business Unit';
        }
        if (externalId.startsWith('TERR_POS_') || externalId.contains('_MR_')) {
            return externalId.contains('_MR_') ? 'MR' : 'Position';
        }
        if (externalId.startsWith('TERR_DM_') || externalId.contains('_DM_')) {
            return 'District';
        }
        if (externalId.startsWith('TERR_LINE_')) {
            return 'Line';
        }
        return 'Line';
    }

    private static Boolean isLeafTerritory(Id territoryId) {
        Integer childCount = [
            SELECT COUNT()
            FROM Territory2
            WHERE ParentTerritory2Id = :territoryId
            WITH USER_MODE
        ];
        return childCount == 0;
    }

    private static void sortChildrenRecursively(List<TerritoryTreeNode> nodes) {
        if (nodes == null) {
            return;
        }
        nodes.sort(new TerritoryNodeNameComparator());
        for (TerritoryTreeNode node : nodes) {
            if (node.children != null && !node.children.isEmpty()) {
                sortChildrenRecursively(node.children);
            }
        }
    }

    private class TerritoryNodeNameComparator implements Comparator<TerritoryTreeNode> {
        public Integer compare(TerritoryTreeNode a, TerritoryTreeNode b) {
            String left = a != null && a.name != null ? a.name : '';
            String right = b != null && b.name != null ? b.name : '';
            return left.compareTo(right);
        }
    }
}