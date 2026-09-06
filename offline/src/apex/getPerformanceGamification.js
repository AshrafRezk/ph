import { makeDualApex } from './_wireAdapter.js';

export default makeDualApex(async () => ({
    userFirstName: '',
    streaks: { activityStreak: 0, coverageStreak: 0 },
    badges: []
}));
