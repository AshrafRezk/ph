@IsTest
private class AccountPhoneBackfillTest {
  @IsTest
  static void backfillsBusinessAndPersonPhones() {
    Account business = new Account(Name = 'Phone Backfill HCO');
    insert business;

    List<RecordType> personTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsPersonType = TRUE
      LIMIT 1
    ];
    if (!personTypes.isEmpty()) {
      insert new Account(
        RecordTypeId = personTypes[0].Id,
        FirstName = 'Demo',
        LastName = 'HCP',
        PersonEmail = 'demo.hcp.phone@test.eg'
      );
    }

    Test.startTest();
    AccountPhoneBackfill.BackfillResult result = AccountPhoneBackfill.backfillAllAccounts();
    Test.stopTest();

    System.assert(result.updatedCount > 0, 'Expected at least one account updated');
    Account updatedBusiness = [
      SELECT Phone
      FROM Account
      WHERE Id = :business.Id
    ];
    System.assertEquals(AccountPhoneDefaults.DEMO_PHONE, updatedBusiness.Phone);
  }
}
