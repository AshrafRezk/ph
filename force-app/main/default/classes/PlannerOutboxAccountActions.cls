/**
 * Server-side handlers for account / consent actions queued by the offline PWA outbox
 * (PlannerMobileRestService.processOutboxAction).
 *
 * The PWA also sends a pre-computed PATCH `body` (stage, status, history text, ...).
 * That body is NEVER applied. Only the intent (account ids, reason, ratings values) is read
 * from the payload; stage, status, history, owner, territory and timestamps are recomputed here
 * by the same services the Lightning UI uses. Everything runs as the calling user
 * (with sharing + USER_MODE), so FLS / sharing still apply.
 */
public with sharing class PlannerOutboxAccountActions {
  public class ActionException extends Exception {}

  private static final Integer CONSENT_MAX_AGE_DAYS = 30;

  // ---------------------------------------------------------------- MARK_ACCOUNT_DUPLICATE
  public static void markDuplicate(Map<String, Object> payload) {
    Id accountId = requireId(payload.get('accountId'), 'Account');
    Id duplicateOfId = requireId(payload.get('duplicateOfId'), 'Original account');
    Account current = loadAccount(accountId);
    if (
      AccountStageService.STAGE_DUPLICATE == stageOf(current) &&
      current.Duplicate_Of__c == duplicateOfId
    ) {
      return; // Already applied (e.g. response lost on a previous drain).
    }
    try {
      AccountStageService.reportDuplicate(accountId, duplicateOfId);
    } catch (Exception e) {
      throw new ActionException(e.getMessage());
    }
  }

  // ---------------------------------------------------------------- MARK_ACCOUNT_INACTIVE
  public static void markInactive(Map<String, Object> payload) {
    Id accountId = requireId(payload.get('accountId'), 'Account');
    String reason = resolveInactiveReason(asString(payload.get('reason')));
    Account current = loadAccount(accountId);
    if (AccountStageService.STAGE_INACTIVE == stageOf(current) && current.Inactive_Reason__c == reason) {
      return;
    }
    try {
      AccountStageService.markInactive(accountId, reason);
    } catch (Exception e) {
      throw new ActionException(e.getMessage());
    }
  }

  // ---------------------------------------------------------------- ADVANCE_ACCOUNT_STAGE
  /**
   * The client only states which transition it believes it made (fromStage -> toStage).
   * The server advances exactly one step from the stage the record is really in, and refuses
   * to run when the record moved on in the meantime so no stage is ever skipped.
   */
  public static void advanceStage(Map<String, Object> payload) {
    Id accountId = requireId(payload.get('accountId'), 'Account');
    String fromStage = asString(payload.get('fromStage'));
    String toStage = asString(payload.get('toStage'));
    Account current = loadAccount(accountId);
    String currentStage = stageOf(current);
    if (String.isNotBlank(toStage) && currentStage == toStage && currentStage != fromStage) {
      return; // Already advanced.
    }
    if (String.isNotBlank(fromStage) && currentStage != fromStage) {
      throw new ActionException(
        'Account stage changed on the server (now ' + currentStage + '). Open the account and advance it again.'
      );
    }
    try {
      AccountStageService.advance(accountId);
    } catch (Exception e) {
      throw new ActionException(e.getMessage());
    }
  }

  // ---------------------------------------------------------------- SAVE_ACCOUNT_RATINGS
  /**
   * Values go through ClmMetricsController.saveAccountRatings -> ClmRatingLayoutService, which
   * recomputes Matrix_Rating__c / Classification__c and resolves the account's territory rows.
   * A client-supplied territory is only honoured when the running user is assigned to it;
   * otherwise the server resolves the territory itself. The client `pending` cache is ignored.
   */
  public static void saveRatings(Map<String, Object> payload) {
    Id accountId = requireId(payload.get('accountId'), 'Account');
    loadAccount(accountId); // Visibility check (USER_MODE).
    Id layoutId = optionalId(payload.get('layoutId'));
    Id territory2Id = validatedUserTerritory(optionalId(payload.get('territory2Id')));
    String fieldInputsJson = jsonText(payload.get('fieldInputsJson'));
    String productRatingsJson = jsonText(payload.get('productRatingsJson'));
    if (String.isBlank(fieldInputsJson) && String.isBlank(productRatingsJson)) {
      throw new ActionException('No rating values were provided.');
    }
    try {
      ClmMetricsController.saveAccountRatings(
        accountId,
        layoutId,
        territory2Id,
        fieldInputsJson,
        productRatingsJson
      );
    } catch (Exception e) {
      throw new ActionException(e.getMessage());
    }
  }

  // ---------------------------------------------------------------- CAPTURE_CONSENT
  /**
   * Visit_Consent__c is not part of every org, so it is addressed dynamically and the action fails
   * with a clear message (instead of a compile dependency) where the object is not deployed.
   * Account is taken from the visit, never from the client; channel / type / status are checked
   * against the picklists; a "Granted" consent needs a signature; Captured_At__c is only honoured
   * when it is a believable offline capture time (not in the future, not older than 30 days).
   */
  public static void captureConsent(Map<String, Object> payload) {
    Id visitId = requireId(payload.get('Visit__c') != null ? payload.get('Visit__c') : payload.get('visitId'), 'Visit');
    String status = String.isBlank(asString(payload.get('Status__c'))) ? 'Granted' : asString(payload.get('Status__c'));
    String signature = asString(payload.get('Signature_Data__c'));
    if (status == 'Granted' && String.isBlank(signature)) {
      throw new ActionException('Capture a signature before granting consent.');
    }
    List<Visit__c> visits = [
      SELECT Id, Account__c, Status__c
      FROM Visit__c
      WHERE Id = :visitId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visits.isEmpty()) {
      throw new ActionException('Visit not found.');
    }
    Visit__c visit = visits[0];
    if (visit.Status__c == 'Cancelled') {
      throw new ActionException('Cancelled visits cannot capture new consent.');
    }
    Datetime capturedAt = boundedCapturedAt(asString(payload.get('Captured_At__c')));

    Schema.SObjectType consentType = Schema.getGlobalDescribe().get('Visit_Consent__c');
    if (consentType == null) {
      throw new ActionException('Visit consent capture is not available in this org (Visit_Consent__c is not deployed).');
    }
    String channel = pickValue(consentType, 'Channel__c', asString(payload.get('Channel__c')), 'channel');
    String consentTypeValue = pickValue(
      consentType,
      'Consent_Type__c',
      asString(payload.get('Consent_Type__c')),
      'consent type'
    );
    status = pickValue(consentType, 'Status__c', status, 'status');

    // Idempotency: the same capture replayed after a lost response must not duplicate.
    Map<String, Object> binds = new Map<String, Object>{
      'visitId' => visit.Id,
      'channel' => channel,
      'consentType' => consentTypeValue,
      'capturedAt' => capturedAt
    };
    List<SObject> existing = Database.queryWithBinds(
      'SELECT Id FROM Visit_Consent__c WHERE Visit__c = :visitId AND Channel__c = :channel ' +
        'AND Consent_Type__c = :consentType AND Captured_At__c = :capturedAt LIMIT 1',
      binds,
      AccessLevel.USER_MODE
    );
    if (!existing.isEmpty()) {
      return;
    }

    SObject record = consentType.newSObject();
    Map<String, Object> values = new Map<String, Object>{
      'Visit__c' => visit.Id,
      'Account__c' => visit.Account__c,
      'Channel__c' => channel,
      'Consent_Type__c' => consentTypeValue,
      'Status__c' => status,
      'Captured_At__c' => capturedAt,
      'Signature_Data__c' => signature,
      'Notes__c' => asString(payload.get('Notes__c'))
    };
    for (String field : values.keySet()) {
      record.put(field, values.get(field));
    }
    try {
      insert as user record;
    } catch (DmlException e) {
      throw new ActionException(e.getDmlMessage(0));
    }
  }

  // ---------------------------------------------------------------- helpers
  private static Account loadAccount(Id accountId) {
    List<Account> rows = [
      SELECT Id, Account_Stage__c, Duplicate_Of__c, Inactive_Reason__c
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new ActionException('Account not found.');
    }
    return rows[0];
  }

  private static String stageOf(Account record) {
    return String.isBlank(record.Account_Stage__c) ? AccountStageService.STAGE_DRAFT : record.Account_Stage__c;
  }

  private static String resolveInactiveReason(String input) {
    if (String.isBlank(input)) {
      throw new ActionException('Choose an inactive reason.');
    }
    for (Schema.PicklistEntry entry : Account.Inactive_Reason__c.getDescribe().getPicklistValues()) {
      if (entry.isActive() && (entry.getValue() == input || entry.getLabel() == input)) {
        return entry.getValue();
      }
    }
    throw new ActionException('Inactive reason "' + input + '" is not valid.');
  }

  @TestVisible
  private static String pickValue(Schema.SObjectType sobjectType, String fieldName, String input, String label) {
    if (String.isBlank(input)) {
      throw new ActionException('Select a ' + label + '.');
    }
    Schema.SObjectField field = sobjectType.getDescribe().fields.getMap().get(fieldName);
    if (field == null) {
      return input;
    }
    List<Schema.PicklistEntry> entries = field.getDescribe().getPicklistValues();
    if (entries.isEmpty()) {
      return input;
    }
    for (Schema.PicklistEntry entry : entries) {
      if (entry.isActive() && (entry.getValue() == input || entry.getLabel() == input)) {
        return entry.getValue();
      }
    }
    throw new ActionException('The ' + label + ' "' + input + '" is not valid.');
  }

  @TestVisible
  private static Datetime boundedCapturedAt(String iso) {
    Datetime now = Datetime.now();
    if (String.isBlank(iso)) {
      return now;
    }
    try {
      Datetime parsed = (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
      if (parsed > now || parsed < now.addDays(-CONSENT_MAX_AGE_DAYS)) {
        return now;
      }
      return parsed;
    } catch (Exception e) {
      return now;
    }
  }

  private static Id validatedUserTerritory(Id territory2Id) {
    if (territory2Id == null) {
      return null;
    }
    List<UserTerritory2Association> rows = [
      SELECT Territory2Id
      FROM UserTerritory2Association
      WHERE UserId = :UserInfo.getUserId() AND Territory2Id = :territory2Id
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : territory2Id;
  }

  private static String jsonText(Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof String) {
      return String.isBlank((String) value) ? null : (String) value;
    }
    return JSON.serialize(value);
  }

  private static String asString(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static Id optionalId(Object value) {
    String raw = asString(value);
    if (String.isBlank(raw) || !Pattern.matches('[a-zA-Z0-9]{15}|[a-zA-Z0-9]{18}', raw.trim())) {
      return null;
    }
    try {
      return Id.valueOf(raw.trim());
    } catch (Exception e) {
      return null;
    }
  }

  private static Id requireId(Object value, String label) {
    Id parsed = optionalId(value);
    if (parsed == null) {
      throw new ActionException(label + ' is not saved on the server yet or has an invalid Id.');
    }
    return parsed;
  }
}
