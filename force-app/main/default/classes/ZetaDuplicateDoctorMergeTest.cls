@IsTest
private class ZetaDuplicateDoctorMergeTest {
  @IsTest
  static void dryRun_doesNotDeleteOrUpdate() {
    Id personRtId = personAccountRecordTypeId();
    if (personRtId == null) {
      return;
    }
    Account withPhone = insertDoctor(
      personRtId,
      'Zdm',
      'DryRun',
      'DOC-ZDMDRY1',
      '01000000001',
      null
    );
    Account withCity = insertDoctor(personRtId, 'Zdm', 'DryRun', 'DOC-ZDMDRY2', null, 'Cairo');

    Test.startTest();
    List<ZetaDuplicateDoctorMerge.GroupResult> results = ZetaDuplicateDoctorMerge.mergeNames(
      new List<String>{ 'Zdm DryRun' },
      true
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals(false, results[0].skipped);
    System.assert(
      results[0].message.startsWith('DRY RUN'),
      'Expected a dry-run message, got: ' + results[0].message
    );
    System.assertEquals(2, [SELECT COUNT() FROM Account WHERE LastName = 'DryRun']);
    Account phoneRow = [
      SELECT BillingCity
      FROM Account
      WHERE Id = :withPhone.Id
    ];
    System.assertEquals(null, phoneRow.BillingCity, 'Dry run must not copy city onto the survivor');
    System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Id = :withCity.Id]);
  }

  @IsTest
  static void mergeNames_fillsBlanksThenDeletesLosers() {
    Id personRtId = personAccountRecordTypeId();
    if (personRtId == null) {
      return;
    }
    insertDoctor(personRtId, 'Zdm', 'PhoneCity', 'DOC-ZDMMRG2', '01000000002', null);
    insertDoctor(personRtId, 'Zdm', 'PhoneCity', 'DOC-ZDMMRG1', null, 'Alexandria');

    Test.startTest();
    List<ZetaDuplicateDoctorMerge.GroupResult> results = ZetaDuplicateDoctorMerge.mergeNames(
      new List<String>{ 'Zdm PhoneCity' },
      false
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals(false, results[0].skipped, results[0].message);
    System.assertEquals(1, [SELECT COUNT() FROM Account WHERE LastName = 'PhoneCity']);
    Account survivor = [
      SELECT PersonMobilePhone, BillingCity, Description, External_ID__c
      FROM Account
      WHERE LastName = 'PhoneCity'
    ];
    System.assertEquals('01000000002', survivor.PersonMobilePhone);
    System.assertEquals('Alexandria', survivor.BillingCity);
    System.assert(survivor.Description.contains('Merged codes:'), survivor.Description);
  }

  @IsTest
  static void mergeNames_reparentsAffiliationAndDropsDuplicateLink() {
    Id personRtId = personAccountRecordTypeId();
    Id hcoRtId = hcoRecordTypeId();
    if (personRtId == null || hcoRtId == null) {
      return;
    }

    Account survivor = insertDoctor(
      personRtId,
      'Zdm',
      'AffMerge',
      'DOC-ZDMAFF1',
      '01000000003',
      'Giza'
    );
    Account loser = insertDoctor(personRtId, 'Zdm', 'AffMerge', 'DOC-ZDMAFF2', null, null);
    Account hospital = new Account(RecordTypeId = hcoRtId, Name = 'Zdm Aff Hospital');
    Account otherHospital = new Account(RecordTypeId = hcoRtId, Name = 'Zdm Aff Other');
    insert as system new List<Account>{ hospital, otherHospital };

    insert as system new List<Account_Affiliation__c>{
      new Account_Affiliation__c(
        Primary_Account__c = survivor.Id,
        Related_Account__c = hospital.Id,
        Affiliation_Type__c = 'Practice',
        Role__c = 'Physician',
        External_ID__c = 'AFF-DOC-ZDMAFF1-HCO-1',
        Is_Active__c = true
      ),
      new Account_Affiliation__c(
        Primary_Account__c = loser.Id,
        Related_Account__c = hospital.Id,
        Affiliation_Type__c = 'Practice',
        Role__c = 'Physician',
        External_ID__c = 'AFF-DOC-ZDMAFF2-HCO-1',
        Is_Active__c = true
      ),
      new Account_Affiliation__c(
        Primary_Account__c = loser.Id,
        Related_Account__c = otherHospital.Id,
        Affiliation_Type__c = 'Practice',
        Role__c = 'Physician',
        External_ID__c = 'AFF-DOC-ZDMAFF2-HCO-2',
        Is_Active__c = true
      )
    };

    Test.startTest();
    ZetaDuplicateDoctorMerge.mergeNames(new List<String>{ 'Zdm AffMerge' }, false);
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id = :loser.Id]);
    List<Account_Affiliation__c> kept = [
      SELECT Related_Account__c
      FROM Account_Affiliation__c
      WHERE Primary_Account__c = :survivor.Id
    ];
    System.assertEquals(2, kept.size(), 'Duplicate hospital link dropped; unique hospital kept');
    Set<Id> relatedIds = new Set<Id>();
    for (Account_Affiliation__c row : kept) {
      relatedIds.add(row.Related_Account__c);
    }
    System.assert(relatedIds.contains(hospital.Id));
    System.assert(relatedIds.contains(otherHospital.Id));
  }

  @IsTest
  static void mergeNames_skipsGroupsLargerThanMax() {
    Id personRtId = personAccountRecordTypeId();
    if (personRtId == null) {
      return;
    }
    insertDoctor(personRtId, 'Zdm', 'SkipThree', 'DOC-ZDMSK1', '01000000004', null);
    insertDoctor(personRtId, 'Zdm', 'SkipThree', 'DOC-ZDMSK2', null, 'Asyut');
    insertDoctor(personRtId, 'Zdm', 'SkipThree', 'DOC-ZDMSK3', null, null);

    ZetaDuplicateDoctorMerge worker = new ZetaDuplicateDoctorMerge(false, 2);
    Test.startTest();
    ZetaDuplicateDoctorMerge.GroupResult result = worker.mergeName('Zdm SkipThree');
    Test.stopTest();

    System.assertEquals(true, result.skipped);
    System.assertEquals(3, [SELECT COUNT() FROM Account WHERE LastName = 'SkipThree']);
  }

  @IsTest
  static void mergeNames_copiesSpecialtyAndKeepsSurvivorPhoneOnConflict() {
    Id personRtId = personAccountRecordTypeId();
    if (personRtId == null) {
      return;
    }
    Account kept = insertDoctor(
      personRtId,
      'Zdm',
      'SpecConf',
      'DOC-ZDMSC1',
      '01000000006',
      'Tanta'
    );
    Account extra = insertDoctor(personRtId, 'Zdm', 'SpecConf', 'DOC-ZDMSC2', '01000000007', null);
    extra.Specialty_1__c = 'Paediatrics';
    update as system extra;

    Test.startTest();
    ZetaDuplicateDoctorMerge.GroupResult result = ZetaDuplicateDoctorMerge.mergeNames(
      new List<String>{ 'Zdm SpecConf' },
      false
    )[0];
    Test.stopTest();

    System.assertEquals(false, result.skipped, result.message);
    Account survivor = [
      SELECT PersonMobilePhone, BillingCity, Specialty_1__c
      FROM Account
      WHERE Id = :kept.Id
    ];
    System.assertEquals('01000000006', survivor.PersonMobilePhone);
    System.assertEquals('Tanta', survivor.BillingCity);
    System.assertEquals('Paediatrics', survivor.Specialty_1__c);
    System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id = :extra.Id]);
  }

  @IsTest
  static void mergeNames_blankAndMissingGroups() {
    System.assertEquals(0, ZetaDuplicateDoctorMerge.mergeNames(null, true).size());
    ZetaDuplicateDoctorMerge.GroupResult blank = ZetaDuplicateDoctorMerge.mergeNames(
      new List<String>{ '' },
      true
    )[0];
    System.assertEquals(true, blank.skipped);
    ZetaDuplicateDoctorMerge.GroupResult missing = ZetaDuplicateDoctorMerge.mergeNames(
      new List<String>{ 'Nobody Here Zdm' },
      true
    )[0];
    System.assertEquals(true, missing.skipped);
  }

  @IsTest
  static void batch_dryRunCompletes() {
    Id personRtId = personAccountRecordTypeId();
    if (personRtId == null) {
      return;
    }
    insertDoctor(personRtId, 'Zdm', 'BatchPair', 'DOC-ZDMBAT1', '01000000005', null);
    insertDoctor(personRtId, 'Zdm', 'BatchPair', 'DOC-ZDMBAT2', null, 'Luxor');

    Test.startTest();
    Id jobId = ZetaDuplicateDoctorMerge.run(true, 2);
    Test.stopTest();

    System.assertNotEquals(null, jobId);
    System.assertEquals(2, [SELECT COUNT() FROM Account WHERE LastName = 'BatchPair']);
  }

  private static Account insertDoctor(
    Id personRtId,
    String firstName,
    String lastName,
    String externalId,
    String mobile,
    String city
  ) {
    Account row = new Account(
      RecordTypeId = personRtId,
      FirstName = firstName,
      LastName = lastName,
      External_ID__c = externalId,
      PersonMobilePhone = mobile,
      BillingCity = city,
      BillingCountry = 'Egypt',
      Account_Status__c = 'Active',
      Account_Stage__c = 'Active'
    );
    insert as system row;
    return row;
  }

  private static Id personAccountRecordTypeId() {
    List<RecordType> rows = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsPersonType = TRUE AND IsActive = TRUE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Id;
  }

  private static Id hcoRecordTypeId() {
    List<RecordType> rows = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Institution_HCO' AND IsActive = TRUE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Id;
  }
}