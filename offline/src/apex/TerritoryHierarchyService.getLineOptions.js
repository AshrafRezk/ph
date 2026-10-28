import { managementApex } from './managementRest.js';

export default managementApex('lines', (params) => ({
    businessUnitTerritoryId: params.businessUnitTerritoryId
}));
