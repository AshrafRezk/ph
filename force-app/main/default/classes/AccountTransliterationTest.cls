@IsTest
private class AccountTransliterationTest {
  private static final String EZABY_AR = '\u0639\u0632\u0628\u064A';
  private static final String EL_EZABY_AR = '\u0627\u0644\u0639\u0632\u0628\u064A';

  @IsTest
  static void latinEzaby_emitsAinStemAndArticle() {
    List<String> vars = AccountTransliteration.latinToArabicVariants('ezaby');
    System.assert(listContains(vars, EZABY_AR), 'ezaby ? ????, got ' + vars);
    System.assert(listContains(vars, EL_EZABY_AR), 'ezaby ? ??????, got ' + vars);
    System.assertEquals(EZABY_AR, AccountTransliteration.preferredArabic('ezaby'));
  }

  @IsTest
  static void arabicEzaby_emitsLatinAndElPrefixes() {
    List<String> vars = AccountTransliteration.arabicToLatinVariants(EL_EZABY_AR);
    System.assert(
      listContainsFold(vars, 'ezaby') || listContainsFold(vars, 'El Ezaby'),
      '?????? ? ezaby / El Ezaby, got ' + vars
    );
    System.assert(listContains(vars, EZABY_AR) || listContains(vars, EL_EZABY_AR));
  }

  @IsTest
  static void articleFoldingAndPhoneticKey() {
    System.assertEquals(
      AccountTransliteration.phoneticKey('ezaby'),
      AccountTransliteration.phoneticKey(EL_EZABY_AR)
    );
    System.assertEquals(
      AccountTransliteration.foldNoArticle('elezaby'),
      AccountTransliteration.foldNoArticle('ezaby')
    );
    System.assertEquals(
      true,
      AccountTransliteration.phoneticMatch('ezaby', EL_EZABY_AR)
    );
    System.assertEquals(
      true,
      AccountTransliteration.phoneticMatch(EZABY_AR, 'El Ezaby')
    );
  }

  @IsTest
  static void threeAsAin_andDigraphs() {
    System.assert(
      listContains(AccountTransliteration.latinToArabicVariants('3zaby'), EZABY_AR),
      '3zaby (3 = ?) should produce ????'
    );
    List<String> kh = AccountTransliteration.latinToArabicVariants('khaled');
    Boolean hasKha = false;
    for (String v : kh) {
      if (v != null && v.contains('\u062E')) {
        hasKha = true;
      }
    }
    System.assert(hasKha, 'kh should map to ?: ' + kh);
  }

  private static Boolean listContains(List<String> values, String expected) {
    return values != null && values.contains(expected);
  }

  private static Boolean listContainsFold(List<String> values, String expected) {
    String want = AccountCognitiveSearch.foldCompact(expected);
    for (String value : values) {
      if (AccountCognitiveSearch.foldCompact(value) == want) {
        return true;
      }
    }
    return false;
  }
}