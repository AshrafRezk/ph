import { onSalesPreview, doctorOptions } from './sampleSalesMapping.js';

export default async function searchRatedDoctors() {
    if (!onSalesPreview()) {
        return null;
    }
    return doctorOptions;
}
