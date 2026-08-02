/**
 * Company branding for employee ID cards.
 */

const LOGO_AL_BORG = 'https://idhcorp.com/wp-content/uploads/2018/08/alborg-logo-1.png';
const LOGO_AL_MOKHTABAR = 'https://idhcorp.com/wp-content/uploads/2020/11/El-Mokhtabar.png';
const LOGO_IDH = 'https://idhcorp.com/wp-content/themes/idh/dist/img/logo-black.png';
const LOGO_BORG_SCAN = 'https://idhcorp.com/wp-content/uploads/2018/10/alborg-scan.png';

const COMPANY_BRANDS = {
    'Al Borg': {
        monogram: 'AB',
        logoUrl: LOGO_AL_BORG,
        headerColor: '#f2c200',
        headerColorDark: '#c9a000',
        monogramColor: '#1a1a1a'
    },
    'Al Mokhtabar': {
        monogram: 'AM',
        logoUrl: LOGO_AL_MOKHTABAR,
        headerColor: '#c8102e',
        headerColorDark: '#9b0d24',
        monogramColor: '#c8102e'
    },
    IDH: {
        monogram: 'IDH',
        logoUrl: LOGO_IDH,
        headerColor: '#c8102e',
        headerColorDark: '#1a1a1a',
        monogramColor: '#c8102e'
    },
    Borgscan: {
        monogram: 'BS',
        logoUrl: LOGO_BORG_SCAN,
        headerColor: '#1e56a0',
        headerColorDark: '#154177',
        monogramColor: '#1e56a0'
    },
    'Al Borg Scan': {
        monogram: 'ABS',
        logoUrl: LOGO_BORG_SCAN,
        headerColor: '#f2c200',
        headerColorDark: '#c9a000',
        monogramColor: '#1a1a1a'
    }
};

const DEFAULT_BRAND = {
    monogram: '—',
    headerColor: '#5b21b6',
    headerColorDark: '#4c1d95',
    monogramColor: '#5b21b6',
    logoUrl: null
};

/**
 * @param {string} company
 * @returns {{ monogram: string, headerColor: string, headerColorDark: string, monogramColor: string, logoUrl: string|null }}
 */
export function getCompanyBrand(company) {
    if (!company) {
        return { ...DEFAULT_BRAND, monogram: '?' };
    }
    const brand = COMPANY_BRANDS[company];
    if (!brand) {
        const initials = company
            .split(/\s+/)
            .filter(Boolean)
            .map((part) => part.charAt(0).toUpperCase())
            .join('')
            .slice(0, 3);
        return {
            ...DEFAULT_BRAND,
            monogram: initials || company.slice(0, 2).toUpperCase()
        };
    }
    return { ...DEFAULT_BRAND, ...brand, logoUrl: brand.logoUrl || null };
}
