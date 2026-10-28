import { plannerApiFetch } from './restHelper.js';

const CACHE_KEY = 'zeta.pwa.plannerViewerContext';

function readCachedContext() {
    try {
        const raw = window.localStorage.getItem(CACHE_KEY);
        return raw ? JSON.parse(raw) : null;
    } catch (_err) {
        return null;
    }
}

function writeCachedContext(context) {
    try {
        window.localStorage.setItem(CACHE_KEY, JSON.stringify(context));
    } catch (_err) {
        /* ignore quota / private mode */
    }
}

export default async function getPlannerViewerContext() {
    try {
        const context = await plannerApiFetch('/services/apexrest/planner/v1/viewer-context');
        if (context) {
            writeCachedContext(context);
        }
        return context;
    } catch (error) {
        const cached = readCachedContext();
        if (cached) {
            return cached;
        }
        throw error;
    }
}
