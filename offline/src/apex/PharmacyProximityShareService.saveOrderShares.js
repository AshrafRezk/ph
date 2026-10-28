import { onSalesPreview, shareReview } from './sampleSalesMapping.js';

export default async function saveOrderShares() {
    if (!onSalesPreview()) {
        return null;
    }
    return shareReview;
}
