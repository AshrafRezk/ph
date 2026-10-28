import { plannerApiFetch } from './restHelper.js';
import { normalizeAccountClassFields } from './classCode.js';

export default async function searchAccountsPage(params = {}) {
    const offset =
        params.offset != null
            ? params.offset
            : params.pageNumber != null
              ? (params.pageNumber - 1) * (params.pageSize || 50)
              : 0;
    const pageSize = params.pageSize || 10;

    const result = await plannerApiFetch('/services/apexrest/planner/v1/accounts/search', {
        method: 'POST',
        body: JSON.stringify({
            searchTerm: params.searchTerm,
            recordTypeDeveloperNames: params.recordTypeDeveloperName
                ? [params.recordTypeDeveloperName]
                : [],
            specialty: params.specialty,
            classification: params.classification,
            brickId: params.brickId,
            brick148Id: params.brick148Id,
            brick702Id: params.brick702Id,
            pageSize,
            pageToken: String(offset),
            contextUserId: params.contextUserId
        })
    });

    const accounts = (result?.accounts || []).map(normalizeAccountClassFields);

    return {
        accounts,
        hasMore: result?.hasMore != null ? result.hasMore : Boolean(result?.nextPageToken),
        totalCount: result?.totalCount != null ? result.totalCount : result?.totalSize || 0
    };
}
