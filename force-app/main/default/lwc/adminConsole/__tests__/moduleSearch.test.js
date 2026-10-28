import { tokenize, buildSearchTokens, matchesQuery } from '../moduleSearch';

const sampleLogistics = {
    title: 'Sample Logistics',
    description: 'Take sample and brand-reminder requests, allocate lots to reps, and record transfers and returns.',
    titleAr: 'لوجستيات العينات',
    keywords: ['expiry', 'inventory']
};
const territory = {
    title: 'Territory Management',
    description: 'Manage product lines, the territory tree, and the people seated on each territory.',
    titleAr: 'إدارة الأقاليم',
    keywords: ['users', 'hierarchy']
};
const callTarget = {
    title: 'Call Target Rules',
    description: 'Lower the monthly call target after approved time off, office work, and meetings.',
    keywords: ['tot', 'leave']
};

const idx = (card, group) => buildSearchTokens(card, group);

describe('moduleSearch', () => {
    it('folds simple plurals so "samples" finds Sample Logistics', () => {
        expect(matchesQuery(idx(sampleLogistics, 'Territory, products & plans'), 'samples')).toBe(true);
    });

    it('matches visible group labels, not internal ids', () => {
        const tokens = idx(territory, 'Territory, products & plans');
        expect(matchesQuery(tokens, 'territory, products')).toBe(true);
        expect(matchesQuery(idx(callTarget, 'Performance & targets'), 'territory, products')).toBe(false);
    });

    it('matches keywords and word prefixes', () => {
        expect(matchesQuery(idx(territory, ''), 'users')).toBe(true);
        expect(matchesQuery(idx(territory, ''), 'hier')).toBe(true);
        expect(matchesQuery(idx(callTarget, ''), 'TOT')).toBe(true);
        expect(matchesQuery(idx(callTarget, ''), 'time off')).toBe(true);
    });

    it('requires every typed word to match', () => {
        expect(matchesQuery(idx(callTarget, ''), 'call holidays')).toBe(false);
    });

    it('matches Arabic names, ignoring alef and taa marbuta variants', () => {
        expect(matchesQuery(idx(territory, ''), 'الاقاليم')).toBe(true);
        expect(matchesQuery(idx(sampleLogistics, ''), 'العينات')).toBe(true);
        expect(matchesQuery(idx(sampleLogistics, ''), 'الأقاليم')).toBe(false);
    });

    it('treats an empty query as a match', () => {
        expect(matchesQuery(idx(callTarget, ''), '   ')).toBe(true);
        expect(tokenize('')).toEqual([]);
    });
});
