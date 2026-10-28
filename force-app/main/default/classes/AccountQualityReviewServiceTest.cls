@IsTest
private class AccountQualityReviewServiceTest {
  @IsTest
  static void proposePlaces_fillsBlankPhoneAndOmitsMatchingPhoneAndName() {
    Account acct = new Account(
      Name = 'Nile Pharmacy Quality',
      BillingStreet = '10 Nile St',
      BillingCity = 'Cairo',
      BillingCountry = 'Egypt',
      BillingLatitude = 30.0444,
      BillingLongitude = 31.2357,
      Phone = '01099887766',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    insert acct;
    acct = reload(acct.Id);

    AccountMapsPlacesService.PlaceCandidate hit = new AccountMapsPlacesService.PlaceCandidate();
    hit.name = 'Nile Pharmacy Quality';
    hit.placeId = 'places/nile-quality-1';
    hit.address = '10 Nile Street, Cairo, Egypt';
    hit.phone = '01099887766';
    hit.latitude = 30.0445;
    hit.longitude = 31.2358;
    hit.provider = 'Google Places';
    AccountNurtureProposeService.testPlaceHits = new List<AccountMapsPlacesService.PlaceCandidate>{ hit };

    AccountNurtureProposeService.ProposalDraft draft = AccountNurtureProposeService.proposePlaces(acct);
    System.assertNotEquals(null, draft, 'Aligned place name should propose.');
    System.assertEquals('Places', draft.provider);
    Set<String> fields = fieldNames(draft);
    System.assert(!fields.contains('Name'), 'Account name must never be proposed.');
    System.assert(fields.contains('Maps_Place_Id__c'), fields);
    System.assert(fields.contains('Maps_Phone_Number__c'), 'Blank maps phone is a fill even when Phone matches.');
    System.assert(!fields.contains('Phone'), 'Matching Phone must not become a correction.');
    System.assertEquals('fill', kindOf(draft, 'Maps_Phone_Number__c'));

    AccountNurtureProposeService.testPlaceHits = new List<AccountMapsPlacesService.PlaceCandidate>();
    System.assertEquals(null, AccountNurtureProposeService.proposePlaces(acct));
  }

  @IsTest
  static void proposePlaces_rejectsWeakNameAndCorrectsSpecialtyStyleAddress() {
    Account acct = new Account(
      Name = 'Ahmed Hassan Clinic',
      BillingStreet = 'Old Street',
      BillingCity = 'Giza',
      BillingCountry = 'Egypt',
      Maps_Phone_Number__c = '01011112222',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    insert acct;
    acct = reload(acct.Id);

    AccountMapsPlacesService.PlaceCandidate weak = new AccountMapsPlacesService.PlaceCandidate();
    weak.name = 'Ahmed Ali Pharmacy';
    weak.placeId = 'places/weak';
    weak.address = '1 Other St, Cairo, Egypt';
    weak.phone = '01033334444';
    AccountNurtureProposeService.testPlaceHits = new List<AccountMapsPlacesService.PlaceCandidate>{ weak };
    System.assertEquals(
      null,
      AccountNurtureProposeService.proposePlaces(acct),
      'Shared given name alone must not propose.'
    );

    AccountMapsPlacesService.PlaceCandidate strong = new AccountMapsPlacesService.PlaceCandidate();
    strong.name = 'Ahmed Hassan Clinic';
    strong.placeId = 'places/strong';
    strong.address = '22 Pyramid Rd, Giza, Egypt';
    strong.phone = '01055556666';
    strong.latitude = 29.98;
    strong.longitude = 31.13;
    AccountNurtureProposeService.testPlaceHits = new List<AccountMapsPlacesService.PlaceCandidate>{ strong };

    AccountNurtureProposeService.ProposalDraft draft = AccountNurtureProposeService.proposePlaces(acct);
    System.assertNotEquals(null, draft);
    System.assertEquals('correction', kindOf(draft, 'BillingStreet'));
    System.assertEquals('correction', kindOf(draft, 'Maps_Phone_Number__c'));
    System.assertEquals('fill', kindOf(draft, 'Phone'), 'Blank Phone is a fill.');
    System.assert(!fieldNames(draft).contains('Name'));
  }

  @IsTest
  static void proposeVezeeta_specialtyFillAndDoctorPick() {
    Account doctor = personAccount('Ahmed Mohamed Quality', 'Cairo');
    if (doctor.IsPersonAccount != true) {
      // Org without person accounts cannot exercise Vezeeta nurture.
      return;
    }
    try {
      doctor.Specialty_1__c = 'Cardiology';
      update doctor;
      doctor = reload(doctor.Id);
    } catch (Exception ignore) {
      // Picklist may not allow Cardiology on this record type; fill path still covered below.
    }

    VezeetaDoctorService.DoctorHit hitA = new VezeetaDoctorService.DoctorHit();
    hitA.urlName = 'ahmed-mohamed-quality';
    hitA.name = 'Ahmed Mohamed Quality';
    hitA.specialty = 'Dermatology';
    hitA.city = 'Cairo';
    hitA.area = 'Dokki';
    hitA.profileUrl = 'https://www.vezeeta.com/en/dr/ahmed-mohamed-quality';

    VezeetaDoctorService.DoctorHit hitB = new VezeetaDoctorService.DoctorHit();
    hitB.urlName = 'ahmed-mohamed-quality-2';
    hitB.name = 'Ahmed Mohamed Quality';
    hitB.specialty = 'Orthopaedics';
    hitB.city = 'Cairo';
    hitB.area = 'Maadi';
    hitB.profileUrl = 'https://www.vezeeta.com/en/dr/ahmed-mohamed-quality-2';

    AccountNurtureProposeService.testVezeetaHits = new List<VezeetaDoctorService.DoctorHit>{ hitA, hitB };
    AccountNurtureProposeService.ProposalDraft pick = AccountNurtureProposeService.proposeVezeeta(doctor);
    System.assertNotEquals(null, pick);
    System.assertEquals('Needs Pick', pick.status);
    System.assertEquals(2, pick.doctorCandidates.size());

    VezeetaDoctorService.DoctorProfile profile = new VezeetaDoctorService.DoctorProfile();
    profile.urlName = 'ahmed-mohamed-quality';
    profile.name = 'Ahmed Mohamed Quality';
    profile.specialty1 = 'Dermatology';
    profile.specialtyLabel = 'Dermatology';
    profile.street = '5 Clinic St';
    profile.city = 'Dokki';
    profile.governorate = 'Cairo';
    profile.landmark = 'Quality Clinic';
    profile.profileUrl = hitA.profileUrl;
    profile.latitude = 30.04;
    profile.longitude = 31.21;
    AccountNurtureProposeService.testVezeetaProfiles = new Map<String, VezeetaDoctorService.DoctorProfile>{
      'ahmed-mohamed-quality' => profile,
      hitA.profileUrl => profile
    };

    AccountNurtureProposeService.testVezeetaHits = new List<VezeetaDoctorService.DoctorHit>{ hitA };
    AccountNurtureProposeService.ProposalDraft draft = AccountNurtureProposeService.proposeVezeeta(doctor);
    System.assertNotEquals(null, draft);
    System.assertEquals('Pending', draft.status);
    String specialtyKind = kindOf(draft, 'Specialty_1__c');
    System.assert(
      specialtyKind == 'fill' || specialtyKind == 'correction',
      'Specialty should be fill or correction, got ' + specialtyKind
    );
    if (String.isNotBlank(doctor.Specialty_1__c) && doctor.Specialty_1__c != 'Dermatology') {
      System.assertEquals('correction', specialtyKind);
    }
    System.assertEquals('fill', kindOf(draft, 'Website'));
    System.assert(!fieldNames(draft).contains('Name'));
  }

  @IsTest
  static void applyAndDismiss_writeOnlyAcceptedFields() {
    Account acct = new Account(
      Name = 'Apply Quality Pharmacy',
      BillingCity = 'Cairo',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    insert acct;

    Account_Quality_Run__c run = new Account_Quality_Run__c(
      Type__c = 'Nurture',
      Status__c = 'Ready',
      Proposal_Count__c = 1
    );
    insert run;

    Map<String, Object> payload = new Map<String, Object>{
      'fields' => new List<Object>{
        new Map<String, Object>{
          'field' => 'Maps_Phone_Number__c',
          'label' => 'Maps phone',
          'current' => null,
          'proposed' => '01077778888',
          'kind' => 'fill',
          'accepted' => true
        },
        new Map<String, Object>{
          'field' => 'Maps_Place_Id__c',
          'label' => 'Google place id',
          'current' => null,
          'proposed' => 'places/apply-1',
          'kind' => 'fill',
          'accepted' => true
        },
        new Map<String, Object>{
          'field' => 'BillingStreet',
          'label' => 'Street',
          'current' => null,
          'proposed' => 'Should Stay Blank',
          'kind' => 'fill',
          'accepted' => false
        }
      }
    };
    Account_Quality_Proposal__c applyRow = new Account_Quality_Proposal__c(
      Run__c = run.Id,
      Account__c = acct.Id,
      Provider__c = 'Places',
      Status__c = 'Pending',
      Decision__c = 'Apply',
      Score__c = 95,
      Summary__c = 'Test apply',
      Payload__c = JSON.serialize(payload)
    );
    Account_Quality_Proposal__c dismissRow = new Account_Quality_Proposal__c(
      Run__c = run.Id,
      Account__c = acct.Id,
      Provider__c = 'Places',
      Status__c = 'Pending',
      Score__c = 80,
      Summary__c = 'Test dismiss',
      Payload__c = JSON.serialize(payload)
    );
    insert new List<Account_Quality_Proposal__c>{ applyRow, dismissRow };

    AccountQualityReviewService.ApplyInput input = new AccountQualityReviewService.ApplyInput();
    input.proposalId = applyRow.Id;
    input.decision = 'Apply';
    input.acceptedFields = new List<String>{ 'Maps_Phone_Number__c', 'Maps_Place_Id__c' };

    Test.startTest();
    AccountQualityReviewService.ApplyResult applied = AccountQualityReviewService.applyProposals(
      new List<AccountQualityReviewService.ApplyInput>{ input }
    );
    AccountQualityReviewService.ApplyResult dismissed = AccountQualityReviewService.dismissProposals(
      new List<Id>{ dismissRow.Id }
    );
    Test.stopTest();

    System.assertEquals(1, applied.applied);
    System.assertEquals(1, dismissed.dismissed);
    Account refreshed = [
      SELECT Maps_Phone_Number__c, Maps_Place_Id__c, BillingStreet, Maps_Enrichment_Status__c
      FROM Account
      WHERE Id = :acct.Id
    ];
    System.assertEquals('01077778888', refreshed.Maps_Phone_Number__c);
    System.assertEquals('places/apply-1', refreshed.Maps_Place_Id__c);
    System.assertEquals(null, refreshed.BillingStreet);
    System.assertEquals('Found', refreshed.Maps_Enrichment_Status__c);
    System.assertEquals(
      'Dismissed',
      [SELECT Status__c FROM Account_Quality_Proposal__c WHERE Id = :dismissRow.Id].Status__c
    );
  }

  @IsTest
  static void duplicateScan_storesPairOnceAndMarkMerge() {
    Database.DMLOptions dml = new Database.DMLOptions();
    dml.DuplicateRuleHeader.allowSave = true;
    Account left = new Account(
      Name = 'Quality Twin Clinic',
      Phone = '01012121212',
      BillingCity = 'Cairo',
      BillingStreet = '1 Twin St',
      BillingLatitude = 30.05,
      BillingLongitude = 31.24,
      Account_Stage__c = AccountStageService.STAGE_DRAFT
    );
    Account right = new Account(
      Name = 'Quality Twin Clinic',
      Phone = '01012121212',
      BillingCity = 'Cairo',
      BillingStreet = '1 Twin Street',
      BillingLatitude = 30.0502,
      BillingLongitude = 31.2402,
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    Database.insert(new List<Account>{ left, right }, dml);

    Account_Quality_Run__c run = new Account_Quality_Run__c(
      Type__c = 'Duplicate',
      Status__c = 'Queued'
    );
    insert run;

    Test.startTest();
    Database.executeBatch(new AccountDuplicateScanBatch(run.Id), 10);
    Test.stopTest();

    List<Account_Quality_Proposal__c> pairs = [
      SELECT Id, Account__c, Match_Account__c, Pair_Key__c, Score__c, Can_Merge__c, Survivor_Account__c, Status__c
      FROM Account_Quality_Proposal__c
      WHERE Run__c = :run.Id AND Provider__c = 'Duplicate'
    ];
    System.assertEquals(1, pairs.size(), 'Pair must be stored once.');
    System.assert(pairs[0].Score__c >= 70, pairs[0].Score__c);
    System.assertEquals(true, pairs[0].Can_Merge__c);
    System.assertEquals(right.Id, pairs[0].Survivor_Account__c, 'Older non-draft should win by default.');

    AccountQualityReviewService.ApplyInput mark = new AccountQualityReviewService.ApplyInput();
    mark.proposalId = pairs[0].Id;
    mark.decision = 'Mark';
    mark.survivorAccountId = right.Id;
    AccountQualityReviewService.ApplyResult markResult = AccountQualityReviewService.applyProposals(
      new List<AccountQualityReviewService.ApplyInput>{ mark }
    );
    System.assertEquals(1, markResult.applied);
    Account marked = [SELECT Account_Stage__c, Duplicate_Of__c FROM Account WHERE Id = :left.Id];
    System.assertEquals(AccountStageService.STAGE_DUPLICATE, marked.Account_Stage__c);
    System.assertEquals(right.Id, marked.Duplicate_Of__c);
  }

  @IsTest
  static void mergeRejectsPersonVersusBusinessAndStartScanReturnsStatus() {
    Account business = new Account(Name = 'Business Quality Merge', Account_Stage__c = AccountStageService.STAGE_ACTIVE);
    insert business;
    Account person = personAccount('Person Quality Merge', 'Cairo');

    Account_Quality_Run__c run = new Account_Quality_Run__c(Type__c = 'Duplicate', Status__c = 'Ready');
    insert run;
    Account_Quality_Proposal__c row = new Account_Quality_Proposal__c(
      Run__c = run.Id,
      Account__c = person.Id,
      Match_Account__c = business.Id,
      Provider__c = 'Duplicate',
      Status__c = 'Pending',
      Score__c = 90,
      Can_Merge__c = false,
      Account_Is_Person__c = true,
      Match_Is_Person__c = false,
      Survivor_Account__c = business.Id,
      Summary__c = 'Person vs business'
    );
    insert row;

    AccountQualityReviewService.ApplyInput input = new AccountQualityReviewService.ApplyInput();
    input.proposalId = row.Id;
    input.decision = 'Merge';
    input.survivorAccountId = business.Id;
    AccountQualityReviewService.ApplyResult result = AccountQualityReviewService.applyProposals(
      new List<AccountQualityReviewService.ApplyInput>{ input }
    );
    System.assertEquals(0, result.applied);
    System.assertEquals(1, result.failed);
    System.assertEquals(
      'Failed',
      [SELECT Status__c FROM Account_Quality_Proposal__c WHERE Id = :row.Id].Status__c
    );

    AccountNurtureProposeService.testPlaceHits = new List<AccountMapsPlacesService.PlaceCandidate>();
    Test.startTest();
    AccountQualityReviewService.JobStatus started = AccountQualityReviewService.startDuplicateScan(
      'Pharmacy,Institution_HCO'
    );
    Test.stopTest();
    System.assertNotEquals(null, started.runId);
    System.assertNotEquals(null, started.jobId);
    AccountQualityReviewService.JobStatus polled = AccountQualityReviewService.getRunStatus(started.runId);
    System.assertEquals(started.runId, polled.runId);
    System.assertEquals('Ready', polled.status);
    List<AccountQualityReviewService.ProposalView> views = AccountQualityReviewService.listProposals(
      run.Id,
      70
    );
    System.assertEquals(1, views.size());
    System.assertEquals(0, AccountQualityReviewService.dismissProposals(new List<Id>()).dismissed);
    System.assertEquals(0, AccountQualityReviewService.applyProposals(new List<AccountQualityReviewService.ApplyInput>()).applied);
    System.assertEquals('None', AccountQualityReviewService.getLatestRun('Nurture').status);
  }

  @IsTest
  static void pickDoctorAndMergeAndNurtureStart_coverReviewPaths() {
    Account doctor = personAccount('Pick Doctor Quality', 'Cairo');
    if (doctor.IsPersonAccount != true) {
      return;
    }
    Account_Quality_Run__c run = new Account_Quality_Run__c(Type__c = 'Nurture', Status__c = 'Ready');
    insert run;

    VezeetaDoctorService.DoctorProfile profile = new VezeetaDoctorService.DoctorProfile();
    profile.urlName = 'pick-doctor-quality';
    profile.name = 'Pick Doctor Quality';
    profile.specialty1 = 'Dermatology';
    profile.street = '1 Pick St';
    profile.city = 'Cairo';
    profile.governorate = 'Cairo';
    profile.profileUrl = 'https://www.vezeeta.com/en/dr/pick-doctor-quality';
    AccountNurtureProposeService.testVezeetaProfiles = new Map<String, VezeetaDoctorService.DoctorProfile>{
      'pick-doctor-quality' => profile,
      profile.profileUrl => profile
    };

    Map<String, Object> payload = new Map<String, Object>{
      'fields' => new List<Object>(),
      'doctors' => new List<Object>{
        new Map<String, Object>{
          'urlName' => 'pick-doctor-quality',
          'name' => 'Pick Doctor Quality',
          'specialty' => 'Dermatology',
          'address' => 'Cairo',
          'profileUrl' => profile.profileUrl,
          'nameScore' => 100
        }
      }
    };
    Account_Quality_Proposal__c needsPick = new Account_Quality_Proposal__c(
      Run__c = run.Id,
      Account__c = doctor.Id,
      Provider__c = 'Vezeeta',
      Status__c = 'Needs Pick',
      Score__c = 95,
      Summary__c = 'Pick one',
      Payload__c = JSON.serialize(payload)
    );
    insert needsPick;

    AccountNurtureProposeService.testPlaceHits = new List<AccountMapsPlacesService.PlaceCandidate>();
    AccountNurtureProposeService.testVezeetaHits = new List<VezeetaDoctorService.DoctorHit>();

    Test.startTest();
    AccountQualityReviewService.ProposalView picked = AccountQualityReviewService.pickDoctor(
      needsPick.Id,
      'pick-doctor-quality'
    );
    AccountQualityReviewService.JobStatus nurture = AccountQualityReviewService.startNurtureScan(
      'PersonAccount',
      true
    );
    AccountQualityReviewService.JobStatus status = AccountQualityReviewService.getRunStatus(run.Id);
    Test.stopTest();

    System.assertEquals('Pending', picked.status);
    System.assertNotEquals(null, picked.fields);
    System.assertNotEquals(null, nurture.runId);
    System.assertEquals('Ready', status.status);

    Account keeper = new Account(Name = 'Merge Cover Keeper', Phone = '01044445555');
    Account loser = new Account(Name = 'Merge Cover Loser', Phone = '01044445555');
    insert new List<Account>{ keeper, loser };
    Account_Quality_Run__c dupRun = new Account_Quality_Run__c(Type__c = 'Duplicate', Status__c = 'Ready');
    insert dupRun;
    Account_Quality_Proposal__c mergeRow = new Account_Quality_Proposal__c(
      Run__c = dupRun.Id,
      Account__c = loser.Id,
      Match_Account__c = keeper.Id,
      Provider__c = 'Duplicate',
      Status__c = 'Pending',
      Score__c = 92,
      Can_Merge__c = true,
      Survivor_Account__c = keeper.Id,
      Summary__c = 'Merge cover'
    );
    insert mergeRow;
    AccountQualityReviewService.ApplyInput mergeInput = new AccountQualityReviewService.ApplyInput();
    mergeInput.proposalId = mergeRow.Id;
    mergeInput.decision = 'Merge';
    mergeInput.survivorAccountId = keeper.Id;
    AccountQualityReviewService.ApplyResult mergeResult = AccountQualityReviewService.applyProposals(
      new List<AccountQualityReviewService.ApplyInput>{ mergeInput }
    );
    System.assertEquals(1, mergeResult.applied);
    System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id = :loser.Id]);

    AccountQualityReviewService.ApplyInput nurtureApply = new AccountQualityReviewService.ApplyInput();
    nurtureApply.proposalId = needsPick.Id;
    nurtureApply.decision = 'Apply';
    nurtureApply.acceptedFields = new List<String>{ 'Website', 'BillingStreet' };
    AccountQualityReviewService.ApplyResult nurtureResult = AccountQualityReviewService.applyProposals(
      new List<AccountQualityReviewService.ApplyInput>{ nurtureApply }
    );
    System.assertEquals(
      1,
      nurtureResult.applied,
      nurtureResult.messages == null ? 'no messages' : String.join(nurtureResult.messages, ' | ')
    );
    Account refreshedDoctor = [SELECT Website, BillingStreet FROM Account WHERE Id = :doctor.Id];
    System.assertEquals(profile.profileUrl, refreshedDoctor.Website);
    System.assertEquals('1 Pick St', refreshedDoctor.BillingStreet);
  }

  @IsTest
  static void nurtureScan_persistsPlacesProposalWithoutCallouts() {
    Account acct = new Account(
      Name = 'Nurture Batch Pharmacy',
      BillingCity = 'Cairo',
      BillingStreet = '9 Batch St',
      BillingCountry = 'Egypt',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    insert acct;

    AccountMapsPlacesService.PlaceCandidate hit = new AccountMapsPlacesService.PlaceCandidate();
    hit.name = 'Nurture Batch Pharmacy';
    hit.placeId = 'places/batch-1';
    hit.address = '9 Batch Street, Cairo, Egypt';
    hit.phone = '01099990000';
    hit.latitude = 30.01;
    hit.longitude = 31.22;
    AccountNurtureProposeService.testPlaceHits = new List<AccountMapsPlacesService.PlaceCandidate>{ hit };
    AccountNurtureProposeService.testVezeetaHits = new List<VezeetaDoctorService.DoctorHit>();

    Account_Quality_Run__c run = new Account_Quality_Run__c(
      Type__c = 'Nurture',
      Status__c = 'Queued',
      Skip_Recently_Reviewed__c = false,
      Record_Type_Filter__c = ''
    );
    insert run;

    Test.startTest();
    Database.executeBatch(new AccountNurtureScanBatch(run.Id), 5);
    Test.stopTest();

    List<Account_Quality_Proposal__c> rows = [
      SELECT Provider__c, Status__c, Payload__c, External_Name__c
      FROM Account_Quality_Proposal__c
      WHERE Run__c = :run.Id
    ];
    System.assert(!rows.isEmpty(), 'Nurture batch should store at least one Places proposal.');
    System.assertEquals('Places', rows[0].Provider__c);
    System.assert(!rows[0].Payload__c.contains('"field":"Name"'));
    Account unchanged = [
      SELECT Maps_Phone_Number__c, Maps_Place_Id__c
      FROM Account
      WHERE Id = :acct.Id
    ];
    System.assertEquals(null, unchanged.Maps_Phone_Number__c, 'Scan must not write Account fields.');
    System.assertEquals(null, unchanged.Maps_Place_Id__c);
  }

  private static Account personAccount(String fullName, String city) {
    List<RecordType> rts = [
      SELECT Id, IsPersonType
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsPersonType = TRUE AND IsActive = TRUE
      LIMIT 1
    ];
    Account row = new Account(
      BillingCity = city,
      BillingCountry = 'Egypt',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    if (!rts.isEmpty()) {
      row.RecordTypeId = rts[0].Id;
      List<String> parts = fullName.trim().split('\\s+');
      if (parts.size() == 1) {
        row.LastName = parts[0];
      } else {
        row.FirstName = parts[0];
        List<String> rest = new List<String>();
        for (Integer i = 1; i < parts.size(); i++) {
          rest.add(parts[i]);
        }
        row.LastName = String.join(rest, ' ');
      }
    } else {
      row.Name = fullName;
    }
    insert row;
    return reload(row.Id);
  }

  private static Account reload(Id accountId) {
    return [
      SELECT
        Id,
        Name,
        IsPersonAccount,
        Phone,
        Website,
        BillingStreet,
        BillingCity,
        BillingCountry,
        BillingLatitude,
        BillingLongitude,
        PersonMobilePhone,
        Clinic_Phone__c,
        Maps_Phone_Number__c,
        Maps_Place_Id__c,
        WhatsApp_Number__c,
        Governorate__c,
        Landmark__c,
        Specialty_1__c,
        Specialty_2__c,
        Specialty_3__c,
        Brick__c,
        Brick_148__c,
        Brick_702__c,
        RecordType.DeveloperName,
        Account_Stage__c
      FROM Account
      WHERE Id = :accountId
    ];
  }

  private static Set<String> fieldNames(AccountNurtureProposeService.ProposalDraft draft) {
    Set<String> names = new Set<String>();
    if (draft == null || draft.fields == null) {
      return names;
    }
    for (AccountNurtureProposeService.FieldDiff diff : draft.fields) {
      names.add(diff.field);
    }
    return names;
  }

  private static String kindOf(AccountNurtureProposeService.ProposalDraft draft, String fieldName) {
    for (AccountNurtureProposeService.FieldDiff diff : draft.fields) {
      if (diff.field == fieldName) {
        return diff.kind;
      }
    }
    return null;
  }
}
