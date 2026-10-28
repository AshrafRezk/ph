@IsTest
private class AccountDuplicateCheckServiceTest {
  @IsTest
  static void findDuplicates_scoresNameMobileTypeAndLocation() {
    Database.DMLOptions dml = new Database.DMLOptions();
    dml.DuplicateRuleHeader.allowSave = true;
    Account source = new Account(
      Name = 'Duplicate Check Clinic',
      Phone = '01099887766',
      BillingCity = 'Cairo',
      BillingStreet = '12 Nile St',
      BillingLatitude = 30.0444,
      BillingLongitude = 31.2357,
      Account_Stage__c = AccountStageService.STAGE_DRAFT
    );
    Account twin = new Account(
      Name = 'Duplicate Check Clinic',
      Phone = '01099887766',
      BillingCity = 'Cairo',
      BillingStreet = '12 Nile Street',
      BillingLatitude = 30.0450,
      BillingLongitude = 31.2360,
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    Account other = new Account(
      Name = 'Aswan Desert Pharmacy',
      Phone = '01100000011',
      BillingCity = 'Aswan',
      BillingStreet = '1 Corniche',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    Database.insert(new List<Account>{ source, twin, other }, dml);

    Test.startTest();
    AccountDuplicateCheckService.CheckResult result = AccountDuplicateCheckService.findAccountDuplicates(source.Id);
    Test.stopTest();

    System.assertEquals(true, result.hasMatches, result.headline);
    System.assert(result.highestPercent >= 70, 'Expected a high duplicate possibility, got ' + result.highestPercent);
    System.assertEquals(twin.Id, result.matches[0].accountId);
    System.assert(result.headline.contains(String.valueOf(result.highestPercent)));
    Boolean sawOther = false;
    for (AccountDuplicateCheckService.MatchRow match : result.matches) {
      if (match.accountId == other.Id) {
        sawOther = true;
      }
      System.assertEquals(4, match.factors.size());
    }
    System.assertEquals(false, sawOther);
  }

  @IsTest
  static void reportDuplicate_linksTheOriginalAccount() {
    Account source = new Account(Name = 'Report Source Clinic', Account_Stage__c = AccountStageService.STAGE_DRAFT);
    Account master = new Account(Name = 'Report Master Clinic', Account_Stage__c = AccountStageService.STAGE_ACTIVE);
    insert new List<Account>{ source, master };

    Test.startTest();
    AccountDuplicateCheckService.ActionResult result = AccountDuplicateCheckService.reportAccountDuplicate(
      source.Id,
      master.Id
    );
    Test.stopTest();

    Account refreshed = [
      SELECT Account_Stage__c, Duplicate_Of__c
      FROM Account
      WHERE Id = :source.Id
    ];
    System.assertEquals(true, result.ok);
    System.assertEquals(AccountStageService.STAGE_DUPLICATE, refreshed.Account_Stage__c);
    System.assertEquals(master.Id, refreshed.Duplicate_Of__c);
    AccountDuplicateCheckService.CheckResult check = AccountDuplicateCheckService.findAccountDuplicates(source.Id);
    System.assertEquals(false, check.canReport);
    System.assertEquals('Report Master Clinic', check.reportedOfName);
  }

  @IsTest
  static void mergeAccounts_keepsTheChosenSurvivor() {
    Account keeper = new Account(Name = 'Merge Keeper Clinic', Phone = '01011112222');
    Account loser = new Account(Name = 'Merge Loser Clinic', Phone = '01011112222');
    insert new List<Account>{ keeper, loser };

    Test.startTest();
    AccountDuplicateCheckService.ActionResult result = AccountDuplicateCheckService.mergeAccountDuplicates(
      keeper.Id,
      loser.Id
    );
    Test.stopTest();

    System.assertEquals(true, result.ok);
    System.assertEquals(keeper.Id, result.survivorId);
    System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Id = :keeper.Id]);
    System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id = :loser.Id]);
  }

  @IsTest
  static void findDuplicates_matchesArabicSpellingAndLatinTransliteration() {
    Database.DMLOptions dml = new Database.DMLOptions();
    dml.DuplicateRuleHeader.allowSave = true;
    String hamza = '\u0623\u062D\u0645\u062F';
    String alef = '\u0627\u062D\u0645\u062F';
    String mohamed = '\u0645\u062D\u0645\u062F';
    Account source = new Account(
      Name = hamza + ' ' + mohamed,
      BillingCity = 'Giza',
      Account_Stage__c = AccountStageService.STAGE_DRAFT
    );
    Account latin = new Account(
      Name = 'Ahmed Mohamed',
      BillingCity = 'Alexandria',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    Account spelling = new Account(
      Name = 'Ahmad Mohammad',
      BillingCity = 'Aswan',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    Account bareAlef = new Account(
      Name = alef + ' ' + mohamed,
      BillingCity = 'Cairo',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    Account differentPerson = new Account(
      Name = 'Hassan Mahmoud',
      BillingCity = 'Giza',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    Account sharedGivenName = new Account(
      Name = 'Ahmed Ali',
      BillingCity = 'Giza',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    Account fatmaArabic = new Account(
      Name = '\u0641\u0627\u0637\u0645\u0629 \u0639\u0644\u064A',
      BillingCity = 'Tanta',
      Account_Stage__c = AccountStageService.STAGE_DRAFT
    );
    Account fatmaLatin = new Account(
      Name = 'Fatima Aly',
      BillingCity = 'Mansoura',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    Account aymanArabic = new Account(
      Name = '\u0623\u064A\u0645\u0646 \u0648\u0647\u0628\u0629',
      BillingCity = 'Cairo',
      Account_Stage__c = AccountStageService.STAGE_DRAFT
    );
    Account aymanLatin = new Account(
      Name = 'Ayman Wahba',
      BillingCity = 'Giza',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    Account unrelated = new Account(
      Name = 'Karim Fathy Pharmacy',
      BillingCity = 'Cairo',
      Account_Stage__c = AccountStageService.STAGE_ACTIVE
    );
    Database.insert(
      new List<Account>{
        source,
        latin,
        spelling,
        bareAlef,
        differentPerson,
        sharedGivenName,
        fatmaArabic,
        fatmaLatin,
        aymanArabic,
        aymanLatin,
        unrelated
      },
      dml
    );

    Test.startTest();
    AccountDuplicateCheckService.CheckResult ahmed = AccountDuplicateCheckService.findAccountDuplicates(source.Id);
    AccountDuplicateCheckService.CheckResult fatma = AccountDuplicateCheckService.findAccountDuplicates(fatmaArabic.Id);
    AccountDuplicateCheckService.CheckResult ayman = AccountDuplicateCheckService.findAccountDuplicates(aymanArabic.Id);
    Test.stopTest();

    Set<Id> ahmedIds = matchIds(ahmed);
    System.assert(ahmedIds.contains(latin.Id), 'Ahmed Mohamed missing. ' + describeMatches(ahmed));
    System.assert(ahmedIds.contains(spelling.Id), 'Ahmad Mohammad missing. ' + describeMatches(ahmed));
    System.assert(ahmedIds.contains(bareAlef.Id), 'Bare-alef twin missing. ' + describeMatches(ahmed));
    System.assert(!ahmedIds.contains(differentPerson.Id), 'Hassan Mahmoud should stay out. ' + describeMatches(ahmed));
    System.assert(!ahmedIds.contains(sharedGivenName.Id), 'Ahmed Ali should stay out. ' + describeMatches(ahmed));

    System.assert(matchIds(fatma).contains(fatmaLatin.Id), 'Fatima Aly missing. ' + describeMatches(fatma));
    System.assert(matchIds(ayman).contains(aymanLatin.Id), 'Ayman Wahba missing. ' + describeMatches(ayman));
    System.assert(!matchIds(ayman).contains(unrelated.Id), 'Unrelated pharmacy should stay out. ' + describeMatches(ayman));
  }

  private static Set<Id> matchIds(AccountDuplicateCheckService.CheckResult result) {
    Set<Id> ids = new Set<Id>();
    if (result == null || result.matches == null) {
      return ids;
    }
    for (AccountDuplicateCheckService.MatchRow match : result.matches) {
      ids.add(match.accountId);
    }
    return ids;
  }

  private static String describeMatches(AccountDuplicateCheckService.CheckResult result) {
    List<String> names = new List<String>();
    if (result != null && result.matches != null) {
      for (AccountDuplicateCheckService.MatchRow match : result.matches) {
        names.add(match.accountName + ' ' + match.percent);
      }
    }
    return (result == null ? 'null' : result.headline) + ' [' + String.join(names, ', ') + ']';
  }

  @IsTest
  static void mergeAccounts_rejectsTheSameAccount() {
    Account business = new Account(Name = 'Business Only Clinic');
    insert business;
    Boolean failed = false;
    try {
      AccountDuplicateCheckService.mergeAccountDuplicates(business.Id, business.Id);
    } catch (AuraHandledException ex) {
      failed = true;
    }
    System.assertEquals(true, failed);
  }
}