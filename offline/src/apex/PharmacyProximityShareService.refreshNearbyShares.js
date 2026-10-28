import { onSalesPreview, shareReview } from './sampleSalesMapping.js';

export default async function refreshNearbyShares() {
    if (!onSalesPreview()) {
        return null;
    }
    return shareReview;
}
