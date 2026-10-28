import { makeDualApex } from './_wireAdapter.js';
import { queryExpenseDetail } from './expenseShared.js';

export default makeDualApex((config) => queryExpenseDetail(config?.expenseId));
