import { plannerApiFetch } from './restHelper.js';

export const COPILOT_APP_KEYS = [
    'LightningSales',
    'PharmaField',
    'Pharma_Management',
    'Pharma_SFE',
    'Care_Coach_Copilot'
];

const NAV_APPS = ['Care_Coach_Copilot', 'Pharma_Management', 'Pharma_SFE', 'LightningSales', 'PharmaField'];

export const RETIRED_TABS = new Set([
    'Meetings_Home',
    'Meeting__c',
    'Meeting_Accounting',
    'Speaker__c',
    'Topic__c',
    'Location__c',
    'Budget__c',
    'Meeting_Workflow__c',
    'Meeting_Workflow_Admin'
]);

export function isSfeProfile() {
    try {
        const raw = localStorage.getItem('zeta.pwa.sfUserProfile');
        const profile = raw ? JSON.parse(raw) : {};
        const name = String(profile.profileName || profile.name || '').toLowerCase();
        return /sfe|system administrator|salesforce admin/.test(name);
    } catch (_err) {
        return false;
    }
}

export function isHiddenLauncherApp(app) {
    const name = String(app?.developerName || '').toLowerCase();
    const label = String(app?.label || '').toLowerCase();
    if (name === 'meetings' || name === 'meetings_admin' || label === 'meetings' || label === 'meetings admin') {
        return true;
    }
    if (name === 'almdevops' || label.includes('lifecycle center')) {
        return !isSfeProfile();
    }
    return false;
}

function parseNavKey(featureKey) {
    const key = String(featureKey || '');
    for (const app of NAV_APPS) {
        const prefix = `nav.${app}.`;
        if (key.startsWith(prefix)) {
            return { app, tab: key.slice(prefix.length) };
        }
    }
    return null;
}

export async function loadSavedNavRules() {
    const soql =
        'SELECT Feature_Key__c, Name, Is_Enabled__c, Sort_Order__c FROM Field_App_Feature__c WHERE Feature_Key__c LIKE \'nav.%\'';
    const data = await plannerApiFetch(`/services/data/v62.0/query?q=${encodeURIComponent(soql)}`);
    const byApp = {};
    for (const row of data?.records || []) {
        const parsed = parseNavKey(row.Feature_Key__c);
        if (!parsed) continue;
        if (!byApp[parsed.app]) byApp[parsed.app] = {};
        byApp[parsed.app][parsed.tab] = {
            enabled: row.Is_Enabled__c === true,
            label: row.Name,
            sort: Number(row.Sort_Order__c) || 0
        };
    }
    return byApp;
}

export function applyCopilotPolicy(apps, rulesByApp) {
    return (apps || [])
        .filter((app) => !isHiddenLauncherApp(app))
        .map((app) => {
            const rules = rulesByApp && (rulesByApp[app.developerName] || null);
            let tabs = Array.isArray(app.tabs) ? app.tabs.slice() : [];
            if (rules && Object.keys(rules).length) {
                const byKey = new Map(tabs.map((tab) => [tab.key, tab]));
                tabs = Object.entries(rules)
                    .filter(([, row]) => row.enabled)
                    .sort((left, right) => left[1].sort - right[1].sort)
                    .map(([key, row]) => byKey.get(key) || { key, label: row.label || key, type: 'TabFlexiPage' });
            } else {
                tabs = tabs.filter(
                    (tab) => !RETIRED_TABS.has(tab.key) && !/^speakers?$/i.test(String(tab.label || '').trim())
                );
            }
            return { ...app, tabs };
        });
}
