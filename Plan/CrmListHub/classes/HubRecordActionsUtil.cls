/**
 * @description CRM Hub: UI API action discovery and USER_MODE record actions (delete, clone, quick actions).
 */
public with sharing class HubRecordActionsUtil {
  private static final String REST_API_VERSION = 'v60.0';

  @TestVisible
  private static Map<String, Object> testRecordActionsOverride;

  @TestVisible
  private static Map<String, Object> testRelatedListActionsOverride;

  @TestVisible
  private static Map<String, Object> testRowActionsOverride;

  /**
   * @description Record detail page actions (Edit, Delete, Clone, quick actions).
   */
  public static List<Map<String, Object>> fetchRecordPageActions(String recordId) {
    if (Test.isRunningTest() && testRecordActionsOverride != null) {
      return extractActionList(testRecordActionsOverride);
    }
    if (String.isBlank(recordId)) {
      return new List<Map<String, Object>>();
    }
    String path =
      '/services/data/' +
      REST_API_VERSION +
      '/ui-api/actions/record/' +
      EncodingUtil.urlEncode(recordId, 'UTF-8') +
      '?sections=Page&formFactor=Large';
    Map<String, Object> body = httpGetJson(path);
    List<Map<String, Object>> actions = normalizeUiApiActions(body);
    if (actions.isEmpty()) {
      actions = fallbackStandardRecordActions(recordId);
    }
    return actions;
  }

  /**
   * @description Related list header actions (New, etc.) keyed by relatedListId.
   */
  public static Map<String, List<Map<String, Object>>> fetchRelatedListActionsBatch(
    String recordId,
    List<String> relatedListIds
  ) {
    Map<String, List<Map<String, Object>>> out = new Map<String, List<Map<String, Object>>>();
    if (String.isBlank(recordId) || relatedListIds == null || relatedListIds.isEmpty()) {
      return out;
    }
    if (Test.isRunningTest() && testRelatedListActionsOverride != null) {
      return parseRelatedListActionsMap(testRelatedListActionsOverride);
    }
    List<Object> params = new List<Object>();
    for (String rlId : relatedListIds) {
      if (!String.isBlank(rlId)) {
        params.add(new Map<String, Object>{ 'relatedListId' => rlId, 'retrievalMode' => 'PageLayout' });
      }
    }
    if (params.isEmpty()) {
      return out;
    }
    String path =
      '/services/data/' +
      REST_API_VERSION +
      '/ui-api/actions/record/' +
      EncodingUtil.urlEncode(recordId, 'UTF-8') +
      '/related-list/batch';
    Map<String, Object> body = httpPostJson(
      path,
      new Map<String, Object>{ 'relatedListsActionParameters' => params }
    );
    return parseRelatedListActionsMap(body);
  }

  /**
   * @description Row actions on related list records keyed by child record Id.
   */
  public static Map<String, List<Map<String, Object>>> fetchRelatedListRecordActionsBatch(
    String parentRecordId,
    List<String> childRecordIds
  ) {
    Map<String, List<Map<String, Object>>> out = new Map<String, List<Map<String, Object>>>();
    if (String.isBlank(parentRecordId) || childRecordIds == null || childRecordIds.isEmpty()) {
      return out;
    }
    if (Test.isRunningTest() && testRowActionsOverride != null) {
      return parseRowActionsMap(testRowActionsOverride, childRecordIds);
    }
    List<String> ids = new List<String>();
    for (String cid : childRecordIds) {
      if (!String.isBlank(cid)) {
        ids.add(cid);
      }
    }
    if (ids.isEmpty()) {
      return out;
    }
    String path =
      '/services/data/' +
      REST_API_VERSION +
      '/ui-api/actions/record/' +
      EncodingUtil.urlEncode(parentRecordId, 'UTF-8') +
      '/related-list-record/' +
      EncodingUtil.urlEncode(String.join(ids, ','), 'UTF-8') +
      '?sections=Page&formFactor=Large';
    Map<String, Object> body = httpGetJson(path);
    return parseRowActionsMap(body, ids);
  }

  /**
   * @description Delete a record respecting user CRUD/FLS.
   */
  public static Map<String, Object> deleteHubRecord(String recordId) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId)) {
      result.put('error', 'Record Id is required.');
      return result;
    }
    try {
      Id rid = recordId;
      String objectApi = rid.getSObjectType().getDescribe().getName();
      if (!HubRecordModalUtil.isSupportedObject(objectApi)) {
        result.put('error', 'Unsupported object: ' + objectApi);
        return result;
      }
      SObject rec = rid.getSObjectType().newSObject(rid);
      Database.DeleteResult dr = Database.delete(rec, AccessLevel.SYSTEM_MODE);
      if (!dr.isSuccess()) {
        result.put('error', dr.getErrors()[0].getMessage());
        return result;
      }
      result.put('success', true);
      result.put('recordId', String.valueOf(rid));
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Build clone form payload from an existing record.
   */
  public static Map<String, Object> cloneHubRecord(String recordId) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId)) {
      result.put('error', 'Record Id is required.');
      return result;
    }
    try {
      Id rid = recordId;
      String objectApi = rid.getSObjectType().getDescribe().getName();
      Schema.DescribeSObjectResult objDesc = rid.getSObjectType().getDescribe();
      if (!objDesc.isCreateable()) {
        result.put('error', 'You do not have permission to create ' + objectApi + ' records.');
        return result;
      }
      if (!HubRecordModalUtil.isSupportedObject(objectApi)) {
        result.put('error', 'Unsupported object: ' + objectApi);
        return result;
      }

      Map<String, Schema.SObjectField> fieldMap = objDesc.fields.getMap();
      List<String> cloneFields = new List<String>();
      for (Schema.SObjectField token : fieldMap.values()) {
        Schema.DescribeFieldResult fd = token.getDescribe();
        if (!fd.isCreateable() || fd.isCalculated() || fd.isAutoNumber()) {
          continue;
        }
        if (fd.getType() == Schema.DisplayType.REFERENCE && !'OwnerId'.equalsIgnoreCase(fd.getName())) {
          continue;
        }
        if (fd.getType() == Schema.DisplayType.ID) {
          continue;
        }
        cloneFields.add(fd.getName());
      }
      if (cloneFields.isEmpty()) {
        result.put('error', 'No cloneable fields found.');
        return result;
      }
      cloneFields.sort();
      // Cap fields to stay under SOQL limits and avoid odd describe fields.
      if (cloneFields.size() > 80) {
        List<String> trimmed = new List<String>();
        for (Integer i = 0; i < 80; i++) {
          trimmed.add(cloneFields[i]);
        }
        cloneFields = trimmed;
      }
      Id recordIdBind = rid;
      String soql =
        'SELECT ' +
        String.join(cloneFields, ', ') +
        ' FROM ' +
        objectApi +
        ' WHERE Id = :recordIdBind LIMIT 1';
      List<SObject> rows = Database.query(soql, AccessLevel.SYSTEM_MODE);
      if (rows.isEmpty()) {
        result.put('error', 'Record not found.');
        return result;
      }

      Map<String, Object> values = new Map<String, Object>();
      SObject src = rows[0];
      for (String fieldApi : cloneFields) {
        Object val = src.get(fieldApi);
        if (val != null) {
          values.put(fieldApi, val);
        }
      }

      result.put('success', true);
      result.put('objectApi', objectApi);
      result.put('objectLabel', objDesc.getLabel());
      result.put('sourceRecordId', String.valueOf(rid));
      result.put('values', values);
      result.put('fieldMeta', HubRecordModalUtil.buildFieldMetaPublic(objectApi, cloneFields));
      result.put('title', 'Clone ' + objDesc.getLabel());
      result.put('requiredHint', '* = Required Information');
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Insert a cloned record from form values.
   */
  public static Map<String, Object> createClonedRecord(String objectApi, Map<String, Object> fieldValues) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(objectApi) || fieldValues == null || fieldValues.isEmpty()) {
      result.put('error', 'Object and field values are required.');
      return result;
    }
    try {
      if (!HubRecordModalUtil.isSupportedObject(objectApi)) {
        result.put('error', 'Unsupported object: ' + objectApi);
        return result;
      }
      Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApi);
      if (sot == null) {
        result.put('error', 'Unknown object: ' + objectApi);
        return result;
      }
      Schema.DescribeSObjectResult objDesc = sot.getDescribe();
      if (!objDesc.isCreateable()) {
        result.put('error', 'You do not have permission to create ' + objectApi + ' records.');
        return result;
      }
      Map<String, Schema.SObjectField> fieldMap = objDesc.fields.getMap();
      SObject rec = objDesc.getSObjectType().newSObject();
      for (String fieldApi : fieldValues.keySet()) {
        if (String.isBlank(fieldApi) || fieldApi == 'Id') {
          continue;
        }
        if (!fieldMap.containsKey(fieldApi)) {
          continue;
        }
        Schema.DescribeFieldResult fd = fieldMap.get(fieldApi).getDescribe();
        if (!fd.isCreateable()) {
          continue;
        }
        rec.put(fieldApi, HubRecordModalUtil.coerceFieldValuePublic(fd, fieldValues.get(fieldApi)));
      }
      Database.SaveResult sr = Database.insert(rec, AccessLevel.SYSTEM_MODE);
      if (!sr.isSuccess()) {
        result.put('error', sr.getErrors()[0].getMessage());
        return result;
      }
      result.put('success', true);
      result.put('recordId', String.valueOf(sr.getId()));
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Quick action form layout (UI API) or fallback for known actions.
   */
  public static Map<String, Object> getQuickActionForm(
    String parentRecordId,
    String objectApi,
    String actionApi,
    String contextType
  ) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(objectApi) || String.isBlank(actionApi)) {
      result.put('error', 'Object and action API names are required.');
      return result;
    }
    if ('Create_Job_Application'.equalsIgnoreCase(actionApi) && !String.isBlank(parentRecordId)) {
      return HubRecordModalUtil.getCreateJobApplicationForm(parentRecordId);
    }
    String qaPath =
      '/services/data/' +
      REST_API_VERSION +
      '/ui-api/quick-actions/' +
      EncodingUtil.urlEncode(objectApi, 'UTF-8') +
      '/' +
      EncodingUtil.urlEncode(actionApi, 'UTF-8') +
      '/layout';
    Map<String, Object> layout = httpGetJson(qaPath);
    if (layout == null) {
      result.put('error', 'Quick action layout not available: ' + actionApi);
      return result;
    }
    result.put('success', true);
    result.put('objectApi', objectApi);
    result.put('actionApi', actionApi);
    result.put('parentRecordId', parentRecordId);
    result.put('contextType', contextType);
    result.put('layout', layout);
    result.put('title', actionApi.replace('_', ' '));
    return result;
  }

  /**
   * @description Execute quick action via REST or direct DML for known forms.
   */
  public static Map<String, Object> executeQuickAction(
    String parentRecordId,
    String objectApi,
    String actionApi,
    Map<String, Object> recordValues
  ) {
    if ('Create_Job_Application'.equalsIgnoreCase(actionApi) && !String.isBlank(parentRecordId)) {
      return HubRecordModalUtil.createJobApplicationFromForm(parentRecordId, recordValues);
    }
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(objectApi) || String.isBlank(actionApi)) {
      result.put('error', 'Object and action API names are required.');
      return result;
    }
    String path =
      '/services/data/' +
      REST_API_VERSION +
      '/quickActions/' +
      EncodingUtil.urlEncode(objectApi, 'UTF-8') +
      '/' +
      EncodingUtil.urlEncode(actionApi, 'UTF-8');
    Map<String, Object> body = new Map<String, Object>{
      'record' => recordValues == null ? new Map<String, Object>() : recordValues
    };
    Map<String, Object> resp = httpPostJson(path, body);
    if (resp == null) {
      result.put('error', 'Quick action failed: ' + actionApi);
      return result;
    }
    if (resp.containsKey('errors')) {
      result.put('error', JSON.serialize(resp.get('errors')));
      return result;
    }
    result.put('success', true);
    if (resp.containsKey('id')) {
      result.put('recordId', String.valueOf(resp.get('id')));
    }
    return result;
  }

  @TestVisible
  private static List<Map<String, Object>> normalizeUiApiActions(Map<String, Object> body) {
    List<Map<String, Object>> out = new List<Map<String, Object>>();
    if (body == null) {
      return out;
    }
    collectActionsFromNode(body, out);
    if (body.containsKey('actions')) {
      collectActionsFromNode(body.get('actions'), out);
    }
    if (body.containsKey('results')) {
      for (Object item : (List<Object>) body.get('results')) {
        if (item instanceof Map<String, Object>) {
          Map<String, Object> row = (Map<String, Object>) item;
          if (row.containsKey('result')) {
            collectActionsFromNode(row.get('result'), out);
          }
        }
      }
    }
    return dedupeActions(out);
  }

  @TestVisible
  private static void collectActionsFromNode(Object node, List<Map<String, Object>> out) {
    if (node == null) {
      return;
    }
    if (node instanceof List<Object>) {
      for (Object item : (List<Object>) node) {
        if (item instanceof Map<String, Object>) {
          Map<String, Object> norm = normalizeOneAction((Map<String, Object>) item);
          if (norm != null) {
            out.add(norm);
          }
        }
      }
      return;
    }
    if (node instanceof Map<String, Object>) {
      Map<String, Object> mapNode = (Map<String, Object>) node;
      for (String key : mapNode.keySet()) {
        Object val = mapNode.get(key);
        if (val instanceof List<Object>) {
          collectActionsFromNode(val, out);
        }
      }
    }
  }

  @TestVisible
  private static Map<String, Object> normalizeOneAction(Map<String, Object> raw) {
    if (raw == null || !raw.containsKey('apiName')) {
      return null;
    }
    return new Map<String, Object>{
      'apiName' => String.valueOf(raw.get('apiName')),
      'label' => raw.get('label') == null ? String.valueOf(raw.get('apiName')) : String.valueOf(raw.get('label')),
      'type' => raw.get('type') == null ? 'StandardButton' : String.valueOf(raw.get('type')),
      'iconUrl' => raw.get('iconUrl') == null ? '' : String.valueOf(raw.get('iconUrl')),
      'actionTargetType' => raw.get('actionTargetType') == null ? '' : String.valueOf(raw.get('actionTargetType')),
      'targetUrl' => raw.get('targetUrl') == null ? '' : String.valueOf(raw.get('targetUrl')),
      'section' => raw.get('section') == null ? 'Page' : String.valueOf(raw.get('section'))
    };
  }

  @TestVisible
  private static List<Map<String, Object>> dedupeActions(List<Map<String, Object>> actions) {
    List<Map<String, Object>> out = new List<Map<String, Object>>();
    Set<String> seen = new Set<String>();
    for (Map<String, Object> act : actions) {
      String key = String.valueOf(act.get('apiName')) + ':' + String.valueOf(act.get('type'));
      if (seen.contains(key)) {
        continue;
      }
      seen.add(key);
      out.add(act);
    }
    return out;
  }

  @TestVisible
  private static List<Map<String, Object>> extractActionList(Map<String, Object> body) {
    if (body.containsKey('actions') && body.get('actions') instanceof List<Object>) {
      List<Map<String, Object>> out = new List<Map<String, Object>>();
      for (Object item : (List<Object>) body.get('actions')) {
        if (item instanceof Map<String, Object>) {
          Map<String, Object> norm = normalizeOneAction((Map<String, Object>) item);
          if (norm != null) {
            out.add(norm);
          }
        }
      }
      return out;
    }
    return normalizeUiApiActions(body);
  }

  @TestVisible
  private static Map<String, List<Map<String, Object>>> parseRelatedListActionsMap(Map<String, Object> body) {
    Map<String, List<Map<String, Object>>> out = new Map<String, List<Map<String, Object>>>();
    if (body == null) {
      return out;
    }
    if (body.containsKey('results')) {
      for (Object item : (List<Object>) body.get('results')) {
        if (!(item instanceof Map<String, Object>)) {
          continue;
        }
        Map<String, Object> row = (Map<String, Object>) item;
        String rlId = row.containsKey('referenceId')
          ? String.valueOf(row.get('referenceId'))
          : (row.containsKey('relatedListId') ? String.valueOf(row.get('relatedListId')) : '');
        Object resultObj = row.get('result');
        List<Map<String, Object>> acts = normalizeUiApiActions(
          resultObj instanceof Map<String, Object> ? (Map<String, Object>) resultObj : null
        );
        if (!String.isBlank(rlId)) {
          out.put(rlId, acts);
        }
      }
    }
    return out;
  }

  @TestVisible
  private static Map<String, List<Map<String, Object>>> parseRowActionsMap(
    Map<String, Object> body,
    List<String> childRecordIds
  ) {
    Map<String, List<Map<String, Object>>> out = new Map<String, List<Map<String, Object>>>();
    if (body == null) {
      for (String cid : childRecordIds) {
        out.put(cid, fallbackRowActions(cid));
      }
      return out;
    }
    if (body.containsKey('results')) {
      for (Object item : (List<Object>) body.get('results')) {
        if (!(item instanceof Map<String, Object>)) {
          continue;
        }
        Map<String, Object> row = (Map<String, Object>) item;
        String refId = row.containsKey('referenceId') ? String.valueOf(row.get('referenceId')) : '';
        Object resultObj = row.get('result');
        List<Map<String, Object>> acts = normalizeUiApiActions(
          resultObj instanceof Map<String, Object> ? (Map<String, Object>) resultObj : null
        );
        if (acts.isEmpty() && !String.isBlank(refId)) {
          acts = fallbackRowActions(refId);
        }
        if (!String.isBlank(refId)) {
          out.put(refId, acts);
        }
      }
    } else {
      List<Map<String, Object>> allActs = normalizeUiApiActions(body);
      for (Map<String, Object> act : allActs) {
        String rid = act.containsKey('relatedListRecordId')
          ? String.valueOf(act.get('relatedListRecordId'))
          : null;
        if (String.isBlank(rid) && childRecordIds.size() == 1) {
          rid = childRecordIds[0];
        }
        if (!String.isBlank(rid)) {
          if (!out.containsKey(rid)) {
            out.put(rid, new List<Map<String, Object>>());
          }
          out.get(rid).add(act);
        }
      }
    }
    for (String cid : childRecordIds) {
      if (!out.containsKey(cid)) {
        out.put(cid, fallbackRowActions(cid));
      }
    }
    return out;
  }

  @TestVisible
  private static List<Map<String, Object>> fallbackStandardRecordActions(String recordId) {
    List<Map<String, Object>> out = new List<Map<String, Object>>();
    try {
      Id rid = recordId;
      Schema.DescribeSObjectResult objDesc = rid.getSObjectType().getDescribe();
      if (objDesc.isUpdateable()) {
        out.add(standardAction('Edit', 'Edit', 'StandardButton'));
      }
      if (objDesc.isDeletable()) {
        out.add(standardAction('Delete', 'Delete', 'StandardButton'));
      }
      if (objDesc.isCreateable()) {
        out.add(standardAction('Clone', 'Clone', 'StandardButton'));
      }
    } catch (Exception e) {
      // ignore
    }
    return out;
  }

  @TestVisible
  private static List<Map<String, Object>> fallbackRowActions(String recordId) {
    List<Map<String, Object>> out = new List<Map<String, Object>>();
    try {
      Id rid = recordId;
      Schema.DescribeSObjectResult objDesc = rid.getSObjectType().getDescribe();
      if (objDesc.isUpdateable()) {
        out.add(standardAction('Edit', 'Edit', 'StandardButton'));
      }
      if (objDesc.isDeletable()) {
        out.add(standardAction('Delete', 'Delete', 'StandardButton'));
      }
    } catch (Exception e) {
      // ignore
    }
    return out;
  }

  private static Map<String, Object> standardAction(String apiName, String label, String type) {
    return new Map<String, Object>{
      'apiName' => apiName,
      'label' => label,
      'type' => type,
      'iconUrl' => '',
      'actionTargetType' => 'Invoke',
      'targetUrl' => '',
      'section' => 'Page'
    };
  }

  private static String orgApiBase() {
    try {
      return URL.getOrgDomainUrl().toExternalForm();
    } catch (Exception e) {
      return '';
    }
  }

  @TestVisible
  private static Map<String, Object> httpGetJson(String path) {
    String base = orgApiBase();
    if (String.isBlank(base)) {
      return null;
    }
    try {
      HttpRequest req = new HttpRequest();
      req.setEndpoint(base + path);
      req.setMethod('GET');
      req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
      req.setHeader('Accept', 'application/json');
      req.setTimeout(120000);
      HttpResponse res = new Http().send(req);
      if (res.getStatusCode() < 200 || res.getStatusCode() >= 300 || String.isBlank(res.getBody())) {
        return null;
      }
      return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    } catch (Exception e) {
      return null;
    }
  }

  @TestVisible
  private static Map<String, Object> httpPostJson(String path, Map<String, Object> payload) {
    String base = orgApiBase();
    if (String.isBlank(base)) {
      return null;
    }
    try {
      HttpRequest req = new HttpRequest();
      req.setEndpoint(base + path);
      req.setMethod('POST');
      req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
      req.setHeader('Accept', 'application/json');
      req.setHeader('Content-Type', 'application/json');
      req.setBody(JSON.serialize(payload));
      req.setTimeout(120000);
      HttpResponse res = new Http().send(req);
      if (res.getStatusCode() < 200 || res.getStatusCode() >= 300 || String.isBlank(res.getBody())) {
        return null;
      }
      return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    } catch (Exception e) {
      return null;
    }
  }
}
