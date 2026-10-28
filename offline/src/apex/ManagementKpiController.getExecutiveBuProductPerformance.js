import { managementApex } from './managementRest.js';

export default managementApex('product-performance', (params) => ({
    buTerritoryId: params.buTerritoryId,
    lineTerritoryId: params.lineTerritoryId,
    districtTerritoryId: params.districtTerritoryId
}));
