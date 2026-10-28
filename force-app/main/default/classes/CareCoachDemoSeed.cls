/**
 * Demo data for Care Coach Co-pilot (Merck PSP): Erbitux, Rebif, Mavenclad and Saizen,
 * ~350 new Erbitux patients a month over six months, calls with transcripts analysed by the
 * Care Coach Insight Engine, orders, care scripts, planned calls and time off.
 *
 *   CareCoachDemoSeed.run();     // products + scripts now, permissions + patients in async jobs
 *   CareCoachDemoSeed.purge();   // removes seeded patients (children cascade)
 */
public without sharing class CareCoachDemoSeed implements Database.Batchable<Integer>, Database.Stateful {
    public static final String SEED_PREFIX = 'SEED-';
    public static final List<String> COACH_USERNAMES = new List<String>{
        'demo.rep@zeta-pharma.com.zeta',
        'demo.rep2@zeta-pharma.com.zeta',
        'demo.dm@zeta-pharma.com.zeta',
        'salesforce.dm@zeta-pharma.com.zeta',
        'omar.bazid@zeta-pharma.com'
    };
    public static final Set<String> SUPERVISOR_USERNAMES = new Set<String>{ 'demo.dm@zeta-pharma.com.zeta' };
    private static final Integer CHUNK_SIZE = 150;

    public class ProductSpec {
        public String code;
        public String name;
        public String therapyArea;
        public Integer monthly;
        public String description;
        public String hcp;
        ProductSpec(String code, String name, String therapyArea, Integer monthly, String hcp, String description) {
            this.code = code;
            this.name = name;
            this.therapyArea = therapyArea;
            this.monthly = monthly;
            this.hcp = hcp;
            this.description = description;
        }
    }

    public static final List<ProductSpec> PRODUCTS = new List<ProductSpec>{
        new ProductSpec('PSP-ERBITUX', 'Erbitux', 'Oncology', 350, 'oncologist',
            'Cetuximab 5 mg/mL solution for infusion. EGFR-targeted therapy for RAS wild-type metastatic colorectal cancer and squamous cell carcinoma of the head and neck.'),
        new ProductSpec('PSP-REBIF', 'Rebif', 'Neurology', 40, 'neurologist',
            'Interferon beta-1a 44 mcg, subcutaneous injection three times weekly (RebiDose pen or RebiSmart auto-injector) for relapsing multiple sclerosis.'),
        new ProductSpec('PSP-MAVENCLAD', 'Mavenclad', 'Neurology', 30, 'neurologist',
            'Cladribine 10 mg tablets. Short-course oral therapy (two treatment weeks a year for two years) for highly active relapsing multiple sclerosis.'),
        new ProductSpec('PSP-SAIZEN', 'Saizen', 'Endocrinology', 20, 'endocrinologist',
            'Somatropin daily subcutaneous injection with the easypod electronic auto-injector for growth hormone deficiency in children and adults.')
    };

    public class Chunk {
        public Integer monthOffset;
        public Integer startIndex;
        public Integer size;
        public List<Integer> productCounts;
    }

    private class PatientPlan {
        Patient__c record;
        ProductSpec spec;
        Id productId;
        String finalStatus;
        String dropReason;
        Date enrolled;
        Boolean child = false;
        Integer monthOffset;
    }

    private class Rng {
        Long state;
        Rng(Long seed) {
            state = Math.mod(Math.abs(seed) * 7919L + 104729L, 2147483648L);
        }
        Integer nextInt(Integer bound) {
            state = Math.mod(state * 1103515245L + 12345L, 2147483648L);
            return Math.mod((Integer) (state >> 8), bound);
        }
        Integer between(Integer lo, Integer hi) {
            return lo + nextInt(hi - lo + 1);
        }
        Boolean chance(Decimal p) {
            return nextInt(10000) < p * 10000;
        }
        String pick(List<String> values) {
            return values[nextInt(values.size())];
        }
    }

    // ---------------------------------------------------------------- state

    private List<Chunk> chunks = new List<Chunk>();
    private List<Id> coachIds = new List<Id>();
    private Id leadCoachId;
    private Map<String, Id> productIds = new Map<String, Id>();
    @TestVisible private Integer patientsCreated = 0;
    @TestVisible private Integer interactionsCreated = 0;
    @TestVisible private Integer ordersCreated = 0;

    public CareCoachDemoSeed() {
        this(1, 6);
    }

    public CareCoachDemoSeed(Decimal scale, Integer months) {
        Date today = Date.today();
        for (Integer m = 0; m < months; m++) {
            Decimal share = 1;
            if (m == 0) {
                share = Decimal.valueOf(today.day()) / Date.daysInMonth(today.year(), today.month());
            }
            Rng monthRng = new Rng(m + 11);
            List<Integer> counts = new List<Integer>();
            Integer total = 0;
            for (ProductSpec p : PRODUCTS) {
                Decimal noise = 0.92 + monthRng.nextInt(160) / 1000.0;
                Integer n = Math.max(1, (p.monthly * scale * share * noise).round(System.RoundingMode.HALF_UP).intValue());
                counts.add(n);
                total += n;
            }
            for (Integer s = 0; s < total; s += CHUNK_SIZE) {
                Chunk c = new Chunk();
                c.monthOffset = m;
                c.startIndex = s;
                c.size = Math.min(CHUNK_SIZE, total - s);
                c.productCounts = counts;
                chunks.add(c);
            }
        }
    }

    // ---------------------------------------------------------------- entry points

    public static Id run() {
        return run(1, 6);
    }

    public static Id run(Decimal scale, Integer months) {
        Map<String, Id> products = upsertProducts();
        seedScripts(products);
        return System.enqueueJob(new Kickoff(scale, months));
    }

    public static Id purge() {
        return Database.executeBatch(new CareCoachDemoSeedPurge(), 200);
    }

    /** Permission set assignments are setup DML, so they run in their own transaction before the batch. */
    public without sharing class Kickoff implements Queueable {
        private Decimal scale;
        private Integer months;
        public Kickoff(Decimal scale, Integer months) {
            this.scale = scale;
            this.months = months;
        }
        public void execute(QueueableContext ctx) {
            assignPermissions();
            if (!Test.isRunningTest()) {
                Database.executeBatch(new CareCoachDemoSeed(scale, months), 1);
            }
        }
    }

    // ---------------------------------------------------------------- batch

    public Iterable<Integer> start(Database.BatchableContext ctx) {
        for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode LIKE 'PSP-%']) {
            productIds.put(p.ProductCode, p.Id);
        }
        leadCoachId = UserInfo.getUserId();
        coachIds = loadCoaches();
        List<Integer> indexes = new List<Integer>();
        for (Integer i = 0; i < chunks.size(); i++) {
            indexes.add(i);
        }
        return indexes;
    }

    public void execute(Database.BatchableContext ctx, List<Integer> scope) {
        for (Integer idx : scope) {
            buildChunk(chunks[idx]);
        }
    }

    public void finish(Database.BatchableContext ctx) {
        schedulePlannedCalls();
        seedTimeOff();
    }

    // ---------------------------------------------------------------- setup

    public static Map<String, Id> upsertProducts() {
        Map<String, Product2> existing = new Map<String, Product2>();
        for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode LIKE 'PSP-%']) {
            existing.put(p.ProductCode, p);
        }
        List<Product2> rows = new List<Product2>();
        for (ProductSpec s : PRODUCTS) {
            Product2 p = existing.containsKey(s.code) ? existing.get(s.code) : new Product2(ProductCode = s.code);
            p.Name = s.name;
            p.IsActive = true;
            p.Therapy_Area__c = s.therapyArea;
            p.Description = s.description;
            rows.add(p);
        }
        upsert rows;
        Map<String, Id> out = new Map<String, Id>();
        for (Product2 p : rows) {
            out.put(p.ProductCode, p.Id);
        }
        return out;
    }

    public static List<Id> assignPermissions() {
        Map<String, Id> sets = new Map<String, Id>();
        for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN ('PSP_Care_Coach', 'PSP_Supervisor')]) {
            sets.put(ps.Name, ps.Id);
        }
        if (!sets.containsKey('PSP_Care_Coach')) {
            return new List<Id>();
        }
        Map<Id, User> users = new Map<Id, User>([
            SELECT Id, Username FROM User
            WHERE IsActive = TRUE AND (Id = :UserInfo.getUserId() OR Username IN :COACH_USERNAMES)
        ]);
        Set<String> assigned = new Set<String>();
        for (PermissionSetAssignment a : [
            SELECT AssigneeId, PermissionSetId FROM PermissionSetAssignment
            WHERE AssigneeId IN :users.keySet() AND PermissionSetId IN :sets.values()
        ]) {
            assigned.add(a.AssigneeId + '|' + a.PermissionSetId);
        }
        List<PermissionSetAssignment> inserts = new List<PermissionSetAssignment>();
        for (User u : users.values()) {
            List<String> wanted = new List<String>{ 'PSP_Care_Coach' };
            if (u.Id == UserInfo.getUserId() || SUPERVISOR_USERNAMES.contains(u.Username)) {
                wanted.add('PSP_Supervisor');
            }
            for (String name : wanted) {
                Id psId = sets.get(name);
                if (psId != null && !assigned.contains(u.Id + '|' + psId)) {
                    inserts.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId));
                }
            }
        }
        Database.insert(inserts, false);
        return new List<Id>(users.keySet());
    }

    private List<Id> loadCoaches() {
        List<Id> out = new List<Id>{ leadCoachId };
        for (PermissionSetAssignment a : [
            SELECT AssigneeId FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'PSP_Care_Coach' AND Assignee.IsActive = TRUE
                AND Assignee.Username IN :COACH_USERNAMES
            ORDER BY Assignee.Username
        ]) {
            if (!out.contains(a.AssigneeId)) {
                out.add(a.AssigneeId);
            }
        }
        return out;
    }

    // ---------------------------------------------------------------- patients

    private void buildChunk(Chunk c) {
        Date today = Date.today();
        Date monthStart = today.toStartOfMonth().addMonths(-c.monthOffset);
        Integer lastDay = c.monthOffset == 0 ? today.day() : Date.daysInMonth(monthStart.year(), monthStart.month());
        String keyPrefix = SEED_PREFIX + monthStart.year() + String.valueOf(monthStart.month()).leftPad(2, '0') + '-';
        String firstKey = keyPrefix + String.valueOf(c.startIndex).leftPad(5, '0');
        if ([SELECT COUNT() FROM Patient__c WHERE External_Id__c = :firstKey] > 0) {
            return;
        }
        Rng rng = new Rng(c.monthOffset * 100003L + c.startIndex + 7);

        List<PatientPlan> plans = new List<PatientPlan>();
        for (Integer i = c.startIndex; i < c.startIndex + c.size; i++) {
            ProductSpec spec = specForIndex(c.productCounts, i);
            plans.add(planPatient(rng, spec, monthStart, lastDay, c.monthOffset, keyPrefix + String.valueOf(i).leftPad(5, '0')));
        }
        List<Patient__c> patients = new List<Patient__c>();
        for (PatientPlan p : plans) {
            patients.add(p.record);
        }
        insert patients;

        List<Patient_Therapy__c> therapies = new List<Patient_Therapy__c>();
        List<Patient_Interaction__c> interactions = new List<Patient_Interaction__c>();
        List<Patient_Order__c> orders = new List<Patient_Order__c>();
        for (PatientPlan p : plans) {
            therapies.add(buildTherapy(rng, p));
            interactions.addAll(buildInteractions(rng, p));
            orders.addAll(buildOrders(rng, p));
        }
        CareCoachCallAnalysisService.applyAnalysis(interactions, false);
        insert therapies;
        insert interactions;
        for (Patient_Order__c o : orders) {
            CareCoachOrderService.applyDefaults(o);
            if (rng.chance(0.12)) {
                o.Priority__c = 'Urgent';
            }
        }
        insert orders;
        insert CareCoachOrderService.defaultItems(orders);

        // Status changes after insert so Patient__History shows the journey.
        List<Patient__c> firstStep = new List<Patient__c>();
        List<Patient__c> secondStep = new List<Patient__c>();
        for (PatientPlan p : plans) {
            if (p.finalStatus == 'Pending') {
                continue;
            }
            if (p.finalStatus == 'Unknown (Failed calls)') {
                firstStep.add(new Patient__c(Id = p.record.Id, Status__c = p.finalStatus));
                continue;
            }
            firstStep.add(new Patient__c(Id = p.record.Id, Status__c = 'Ongoing'));
            if (p.finalStatus.startsWith('Dropped')) {
                secondStep.add(new Patient__c(Id = p.record.Id, Status__c = p.finalStatus, Drop_Reason__c = p.dropReason));
            }
        }
        update firstStep;
        update secondStep;
        CareCoachPatientService.refreshPatientFromCalls(new Map<Id, Patient__c>(patients).keySet());

        patientsCreated += patients.size();
        interactionsCreated += interactions.size();
        ordersCreated += orders.size();
    }

    private static ProductSpec specForIndex(List<Integer> counts, Integer idx) {
        Integer cumulative = 0;
        for (Integer i = 0; i < PRODUCTS.size(); i++) {
            cumulative += counts[i];
            if (idx < cumulative) {
                return PRODUCTS[i];
            }
        }
        return PRODUCTS[0];
    }

    private static final List<String> MALE_NAMES = new List<String>{
        'Ahmed', 'Mohamed', 'Mahmoud', 'Mostafa', 'Omar', 'Youssef', 'Karim', 'Hany', 'Tarek', 'Sherif', 'Amr', 'Khaled',
        'Hossam', 'Ibrahim', 'Hassan', 'Waleed', 'Adel', 'Samir', 'Ashraf', 'Nabil', 'Magdy', 'Ayman', 'Ramy', 'Sameh',
        'Bassem', 'Ziad', 'Islam', 'Mina', 'Peter', 'Girgis', 'Seif', 'Yassin', 'Adam', 'Hamza', 'Marwan'
    };
    private static final List<String> FEMALE_NAMES = new List<String>{
        'Fatma', 'Mona', 'Nour', 'Sara', 'Mariam', 'Heba', 'Aya', 'Yasmin', 'Dina', 'Rania', 'Salma', 'Nada', 'Hoda',
        'Laila', 'Amira', 'Eman', 'Reem', 'Shaimaa', 'Nermeen', 'Ghada', 'Samar', 'Doaa', 'Marwa', 'Hanan', 'Mai', 'Rana',
        'Farida', 'Malak', 'Christine', 'Marina', 'Jana', 'Habiba', 'Lina'
    };
    private static final List<String> LAST_NAMES = new List<String>{
        'El-Sayed', 'Hassan', 'Mahmoud', 'Abdelrahman', 'Ibrahim', 'Mostafa', 'Farouk', 'Shawky', 'Mansour', 'Salem',
        'Nasr', 'Fawzy', 'Gamal', 'Kamel', 'Hamdy', 'Soliman', 'Zaki', 'Ragab', 'Hegazy', 'Badawy', 'Khalil', 'Youssef',
        'Morsi', 'Saad', 'Tawfik', 'Adly', 'Naguib', 'Habib', 'Ghali', 'Azer', 'Abdallah', 'Sabry', 'Lotfy', 'Helmy'
    };
    private static final List<String> CITIES = new List<String>{
        'Cairo', 'Cairo', 'Cairo', 'Giza', 'Giza', 'Alexandria', 'Alexandria', 'Mansoura', 'Tanta', 'Zagazig', 'Assiut',
        'Port Said', 'Ismailia', 'Suez', 'Minya', 'Sohag', 'Luxor', 'Aswan', 'Damanhour', 'Beni Suef'
    };
    private static final Map<String, String> GOVERNORATE_CODES = new Map<String, String>{
        'Cairo' => '01', 'Alexandria' => '02', 'Port Said' => '03', 'Suez' => '04', 'Damanhour' => '18', 'Mansoura' => '12',
        'Tanta' => '16', 'Zagazig' => '13', 'Ismailia' => '19', 'Giza' => '21', 'Beni Suef' => '22', 'Minya' => '24',
        'Assiut' => '25', 'Sohag' => '26', 'Luxor' => '29', 'Aswan' => '28'
    };
    private static final List<String> STREETS = new List<String>{
        'El Tahrir St.', 'Abbas El Akkad St.', 'Makram Ebeid St.', 'El Haram St.', 'Gameat El Dowal St.', 'El Horreya Rd.',
        'Salah Salem St.', 'El Nasr Rd.', 'Port Said St.', 'El Galaa St.', 'Omar Ibn El Khattab St.', 'El Geish St.'
    };
    private static final List<String> OCCUPATIONS = new List<String>{
        'Teacher', 'Engineer', 'Accountant', 'Retired', 'Retired', 'Housewife', 'Housewife', 'Driver', 'Civil servant',
        'Pharmacist', 'Sales representative', 'Shop owner', 'Farmer', 'Nurse', 'Lawyer', 'IT specialist', 'Student'
    };
    private static final Map<String, List<String>> HOSPITALS = new Map<String, List<String>>{
        'Oncology' => new List<String>{ 'National Cancer Institute, Cairo', 'Ain Shams University Oncology Centre', 'Kasr Al Ainy Centre of Clinical Oncology', 'Alexandria University Oncology Hospital', 'Mansoura University Oncology Centre', 'Dar Al Fouad Hospital', 'Baheya Hospital' },
        'Neurology' => new List<String>{ 'Ain Shams University MS Unit', 'Kasr Al Ainy MS Clinic', 'Alexandria University Neurology Hospital', 'Nasser Institute Hospital', 'Cleopatra Hospital', 'As-Salam International Hospital' },
        'Endocrinology' => new List<String>{ 'Abou El Reesh Children\'s Hospital', 'Ain Shams Paediatric Endocrinology Clinic', 'National Institute of Diabetes and Endocrinology', 'Alexandria University Children\'s Hospital', 'Mansoura University Children\'s Hospital' }
    };
    private static final Map<String, List<String>> PHYSICIANS = new Map<String, List<String>>{
        'Oncology' => new List<String>{ 'Dr. Hesham El Ghazaly', 'Dr. Rabab Gaafar', 'Dr. Hamdy Abdel Azim', 'Dr. Manal El Mahdy', 'Dr. Ahmed Hussein', 'Dr. Mohamed Abdel Mooti', 'Dr. Nermeen Said' },
        'Neurology' => new List<String>{ 'Dr. Magd Zakaria', 'Dr. Nevin Shalaby', 'Dr. Mohamed Hegazy', 'Dr. Hany Aref', 'Dr. Amr Hassan', 'Dr. Sherif Hamdy' },
        'Endocrinology' => new List<String>{ 'Dr. Mona Salem', 'Dr. Rasha Tarif', 'Dr. Noha Musa', 'Dr. Hala Elmougy', 'Dr. Ashraf Soliman' }
    };
    private static final Map<String, List<String>> DIAGNOSES = new Map<String, List<String>>{
        'PSP-ERBITUX' => new List<String>{ 'Metastatic colorectal cancer, RAS wild-type', 'Metastatic colorectal cancer, RAS wild-type', 'Locally advanced SCC of head and neck', 'Recurrent/metastatic SCC of head and neck' },
        'PSP-REBIF' => new List<String>{ 'Relapsing-remitting multiple sclerosis', 'Relapsing-remitting multiple sclerosis', 'Clinically isolated syndrome' },
        'PSP-MAVENCLAD' => new List<String>{ 'Highly active relapsing multiple sclerosis' },
        'PSP-SAIZEN' => new List<String>{ 'Paediatric growth hormone deficiency', 'Paediatric growth hormone deficiency', 'Turner syndrome', 'Small for gestational age', 'Adult growth hormone deficiency' }
    };
    private static final List<String> LEAD_SOURCES = new List<String>{
        'Physician Referral', 'Physician Referral', 'Physician Referral', 'Physician Referral', 'Hospital', 'Hospital',
        'Hotline', 'Pharmacy', 'Patient Association', 'Website'
    };

    private PatientPlan planPatient(Rng rng, ProductSpec spec, Date monthStart, Integer lastDay, Integer monthOffset, String externalId) {
        PatientPlan plan = new PatientPlan();
        plan.spec = spec;
        plan.productId = productIds.get(spec.code);
        plan.monthOffset = monthOffset;
        plan.enrolled = monthStart.addDays(rng.nextInt(lastDay));

        Decimal maleShare = spec.code == 'PSP-ERBITUX' ? 0.58 : (spec.code == 'PSP-SAIZEN' ? 0.6 : 0.3);
        Boolean male = rng.chance(maleShare);
        Integer age;
        if (spec.code == 'PSP-ERBITUX') {
            age = rng.between(42, 78);
        } else if (spec.code == 'PSP-SAIZEN') {
            plan.child = rng.chance(0.75);
            age = plan.child ? rng.between(4, 15) : rng.between(24, 55);
        } else {
            age = rng.between(21, 50);
        }
        Date birth = Date.today().addYears(-age).addDays(-rng.nextInt(360));
        String firstName = rng.pick(male ? MALE_NAMES : FEMALE_NAMES);
        String lastName = rng.pick(LAST_NAMES);
        String city = rng.pick(CITIES);

        plan.finalStatus = pickStatus(rng, monthOffset);
        Integer daysEnrolled = plan.enrolled.daysBetween(Date.today());
        if (plan.finalStatus.startsWith('Dropped') && daysEnrolled < 21) {
            plan.finalStatus = daysEnrolled < 4 ? 'Pending' : 'Ongoing';
        } else if (plan.finalStatus == 'Ongoing' && daysEnrolled < 4) {
            plan.finalStatus = 'Pending';
        } else if (plan.finalStatus == 'Unknown (Failed calls)' && daysEnrolled < 5) {
            plan.finalStatus = 'Pending';
        }
        if (plan.finalStatus == 'Dropped (Switched)') {
            plan.dropReason = rng.chance(0.7) ? 'Switched therapy' : 'Physician decision';
        } else if (plan.finalStatus == 'Dropped (Stopped)') {
            Integer r = rng.nextInt(100);
            plan.dropReason = r < 35 ? 'Side effects'
                : r < 60 ? 'Cost / access'
                : r < 78 ? 'Lost to follow-up'
                : (r < 95 || spec.code != 'PSP-ERBITUX') ? 'Physician decision' : 'Deceased';
        }

        Id coach = coachIds.size() == 1 || rng.chance(0.22) ? leadCoachId : coachIds[1 + rng.nextInt(coachIds.size() - 1)];
        String email = rng.chance(0.4)
            ? (firstName + '.' + lastName).toLowerCase().replaceAll('[^a-z.]', '') + rng.between(10, 99) + '@gmail.com'
            : null;

        plan.record = new Patient__c(
            External_Id__c = externalId,
            OwnerId = coach,
            Care_Coach__c = coach,
            First_Name__c = firstName,
            Last_Name__c = lastName,
            Gender__c = male ? 'Male' : 'Female',
            Birthdate__c = birth,
            Phone__c = egyptMobile(rng),
            Mobile__c = rng.chance(0.3) ? egyptMobile(rng) : null,
            Email__c = email,
            City__c = city,
            Address__c = rng.between(2, 180) + ' ' + rng.pick(STREETS) + ', ' + city,
            National_Id__c = nationalId(rng, birth, city),
            Nationality__c = rng.chance(0.94) ? 'Egyptian' : rng.pick(new List<String>{ 'Sudanese', 'Syrian', 'Saudi', 'Jordanian' }),
            Marital_Status__c = plan.child ? 'Single' : rng.pick(new List<String>{ 'Married', 'Married', 'Married', 'Single', 'Widowed', 'Divorced' }),
            Occupation__c = plan.child ? 'Student' : rng.pick(OCCUPATIONS),
            Status__c = 'Pending',
            Primary_Product__c = plan.productId,
            Diagnosis__c = rng.pick(DIAGNOSES.get(spec.code)),
            Diagnosis_Date__c = plan.enrolled.addDays(-rng.between(14, 420)),
            Physician_Name__c = rng.pick(PHYSICIANS.get(spec.therapyArea)),
            Hospital__c = rng.pick(HOSPITALS.get(spec.therapyArea)),
            Lead_Source__c = rng.pick(LEAD_SOURCES),
            Enrollment_Date__c = plan.enrolled,
            Journey_Start_Date__c = plan.finalStatus == 'Pending' ? null : minDate(plan.enrolled.addDays(rng.between(1, 6)), Date.today()),
            Consent_Given__c = plan.finalStatus != 'Pending' || rng.chance(0.5)
        );
        return plan;
    }

    /** Demo patients and coaches are in Egypt; call times are wall-clock Cairo time whatever the running user's zone. */
    private static final TimeZone DEMO_TZ = TimeZone.getTimeZone('Africa/Cairo');

    private static Datetime demoTime(Date day, Time wallClock) {
        Datetime gmt = Datetime.newInstanceGmt(day, wallClock);
        return gmt.addSeconds(-DEMO_TZ.getOffset(gmt) / 1000);
    }

    private static Date minDate(Date a, Date b) {
        return a < b ? a : b;
    }

    private static String pickStatus(Rng rng, Integer monthOffset) {
        Decimal t = Math.min(monthOffset, 5) / 5.0;
        Decimal pPending = 0.55 - 0.47 * t;
        Decimal pUnknown = 0.07 - 0.01 * t;
        Decimal pSwitched = 0.01 + 0.08 * t;
        Decimal pStopped = 0.02 + 0.11 * t;
        Decimal r = rng.nextInt(10000) / 10000.0;
        if (r < pPending) return 'Pending';
        if (r < pPending + pUnknown) return 'Unknown (Failed calls)';
        if (r < pPending + pUnknown + pSwitched) return 'Dropped (Switched)';
        if (r < pPending + pUnknown + pSwitched + pStopped) return 'Dropped (Stopped)';
        return 'Ongoing';
    }

    private static String egyptMobile(Rng rng) {
        String prefix = new List<String>{ '10', '11', '12', '15' }[rng.nextInt(4)];
        return '+20 ' + prefix + ' ' + String.valueOf(rng.between(1000, 9999)) + ' ' + String.valueOf(rng.between(1000, 9999));
    }

    private static String nationalId(Rng rng, Date birth, String city) {
        String century = birth.year() >= 2000 ? '3' : '2';
        String yy = String.valueOf(Math.mod(birth.year(), 100)).leftPad(2, '0');
        String gov = GOVERNORATE_CODES.containsKey(city) ? GOVERNORATE_CODES.get(city) : '01';
        return century + yy + String.valueOf(birth.month()).leftPad(2, '0') + String.valueOf(birth.day()).leftPad(2, '0') +
            gov + String.valueOf(rng.between(1000, 9999)) + String.valueOf(rng.nextInt(10));
    }

    private static Patient_Therapy__c buildTherapy(Rng rng, PatientPlan p) {
        Patient_Therapy__c t = new Patient_Therapy__c(
            Patient__c = p.record.Id,
            Product__c = p.productId,
            Start_Date__c = p.enrolled.addDays(rng.between(3, 12))
        );
        if (p.spec.code == 'PSP-ERBITUX') {
            Boolean biweekly = rng.chance(0.6);
            t.Dosage__c = biweekly ? '500 mg/m² every 2 weeks' : '400 mg/m² loading, then 250 mg/m² weekly';
            t.Dosage_Form__c = 'IV infusion';
            t.Frequency__c = biweekly ? 'Every 2 weeks' : 'Weekly';
        } else if (p.spec.code == 'PSP-REBIF') {
            Boolean smart = rng.chance(0.55);
            t.Dosage__c = '44 mcg';
            t.Dosage_Form__c = smart ? 'Auto-injector' : 'Pre-filled pen';
            t.Frequency__c = '3 times weekly';
            t.Device_Serial__c = smart ? 'RS-' + rng.between(100000, 999999) : null;
        } else if (p.spec.code == 'PSP-MAVENCLAD') {
            t.Dosage__c = '3.5 mg/kg over 2 years';
            t.Dosage_Form__c = 'Tablet';
            t.Frequency__c = '2 treatment weeks per year';
        } else {
            t.Dosage__c = p.child ? '0.025–0.035 mg/kg/day' : '0.2–0.5 mg/day';
            t.Dosage_Form__c = 'Cartridge';
            t.Frequency__c = 'Daily, evening';
            t.Device_Serial__c = 'EP-' + rng.between(10000, 99999);
        }
        if (p.finalStatus.startsWith('Dropped')) {
            t.Status__c = 'Stopped';
            t.Stop_Date__c = Date.today().addDays(-rng.between(3, 25));
            if (t.Stop_Date__c < t.Start_Date__c) {
                t.Stop_Date__c = t.Start_Date__c;
            }
        } else if (p.finalStatus == 'Unknown (Failed calls)') {
            t.Status__c = 'Paused';
        } else {
            t.Status__c = 'Active';
        }
        return t;
    }

    // ---------------------------------------------------------------- interactions

    private List<Patient_Interaction__c> buildInteractions(Rng rng, PatientPlan p) {
        List<Patient_Interaction__c> out = new List<Patient_Interaction__c>();
        Date today = Date.today();
        Date d = p.enrolled.addDays(rng.between(0, 2));
        if (d >= today) {
            if (p.finalStatus == 'Pending') {
                return out;
            }
            d = today.addDays(-1);
        }

        if (p.finalStatus == 'Unknown (Failed calls)') {
            Integer attempts = rng.between(2, 4);
            for (Integer k = 0; k < attempts && d < today; k++) {
                out.add(call(rng, p, d, unreachedStatus(rng), k == 0 ? 'Welcome call' : 'Re-engagement', null, 'Outbound'));
                d = d.addDays(rng.between(2, 6));
            }
            return out;
        }

        if (p.finalStatus == 'Pending') {
            if (rng.chance(0.5)) {
                out.add(call(rng, p, d, unreachedStatus(rng), 'Welcome call', null, 'Outbound'));
                d = d.addDays(rng.between(1, 3));
            }
            if (d < today) {
                if (rng.chance(0.6)) {
                    out.add(call(rng, p, d, 'Reached', 'Welcome call', 'welcome', 'Outbound'));
                } else {
                    out.add(call(rng, p, d, rng.chance(0.5) ? 'Call back' : 'Unreached (No Answer)', 'Welcome call', null, 'Outbound'));
                }
            }
            return out;
        }

        // Ongoing and dropped patients have an onboarding call followed by regular follow-ups.
        if (rng.chance(0.25)) {
            out.add(call(rng, p, d, unreachedStatus(rng), 'Welcome call', null, 'Outbound'));
            d = d.addDays(1);
        }
        out.add(call(rng, p, d, 'Reached', 'Welcome call', 'welcome', 'Outbound'));
        if ((p.spec.code == 'PSP-REBIF' || p.spec.code == 'PSP-SAIZEN') && d.addDays(6) < today) {
            Patient_Interaction__c training = call(rng, p, d.addDays(rng.between(4, 8)), 'Reached', 'Injection training', 'training', 'Outbound');
            if (rng.chance(0.35)) {
                training.Type__c = 'Home Visit';
            }
            out.add(training);
        }

        Boolean dropped = p.finalStatus.startsWith('Dropped');
        Date dropDay = today.addDays(-rng.between(3, 20));
        if (dropDay <= d.addDays(7)) {
            dropDay = minDate(d.addDays(7), today.addDays(-1));
        }
        Date horizon = dropped ? dropDay : today;
        Date next = d.addDays(rng.between(18, 32));
        Integer followUps = 0;
        Integer maxFollowUps = dropped ? rng.between(1, 3) : 4;
        while (next < horizon && followUps < maxFollowUps) {
            if (rng.chance(0.15)) {
                out.add(call(rng, p, next, unreachedStatus(rng), 'Follow up', null, 'Outbound'));
                next = next.addDays(rng.between(1, 3));
                if (next >= horizon) {
                    break;
                }
            }
            String tone = pickTone(rng);
            String reason = tone == 'sideEffects' || tone == 'serious' ? 'Side effect report'
                : tone == 'refill' ? 'Order refill'
                : tone == 'adherence' ? 'Adherence check'
                : tone == 'education' ? 'Disease education'
                : rng.chance(0.5) ? 'Follow up' : 'Adherence check';
            String direction = (tone == 'refill' || tone == 'sideEffects' || tone == 'serious') && rng.chance(0.35) ? 'Inbound' : 'Outbound';
            out.add(call(rng, p, next, 'Reached', reason, tone, direction));
            if (rng.chance(0.2) && next.addDays(9) < horizon) {
                out.add(message(rng, p, next.addDays(rng.between(3, 9))));
            }
            next = next.addDays(rng.between(24, 38));
            followUps++;
        }

        if (dropped) {
            if (p.dropReason == 'Lost to follow-up') {
                out.add(call(rng, p, dropDay.addDays(-4), unreachedStatus(rng), 'Re-engagement', null, 'Outbound'));
                out.add(call(rng, p, dropDay, unreachedStatus(rng), 'Re-engagement', null, 'Outbound'));
            } else if (p.dropReason == 'Deceased') {
                Patient_Interaction__c c = call(rng, p, dropDay, 'Reached', 'Follow up', null, 'Inbound');
                c.Notes__c = 'Family informed the programme that the patient passed away. Condolences offered; file closed.';
                out.add(c);
            } else {
                String tone = p.dropReason == 'Side effects' ? 'stopped'
                    : p.dropReason == 'Cost / access' ? 'cost'
                    : 'switch';
                out.add(call(rng, p, dropDay, 'Reached', tone == 'stopped' ? 'Side effect report' : 'Follow up', tone, rng.chance(0.4) ? 'Inbound' : 'Outbound'));
            }
        } else {
            Patient_Interaction__c last = null;
            for (Patient_Interaction__c i : out) {
                if (i.Status__c == 'Reached' && i.Type__c != 'SMS' && i.Type__c != 'WhatsApp') {
                    last = i;
                }
            }
            if (last != null) {
                Date due = last.Start__c.date().addDays(rng.between(21, 35));
                last.Follow_Up_Date__c = due;
            }
        }
        return out;
    }

    private static String pickTone(Rng rng) {
        Integer r = rng.nextInt(100);
        if (r < 50) return 'positive';
        if (r < 66) return 'sideEffects';
        if (r < 78) return 'refill';
        if (r < 86) return 'adherence';
        if (r < 91) return 'education';
        if (r < 97) return 'cost';
        return 'serious';
    }

    private static String unreachedStatus(Rng rng) {
        Integer r = rng.nextInt(10);
        return r < 6 ? 'Unreached (No Answer)' : (r < 8 ? 'Unreached (Switched Off)' : 'Call back');
    }

    private Map<String, Id> demoScripts;

    private Id demoScript(Id productId, String tone) {
        if (demoScripts == null) {
            demoScripts = CareCoachCallSamples.scriptIds();
        }
        return CareCoachCallSamples.scriptId(demoScripts, productId, CareCoachCallSamples.categoryFor(tone));
    }

    private Patient_Interaction__c call(Rng rng, PatientPlan p, Date day, String status, String reason, String tone, String direction) {
        Datetime startAt = demoTime(day, Time.newInstance(rng.between(9, 16), rng.nextInt(4) * 15, 0, 0));
        Boolean reached = status == 'Reached';
        Integer minutes = reached ? rng.between(6, 18) : 1;
        Patient_Interaction__c i = new Patient_Interaction__c(
            Patient__c = p.record.Id,
            Subject__c = reason + ' - ' + p.spec.name,
            Type__c = 'Call',
            Direction__c = direction,
            Status__c = status,
            Interaction_Reason__c = reason,
            Priority__c = tone == 'serious' || tone == 'stopped' ? 'High' : (tone == 'adherence' || tone == 'cost' ? 'Medium' : 'Low'),
            Start__c = startAt,
            End__c = startAt.addMinutes(minutes),
            Duration_Minutes__c = minutes,
            Care_Coach__c = p.record.Care_Coach__c,
            Product__c = p.productId,
            Adverse_Event_Reported__c = tone == 'serious'
        );
        if (reached && tone != null) {
            Boolean arabic = rng.chance(0.35) && tone != 'serious';
            i.Language__c = arabic ? CareCoachCallSamples.LANG_AR : CareCoachCallSamples.LANG_EN;
            i.Transcript__c = arabic
                ? CareCoachCallSamples.transcript(true, tone)
                : transcript(rng, p, tone);
            i.Notes__c = arabic ? CareCoachCallSamples.notes(true, tone) : NOTES.get(tone);
            i.Care_Script__c = demoScript(p.productId, tone);
            if (arabic) {
                i.Recording_Consent__c = true;
                i.Recording_URL__c = CareCoachCallSamples.recordingUrl(CareCoachCallSamples.fileFor(true, tone));
            }
        } else if (!reached) {
            i.Notes__c = status == 'Call back' ? 'Patient asked to be called back later.' : 'No answer, will retry.';
        }
        return i;
    }

    private static Patient_Interaction__c message(Rng rng, PatientPlan p, Date day) {
        if (day >= Date.today()) {
            day = Date.today().addDays(-1);
        }
        Datetime startAt = demoTime(day, Time.newInstance(rng.between(9, 18), 0, 0, 0));
        Boolean whatsapp = rng.chance(0.7);
        return new Patient_Interaction__c(
            Patient__c = p.record.Id,
            Subject__c = (whatsapp ? 'WhatsApp' : 'SMS') + ' reminder - ' + p.spec.name,
            Type__c = whatsapp ? 'WhatsApp' : 'SMS',
            Direction__c = 'Outbound',
            Status__c = 'Reached',
            Interaction_Reason__c = rng.chance(0.5) ? 'Order refill' : 'Adherence check',
            Priority__c = 'Low',
            Start__c = startAt,
            End__c = startAt,
            Care_Coach__c = p.record.Care_Coach__c,
            Product__c = p.productId,
            Notes__c = rng.chance(0.5)
                ? 'Refill reminder sent with the delivery tracking link.'
                : 'Dose reminder and link to the programme education video sent.'
        );
    }

    private static final Map<String, String> NOTES = new Map<String, String>{
        'welcome' => 'Programme explained, consent confirmed, education pack sent by WhatsApp.',
        'training' => 'Device training completed; injection-site rotation reviewed.',
        'positive' => 'Patient doing well, adherent, no new concerns.',
        'sideEffects' => 'Mild side effects reported; management tips shared, PV log created.',
        'serious' => 'Possible serious adverse event. Escalated to pharmacovigilance and treating physician.',
        'adherence' => 'Missed doses reported; reminder plan agreed.',
        'refill' => 'Refill order raised; delivery slot confirmed.',
        'education' => 'Disease education and monitoring schedule reviewed.',
        'cost' => 'Access / reimbursement concern; referred to the patient access team.',
        'switch' => 'Physician switched therapy; programme file closed.',
        'stopped' => 'Patient stopped therapy because of side effects; physician informed.'
    };

    // ---------------------------------------------------------------- transcripts

    private static String transcript(Rng rng, PatientPlan p, String tone) {
        String s = p.child ? 'Caregiver' : 'Patient';
        String product = p.spec.name;
        String code = p.spec.code;
        String hcp = p.spec.hcp;
        String device = code == 'PSP-REBIF' ? 'RebiSmart' : code == 'PSP-SAIZEN' ? 'easypod' : code == 'PSP-MAVENCLAD' ? 'tablets' : 'infusion';
        String doses = code == 'PSP-MAVENCLAD' ? 'tablets' : code == 'PSP-ERBITUX' ? 'infusion sessions' : 'injections';
        String subject = p.child ? 'he' : 'I';
        List<String> lines = new List<String>();
        lines.add('Coach: Hello, this is your care coach from the ' + product + ' patient support programme. Is this a good time to talk for a few minutes?');
        lines.add(s + ': ' + (p.child ? 'Yes, I am his mother, we can talk now.' : rng.pick(new List<String>{ 'Yes, go ahead.', 'Yes, of course.', 'Yes, I have a few minutes.' })));

        if (tone == 'welcome') {
            lines.add('Coach: Welcome to the programme. I will be your care coach. I will call you regularly, help with orders and deliveries, and answer questions about your treatment.');
            lines.add(s + ': Thank you. I was a bit worried when the ' + hcp + ' told me about the treatment, but this is really helpful.');
            lines.add('Coach: That is completely normal. Has the clinic confirmed the date of your first ' + (code == 'PSP-ERBITUX' ? 'infusion' : 'dose') + '?');
            lines.add(s + ': Yes, the appointment is next week and the pharmacy already called us.');
            lines.add('Coach: Great. I will send you the consent form and our education booklet by WhatsApp. Do you agree to receive calls and messages from the programme?');
            lines.add(s + ': Yes, I agree. Thank you.');
        } else if (tone == 'training') {
            lines.add('Coach: Today we will go through the ' + device + ' step by step. Please have it in front of you.');
            lines.add(s + ': The first time was difficult, ' + (p.child ? 'he was afraid of the needle.' : 'I was afraid of the needle.'));
            lines.add('Coach: That is common. Let us check the dose on the screen, clean the site, and remember to rotate between thighs, abdomen and arms.');
            lines.add(s + ': OK, now it feels easier. I am more confident, thank you.');
        } else if (tone == 'positive') {
            lines.add('Coach: How have things been with ' + product + ' since our last call?');
            if (p.child) {
                lines.add(s + ': He is doing well. We have not missed a dose and the easypod is easier now. He grew two centimetres since the last visit, we are very happy.');
            } else {
                lines.add(s + ': ' + rng.pick(new List<String>{
                    'Honestly I feel better. I have taken every dose on time.',
                    'Everything is going well, I am on track with the ' + doses + '.',
                    'I feel good, the ' + hcp + ' said the last results improved.'
                }));
            }
            lines.add('Coach: That is great to hear. Any new symptoms or questions about supply?');
            lines.add(s + ': Everything is fine. The last delivery came on time, thank you.');
        } else if (tone == 'sideEffects') {
            lines.add('Coach: How have you been feeling since the last ' + (code == 'PSP-ERBITUX' ? 'infusion' : 'dose') + '?');
            lines.add(s + ': ' + sideEffectLine(rng, code));
            lines.add('Coach: Thank you for telling me. I am logging this for our safety team and I will share the side-effect guide. Please mention it to your ' + hcp + ' at the next appointment.');
            lines.add(s + ': OK, I will. It is manageable, but I wanted you to know.');
        } else if (tone == 'serious') {
            lines.add('Coach: How have you been since we last spoke?');
            lines.add(s + ': ' + seriousLine(code));
            lines.add('Coach: I am sorry to hear that. This is important, so I am reporting it to pharmacovigilance today. Please contact your ' + hcp + ' today and do not take the next dose until they confirm.');
            lines.add(s + ': Yes, we have an appointment tomorrow morning.');
        } else if (tone == 'adherence') {
            lines.add('Coach: How has it been going with your ' + doses + '?');
            Integer variant = rng.nextInt(3);
            if (variant == 0) {
                lines.add(s + ': To be honest it has been difficult. ' + (p.child
                    ? 'We missed two doses last week because we were travelling, and he forgot one more at his grandmother\'s house.'
                    : 'I missed two doses last week because I was travelling, and I forgot one more.'));
                lines.add('Coach: Thank you for being honest, that happens. What would make it easier?');
                lines.add(s + ': ' + (p.child ? 'He is tired of the injections sometimes and cries.' : 'I am tired of the ' + doses + ' sometimes. I am not sure I can keep going like this.'));
            } else if (variant == 1) {
                lines.add(s + ': ' + (p.child ? 'We skipped one dose because he felt bad after the one before.' : 'I skipped the last dose because I felt bad after the one before.'));
                lines.add('Coach: I understand. How are you feeling now?');
                lines.add(s + ': Better today, but I am worried it is not working.');
            } else {
                lines.add(s + ': Mostly fine, but I had to delay one dose because of work and I missed another one on the weekend.');
                lines.add('Coach: Thanks for telling me. Would a reminder help?');
                lines.add(s + ': Yes, a reminder would be good.');
            }
            lines.add('Coach: Let us set a daily reminder on your phone and I will call you again next week to check in.');
        } else if (tone == 'refill') {
            lines.add('Coach: I am calling about your next order.');
            lines.add(s + ': Yes, ' + (subject == 'he' ? 'we have' : 'I have') + ' one box left, so we need a refill for next week.');
            lines.add('Coach: No problem, I have raised the order. The delivery will arrive on Thursday, is that good?');
            lines.add(s + ': Yes, that is fine, thank you.');
        } else if (tone == 'education') {
            lines.add('Coach: I wanted to remind you about your monitoring schedule.');
            lines.add(s + ': ' + (code == 'PSP-MAVENCLAD'
                ? 'Yes, the neurologist asked for a blood test before the second treatment week.'
                : code == 'PSP-ERBITUX' ? 'The oncologist wants a scan and a magnesium blood test before the next cycle.'
                : code == 'PSP-SAIZEN' ? 'The endocrinologist asked for an x-ray of the hand and a blood test.'
                : 'The neurologist asked for an MRI in two months.'));
            lines.add('Coach: Exactly. Book the lab this week and share the results with the clinic. I will send you the checklist.');
            lines.add(s + ': Good, that is helpful. I will do it.');
        } else if (tone == 'cost') {
            lines.add('Coach: Is everything OK with your next order?');
            lines.add(s + ': The medicine is expensive and the insurance has not approved the next pack yet. I might delay the next order until they reply.');
            lines.add('Coach: I understand. I will connect you with our access team today; they can help with the reimbursement file and the patient assistance programme.');
            lines.add(s + ': OK. I am worried about the cost, but I will wait for their call.');
        } else if (tone == 'switch') {
            lines.add('Coach: How are things going with ' + product + '?');
            lines.add(s + ': The ' + hcp + ' decided to switch ' + (p.child ? 'him' : 'me') + ' to another treatment after the last ' +
                (code == 'PSP-ERBITUX' ? 'scan' : code == 'PSP-SAIZEN' ? 'review' : 'MRI') + ', so ' + subject + ' stopped ' + product + ' this month.');
            lines.add('Coach: Thank you for letting us know. I will close your file for ' + product + '. You can call the hotline any time if you need us.');
            lines.add(s + ': OK, goodbye.');
        } else if (tone == 'stopped') {
            lines.add('Coach: I noticed we have not had an order for a while. How are you?');
            lines.add(s + ': ' + subject.capitalize() + ' stopped taking it. ' + sideEffectLine(rng, code) + ' It was too much, I was scared and the ' + hcp + ' agreed to stop.');
            lines.add('Coach: I am sorry you went through that. I will record the side effects for our safety team and inform your ' + hcp + '.');
            lines.add(s + ': OK.');
        }

        if (tone != 'switch' && tone != 'stopped') {
            lines.add('Coach: Thank you for your time. I have noted everything and I will call you again in a few weeks. The programme hotline is available any time.');
            lines.add(s + ': ' + (tone == 'serious' || tone == 'adherence' || tone == 'cost' ? 'OK. Goodbye.' : 'Thank you, goodbye.'));
        }
        return String.join(lines, '\n');
    }

    private static String sideEffectLine(Rng rng, String code) {
        if (code == 'PSP-ERBITUX') {
            return rng.pick(new List<String>{
                'I have an acne-like rash on my face and chest, and my skin is very dry and itchy.',
                'My nails are cracking at the edges and I had some diarrhoea after the infusion days.',
                'There is a rash on my face and I feel fatigue for two days after each session.'
            });
        } else if (code == 'PSP-REBIF') {
            return rng.pick(new List<String>{
                'The night after the injection I get flu-like symptoms, some chills and a headache.',
                'There is redness and a bit of bruising at the injection site on my thigh.',
                'I feel tired all day after the injection and I have a headache.'
            });
        } else if (code == 'PSP-MAVENCLAD') {
            return rng.pick(new List<String>{
                'I felt some fatigue and a headache during the treatment week.',
                'The lab said my lymphocyte count is a bit low on the last blood test.',
                'I had some nausea during the treatment week, but it passed.'
            });
        }
        return rng.pick(new List<String>{
            'Sometimes there is headache in the evening and redness where we inject.',
            'There was some knee pain after football, I was not sure if it is related.',
            'We noticed some swelling at the injection site for a day.'
        });
    }

    private static String seriousLine(String code) {
        if (code == 'PSP-ERBITUX') {
            return 'During the last infusion I had a severe reaction, I could not catch my breath and they kept me in the hospital overnight.';
        } else if (code == 'PSP-REBIF') {
            return 'Two days ago my face was swelling and I had trouble with my breath, I went to the emergency room.';
        } else if (code == 'PSP-MAVENCLAD') {
            return 'I have shingles now and it is very painful. The doctor sent me to the hospital for tests.';
        }
        return 'He had a seizure last week and we went to the emergency department. We stopped the injections until we see the doctor.';
    }

    // ---------------------------------------------------------------- orders

    private static final List<String> PHARMACIES = new List<String>{
        'El Ezaby Pharmacy', 'Seif Pharmacies', 'Misr Pharmacies', 'Roshdy Pharmacy', '19011 Pharmacy', 'Al Tarshouby Pharmacy'
    };

    private static List<Patient_Order__c> buildOrders(Rng rng, PatientPlan p) {
        List<Patient_Order__c> out = new List<Patient_Order__c>();
        Date today = Date.today();
        Integer count = 0;
        if (p.finalStatus == 'Ongoing') {
            count = Math.min(4, Math.max(1, p.monthOffset));
        } else if (p.finalStatus.startsWith('Dropped')) {
            count = p.monthOffset >= 1 ? 1 : 0;
        } else if (p.finalStatus == 'Pending') {
            count = rng.chance(0.3) ? 1 : 0;
        } else {
            count = rng.chance(0.4) ? 1 : 0;
        }
        Date d = p.enrolled.addDays(rng.between(2, 8));
        for (Integer k = 0; k < count && d <= today; k++) {
            Boolean latest = k == count - 1 || d.addDays(30) > today;
            Patient_Order__c o = new Patient_Order__c(
                Patient__c = p.record.Id,
                Product__c = p.productId,
                Care_Coach__c = p.record.Care_Coach__c,
                Order_Date__c = d,
                Quantity__c = quantityFor(rng, p.spec.code)
            );
            if (p.spec.code == 'PSP-ERBITUX') {
                o.Channel__c = rng.chance(0.8) ? 'Hospital' : 'Pharmacy Pick-up';
            } else {
                o.Channel__c = rng.chance(0.6) ? 'Home Delivery' : 'Pharmacy Pick-up';
            }
            o.Pharmacy__c = o.Channel__c == 'Hospital' ? p.record.Hospital__c : (o.Channel__c == 'Pharmacy Pick-up' ? rng.pick(PHARMACIES) : null);
            o.Delivery_Address__c = o.Channel__c == 'Home Delivery' ? p.record.Address__c : null;
            if (p.finalStatus == 'Pending') {
                o.Status__c = 'Requested';
            } else if (latest && today.daysBetween(d) > -14 && p.finalStatus == 'Ongoing') {
                o.Status__c = rng.pick(new List<String>{ 'Requested', 'Approved', 'Dispatched', 'Delivered' });
            } else if (p.finalStatus.startsWith('Dropped') && rng.chance(0.25)) {
                o.Status__c = 'Cancelled';
                o.Notes__c = 'Cancelled after therapy was stopped.';
            } else {
                o.Status__c = 'Delivered';
            }
            if (o.Status__c == 'Delivered') {
                o.Delivery_Date__c = d.addDays(rng.between(1, 4));
                if (o.Delivery_Date__c > today) {
                    o.Delivery_Date__c = today;
                }
            }
            out.add(o);
            d = d.addDays(rng.between(26, 34));
            if (latest) {
                break;
            }
        }
        return out;
    }

    private static Integer quantityFor(Rng rng, String code) {
        if (code == 'PSP-ERBITUX') return rng.between(2, 6);
        if (code == 'PSP-REBIF') return rng.between(1, 2);
        if (code == 'PSP-MAVENCLAD') return 1;
        return rng.between(2, 4);
    }

    // ---------------------------------------------------------------- planner

    private void schedulePlannedCalls() {
        List<Date> days = new List<Date>();
        Date d = Date.today().addDays(1);
        while (days.size() < 8) {
            Integer dow = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(d), 7); // 0 = Sunday
            if (dow != 5 && dow != 6) {
                days.add(d);
            }
            d = d.addDays(1);
        }
        List<Time> slots = new List<Time>{
            Time.newInstance(9, 5, 0, 0), Time.newInstance(9, 40, 0, 0), Time.newInstance(10, 15, 0, 0),
            Time.newInstance(11, 0, 0, 0), Time.newInstance(13, 10, 0, 0), Time.newInstance(14, 0, 0, 0),
            Time.newInstance(15, 30, 0, 0)
        };
        String pattern = SEED_PREFIX + '%';
        List<Patient_Interaction__c> planned = new List<Patient_Interaction__c>();
        Set<Id> touched = new Set<Id>();
        Integer coachIndex = 0;
        for (Id coach : coachIds) {
            coachIndex++;
            Integer perDay = coach == leadCoachId ? 7 : 4;
            Integer stride = coach == leadCoachId ? 1 : 3;
            Integer maxRows = perDay * days.size();
            List<Patient__c> candidates = [
                SELECT Id, Primary_Product__c, Primary_Product__r.Name, Status__c, AI_Risk_Score__c
                FROM Patient__c
                WHERE Care_Coach__c = :coach AND External_Id__c LIKE :pattern
                    AND Status_Group__c IN ('Ongoing', 'Pending') AND Next_Call_Date__c = NULL
                ORDER BY AI_Risk_Score__c DESC NULLS LAST, Enrollment_Date__c DESC
                LIMIT :maxRows
            ];
            Integer idx = 0;
            for (Date day : days) {
                for (Integer k = 0; k < perDay && idx < candidates.size(); k++) {
                    Patient__c p = candidates[idx++];
                    Time slot = slots[Math.mod(k * stride + (coach == leadCoachId ? 0 : coachIndex), slots.size())];
                    Datetime startAt = demoTime(day, slot);
                    if (startAt < System.now()) {
                        startAt = demoTime(day.addDays(7), slot);
                    }
                    String reason = p.Status__c == 'Pending' ? 'Welcome call'
                        : (p.AI_Risk_Score__c != null && p.AI_Risk_Score__c >= 60 ? 'Adherence check' : 'Follow up');
                    planned.add(new Patient_Interaction__c(
                        Patient__c = p.Id,
                        Subject__c = reason + ' - ' + p.Primary_Product__r.Name,
                        Type__c = 'Call',
                        Direction__c = 'Outbound',
                        Status__c = 'Planned',
                        Interaction_Reason__c = reason,
                        Priority__c = reason == 'Adherence check' ? 'High' : 'Medium',
                        Start__c = startAt,
                        End__c = startAt.addMinutes(5),
                        Duration_Minutes__c = 5,
                        Care_Coach__c = coach,
                        Product__c = p.Primary_Product__c
                    ));
                    touched.add(p.Id);
                }
            }
        }
        insert planned;
        CareCoachPatientService.refreshPatientFromCalls(touched);
    }

    private void seedTimeOff() {
        Integer existing = [SELECT COUNT() FROM Time_Off_Request__c WHERE OwnerId = :leadCoachId AND Start_Date_Time__c >= :System.now()];
        if (existing > 0) {
            return;
        }
        String typeValue;
        for (Schema.PicklistEntry e : Time_Off_Request__c.Type__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                typeValue = e.getValue();
                break;
            }
        }
        if (typeValue == null) {
            return;
        }
        Date nextWeek = Date.today().addDays(7);
        Time_Off_Request__c leave = new Time_Off_Request__c(OwnerId = leadCoachId, Stage__c = 'Submitted for Approval');
        CareCoachPlannerController.applyTimeOff(leave, typeValue, 'Full_Day', null,
            Datetime.newInstance(nextWeek, Time.newInstance(9, 0, 0, 0)), 'Annual leave (demo)');
        Time_Off_Request__c clinic = new Time_Off_Request__c(OwnerId = leadCoachId, Stage__c = 'Draft');
        CareCoachPlannerController.applyTimeOff(clinic, typeValue, 'Hours', '2',
            Datetime.newInstance(nextWeek.addDays(-2), Time.newInstance(13, 0, 0, 0)), 'Clinic visit (demo)');
        for (Database.SaveResult r : Database.insert(new List<Time_Off_Request__c>{ leave, clinic }, false)) {
            if (!r.isSuccess()) {
                System.debug(LoggingLevel.WARN, 'Care Coach demo time off skipped: ' + r.getErrors()[0].getMessage());
            }
        }
    }

    /** Planned calls for the coming working week and demo time off; safe to re-run. */
    public static void seedPlanner() {
        CareCoachDemoSeed s = new CareCoachDemoSeed(0, 0);
        s.leadCoachId = UserInfo.getUserId();
        s.coachIds = s.loadCoaches();
        s.schedulePlannedCalls();
        s.seedTimeOff();
    }

    // ---------------------------------------------------------------- knowledge

    public static void seedScripts(Map<String, Id> products) {
        if ([SELECT COUNT() FROM Care_Script__c WHERE Product__c IN :products.values()] > 0) {
            return;
        }
        List<Care_Script__c> rows = new List<Care_Script__c>();
        Date published = Date.today().addMonths(-4);
        rows.add(script(products, 'PSP-ERBITUX', 'Oncology', 'Managing the acne-like rash', 'Side effects',
            'What can I do about the rash on my face and chest?',
            '<p>An acne-like rash is the most common side effect of cetuximab and usually appears in the first 2–3 weeks. It is a sign the medicine is working on the EGFR receptor.</p><ul><li>Wash with a mild, soap-free cleanser and lukewarm water.</li><li>Apply a fragrance-free moisturiser twice a day.</li><li>Use SPF 30+ sunscreen and avoid direct sun.</li><li>Do <b>not</b> use over-the-counter acne products; they dry the skin.</li></ul><p>Tell your oncologist if the rash is painful, infected or stops you sleeping — they may prescribe an antibiotic cream or tablets.</p>',
            'Skin care routine and when to escalate a cetuximab rash.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-ERBITUX', 'Oncology', 'Infusion reactions', 'Side effects',
            'What should I watch for during and after the infusion?',
            '<p>Infusion reactions usually happen during the first infusion or within an hour of it. The team will give you pre-medication and monitor you.</p><p><b>Call for help immediately</b> if you have difficulty breathing, wheezing, swelling of the face or lips, or feel faint.</p><p>Mild chills or fever the evening after the infusion can be treated with paracetamol; report it at your next call.</p>',
            'Recognising infusion reactions; urgent symptoms.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-ERBITUX', 'Oncology', 'Magnesium and blood tests', 'Adherence',
            'Why do I need magnesium blood tests?',
            '<p>Cetuximab can lower magnesium levels, which may cause tiredness or muscle cramps. Your oncologist will check your magnesium before each cycle and give supplements if needed.</p><p>Keep your lab appointments and bring previous results to each visit.</p>',
            'Monitoring schedule for electrolytes.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-ERBITUX', 'Oncology', 'Infusion schedule and missed sessions', 'Administration',
            'What happens if I miss an infusion session?',
            '<p>Erbitux is given weekly or every two weeks at the hospital. If you cannot attend, call the oncology day-care unit as early as possible to reschedule — do not skip the session without telling the team.</p><p>Your care coach can help arrange transport or reschedule the delivery of your vials to the hospital pharmacy.</p>',
            'Rescheduling infusions and coordinating vial delivery.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-ERBITUX', 'Oncology', 'Access and reimbursement support', 'Access & reimbursement',
            'Can the programme help with the cost of treatment?',
            '<p>The patient access team can review your insurance or Universal Health Insurance coverage, help prepare the reimbursement file, and check eligibility for the patient assistance programme.</p><p>Ask your care coach to open an access request; the team calls back within two working days.</p>',
            'Referral path to the access team.', 'Not Validated', 'Draft', null));

        rows.add(script(products, 'PSP-REBIF', 'Neurology', 'Flu-like symptoms after injection', 'Side effects',
            'How can I reduce flu-like symptoms after Rebif?',
            '<p>Flu-like symptoms (fever, chills, muscle aches, headache) are common in the first months and usually improve over time.</p><ul><li>Inject in the evening so you sleep through the symptoms.</li><li>Take paracetamol or ibuprofen before the injection if your neurologist agrees.</li><li>Drink plenty of water.</li></ul>',
            'Evening dosing and pre-medication tips.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-REBIF', 'Neurology', 'Injection-site care and rotation', 'Administration',
            'How do I avoid redness and bruising at the injection site?',
            '<p>Rotate injection sites between the thighs, abdomen, upper arms and buttocks. RebiSmart can remind you which site is next.</p><p>Let the medicine reach room temperature, clean the skin and let it dry, and apply a cold pack after the injection. Report any area that is hot, painful or has broken skin.</p>',
            'Site rotation plan using RebiSmart.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-REBIF', 'Neurology', 'Storing Rebif', 'Storage & handling',
            'How should I store my pens or cartridges?',
            '<p>Store Rebif in the fridge (2–8 °C), never in the freezer. If needed you can keep it at room temperature (up to 25 °C) for up to 14 days. Keep it in the original box away from light.</p><p>When travelling, use a cool bag and carry a letter from your neurologist.</p>',
            'Cold-chain and travel guidance.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-REBIF', 'Neurology', 'Liver tests and blood counts', 'Adherence',
            'Which tests do I need while on Rebif?',
            '<p>Your neurologist will check liver enzymes and blood counts at 1, 3 and 6 months and then regularly. Thyroid tests may also be requested. An MRI is usually repeated every 6–12 months.</p>',
            'Monitoring schedule.', 'Validated', 'Published', published));

        rows.add(script(products, 'PSP-MAVENCLAD', 'Neurology', 'How Mavenclad treatment weeks work', 'Disease education',
            'How often do I take Mavenclad tablets?',
            '<p>Mavenclad is taken in two short courses per year, for two years. Each course has two treatment weeks about one month apart, with 1–2 tablets a day for 4–5 days depending on your weight.</p><p>There is no treatment in years 3 and 4, but your neurologist will continue to follow you.</p>',
            'Dosing calendar for years 1 and 2.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-MAVENCLAD', 'Neurology', 'Lymphocyte blood tests', 'Adherence',
            'Why do I need a lymphocyte count?',
            '<p>Cladribine lowers lymphocytes (a type of white blood cell). Your doctor checks your count before each treatment year and 2 and 6 months after starting. The second year only starts if your count has recovered enough.</p>',
            'Lymphocyte monitoring and treatment decisions.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-MAVENCLAD', 'Neurology', 'Infections and shingles', 'Side effects',
            'What should I do if I get an infection?',
            '<p>Because lymphocytes are lower, infections such as shingles (herpes zoster) are more likely. Contact your neurologist promptly if you notice a painful rash with blisters, fever, or signs of infection. Vaccination against shingles may be recommended before treatment.</p>',
            'Infection warning signs.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-MAVENCLAD', 'Neurology', 'Handling the tablets', 'Storage & handling',
            'How do I handle and take the tablets?',
            '<p>Swallow the tablet whole with water, with dry hands, and wash your hands afterwards. Do not take other oral medicines within 3 hours. Store in the original packaging at room temperature.</p>',
            'Safe handling of cytotoxic tablets.', 'Not Validated', 'Draft', null));

        rows.add(script(products, 'PSP-SAIZEN', 'Endocrinology', 'Using the easypod auto-injector', 'Administration',
            'How do we give the daily injection with easypod?',
            '<p>Easypod delivers the dose automatically once the skin sensor detects contact. Load the cartridge, attach a new needle, check the dose on the screen, and hold the device at 90° until the confirmation tone.</p><p>Easypod records every injection; your care coach can review adherence with you through easypod connect.</p>',
            'Step-by-step easypod technique.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-SAIZEN', 'Endocrinology', 'Helping children with daily injections', 'Adherence',
            'My child is tired of the injections — what can help?',
            '<p>Keep the same time every evening, let the child choose the injection site, and use a reward chart. Easypod\'s needle-hiding design helps with fear of needles.</p><p>If doses are being missed, tell your care coach; we can arrange a nurse home visit.</p>',
            'Adherence tips for caregivers.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-SAIZEN', 'Endocrinology', 'Storing Saizen cartridges', 'Storage & handling',
            'How do we store the cartridges?',
            '<p>Keep unopened and in-use cartridges in the fridge (2–8 °C). Once opened, use within 28 days. Do not freeze. Remove the needle after each injection.</p>',
            'Fridge storage and in-use period.', 'Validated', 'Published', published));
        rows.add(script(products, 'PSP-SAIZEN', 'Endocrinology', 'Growth checks and x-rays', 'Disease education',
            'How will the doctor know the treatment is working?',
            '<p>Height is measured every 3–6 months and compared with growth charts. A hand x-ray (bone age) and IGF-1 blood test help the endocrinologist adjust the dose.</p>',
            'Monitoring growth response.', 'Validated', 'Published', published));

        rows.add(script(products, null, 'General', 'Reporting a side effect (pharmacovigilance)', 'Side effects',
            'How does the programme handle side-effect reports?',
            '<p>Every side effect mentioned during a call is recorded and forwarded to Merck pharmacovigilance within 24 hours, even if it seems minor. Serious events (hospitalisation, severe allergic reaction, seizure) are escalated immediately and the treating physician is informed.</p>',
            'PV reporting standard for care coaches.', 'Validated', 'Published', published));
        rows.add(script(products, null, 'General', 'Consent and privacy', 'Access & reimbursement',
            'Who can see my personal information?',
            '<p>Only your care coach team can see your name and contact details. The pharmaceutical company only receives de-identified information (initials, age and gender) together with treatment and call outcomes, to improve the programme.</p>',
            'Patient privacy statement.', 'Validated', 'Published', published));
        insert rows;
    }

    private static Care_Script__c script(Map<String, Id> products, String code, String therapyArea, String title, String category,
        String question, String answer, String summary, String validation, String publication, Date publishedOn) {
        return new Care_Script__c(
            Product__c = code == null ? null : products.get(code),
            Therapy_Area__c = therapyArea,
            Title__c = title,
            Category__c = category,
            Question__c = question,
            Answer__c = answer,
            Summary__c = summary,
            Language__c = 'English',
            Validation_Status__c = validation,
            Publication_Status__c = publication,
            Published_Date__c = publishedOn,
            Helpful_Count__c = publication == 'Published' ? Math.mod(Math.abs(title.hashCode()), 40) : 0
        );
    }
}