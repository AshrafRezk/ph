import { makeDualApex } from './_wireAdapter.js';
import { loadHomeDashboard } from './homeDashboard.js';

export default makeDualApex(async (params) => {
    const dash = await loadHomeDashboard(params || {});
    return dash?.accountCoverageRows || [];
});
