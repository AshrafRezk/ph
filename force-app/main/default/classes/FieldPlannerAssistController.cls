public with sharing class FieldPlannerAssistController {
  public class WeeklyRecommendationRow {
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public Decimal targetVisitFrequency;
    @AuraEnabled public Decimal actualVisits;
    @AuraEnabled public Decimal visitGap;
    @AuraEnabled public String frequencyStatus;
    @AuraEnabled public Integer plannedCountThisWeek;
    @AuraEnabled public Boolean plannedThisWeek;
    @AuraEnabled public String reason;
    @AuraEnabled public Integer rank;
  }

  public class WeeklyPlanForecast {
    @AuraEnabled public Integer plannedVisitCount;
    @AuraEnabled public Integer remainingWorkingDays;
    @AuraEnabled public Decimal dailyFrequency;
    @AuraEnabled public String paceLabel;
    @AuraEnabled public Integer recommendationCount;
    @AuraEnabled public Decimal projectedDailyIfAdded;
    @AuraEnabled public Integer dailyCallTarget;
    @AuraEnabled public Integer weeklyTarget;
    @AuraEnabled public Integer additionalCallsNeeded;
  }

  public class WeeklyPlanRecommendations {
    @AuraEnabled public List<WeeklyRecommendationRow> recommendations;
    @AuraEnabled public WeeklyPlanForecast forecast;
  }

  public class CopyWeekResult {
    @AuraEnabled public Integer createdCount;
    @AuraEnabled public Integer skippedCount;
    @AuraEnabled public Integer errorCount;
    @AuraEnabled public List<FieldPlannerController.VisitSummary> visits;
    @AuraEnabled public List<CopyIssue> issues;
  }

  /** One source visit that was not copied, with the reason (skip or save error). */
  public class CopyIssue {
    @AuraEnabled public Id sourceVisitId;
    @AuraEnabled public String accountName;
    @AuraEnabled public Date sourceDate;
    @AuraEnabled public Date targetDate;
    @AuraEnabled public Boolean isError;
    @AuraEnabled public String message;
  }

  public class TotSummary {
    @AuraEnabled public Id id;
    @AuraEnabled public String name;
    @AuraEnabled public String typeLabel;
    @AuraEnabled public String spanType;
    @AuraEnabled public String stage;
    @AuraEnabled public DateTime startDateTime;
    @AuraEnabled public DateTime endDateTime;
    @AuraEnabled public Boolean isFullDay;
  }

  @AuraEnabled(cacheable=true)
  public static WeeklyPlanRecommendations getWeeklyPlanRecommendations(
    Date weekStart,
    Date weekEnd,
    Id contextUserId
  ) {
    if (weekStart == null || weekEnd == null) {
      throw PlannerUserMessage.aura('Week start and end dates are required.');
    }
    Id resolvedUserId = contextUserId == null ? UserInfo.getUserId() : contextUserId;
    FieldPlannerController.PlannerPayload weekData = FieldPlannerController.getPlannerData(
      weekStart,
      weekEnd,
      resolvedUserId
    );
    List<FieldPlannerController.VisitSummary> weekVisits =
      weekData == null || weekData.visits == null
        ? new List<FieldPlannerController.VisitSummary>()
        : weekData.visits;

    Map<Id, Integer> plannedByAccount = new Map<Id, Integer>();
    Map<Id, String> accountNames = new Map<Id, String>();
    Integer plannedVisitCount = 0;
    for (FieldPlannerController.VisitSummary visit : weekVisits) {
      if (visit == null || visit.accountId == null || visit.status == 'Cancelled') {
        continue;
      }
      plannedVisitCount++;
      Integer count = plannedByAccount.containsKey(visit.accountId)
        ? plannedByAccount.get(visit.accountId)
        : 0;
      plannedByAccount.put(visit.accountId, count + 1);
      if (String.isNotBlank(visit.accountName)) {
        accountNames.put(visit.accountId, visit.accountName);
      }
    }

    Integer remainingWorkingDays = 0;
    Date cursor = weekStart;
    Date today = Date.today();
    while (cursor <= weekEnd) {
      if (WorkingCalendarUtil.isWorkingDay(cursor) && cursor >= today) {
        remainingWorkingDays++;
      }
      cursor = cursor.addDays(1);
    }
    if (remainingWorkingDays == 0) {
      remainingWorkingDays = 1;
    }

    List<WeeklyRecommendationRow> top = buildTargetRecommendations(
      resolvedUserId,
      plannedByAccount
    );

    WeeklyPlanForecast forecast = new WeeklyPlanForecast();
    forecast.plannedVisitCount = plannedVisitCount;
    forecast.remainingWorkingDays = remainingWorkingDays;
    forecast.dailyFrequency = ((Decimal) plannedVisitCount / remainingWorkingDays)
      .setScale(1, RoundingMode.HALF_UP);
    forecast.recommendationCount = top.size();
    Integer unplannedRecs = 0;
    for (WeeklyRecommendationRow row : top) {
      if (row.plannedThisWeek != true) {
        unplannedRecs++;
      }
    }
    forecast.projectedDailyIfAdded = ((Decimal) (plannedVisitCount + unplannedRecs) / remainingWorkingDays)
      .setScale(1, RoundingMode.HALF_UP);
    forecast.paceLabel = forecast.dailyFrequency >= 4
      ? 'On track'
      : (forecast.dailyFrequency >= 2.5 ? 'Needs a few more visits' : 'Behind pace');

    Integer dailyCallTarget = resolveDailyCallTarget(resolvedUserId, weekStart);
    Integer workingDaysInWeek = countWorkingDays(weekStart, weekEnd);
    Integer weeklyTarget = dailyCallTarget * Math.max(1, workingDaysInWeek);
    forecast.dailyCallTarget = dailyCallTarget;
    forecast.weeklyTarget = weeklyTarget;
    forecast.additionalCallsNeeded = Math.max(0, weeklyTarget - plannedVisitCount);

    WeeklyPlanRecommendations result = new WeeklyPlanRecommendations();
    result.recommendations = top;
    result.forecast = forecast;
    return result;
  }

  private static Integer resolveDailyCallTarget(Id employeeId, Date referenceDate) {
    Integer fallback = 8;
    if (employeeId == null || referenceDate == null) {
      return fallback;
    }
    Date monthStart = referenceDate.toStartOfMonth();
    Date monthEnd = monthStart.addMonths(1).addDays(-1);
    Integer workingDaysInMonth = countWorkingDays(monthStart, monthEnd);
    Decimal visitTarget = null;
    List<Employee_Time_Card__c> cards = [
      SELECT Visit_Target__c
      FROM Employee_Time_Card__c
      WHERE Employee__c = :employeeId AND Time_Card_Month_Start_Date__c = :monthStart
      WITH USER_MODE
      LIMIT 1
    ];
    if (!cards.isEmpty()) {
      visitTarget = cards[0].Visit_Target__c;
    }
    if (visitTarget != null && visitTarget > 0 && workingDaysInMonth > 0) {
      return Math.max(1, Integer.valueOf(Math.ceil(visitTarget / workingDaysInMonth)));
    }
    return fallback;
  }

  private static Integer countWorkingDays(Date rangeStart, Date rangeEnd) {
    if (rangeStart == null || rangeEnd == null || rangeStart > rangeEnd) {
      return 0;
    }
    Integer total = 0;
    Date cursor = rangeStart;
    while (cursor <= rangeEnd) {
      if (WorkingCalendarUtil.isWorkingDay(cursor)) {
        total++;
      }
      cursor = cursor.addDays(1);
    }
    return total;
  }

  @TestVisible
  private static List<WeeklyRecommendationRow> buildTargetRecommendations(
    Id resolvedUserId,
    Map<Id, Integer> plannedByAccount
  ) {
    if (resolvedUserId == null || plannedByAccount == null) {
      return new List<WeeklyRecommendationRow>();
    }
    // Frequency gaps come from Employee_Time_Card_Account_Target__c when the monthly
    // timecard exists. Empty list is a valid “no open gaps” response.
    return loadFrequencyGapRows(resolvedUserId, plannedByAccount);
  }

  private static List<WeeklyRecommendationRow> loadFrequencyGapRows(
    Id resolvedUserId,
    Map<Id, Integer> plannedByAccount
  ) {
    if (resolvedUserId == null || plannedByAccount == null) {
      return new List<WeeklyRecommendationRow>();
    }
    List<WeeklyRecommendationRow> top = new List<WeeklyRecommendationRow>();
    Date monthStart = Date.today().toStartOfMonth();
    Integer matchingCards = [
      SELECT COUNT()
      FROM Employee_Time_Card__c
      WHERE Employee__c = :resolvedUserId AND Time_Card_Month_Start_Date__c = :monthStart
    ];
    if (matchingCards == 0) {
      return top;
    }
    for (Employee_Time_Card_Account_Target__c target : [
      SELECT
        Account__c,
        Account__r.Name,
        Target_Visit_Frequency__c,
        Actual_Visits__c,
        Frequency_Status__c
      FROM Employee_Time_Card_Account_Target__c
      WHERE
        Employee_Time_Card__r.Employee__c = :resolvedUserId
        AND Employee_Time_Card__r.Time_Card_Month_Start_Date__c = :monthStart
        AND Account__c != NULL
      WITH USER_MODE
      ORDER BY Frequency_Status__c ASC NULLS LAST
      LIMIT 40
    ]) {
      Boolean isLcf = target.Frequency_Status__c == 'LCF';
      Decimal targetFreq = target.Target_Visit_Frequency__c;
      Decimal actualVisits = target.Actual_Visits__c == null ? 0 : target.Actual_Visits__c;
      Boolean belowTarget = targetFreq != null && actualVisits < targetFreq;
      if (!isLcf && !belowTarget) {
        continue;
      }
      Integer plannedCount = plannedByAccount.containsKey(target.Account__c)
        ? plannedByAccount.get(target.Account__c)
        : 0;
      Decimal gap = (targetFreq == null ? 0 : targetFreq) - actualVisits;
      if (plannedCount > 0 && gap <= 0) {
        continue;
      }
      WeeklyRecommendationRow row = new WeeklyRecommendationRow();
      row.accountId = target.Account__c;
      row.accountName = target.Account__r.Name;
      row.targetVisitFrequency = targetFreq;
      row.actualVisits = actualVisits;
      row.visitGap = gap;
      row.frequencyStatus = target.Frequency_Status__c;
      row.plannedCountThisWeek = plannedCount;
      row.plannedThisWeek = plannedCount > 0;
      row.reason = row.plannedThisWeek == true
        ? 'Already on this week — keep coverage'
        : (isLcf ? 'Behind frequency (LCF) — plan a draft visit' : 'Below target — add to this week');
      row.rank = top.size() + 1;
      top.add(row);
      if (top.size() >= 12) {
        break;
      }
    }
    return top;
  }

  @AuraEnabled
  public static List<FieldPlannerController.VisitSummary> copyDayVisits(
    Date sourceDate,
    Date targetDate,
    Id contextUserId
  ) {
    return copyDayVisitsInternal(sourceDate, targetDate, contextUserId).visits;
  }

  @AuraEnabled
  public static CopyWeekResult copyWeekVisits(
    Date targetWeekStart,
    Integer weekCount,
    Id contextUserId
  ) {
    if (targetWeekStart == null) {
      throw PlannerUserMessage.aura('Target week start is required.');
    }
    if (weekCount == null || (weekCount != 1 && weekCount != 2)) {
      throw PlannerUserMessage.aura('Choose 1 week or 2 weeks to copy.');
    }
    Id resolvedUserId = contextUserId == null ? UserInfo.getUserId() : contextUserId;
    if (resolvedUserId != UserInfo.getUserId()) {
      throw PlannerUserMessage.aura('You cannot edit another rep\'s planner.');
    }

    Integer daySpan = 7 * weekCount;
    Date sourceWeekStart = targetWeekStart.addDays(-daySpan);
    CopyWeekResult result = new CopyWeekResult();
    result.createdCount = 0;
    result.skippedCount = 0;
    result.errorCount = 0;
    result.visits = new List<FieldPlannerController.VisitSummary>();
    result.issues = new List<CopyIssue>();

    for (Integer offset = 0; offset < daySpan; offset++) {
      Date sourceDate = sourceWeekStart.addDays(offset);
      Date targetDate = targetWeekStart.addDays(offset);
      if (WorkingCalendarUtil.isBlockedDay(targetDate)) {
        continue;
      }
      DayCopyResult dayResult = copyDayVisitsInternal(sourceDate, targetDate, resolvedUserId);
      result.visits.addAll(dayResult.visits);
      result.issues.addAll(dayResult.issues);
      result.createdCount += dayResult.visits.size();
      result.skippedCount += dayResult.skippedCount;
      result.errorCount += dayResult.errorCount;
    }
    return result;
  }

  private class DayCopyResult {
    public List<FieldPlannerController.VisitSummary> visits = new List<FieldPlannerController.VisitSummary>();
    public List<CopyIssue> issues = new List<CopyIssue>();
    public Integer skippedCount = 0;
    public Integer errorCount = 0;

    void skip(FieldPlannerController.VisitSummary source, Date sourceDate, Date targetDate, String message, Boolean isError) {
      CopyIssue issue = new CopyIssue();
      issue.sourceVisitId = source == null ? null : source.id;
      issue.accountName = source == null ? null : source.accountName;
      issue.sourceDate = sourceDate;
      issue.targetDate = targetDate;
      issue.isError = isError;
      issue.message = message;
      issues.add(issue);
      skippedCount++;
      if (isError) {
        errorCount++;
      }
    }
  }

  private static DayCopyResult copyDayVisitsInternal(
    Date sourceDate,
    Date targetDate,
    Id contextUserId
  ) {
    DayCopyResult result = new DayCopyResult();
    if (sourceDate == null || targetDate == null) {
      throw PlannerUserMessage.aura('Pick a source day and a target day.');
    }
    if (sourceDate == targetDate) {
      throw PlannerUserMessage.aura('Source and target days must be different.');
    }
    if (WorkingCalendarUtil.isBlockedDay(targetDate)) {
      throw PlannerUserMessage.aura(
        PublicHolidayService.isPublicHoliday(targetDate)
          ? 'Visits cannot be scheduled on a public holiday.'
          : 'Visits can only be scheduled on working days (' +
            PlannerRulesService.workingDaysLabelForUser(contextUserId == null ? UserInfo.getUserId() : contextUserId) +
            ').'
      );
    }
    Id resolvedUserId = contextUserId == null ? UserInfo.getUserId() : contextUserId;
    if (resolvedUserId != UserInfo.getUserId()) {
      throw PlannerUserMessage.aura('You cannot edit another rep\'s planner.');
    }

    FieldPlannerController.PlannerPayload sourceData = FieldPlannerController.getPlannerData(
      sourceDate,
      sourceDate,
      resolvedUserId
    );
    FieldPlannerController.PlannerPayload targetData = FieldPlannerController.getPlannerData(
      targetDate,
      targetDate,
      resolvedUserId
    );
    List<FieldPlannerController.VisitSummary> sourceVisits =
      sourceData == null || sourceData.visits == null
        ? new List<FieldPlannerController.VisitSummary>()
        : sourceData.visits;
    Set<Id> targetAccountIds = new Set<Id>();
    if (targetData != null && targetData.visits != null) {
      for (FieldPlannerController.VisitSummary existing : targetData.visits) {
        if (existing != null && existing.accountId != null && existing.status != 'Cancelled') {
          targetAccountIds.add(existing.accountId);
        }
      }
    }

    // D1-03: Completed, Scheduled and other open visits copy as Drafts; only Cancelled ones are skipped.
    for (FieldPlannerController.VisitSummary source : sourceVisits) {
      if (source == null || source.accountId == null) {
        result.skip(source, sourceDate, targetDate, 'Visit has no account.', false);
        continue;
      }
      if (source.status == 'Cancelled') {
        result.skip(source, sourceDate, targetDate, 'Cancelled visits are not copied.', false);
        continue;
      }
      if (targetAccountIds.contains(source.accountId)) {
        result.skip(source, sourceDate, targetDate, 'Already has a visit on the target day.', false);
        continue;
      }
      if (source.startDateTime == null || source.endDateTime == null) {
        result.skip(source, sourceDate, targetDate, 'Visit has no start or end time.', false);
        continue;
      }
      Integer durationSeconds = Integer.valueOf(
        (source.endDateTime.getTime() - source.startDateTime.getTime()) / 1000
      );
      if (durationSeconds <= 0) {
        durationSeconds = 30 * 60;
      }
      DateTime newStart = DateTime.newInstance(targetDate, source.startDateTime.time());
      DateTime newEnd = newStart.addSeconds(durationSeconds);
      try {
        result.visits.add(
          FieldPlannerController.upsertVisit(
            null,
            source.accountId,
            newStart,
            newEnd,
            'Draft',
            'Planned (Automatically)',
            null,
            source.zetaProjectId,
            source.visitObjective
          )
        );
        targetAccountIds.add(source.accountId);
      } catch (Exception ex) {
        result.skip(source, sourceDate, targetDate, PlannerUserMessage.fromException(ex), true);
      }
    }
    return result;
  }

  @AuraEnabled
  public static TotSummary updateTimeOff(Id timeOffId, DateTime endDateTime) {
    if (timeOffId == null) {
      throw PlannerUserMessage.aura('Time off Id is required.');
    }
    if (endDateTime == null) {
      throw PlannerUserMessage.aura('End date/time is required.');
    }
    List<Time_Off_Request__c> rows = [
      SELECT
        Id,
        Name,
        Type__c,
        Span_Type__c,
        Stage__c,
        Start_Date_Time__c,
        End_Date_Time__c
      FROM Time_Off_Request__c
      WHERE Id = :timeOffId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw PlannerUserMessage.aura('Time off request not found.');
    }
    Time_Off_Request__c request = rows[0];
    if (request.Span_Type__c == 'Full_Day') {
      throw PlannerUserMessage.aura('Full-day time off cannot be resized. Change it to hours first.');
    }
    if (request.Start_Date_Time__c == null || endDateTime <= request.Start_Date_Time__c) {
      throw PlannerUserMessage.aura('End time must be after start time.');
    }
    Long seconds = (endDateTime.getTime() - request.Start_Date_Time__c.getTime()) / 1000;
    Decimal hours = (Decimal.valueOf(seconds) / 3600).setScale(2, RoundingMode.HALF_UP);
    if (hours < 0.25) {
      throw PlannerUserMessage.aura('Time off must be at least 15 minutes.');
    }
    request.End_Date_Time__c = endDateTime;
    request.Span_Type__c = 'Hours';
    request.Span_Duration__c = hours;
    request.Span_Duration_Select__c = hours == hours.setScale(0, RoundingMode.HALF_UP)
      ? String.valueOf(hours.intValue())
      : String.valueOf(hours);
    update as user request;

    TotSummary summary = new TotSummary();
    summary.id = request.Id;
    summary.name = request.Name;
    summary.typeLabel = request.Type__c;
    summary.spanType = request.Span_Type__c;
    summary.stage = request.Stage__c;
    summary.startDateTime = request.Start_Date_Time__c;
    summary.endDateTime = request.End_Date_Time__c;
    summary.isFullDay = false;
    return summary;
  }
}