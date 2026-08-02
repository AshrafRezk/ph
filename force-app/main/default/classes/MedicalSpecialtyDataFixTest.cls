@IsTest
private class MedicalSpecialtyDataFixTest {
  @IsTest
  static void runBatch_leavesValidApiValuesUnchanged() {
    Account account = buildHcpAccount('Dr Specialty Stable');
    account.Specialty_1__c = 'Paediatric_Oncology';
    insert account;

    Test.startTest();
    Id jobId = MedicalSpecialtyDataFix.runBatch();
    Test.stopTest();

    System.assertNotEquals(null, jobId);

    Account updated = [
      SELECT Specialty_1__c
      FROM Account
      WHERE Id = :account.Id
    ];
    System.assertEquals('Paediatric_Oncology', updated.Specialty_1__c);
  }

  private static Account buildHcpAccount(String label) {
    Account account = new Account(
      BillingCity = 'Cairo',
      BillingStreet = '1 Nile St',
      Tier__c = 'A',
      Professional_Designation__c = 'MD',
      Account_Status__c = 'Active'
    );
    Id personRecordTypeId = getPersonAccountRecordTypeId();
    if (personRecordTypeId != null) {
      account.RecordTypeId = personRecordTypeId;
      account.LastName = label;
    } else {
      account.Name = label;
    }
    return account;
  }

  private static Id getPersonAccountRecordTypeId() {
    List<RecordType> hcpTypes = [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsActive = TRUE
        AND DeveloperName IN ('SDO_PersonAccounts', 'Medical_Professional_HCP')
      LIMIT 1
    ];
    return hcpTypes.isEmpty() ? null : hcpTypes[0].Id;
  }
}
