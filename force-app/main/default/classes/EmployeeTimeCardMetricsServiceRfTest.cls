@IsTest
private class EmployeeTimeCardMetricsServiceRfTest {
  @IsTest
  static void recalcTimeCardRollups_countsMcfTowardRfPercent() {
    Account lcfAccount = new Account(Name = 'RF Rollup LCF Account');
    Account mcfAccount = new Account(Name = 'RF Rollup MCF Account');
    insert new List<Account>{ lcfAccount, mcfAccount };

    Date monthStart = Date.today().toStartOfMonth();
    Employee_Time_Card__c timeCard = new Employee_Time_Card__c(
      Employee__c = UserInfo.getUserId(),
      Time_Card_Month_Start_Date__c = monthStart,
      Time_Card_Month_End_Date__c = monthStart.addMonths(1).addDays(-1),
      Unique_Identifier__c = UserInfo.getUserId() + ':' + String.valueOf(monthStart),
      Active_Time_Card__c = true
    );
    insert timeCard;

    insert new List<Employee_Time_Card_Account_Target__c>{
      new Employee_Time_Card_Account_Target__c(
        Employee_Time_Card__c = timeCard.Id,
        Account__c = lcfAccount.Id,
        Potentiality__c = 'A',
        Target_Visit_Frequency__c = 2,
        Actual_Visits__c = 0,
        Unique_Key__c = timeCard.Id + ':' + lcfAccount.Id
      ),
      new Employee_Time_Card_Account_Target__c(
        Employee_Time_Card__c = timeCard.Id,
        Account__c = mcfAccount.Id,
        Potentiality__c = 'A',
        Target_Visit_Frequency__c = 2,
        Actual_Visits__c = 3,
        Unique_Key__c = timeCard.Id + ':' + mcfAccount.Id
      )
    };

    Test.startTest();
    EmployeeTimeCardMetricsService.recalcTimeCardRollups(new Set<Id>{ timeCard.Id });
    Test.stopTest();

    timeCard = [
      SELECT RCF_Percent__c, LCF_Percent__c
      FROM Employee_Time_Card__c
      WHERE Id = :timeCard.Id
    ];
    System.assertEquals(0.5, timeCard.RCF_Percent__c);
    System.assertEquals(0.5, timeCard.LCF_Percent__c);
  }
}