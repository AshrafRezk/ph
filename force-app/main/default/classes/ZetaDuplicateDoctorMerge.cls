/**
 * Collapses same-name Zeta Person Accounts (duplicate-names-doctors.csv).
 *
 * Apex cannot read the local CSV. This job uses the same grouping: Person
 * Accounts whose External_ID__c is DOC-% , grouped by Name, count > 1.
 *
 * For each name group it keeps the most complete Account, copies blank
 * fields from the others (phone from one, city from another, …), reparents
 * affiliations / visit attendees that would block delete, then deletes the
 * losers. The survivor keeps its Id and External_ID so visits stay attached.
 *
 * Do not run this on huge common-name groups (محمد صلاح × 31) unless you
 * are sure they are one person. Default maxGroupSize is 2.
 *
 * Anonymous:
 *   Id jobId = ZetaDuplicateDoctorMerge.run(true, 2);   // dry run
 *   Id jobId = ZetaDuplicateDoctorMerge.run(false, 2);  // merge pairs
 *   ZetaDuplicateDoctorMerge.mergeNames(new List<String>{ 'Name' }, false);
 */
public without sharing class ZetaDuplicateDoctorMerge implements Database.Batchable<String>, Database.Stateful {
  private static final List<String> FILL_FIELDS = new List<String>{
    'PersonMobilePhone',
    'PersonEmail',
    'Phone',
    'BillingStreet',
    'BillingCity',
    'BillingState',
    'BillingPostalCode',
    'BillingCountry',
    'Landmark__c',
    'Governorate__c',
    'Customer_Class__c',
    'Maps_Place_Id__c',
    'Brick__c',
    'Brick_148__c',
    'Brick_702__c'
  };
  private static final List<String> SPECIALTY_FIELDS = new List<String>{
    'Specialty_1__c',
    'Specialty_2__c',
    'Specialty_3__c',
    'Specialty_4__c'
  };

  public Boolean dryRun;
  public Integer maxGroupSize;
  public Integer mergedGroups = 0;
  public Integer skippedGroups = 0;
  public Integer deletedAccounts = 0;
  public List<String> errors = new List<String>();

  public class GroupResult {
    public String personName;
    public Integer sourceCount;
    public Id survivorId;
    public String survivorExternalId;
    public List<String> deletedExternalIds = new List<String>();
    public List<String> filledFields = new List<String>();
    public List<String> discardedValues = new List<String>();
    public Boolean skipped;
    public String message;
  }

  public ZetaDuplicateDoctorMerge() {
    this(true, 2);
  }

  public ZetaDuplicateDoctorMerge(Boolean dryRun, Integer maxGroupSize) {
    this.dryRun = dryRun == true;
    this.maxGroupSize = maxGroupSize == null || maxGroupSize < 2 ? 2 : maxGroupSize;
  }

  public static Id run(Boolean dryRun, Integer maxGroupSize) {
    return Database.executeBatch(new ZetaDuplicateDoctorMerge(dryRun, maxGroupSize), 1);
  }

  public static List<GroupResult> mergeNames(List<String> names, Boolean dryRun) {
    ZetaDuplicateDoctorMerge worker = new ZetaDuplicateDoctorMerge(dryRun, 200);
    List<GroupResult> results = new List<GroupResult>();
    if (names == null) {
      return results;
    }
    for (String personName : names) {
      results.add(worker.mergeName(personName));
    }
    return results;
  }

  public Iterable<String> start(Database.BatchableContext context) {
    List<String> names = new List<String>();
    for (AggregateResult row : [
      SELECT Name personName, COUNT(Id) nameCount
      FROM Account
      WHERE IsPersonAccount = TRUE AND External_ID__c LIKE 'DOC-%'
      WITH SYSTEM_MODE
      GROUP BY Name
      HAVING COUNT(Id) > 1
      ORDER BY COUNT(Id) ASC
    ]) {
      Integer nameCount = (Integer) row.get('nameCount');
      if (nameCount > maxGroupSize) {
        skippedGroups++;
        continue;
      }
      names.add((String) row.get('personName'));
    }
    return names;
  }

  public void execute(Database.BatchableContext context, List<String> scope) {
    for (String personName : scope) {
      GroupResult result = mergeName(personName);
      if (result.skipped) {
        skippedGroups++;
      } else if (result.survivorId != null && !dryRun) {
        mergedGroups++;
        deletedAccounts += result.deletedExternalIds.size();
      } else if (result.survivorId != null && dryRun) {
        mergedGroups++;
      }
      if (String.isNotBlank(result.message) && result.message.startsWith('ERROR')) {
        errors.add(personName + ': ' + result.message);
      }
    }
  }

  public void finish(Database.BatchableContext context) {
    System.debug(
      LoggingLevel.INFO,
      'ZetaDuplicateDoctorMerge dryRun=' +
        dryRun +
        ' maxGroupSize=' +
        maxGroupSize +
        ' mergedGroups=' +
        mergedGroups +
        ' skippedGroups=' +
        skippedGroups +
        ' deletedAccounts=' +
        deletedAccounts +
        ' errors=' +
        errors.size()
    );
    for (String error : errors) {
      System.debug(LoggingLevel.ERROR, error);
    }
  }

  public GroupResult mergeName(String personName) {
    GroupResult result = new GroupResult();
    result.personName = personName;
    result.skipped = true;
    if (String.isBlank(personName)) {
      result.message = 'Blank name';
      return result;
    }

    List<Account> rows = queryGroup(personName);
    result.sourceCount = rows.size();
    if (rows.size() < 2) {
      result.message = 'Fewer than 2 DOC-% Person Accounts for this name';
      return result;
    }
    if (rows.size() > maxGroupSize) {
      result.message = 'Group size ' + rows.size() + ' exceeds maxGroupSize ' + maxGroupSize;
      return result;
    }

    Account survivor = pickSurvivor(rows);
    result.survivorId = survivor.Id;
    result.survivorExternalId = survivor.External_ID__c;
    result.skipped = false;

    List<Account> losers = new List<Account>();
    for (Account row : rows) {
      if (row.Id != survivor.Id) {
        losers.add(row);
        result.deletedExternalIds.add(row.External_ID__c);
      }
    }

    applyAggregation(survivor, losers, result);

    if (dryRun) {
      result.message =
        'DRY RUN keep ' +
        survivor.External_ID__c +
        ' delete ' +
        String.join(result.deletedExternalIds, ', ');
      return result;
    }

    try {
      reparentRestrictLookups(loserIds(losers), survivor.Id);
      update as system toPatch(survivor);
      delete as system losers;
      result.message =
        'Kept ' +
        survivor.External_ID__c +
        ' deleted ' +
        String.join(result.deletedExternalIds, ', ');
    } catch (Exception ex) {
      result.skipped = true;
      result.message = 'ERROR ' + ex.getMessage();
    }
    return result;
  }

  private static List<Account> queryGroup(String personName) {
    return [
      SELECT
        Id,
        Name,
        External_ID__c,
        Description,
        PersonMobilePhone,
        PersonEmail,
        Phone,
        BillingStreet,
        BillingCity,
        BillingState,
        BillingPostalCode,
        BillingCountry,
        Landmark__c,
        Governorate__c,
        Customer_Class__c,
        Maps_Place_Id__c,
        Brick__c,
        Brick_148__c,
        Brick_702__c,
        Specialty_1__c,
        Specialty_2__c,
        Specialty_3__c,
        Specialty_4__c
      FROM Account
      WHERE
        Name = :personName
        AND IsPersonAccount = TRUE
        AND External_ID__c LIKE 'DOC-%'
      WITH SYSTEM_MODE
    ];
  }

  private static Account pickSurvivor(List<Account> rows) {
    Account best = rows[0];
    Integer bestScore = completenessScore(best);
    for (Integer i = 1; i < rows.size(); i++) {
      Account candidate = rows[i];
      Integer score = completenessScore(candidate);
      if (
        score > bestScore ||
        (score == bestScore &&
        String.valueOf(candidate.External_ID__c) < String.valueOf(best.External_ID__c))
      ) {
        best = candidate;
        bestScore = score;
      }
    }
    return best;
  }

  private static Integer completenessScore(Account row) {
    Integer score = 0;
    for (String fieldName : FILL_FIELDS) {
      if (isFilled(row.get(fieldName))) {
        score++;
      }
    }
    for (String fieldName : SPECIALTY_FIELDS) {
      if (isFilled(row.get(fieldName))) {
        score++;
      }
    }
    return score;
  }

  private static void applyAggregation(Account survivor, List<Account> losers, GroupResult result) {
    for (Account loser : losers) {
      for (String fieldName : FILL_FIELDS) {
        Object survivorValue = survivor.get(fieldName);
        Object loserValue = loser.get(fieldName);
        if (!isFilled(survivorValue) && isFilled(loserValue)) {
          survivor.put(fieldName, loserValue);
          result.filledFields.add(fieldName + ' from ' + loser.External_ID__c);
        } else if (
          isFilled(survivorValue) &&
          isFilled(loserValue) &&
          String.valueOf(survivorValue) != String.valueOf(loserValue)
        ) {
          result.discardedValues.add(
            fieldName + '=' + String.valueOf(loserValue) + ' from ' + loser.External_ID__c
          );
        }
      }
      mergeSpecialties(survivor, loser, result);
    }

    List<String> noteLines = new List<String>();
    if (String.isNotBlank(survivor.Description)) {
      noteLines.add(survivor.Description);
    }
    noteLines.add('Zeta same-name merge ' + Datetime.now().formatGmt('yyyy-MM-dd'));
    noteLines.add('Kept ' + survivor.External_ID__c);
    noteLines.add('Merged codes: ' + String.join(result.deletedExternalIds, ', '));
    if (!result.filledFields.isEmpty()) {
      noteLines.add('Filled: ' + String.join(result.filledFields, '; '));
    }
    if (!result.discardedValues.isEmpty()) {
      noteLines.add('Discarded conflicts: ' + String.join(result.discardedValues, '; '));
    }
    survivor.Description = clip(String.join(noteLines, '\n'), 32000);
  }

  private static void mergeSpecialties(Account survivor, Account loser, GroupResult result) {
    Set<String> have = new Set<String>();
    for (String fieldName : SPECIALTY_FIELDS) {
      String value = (String) survivor.get(fieldName);
      if (String.isNotBlank(value)) {
        have.add(value);
      }
    }
    for (String fieldName : SPECIALTY_FIELDS) {
      String incoming = (String) loser.get(fieldName);
      if (String.isBlank(incoming) || have.contains(incoming)) {
        continue;
      }
      Boolean placed = false;
      for (String slot : SPECIALTY_FIELDS) {
        if (!isFilled(survivor.get(slot))) {
          survivor.put(slot, incoming);
          have.add(incoming);
          result.filledFields.add(slot + ' from ' + loser.External_ID__c);
          placed = true;
          break;
        }
      }
      if (!placed) {
        result.discardedValues.add(fieldName + '=' + incoming + ' from ' + loser.External_ID__c);
      }
    }
  }

  private static void reparentRestrictLookups(Set<Id> loserIds, Id survivorId) {
    if (loserIds.isEmpty()) {
      return;
    }
    reparentAffiliations(loserIds, survivorId);
    reparentVisitAttendees(loserIds, survivorId);
    reparentTerritoryFields(loserIds, survivorId);
    reparentTerritoryProductFields(loserIds, survivorId);
    reparentProjectGoals(loserIds, survivorId);
  }

  private static void reparentAffiliations(Set<Id> loserIds, Id survivorId) {
    List<Account_Affiliation__c> rows = [
      SELECT Id, Primary_Account__c, Related_Account__c, External_ID__c
      FROM Account_Affiliation__c
      WHERE Primary_Account__c IN :loserIds OR Related_Account__c IN :loserIds
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      return;
    }

    Set<String> pairKeys = new Set<String>();
    for (Account_Affiliation__c existing : [
      SELECT Primary_Account__c, Related_Account__c
      FROM Account_Affiliation__c
      WHERE Primary_Account__c = :survivorId OR Related_Account__c = :survivorId
      WITH SYSTEM_MODE
    ]) {
      pairKeys.add(pairKey(existing.Primary_Account__c, existing.Related_Account__c));
    }

    List<Account_Affiliation__c> updates = new List<Account_Affiliation__c>();
    List<Account_Affiliation__c> deletes = new List<Account_Affiliation__c>();
    for (Account_Affiliation__c row : rows) {
      Id primaryId = loserIds.contains(row.Primary_Account__c) ? survivorId : row.Primary_Account__c;
      Id relatedId = loserIds.contains(row.Related_Account__c) ? survivorId : row.Related_Account__c;
      if (primaryId == relatedId) {
        deletes.add(row);
        continue;
      }
      String key = pairKey(primaryId, relatedId);
      if (pairKeys.contains(key)) {
        deletes.add(row);
        continue;
      }
      row.Primary_Account__c = primaryId;
      row.Related_Account__c = relatedId;
      pairKeys.add(key);
      updates.add(row);
    }
    if (!deletes.isEmpty()) {
      delete as system deletes;
    }
    if (!updates.isEmpty()) {
      update as system updates;
    }
  }

  private static void reparentVisitAttendees(Set<Id> loserIds, Id survivorId) {
    if (!Schema.sObjectType.Visit_Attendee__c.isAccessible()) {
      return;
    }
    List<Visit_Attendee__c> rows = [
      SELECT Id, Account__c, Visit__c
      FROM Visit_Attendee__c
      WHERE Account__c IN :loserIds
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      return;
    }
    Set<Id> visitIds = new Set<Id>();
    for (Visit_Attendee__c row : rows) {
      visitIds.add(row.Visit__c);
    }
    Set<String> existingKeys = new Set<String>();
    for (Visit_Attendee__c existing : [
      SELECT Account__c, Visit__c
      FROM Visit_Attendee__c
      WHERE Visit__c IN :visitIds AND Account__c = :survivorId
      WITH SYSTEM_MODE
    ]) {
      existingKeys.add(String.valueOf(existing.Visit__c) + ':' + String.valueOf(existing.Account__c));
    }
    List<Visit_Attendee__c> updates = new List<Visit_Attendee__c>();
    List<Visit_Attendee__c> deletes = new List<Visit_Attendee__c>();
    for (Visit_Attendee__c row : rows) {
      String key = String.valueOf(row.Visit__c) + ':' + String.valueOf(survivorId);
      if (existingKeys.contains(key)) {
        deletes.add(row);
      } else {
        row.Account__c = survivorId;
        existingKeys.add(key);
        updates.add(row);
      }
    }
    if (!deletes.isEmpty()) {
      delete as system deletes;
    }
    if (!updates.isEmpty()) {
      update as system updates;
    }
  }

  private static void reparentTerritoryFields(Set<Id> loserIds, Id survivorId) {
    List<Account_Territory_Fields__c> rows = [
      SELECT Id, Account__c, Territory2_Id__c, Unique_Key__c
      FROM Account_Territory_Fields__c
      WHERE Account__c IN :loserIds
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      return;
    }
    Set<String> territories = new Set<String>();
    for (Account_Territory_Fields__c existing : [
      SELECT Territory2_Id__c
      FROM Account_Territory_Fields__c
      WHERE Account__c = :survivorId
      WITH SYSTEM_MODE
    ]) {
      territories.add(existing.Territory2_Id__c);
    }
    List<Account_Territory_Fields__c> updates = new List<Account_Territory_Fields__c>();
    List<Account_Territory_Fields__c> deletes = new List<Account_Territory_Fields__c>();
    for (Account_Territory_Fields__c row : rows) {
      if (territories.contains(row.Territory2_Id__c)) {
        deletes.add(row);
      } else {
        row.Account__c = survivorId;
        row.Unique_Key__c = String.valueOf(survivorId) + ':' + row.Territory2_Id__c;
        territories.add(row.Territory2_Id__c);
        updates.add(row);
      }
    }
    if (!deletes.isEmpty()) {
      delete as system deletes;
    }
    if (!updates.isEmpty()) {
      update as system updates;
    }
  }

  private static void reparentTerritoryProductFields(Set<Id> loserIds, Id survivorId) {
    List<Account_Territory_Product_Fields__c> rows = [
      SELECT Id, Account__c, Territory2_Id__c, Product2_Id__c, Unique_Key__c
      FROM Account_Territory_Product_Fields__c
      WHERE Account__c IN :loserIds
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      return;
    }
    Set<String> comboKeys = new Set<String>();
    for (Account_Territory_Product_Fields__c existing : [
      SELECT Territory2_Id__c, Product2_Id__c
      FROM Account_Territory_Product_Fields__c
      WHERE Account__c = :survivorId
      WITH SYSTEM_MODE
    ]) {
      comboKeys.add(existing.Territory2_Id__c + ':' + existing.Product2_Id__c);
    }
    List<Account_Territory_Product_Fields__c> updates = new List<Account_Territory_Product_Fields__c>();
    List<Account_Territory_Product_Fields__c> deletes = new List<Account_Territory_Product_Fields__c>();
    for (Account_Territory_Product_Fields__c row : rows) {
      String key = row.Territory2_Id__c + ':' + row.Product2_Id__c;
      if (comboKeys.contains(key)) {
        deletes.add(row);
      } else {
        row.Account__c = survivorId;
        row.Unique_Key__c = String.valueOf(survivorId) + ':' + key;
        comboKeys.add(key);
        updates.add(row);
      }
    }
    if (!deletes.isEmpty()) {
      delete as system deletes;
    }
    if (!updates.isEmpty()) {
      update as system updates;
    }
  }

  private static void reparentProjectGoals(Set<Id> loserIds, Id survivorId) {
    List<Pharma_Project_Account_Goal__c> rows = [
      SELECT Id, Account__c
      FROM Pharma_Project_Account_Goal__c
      WHERE Account__c IN :loserIds
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      return;
    }
    for (Pharma_Project_Account_Goal__c row : rows) {
      row.Account__c = survivorId;
    }
    update as system rows;
  }

  private static Account toPatch(Account survivor) {
    Account patch = new Account(Id = survivor.Id, Description = survivor.Description);
    for (String fieldName : FILL_FIELDS) {
      patch.put(fieldName, survivor.get(fieldName));
    }
    for (String fieldName : SPECIALTY_FIELDS) {
      patch.put(fieldName, survivor.get(fieldName));
    }
    return patch;
  }

  private static Set<Id> loserIds(List<Account> losers) {
    Set<Id> ids = new Set<Id>();
    for (Account loser : losers) {
      ids.add(loser.Id);
    }
    return ids;
  }

  private static String pairKey(Id leftId, Id rightId) {
    return String.valueOf(leftId) + '>' + String.valueOf(rightId);
  }

  private static Boolean isFilled(Object value) {
    if (value == null) {
      return false;
    }
    if (value instanceof String) {
      return String.isNotBlank((String) value);
    }
    return true;
  }

  private static String clip(String value, Integer maxLength) {
    if (value == null || value.length() <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength);
  }
}