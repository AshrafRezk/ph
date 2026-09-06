import { makeDualApex } from './_wireAdapter.js';

export default makeDualApex(async (params = {}) => ({
    accountId: params.accountId,
    isKol: params.isKol === true
}));
