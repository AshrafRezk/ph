import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/class-engine/v1/save-ratings';

export default async function saveProductRatings(params = {}) {
    return plannerApiFetch(PATH, {
        method: 'POST',
        body: JSON.stringify({
            accountId: params.accountId || null,
            territoryId: params.territoryId || null,
            product2Id: params.product2Id || null,
            potential: params.potential,
            penetration: params.penetration
        })
    });
}
