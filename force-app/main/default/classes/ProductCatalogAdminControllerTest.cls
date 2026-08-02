@IsTest
private class ProductCatalogAdminControllerTest {

    @IsTest
    static void getProductCatalogTree_groupsByFamily() {
        insert new Product2(
            Name = 'Empacoza Test',
            ProductCode = 'ZETA-TEST-1',
            External_ID__c = 'ZETA_TEST_1',
            Family = 'Empacoza',
            Therapy_Area__c = 'Diabetes',
            Product_Image_URL__c = 'https://example.com/empacoza-test.png',
            IsActive = true
        );
        insert new Product2(
            Name = 'Dozova Test',
            ProductCode = 'ZETA-TEST-2',
            External_ID__c = 'ZETA_TEST_2',
            Family = 'Dozova',
            Therapy_Area__c = 'CHC',
            IsActive = true
        );

        Test.startTest();
        List<ProductCatalogAdminController.ProductTreeNode> tree =
            ProductCatalogAdminController.getProductCatalogTree();
        Test.stopTest();

        System.assert(tree.size() >= 2);

        Boolean foundImageUrl = false;
        for (ProductCatalogAdminController.ProductTreeNode familyNode : tree) {
            for (ProductCatalogAdminController.ProductTreeNode productNode : familyNode.children) {
                if (productNode.label == 'Empacoza Test') {
                    System.assertEquals('https://example.com/empacoza-test.png', productNode.imageUrl);
                    foundImageUrl = true;
                }
            }
        }
        System.assertEquals(true, foundImageUrl, 'Expected product image URL in catalog tree');
    }

    @IsTest
    static void saveProductTerritoryAlignments_createsAndRemovesRows() {
        Product2 product = new Product2(
            Name = 'Alignment Test Product',
            ProductCode = 'ZETA-ALIGN',
            External_ID__c = 'ZETA_ALIGN_TEST',
            Family = 'Empacoza',
            Therapy_Area__c = 'Diabetes',
            IsActive = true
        );
        insert product;

        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return;
        }
        Territory2Model model = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        Territory2 territory = new Territory2(
            Name = 'Product Align Test Territory',
            DeveloperName = 'Product_Align_Test',
            Territory2ModelId = model.Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = 'TERR_PRODUCT_ALIGN_TEST'
        );
        insert territory;

        Test.startTest();
        ProductCatalogAdminController.saveProductTerritoryAlignments(
            product.Id,
            new List<Id>{ territory.Id }
        );
        Integer cleared = ProductCatalogAdminController.saveProductTerritoryAlignments(
            product.Id,
            new List<Id>()
        );
        Test.stopTest();

        System.assertEquals(0, cleared);
    }
}
