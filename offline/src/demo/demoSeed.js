/**
 * Shared fictional seed for the store-review demo. Every fixture builds from these records
 * so Home, Planner, Accounts, visits and CLM tell one consistent story.
 * Names are invented. Ids are 18 characters with a DEMO marker.
 */

export const DEMO_USER_ID = '005DEMO00000000001';
export const DEMO_MANAGER_ID = '005DEMO00000000002';
export const DEMO_TERRITORY = {
    id: '0MIDEMO00000000001',
    name: 'DEMO CARDIO CAIRO-EAST',
    line: 'CARDIO',
    district: 'DEMO DM CAIRO',
    managerName: 'Demo District Manager'
};

/** Local calendar date (not UTC) as yyyy-mm-dd. */
const iso = (d) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

/** Today in the device time zone, as yyyy-mm-dd. */
export function todayIso() {
    return iso(new Date());
}

export function addDays(dateIso, days) {
    const d = new Date(`${dateIso}T00:00:00`);
    d.setDate(d.getDate() + days);
    return iso(d);
}

export const DEMO_PRODUCTS = [
    { id: '01tDEMO00000000001', name: 'Cardiora 10 mg', code: 'DEMO-CRD10', brand: 'Cardiora', type: 'Detail' },
    { id: '01tDEMO00000000002', name: 'Cardiora 20 mg', code: 'DEMO-CRD20', brand: 'Cardiora', type: 'Detail' },
    { id: '01tDEMO00000000003', name: 'Lipovia 40 mg', code: 'DEMO-LPV40', brand: 'Lipovia', type: 'Detail' },
    { id: '01tDEMO00000000004', name: 'Glucoset XR 500 mg', code: 'DEMO-GLX500', brand: 'Glucoset', type: 'Detail' },
    { id: '01tDEMO00000000005', name: 'Cardiora 10 mg sample pack', code: 'DEMO-CRD10-S', brand: 'Cardiora', type: 'Sample' }
];

/**
 * channel: AM = hospital, PM = clinic / pharmacy (Zeta rule).
 * classCode: A/B/C call class. frequency: planned calls per month.
 */
export const DEMO_ACCOUNTS = [
    { id: '001DEMO00000000001', name: 'Dr. Karim Nabil', kind: 'HCP', specialty: 'Cardiology', classCode: 'A', frequency: 4, channel: 'PM', city: 'Nasr City', brick: 'Nasr City 1', lat: 30.0561, lng: 31.3302, phone: '+20 100 000 0001' },
    { id: '001DEMO00000000002', name: 'Dr. Laila Samir', kind: 'HCP', specialty: 'Internal Medicine', classCode: 'A', frequency: 4, channel: 'AM', city: 'Heliopolis', brick: 'Heliopolis 2', lat: 30.0911, lng: 31.3226, phone: '+20 100 000 0002' },
    { id: '001DEMO00000000003', name: 'Dr. Omar Fathy', kind: 'HCP', specialty: 'Cardiology', classCode: 'B', frequency: 2, channel: 'AM', city: 'Abbassia', brick: 'Abbassia 1', lat: 30.0722, lng: 31.2831, phone: '+20 100 000 0003' },
    { id: '001DEMO00000000004', name: 'Dr. Nour Hassan', kind: 'HCP', specialty: 'Endocrinology', classCode: 'B', frequency: 2, channel: 'PM', city: 'Nasr City', brick: 'Nasr City 2', lat: 30.0626, lng: 31.3455, phone: '+20 100 000 0004' },
    { id: '001DEMO00000000005', name: 'Dr. Youssef Adel', kind: 'HCP', specialty: 'General Practice', classCode: 'C', frequency: 1, channel: 'PM', city: 'Heliopolis', brick: 'Heliopolis 1', lat: 30.0866, lng: 31.3402, phone: '+20 100 000 0005' },
    { id: '001DEMO00000000006', name: 'Dr. Mariam Tarek', kind: 'HCP', specialty: 'Cardiology', classCode: 'A', frequency: 4, channel: 'AM', city: 'Abbassia', brick: 'Abbassia 2', lat: 30.0705, lng: 31.2905, phone: '+20 100 000 0006' },
    { id: '001DEMO00000000007', name: 'Dr. Hany Mostafa', kind: 'HCP', specialty: 'Internal Medicine', classCode: 'B', frequency: 2, channel: 'PM', city: 'Nasr City', brick: 'Nasr City 1', lat: 30.0499, lng: 31.3378, phone: '+20 100 000 0007' },
    { id: '001DEMO00000000008', name: 'Demo Heart Clinic', kind: 'Clinic', specialty: 'Cardiology', classCode: 'B', frequency: 2, channel: 'PM', city: 'Heliopolis', brick: 'Heliopolis 2', lat: 30.0944, lng: 31.3301, phone: '+20 100 000 0008' },
    { id: '001DEMO00000000009', name: 'Nile Demo Pharmacy', kind: 'Pharmacy', specialty: 'Pharmacy', classCode: 'A', frequency: 4, channel: 'PM', city: 'Nasr City', brick: 'Nasr City 2', lat: 30.0588, lng: 31.3511, phone: '+20 100 000 0009' },
    { id: '001DEMO00000000010', name: 'Cairo Demo Pharmacy', kind: 'Pharmacy', specialty: 'Pharmacy', classCode: 'B', frequency: 2, channel: 'PM', city: 'Abbassia', brick: 'Abbassia 1', lat: 30.0741, lng: 31.2799, phone: '+20 100 000 0010' },
    { id: '001DEMO00000000011', name: 'Demo General Hospital', kind: 'Hospital', specialty: 'Hospital', classCode: 'A', frequency: 4, channel: 'AM', city: 'Abbassia', brick: 'Abbassia 2', lat: 30.0689, lng: 31.2867, phone: '+20 100 000 0011' },
    { id: '001DEMO00000000012', name: 'Dr. Salma Ibrahim', kind: 'HCP', specialty: 'Endocrinology', classCode: 'C', frequency: 1, channel: 'PM', city: 'Heliopolis', brick: 'Heliopolis 1', lat: 30.0899, lng: 31.3188, phone: '+20 100 000 0012' }
];

/**
 * Visits relative to today: past days are Completed, today has two Planned and one Completed,
 * the coming days are Planned. Ids are stable so a visit opened from Home matches the Planner.
 */
export function demoVisits() {
    const today = todayIso();
    const plan = [
        { day: -6, account: 1, status: 'Completed', time: '10:00' },
        { day: -6, account: 9, status: 'Completed', time: '12:30' },
        { day: -5, account: 2, status: 'Completed', time: '09:30' },
        { day: -4, account: 6, status: 'Completed', time: '11:00' },
        { day: -3, account: 11, status: 'Completed', time: '10:30' },
        { day: -2, account: 4, status: 'Completed', time: '13:00' },
        { day: -1, account: 7, status: 'Completed', time: '10:00' },
        { day: 0, account: 1, status: 'Completed', time: '09:30' },
        { day: 0, account: 3, status: 'Planned', time: '11:30' },
        { day: 0, account: 9, status: 'Planned', time: '13:30' },
        { day: 1, account: 2, status: 'Planned', time: '10:00' },
        { day: 1, account: 10, status: 'Planned', time: '12:00' },
        { day: 2, account: 6, status: 'Planned', time: '10:30' },
        { day: 2, account: 8, status: 'Planned', time: '12:30' },
        { day: 3, account: 5, status: 'Planned', time: '11:00' },
        { day: 4, account: 12, status: 'Planned', time: '10:00' }
    ];
    return plan.map((p, i) => {
        const account = DEMO_ACCOUNTS[p.account - 1];
        const date = addDays(today, p.day);
        const start = `${date}T${p.time}:00`;
        const endHour = String(Number(p.time.slice(0, 2)) + 1).padStart(2, '0');
        return {
            id: `a0VDEMO${String(i + 1).padStart(11, '0')}`,
            name: `V-DEMO-${String(i + 1).padStart(4, '0')}`,
            accountId: account.id,
            accountName: account.name,
            account,
            date,
            start,
            end: `${date}T${endHour}${p.time.slice(2)}:00`,
            status: p.status,
            channel: account.channel,
            productIds: [DEMO_PRODUCTS[0].id, DEMO_PRODUCTS[2].id]
        };
    });
}

export const DEMO_CLM_DECKS = [
    { id: 'a0CDEMO00000000001', name: 'Cardiora: Blood pressure control', productId: DEMO_PRODUCTS[0].id, slides: 6, format: 'HTML' },
    { id: 'a0CDEMO00000000002', name: 'Lipovia: LDL targets', productId: DEMO_PRODUCTS[2].id, slides: 5, format: 'HTML' },
    { id: 'a0CDEMO00000000003', name: 'Glucoset XR: Once-daily dosing', productId: DEMO_PRODUCTS[3].id, slides: 4, format: 'PDF' }
];

export const DEMO_COURSES = [
    { id: 'a0LDEMO00000000001', title: 'Cardiora product training', description: 'Mechanism, dosing and key messages.', progress: 100, status: 'Completed' },
    { id: 'a0LDEMO00000000002', title: 'Lipovia launch module', description: 'Lipid targets and objection handling.', progress: 40, status: 'In Progress' },
    { id: 'a0LDEMO00000000003', title: 'Compliant field conduct', description: 'Samples, gifts and reporting rules.', progress: 0, status: 'Not Started' }
];

export function accountById(id) {
    return DEMO_ACCOUNTS.find((a) => a.id === id) || null;
}
