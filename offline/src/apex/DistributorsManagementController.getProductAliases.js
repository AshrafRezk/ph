import { onSalesPreview, productRows } from './sampleSalesMapping.js';

export default async function getProductAliases() {
    if (!onSalesPreview()) {
        return null;
    }
    return productRows;
}
