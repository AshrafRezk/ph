import { plannerApiFetch } from './restHelper.js';
import { isOffline } from './restHelper.js';

export default async function askPlannerQuestion(params = {}) {
    if (isOffline()) {
        return {
            answer: 'Planner Q&A needs an internet connection. Reconnect and try again.',
            contextSummary: ''
        };
    }
    return plannerApiFetch('/services/apexrest/planner/assist/v1/agent/ask', {
        method: 'POST',
        body: JSON.stringify({
            question: params.question,
            weekStart: params.weekStart,
            contextUserId: params.contextUserId
        })
    });
}
