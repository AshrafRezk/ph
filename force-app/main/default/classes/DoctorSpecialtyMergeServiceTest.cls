@IsTest
private class DoctorSpecialtyMergeServiceTest {
  private static Account doctor(String code, String specialty, String phone) {
    return new Account(
      RecordTypeId = AccountMasterImportUtil.hcpRecordTypeId(),
      External_ID__c = AccountMasterImportUtil.doctorExternalId(code),
      Institution_Type__c = 'Doctor',
      FirstName = 'احمد',
      LastName = 'حامد الجوهري',
      Specialty_1__c = specialty,
      PersonMobilePhone = phone,
      BillingCountry = 'Egypt'
    );
  }

  private static Account clinic(String id, String street) {
    return new Account(
      Name = 'Clinic ' + id,
      RecordTypeId = AccountMasterImportUtil.clinicHcpRecordTypeId(),
      External_ID__c = AccountMasterImportUtil.clinicExternalId(id),
      Institution_Type__c = 'Clinic',
      BillingStreet = street,
      BillingCity = 'المعادي',
      BillingCountry = 'Egypt'
    );
  }

  private static Account_Affiliation__c link(Id doctorId, Id placeId) {
    return new Account_Affiliation__c(
      Primary_Account__c = doctorId,
      Related_Account__c = placeId,
      Affiliation_Type__c = 'Practice',
      Role__c = 'Physician',
      Is_Active__c = true
    );
  }

  private static Account_Territory_Fields__c atf(Id accountId, String territory, String cls, Decimal visits) {
    return new Account_Territory_Fields__c(
      Account__c = accountId,
      Territory2_Id__c = territory,
      Unique_Key__c = (String.valueOf(accountId) + '_' + territory).left(40),
      Is_Active__c = true,
      HCP_Classification__c = cls,
      Call_Plan_Visits_Per_Month__c = visits
    );
  }

  @IsTest
  static void compareAndMerge_keepsEverything() {
    Account a = doctor('91001', 'Internal_Medicine', '01001234567');
    Account b = doctor('91002', 'Gastroenterology', '+201001234567');
    b.PersonEmail = 'dr@example.com';
    Account c1 = clinic('81001', 'شارع 9 المعادي');
    Account c2 = clinic('81002', 'شارع 9 المعادي برج النور');
    insert new List<Account>{ a, b, c1, c2 };
    insert new List<Account_Affiliation__c>{ link(a.Id, c1.Id), link(b.Id, c2.Id), link(b.Id, c1.Id) };
    String terrShared = '0MI000000000001';
    String terrOther = '0MI000000000002';
    insert new List<Account_Territory_Fields__c>{
      atf(a.Id, terrShared, 'B2', 1),
      atf(b.Id, terrShared, 'A1', 3),
      atf(b.Id, terrOther, 'A3', 2)
    };

    Test.startTest();
    DoctorSpecialtyMergeService.PairView view = DoctorSpecialtyMergeService.comparePair('91001', 'DOC-91002');
    DoctorSpecialtyMergeService.MergeResult result = DoctorSpecialtyMergeService.mergePair(null, a.Id, b.Id);
    Test.stopTest();

    System.assert(view.score >= 70, 'Same phone + shared clinic + related specialties: ' + JSON.serialize(view.factors));
    System.assertEquals(2, view.mergedSpecialties.size());

    Account kept = [
      SELECT Specialty_1__c, Specialty_2__c, PersonEmail, Merged_External_IDs__c
      FROM Account
      WHERE Id = :a.Id
    ];
    System.assertEquals('Internal_Medicine', kept.Specialty_1__c);
    System.assertEquals('Gastroenterology', kept.Specialty_2__c);
    System.assertEquals('dr@example.com', kept.PersonEmail, 'Blank field filled from the other record');
    System.assertEquals(';DOC-91002;', kept.Merged_External_IDs__c);
    System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id = :b.Id]);

    List<Account_Territory_Fields__c> rows = [
      SELECT Territory2_Id__c, HCP_Classification__c, Call_Plan_Visits_Per_Month__c, Unique_Key__c
      FROM Account_Territory_Fields__c
      WHERE Account__c = :a.Id
      ORDER BY Territory2_Id__c
    ];
    System.assertEquals(2, rows.size(), 'One row per line');
    System.assertEquals('A1', rows[0].HCP_Classification__c, 'Better class kept on the shared line');
    System.assertEquals(3, rows[0].Call_Plan_Visits_Per_Month__c, 'Higher visits kept on the shared line');
    System.assertEquals('A3', rows[1].HCP_Classification__c, 'Other line keeps its own class');
    System.assert(rows[1].Unique_Key__c.startsWith(String.valueOf(a.Id)));

    System.assertEquals(2, [SELECT COUNT() FROM Account_Affiliation__c WHERE Primary_Account__c = :a.Id], 'Both clinics, no double link');
    System.assertEquals(1, result.combinedTargetRows);

    Account_Quality_Proposal__c log = [SELECT Status__c, Payload__c FROM Account_Quality_Proposal__c LIMIT 1];
    System.assertEquals('Applied', log.Status__c);
    System.assert(log.Payload__c.contains('removedDoctor'), 'Snapshot of the removed record kept');
    System.assertEquals(a.Id, DoctorSpecialtyMergeService.survivorsForMergedCodes(new Set<String>{ 'DOC-91002' }).get('DOC-91002'));
  }

  @IsTest
  static void scan_groupsAndScoresPairs() {
    Account a = doctor('92001', 'Nephrology', '01005550000');
    Account b = doctor('92002', 'Internal_Medicine', '01005550000');
    Account other = doctor('92003', 'Nephrology', null);
    other.LastName = 'منصور';
    insert new List<Account>{ a, b, other };
    Account_Quality_Run__c run = DoctorSpecialtyMergeService.newRun('Queued');
    insert run;

    Test.startTest();
    Database.executeBatch(new DoctorSpecialtyScanBatch(run.Id), 500);
    Test.stopTest();

    Account_Quality_Run__c done = [SELECT Status__c, Accounts_Scanned__c FROM Account_Quality_Run__c WHERE Id = :run.Id];
    System.assertEquals('Ready', done.Status__c);
    System.assert(done.Accounts_Scanned__c >= 3);
  }

  @IsTest
  static void pairScorer_storesProposalsAndLists() {
    Account a = doctor('93001', 'Diabetology', '01007770000');
    Account b = doctor('93002', 'Endocrinology', '01007770000');
    insert new List<Account>{ a, b };
    Account_Quality_Run__c run = DoctorSpecialtyMergeService.newRun('Running');
    insert run;

    Test.startTest();
    Database.executeBatch(
      new DoctorSpecialtyPairScorer(run.Id, new List<List<String>>{ new List<String>{ a.Id, b.Id } }),
      20
    );
    Test.stopTest();

    List<DoctorSpecialtyMergeService.PairView> pairs = DoctorSpecialtyMergeService.listPairs(run.Id, 30, false);
    System.assertEquals(1, pairs.size());
    System.assertNotEquals(null, pairs[0].suggestedSurvivorId);
    System.assertEquals('Ready', DoctorSpecialtyMergeService.getLatestRun().status);

    DoctorSpecialtyMergeService.dismissPairs(new List<Id>{ pairs[0].proposalId });
    System.assertEquals(0, DoctorSpecialtyMergeService.listPairs(run.Id, 30, false).size());
    System.assertEquals(1, DoctorSpecialtyMergeService.listPairs(run.Id, 30, true).size());
  }

  @IsTest
  static void startScan_queuesRun() {
    Test.startTest();
    AccountQualityReviewService.JobStatus status = DoctorSpecialtyMergeService.startScan();
    AccountQualityReviewService.JobStatus again = DoctorSpecialtyMergeService.startScan();
    Test.stopTest();
    System.assertNotEquals(null, status.runId);
    System.assertEquals(status.runId, again.runId, 'A running scan is reused');
  }

  @IsTest
  static void imports_followMergedCodes() {
    Account kept = doctor('94001', 'Cardiology', null);
    kept.Merged_External_IDs__c = ';DOC-94002;';
    insert kept;

    AccountManagementController.DoctorRow row = new AccountManagementController.DoctorRow();
    row.code = '94002';
    row.doctor = 'احمد حامد الجوهري';

    Test.startTest();
    AccountManagementController.ChunkResult result = AccountManagementController.upsertDoctorChunk(
      new List<AccountManagementController.DoctorRow>{ row },
      false
    );
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM Account WHERE External_ID__c = 'DOC-94002'], 'Merged doctor not recreated');
    System.assertEquals(1, result.skippedCount);
  }

  @IsTest
  static void compare_rejectsBadInput() {
    Account a = doctor('95001', 'Cardiology', null);
    insert a;
    for (List<String> codes : new List<List<String>>{
      new List<String>{ '95001', '95001' },
      new List<String>{ '95001', 'nope' },
      new List<String>{ '', '95001' }
    }) {
      try {
        DoctorSpecialtyMergeService.comparePair(codes[0], codes[1]);
        System.assert(false, 'Expected an error for ' + codes);
      } catch (AuraHandledException expected) {
        System.assertNotEquals(null, expected.getMessage());
      }
    }
  }
}
