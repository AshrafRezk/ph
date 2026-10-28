public with sharing class ProductCatalogAdminController {

    public class ProductTreeNode {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String nodeType;
        @AuraEnabled public Id productId;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productType;
        @AuraEnabled public String externalId;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String salesLine;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public List<ProductTreeNode> children;
    }

    public class TerritoryTreeNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id parentId;
        @AuraEnabled public Boolean hasChildren;
        @AuraEnabled public Boolean aligned;
        @AuraEnabled public List<TerritoryTreeNode> children;
    }

    // Inactive products are included (flagged isActive = false) so admins can still find and fix them.
    @AuraEnabled(cacheable=true)
    public static List<ProductTreeNode> getProductCatalogTree() {
        List<Product2> products = [
            SELECT
                Id,
                Name,
                Primary_Brand__c,
                Therapy_Area__c,
                ProductCode,
                External_ID__c,
                Product_Image_URL__c,
                Product_Type__c,
                Parent_Product__c,
                Sales_Line__c,
                IsActive
            FROM Product2
            WITH USER_MODE
            ORDER BY Name ASC
        ];
        if (products.isEmpty()) {
            return new List<ProductTreeNode>();
        }

        Map<Id, ProductTreeNode> nodesById = new Map<Id, ProductTreeNode>();
        Map<Id, List<ProductTreeNode>> childrenByParentId = new Map<Id, List<ProductTreeNode>>();

        for (Product2 product : products) {
            ProductTreeNode node = toProductNode(product);
            nodesById.put(product.Id, node);
            Id parentId = product.Parent_Product__c;
            if (parentId != null) {
                if (!childrenByParentId.containsKey(parentId)) {
                    childrenByParentId.put(parentId, new List<ProductTreeNode>());
                }
                childrenByParentId.get(parentId).add(node);
            }
        }

        for (Id parentId : childrenByParentId.keySet()) {
            if (nodesById.containsKey(parentId)) {
                List<ProductTreeNode> children = childrenByParentId.get(parentId);
                children.sort(new ProductNodeLabelComparator());
                nodesById.get(parentId).children = children;
            }
        }

        List<ProductTreeNode> roots = new List<ProductTreeNode>();
        for (Product2 product : products) {
            Boolean isRootType =
                product.Product_Type__c == 'Brand'
                || (product.Parent_Product__c == null
                    && product.Product_Type__c != 'Sample'
                    && product.Product_Type__c != 'Brand Reminder');
            if (!isRootType) {
                continue;
            }
            if (product.Parent_Product__c != null && nodesById.containsKey(product.Parent_Product__c)) {
                continue;
            }
            ProductTreeNode rootNode = nodesById.get(product.Id);
            if (rootNode.children == null) {
                rootNode.children = new List<ProductTreeNode>();
            }
            roots.add(rootNode);
        }

        if (roots.isEmpty()) {
            for (Product2 product : products) {
                if (product.Parent_Product__c == null) {
                    ProductTreeNode orphan = nodesById.get(product.Id);
                    if (orphan != null) {
                        if (orphan.children == null) {
                            orphan.children = new List<ProductTreeNode>();
                        }
                        roots.add(orphan);
                    }
                }
            }
        }

        roots.sort(new ProductNodeLabelComparator());
        return roots;
    }

    private static ProductTreeNode toProductNode(Product2 product) {
        ProductTreeNode node = new ProductTreeNode();
        node.key = String.valueOf(product.Id);
        node.label = product.Name;
        node.productId = product.Id;
        node.therapyArea = product.Therapy_Area__c;
        node.productCode = product.ProductCode;
        node.externalId = product.External_ID__c;
        node.productType = product.Product_Type__c;
        node.imageUrl = product.Product_Image_URL__c;
        node.salesLine = product.Sales_Line__c;
        node.isActive = product.IsActive == true;
        node.nodeType = resolveNodeType(product.Product_Type__c);
        node.children = new List<ProductTreeNode>();
        return node;
    }

    private static String resolveNodeType(String productType) {
        if (productType == 'Brand') {
            return 'brand';
        }
        if (productType == 'Detail') {
            return 'detail';
        }
        if (productType == 'Sample') {
            return 'sample';
        }
        if (productType == 'Brand Reminder') {
            return 'brand_reminder';
        }
        return 'product';
    }

    // Not cacheable: the screen reloads this right after saving and must see the saved state.
    @AuraEnabled
    public static List<TerritoryTreeNode> getTerritoryTreeForProduct(Id productId) {
        Set<String> alignedTerritoryIds = loadAlignedTerritoryIds(productId);
        return buildTerritoryTree(alignedTerritoryIds);
    }

    @AuraEnabled
    public static Integer saveProductTerritoryAlignments(Id productId, List<Id> territoryIds) {
        if (productId == null) {
            throw new AuraHandledException('Select a product before saving territory alignment.');
        }

        Set<Id> requestedTerritoryIds = territoryIds == null
            ? new Set<Id>()
            : new Set<Id>(territoryIds);

        List<Product_Territory_Alignment__c> existing = [
            SELECT Id, Territory2_Id__c, Is_Active__c
            FROM Product_Territory_Alignment__c
            WHERE Product2_Id__c = :String.valueOf(productId)
            WITH USER_MODE
        ];

        List<Product_Territory_Alignment__c> toDelete = new List<Product_Territory_Alignment__c>();
        List<Product_Territory_Alignment__c> toReactivate = new List<Product_Territory_Alignment__c>();
        Set<Id> existingTerritoryIds = new Set<Id>();
        for (Product_Territory_Alignment__c alignment : existing) {
            Id territoryId = parseTerritoryId(alignment.Territory2_Id__c);
            if (territoryId == null) {
                toDelete.add(alignment);
                continue;
            }
            existingTerritoryIds.add(territoryId);
            if (!requestedTerritoryIds.contains(territoryId)) {
                toDelete.add(alignment);
            } else if (alignment.Is_Active__c != true) {
                // Ticking a territory again brings back its inactive alignment instead of silently skipping it.
                toReactivate.add(new Product_Territory_Alignment__c(
                    Id = alignment.Id,
                    Is_Active__c = true,
                    Effective_Start_Date__c = Date.today()
                ));
            }
        }
        if (!toDelete.isEmpty()) {
            delete as user toDelete;
        }
        if (!toReactivate.isEmpty()) {
            update as user toReactivate;
        }

        List<Product_Territory_Alignment__c> toInsert = new List<Product_Territory_Alignment__c>();
        for (Id territoryId : requestedTerritoryIds) {
            if (territoryId == null || existingTerritoryIds.contains(territoryId)) {
                continue;
            }
            toInsert.add(new Product_Territory_Alignment__c(
                Product2_Id__c = String.valueOf(productId),
                Territory2_Id__c = String.valueOf(territoryId),
                Is_Active__c = true,
                Effective_Start_Date__c = Date.today()
            ));
        }
        if (!toInsert.isEmpty()) {
            insert as user toInsert;
        }
        return requestedTerritoryIds.size();
    }

    private static Set<String> loadAlignedTerritoryIds(Id productId) {
        Set<String> aligned = new Set<String>();
        if (productId == null) {
            return aligned;
        }
        for (Product_Territory_Alignment__c alignment : [
            SELECT Territory2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE Product2_Id__c = :String.valueOf(productId)
                AND Is_Active__c = TRUE
            WITH USER_MODE
        ]) {
            if (alignment.Territory2_Id__c != null) {
                aligned.add(alignment.Territory2_Id__c);
            }
        }
        return aligned;
    }

    private static List<TerritoryTreeNode> buildTerritoryTree(Set<String> alignedTerritoryIds) {
        List<Territory2> territories = [
            SELECT Id, Name, ParentTerritory2Id
            FROM Territory2
            WHERE External_ID__c LIKE 'TERR_%'
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 5000
        ];
        if (territories.isEmpty()) {
            return new List<TerritoryTreeNode>();
        }

        Map<Id, List<TerritoryTreeNode>> childrenByParent = new Map<Id, List<TerritoryTreeNode>>();
        Map<Id, TerritoryTreeNode> nodesById = new Map<Id, TerritoryTreeNode>();

        for (Territory2 territory : territories) {
            TerritoryTreeNode node = new TerritoryTreeNode();
            node.id = territory.Id;
            node.name = territory.Name;
            node.parentId = territory.ParentTerritory2Id;
            node.aligned = alignedTerritoryIds.contains(String.valueOf(territory.Id));
            node.children = new List<TerritoryTreeNode>();
            node.hasChildren = false;
            nodesById.put(territory.Id, node);
        }

        for (Territory2 territory : territories) {
            TerritoryTreeNode node = nodesById.get(territory.Id);
            if (territory.ParentTerritory2Id != null && nodesById.containsKey(territory.ParentTerritory2Id)) {
                if (!childrenByParent.containsKey(territory.ParentTerritory2Id)) {
                    childrenByParent.put(territory.ParentTerritory2Id, new List<TerritoryTreeNode>());
                }
                childrenByParent.get(territory.ParentTerritory2Id).add(node);
            }
        }

        for (Id parentId : childrenByParent.keySet()) {
            if (nodesById.containsKey(parentId)) {
                List<TerritoryTreeNode> children = childrenByParent.get(parentId);
                children.sort(new TerritoryNodeNameComparator());
                nodesById.get(parentId).children = children;
                nodesById.get(parentId).hasChildren = !children.isEmpty();
            }
        }

        List<TerritoryTreeNode> roots = new List<TerritoryTreeNode>();
        for (Territory2 territory : territories) {
            TerritoryTreeNode node = nodesById.get(territory.Id);
            if (territory.ParentTerritory2Id == null || !nodesById.containsKey(territory.ParentTerritory2Id)) {
                roots.add(node);
            }
        }
        roots.sort(new TerritoryNodeNameComparator());
        return roots;
    }

    private static Id parseTerritoryId(String territoryIdValue) {
        if (String.isBlank(territoryIdValue)) {
            return null;
        }
        try {
            return (Id) territoryIdValue;
        } catch (Exception ex) {
            return null;
        }
    }

    private class ProductNodeLabelComparator implements Comparator<ProductTreeNode> {
        public Integer compare(ProductTreeNode left, ProductTreeNode right) {
            String leftLabel = left != null && left.label != null ? left.label : '';
            String rightLabel = right != null && right.label != null ? right.label : '';
            return leftLabel.compareTo(rightLabel);
        }
    }

    private class TerritoryNodeNameComparator implements Comparator<TerritoryTreeNode> {
        public Integer compare(TerritoryTreeNode left, TerritoryTreeNode right) {
            String leftName = left != null && left.name != null ? left.name : '';
            String rightName = right != null && right.name != null ? right.name : '';
            return leftName.compareTo(rightName);
        }
    }
}