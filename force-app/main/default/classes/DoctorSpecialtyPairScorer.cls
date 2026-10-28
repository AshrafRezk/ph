/**
 * Second pass of the Doctor specialty merger scan (see DoctorSpecialtyScanBatch): scores each
 * same-name group and stores pairs at or above DoctorSpecialtyMergeService.MIN_SCORE.
 * Groups larger than 40 doctors are capped.
 */
public without sharing class DoctorSpecialtyPairScorer implements Database.Batchable<List<String>>, Database.Stateful {
  private Id runId;
  private List<List<String>> groups;
  private Integer stored = 0;
  private String lastError;

  public DoctorSpecialtyPairScorer(Id runId, List<List<String>> groups) {
    this.runId = runId;
    this.groups = groups;
  }

  public Iterable<List<String>> start(Database.BatchableContext bc) {
    return groups;
  }

  public void execute(Database.BatchableContext bc, List<List<String>> scope) {
    List<Account_Quality_Proposal__c> rows = new List<Account_Quality_Proposal__c>();
    for (List<String> grp : scope) {
      List<Id> ids = new List<Id>();
      for (String raw : grp) {
        if (ids.size() < 40) {
          ids.add(Id.valueOf(raw));
        }
      }
      Map<Id, Integer> sizes = new Map<Id, Integer>();
      for (Id i : ids) {
        sizes.put(i, grp.size());
      }
      try {
        Map<String, DoctorSpecialtyMergeService.Scored> scored = DoctorSpecialtyMergeService.score(ids, sizes);
        for (String key : scored.keySet()) {
          DoctorSpecialtyMergeService.Scored s = scored.get(key);
          if (s.points < DoctorSpecialtyMergeService.MIN_SCORE) {
            continue;
          }
          Id a = Id.valueOf(key.left(18));
          Id b = Id.valueOf(key.substring(18));
          rows.add(new Account_Quality_Proposal__c(
            Run__c = runId,
            Pair_Key__c = key.left(40),
            Account__c = a,
            Match_Account__c = b,
            Provider__c = DoctorSpecialtyMergeService.RUN_TYPE,
            Status__c = 'Pending',
            Score__c = s.points,
            Possibility_Label__c = DoctorSpecialtyMergeService.labelFor(s.points),
            Summary__c = 'Same doctor name with different specialties.',
            Account_Is_Person__c = true,
            Match_Is_Person__c = true,
            Can_Merge__c = true,
            Payload__c = DoctorSpecialtyMergeService.factorsJson(s)
          ));
        }
      } catch (Exception ex) {
        lastError = ex.getMessage();
      }
    }
    insert rows;
    stored += rows.size();
  }

  public void finish(Database.BatchableContext bc) {
    update new Account_Quality_Run__c(
      Id = runId,
      Status__c = 'Ready',
      Proposal_Count__c = stored,
      Error_Message__c = lastError
    );
  }
}
