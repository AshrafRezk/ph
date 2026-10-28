import { makeDualApex } from './_wireAdapter.js';
import { updateMyExpenseRecord } from './expenseShared.js';

export default makeDualApex((config) => updateMyExpenseRecord(config || {}));
