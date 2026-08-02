import { mergeRatingValues, hasMeaningfulValue } from 'c/ratingValueMerge';

describe('c/ratingValueMerge', () => {
    it('keeps fallback when live emits empty strings', () => {
        const fallback = {
            Is_KOL__c: true,
            KOL_In_What__c: 'High Prescriber',
            Potential__c: 'A'
        };
        const live = {
            KOL_In_What__c: '',
            Potential__c: 'B'
        };

        const merged = mergeRatingValues(fallback, live);

        expect(merged.KOL_In_What__c).toBe('High Prescriber');
        expect(merged.Potential__c).toBe('B');
    });

    it('applies explicit toggle values from live state', () => {
        const fallback = { Is_KOL__c: true, KOL_In_What__c: 'High Prescriber' };
        const live = { Is_KOL__c: false };

        const merged = mergeRatingValues(fallback, live);

        expect(merged.Is_KOL__c).toBe(false);
        expect(merged.KOL_In_What__c).toBe('High Prescriber');
    });

    it('treats booleans as meaningful values', () => {
        expect(hasMeaningfulValue(false)).toBe(true);
        expect(hasMeaningfulValue('')).toBe(false);
        expect(hasMeaningfulValue('Weekly')).toBe(true);
    });
});
