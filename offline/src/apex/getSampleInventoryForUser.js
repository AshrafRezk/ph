import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { currentUserId, esc } from './learningShared.js';

const API_VERSION = 'v62.0';

async function soql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

async function getSampleInventoryForUser() {
    const userId = currentUserId();
    if (!userId) {
        return [];
    }
    try {
        const rows = await soql(
            'SELECT Id, Product2__c, Product2__r.Name, Product2__r.Product_Image_URL__c, ' +
                'Lot_Number__c, Quantity_On_Hand__c, Expiry_Date__c ' +
                'FROM Sample_Inventory__c ' +
                `WHERE Owner_User__c = '${esc(userId)}' AND Quantity_On_Hand__c > 0 ` +
                "AND Product2__r.Product_Type__c IN ('Sample','Brand Reminder') " +
                'ORDER BY Product2__r.Name ASC, Lot_Number__c ASC'
        );
        return rows.map((row) => {
            const product = row.Product2__r || {};
            return {
                id: row.Id,
                productId: row.Product2__c,
                productName: product.Name || null,
                imageUrl: product.Product_Image_URL__c || null,
                lotNumber: row.Lot_Number__c || null,
                quantityOnHand: row.Quantity_On_Hand__c,
                expiryDate: row.Expiry_Date__c || null
            };
        });
    } catch (_error) {
        return [];
    }
}

export default makeDualApex(getSampleInventoryForUser);
