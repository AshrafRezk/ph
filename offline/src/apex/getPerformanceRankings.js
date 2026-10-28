import { makeDualApex } from './_wireAdapter.js';
import { loadHomeDashboard } from './homeDashboard.js';

export default makeDualApex(async (params) => {
    const dash = await loadHomeDashboard(params || {});
    return (
        dash?.rankings || {
            buName: '',
            buRank: null,
            buTotal: 0,
            companyRank: null,
            companyTotal: 0,
            myCoveragePercent: 0,
            top5InBu: [],
            top5Company: [],
            personAbove: null,
            isFirstInBu: false
        }
    );
});
