public without sharing class AccountPhoneBackfill {
  private static final Integer BATCH_SIZE = 200;

  public class BackfillResult {
    public Integer updatedCount = 0;
    public Integer failedCount = 0;
    public String message;
  }

  public static BackfillResult backfillAllAccounts() {
    BackfillResult result = new BackfillResult();
    Boolean hasPersonMobile = Schema.SObjectType.Account.fields.getMap()
      .containsKey('PersonMobilePhone');

    List<Account> updates = new List<Account>();
    for (Account acct : [
      SELECT Id, IsPersonAccount
      FROM Account
      WITH SYSTEM_MODE
    ]) {
      Account patch = new Account(Id = acct.Id);
      patch.Phone = AccountPhoneDefaults.DEMO_PHONE;
      if (hasPersonMobile && acct.IsPersonAccount) {
        patch.PersonMobilePhone = AccountPhoneDefaults.DEMO_PHONE;
      }
      updates.add(patch);
    }

    for (Integer start = 0; start < updates.size(); start += BATCH_SIZE) {
      Integer endIdx = Math.min(start + BATCH_SIZE, updates.size());
      List<Account> batch = new List<Account>();
      for (Integer i = start; i < endIdx; i++) {
        batch.add(updates[i]);
      }
      Database.SaveResult[] results = Database.update(batch, false, AccessLevel.SYSTEM_MODE);
      for (Database.SaveResult sr : results) {
        if (sr.isSuccess()) {
          result.updatedCount++;
        } else {
          result.failedCount++;
        }
      }
    }

    result.message =
      'Updated phone on ' +
      result.updatedCount +
      ' accounts (' +
      result.failedCount +
      ' failed).';
    return result;
  }
}
