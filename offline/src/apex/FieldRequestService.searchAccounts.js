import { makeDualApex } from './_wireAdapter.js';
import searchAccounts from './FieldAccountSearch.search.js';

async function search(params = {}) {
    const term = String(params.term || '').trim();
    if (term.length < 2) return [];
    return searchAccounts({ term });
}

export default makeDualApex(search);
