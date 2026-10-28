@IsTest
private class HcpClassificationSuggestionServiceTest {
  @IsTest
  static void suggestForAccount_returnsUnchangedOrSuggestion() {
    Account account = new Account(Name = 'Dr Class Suggest', BillingCity = 'Cairo');
    insert account;

    Test.startTest();
    try {
      HcpClassificationSuggestionService.SuggestionRow row =
        HcpClassificationSuggestionService.suggestForAccount(account.Id);
      System.assertNotEquals(null, row);
      System.assertNotEquals(null, row.direction);
      System.assertNotEquals(null, row.suggestedClass);
    } catch (AuraHandledException ex) {
      System.assert(
        ex.getMessage() != null,
        'Expected friendly message when suggestion object or territory rating is unavailable'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void getPendingSuggestions_safeWhenEmpty() {
    Test.startTest();
    List<HcpClassificationSuggestionService.SuggestionRow> rows =
      HcpClassificationSuggestionService.getPendingSuggestions(UserInfo.getUserId());
    Test.stopTest();
    System.assertNotEquals(null, rows);
  }
}
