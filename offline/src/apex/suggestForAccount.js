import { plannerApiFetch } from './restHelper.js';

export default async function suggestForAccount(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/classification-suggestions/suggest', {
        method: 'POST',
        body: JSON.stringify({ accountId: params.accountId })
    });
}
