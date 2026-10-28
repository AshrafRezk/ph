/**
 * Interactive Field Co-pilot KPI scorecard — realtime visits + editable framework targets.
 */
public with sharing class FieldRepKpiController {
    public class Scorecard {
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Decimal rightFrequencyPercent;
        @AuraEnabled public Decimal dailyCallRatePercent;
        @AuraEnabled public Decimal visitCoveragePercent;
        @AuraEnabled public Decimal remainingCalls;
        @AuraEnabled public Decimal actualVisits;
        @AuraEnabled public Decimal targetVisits;
        @AuraEnabled public Decimal daysInField;
        @AuraEnabled public Decimal quizPercent;
        @AuraEnabled public Decimal targetCoverage;
        @AuraEnabled public Decimal targetRightFrequency;
        @AuraEnabled public Decimal targetDailyCallRate;
        @AuraEnabled public Decimal targetQuiz;
        @AuraEnabled public String periodLabel;
        @AuraEnabled public String roleKey;
        @AuraEnabled public List<KpiCard> cards;
    }

    public class KpiCard {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal actual;
        @AuraEnabled public Decimal target;
        @AuraEnabled public String status;
        @AuraEnabled public String detail;
    }

    @AuraEnabled(cacheable=true)
    public static Scorecard getMyScorecard() {
        FieldRepHomeController.HomeMetrics home = FieldRepHomeController.getHomeMetrics(null);
        Scorecard card = new Scorecard();
        card.roleKey = 'MSR';
        card.periodLabel = Datetime.now().format('MMMM yyyy');
        card.coveragePercent = home == null ? 0 : nvl(home.customerCoveragePercent);
        card.rightFrequencyPercent = home == null ? 0 : nvl(home.rfPercentTotal);
        card.visitCoveragePercent = home == null ? 0 : nvl(home.visitCoveragePercent);
        card.remainingCalls = home == null ? 0 : nvl(home.remainingCalls);
        card.actualVisits = home == null ? 0 : nvl(home.actualVisitsTotal);
        card.targetVisits = home == null ? 0 : nvl(home.targetVisitsTotal);
        card.daysInField = estimateDaysInField();
        // Daily target comes from the one call-rate resolver (territory, then line, BU, org rule).
        Decimal dailyTarget = CallRateRuleService.dailyCallRateOrDefault(home == null ? null : home.targetCallRate);
        card.dailyCallRatePercent = card.daysInField > 0
            ? ((card.actualVisits / card.daysInField) / dailyTarget * 100).setScale(1, RoundingMode.HALF_UP)
            : 0;
        // Placeholder until quiz engine wires achievement % for the running user.
        card.quizPercent = null;

        card.targetCoverage = ZetaKpiTargets.coverageTargetForRole('MSR');
        card.targetRightFrequency = ZetaKpiTargets.rightFrequencyTargetForRole('MSR');
        card.targetDailyCallRate = ZetaKpiTargets.dailyCallRateTargetForRole('MSR');
        card.targetQuiz = ZetaKpiTargets.quizTargetForRole('MSR');

        card.cards = new List<KpiCard>{
            buildCard('coverage', 'Coverage', card.coveragePercent, card.targetCoverage, 'Target doctors visited ÷ target customers'),
            buildCard('rf', 'Right Frequency', card.rightFrequencyPercent, card.targetRightFrequency, 'Customers at target frequency ÷ target customers'),
            buildCard('dcr', 'Daily Call Rate', card.dailyCallRatePercent, card.targetDailyCallRate, 'Visits ÷ days in field (normalized)'),
            buildCard('visits', 'Visit coverage', card.visitCoveragePercent, card.targetCoverage, 'Actual visits ÷ target visits'),
            buildCard('quiz', 'Quizzes', card.quizPercent, card.targetQuiz, 'Medical + product knowledge (when assigned)')
        };
        return card;
    }

    private static KpiCard buildCard(String key, String label, Decimal actual, Decimal target, String detail) {
        KpiCard c = new KpiCard();
        c.key = key;
        c.label = label;
        c.actual = actual;
        c.target = target;
        c.detail = detail;
        if (actual == null) {
            c.status = 'pending';
        } else if (target != null && actual >= target) {
            c.status = 'good';
        } else if (target != null && actual >= target * 0.75) {
            c.status = 'warn';
        } else {
            c.status = 'low';
        }
        return c;
    }

    private static Decimal nvl(Decimal value) {
        return value == null ? 0 : value;
    }

    private static Decimal estimateDaysInField() {
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = Date.today();
        Integer working = 0;
        for (Date d = monthStart; d <= monthEnd; d = d.addDays(1)) {
            Datetime dt = Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0));
            String dow = dt.format('u');
            // Egypt working week Sat–Wed (u: 6=Sat … 3=Wed). Treat Thu=4 Fri=5 as weekend.
            if (dow != '4' && dow != '5') {
                working++;
            }
        }
        return working;
    }
}
