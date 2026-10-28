/**
 * Admin Console > Account data quality > "Doctor specialty merger".
 *
 * Finds doctors (person accounts) entered twice under different specialties
 * (Dr. X / Internal Medicine and Dr. X / Gastroenterology) and merges them into
 * one doctor that keeps every specialty, every visit and every line's rating.
 *
 * Evidence per pair: same phone, same clinic / polyclinic, clinic address in the
 * same area, rare full name, related specialties. Nothing merges without an SFE click.
 *
 * Merge = no data loss:
 *  - blank fields on the kept doctor are filled from the other one; values that
 *    differ are kept on the proposal (Payload__c) as a snapshot of the removed record;
 *  - specialties are combined into Specialty 1-4; the removed doctor's code goes to
 *    Merged_External_IDs__c so later Target / Master uploads still find the doctor;
 *  - visits, attendees, affiliations (clinics, pharmacies), target rows and every other
 *    related record move to the kept doctor (Database.merge);
 *  - two target rows for the same territory (same line) become one: higher visits/month,
 *    better class; per-line ratings on other territories stay as they are.
 */
public with sharing class DoctorSpecialtyMergeService {
  public static final String RUN_TYPE = 'Specialty';
  public static final Integer MIN_SCORE = 30;
  private static final List<String> SPECIALTY_FIELDS = new List<String>{
    'Specialty_1__c',
    'Specialty_2__c',
    'Specialty_3__c',
    'Specialty_4__c'
  };
  // Fields never copied between the two doctors.
  private static final Set<String> SKIP_FIELDS = new Set<String>{
    'id', 'ownerid', 'recordtypeid', 'name', 'firstname', 'lastname', 'middlename', 'suffix',
    'salutation', 'external_id__c', 'merged_external_ids__c', 'specialty_1__c', 'specialty_2__c',
    'specialty_3__c', 'specialty_4__c', 'masterrecordid', 'parentid', 'personcontactid',
    'duplicate_of__c', 'account_stage__c', 'stage_history__c', 'stage_send_back_message__c'
  };
  // Specialties that commonly sit on one doctor (both directions are checked).
  private static final Map<String, Set<String>> RELATED_SPECIALTIES = new Map<String, Set<String>>{
    'Internal_Medicine' => new Set<String>{
      'Gastroenterology', 'Hepatology', 'Nephrology', 'Diabetology', 'Endocrinology', 'Cardiology',
      'Pneumology', 'Rheumatology', 'Haematology', 'Tropical_Medicine', 'Nutrition_Medicine',
      'Intensive_Care', 'Oncology', 'Neurology'
    },
    'Gastroenterology' => new Set<String>{ 'Hepatology', 'Tropical_Medicine', 'Nutrition_Medicine' },
    'Diabetology' => new Set<String>{ 'Endocrinology', 'Nutrition_Medicine' },
    'General_Surgery' => new Set<String>{ 'Vascular_Surgery', 'Plastic_Surgery', 'Urology', 'Orthopaedics', 'Oncology' },
    'Orthopaedics' => new Set<String>{ 'Rheumatology' },
    'Urology' => new Set<String>{ 'Andrology', 'Nephrology' },
    'Dermatology' => new Set<String>{ 'Andrology', 'Plastic_Surgery' },
    'Paediatrics' => new Set<String>{ 'Nutrition_Medicine' },
    'Neurology' => new Set<String>{ 'Psychiatry' },
    'Obstetrics_and_Gynaecology' => new Set<String>{ 'Endocrinology' }
  };

  public class DoctorCard {
    @AuraEnabled public Id id;
    @AuraEnabled public String name;
    @AuraEnabled public String code;
    @AuraEnabled public String mergedCodes;
    @AuraEnabled public List<String> specialties = new List<String>();
    @AuraEnabled public String phones;
    @AuraEnabled public String customerClass;
    @AuraEnabled public String status;
    @AuraEnabled public List<String> workplaces = new List<String>();
    @AuraEnabled public List<String> lines = new List<String>();
    @AuraEnabled public Integer visitCount;
    @AuraEnabled public Integer filledFieldCount;
  }

  public class FactorView {
    @AuraEnabled public String label;
    @AuraEnabled public Integer points;
  }

  public class PairView {
    @AuraEnabled public Id proposalId;
    @AuraEnabled public String status;
    @AuraEnabled public Integer score;
    @AuraEnabled public String label;
    @AuraEnabled public List<FactorView> factors = new List<FactorView>();
    @AuraEnabled public DoctorCard left;
    @AuraEnabled public DoctorCard right;
    @AuraEnabled public Id suggestedSurvivorId;
    @AuraEnabled public List<String> mergedSpecialties = new List<String>();
    @AuraEnabled public String errorMessage;
    @AuraEnabled public String note;
  }

  public class MergeResult {
    @AuraEnabled public Id survivorId;
    @AuraEnabled public String message;
    @AuraEnabled public List<String> filledFields = new List<String>();
    @AuraEnabled public List<String> keptDifferentValues = new List<String>();
    @AuraEnabled public List<String> specialties = new List<String>();
    @AuraEnabled public Integer combinedTargetRows = 0;
    @AuraEnabled public Integer removedDuplicateLinks = 0;
  }

  // ---------------------------------------------------------------- scan

  @AuraEnabled
  public static AccountQualityReviewService.JobStatus startScan() {
    requireMergeAccess();
    List<Account_Quality_Run__c> active = [
      SELECT Id
      FROM Account_Quality_Run__c
      WHERE Type__c = :RUN_TYPE AND Status__c IN ('Queued', 'Running')
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!active.isEmpty()) {
      return AccountQualityReviewService.getRunStatus(active[0].Id);
    }
    Account_Quality_Run__c run = newRun('Queued');
    insert run;
    run.Job_Id__c = String.valueOf(Database.executeBatch(new DoctorSpecialtyScanBatch(run.Id), 500));
    update run;
    return AccountQualityReviewService.getRunStatus(run.Id);
  }

  @AuraEnabled
  public static AccountQualityReviewService.JobStatus getLatestRun() {
    return AccountQualityReviewService.getLatestRun(RUN_TYPE);
  }

  @AuraEnabled
  public static List<PairView> listPairs(Id runId, Integer minScore, Boolean includeClosed) {
    Integer floor = minScore == null ? MIN_SCORE : minScore;
    List<String> statuses = includeClosed == true
      ? new List<String>{ 'Pending', 'Failed', 'Applied', 'Dismissed' }
      : new List<String>{ 'Pending', 'Failed' };
    List<Account_Quality_Proposal__c> rows = [
      SELECT Id, Account__c, Match_Account__c, Survivor_Account__c, Status__c, Score__c,
        Possibility_Label__c, Payload__c, Error_Message__c, External_Name__c
      FROM Account_Quality_Proposal__c
      WHERE Run__c = :runId AND Provider__c = :RUN_TYPE AND Score__c >= :floor AND Status__c IN :statuses
      WITH SYSTEM_MODE
      ORDER BY Score__c DESC, CreatedDate ASC
      LIMIT 100
    ];
    Set<Id> ids = new Set<Id>();
    for (Account_Quality_Proposal__c row : rows) {
      ids.add(row.Account__c);
      ids.add(row.Match_Account__c);
    }
    ids.remove(null);
    Map<Id, DoctorCard> cards = loadCards(ids);
    List<PairView> views = new List<PairView>();
    for (Account_Quality_Proposal__c row : rows) {
      PairView view = new PairView();
      view.proposalId = row.Id;
      view.status = row.Status__c;
      view.score = row.Score__c == null ? 0 : row.Score__c.intValue();
      view.label = row.Possibility_Label__c;
      view.errorMessage = row.Error_Message__c;
      view.left = cards.get(row.Account__c);
      view.right = cards.get(row.Match_Account__c);
      if (row.Status__c == 'Applied') {
        view.left = cards.get(row.Survivor_Account__c);
        view.right = null;
        view.note = 'Merged ' + row.External_Name__c + ' into this doctor.';
      } else if (view.left == null || view.right == null) {
        continue;
      }
      view.factors = parseFactors(row.Payload__c);
      finishView(view, row.Survivor_Account__c);
      views.add(view);
    }
    return views;
  }

  /** Compare two doctors by code (59087, DOC-59087) or record Id, without a scan. */
  @AuraEnabled
  public static PairView comparePair(String first, String second) {
    Account a = findDoctor(first);
    Account b = findDoctor(second);
    if (a.Id == b.Id) {
      throw error('Both codes point to the same doctor.');
    }
    Map<Id, DoctorCard> cards = loadCards(new Set<Id>{ a.Id, b.Id });
    PairView view = new PairView();
    view.status = 'Pending';
    view.left = cards.get(a.Id);
    view.right = cards.get(b.Id);
    Scored s = score(new List<Id>{ a.Id, b.Id }, null).get(pairKey(a.Id, b.Id));
    view.score = s == null ? 0 : s.points;
    view.label = labelFor(view.score);
    view.factors = s == null ? new List<FactorView>() : s.factors;
    finishView(view, null);
    return view;
  }

  @AuraEnabled
  public static AccountQualityReviewService.ApplyResult dismissPairs(List<Id> proposalIds) {
    requireMergeAccess();
    return AccountQualityReviewService.dismissProposals(proposalIds);
  }

  // ---------------------------------------------------------------- merge

  /** Merge from a scan row, or (proposalId null) from a manual compare of two doctors. */
  @AuraEnabled
  public static MergeResult mergePair(Id proposalId, Id survivorId, Id otherId) {
    requireMergeAccess();
    Account_Quality_Proposal__c row;
    if (proposalId != null) {
      row = [
        SELECT Id, Run__c, Account__c, Match_Account__c, Status__c, Payload__c
        FROM Account_Quality_Proposal__c
        WHERE Id = :proposalId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (row.Status__c == 'Applied') {
        throw error('This pair was already merged.');
      }
      otherId = survivorId == row.Account__c ? row.Match_Account__c : row.Account__c;
    } else {
      row = manualProposal(survivorId, otherId);
    }
    if (survivorId == null || otherId == null || survivorId == otherId) {
      throw error('Choose which doctor to keep.');
    }

    Savepoint sp = Database.setSavepoint();
    try {
      // Save the log row first: the merge re-points its doctor lookups to the kept record.
      Account goneDoctor = [SELECT Name, External_ID__c FROM Account WHERE Id = :otherId WITH SYSTEM_MODE LIMIT 1];
      row.External_Name__c = (goneDoctor.Name + ' (' + goneDoctor.External_ID__c + ')').left(255);
      upsert row;
      MergeOutcome outcome = mergeDoctors(survivorId, otherId);
      Map<String, Object> payload = parsePayload(row.Payload__c);
      payload.put('mergedAt', String.valueOf(System.now()));
      payload.put('mergedBy', UserInfo.getName());
      payload.put('removedDoctor', outcome.loserSnapshot);
      payload.put('keptDifferentValues', outcome.result.keptDifferentValues);
      payload.put('combinedTargetRows', outcome.removedAtf);
      // Only the log fields: the row in memory still points at the removed doctor.
      update new Account_Quality_Proposal__c(
        Id = row.Id,
        Payload__c = JSON.serialize(payload).left(131072),
        Status__c = 'Applied',
        Decision__c = 'Merge',
        Survivor_Account__c = survivorId,
        Error_Message__c = null
      );
      return outcome.result;
    } catch (Exception ex) {
      Boolean existed = proposalId != null;
      Database.rollback(sp);
      if (existed) {
        update new Account_Quality_Proposal__c(
          Id = proposalId,
          Status__c = 'Failed',
          Error_Message__c = ex.getMessage().left(32000)
        );
      }
      throw error(ex.getMessage());
    }
  }

  private class MergeOutcome {
    MergeResult result = new MergeResult();
    Map<String, Object> loserSnapshot = new Map<String, Object>();
    List<Map<String, Object>> removedAtf = new List<Map<String, Object>>();
  }

  private static MergeOutcome mergeDoctors(Id survivorId, Id loserId) {
    MergeOutcome outcome = new MergeOutcome();
    List<String> fields = copyableFields();
    String soql =
      'SELECT Id, Name, IsPersonAccount, External_ID__c, Merged_External_IDs__c, ' +
      String.join(SPECIALTY_FIELDS, ', ') + ', ' + String.join(fields, ', ') +
      ' FROM Account WHERE Id IN :ids';
    Set<Id> ids = new Set<Id>{ survivorId, loserId };
    Map<Id, Account> pair = new Map<Id, Account>((List<Account>) Database.query(soql, AccessLevel.SYSTEM_MODE));
    Account keep = pair.get(survivorId);
    Account gone = pair.get(loserId);
    if (keep == null || gone == null) {
      throw error('One of the doctors no longer exists.');
    }
    if (keep.IsPersonAccount != true || gone.IsPersonAccount != true) {
      throw error('Only doctors (person accounts) can be merged here.');
    }
    outcome.loserSnapshot = gone.getPopulatedFieldsAsMap().clone();
    outcome.loserSnapshot.remove('attributes');

    Account changes = new Account(Id = keep.Id);
    for (String f : fields) {
      Object mine = keep.get(f);
      Object theirs = gone.get(f);
      if (isBlank(theirs)) {
        continue;
      }
      if (isBlank(mine)) {
        changes.put(f, theirs);
        outcome.result.filledFields.add(label(f));
      } else if (String.valueOf(mine) != String.valueOf(theirs)) {
        outcome.result.keptDifferentValues.add(label(f) + ': kept "' + mine + '", other had "' + theirs + '"');
      }
    }

    List<String> specialties = combineSpecialties(keep, gone);
    for (Integer i = 0; i < SPECIALTY_FIELDS.size(); i++) {
      changes.put(SPECIALTY_FIELDS[i], i < specialties.size() ? specialties[i] : null);
    }
    if (specialties.size() > SPECIALTY_FIELDS.size()) {
      outcome.result.keptDifferentValues.add('Extra specialties (no free slot): ' +
        String.join(sublist(specialties, SPECIALTY_FIELDS.size()), ', '));
    }
    outcome.result.specialties = sublist(specialties, 0, SPECIALTY_FIELDS.size());
    changes.Merged_External_IDs__c = mergedCodes(keep, gone);

    Database.DMLOptions opts = new Database.DMLOptions();
    opts.DuplicateRuleHeader.allowSave = true;
    opts.OptAllOrNone = true;
    Database.update(changes, opts);

    outcome.removedAtf = combineTargetRows(keep.Id, gone.Id);
    outcome.result.combinedTargetRows = outcome.removedAtf.size();

    Database.MergeResult merged = Database.merge(new Account(Id = keep.Id), gone.Id, false);
    if (!merged.isSuccess()) {
      throw error(merged.getErrors().isEmpty() ? 'Merge failed.' : merged.getErrors()[0].getMessage());
    }

    rekeyTargetRows(keep.Id);
    outcome.result.removedDuplicateLinks = removeDuplicateAffiliations(keep.Id);
    outcome.result.survivorId = keep.Id;
    outcome.result.message =
      'Merged ' + gone.External_ID__c + ' into ' + keep.Name + ' (' + keep.External_ID__c + '). Specialties: ' +
      String.join(outcome.result.specialties, ', ') + '.';
    return outcome;
  }

  /** Same territory on both doctors = same line: keep one row with the higher visits and better class. */
  private static List<Map<String, Object>> combineTargetRows(Id keepId, Id goneId) {
    List<Map<String, Object>> removed = new List<Map<String, Object>>();
    Map<String, Account_Territory_Fields__c> keepByTerritory = new Map<String, Account_Territory_Fields__c>();
    List<Account_Territory_Fields__c> goneRows = new List<Account_Territory_Fields__c>();
    for (Account_Territory_Fields__c atf : [
      SELECT Id, Account__c, Territory2_Id__c, Call_Plan_Visits_Per_Month__c, HCP_Classification__c,
        Classification__c, Potential__c, Is_Active__c
      FROM Account_Territory_Fields__c
      WHERE Account__c IN :new Set<Id>{ keepId, goneId }
      WITH SYSTEM_MODE
    ]) {
      if (atf.Account__c == keepId) {
        keepByTerritory.put(atf.Territory2_Id__c, atf);
      } else {
        goneRows.add(atf);
      }
    }
    List<Account_Territory_Fields__c> toUpdate = new List<Account_Territory_Fields__c>();
    Map<Id, Id> replacedBy = new Map<Id, Id>();
    for (Account_Territory_Fields__c other : goneRows) {
      Account_Territory_Fields__c mine = keepByTerritory.get(other.Territory2_Id__c);
      if (mine == null) {
        continue;
      }
      Decimal a = mine.Call_Plan_Visits_Per_Month__c == null ? 0 : mine.Call_Plan_Visits_Per_Month__c;
      Decimal b = other.Call_Plan_Visits_Per_Month__c == null ? 0 : other.Call_Plan_Visits_Per_Month__c;
      if (b > a) {
        mine.Call_Plan_Visits_Per_Month__c = other.Call_Plan_Visits_Per_Month__c;
      }
      if (betterClass(other.HCP_Classification__c, mine.HCP_Classification__c)) {
        mine.HCP_Classification__c = other.HCP_Classification__c;
        mine.Classification__c = other.Classification__c;
        mine.Potential__c = other.Potential__c;
      }
      mine.Is_Active__c = mine.Is_Active__c == true || other.Is_Active__c == true;
      toUpdate.add(mine);
      replacedBy.put(other.Id, mine.Id);
      Map<String, Object> snap = other.getPopulatedFieldsAsMap().clone();
      snap.remove('attributes');
      removed.add(snap);
    }
    if (replacedBy.isEmpty()) {
      return removed;
    }
    update as system toUpdate;
    // Monthly visit rows hang off the target row: point them at the kept one, drop same-month doubles.
    List<Account_Month_Frequency__c> months = [
      SELECT Id, Account_Territory_Fields__c, Territory2_Id__c, Month_Start__c, Frequency__c
      FROM Account_Month_Frequency__c
      WHERE Account_Territory_Fields__c IN :replacedBy.keySet() OR Account_Territory_Fields__c IN :replacedBy.values()
      WITH SYSTEM_MODE
    ];
    Map<String, Account_Month_Frequency__c> keepMonth = new Map<String, Account_Month_Frequency__c>();
    List<Account_Month_Frequency__c> monthDeletes = new List<Account_Month_Frequency__c>();
    List<Account_Month_Frequency__c> monthUpdates = new List<Account_Month_Frequency__c>();
    for (Account_Month_Frequency__c m : months) {
      if (!replacedBy.containsKey(m.Account_Territory_Fields__c)) {
        keepMonth.put(m.Territory2_Id__c + '|' + m.Month_Start__c, m);
      }
    }
    for (Account_Month_Frequency__c m : months) {
      if (!replacedBy.containsKey(m.Account_Territory_Fields__c)) {
        continue;
      }
      Account_Month_Frequency__c mine = keepMonth.get(m.Territory2_Id__c + '|' + m.Month_Start__c);
      if (mine == null) {
        m.Account_Territory_Fields__c = replacedBy.get(m.Account_Territory_Fields__c);
        monthUpdates.add(m);
      } else {
        if (m.Frequency__c != null && (mine.Frequency__c == null || m.Frequency__c > mine.Frequency__c)) {
          mine.Frequency__c = m.Frequency__c;
          monthUpdates.add(mine);
        }
        monthDeletes.add(m);
      }
    }
    update as system monthUpdates;
    delete as system monthDeletes;
    delete as system [SELECT Id FROM Account_Territory_Fields__c WHERE Id IN :replacedBy.keySet()];
    return removed;
  }

  private static void rekeyTargetRows(Id keepId) {
    List<Account_Territory_Fields__c> rows = [
      SELECT Id, Territory2_Id__c, Unique_Key__c
      FROM Account_Territory_Fields__c
      WHERE Account__c = :keepId
      WITH SYSTEM_MODE
    ];
    List<Account_Territory_Fields__c> changed = new List<Account_Territory_Fields__c>();
    for (Account_Territory_Fields__c atf : rows) {
      String key = (String.valueOf(keepId) + '_' + atf.Territory2_Id__c).left(40);
      if (atf.Unique_Key__c != key) {
        atf.Unique_Key__c = key;
        changed.add(atf);
      }
    }
    update as system changed;
    List<Account_Month_Frequency__c> months = [
      SELECT Id, Territory2_Id__c, Month_Start__c, Unique_Key__c
      FROM Account_Month_Frequency__c
      WHERE Account__c = :keepId
      WITH SYSTEM_MODE
    ];
    List<Account_Month_Frequency__c> monthChanged = new List<Account_Month_Frequency__c>();
    for (Account_Month_Frequency__c m : months) {
      String key = AccountMonthFrequencyService.uniqueKey(keepId, m.Territory2_Id__c, m.Month_Start__c);
      if (m.Unique_Key__c != key) {
        m.Unique_Key__c = key;
        monthChanged.add(m);
      }
    }
    update as system monthChanged;
  }

  /** After the merge the doctor can hold two links to the same clinic; keep the oldest. */
  private static Integer removeDuplicateAffiliations(Id keepId) {
    Set<Id> seen = new Set<Id>();
    List<Account_Affiliation__c> doubles = new List<Account_Affiliation__c>();
    for (Account_Affiliation__c aff : [
      SELECT Id, Related_Account__c
      FROM Account_Affiliation__c
      WHERE Primary_Account__c = :keepId
      WITH SYSTEM_MODE
      ORDER BY CreatedDate ASC
    ]) {
      if (seen.contains(aff.Related_Account__c)) {
        doubles.add(aff);
      } else {
        seen.add(aff.Related_Account__c);
      }
    }
    delete as system doubles;
    return doubles.size();
  }

  // ---------------------------------------------------------------- scoring (shared with the scan)

  public class Scored {
    public Integer points = 0;
    public List<FactorView> factors = new List<FactorView>();
  }

  /** Scores every pair inside each group of doctor Ids (same folded name). */
  public static Map<String, Scored> score(List<Id> doctorIds, Map<Id, Integer> groupSizeById) {
    Map<String, Scored> out = new Map<String, Scored>();
    if (doctorIds == null || doctorIds.size() < 2) {
      return out;
    }
    Map<Id, Account> docs = new Map<Id, Account>([
      SELECT Id, Name, PersonMobilePhone, Phone, WhatsApp_Number__c, Clinic_Phone__c,
        Specialty_1__c, Specialty_2__c, Specialty_3__c, Specialty_4__c
      FROM Account
      WHERE Id IN :doctorIds
      WITH SYSTEM_MODE
    ]);
    Map<Id, List<Account_Affiliation__c>> places = workplacesFor(docs.keySet());
    List<Id> ordered = new List<Id>(docs.keySet());
    for (Integer i = 0; i < ordered.size(); i++) {
      for (Integer j = i + 1; j < ordered.size(); j++) {
        Account a = docs.get(ordered[i]);
        Account b = docs.get(ordered[j]);
        Set<String> sa = specialtiesOf(a);
        Set<String> sb = specialtiesOf(b);
        if (sa.isEmpty() || sb.isEmpty() || sa.equals(sb)) {
          continue;
        }
        Scored s = new Scored();
        Set<String> pa = phonesOf(a);
        pa.retainAll(phonesOf(b));
        if (!pa.isEmpty()) {
          add(s, 'Same phone number', 40);
        }
        Decimal bestAddress = 0;
        Boolean sameArea = false;
        Boolean samePlace = false;
        for (Account_Affiliation__c x : places.get(a.Id) == null ? new List<Account_Affiliation__c>() : places.get(a.Id)) {
          for (Account_Affiliation__c y : places.get(b.Id) == null ? new List<Account_Affiliation__c>() : places.get(b.Id)) {
            if (x.Related_Account__c == y.Related_Account__c) {
              samePlace = true;
            }
            String ca = fold(x.Related_Account__r.BillingCity);
            if (String.isNotBlank(ca) && ca == fold(y.Related_Account__r.BillingCity)) {
              sameArea = true;
              bestAddress = Math.max(bestAddress, overlap(x.Related_Account__r.BillingStreet, y.Related_Account__r.BillingStreet));
            }
          }
        }
        if (samePlace) {
          add(s, 'Same clinic / polyclinic', 30);
        }
        if (bestAddress >= 0.3) {
          add(s, 'Clinic address matches (' + (bestAddress * 100).intValue() + '%)', (bestAddress * 30).intValue());
        }
        if (sameArea) {
          add(s, 'Clinic in the same area', 15);
        }
        Integer words = AccountCognitiveSearch.foldName(a.Name).split(' ').size();
        Integer groupSize = groupSizeById == null || groupSizeById.get(a.Id) == null ? 2 : groupSizeById.get(a.Id);
        if (words >= 3 && groupSize <= 2) {
          add(s, 'Rare full name', 10);
        } else if (groupSize > 5) {
          add(s, 'Common name (' + groupSize + ' doctors)', -10);
        }
        if (related(sa, sb)) {
          add(s, 'Specialties often held together', 10);
        } else if (!sa.contains('General_Practice') && !sb.contains('General_Practice')) {
          add(s, 'Specialties rarely held together', -10);
        }
        s.points = Math.max(0, Math.min(100, s.points));
        out.put(pairKey(a.Id, b.Id), s);
      }
    }
    return out;
  }

  public static String pairKey(Id a, Id b) {
    String x = String.valueOf(a);
    String y = String.valueOf(b);
    return x < y ? x + y : y + x;
  }

  public static String labelFor(Integer points) {
    return points >= 70 ? 'Very likely' : points >= 50 ? 'Likely' : 'Possible';
  }

  public static Account_Quality_Run__c newRun(String status) {
    return new Account_Quality_Run__c(
      Type__c = RUN_TYPE,
      Status__c = status,
      Record_Type_Filter__c = 'PersonAccount',
      Proposal_Count__c = 0,
      Accounts_Scanned__c = 0,
      Applied_Count__c = 0,
      Dismissed_Count__c = 0
    );
  }

  public static String factorsJson(Scored s) {
    return JSON.serialize(new Map<String, Object>{ 'factors' => s.factors });
  }

  // ---------------------------------------------------------------- imports

  /** DOC- codes that were merged away -> the doctor that now carries them. */
  public static Map<String, Id> survivorsForMergedCodes(Set<String> externalIds) {
    Map<String, Id> out = new Map<String, Id>();
    List<String> likes = new List<String>();
    for (String ext : externalIds == null ? new Set<String>() : externalIds) {
      if (String.isNotBlank(ext) && ext.startsWith(AccountMasterImportUtil.EXT_DOC_PREFIX)) {
        likes.add('%;' + ext + ';%');
      }
    }
    if (likes.isEmpty()) {
      return out;
    }
    for (Account acc : [
      SELECT Id, Merged_External_IDs__c
      FROM Account
      WHERE Merged_External_IDs__c LIKE :likes
      WITH SYSTEM_MODE
    ]) {
      for (String code : acc.Merged_External_IDs__c.split(';')) {
        if (externalIds.contains(code)) {
          out.put(code, acc.Id);
        }
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- helpers

  private static Map<Id, DoctorCard> loadCards(Set<Id> ids) {
    Map<Id, DoctorCard> cards = new Map<Id, DoctorCard>();
    if (ids.isEmpty()) {
      return cards;
    }
    List<String> fields = copyableFields();
    String soql =
      'SELECT Id, Name, External_ID__c, Merged_External_IDs__c, IsPersonAccount, ' +
      String.join(SPECIALTY_FIELDS, ', ') + ', ' + String.join(fields, ', ') +
      ' FROM Account WHERE Id IN :ids AND IsPersonAccount = true';
    Map<Id, List<Account_Affiliation__c>> places = workplacesFor(ids);
    Map<String, String> territoryNames = new Map<String, String>();
    List<Account_Territory_Fields__c> atfs = [
      SELECT Account__c, Territory2_Id__c, HCP_Classification__c, Call_Plan_Visits_Per_Month__c
      FROM Account_Territory_Fields__c
      WHERE Account__c IN :ids
      WITH SYSTEM_MODE
    ];
    Set<Id> terrIds = new Set<Id>();
    for (Account_Territory_Fields__c atf : atfs) {
      try {
        terrIds.add(Id.valueOf(atf.Territory2_Id__c));
      } catch (Exception badId) {
        continue;
      }
    }
    for (Territory2 t : [SELECT Id, Name FROM Territory2 WHERE Id IN :terrIds]) {
      territoryNames.put(String.valueOf(t.Id), t.Name);
    }
    Map<Id, Integer> visits = new Map<Id, Integer>();
    for (AggregateResult ar : [
      SELECT Account__c acc, COUNT(Id) n
      FROM Visit__c
      WHERE Account__c IN :ids
      WITH SYSTEM_MODE
      GROUP BY Account__c
    ]) {
      visits.put((Id) ar.get('acc'), (Integer) ar.get('n'));
    }
    for (Account acc : (List<Account>) Database.query(soql, AccessLevel.SYSTEM_MODE)) {
      DoctorCard card = new DoctorCard();
      card.id = acc.Id;
      card.name = acc.Name;
      card.code = acc.External_ID__c;
      card.mergedCodes = acc.Merged_External_IDs__c == null ? null : acc.Merged_External_IDs__c.replace(';', ' ').trim();
      card.specialties = specialtyLabels(acc);
      card.phones = String.join(new List<String>(phonesOf(acc)), ', ');
      card.customerClass = (String) acc.get('Customer_Class__c');
      card.status = (String) acc.get('Account_Status__c');
      card.visitCount = visits.containsKey(acc.Id) ? visits.get(acc.Id) : 0;
      Integer filled = 0;
      for (String f : fields) {
        if (!isBlank(acc.get(f))) {
          filled++;
        }
      }
      card.filledFieldCount = filled;
      for (Account_Affiliation__c aff : places.get(acc.Id) == null ? new List<Account_Affiliation__c>() : places.get(acc.Id)) {
        List<String> parts = new List<String>{ aff.Related_Account__r.Name };
        if (String.isNotBlank(aff.Related_Account__r.BillingStreet)) {
          parts.add(aff.Related_Account__r.BillingStreet);
        }
        if (String.isNotBlank(aff.Related_Account__r.BillingCity)) {
          parts.add(aff.Related_Account__r.BillingCity);
        }
        card.workplaces.add(String.join(parts, ' · '));
      }
      for (Account_Territory_Fields__c atf : atfs) {
        if (atf.Account__c != acc.Id) {
          continue;
        }
        String terr = territoryNames.containsKey(atf.Territory2_Id__c) ? territoryNames.get(atf.Territory2_Id__c) : atf.Territory2_Id__c;
        card.lines.add(terr + ' · class ' + (atf.HCP_Classification__c == null ? '—' : atf.HCP_Classification__c) + ' · ' +
          (atf.Call_Plan_Visits_Per_Month__c == null ? '—' : String.valueOf(atf.Call_Plan_Visits_Per_Month__c.stripTrailingZeros())) + '/month');
      }
      cards.put(acc.Id, card);
    }
    return cards;
  }

  private static void finishView(PairView view, Id storedSurvivor) {
    if (view.left == null || view.right == null) {
      return;
    }
    // Keep the doctor with more history: visits, then lines, then filled fields.
    DoctorCard a = view.left;
    DoctorCard b = view.right;
    Integer ra = a.visitCount * 1000 + a.lines.size() * 100 + a.filledFieldCount;
    Integer rb = b.visitCount * 1000 + b.lines.size() * 100 + b.filledFieldCount;
    view.suggestedSurvivorId = storedSurvivor != null ? storedSurvivor : (rb > ra ? b.id : a.id);
    DoctorCard first = view.suggestedSurvivorId == a.id ? a : b;
    DoctorCard second = first == a ? b : a;
    Set<String> seen = new Set<String>();
    for (String s : first.specialties) {
      if (seen.add(s)) {
        view.mergedSpecialties.add(s);
      }
    }
    for (String s : second.specialties) {
      if (seen.add(s)) {
        view.mergedSpecialties.add(s);
      }
    }
  }

  private static Account_Quality_Proposal__c manualProposal(Id a, Id b) {
    List<Account_Quality_Run__c> runs = [
      SELECT Id
      FROM Account_Quality_Run__c
      WHERE Type__c = :RUN_TYPE
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    Id runId;
    if (runs.isEmpty()) {
      Account_Quality_Run__c run = newRun('Ready');
      insert run;
      runId = run.Id;
    } else {
      runId = runs[0].Id;
    }
    Scored s = score(new List<Id>{ a, b }, null).get(pairKey(a, b));
    return new Account_Quality_Proposal__c(
      Run__c = runId,
      Pair_Key__c = pairKey(a, b).left(40),
      Account__c = a,
      Match_Account__c = b,
      Provider__c = RUN_TYPE,
      Status__c = 'Pending',
      Score__c = s == null ? 0 : s.points,
      Possibility_Label__c = labelFor(s == null ? 0 : s.points),
      Summary__c = 'Merged by code from the Doctor specialty merger.',
      Account_Is_Person__c = true,
      Match_Is_Person__c = true,
      Can_Merge__c = true,
      Payload__c = s == null ? '{}' : factorsJson(s)
    );
  }

  private static Account findDoctor(String codeOrId) {
    String raw = codeOrId == null ? '' : codeOrId.trim();
    if (String.isBlank(raw)) {
      throw error('Enter two doctor codes.');
    }
    String ext = raw.toUpperCase().startsWith(AccountMasterImportUtil.EXT_DOC_PREFIX)
      ? AccountMasterImportUtil.EXT_DOC_PREFIX + raw.substring(AccountMasterImportUtil.EXT_DOC_PREFIX.length())
      : AccountMasterImportUtil.EXT_DOC_PREFIX + raw;
    Id asId = null;
    try {
      asId = Id.valueOf(raw);
    } catch (Exception notAnId) {
      asId = null;
    }
    List<Account> hits = [
      SELECT Id, Name
      FROM Account
      WHERE IsPersonAccount = true AND (External_ID__c = :ext OR Id = :asId)
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (hits.isEmpty()) {
      Map<String, Id> merged = survivorsForMergedCodes(new Set<String>{ ext });
      if (merged.containsKey(ext)) {
        throw error(ext + ' was already merged into another doctor.');
      }
      throw error('No doctor with code ' + raw + '.');
    }
    return hits[0];
  }

  private static Map<Id, List<Account_Affiliation__c>> workplacesFor(Set<Id> doctorIds) {
    Map<Id, List<Account_Affiliation__c>> out = new Map<Id, List<Account_Affiliation__c>>();
    for (Account_Affiliation__c aff : [
      SELECT Primary_Account__c, Related_Account__c, Related_Account__r.Name, Related_Account__r.BillingStreet,
        Related_Account__r.BillingCity
      FROM Account_Affiliation__c
      WHERE Primary_Account__c IN :doctorIds AND Is_Active__c = true
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
    ]) {
      if (!out.containsKey(aff.Primary_Account__c)) {
        out.put(aff.Primary_Account__c, new List<Account_Affiliation__c>());
      }
      out.get(aff.Primary_Account__c).add(aff);
    }
    return out;
  }

  private static List<String> copyableFields() {
    List<String> out = new List<String>();
    for (Schema.SObjectField token : Schema.SObjectType.Account.fields.getMap().values()) {
      Schema.DescribeFieldResult d = token.getDescribe();
      String n = d.getName();
      if (!d.isUpdateable() || d.isCalculated() || SKIP_FIELDS.contains(n.toLowerCase())) {
        continue;
      }
      if (d.getType() == Schema.DisplayType.ADDRESS || d.getType() == Schema.DisplayType.LOCATION) {
        continue;
      }
      out.add(n);
    }
    out.sort();
    return out;
  }

  private static List<String> combineSpecialties(Account keep, Account gone) {
    List<String> out = new List<String>();
    for (Account acc : new List<Account>{ keep, gone }) {
      for (String f : SPECIALTY_FIELDS) {
        String v = (String) acc.get(f);
        if (String.isNotBlank(v) && !out.contains(v)) {
          out.add(v);
        }
      }
    }
    return out;
  }

  private static String mergedCodes(Account keep, Account gone) {
    List<String> codes = new List<String>();
    for (String part : new List<String>{ keep.Merged_External_IDs__c, gone.External_ID__c, gone.Merged_External_IDs__c }) {
      for (String code : (part == null ? '' : part).split(';')) {
        if (String.isNotBlank(code) && code != keep.External_ID__c && !codes.contains(code.trim())) {
          codes.add(code.trim());
        }
      }
    }
    return codes.isEmpty() ? null : (';' + String.join(codes, ';') + ';').left(255);
  }

  private static Set<String> specialtiesOf(Account acc) {
    Set<String> out = new Set<String>();
    for (String f : SPECIALTY_FIELDS) {
      String v = (String) acc.get(f);
      if (String.isNotBlank(v)) {
        out.add(v);
      }
    }
    return out;
  }

  private static List<String> specialtyLabels(Account acc) {
    Map<String, String> labels = new Map<String, String>();
    for (Schema.PicklistEntry e : Account.Specialty_1__c.getDescribe().getPicklistValues()) {
      labels.put(e.getValue(), e.getLabel());
    }
    List<String> out = new List<String>();
    for (String f : SPECIALTY_FIELDS) {
      String v = (String) acc.get(f);
      if (String.isNotBlank(v)) {
        out.add(labels.containsKey(v) ? labels.get(v) : v);
      }
    }
    return out;
  }

  private static Set<String> phonesOf(Account acc) {
    Set<String> out = new Set<String>();
    for (String f : new List<String>{ 'PersonMobilePhone', 'Phone', 'WhatsApp_Number__c', 'Clinic_Phone__c' }) {
      Object v = acc.get(f);
      String digits = v == null ? '' : String.valueOf(v).replaceAll('[^0-9]', '');
      if (digits.length() >= 9) {
        out.add(digits.right(9));
      }
    }
    return out;
  }

  private static Boolean related(Set<String> a, Set<String> b) {
    for (String x : a) {
      for (String y : b) {
        if (
          (RELATED_SPECIALTIES.containsKey(x) && RELATED_SPECIALTIES.get(x).contains(y)) ||
          (RELATED_SPECIALTIES.containsKey(y) && RELATED_SPECIALTIES.get(y).contains(x))
        ) {
          return true;
        }
      }
    }
    return false;
  }

  private static Decimal overlap(String a, String b) {
    Set<String> ta = addressTokens(a);
    Set<String> tb = addressTokens(b);
    if (ta.isEmpty() || tb.isEmpty()) {
      return 0;
    }
    Set<String> union = new Set<String>(ta);
    union.addAll(tb);
    ta.retainAll(tb);
    return Decimal.valueOf(ta.size()) / union.size();
  }

  private static final Set<String> ADDRESS_STOP = new Set<String>{
    'شارع', 'امام', 'بجوار', 'خلف', 'عماره', 'برج', 'الدور', 'اعلي', 'فوق', 'مدخل', 'الاول', 'الثاني'
  };

  private static Set<String> addressTokens(String raw) {
    Set<String> out = new Set<String>();
    for (String t : fold(raw).split(' ')) {
      if (t.length() > 2 && !ADDRESS_STOP.contains(t)) {
        out.add(t);
      }
    }
    return out;
  }

  private static Map<String, String> foldCache = new Map<String, String>();

  // Scans compare the same clinic addresses many times; fold each text once per transaction.
  private static String fold(String raw) {
    String key = raw == null ? '' : raw;
    if (!foldCache.containsKey(key)) {
      foldCache.put(key, AccountCognitiveSearch.foldName(key));
    }
    return foldCache.get(key);
  }

  private static Boolean betterClass(String candidate, String current) {
    if (String.isBlank(candidate)) {
      return false;
    }
    return String.isBlank(current) || candidate.toUpperCase() < current.toUpperCase();
  }

  private static void add(Scored s, String label, Integer points) {
    FactorView f = new FactorView();
    f.label = label;
    f.points = points;
    s.factors.add(f);
    s.points += points;
  }

  private static List<FactorView> parseFactors(String payload) {
    List<FactorView> out = new List<FactorView>();
    Object raw = parsePayload(payload).get('factors');
    if (raw instanceof List<Object>) {
      for (Object item : (List<Object>) raw) {
        Map<String, Object> m = (Map<String, Object>) item;
        FactorView f = new FactorView();
        f.label = (String) m.get('label');
        f.points = m.get('points') == null ? 0 : Integer.valueOf(m.get('points'));
        out.add(f);
      }
    }
    return out;
  }

  private static Map<String, Object> parsePayload(String payload) {
    if (String.isBlank(payload)) {
      return new Map<String, Object>();
    }
    try {
      return (Map<String, Object>) JSON.deserializeUntyped(payload);
    } catch (Exception e) {
      return new Map<String, Object>{ 'previousPayload' => payload };
    }
  }

  private static List<String> sublist(List<String> items, Integer start) {
    return sublist(items, start, items.size());
  }

  private static List<String> sublist(List<String> items, Integer start, Integer endExclusive) {
    List<String> out = new List<String>();
    for (Integer i = start; i < Math.min(endExclusive, items.size()); i++) {
      out.add(items[i]);
    }
    return out;
  }

  private static Boolean isBlank(Object value) {
    return value == null || (value instanceof String && String.isBlank((String) value));
  }

  private static String label(String fieldName) {
    return Schema.SObjectType.Account.fields.getMap().get(fieldName).getDescribe().getLabel();
  }

  private static void requireMergeAccess() {
    if (!AccountDuplicateCheckService.canMergeAccounts()) {
      throw error('Only SFE can merge doctors.');
    }
  }

  private static AuraHandledException error(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
