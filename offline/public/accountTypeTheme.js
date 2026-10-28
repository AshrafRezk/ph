const HCP_RECORD_TYPES = new Set([
    'SDO_PersonAccounts',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact'
]);

export const ACCOUNT_THEME = {
    pharmacy: {
        kind: 'pharmacy',
        label: 'Pharmacy',
        color: '#176935',
        ink: '#ffffff',
        soft: '#e8f4ec',
        border: '#b7dcc4',
        iconUrl: '/icons/account/pharmacy.png'
    },
    hco: {
        kind: 'hco',
        label: 'HCO',
        color: '#fdbf29',
        ink: '#3a2a00',
        soft: '#fff6dc',
        border: '#f3d98a',
        iconUrl: '/icons/account/hco.png'
    },
    hcp: {
        kind: 'hcp',
        label: 'HCP',
        color: '#3f7de5',
        ink: '#ffffff',
        soft: '#eaf1fc',
        border: '#c5d7f6',
        iconUrl: '/icons/account/hcp.png'
    },
    account: {
        kind: 'account',
        label: 'Account',
        color: '#032d60',
        ink: '#ffffff',
        soft: '#eef2f6',
        border: '#c9d3df',
        iconUrl: ''
    }
};

export function resolveAccountThemeKind(recordTypeDeveloperName, recordTypeName) {
    const developerName = recordTypeDeveloperName || '';
    const label = String(recordTypeName || '').toLowerCase();
    if (developerName === 'Pharmacy' || label.includes('pharmacy')) {
        return 'pharmacy';
    }
    if (
        HCP_RECORD_TYPES.has(developerName) ||
        label.includes('hcp') ||
        label.includes('doctor') ||
        label.includes('professional') ||
        label.includes('person')
    ) {
        return 'hcp';
    }
    if (
        developerName === 'Institution_HCO' ||
        label.includes('hco') ||
        label.includes('institution') ||
        label.includes('clinic') ||
        label.includes('hospital')
    ) {
        return 'hco';
    }
    return 'account';
}

export function accountThemeFor(recordTypeDeveloperName, recordTypeName) {
    const kind = resolveAccountThemeKind(recordTypeDeveloperName, recordTypeName);
    return ACCOUNT_THEME[kind] || ACCOUNT_THEME.account;
}
