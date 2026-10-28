/**
 * Covers the outbox action types the PWA queues beyond the planner basics
 * (critical issue 47): call report, CLM session lifecycle, account stage / ratings, consent.
 */
@IsTest
private class PlannerMobileRestServiceOutboxTest {
  @TestSetup
  static void setupData() {
    Account account = new Account(Name = 'Outbox Visit Account');
    insert account;
    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.now(),
      End_Date__c = DateTime.now().addHours(1),
      Visit_Date__c = DateTime.now(),
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert new CLM_Presentation__c(
      Name = 'Outbox Deck',
      Status__c = 'Available',
      Format__c = 'PDF',
      Slide_Count__c = 1,
      Allow_Unaligned__c = true
    );
  }

  // ------------------------------------------------------------------ helpers
  private static Map<String, Object> action(String type, String key) {
    return new Map<String, Object>{ 'actionType' => type, 'clientActionKey' => key };
  }

  private static Map<String, Object> post(List<Map<String, Object>> actions) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/planner/v1/outbox';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'actions' => actions }));
    RestContext.request = req;
    RestContext.response = res;
    Test.startTest();
    PlannerMobileRestService.doPost();
    Test.stopTest();
    System.assertEquals(200, res.statusCode, res.responseBody == null ? 'no body' : res.responseBody.toString());
    return (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
  }

  private static Map<String, Object> resultAt(Map<String, Object> response, Integer index) {
    return (Map<String, Object>) ((List<Object>) response.get('results'))[index];
  }

  private static void assertOk(Map<String, Object> response, Integer index) {
    Map<String, Object> r = resultAt(response, index);
    System.assertEquals(true, r.get('success'), 'Action ' + index + ' failed: ' + r.get('error'));
  }

  private static String errorAt(Map<String, Object> response, Integer index) {
    Map<String, Object> r = resultAt(response, index);
    System.assertEquals(false, r.get('success'), 'Action ' + index + ' was expected to fail.');
    return String.valueOf(r.get('error'));
  }

  private static Visit__c visit() {
    return [SELECT Id, Account__c FROM Visit__c LIMIT 1];
  }

  private static CLM_Presentation__c presentation() {
    CLM_Presentation__c p = [SELECT Id FROM CLM_Presentation__c LIMIT 1];
    if ([SELECT COUNT() FROM CLM_Sequence__c WHERE CLM_Presentation__c = :p.Id] == 0) {
      insert new CLM_Sequence__c(
        CLM_Presentation__c = p.Id,
        Sequence_Order__c = 1,
        Sequence_Name__c = 'Intro',
        Name = 'Intro',
        Page_Number__c = 1,
        File_Name__c = 'outbox.pdf'
      );
    }
    return p;
  }

  private static Id startSessionDirect(Id visitId, Id presentationId) {
    return ClmMetricsController.startSession(visitId, presentationId).id;
  }

  private static Account newAccount(String name, String stage) {
    Account a = new Account(Name = name, Account_Stage__c = stage);
    insert a;
    return a;
  }

  // ------------------------------------------------------------------ SAVE_CALL_REPORT
  @IsTest
  static void saveCallReport_savesThroughVisitCallReportService() {
    Visit__c v = visit();
    Account acc = [SELECT Id, Name FROM Account WHERE Id = :v.Account__c];
    Map<String, Object> request = new Map<String, Object>{
      'visitId' => v.Id,
      'status' => 'Draft',
      'visitObjective' => 'Saved via outbox',
      'attendees' => new List<Object>{
        new Map<String, Object>{
          'accountId' => acc.Id,
          'accountName' => acc.Name,
          'isPrimary' => true,
          'displayOrder' => 1
        }
      },
      'products' => new List<Object>(),
      'samples' => new List<Object>(),
      'clmSessions' => new List<Object>()
    };
    Map<String, Object> a = action('SAVE_CALL_REPORT', 'save_call_' + v.Id);
    a.put('visitId', v.Id);
    a.put('callReportJson', JSON.serialize(request));

    Map<String, Object> response = post(new List<Map<String, Object>>{ a });
    assertOk(response, 0);
    System.assertEquals('Saved via outbox', [SELECT Visit_Objective__c FROM Visit__c WHERE Id = :v.Id].Visit_Objective__c);
  }

  @IsTest
  static void saveCallReport_rejectsMissingBodyUnsavedVisitAndMismatch() {
    Visit__c v = visit();
    Map<String, Object> noBody = action('SAVE_CALL_REPORT', 'no_body');
    Map<String, Object> localVisit = action('SAVE_CALL_REPORT', 'local_visit');
    localVisit.put('callReportJson', JSON.serialize(new Map<String, Object>{ 'visitId' => 'local_visit_1', 'status' => 'Draft' }));
    Map<String, Object> mismatch = action('SAVE_CALL_REPORT', 'mismatch');
    mismatch.put('visitId', v.Id);
    mismatch.put('callReportJson', JSON.serialize(new Map<String, Object>{ 'visitId' => v.Account__c, 'status' => 'Draft' }));

    Map<String, Object> response = post(new List<Map<String, Object>>{ noBody, localVisit, mismatch });
    System.assert(errorAt(response, 0).contains('callReportJson is required'));
    System.assert(errorAt(response, 1).contains('not saved on the server'));
    System.assert(errorAt(response, 2).contains('does not match'));
  }

  // ------------------------------------------------------------------ CLM session actions
  @IsTest
  static void startSession_createsSessionAndReturnsClientKeyMapping() {
    Visit__c v = visit();
    CLM_Presentation__c p = presentation();
    Map<String, Object> a = action('START_SESSION', 'start_1');
    a.put('clientSessionKey', 'local_session_1');
    a.put('visitId', v.Id);
    a.put('presentationId', p.Id);

    Map<String, Object> response = post(new List<Map<String, Object>>{ a });
    assertOk(response, 0);
    Map<String, Object> sessionMap = (Map<String, Object>) response.get('sessionIdByClientKey');
    System.assert(sessionMap.containsKey('local_session_1'));
    Id sessionId = (Id) String.valueOf(sessionMap.get('local_session_1'));
    System.assertEquals(1, [SELECT COUNT() FROM CLM_Presentation_Session__c WHERE Id = :sessionId]);
  }

  @IsTest
  static void startAdhocSession_createsSessionAndVisitMapping() {
    CLM_Presentation__c p = presentation();
    Map<String, Object> a = action('START_ADHOC_SESSION', 'adhoc_1');
    a.put('clientSessionKey', 'local_adhoc_1');
    a.put('clientVisitKey', 'local_adhoc_visit_1');
    a.put('presentationId', p.Id);

    Map<String, Object> response = post(new List<Map<String, Object>>{ a });
    assertOk(response, 0);
    System.assert(((Map<String, Object>) response.get('sessionIdByClientKey')).containsKey('local_adhoc_1'));
    System.assert(((Map<String, Object>) resultAt(response, 0).get('visitIdByClientKey')).containsKey('local_adhoc_visit_1'));
  }

  @IsTest
  static void logSlideEvent_usesSessionStartedEarlierInSameBatch() {
    Visit__c v = visit();
    CLM_Presentation__c p = presentation();
    CLM_Sequence__c seq = [SELECT Id FROM CLM_Sequence__c WHERE CLM_Presentation__c = :p.Id LIMIT 1];
    Map<String, Object> start = action('START_SESSION', 'start_2');
    start.put('clientSessionKey', 'local_session_2');
    start.put('visitId', v.Id);
    start.put('presentationId', p.Id);
    Map<String, Object> slide = action('LOG_SLIDE_EVENT', 'slide_2');
    slide.put('clientSessionKey', 'local_session_2');
    slide.put('sequenceId', seq.Id);
    slide.put('dwellSeconds', 12);
    slide.put('trackingPaused', false);

    Map<String, Object> response = post(new List<Map<String, Object>>{ start, slide });
    assertOk(response, 0);
    assertOk(response, 1);
  }

  @IsTest
  static void logSlideEvent_failsWithoutResolvableSession() {
    Map<String, Object> slide = action('LOG_SLIDE_EVENT', 'slide_bad');
    slide.put('clientSessionKey', 'not_a_real_session');
    Map<String, Object> response = post(new List<Map<String, Object>>{ slide });
    System.assert(errorAt(response, 0).contains('Session Id is required'));
  }

  @IsTest
  static void saveMessageResponses_savesForSession() {
    Visit__c v = visit();
    CLM_Presentation__c p = presentation();
    Id sessionId = startSessionDirect(v.Id, p.Id);
    Map<String, Object> a = action('SAVE_MESSAGE_RESPONSES', 'msg_1');
    a.put('clientSessionKey', String.valueOf(sessionId));
    a.put(
      'responsesJson',
      JSON.serialize(
        new List<Object>{
          new Map<String, Object>{
            'productName' => 'Prod',
            'messageName' => 'Efficacy',
            'sentiment' => 'Positive',
            'sortOrder' => 1
          }
        }
      )
    );
    Map<String, Object> response = post(new List<Map<String, Object>>{ a });
    assertOk(response, 0);
  }

  @IsTest
  static void completeSession_completesSession() {
    Visit__c v = visit();
    CLM_Presentation__c p = presentation();
    Id sessionId = startSessionDirect(v.Id, p.Id);
    Map<String, Object> a = action('COMPLETE_SESSION', 'complete_1');
    a.put('clientSessionKey', String.valueOf(sessionId));
    Map<String, Object> response = post(new List<Map<String, Object>>{ a });
    assertOk(response, 0);
  }

  @IsTest
  static void cancelSession_cancelsAdhocSessionStartedInSameBatch() {
    CLM_Presentation__c p = presentation();
    Map<String, Object> start = action('START_ADHOC_SESSION', 'adhoc_2');
    start.put('clientSessionKey', 'local_adhoc_2');
    start.put('clientVisitKey', 'local_adhoc_visit_2');
    start.put('presentationId', p.Id);
    Map<String, Object> cancel = action('CANCEL_SESSION', 'cancel_2');
    cancel.put('clientSessionKey', 'local_adhoc_2');
    Map<String, Object> response = post(new List<Map<String, Object>>{ start, cancel });
    assertOk(response, 0);
    assertOk(response, 1);
  }

  @IsTest
  static void sessionActions_withoutSessionFailWithoutAbortingBatch() {
    Map<String, Object> complete = action('COMPLETE_SESSION', 'complete_bad');
    Map<String, Object> cancel = action('CANCEL_SESSION', 'cancel_bad');
    Map<String, Object> messages = action('SAVE_MESSAGE_RESPONSES', 'msg_bad');
    messages.put('responsesJson', '[]');
    Map<String, Object> unknown = action('FUTURE_ACTION', 'future_1');
    Map<String, Object> response = post(new List<Map<String, Object>>{ complete, cancel, messages, unknown });
    errorAt(response, 0);
    errorAt(response, 1);
    errorAt(response, 2);
    System.assert(errorAt(response, 3).contains('Unsupported outbox action'));
  }

  // ------------------------------------------------------------------ account actions
  @IsTest
  static void advanceAccountStage_advancesOneStepAndIgnoresClientBody() {
    Account a = newAccount('Advance Me', 'Draft');
    Map<String, Object> act = action('ADVANCE_ACCOUNT_STAGE', 'advance_1');
    act.put(
      'payloadJson',
      JSON.serialize(
        new Map<String, Object>{
          'accountId' => a.Id,
          'fromStage' => 'Draft',
          'toStage' => 'Pending DM',
          'history' => 'forged history',
          'body' => new Map<String, Object>{ 'Account_Stage__c' => 'Active' }
        }
      )
    );
    Map<String, Object> response = post(new List<Map<String, Object>>{ act });
    assertOk(response, 0);
    Account after = [SELECT Account_Stage__c, Stage_History__c FROM Account WHERE Id = :a.Id];
    System.assertEquals('Pending DM', after.Account_Stage__c);
    System.assert(!String.valueOf(after.Stage_History__c).contains('forged'));
  }

  @IsTest
  static void advanceAccountStage_refusesWhenServerStageMovedAndIsIdempotent() {
    Account a = newAccount('Moved On', 'Pending SFE');
    Map<String, Object> stale = action('ADVANCE_ACCOUNT_STAGE', 'advance_stale');
    stale.put(
      'payloadJson',
      JSON.serialize(new Map<String, Object>{ 'accountId' => a.Id, 'fromStage' => 'Draft', 'toStage' => 'Pending DM' })
    );
    Map<String, Object> replay = action('ADVANCE_ACCOUNT_STAGE', 'advance_replay');
    replay.put(
      'payloadJson',
      JSON.serialize(new Map<String, Object>{ 'accountId' => a.Id, 'fromStage' => 'Pending DM', 'toStage' => 'Pending SFE' })
    );
    Map<String, Object> response = post(new List<Map<String, Object>>{ stale, replay });
    System.assert(errorAt(response, 0).contains('stage changed'));
    assertOk(response, 1); // Already at toStage: replay is a no-op, not a second advance.
    System.assertEquals('Pending SFE', [SELECT Account_Stage__c FROM Account WHERE Id = :a.Id].Account_Stage__c);
  }

  @IsTest
  static void markAccountInactive_recomputesStageAndValidatesReason() {
    String reason = null;
    for (Schema.PicklistEntry entry : Account.Inactive_Reason__c.getDescribe().getPicklistValues()) {
      if (entry.isActive()) {
        reason = entry.getValue();
        break;
      }
    }
    System.assertNotEquals(null, reason, 'Inactive_Reason__c needs an active value.');
    Account a = newAccount('Go Inactive', 'Active');
    Map<String, Object> good = action('MARK_ACCOUNT_INACTIVE', 'inactive_ok');
    good.put(
      'payloadJson',
      JSON.serialize(
        new Map<String, Object>{
          'accountId' => a.Id,
          'reason' => reason,
          'body' => new Map<String, Object>{ 'Account_Stage__c' => 'Active', 'Account_Status__c' => 'Active' }
        }
      )
    );
    Map<String, Object> bad = action('MARK_ACCOUNT_INACTIVE', 'inactive_bad');
    bad.put(
      'payloadJson',
      JSON.serialize(new Map<String, Object>{ 'accountId' => a.Id, 'reason' => 'Not A Real Reason' })
    );
    Map<String, Object> response = post(new List<Map<String, Object>>{ good, bad });
    assertOk(response, 0);
    System.assert(errorAt(response, 1).contains('not valid'));
    Account after = [SELECT Account_Stage__c, Account_Status__c, Inactive_Reason__c FROM Account WHERE Id = :a.Id];
    System.assertEquals('Inactive', after.Account_Stage__c);
    System.assertEquals('Inactive', after.Account_Status__c);
    System.assertEquals(reason, after.Inactive_Reason__c);
  }

  @IsTest
  static void markAccountDuplicate_recomputesStageAndRejectsSelfReference() {
    Account dup = newAccount('Dup Record', 'Draft');
    Account master = newAccount('Master Record', 'Active');
    Map<String, Object> good = action('MARK_ACCOUNT_DUPLICATE', 'dup_ok');
    good.put(
      'payloadJson',
      JSON.serialize(
        new Map<String, Object>{
          'accountId' => dup.Id,
          'duplicateOfId' => master.Id,
          'body' => new Map<String, Object>{ 'Account_Stage__c' => 'Active', 'Account_Status__c' => 'Active' }
        }
      )
    );
    Map<String, Object> self = action('MARK_ACCOUNT_DUPLICATE', 'dup_self');
    self.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'accountId' => master.Id, 'duplicateOfId' => master.Id }));
    Map<String, Object> noId = action('MARK_ACCOUNT_DUPLICATE', 'dup_noid');
    noId.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'accountId' => 'local_account_1', 'duplicateOfId' => master.Id }));

    Map<String, Object> response = post(new List<Map<String, Object>>{ good, self, noId });
    assertOk(response, 0);
    errorAt(response, 1);
    System.assert(errorAt(response, 2).contains('not saved on the server'));
    Account after = [SELECT Account_Stage__c, Account_Status__c, Duplicate_Of__c FROM Account WHERE Id = :dup.Id];
    System.assertEquals('Duplicate', after.Account_Stage__c);
    System.assertEquals('Inactive', after.Account_Status__c);
    System.assertEquals(master.Id, after.Duplicate_Of__c);
  }

  @IsTest
  static void saveAccountRatings_persistsAndRecomputesMatrix() {
    Account a = newAccount('Rate Me', 'Active');
    Map<String, Object> act = action('SAVE_ACCOUNT_RATINGS', 'ratings_1');
    act.put(
      'payloadJson',
      JSON.serialize(
        new Map<String, Object>{
          'accountId' => a.Id,
          'territory2Id' => '0MI000000000000AAA', // Not the user's territory: ignored, server resolves.
          'fieldInputsJson' => JSON.serialize(
            new List<Object>{
              new Map<String, Object>{
                'objectApiName' => 'Account_Territory_Fields__c',
                'fieldApiName' => 'Potential__c',
                'valueJson' => '"A"'
              },
              new Map<String, Object>{
                'objectApiName' => 'Account_Territory_Fields__c',
                'fieldApiName' => 'Penetration__c',
                'valueJson' => '"1"'
              },
              new Map<String, Object>{
                'objectApiName' => 'Account_Territory_Fields__c',
                'fieldApiName' => 'Matrix_Rating__c',
                'valueJson' => '"z9"'
              }
            }
          ),
          'productRatingsJson' => '[]'
        }
      )
    );
    Map<String, Object> empty = action('SAVE_ACCOUNT_RATINGS', 'ratings_empty');
    empty.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'accountId' => a.Id }));

    Map<String, Object> response = post(new List<Map<String, Object>>{ act, empty });
    assertOk(response, 0);
    System.assert(errorAt(response, 1).contains('No rating values'));
    List<Account_Territory_Fields__c> rows = [
      SELECT Matrix_Rating__c, Classification__c
      FROM Account_Territory_Fields__c
      WHERE Account__c = :a.Id
    ];
    System.assertEquals(1, rows.size());
    System.assertEquals('a1', rows[0].Matrix_Rating__c, 'Matrix rating is recomputed server-side.');
    System.assertEquals('A', rows[0].Classification__c);
  }

  // ------------------------------------------------------------------ account action edge cases
  @IsTest
  static void accountActions_replaysAreNoOpsAndBadInputIsRejected() {
    String reason = null;
    for (Schema.PicklistEntry entry : Account.Inactive_Reason__c.getDescribe().getPicklistValues()) {
      if (entry.isActive()) {
        reason = entry.getValue();
        break;
      }
    }
    Account master = newAccount('Replay Master', 'Active');
    Account alreadyDup = newAccount('Replay Dup', 'Draft');
    AccountStageService.markDuplicate(alreadyDup.Id, master.Id);
    Account alreadyInactive = newAccount('Replay Inactive', 'Draft');
    AccountStageService.markInactive(alreadyInactive.Id, reason);

    Map<String, Object> dupReplay = action('MARK_ACCOUNT_DUPLICATE', 'replay_dup');
    dupReplay.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'accountId' => alreadyDup.Id, 'duplicateOfId' => master.Id }));
    Map<String, Object> inactiveReplay = action('MARK_ACCOUNT_INACTIVE', 'replay_inactive');
    inactiveReplay.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'accountId' => alreadyInactive.Id, 'reason' => reason }));
    Map<String, Object> noReason = action('MARK_ACCOUNT_INACTIVE', 'no_reason');
    noReason.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'accountId' => master.Id }));
    Map<String, Object> missingAccount = action('MARK_ACCOUNT_INACTIVE', 'missing_account');
    missingAccount.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'accountId' => '001000000000000AAA', 'reason' => reason }));
    Map<String, Object> cannotAdvance = action('ADVANCE_ACCOUNT_STAGE', 'cannot_advance');
    cannotAdvance.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'accountId' => master.Id, 'fromStage' => 'Active' }));
    Map<String, Object> dupAlready = action('MARK_ACCOUNT_DUPLICATE', 'dup_again');
    dupAlready.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'accountId' => alreadyDup.Id, 'duplicateOfId' => alreadyInactive.Id }));
    Map<String, Object> inactiveAlready = action('MARK_ACCOUNT_INACTIVE', 'inactive_again');
    inactiveAlready.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'accountId' => alreadyInactive.Id, 'reason' => reason == null ? 'x' : reason, 'extra' => 1 }));

    Map<String, Object> response = post(
      new List<Map<String, Object>>{ dupReplay, inactiveReplay, noReason, missingAccount, cannotAdvance, dupAlready, inactiveAlready }
    );
    assertOk(response, 0);
    assertOk(response, 1);
    System.assert(errorAt(response, 2).contains('Choose an inactive reason'));
    System.assert(errorAt(response, 3).contains('Account not found'));
    errorAt(response, 4);
    errorAt(response, 5); // Duplicate of a different original: AccountStageService refuses re-marking.
    assertOk(response, 6);
  }

  @IsTest
  static void consentHelpers_validatePicklistsAndCaptureTime() {
    Schema.SObjectType accountType = Account.SObjectType;
    String rating = Account.Rating.getDescribe().getPicklistValues()[0].getValue();
    System.assertEquals(rating, PlannerOutboxAccountActions.pickValue(accountType, 'Rating', rating, 'rating'));
    System.assertEquals('anything', PlannerOutboxAccountActions.pickValue(accountType, 'No_Such_Field__c', 'anything', 'x'));
    System.assertEquals('free text', PlannerOutboxAccountActions.pickValue(accountType, 'Name', 'free text', 'name'));
    for (String bad : new List<String>{ '', 'definitely-not-a-picklist-value' }) {
      Boolean threw = false;
      try {
        PlannerOutboxAccountActions.pickValue(accountType, 'Rating', bad, 'rating');
      } catch (PlannerOutboxAccountActions.ActionException e) {
        threw = true;
      }
      System.assert(threw, 'Expected rejection for "' + bad + '"');
    }

    Datetime now = Datetime.now();
    System.assert(PlannerOutboxAccountActions.boundedCapturedAt(null) >= now.addSeconds(-5));
    System.assert(PlannerOutboxAccountActions.boundedCapturedAt('not a date') >= now.addSeconds(-5));
    System.assert(PlannerOutboxAccountActions.boundedCapturedAt(now.addDays(3).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')) <= Datetime.now());
    System.assert(PlannerOutboxAccountActions.boundedCapturedAt(now.addDays(-90).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')) >= now.addSeconds(-5));
    Datetime recent = now.addHours(-2);
    Datetime kept = PlannerOutboxAccountActions.boundedCapturedAt(recent.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
    System.assert(Math.abs(kept.getTime() - recent.getTime()) < 2000, 'A believable offline capture time is preserved.');
  }

  @IsTest
  static void saveAccountRatings_acceptsStructuredJsonAndSurfacesServiceErrors() {
    Account a = newAccount('Rate Structured', 'Active');
    Map<String, Object> structured = action('SAVE_ACCOUNT_RATINGS', 'ratings_structured');
    structured.put(
      'payloadJson',
      JSON.serialize(
        new Map<String, Object>{
          'accountId' => a.Id,
          'fieldInputsJson' => new List<Object>{
            new Map<String, Object>{
              'objectApiName' => 'Account_Territory_Fields__c',
              'fieldApiName' => 'Potential__c',
              'valueJson' => '"B"'
            }
          }
        }
      )
    );
    Map<String, Object> invalidRows = action('SAVE_ACCOUNT_RATINGS', 'ratings_invalid_rows');
    invalidRows.put(
      'payloadJson',
      JSON.serialize(
        new Map<String, Object>{
          'accountId' => a.Id,
          'fieldInputsJson' => '[{"objectApiName":"","fieldApiName":"Potential__c"}]'
        }
      )
    );
    Map<String, Object> response = post(new List<Map<String, Object>>{ structured, invalidRows });
    assertOk(response, 0);
    errorAt(response, 1);
    System.assertEquals(1, [SELECT COUNT() FROM Account_Territory_Fields__c WHERE Account__c = :a.Id AND Potential__c = 'B']);
  }

  // ------------------------------------------------------------------ REST-context safety
  @IsTest
  static void restSafeError_returnsPlainExceptionInRestAndAuraElsewhere() {
    System.assert(RestSafeError.make('Aura msg') instanceof AuraHandledException);
    System.assertEquals('Aura msg', RestSafeError.make('Aura msg').getMessage());
    RestSafeError.forceRestForTest = true;
    Exception rest = RestSafeError.make('Rest msg');
    System.assert(rest instanceof RestSafeError.RestException);
    System.assertEquals('Rest msg', rest.getMessage());
  }

  @IsTest
  static void restContext_serviceFailuresAreRecordedPerActionWithoutAbortingBatch() {
    // In a real REST request `new AuraHandledException` raises an uncatchable LimitException.
    // Services now throw through RestSafeError; simulate the REST quiddity to prove the batch survives.
    RestSafeError.forceRestForTest = true;
    Account active = newAccount('Cannot Advance', 'Active');
    Account draft = newAccount('Can Advance', 'Draft');
    Map<String, Object> complete = action('COMPLETE_SESSION', 'rest_complete');
    Map<String, Object> noSession = action('LOG_SLIDE_EVENT', 'rest_slide');
    noSession.put('clientSessionKey', 'local_nothing');
    Map<String, Object> cannotAdvance = action('ADVANCE_ACCOUNT_STAGE', 'rest_cannot_advance');
    cannotAdvance.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'accountId' => active.Id, 'fromStage' => 'Active' }));
    Map<String, Object> startNoVisit = action('START_SESSION', 'rest_start');
    startNoVisit.put('clientSessionKey', 'local_s');
    Map<String, Object> badStatusReport = action('SAVE_CALL_REPORT', 'rest_report');
    badStatusReport.put(
      'callReportJson',
      JSON.serialize(new Map<String, Object>{ 'visitId' => visit().Id, 'status' => 'Completed' })
    );
    Map<String, Object> ok = action('ADVANCE_ACCOUNT_STAGE', 'rest_ok');
    ok.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'accountId' => draft.Id, 'fromStage' => 'Draft' }));

    Map<String, Object> response = post(
      new List<Map<String, Object>>{ complete, noSession, cannotAdvance, startNoVisit, badStatusReport, ok }
    );
    errorAt(response, 0);
    errorAt(response, 1);
    System.assert(errorAt(response, 2).contains('cannot be advanced'));
    errorAt(response, 3);
    errorAt(response, 4);
    assertOk(response, 5);
    System.assertEquals('Pending DM', [SELECT Account_Stage__c FROM Account WHERE Id = :draft.Id].Account_Stage__c);
  }

  @IsTest
  static void visitStatusRules_rejectInvalidChangesThroughRestSafeErrors() {
    String planned = VisitStatusHelper.TYPE_PLANNED_AUTO;
    String unplanned = VisitStatusHelper.TYPE_UNPLANNED;
    // Allowed transitions never throw.
    VisitStatusHelper.assertTransitionAllowed(null, 'Scheduled', unplanned, false);
    VisitStatusHelper.assertTransitionAllowed('Scheduled', 'Completed', unplanned, false);
    VisitStatusHelper.assertTransitionAllowed('Draft', 'Submitted', planned, false);
    VisitStatusHelper.assertTransitionAllowed('Submitted', 'Scheduled', planned, false);
    VisitStatusHelper.assertTransitionAllowed('Scheduled', 'Completed', planned, false);
    VisitStatusHelper.assertTransitionAllowed('Rescheduled', 'Scheduled', planned, false);
    VisitStatusHelper.assertTransitionAllowed('Completed', 'Draft', planned, false, true);
    VisitStatusHelper.validateStatusChange(null, null, null);
    VisitStatusHelper.validateStatusChange('Cancelled', null, 'Customer asked');

    for (Boolean rest : new List<Boolean>{ false, true }) {
      RestSafeError.forceRestForTest = rest;
      List<String> failures = new List<String>();
      try {
        VisitStatusHelper.assertTransitionAllowed('Scheduled', 'Draft', unplanned, false);
      } catch (Exception e) {
        failures.add(e.getMessage());
        System.assertEquals(rest, e instanceof RestSafeError.RestException);
      }
      try {
        VisitStatusHelper.assertTransitionAllowed('Completed', 'Draft', planned, false);
      } catch (Exception e) {
        failures.add(e.getMessage());
      }
      try {
        VisitStatusHelper.validateStatusChange('Cancelled', null, null);
      } catch (Exception e) {
        failures.add(e.getMessage());
      }
      try {
        VisitStatusHelper.validateStatusChange('Completed', DateTime.now().addDays(10), null);
      } catch (Exception e) {
        failures.add(e.getMessage());
      }
      System.assertEquals(4, failures.size(), 'Every invalid change is rejected: ' + String.join(failures, ' | '));
      System.assert(failures[2].contains('Cancellation reason is required'));
    }
  }

  // ------------------------------------------------------------------ CAPTURE_CONSENT
  @IsTest
  static void captureConsent_failsClearlyWhenObjectMissingOrSavesWhenPresent() {
    Visit__c v = visit();
    Schema.SObjectType consentType = Schema.getGlobalDescribe().get('Visit_Consent__c');
    Map<String, Object> payload = new Map<String, Object>{
      'Visit__c' => v.Id,
      'Account__c' => '001000000000000AAA', // Forged: ignored, account comes from the visit.
      'Channel__c' => 'In Person',
      'Consent_Type__c' => 'Data Processing',
      'Status__c' => 'Declined'
    };
    if (consentType != null) {
      Schema.DescribeFieldResult channel = consentType.getDescribe().fields.getMap().get('Channel__c').getDescribe();
      Schema.DescribeFieldResult type = consentType.getDescribe().fields.getMap().get('Consent_Type__c').getDescribe();
      Schema.DescribeFieldResult status = consentType.getDescribe().fields.getMap().get('Status__c').getDescribe();
      payload.put('Channel__c', channel.getPicklistValues()[0].getValue());
      payload.put('Consent_Type__c', type.getPicklistValues()[0].getValue());
      payload.put('Status__c', status.getPicklistValues()[0].getValue());
      payload.put('Signature_Data__c', 'data:image/png;base64,AAAA');
    }
    Map<String, Object> act = action('CAPTURE_CONSENT', 'consent_1');
    act.put('payloadJson', JSON.serialize(payload));
    Map<String, Object> unsigned = action('CAPTURE_CONSENT', 'consent_unsigned');
    unsigned.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'Visit__c' => v.Id, 'Channel__c' => 'x', 'Consent_Type__c' => 'y', 'Status__c' => 'Granted' }));
    Map<String, Object> noVisit = action('CAPTURE_CONSENT', 'consent_no_visit');
    noVisit.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'Visit__c' => 'a00000000000000AAA', 'Status__c' => 'Declined' }));
    Map<String, Object> localVisit = action('CAPTURE_CONSENT', 'consent_local_visit');
    localVisit.put('payloadJson', JSON.serialize(new Map<String, Object>{ 'Visit__c' => 'local_visit_9', 'Status__c' => 'Declined' }));

    Map<String, Object> response = post(new List<Map<String, Object>>{ act, unsigned, noVisit, localVisit });
    System.assert(errorAt(response, 1).contains('Capture a signature'));
    System.assert(errorAt(response, 2).contains('Visit not found'));
    System.assert(errorAt(response, 3).contains('not saved on the server'));
    if (consentType == null) {
      System.assert(errorAt(response, 0).contains('not available in this org'));
    } else {
      assertOk(response, 0);
      System.assertEquals(
        v.Account__c,
        (Id) Database.query('SELECT Account__c FROM Visit_Consent__c WHERE Visit__c = \'' + v.Id + '\' LIMIT 1')[0].get('Account__c')
      );
    }
  }
}
