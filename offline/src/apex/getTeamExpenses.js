import { makeDualApex } from './_wireAdapter.js';
import { queryTeamExpenses } from './expenseShared.js';

export default makeDualApex(() => queryTeamExpenses());
