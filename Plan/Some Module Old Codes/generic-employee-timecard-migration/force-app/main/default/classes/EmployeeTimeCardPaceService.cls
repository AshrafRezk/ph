/**
 * Walk-in pace calculations for generic Employee Time Card migration (no brand/commission).
 */
public with sharing class EmployeeTimeCardPaceService {

  public static final String STATUS_AHEAD = 'ahead';
  public static final String STATUS_ON_TRACK = 'on_track';
  public static final String STATUS_BEHIND = 'behind';
  public static final String STATUS_CRITICAL = 'critical';
  public static final String STATUS_NOT_APPLICABLE = 'not_applicable';

  private static final Decimal ON_TRACK_THRESHOLD = 90;
  private static final Decimal CRITICAL_THRESHOLD = 50;
  private static final Integer ON_FIRE_STREAK_DAYS = 5;

  public class PaceMetric {
    @AuraEnabled public String metricKey { get; set; }
    @AuraEnabled public String label { get; set; }
    @AuraEnabled public String channelType { get; set; }
    @AuraEnabled public Decimal actual { get; set; }
    @AuraEnabled public Decimal target { get; set; }
    @AuraEnabled public Decimal currentAchPercent { get; set; }
    @AuraEnabled public Decimal projectedActual { get; set; }
    @AuraEnabled public Decimal projectedAchPercent { get; set; }
    @AuraEnabled public String paceStatus { get; set; }
    @AuraEnabled public String valueType { get; set; }
  }

  public class PaceAction {
    @AuraEnabled public String title { get; set; }
    @AuraEnabled public String body { get; set; }
    @AuraEnabled public Integer priority { get; set; }
    @AuraEnabled public String iconName { get; set; }
  }

  public class PaceBadge {
    @AuraEnabled public String badgeKey { get; set; }
    @AuraEnabled public String label { get; set; }
    @AuraEnabled public String description { get; set; }
    @AuraEnabled public String earnedReason { get; set; }
    @AuraEnabled public String howToEarn { get; set; }
    @AuraEnabled public String criteria { get; set; }
    @AuraEnabled public Boolean earned { get; set; }
    @AuraEnabled public String iconName { get; set; }
  }

  public class PaceWorkingDays {
    @AuraEnabled public Integer elapsedWorkingDays { get; set; }
    @AuraEnabled public Integer totalWorkingDays { get; set; }
    @AuraEnabled public Decimal paceRatio { get; set; }
    @AuraEnabled public Integer dayOfMonth { get; set; }
    @AuraEnabled public Integer cumulativeVisits { get; set; }
    @AuraEnabled public Decimal visitsRunRateTarget { get; set; }
    @AuraEnabled public Decimal visitsRunRatePercent { get; set; }
  }

  public class PaceActivitySummary {
    @AuraEnabled public Integer visitStreakDays { get; set; }
    @AuraEnabled public Integer totalVisits { get; set; }
    @AuraEnabled public Integer amVisits { get; set; }
    @AuraEnabled public Integer pmVisits { get; set; }
    @AuraEnabled public Integer coachingVisits { get; set; }
    @AuraEnabled public Decimal timeOffDays { get; set; }
    @AuraEnabled public Decimal totDays { get; set; }
    @AuraEnabled public Decimal totDaysExcludingWeekends { get; set; }
    @AuraEnabled public Integer callRateActual { get; set; }
    @AuraEnabled public Decimal callRateTarget { get; set; }
    @AuraEnabled public Decimal callRatePercent { get; set; }
    @AuraEnabled public String callRateStatus { get; set; }
  }

  public class PaceDetailResult {
    @AuraEnabled public Id timeCardId { get; set; }
    @AuraEnabled public Id employeeUserId { get; set; }
    @AuraEnabled public String employeeName { get; set; }
    @AuraEnabled public String employeeCompany { get; set; }
    @AuraEnabled public String employeeReportDetails { get; set; }
    @AuraEnabled public Integer year { get; set; }
    @AuraEnabled public Integer month { get; set; }
    @AuraEnabled public PaceWorkingDays workingDays { get; set; }
    @AuraEnabled public PaceMetric walkInRevenue { get; set; }
    @AuraEnabled public PaceMetric walkInVisits { get; set; }
    @AuraEnabled public List<PaceAction> nextBestActions { get; set; }
    @AuraEnabled public List<PaceBadge> badges { get; set; }
    @AuraEnabled public Integer streakDays { get; set; }
    @AuraEnabled public PaceActivitySummary activitySummary { get; set; }
  }

  public class PaceTeamRow {
    @AuraEnabled public Id timeCardId { get; set; }
    @AuraEnabled public Id employeeUserId { get; set; }
    @AuraEnabled public String employeeName { get; set; }
    @AuraEnabled public String employeeCompany { get; set; }
    @AuraEnabled public String businessSegment { get; set; }
    @AuraEnabled public String overallPaceStatus { get; set; }
    @AuraEnabled public Decimal projectedWalkInRevenueAchPercent { get; set; }
    @AuraEnabled public Decimal projectedWalkInVisitsAchPercent { get; set; }
    @AuraEnabled public Integer badgeCountEarned { get; set; }
    @AuraEnabled public Integer streakDays { get; set; }
    @AuraEnabled public Decimal callRatePercent { get; set; }
    @AuraEnabled public Decimal timeOffDays { get; set; }
  }

  public class PaceTeamGridResult {
    @AuraEnabled public List<PaceTeamRow> rows { get; set; }
    @AuraEnabled public Integer totalCount { get; set; }
    @AuraEnabled public Integer page { get; set; }
    @AuraEnabled public Integer pageSize { get; set; }
    @AuraEnabled public Boolean hasMore { get; set; }
  }

  public static PaceDetailResult buildPaceDetail(
    Employee_Time_Card__c card,
    List<Employee_Time_Card_Day_Entry__c> dayEntries,
    Date asOfDate
  ) {
    PaceDetailResult result = new PaceDetailResult();
    if (card == null) {
      return result;
    }

    Date effectiveAsOf = asOfDate == null ? Date.today() : asOfDate;
    PaceWorkingDays wd = computeWorkingDays(card, dayEntries, effectiveAsOf);

    result.timeCardId = card.Id;
    result.employeeUserId = card.Employee__c;
    result.employeeName = card.Employee__r != null ? card.Employee__r.Name : null;
    result.employeeCompany = card.Company_Name__c;
    result.employeeReportDetails = getQueriedReportDetails(card);
    result.year = card.Time_Card_Month_Start_Date__c != null
      ? card.Time_Card_Month_Start_Date__c.year()
      : effectiveAsOf.year();
    result.month = card.Time_Card_Month_Start_Date__c != null
      ? card.Time_Card_Month_Start_Date__c.month()
      : effectiveAsOf.month();
    result.workingDays = wd;

    result.walkInRevenue = buildMetric(
      'walkin_rev',
      'Walk-in Revenue',
      'walkin',
      card.Walk_in_Revenue__c,
      card.Walk_in_Revenue_Target__c,
      card.Walk_in_Revenue_Ach__c,
      wd.paceRatio,
      true
    );
    result.walkInVisits = buildMetric(
      'walkin_vis',
      'Walk-in Visits',
      'walkin',
      card.Walk_in_Visits__c,
      card.Walk_in_Visits_Target__c,
      card.Walk_in_Visits_Ach__c,
      wd.paceRatio,
      true
    );

    Date monthStart = card.Time_Card_Month_Start_Date__c;
    result.activitySummary = buildActivitySummary(dayEntries, effectiveAsOf, monthStart);
    applyCallRateFromWorkingDays(result.activitySummary, wd);
    result.streakDays = result.activitySummary != null ? result.activitySummary.visitStreakDays : 0;
    result.badges = buildBadges(result, wd);
    result.nextBestActions = buildNextBestActions(result, wd);
    return result;
  }

  public static PaceTeamRow buildTeamRow(
    Employee_Time_Card__c card,
    List<Employee_Time_Card_Day_Entry__c> dayEntries,
    Date asOfDate
  ) {
    PaceDetailResult detail = buildPaceDetail(card, dayEntries, asOfDate);
    PaceTeamRow row = new PaceTeamRow();
    row.timeCardId = detail.timeCardId;
    row.employeeUserId = detail.employeeUserId;
    row.employeeName = detail.employeeName;
    row.employeeCompany = detail.employeeCompany;
    row.businessSegment = card.Employee__r != null ? card.Employee__r.Department : null;
    row.projectedWalkInRevenueAchPercent = detail.walkInRevenue != null
      ? detail.walkInRevenue.projectedAchPercent
      : 0;
    row.projectedWalkInVisitsAchPercent = detail.walkInVisits != null
      ? detail.walkInVisits.projectedAchPercent
      : 0;
    row.streakDays = detail.streakDays;
    row.callRatePercent = detail.activitySummary != null ? detail.activitySummary.callRatePercent : 0;
    row.timeOffDays = detail.activitySummary != null ? detail.activitySummary.timeOffDays : 0;
    row.badgeCountEarned = countEarnedBadges(detail.badges);
    row.overallPaceStatus = worstStatus(
      new List<String>{
        detail.walkInRevenue != null ? detail.walkInRevenue.paceStatus : STATUS_BEHIND,
        detail.walkInVisits != null ? detail.walkInVisits.paceStatus : STATUS_BEHIND
      }
    );
    return row;
  }

  public static PaceWorkingDays computeWorkingDays(
    Employee_Time_Card__c card,
    List<Employee_Time_Card_Day_Entry__c> dayEntries,
    Date asOfDate
  ) {
    PaceWorkingDays wd = new PaceWorkingDays();
    wd.elapsedWorkingDays = 0;
    wd.totalWorkingDays = 0;
    wd.cumulativeVisits = 0;
    Decimal dailyTarget = nvl(card.Target_Daily_Visits__c);
    Decimal runRateTargetSum = 0;

    if (dayEntries != null && !dayEntries.isEmpty()) {
      for (Employee_Time_Card_Day_Entry__c entry : dayEntries) {
        Decimal calDays = nvl(entry.Calendar_Working_Days__c);
        wd.totalWorkingDays += calDays.intValue();
        if (entry.Date__c != null && entry.Date__c <= asOfDate) {
          wd.elapsedWorkingDays += calDays.intValue();
          wd.cumulativeVisits += nvl(entry.Total_Visits__c).intValue();
        }
      }
    } else if (card.Time_Card_Month_Start_Date__c != null && card.Time_Card_Month_End_Date__c != null) {
      String department = card.Employee__r != null ? card.Employee__r.Department : null;
      Date cursor = card.Time_Card_Month_Start_Date__c;
      while (cursor <= card.Time_Card_Month_End_Date__c) {
        if (!EmployeeTimeCardFlowHelper.isWeekendDay(cursor, department)) {
          wd.totalWorkingDays++;
          if (cursor <= asOfDate) {
            wd.elapsedWorkingDays++;
          }
        }
        cursor = cursor.addDays(1);
      }
    }

    if (wd.elapsedWorkingDays < 1) {
      wd.elapsedWorkingDays = 1;
    }
    if (wd.totalWorkingDays < wd.elapsedWorkingDays) {
      wd.totalWorkingDays = wd.elapsedWorkingDays;
    }

    wd.paceRatio = wd.totalWorkingDays > 0
      ? Decimal.valueOf(wd.elapsedWorkingDays) / Decimal.valueOf(wd.totalWorkingDays)
      : 1;
    if (asOfDate >= card.Time_Card_Month_End_Date__c && card.Time_Card_Month_End_Date__c != null) {
      wd.paceRatio = 1;
    }

    wd.dayOfMonth = asOfDate.day();
    wd.visitsRunRateTarget = runRateTargetSum > 0 ? runRateTargetSum : dailyTarget * wd.elapsedWorkingDays;
    wd.visitsRunRatePercent = wd.visitsRunRateTarget > 0
      ? (nvl(wd.cumulativeVisits) / wd.visitsRunRateTarget) * 100
      : 0;
    return wd;
  }

  public static PaceMetric buildMetric(
    String metricKey,
    String label,
    String channelType,
    Decimal actual,
    Decimal target,
    Decimal storedAch,
    Decimal paceRatio,
    Boolean applicable
  ) {
    PaceMetric m = new PaceMetric();
    m.metricKey = metricKey;
    m.label = label;
    m.channelType = channelType;
    m.actual = nvl(actual);
    m.target = nvl(target);
    m.currentAchPercent = storedAch != null
      ? nvl(storedAch)
      : EmployeeTimeCardAchievementService.achievementPercent(m.actual, m.target);
    Decimal safeRatio = paceRatio != null && paceRatio > 0 ? paceRatio : 1;
    m.projectedActual = safeRatio > 0 ? m.actual / safeRatio : m.actual;
    m.projectedAchPercent = EmployeeTimeCardAchievementService.achievementPercent(
      m.projectedActual,
      m.target
    );
    if (m.target > 0 && m.currentAchPercent > 0 && safeRatio > 0) {
      m.projectedAchPercent = m.currentAchPercent / safeRatio;
    }
    m.valueType = metricKey != null && metricKey.endsWith('_vis') ? 'count' : 'currency';
    m.paceStatus = applicable == true
      ? paceStatusFromProjected(m.projectedAchPercent)
      : STATUS_NOT_APPLICABLE;
    return m;
  }

  public static PaceActivitySummary buildActivitySummary(
    List<Employee_Time_Card_Day_Entry__c> dayEntries,
    Date asOfDate,
    Date monthStart
  ) {
    PaceActivitySummary summary = new PaceActivitySummary();
    summary.visitStreakDays = 0;
    summary.totalVisits = 0;
    summary.amVisits = 0;
    summary.pmVisits = 0;
    summary.coachingVisits = 0;
    summary.timeOffDays = 0;
    summary.totDays = 0;
    summary.totDaysExcludingWeekends = 0;

    if (dayEntries == null || dayEntries.isEmpty() || asOfDate == null) {
      return summary;
    }

    Map<Date, Employee_Time_Card_Day_Entry__c> byDate = indexDayEntriesByDate(dayEntries);
    Date earliest = monthStart != null ? monthStart : minEntryDate(byDate);
    if (earliest == null) {
      return summary;
    }

    for (Employee_Time_Card_Day_Entry__c entry : dayEntries) {
      if (entry.Date__c == null || entry.Date__c > asOfDate) {
        continue;
      }
      summary.amVisits += visitCount(entry.Planned_AM_Visits__c, entry.Unplanned_AM_Visits__c);
      summary.pmVisits += visitCount(entry.Planned_PM_Visits__c, entry.Unplanned_PM_Visits__c);
      summary.coachingVisits += visitCount(
        entry.Planned_Coaching_Visits__c,
        entry.Unplanned_Coaching_Visits__c
      );
      summary.timeOffDays += nvl(entry.Time_off_Days__c);
    }
    summary.totalVisits = summary.amVisits + summary.pmVisits + summary.coachingVisits;

    Employee_Time_Card_Day_Entry__c asOfEntry = findLatestEntryOnOrBefore(byDate, asOfDate);
    if (asOfEntry != null) {
      summary.totDays = nvl(asOfEntry.TOT_Days__c);
      summary.totDaysExcludingWeekends = nvl(asOfEntry.TOT_Days_Excluding_Weekends__c);
    }

    summary.visitStreakDays = computeVisitStreak(byDate, asOfDate, earliest);
    return summary;
  }

  public static String paceStatusFromProjected(Decimal projectedAch) {
    if (projectedAch >= 100) {
      return STATUS_AHEAD;
    }
    if (projectedAch >= ON_TRACK_THRESHOLD) {
      return STATUS_ON_TRACK;
    }
    if (projectedAch >= CRITICAL_THRESHOLD) {
      return STATUS_BEHIND;
    }
    return STATUS_CRITICAL;
  }

  public static String worstStatus(List<String> statuses) {
    String worst = STATUS_AHEAD;
    for (String s : statuses) {
      if (paceRank(s) < paceRank(worst)) {
        worst = s;
      }
    }
    return worst;
  }

  public static Integer countEarnedBadges(List<PaceBadge> badges) {
    Integer count = 0;
    if (badges == null) {
      return 0;
    }
    for (PaceBadge b : badges) {
      if (b.earned == true) {
        count++;
      }
    }
    return count;
  }

  private static void applyCallRateFromWorkingDays(PaceActivitySummary summary, PaceWorkingDays wd) {
    if (summary == null || wd == null) {
      return;
    }
    summary.callRateActual = wd.cumulativeVisits;
    summary.callRateTarget = wd.visitsRunRateTarget;
    summary.callRatePercent = wd.visitsRunRatePercent;
    summary.callRateStatus = paceStatusFromProjected(wd.visitsRunRatePercent);
  }

  private static List<PaceBadge> buildBadges(PaceDetailResult detail, PaceWorkingDays wd) {
    List<PaceBadge> badges = new List<PaceBadge>();
    Integer streak = detail.streakDays != null ? detail.streakDays : 0;
    badges.add(
      buildBadge(
        'on_fire',
        'On Fire',
        'utility:trending',
        streak >= ON_FIRE_STREAK_DAYS,
        ON_FIRE_STREAK_DAYS + '+ consecutive working days with visits',
        streak + '-day visit streak',
        'Log visits every working day to build a streak.'
      )
    );

    Decimal revProj = detail.walkInRevenue != null ? nvl(detail.walkInRevenue.projectedAchPercent) : 0;
    badges.add(
      buildBadge(
        'revenue_rocket',
        'Revenue Rocket',
        'utility:jump_to_top',
        revProj >= 100,
        '100%+ projected walk-in revenue',
        'Projected walk-in revenue is ' + revProj.setScale(0) + '% of target.',
        'Reach 100% projected walk-in revenue by month end.'
      )
    );

    Decimal visProj = detail.walkInVisits != null ? nvl(detail.walkInVisits.projectedAchPercent) : 0;
    badges.add(
      buildBadge(
        'visit_champion',
        'Visit Champion',
        'utility:trail',
        visProj >= ON_TRACK_THRESHOLD,
        '90%+ projected walk-in visits',
        'Projected walk-in visits are ' + visProj.setScale(0) + '% of target.',
        'Reach 90%+ projected walk-in visits by month end.'
      )
    );
    return badges;
  }

  private static PaceBadge buildBadge(
    String key,
    String label,
    String icon,
    Boolean earned,
    String criteria,
    String earnedReason,
    String howToEarn
  ) {
    PaceBadge b = new PaceBadge();
    b.badgeKey = key;
    b.label = label;
    b.iconName = icon;
    b.earned = earned;
    b.criteria = criteria;
    b.earnedReason = earnedReason;
    b.howToEarn = howToEarn;
    b.description = earned ? earnedReason : howToEarn;
    return b;
  }

  private static List<PaceAction> buildNextBestActions(PaceDetailResult detail, PaceWorkingDays wd) {
    List<PaceAction> actions = new List<PaceAction>();
    if (detail.walkInRevenue != null && detail.walkInRevenue.paceStatus == STATUS_CRITICAL) {
      actions.add(action(1, 'Critical revenue pace', 'Walk-in revenue is below 50% projected — prioritize top accounts.', 'utility:warning'));
    }
    if (detail.walkInVisits != null && detail.walkInVisits.paceStatus == STATUS_BEHIND) {
      actions.add(action(2, 'Boost visit pace', 'Book additional visits today to stay on track.', 'utility:event'));
    }
    if (detail.streakDays == 0) {
      actions.add(action(3, 'Rebuild your streak', 'Complete planned visits today to start a new activity streak.', 'utility:refresh'));
    }
    if (wd != null && wd.visitsRunRatePercent < 80 && wd.visitsRunRateTarget > 0) {
      actions.add(
        action(
          4,
          'Daily visits behind',
          'You are at ' + wd.visitsRunRatePercent.setScale(0) + '% of expected visits for days elapsed.',
          'utility:call'
        )
      );
    }
    return actions;
  }

  private static PaceAction action(Integer priority, String title, String body, String icon) {
    PaceAction a = new PaceAction();
    a.priority = priority;
    a.title = title;
    a.body = body;
    a.iconName = icon;
    return a;
  }

  private static Integer computeVisitStreak(
    Map<Date, Employee_Time_Card_Day_Entry__c> byDate,
    Date asOfDate,
    Date monthStart
  ) {
    if (byDate == null || byDate.isEmpty() || asOfDate == null) {
      return 0;
    }
    Date earliest = monthStart != null ? monthStart : minEntryDate(byDate);
    if (earliest == null) {
      return 0;
    }
    Date cursor = asOfDate;
    while (cursor >= earliest && !byDate.containsKey(cursor)) {
      cursor = cursor.addDays(-1);
    }
    if (cursor < earliest) {
      return 0;
    }
    Integer streak = 0;
    while (cursor >= earliest) {
      if (!byDate.containsKey(cursor)) {
        break;
      }
      Employee_Time_Card_Day_Entry__c entry = byDate.get(cursor);
      if (entry.Day_Definition__c == 'Weekend Day') {
        cursor = cursor.addDays(-1);
        continue;
      }
      if (isVisitActivityDay(entry)) {
        streak++;
        cursor = cursor.addDays(-1);
      } else {
        break;
      }
    }
    return streak;
  }

  private static Boolean isVisitActivityDay(Employee_Time_Card_Day_Entry__c entry) {
    if (entry == null) {
      return false;
    }
    if (nvl(entry.Days_with_Activities__c) >= 1) {
      return true;
    }
    return nvl(entry.Total_Visits__c) >= 1 &&
      nvl(entry.Time_off_Days__c) == 0 &&
      entry.Day_Definition__c == 'Weekday';
  }

  private static Integer visitCount(Decimal planned, Decimal unplanned) {
    return nvl(planned).intValue() + nvl(unplanned).intValue();
  }

  private static Map<Date, Employee_Time_Card_Day_Entry__c> indexDayEntriesByDate(
    List<Employee_Time_Card_Day_Entry__c> dayEntries
  ) {
    Map<Date, Employee_Time_Card_Day_Entry__c> byDate = new Map<Date, Employee_Time_Card_Day_Entry__c>();
    if (dayEntries == null) {
      return byDate;
    }
    for (Employee_Time_Card_Day_Entry__c entry : dayEntries) {
      if (entry.Date__c != null) {
        byDate.put(entry.Date__c, entry);
      }
    }
    return byDate;
  }

  private static Date minEntryDate(Map<Date, Employee_Time_Card_Day_Entry__c> byDate) {
    Date earliest = null;
    for (Date d : byDate.keySet()) {
      if (earliest == null || d < earliest) {
        earliest = d;
      }
    }
    return earliest;
  }

  private static Employee_Time_Card_Day_Entry__c findLatestEntryOnOrBefore(
    Map<Date, Employee_Time_Card_Day_Entry__c> byDate,
    Date asOfDate
  ) {
    Employee_Time_Card_Day_Entry__c latest = null;
    for (Date d : byDate.keySet()) {
      if (d > asOfDate) {
        continue;
      }
      if (latest == null || d > latest.Date__c) {
        latest = byDate.get(d);
      }
    }
    return latest;
  }

  private static Integer paceRank(String status) {
    if (status == STATUS_AHEAD) {
      return 4;
    }
    if (status == STATUS_ON_TRACK) {
      return 3;
    }
    if (status == STATUS_BEHIND) {
      return 2;
    }
    return 1;
  }

  private static String getQueriedReportDetails(Employee_Time_Card__c card) {
    if (card == null) {
      return null;
    }
    Map<String, Object> populated = card.getPopulatedFieldsAsMap();
    return populated.containsKey('Employee_Report_Details__c')
      ? (String) card.get('Employee_Report_Details__c')
      : null;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
