import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

export default makeDualApex(async () => {
    try {
        const describe = await plannerApiFetch('/services/data/v59.0/sobjects/Account/describe', {
            method: 'GET'
        });
        const infos = describe?.recordTypeInfos || [];
        const preferred = [
            'PersonAccount',
            'Medical_Professional_HCP',
            'Institution_HCO',
            'Pharmacy',
            'Business_Contact',
            'SDO_PersonAccounts'
        ];
        const labels = {
            PersonAccount: 'HCP (Medical Professional)',
            Medical_Professional_HCP: 'HCP (Organization)',
            Institution_HCO: 'HCO (Institution)',
            Pharmacy: 'Pharmacy',
            Business_Contact: 'Business Contact',
            SDO_PersonAccounts: 'HCP (Person Account)'
        };
        const options = [];
        for (const dev of preferred) {
            const info = infos.find((rt) => rt.developerName === dev && rt.available && !rt.master);
            if (!info) continue;
            options.push({
                recordTypeId: info.recordTypeId,
                developerName: dev,
                label: labels[dev] || info.name,
                description: info.name,
                iconName: 'standard:account',
                isPersonAccount: Boolean(info.personAccount || String(dev).includes('Person'))
            });
        }
        if (options.length) return options;
    } catch (_e) {
        // fall through
    }
    return [
        {
            recordTypeId: null,
            developerName: 'PersonAccount',
            label: 'HCP (Medical Professional)',
            description: 'Create a doctor / specialist account.',
            iconName: 'standard:person_account',
            isPersonAccount: true
        }
    ];
});
