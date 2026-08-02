/**
 * Walk-in monthly performance CSV export for pace dashboard.
 */
public without sharing class EmployeeTimeCardPaceExportService {

  public class PaceExportRow {
    @AuraEnabled public String employeeName { get; set; }
    @AuraEnabled public String company { get; set; }
    @AuraEnabled public String businessSegment { get; set; }
    @AuraEnabled public Decimal walkInRevenueActual { get; set; }
    @AuraEnabled public Decimal walkInRevenueTarget { get; set; }
    @AuraEnabled public Decimal walkInRevenueAchPercent { get; set; }
    @AuraEnabled public Decimal walkInRevenueProjectedAchPercent { get; set; }
    @AuraEnabled public Decimal walkInVisitsActual { get; set; }
    @AuraEnabled public Decimal walkInVisitsTarget { get; set; }
    @AuraEnabled public Decimal walkInVisitsAchPercent { get; set; }
    @AuraEnabled public Decimal walkInVisitsProjectedAchPercent { get; set; }
    @AuraEnabled public Decimal callRatePercent { get; set; }
    @AuraEnabled public String paceStatus { get; set; }
    @AuraEnabled public Integer badgeCount { get; set; }
    @AuraEnabled public Integer streakDays { get; set; }
    @AuraEnabled public Decimal timeOffDays { get; set; }
  }

  public static List<PaceExportRow> loadExportRows(Integer year, Integer month) {
    Date monthStart = Date.newInstance(year, month, 1);
    Date monthEnd = monthStart.addMonths(1).addDays(-1);

    List<Employee_Time_Card__c> cards = [
      SELECT
        Id,
        Employee__c,
        Employee__r.Name,
        Employee__r.Department,
        Company_Name__c,
        Time_Card_Month_Start_Date__c,
        Time_Card_Month_End_Date__c,
        Target_Daily_Visits__c,
        Walk_in_Revenue__c,
        Walk_in_Revenue_Target__c,
        Walk_in_Revenue_Ach__c,
        Walk_in_Visits__c,
        Walk_in_Visits_Target__c,
        Walk_in_Visits_Ach__c
      FROM Employee_Time_Card__c
      WHERE
        Time_Card_Month_Start_Date__c = :monthStart
        AND Time_Card_Month_End_Date__c = :monthEnd
        AND Employee__c != NULL
      ORDER BY Employee__r.Name ASC
    ];

    Set<Id> cardIds = new Set<Id>();
    for (Employee_Time_Card__c c : cards) {
      cardIds.add(c.Id);
    }

    Map<Id, List<Employee_Time_Card_Day_Entry__c>> entriesByCard =
      new Map<Id, List<Employee_Time_Card_Day_Entry__c>>();
    for (Employee_Time_Card_Day_Entry__c e : [
      SELECT
        Employee_Time_Card__c,
        Date__c,
        Day_Definition__c,
        Calendar_Working_Days__c,
        Planned_AM_Visits__c,
        Planned_PM_Visits__c,
        Planned_Coaching_Visits__c,
        Unplanned_AM_Visits__c,
        Unplanned_PM_Visits__c,
        Unplanned_Coaching_Visits__c,
        Total_Visits__c,
        Days_with_Activities__c,
        Time_off_Days__c,
        TOT_Days__c,
        TOT_Days_Excluding_Weekends__c
      FROM Employee_Time_Card_Day_Entry__c
      WHERE Employee_Time_Card__c IN :cardIds
      ORDER BY Date__c ASC
    ]) {
      if (!entriesByCard.containsKey(e.Employee_Time_Card__c)) {
        entriesByCard.put(e.Employee_Time_Card__c, new List<Employee_Time_Card_Day_Entry__c>());
      }
      entriesByCard.get(e.Employee_Time_Card__c).add(e);
    }

    List<PaceExportRow> rows = new List<PaceExportRow>();
    for (Employee_Time_Card__c card : cards) {
      List<Employee_Time_Card_Day_Entry__c> entries = entriesByCard.containsKey(card.Id)
        ? entriesByCard.get(card.Id)
        : new List<Employee_Time_Card_Day_Entry__c>();
      EmployeeTimeCardPaceService.PaceDetailResult detail =
        EmployeeTimeCardPaceService.buildPaceDetail(card, entries, Date.today());

      PaceExportRow row = new PaceExportRow();
      row.employeeName = detail.employeeName;
      row.company = detail.employeeCompany;
      row.businessSegment = card.Employee__r != null ? card.Employee__r.Department : null;
      row.walkInRevenueActual = detail.walkInRevenue != null ? detail.walkInRevenue.actual : 0;
      row.walkInRevenueTarget = detail.walkInRevenue != null ? detail.walkInRevenue.target : 0;
      row.walkInRevenueAchPercent = detail.walkInRevenue != null ? detail.walkInRevenue.currentAchPercent : 0;
      row.walkInRevenueProjectedAchPercent = detail.walkInRevenue != null
        ? detail.walkInRevenue.projectedAchPercent
        : 0;
      row.walkInVisitsActual = detail.walkInVisits != null ? detail.walkInVisits.actual : 0;
      row.walkInVisitsTarget = detail.walkInVisits != null ? detail.walkInVisits.target : 0;
      row.walkInVisitsAchPercent = detail.walkInVisits != null ? detail.walkInVisits.currentAchPercent : 0;
      row.walkInVisitsProjectedAchPercent = detail.walkInVisits != null
        ? detail.walkInVisits.projectedAchPercent
        : 0;
      row.callRatePercent = detail.activitySummary != null ? detail.activitySummary.callRatePercent : 0;
      row.paceStatus = EmployeeTimeCardPaceService.worstStatus(
        new List<String>{
          detail.walkInRevenue != null ? detail.walkInRevenue.paceStatus : 'behind',
          detail.walkInVisits != null ? detail.walkInVisits.paceStatus : 'behind'
        }
      );
      row.badgeCount = EmployeeTimeCardPaceService.countEarnedBadges(detail.badges);
      row.streakDays = detail.streakDays;
      row.timeOffDays = detail.activitySummary != null ? detail.activitySummary.timeOffDays : 0;
      rows.add(row);
    }
    return rows;
  }

  public static String buildCsv(List<PaceExportRow> rows) {
    List<String> lines = new List<String>();
    lines.add(
      'Employee,Company,Segment,WI Revenue Actual,WI Revenue Target,WI Revenue Ach %,WI Revenue Proj %,' +
      'WI Visits Actual,WI Visits Target,WI Visits Ach %,WI Visits Proj %,Call Rate %,Pace Status,Badges,Streak,Time Off Days'
    );
    if (rows == null) {
      return String.join(lines, '\n');
    }
    for (PaceExportRow r : rows) {
      lines.add(
        csv(r.employeeName) + ',' +
        csv(r.company) + ',' +
        csv(r.businessSegment) + ',' +
        csv(r.walkInRevenueActual) + ',' +
        csv(r.walkInRevenueTarget) + ',' +
        csv(r.walkInRevenueAchPercent) + ',' +
        csv(r.walkInRevenueProjectedAchPercent) + ',' +
        csv(r.walkInVisitsActual) + ',' +
        csv(r.walkInVisitsTarget) + ',' +
        csv(r.walkInVisitsAchPercent) + ',' +
        csv(r.walkInVisitsProjectedAchPercent) + ',' +
        csv(r.callRatePercent) + ',' +
        csv(r.paceStatus) + ',' +
        csv(r.badgeCount) + ',' +
        csv(r.streakDays) + ',' +
        csv(r.timeOffDays)
      );
    }
    return String.join(lines, '\n');
  }

  private static String csv(Object value) {
    if (value == null) {
      return '';
    }
    String s = String.valueOf(value);
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"' + s.replace('"', '""') + '"';
    }
    return s;
  }
}
