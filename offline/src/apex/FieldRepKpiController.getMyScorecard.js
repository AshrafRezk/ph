import { makeDualApex } from './_wireAdapter.js';
import { loadHomeDashboard } from './homeDashboard.js';

function nvl(value) {
    const num = Number(value);
    return Number.isFinite(num) ? num : 0;
}

function buildCard(key, label, actual, target, detail) {
    let status = 'pending';
    if (actual == null) {
        status = 'pending';
    } else if (target != null && actual >= target) {
        status = 'good';
    } else if (target != null && actual >= target * 0.75) {
        status = 'warn';
    } else {
        status = 'bad';
    }
    return { key, label, actual, target, status, detail };
}

export default makeDualApex(async () => {
    const dash = (await loadHomeDashboard({})) || {};
    const home = dash.metrics || {};
    const coveragePercent = nvl(home.customerCoveragePercent);
    const rightFrequencyPercent = nvl(home.rfPercentTotal);
    const visitCoveragePercent = nvl(home.visitCoveragePercent);
    const remainingCalls = nvl(home.remainingCalls);
    const actualVisits = nvl(home.actualVisitsTotal);
    const targetVisits = nvl(home.targetVisitsTotal);
    const daysInField = Math.max(1, new Date().getDate());
    const dailyCallRatePercent =
        daysInField > 0 ? Math.round(((actualVisits / daysInField) / 12) * 1000) / 10 : 0;
    const targetCoverage = 80;
    const targetRightFrequency = 70;
    const targetDailyCallRate = 100;
    const targetQuiz = 80;
    return {
        roleKey: 'MSR',
        periodLabel: new Date().toLocaleString(undefined, { month: 'long', year: 'numeric' }),
        coveragePercent,
        rightFrequencyPercent,
        visitCoveragePercent,
        remainingCalls,
        actualVisits,
        targetVisits,
        daysInField,
        dailyCallRatePercent,
        quizPercent: null,
        targetCoverage,
        targetRightFrequency,
        targetDailyCallRate,
        targetQuiz,
        cards: [
            buildCard('coverage', 'Coverage', coveragePercent, targetCoverage, 'Target doctors visited ÷ target customers'),
            buildCard(
                'rf',
                'Right Frequency',
                rightFrequencyPercent,
                targetRightFrequency,
                'Customers at target frequency ÷ target customers'
            ),
            buildCard(
                'dcr',
                'Daily Call Rate',
                dailyCallRatePercent,
                targetDailyCallRate,
                'Visits ÷ days in field (normalized)'
            ),
            buildCard(
                'visits',
                'Visit coverage',
                visitCoveragePercent,
                targetCoverage,
                'Actual visits ÷ target visits'
            ),
            buildCard('quiz', 'Quizzes', null, targetQuiz, 'Medical + product knowledge (when assigned)')
        ]
    };
});
