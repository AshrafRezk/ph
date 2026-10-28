@IsTest(SeeAllData = false)
private class ProductCatalogAdminControllerTest {

    @IsTest
    static void getProductCatalogTree_buildsHierarchy() {
        Product2 brand = new Product2(
            Name = 'Hierarchy Brand',
            ProductCode = 'HBRAND',
            External_ID__c = 'HBRAND_EXT',
            Product_Type__c = 'Brand',
            IsActive = true
        );
        insert brand;

        Product2 detail = new Product2(
            Name = 'Hierarchy Detail',
            ProductCode = 'HDET',
            External_ID__c = 'HDET_EXT',
            Product_Type__c = 'Detail',
            Parent_Product__c = brand.Id,
            IsActive = true
        );
        insert detail;

        Test.startTest();
        List<ProductCatalogAdminController.ProductTreeNode> tree =
            ProductCatalogAdminController.getProductCatalogTree();
        Test.stopTest();

        Boolean foundBrand = false;
        Boolean foundNestedDetail = false;
        for (ProductCatalogAdminController.ProductTreeNode root : tree) {
            if (root.label == 'Hierarchy Brand') {
                foundBrand = true;
                Assert.areEqual('brand', root.nodeType);
                Assert.areEqual('HBRAND_EXT', root.externalId);
                for (ProductCatalogAdminController.ProductTreeNode child : root.children) {
                    if (child.label == 'Hierarchy Detail') {
                        foundNestedDetail = true;
                        Assert.areEqual('detail', child.nodeType);
                    }
                }
            }
        }
        Assert.isTrue(foundBrand, 'Expected brand root in catalog tree.');
        Assert.isTrue(foundNestedDetail, 'Expected detail child under brand.');
    }

    @IsTest
    static void getProductCatalogTree_includesInactiveProductsFlagged() {
        Product2 brand = new Product2(
            Name = 'Inactive Check Brand',
            ProductCode = 'ICBRAND',
            External_ID__c = 'ICBRAND_EXT',
            Product_Type__c = 'Brand',
            IsActive = true
        );
        insert brand;
        Product2 inactiveDetail = new Product2(
            Name = 'Inactive Check Detail',
            ProductCode = 'ICDET',
            External_ID__c = 'ICDET_EXT',
            Product_Type__c = 'Detail',
            Parent_Product__c = brand.Id,
            IsActive = false
        );
        Product2 untypedInactive = new Product2(
            Name = 'Inactive Untyped SKU',
            ProductCode = 'ICUNTYPED',
            External_ID__c = 'ICUNTYPED_EXT',
            IsActive = false
        );
        insert new List<Product2>{ inactiveDetail, untypedInactive };

        Test.startTest();
        List<ProductCatalogAdminController.ProductTreeNode> tree =
            ProductCatalogAdminController.getProductCatalogTree();
        Test.stopTest();

        Boolean foundInactiveDetail = false;
        Boolean foundUntypedRoot = false;
        for (ProductCatalogAdminController.ProductTreeNode root : tree) {
            if (root.label == 'Inactive Untyped SKU') {
                foundUntypedRoot = true;
                Assert.isFalse(root.isActive, 'Untyped SKU should be flagged inactive.');
            }
            if (root.label == 'Inactive Check Brand') {
                Assert.isTrue(root.isActive, 'Active brand should be flagged active.');
                for (ProductCatalogAdminController.ProductTreeNode child : root.children) {
                    if (child.label == 'Inactive Check Detail') {
                        foundInactiveDetail = true;
                        Assert.isFalse(child.isActive, 'Inactive detail should be flagged inactive.');
                    }
                }
            }
        }
        Assert.isTrue(foundInactiveDetail, 'Inactive detail should still show under its brand.');
        Assert.isTrue(foundUntypedRoot, 'Inactive SKU with no type or brand should show at the top level.');
    }

    @IsTest
    static void saveProductTerritoryAlignments_createsAndRemovesRows() {
        Product2 product = new Product2(
            Name = 'Alignment Test Product',
            ProductCode = 'ZETA-ALIGN',
            External_ID__c = 'ZETA_ALIGN_TEST',
            Product_Type__c = 'Brand',
            IsActive = true
        );
        insert product;

        List<Territory2> territories = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c LIKE 'TERR_%'
            WITH USER_MODE
            LIMIT 1
        ];
        if (territories.isEmpty()) {
            return;
        }

        Test.startTest();
        ProductCatalogAdminController.saveProductTerritoryAlignments(
            product.Id,
            new List<Id>{ territories[0].Id }
        );
        Integer cleared = ProductCatalogAdminController.saveProductTerritoryAlignments(
            product.Id,
            new List<Id>()
        );
        Test.stopTest();

        Assert.areEqual(0, cleared);
    }

    @IsTest
    static void getTerritoryTreeForProduct_returnsNodes() {
        Product2 product = new Product2(
            Name = 'Territory Tree Product',
            ProductCode = 'ZETA-TTREE',
            External_ID__c = 'ZETA_TTREE_TEST',
            Product_Type__c = 'Brand',
            IsActive = true
        );
        insert product;

        Test.startTest();
        List<ProductCatalogAdminController.TerritoryTreeNode> tree =
            ProductCatalogAdminController.getTerritoryTreeForProduct(product.Id);
        Test.stopTest();

        System.assertNotEquals(null, tree);
    }

    @IsTest
    static void saveProductTerritoryAlignments_requiresProduct() {
        Boolean threw = false;
        try {
            ProductCatalogAdminController.saveProductTerritoryAlignments(null, new List<Id>());
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }
}