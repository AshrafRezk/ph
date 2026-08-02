public class AccountPhoneDefaults {
  public static final String DEMO_PHONE = '+201204680466';

  public static void applyDemoPhone(Account acct) {
    if (acct == null) {
      return;
    }
    acct.Phone = DEMO_PHONE;
  }

  public static void applyDemoPhoneForPerson(Account acct) {
    applyDemoPhone(acct);
    if (Schema.SObjectType.Account.fields.getMap().containsKey('PersonMobilePhone')) {
      acct.PersonMobilePhone = DEMO_PHONE;
    }
  }
}
