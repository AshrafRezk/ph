import { makeDualApex } from './_wireAdapter.js';
import { queryMyExpenses } from './expenseShared.js';

export default makeDualApex((config) => queryMyExpenses(config?.limitSize));
