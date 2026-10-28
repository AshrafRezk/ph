import { makeDualApex } from './_wireAdapter.js';
import { loadDashboard } from './kamDashboardData.js';

export default makeDualApex((params) => loadDashboard(params || {}));
