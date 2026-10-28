public with sharing class HcpClassificationSuggestionService {
  public class SuggestionRow {
    @AuraEnabled public Id id;
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public String currentClass;
    @AuraEnabled public String suggestedClass;
    @AuraEnabled public String direction;
    @AuraEnabled public String evidence;
    @AuraEnabled public String status;
  }

  public class DecisionRequest {
    @AuraEnabled public Id suggestionId;
    @AuraEnabled public String rejectionReason;
    @AuraEnabled public String overwrittenClass;
  }

  private static final List<String> CLASS_LADDER = new List<String>{
    'C3', 'C2', 'C1', 'B3', 'B2', 'B1', 'A3', 'A2', 'A1'
  };

  @AuraEnabled
  public static List<SuggestionRow> getPendingSuggestions(Id contextUserId) {
    Id userId = contextUserId == null ? UserInfo.getUserId() : contextUserId;
    List<SuggestionRow> rows = new List<SuggestionRow>();
    if (!suggestionObjectAvailable()) {
      return rows;
    }
    for (SObject record : Database.query(
      'SELECT Id, Account__c, Account__r.Name, Current_Class__c, Suggested_Class__c, Direction__c, Evidence__c, Status__c ' +
      'FROM HCP_Classification_Suggestion__c ' +
      'WHERE Status__c = \'Pending\' AND Target_User__c = :userId ' +
      'WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 50'
    )) {
      SuggestionRow row = new SuggestionRow();
      row.id = (Id) record.get('Id');
      row.accountId = (Id) record.get('Account__c');
      SObject account = record.getSObject('Account__r');
      row.accountName = account == null ? null : (String) account.get('Name');
      row.currentClass = (String) record.get('Current_Class__c');
      row.suggestedClass = (String) record.get('Suggested_Class__c');
      row.direction = (String) record.get('Direction__c');
      row.evidence = (String) record.get('Evidence__c');
      row.status = (String) record.get('Status__c');
      rows.add(row);
    }
    return rows;
  }

  @AuraEnabled
  public static SuggestionRow suggestForAccount(Id accountId) {
    if (accountId == null) {
      throw PlannerUserMessage.aura('Account Id is required.');
    }
    if (!suggestionObjectAvailable()) {
      throw PlannerUserMessage.aura('Classification suggestions are not available in this org yet.');
    }

    String currentClass = resolveCurrentClass(accountId);
    Decimal neighbourVolume = neighbourPharmacyVolume(accountId);
    Decimal writtenPotential = writtenPotentialVolume(accountId);
    Integer currentScore = classScore(currentClass);
    Integer suggestedScore = currentScore;
    if (neighbourVolume > 0 && writtenPotential > 0) {
      Decimal ratio = neighbourVolume / writtenPotential;
      if (ratio >= 1.35) {
        suggestedScore = Math.min(CLASS_LADDER.size(), currentScore + 1);
      } else if (ratio <= 0.65) {
        suggestedScore = Math.max(1, currentScore - 1);
      }
    }
    String suggestedClass = CLASS_LADDER[suggestedScore - 1];
    String direction = suggestedScore > currentScore
      ? 'Up'
      : (suggestedScore < currentScore ? 'Down' : 'Unchanged');
    String evidence =
      'Neighbouring + affiliation pharmacy volume (incl. captured sales-order/bulk) = ' +
      String.valueOf(neighbourVolume.setScale(0)) +
      ' UOM vs written potential ' +
      String.valueOf(writtenPotential.setScale(0)) +
      ' UOM.';

    if (direction == 'Unchanged') {
      SuggestionRow unchanged = new SuggestionRow();
      unchanged.accountId = accountId;
      unchanged.currentClass = currentClass;
      unchanged.suggestedClass = suggestedClass;
      unchanged.direction = direction;
      unchanged.evidence = evidence;
      unchanged.status = 'Pending';
      return unchanged;
    }

    SObject suggestion = Schema.getGlobalDescribe().get('HCP_Classification_Suggestion__c').newSObject();
    suggestion.put('Account__c', accountId);
    suggestion.put('Target_User__c', UserInfo.getUserId());
    suggestion.put('Current_Class__c', currentClass);
    suggestion.put('Suggested_Class__c', suggestedClass);
    suggestion.put('Direction__c', direction);
    suggestion.put('Evidence__c', evidence);
    suggestion.put('Status__c', 'Pending');
    insert as user suggestion;

    SuggestionRow row = new SuggestionRow();
    row.id = (Id) suggestion.get('Id');
    row.accountId = accountId;
    row.currentClass = currentClass;
    row.suggestedClass = suggestedClass;
    row.direction = direction;
    row.evidence = evidence;
    row.status = 'Pending';
    return row;
  }

  @AuraEnabled
  public static SuggestionRow approveSuggestion(Id suggestionId) {
    SObject suggestion = loadSuggestion(suggestionId);
    String suggestedClass = (String) suggestion.get('Suggested_Class__c');
    Id accountId = (Id) suggestion.get('Account__c');
    applyClassToAtf(accountId, suggestedClass);
    suggestion.put('Status__c', 'Approved');
    update as user suggestion;
    return toRow(suggestion);
  }

  @AuraEnabled
  public static SuggestionRow rejectSuggestion(DecisionRequest request) {
    if (request == null || request.suggestionId == null) {
      throw PlannerUserMessage.aura('Suggestion Id is required.');
    }
    if (String.isBlank(request.rejectionReason)) {
      throw PlannerUserMessage.aura('Enter a rejection reason.');
    }
    if (String.isBlank(request.overwrittenClass)) {
      throw PlannerUserMessage.aura('Enter the overwritten classification.');
    }
    SObject suggestion = loadSuggestion(request.suggestionId);
    Id accountId = (Id) suggestion.get('Account__c');
    applyClassToAtf(accountId, request.overwrittenClass);
    suggestion.put('Status__c', 'Rejected');
    suggestion.put('Rejection_Reason__c', request.rejectionReason);
    suggestion.put('Overwritten_Class__c', request.overwrittenClass);
    update as user suggestion;
    return toRow(suggestion);
  }

  private static Boolean suggestionObjectAvailable() {
    return Schema.getGlobalDescribe().containsKey('HCP_Classification_Suggestion__c');
  }

  private static SObject loadSuggestion(Id suggestionId) {
    List<SObject> rows = Database.query(
      'SELECT Id, Account__c, Account__r.Name, Current_Class__c, Suggested_Class__c, Direction__c, Evidence__c, Status__c, Rejection_Reason__c, Overwritten_Class__c ' +
      'FROM HCP_Classification_Suggestion__c WHERE Id = :suggestionId WITH USER_MODE LIMIT 1'
    );
    if (rows.isEmpty()) {
      throw PlannerUserMessage.aura('Suggestion not found.');
    }
    return rows[0];
  }

  private static SuggestionRow toRow(SObject record) {
    SuggestionRow row = new SuggestionRow();
    row.id = (Id) record.get('Id');
    row.accountId = (Id) record.get('Account__c');
    SObject account = record.getSObject('Account__r');
    row.accountName = account == null ? null : (String) account.get('Name');
    row.currentClass = (String) record.get('Current_Class__c');
    row.suggestedClass = (String) record.get('Suggested_Class__c');
    row.direction = (String) record.get('Direction__c');
    row.evidence = (String) record.get('Evidence__c');
    row.status = (String) record.get('Status__c');
    return row;
  }

  private static String resolveCurrentClass(Id accountId) {
    List<Account_Territory_Fields__c> rows = [
      SELECT HCP_Classification__c, Classification__c, Matrix_Rating__c
      FROM Account_Territory_Fields__c
      WHERE Account__c = :accountId
      WITH USER_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      return 'B2';
    }
    if (String.isNotBlank(rows[0].HCP_Classification__c)) {
      return rows[0].HCP_Classification__c;
    }
    if (String.isNotBlank(rows[0].Matrix_Rating__c)) {
      return rows[0].Matrix_Rating__c.toUpperCase();
    }
    return String.isBlank(rows[0].Classification__c) ? 'B2' : rows[0].Classification__c + '2';
  }

  private static void applyClassToAtf(Id accountId, String classValue) {
    List<Account_Territory_Fields__c> rows = [
      SELECT Id, HCP_Classification__c
      FROM Account_Territory_Fields__c
      WHERE Account__c = :accountId
      WITH USER_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw PlannerUserMessage.aura('No territory rating found for this account.');
    }
    rows[0].HCP_Classification__c = classValue;
    update as user rows;
  }

  private static Decimal writtenPotentialVolume(Id accountId) {
    Decimal total = 0;
    for (Account_Territory_Product_Fields__c row : [
      SELECT Potential__c
      FROM Account_Territory_Product_Fields__c
      WHERE Account__c = :accountId AND Potential__c != null
      WITH USER_MODE
      LIMIT 200
    ]) {
      total += row.Potential__c;
    }
    return total;
  }

  private static Decimal neighbourPharmacyVolume(Id accountId) {
    Set<Id> pharmacyIds = new Set<Id>();
    pharmacyIds.addAll(HcpProductRoiService.affiliatedPharmacyIdsPublic(accountId));
    pharmacyIds.addAll(geoNeighbouringPharmacyIds(accountId));
    pharmacyIds.remove(accountId);
    Decimal total = 0;
    if (pharmacyIds.isEmpty()) {
      return total;
    }
    for (AggregateResult ar : [
      SELECT SUM(Quantity_Withdrawn__c) qty
      FROM Pharmacy_Sales_Withdrawal__c
      WHERE Pharmacy_Account__c IN :pharmacyIds
      WITH USER_MODE
    ]) {
      total += ar.get('qty') == null ? 0 : (Decimal) ar.get('qty');
    }
    if (atpfHasVolumeFields()) {
      for (Account_Territory_Product_Fields__c row : Database.query(
        'SELECT Sales_Order_Volume_UOM__c, Total_Volume_UOM__c ' +
        'FROM Account_Territory_Product_Fields__c ' +
        'WHERE Account__c IN :pharmacyIds WITH USER_MODE LIMIT 500'
      )) {
        Decimal salesOrder = (Decimal) row.get('Sales_Order_Volume_UOM__c');
        Decimal totalVolume = (Decimal) row.get('Total_Volume_UOM__c');
        if (salesOrder != null) {
          total += salesOrder;
        } else if (totalVolume != null) {
          total += totalVolume;
        }
      }
    }
    return total;
  }

  private static Set<Id> geoNeighbouringPharmacyIds(Id accountId) {
    Set<Id> pharmacyIds = new Set<Id>();
    List<Account> centers = [
      SELECT BillingLatitude, BillingLongitude
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (centers.isEmpty() || centers[0].BillingLatitude == null || centers[0].BillingLongitude == null) {
      return pharmacyIds;
    }
    Decimal centerLat = centers[0].BillingLatitude;
    Decimal centerLng = centers[0].BillingLongitude;
    Id pharmacyRtId = null;
    for (RecordType rt : [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsActive = TRUE AND DeveloperName = 'Pharmacy'
      LIMIT 1
    ]) {
      pharmacyRtId = rt.Id;
    }
    if (pharmacyRtId == null) {
      return pharmacyIds;
    }
    for (Account pharmacy : [
      SELECT Id, BillingLatitude, BillingLongitude
      FROM Account
      WHERE
        RecordTypeId = :pharmacyRtId
        AND Id != :accountId
        AND BillingLatitude != NULL
        AND BillingLongitude != NULL
      WITH USER_MODE
      LIMIT 500
    ]) {
      Decimal distanceKm = haversineKm(
        centerLat,
        centerLng,
        pharmacy.BillingLatitude,
        pharmacy.BillingLongitude
      );
      if (distanceKm <= 5) {
        pharmacyIds.add(pharmacy.Id);
      }
    }
    return pharmacyIds;
  }

  private static Decimal haversineKm(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
    Double r = 6371;
    Double dLat = ((Double) (lat2 - lat1)) * Math.PI / 180;
    Double dLon = ((Double) (lon2 - lon1)) * Math.PI / 180;
    Double a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(((Double) lat1) * Math.PI / 180) *
      Math.cos(((Double) lat2) * Math.PI / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
    Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return (Decimal) (r * c);
  }

  private static Boolean atpfHasVolumeFields() {
    Map<String, Schema.SObjectField> fields = Schema.SObjectType.Account_Territory_Product_Fields__c.fields.getMap();
    return fields.containsKey('Sales_Order_Volume_UOM__c') && fields.containsKey('Total_Volume_UOM__c');
  }

  private static Integer classScore(String value) {
    if (String.isBlank(value)) {
      return 5;
    }
    String normalized = value.trim().toUpperCase();
    Integer idx = CLASS_LADDER.indexOf(normalized);
    if (idx >= 0) {
      return idx + 1;
    }
    if (normalized.startsWith('A')) {
      return 8;
    }
    if (normalized.startsWith('C')) {
      return 2;
    }
    return 5;
  }
}
