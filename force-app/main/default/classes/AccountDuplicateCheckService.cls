/**
 * Scores other accounts against one account using name, mobile, type, and location.
 * Name matching is cognitive: Arabic spelling and Latin transliteration count as the
 * same name (أحمد, احمد, Ahmed, Ahmad), using AccountCognitiveSearch.
 * Report links the current account as a duplicate. Merge keeps one record.
 */
public with sharing class AccountDuplicateCheckService {
  private static final Integer NAME_WEIGHT = 40;
  private static final Integer MOBILE_WEIGHT = 30;
  private static final Integer TYPE_WEIGHT = 15;
  private static final Integer LOCATION_WEIGHT = 15;
  private static final Integer INCLUDE_PERCENT = 45;

  public class Factor {
    @AuraEnabled public String key;
    @AuraEnabled public String label;
    @AuraEnabled public Integer percent;
  }

  public class MatchRow {
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public String recordTypeName;
    @AuraEnabled public String phone;
    @AuraEnabled public String location;
    @AuraEnabled public Integer percent;
    @AuraEnabled public String possibilityLabel;
    @AuraEnabled public String summary;
    @AuraEnabled public List<Factor> factors;
  }

  public class CheckResult {
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public String recordTypeName;
    @AuraEnabled public String phone;
    @AuraEnabled public String location;
    @AuraEnabled public Integer highestPercent;
    @AuraEnabled public String possibilityLabel;
    @AuraEnabled public String headline;
    @AuraEnabled public Boolean hasMatches;
    @AuraEnabled public Boolean canReport;
    @AuraEnabled public Boolean canMerge;
    @AuraEnabled public String reportedOfName;
    @AuraEnabled public List<MatchRow> matches;
  }

  public class ActionResult {
    @AuraEnabled public Boolean ok;
    @AuraEnabled public String message;
    @AuraEnabled public Id survivorId;
    @AuraEnabled public Boolean sourceRemoved;
  }

  private class Scored {
    Account candidate;
    Integer nameScore;
    Integer mobileScore;
    Integer typeScore;
    Integer locationScore;
    Integer percent;
  }

  @AuraEnabled
  public static CheckResult findAccountDuplicates(Id accountId) {
    if (accountId == null) {
      throw error('Account is required.');
    }
    Account source = queryAccount(accountId);
    if (source == null) {
      throw error('Account was not found.');
    }

    CheckResult result = new CheckResult();
    result.accountId = source.Id;
    result.accountName = source.Name;
    result.recordTypeName = source.RecordType == null ? null : source.RecordType.Name;
    result.phone = displayPhone(source);
    result.location = displayLocation(source);
    result.matches = new List<MatchRow>();
    result.canReport = canReport(source);
    result.canMerge = canMergeAccounts();
    result.reportedOfName = reportedOfName(source);

    List<Scored> scored = new List<Scored>();
    for (Account candidate : findCandidates(source)) {
      if (candidate.Id == source.Id) {
        continue;
      }
      Scored row = scorePair(source, candidate);
      if (!include(row)) {
        continue;
      }
      scored.add(row);
    }
    scored.sort(new ScoredSort());

    Integer limitSize = Math.min(scored.size(), 12);
    for (Integer i = 0; i < limitSize; i++) {
      result.matches.add(toMatch(scored[i]));
    }
    result.hasMatches = !result.matches.isEmpty();
    result.highestPercent = result.hasMatches ? result.matches[0].percent : 0;
    result.possibilityLabel = result.hasMatches ? possibilityLabel(result.highestPercent) : 'None';
    result.headline = headline(result);
    return result;
  }

  /**
   * Likely duplicates for an account that is not saved yet (create wizard): a strong
   * name match, or the same mobile with a similar name.
   */
  public static List<MatchRow> findLikelyDuplicatesForDraft(Account draft) {
    List<MatchRow> matches = new List<MatchRow>();
    if (draft == null || String.isBlank(draft.Name)) {
      return matches;
    }
    List<Scored> scored = new List<Scored>();
    for (Account candidate : findCandidates(draft)) {
      Scored row = scorePair(draft, candidate);
      if (row.percent >= 70 || (row.mobileScore == 100 && row.nameScore >= 80)) {
        scored.add(row);
      }
    }
    scored.sort(new ScoredSort());
    for (Integer i = 0; i < Math.min(scored.size(), 3); i++) {
      matches.add(toMatch(scored[i]));
    }
    return matches;
  }

  @AuraEnabled
  public static ActionResult reportAccountDuplicate(Id accountId, Id duplicateOfId) {
    if (accountId == null || duplicateOfId == null) {
      throw error('Choose the account this record duplicates.');
    }
    AccountStageService.StageView view = AccountStageService.reportDuplicate(accountId, duplicateOfId);
    ActionResult result = new ActionResult();
    result.ok = true;
    result.survivorId = duplicateOfId;
    result.sourceRemoved = false;
    result.message = 'Reported as a duplicate of ' + (view.duplicateOfName == null ? 'the selected account' : view.duplicateOfName) + '.';
    return result;
  }

  @AuraEnabled
  public static ActionResult mergeAccountDuplicates(Id survivorId, Id duplicateId) {
    if (survivorId == null || duplicateId == null) {
      throw error('Choose which account to keep.');
    }
    if (survivorId == duplicateId) {
      throw error('Choose two different accounts to merge.');
    }
    if (!canMergeAccounts()) {
      throw error('Only SFE can approve and merge duplicate accounts. Report the duplicate to SFE instead.');
    }
    if (!Schema.sObjectType.Account.isDeletable() || !Schema.sObjectType.Account.isUpdateable()) {
      throw error('You do not have permission to merge accounts.');
    }

    Map<Id, Account> pair = new Map<Id, Account>([
      SELECT Id, Name, IsPersonAccount
      FROM Account
      WHERE Id IN :new Set<Id>{ survivorId, duplicateId }
      WITH USER_MODE
    ]);
    if (!pair.containsKey(survivorId) || !pair.containsKey(duplicateId)) {
      throw error('One of these accounts is no longer available.');
    }
    if (pair.get(survivorId).IsPersonAccount != pair.get(duplicateId).IsPersonAccount) {
      throw error('A person account cannot be merged with a business account. Report the duplicate instead.');
    }

    String keptName = pair.get(survivorId).Name;
    Database.MergeResult merged = Database.merge(new Account(Id = survivorId), duplicateId, false);
    if (!merged.isSuccess()) {
      String message = merged.getErrors().isEmpty() ? 'Merge failed.' : merged.getErrors()[0].getMessage();
      throw error(message);
    }

    ActionResult result = new ActionResult();
    result.ok = true;
    result.survivorId = survivorId;
    result.sourceRemoved = duplicateId != survivorId;
    result.message = 'Merged into ' + keptName + '. Related records now sit on that account.';
    return result;
  }

  private static Boolean include(Scored row) {
    if (row.percent >= INCLUDE_PERCENT) {
      return true;
    }
    return row.mobileScore == 100 || (row.nameScore >= 90 && row.typeScore == 100);
  }

  private static Scored scorePair(Account source, Account candidate) {
    Scored row = new Scored();
    row.candidate = candidate;
    row.nameScore = nameScore(source.Name, candidate.Name);
    row.mobileScore = mobileScore(phonesOf(source), phonesOf(candidate));
    row.typeScore = typeScore(source, candidate);
    row.locationScore = locationScore(source, candidate);
    Integer weighted =
      (row.nameScore * NAME_WEIGHT +
        row.mobileScore * MOBILE_WEIGHT +
        row.typeScore * TYPE_WEIGHT +
        row.locationScore * LOCATION_WEIGHT) / 100;
    if (row.mobileScore == 100) {
      weighted = Math.max(weighted, 55);
    }
    if (row.nameScore == 100 && row.typeScore == 100) {
      weighted = Math.max(weighted, 60);
    }
    if (row.nameScore >= 90 && row.typeScore == 100 && row.locationScore >= 70) {
      weighted = Math.max(weighted, 80);
    }
    if (row.nameScore >= 90) {
      weighted = Math.max(weighted, 62);
    }
    row.percent = Math.min(100, weighted);
    return row;
  }

  private static MatchRow toMatch(Scored row) {
    MatchRow match = new MatchRow();
    match.accountId = row.candidate.Id;
    match.accountName = row.candidate.Name;
    match.recordTypeName = row.candidate.RecordType == null ? null : row.candidate.RecordType.Name;
    match.phone = displayPhone(row.candidate);
    match.location = displayLocation(row.candidate);
    match.percent = row.percent;
    match.possibilityLabel = possibilityLabel(row.percent);
    match.factors = new List<Factor>{
      factor('name', 'Name', row.nameScore),
      factor('mobile', 'Mobile', row.mobileScore),
      factor('type', 'Type', row.typeScore),
      factor('location', 'Location', row.locationScore)
    };
    match.summary = summaryFor(row);
    return match;
  }

  private static Factor factor(String key, String label, Integer percent) {
    Factor item = new Factor();
    item.key = key;
    item.label = label;
    item.percent = percent == null ? 0 : percent;
    return item;
  }

  private static String summaryFor(Scored row) {
    List<String> strong = new List<String>();
    if (row.nameScore >= 80) strong.add('name');
    if (row.mobileScore >= 80) strong.add('mobile');
    if (row.typeScore == 100) strong.add('type');
    if (row.locationScore >= 70) strong.add('location');
    String basis = strong.isEmpty() ? 'a partial match' : String.join(strong, ', ');
    return row.percent + '% ' + possibilityLabel(row.percent).toLowerCase() + ' duplicate based on ' + basis + '.';
  }

  private static String headline(CheckResult result) {
    if (String.isNotBlank(result.reportedOfName)) {
      return 'This account is already reported as a duplicate of ' + result.reportedOfName + '.';
    }
    if (!result.hasMatches) {
      return 'No likely duplicate. Name, mobile, type, and location do not line up with another account.';
    }
    MatchRow top = result.matches[0];
    return result.highestPercent + '% ' + result.possibilityLabel.toLowerCase() + ' duplicate of ' + top.accountName + '.';
  }

  private static String possibilityLabel(Integer percent) {
    Integer value = percent == null ? 0 : percent;
    if (value >= 85) return 'Very likely';
    if (value >= 70) return 'Likely';
    if (value >= 50) return 'Possible';
    return 'Weak';
  }

  private static Boolean canReport(Account source) {
    if (!Schema.sObjectType.Account.isUpdateable() || !hasField('Account_Stage__c') || !hasField('Duplicate_Of__c')) {
      return false;
    }
    return normalizeStage(stringField(source, 'Account_Stage__c')) != 'Duplicate';
  }

  /** Merge is SFE-only (custom permission or SFE title / System Administrator). */
  @TestVisible
  public static Boolean canMergeAccounts() {
    try {
      if (FeatureManagement.checkPermission('Merge_Account_Duplicates')) {
        return true;
      }
    } catch (Exception ignore) {
      // Permission may not be deployed yet.
    }
    List<User> me = [
      SELECT Title, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (me.isEmpty()) {
      return false;
    }
    String titleLower = me[0].Title == null ? '' : me[0].Title.toLowerCase();
    if (titleLower.contains('sales force excellence')
      || titleLower.contains('sfe')
      || titleLower.contains('field intelligence')) {
      return true;
    }
    return me[0].Profile != null && me[0].Profile.Name == 'System Administrator';
  }

  private static String reportedOfName(Account source) {
    if (normalizeStage(stringField(source, 'Account_Stage__c')) != 'Duplicate') {
      return null;
    }
    SObject master = source.getSObject('Duplicate_Of__r');
    return master == null ? null : (String) master.get('Name');
  }

  private static String normalizeStage(String value) {
    return value == null ? '' : value.trim();
  }

  private static List<Account> findCandidates(Account source) {
    Map<Id, Account> byId = new Map<Id, Account>();
    List<String> filters = new List<String>();
    Id sourceId = source.Id;
    String sourceName = source.Name;
    String sourceCity = source.BillingCity;
    String nameLike = namePrefix(source.Name);
    Id sourceBrickId = brickId(source);
    List<String> phoneList = new List<String>(storedPhones(source));
    String phone0 = phoneList.size() > 0 ? phoneList[0] : null;
    String phone1 = phoneList.size() > 1 ? phoneList[1] : null;
    String phone2 = phoneList.size() > 2 ? phoneList[2] : null;
    String phone3 = phoneList.size() > 3 ? phoneList[3] : null;
    Integer phoneCount = Math.min(phoneList.size(), 4);
    String phoneLike = phoneTailLike(source);

    if (String.isNotBlank(sourceName)) {
      filters.add('Name = :sourceName');
    }
    String cognitiveClause = cognitiveNameClause(sourceName);
    if (String.isNotBlank(cognitiveClause)) {
      filters.add(cognitiveClause);
    }
    if (String.isNotBlank(nameLike) && String.isNotBlank(sourceCity)) {
      filters.add('(BillingCity = :sourceCity AND Name LIKE :nameLike)');
    }
    if (String.isNotBlank(nameLike) && sourceBrickId != null && hasField('Brick__c')) {
      filters.add('(Brick__c = :sourceBrickId AND Name LIKE :nameLike)');
    }
    if (phoneCount > 0 && !phoneFields().isEmpty()) {
      filters.add(phoneOrClause(phoneCount));
    }
    if (filters.isEmpty() && String.isBlank(phoneLike) && source.BillingLatitude == null) {
      return new List<Account>();
    }

    String selectClause = 'SELECT ' + String.join(queryFields(), ', ') + ' FROM Account ';
    if (!filters.isEmpty()) {
      String soql =
        selectClause +
        'WHERE Id != :sourceId AND (' +
        String.join(filters, ' OR ') +
        ') WITH USER_MODE LIMIT 150';
      for (Account row : Database.query(soql)) {
        byId.put(row.Id, row);
      }
    }
    if (String.isNotBlank(phoneLike) && !phoneFields().isEmpty()) {
      String soql =
        selectClause +
        'WHERE Id != :sourceId AND (' +
        phoneLikeClause() +
        ') WITH USER_MODE LIMIT 40';
      for (Account row : Database.query(soql)) {
        byId.put(row.Id, row);
      }
    }
    if (source.BillingLatitude != null && source.BillingLongitude != null) {
      Decimal latMin = source.BillingLatitude - 0.08;
      Decimal latMax = source.BillingLatitude + 0.08;
      Decimal lngMin = source.BillingLongitude - 0.08;
      Decimal lngMax = source.BillingLongitude + 0.08;
      String soql =
        selectClause +
        'WHERE Id != :sourceId AND BillingLatitude >= :latMin AND BillingLatitude <= :latMax ' +
        'AND BillingLongitude >= :lngMin AND BillingLongitude <= :lngMax WITH USER_MODE LIMIT 40';
      for (Account row : Database.query(soql)) {
        byId.put(row.Id, row);
      }
    }
    return byId.values();
  }

  private static String phoneOrClause(Integer size) {
    List<String> binds = new List<String>{ ':phone0', ':phone1', ':phone2', ':phone3' };
    List<String> parts = new List<String>();
    List<String> fields = phoneFields();
    for (Integer i = 0; i < size; i++) {
      for (String fieldName : fields) {
        parts.add(fieldName + ' = ' + binds[i]);
      }
    }
    return '(' + String.join(parts, ' OR ') + ')';
  }

  private static String phoneLikeClause() {
    List<String> parts = new List<String>();
    for (String fieldName : phoneFields()) {
      parts.add(fieldName + ' LIKE :phoneLike');
    }
    return String.join(parts, ' OR ');
  }

  private static List<String> phoneFields() {
    List<String> fields = new List<String>();
    if (canFilter('Phone')) fields.add('Phone');
    for (String extra : new List<String>{ 'PersonMobilePhone', 'Clinic_Phone__c', 'Maps_Phone_Number__c', 'WhatsApp_Number__c' }) {
      if (canFilter(extra)) fields.add(extra);
    }
    return fields;
  }

  private static List<String> queryFields() {
    List<String> fields = new List<String>{
      'Id',
      'Name',
      'Phone',
      'BillingCity',
      'BillingStreet',
      'BillingLatitude',
      'BillingLongitude',
      'RecordTypeId',
      'RecordType.Name',
      'RecordType.DeveloperName',
      'IsPersonAccount'
    };
    for (String extra : new List<String>{
      'PersonMobilePhone',
      'Clinic_Phone__c',
      'Maps_Phone_Number__c',
      'WhatsApp_Number__c',
      'Governorate__c',
      'Account_Stage__c',
      'Duplicate_Of__c',
      'Brick__c'
    }) {
      if (hasField(extra)) {
        fields.add(extra);
      }
    }
    if (hasField('Duplicate_Of__c')) {
      fields.add('Duplicate_Of__r.Name');
    }
    if (hasField('Brick__c')) {
      fields.add('Brick__r.Name');
    }
    return fields;
  }

  private static Account queryAccount(Id accountId) {
    String soql = 'SELECT ' + String.join(queryFields(), ', ') + ' FROM Account WHERE Id = :accountId WITH USER_MODE LIMIT 1';
    List<Account> rows = Database.query(soql);
    return rows.isEmpty() ? null : rows[0];
  }

  private static Integer nameScore(String leftRaw, String rightRaw) {
    return Math.max(literalNameScore(leftRaw, rightRaw), AccountCognitiveSearch.scoreAlignedNames(leftRaw, rightRaw));
  }

  private static String cognitiveNameClause(String sourceName) {
    List<String> tokens = new List<String>();
    for (String token : AccountCognitiveSearch.tokenize(sourceName)) {
      String folded = AccountCognitiveSearch.foldName(token);
      if (String.isBlank(folded) || folded.length() < 3 || STOP_TOKENS.contains(folded)) {
        continue;
      }
      tokens.add(token);
      if (tokens.size() == 4) {
        break;
      }
    }
    if (tokens.isEmpty()) {
      return null;
    }
    List<String> fields = new List<String>{ 'Name' };
    if (canFilter('FirstName')) {
      fields.add('FirstName');
    }
    if (canFilter('LastName')) {
      fields.add('LastName');
    }
    List<String> groups = new List<String>();
    for (String token : tokens) {
      List<String> likes = new List<String>();
      for (String needle : AccountCognitiveSearch.searchNeedles(token)) {
        String literal = likeContains(needle);
        if (String.isBlank(literal)) {
          continue;
        }
        for (String fieldName : fields) {
          likes.add(fieldName + ' LIKE ' + literal);
        }
      }
      if (!likes.isEmpty()) {
        groups.add('(' + String.join(likes, ' OR ') + ')');
      }
    }
    return groups.isEmpty() ? null : '(' + String.join(groups, ' AND ') + ')';
  }

  private static String likeContains(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String safe = raw.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    return '\'%' + String.escapeSingleQuotes(safe) + '%\'';
  }

  private static Integer literalNameScore(String leftRaw, String rightRaw) {
    String left = normalizeName(leftRaw);
    String right = normalizeName(rightRaw);
    if (String.isBlank(left) || String.isBlank(right)) {
      return 0;
    }
    if (left == right) {
      return 100;
    }
    Integer shorter = Math.min(left.length(), right.length());
    Integer longer = Math.max(left.length(), right.length());
    if (shorter >= 4 && (left.contains(right) || right.contains(left)) && shorter * 100 / longer >= 60) {
      return 88;
    }
    Set<String> leftTokens = significantTokens(left);
    Set<String> rightTokens = significantTokens(right);
    Integer tokenScore = 0;
    if (!leftTokens.isEmpty() && !rightTokens.isEmpty()) {
      Integer overlap = 0;
      for (String token : leftTokens) {
        if (rightTokens.contains(token)) {
          overlap++;
        }
      }
      Integer unionSize = leftTokens.size() + rightTokens.size() - overlap;
      tokenScore = unionSize == 0 ? 0 : overlap * 100 / unionSize;
      if (overlap > 0 && overlap == Math.min(leftTokens.size(), rightTokens.size()) && shorter >= 8) {
        tokenScore = Math.max(tokenScore, 84);
      }
    }
    Integer editScore = 0;
    if (left.length() <= 48 && right.length() <= 48) {
      Integer maxLen = Math.max(left.length(), right.length());
      Integer distance = levenshtein(left, right);
      editScore = maxLen == 0 ? 0 : (maxLen - distance) * 100 / maxLen;
    }
    Integer best = Math.max(tokenScore, editScore);
    return best >= 72 ? best : 0;
  }

  private static Integer mobileScore(Set<String> left, Set<String> right) {
    if (left.isEmpty() || right.isEmpty()) {
      return 0;
    }
    for (String phone : left) {
      if (right.contains(phone) && phone.length() >= 8) {
        return 100;
      }
    }
    for (String phone : left) {
      for (String other : right) {
        if (phone.length() >= 8 && other.length() >= 8 && (phone.endsWith(other) || other.endsWith(phone))) {
          return 80;
        }
      }
    }
    return 0;
  }

  private static Integer typeScore(Account source, Account candidate) {
    if (source.RecordTypeId != null && source.RecordTypeId == candidate.RecordTypeId) {
      return 100;
    }
    String left = source.RecordType == null ? null : source.RecordType.DeveloperName;
    String right = candidate.RecordType == null ? null : candidate.RecordType.DeveloperName;
    if (String.isNotBlank(left) && left == right) {
      return 100;
    }
    return 0;
  }

  private static Integer locationScore(Account source, Account candidate) {
    Integer best = 0;
    if (
      source.BillingLatitude != null &&
      source.BillingLongitude != null &&
      candidate.BillingLatitude != null &&
      candidate.BillingLongitude != null
    ) {
      Decimal km = distanceKm(
        source.BillingLatitude,
        source.BillingLongitude,
        candidate.BillingLatitude,
        candidate.BillingLongitude
      );
      if (km <= 0.2) best = 100;
      else if (km <= 0.8) best = 85;
      else if (km <= 3) best = 60;
      else if (km <= 12) best = 30;
    }
    Id leftBrick = brickId(source);
    Id rightBrick = brickId(candidate);
    if (leftBrick != null && leftBrick == rightBrick) {
      best = Math.max(best, 80);
    }
    String leftCity = normalizeName(source.BillingCity);
    String rightCity = normalizeName(candidate.BillingCity);
    String leftGov = normalizeName(stringField(source, 'Governorate__c'));
    String rightGov = normalizeName(stringField(candidate, 'Governorate__c'));
    Boolean samePlace =
      (String.isNotBlank(leftCity) && leftCity == rightCity) ||
      (String.isNotBlank(leftGov) && leftGov == rightGov);
    if (samePlace && streetSimilar(source.BillingStreet, candidate.BillingStreet)) {
      best = Math.max(best, 90);
    } else if (samePlace) {
      best = Math.max(best, 45);
    }
    return best;
  }

  private static Boolean streetSimilar(String leftRaw, String rightRaw) {
    String left = normalizeName(leftRaw);
    String right = normalizeName(rightRaw);
    if (String.isBlank(left) || String.isBlank(right)) {
      return false;
    }
    if (left == right || left.contains(right) || right.contains(left)) {
      return true;
    }
    Integer maxLen = Math.max(left.length(), right.length());
    if (maxLen > 60) {
      return false;
    }
    Integer distance = levenshtein(left, right);
    return (maxLen - distance) * 100 / maxLen >= 70;
  }

  private static Decimal distanceKm(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
    Double earth = 6371.0;
    Double dLat = toRad((Double) (lat2 - lat1));
    Double dLon = toRad((Double) (lon2 - lon1));
    Double lat1Rad = toRad((Double) lat1);
    Double lat2Rad = toRad((Double) lat2);
    Double a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1Rad) * Math.cos(lat2Rad) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return Decimal.valueOf(earth * c);
  }

  private static Double toRad(Double degrees) {
    return degrees * Math.PI / 180;
  }

  private static Set<String> phonesOf(Account account) {
    Set<String> phones = new Set<String>();
    addPhone(phones, account.Phone);
    addPhone(phones, stringField(account, 'PersonMobilePhone'));
    addPhone(phones, stringField(account, 'Clinic_Phone__c'));
    addPhone(phones, stringField(account, 'Maps_Phone_Number__c'));
    addPhone(phones, stringField(account, 'WhatsApp_Number__c'));
    return phones;
  }

  private static Set<String> storedPhones(Account account) {
    Set<String> phones = new Set<String>();
    addRaw(phones, account.Phone);
    addRaw(phones, stringField(account, 'PersonMobilePhone'));
    addRaw(phones, stringField(account, 'Clinic_Phone__c'));
    addRaw(phones, stringField(account, 'Maps_Phone_Number__c'));
    addRaw(phones, stringField(account, 'WhatsApp_Number__c'));
    return phones;
  }

  private static void addRaw(Set<String> phones, String value) {
    if (String.isNotBlank(value)) {
      phones.add(value.trim());
    }
  }

  private static void addPhone(Set<String> phones, String value) {
    String digits = value == null ? '' : value.replaceAll('\\D', '');
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('20') && digits.length() > 10) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length() > 10) {
      digits = digits.substring(digits.length() - 10);
    }
    if (digits.length() >= 8) {
      phones.add(digits);
    }
  }

  private static String phoneTailLike(Account source) {
    Set<String> phones = phonesOf(source);
    if (phones.isEmpty()) {
      return null;
    }
    String tail = new List<String>(phones)[0];
    if (tail.length() < 8) {
      return null;
    }
    return '%' + tail.right(8);
  }

  private static String displayPhone(Account account) {
    for (String value : new List<String>{
      stringField(account, 'PersonMobilePhone'),
      account.Phone,
      stringField(account, 'WhatsApp_Number__c'),
      stringField(account, 'Clinic_Phone__c'),
      stringField(account, 'Maps_Phone_Number__c')
    }) {
      if (String.isNotBlank(value)) {
        return value;
      }
    }
    return '—';
  }

  private static String displayLocation(Account account) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(account.BillingStreet)) parts.add(account.BillingStreet);
    if (String.isNotBlank(account.BillingCity)) parts.add(account.BillingCity);
    String governorate = stringField(account, 'Governorate__c');
    if (String.isNotBlank(governorate) && governorate != account.BillingCity) parts.add(governorate);
    SObject brick = hasField('Brick__c') ? account.getSObject('Brick__r') : null;
    if (brick != null && brick.get('Name') != null) parts.add(String.valueOf(brick.get('Name')));
    return parts.isEmpty() ? '—' : String.join(parts, ', ');
  }

  private static Id brickId(Account account) {
    if (!hasField('Brick__c')) {
      return null;
    }
    return (Id) account.get('Brick__c');
  }

  private static String stringField(Account account, String fieldName) {
    if (!hasField(fieldName)) {
      return null;
    }
    Object value = account.get(fieldName);
    return value == null ? null : String.valueOf(value);
  }

  private static String namePrefix(String name) {
    for (String token : significantTokens(normalizeName(name))) {
      if (token.length() >= 3) {
        return token + '%';
      }
    }
    return null;
  }

  private static Set<String> significantTokens(String normalized) {
    Set<String> tokens = new Set<String>();
    if (String.isBlank(normalized)) {
      return tokens;
    }
    for (String token : normalized.split(' ')) {
      if (String.isBlank(token) || token.length() < 2 || STOP_TOKENS.contains(token)) {
        continue;
      }
      tokens.add(token);
    }
    return tokens;
  }

  private static String normalizeName(String value) {
    if (String.isBlank(value)) {
      return '';
    }
    String text = value.toLowerCase().replaceAll('[^\\p{L}\\p{N}\\s]', ' ');
    return text.replaceAll('\\s+', ' ').trim();
  }

  private static Integer levenshtein(String left, String right) {
    Integer n = left.length();
    Integer m = right.length();
    List<Integer> prev = new List<Integer>();
    List<Integer> curr = new List<Integer>();
    for (Integer j = 0; j <= m; j++) {
      prev.add(j);
      curr.add(0);
    }
    for (Integer i = 1; i <= n; i++) {
      curr[0] = i;
      for (Integer j = 1; j <= m; j++) {
        Integer cost = left.substring(i - 1, i) == right.substring(j - 1, j) ? 0 : 1;
        Integer deleteCost = prev[j] + 1;
        Integer insertCost = curr[j - 1] + 1;
        Integer replaceCost = prev[j - 1] + cost;
        curr[j] = Math.min(deleteCost, Math.min(insertCost, replaceCost));
      }
      List<Integer> swap = prev;
      prev = curr;
      curr = swap;
    }
    return prev[m];
  }

  private static Boolean hasField(String fieldName) {
    Schema.DescribeFieldResult describe = describeField(fieldName);
    return describe != null && describe.isAccessible();
  }

  private static Boolean canFilter(String fieldName) {
    Schema.DescribeFieldResult describe = describeField(fieldName);
    return describe != null && describe.isAccessible() && describe.isFilterable();
  }

  private static Schema.DescribeFieldResult describeField(String fieldName) {
    if (String.isBlank(fieldName)) {
      return null;
    }
    Map<String, Schema.SObjectField> fields = Schema.SObjectType.Account.fields.getMap();
    if (!fields.containsKey(fieldName)) {
      return null;
    }
    return fields.get(fieldName).getDescribe();
  }

  private static AuraHandledException error(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }

  private static final Set<String> STOP_TOKENS = new Set<String>{
    'dr', 'doctor', 'prof', 'mr', 'mrs', 'ms', 'pharmacy', 'clinic', 'hospital', 'center', 'centre',
    'medical', 'lab', 'the', 'and', 'of', 'al', 'el',
    'صيدلية', 'صيدليه', 'مستشفى', 'مستشفي', 'مركز', 'عيادة', 'عياده', 'دكتور', 'الدكتور'
  };

  private class ScoredSort implements System.Comparator<Scored> {
    public Integer compare(Scored left, Scored right) {
      Integer l = left == null || left.percent == null ? 0 : left.percent;
      Integer r = right == null || right.percent == null ? 0 : right.percent;
      return r - l;
    }
  }
}