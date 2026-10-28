import { makeDualApex } from './_wireAdapter.js';
import { deleteMyExpenseRecord } from './expenseShared.js';

export default makeDualApex((config) => deleteMyExpenseRecord(config?.expenseId));
