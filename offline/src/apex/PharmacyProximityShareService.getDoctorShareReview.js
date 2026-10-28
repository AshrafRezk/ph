import { onSalesPreview, shareReview } from './sampleSalesMapping.js';

export default async function getDoctorShareReview() {
    if (!onSalesPreview()) {
        return null;
    }
    return shareReview;
}
