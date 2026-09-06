import { makeDualApex } from './_wireAdapter.js';

export default makeDualApex(async () => ({
    buName: '',
    buRank: null,
    buTotal: 0,
    companyRank: null,
    companyTotal: 0,
    myCoveragePercent: 0,
    top5InBu: [],
    top5Company: [],
    personAbove: null,
    isFirstInBu: false
}));
