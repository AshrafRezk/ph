/**
 * Elevated SOQL for team pace grid (generic walk-in only).
 */
public without sharing class EmployeeTimeCardPaceTeamQuery {

  private static final String ALL_VALUE = '__all__';

  public static List<EmployeeTimeCardPaceController.FilterOption> loadUserFilterOptions() {
    List<EmployeeTimeCardPaceController.FilterOption> options =
      new List<EmployeeTimeCardPaceController.FilterOption>();
    for (AggregateResult ar : [
      SELECT
        Employee__c empId,
        Employee__r.Name empName,
        Company_Name__c companyName,
        Employee__r.Department empDepartment
      FROM Employee_Time_Card__c
      WHERE Employee__c != NULL AND Employee__r.IsActive = TRUE
      GROUP BY Employee__c, Employee__r.Name, Company_Name__c, Employee__r.Department
      ORDER BY Employee__r.Name ASC
      LIMIT 500
    ]) {
      EmployeeTimeCardPaceController.FilterOption opt = new EmployeeTimeCardPaceController.FilterOption();
      opt.value = (String) ar.get('empId');
      opt.label = (String) ar.get('empName');
      opt.company = (String) ar.get('companyName');
      opt.businessSegment = (String) ar.get('empDepartment');
      options.add(opt);
    }
    return options;
  }

  public static List<EmployeeTimeCardPaceController.FilterOption> loadCompanyFilterOptions() {
    return loadDistinctOptions('Company_Name__c');
  }

  public static List<EmployeeTimeCardPaceController.FilterOption> loadBusinessSegmentFilterOptions() {
    return loadDistinctOptions('Employee__r.Department');
  }

  private static List<EmployeeTimeCardPaceController.FilterOption> loadDistinctOptions(String groupField) {
    List<EmployeeTimeCardPaceController.FilterOption> options =
      new List<EmployeeTimeCardPaceController.FilterOption>();
    String soql =
      'SELECT ' + groupField + ' val FROM Employee_Time_Card__c WHERE Employee__c != NULL AND ' +
      groupField + ' != NULL GROUP BY ' + groupField + ' ORDER BY ' + groupField + ' ASC LIMIT 200';
    for (AggregateResult ar : Database.query(soql)) {
      String val = (String) ar.get('val');
      if (String.isBlank(val)) {
        continue;
      }
      EmployeeTimeCardPaceController.FilterOption opt = new EmployeeTimeCardPaceController.FilterOption();
      opt.value = val;
      opt.label = val;
      options.add(opt);
    }
    return options;
  }

  public static EmployeeTimeCardPaceService.PaceTeamGridResult loadTeamGrid(
    Integer year,
    Integer month,
    Integer page,
    Integer pageSize,
    EmployeeTimeCardPaceController.TeamGridFilters filters
  ) {
    Date monthStart = Date.newInstance(year, month, 1);
    Date monthEnd = monthStart.addMonths(1).addDays(-1);
    Integer safePage = page == null || page < 1 ? 1 : page;
    Integer safePageSize = pageSize == null || pageSize < 1 ? 25 : pageSize;

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
        Id,
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

    List<EmployeeTimeCardPaceService.PaceTeamRow> allRows = new List<EmployeeTimeCardPaceService.PaceTeamRow>();
    for (Employee_Time_Card__c card : cards) {
      List<Employee_Time_Card_Day_Entry__c> entries = entriesByCard.containsKey(card.Id)
        ? entriesByCard.get(card.Id)
        : new List<Employee_Time_Card_Day_Entry__c>();
      allRows.add(EmployeeTimeCardPaceService.buildTeamRow(card, entries, Date.today()));
    }

    List<EmployeeTimeCardPaceService.PaceTeamRow> filtered = applyFilters(allRows, filters);
    sortRows(filtered, filters);

    Integer totalCount = filtered.size();
    Integer offset = (safePage - 1) * safePageSize;
    Integer endIndex = Math.min(offset + safePageSize, totalCount);
    List<EmployeeTimeCardPaceService.PaceTeamRow> pageRows = new List<EmployeeTimeCardPaceService.PaceTeamRow>();
    for (Integer i = offset; i < endIndex; i++) {
      pageRows.add(filtered[i]);
    }

    EmployeeTimeCardPaceService.PaceTeamGridResult grid = new EmployeeTimeCardPaceService.PaceTeamGridResult();
    grid.rows = pageRows;
    grid.totalCount = totalCount;
    grid.page = safePage;
    grid.pageSize = safePageSize;
    grid.hasMore = offset + pageRows.size() < totalCount;
    return grid;
  }

  private static List<EmployeeTimeCardPaceService.PaceTeamRow> applyFilters(
    List<EmployeeTimeCardPaceService.PaceTeamRow> rows,
    EmployeeTimeCardPaceController.TeamGridFilters filters
  ) {
    if (filters == null) {
      return rows;
    }
    List<EmployeeTimeCardPaceService.PaceTeamRow> filtered = new List<EmployeeTimeCardPaceService.PaceTeamRow>();
    for (EmployeeTimeCardPaceService.PaceTeamRow row : rows) {
      if (matchesFilters(row, filters)) {
        filtered.add(row);
      }
    }
    return filtered;
  }

  private static Boolean matchesFilters(
    EmployeeTimeCardPaceService.PaceTeamRow row,
    EmployeeTimeCardPaceController.TeamGridFilters filters
  ) {
    if (String.isNotBlank(filters.paceStatus) && filters.paceStatus != ALL_VALUE) {
      if (row.overallPaceStatus != filters.paceStatus) {
        return false;
      }
    }
    if (String.isNotBlank(filters.company) && filters.company != ALL_VALUE) {
      if (row.employeeCompany != filters.company) {
        return false;
      }
    }
    if (String.isNotBlank(filters.businessSegment) && filters.businessSegment != ALL_VALUE) {
      if (row.businessSegment != filters.businessSegment) {
        return false;
      }
    }
    Decimal callRate = row.callRatePercent != null ? row.callRatePercent : 0;
    if (filters.minCallRate != null && callRate < filters.minCallRate) {
      return false;
    }
    if (filters.maxCallRate != null && callRate > filters.maxCallRate) {
      return false;
    }
    Decimal revPct = row.projectedWalkInRevenueAchPercent != null
      ? row.projectedWalkInRevenueAchPercent
      : 0;
    if (filters.minRevPercent != null && revPct < filters.minRevPercent) {
      return false;
    }
    if (filters.maxRevPercent != null && revPct > filters.maxRevPercent) {
      return false;
    }
    return true;
  }

  private static void sortRows(
    List<EmployeeTimeCardPaceService.PaceTeamRow> rows,
    EmployeeTimeCardPaceController.TeamGridFilters filters
  ) {
    Boolean ascending = filters == null ||
      String.isBlank(filters.sortDirection) ||
      filters.sortDirection == 'asc';
    rows.sort(new NameRowComparator(ascending));
  }

  private class NameRowComparator implements Comparator<EmployeeTimeCardPaceService.PaceTeamRow> {
    private Boolean ascending;

    NameRowComparator(Boolean ascending) {
      this.ascending = ascending;
    }

    public Integer compare(
      EmployeeTimeCardPaceService.PaceTeamRow a,
      EmployeeTimeCardPaceService.PaceTeamRow b
    ) {
      String nameA = a.employeeName != null ? a.employeeName : '';
      String nameB = b.employeeName != null ? b.employeeName : '';
      Integer cmp = nameA.toLowerCase().compareTo(nameB.toLowerCase());
      if (cmp == 0) {
        return 0;
      }
      return ascending ? cmp : -cmp;
    }
  }
}
