import { onSalesPreview, productNav } from './sampleSalesMapping.js';

export default async function getProductMappingNav() {
    if (!onSalesPreview()) {
        return null;
    }
    return productNav;
}
