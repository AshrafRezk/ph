@IsTest
private class PlannerMobileRestServiceTest {
  private static RestResponse invokeGetWithParams(String path, Map<String, String> params) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/planner/v1/' + path;
    req.httpMethod = 'GET';
    if (params != null) {
      req.params.putAll(params);
    }
    RestContext.request = req;
    RestContext.response = res;
    PlannerMobileRestService.doGet();
    return res;
  }

  private static RestResponse invokePost(String path, String body) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/planner/v1/' + path;
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body == null ? '{}' : body);
    RestContext.request = req;
    RestContext.response = res;
    PlannerMobileRestService.doPost();
    return res;
  }

  // The deploying user's real territory tree can be deep enough to exhaust the 100-SOQL limit in
  // TerritoryHierarchyService / AccountsTabController.expandTerritoryHierarchy. Territory-sensitive
  // routes are exercised for a user with no territory assignment (rolled back with the test).
  private static void dropRunnerTerritory() {
    delete [SELECT Id FROM UserTerritory2Association WHERE UserId = :UserInfo.getUserId()];
  }

  @IsTest
  static void getUiMetadata_returnsConfig() {
    Test.startTest();
    RestResponse res = invokeGetWithParams('ui-metadata', null);
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    System.assert(res.responseBody != null);
  }

  @IsTest
  static void getTimeOff_returnsMyRequests() {
    Time_Off_Request__c request = new Time_Off_Request__c(
      Type__c = 'Holiday',
      Span_Type__c = 'Full_Day',
      Start_Date_Time__c = DateTime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0)),
      End_Date_Time__c = DateTime.newInstance(Date.today(), Time.newInstance(17, 0, 0, 0)),
      Stage__c = 'Draft'
    );
    insert request;

    Test.startTest();
    RestResponse res = invokeGetWithParams(
      'time-off',
      new Map<String, String>{ 'limitSize' => '5' }
    );
    Test.stopTest();
    System.assertEquals(200, res.statusCode, res.responseBody == null ? 'null body' : res.responseBody.toString());
    System.assertNotEquals(null, res.responseBody);
  }

  @IsTest
  static void getHomeDashboard_returnsPayload() {
    dropRunnerTerritory();
    Test.startTest();
    RestResponse res = invokeGetWithParams('home/dashboard', null);
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    String body = res.responseBody.toString();
    System.assert(body.contains('metrics'));
    System.assert(body.contains('todayVisits'));
    System.assert(body.contains('accountCoverageRows'));
    System.assert(body.contains('userId'));

    Map<String, Object> auraPayload = PlannerMobileRestService.getHomeDashboard(null);
    System.assertNotEquals(null, auraPayload);
    System.assert(auraPayload.containsKey('accountCoverageRows'));
    System.assert(auraPayload.containsKey('userId'));
  }

  @IsTest
  static void getTodayPlanPayload_returnsPayload() {
    Test.startTest();
    RestResponse res = invokeGetWithParams(
      'home/today-plan',
      new Map<String, String>{ 'planDate' => String.valueOf(Date.today()) }
    );
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    String body = res.responseBody.toString();
    System.assert(body.contains('visits'));
    System.assert(body.contains('userId'));
    System.assert(body.contains('viewerContext'));

    Map<String, Object> auraPayload = PlannerMobileRestService.getTodayPlanPayload(null, Date.today());
    System.assertNotEquals(null, auraPayload);
    System.assert(auraPayload.containsKey('visits'));
    System.assert(auraPayload.containsKey('userId'));
  }

  @IsTest
  static void getNextBestCustomersPayload_returnsPayload() {
    Test.startTest();
    RestResponse res = invokeGetWithParams(
      'home/next-best-customers',
      new Map<String, String>{ 'limitSize' => '5' }
    );
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    String body = res.responseBody.toString();
    System.assert(body.contains('rows'));
    System.assert(body.contains('userId'));

    Map<String, Object> auraPayload = PlannerMobileRestService.getNextBestCustomersPayload(null, 5);
    System.assertNotEquals(null, auraPayload);
    System.assert(auraPayload.containsKey('rows'));
    System.assert(auraPayload.containsKey('userId'));
  }

  @IsTest
  static void getAccountsTabRoutes_ok() {
    Test.startTest();
    RestResponse pageRes = invokeGetWithParams(
      'accounts-tab/page',
      new Map<String, String>{
        'scope' => 'both',
        'searchTerm' => '',
        'recordTypeDeveloperName' => 'All',
        'classification' => '',
        'sortBy' => 'agentforceScore',
        'sortDirection' => 'desc',
        'offset' => '0',
        'pageSize' => '10'
      }
    );
    RestResponse mapRes = invokeGetWithParams(
      'accounts-tab/map-points',
      new Map<String, String>{ 'scope' => 'both', 'pageSize' => '5' }
    );
    RestResponse optionsRes = invokeGetWithParams('accounts-tab/record-type-options', null);
    Test.stopTest();

    System.assertEquals(200, pageRes.statusCode);
    String pageBody = pageRes.responseBody.toString();
    System.assert(pageBody.contains('rows'));
    System.assert(pageBody.contains('totalCount'));
    System.assert(pageBody.contains('recordTypeCounts'));

    System.assertEquals(200, mapRes.statusCode);
    String mapBody = mapRes.responseBody.toString();
    System.assert(mapBody.contains('rows'));
    System.assert(mapBody.contains('mapEligibleCount'));

    System.assertEquals(200, optionsRes.statusCode);
    String optionsBody = optionsRes.responseBody.toString();
    System.assert(optionsBody.contains('label'));
    System.assert(optionsBody.contains('value'));

    List<AccountsTabController.RecordTypeFilterOption> options = AccountsTabController.getAccountsTabRecordTypeOptions();
    System.assertNotEquals(null, options);
    System.assert(!options.isEmpty());
  }

  @IsTest
  static void getWeekAndSyncPull_ok() {
    Date weekStart = Date.today().toStartOfWeek();
    Test.startTest();
    RestResponse weekRes = invokeGetWithParams(
      'week',
      new Map<String, String>{
        'weekStart' => String.valueOf(weekStart),
        'weekEnd' => String.valueOf(weekStart.addDays(6))
      }
    );
    RestResponse pullRes = invokeGetWithParams('sync/pull', null);
    RestResponse mapRes = invokeGetWithParams('accounts/map', null);
    RestResponse filterRes = invokeGetWithParams('accounts/filters', null);
    RestResponse rtRes = invokeGetWithParams('accounts/record-types', null);
    RestResponse projectRes = invokeGetWithParams('projects', null);
    RestResponse targetRes = invokeGetWithParams('targets', null);
    Test.stopTest();
    System.assertEquals(200, weekRes.statusCode);
    System.assert(weekRes.responseBody.toString().contains('"meetings"'), 'Week payload must include meetings');
    System.assertEquals(200, pullRes.statusCode);
    System.assertEquals(200, mapRes.statusCode);
    System.assertEquals(200, filterRes.statusCode);
    System.assertEquals(200, rtRes.statusCode);
    System.assertEquals(200, projectRes.statusCode);
    System.assertEquals(200, targetRes.statusCode);
  }

  @IsTest
  static void getUnknownPath_returns404() {
    Test.startTest();
    RestResponse res = invokeGetWithParams('not-a-real-path', null);
    Test.stopTest();
    System.assertEquals(404, res.statusCode);
  }

  @IsTest
  static void postOutbox_emptyActions_ok() {
    Test.startTest();
    RestResponse res = invokePost('outbox', '{"actions":[]}');
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
  }

  @IsTest
  static void postSearchAndUnknown_ok() {
    Test.startTest();
    RestResponse searchRes = invokePost(
      'accounts/search',
      '{"searchTerm":"x","recordTypeDeveloperNames":["All"],"pageSize":10}'
    );
    RestResponse unknown = invokePost('not-a-real-path', '{}');
    Test.stopTest();
    System.assertEquals(200, searchRes.statusCode);
    System.assertEquals(404, unknown.statusCode);
  }

  static void postVisitTotAndOutbox_ok() {
    Account account = new Account(Name = 'Mobile Rest Visit Account');
    insert account;
    Date workingDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 2);
    String startIso = DateTime.newInstance(workingDay, Time.newInstance(11, 0, 0, 0)).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    String endIso = DateTime.newInstance(workingDay, Time.newInstance(12, 0, 0, 0)).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

    Test.startTest();
    RestResponse upsertRes = invokePost(
      'visits/upsert',
      JSON.serialize(
        new Map<String, Object>{
          'accountId' => account.Id,
          'startDateTime' => startIso,
          'endDateTime' => endIso,
          'status' => 'Draft',
          'visitType' => 'Planned (Automatically)'
        }
      )
    );
    Map<String, Object> created = (Map<String, Object>) JSON.deserializeUntyped(upsertRes.responseBody.toString());
    String visitId = String.valueOf(created.get('id'));

    String laterStart = DateTime.newInstance(workingDay, Time.newInstance(13, 0, 0, 0)).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
    String laterEnd = DateTime.newInstance(workingDay, Time.newInstance(14, 0, 0, 0)).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    invokePost(
      'visits/reschedule',
      JSON.serialize(
        new Map<String, Object>{
          'moves' => new List<Object>{
            new Map<String, Object>{
              'visitId' => visitId,
              'startDateTime' => laterStart,
              'endDateTime' => laterEnd
            }
          }
        }
      )
    );

    RestResponse totRes = invokePost(
      'time-off',
      JSON.serialize(
        new Map<String, Object>{
          'typeValue' => 'Holiday',
          'spanType' => 'Hours',
          'durationHours' => '2',
          'startDateTime' => laterStart,
          'comments' => 'mobile',
          'stage' => 'Draft'
        }
      )
    );

    RestResponse outboxRes = invokePost(
      'outbox',
      JSON.serialize(
        new Map<String, Object>{
          'actions' => new List<Object>{
            new Map<String, Object>{
              'id' => '1',
              'actionType' => 'UPSERT_VISIT',
              'clientVisitKey' => 'ck1',
              'payloadJson' => JSON.serialize(
                new Map<String, Object>{
                  'accountId' => account.Id,
                  'startDateTime' => startIso,
                  'endDateTime' => endIso,
                  'status' => 'Draft',
                  'visitType' => 'Planned (Automatically)'
                }
              )
            },
            new Map<String, Object>{
              'id' => '2',
              'actionType' => 'RESCHEDULE_VISITS',
              'payloadJson' => JSON.serialize(
                new Map<String, Object>{
                  'visitIds' => new List<String>{ visitId },
                  'startDateTimes' => new List<String>{ laterStart },
                  'endDateTimes' => new List<String>{ laterEnd }
                }
              )
            },
            new Map<String, Object>{
              'id' => '3',
              'actionType' => 'DELETE_VISIT',
              'payloadJson' => JSON.serialize(new Map<String, Object>{ 'visitId' => visitId })
            },
            new Map<String, Object>{
              'id' => '4',
              'actionType' => 'CREATE_TIME_OFF',
              'payloadJson' => JSON.serialize(
                new Map<String, Object>{
                  'typeValue' => 'Sick',
                  'spanType' => 'Full_Day',
                  'startDateTime' => startIso,
                  'stage' => 'Draft'
                }
              )
            },
            new Map<String, Object>{
              'id' => '5',
              'actionType' => 'UNKNOWN',
              'payloadJson' => '{}'
            }
          }
        }
      )
    );

    invokePost('visits/delete', JSON.serialize(new Map<String, Object>{ 'visitId' => visitId }));

    Date submitDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 4);
    String submitStartIso = DateTime.newInstance(submitDay, Time.newInstance(9, 0, 0, 0))
      .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    String submitEndIso = DateTime.newInstance(submitDay, Time.newInstance(10, 0, 0, 0))
      .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    RestResponse upsertSubmitRes = invokePost(
      'visits/upsert',
      JSON.serialize(
        new Map<String, Object>{
          'accountId' => account.Id,
          'startDateTime' => submitStartIso,
          'endDateTime' => submitEndIso,
          'status' => 'Draft',
          'visitType' => 'Planned (Automatically)'
        }
      )
    );
    System.assertEquals(
      200,
      upsertSubmitRes.statusCode,
      upsertSubmitRes.responseBody == null ? 'no body' : upsertSubmitRes.responseBody.toString()
    );
    Map<String, Object> submitVisitRow = (Map<String, Object>) JSON.deserializeUntyped(
      upsertSubmitRes.responseBody.toString()
    );
    String submitVisitId = String.valueOf(submitVisitRow.get('id'));
    RestResponse submitRes = invokePost(
      'visits/submit',
      JSON.serialize(new Map<String, Object>{ 'visitId' => submitVisitId })
    );
    RestResponse weekSubmitRes = invokePost(
      'visits/submit-week',
      JSON.serialize(
        new Map<String, Object>{
          'weekStart' => String.valueOf(submitDay),
          'weekEnd' => String.valueOf(submitDay)
        }
      )
    );
    RestResponse weekMissing = invokeGetWithParams('week', null);
    Test.stopTest();

    System.assertEquals(200, upsertRes.statusCode);
    System.assertEquals(200, totRes.statusCode);
    System.assertEquals(200, outboxRes.statusCode);
    System.assertEquals(
      200,
      submitRes.statusCode,
      submitRes.responseBody == null ? 'no body' : submitRes.responseBody.toString()
    );
    System.assertEquals(
      200,
      weekSubmitRes.statusCode,
      weekSubmitRes.responseBody == null ? 'no body' : weekSubmitRes.responseBody.toString()
    );
    System.assertEquals(400, weekMissing.statusCode);
  }

  @IsTest
  static void getMeAndTerritoryContext_ok() {
    Test.startTest();
    RestResponse meRes = invokeGetWithParams('me', null);
    RestResponse territoryRes = invokeGetWithParams('territory-context', null);
    RestResponse clearRes = invokePost(
      'territory-context',
      JSON.serialize(new Map<String, Object>{ 'territoryId' => null })
    );
    Test.stopTest();

    System.assertEquals(200, meRes.statusCode);
    String meBody = meRes.responseBody.toString();
    System.assert(meBody.contains('firstName') || meBody.contains('name'));
    System.assert(meBody.contains('email'));
    System.assertEquals(200, territoryRes.statusCode);
    System.assert(territoryRes.responseBody.toString().contains('usingAllAssigned'));
    System.assertEquals(200, clearRes.statusCode);
  }

  @IsTest
  static void meetingsApprovalsAndRemainingReads_ok() {
    Date weekStart = Date.today().toStartOfWeek();
    DateTime startDt = DateTime.newInstance(weekStart.addDays(2), Time.newInstance(10, 0, 0, 0));
    String startIso = startDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    String endIso = startDt.addHours(1).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

    Test.startTest();
    RestResponse types = invokeGetWithParams('meetings/record-types', null);
    List<Object> typeRows = (List<Object>) JSON.deserializeUntyped(types.responseBody.toString());
    String recordType = 'Promotional_Activity';
    if (!typeRows.isEmpty()) {
      recordType = String.valueOf(((Map<String, Object>) typeRows[0]).get('value'));
    }
    RestResponse created = invokePost(
      'meetings',
      JSON.serialize(
        new Map<String, Object>{
          'recordTypeDeveloperName' => recordType,
          'startDateTime' => startIso,
          'endDateTime' => endIso,
          'title' => 'REST meeting'
        }
      )
    );
    RestResponse listed = invokeGetWithParams(
      'meetings',
      new Map<String, String>{
        'weekStart' => String.valueOf(weekStart),
        'weekEnd' => String.valueOf(weekStart.addDays(6))
      }
    );
    Test.stopTest();

    System.assertEquals(200, types.statusCode);
    System.assertEquals(200, created.statusCode, created.responseBody == null ? 'null' : created.responseBody.toString());
    System.assertEquals(200, listed.statusCode);
  }

  @IsTest
  static void meetingsApprovalsAndRemainingReads_readRoutes_ok() {
    dropRunnerTerritory();
    Test.startTest();
    invokeGetWithParams('viewer-context', null);
    invokeGetWithParams('brick-alerts', null);
    invokeGetWithParams('classification-suggestions', null);
    invokeGetWithParams('visits/pending-approvals', null);
    invokeGetWithParams('home/next-best-customers', new Map<String, String>{ 'limitSize' => '3' });
    invokeGetWithParams('home/monthly-timecard', null);
    Test.stopTest();
  }

  @IsTest
  static void timecardTileAndLeaveRoutes_ok() {
    dropRunnerTerritory();
    Test.startTest();
    RestResponse tile = invokeGetWithParams('home/monthly-timecard/details', new Map<String, String>{ 'tileId' => 'field' });
    RestResponse leaves = invokeGetWithParams('home/monthly-timecard/leaves', null);
    Test.stopTest();
    System.assertEquals(200, tile.statusCode, tile.responseBody?.toString());
    System.assert(tile.responseBody.toString().contains('"tileId":"field"'), tile.responseBody.toString());
    System.assertEquals(200, leaves.statusCode, leaves.responseBody?.toString());
  }

  @IsTest
  static void meetingsApprovalsAndRemainingReads_accountsAndPosts_ok() {
    dropRunnerTerritory();
    Date weekStart = Date.today().toStartOfWeek();
    DateTime startDt = DateTime.newInstance(weekStart.addDays(2), Time.newInstance(10, 0, 0, 0));
    String startIso = startDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    Test.startTest();
    invokeGetWithParams(
      'accounts-tab/page',
      new Map<String, String>{ 'scope' => 'mine', 'pageSize' => '5', 'offset' => '0' }
    );
    invokeGetWithParams(
      'accounts-tab/map-points',
      new Map<String, String>{ 'scope' => 'mine', 'pageSize' => '5' }
    );
    invokePost('visits/approve', '{"visitId":null}');
    invokePost('visits/reject', '{"visitId":null,"rejectionReason":"No"}');
    invokePost('meetings/approve', '{"meetingId":null}');
    invokePost('meetings/reject', '{"meetingId":null,"rejectionReason":"No"}');
    invokePost('time-off/approve', '{"requestId":null}');
    invokePost('time-off/reject', '{"requestId":null,"rejectionReason":"No"}');
    invokePost('me/photo', '{"photoBase64":null}');
    RestResponse outbox = invokePost(
      'outbox',
      JSON.serialize(
        new Map<String, Object>{
          'actions' => new List<Object>{
            new Map<String, Object>{
              'id' => 'del',
              'actionType' => 'DELETE_VISIT',
              'payloadJson' => '{"visitId":null}'
            },
            new Map<String, Object>{
              'id' => 'sub',
              'actionType' => 'SUBMIT_VISIT',
              'payloadJson' => '{"visitId":null}'
            },
            new Map<String, Object>{
              'id' => 'tot',
              'actionType' => 'CREATE_TIME_OFF',
              'clientActionKey' => 'tot1',
              'payloadJson' => JSON.serialize(
                new Map<String, Object>{
                  'typeValue' => 'Training',
                  'spanType' => 'Hours',
                  'durationHours' => '1',
                  'startDateTime' => startIso,
                  'stage' => 'Draft'
                }
              )
            },
            new Map<String, Object>{ 'id' => 'bad', 'actionType' => 'NOPE', 'payloadJson' => '{}' }
          }
        }
      )
    );
    Test.stopTest();

    System.assertEquals(200, outbox.statusCode);
  }

  @IsTest
  static void badLimitAndReschedule_coverRemainingBranches() {
    Test.startTest();
    RestResponse badLimit = invokeGetWithParams(
      'time-off',
      new Map<String, String>{ 'limitSize' => 'nope' }
    );
    RestResponse reschedule = invokePost(
      'visits/reschedule',
      '{"visitIds":[],"startDateTimes":[],"endDateTimes":[]}'
    );
    Test.stopTest();
    System.assertEquals(200, badLimit.statusCode);
    System.assert(reschedule.statusCode == 200 || reschedule.statusCode == 400);
  }

  @IsTest
  static void meetingEditsAndOfflineMeetingActions() {
    String rt = MeetingPlannerController.getMeetingRecordTypes()[0].value;
    DateTime startAt = System.now().addDays(4);
    String startIso = startAt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    String endIso = startAt.addHours(1).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    MeetingPlannerController.MeetingSummary created = MeetingPlannerController.createMeeting(
      rt, startAt, startAt.addHours(1), 'Planner meeting', null
    );

    Test.startTest();
    RestResponse updated = invokePost('meetings/update', JSON.serialize(new Map<String, Object>{
      'meetingId' => created.id, 'startDateTime' => startIso, 'endDateTime' => endIso, 'title' => 'Moved'
    }));
    RestResponse queued = invokePost('outbox', JSON.serialize(new Map<String, Object>{ 'actions' => new List<Object>{
      new Map<String, Object>{ 'id' => '1', 'actionType' => 'CREATE_MEETING', 'clientActionKey' => 'local-1', 'payloadJson' => JSON.serialize(
        new Map<String, Object>{ 'recordTypeDeveloperName' => rt, 'startDateTime' => startIso, 'endDateTime' => endIso, 'title' => 'Offline' }) },
      new Map<String, Object>{ 'id' => '2', 'actionType' => 'UPDATE_MEETING', 'payloadJson' => JSON.serialize(
        new Map<String, Object>{ 'meetingId' => 'local-2', 'startDateTime' => startIso, 'endDateTime' => endIso, 'title' => 'X' }) },
      new Map<String, Object>{ 'id' => '3', 'actionType' => 'DELETE_MEETING', 'payloadJson' => JSON.serialize(
        new Map<String, Object>{ 'meetingId' => 'local-3' }) }
    } }));
    RestResponse removed = invokePost('meetings/delete', JSON.serialize(new Map<String, Object>{ 'meetingId' => created.id }));
    RestResponse unsynced = invokePost('meetings/delete', JSON.serialize(new Map<String, Object>{ 'meetingId' => 'local-9' }));
    Test.stopTest();

    System.assertEquals(200, updated.statusCode, updated.responseBody.toString());
    List<Object> results = (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(queued.responseBody.toString())).get('results');
    System.assertEquals(true, ((Map<String, Object>) results[0]).get('success'));
    System.assertNotEquals(null, ((Map<String, Object>) ((Map<String, Object>) results[0]).get('visitIdByClientKey')).get('local-1'));
    System.assertEquals(false, ((Map<String, Object>) results[1]).get('success'), 'An unsynced meeting cannot be updated yet');
    System.assertEquals(true, ((Map<String, Object>) results[2]).get('success'));
    System.assertEquals(200, removed.statusCode);
    System.assertEquals(0, [SELECT COUNT() FROM Meeting__c WHERE Id = :created.id]);
    System.assertEquals(200, unsynced.statusCode);
  }
}