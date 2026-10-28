import { plannerApiFetch } from './restHelper.js';

const API_VERSION = 'v62.0';

// The org presentation REST list still drops non-PDF decks. Query the records
// directly so HTML packages and PDFs both show up in the installed PWA.
export default async function getRepPresentations() {
    const query =
        "SELECT Id, Name, Status__c, Format__c, Product__r.Name, Product__r.Product_Image_URL__c, " +
        "Slide_Count__c, Tags__c FROM CLM_Presentation__c " +
        "WHERE Status__c = 'Available' ORDER BY Name ASC";
    const result = await plannerApiFetch(`/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`);
    return (result?.records || []).map((row) => ({
        id: row.Id,
        name: row.Name,
        status: row.Status__c,
        formatType: row.Format__c,
        productName: row.Product__r ? row.Product__r.Name : null,
        imageUrl: row.Product__r ? row.Product__r.Product_Image_URL__c : null,
        slideCount: row.Slide_Count__c != null ? Number(row.Slide_Count__c) : 0,
        tags: row.Tags__c
    }));
}
