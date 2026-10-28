import { makeDualApex } from './_wireAdapter.js';
import { rejectExpenseRecord } from './expenseShared.js';

export default makeDualApex((config) =>
    rejectExpenseRecord(config?.expenseId, config?.rejectionReason)
);
