import { onSalesPreview, batches } from './sampleSalesMapping.js';

export default async function getImportBatches() {
    if (!onSalesPreview()) {
        return null;
    }
    return batches;
}
