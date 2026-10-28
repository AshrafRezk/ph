@IsTest(SeeAllData = false)
private class PharmaProductOnboardingServiceTest {
    @IsTest
    static void seedFromCsv_createsBrandAndDetailHierarchy() {
        String csv =
            'Unit,Line,primary_brand,Brand,Product_Type,Parent_External_Id,Zeta_Code,Mendix_External_Id,Zeta_Name,Is_Active\n'
            + 'DIAB,DIAB-I,TestBrand,TestBrand,Detail,BRAND_TESTBRAND,ZTB001,MX-TB-001,Test Detail SKU,Yes\n';

        Test.startTest();
        PharmaProductOnboardingService.SeedResult result = PharmaProductOnboardingService.seedFromCsv(csv);
        Test.stopTest();

        Assert.isTrue(result.brandsUpserted >= 1);
        Assert.isTrue(result.productsUpserted >= 1);

        Product2 brand = [
            SELECT Id, Product_Type__c
            FROM Product2
            WHERE External_ID__c = :PharmaProductOnboardingService.brandExternalId('TestBrand')
            LIMIT 1
        ];
        Assert.areEqual('Brand', brand.Product_Type__c);

        Product2 detail = [
            SELECT Id, Product_Type__c, Parent_Product__c, External_ID__c
            FROM Product2
            WHERE External_ID__c = 'MX-TB-001'
            LIMIT 1
        ];
        Assert.areEqual('Detail', detail.Product_Type__c);
        Assert.areEqual(brand.Id, detail.Parent_Product__c);
    }

    @IsTest
    static void brandExternalId_normalizesSpaces() {
        Assert.areEqual('BRAND_DOZOVA', PharmaProductOnboardingService.brandExternalId('Dozova'));
    }
}