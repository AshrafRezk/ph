import { plannerApiFetch } from './restHelper.js';

const NBC_PATH = '/services/apexrest/planner/v1/home/next-best-customers';

export default async function getNextBestCustomersPayload(params = {}) {
    const query = new URLSearchParams();
    if (params.limitSize) {
        query.set('limitSize', String(params.limitSize));
    }
    if (params.contextUserId) {
        query.set('contextUserId', params.contextUserId);
    }
    const suffix = query.toString() ? `?${query.toString()}` : '';
    return plannerApiFetch(`${NBC_PATH}${suffix}`);
}
