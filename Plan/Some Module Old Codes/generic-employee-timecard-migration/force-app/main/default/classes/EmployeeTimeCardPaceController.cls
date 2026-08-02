/**
 * Aura-enabled API for the generic Employee Pace Dashboard LWC.
 */
public with sharing class EmployeeTimeCardPaceController {

  public static final String TEAM_PERMISSION = 'View_Employee_Pace_Team';
  private static final Integer DEFAULT_PAGE_SIZE = 25;
  private static final Integer MAX_PAGE_SIZE = 50;

  public class FilterOption {
    @AuraEnabled public String label { get; set; }
    @AuraEnabled public String value { get; set; }
    @AuraEnabled public String company { get; set; }
    @AuraEnabled public String externalId { get; set; }
    @AuraEnabled public String businessSegment { get; set; }
  }

  public class FilterOptionsResult {
    @AuraEnabled public List<FilterOption> monthOptions { get; set; }
    @AuraEnabled public List<FilterOption> userOptions { get; set; }
    @AuraEnabled public List<FilterOption> companyOptions { get; set; }
    @AuraEnabled public List<FilterOption> businessSegmentOptions { get; set; }
    @AuraEnabled public Boolean canViewTeam { get; set; }
    @AuraEnabled public Id defaultUserId { get; set; }
    @AuraEnabled public String defaultMonthValue { get; set; }
  }

  public class TeamGridFilters {
    @AuraEnabled public String paceStatus { get; set; }
    @AuraEnabled public String company { get; set; }
    @AuraEnabled public String businessSegment { get; set; }
    @AuraEnabled public Decimal minCallRate { get; set; }
    @AuraEnabled public Decimal maxCallRate { get; set; }
    @AuraEnabled public Decimal minRevPercent { get; set; }
    @AuraEnabled public Decimal maxRevPercent { get; set; }
    @AuraEnabled public String sortField { get; set; }
    @AuraEnabled public String sortDirection { get; set; }
  }

  @AuraEnabled(cacheable=true)
  public static FilterOptionsResult getFilterOptions() {
    FilterOptionsResult result = new FilterOptionsResult();
    result.canViewTeam = canViewTeam();
    result.defaultUserId = UserInfo.getUserId();
    result.monthOptions = buildMonthOptions();
    result.defaultMonthValue = monthValue(Date.today().year(), Date.today().month());

    if (result.canViewTeam) {
      result.userOptions = EmployeeTimeCardPaceTeamQuery.loadUserFilterOptions();
      result.companyOptions = EmployeeTimeCardPaceTeamQuery.loadCompanyFilterOptions();
      result.businessSegmentOptions = EmployeeTimeCardPaceTeamQuery.loadBusinessSegmentFilterOptions();
    } else {
      result.userOptions = new List<FilterOption>();
      result.companyOptions = new List<FilterOption>();
      result.businessSegmentOptions = new List<FilterOption>();
    }
    return result;
  }

  @AuraEnabled(cacheable=true)
  public static EmployeeTimeCardPaceService.PaceDetailResult getPaceDetail(
    Integer year,
    Integer month,
    Id userId
  ) {
    Id resolvedUserId = resolveUserId(userId);
    Employee_Time_Card__c card = queryTimeCard(year, month, resolvedUserId);
    if (card == null) {
      return new EmployeeTimeCardPaceService.PaceDetailResult();
    }
    List<Employee_Time_Card_Day_Entry__c> dayEntries = queryDayEntries(card.Id);
    return EmployeeTimeCardPaceService.buildPaceDetail(card, dayEntries, Date.today());
  }

  @AuraEnabled(cacheable=true)
  public static EmployeeTimeCardPaceService.PaceTeamGridResult getPaceTeamGrid(
    Integer year,
    Integer month,
    Integer page,
    Integer pageSize,
    TeamGridFilters filters
  ) {
    if (!canViewTeam()) {
      throw new AuraHandledException('You do not have permission to view the team pace grid.');
    }

    Integer safePage = page == null || page < 1 ? 1 : page;
    Integer safeSize = pageSize == null || pageSize < 1
      ? DEFAULT_PAGE_SIZE
      : Math.min(pageSize, MAX_PAGE_SIZE);

    return EmployeeTimeCardPaceTeamQuery.loadTeamGrid(year, month, safePage, safeSize, filters);
  }

  public static Boolean canViewTeam() {
    return FeatureManagement.checkPermission(TEAM_PERMISSION);
  }

  private static Id resolveUserId(Id userId) {
    if (!canViewTeam()) {
      return UserInfo.getUserId();
    }
    return userId != null ? userId : UserInfo.getUserId();
  }

  private static List<FilterOption> buildMonthOptions() {
    List<FilterOption> options = new List<FilterOption>();
    Date cursor = Date.today().toStartOfMonth();
    for (Integer i = 0; i < 12; i++) {
      FilterOption opt = new FilterOption();
      opt.label = formatMonthLabel(cursor);
      opt.value = monthValue(cursor.year(), cursor.month());
      options.add(opt);
      cursor = cursor.addMonths(-1);
    }
    return options;
  }

  public static String monthValue(Integer year, Integer month) {
    String monthPart = month < 10 ? '0' + String.valueOf(month) : String.valueOf(month);
    return String.valueOf(year) + '-' + monthPart;
  }

  public static Date monthStartFromValue(String monthValue) {
    if (String.isBlank(monthValue) || !monthValue.contains('-')) {
      return Date.today().toStartOfMonth();
    }
    List<String> parts = monthValue.split('-');
    return Date.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), 1);
  }

  private static String formatMonthLabel(Date monthStart) {
    return Datetime.newInstance(monthStart.year(), monthStart.month(), 1, 0, 0, 0)
      .format('MMMM yyyy');
  }

  private static Employee_Time_Card__c queryTimeCard(Integer year, Integer month, Id userId) {
    Date monthStart = Date.newInstance(year, month, 1);
    Date monthEnd = monthStart.addMonths(1).addDays(-1);
    List<Employee_Time_Card__c> cards = [
      SELECT
        Id,
        Employee_Report_Details__c,
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
        Employee__c = :userId
        AND Time_Card_Month_Start_Date__c = :monthStart
        AND Time_Card_Month_End_Date__c = :monthEnd
      LIMIT 1
    ];
    return cards.isEmpty() ? null : cards[0];
  }

  private static List<Employee_Time_Card_Day_Entry__c> queryDayEntries(Id timeCardId) {
    return [
      SELECT
        Id,
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
      WHERE Employee_Time_Card__c = :timeCardId
      ORDER BY Date__c ASC
    ];
  }
}
