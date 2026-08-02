@IsTest
private class TerritoryAdminServiceTest {

    @IsTest
    static void getProductLines_returnsList() {
        Test.startTest();
        List<TerritoryAdminService.LineSummary> lines = TerritoryAdminService.getProductLines();
        Test.stopTest();
        System.assertNotEquals(null, lines);
    }

    @IsTest
    static void resolveLevel_classifiesTerritoryDepth() {
        System.assertEquals('Head Office', TerritoryAdminService.resolveLevel('TERR_HEAD_OFFICE'));
        System.assertEquals('Line', TerritoryAdminService.resolveLevel('TERR_DIABETES'));
        System.assertEquals('District', TerritoryAdminService.resolveLevel('TERR_DIABETES_DM_1'));
        System.assertEquals('MR', TerritoryAdminService.resolveLevel('TERR_DIABETES_DM_1_MR_1'));
    }
}
