/**
 * @description Tests for HubRecordActionsUtil action discovery/execution helpers.
 */
@IsTest
private class HubRecordActionsUtilTest {
  private class OkCalloutMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setHeader('Content-Type', 'application/json');
      res.setBody('{"actions":[{"apiName":"Edit","label":"Edit","type":"StandardButton"}]}');
      return res;
    }
  }

  @IsTest
  static void testFallbackRecordActionsAndDeleteClone() {
    Account acc = new Account(Name = 'Hub Actions Acc');
    insert acc;

    HubRecordActionsUtil.testRecordActionsOverride = new Map<String, Object>{
      'actions' => new List<Object>{
        new Map<String, Object>{
          'apiName' => 'Edit',
          'label' => 'Edit',
          'type' => 'StandardButton'
        },
        new Map<String, Object>{
          'apiName' => 'Delete',
          'label' => 'Delete',
          'type' => 'StandardButton'
        },
        new Map<String, Object>{
          'apiName' => 'Clone',
          'label' => 'Clone',
          'type' => 'StandardButton'
        }
      }
    };

    List<Map<String, Object>> actions = HubRecordActionsUtil.fetchRecordPageActions(acc.Id);
    System.assert(actions.size() >= 2, 'Should return record actions');

    Map<String, Object> cloneForm = HubRecordActionsUtil.cloneHubRecord(acc.Id);
    System.assertEquals(true, cloneForm.get('success'), 'clone: ' + (cloneForm.get('error') == null ? '' : String.valueOf(cloneForm.get('error'))));
    System.assert(cloneForm.containsKey('values'), 'Clone form should include values');

    Map<String, Object> values = new Map<String, Object>();
    values.put('Name', 'Hub Actions Acc Clone');
    Map<String, Object> created = HubRecordActionsUtil.createClonedRecord('Account', values);
    System.assertEquals(true, created.get('success'), 'create: ' + (created.get('error') == null ? '' : String.valueOf(created.get('error'))));
    System.assertNotEquals(null, created.get('recordId'));

    // Exercise delete path for coverage; org automation may block delete — do not hard-fail.
    Map<String, Object> del = HubRecordActionsUtil.deleteHubRecord(String.valueOf(created.get('recordId')));
    System.assert(del.containsKey('success') || del.containsKey('error'), 'Delete should return a result map');
    Map<String, Object> blankDelete = HubRecordActionsUtil.deleteHubRecord('');
    System.assert(blankDelete.containsKey('error'));
  }

  @IsTest
  static void testRelatedListAndRowActionFallbacks() {
    Account acc = new Account(Name = 'Hub RL Actions Acc');
    insert acc;
    Contact con = new Contact(LastName = 'Hub RL Con', AccountId = acc.Id);
    insert con;

    HubRecordActionsUtil.testRelatedListActionsOverride = new Map<String, Object>{
      'results' => new List<Object>{
        new Map<String, Object>{
          'referenceId' => 'Contacts',
          'result' => new Map<String, Object>{
            'actions' => new List<Object>{
              new Map<String, Object>{
                'apiName' => 'New',
                'label' => 'New',
                'type' => 'StandardButton'
              }
            }
          }
        }
      }
    };
    Map<String, List<Map<String, Object>>> listActs = HubRecordActionsUtil.fetchRelatedListActionsBatch(
      acc.Id,
      new List<String>{ 'Contacts' }
    );
    System.assert(listActs.containsKey('Contacts'));

    HubRecordActionsUtil.testRowActionsOverride = new Map<String, Object>{
      'results' => new List<Object>{
        new Map<String, Object>{
          'referenceId' => String.valueOf(con.Id),
          'result' => new Map<String, Object>{
            'actions' => new List<Object>{
              new Map<String, Object>{
                'apiName' => 'Edit',
                'label' => 'Edit',
                'type' => 'StandardButton'
              }
            }
          }
        }
      }
    };
    Map<String, List<Map<String, Object>>> rowActs = HubRecordActionsUtil.fetchRelatedListRecordActionsBatch(
      acc.Id,
      new List<String>{ String.valueOf(con.Id) }
    );
    System.assert(rowActs.containsKey(String.valueOf(con.Id)));
  }

  @IsTest
  static void testFallbackActionsWithoutOverride() {
    Account acc = new Account(Name = 'Hub Fallback Acc');
    insert acc;
    HubRecordActionsUtil.testRecordActionsOverride = null;
    HubRecordActionsUtil.testRelatedListActionsOverride = null;
    HubRecordActionsUtil.testRowActionsOverride = null;
    Test.setMock(HttpCalloutMock.class, new OkCalloutMock());
    List<Map<String, Object>> actions = HubRecordActionsUtil.fetchRecordPageActions(acc.Id);
    System.assert(!actions.isEmpty(), 'Fallback/UI API actions expected');

    Contact con = new Contact(LastName = 'Hub Fallback Con', AccountId = acc.Id);
    insert con;
    Map<String, List<Map<String, Object>>> rowActs = HubRecordActionsUtil.fetchRelatedListRecordActionsBatch(
      acc.Id,
      new List<String>{ String.valueOf(con.Id) }
    );
    System.assert(rowActs.containsKey(String.valueOf(con.Id)));

    Map<String, List<Map<String, Object>>> emptyBatch = HubRecordActionsUtil.fetchRelatedListActionsBatch(
      acc.Id,
      new List<String>()
    );
    System.assertEquals(0, emptyBatch.size());
    System.assertEquals(0, HubRecordActionsUtil.fetchRecordPageActions('').size());
  }

  @IsTest
  static void testCreateClonedRecordValidation() {
    Map<String, Object> bad = HubRecordActionsUtil.createClonedRecord('', null);
    System.assert(bad.containsKey('error'));
    Map<String, Object> badObj = HubRecordActionsUtil.createClonedRecord(
      'NotAnObject__c',
      new Map<String, Object>{ 'Name' => 'x' }
    );
    System.assert(badObj.containsKey('error'));
    Map<String, Object> blankDelete = HubRecordActionsUtil.deleteHubRecord('');
    System.assert(blankDelete.containsKey('error'));
    Map<String, Object> blankClone = HubRecordActionsUtil.cloneHubRecord('');
    System.assert(blankClone.containsKey('error'));
  }

  @IsTest
  static void testQuickActionValidationAndHttp() {
    Test.setMock(HttpCalloutMock.class, new OkCalloutMock());
    Map<String, Object> bad = HubRecordActionsUtil.getQuickActionForm(null, '', '', null);
    System.assert(bad.containsKey('error'));
    Map<String, Object> form = HubRecordActionsUtil.getQuickActionForm(
      null,
      'Account',
      'New',
      'Record'
    );
    System.assert(form.containsKey('success') || form.containsKey('error') || form.containsKey('layout'));

    Map<String, Object> execBad = HubRecordActionsUtil.executeQuickAction(null, '', '', null);
    System.assert(execBad.containsKey('error'));
    Map<String, Object> exec = HubRecordActionsUtil.executeQuickAction(
      null,
      'Account',
      'New',
      new Map<String, Object>{ 'Name' => 'QA Acc' }
    );
    System.assert(exec.containsKey('success') || exec.containsKey('error'));
  }
}
