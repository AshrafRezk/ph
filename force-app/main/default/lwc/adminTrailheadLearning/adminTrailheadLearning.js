import { LightningElement } from 'lwc';

const TRAILHEAD = 'https://trailhead.salesforce.com/content/learn/';

// Suggested order: start with reports and dashboards, then the admin basics.
const TRACKS = [
    {
        id: 'reports',
        title: '1. Reports and dashboards',
        blurb: 'Start here. Covers report types, filters, groupings, charts, and dashboards for managers.',
        items: [
            {
                id: 'rd-quick-look',
                kind: 'Module',
                title: 'Reports and Dashboards: Quick Look',
                blurb: 'A short first look at what reports and dashboards can show.',
                url: TRAILHEAD + 'modules/reports-dashboards-quick-look'
            },
            {
                id: 'rd-lex',
                kind: 'Module',
                title: 'Reports & Dashboards for Lightning Experience',
                blurb: 'Build reports, add filters and summaries, and put charts on a dashboard.',
                url: TRAILHEAD + 'modules/lex_implementation_reports_dashboards'
            }
        ]
    },
    {
        id: 'admin',
        title: '2. Salesforce administration',
        blurb: 'The basics every Zeta admin needs before changing users, access, or data.',
        items: [
            {
                id: 'admin-beginner',
                kind: 'Trail',
                title: 'Admin Beginner',
                blurb: 'Objects, fields, users, security, data, and the Lightning Experience setup screens.',
                url: TRAILHEAD + 'trails/force_com_admin_beginner'
            },
            {
                id: 'user-mgmt',
                kind: 'Module',
                title: 'User Management',
                blurb: 'Add and deactivate users, profiles, permission sets, and login access.',
                url: TRAILHEAD + 'modules/lex_implementation_user_setup_mgmt'
            },
            {
                id: 'data-security',
                kind: 'Module',
                title: 'Data Security',
                blurb: 'Who can see which records and fields, and how sharing works.',
                url: TRAILHEAD + 'modules/data_security'
            },
            {
                id: 'data-mgmt',
                kind: 'Module',
                title: 'Data Management',
                blurb: 'Import and export data safely, and when to use Data Loader.',
                url: TRAILHEAD + 'modules/lex_implementation_data_management'
            },
            {
                id: 'admin-intermediate',
                kind: 'Trail',
                title: 'Admin Intermediate',
                blurb: 'Next step after Admin Beginner: formulas, validation, automation, and more.',
                url: TRAILHEAD + 'trails/force_com_admin_intermediate'
            },
            {
                id: 'formulas',
                kind: 'Module',
                title: 'Formulas and Validations',
                blurb: 'Formula fields and validation rules, which also help with report columns.',
                url: TRAILHEAD + 'modules/point_click_business_logic'
            },
            {
                id: 'mobile',
                kind: 'Module',
                title: 'Salesforce Mobile App Customization',
                blurb: 'How the Salesforce mobile app shows records and actions to field users.',
                url: TRAILHEAD + 'modules/salesforce1_mobile_app'
            }
        ]
    }
];

export default class AdminTrailheadLearning extends LightningElement {
    get tracks() {
        return TRACKS;
    }
}
