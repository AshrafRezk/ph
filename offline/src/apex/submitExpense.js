import { makeDualApex } from './_wireAdapter.js';
import { createExpense } from './expenseShared.js';

export default makeDualApex((config) => createExpense(config || {}));
