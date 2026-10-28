import { makeDualApex } from './_wireAdapter.js';
import { loadHomeDashboard } from './homeDashboard.js';

export default makeDualApex(async (params) => {
    const dash = await loadHomeDashboard(params || {});
    return (
        dash?.gamification || {
            userFirstName: '',
            streaks: { activityStreak: 0, coverageStreak: 0 },
            badges: []
        }
    );
});
