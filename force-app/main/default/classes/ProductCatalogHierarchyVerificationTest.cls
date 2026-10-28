@IsTest(SeeAllData = false)
private class ProductCatalogHierarchyVerificationTest {
    @IsTest
    static void onboarding_and_catalog_and_dispenseExpansion() {
        String csv =
            'Unit,Line,primary_brand,Brand,Product_Type,Parent_External_Id,Zeta_Code,Mendix_External_Id,Zeta_Name,Is_Active\n'
            + 'DIAB,DIAB-I,VerifyBrand,VerifyBrand,Detail,BRAND_VERIFYBRAND,VBD001,VBD001-MX,Verify Detail,Yes\n'
            + 'DIAB,DIAB-I,VerifyBrand,VerifyBrand,Brand Reminder,VBD001-MX,VBR001,VBR001-MX,Verify Reminder,Yes\n';

        Test.startTest();
        PharmaProductOnboardingService.SeedResult seedResult = PharmaProductOnboardingService.seedFromCsv(csv);
        List<ProductCatalogAdminController.ProductTreeNode> tree =
            ProductCatalogAdminController.getProductCatalogTree();
        Test.stopTest();

        Assert.isTrue(seedResult.productsUpserted >= 1);

        Product2 detail = [
            SELECT Id, Sales_Line__c
            FROM Product2
            WHERE External_ID__c = 'VBD001-MX'
            LIMIT 1
        ];

        Boolean hasBrandRoot = false;
        for (ProductCatalogAdminController.ProductTreeNode root : tree) {
            if (root.productType == 'Brand' && root.label == 'VerifyBrand') {
                hasBrandRoot = true;
            }
        }
        Assert.isTrue(hasBrandRoot, 'Catalog tree should include onboarded brand root.');

        Integer reminderCount = [
            SELECT COUNT()
            FROM Product2
            WHERE Product_Type__c = 'Brand Reminder' AND Parent_Product__c = :detail.Id
        ];
        Assert.isTrue(reminderCount >= 1, 'Onboarding should create Brand Reminder under detail.');
    }
}