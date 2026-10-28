import { onSalesPreview, geocodeStatus } from './sampleSalesMapping.js';

export default async function getGeocodeConfigStatus() {
    if (!onSalesPreview()) {
        return null;
    }
    return geocodeStatus;
}
