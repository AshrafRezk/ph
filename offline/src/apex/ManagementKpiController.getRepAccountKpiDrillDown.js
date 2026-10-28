import { managementApex } from './managementRest.js';

export default managementApex('rep-accounts', (params) => ({
    repUserId: params.repUserId,
    periodMonthKey: params.periodMonthKey
}));
