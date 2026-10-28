import { onSalesPreview, selloutRows } from './sampleSalesMapping.js';

export default async function getSelloutAliases() {
    if (!onSalesPreview()) {
        return null;
    }
    return selloutRows;
}
