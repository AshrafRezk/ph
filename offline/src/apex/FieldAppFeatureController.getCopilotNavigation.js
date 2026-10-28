import { plannerApiFetch } from './restHelper.js';
import { loadSavedNavRules, RETIRED_TABS } from './copilotNav.js';

const APPS = [
    {
        key: 'LightningSales',
        label: 'Field Co-pilot',
        tabs: [
            ['Field_Rep_Home_App', 'Home'],
            ['Field_Rep_Planner', 'Planner'],
            ['Accounts_Tab', 'Accounts'],
            ['My_Learning', 'My Learning'],
            ['Class_Engine', 'Class Engine'],
            ['CLM_Presentations', 'CLM Presentations'],
            ['Reports_Hub', 'Reports Hub'],
            ['Pharmacy_Sales_Dashboard', 'Pharmacy Sales'],
            ['My_Team', 'My Team'],
            ['standard-report', 'Reports'],
            ['standard-Dashboard', 'Dashboards'],
            ['Meetings_Home', 'Meetings'],
            ['Speaker__c', 'Speakers']
        ]
    },
    {
        key: 'Pharma_Management',
        label: 'Lead Co-pilot',
        tabs: [
            ['Management_Home', 'Workforce'],
            ['Field_Tracking', 'Field Tracking'],
            ['Reports_Hub', 'Reports Hub'],
            ['Pharmacy_Sales_Dashboard', 'Pharmacy Sales'],
            ['Field_Voice_Insights', 'Field Voice'],
            ['Admin_Console', 'Admin Console'],
            ['My_Learning', 'My Learning'],
            ['Accounts_Tab', 'Accounts'],
            ['standard-Dashboard', 'Dashboards'],
            ['standard-report', 'Reports']
        ]
    },
    {
        key: 'Pharma_SFE',
        label: 'SFE Co-pilot',
        tabs: [
            ['Admin_Console', 'Admin Console'],
            ['Accounts_Tab', 'Accounts'],
            ['Class_Engine', 'Class Engine'],
            ['Field_Rep_Planner', 'Planner'],
            ['Reports_Hub', 'Reports Hub'],
            ['Pharmacy_Sales_Dashboard', 'Pharmacy Sales'],
            ['Management_Home', 'Workforce'],
            ['Field_Tracking', 'Field Tracking'],
            ['KAM_Management_Dashboard', 'KAM Management'],
            ['My_Team', 'My Team'],
            ['CLM_Presentations', 'CLM Presentations'],
            ['standard-report', 'Reports'],
            ['standard-Dashboard', 'Dashboards']
        ]
    },
    {
        key: 'Care_Coach_Copilot',
        label: 'Care Coach Co-pilot',
        tabs: [
            ['Care_Coach_Home', 'Home'],
            ['Care_Coach_Patients', 'Patients'],
            ['Care_Coach_Planner', 'Planner'],
            ['Care_Coach_Products', 'Products'],
            ['Care_Coach_Orders', 'Orders'],
            ['Care_Coach_Knowledge', 'Knowledge']
        ]
    }
];

export default async function getCopilotNavigation() {
    let rules = {};
    try {
        rules = await loadSavedNavRules();
    } catch (_err) {
        rules = {};
    }
    let liveByApp = new Map();
    try {
        const data = await plannerApiFetch('/services/data/v62.0/ui-api/apps?formFactor=Large');
        for (const app of data?.apps || []) {
            const key = app.developerName;
            const items = app.navItems || app.items || [];
            liveByApp.set(
                key,
                items
                    .filter((item) => item && (item.developerName || item.name))
                    .map((item) => [item.developerName || item.name, item.label || item.developerName])
            );
        }
    } catch (_err) {
        liveByApp = new Map();
    }
    return APPS.map((app) => {
        const saved = rules[app.key];
        const hasSaved = saved && Object.keys(saved).length > 0;
        const merged = new Map(app.tabs);
        for (const pair of liveByApp.get(app.key) || []) {
            if (!merged.has(pair[0])) merged.set(pair[0], pair[1]);
        }
        return {
            key: app.key,
            label: app.label,
            tabs: [...merged.entries()].map(([key, label]) => ({
                key,
                label: (hasSaved && saved[key]?.label) || label,
                enabled: hasSaved ? saved[key]?.enabled === true : !RETIRED_TABS.has(key)
            }))
        };
    });
}
