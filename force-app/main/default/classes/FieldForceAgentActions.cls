public with sharing class FieldForceAgentActions {
    private static final Integer MAX_VISIT_LINES = 12;
    private static final Integer MAX_NBC_LINES = 5;
    private static final Integer MAX_NEARBY_LINES = 5;

    public class HomeDashboardRequest {
        @InvocableVariable(
            label='Context User Id'
            description='Optional user id. Defaults to the running user.'
        )
        public Id contextUserId;
    }

    public class PlannerWeekRequest {
        @InvocableVariable(
            label='Context User Id'
            description='Optional user id. Defaults to the running user.'
        )
        public Id contextUserId;

        @InvocableVariable(
            label='Week Start Date'
            description='Optional Monday of the planner week. Defaults to the current week.'
        )
        public Date weekStartDate;
    }

    public class AccountFieldRequest {
        @InvocableVariable(
            required=true
            label='Account Id'
            description='The Account record to summarize. Use the current record id when the user is on an account page.'
        )
        public Id accountId;
    }

    public class BriefResult {
        @InvocableVariable(label='Summary' description='Field-force context for the agent to answer with.')
        public String summary;
    }

    public static List<BriefResult> buildHomeDashboardBrief(List<HomeDashboardRequest> requests) {
        List<BriefResult> results = new List<BriefResult>();
        for (HomeDashboardRequest request : requests) {
            BriefResult result = new BriefResult();
            result.summary = buildHomeSummary(request == null ? null : request.contextUserId);
            results.add(result);
        }
        return results;
    }

    public static List<BriefResult> buildPlannerWeekBrief(List<PlannerWeekRequest> requests) {
        List<BriefResult> results = new List<BriefResult>();
        for (PlannerWeekRequest request : requests) {
            BriefResult result = new BriefResult();
            result.summary = buildPlannerSummary(request);
            results.add(result);
        }
        return results;
    }

    public static List<BriefResult> buildAccountFieldBrief(List<AccountFieldRequest> requests) {
        List<BriefResult> results = new List<BriefResult>();
        for (AccountFieldRequest request : requests) {
            BriefResult result = new BriefResult();
            result.summary = buildAccountSummary(request == null ? null : request.accountId);
            results.add(result);
        }
        return results;
    }

    private static String buildHomeSummary(Id contextUserId) {
        List<String> lines = new List<String>();
        lines.add('Field Rep Home dashboard context:');

        FieldRepHomeController.HomeMetrics metrics = FieldRepHomeController.getHomeMetrics(contextUserId);
        lines.add(
            'Plan-cycle coverage: visit coverage ' +
            formatPercent(metrics.visitCoveragePercent) +
            ', customer coverage ' +
            formatPercent(metrics.customerCoveragePercent) +
            '. Overall RF% ' +
            formatPercent(metrics.rfPercentTotal) +
            ' (LF% ' +
            formatPercent(metrics.lfPercentTotal) +
            ', MF% ' +
            formatPercent(metrics.mfPercentTotal) +
            ').'
        );

        if (metrics.byClassification != null && !metrics.byClassification.isEmpty()) {
            List<String> classLines = new List<String>();
            for (FieldRepHomeController.ClassificationMetrics row : metrics.byClassification) {
                classLines.add(
                    row.classification +
                    ': visit coverage ' +
                    formatPercent(row.visitCoveragePercent) +
                    ', RF% ' +
                    formatPercent(row.rfPercent)
                );
            }
            lines.add('By classification — ' + String.join(classLines, '; ') + '.');
        }

        FieldPlannerController.PlannerPayload todayPlan = FieldRepHomeController.getTodayPlan(contextUserId);
        Integer todayVisitCount = todayPlan.visits == null ? 0 : todayPlan.visits.size();
        Integer todayTotCount = todayPlan.timeOffBlocks == null ? 0 : todayPlan.timeOffBlocks.size();
        lines.add('Today: ' + todayVisitCount + ' scheduled visit(s), ' + todayTotCount + ' time-off block(s).');

        if (todayPlan.visits != null && !todayPlan.visits.isEmpty()) {
            List<String> visitLines = new List<String>();
            Integer count = 0;
            for (FieldPlannerController.VisitSummary visit : todayPlan.visits) {
                visitLines.add(
                    formatDateTime(visit.startDateTime) +
                    ' — ' +
                    safeString(visit.accountName) +
                    ' (' +
                    safeString(visit.status) +
                    ')'
                );
                count++;
                if (count >= MAX_VISIT_LINES) {
                    break;
                }
            }
            lines.add('Up next today: ' + String.join(visitLines, '; ') + '.');
        }

        List<FieldRepHomeController.NextBestCustomerRow> nbcRows = FieldRepHomeController.getNextBestCustomers(
            contextUserId,
            MAX_NBC_LINES
        );
        if (!nbcRows.isEmpty()) {
            List<String> nbcLines = new List<String>();
            for (FieldRepHomeController.NextBestCustomerRow row : nbcRows) {
                nbcLines.add(
                    row.rank +
                    '. ' +
                    safeString(row.accountName) +
                    ' (gap ' +
                    formatDecimal(row.visitGap) +
                    ', class ' +
                    safeString(row.calculatedClassification) +
                    (row.plannedToday ? ', planned today' : '') +
                    ')'
                );
            }
            lines.add('Top next-best customers: ' + String.join(nbcLines, '; ') + '.');
        } else {
            lines.add('No next-best customer recommendations are available right now.');
        }

        return String.join(lines, '\n');
    }

    private static String buildPlannerSummary(PlannerWeekRequest request) {
        Id contextUserId = request == null ? null : request.contextUserId;
        Date weekStart = request == null || request.weekStartDate == null
            ? startOfWeek(Date.today())
            : request.weekStartDate;
        Date weekEnd = weekStart.addDays(6);

        FieldPlannerController.PlannerPayload payload = FieldPlannerController.getPlannerData(
            weekStart,
            weekEnd,
            contextUserId
        );

        List<String> lines = new List<String>();
        lines.add(
            'Field Planner context for week ' +
            formatDate(weekStart) +
            ' to ' +
            formatDate(weekEnd) +
            ':'
        );

        Integer visitCount = payload.visits == null ? 0 : payload.visits.size();
        Integer totCount = payload.timeOffBlocks == null ? 0 : payload.timeOffBlocks.size();
        lines.add('Scheduled visits: ' + visitCount + '. Time-off blocks: ' + totCount + '.');

        if (payload.visits != null && !payload.visits.isEmpty()) {
            Map<String, Integer> visitsByDay = new Map<String, Integer>();
            List<String> visitLines = new List<String>();
            Integer count = 0;
            for (FieldPlannerController.VisitSummary visit : payload.visits) {
                String dayKey = formatDate(visit.startDateTime == null ? null : visit.startDateTime.date());
                Integer dayCount = visitsByDay.containsKey(dayKey) ? visitsByDay.get(dayKey) : 0;
                visitsByDay.put(dayKey, dayCount + 1);
                visitLines.add(
                    formatDateTime(visit.startDateTime) +
                    ' — ' +
                    safeString(visit.accountName) +
                    ' (' +
                    safeString(visit.status) +
                    ')'
                );
                count++;
                if (count >= MAX_VISIT_LINES) {
                    break;
                }
            }
            List<String> daySummaries = new List<String>();
            for (String dayKey : visitsByDay.keySet()) {
                daySummaries.add(dayKey + ': ' + visitsByDay.get(dayKey));
            }
            lines.add('Visits by day — ' + String.join(daySummaries, ', ') + '.');
            lines.add('Upcoming visits: ' + String.join(visitLines, '; ') + '.');
        } else {
            lines.add('No visits are scheduled this week yet.');
        }

        if (payload.timeOffBlocks != null && !payload.timeOffBlocks.isEmpty()) {
            List<String> totLines = new List<String>();
            for (FieldPlannerController.TotSummary tot : payload.timeOffBlocks) {
                totLines.add(
                    formatDateTime(tot.startDateTime) +
                    ' — ' +
                    safeString(tot.typeLabel) +
                    ' (' +
                    safeString(tot.stage) +
                    ')'
                );
            }
            lines.add('Time off: ' + String.join(totLines, '; ') + '.');
        }

        List<FieldRepHomeController.NextBestCustomerRow> nbcRows = FieldRepHomeController.getNextBestCustomers(
            contextUserId,
            MAX_NBC_LINES
        );
        if (!nbcRows.isEmpty()) {
            List<String> gapLines = new List<String>();
            for (FieldRepHomeController.NextBestCustomerRow row : nbcRows) {
                if (row.planned) {
                    continue;
                }
                gapLines.add(safeString(row.accountName) + ' (gap ' + formatDecimal(row.visitGap) + ')');
                if (gapLines.size() >= MAX_NBC_LINES) {
                    break;
                }
            }
            if (!gapLines.isEmpty()) {
                lines.add('Unplanned high-priority accounts to consider: ' + String.join(gapLines, '; ') + '.');
            }
        }

        return String.join(lines, '\n');
    }

    private static String buildAccountSummary(Id accountId) {
        if (accountId == null) {
            return 'Account id is required to summarize field-force account context.';
        }

        AccountVisitInsightsController.AccountVisitContext context = AccountVisitInsightsController.getAccountVisitContext(
            accountId
        );
        List<String> lines = new List<String>();
        lines.add('Account field context for ' + safeString(context.accountName) + ':');

        if (!context.hasPlanTarget) {
            lines.add('No active plan-cycle target is assigned to this account.');
        } else {
            lines.add(
                'Plan-cycle target ' +
                formatDecimal(context.targetVisits) +
                ' visits, actual ' +
                formatDecimal(context.actualVisits) +
                ', gap ' +
                formatDecimal(context.visitGap) +
                ', reach ' +
                formatPercent(context.reachPercent) +
                ', frequency status ' +
                safeString(context.frequencyStatus) +
                '.'
            );
            lines.add(
                'Pace: ' +
                paceLabel(context.paceStatus) +
                ' (' +
                formatPercent(context.projectedPercent) +
                ' projected, ' +
                (context.willMeetTarget ? 'on track to meet target' : 'not on track to meet target') +
                ').'
            );
        }

        if (context.futureVisits != null && !context.futureVisits.isEmpty()) {
            List<String> visitLines = new List<String>();
            Integer count = 0;
            for (AccountVisitInsightsController.FutureVisitRow visit : context.futureVisits) {
                visitLines.add(
                    formatDateTime(visit.startDateTime) +
                    ' — ' +
                    safeString(visit.status)
                );
                count++;
                if (count >= MAX_VISIT_LINES) {
                    break;
                }
            }
            lines.add('Upcoming visits: ' + String.join(visitLines, '; ') + '.');
        } else {
            lines.add('No upcoming visits are scheduled for this account.');
        }

        AccountVisitInsightsController.NearbyPlanTargetsResult neighbors = AccountVisitInsightsController.getNearbyPlanTargets(
            accountId,
            null
        );
        if (neighbors != null && neighbors.targets != null && !neighbors.targets.isEmpty()) {
            List<String> nearbyLines = new List<String>();
            Integer count = 0;
            for (AccountVisitInsightsController.NearbyPlanTarget target : neighbors.targets) {
                if (target.isCenterAccount == true) {
                    continue;
                }
                nearbyLines.add(
                    safeString(target.name) +
                    ' (' +
                    formatDecimal(target.distanceKm) +
                    ' km, gap ' +
                    formatDecimal(target.visitGap) +
                    ')'
                );
                count++;
                if (count >= MAX_NEARBY_LINES) {
                    break;
                }
            }
            if (!nearbyLines.isEmpty()) {
                lines.add('Nearby accounts in the plan cycle: ' + String.join(nearbyLines, '; ') + '.');
            }
        }

        return String.join(lines, '\n');
    }

    private static Date startOfWeek(Date value) {
        Date anchor = value == null ? Date.today() : value;
        Datetime anchorDt = Datetime.newInstance(anchor, Time.newInstance(0, 0, 0, 0));
        Integer isoDay = Integer.valueOf(anchorDt.format('u'));
        Integer diff = isoDay == 7 ? -6 : 1 - isoDay;
        return anchor.addDays(diff);
    }

    private static String paceLabel(String paceStatus) {
        if (paceStatus == 'ahead') {
            return 'Ahead of target pace';
        }
        if (paceStatus == 'on_track') {
            return 'On track';
        }
        if (paceStatus == 'behind') {
            return 'Behind target pace';
        }
        if (paceStatus == 'critical') {
            return 'Critically behind pace';
        }
        return 'Pace not available';
    }

    private static String formatPercent(Decimal value) {
        if (value == null) {
            return '0%';
        }
        return String.valueOf(value.setScale(0)) + '%';
    }

    private static String formatDecimal(Decimal value) {
        if (value == null) {
            return '0';
        }
        return String.valueOf(value.setScale(1));
    }

    private static Decimal valueOrZero(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String safeString(String value) {
        return String.isBlank(value) ? '—' : value;
    }

    private static String formatDate(Date value) {
        if (value == null) {
            return '—';
        }
        return value.format();
    }

    private static String formatDateTime(DateTime value) {
        if (value == null) {
            return '—';
        }
        return value.format('yyyy-MM-dd HH:mm');
    }
}
