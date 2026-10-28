import { EGYPT_BOUNDS, escapeHtml, fitBoundsFor, isInEgypt, popupHtml } from '../distributorMapUtils';

describe('distributorMapUtils', () => {
    it('escapes HTML in popup values', () => {
        expect(escapeHtml(`<img src=x onerror="a('b')">&`)).toBe(
            '&lt;img src=x onerror=&quot;a(&#39;b&#39;)&quot;&gt;&amp;'
        );
        const html = popupHtml({
            clientName: '<script>alert(1)</script>',
            distributorCode: 'EPDA',
            address: 'a & b',
            pharmacyName: null,
            status: 'Unmatched'
        });
        expect(html).not.toContain('<script>');
        expect(html).toContain('&lt;script&gt;');
        expect(html).toContain('a &amp; b');
        expect(html).toContain('Unmatched');
    });

    it('recognises coordinates inside Egypt only', () => {
        expect(isInEgypt(30.04, 31.23)).toBe(true);
        expect(isInEgypt(0, 0)).toBe(false);
        expect(isInEgypt(48.8, 2.3)).toBe(false);
        expect(isInEgypt(null, 31)).toBe(false);
    });

    it('fits to in-Egypt markers and falls back to Egypt', () => {
        expect(fitBoundsFor([[30, 31], [0, 0], [31.2, 29.9]])).toEqual([[30, 31], [31.2, 29.9]]);
        expect(fitBoundsFor([[0, 0]])).toBe(EGYPT_BOUNDS);
        expect(fitBoundsFor([])).toBe(EGYPT_BOUNDS);
    });
});
