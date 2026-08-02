@IsTest(SeeAllData=true)
private class FatmaAccountsAccessTest {
  private static final String FATMA_USERNAME = 'diabetes.mr@pharma.demo';

  @IsTest
  static void fieldRepSeesTerritoryAccounts() {
    List<User> users = [
      SELECT Id
      FROM User
      WHERE Username = :FATMA_USERNAME AND IsActive = TRUE
      LIMIT 1
    ];
    if (users.isEmpty()) {
      return;
    }

    System.runAs(users[0]) {
      AccountsTabController.AccountsTabPage accountsTab =
        AccountsTabController.getAccountsTabPage(
          'both',
          null,
          'All',
          null,
          null,
          'asc',
          0,
          10,
          Date.today().toStartOfMonth(),
          null,
          null
        );

      FieldPlannerController.AccountPageResult planner =
        FieldPlannerController.searchAccountsPage(
          null,
          'All',
          null,
          null,
          null,
          0,
          25,
          null
        );

      System.assert(
        accountsTab.totalCount > 0,
        'Accounts tab should list territory accounts for field rep.'
      );
      System.assert(
        planner.totalCount > 0,
        'Planner should list territory accounts for field rep.'
      );
    }
  }
}
