@IsTest
private class EmployeeTimeCardPaceControllerTest {

  @IsTest
  static void getPaceDetail_returnsWalkInMetrics() {
    User u = [SELECT Id FROM User WHERE IsActive = TRUE LIMIT 1];
    Date monthStart = Date.today().toStartOfMonth();
    Date monthEnd = monthStart.addMonths(1).addDays(-1);

    Employee_Time_Card__c card = new Employee_Time_Card__c(
      Employee__c = u.Id,
      Time_Card_Month_Start_Date__c = monthStart,
      Time_Card_Month_End_Date__c = monthEnd,
      Walk_in_Revenue__c = 5000,
      Walk_in_Revenue_Target__c = 10000,
      Walk_in_Revenue_Ach__c = 50,
      Walk_in_Visits__c = 20,
      Walk_in_Visits_Target__c = 40,
      Walk_in_Visits_Ach__c = 50
    );
    insert card;

    System.runAs(u) {
      Test.startTest();
      EmployeeTimeCardPaceService.PaceDetailResult detail = EmployeeTimeCardPaceController.getPaceDetail(
        monthStart.year(),
        monthStart.month(),
        u.Id
      );
      Test.stopTest();

      System.assertEquals(card.Id, detail.timeCardId);
      System.assertNotEquals(null, detail.walkInRevenue);
      System.assertEquals(5000, detail.walkInRevenue.actual);
      System.assertNotEquals(null, detail.walkInVisits);
      System.assertEquals(20, detail.walkInVisits.actual);
    }
  }
}
