export function onSalesPreview() {
    return typeof window !== 'undefined' && /sales-mapping-preview/.test(window.location.pathname);
}

export const accuracy = {
    productAliases: 858,
    productsConfirmed: 809,
    productAccuracy: 94.3,
    sellouts: 4770,
    selloutsMapped: 4120,
    pharmacyAccuracy: 86.4,
    matchedByCode: 2910,
    matchedByName: 820,
    matchedByMap: 280,
    matchedBySfe: 110,
    needsReview: 650
};

export const geocodeStatus = {
    hasGoogleKey: true,
    providerLabel: 'Google Geocoding, then Google Places',
    proximityMeters: 150,
    autoConfirmThreshold: 85
};

export const productNav = {
    distributors: [
        { key: 'IBNSINA', label: 'IBNSINA', count: 251 },
        { key: 'POS', label: 'POS', count: 170 },
        { key: 'Sofico', label: 'Sofico', count: 102 },
        { key: 'Elezaby', label: 'Elezaby', count: 92 },
        { key: 'Ebda', label: 'EPDA', count: 91 },
        { key: 'Egydrug', label: 'Egydrug', count: 81 }
    ],
    productLines: []
};

export const productRows = [
    rowProduct('1', 'IBNSINA', '44120', 'EMPACOZA 10/5 MG 30 TAB', 'Empacoza 10', 'Ep10', 'DIAB', 100, 'ExactCode', 'Confirmed'),
    rowProduct('2', 'Sofico', '1015473', 'EMPACOZA PLUS 25/5 MG 30 TAB', 'Empacoza Plus', 'Ep25', 'DIAB', 100, 'ExactCode', 'Confirmed'),
    rowProduct('3', 'Egydrug', '99258', 'DOZOVA 10 MG 30 TAB', 'Dozova', 'Dz10', 'GIT', 92, 'FuzzyName', 'Suggested'),
    rowProduct('4', 'Elezaby', '622400', 'NEXICURE 14 TAB', 'Nexicure', 'Nx14', 'CHC', 88, 'FuzzyName', 'Suggested'),
    rowProduct('5', 'POS', '88011', 'ZETACOLEST PLUS', 'Zetacolest Plus', 'ZcP', 'CHC', 100, 'ExactCode', 'Confirmed')
];

export const selloutRows = [
    rowSellout('s1', 'IBNSINA', '1508821', 'El Ezaby Zamalek', '26th July, Zamalek', 'Cairo', 'El Ezaby Zamalek', 100, 'ExactCode', 'Geocoded', 'Confirmed'),
    rowSellout('s2', 'Sofico', '22019', 'Seif Pharmacy Mohandessin', 'Gameat El Dewal', 'Giza', 'Seif Pharmacy Mohandessin', 86, 'GeoProximity+Pharmacy', 'Geocoded', 'Suggested'),
    rowSellout('s3', 'Egydrug', '44190', '19011 Pharmacy Dokki', 'Dokki St', 'Giza', '19011 Pharmacy', 74, 'FuzzyName', 'Geocoded', 'Suggested'),
    rowSellout('s4', 'POS', '7731', 'Unknown client Giza', '', 'Giza', '', null, '', 'Failed', 'Unmatched')
];

export const batches = [
    {
        batchId: 'b1',
        fileName: 'Ibnsina monthly June.xlsx',
        distributorCode: 'IBNSINA',
        status: 'Completed',
        rowsInserted: 1840,
        rowsUpdated: 120,
        rowsFailed: 14,
        aliasesCreated: 40,
        needsReview: 96
    },
    {
        batchId: 'b2',
        fileName: 'Ebda week 14 June.xlsx',
        distributorCode: 'EPDA',
        status: 'Needs review',
        rowsInserted: 640,
        rowsUpdated: 22,
        rowsFailed: 8,
        aliasesCreated: 18,
        needsReview: 54
    }
];

export const doctorOptions = [
    {
        doctorId: 'doc1',
        doctorName: 'Ahmed Ali 49',
        ratedProducts: 'Empacoza, Nexicure'
    }
];

export const shareReview = {
    doctorId: 'doc1',
    doctorName: 'Ahmed Ali 49',
    ratedProducts: 'Empacoza, Nexicure',
    hasRating: true,
    shareTotal: 100,
    message:
        'Closer pharmacies start with a higher share. Adjust the percents so they still add up to 100, then save.',
    pharmacies: [
        {
            affiliationId: 'aff1',
            pharmacyId: 'ph1',
            pharmacyName: 'El Ezaby Zamalek',
            distanceMeters: 80,
            orderSharePercent: 63.64
        },
        {
            affiliationId: 'aff2',
            pharmacyId: 'ph2',
            pharmacyName: 'Seif Pharmacy Mohandessin',
            distanceMeters: 210,
            orderSharePercent: 24.24
        },
        {
            affiliationId: 'aff3',
            pharmacyId: 'ph3',
            pharmacyName: '19011 Pharmacy Dokki',
            distanceMeters: 420,
            orderSharePercent: 12.12
        }
    ]
};

function rowProduct(recordId, distributorCode, itemCode, itemName, productName, zetaCode, productFamily, confidence, matchMethod, status) {
    return {
        recordId,
        distributorCode,
        itemCode,
        itemName,
        productId: 'p1',
        productName,
        productUrl: '#',
        productFamily,
        zetaCode,
        confidence,
        matchMethod,
        status
    };
}

function rowSellout(recordId, distributorCode, clientCode, clientName, address, governorate, pharmacyName, confidence, matchMethod, geocodeStatus, status) {
    return {
        recordId,
        recordUrl: '#',
        distributorCode,
        clientCode,
        clientName,
        address,
        governorate,
        pharmacyId: pharmacyName ? 'ph' : null,
        pharmacyName: pharmacyName || null,
        pharmacyUrl: pharmacyName ? '#' : null,
        confidence,
        matchMethod,
        geocodeStatus,
        geocodeMessage: geocodeStatus === 'Failed' ? 'Google Places found no business at this name and area.' : '',
        geocodeRecommendation: geocodeStatus === 'Failed' ? 'Search and link an existing pharmacy, or reject the row.' : '',
        status
    };
}
