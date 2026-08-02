public with sharing class MedicalSpecialtyDataFix implements Database.Batchable<SObject> {
  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator([
      SELECT Id, Specialty_1__c, Specialty_2__c, Specialty_3__c, Specialty_4__c
      FROM Account
      WHERE
        Specialty_1__c != NULL
        OR Specialty_2__c != NULL
        OR Specialty_3__c != NULL
        OR Specialty_4__c != NULL
    ]);
  }

  public void execute(Database.BatchableContext context, List<Account> scope) {
    List<Account> updates = new List<Account>();

    for (Account account : scope) {
      Account updateRow = new Account(Id = account.Id);
      Boolean changed = false;

      changed |= applyNormalizedValue(updateRow, account, 'Specialty_1__c');
      changed |= applyNormalizedValue(updateRow, account, 'Specialty_2__c');
      changed |= applyNormalizedValue(updateRow, account, 'Specialty_3__c');
      changed |= applyNormalizedValue(updateRow, account, 'Specialty_4__c');

      if (changed) {
        updates.add(updateRow);
      }
    }

    if (!updates.isEmpty()) {
      update updates;
    }
  }

  public void finish(Database.BatchableContext context) {
  }

  public static Id runBatch() {
    return Database.executeBatch(new MedicalSpecialtyDataFix(), 200);
  }

  private static Boolean applyNormalizedValue(
    Account updateRow,
    Account source,
    String fieldApiName
  ) {
    String currentValue = (String) source.get(fieldApiName);
    if (String.isBlank(currentValue)) {
      return false;
    }

    String normalizedValue = MedicalSpecialtyPicklist.resolveApiValue(currentValue);
    if (normalizedValue == currentValue) {
      return false;
    }

    updateRow.put(fieldApiName, normalizedValue);
    return true;
  }
}
