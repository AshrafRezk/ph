import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

// ClmMetricsController.getSessionDetail over ClmMobileRestService GET sessions/{id}.
// clmMessageFeedback wires it for the product name and message topics.
export default makeDualApex((params = {}) => {
    const sessionId = params && params.sessionId;
    if (!sessionId) return Promise.resolve(null);
    return plannerApiFetch(`/services/apexrest/clm/v1/sessions/${encodeURIComponent(sessionId)}`);
});
