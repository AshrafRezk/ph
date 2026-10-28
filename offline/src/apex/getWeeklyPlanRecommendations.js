import { plannerApiFetch } from './restHelper.js';

export default async function getWeeklyPlanRecommendations(params = {}) {
    const query = new URLSearchParams();
    if (params.weekStart) query.set('weekStart', params.weekStart);
    if (params.weekEnd) query.set('weekEnd', params.weekEnd);
    if (params.contextUserId) query.set('contextUserId', params.contextUserId);
    const suffix = query.toString() ? `?${query.toString()}` : '';
    return plannerApiFetch(`/services/apexrest/planner/assist/v1/week-recommendations${suffix}`);
}
