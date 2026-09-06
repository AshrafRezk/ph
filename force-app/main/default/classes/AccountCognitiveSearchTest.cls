@IsTest
private class AccountCognitiveSearchTest {
  private static final String AHMED_HAMZA = '\u0623\u062D\u0645\u062F';
  private static final String AHMED_ALEF = '\u0627\u062D\u0645\u062F';
  private static final String MOHAMED_AR = '\u0645\u062D\u0645\u062F';
  private static final String FATMA_AR = '\u0641\u0627\u0637\u0645\u0629';
  private static final String ABDELRAHMAN_AR = '\u0639\u0628\u062F\u0627\u0644\u0631\u062D\u0645\u0646';

  @IsTest
  static void dictionary_isSubstantialAndBidirectional() {
    System.assert(
      AccountNameDictionary.groupCount() >= 150,
      'Expected a real name library, not a handful of groups.'
    );
    System.assert(
      familyContains('Ahmed', new List<String>{ 'Ahmad', AHMED_HAMZA, AHMED_ALEF }),
      'Ahmed group should include Ahmad and both Arabic alef forms.'
    );
    System.assert(
      familyContains('Mohamed', new List<String>{ 'Muhammad', 'Mohammed', 'Mohammad', MOHAMED_AR }),
      'Mohamed group should include common Latin spellings and Arabic.'
    );
    System.assert(
      familyContains('Fatma', new List<String>{ 'Fatima', FATMA_AR }),
      'Fatma group should include Fatima and Arabic.'
    );
    System.assert(
      familyContains('Abdelrahman', new List<String>{ 'Abdul Rahman', 'Abd El Rahman', ABDELRAHMAN_AR }),
      'Abdelrahman should expand Abd/Abdel/Abdul spacing and Arabic.'
    );
    System.assert(
      familyContains('El Ezaby', new List<String>{ 'Ezaby', '\u0627\u0644\u0639\u0632\u0628\u064A', '\u0639\u0632\u0628\u064A' }),
      'Brand dictionary should include El Ezaby / Ezaby / ?????? / ????.'
    );
  }

  @IsTest
  static void foldName_ahmedHamzaAndAlefCollide() {
    System.assertEquals(
      AccountCognitiveSearch.foldName(AHMED_HAMZA),
      AccountCognitiveSearch.foldName(AHMED_ALEF)
    );
    System.assertEquals(
      AccountCognitiveSearch.foldName('\u0641\u0627\u0637\u0645\u0629'),
      AccountCognitiveSearch.foldName('\u0641\u0627\u0637\u0645\u0647')
    );
  }

  @IsTest
  static void expandToken_ahmedFamily_allFourQueriesShareArabicAndLatin() {
    List<String> queries = new List<String>{ 'Ahmed', 'Ahmad', AHMED_HAMZA, AHMED_ALEF };
    for (String query : queries) {
      List<String> expanded = AccountCognitiveSearch.expandToken(query);
      System.assert(
        containsFold(expanded, 'Ahmed') || containsFold(expanded, 'Ahmad'),
        query + ' should expand to a Latin Ahmed/Ahmad form: ' + expanded
      );
      System.assert(
        containsFold(expanded, AHMED_HAMZA) || containsFold(expanded, AHMED_ALEF),
        query + ' should expand to Arabic Ahmed: ' + expanded
      );
    }
  }

  @IsTest
  static void expandQuery_abdelrahmanCompounds() {
    List<String> expanded = AccountCognitiveSearch.expandQuery('Abd El Rahman');
    System.assert(
      containsFold(expanded, 'Abdelrahman') || containsFold(expanded, ABDELRAHMAN_AR),
      'Abd El Rahman should join into the Abdelrahman family: ' + expanded
    );
    List<String> fromArabic = AccountCognitiveSearch.expandToken(ABDELRAHMAN_AR);
    System.assert(
      containsFold(fromArabic, 'Abdelrahman') || containsFold(fromArabic, 'Abdulrahman'),
      'Arabic Abdelrahman should expand to Latin.'
    );
  }

  @IsTest
  static void unknownName_stillGetsSpellingAndPartialVariants() {
    List<String> expanded = AccountCognitiveSearch.expandToken('Nermeenn');
    System.assert(expanded.size() > 1, 'Unknown tokens should still get spelling variants.');
    System.assert(
      containsFold(expanded, 'nermeenn') || containsFold(expanded, 'nermenn'),
      'Doubled-consonant / e-a variants should be present.'
    );
  }

  @IsTest
  static void scoreAndHaystack_andTransliterationHelpers() {
    System.assert(AccountCognitiveSearch.scoreName('Ahmed', AHMED_HAMZA) >= 75);
    System.assertEquals(
      true,
      AccountCognitiveSearch.tokenMatchesHaystack(
        'Dr ' + AHMED_HAMZA + ' Cairo',
        null,
        'Ahmed'
      )
    );
    System.assertEquals(true, AccountCognitiveSearch.isNumericOrCode('12345'));
    System.assertEquals(
      AccountCognitiveSearch.foldName(AHMED_HAMZA),
      AccountCognitiveSearch.foldName(
        AccountCognitiveSearch.stripTashkeelAndTatweel('\u0623\u062D\u0652\u0645\u062F')
      )
    );
    System.assert(String.isNotBlank(AccountCognitiveSearch.latinToArabic('ahmed')));
    System.assert(String.isNotBlank(AccountCognitiveSearch.arabicToLatin(AHMED_ALEF)));
    List<String> orth = AccountCognitiveSearch.arabicOrthographyVariants(AHMED_HAMZA);
    System.assert(!orth.isEmpty());
  }

  @IsTest
  static void expandToken_coversDictionarySample() {
    Integer count = 0;
    for (List<String> nameGroup : AccountNameDictionary.allGroups()) {
      if (nameGroup == null || nameGroup.isEmpty()) {
        continue;
      }
      System.assert(!AccountCognitiveSearch.expandToken(nameGroup[0]).isEmpty());
      if (nameGroup.size() > 1) {
        AccountCognitiveSearch.expandQuery(nameGroup[1]);
      }
      count++;
      if (count >= 40) {
        break;
      }
    }
    System.assertEquals(
      false,
      AccountCognitiveSearch.tokenMatchesHaystack('Cairo Clinic', null, 'Ahmed')
    );
    System.assert(AccountCognitiveSearch.scoreName('Ahmed Ali', 'Ahmad Aly') > 0);
    System.assert(AccountCognitiveSearch.expandQuery('Abd El Rahman').size() > 1);
  }

  @IsTest
  static void ezaby_latinFindsArabicStemAndElEzaby() {
    String ezabyAr = '\u0639\u0632\u0628\u064A';
    String elEzabyAr = '\u0627\u0644\u0639\u0632\u0628\u064A';
    List<String> fromLatin = AccountCognitiveSearch.expandToken('ezaby');
    System.assert(
      containsStem(fromLatin, ezabyAr),
      'ezaby must expand to Arabic ???? for SOQL LIKE: ' + fromLatin
    );
    System.assert(
      containsStem(fromLatin, elEzabyAr),
      'ezaby must expand to ??????: ' + fromLatin
    );
    System.assert(
      containsStem(fromLatin, 'Ezaby') || containsStem(fromLatin, 'El Ezaby'),
      'ezaby must keep Latin Ezaby / El Ezaby forms: ' + fromLatin
    );
    System.assertEquals(
      true,
      AccountCognitiveSearch.tokenMatchesHaystack(elEzabyAr, null, 'ezaby'),
      'ezaby must match haystack ??????'
    );
    System.assertEquals(
      true,
      AccountCognitiveSearch.tokenMatchesHaystack('El Ezaby Pharmacy', null, 'ezaby')
    );
    System.assert(AccountCognitiveSearch.scoreName('ezaby', elEzabyAr) >= 75);
  }

  @IsTest
  static void ezaby_arabicFindsLatinBrand() {
    String ezabyAr = '\u0639\u0632\u0628\u064A';
    String elEzabyAr = '\u0627\u0644\u0639\u0632\u0628\u064A';
    List<String> fromArabic = AccountCognitiveSearch.expandToken(ezabyAr);
    System.assert(
      containsStem(fromArabic, 'ezaby') || containsStem(fromArabic, 'El Ezaby'),
      '???? must expand to Latin ezaby / El Ezaby: ' + fromArabic
    );
    System.assertEquals(
      true,
      AccountCognitiveSearch.tokenMatchesHaystack('El Ezaby', null, ezabyAr)
    );
    System.assertEquals(
      true,
      AccountCognitiveSearch.tokenMatchesHaystack(elEzabyAr, null, ezabyAr)
    );
  }

  @IsTest
  static void unknownToken_stillTransliteratesAinAndGhain() {
    List<String> ghorab = AccountCognitiveSearch.expandToken('ghorab');
    System.assert(
      containsStem(ghorab, '\u063A'),
      'Unknown ghorab should still map gh ? ?: ' + ghorab
    );
    String arabic = AccountCognitiveSearch.latinToArabic('ezaby');
    System.assert(
      arabic != null && arabic.contains('\u0639'),
      'Preferred ezaby transliteration must include ain ?, got: ' + arabic
    );
  }

  @IsTest
  static void expandTokenForFieldSearch_includesPhoneAndSpecialtyForms() {
    List<String> phoneVariants = AccountCognitiveSearch.expandTokenForFieldSearch('01012345678');
    System.assert(
      containsFold(phoneVariants, '1012345678') || containsFold(phoneVariants, '+201012345678'),
      'Phone search variants should include normalized Egypt digits: ' + phoneVariants
    );
    List<String> specialtyVariants = AccountCognitiveSearch.expandTokenForFieldSearch('Cardiology');
    System.assert(
      containsFold(specialtyVariants, 'Cardiology'),
      'Specialty token should stay searchable: ' + specialtyVariants
    );
  }

  @IsTest
  static void searchMasterList_ezabyLatinFindsArabicAndElEzaby() {
    Id recordTypeId = resolveBusinessAccountRecordTypeId();
    String arabicName = '\u0627\u0644\u0639\u0632\u0628\u064A';
    Account arabic = new Account(
      Name = arabicName,
      RecordTypeId = recordTypeId,
      BillingCity = 'Cairo',
      BillingStreet = 'Tahrir'
    );
    Account latin = new Account(
      Name = 'El Ezaby',
      RecordTypeId = recordTypeId,
      BillingCity = 'Cairo',
      BillingStreet = 'Tahrir'
    );
    Database.insert(new List<Account>{ arabic, latin }, AccessLevel.SYSTEM_MODE);

    System.assert(
      masterSearchFinds(arabic.Id, 'ezaby', recordTypeId),
      'Latin ezaby must find account named ??????'
    );
    System.assert(
      masterSearchFinds(latin.Id, 'ezaby', recordTypeId),
      'Latin ezaby must find account named El Ezaby'
    );
    System.assert(
      masterSearchFinds(arabic.Id, '\u0639\u0632\u0628\u064A', recordTypeId),
      'Arabic ???? must find ??????'
    );
    System.assert(
      masterSearchFinds(latin.Id, '\u0639\u0632\u0628\u064A', recordTypeId),
      'Arabic ???? must find El Ezaby'
    );
  }

  private static Id resolveBusinessAccountRecordTypeId() {
    List<RecordType> types = [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsActive = TRUE
        AND DeveloperName IN ('Pharmacy', 'Institution_HCO', 'Medical_Professional_HCP')
      LIMIT 10
    ];
    System.assert(!types.isEmpty(), 'Expected a business Account record type for master search.');
    return types[0].Id;
  }

  private static Boolean masterSearchFinds(Id accountId, String query, Id recordTypeId) {
    List<AccountsTabController.MasterSearchRow> rows =
      AccountsTabController.searchMasterList(query, recordTypeId, false);
    for (AccountsTabController.MasterSearchRow row : rows) {
      if (row.accountId == accountId) {
        return true;
      }
    }
    rows = AccountsTabController.searchMasterList(query, recordTypeId, true);
    for (AccountsTabController.MasterSearchRow row : rows) {
      if (row.accountId == accountId) {
        return true;
      }
    }
    return false;
  }

  private static Boolean familyContains(String canonical, List<String> required) {
    for (List<String> nameGroup : AccountNameDictionary.allGroups()) {
      if (nameGroup.isEmpty() || nameGroup[0] != canonical) {
        continue;
      }
      for (String need : required) {
        if (!containsFold(nameGroup, need)) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  private static Boolean containsFold(List<String> values, String expected) {
    String want = AccountCognitiveSearch.foldCompact(expected);
    for (String value : values) {
      if (AccountCognitiveSearch.foldCompact(value) == want) {
        return true;
      }
    }
    return false;
  }

  private static Boolean containsStem(List<String> values, String expected) {
    String want = AccountCognitiveSearch.foldCompact(expected);
    if (String.isBlank(want)) {
      return false;
    }
    for (String value : values) {
      String got = AccountCognitiveSearch.foldCompact(value);
      if (got == want || got.contains(want) || (want.contains(got) && got.length() >= 3)) {
        return true;
      }
    }
    return false;
  }
}
