public with sharing class BrickSalesAlertService {
  public class BrickAlertRow {
    @AuraEnabled public Id brickId;
    @AuraEnabled public String brickName;
    @AuraEnabled public Decimal growthPercent;
    @AuraEnabled public Decimal revenueDelta;
    @AuraEnabled public List<DoctorFocusRow> doctors;
  }

  public class DoctorFocusRow {
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
  }

  @AuraEnabled
  public static List<BrickAlertRow> getBrickGrowthAlerts(Id contextUserId) {
    Id userId = contextUserId == null ? UserInfo.getUserId() : contextUserId;
    List<BrickAlertRow> alerts = new List<BrickAlertRow>();

    Date thisMonth = Date.today().toStartOfMonth();
    Date priorMonth = thisMonth.addMonths(-1);
    Map<Id, Decimal> thisMonthByBrick = new Map<Id, Decimal>();
    Map<Id, Decimal> priorMonthByBrick = new Map<Id, Decimal>();
    Map<Id, String> brickNames = new Map<Id, String>();

    for (AggregateResult ar : [
      SELECT Brick__c brickId, Brick__r.Name brickName, Report_Month__c monthStart, SUM(Revenue__c) revenue
      FROM Pharmacy_Sales_Withdrawal__c
      WHERE Report_Month__c IN :new List<Date>{ thisMonth, priorMonth } AND Brick__c != null
      WITH USER_MODE
      GROUP BY Brick__c, Brick__r.Name, Report_Month__c
    ]) {
      Id brickId = (Id) ar.get('brickId');
      brickNames.put(brickId, (String) ar.get('brickName'));
      Decimal revenue = ar.get('revenue') == null ? 0 : (Decimal) ar.get('revenue');
      Date monthStart = (Date) ar.get('monthStart');
      if (monthStart == thisMonth) {
        thisMonthByBrick.put(brickId, revenue);
      } else {
        priorMonthByBrick.put(brickId, revenue);
      }
    }

    for (Id brickId : thisMonthByBrick.keySet()) {
      Decimal currentRevenue = thisMonthByBrick.get(brickId);
      Decimal priorRevenue = priorMonthByBrick.containsKey(brickId) ? priorMonthByBrick.get(brickId) : 0;
      if (priorRevenue <= 0) {
        continue;
      }
      Decimal growth = ((currentRevenue - priorRevenue) / priorRevenue) * 100;
      if (growth < 15) {
        continue;
      }
      BrickAlertRow alert = new BrickAlertRow();
      alert.brickId = brickId;
      alert.brickName = brickNames.get(brickId);
      alert.growthPercent = growth.setScale(1, RoundingMode.HALF_UP);
      alert.revenueDelta = (currentRevenue - priorRevenue).setScale(0, RoundingMode.HALF_UP);
      alert.doctors = doctorsInBrick(brickId, userId);
      alerts.add(alert);
    }
    return alerts;
  }

  @AuraEnabled
  public static Integer notifyRepsForGrowingBricks() {
    Integer sent = 0;
    CustomNotificationType notificationType = notificationType();
    if (notificationType == null) {
      return 0;
    }
    for (BrickAlertRow alert : getBrickGrowthAlerts(null)) {
      if (alert.doctors == null || alert.doctors.isEmpty()) {
        continue;
      }
      Set<String> recipients = new Set<String>{ String.valueOf(UserInfo.getUserId()) };
      Messaging.CustomNotification notification = new Messaging.CustomNotification();
      notification.setTitle('Brick sales up: ' + alert.brickName);
      notification.setBody(
        alert.brickName +
        ' sell-out rose ' +
        String.valueOf(alert.growthPercent) +
        '%. Focus on ' +
        alert.doctors.size() +
        ' doctor(s) in this brick.'
      );
      notification.setNotificationTypeId(notificationType.Id);
      notification.setTargetId(alert.brickId);
      try {
        notification.send(recipients);
        sent++;
      } catch (Exception ignore) {
        // Notification delivery is best-effort.
      }
    }
    return sent;
  }

  private static List<DoctorFocusRow> doctorsInBrick(Id brickId, Id userId) {
    List<DoctorFocusRow> doctors = new List<DoctorFocusRow>();
    Set<Id> pharmacyIds = new Set<Id>();
    for (Brick_Pharmacy__c membership : [
      SELECT Pharmacy_Account__c
      FROM Brick_Pharmacy__c
      WHERE Brick__c = :brickId AND Is_Active__c = TRUE AND Pharmacy_Account__c != null
      WITH USER_MODE
      LIMIT 200
    ]) {
      pharmacyIds.add(membership.Pharmacy_Account__c);
    }
    for (Account pharmacy : [
      SELECT Id FROM Account WHERE Brick__c = :brickId WITH USER_MODE LIMIT 200
    ]) {
      pharmacyIds.add(pharmacy.Id);
    }
    if (pharmacyIds.isEmpty()) {
      return doctors;
    }
    Set<Id> doctorIds = new Set<Id>();
    for (Account_Affiliation__c affiliation : [
      SELECT Primary_Account__c, Related_Account__c, Primary_Account__r.Name, Related_Account__r.Name,
        Primary_Account__r.IsPersonAccount, Related_Account__r.IsPersonAccount
      FROM Account_Affiliation__c
      WHERE Primary_Account__c IN :pharmacyIds OR Related_Account__c IN :pharmacyIds
      WITH USER_MODE
      LIMIT 400
    ]) {
      if (affiliation.Primary_Account__r != null &&
        affiliation.Primary_Account__r.IsPersonAccount == true &&
        !pharmacyIds.contains(affiliation.Primary_Account__c) &&
        doctorIds.add(affiliation.Primary_Account__c)) {
        DoctorFocusRow row = new DoctorFocusRow();
        row.accountId = affiliation.Primary_Account__c;
        row.accountName = affiliation.Primary_Account__r.Name;
        doctors.add(row);
      }
      if (affiliation.Related_Account__r != null &&
        affiliation.Related_Account__r.IsPersonAccount == true &&
        !pharmacyIds.contains(affiliation.Related_Account__c) &&
        doctorIds.add(affiliation.Related_Account__c)) {
        DoctorFocusRow row = new DoctorFocusRow();
        row.accountId = affiliation.Related_Account__c;
        row.accountName = affiliation.Related_Account__r.Name;
        doctors.add(row);
      }
      if (doctors.size() >= 15) {
        break;
      }
    }
    return doctors;
  }

  private static CustomNotificationType notificationType() {
    List<CustomNotificationType> rows = [
      SELECT Id
      FROM CustomNotificationType
      WHERE DeveloperName = 'Brick_Sales_Increase'
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }
}
