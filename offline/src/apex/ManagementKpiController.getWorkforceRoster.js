import { managementApex } from './managementRest.js';

export default managementApex('workforce-roster', (params) => ({
    workforceType: params.workforceType,
    buTerritoryId: params.buTerritoryId,
    lineTerritoryId: params.lineTerritoryId,
    districtTerritoryId: params.districtTerritoryId
}));
