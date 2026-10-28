/**
 * Doctor specialty merger scan, two passes:
 *  1. this batch reads every doctor once and groups them by folded name
 *     (أحمد / احمد, ة / ه …), keeping only names whose doctors have different specialties;
 *  2. DoctorSpecialtyPairScorer scores each group with
 *     DoctorSpecialtyMergeService.score and stores pairs at or above MIN_SCORE as proposals.
 * Writes no Account changes.
 */
public without sharing class DoctorSpecialtyScanBatch implements Database.Batchable<SObject>, Database.Stateful {
  private Id runId;
  private Integer scanned = 0;
  // folded name -> "id|specialties" entries
  private Map<String, List<String>> byName = new Map<String, List<String>>();

  public DoctorSpecialtyScanBatch(Id runId) {
    this.runId = runId;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    update new Account_Quality_Run__c(Id = runId, Status__c = 'Running');
    return Database.getQueryLocator([
      SELECT Id, Name, Specialty_1__c, Specialty_2__c, Specialty_3__c, Specialty_4__c
      FROM Account
      WHERE IsPersonAccount = true AND Specialty_1__c != null
        AND (Account_Stage__c = null OR Account_Stage__c != 'Duplicate')
      ORDER BY Id
    ]);
  }

  public void execute(Database.BatchableContext bc, List<Account> scope) {
    for (Account acc : scope) {
      scanned++;
      String key = AccountCognitiveSearch.foldName(acc.Name);
      if (key.split(' ').size() < 2) {
        continue;
      }
      List<String> specs = new List<String>();
      for (String v : new List<String>{ acc.Specialty_1__c, acc.Specialty_2__c, acc.Specialty_3__c, acc.Specialty_4__c }) {
        if (String.isNotBlank(v)) {
          specs.add(v);
        }
      }
      specs.sort();
      if (!byName.containsKey(key)) {
        byName.put(key, new List<String>());
      }
      byName.get(key).add(acc.Id + '|' + String.join(specs, ','));
    }
  }

  public void finish(Database.BatchableContext bc) {
    List<List<String>> groups = new List<List<String>>();
    for (List<String> entries : byName.values()) {
      if (entries.size() < 2) {
        continue;
      }
      Set<String> specSets = new Set<String>();
      List<String> ids = new List<String>();
      for (String e : entries) {
        specSets.add(e.substringAfter('|'));
        ids.add(e.substringBefore('|'));
      }
      if (specSets.size() > 1) {
        groups.add(ids);
      }
    }
    update new Account_Quality_Run__c(Id = runId, Accounts_Scanned__c = scanned);
    // Tests run the scorer directly; a batch cannot chain another one inside Test.stopTest.
    if (groups.isEmpty() || Test.isRunningTest()) {
      update new Account_Quality_Run__c(Id = runId, Status__c = 'Ready');
      return;
    }
    Database.executeBatch(new DoctorSpecialtyPairScorer(runId, groups), 5);
  }
}
