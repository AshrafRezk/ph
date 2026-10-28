import { makeDualApex } from './_wireAdapter.js';
import { soql } from './learningShared.js';
import {
    requireVisit,
    visitLocked,
    productOptions,
    SENTIMENT_OPTIONS,
    esc
} from './fieldWorkflowShared.js';

export default makeDualApex(async (params = {}) => {
    const visit = await requireVisit(params.visitId);
    const options = await productOptions();
    const rows = await soql(
        'SELECT Id, Product_Name__c, Efficacy_Sentiment__c, Safety_Sentiment__c, Indication_Sentiment__c, ' +
            'Side_Effects_Sentiment__c, Usage_Sentiment__c, Visit_Feedback__c ' +
            `FROM Visit_Product_Survey_Feedback__c WHERE Visit__c = '${esc(visit.Id)}' ORDER BY CreatedDate DESC LIMIT 50`
    );
    return {
        isLocked: visitLocked(visit),
        productOptions: options,
        sentimentOptions: SENTIMENT_OPTIONS,
        rows: rows.map((row) => ({
            id: row.Id,
            productName: row.Product_Name__c,
            efficacy: row.Efficacy_Sentiment__c,
            safety: row.Safety_Sentiment__c,
            indication: row.Indication_Sentiment__c,
            sideEffects: row.Side_Effects_Sentiment__c,
            usage: row.Usage_Sentiment__c,
            notes: row.Visit_Feedback__c
        }))
    };
});
