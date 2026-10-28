@IsTest
private class BrickSalesAlertServiceTest {
  @IsTest
  static void getBrickGrowthAlerts_returnsList() {
    Test.startTest();
    List<BrickSalesAlertService.BrickAlertRow> alerts =
      BrickSalesAlertService.getBrickGrowthAlerts(UserInfo.getUserId());
    Test.stopTest();
    System.assertNotEquals(null, alerts);
  }

  @IsTest
  static void notifyRepsForGrowingBricks_isBestEffort() {
    Test.startTest();
    Integer sent = BrickSalesAlertService.notifyRepsForGrowingBricks();
    Test.stopTest();
    System.assert(sent >= 0);
  }
}
