import { makeDualApex } from './_wireAdapter.js';
import { queryExpenseFormContext } from './expenseShared.js';

export default makeDualApex((config) => queryExpenseFormContext(config?.expenseDate));
