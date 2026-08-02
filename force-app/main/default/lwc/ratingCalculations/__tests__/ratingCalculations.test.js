import { applyCalculatedValues } from 'c/ratingCalculations';

describe('c/ratingCalculations', () => {
    it('preserves KOL reason when Is_KOL__c is absent but reason is set', () => {
        const result = applyCalculatedValues(
            [],
            { KOL_In_What__c: 'Key Scientific Leader' },
            'HCP'
        );

        expect(result.KOL_In_What__c).toBe('Key Scientific Leader');
        expect(result.Is_KOL__c).toBe(true);
    });

    it('clears KOL reason when Is_KOL__c is explicitly false', () => {
        const result = applyCalculatedValues(
            [],
            {
                Is_KOL__c: false,
                KOL_In_What__c: 'High Prescriber'
            },
            'HCP'
        );

        expect(result.KOL_In_What__c).toBe('');
        expect(result.Is_KOL__c).toBe(false);
    });
});
