import { plannerApiFetch } from './restHelper.js';

const TODAY_PLAN_PATH = '/services/apexrest/planner/v1/home/today-plan';

export default async function getTodayPlanPayload(params = {}) {
    const query = new URLSearchParams();
    if (params.planDate) {
        query.set('planDate', params.planDate);
    }
    if (params.contextUserId) {
        query.set('contextUserId', params.contextUserId);
    }
    const suffix = query.toString() ? `?${query.toString()}` : '';
    return plannerApiFetch(`${TODAY_PLAN_PATH}${suffix}`);
}
