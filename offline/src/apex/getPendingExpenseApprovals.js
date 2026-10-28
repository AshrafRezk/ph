import { makeDualApex } from './_wireAdapter.js';
import { queryPendingApprovals } from './expenseShared.js';

export default makeDualApex(() => queryPendingApprovals());
