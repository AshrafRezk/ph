import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/class-engine/v1/save-chosen';

export default async function saveChosenClasses(params = {}) {
    return plannerApiFetch(PATH, {
        method: 'POST',
        body: JSON.stringify({
            cycleId: params.cycleId || null,
            updates: params.updates || []
        })
    });
}
