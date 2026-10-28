import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const API_VERSION = 'v62.0';

async function describePicklist(objectName, fieldName) {
    try {
        const describe = await plannerApiFetch(
            `/services/data/${API_VERSION}/sobjects/${objectName}/describe`
        );
        const field = (describe?.fields || []).find((f) => f.name === fieldName);
        return (field?.picklistValues || [])
            .filter((entry) => entry.active !== false)
            .map((entry) => ({
                label: entry.label,
                value: entry.value
            }));
    } catch (_err) {
        return [];
    }
}

export default makeDualApex(() => describePicklist('Account_Affiliation__c', 'Strength__c'));
