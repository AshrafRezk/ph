import { loadHomeDashboard } from './homeDashboard.js';

// Same call (and per-territory saved copy) as the Home cards.
export default async function getHomeDashboard(params = {}) {
    return loadHomeDashboard(params);
}
