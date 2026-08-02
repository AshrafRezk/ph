/**
 * @description CRM Hub record modal: Lightning FlexiPage tabs + layout + record data in system mode.
 */
public without sharing class HubRecordModalUtil {

  private static final String REST_API_VERSION = 'v60.0';
  private static final Integer RELATED_LIST_PREVIEW_LIMIT = 5;
  private static final Integer RELATED_LIST_VIEW_ALL_LIMIT = 200;

  private static final Map<String, String> STANDARD_TAB_LABELS = new Map<String, String>{
    'Standard.Tab.detail' => 'Details',
    'Standard.Tab.activity' => 'Activity',
    'Standard.Tab.relatedLists' => 'Related',
    'Standard.Tab.collaborate' => 'Chatter',
    'Standard.Tab.news' => 'News',
    'Standard.Tab.salesNavigator' => 'Sales Navigator'
  };

  @TestVisible
  private static Map<String, Object> testLayoutOverride;

  @TestVisible
  private static List<Map<String, Object>> testTabsOverride;

  @TestVisible
  private static Map<String, Object> testPathOverride;

  private static final Map<String, String> PROCESS_FIELD_TO_API = new Map<String, String>{
    'OpportunityStage' => 'StageName',
    'LeadStatus' => 'Status',
    'CaseStatus' => 'Status',
    'QuoteStatus' => 'Status'
  };

  private static final Set<String> SUPPORTED_OBJECTS = new Set<String>{
    'Lead',
    'Opportunity',
    'Account',
    'Contact',
    'Job_Application__c',
    'Position__c',
    'Employment_Contract__c'
  };

  private static Map<String, Map<String, Object>> pathMasterConfigCache = new Map<String, Map<String, Object>>();
  private static Map<String, List<String>> pathOrderedValuesCache = new Map<String, List<String>>();

  /**
   * @description Full modal payload (legacy monolithic fetch). Prefer progressive shell/details/tabs/path calls.
   */
  public static Map<String, Object> fetchRecordModalData(String recordId) {
    Map<String, Object> shell = fetchRecordModalShell(recordId);
    if (shell.containsKey('error')) {
      return shell;
    }
    Map<String, Object> details = fetchRecordModalDetails(recordId);
    if (details.containsKey('error')) {
      return details;
    }
    Map<String, Object> tabsRes = fetchRecordModalTabs(recordId);
    if (tabsRes.containsKey('error')) {
      return tabsRes;
    }
    Map<String, Object> pathRes = fetchRecordModalPath(recordId);

    Map<String, Object> result = mergeModalPayload(shell, details);
    result.put('tabs', tabsRes.get('tabs'));
    if (pathRes.get('path') != null) {
      result.put('path', pathRes.get('path'));
    }

    Id rid = recordId;
    String objectApi = (String) result.get('objectApi');
    Map<String, Object> layout = (Map<String, Object>) details.get('layout');
    List<Map<String, Object>> tabs = (List<Map<String, Object>>) tabsRes.get('tabs');
    result.put('relatedListData', fetchRelatedListData(objectApi, rid, layout, tabs));
    return result;
  }

  /**
   * @description Fast shell: record name, object type, record type id (minimal SOQL).
   */
  public static Map<String, Object> fetchRecordModalShell(String recordId) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId)) {
      result.put('error', 'Record Id is required.');
      return result;
    }
    try {
      RecordModalContext ctx = resolveRecordModalContext(recordId);
      if (ctx == null) {
        result.put('error', 'Record not found.');
        return result;
      }
      result.put('recordId', String.valueOf(ctx.recordId));
      result.put('objectApi', ctx.objectApi);
      result.put('objectLabel', ctx.objectLabel);
      result.put('recordTypeId', String.valueOf(ctx.recordTypeId));
      result.put('recordName', recordDisplayName(ctx.record, ctx.objectApi));
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Details tab only: page layout + field values (no FlexiPage, path, or related lists).
   */
  public static Map<String, Object> fetchRecordModalDetails(String recordId) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId)) {
      result.put('error', 'Record Id is required.');
      return result;
    }
    try {
      RecordModalContext ctx = resolveRecordModalContext(recordId);
      if (ctx == null) {
        result.put('error', 'Record not found.');
        return result;
      }

      Map<String, Object> layout = normalizeLayoutLabels(resolveLayout(ctx.objectApi, ctx.recordTypeId));
      Set<String> allFieldApis = getAllObjectFieldApis(ctx.objectApi);
      Set<String> layoutFieldApis = layout == null
        ? new Set<String>()
        : extractLayoutFieldApis(layout, ctx.objectApi);

      if (layout == null) {
        List<String> sortedApis = new List<String>(allFieldApis);
        sortedApis.sort();
        layout = new Map<String, Object>{
          'detailLayoutSections' => new List<Object>{
            buildLayoutSection('All Fields', sortedApis, ctx.objectApi)
          }
        };
      } else {
        layout = augmentLayoutWithAllFields(layout, layoutFieldApis, allFieldApis, ctx.objectApi);
      }

      Set<String> requestedFields = new Set<String>();
      requestedFields.addAll(allFieldApis);
      requestedFields.addAll(layoutFieldApis);
      Set<String> lookupNames = referenceNamePaths(ctx.objectApi);
      requestedFields.addAll(lookupNames);
      List<String> queryFields = filterQueryableFields(ctx.objectApi, requestedFields);
      // Prefer layout fields (and lookup Names) first so they survive the 200-field SOQL cap.
      Set<String> preferred = new Set<String>();
      preferred.addAll(layoutFieldApis);
      preferred.addAll(lookupNames);
      queryFields = prioritizeFields(queryFields, preferred);
      if (queryFields.isEmpty()) {
        result.put('error', 'No queryable fields for ' + ctx.objectApi + '.');
        return result;
      }

      SObject rec = queryRecordFieldsWithAllFields(ctx.recordId, ctx.objectApi, queryFields);
      if (rec == null) {
        result.put('error', 'Record not found.');
        return result;
      }

      result.put('objectApi', ctx.objectApi);
      result.put('objectLabel', ctx.objectLabel);
      result.put('recordId', String.valueOf(ctx.recordId));
      result.put('recordName', recordDisplayName(rec, ctx.objectApi));
      result.put('layout', layout);
      result.put('values', recordToValueMap(rec, queryFields, ctx.objectApi, allFieldApis));
      result.put('fieldMeta', buildFieldMeta(ctx.objectApi, queryFields));
      result.put(
        'recordActions',
        HubRecordActionsUtil.fetchRecordPageActions(String.valueOf(ctx.recordId))
      );
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Lightning / layout tab configuration (FlexiPage callouts deferred here).
   */
  public static Map<String, Object> fetchRecordModalTabs(String recordId) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId)) {
      result.put('error', 'Record Id is required.');
      return result;
    }
    try {
      RecordModalContext ctx = resolveRecordModalContext(recordId);
      if (ctx == null) {
        result.put('error', 'Record not found.');
        return result;
      }
      Map<String, Object> layout = normalizeLayoutLabels(resolveLayout(ctx.objectApi, ctx.recordTypeId));
      if (layout == null) {
        layout = new Map<String, Object>{
          'detailLayoutSections' => new List<Object>(),
          'relatedLists' => new List<Object>()
        };
      }
      result.put('recordId', String.valueOf(ctx.recordId));
      result.put('objectApi', ctx.objectApi);
      result.put('tabs', resolveRecordTabs(ctx.objectApi, layout));
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Path assistant bar data (deferred from details fetch).
   */
  public static Map<String, Object> fetchRecordModalPath(String recordId) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId)) {
      result.put('error', 'Record Id is required.');
      return result;
    }
    try {
      if (Test.isRunningTest() && testPathOverride != null) {
        result.put('path', testPathOverride);
        result.put('recordId', recordId);
        return result;
      }
      RecordModalContext ctx = resolveRecordModalContext(recordId);
      if (ctx == null) {
        result.put('error', 'Record not found.');
        return result;
      }
      Map<String, Object> pathAssistantConfig = fetchPathAssistantConfig(ctx.objectApi, ctx.recordTypeId);
      String pathFieldApi = resolvePathFieldApi(pathAssistantConfig, ctx.objectApi);
      if (String.isBlank(pathFieldApi) || !ctx.objDesc.fields.getMap().containsKey(pathFieldApi)) {
        return result;
      }

      SObject rec = queryRecordFields(ctx.recordId, ctx.objectApi, new List<String>{ pathFieldApi });
      if (rec == null) {
        result.put('error', 'Record not found.');
        return result;
      }

      Map<String, Object> pathData = resolvePathData(
        ctx.objectApi,
        ctx.recordTypeId,
        rec,
        pathAssistantConfig,
        pathFieldApi
      );
      if (pathData != null && !pathData.isEmpty()) {
        result.put('path', pathData);
      }
      result.put('recordId', String.valueOf(ctx.recordId));
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Update editable fields on a hub record (system mode, without sharing).
   */
  public static Map<String, Object> updateRecordFields(
    String recordId,
    Map<String, Object> fieldValues
  ) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId)) {
      result.put('error', 'Record Id is required.');
      return result;
    }
    if (fieldValues == null || fieldValues.isEmpty()) {
      result.put('error', 'No fields to update.');
      return result;
    }
    try {
      RecordModalContext ctx = resolveRecordModalContext(recordId);
      if (ctx == null) {
        result.put('error', 'Record not found.');
        return result;
      }
      if (!SUPPORTED_OBJECTS.contains(ctx.objectApi)) {
        result.put('error', 'Unsupported object: ' + ctx.objectApi);
        return result;
      }

      Map<String, Schema.SObjectField> fieldMap = ctx.objDesc.fields.getMap();
      SObject rec = ctx.objDesc.getSObjectType().newSObject(ctx.recordId);
      List<String> updatedFields = new List<String>();

      for (String fieldApi : fieldValues.keySet()) {
        if (String.isBlank(fieldApi) || fieldApi == 'Id' || fieldApi.contains('.')) {
          continue;
        }
        if (!fieldMap.containsKey(fieldApi)) {
          result.put('error', 'Unknown field: ' + fieldApi);
          return result;
        }
        Schema.DescribeFieldResult fd = fieldMap.get(fieldApi).getDescribe();
        if (!isFieldEditable(fd)) {
          result.put('error', 'Field is not editable: ' + fieldApi);
          return result;
        }
        Object coerced = coerceFieldValue(fd, fieldValues.get(fieldApi));
        rec.put(fieldApi, coerced);
        updatedFields.add(fieldApi);
      }

      if (updatedFields.isEmpty()) {
        result.put('error', 'No valid fields to update.');
        return result;
      }

      Database.SaveResult sr = Database.update(rec, AccessLevel.SYSTEM_MODE);
      if (!sr.isSuccess()) {
        List<String> msgs = new List<String>();
        for (Database.Error err : sr.getErrors()) {
          msgs.add(err.getMessage());
        }
        result.put('error', String.join(msgs, '; '));
        return result;
      }

      List<String> refreshFields = new List<String>(updatedFields);
      for (String updatedField : updatedFields) {
        if (!fieldMap.containsKey(updatedField)) {
          continue;
        }
        Schema.DescribeFieldResult refreshedFd = fieldMap.get(updatedField).getDescribe();
        if (
          refreshedFd.getType() == Schema.DisplayType.REFERENCE &&
          !String.isBlank(refreshedFd.getRelationshipName())
        ) {
          refreshFields.add(refreshedFd.getRelationshipName() + '.Name');
        }
      }
      SObject refreshed = queryRecordFields(ctx.recordId, ctx.objectApi, refreshFields);
      Map<String, Object> values = new Map<String, Object>();
      if (refreshed != null) {
        Map<String, Object> populated = refreshed.getPopulatedFieldsAsMap();
        for (String f : refreshFields) {
          if (f.contains('.')) {
            String rel = f.substring(0, f.indexOf('.'));
            String child = f.substring(f.indexOf('.') + 1);
            Object relObj = populated.get(rel);
            if (relObj instanceof SObject) {
              values.put(f, ((SObject) relObj).get(child));
            }
          } else {
            values.put(f, formatFieldValueForModal(f, refreshed.get(f), fieldMap));
          }
        }
      }
      result.put('success', true);
      result.put('values', values);
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Prefill payload for Create Job Application form (mirrors Lead/Contact quick actions).
   */
  public static Map<String, Object> getCreateJobApplicationForm(String recordId) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId)) {
      result.put('error', 'Record Id is required.');
      return result;
    }
    try {
      RecordModalContext ctx = resolveRecordModalContext(recordId);
      if (ctx == null) {
        result.put('error', 'Record not found.');
        return result;
      }
      if (ctx.objectApi != 'Lead' && ctx.objectApi != 'Contact') {
        result.put('error', 'Create Job Application is only available on Lead or Contact.');
        return result;
      }

      Map<String, Object> defaults = buildCreateJobApplicationDefaults(ctx);
      if (defaults.containsKey('error')) {
        return defaults;
      }

      result.put('success', true);
      result.put('parentObjectApi', ctx.objectApi);
      result.put('parentField', defaults.get('parentField'));
      result.put('parentId', defaults.get('parentId'));
      result.put('parentName', defaults.get('parentName'));
      result.put('positionId', defaults.get('positionId'));
      result.put('positionName', defaults.get('positionName'));
      result.put('nextStep', defaults.get('nextStep'));
      result.put('status', defaults.get('status'));
      result.put('statusOptions', picklistValuesFromDescribe(
        Job_Application__c.Status__c.getDescribe()
      ));
      result.put('positionLookupObject', 'Position__c');
      result.put('title', 'Create Job Application');
      result.put('requiredHint', '* = Required Information');
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Create Job Application from Lead/Contact using form field values (Lightning parity).
   */
  public static Map<String, Object> createJobApplicationFromForm(
    String recordId,
    Map<String, Object> fieldValues
  ) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId)) {
      result.put('error', 'Record Id is required.');
      return result;
    }
    try {
      RecordModalContext ctx = resolveRecordModalContext(recordId);
      if (ctx == null) {
        result.put('error', 'Record not found.');
        return result;
      }
      if (ctx.objectApi != 'Lead' && ctx.objectApi != 'Contact') {
        result.put('error', 'Create Job Application is only available on Lead or Contact.');
        return result;
      }

      Map<String, Object> defaults = buildCreateJobApplicationDefaults(ctx);
      if (defaults.containsKey('error')) {
        return defaults;
      }

      Map<String, Object> values = fieldValues == null
        ? new Map<String, Object>()
        : fieldValues;

      Job_Application__c ja = new Job_Application__c();
      if (ctx.objectApi == 'Lead') {
        ja.Lead__c = ctx.recordId;
      } else {
        ja.Contact__c = ctx.recordId;
      }

      String statusVal = stringOrNull(values.get('Status__c'));
      if (String.isBlank(statusVal)) {
        statusVal = (String) defaults.get('status');
      }
      ja.Status__c = statusVal;

      String nextStepVal = stringOrNull(values.get('NextStep__c'));
      if (nextStepVal == null) {
        nextStepVal = (String) defaults.get('nextStep');
      }
      ja.NextStep__c = nextStepVal;

      if (values.containsKey('Position__c')) {
        String posRaw = stringOrNull(values.get('Position__c'));
        ja.Position__c = String.isBlank(posRaw) ? null : (Id) posRaw;
      } else {
        String defaultPos = stringOrNull(defaults.get('positionId'));
        ja.Position__c = String.isBlank(defaultPos) ? null : (Id) defaultPos;
      }

      Database.SaveResult sr = Database.insert(ja, AccessLevel.SYSTEM_MODE);
      if (!sr.isSuccess()) {
        List<String> msgs = new List<String>();
        for (Database.Error err : sr.getErrors()) {
          msgs.add(err.getMessage());
        }
        result.put('error', String.join(msgs, '; '));
        return result;
      }

      Job_Application__c created = [
        SELECT Id, Name, ApplicantName__c, Status__c, Position__c
        FROM Job_Application__c
        WHERE Id = :sr.getId()
        LIMIT 1
      ];
      result.put('success', true);
      result.put('jobApplicationId', String.valueOf(created.Id));
      result.put(
        'recordName',
        String.isNotBlank(created.Name) ? created.Name : 'Job Application'
      );
      result.put('message', 'Job application created!');
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Legacy helper: create JA with Lightning quick-action defaults (no form edits).
   */
  public static Map<String, Object> createJobApplicationFromParent(String recordId) {
    return createJobApplicationFromForm(recordId, null);
  }

  /**
   * @description Generic Name lookup search for CRM Hub (SOSL with SOQL fallback).
   */
  public static Map<String, Object> searchLookupRecords(
    String objectApi,
    String searchTerm,
    Integer resultLimit
  ) {
    Map<String, Object> result = new Map<String, Object>();
    List<Map<String, Object>> records = new List<Map<String, Object>>();
    result.put('records', records);
    if (String.isBlank(objectApi)) {
      result.put('error', 'Object is required for lookup search.');
      return result;
    }
    Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApi);
    if (sot == null) {
      result.put('error', 'Unknown object: ' + objectApi);
      return result;
    }
    Schema.DescribeSObjectResult od = sot.getDescribe();
    if (!od.isQueryable()) {
      result.put('error', 'Object is not queryable: ' + objectApi);
      return result;
    }
    if (!od.fields.getMap().containsKey('Name')) {
      result.put('error', 'Object has no Name field for lookup search.');
      return result;
    }

    Integer lim = resultLimit == null || resultLimit < 1 ? 20 : Math.min(resultLimit, 50);
    String term = searchTerm == null ? '' : searchTerm.trim();
    try {
      if (term.length() >= 2) {
        String safe = String.escapeSingleQuotes(term);
        String sosl =
          'FIND \'*' +
          safe +
          '*\' IN NAME FIELDS RETURNING ' +
          objectApi +
          '(Id, Name ORDER BY Name) LIMIT ' +
          String.valueOf(lim);
        List<List<SObject>> raw = Search.query(sosl);
        if (!raw.isEmpty()) {
          for (SObject row : raw[0]) {
            records.add(
              new Map<String, Object>{
                'id' => String.valueOf(row.get('Id')),
                'name' => String.valueOf(row.get('Name'))
              }
            );
          }
        }
      }
      if (records.isEmpty()) {
        String likeTerm = '%' + term + '%';
        String soql =
          'SELECT Id, Name FROM ' +
          objectApi +
          ' WHERE Name LIKE :likeTerm ORDER BY Name LIMIT :lim';
        for (
          SObject row : Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'likeTerm' => likeTerm, 'lim' => lim },
            AccessLevel.SYSTEM_MODE
          )
        ) {
          records.add(
            new Map<String, Object>{
              'id' => String.valueOf(row.get('Id')),
              'name' => String.valueOf(row.get('Name'))
            }
          );
        }
      }
      result.put('success', true);
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  private static Map<String, Object> buildCreateJobApplicationDefaults(RecordModalContext ctx) {
    Map<String, Object> defaults = new Map<String, Object>();
    if (ctx.objectApi == 'Lead') {
      Lead ld = [
        SELECT Id, Name, Position__c, Position__r.Name, IsConverted
        FROM Lead
        WHERE Id = :ctx.recordId
        LIMIT 1
      ];
      if (ld.IsConverted) {
        defaults.put('error', 'Cannot create a Job Application on a converted Lead.');
        return defaults;
      }
      defaults.put('parentField', 'Lead__c');
      defaults.put('parentId', String.valueOf(ld.Id));
      defaults.put('parentName', ld.Name);
      defaults.put(
        'positionId',
        ld.Position__c == null ? null : String.valueOf(ld.Position__c)
      );
      defaults.put(
        'positionName',
        ld.Position__r == null ? null : ld.Position__r.Name
      );
      // Matches Lead.Create_Job_Application quick action override.
      defaults.put('nextStep', 'Got any feedback?');
      defaults.put('status', 'New');
      return defaults;
    }

    Contact con = [
      SELECT Id, Name
      FROM Contact
      WHERE Id = :ctx.recordId
      LIMIT 1
    ];
    defaults.put('parentField', 'Contact__c');
    defaults.put('parentId', String.valueOf(con.Id));
    defaults.put('parentName', con.Name);
    // Contact.Create_Job_Application does not override Position__c.
    defaults.put('positionId', null);
    defaults.put('positionName', null);
    defaults.put('nextStep', 'Got a response?');
    defaults.put('status', 'New');
    return defaults;
  }

  private static String stringOrNull(Object raw) {
    if (raw == null) {
      return null;
    }
    String s = String.valueOf(raw);
    return s;
  }

  /**
   * @description Single related list block for on-demand tab loading.
   */
  public static Map<String, Object> fetchRecordModalRelatedList(
    String recordId,
    String relatedListApi,
    String tabId,
    Integer rowLimit
  ) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId) || String.isBlank(relatedListApi)) {
      result.put('error', 'Record Id and related list API name are required.');
      return result;
    }
    try {
      RecordModalContext ctx = resolveRecordModalContext(recordId);
      if (ctx == null) {
        result.put('error', 'Record not found.');
        return result;
      }
      Map<String, Object> layout = normalizeLayoutLabels(resolveLayout(ctx.objectApi, ctx.recordTypeId));
      Map<String, Object> rlMeta = findLayoutRelatedList(layout, relatedListApi);
      if (rlMeta == null) {
        rlMeta = new Map<String, Object>{
          'label' => relatedListApi,
          'name' => relatedListApi
        };
      }

      Integer limitRows = resolveRelatedListRowLimit(rowLimit);
      Map<String, Object> block = fetchOneRelatedList(
        ctx.objectApi,
        ctx.recordId,
        rlMeta,
        relatedListApi,
        limitRows
      );
      if (block == null) {
        block = new Map<String, Object>{
          'label' => rlMeta.get('label'),
          'name' => relatedListApi,
          'columns' => parseRelatedListColumns(rlMeta),
          'rows' => new List<Map<String, Object>>(),
          'totalSize' => 0
        };
      }
      if (!String.isBlank(tabId)) {
        block.put('tabId', tabId);
      }
      enrichRelatedListBlockWithActions(ctx.recordId, relatedListApi, block);
      result.put('relatedList', block);
      result.put('recordId', String.valueOf(ctx.recordId));
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Attach UI API list/row actions and child object metadata to a related list block.
   */
  @TestVisible
  private static void enrichRelatedListBlockWithActions(
    Id parentRecordId,
    String relatedListApi,
    Map<String, Object> block
  ) {
    if (block == null || parentRecordId == null) {
      return;
    }
    ChildRelationshipInfo relInfo = resolveChildRelationship(
      parentRecordId.getSObjectType().getDescribe().getName(),
      relatedListApi
    );
    if (relInfo != null) {
      block.put('childObjectApi', relInfo.childObjectApi);
    }
    Map<String, List<Map<String, Object>>> listActionsMap = HubRecordActionsUtil.fetchRelatedListActionsBatch(
      String.valueOf(parentRecordId),
      new List<String>{ relatedListApi }
    );
    block.put(
      'listActions',
      listActionsMap.containsKey(relatedListApi)
        ? listActionsMap.get(relatedListApi)
        : new List<Map<String, Object>>()
    );
    List<Map<String, Object>> rows = block.containsKey('rows')
      ? (List<Map<String, Object>>) block.get('rows')
      : new List<Map<String, Object>>();
    List<String> rowIds = new List<String>();
    for (Map<String, Object> row : rows) {
      if (row != null && row.get('id') != null) {
        rowIds.add(String.valueOf(row.get('id')));
      }
    }
    if (rowIds.isEmpty()) {
      return;
    }
    Map<String, List<Map<String, Object>>> rowActionsMap = HubRecordActionsUtil.fetchRelatedListRecordActionsBatch(
      String.valueOf(parentRecordId),
      rowIds
    );
    for (Map<String, Object> row : rows) {
      if (row == null || row.get('id') == null) {
        continue;
      }
      String rid = String.valueOf(row.get('id'));
      row.put(
        'actions',
        rowActionsMap.containsKey(rid) ? rowActionsMap.get(rid) : new List<Map<String, Object>>()
      );
    }
  }

  /**
   * @description Potential duplicates payload for the Duplicates tab.
   */
  public static Map<String, Object> fetchPotentialDuplicates(String recordId) {
    return HubDuplicateUtil.fetchPotentialDuplicates(recordId);
  }

  /** @description Supported CRM Hub modal objects (for action utilities). */
  public static Boolean isSupportedObject(String objectApi) {
    return SUPPORTED_OBJECTS.contains(objectApi);
  }

  /** @description Expose field meta builder for clone forms. */
  public static Map<String, Object> buildFieldMetaPublic(String objectApi, List<String> fields) {
    return buildFieldMeta(objectApi, fields);
  }

  /** @description Expose field coercion for clone/create actions. */
  public static Object coerceFieldValuePublic(Schema.DescribeFieldResult fd, Object raw) {
    return coerceFieldValue(fd, raw);
  }

  /**
   * @description Tasks/Events timeline for the Communications tab.
   */
  public static Map<String, Object> fetchRecordModalActivities(String recordId) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId)) {
      result.put('error', 'Record Id is required.');
      return result;
    }
    try {
      Id rid = recordId;
      result.put('activities', loadActivitiesForRecord(rid));
      result.put('recordId', String.valueOf(rid));
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Create Task / Call / Event related to the record.
   */
  public static Map<String, Object> createRecordModalActivity(
    String recordId,
    String activityType,
    Map<String, Object> fields
  ) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId)) {
      result.put('error', 'Record Id is required.');
      return result;
    }
    try {
      Id rid = recordId;
      Map<String, Object> values = fields == null ? new Map<String, Object>() : fields;
      String subject = values.get('Subject') == null ? '' : String.valueOf(values.get('Subject')).trim();
      if (String.isBlank(subject)) {
        result.put('error', 'Subject is required.');
        return result;
      }
      String kind = String.isBlank(activityType) ? 'Task' : activityType.trim();
      if ('Event'.equalsIgnoreCase(kind)) {
        Event ev = new Event();
        ev.WhatId = rid;
        ev.Subject = subject;
        if (values.get('Description') != null) {
          ev.Description = String.valueOf(values.get('Description'));
        }
        Datetime startDt = parseActivityDateTime(values.get('StartDateTime'));
        Datetime endDt = parseActivityDateTime(values.get('EndDateTime'));
        if (startDt == null) {
          startDt = System.now();
        }
        if (endDt == null) {
          endDt = startDt.addHours(1);
        }
        ev.StartDateTime = startDt;
        ev.EndDateTime = endDt;
        insert ev;
      } else {
        Task t = new Task();
        t.WhatId = rid;
        t.Subject = subject;
        t.Status = 'Not Started';
        if (values.get('Description') != null) {
          t.Description = String.valueOf(values.get('Description'));
        }
        if (values.get('Priority') != null) {
          t.Priority = String.valueOf(values.get('Priority'));
        } else {
          t.Priority = 'Normal';
        }
        Date due = parseActivityDate(values.get('ActivityDate'));
        if (due != null) {
          t.ActivityDate = due;
        }
        if ('Call'.equalsIgnoreCase(kind)) {
          t.TaskSubtype = 'Call';
          t.Status = 'Completed';
          if (t.ActivityDate == null) {
            t.ActivityDate = Date.today();
          }
        }
        insert t;
      }
      result.put('success', true);
      result.put('activities', loadActivitiesForRecord(rid));
      result.put('recordId', String.valueOf(rid));
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  /**
   * @description Mark an open Task complete.
   */
  public static Map<String, Object> completeRecordModalActivity(String recordId, String activityId) {
    Map<String, Object> result = new Map<String, Object>();
    if (String.isBlank(recordId) || String.isBlank(activityId)) {
      result.put('error', 'Record Id and activity Id are required.');
      return result;
    }
    try {
      Id rid = recordId;
      Id actId = activityId;
      List<Task> tasks = [
        SELECT Id, Status, WhatId
        FROM Task
        WHERE Id = :actId AND WhatId = :rid
        LIMIT 1
      ];
      if (tasks.isEmpty()) {
        result.put('error', 'Task not found for this record.');
        return result;
      }
      tasks[0].Status = 'Completed';
      update tasks;
      result.put('success', true);
      result.put('activities', loadActivitiesForRecord(rid));
      result.put('recordId', String.valueOf(rid));
    } catch (Exception e) {
      result.put('error', e.getMessage());
    }
    return result;
  }

  @TestVisible
  private static List<Map<String, Object>> loadActivitiesForRecord(Id recordId) {
    List<Map<String, Object>> activities = new List<Map<String, Object>>();
    for (Task t : [
      SELECT
        Id,
        Subject,
        Status,
        Priority,
        ActivityDate,
        Description,
        TaskSubtype,
        IsClosed,
        Owner.Name,
        CreatedDate
      FROM Task
      WHERE WhatId = :recordId
      ORDER BY ActivityDate DESC NULLS LAST, CreatedDate DESC
      LIMIT 100
    ]) {
      String typeLabel = 'Call'.equalsIgnoreCase(String.valueOf(t.TaskSubtype)) ? 'Call' : 'Task';
      activities.add(
        new Map<String, Object>{
          'id' => String.valueOf(t.Id),
          'type' => typeLabel,
          'subject' => t.Subject,
          'status' => t.Status,
          'activityDate' => t.ActivityDate == null ? null : String.valueOf(t.ActivityDate),
          'description' => t.Description,
          'ownerName' => t.Owner != null ? t.Owner.Name : null,
          'isOpen' => t.IsClosed != true
        }
      );
    }
    for (Event ev : [
      SELECT
        Id,
        Subject,
        StartDateTime,
        EndDateTime,
        Description,
        Owner.Name,
        CreatedDate
      FROM Event
      WHERE WhatId = :recordId
      ORDER BY StartDateTime DESC NULLS LAST, CreatedDate DESC
      LIMIT 100
    ]) {
      Boolean isOpen = ev.EndDateTime == null || ev.EndDateTime >= System.now();
      activities.add(
        new Map<String, Object>{
          'id' => String.valueOf(ev.Id),
          'type' => 'Event',
          'subject' => ev.Subject,
          'status' => isOpen ? 'Open' : 'Completed',
          'activityDate' => ev.StartDateTime == null
            ? null
            : ev.StartDateTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
          'description' => ev.Description,
          'ownerName' => ev.Owner != null ? ev.Owner.Name : null,
          'isOpen' => isOpen
        }
      );
    }
    return activities;
  }

  @TestVisible
  private static Date parseActivityDate(Object raw) {
    if (raw == null) {
      return null;
    }
    String s = String.valueOf(raw).trim();
    if (String.isBlank(s)) {
      return null;
    }
    if (s.length() >= 10) {
      try {
        return Date.valueOf(s.substring(0, 10));
      } catch (Exception e) {
        // fall through
      }
    }
    return null;
  }

  @TestVisible
  private static Datetime parseActivityDateTime(Object raw) {
    if (raw == null) {
      return null;
    }
    String s = String.valueOf(raw).trim();
    if (String.isBlank(s)) {
      return null;
    }
    try {
      if (s.contains('T')) {
        String normalized = s.replace('T', ' ');
        if (normalized.length() == 16) {
          normalized += ':00';
        }
        return Datetime.valueOf(normalized);
      }
      return Datetime.valueOf(s);
    } catch (Exception e) {
      return null;
    }
  }

  private class RecordModalContext {
    public Id recordId;
    public String objectApi;
    public String objectLabel;
    public Id recordTypeId;
    public Schema.DescribeSObjectResult objDesc;
    public SObject record;
  }

  @TestVisible
  private static RecordModalContext resolveRecordModalContext(String recordId) {
    Id rid = recordId;
    Schema.DescribeSObjectResult objDesc = rid.getSObjectType().getDescribe();
    String objectApi = objDesc.getName();
    Map<String, Schema.SObjectField> fieldMap = objDesc.fields.getMap();

    List<String> shellFields = new List<String>{ 'Id' };
    if (fieldMap.containsKey('Name')) {
      shellFields.add('Name');
    }
    if (fieldMap.containsKey('RecordTypeId')) {
      shellFields.add('RecordTypeId');
    }

    String soql =
      'SELECT ' +
      String.join(shellFields, ', ') +
      ' FROM ' +
      objectApi +
      ' WHERE Id = :rid LIMIT 1';
    List<SObject> rows = Database.queryWithBinds(
      soql,
      new Map<String, Object>{ 'rid' => rid },
      AccessLevel.SYSTEM_MODE
    );
    if (rows.isEmpty()) {
      return null;
    }

    SObject rec = rows[0];
    Id recordTypeId = null;
    if (fieldMap.containsKey('RecordTypeId')) {
      recordTypeId = (Id) rec.get('RecordTypeId');
    }
    if (recordTypeId == null) {
      recordTypeId = resolveRecordTypeId(rid, objectApi, objDesc);
    }

    RecordModalContext ctx = new RecordModalContext();
    ctx.recordId = rid;
    ctx.objectApi = objectApi;
    ctx.objectLabel = objDesc.getLabel();
    ctx.recordTypeId = recordTypeId;
    ctx.objDesc = objDesc;
    ctx.record = rec;
    return ctx;
  }

  @TestVisible
  private static SObject queryRecordFields(Id recordId, String objectApi, List<String> queryFields) {
    if (queryFields == null || queryFields.isEmpty()) {
      return null;
    }
    String soql =
      'SELECT ' +
      String.join(queryFields, ', ') +
      ' FROM ' +
      objectApi +
      ' WHERE Id = :recordId LIMIT 1';
    List<SObject> rows = Database.queryWithBinds(
      soql,
      new Map<String, Object>{ 'recordId' => recordId },
      AccessLevel.SYSTEM_MODE
    );
    return rows.isEmpty() ? null : rows[0];
  }

  private static Map<String, Object> mergeModalPayload(
    Map<String, Object> shell,
    Map<String, Object> details
  ) {
    Map<String, Object> merged = new Map<String, Object>();
    merged.putAll(shell);
    for (String key : details.keySet()) {
      merged.put(key, details.get(key));
    }
    return merged;
  }

  private static final Set<String> SKIP_RELATED_LIST_KEYS = new Set<String>{
    'RelatedActivityList',
    'RelatedHistoryList',
    'RelatedNoteList',
    'RelatedEntityHistoryList',
    'RelatedContentNoteList',
    'RelatedEmailStatusList',
    'RelatedCampaignList',
    'RelatedAccountSalesTeam',
    'RelatedPartnerList',
    'RelatedProcessHistoryList'
  };

  @TestVisible
  private static List<Map<String, Object>> resolveRecordTabs(String objectApi, Map<String, Object> layout) {
    List<Map<String, Object>> tabs;
    if (Test.isRunningTest() && testTabsOverride != null) {
      tabs = ensureOpportunityHubTabs(objectApi, testTabsOverride, layout);
    } else {
      List<Map<String, Object>> flexiTabs = resolveFlexiPageTabs(objectApi, layout);
      if (!flexiTabs.isEmpty()) {
        tabs = ensureOpportunityHubTabs(objectApi, flexiTabs, layout);
      } else {
        tabs = ensureOpportunityHubTabs(objectApi, buildTabsFromLayout(layout), layout);
      }
    }
    return ensureDuplicatesTab(objectApi, tabs);
  }

  /**
   * @description Opportunity CRM Hub: guarantee Communications, Contact Roles,
   * Salesforce Power, and Agentforce Intent Insights alongside FlexiPage tabs.
   */
  @TestVisible
  private static List<Map<String, Object>> ensureOpportunityHubTabs(
    String objectApi,
    List<Map<String, Object>> tabs,
    Map<String, Object> layout
  ) {
    List<Map<String, Object>> resultTabs = ensureSalesforcePowerTab(objectApi, tabs);
    if (!'Opportunity'.equals(objectApi)) {
      return resultTabs;
    }
    resultTabs = ensureActivityTab(resultTabs);
    resultTabs = ensureContactRelatedTab(resultTabs, layout);
    resultTabs = ensureIntentInsightsTab(resultTabs);
    return resultTabs;
  }

  /**
   * @description Opportunity CRM Hub: always expose Salesforce Power (VF/LWC clone) as a tab.
   */
  @TestVisible
  private static List<Map<String, Object>> ensureSalesforcePowerTab(
    String objectApi,
    List<Map<String, Object>> tabs
  ) {
    if (!'Opportunity'.equals(objectApi)) {
      return tabs == null ? new List<Map<String, Object>>() : tabs;
    }
    List<Map<String, Object>> resultTabs = tabs == null
      ? new List<Map<String, Object>>()
      : new List<Map<String, Object>>(tabs);
    for (Map<String, Object> tab : resultTabs) {
      if (tab == null) {
        continue;
      }
      if (isSalesforcePowerTab(tab)) {
        tab.put('type', 'salesforcePower');
        tab.put('componentName', 'c:opportunitySalesforcePower');
        if (String.isBlank(String.valueOf(tab.get('label')))) {
          tab.put('label', 'Salesforce Power');
        }
        return resultTabs;
      }
    }
    Integer insertAt = resultTabs.isEmpty() ? 0 : 1;
    Map<String, Object> powerTab = new Map<String, Object>{
      'id' => 'salesforce_power',
      'label' => 'Salesforce Power',
      'type' => 'salesforcePower',
      'componentName' => 'c:opportunitySalesforcePower',
      'active' => false
    };
    if (insertAt >= resultTabs.size()) {
      resultTabs.add(powerTab);
    } else {
      resultTabs.add(insertAt, powerTab);
    }
    return resultTabs;
  }

  @TestVisible
  private static List<Map<String, Object>> ensureDuplicatesTab(
    String objectApi,
    List<Map<String, Object>> tabs
  ) {
    Set<String> dupObjects = new Set<String>{ 'Lead', 'Contact', 'Account', 'Job_Application__c' };
    if (!dupObjects.contains(objectApi)) {
      return tabs == null ? new List<Map<String, Object>>() : tabs;
    }
    List<Map<String, Object>> resultTabs = tabs == null
      ? new List<Map<String, Object>>()
      : new List<Map<String, Object>>(tabs);
    for (Map<String, Object> tab : resultTabs) {
      if (tab != null && 'duplicates'.equals(String.valueOf(tab.get('type')))) {
        tab.put('label', 'Potential Duplicates');
        return resultTabs;
      }
    }
    Map<String, Object> dupTab = new Map<String, Object>{
      'id' => 'potential_duplicates',
      'label' => 'Potential Duplicates',
      'type' => 'duplicates',
      'active' => false
    };
    resultTabs.add(dupTab);
    return resultTabs;
  }

  @TestVisible
  private static List<Map<String, Object>> ensureActivityTab(List<Map<String, Object>> tabs) {
    List<Map<String, Object>> resultTabs = tabs == null
      ? new List<Map<String, Object>>()
      : new List<Map<String, Object>>(tabs);
    for (Map<String, Object> tab : resultTabs) {
      if (tab == null) {
        continue;
      }
      if (isActivityTab(tab)) {
        tab.put('type', 'activity');
        if (String.isBlank(String.valueOf(tab.get('label')))) {
          tab.put('label', 'Communications');
        }
        return resultTabs;
      }
    }
    Integer insertAt = resultTabs.isEmpty() ? 0 : 1;
    Map<String, Object> activityTab = new Map<String, Object>{
      'id' => 'communications',
      'label' => 'Communications',
      'type' => 'activity',
      'active' => false
    };
    if (insertAt >= resultTabs.size()) {
      resultTabs.add(activityTab);
    } else {
      resultTabs.add(insertAt, activityTab);
    }
    return resultTabs;
  }

  @TestVisible
  private static List<Map<String, Object>> ensureContactRelatedTab(
    List<Map<String, Object>> tabs,
    Map<String, Object> layout
  ) {
    List<Map<String, Object>> resultTabs = tabs == null
      ? new List<Map<String, Object>>()
      : new List<Map<String, Object>>(tabs);
    if (hasContactRelatedTab(resultTabs)) {
      return resultTabs;
    }

    List<Map<String, Object>> relatedBlocks = new List<Map<String, Object>>();
    Map<String, Object> contactRolesMeta = findLayoutRelatedList(layout, 'RelatedContactRoleList');
    if (contactRolesMeta == null) {
      contactRolesMeta = findLayoutRelatedList(layout, 'OpportunityContactRoles');
    }
    String contactRolesName = contactRolesMeta != null && contactRolesMeta.get('name') != null
      ? String.valueOf(contactRolesMeta.get('name'))
      : 'OpportunityContactRoles';
    String contactRolesLabel = contactRolesMeta != null && contactRolesMeta.get('label') != null
      ? decodeHtmlEntities(String.valueOf(contactRolesMeta.get('label')))
      : 'Contact Roles';
    relatedBlocks.add(
      new Map<String, Object>{
        'relatedListName' => contactRolesName,
        'relatedListLabel' => contactRolesLabel,
        'relatedListMeta' => contactRolesMeta
      }
    );
    relatedBlocks.add(
      new Map<String, Object>{
        'relatedListName' => 'ParentAccountContacts',
        'relatedListLabel' => 'Contacts for Parent Account',
        'relatedListMeta' => new Map<String, Object>{
          'label' => 'Contacts for Parent Account',
          'name' => 'ParentAccountContacts',
          'relatedList' => 'ParentAccountContacts',
          'columns' => new List<Object>{
            'CONTACT.FULL_NAME',
            'CONTACT.TITLE',
            'CONTACT.EMAIL',
            'CONTACT.PHONE',
            'CREATED_DATE'
          }
        }
      }
    );

    Integer insertAt = Math.min(2, resultTabs.size());
    Map<String, Object> contactsTab = new Map<String, Object>{
      'id' => 'contact_roles',
      'label' => 'Contacts',
      'type' => 'relatedMulti',
      'relatedBlocks' => relatedBlocks,
      'active' => false
    };
    if (insertAt >= resultTabs.size()) {
      resultTabs.add(contactsTab);
    } else {
      resultTabs.add(insertAt, contactsTab);
    }
    return resultTabs;
  }

  @TestVisible
  private static List<Map<String, Object>> ensureIntentInsightsTab(List<Map<String, Object>> tabs) {
    List<Map<String, Object>> resultTabs = tabs == null
      ? new List<Map<String, Object>>()
      : new List<Map<String, Object>>(tabs);
    for (Map<String, Object> tab : resultTabs) {
      if (tab == null) {
        continue;
      }
      if (isIntentInsightsTab(tab)) {
        tab.put('type', 'intentInsights');
        tab.put('componentName', 'c:powerIntentViewer');
        if (String.isBlank(String.valueOf(tab.get('label')))) {
          tab.put('label', 'Agentforce Intent Insights');
        }
        return resultTabs;
      }
    }
    Integer insertAt = Math.min(3, resultTabs.size());
    Map<String, Object> insightsTab = new Map<String, Object>{
      'id' => 'intent_insights',
      'label' => 'Agentforce Intent Insights',
      'type' => 'intentInsights',
      'componentName' => 'c:powerIntentViewer',
      'active' => false
    };
    if (insertAt >= resultTabs.size()) {
      resultTabs.add(insightsTab);
    } else {
      resultTabs.add(insertAt, insightsTab);
    }
    return resultTabs;
  }

  @TestVisible
  private static Boolean isActivityTab(Map<String, Object> tab) {
    if (tab == null) {
      return false;
    }
    if ('activity'.equals(tab.get('type'))) {
      return true;
    }
    String label = tab.get('label') == null ? '' : String.valueOf(tab.get('label')).toLowerCase();
    if (
      label == 'activity' ||
      label == 'activities' ||
      label == 'communications' ||
      label == 'communication'
    ) {
      return true;
    }
    String componentName = tab.get('componentName') == null
      ? ''
      : String.valueOf(tab.get('componentName')).toLowerCase();
    return isActivityComponentName(componentName);
  }

  @TestVisible
  private static Boolean isActivityComponentName(String componentName) {
    if (String.isBlank(componentName)) {
      return false;
    }
    String lower = componentName.toLowerCase();
    return lower.contains('activitypanel') ||
      lower.contains('activity_composer') ||
      lower.contains('runtime_sales_activities');
  }

  @TestVisible
  private static Boolean isIntentInsightsTab(Map<String, Object> tab) {
    if (tab == null) {
      return false;
    }
    if ('intentInsights'.equals(tab.get('type'))) {
      return true;
    }
    String label = tab.get('label') == null ? '' : String.valueOf(tab.get('label')).toLowerCase();
    if (label.contains('intent insight') || label == 'agentforce intent insights') {
      return true;
    }
    String componentName = tab.get('componentName') == null
      ? ''
      : String.valueOf(tab.get('componentName')).toLowerCase();
    return componentName.contains('powerintentviewer') ||
      componentName.contains('intentinsight');
  }

  @TestVisible
  private static Boolean hasContactRelatedTab(List<Map<String, Object>> tabs) {
    if (tabs == null) {
      return false;
    }
    for (Map<String, Object> tab : tabs) {
      if (tab == null) {
        continue;
      }
      String label = tab.get('label') == null ? '' : String.valueOf(tab.get('label')).toLowerCase();
      if (
        label.contains('contact role') ||
        label == 'contacts' ||
        label.contains('contacts for parent')
      ) {
        return true;
      }
      String rlName = tab.get('relatedListName') == null
        ? ''
        : String.valueOf(tab.get('relatedListName')).toLowerCase();
      if (
        rlName.contains('contactrole') ||
        rlName == 'opportunitycontactroles' ||
        rlName == 'parentaccountcontacts'
      ) {
        return true;
      }
      List<Object> blocks = (List<Object>) tab.get('relatedBlocks');
      if (blocks != null) {
        for (Object blockObj : blocks) {
          Map<String, Object> block = (Map<String, Object>) blockObj;
          if (block == null) {
            continue;
          }
          String blockName = block.get('relatedListName') == null
            ? ''
            : String.valueOf(block.get('relatedListName')).toLowerCase();
          String blockLabel = block.get('relatedListLabel') == null
            ? ''
            : String.valueOf(block.get('relatedListLabel')).toLowerCase();
          if (
            blockName.contains('contactrole') ||
            blockName == 'opportunitycontactroles' ||
            blockName == 'parentaccountcontacts' ||
            blockLabel.contains('contact role') ||
            blockLabel.contains('contacts for parent')
          ) {
            return true;
          }
        }
      }
    }
    return false;
  }

  @TestVisible
  private static Boolean isSalesforcePowerTab(Map<String, Object> tab) {
    if (tab == null) {
      return false;
    }
    if ('salesforcePower'.equals(tab.get('type'))) {
      return true;
    }
    String label = tab.get('label') == null ? '' : String.valueOf(tab.get('label')).toLowerCase();
    if (
      label == 'salesforce power' ||
      label == 'agentforce opportunity consultant' ||
      label == 'agentforce consultant' ||
      (label.contains('agentforce') && label.contains('consultant'))
    ) {
      return true;
    }
    String componentName = tab.get('componentName') == null
      ? ''
      : String.valueOf(tab.get('componentName'));
    if (String.isBlank(componentName)) {
      return false;
    }
    String lower = componentName.toLowerCase();
    return lower.contains('opportunitysalesforcepower') ||
      lower.contains('salesforce_power') ||
      lower.contains('opportunity_salesforce_power');
  }

  @TestVisible
  private static List<Map<String, Object>> resolveFlexiPageTabs(String objectApi, Map<String, Object> layout) {
    List<Map<String, Object>> pages = fetchFlexiPages(objectApi);
    if (pages.isEmpty()) {
      return new List<Map<String, Object>>();
    }

    List<Map<String, Object>> bestTabs = new List<Map<String, Object>>();
    for (Map<String, Object> page : pages) {
      Map<String, Object> metadata = (Map<String, Object>) page.get('metadata');
      if (metadata == null) {
        continue;
      }
      List<Map<String, Object>> tabs = parseFlexiPageMetadata(metadata, layout);
      if (tabs.size() > bestTabs.size()) {
        bestTabs = tabs;
      }
    }
    return bestTabs;
  }

  @TestVisible
  private static List<Map<String, Object>> fetchFlexiPages(String objectApi) {
    List<Map<String, Object>> out = new List<Map<String, Object>>();
    String soql =
      'SELECT Id, DeveloperName FROM FlexiPage WHERE EntityDefinition.QualifiedApiName = \'' +
      String.escapeSingleQuotes(objectApi) +
      '\' AND Type = \'RecordPage\'';
    String path =
      '/services/data/' +
      REST_API_VERSION +
      '/tooling/query?q=' +
      EncodingUtil.urlEncode(soql, 'UTF-8');
    Map<String, Object> body = null;
    for (String base : orgApiBaseUrls()) {
      body = httpGetJson(base + path);
      if (body != null && body.containsKey('records')) {
        break;
      }
    }
    if (body == null) {
      return out;
    }
    List<Object> records = (List<Object>) body.get('records');
    if (records == null) {
      return out;
    }
    for (Object recObj : records) {
      Map<String, Object> rec = (Map<String, Object>) recObj;
      String pageId = rec.get('Id') == null ? '' : String.valueOf(rec.get('Id'));
      if (String.isBlank(pageId)) {
        continue;
      }
      Map<String, Object> pageBody = fetchFlexiPageById(pageId);
      if (pageBody == null) {
        continue;
      }
      Map<String, Object> metadata = (Map<String, Object>) pageBody.get('Metadata');
      if (metadata == null) {
        continue;
      }
      out.add(
        new Map<String, Object>{
          'developerName' => rec.get('DeveloperName'),
          'metadata' => metadata
        }
      );
    }
    return out;
  }

  @TestVisible
  private static Map<String, Object> fetchFlexiPageById(String pageId) {
    String path = '/services/data/' + REST_API_VERSION + '/tooling/sobjects/FlexiPage/' + pageId;
    for (String base : orgApiBaseUrls()) {
      Map<String, Object> body = httpGetJson(base + path);
      if (body != null && body.containsKey('Metadata')) {
        return body;
      }
    }
    return null;
  }

  @TestVisible
  private static List<Map<String, Object>> parseFlexiPageMetadata(
    Map<String, Object> metadata,
    Map<String, Object> layout
  ) {
    Map<String, List<Map<String, Object>>> facetComponents = buildFacetComponentMap(metadata);
    String tabsFacet = findTabsFacetName(metadata);
    if (String.isBlank(tabsFacet) || !facetComponents.containsKey(tabsFacet)) {
      return new List<Map<String, Object>>();
    }

    List<Map<String, Object>> tabs = new List<Map<String, Object>>();
    Integer tabIndex = 0;
    for (Map<String, Object> comp : facetComponents.get(tabsFacet)) {
      if (!'flexipage:tab'.equals(comp.get('componentName'))) {
        continue;
      }
      Map<String, Object> props = (Map<String, Object>) comp.get('props');
      if (props == null) {
        continue;
      }
      String bodyFacet = props.get('body') == null ? '' : String.valueOf(props.get('body'));
      String title = props.get('title') == null ? 'Tab' : String.valueOf(props.get('title'));
      String tabId = 'tab_' + tabIndex;
      Boolean active = 'true'.equalsIgnoreCase(String.valueOf(props.get('active')));
      Map<String, Object> tab = buildTabFromFacet(tabId, resolveTabLabel(title), bodyFacet, facetComponents, layout);
      tab.put('active', active);
      tabs.add(tab);
      tabIndex++;
    }
    if (!tabs.isEmpty() && !hasActiveTab(tabs)) {
      tabs[0].put('active', true);
    }
    return tabs;
  }

  private static Boolean hasActiveTab(List<Map<String, Object>> tabs) {
    for (Map<String, Object> tab : tabs) {
      if (tab.get('active') == true) {
        return true;
      }
    }
    return false;
  }

  @TestVisible
  private static Map<String, Object> buildTabFromFacet(
    String tabId,
    String label,
    String bodyFacet,
    Map<String, List<Map<String, Object>>> facetComponents,
    Map<String, Object> layout
  ) {
    List<Map<String, Object>> bodyComps = facetComponents.get(bodyFacet);
    if (bodyComps == null || bodyComps.isEmpty()) {
      return new Map<String, Object>{
        'id' => tabId,
        'label' => label,
        'type' => 'custom',
        'message' => 'This tab is available in Salesforce Lightning.'
      };
    }

    Boolean hasDetail = false;
    List<Map<String, Object>> relatedBlocks = new List<Map<String, Object>>();
    String customComponent = null;
    Map<String, Object> customProps = null;
    for (Map<String, Object> comp : bodyComps) {
      String componentName = (String) comp.get('componentName');
      Map<String, Object> props = (Map<String, Object>) comp.get('props');
      if ('force:detailPanel'.equals(componentName)) {
        hasDetail = true;
      } else if ('force:relatedListContainer'.equals(componentName)) {
        relatedBlocks.addAll(buildRelatedBlocksFromLayout(layout));
      } else if (
        'force:relatedListSingleContainer'.equals(componentName) ||
        'lst:dynamicRelatedList'.equals(componentName)
      ) {
        String rlName = resolveRelatedListApiFromProps(props, layout);
        String rlLabel = props != null && props.get('relatedListLabel') != null
          ? String.valueOf(props.get('relatedListLabel'))
          : label;
        if (String.isBlank(rlName) && !String.isBlank(rlLabel)) {
          rlName = findRelatedListNameByLabel(layout, rlLabel);
        }
        Map<String, Object> rlMeta = findLayoutRelatedList(layout, rlName);
        if (rlMeta != null && String.isBlank(rlLabel)) {
          rlLabel = rlMeta.get('label') == null ? rlName : String.valueOf(rlMeta.get('label'));
        }
        relatedBlocks.add(
          new Map<String, Object>{
            'relatedListName' => rlName,
            'relatedListLabel' => rlLabel,
            'relatedListMeta' => rlMeta
          }
        );
      } else if (!String.isBlank(componentName)) {
        customComponent = componentName;
        customProps = props;
      }
    }

    if (hasDetail) {
      return new Map<String, Object>{
        'id' => tabId,
        'label' => label,
        'type' => 'details'
      };
    }
    relatedBlocks = filterValidRelatedBlocks(relatedBlocks);
    if (relatedBlocks.size() == 1) {
      Map<String, Object> block = relatedBlocks[0];
      return new Map<String, Object>{
        'id' => tabId,
        'label' => label,
        'type' => 'related',
        'relatedListName' => block.get('relatedListName'),
        'relatedListLabel' => block.get('relatedListLabel'),
        'relatedListMeta' => block.get('relatedListMeta')
      };
    }
    if (relatedBlocks.size() > 1) {
      return new Map<String, Object>{
        'id' => tabId,
        'label' => label,
        'type' => 'relatedMulti',
        'relatedBlocks' => relatedBlocks
      };
    }

    if (isActivityComponentName(customComponent) || isActivityTab(new Map<String, Object>{ 'label' => label })) {
      return new Map<String, Object>{
        'id' => tabId,
        'label' => label,
        'type' => 'activity',
        'componentName' => customComponent
      };
    }

    Map<String, Object> visualforceTab = tryBuildVisualforceTab(
      tabId,
      label,
      customComponent,
      customProps
    );
    if (visualforceTab != null) {
      return visualforceTab;
    }

    Map<String, Object> rssTab = tryBuildRssFeedTab(tabId, label, customComponent, customProps);
    if (rssTab != null) {
      return rssTab;
    }

    Map<String, Object> candidate = new Map<String, Object>{
      'id' => tabId,
      'label' => label,
      'type' => 'custom',
      'componentName' => customComponent,
      'message' =>
        'This Lightning component' +
        (String.isBlank(customComponent) ? '' : ' (' + customComponent + ')') +
        ' is not available in CRM Hub. Open the record in Salesforce for the full experience.'
    };
    if (isSalesforcePowerTab(candidate)) {
      candidate.put('type', 'salesforcePower');
      candidate.put('componentName', 'c:opportunitySalesforcePower');
      candidate.put('message', null);
    } else if (isIntentInsightsTab(candidate)) {
      candidate.put('type', 'intentInsights');
      candidate.put('componentName', 'c:powerIntentViewer');
      candidate.put('message', null);
    }
    return candidate;
  }

  @TestVisible
  private static Map<String, Object> tryBuildVisualforceTab(
    String tabId,
    String label,
    String componentName,
    Map<String, Object> props
  ) {
    String lowerComponent = componentName == null ? '' : componentName.toLowerCase();
    String lowerLabel = label == null ? '' : label.toLowerCase();
    Boolean isVisualforce = lowerComponent.contains('visualforcepage');
    Boolean isTeamBuilder = lowerLabel.contains('team builder') || lowerLabel == 'team builder';
    if (!isVisualforce && !isTeamBuilder) {
      return null;
    }
    String pageName = extractVisualforcePageName(props);
    if (String.isBlank(pageName) && isTeamBuilder) {
      pageName = 'OpportunityTeam';
    }
    if (String.isBlank(pageName)) {
      return null;
    }
    return new Map<String, Object>{
      'id' => tabId,
      'label' => label,
      'type' => 'visualforce',
      'pageName' => pageName,
      'componentName' => componentName
    };
  }

  @TestVisible
  private static String extractVisualforcePageName(Map<String, Object> props) {
    if (props == null) {
      return null;
    }
    for (String key : new List<String>{
      'pageName',
      'visualforcePage',
      'page',
      'apexPageName',
      'vfPageName'
    }) {
      if (props.get(key) != null && !String.isBlank(String.valueOf(props.get(key)))) {
        return String.valueOf(props.get(key));
      }
    }
    return null;
  }

  @TestVisible
  private static Map<String, Object> tryBuildRssFeedTab(
    String tabId,
    String label,
    String componentName,
    Map<String, Object> props
  ) {
    String lowerComponent = componentName == null ? '' : componentName.toLowerCase();
    String lowerLabel = label == null ? '' : label.toLowerCase();
    Boolean isRss =
      lowerComponent.contains('cloudastickrssfeedviewer') ||
      lowerComponent.contains('rssfeedviewer');
    Boolean isNews =
      lowerLabel.contains('agentforce news') ||
      lowerLabel == 'news' ||
      lowerLabel.contains('rss');
    if (!isRss && !isNews) {
      return null;
    }
    String rssField = 'Google_Alert_URL__c';
    if (props != null && props.get('rssUrlFieldName') != null) {
      String fromProps = String.valueOf(props.get('rssUrlFieldName'));
      if (!String.isBlank(fromProps)) {
        rssField = fromProps;
      }
    }
    return new Map<String, Object>{
      'id' => tabId,
      'label' => label,
      'type' => 'rssFeed',
      'componentName' => 'c:cloudastickRssFeedViewer',
      'rssUrlFieldName' => rssField
    };
  }

  @TestVisible
  private static List<Map<String, Object>> filterValidRelatedBlocks(
    List<Map<String, Object>> relatedBlocks
  ) {
    List<Map<String, Object>> valid = new List<Map<String, Object>>();
    if (relatedBlocks == null) {
      return valid;
    }
    for (Map<String, Object> block : relatedBlocks) {
      String name = block.get('relatedListName') == null
        ? ''
        : String.valueOf(block.get('relatedListName'));
      if (!String.isBlank(name)) {
        valid.add(block);
      }
    }
    return valid;
  }

  @TestVisible
  private static Map<String, List<Map<String, Object>>> buildFacetComponentMap(Map<String, Object> metadata) {
    Map<String, List<Map<String, Object>>> facetComponents = new Map<String, List<Map<String, Object>>>();
    if (metadata == null || !metadata.containsKey('flexiPageRegions')) {
      return facetComponents;
    }
    List<Object> regions = (List<Object>) metadata.get('flexiPageRegions');
    for (Object regionObj : regions) {
      Map<String, Object> region = (Map<String, Object>) regionObj;
      String facetName = region.get('name') == null ? '' : String.valueOf(region.get('name'));
      List<Map<String, Object>> comps = new List<Map<String, Object>>();
      List<Object> items = (List<Object>) region.get('itemInstances');
      if (items != null) {
        for (Object itemObj : items) {
          Map<String, Object> item = (Map<String, Object>) itemObj;
          Map<String, Object> ci = (Map<String, Object>) item.get('componentInstance');
          if (ci == null) {
            continue;
          }
          Map<String, Object> props = new Map<String, Object>();
          List<Object> propList = (List<Object>) ci.get('componentInstanceProperties');
          if (propList != null) {
            for (Object propObj : propList) {
              Map<String, Object> prop = (Map<String, Object>) propObj;
              if (prop.get('name') != null) {
                props.put(String.valueOf(prop.get('name')), prop.get('value'));
              }
            }
          }
          comps.add(
            new Map<String, Object>{
              'componentName' => ci.get('componentName'),
              'props' => props
            }
          );
        }
      }
      facetComponents.put(facetName, comps);
    }
    return facetComponents;
  }

  @TestVisible
  private static String findTabsFacetName(Map<String, Object> metadata) {
    if (metadata == null || !metadata.containsKey('flexiPageRegions')) {
      return '';
    }
    List<Object> regions = (List<Object>) metadata.get('flexiPageRegions');
    for (Object regionObj : regions) {
      Map<String, Object> region = (Map<String, Object>) regionObj;
      List<Object> items = (List<Object>) region.get('itemInstances');
      if (items == null) {
        continue;
      }
      for (Object itemObj : items) {
        Map<String, Object> item = (Map<String, Object>) itemObj;
        Map<String, Object> ci = (Map<String, Object>) item.get('componentInstance');
        if (ci == null || !'flexipage:tabset'.equals(ci.get('componentName'))) {
          continue;
        }
        List<Object> propList = (List<Object>) ci.get('componentInstanceProperties');
        if (propList == null) {
          continue;
        }
        for (Object propObj : propList) {
          Map<String, Object> prop = (Map<String, Object>) propObj;
          if ('tabs'.equals(prop.get('name')) && prop.get('value') != null) {
            return String.valueOf(prop.get('value'));
          }
        }
      }
    }
    return '';
  }

  @TestVisible
  private static String resolveTabLabel(String title) {
    if (String.isBlank(title)) {
      return 'Tab';
    }
    if (STANDARD_TAB_LABELS.containsKey(title)) {
      return STANDARD_TAB_LABELS.get(title);
    }
    return decodeHtmlEntities(title);
  }

  @TestVisible
  private static String decodeHtmlEntities(String value) {
    if (String.isBlank(value)) {
      return value;
    }
    String decoded = value;
    for (Integer i = 0; i < 4; i++) {
      String previous = decoded;
      decoded = decoded.replace('&amp;', '&');
      decoded = decoded.replace('&AMP;', '&');
      decoded = decoded.replace('&lt;', '<');
      decoded = decoded.replace('&LT;', '<');
      decoded = decoded.replace('&gt;', '>');
      decoded = decoded.replace('&GT;', '>');
      decoded = decoded.replace('&quot;', '"');
      decoded = decoded.replace('&QUOT;', '"');
      decoded = decoded.replace('&#39;', '\'');
      decoded = decoded.replace('&#039;', '\'');
      if (decoded == previous) {
        break;
      }
    }
    return decoded;
  }

  @TestVisible
  private static Map<String, Object> normalizeLayoutLabels(Map<String, Object> layout) {
    if (layout == null) {
      return null;
    }
    if (layout.containsKey('detailLayoutSections')) {
      List<Object> sections = (List<Object>) layout.get('detailLayoutSections');
      for (Object secObj : sections) {
        Map<String, Object> section = (Map<String, Object>) secObj;
        if (section.get('heading') != null) {
          section.put('heading', decodeHtmlEntities(String.valueOf(section.get('heading'))));
        }
        List<Object> rows = (List<Object>) section.get('layoutRows');
        if (rows == null) {
          continue;
        }
        for (Object rowObj : rows) {
          Map<String, Object> row = (Map<String, Object>) rowObj;
          List<Object> items = (List<Object>) row.get('layoutItems');
          if (items == null) {
            continue;
          }
          for (Object itemObj : items) {
            Map<String, Object> item = (Map<String, Object>) itemObj;
            if (item.get('label') != null) {
              item.put('label', decodeHtmlEntities(String.valueOf(item.get('label'))));
            }
          }
        }
      }
    }
    if (layout.containsKey('relatedLists')) {
      List<Object> rls = (List<Object>) layout.get('relatedLists');
      for (Object rlObj : rls) {
        Map<String, Object> rlMeta = (Map<String, Object>) rlObj;
        if (rlMeta.get('label') != null) {
          rlMeta.put('label', decodeHtmlEntities(String.valueOf(rlMeta.get('label'))));
        }
      }
    }
    return layout;
  }

  @TestVisible
  private static List<Map<String, Object>> buildTabsFromLayout(Map<String, Object> layout) {
    List<Map<String, Object>> tabs = new List<Map<String, Object>>();
    tabs.add(
      new Map<String, Object>{
        'id' => 'details',
        'label' => 'Details',
        'type' => 'details',
        'active' => true
      }
    );
    if (layout == null || !layout.containsKey('relatedLists')) {
      return tabs;
    }
    Integer tabIndex = 0;
    List<Object> rls = (List<Object>) layout.get('relatedLists');
    for (Object rlObj : rls) {
      Map<String, Object> rlMeta = (Map<String, Object>) rlObj;
      String relatedListKey = rlMeta.get('relatedList') == null
        ? ''
        : String.valueOf(rlMeta.get('relatedList'));
      if (SKIP_RELATED_LIST_KEYS.contains(relatedListKey)) {
        continue;
      }
      String rlName = rlMeta.get('name') == null ? '' : String.valueOf(rlMeta.get('name'));
      if (String.isBlank(rlName)) {
        continue;
      }
      String label = rlMeta.get('label') == null
        ? rlName
        : decodeHtmlEntities(String.valueOf(rlMeta.get('label')));
      tabs.add(
        new Map<String, Object>{
          'id' => 'rl_' + tabIndex,
          'label' => label,
          'type' => 'related',
          'relatedListName' => rlName,
          'relatedListLabel' => label,
          'relatedListMeta' => rlMeta
        }
      );
      tabIndex++;
      if (tabIndex >= 8) {
        break;
      }
    }
    return tabs;
  }

  @TestVisible
  private static Map<String, Object> findLayoutRelatedList(Map<String, Object> layout, String rlName) {
    if (layout == null || String.isBlank(rlName) || !layout.containsKey('relatedLists')) {
      return null;
    }
    List<Object> rls = (List<Object>) layout.get('relatedLists');
    for (Object rlObj : rls) {
      Map<String, Object> rlMeta = (Map<String, Object>) rlObj;
      String name = rlMeta.get('name') == null ? '' : String.valueOf(rlMeta.get('name'));
      String relatedListKey = rlMeta.get('relatedList') == null
        ? ''
        : String.valueOf(rlMeta.get('relatedList'));
      if (rlName.equalsIgnoreCase(name) || rlName.equalsIgnoreCase(relatedListKey)) {
        return rlMeta;
      }
    }
    return null;
  }

  @TestVisible
  private static List<Map<String, Object>> fetchRelatedListData(
    String parentObjectApi,
    Id parentId,
    Map<String, Object> layout,
    List<Map<String, Object>> tabs
  ) {
    List<Map<String, Object>> out = new List<Map<String, Object>>();
    if (tabs == null || tabs.isEmpty()) {
      return out;
    }

    Set<String> fetched = new Set<String>();
    for (Map<String, Object> tab : tabs) {
      String tabType = tab.get('type') == null ? '' : String.valueOf(tab.get('type'));
      if ('related'.equals(tabType)) {
        Map<String, Object> block = fetchRelatedListForTab(parentObjectApi, parentId, tab, fetched);
        if (block != null) {
          out.add(block);
        }
      } else if ('relatedMulti'.equals(tabType)) {
        List<Object> blocks = (List<Object>) tab.get('relatedBlocks');
        if (blocks != null) {
          for (Object blockObj : blocks) {
            Map<String, Object> blockDef = (Map<String, Object>) blockObj;
            Map<String, Object> pseudoTab = new Map<String, Object>{
              'id' => tab.get('id'),
              'relatedListName' => blockDef.get('relatedListName'),
              'relatedListLabel' => blockDef.get('relatedListLabel'),
              'relatedListMeta' => blockDef.get('relatedListMeta')
            };
            Map<String, Object> block = fetchRelatedListForTab(parentObjectApi, parentId, pseudoTab, fetched);
            if (block != null) {
              out.add(block);
            }
          }
        }
      }
    }
    return out;
  }

  private static Map<String, Object> fetchRelatedListForTab(
    String parentObjectApi,
    Id parentId,
    Map<String, Object> tab,
    Set<String> fetched
  ) {
    String rlName = tab.get('relatedListName') == null ? '' : String.valueOf(tab.get('relatedListName'));
    if (String.isBlank(rlName)) {
      return null;
    }

    Map<String, Object> rlMeta = (Map<String, Object>) tab.get('relatedListMeta');
    if (rlMeta == null) {
      rlMeta = new Map<String, Object>{
        'label' => tab.get('relatedListLabel'),
        'name' => rlName
      };
    }
    String rlLabel = tab.get('relatedListLabel') == null
      ? (rlMeta.get('label') == null ? rlName : String.valueOf(rlMeta.get('label')))
      : String.valueOf(tab.get('relatedListLabel'));

    String fetchKey = String.valueOf(tab.get('id')) + ':' + rlName + ':' + rlLabel;
    if (fetched.contains(fetchKey)) {
      return null;
    }
    fetched.add(fetchKey);

    Map<String, Object> block = fetchOneRelatedList(
      parentObjectApi,
      parentId,
      rlMeta,
      rlName,
      RELATED_LIST_PREVIEW_LIMIT
    );
    if (block == null) {
      block = new Map<String, Object>{
        'tabId' => tab.get('id'),
        'label' => rlLabel,
        'name' => rlName,
        'columns' => parseRelatedListColumns(rlMeta),
        'rows' => new List<Map<String, Object>>(),
        'totalSize' => 0
      };
    } else {
      block.put('tabId', tab.get('id'));
      if (block.get('label') == null) {
        block.put('label', rlLabel);
      }
    }
    return block;
  }

  @TestVisible
  private static Map<String, Object> fetchOneRelatedList(
    String parentObjectApi,
    Id parentId,
    Map<String, Object> rlMeta,
    String rlName,
    Integer rowLimit
  ) {
    if ('ParentAccountContacts'.equalsIgnoreCase(rlName) && 'Opportunity'.equals(parentObjectApi)) {
      return fetchParentAccountContacts(parentId, rlMeta, rowLimit);
    }

    ChildRelationshipInfo relInfo = resolveChildRelationship(parentObjectApi, rlName);
    if (relInfo == null) {
      return null;
    }

    Integer limitRows = resolveRelatedListRowLimit(rowLimit);
    List<Map<String, Object>> colDefs = parseRelatedListColumns(rlMeta);
    List<String> queryFields = buildRelatedListQueryFields(colDefs, relInfo.childObjectApi);
    if (queryFields.isEmpty()) {
      queryFields.add('Id');
    }

    String orderClause = 'Id DESC';
    Map<String, Schema.SObjectField> childFieldMap = Schema.getGlobalDescribe()
      .get(relInfo.childObjectApi)
      .getDescribe()
      .fields.getMap();
    if (childFieldMap.containsKey('CreatedDate')) {
      orderClause = 'CreatedDate DESC';
    }

    String soql =
      'SELECT ' +
      String.join(queryFields, ', ') +
      ' FROM ' +
      relInfo.childObjectApi +
      ' WHERE ' +
      relInfo.foreignKeyField +
      ' = :parentId ORDER BY ' +
      orderClause +
      ' LIMIT :limitRows';
    List<SObject> records = Database.queryWithBinds(
      soql,
      new Map<String, Object>{ 'parentId' => parentId, 'limitRows' => limitRows },
      AccessLevel.SYSTEM_MODE
    );

    Integer totalSize = countRelatedRecords(relInfo, parentId);
    List<Map<String, Object>> rows = buildRelatedRowsFromRecords(records, colDefs, relInfo.childObjectApi);

    return new Map<String, Object>{
      'label' => rlMeta.get('label') == null ? rlName : String.valueOf(rlMeta.get('label')),
      'name' => rlName,
      'relatedList' => rlMeta.get('relatedList'),
      'columns' => colDefs,
      'rows' => rows,
      'totalSize' => totalSize
    };
  }

  @TestVisible
  private static Map<String, Object> fetchParentAccountContacts(
    Id opportunityId,
    Map<String, Object> rlMeta,
    Integer rowLimit
  ) {
    Integer limitRows = resolveRelatedListRowLimit(rowLimit);
    List<Opportunity> opps = [
      SELECT AccountId
      FROM Opportunity
      WHERE Id = :opportunityId
      LIMIT 1
    ];
    if (opps.isEmpty() || opps[0].AccountId == null) {
      return new Map<String, Object>{
        'label' => 'Contacts for Parent Account',
        'name' => 'ParentAccountContacts',
        'relatedList' => 'ParentAccountContacts',
        'columns' => parseRelatedListColumns(rlMeta),
        'rows' => new List<Map<String, Object>>(),
        'totalSize' => 0
      };
    }
    Id accountId = opps[0].AccountId;
    List<Map<String, Object>> colDefs = parseRelatedListColumns(rlMeta);
    // Map CONTACT.* layout columns onto Contact fields
    for (Map<String, Object> col : colDefs) {
      String fieldApi = relatedListColumnFieldApi(col);
      if (String.isBlank(fieldApi)) {
        continue;
      }
      if (fieldApi.equalsIgnoreCase('PHONE')) {
        col.put('field', 'Phone');
        col.put('fieldApiName', 'Phone');
      } else if (fieldApi.equalsIgnoreCase('EMAIL')) {
        col.put('field', 'Email');
        col.put('fieldApiName', 'Email');
      } else if (fieldApi.equalsIgnoreCase('TITLE')) {
        col.put('field', 'Title');
        col.put('fieldApiName', 'Title');
      }
    }
    List<String> queryFields = buildRelatedListQueryFields(colDefs, 'Contact');
    if (!queryFields.contains('Name')) {
      queryFields.add('Name');
    }
    String soql =
      'SELECT ' +
      String.join(queryFields, ', ') +
      ' FROM Contact WHERE AccountId = :accountId ORDER BY CreatedDate DESC LIMIT :limitRows';
    List<SObject> records = Database.queryWithBinds(
      soql,
      new Map<String, Object>{ 'accountId' => accountId, 'limitRows' => limitRows },
      AccessLevel.SYSTEM_MODE
    );
      Integer totalSize = [
        SELECT COUNT()
        FROM Contact
        WHERE AccountId = :accountId
      ];
      return new Map<String, Object>{
        'label' => 'Contacts for Parent Account',
        'name' => 'ParentAccountContacts',
        'relatedList' => 'ParentAccountContacts',
        'columns' => colDefs,
        'rows' => buildRelatedRowsFromRecords(records, colDefs, 'Contact'),
        'totalSize' => totalSize
      };
    }

  private class ChildRelationshipInfo {
    public String childObjectApi;
    public String foreignKeyField;
  }

  @TestVisible
  private static Integer resolveRelatedListRowLimit(Integer rowLimit) {
    if (rowLimit == null || rowLimit <= 0) {
      return RELATED_LIST_PREVIEW_LIMIT;
    }
    return Math.min(rowLimit, RELATED_LIST_VIEW_ALL_LIMIT);
  }

  @TestVisible
  private static ChildRelationshipInfo resolveChildRelationship(
    String parentObjectApi,
    String relationshipName
  ) {
    if (String.isBlank(parentObjectApi) || String.isBlank(relationshipName)) {
      return null;
    }
    Schema.DescribeSObjectResult parentDesc = Schema.getGlobalDescribe()
      .get(parentObjectApi)
      .getDescribe();
    for (Schema.ChildRelationship cr : parentDesc.getChildRelationships()) {
      if (cr.getRelationshipName() == null) {
        continue;
      }
      if (!relationshipName.equalsIgnoreCase(cr.getRelationshipName())) {
        continue;
      }
      ChildRelationshipInfo info = new ChildRelationshipInfo();
      info.childObjectApi = cr.getChildSObject().getDescribe().getName();
      info.foreignKeyField = cr.getField().getDescribe().getName();
      return info;
    }
    return null;
  }

  @TestVisible
  private static List<String> buildRelatedListQueryFields(
    List<Map<String, Object>> colDefs,
    String childObjectApi
  ) {
    Set<String> requested = new Set<String>{ 'Id' };
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(childObjectApi)
      .getDescribe()
      .fields.getMap();
    if (fieldMap.containsKey('Name')) {
      requested.add('Name');
    } else if (fieldMap.containsKey('Subject')) {
      requested.add('Subject');
    }
    for (Map<String, Object> colDef : colDefs) {
      String fieldApi = relatedListColumnFieldApi(colDef);
      if (!String.isBlank(fieldApi)) {
        requested.add(fieldApi);
      }
    }
    return filterQueryableFields(childObjectApi, requested);
  }

  @TestVisible
  private static Integer countRelatedRecords(ChildRelationshipInfo relInfo, Id parentId) {
    if (relInfo == null) {
      return 0;
    }
    String countSoql =
      'SELECT COUNT() FROM ' +
      relInfo.childObjectApi +
      ' WHERE ' +
      relInfo.foreignKeyField +
      ' = :parentId';
    return Database.countQueryWithBinds(
      countSoql,
      new Map<String, Object>{ 'parentId' => parentId },
      AccessLevel.SYSTEM_MODE
    );
  }

  @TestVisible
  private static List<Map<String, Object>> buildRelatedRowsFromRecords(
    List<SObject> records,
    List<Map<String, Object>> colDefs,
    String childObjectApi
  ) {
    List<Map<String, Object>> rows = new List<Map<String, Object>>();
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(childObjectApi)
      .getDescribe()
      .fields.getMap();
    for (SObject rec : records) {
      String rowId = String.valueOf(rec.get('Id'));
      Map<String, Object> cells = new Map<String, Object>();
      for (Map<String, Object> colDef : colDefs) {
        String fieldApi = relatedListColumnFieldApi(colDef);
        Object val = readRelatedSObjectField(rec, fieldApi, fieldMap);
        cells.put(fieldApi, formatRelatedCellValue(val, fieldMap.get(fieldApi)));
      }
      rows.add(
        new Map<String, Object>{
          'id' => rowId,
          'name' => relatedRowDisplayName(rec, childObjectApi),
          'cells' => cells
        }
      );
    }
    return rows;
  }

  @TestVisible
  private static Object readRelatedSObjectField(
    SObject rec,
    String fieldApi,
    Map<String, Schema.SObjectField> fieldMap
  ) {
    if (rec == null || String.isBlank(fieldApi)) {
      return null;
    }
    if (fieldApi.contains('.')) {
      List<String> parts = fieldApi.split('\\.');
      SObject current = rec;
      for (Integer i = 0; i < parts.size() - 1; i++) {
        if (current == null) {
          return null;
        }
        current = current.getSObject(parts[i]);
      }
      return current == null ? null : current.get(parts[parts.size() - 1]);
    }
    if (fieldMap != null && fieldMap.containsKey(fieldApi)) {
      return rec.get(fieldApi);
    }
    Map<String, Object> populated = rec.getPopulatedFieldsAsMap();
    for (String key : populated.keySet()) {
      if (key.equalsIgnoreCase(fieldApi)) {
        return populated.get(key);
      }
    }
    return null;
  }

  @TestVisible
  private static String relatedListColumnFieldApi(Map<String, Object> colDef) {
    if (colDef == null) {
      return '';
    }
    if (colDef.get('fieldApiName') != null) {
      return String.valueOf(colDef.get('fieldApiName'));
    }
    if (colDef.get('field') != null) {
      return String.valueOf(colDef.get('field'));
    }
    return '';
  }

  @TestVisible
  private static String relatedRowDisplayName(SObject rec, String objectApi) {
    if (rec == null) {
      return '';
    }
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap();
    if (fieldMap.containsKey('Name')) {
      Object name = rec.get('Name');
      if (name != null) {
        return String.valueOf(name);
      }
    }
    if (fieldMap.containsKey('Subject')) {
      Object subject = rec.get('Subject');
      if (subject != null) {
        return String.valueOf(subject);
      }
    }
    return String.valueOf(rec.get('Id'));
  }

  @TestVisible
  private static List<Map<String, Object>> buildRelatedBlocksFromLayout(Map<String, Object> layout) {
    List<Map<String, Object>> blocks = new List<Map<String, Object>>();
    if (layout == null || !layout.containsKey('relatedLists')) {
      return blocks;
    }
    List<Object> rls = (List<Object>) layout.get('relatedLists');
    for (Object rlObj : rls) {
      Map<String, Object> rlMeta = (Map<String, Object>) rlObj;
      String relatedListKey = rlMeta.get('relatedList') == null
        ? ''
        : String.valueOf(rlMeta.get('relatedList'));
      if (SKIP_RELATED_LIST_KEYS.contains(relatedListKey)) {
        continue;
      }
      String rlName = rlMeta.get('name') == null ? '' : String.valueOf(rlMeta.get('name'));
      if (String.isBlank(rlName)) {
        continue;
      }
      String rlLabel = rlMeta.get('label') == null
        ? rlName
        : decodeHtmlEntities(String.valueOf(rlMeta.get('label')));
      blocks.add(
        new Map<String, Object>{
          'relatedListName' => rlName,
          'relatedListLabel' => rlLabel,
          'relatedListMeta' => rlMeta
        }
      );
      if (blocks.size() >= 8) {
        break;
      }
    }
    return blocks;
  }

  @TestVisible
  private static String resolveRelatedListApiFromProps(
    Map<String, Object> props,
    Map<String, Object> layout
  ) {
    if (props == null) {
      return '';
    }
    List<String> keys = new List<String>{ 'relatedListApiName', 'relatedListName', 'relatedList' };
    for (String key : keys) {
      if (props.get(key) != null && String.isNotBlank(String.valueOf(props.get(key)))) {
        return String.valueOf(props.get(key));
      }
    }
    return '';
  }

  @TestVisible
  private static String findRelatedListNameByLabel(Map<String, Object> layout, String label) {
    if (layout == null || String.isBlank(label) || !layout.containsKey('relatedLists')) {
      return '';
    }
    String normalized = label.trim().toLowerCase();
    List<Object> rls = (List<Object>) layout.get('relatedLists');
    for (Object rlObj : rls) {
      Map<String, Object> rlMeta = (Map<String, Object>) rlObj;
      String rlLabel = rlMeta.get('label') == null ? '' : String.valueOf(rlMeta.get('label'));
      if (rlLabel.trim().toLowerCase() == normalized) {
        return rlMeta.get('name') == null ? '' : String.valueOf(rlMeta.get('name'));
      }
    }
    return '';
  }

  @TestVisible
  private static String formatRelatedCellValue(Object val) {
    return formatRelatedCellValue(val, null);
  }

  @TestVisible
  private static String formatRelatedCellValue(Object val, Schema.SObjectField fieldToken) {
    if (val == null) {
      return '';
    }
    if (fieldToken != null) {
      Schema.DescribeFieldResult fd = fieldToken.getDescribe();
      if (fd.getType() == Schema.DisplayType.DATE && val instanceof Date) {
        return ((Date) val).format();
      }
      if (fd.getType() == Schema.DisplayType.DATETIME && val instanceof Datetime) {
        return ((Datetime) val).format('MMM d, yyyy h:mm a');
      }
      if (fd.getType() == Schema.DisplayType.BOOLEAN && val instanceof Boolean) {
        return ((Boolean) val) ? 'Yes' : 'No';
      }
    }
    if (val instanceof Date) {
      return ((Date) val).format();
    }
    if (val instanceof Datetime) {
      return ((Datetime) val).format('MMM d, yyyy h:mm a');
    }
    if (val instanceof Boolean) {
      return ((Boolean) val) ? 'Yes' : 'No';
    }
    if (val instanceof Decimal || val instanceof Integer || val instanceof Long || val instanceof Double) {
      return String.valueOf(val);
    }
    return String.valueOf(val);
  }

  @TestVisible
  private static List<Map<String, Object>> parseRelatedListColumns(Map<String, Object> rlMeta) {
    List<Map<String, Object>> cols = new List<Map<String, Object>>();
    List<Object> rawCols = rlMeta == null ? null : (List<Object>) rlMeta.get('columns');
    if (rawCols == null || rawCols.isEmpty()) {
      cols.add(buildRelatedColumnDef('Name', 'Name'));
      return cols;
    }
    Set<String> seen = new Set<String>();
    for (Object colObj : rawCols) {
      String fieldApi = '';
      String label = '';
      if (colObj instanceof Map<String, Object>) {
        Map<String, Object> colMap = (Map<String, Object>) colObj;
        if (colMap.get('fieldApiName') != null) {
          fieldApi = String.valueOf(colMap.get('fieldApiName'));
        } else if (colMap.get('name') != null) {
          fieldApi = relatedListColumnToFieldApi(String.valueOf(colMap.get('name')));
        }
        if (colMap.get('label') != null) {
          label = decodeHtmlEntities(String.valueOf(colMap.get('label')));
        }
      } else {
        String raw = String.valueOf(colObj);
        fieldApi = relatedListColumnToFieldApi(raw);
        label = relatedListColumnLabel(raw, fieldApi);
      }
      if (String.isBlank(fieldApi) || seen.contains(fieldApi)) {
        continue;
      }
      seen.add(fieldApi);
      if (String.isBlank(label)) {
        label = relatedListColumnLabel(fieldApi, fieldApi);
      }
      cols.add(buildRelatedColumnDef(fieldApi, label));
      if (cols.size() >= 8) {
        break;
      }
    }
    if (cols.isEmpty()) {
      cols.add(buildRelatedColumnDef('Name', 'Name'));
    }
    return cols;
  }

  private static Map<String, Object> buildRelatedColumnDef(String fieldApi, String label) {
    return new Map<String, Object>{
      'field' => fieldApi,
      'fieldApiName' => fieldApi,
      'label' => label
    };
  }

  @TestVisible
  private static String relatedListColumnToFieldApi(String raw) {
    if (String.isBlank(raw)) {
      return '';
    }
    String s = raw.trim();
    if (s.contains('.')) {
      s = s.substring(s.lastIndexOf('.') + 1);
    }
    if (s.equalsIgnoreCase('FULL_NAME') || s.equalsIgnoreCase('NAME')) {
      return 'Name';
    }
    if (s.equalsIgnoreCase('ContactName')) {
      return 'Contact.Name';
    }
    if (s.equalsIgnoreCase('ContactTitle')) {
      return 'Contact.Title';
    }
    if (s.equalsIgnoreCase('ContactPhone')) {
      return 'Contact.Phone';
    }
    if (s.equalsIgnoreCase('ContactEmail')) {
      return 'Contact.Email';
    }
    if (s.equalsIgnoreCase('IsPrimary')) {
      return 'IsPrimary';
    }
    if (s.equalsIgnoreCase('TYPE')) {
      return 'Type';
    }
    if (s.equalsIgnoreCase('CREATED_DATE')) {
      return 'CreatedDate';
    }
    if (s.equalsIgnoreCase('LAST_UPDATE')) {
      return 'LastModifiedDate';
    }
    if (s.equalsIgnoreCase('STATUS')) {
      return 'Status';
    }
    if (s.equalsIgnoreCase('COMPANY')) {
      return 'Company';
    }
    if (s.equalsIgnoreCase('TITLE')) {
      return 'Title';
    }
    if (s.equalsIgnoreCase('SUBJECT')) {
      return 'Subject';
    }
    if (s.endsWith('__c') || s.endsWith('Id') || s.equals('Name') || s.equals('Status')) {
      return s;
    }
    if (s.contains('_')) {
      return s;
    }
    return s;
  }

  @TestVisible
  private static String relatedListColumnLabel(String raw, String fieldApi) {
    if (raw.contains('.')) {
      String tail = raw.substring(raw.lastIndexOf('.') + 1);
      return tail.replace('_', ' ');
    }
    return fieldApi.replace('_', ' ');
  }

  @TestVisible
  private static Object readRelatedRecordField(Map<String, Object> rec, String fieldApi) {
    if (rec.containsKey(fieldApi)) {
      return rec.get(fieldApi);
    }
    for (String key : rec.keySet()) {
      if (key.equalsIgnoreCase(fieldApi)) {
        return rec.get(key);
      }
    }
    return null;
  }

  @TestVisible
  private static String relatedRowDisplayName(Map<String, Object> rec) {
    if (rec.get('Name') != null) {
      return String.valueOf(rec.get('Name'));
    }
    for (String key : rec.keySet()) {
      if (key.equalsIgnoreCase('Name') && rec.get(key) != null) {
        return String.valueOf(rec.get(key));
      }
    }
    return rec.get('Id') == null ? '' : String.valueOf(rec.get('Id'));
  }

  @TestVisible
  private static Id resolveRecordTypeId(Id rid, String objectApi, Schema.DescribeSObjectResult objDesc) {
    Map<String, Schema.SObjectField> fieldMap = objDesc.fields.getMap();
    if (fieldMap.containsKey('RecordTypeId')) {
      String rtSoql = 'SELECT RecordTypeId FROM ' + objectApi + ' WHERE Id = :rid LIMIT 1';
      List<SObject> rtRows = Database.queryWithBinds(
        rtSoql,
        new Map<String, Object>{ 'rid' => rid },
        AccessLevel.SYSTEM_MODE
      );
      if (!rtRows.isEmpty()) {
        Id rtId = (Id) rtRows[0].get('RecordTypeId');
        if (rtId != null) {
          return rtId;
        }
      }
    }
    for (Schema.RecordTypeInfo rti : objDesc.getRecordTypeInfos()) {
      if (rti.isDefaultRecordTypeMapping()) {
        return rti.getRecordTypeId();
      }
    }
    for (Schema.RecordTypeInfo rti : objDesc.getRecordTypeInfos()) {
      if (rti.isMaster()) {
        return rti.getRecordTypeId();
      }
    }
    return objDesc.getRecordTypeInfos()[0].getRecordTypeId();
  }

  @TestVisible
  private static Map<String, Object> resolveLayout(String objectApi, Id recordTypeId) {
    if (Test.isRunningTest() && testLayoutOverride != null) {
      return testLayoutOverride;
    }
    String path =
      '/services/data/' +
      REST_API_VERSION +
      '/sobjects/' +
      EncodingUtil.urlEncode(objectApi, 'UTF-8') +
      '/describe/layouts/' +
      EncodingUtil.urlEncode(String.valueOf(recordTypeId), 'UTF-8');
    for (String base : orgApiBaseUrls()) {
      Map<String, Object> body = httpGetJson(base + path);
      if (body != null && body.containsKey('detailLayoutSections')) {
        return body;
      }
    }
    return null;
  }

  private static List<String> orgApiBaseUrls() {
    List<String> urls = new List<String>();
    try {
      urls.add(URL.getOrgDomainUrl().toExternalForm());
    } catch (Exception e) {
      // ignore
    }
    return urls;
  }

  @TestVisible
  private static Map<String, Object> httpGetJson(String endpoint) {
    try {
      HttpRequest req = new HttpRequest();
      req.setEndpoint(endpoint);
      req.setMethod('GET');
      req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
      req.setHeader('Accept', 'application/json');
      req.setTimeout(120000);
      HttpResponse res = new Http().send(req);
      if (res.getStatusCode() != 200 || String.isBlank(res.getBody())) {
        return null;
      }
      return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    } catch (Exception e) {
      return null;
    }
  }

  @TestVisible
  private static Set<String> getAllObjectFieldApis(String objectApi) {
    Set<String> apis = new Set<String>();
    if (String.isBlank(objectApi)) {
      return apis;
    }
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap();
    for (Schema.SObjectField token : fieldMap.values()) {
      Schema.DescribeFieldResult fd = token.getDescribe();
      if (fd.isDeprecatedAndHidden()) {
        continue;
      }
      Schema.DisplayType dt = fd.getType();
      if (dt == Schema.DisplayType.BASE64) {
        continue;
      }
      String fieldName = fd.getName();
      if (dt == Schema.DisplayType.ADDRESS || dt == Schema.DisplayType.LOCATION) {
        apis.add(fieldName);
        for (String sub : resolveCompoundSubfieldApis(fieldName, dt, fieldMap)) {
          apis.add(sub);
        }
      } else {
        apis.add(fieldName);
      }
    }
    return apis;
  }

  @TestVisible
  private static Map<String, Object> buildLayoutSection(
    String heading,
    List<String> fieldApis,
    String objectApi
  ) {
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap();
    List<Object> rows = new List<Object>();
    List<Object> currentItems = new List<Object>();
    for (Integer i = 0; i < fieldApis.size(); i++) {
      String fieldApi = fieldApis[i];
      if (String.isBlank(fieldApi)) {
        continue;
      }
      String label = fieldApi;
      String type = 'string';
      Schema.SObjectField token = fieldMap.get(fieldApi);
      if (token != null) {
        Schema.DescribeFieldResult fd = token.getDescribe();
        label = decodeHtmlEntities(fd.getLabel());
        type = mapModalFieldType(fd.getType());
      }
      currentItems.add(
        new Map<String, Object>{
          'label' => label,
          'placeholder' => false,
          'layoutComponents' => new List<Object>{
            new Map<String, Object>{
              'type' => 'Field',
              'value' => fieldApi,
              'details' => new Map<String, Object>{
                'type' => type,
                'name' => fieldApi,
                'label' => label
              }
            }
          }
        }
      );
      if (currentItems.size() == 2 || i == fieldApis.size() - 1) {
        rows.add(new Map<String, Object>{ 'layoutItems' => new List<Object>(currentItems) });
        currentItems = new List<Object>();
      }
    }
    return new Map<String, Object>{
      'heading' => heading,
      'useHeading' => true,
      'layoutRows' => rows
    };
  }

  @TestVisible
  private static Map<String, Object> augmentLayoutWithAllFields(
    Map<String, Object> layout,
    Set<String> layoutFieldApis,
    Set<String> allFieldApis,
    String objectApi
  ) {
    List<String> missing = new List<String>();
    for (String fieldApi : allFieldApis) {
      if (String.isBlank(fieldApi) || fieldApi == 'Id' || layoutFieldApis.contains(fieldApi)) {
        continue;
      }
      missing.add(fieldApi);
    }
    if (missing.isEmpty()) {
      return layout;
    }
    missing.sort();
    List<Object> sections = layout.containsKey('detailLayoutSections')
      ? new List<Object>((List<Object>) layout.get('detailLayoutSections'))
      : new List<Object>();
    sections.add(buildLayoutSection('All Fields', missing, objectApi));
    Map<String, Object> augmented = new Map<String, Object>(layout);
    augmented.put('detailLayoutSections', sections);
    return augmented;
  }

  @TestVisible
  private static SObject queryRecordFieldsWithAllFields(
    Id recordId,
    String objectApi,
    List<String> fallbackFields
  ) {
    if (recordId == null || String.isBlank(objectApi)) {
      return null;
    }
    Integer fieldCount = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap()
      .size();
    if (fieldCount <= 200) {
      try {
        String soql =
          'SELECT FIELDS(ALL) FROM ' +
          String.escapeSingleQuotes(objectApi) +
          ' WHERE Id = :recordId LIMIT 1';
        List<SObject> rows = Database.queryWithBinds(
          soql,
          new Map<String, Object>{ 'recordId' => recordId },
          AccessLevel.SYSTEM_MODE
        );
        if (!rows.isEmpty()) {
          return rows[0];
        }
      } catch (Exception e) {
        // Fall through to explicit field list.
      }
    }
    List<String> capped = capQueryFields(fallbackFields, 200);
    return queryRecordFields(recordId, objectApi, capped);
  }

  @TestVisible
  private static List<String> capQueryFields(List<String> fields, Integer maxFields) {
    if (fields == null || fields.isEmpty()) {
      return new List<String>();
    }
    if (fields.size() <= maxFields) {
      return fields;
    }
    List<String> capped = new List<String>();
    Set<String> seen = new Set<String>();
    for (String f : fields) {
      if (String.isBlank(f) || seen.contains(f)) {
        continue;
      }
      if (f == 'Id' || f == 'Name' || capped.size() < maxFields) {
        capped.add(f);
        seen.add(f);
      }
      if (capped.size() >= maxFields) {
        break;
      }
    }
    return capped;
  }

  @TestVisible
  private static List<String> prioritizeFields(List<String> queryFields, Set<String> preferred) {
    if (queryFields == null || queryFields.isEmpty()) {
      return new List<String>();
    }
    if (preferred == null || preferred.isEmpty()) {
      return queryFields;
    }
    List<String> first = new List<String>();
    List<String> rest = new List<String>();
    Set<String> seen = new Set<String>();
    for (String f : queryFields) {
      if (String.isBlank(f) || seen.contains(f)) {
        continue;
      }
      seen.add(f);
      if (preferred.contains(f) || f == 'Id' || f == 'Name') {
        first.add(f);
      } else {
        rest.add(f);
      }
    }
    first.addAll(rest);
    return first;
  }

  @TestVisible
  private static Set<String> extractLayoutFieldApis(Map<String, Object> layout, String objectApi) {
    Set<String> fields = new Set<String>();
    if (layout == null || !layout.containsKey('detailLayoutSections')) {
      return fields;
    }
    Map<String, Schema.SObjectField> fieldMap = String.isBlank(objectApi)
      ? new Map<String, Schema.SObjectField>()
      : Schema.getGlobalDescribe().get(objectApi).getDescribe().fields.getMap();
    List<Object> sections = (List<Object>) layout.get('detailLayoutSections');
    for (Object secObj : sections) {
      Map<String, Object> section = (Map<String, Object>) secObj;
      List<Object> rows = (List<Object>) section.get('layoutRows');
      if (rows == null) {
        continue;
      }
      for (Object rowObj : rows) {
        Map<String, Object> row = (Map<String, Object>) rowObj;
        List<Object> items = (List<Object>) row.get('layoutItems');
        if (items == null) {
          continue;
        }
        for (Object itemObj : items) {
          Map<String, Object> item = (Map<String, Object>) itemObj;
          if (item.get('placeholder') == true) {
            continue;
          }
          List<Object> components = (List<Object>) item.get('layoutComponents');
          if (components == null) {
            continue;
          }
          for (Object compObj : components) {
            Map<String, Object> comp = (Map<String, Object>) compObj;
            if (!'Field'.equals(comp.get('type'))) {
              continue;
            }
            String fieldApi = (String) comp.get('value');
            if (String.isBlank(fieldApi)) {
              continue;
            }
            fields.add(fieldApi);
            addCompoundSubfields(fieldMap, fieldApi, fields);
            Map<String, Object> details = (Map<String, Object>) comp.get('details');
            Boolean isReference =
              details != null &&
              'reference'.equalsIgnoreCase(String.valueOf(details.get('type')));
            if (!isReference && fieldMap.containsKey(fieldApi)) {
              isReference =
                fieldMap.get(fieldApi).getDescribe().getType() == Schema.DisplayType.REFERENCE;
            }
            if (isReference) {
              String rel = details == null ? null : (String) details.get('relationshipName');
              if (String.isBlank(rel) && fieldMap.containsKey(fieldApi)) {
                rel = fieldMap.get(fieldApi).getDescribe().getRelationshipName();
              }
              if (!String.isBlank(rel)) {
                fields.add(rel + '.Name');
              }
            }
          }
        }
      }
    }
    return fields;
  }

  /**
   * @description Relationship.Name paths for every lookup/master-detail that has a Name field.
   */
  @TestVisible
  private static Set<String> referenceNamePaths(String objectApi) {
    Set<String> paths = new Set<String>();
    if (String.isBlank(objectApi) || !Schema.getGlobalDescribe().containsKey(objectApi)) {
      return paths;
    }
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap();
    for (Schema.SObjectField token : fieldMap.values()) {
      Schema.DescribeFieldResult fd = token.getDescribe();
      if (fd.getType() != Schema.DisplayType.REFERENCE) {
        continue;
      }
      String rel = fd.getRelationshipName();
      if (String.isBlank(rel)) {
        continue;
      }
      List<Schema.SObjectType> refs = fd.getReferenceTo();
      if (refs == null || refs.isEmpty()) {
        continue;
      }
      if (refs[0].getDescribe().fields.getMap().containsKey('Name')) {
        paths.add(rel + '.Name');
      }
    }
    return paths;
  }

  /**
   * @description Resolve a relationship name (Account, Position__r) to its lookup field token.
   */
  @TestVisible
  private static Schema.SObjectField resolveRelationshipField(
    Map<String, Schema.SObjectField> fieldMap,
    String relationshipName
  ) {
    if (fieldMap == null || fieldMap.isEmpty() || String.isBlank(relationshipName)) {
      return null;
    }
    Schema.SObjectField relField = fieldMap.get(relationshipName + 'Id');
    if (relField != null) {
      return relField;
    }
    relField = fieldMap.get(relationshipName);
    if (relField != null) {
      return relField;
    }
    // Custom lookups: Position__r → Position__c
    if (relationshipName.endsWith('__r')) {
      relField = fieldMap.get(relationshipName.substring(0, relationshipName.length() - 1) + 'c');
      if (relField != null) {
        return relField;
      }
    }
    for (Schema.SObjectField token : fieldMap.values()) {
      Schema.DescribeFieldResult fd = token.getDescribe();
      if (
        fd.getType() == Schema.DisplayType.REFERENCE &&
        relationshipName.equals(fd.getRelationshipName())
      ) {
        return token;
      }
    }
    return null;
  }

  @TestVisible
  private static void addCompoundSubfields(
    Map<String, Schema.SObjectField> fieldMap,
    String fieldApi,
    Set<String> fields
  ) {
    if (fieldMap == null || fieldMap.isEmpty() || String.isBlank(fieldApi) || !fieldMap.containsKey(fieldApi)) {
      return;
    }
    Schema.DescribeFieldResult fd = fieldMap.get(fieldApi).getDescribe();
    for (String sub : resolveCompoundSubfieldApis(fieldApi, fd.getType(), fieldMap)) {
      fields.add(sub);
    }
  }

  @TestVisible
  private static List<String> resolveCompoundSubfieldApis(
    String compoundApi,
    Schema.DisplayType dt,
    Map<String, Schema.SObjectField> fieldMap
  ) {
    List<String> subs = new List<String>();
    if (dt == Schema.DisplayType.ADDRESS) {
      String prefix = compoundApi.endsWith('Address')
        ? compoundApi.substring(0, compoundApi.length() - 'Address'.length())
        : '';
      addSubfieldIfPresent(subs, fieldMap, prefix + 'Street');
      addSubfieldIfPresent(subs, fieldMap, prefix + 'City');
      addSubfieldIfPresent(subs, fieldMap, prefix + 'State');
      addSubfieldIfPresent(subs, fieldMap, prefix + 'PostalCode');
      addSubfieldIfPresent(subs, fieldMap, prefix + 'Country');
    } else if (dt == Schema.DisplayType.LOCATION) {
      String prefix = compoundApi.endsWith('Location')
        ? compoundApi.substring(0, compoundApi.length() - 'Location'.length())
        : '';
      addSubfieldIfPresent(subs, fieldMap, prefix + 'Latitude');
      addSubfieldIfPresent(subs, fieldMap, prefix + 'Longitude');
    }
    return subs;
  }

  private static void addSubfieldIfPresent(
    List<String> subs,
    Map<String, Schema.SObjectField> fieldMap,
    String subApi
  ) {
    if (fieldMap.containsKey(subApi)) {
      subs.add(subApi);
    }
  }

  @TestVisible
  private static List<String> filterQueryableFields(String objectApi, Set<String> requested) {
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap();
    List<String> out = new List<String>();
    Set<String> seen = new Set<String>();
    for (String f : requested) {
      if (String.isBlank(f) || seen.contains(f)) {
        continue;
      }
      if (f.contains('.')) {
        String rel = f.substring(0, f.indexOf('.'));
        String child = f.substring(f.indexOf('.') + 1);
        Schema.SObjectField relField = resolveRelationshipField(fieldMap, rel);
        if (relField == null) {
          continue;
        }
        Schema.DescribeFieldResult relDesc = relField.getDescribe();
        List<Schema.SObjectType> refs = relDesc.getReferenceTo();
        if (refs == null || refs.isEmpty()) {
          continue;
        }
        Map<String, Schema.SObjectField> childMap = refs[0].getDescribe().fields.getMap();
        if (!childMap.containsKey(child)) {
          continue;
        }
        out.add(f);
        seen.add(f);
      } else if (fieldMap.containsKey(f)) {
        Schema.DescribeFieldResult fd = fieldMap.get(f).getDescribe();
        if (fd.getType() == Schema.DisplayType.ADDRESS || fd.getType() == Schema.DisplayType.LOCATION) {
          for (String sub : resolveCompoundSubfieldApis(f, fd.getType(), fieldMap)) {
            if (!seen.contains(sub)) {
              out.add(sub);
              seen.add(sub);
            }
          }
        } else {
          out.add(f);
          seen.add(f);
        }
      }
    }
    return out;
  }

  @TestVisible
  private static Map<String, Object> recordToValueMap(
    SObject rec,
    List<String> fields,
    String objectApi,
    Set<String> layoutFieldApis
  ) {
    Map<String, Object> values = new Map<String, Object>();
    Map<String, Object> populated = rec.getPopulatedFieldsAsMap();
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap();
    for (String f : fields) {
      if (f.contains('.')) {
        String rel = f.substring(0, f.indexOf('.'));
        String child = f.substring(f.indexOf('.') + 1);
        Object relObj = populated.get(rel);
        if (relObj instanceof SObject) {
          values.put(f, ((SObject) relObj).get(child));
        }
      } else {
        Object val = null;
        if (populated.containsKey(f)) {
          val = populated.get(f);
        } else {
          try {
            val = rec.get(f);
          } catch (Exception e) {
            val = null;
          }
        }
        values.put(f, formatFieldValueForModal(f, val, fieldMap));
      }
    }
    enrichCompoundFieldValues(rec, layoutFieldApis, values, fieldMap);
    return values;
  }

  @TestVisible
  private static void enrichCompoundFieldValues(
    SObject rec,
    Set<String> layoutFieldApis,
    Map<String, Object> values,
    Map<String, Schema.SObjectField> fieldMap
  ) {
    if (layoutFieldApis == null || layoutFieldApis.isEmpty()) {
      return;
    }
    for (String fieldApi : layoutFieldApis) {
      if (!fieldMap.containsKey(fieldApi)) {
        continue;
      }
      Schema.DescribeFieldResult fd = fieldMap.get(fieldApi).getDescribe();
      if (fd.getType() == Schema.DisplayType.ADDRESS) {
        values.put(fieldApi, formatAddressCompound(rec, fd));
      } else if (fd.getType() == Schema.DisplayType.LOCATION) {
        values.put(fieldApi, formatLocationCompound(rec, fd));
      }
    }
  }

  @TestVisible
  private static String formatAddressCompound(SObject rec, Schema.DescribeFieldResult fd) {
    List<String> parts = new List<String>();
    for (String sub : resolveCompoundSubfieldApis(fd.getName(), fd.getType(), rec.getSObjectType().getDescribe().fields.getMap())) {
      Object val = rec.get(sub);
      if (val != null && String.valueOf(val).trim().length() > 0) {
        parts.add(String.valueOf(val).trim());
      }
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  @TestVisible
  private static String formatLocationCompound(SObject rec, Schema.DescribeFieldResult fd) {
    List<String> parts = new List<String>();
    for (String sub : resolveCompoundSubfieldApis(fd.getName(), fd.getType(), rec.getSObjectType().getDescribe().fields.getMap())) {
      Object val = rec.get(sub);
      if (val != null) {
        parts.add(String.valueOf(val));
      }
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  @TestVisible
  private static Object formatFieldValueForModal(
    String fieldApi,
    Object val,
    Map<String, Schema.SObjectField> fieldMap
  ) {
    if (val == null) {
      return null;
    }
    Schema.SObjectField token = fieldMap.get(fieldApi);
    if (token == null) {
      return val;
    }
    Schema.DescribeFieldResult fd = token.getDescribe();
    Schema.DisplayType dt = fd.getType();
    if (dt == Schema.DisplayType.DATE && val instanceof Date) {
      return ((Date) val).format();
    }
    if (dt == Schema.DisplayType.DATETIME && val instanceof Datetime) {
      return ((Datetime) val).format('MMM d, yyyy h:mm a');
    }
    if (
      dt == Schema.DisplayType.CURRENCY ||
      dt == Schema.DisplayType.DOUBLE ||
      dt == Schema.DisplayType.PERCENT ||
      dt == Schema.DisplayType.INTEGER
    ) {
      return val;
    }
    return val;
  }

  @TestVisible
  private static Map<String, Object> buildFieldMeta(String objectApi, List<String> fields) {
    Map<String, Object> meta = new Map<String, Object>();
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap();
    for (String f : fields) {
      if (String.isBlank(f) || f.contains('.')) {
        continue;
      }
      Schema.SObjectField token = fieldMap.get(f);
      if (token == null) {
        continue;
      }
      Schema.DescribeFieldResult fd = token.getDescribe();
      Boolean htmlFormatted = fd.isHtmlFormatted();
      Boolean htmlCapable =
        htmlFormatted ||
        fd.getType() == Schema.DisplayType.TEXTAREA ||
        (fd.isCalculated() && fd.getType() == Schema.DisplayType.STRING);
      Boolean updateable = isFieldEditable(fd);
      Map<String, Object> fieldMeta = new Map<String, Object>{
        'type' => mapModalFieldType(fd.getType()),
        'label' => decodeHtmlEntities(fd.getLabel()),
        'htmlCapable' => htmlCapable,
        'htmlFormatted' => htmlFormatted,
        'calculated' => fd.isCalculated(),
        'scale' => fd.getScale(),
        'precision' => fd.getPrecision(),
        'length' => fd.getLength(),
        'updateable' => updateable,
        'readOnly' => !updateable,
        'required' => !fd.isNillable() && !fd.isDefaultedOnCreate()
      };
      if (htmlFormatted) {
        fieldMeta.put('extraTypeInfo', 'richtext');
      }
      if (
        updateable &&
        (fd.getType() == Schema.DisplayType.PICKLIST ||
        fd.getType() == Schema.DisplayType.MULTIPICKLIST)
      ) {
        fieldMeta.put('picklistValues', picklistValuesFromDescribe(fd));
      }
      if (fd.getType() == Schema.DisplayType.ADDRESS || fd.getType() == Schema.DisplayType.LOCATION) {
        fieldMeta.put('compound', true);
        fieldMeta.put(
          'compoundFields',
          resolveCompoundSubfieldApis(f, fd.getType(), fieldMap)
        );
      }
      if (fd.getType() == Schema.DisplayType.REFERENCE) {
        fieldMeta.put('relationshipName', fd.getRelationshipName());
        List<String> referenceTo = new List<String>();
        for (Schema.SObjectType refType : fd.getReferenceTo()) {
          referenceTo.add(refType.getDescribe().getName());
        }
        fieldMeta.put('referenceTo', referenceTo);
      }
      meta.put(f, fieldMeta);
    }
    return meta;
  }

  @TestVisible
  private static String mapModalFieldType(Schema.DisplayType dt) {
    if (dt == Schema.DisplayType.BOOLEAN) {
      return 'boolean';
    }
    if (dt == Schema.DisplayType.CURRENCY) {
      return 'currency';
    }
    if (dt == Schema.DisplayType.DOUBLE || dt == Schema.DisplayType.INTEGER || dt == Schema.DisplayType.LONG) {
      return 'double';
    }
    if (dt == Schema.DisplayType.PERCENT) {
      return 'percent';
    }
    if (dt == Schema.DisplayType.DATE) {
      return 'date';
    }
    if (dt == Schema.DisplayType.DATETIME) {
      return 'datetime';
    }
    if (dt == Schema.DisplayType.EMAIL) {
      return 'email';
    }
    if (dt == Schema.DisplayType.PHONE) {
      return 'phone';
    }
    if (dt == Schema.DisplayType.URL) {
      return 'url';
    }
    if (dt == Schema.DisplayType.REFERENCE || dt == Schema.DisplayType.ID) {
      return 'reference';
    }
    if (dt == Schema.DisplayType.PICKLIST) {
      return 'picklist';
    }
    if (dt == Schema.DisplayType.MULTIPICKLIST) {
      return 'multipicklist';
    }
    if (dt == Schema.DisplayType.TEXTAREA) {
      return 'textarea';
    }
    if (dt == Schema.DisplayType.ADDRESS) {
      return 'address';
    }
    if (dt == Schema.DisplayType.LOCATION) {
      return 'location';
    }
    return 'string';
  }

  /**
   * @description Path bar payload: ordered steps, current value, guidance (read-only).
   */
  @TestVisible
  private static Map<String, Object> resolvePathData(
    String objectApi,
    Id recordTypeId,
    SObject rec,
    Map<String, Object> pathAssistantConfig,
    String pathFieldApi
  ) {
    if (Test.isRunningTest() && testPathOverride != null) {
      return testPathOverride;
    }
    if (pathAssistantConfig == null || String.isBlank(pathFieldApi) || rec == null) {
      return null;
    }
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap();
    if (!fieldMap.containsKey(pathFieldApi)) {
      return null;
    }
    Schema.DescribeFieldResult fieldDesc = fieldMap.get(pathFieldApi).getDescribe();
    if (
      fieldDesc.getType() != Schema.DisplayType.PICKLIST &&
      fieldDesc.getType() != Schema.DisplayType.MULTIPICKLIST
    ) {
      return null;
    }

    Object rawCurrent = rec.get(pathFieldApi);
    String currentValue = rawCurrent == null ? '' : String.valueOf(rawCurrent);
    Map<String, String> guidanceByValue = parsePathGuidanceByValue(pathAssistantConfig);
    List<String> orderedValues = resolveOrderedPicklistValues(objectApi, recordTypeId, pathFieldApi);
    if (orderedValues.isEmpty()) {
      orderedValues = picklistValuesFromDescribe(fieldDesc);
    }
    orderedValues = filterPathStepValues(orderedValues, guidanceByValue.keySet(), pathAssistantConfig);
    if (orderedValues.isEmpty()) {
      return null;
    }

    List<Map<String, Object>> steps = buildPathSteps(orderedValues, currentValue, guidanceByValue, fieldDesc);
    Map<String, Object> path = new Map<String, Object>{
      'fieldApiName' => pathFieldApi,
      'fieldLabel' => fieldDesc.getLabel(),
      'currentValue' => currentValue,
      'steps' => steps,
      'pathLabel' => pathAssistantConfig.get('masterLabel')
    };
    String guidanceText = guidanceByValue.get(currentValue);
    if (!String.isBlank(guidanceText)) {
      path.put('guidanceText', guidanceText);
    }
    return path;
  }

  @TestVisible
  private static Map<String, Object> fetchPathAssistantConfig(String objectApi, Id recordTypeId) {
    if (String.isBlank(objectApi) || recordTypeId == null) {
      return null;
    }
    Map<String, Object> config = queryPathAssistant(objectApi, recordTypeId);
    if (config != null) {
      return config;
    }
    return queryPathAssistantMaster(objectApi);
  }

  @TestVisible
  private static Map<String, Object> queryPathAssistant(String objectApi, Id recordTypeId) {
    String soql =
      'SELECT MasterLabel, SobjectProcessField, Metadata FROM PathAssistant WHERE SobjectType = \'' +
      String.escapeSingleQuotes(objectApi) +
      '\' AND RecordTypeId = \'' +
      String.escapeSingleQuotes(String.valueOf(recordTypeId)) +
      '\' AND IsActive = true LIMIT 1';
    return parsePathAssistantQueryResult(soql);
  }

  @TestVisible
  private static Map<String, Object> queryPathAssistantMaster(String objectApi) {
    String soql =
      'SELECT MasterLabel, SobjectProcessField, Metadata FROM PathAssistant WHERE SobjectType = \'' +
      String.escapeSingleQuotes(objectApi) +
      '\' AND IsMasterRecordType = true AND IsActive = true LIMIT 1';
    return parsePathAssistantQueryResult(soql);
  }

  @TestVisible
  private static Map<String, Object> parsePathAssistantQueryResult(String soql) {
    String path =
      '/services/data/' +
      REST_API_VERSION +
      '/tooling/query?q=' +
      EncodingUtil.urlEncode(soql, 'UTF-8');
    Map<String, Object> body = null;
    for (String base : orgApiBaseUrls()) {
      body = httpGetJson(base + path);
      if (body != null && body.containsKey('records')) {
        break;
      }
    }
    if (body == null) {
      return null;
    }
    List<Object> records = (List<Object>) body.get('records');
    if (records == null || records.isEmpty()) {
      return null;
    }
    Map<String, Object> row = (Map<String, Object>) records[0];
    Map<String, Object> out = new Map<String, Object>();
    if (row.get('MasterLabel') != null) {
      out.put('masterLabel', String.valueOf(row.get('MasterLabel')));
    }
    if (row.get('SobjectProcessField') != null) {
      out.put('sobjectProcessField', String.valueOf(row.get('SobjectProcessField')));
    }
    if (row.get('Metadata') != null) {
      out.put('metadata', row.get('Metadata'));
    }
    return out.isEmpty() ? null : out;
  }

  /**
   * @description Ordered path-assistant picklist values for a field (empty when no path / field mismatch).
   *              Used by CRM Hub Kanban to show lanes in path/picklist order.
   */
  public static List<String> pathOrderedPicklistValues(String objectApi, String fieldApi) {
    List<String> out = new List<String>();
    if (String.isBlank(objectApi) || String.isBlank(fieldApi)) {
      return out;
    }
    String cacheKey = objectApi + ':' + fieldApi;
    if (pathOrderedValuesCache.containsKey(cacheKey)) {
      return pathOrderedValuesCache.get(cacheKey);
    }
    try {
      Map<String, Object> config;
      if (pathMasterConfigCache.containsKey(objectApi)) {
        config = pathMasterConfigCache.get(objectApi);
      } else {
        config = queryPathAssistantMaster(objectApi);
        pathMasterConfigCache.put(objectApi, config);
      }
      if (config == null) {
        pathOrderedValuesCache.put(cacheKey, out);
        return out;
      }
      String pathField = resolvePathFieldApi(config, objectApi);
      if (String.isBlank(pathField) || !pathField.equalsIgnoreCase(fieldApi)) {
        pathOrderedValuesCache.put(cacheKey, out);
        return out;
      }
      Object metadataObj = config.get('metadata');
      if (!(metadataObj instanceof Map<String, Object>)) {
        pathOrderedValuesCache.put(cacheKey, out);
        return out;
      }
      List<Object> steps = (List<Object>) ((Map<String, Object>) metadataObj).get('pathAssistantSteps');
      if (steps == null || steps.isEmpty()) {
        pathOrderedValuesCache.put(cacheKey, out);
        return out;
      }
      Set<String> seen = new Set<String>();
      for (Object stepObj : steps) {
        Map<String, Object> step = (Map<String, Object>) stepObj;
        String valueName = step.get('picklistValueName') == null
          ? ''
          : String.valueOf(step.get('picklistValueName'));
        if (!String.isBlank(valueName) && !seen.contains(valueName)) {
          out.add(valueName);
          seen.add(valueName);
        }
      }
    } catch (Exception e) {
      out = new List<String>();
    }
    pathOrderedValuesCache.put(cacheKey, out);
    return out;
  }

  @TestVisible
  private static String resolvePathFieldApi(Map<String, Object> pathAssistantConfig, String objectApi) {
    if (pathAssistantConfig == null) {
      return null;
    }
    Object metadataObj = pathAssistantConfig.get('metadata');
    if (metadataObj instanceof Map<String, Object>) {
      Map<String, Object> metadata = (Map<String, Object>) metadataObj;
      if (metadata.get('fieldName') != null) {
        return String.valueOf(metadata.get('fieldName'));
      }
    }
    String processField = pathAssistantConfig.get('sobjectProcessField') == null
      ? ''
      : String.valueOf(pathAssistantConfig.get('sobjectProcessField'));
    if (PROCESS_FIELD_TO_API.containsKey(processField)) {
      return PROCESS_FIELD_TO_API.get(processField);
    }
    if (!String.isBlank(processField) && fieldExistsOnObject(objectApi, processField)) {
      return processField;
    }
    return defaultPathFieldForObject(objectApi);
  }

  @TestVisible
  private static String defaultPathFieldForObject(String objectApi) {
    if ('Opportunity'.equals(objectApi)) {
      return 'StageName';
    }
    if ('Lead'.equals(objectApi) || 'Case'.equals(objectApi)) {
      return 'Status';
    }
    if ('Job_Application__c'.equals(objectApi) || 'Position__c'.equals(objectApi)) {
      return 'Status__c';
    }
    return null;
  }

  @TestVisible
  private static Boolean fieldExistsOnObject(String objectApi, String fieldApi) {
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap();
    return fieldMap.containsKey(fieldApi);
  }

  @TestVisible
  private static Map<String, String> parsePathGuidanceByValue(Map<String, Object> pathAssistantConfig) {
    Map<String, String> guidance = new Map<String, String>();
    Object metadataObj = pathAssistantConfig.get('metadata');
    if (!(metadataObj instanceof Map<String, Object>)) {
      return guidance;
    }
    Map<String, Object> metadata = (Map<String, Object>) metadataObj;
    List<Object> steps = (List<Object>) metadata.get('pathAssistantSteps');
    if (steps == null) {
      return guidance;
    }
    for (Object stepObj : steps) {
      Map<String, Object> step = (Map<String, Object>) stepObj;
      String valueName = step.get('picklistValueName') == null
        ? ''
        : String.valueOf(step.get('picklistValueName'));
      if (String.isBlank(valueName)) {
        continue;
      }
      Object info = step.get('info');
      if (info != null && String.valueOf(info).trim().length() > 0) {
        guidance.put(valueName, String.valueOf(info));
      } else {
        guidance.put(valueName, '');
      }
    }
    return guidance;
  }

  @TestVisible
  private static List<String> resolveOrderedPicklistValues(
    String objectApi,
    Id recordTypeId,
    String fieldApi
  ) {
    List<String> fromBusinessProcess = businessProcessPicklistValues(recordTypeId);
    if (!fromBusinessProcess.isEmpty()) {
      return fromBusinessProcess;
    }
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap();
    if (!fieldMap.containsKey(fieldApi)) {
      return new List<String>();
    }
    return picklistValuesFromDescribe(fieldMap.get(fieldApi).getDescribe());
  }

  @TestVisible
  private static List<String> businessProcessPicklistValues(Id recordTypeId) {
    List<String> values = new List<String>();
    if (recordTypeId == null) {
      return values;
    }
    List<RecordType> rts = [
      SELECT BusinessProcessId
      FROM RecordType
      WHERE Id = :recordTypeId
      LIMIT 1
    ];
    if (rts.isEmpty() || rts[0].BusinessProcessId == null) {
      return values;
    }
    String bpId = String.valueOf(rts[0].BusinessProcessId);
    String soql =
      'SELECT Metadata FROM BusinessProcess WHERE Id = \'' + String.escapeSingleQuotes(bpId) + '\' LIMIT 1';
    String path =
      '/services/data/' +
      REST_API_VERSION +
      '/tooling/query?q=' +
      EncodingUtil.urlEncode(soql, 'UTF-8');
    Map<String, Object> body = null;
    for (String base : orgApiBaseUrls()) {
      body = httpGetJson(base + path);
      if (body != null && body.containsKey('records')) {
        break;
      }
    }
    if (body == null) {
      return values;
    }
    List<Object> records = (List<Object>) body.get('records');
    if (records == null || records.isEmpty()) {
      return values;
    }
    Map<String, Object> row = (Map<String, Object>) records[0];
    Object metadataObj = row.get('Metadata');
    if (!(metadataObj instanceof Map<String, Object>)) {
      return values;
    }
    List<Object> bpValues = (List<Object>) ((Map<String, Object>) metadataObj).get('values');
    if (bpValues == null) {
      return values;
    }
    for (Object valObj : bpValues) {
      Map<String, Object> val = (Map<String, Object>) valObj;
      String apiName = val.get('fullName') == null ? '' : String.valueOf(val.get('fullName'));
      if (!String.isBlank(apiName)) {
        values.add(apiName);
      }
    }
    return values;
  }

  @TestVisible
  private static List<String> picklistValuesFromDescribe(Schema.DescribeFieldResult fieldDesc) {
    List<String> values = new List<String>();
    for (Schema.PicklistEntry pe : fieldDesc.getPicklistValues()) {
      if (pe.isActive()) {
        values.add(pe.getValue());
      }
    }
    return values;
  }

  @TestVisible
  private static List<String> filterPathStepValues(
    List<String> orderedValues,
    Set<String> configuredValues,
    Map<String, Object> pathAssistantConfig
  ) {
    if (orderedValues == null || orderedValues.isEmpty()) {
      return new List<String>();
    }
    if (configuredValues == null || configuredValues.isEmpty()) {
      return orderedValues;
    }
    List<String> filtered = new List<String>();
    Set<String> seen = new Set<String>();
    for (String val : orderedValues) {
      if (configuredValues.contains(val) && !seen.contains(val)) {
        filtered.add(val);
        seen.add(val);
      }
    }
    for (String configured : configuredValues) {
      if (!seen.contains(configured)) {
        filtered.add(configured);
        seen.add(configured);
      }
    }
    return filtered.isEmpty() ? orderedValues : filtered;
  }

  @TestVisible
  private static List<Map<String, Object>> buildPathSteps(
    List<String> orderedValues,
    String currentValue,
    Map<String, String> guidanceByValue,
    Schema.DescribeFieldResult fieldDesc
  ) {
    List<Map<String, Object>> steps = new List<Map<String, Object>>();
    Map<String, String> labelByValue = picklistLabelMap(fieldDesc);
    Integer currentIndex = -1;
    for (Integer i = 0; i < orderedValues.size(); i++) {
      if (orderedValues[i] == currentValue) {
        currentIndex = i;
        break;
      }
    }
    for (Integer i = 0; i < orderedValues.size(); i++) {
      String value = orderedValues[i];
      String status = 'upcoming';
      if (currentIndex >= 0) {
        if (i < currentIndex) {
          status = 'complete';
        } else if (i == currentIndex) {
          status = 'current';
        }
      } else if (value == currentValue) {
        status = 'current';
      }
      Map<String, Object> step = new Map<String, Object>{
        'value' => value,
        'label' => labelByValue.containsKey(value) ? labelByValue.get(value) : value,
        'status' => status
      };
      if (guidanceByValue != null && guidanceByValue.containsKey(value)) {
        String g = guidanceByValue.get(value);
        if (!String.isBlank(g)) {
          step.put('guidanceText', g);
        }
      }
      steps.add(step);
    }
    return steps;
  }

  @TestVisible
  private static Map<String, String> picklistLabelMap(Schema.DescribeFieldResult fieldDesc) {
    Map<String, String> labels = new Map<String, String>();
    for (Schema.PicklistEntry pe : fieldDesc.getPicklistValues()) {
      labels.put(pe.getValue(), pe.getLabel());
    }
    return labels;
  }

  @TestVisible
  private static Boolean isFieldEditable(Schema.DescribeFieldResult fd) {
    if (fd == null) {
      return false;
    }
    if (fd.isCalculated() || fd.isAutoNumber()) {
      return false;
    }
    if (
      fd.getType() == Schema.DisplayType.ID ||
      fd.getType() == Schema.DisplayType.ADDRESS ||
      fd.getType() == Schema.DisplayType.LOCATION
    ) {
      return false;
    }
    if (fd.getType() == Schema.DisplayType.REFERENCE) {
      return fd.isUpdateable();
    }
    return true;
  }

  @TestVisible
  private static Object coerceFieldValue(Schema.DescribeFieldResult fd, Object raw) {
    if (raw == null || (raw instanceof String && String.isBlank((String) raw))) {
      return null;
    }
    Schema.DisplayType dt = fd.getType();
    if (dt == Schema.DisplayType.BOOLEAN) {
      if (raw instanceof Boolean) {
        return raw;
      }
      String s = String.valueOf(raw).trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes' || s == 'on') {
        return true;
      }
      if (s == 'false' || s == '0' || s == 'no' || s == 'off') {
        return false;
      }
      return Boolean.valueOf(s);
    }
    if (dt == Schema.DisplayType.DATE) {
      if (raw instanceof Date) {
        return raw;
      }
      return Date.valueOf(String.valueOf(raw).trim());
    }
    if (dt == Schema.DisplayType.DATETIME) {
      if (raw instanceof Datetime) {
        return raw;
      }
      String s = String.valueOf(raw).trim();
      if (s.contains('T')) {
        s = s.replace('T', ' ');
        if (s.length() == 16) {
          s += ':00';
        }
      }
      return Datetime.valueOf(s);
    }
    if (
      dt == Schema.DisplayType.CURRENCY ||
      dt == Schema.DisplayType.DOUBLE ||
      dt == Schema.DisplayType.PERCENT
    ) {
      if (raw instanceof Decimal) {
        return raw;
      }
      return Decimal.valueOf(String.valueOf(raw).trim());
    }
    if (dt == Schema.DisplayType.INTEGER || dt == Schema.DisplayType.LONG) {
      if (raw instanceof Integer) {
        return raw;
      }
      return Integer.valueOf(String.valueOf(raw).trim());
    }
    if (dt == Schema.DisplayType.PICKLIST) {
      String val = String.valueOf(raw).trim();
      for (Schema.PicklistEntry pe : fd.getPicklistValues()) {
        if (pe.isActive() && pe.getValue() == val) {
          return val;
        }
      }
      throw new IllegalArgumentException('Invalid picklist value: ' + val);
    }
    if (dt == Schema.DisplayType.MULTIPICKLIST) {
      return coerceMultipicklistValue(fd, raw);
    }
    if (dt == Schema.DisplayType.REFERENCE || dt == Schema.DisplayType.ID) {
      return Id.valueOf(String.valueOf(raw).trim());
    }
    return String.valueOf(raw);
  }

  @TestVisible
  private static String coerceMultipicklistValue(Schema.DescribeFieldResult fd, Object raw) {
    List<String> parts = new List<String>();
    if (raw instanceof List<Object>) {
      for (Object item : (List<Object>) raw) {
        if (item != null && !String.isBlank(String.valueOf(item))) {
          parts.add(String.valueOf(item).trim());
        }
      }
    } else {
      for (String part : String.valueOf(raw).split(';')) {
        if (!String.isBlank(part)) {
          parts.add(part.trim());
        }
      }
    }
    if (parts.isEmpty()) {
      return null;
    }
    Set<String> valid = new Set<String>();
    for (Schema.PicklistEntry pe : fd.getPicklistValues()) {
      if (pe.isActive()) {
        valid.add(pe.getValue());
      }
    }
    List<String> out = new List<String>();
    for (String val : parts) {
      if (!valid.contains(val)) {
        throw new IllegalArgumentException('Invalid multipicklist value: ' + val);
      }
      if (!out.contains(val)) {
        out.add(val);
      }
    }
    return String.join(out, ';');
  }

  @TestVisible
  private static String recordDisplayName(SObject rec, String objectApi) {
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap();
    if (fieldMap.containsKey('Name')) {
      Object name = rec.get('Name');
      if (name != null) {
        return decodeHtmlEntities(String.valueOf(name));
      }
    }
    return String.valueOf(rec.get('Id'));
  }
}