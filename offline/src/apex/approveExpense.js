import { makeDualApex } from './_wireAdapter.js';
import { approveExpenseRecord } from './expenseShared.js';

export default makeDualApex((config) => approveExpenseRecord(config?.expenseId));
