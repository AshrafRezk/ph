import { managementApex } from './managementRest.js';

export default managementApex('team-kpis', (params) => ({
    buTerritoryId: params.buTerritoryId,
    lineTerritoryId: params.lineTerritoryId,
    districtTerritoryId: params.districtTerritoryId,
    periodMonthKey: params.periodMonthKey
}));
