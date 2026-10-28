/**
 * REST facade for the Accounts tab New Account wizard.
 * Isolated from PlannerMobileRestService so it can deploy without that class's
 * broader dependency graph. The offline PWA calls these routes so master-list
 * search, map intelligence, and create match Lightning LWC behavior.
 */
@RestResource(urlMapping='/accounts-tab/v1/*')
global with sharing class AccountsTabWizardRestService {
  global class ErrorResponse {
    public String message;
    public ErrorResponse(String message) {
      this.message = message;
    }
  }

  @HttpGet
  global static void doGet() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json');
    try {
      String path = restPath(req);
      if (path == 'createable-record-types') {
        writeJson(res, 200, AccountsTabController.getCreateableAccountRecordTypes());
        return;
      }
      if (path == 'wizard-options') {
        writeJson(res, 200, AccountsTabController.getWizardCreateOptions());
        return;
      }
      if (path == 'approval-manager') {
        writeJson(res, 200, AccountsTabController.isAccountApprovalManager());
        return;
      }
      if (path == 'pending-approvals') {
        writeJson(res, 200, AccountsTabController.getPendingAccountApprovals());
        return;
      }
      if (path == 'nurture-summary') {
        writeJson(res, 200, AccountsTabController.getAccountNurtureSummary());
        return;
      }
      if (path == 'duplicate-check') {
        Map<String, String> params = req.params == null ? new Map<String, String>() : req.params;
        writeJson(
          res,
          200,
          AccountDuplicateCheckService.findAccountDuplicates(blankToNullId(params.get('accountId')))
        );
        return;
      }
      if (path == 'export') {
        Map<String, String> params = req.params == null ? new Map<String, String>() : req.params;
        writeJson(
          res,
          200,
          AccountsTabController.exportAccountsCsv(
            params.get('scope'),
            params.get('searchTerm'),
            params.get('recordTypeDeveloperName'),
            params.get('classification'),
            params.get('sortBy'),
            params.get('sortDirection'),
            null,
            blankToNullId(params.get('contextUserId')),
            blankToNullId(params.get('brickId')),
            params.get('specialtyFilter')
          )
        );
        return;
      }
      if (path == 'export-chunk') {
        Map<String, String> params = req.params == null ? new Map<String, String>() : req.params;
        writeJson(
          res,
          200,
          AccountsTabController.exportAccountsCsvChunk(
            params.get('scope'),
            params.get('searchTerm'),
            params.get('recordTypeDeveloperName'),
            params.get('classification'),
            blankToNullId(params.get('contextUserId')),
            blankToNullId(params.get('brickId')),
            params.get('specialtyFilter'),
            'true'.equalsIgnoreCase(params.get('fullBook')),
            params.get('afterId')
          )
        );
        return;
      }
      writeJson(res, 404, new ErrorResponse('Unknown GET path: ' + path));
    } catch (Exception e) {
      writeJson(res, 400, new ErrorResponse(e.getMessage()));
    }
  }

  @HttpPost
  global static void doPost() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json');
    try {
      String path = restPath(req);
      String body = req.requestBody == null ? '{}' : req.requestBody.toString();
      if (path == 'master-search') {
        writeJson(res, 200, searchMasterList(body));
        return;
      }
      if (path == 'map-places') {
        writeJson(res, 200, searchMapPlaces(body));
        return;
      }
      if (path == 'vezeeta-search') {
        Map<String, Object> payload = parseJsonMap(body);
        writeJson(res, 200, VezeetaDoctorService.searchVezeetaDoctors(stringFrom(payload.get('searchTerm'))));
        return;
      }
      if (path == 'vezeeta-profile') {
        Map<String, Object> payload = parseJsonMap(body);
        writeJson(res, 200, VezeetaDoctorService.getVezeetaDoctor(stringFrom(payload.get('profileUrl'))));
        return;
      }
      if (path == 'vezeeta-profile-url') {
        Map<String, Object> payload = parseJsonMap(body);
        VezeetaDoctorService.saveVezeetaProfileUrl(
          blankToNullId(stringFrom(payload.get('accountId'))),
          stringFrom(payload.get('profileUrl'))
        );
        writeJson(res, 200, new Map<String, Object>{ 'ok' => true });
        return;
      }
      if (path == 'create') {
        writeJson(res, 200, AccountsTabController.createAccountFromWizard(parseWizardCreateInput(body)));
        return;
      }
      if (path == 'resolve-bricks') {
        Map<String, Object> payload = parseJsonMap(body);
        writeJson(
          res,
          200,
          resolveBricksFromPin(toDecimal(payload.get('latitude')), toDecimal(payload.get('longitude')))
        );
        return;
      }
      if (path == 'set-kol') {
        Map<String, Object> payload = parseJsonMap(body);
        writeJson(
          res,
          200,
          AccountsTabController.setAccountKol(
            blankToNullId(stringFrom(payload.get('accountId'))),
            toBoolean(payload.get('isKol'), false)
          )
        );
        return;
      }
      if (path == 'approve-account') {
        Map<String, Object> payload = parseJsonMap(body);
        AccountsTabController.approveAccountSubmission(blankToNullId(stringFrom(payload.get('accountId'))));
        writeJson(res, 200, new Map<String, Object>{ 'ok' => true });
        return;
      }
      if (path == 'reject-account') {
        Map<String, Object> payload = parseJsonMap(body);
        AccountsTabController.rejectAccountSubmission(
          blankToNullId(stringFrom(payload.get('accountId'))),
          stringFrom(payload.get('rejectionReason'))
        );
        writeJson(res, 200, new Map<String, Object>{ 'ok' => true });
        return;
      }
      if (path == 'report-duplicate') {
        Map<String, Object> payload = parseJsonMap(body);
        writeJson(
          res,
          200,
          AccountDuplicateCheckService.reportAccountDuplicate(
            blankToNullId(stringFrom(payload.get('accountId'))),
            blankToNullId(stringFrom(payload.get('duplicateOfId')))
          )
        );
        return;
      }
      if (path == 'merge-accounts') {
        Map<String, Object> payload = parseJsonMap(body);
        writeJson(
          res,
          200,
          AccountDuplicateCheckService.mergeAccountDuplicates(
            blankToNullId(stringFrom(payload.get('survivorId'))),
            blankToNullId(stringFrom(payload.get('duplicateId')))
          )
        );
        return;
      }
      writeJson(res, 404, new ErrorResponse('Unknown POST path: ' + path));
    } catch (Exception e) {
      writeJson(res, 400, new ErrorResponse(e.getMessage()));
    }
  }

  private static List<AccountsTabController.MasterSearchRow> searchMasterList(String body) {
    Map<String, Object> payload = parseJsonMap(body);
    return AccountsTabController.searchMasterListWithFilters(
      stringFrom(payload.get('searchTerm')),
      blankToNullId(stringFrom(payload.get('recordTypeId'))),
      toBoolean(payload.get('cognitive'), false),
      blankToNullId(stringFrom(payload.get('brick148Id'))),
      blankToNullId(stringFrom(payload.get('brick702Id'))),
      stringFrom(payload.get('specialtyFilter'))
    );
  }

  private static AccountsTabController.MapPlaceSearchResult searchMapPlaces(String body) {
    Map<String, Object> payload = parseJsonMap(body);
    AccountsTabController.MapPlaceGeoFilter geoFilter = null;
    if (payload.get('geoFilter') != null) {
      geoFilter = (AccountsTabController.MapPlaceGeoFilter) JSON.deserialize(
        JSON.serialize(payload.get('geoFilter')),
        AccountsTabController.MapPlaceGeoFilter.class
      );
    }
    return AccountsTabController.searchMapPlaces(
      stringFrom(payload.get('searchTerm')),
      stringFrom(payload.get('recordTypeDeveloperName')),
      geoFilter
    );
  }

  private static AccountsTabController.WizardCreateInput parseWizardCreateInput(String body) {
    Map<String, Object> payload = parseJsonMap(body);
    Object raw = payload.get('input');
    if (raw == null) {
      raw = payload;
    }
    return (AccountsTabController.WizardCreateInput) JSON.deserialize(
      JSON.serialize(raw),
      AccountsTabController.WizardCreateInput.class
    );
  }

  private static String restPath(RestRequest req) {
    String path = req == null || String.isBlank(req.requestURI)
      ? ''
      : req.requestURI.substringAfter('/accounts-tab/v1');
    if (path.startsWith('/')) {
      path = path.substring(1);
    }
    if (path.contains('?')) {
      path = path.substringBefore('?');
    }
    return path;
  }

  private static Map<String, Object> parseJsonMap(String body) {
    if (String.isBlank(body)) {
      return new Map<String, Object>();
    }
    Object parsed = JSON.deserializeUntyped(body);
    if (parsed instanceof Map<String, Object>) {
      return (Map<String, Object>) parsed;
    }
    return new Map<String, Object>();
  }

  private static void writeJson(RestResponse res, Integer statusCode, Object payload) {
    res.statusCode = statusCode;
    res.responseBody = Blob.valueOf(JSON.serialize(payload));
  }

  private static Id blankToNullId(String value) {
    return String.isBlank(value) ? null : (Id) value;
  }

  private static String stringFrom(Object value) {
    if (value == null) {
      return null;
    }
    String text = String.valueOf(value);
    if (String.isBlank(text) || text == 'null' || text == 'undefined') {
      return null;
    }
    return text;
  }

  private static Boolean toBoolean(Object value, Boolean fallback) {
    if (value == null) {
      return fallback;
    }
    if (value instanceof Boolean) {
      return (Boolean) value;
    }
    String text = String.valueOf(value);
    if (text.equalsIgnoreCase('true')) {
      return true;
    }
    if (text.equalsIgnoreCase('false')) {
      return false;
    }
    return fallback;
  }

  private static Map<String, Object> resolveBricksFromPin(Decimal latitude, Decimal longitude) {
    Map<String, Object> match = new Map<String, Object>{
      'brick148Id' => null,
      'brick702Id' => null,
      'brick148Label' => null,
      'brick702Label' => null
    };
    if (latitude == null || longitude == null) {
      return match;
    }
    Account nearest = nearestGeocodedAccount(latitude, longitude);
    if (nearest == null) {
      return match;
    }
    applyAccountBricksToMatch(nearest, match);
    return match;
  }

  private static Account nearestGeocodedAccount(Decimal latitude, Decimal longitude) {
    Decimal box = 0.2;
    Decimal minLat = latitude - box;
    Decimal maxLat = latitude + box;
    Decimal minLng = longitude - box;
    Decimal maxLng = longitude + box;
    String soql =
      'SELECT Id, BillingLatitude, BillingLongitude, Brick__c, Brick__r.Brick_Level__c, ' +
      'Brick__r.Parent_Brick__c, Brick__r.Name, Brick__r.Brick_Code__c';
    if (accountHasField('Brick_148__c')) {
      soql += ', Brick_148__c, Brick_148__r.Name, Brick_148__r.Brick_Code__c, Brick_148__r.Parent_Brick__c';
    }
    if (accountHasField('Brick_702__c')) {
      soql += ', Brick_702__c, Brick_702__r.Name, Brick_702__r.Brick_Code__c, Brick_702__r.Parent_Brick__c';
    }
    soql +=
      ' FROM Account WHERE BillingLatitude != NULL AND BillingLongitude != NULL' +
      ' AND BillingLatitude >= :minLat AND BillingLatitude <= :maxLat' +
      ' AND BillingLongitude >= :minLng AND BillingLongitude <= :maxLng' +
      ' LIMIT 80';
    List<Account> nearby = Database.query(soql, AccessLevel.SYSTEM_MODE);
    Account best = null;
    Decimal bestScore = null;
    for (Account account : nearby) {
      Decimal dlat = account.BillingLatitude - latitude;
      Decimal dlng = account.BillingLongitude - longitude;
      Decimal score = (dlat * dlat) + (dlng * dlng);
      if (bestScore == null || score < bestScore) {
        bestScore = score;
        best = account;
      }
    }
    return best;
  }

  private static void applyAccountBricksToMatch(Account account, Map<String, Object> match) {
    if (accountHasField('Brick_702__c') && account.get('Brick_702__c') != null) {
      match.put('brick702Id', account.get('Brick_702__c'));
      Brick__c brick702 = (Brick__c) account.getSObject('Brick_702__r');
      if (brick702 != null) {
        match.put('brick702Label', formatBrickName(brick702.Brick_Code__c, brick702.Name));
        if (brick702.Parent_Brick__c != null) {
          match.put('brick148Id', brick702.Parent_Brick__c);
        }
      }
    }
    if (match.get('brick148Id') == null && accountHasField('Brick_148__c') && account.get('Brick_148__c') != null) {
      match.put('brick148Id', account.get('Brick_148__c'));
      Brick__c brick148 = (Brick__c) account.getSObject('Brick_148__r');
      if (brick148 != null) {
        match.put('brick148Label', formatBrickName(brick148.Brick_Code__c, brick148.Name));
      }
    } else if (match.get('brick148Id') != null && match.get('brick148Label') == null && accountHasField('Brick_148__c')) {
      Brick__c brick148 = (Brick__c) account.getSObject('Brick_148__r');
      if (brick148 != null) {
        match.put('brick148Label', formatBrickName(brick148.Brick_Code__c, brick148.Name));
      }
    }
    if ((match.get('brick148Id') == null || match.get('brick702Id') == null) && account.Brick__c != null) {
      String level = account.Brick__r == null ? null : account.Brick__r.Brick_Level__c;
      if (match.get('brick702Id') == null && level == '702') {
        match.put('brick702Id', account.Brick__c);
        match.put('brick702Label', formatBrickName(account.Brick__r.Brick_Code__c, account.Brick__r.Name));
        if (match.get('brick148Id') == null) {
          match.put('brick148Id', account.Brick__r.Parent_Brick__c);
        }
      } else if (match.get('brick148Id') == null && level == '148') {
        match.put('brick148Id', account.Brick__c);
        match.put('brick148Label', formatBrickName(account.Brick__r.Brick_Code__c, account.Brick__r.Name));
      }
    }
  }

  private static Boolean accountHasField(String fieldName) {
    if (String.isBlank(fieldName)) {
      return false;
    }
    Map<String, Schema.SObjectField> fields = Schema.SObjectType.Account.fields.getMap();
    return fields.containsKey(fieldName);
  }

  private static String formatBrickName(String code, String name) {
    if (String.isNotBlank(code) && String.isNotBlank(name)) {
      return code + ' — ' + name;
    }
    return name;
  }

  private static Decimal toDecimal(Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof Decimal) {
      return (Decimal) value;
    }
    if (value instanceof Integer) {
      return Decimal.valueOf((Integer) value);
    }
    if (value instanceof Long) {
      return Decimal.valueOf((Long) value);
    }
    String text = String.valueOf(value);
    if (String.isBlank(text) || text == 'null') {
      return null;
    }
    return Decimal.valueOf(text);
  }
}