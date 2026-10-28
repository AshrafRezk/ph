import { managementApex } from './managementRest.js';

export default managementApex('districts', (params) => ({
    lineTerritoryId: params.lineTerritoryId
}));
