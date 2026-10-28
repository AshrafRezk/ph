@IsTest
private class S_BricksManagementControllerTest {
    @IsTest
    static void smoke() {
        List<BricksManagementController.BrickRow> bricks = BricksManagementController.listBricks();
        System.assertNotEquals(null, bricks);
        System.assertNotEquals(null, BricksManagementController.getBricksByTerritory(null));
        System.assertNotEquals(null, BricksManagementController.getBrickPharmacies(null));
        System.assertNotEquals(null, BricksManagementController.listPharmacies(null));
        System.assertNotEquals(null, BricksManagementController.searchPharmacyOptions('x'));
        BricksManagementController.SeedResult seed = BricksManagementController.seedBrickDemoData();
        System.assertNotEquals(null, seed);
        System.assertNotEquals(null, seed.message);
    }
}
