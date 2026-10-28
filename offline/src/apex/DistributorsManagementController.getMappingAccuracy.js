import { onSalesPreview, accuracy } from './sampleSalesMapping.js';

export default async function getMappingAccuracy() {
    if (!onSalesPreview()) {
        return null;
    }
    return accuracy;
}
