public with sharing class VisitCallReportController {

  @AuraEnabled(cacheable=true)
  public static VisitCallReportService.CallReportPayload getCallReportPayload(Id visitId) {
    return VisitCallReportService.getCallReportPayload(visitId);
  }

  @AuraEnabled(cacheable=true)
  public static List<VisitCallReportService.TerritoryProductOption> getTerritoryProducts(Id visitId) {
    return VisitCallReportService.getTerritoryProducts(visitId);
  }

  @AuraEnabled(cacheable=true)
  public static List<VisitCallReportService.AttendeeCandidate> searchAttendeeCandidates(
    Id visitId,
    String searchTerm,
    Integer offset
  ) {
    return VisitCallReportService.searchAttendeeCandidates(visitId, searchTerm, offset);
  }

  @AuraEnabled(cacheable=true)
  public static List<VisitCallReportService.SampleInventoryOption> getSampleInventoryForUser() {
    return VisitCallReportService.getSampleInventoryForUser();
  }

  @AuraEnabled(cacheable=true)
  public static List<CLM_Presentation__c> getActiveClmPresentations() {
    return [
      SELECT Id, Name, Product__c, Status__c, Slide_Count__c
      FROM CLM_Presentation__c
      WHERE Status__c = 'Available'
      WITH USER_MODE
      ORDER BY Name ASC
      LIMIT 100
    ];
  }

  @AuraEnabled
  public static VisitCallReportService.CallReportPayload saveCallReport(
    VisitCallReportService.SaveRequest request
  ) {
    return VisitCallReportService.saveCallReport(request);
  }

  @RemoteAction
  public static VisitCallReportService.CallReportPayload getCallReportPayloadRemote(Id visitId) {
    return VisitCallReportService.getCallReportPayload(visitId);
  }

  @RemoteAction
  public static List<VisitCallReportService.TerritoryProductOption> getTerritoryProductsRemote(
    Id visitId
  ) {
    return VisitCallReportService.getTerritoryProducts(visitId);
  }

  @RemoteAction
  public static List<VisitCallReportService.AttendeeCandidate> searchAttendeeCandidatesRemote(
    Id visitId,
    String searchTerm,
    Integer offset
  ) {
    return VisitCallReportService.searchAttendeeCandidates(visitId, searchTerm, offset);
  }

  @RemoteAction
  public static List<VisitCallReportService.SampleInventoryOption> getSampleInventoryForUserRemote() {
    return VisitCallReportService.getSampleInventoryForUser();
  }

  @RemoteAction
  public static VisitCallReportService.CallReportPayload saveCallReportRemote(String requestJson) {
    return VisitCallReportService.saveCallReport(parseSaveRequest(requestJson));
  }

  private static VisitCallReportService.SaveRequest parseSaveRequest(String requestJson) {
    Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(requestJson);
    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = (Id) root.get('visitId');
    request.status = (String) root.get('status');
    request.visitObjective = (String) root.get('visitObjective');
    request.visitNotes = (String) root.get('visitNotes');
    request.clmPresentation = (String) root.get('clmPresentation');
    if (root.get('nextVisitDate') != null) {
      request.nextVisitDate = Date.valueOf(String.valueOf(root.get('nextVisitDate')));
    }
    request.cancellationReason = (String) root.get('cancellationReason');
    request.attendees = parseAttendeeRows((List<Object>) root.get('attendees'));
    request.products = parseProductRows((List<Object>) root.get('products'));
    request.samples = parseSampleRows((List<Object>) root.get('samples'));
    request.clmSessions = new List<VisitCallReportService.ClmSessionRow>();
    return request;
  }

  private static List<VisitCallReportService.AttendeeRow> parseAttendeeRows(List<Object> rawRows) {
    List<VisitCallReportService.AttendeeRow> rows = new List<VisitCallReportService.AttendeeRow>();
    if (rawRows == null) {
      return rows;
    }
    for (Object raw : rawRows) {
      Map<String, Object> item = (Map<String, Object>) raw;
      VisitCallReportService.AttendeeRow row = new VisitCallReportService.AttendeeRow();
      row.id = item.containsKey('id') && item.get('id') != null ? (Id) item.get('id') : null;
      row.accountId = (Id) item.get('accountId');
      row.accountName = (String) item.get('accountName');
      row.specialty = (String) item.get('specialty');
      row.recordTypeDeveloperName = (String) item.get('recordTypeDeveloperName');
      row.accountTypeLabel = (String) item.get('accountTypeLabel');
      row.role = (String) item.get('role');
      row.isPrimary = item.get('isPrimary') == true;
      if (item.get('displayOrder') != null) {
        row.displayOrder = Integer.valueOf(String.valueOf(item.get('displayOrder')));
      }
      rows.add(row);
    }
    return rows;
  }

  private static List<VisitCallReportService.ProductDetailRow> parseProductRows(List<Object> rawRows) {
    List<VisitCallReportService.ProductDetailRow> rows = new List<VisitCallReportService.ProductDetailRow>();
    if (rawRows == null) {
      return rows;
    }
    for (Object raw : rawRows) {
      Map<String, Object> item = (Map<String, Object>) raw;
      VisitCallReportService.ProductDetailRow row = new VisitCallReportService.ProductDetailRow();
      row.id = item.containsKey('id') && item.get('id') != null ? (Id) item.get('id') : null;
      row.productId = (Id) item.get('productId');
      row.productName = (String) item.get('productName');
      row.detailType = (String) item.get('detailType');
      row.notes = (String) item.get('notes');
      if (item.get('displayOrder') != null) {
        row.displayOrder = Integer.valueOf(String.valueOf(item.get('displayOrder')));
      }
      row.messages = new List<VisitCallReportService.ProductMessageRow>();
      rows.add(row);
    }
    return rows;
  }

  private static List<VisitCallReportService.SampleRow> parseSampleRows(List<Object> rawRows) {
    List<VisitCallReportService.SampleRow> rows = new List<VisitCallReportService.SampleRow>();
    if (rawRows == null) {
      return rows;
    }
    for (Object raw : rawRows) {
      Map<String, Object> item = (Map<String, Object>) raw;
      VisitCallReportService.SampleRow row = new VisitCallReportService.SampleRow();
      row.id = item.containsKey('id') && item.get('id') != null ? (Id) item.get('id') : null;
      row.productId = item.containsKey('productId') ? (Id) item.get('productId') : null;
      row.productName = (String) item.get('productName');
      row.visitAttendeeId = item.containsKey('visitAttendeeId') ? (Id) item.get('visitAttendeeId') : null;
      row.attendeeName = (String) item.get('attendeeName');
      row.lotNumber = (String) item.get('lotNumber');
      row.sampleInventoryId = item.containsKey('sampleInventoryId')
        ? (Id) item.get('sampleInventoryId')
        : null;
      if (item.get('quantity') != null) {
        row.quantity = Decimal.valueOf(String.valueOf(item.get('quantity')));
      }
      rows.add(row);
    }
    return rows;
  }
}
