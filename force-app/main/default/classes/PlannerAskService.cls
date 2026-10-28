public with sharing class PlannerAskService {
  public class PlannerAskResult {
    @AuraEnabled public String answer;
    @AuraEnabled public String contextSummary;
  }

  @AuraEnabled
  public static PlannerAskResult askPlannerQuestion(String question, Date weekStartDate, Id contextUserId) {
    Date start = weekStartDate == null ? Date.today().toStartOfWeek() : weekStartDate;
    Date weekEnd = start.addDays(6);

    FieldPlannerAssistController.WeeklyPlanRecommendations recs;
    try {
      recs = FieldPlannerAssistController.getWeeklyPlanRecommendations(start, weekEnd, contextUserId);
    } catch (Exception ignore) {
      recs = null;
    }

    String context = buildWeekContext(start, weekEnd, contextUserId, recs);
    PlannerAskResult result = new PlannerAskResult();
    result.contextSummary = context;
    result.answer = answerFromPlannerContext(question, context, recs);
    return result;
  }

  private static String buildWeekContext(
    Date weekStart,
    Date weekEnd,
    Id contextUserId,
    FieldPlannerAssistController.WeeklyPlanRecommendations recs
  ) {
    List<String> lines = new List<String>();
    lines.add('Planner week ' + String.valueOf(weekStart) + ' to ' + String.valueOf(weekEnd) + ':');
    try {
      FieldPlannerController.PlannerPayload data = FieldPlannerController.getPlannerData(
        weekStart,
        weekEnd,
        contextUserId
      );
      Integer visitCount = data == null || data.visits == null ? 0 : data.visits.size();
      Integer totCount = data == null || data.timeOffBlocks == null ? 0 : data.timeOffBlocks.size();
      lines.add(visitCount + ' visit(s) on the calendar.');
      lines.add('Time off: ' + totCount + ' block(s).');
      Map<String, Integer> byDay = new Map<String, Integer>();
      if (data != null && data.visits != null) {
        for (FieldPlannerController.VisitSummary visit : data.visits) {
          if (visit == null || visit.startDateTime == null) {
            continue;
          }
          String dayKey = String.valueOf(visit.startDateTime.date());
          byDay.put(dayKey, (byDay.containsKey(dayKey) ? byDay.get(dayKey) : 0) + 1);
        }
      }
      if (!byDay.isEmpty()) {
        List<String> dayParts = new List<String>();
        for (String dayKey : byDay.keySet()) {
          dayParts.add(dayKey + '=' + byDay.get(dayKey));
        }
        lines.add('Visits by day: ' + String.join(dayParts, ', ') + '.');
      }
    } catch (Exception ignore) {
      lines.add('Visit calendar context unavailable.');
    }
    if (recs != null && recs.forecast != null) {
      lines.add(
        'Pace/coverage: ' +
          recs.forecast.plannedVisitCount +
          ' planned · ' +
          recs.forecast.dailyFrequency +
          '/day · ' +
          safe(recs.forecast.paceLabel)
      );
    }
    return String.join(lines, '\n');
  }

  private static String answerFromPlannerContext(
    String question,
    String context,
    FieldPlannerAssistController.WeeklyPlanRecommendations recs
  ) {
    String q = String.isBlank(question) ? '' : question.toLowerCase();
    if (recs != null && recs.forecast != null) {
      if (q.contains('pace') || q.contains('frequency') || q.contains('daily')) {
        return 'This week has ' +
          recs.forecast.plannedVisitCount +
          ' planned visits across ' +
          recs.forecast.remainingWorkingDays +
          ' remaining working days (' +
          String.valueOf(recs.forecast.dailyFrequency) +
          ' visits/day). Pace: ' +
          safe(recs.forecast.paceLabel) +
          '.';
      }
      if ((q.contains('behind') || q.contains('lcf') || q.contains('recommend') || q.contains('who')) &&
        recs.recommendations != null &&
        !recs.recommendations.isEmpty()) {
        List<String> names = new List<String>();
        Integer count = 0;
        for (FieldPlannerAssistController.WeeklyRecommendationRow row : recs.recommendations) {
          if (row.plannedThisWeek == true) {
            continue;
          }
          names.add(safe(row.accountName) + ' (' + safe(row.reason) + ')');
          count++;
          if (count >= 5) {
            break;
          }
        }
        if (!names.isEmpty()) {
          return 'Top accounts to plan: ' + String.join(names, '; ') + '.';
        }
      }
      if (q.contains('tot') || q.contains('time off')) {
        String totLine = extractContextLine(context, 'Time off:');
        return totLine != null ? totLine : 'No time-off blocks are listed for this week.';
      }
      if (q.contains('light') || q.contains('gap') || q.contains('empty')) {
        String dayLine = extractContextLine(context, 'Visits by day');
        return dayLine != null ? dayLine : 'Visit-by-day breakdown is not available yet.';
      }
      if (q.contains('cover')) {
        String coverage = extractContextLine(context, 'coverage');
        return coverage != null ? coverage : 'Coverage details are not available for this week.';
      }
    }
    if (String.isNotBlank(context)) {
      return 'Here is the week brief:\n' + context;
    }
    return 'I could not build planner context for that question. Try asking about pace, coverage, or who is behind.';
  }

  private static String extractContextLine(String context, String needle) {
    if (String.isBlank(context) || String.isBlank(needle)) {
      return null;
    }
    for (String line : context.split('\n')) {
      if (line != null && line.toLowerCase().contains(needle.toLowerCase())) {
        return line.trim();
      }
    }
    return null;
  }

  private static String safe(String value) {
    return String.isBlank(value) ? '—' : value;
  }
}