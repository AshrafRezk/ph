const PACK_LIMIT = 255;

export const CITIES = [
    '6th of October City',
    'Abu ElMatamir',
    'Alexandria',
    'Assiut',
    'Aswan',
    'Banha',
    'Beni Suef',
    'Cairo',
    'Damanhur',
    'Damietta',
    'Fayoum',
    'Giza',
    'Heliopolis',
    'Hurghada',
    'Ismailia',
    'Kafr El Sheikh',
    'Luxor',
    'Maadi',
    'Mansoura',
    'Minya',
    'Nasr City',
    'Port Said',
    'Qena',
    'Sheikh Zayed',
    'Shibin El Kom',
    'Sohag',
    'Suez',
    'Tanta',
    'Zagazig'
];

const FIELD_ACTIVITY_LIMIT = 12;
const TEAM_MEETING_LIMIT = 2;

export const CATEGORIES = [
    {
        id: 'transportation',
        label: 'Transportation',
        icon: 'utility:trail',
        tone: 'tone-blue',
        kinds: ['car-service', 'parking', 'bus-transit']
    },
    {
        id: 'stay',
        label: 'Accommodation & Dining',
        icon: 'utility:home',
        tone: 'tone-rose',
        kinds: ['hotel', 'catering']
    },
    {
        id: 'operational',
        label: 'Operational',
        icon: 'utility:package',
        tone: 'tone-violet',
        kinds: ['courier', 'mobile']
    },
    {
        id: 'miscellaneous',
        label: 'Miscellaneous',
        icon: 'utility:record',
        tone: 'tone-slate',
        kinds: ['misc']
    }
];

export const KINDS = {
    'car-service': {
        id: 'car-service',
        label: 'Car Service',
        blurb: 'Maintenance, repair, and fuel expenses for company-approved vehicles.',
        tag: 'Fuel & repair',
        icon: 'utility:trail',
        tone: 'tone-blue'
    },
    parking: {
        id: 'parking',
        label: 'Parking',
        blurb: 'Official business-related parking fees and toll charges.',
        tag: 'Daily / monthly',
        icon: 'utility:checkin',
        tone: 'tone-amber'
    },
    'bus-transit': {
        id: 'bus-transit',
        label: 'Bus & Transit',
        blurb: 'Public transportation, tickets, taxis, and in-city allowances.',
        tag: 'Commute',
        icon: 'utility:trail',
        tone: 'tone-teal'
    },
    hotel: {
        id: 'hotel',
        label: 'Hotel Stay',
        blurb: 'Business trip accommodation and overnight lodging expenses.',
        tag: 'Lodging',
        icon: 'utility:home',
        tone: 'tone-rose'
    },
    catering: {
        id: 'catering',
        label: 'Catering & Meals',
        blurb: 'Field meals, overnight meals, team meetings, and travel allowances.',
        tag: 'Meals',
        icon: 'utility:retail_execution',
        tone: 'tone-amber'
    },
    courier: {
        id: 'courier',
        label: 'Courier Services',
        blurb: 'Shipping, postage, and document delivery for official business needs.',
        tag: 'Shipping',
        icon: 'utility:package',
        tone: 'tone-violet'
    },
    mobile: {
        id: 'mobile',
        label: 'Mobile & Internet',
        blurb: 'Monthly telecommunication bills and roaming charges for work lines.',
        tag: 'Telecom',
        icon: 'utility:call',
        tone: 'tone-violet'
    },
    misc: {
        id: 'misc',
        label: 'Others',
        blurb: 'Meeting rooms, tools, and other uncategorized business expenses.',
        tag: 'General',
        icon: 'utility:record',
        tone: 'tone-slate'
    }
};

const TYPE_BY_KIND = {
    'car-service': 'Fuel',
    parking: 'Parking',
    hotel: 'Accommodation',
    catering: 'Meal',
    courier: 'Others',
    mobile: 'Communication',
    misc: 'Others'
};

function text(key, label, required, extra = {}) {
    return { key, label, kind: 'text', required: Boolean(required), full: false, ...extra };
}

function area(key, label, required, extra = {}) {
    return { key, label, kind: 'textarea', required: Boolean(required), full: true, ...extra };
}

function date(key, label, required) {
    return { key, label, kind: 'date', required: Boolean(required), full: false };
}

function money(key, label, required, extra = {}) {
    return { key, label, kind: 'money', required: Boolean(required), full: false, ...extra };
}

function number(key, label, required, extra = {}) {
    return { key, label, kind: 'number', required: Boolean(required), full: false, ...extra };
}

function select(key, label, choices, required, extra = {}) {
    const options = [
        { key: `${key}-placeholder`, value: '', label: 'Select an option', disabled: true },
        ...choices.map((choice) =>
            typeof choice === 'string'
                ? { key: `${key}-${choice}`, value: choice, label: choice, disabled: false }
                : { key: `${key}-${choice.value}`, value: choice.value, label: choice.label, disabled: false }
        )
    ];
    return { key, label, kind: 'select', required: Boolean(required), full: true, options, ...extra };
}

function place(key, label, required, extra = {}) {
    return { key, label, kind: 'place', required: Boolean(required), full: false, placeholder: 'Search Egypt', ...extra };
}

function citySelect(key, label, required, _current) {
    return place(key, label, required);
}

function mealChoices(accommodation) {
    if (accommodation === 'B&B' || accommodation === 'Half Board') {
        return ['Lunch', 'Dinner'];
    }
    return ['Breakfast', 'Lunch', 'Dinner'];
}

export function fieldsFor(kindId, values = {}) {
    switch (kindId) {
        case 'car-service':
            return carFields(values);
        case 'parking':
            return [
                date('invoiceDate', 'Invoice Date', true),
                place('location', 'Location', true, { placeholder: 'Search where the vehicle was parked' }),
                money('value', 'Value', true),
                area('description', 'Description', false, { placeholder: 'What the parking or toll charge was for' })
            ];
        case 'bus-transit':
            return transitFields(values);
        case 'hotel':
            return [
                date('invoiceDate', 'Invoice Date', true),
                citySelect('location', 'Location', true, values.location),
                text('providerName', 'Provider Name', true, { placeholder: 'Hotel name' }),
                number('numberOfDays', 'Number Of Days', true, { integer: true, min: 1 }),
                select('roomType', 'Room Type', ['Single', 'Double', 'Twin'], true, { full: false }),
                select('accommodationType', 'Accommodation Type', ['Bed Only', 'B&B', 'Half Board'], true, { full: false }),
                money('value', 'Value', true)
            ];
        case 'catering':
            return cateringFields(values);
        case 'courier':
            return [
                date('invoiceDate', 'Invoice Date', true),
                place('shippedFrom', 'Shipped From Location', true),
                place('shippedTo', 'Shipped To Location', true),
                text('shipmentType', 'Shipment Type', true, { placeholder: 'Documents, samples, parcels' }),
                text('providerName', 'Provider Name', true),
                text('shippedToPerson', 'Shipped To Person', true),
                area('description', 'Description', false),
                money('value', 'Value', true)
            ];
        case 'mobile':
            return mobileFields(values);
        case 'misc':
            return miscFields(values);
        default:
            return [];
    }
}

function carFields(values) {
    const fields = [select('category', 'Category', ['Car Maintenance', 'Car Insurance'], true)];
    if (values.category === 'Car Insurance') {
        fields.push(
            date('invoiceDate', 'Invoice Date', true),
            date('policyIssuanceDate', 'Policy Issuance Date', true),
            date('policyExpiryDate', 'Policy Expiry Date', true),
            text('insuranceCompany', 'Insurance Company', true),
            money('value', 'Value', true)
        );
        return fields;
    }
    fields.push(select('maintenanceItem', 'Car Maintenance', ['Battery', 'Brake Pad', 'Tire'], true));
    fields.push(date('invoiceDate', 'Invoice Date', true));
    fields.push(text('providerName', 'Provider Name', true));
    fields.push(money('tax', 'Tax', true, { allowZero: true }));
    if (values.maintenanceItem === 'Tire') {
        fields.push(number('kilometerReading', 'Kilometer Reading', true, { integer: true, min: 1 }));
    }
    fields.push(money('value', 'Value', true));
    return fields;
}

function transitFields(values) {
    const fields = [select('transportationType', 'Transportation Type', ['Travel', 'In City'], true)];
    if (values.transportationType === 'In City') {
        fields.push(
            select(
                'cityType',
                'Type',
                ['Transportation Allowance', 'Taxi', 'Car Utilization Allowance', 'Daily Representative Expense'],
                true
            ),
            place('from', 'From', true),
            place('to', 'To', true),
            text('providerName', 'Provider Name', values.cityType === 'Taxi'),
            money('value', 'Value', true),
            area('description', 'Description', false),
            date('date', 'Date', true)
        );
        return fields;
    }
    fields.push(select('travelType', 'Travel Type', ['Kilometer Expense', 'Travel Ticket', 'Road Toll Ticket'], true));
    if (values.travelType === 'Kilometer Expense') {
        fields.push(
            citySelect('from', 'From', true, values.from),
            citySelect('to', 'To', true, values.to),
            money('value', 'Value', true, { hint: 'Enter the kilometer allowance for this route.' }),
            area('description', 'Description', false),
            date('invoiceDate', 'Invoice Date', true)
        );
        return fields;
    }
    fields.push(
        place('from', 'From', true),
        place('to', 'To', true),
        text('providerName', 'Provider Name', true),
        money('value', 'Value', true),
        area('description', 'Description', false),
        date('date', 'Date', true)
    );
    return fields;
}

function cateringFields(values) {
    const fields = [
        select('cateringType', 'Catering Type', ['Field Activity', 'Overnight Meal', 'Team Meeting', 'Travel Allowance'], true)
    ];
    if (values.cateringType === 'Overnight Meal') {
        fields.push(
            date('invoiceDate', 'Invoice Date', true),
            citySelect('location', 'Location', true, values.location),
            place('restaurant', 'Restaurant', true, { restaurants: true, full: true, placeholder: 'Search restaurants in Egypt' }),
            select('accommodationType', 'Accommodation Type', ['Bed Only', 'B&B', 'Half Board'], true, { full: false }),
            select('mealType', 'Meal Type', mealChoices(values.accommodationType), true, { full: false }),
            money('value', 'Value', true),
            select('uploadInvoice', 'Upload Invoice', ['YES', 'NO'], true, { full: false })
        );
        return fields;
    }
    if (values.cateringType === 'Team Meeting') {
        fields.push(
            date('invoiceDate', 'Invoice Date', true),
            citySelect('location', 'Location', true, values.location),
            place('restaurant', 'Restaurant', true, { restaurants: true, full: true, placeholder: 'Search restaurants in Egypt' }),
            select('meetingType', 'Meeting Type', ['Breakfast', 'Lunch', 'Dinner', 'Full day'], true, { full: false }),
            area('description', 'Description', false),
            money('value', 'Value', true, { hint: 'Use the allowance set for each person attending.' })
        );
        return fields;
    }
    if (values.cateringType === 'Travel Allowance') {
        fields.push(
            date('date', 'Date', true),
            citySelect('from', 'From', true, values.from),
            citySelect('to', 'To', true, values.to),
            number('distanceKm', 'Distance (km)', true, {
                hint: 'Only trips longer than 50 km qualify.'
            }),
            area('description', 'Description', false),
            money('value', 'Value', true, {
                min: 50,
                max: 70,
                hint: 'Refreshment allowance is between 50 and 70 EGP.'
            })
        );
        return fields;
    }
    fields.push(
        date('date', 'Date', true),
        citySelect('location', 'Location', true, values.location),
        place('restaurant', 'Restaurant', true, { restaurants: true, full: true, placeholder: 'Search restaurants in Egypt' }),
        money('value', 'Value', true, { hint: 'Use the meal allowance set for your title.' })
    );
    return fields;
}

function mobileFields(values) {
    const fields = [select('communicationType', 'Communication Type', ['Internet', 'Roaming', 'Voice Call'], true)];
    fields.push(date('invoiceDate', 'Invoice Date', true));
    if (values.communicationType === 'Voice Call') {
        fields.push(
            text('mobileNumber', 'Mobile Number', true, {
                placeholder: '1XXXXXXXXX',
                hint: 'Egyptian mobile number. Country code +20 is added for you.'
            })
        );
    } else {
        fields.push(text('providerName', 'Provider Name', true));
    }
    fields.push(money('value', 'Value', true));
    return fields;
}

function miscFields(values) {
    const fields = [select('miscType', 'Type', ['Meeting Room', 'Tool / Miscellaneous'], true)];
    if (values.miscType === 'Tool / Miscellaneous') {
        fields.push(date('invoiceDate', 'Invoice Date', true));
        fields.push(text('providerName', 'Provider Name', true));
    }
    fields.push(money('value', 'Value', true));
    fields.push(area('description', 'Description', values.miscType === 'Meeting Room'));
    return fields;
}

export function initialValues(kindId) {
    const today = new Date().toISOString().slice(0, 10);
    const common = {
        value: '',
        description: '',
        employees: [],
        destinations: []
    };
    switch (kindId) {
        case 'car-service':
            return {
                ...common,
                category: 'Car Maintenance',
                maintenanceItem: 'Battery',
                invoiceDate: today,
                providerName: '',
                tax: '',
                kilometerReading: '',
                insuranceCompany: '',
                policyIssuanceDate: '',
                policyExpiryDate: ''
            };
        case 'parking':
            return { ...common, invoiceDate: today, location: '' };
        case 'bus-transit':
            return {
                ...common,
                transportationType: 'Travel',
                travelType: 'Kilometer Expense',
                cityType: '',
                from: '',
                to: '',
                providerName: '',
                invoiceDate: today,
                date: today
            };
        case 'hotel':
            return {
                ...common,
                invoiceDate: today,
                location: '',
                providerName: '',
                numberOfDays: '',
                roomType: '',
                accommodationType: ''
            };
        case 'catering':
            return {
                ...common,
                cateringType: 'Field Activity',
                date: today,
                invoiceDate: today,
                location: '',
                accommodationType: '',
                mealType: '',
                uploadInvoice: 'NO',
                meetingType: '',
                from: '',
                to: '',
                distanceKm: ''
            };
        case 'courier':
            return {
                ...common,
                invoiceDate: today,
                shippedFrom: '',
                shippedTo: '',
                shipmentType: '',
                providerName: '',
                shippedToPerson: ''
            };
        case 'mobile':
            return {
                ...common,
                communicationType: 'Voice Call',
                invoiceDate: today,
                mobileNumber: '',
                providerName: ''
            };
        case 'misc':
            return { ...common, miscType: 'Meeting Room', invoiceDate: today, providerName: '' };
        default:
            return { ...common, invoiceDate: today, date: today };
    }
}

export function invoiceMode(kindId, values = {}) {
    if (kindId === 'catering' && values.cateringType === 'Overnight Meal') {
        return 'choice';
    }
    if (kindId === 'catering' && (values.cateringType === 'Field Activity' || values.cateringType === 'Travel Allowance')) {
        return 'hidden';
    }
    if (kindId === 'car-service' || kindId === 'parking' || kindId === 'hotel' || kindId === 'courier' || kindId === 'mobile') {
        return 'required';
    }
    if (kindId === 'bus-transit' && values.transportationType !== 'In City') {
        if (values.travelType === 'Travel Ticket' || values.travelType === 'Road Toll Ticket') {
            return 'required';
        }
    }
    if (kindId === 'misc' && values.miscType === 'Tool / Miscellaneous') {
        return 'required';
    }
    if (kindId === 'bus-transit' || kindId === 'misc' || (kindId === 'catering' && values.cateringType === 'Team Meeting')) {
        return 'optional';
    }
    return 'hidden';
}

export function showsEmployees(kindId, values = {}) {
    return kindId === 'catering' && (values.cateringType === 'Field Activity' || values.cateringType === 'Team Meeting');
}

export function showsRoute(kindId, values = {}) {
    if (kindId === 'bus-transit' && values.transportationType !== 'In City' && values.travelType === 'Kilometer Expense') {
        return true;
    }
    if (
        kindId === 'bus-transit' &&
        values.transportationType === 'In City' &&
        values.cityType === 'Car Utilization Allowance'
    ) {
        return true;
    }
    return kindId === 'catering' && values.cateringType === 'Travel Allowance';
}

export function showsDestinations(kindId, values = {}) {
    return (
        kindId === 'bus-transit' &&
        values.transportationType === 'In City' &&
        values.cityType === 'Car Utilization Allowance'
    );
}

export function policyNote(kindId, values = {}) {
    if (kindId !== 'catering') {
        if (kindId === 'bus-transit' && values.transportationType !== 'In City') {
            return 'Minibus and transit allowances do not need an invoice. Tickets and road tolls do.';
        }
        return '';
    }
    switch (values.cateringType) {
        case 'Field Activity':
            return 'For first-line managers on coaching visits. Up to 12 requests a month. Regional managers do not have a field activity allowance.';
        case 'Overnight Meal':
            return 'For someone traveling during an event who needs a meal that is not covered by the hotel. The meal list follows the accommodation type.';
        case 'Team Meeting':
            return 'For managers other than first-line. Allowance is a set amount per person, with up to 2 meetings a month.';
        case 'Travel Allowance':
            return 'Refreshment allowance for travel over 50 km. The amount must be between 50 and 70 EGP.';
        default:
            return '';
    }
}

export function typeFor(kindId, values = {}) {
    if (kindId === 'car-service' && values.category === 'Car Insurance') {
        return 'Transportation';
    }
    if (kindId === 'bus-transit') {
        if (values.transportationType !== 'In City' && values.travelType === 'Road Toll Ticket') {
            return 'Toll';
        }
        if (values.transportationType !== 'In City' && values.travelType === 'Travel Ticket') {
            return 'Transport';
        }
        return 'Transportation';
    }
    if (kindId === 'misc' && values.miscType === 'Meeting Room') {
        return 'Conference_Event';
    }
    return TYPE_BY_KIND[kindId] || 'Others';
}

export function primaryDate(kindId, values = {}) {
    return values.invoiceDate || values.date || '';
}

function cleanText(value) {
    return value == null ? '' : String(value).trim();
}

function monthKey(value) {
    const textValue = String(value || '');
    return /^\d{4}-\d{2}/.test(textValue) ? textValue.slice(0, 7) : '';
}

function countCatering(expenses, cateringType, isoDate, excludeId) {
    const month = monthKey(isoDate);
    if (!month) {
        return 0;
    }
    return (expenses || []).filter((row) => {
        if (excludeId && String(row.id || row.expenseId) === String(excludeId)) {
            return false;
        }
        const parsed = parsePacked(row.description);
        return (
            parsed.kindId === 'catering' &&
            parsed.values?.cateringType === cateringType &&
            monthKey(row.expenseDate) === month
        );
    }).length;
}

function storedValues(kindId, values, invoiceNames) {
    const stored = {};
    fieldsFor(kindId, values).forEach((field) => {
        const raw = values[field.key];
        if (raw == null || raw === '' || field.key === 'employees' || field.key === 'destinations') {
            return;
        }
        stored[field.key] = typeof raw === 'string' ? raw.trim() : raw;
    });
    if (showsEmployees(kindId, values) && Array.isArray(values.employees) && values.employees.length) {
        stored.employees = values.employees;
    }
    if (showsDestinations(kindId, values) && Array.isArray(values.destinations) && values.destinations.length) {
        stored.destinations = values.destinations.map((row) => ({
            from: row.from,
            to: row.to,
            km: row.km
        }));
    }
    if (invoiceNames?.length) {
        stored.invoiceFiles = invoiceNames.join(', ');
    }
    Object.keys(values).forEach((key) => {
        if ((/Lat$|Lng$/.test(key) || key === 'dayRoute') && values[key]) {
            stored[key] = values[key];
        }
    });
    if (values.tripDistanceKm) {
        stored.tripKm = String(values.tripDistanceKm).slice(0, 8);
    }
    if (values.tripFuelCost) {
        stored.fuelEgp = String(values.tripFuelCost).slice(0, 8);
    }
    if (values.tripTollNames) {
        stored.tolls = String(values.tripTollNames).slice(0, 60);
    }
    return stored;
}

export function packExpense(kindId, values, invoiceNames = []) {
    const packed = `§${kindId}|${JSON.stringify(storedValues(kindId, values, invoiceNames))}`;
    return packed.length <= PACK_LIMIT ? packed : null;
}

export function parsePacked(description) {
    const textValue = String(description || '');
    const match = textValue.match(/^§([a-z0-9-]+)\|(.*)$/s);
    if (!match) {
        return { kindId: null, values: null, summary: textValue };
    }
    const kindId = KINDS[match[1]] ? match[1] : null;
    if (!kindId) {
        return { kindId: null, values: null, summary: textValue };
    }
    if (match[2].startsWith('{')) {
        try {
            const values = JSON.parse(match[2]);
            return { kindId, values, summary: summaryFor(kindId, values) };
        } catch (_error) {
            return { kindId, values: null, summary: match[2] };
        }
    }
    return { kindId, values: null, summary: match[2] };
}

export function summaryFor(kindId, values = {}) {
    const kind = KINDS[kindId];
    const bits = [];
    if (kindId === 'car-service') {
        bits.push(values.category === 'Car Insurance' ? 'Car Insurance' : values.maintenanceItem || 'Car Maintenance');
    } else if (kindId === 'bus-transit') {
        bits.push(values.transportationType === 'In City' ? values.cityType || 'In City' : values.travelType || 'Travel');
    } else if (kindId === 'catering') {
        bits.push(values.cateringType || 'Meal');
        if (values.mealType) {
            bits.push(values.mealType);
        }
    } else if (kindId === 'mobile') {
        bits.push(values.communicationType || 'Communication');
    } else if (kindId === 'misc') {
        bits.push(values.miscType || 'Other');
    } else if (kind) {
        bits.push(kind.label);
    }
    const route = [values.from, values.to].filter(Boolean).join(' → ');
    if (route) {
        bits.push(route);
    }
    ['location', 'providerName', 'insuranceCompany', 'shippedToPerson', 'mobileNumber'].forEach((key) => {
        if (values[key]) {
            bits.push(String(values[key]));
        }
    });
    if (values.description) {
        bits.push(String(values.description));
    }
    return bits.filter(Boolean).join(' · ') || kind?.label || '';
}

export function detailLinesFor(kindId, values = {}) {
    if (!kindId || !values) {
        return [];
    }
    const skip = new Set(['value', 'invoiceDate', 'date']);
    const lines = [];
    fieldsFor(kindId, values).forEach((field) => {
        if (skip.has(field.key)) {
            return;
        }
        const raw = values[field.key];
        if (raw == null || raw === '') {
            return;
        }
        lines.push({ key: field.key, label: field.label, value: String(raw) });
    });
    if (Array.isArray(values.employees) && values.employees.length) {
        lines.push({ key: 'employees', label: 'Employees', value: values.employees.join(', ') });
    }
    if (Array.isArray(values.destinations) && values.destinations.length) {
        lines.push({
            key: 'destinations',
            label: 'Destinations',
            value: values.destinations.map((row) => `${row.from} → ${row.to} (${row.km} km)`).join('; ')
        });
    }
    if (values.dayRoute) {
        lines.push({ key: 'dayRoute', label: 'Day route', value: String(values.dayRoute) });
    }
    if (values.tripKm) {
        lines.push({ key: 'tripKm', label: 'Driving distance', value: `${values.tripKm} km` });
    }
    if (values.fuelEgp) {
        lines.push({ key: 'fuelEgp', label: 'Estimated fuel', value: `${values.fuelEgp} EGP` });
    }
    if (values.tolls) {
        lines.push({ key: 'tolls', label: 'Tolls', value: String(values.tolls) });
    }
    if (values.invoiceFiles) {
        lines.push({ key: 'invoiceFiles', label: 'Invoices', value: String(values.invoiceFiles) });
    }
    return lines;
}

export function displayFromDescription(description, fallbackLabel) {
    const parsed = parsePacked(description);
    if (!parsed.kindId) {
        return {
            typeLabel: fallbackLabel,
            descriptionLabel: description || '—',
            hasDescription: Boolean(description),
            detailLines: []
        };
    }
    const summary = parsed.summary || KINDS[parsed.kindId].label;
    return {
        typeLabel: KINDS[parsed.kindId].label,
        descriptionLabel: summary || '—',
        hasDescription: Boolean(summary),
        detailLines: parsed.values ? detailLinesFor(parsed.kindId, parsed.values) : []
    };
}

function kindFromType(typeValue) {
    switch (typeValue) {
        case 'Parking':
            return 'parking';
        case 'Fuel':
            return 'car-service';
        case 'Accommodation':
            return 'hotel';
        case 'Meal':
            return 'catering';
        case 'Communication':
            return 'mobile';
        case 'Toll':
        case 'Transport':
        case 'Transportation':
            return 'bus-transit';
        case 'Conference_Event':
            return 'misc';
        default:
            return 'misc';
    }
}

export function valuesFromExpense(expense) {
    const parsed = parsePacked(expense?.description);
    if (parsed.kindId && parsed.values) {
        return {
            kindId: parsed.kindId,
            values: {
                ...initialValues(parsed.kindId),
                ...parsed.values,
                mobileNumber: String(parsed.values.mobileNumber || '').replace(/^\+20/, ''),
                employees: Array.isArray(parsed.values.employees) ? parsed.values.employees : [],
                destinations: Array.isArray(parsed.values.destinations)
                    ? parsed.values.destinations.map((row, index) => ({
                          ...row,
                          id: row.id || `dest-${index}`
                      }))
                    : []
            }
        };
    }
    const kindId = kindFromType(expense?.typeValue);
    const dateValue = String(expense?.expenseDate || '').slice(0, 10);
    return {
        kindId,
        values: {
            ...initialValues(kindId),
            value: expense?.amount == null ? '' : String(expense.amount),
            invoiceDate: dateValue,
            date: dateValue,
            description: parsed.summary || ''
        }
    };
}

function checkNumber(field, raw) {
    const num = Number(raw);
    if (!Number.isFinite(num)) {
        return `Enter a valid ${field.label.toLowerCase()}.`;
    }
    if (field.integer && !Number.isInteger(num)) {
        return `${field.label} must be a whole number.`;
    }
    if (field.allowZero) {
        if (num < 0) {
            return `${field.label} cannot be negative.`;
        }
    } else if (field.min == null && num <= 0) {
        return `${field.label} must be greater than zero.`;
    }
    if (field.min != null && field.max != null && (num < field.min || num > field.max)) {
        return 'Travel allowance must be between 50 and 70 EGP.';
    }
    if (field.min != null && num < field.min) {
        if (field.key === 'distanceKm') {
            return 'Travel allowance is only for trips longer than 50 km.';
        }
        return `${field.label} must be at least ${field.min}.`;
    }
    if (field.max != null && num > field.max) {
        return `${field.label} must be at most ${field.max}.`;
    }
    return '';
}

export function validateExpense(kindId, values = {}, context = {}) {
    const fields = {};
    const defs = fieldsFor(kindId, values);
    defs.forEach((field) => {
        const raw = cleanText(values[field.key]);
        if (field.required && !raw) {
            fields[field.key] = `${field.label} is required.`;
            return;
        }
        if (!raw) {
            return;
        }
        if (field.kind === 'money' || field.kind === 'number') {
            const message = checkNumber(field, raw);
            if (message) {
                fields[field.key] = message;
            }
        }
        if (field.kind === 'date' && !/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
            fields[field.key] = `Enter a valid ${field.label.toLowerCase()}.`;
        }
    });

    if (kindId === 'car-service' && values.category === 'Car Insurance') {
        if (values.policyIssuanceDate && values.policyExpiryDate && values.policyExpiryDate <= values.policyIssuanceDate) {
            fields.policyExpiryDate = 'Policy expiry must be after the issuance date.';
        }
    }

    if (values.distanceKm) {
        const km = Number(values.distanceKm);
        if (Number.isFinite(km) && km <= 50) {
            fields.distanceKm = 'Travel allowance is only for trips longer than 50 km.';
        }
    }

    if (values.from && values.to && cleanText(values.from).toLowerCase() === cleanText(values.to).toLowerCase()) {
        fields.to = 'From and To must be different places.';
    }
    if (
        values.shippedFrom &&
        values.shippedTo &&
        cleanText(values.shippedFrom).toLowerCase() === cleanText(values.shippedTo).toLowerCase()
    ) {
        fields.shippedTo = 'Shipped from and shipped to must be different places.';
    }

    if (kindId === 'mobile' && values.communicationType === 'Voice Call' && values.mobileNumber) {
        const local = cleanText(values.mobileNumber).replace(/\s+/g, '');
        if (!/^1[0125]\d{8}$/.test(local)) {
            fields.mobileNumber = 'Enter a valid Egyptian mobile number, for example 1001234567.';
        }
    }

    if (showsEmployees(kindId, values)) {
        const people = Array.isArray(values.employees) ? values.employees.filter(Boolean) : [];
        if (!people.length) {
            fields.employees = 'Add at least one employee.';
        }
    }

    if (showsDestinations(kindId, values)) {
        const rows = Array.isArray(values.destinations) ? values.destinations : [];
        if (!rows.length) {
            fields.destinations = 'Add at least one destination for car utilization.';
        }
    }

    const mode = invoiceMode(kindId, values);
    const fileCount = Number(context.invoiceCount) || 0;
    if ((mode === 'required' || (mode === 'choice' && values.uploadInvoice === 'YES')) && fileCount < 1) {
        fields.invoiceFiles = 'Upload the electronic invoice.';
    }

    if (kindId === 'catering' && values.cateringType === 'Field Activity') {
        const fieldCount = countCatering(context.expenses, 'Field Activity', primaryDate(kindId, values), context.excludeId);
        if (fieldCount >= FIELD_ACTIVITY_LIMIT) {
            fields.cateringType = 'Field activity is limited to 12 requests per month.';
        }
    }

    if (kindId === 'catering' && values.cateringType === 'Team Meeting') {
        const meetingCount = countCatering(context.expenses, 'Team Meeting', primaryDate(kindId, values), context.excludeId);
        if (meetingCount >= TEAM_MEETING_LIMIT) {
            fields.cateringType = 'Team meetings are limited to 2 requests per month.';
        }
    }

    const names = context.invoiceNames || [];
    if (!Object.keys(fields).length && !packExpense(kindId, values, names)) {
        fields.description =
            'These details are too long to save. Shorten names, notes, or the employee list (255 characters altogether).';
    }

    const message = Object.keys(fields).length ? 'Check the highlighted fields before submitting.' : '';
    return { message, fields };
}

export function buildPayload(kindId, values, invoiceNames = []) {
    const mobile =
        kindId === 'mobile' && values.communicationType === 'Voice Call'
            ? { ...values, mobileNumber: `+20${cleanText(values.mobileNumber).replace(/\s+/g, '')}` }
            : values;
    return {
        typeValue: typeFor(kindId, mobile),
        amount: Number(mobile.value),
        expenseDate: primaryDate(kindId, mobile),
        description: packExpense(kindId, mobile, invoiceNames)
    };
}