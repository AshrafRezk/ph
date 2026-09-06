@IsTest
private class AccountCreateQualityServiceTest {
  @IsTest
  static void baselineScoreWhenRequiredsMet_pharmacy() {
    AccountsTabController.WizardCreateInput input = requiredPharmacyInput();

    Test.startTest();
    AccountCreateQualityService.QualityScore score = AccountCreateQualityService.evaluate(input);
    Test.stopTest();

    System.assertEquals(true, score.canSave);
    System.assertEquals(AccountCreateQualityService.BASELINE_SCORE, score.score);
    System.assertEquals('Fair', score.label);
    System.assertEquals(1, score.uniquePhoneCount);
    System.assertEquals(false, score.duplicatePhones);
    System.assert(score.extrasToImprove.size() > 0, 'Extras that raise the score should be listed.');
  }

  @IsTest
  static void extraUniquePhonesAndEmailRaiseScore() {
    AccountsTabController.WizardCreateInput input = requiredPharmacyInput();
    input.whatsappNumber = '01011111111';
    input.phone = '01022222222';
    input.clinicPhone = '02 3333 3333';
    input.email = 'quality@example.com';

    AccountCreateQualityService.QualityScore score = AccountCreateQualityService.evaluate(input);

    System.assertEquals(true, score.canSave);
    Integer expected =
      AccountCreateQualityService.BASELINE_SCORE +
      AccountCreateQualityService.BONUS_PHONE_2 +
      AccountCreateQualityService.BONUS_PHONE_3 +
      AccountCreateQualityService.BONUS_EMAIL;
    System.assertEquals(expected, score.score);
    System.assertEquals('Excellent', score.label);
    System.assertEquals(3, score.uniquePhoneCount);
  }

  @IsTest
  static void duplicatePhonesDoNotAddBonus() {
    AccountsTabController.WizardCreateInput input = requiredPharmacyInput();
    input.whatsappNumber = '+201011111111';
    input.phone = '01011111111';
    input.clinicPhone = '00201011111111';
    input.email = 'dup@example.com';

    AccountCreateQualityService.QualityScore score = AccountCreateQualityService.evaluate(input);

    System.assertEquals(true, score.duplicatePhones);
    System.assertEquals(1, score.uniquePhoneCount);
    Integer expected =
      AccountCreateQualityService.BASELINE_SCORE + AccountCreateQualityService.BONUS_EMAIL;
    System.assertEquals(expected, score.score, 'Duplicate numbers must not count as extra channels.');
    System.assert(String.isNotBlank(score.duplicatePhoneMessage));
  }

  @IsTest
  static void hcpSecondAndThirdSpecialtyRaiseScore() {
    Id hcpTypeId = resolveRecordTypeId(
      new Set<String>{ 'PersonAccount', 'SDO_PersonAccounts', 'Medical_Professional_HCP' }
    );
    AccountsTabController.WizardCreateInput input = requiredPharmacyInput();
    input.recordTypeId = hcpTypeId;
    input.name = 'Mona Hassan';
    input.lastName = 'Hassan';
    input.firstName = 'Mona';
    input.pharmacyType = null;
    input.specialty1 = 'Cardiology';
    input.specialty2 = 'Internal Medicine';
    input.specialty3 = 'Endocrinology';

    AccountCreateQualityService.QualityScore score = AccountCreateQualityService.evaluate(input);

    System.assertEquals(true, score.canSave, String.join(score.missingRequired, ', '));
    Integer expected =
      AccountCreateQualityService.BASELINE_SCORE +
      AccountCreateQualityService.BONUS_SPECIALTY_2 +
      AccountCreateQualityService.BONUS_SPECIALTY_3;
    System.assertEquals(expected, score.score);
  }

  @IsTest
  static void missingRequiredsBlockSave() {
    AccountsTabController.WizardCreateInput input = new AccountsTabController.WizardCreateInput();
    input.recordTypeId = resolveRecordTypeId(new Set<String>{ 'Pharmacy', 'Institution_HCO' });

    AccountCreateQualityService.QualityScore score = AccountCreateQualityService.evaluate(input);

    System.assertEquals(false, score.canSave);
    System.assert(score.score < AccountCreateQualityService.BASELINE_SCORE);
    Boolean threw = false;
    try {
      AccountCreateQualityService.assertCanSave(input);
    } catch (AuraHandledException ex) {
      threw = true;
    }
    System.assertEquals(true, threw, 'Save must be blocked until requireds are met.');
  }

  @IsTest
  static void egyptPhoneNormalizationAndQueryDetection() {
    System.assertEquals('+201012345678', AccountCreateQualityService.normalizeEgyptPhone('01012345678'));
    System.assertEquals('+201012345678', AccountCreateQualityService.normalizeEgyptPhone('+20 101 234 5678'));
    System.assertEquals('+201012345678', AccountCreateQualityService.normalizeEgyptPhone('00201012345678'));
    System.assertEquals(true, AccountCreateQualityService.looksLikePhoneQuery('01012345678'));
    System.assertEquals(true, AccountCreateQualityService.looksLikePhoneQuery('+20-101-234-5678'));
    System.assertEquals(false, AccountCreateQualityService.looksLikePhoneQuery('El Ezaby'));
    System.assertEquals(
      true,
      AccountCreateQualityService.phonesMatch('01012345678', '+201012345678')
    );
    List<String> queries = AccountCreateQualityService.egyptPhoneSearchQueries('01012345678');
    System.assert(queries.contains('+201012345678'));
    System.assert(queries.contains('01012345678'));
  }

  private static AccountsTabController.WizardCreateInput requiredPharmacyInput() {
    Id recordTypeId = resolveRecordTypeId(new Set<String>{ 'Pharmacy', 'Institution_HCO' });
    AccountsTabController.WizardCreateInput input = new AccountsTabController.WizardCreateInput();
    input.recordTypeId = recordTypeId;
    input.name = 'Quality Pharmacy';
    input.pharmacyType = 'Retail';
    input.institutionType = 'Hospital';
    input.phone = '01099999999';
    input.street = '12 Tahrir Street';
    input.city = 'Cairo';
    input.building = 'Tower A';
    input.governorate = 'Cairo';
    input.landmark = 'Near the museum';
    input.latitude = 30.0444;
    input.longitude = 31.2357;
    input.brick148Id = fakeId(Brick__c.SObjectType);
    input.brick702Id = fakeId(Brick__c.SObjectType);
    return input;
  }

  private static Id resolveRecordTypeId(Set<String> devNames) {
    List<RecordType> types = [
      SELECT Id
      FROM RecordType
      WHERE SobjectType = 'Account' AND IsActive = TRUE AND DeveloperName IN :devNames
      LIMIT 1
    ];
    System.assert(!types.isEmpty(), 'Expected an account record type.');
    return types[0].Id;
  }

  private static Id fakeId(Schema.SObjectType sot) {
    String prefix = sot.getDescribe().getKeyPrefix();
    return (Id) (prefix + '000000000001');
  }
}
