/**
 * Demo personas sourced from Plan/Zeta Demo Data (Diab III, Feb 2026).
 * Diabetes BU uses exact CRM/sales figures; other BUs use Chemipharm demo names + archetype metrics.
 */
public without sharing class ChemipharmDemoDataProfiles {

    public class DemoUserProfile {
        public String demoUserKey;
        public String firstName;
        public String lastName;
        public String roleLabel;
        public String department;
        public String areaLabel;
        public Date hireDate;
        public Boolean probation;
        public Integer febActualVisits;
        public Decimal visitAchievementPct;
        public Decimal coveragePct;
        public Decimal salesAchievementPct;
        public Integer targetCustomers;
    }

    private static final List<Decimal> MONTH_VOLUME_FACTORS = new List<Decimal>{
        0.97, 1.00, 1.03, 0.98, 1.02, 0.99
    };

    // Fatma HELWAN Empacoza Trio rows — DIB III FEB SALES ACH.xlsx
    private static final Decimal DIABETES_SALES_TARGET_EGP = 736560.0;
    private static final Decimal DIABETES_SALES_ACTUAL_EGP = 624144.7356625701;

    private static final Set<String> DIABETES_BRICK_EXT_IDS = new Set<String>{
        'BRICK_EG10201', 'BRICK_EG10202'
    };

    private static final Set<String> PRIMARY_DEMO_USER_KEYS = new Set<String>{
        'git_dm', 'git_mr', 'cns_dm', 'cns_mr', 'amr_mr',
        'rheum_dm', 'rheum_mr', 'cardio_dm', 'cardio_mr',
        'chc_dm', 'chc_mr'
    };

    private static final Map<String, DemoUserProfile> PROFILES_BY_KEY = buildProfiles();

    public static DemoUserProfile getUserProfile(String demoUserKey) {
        return PROFILES_BY_KEY.get(demoUserKey);
    }

    public static List<String> getAllDemoUserKeys() {
        List<String> keys = new List<String>();
        for (String key : PRIMARY_DEMO_USER_KEYS) {
            if (PROFILES_BY_KEY.containsKey(key)) {
                keys.add(key);
            }
        }
        return keys;
    }

    public static String resolveDemoUserKeyFromUsername(String username) {
        if (String.isBlank(username)) {
            return null;
        }
        String localPart = username.substringBefore('@').toLowerCase();
        return localPart.replace('.', '_');
    }

    public static Integer getMonthlyVisitVolume(String demoUserKey, Integer monthIndex) {
        DemoUserProfile profile = getUserProfile(demoUserKey);
        if (profile == null || profile.febActualVisits == null) {
            return 0;
        }
        if (monthIndex == null || monthIndex < 0) {
            monthIndex = 0;
        }
        if (monthIndex >= MONTH_VOLUME_FACTORS.size()) {
            monthIndex = Math.mod(monthIndex, MONTH_VOLUME_FACTORS.size());
        }

        Integer baseline = profile.febActualVisits;
        Decimal factor = MONTH_VOLUME_FACTORS[monthIndex];
        return Integer.valueOf(Math.max(0, Math.round(baseline * factor)));
    }

    public static Decimal getCoveragePct(String demoUserKey) {
        DemoUserProfile profile = getUserProfile(demoUserKey);
        return profile == null ? 0.87 : valueOrZero(profile.coveragePct);
    }

    public static Decimal getVisitAchievementPct(String demoUserKey) {
        DemoUserProfile profile = getUserProfile(demoUserKey);
        return profile == null ? null : profile.visitAchievementPct;
    }

    public static Decimal getSalesAchievementPct(String demoUserKey) {
        DemoUserProfile profile = getUserProfile(demoUserKey);
        return profile == null ? null : profile.salesAchievementPct;
    }

    public static Decimal getDiabetesSalesTargetEgp() {
        return DIABETES_SALES_TARGET_EGP;
    }

    public static Decimal getDiabetesSalesActualEgp() {
        return DIABETES_SALES_ACTUAL_EGP;
    }

    public static Boolean isDiabetesBrick(String brickExternalId) {
        return brickExternalId != null && DIABETES_BRICK_EXT_IDS.contains(brickExternalId);
    }

    public static List<Decimal> getCoachingScores(String mrKey) {
        if (mrKey == 'git_mr' || mrKey == 'rheum_mr' || mrKey == 'cluster_mr') {
            return new List<Decimal>{ 78, 80, 82, 84, 85, 85 };
        }
        if (mrKey == 'chc_mr') {
            return new List<Decimal>{ 70, 72, 74, 76, 78, 80 };
        }
        if (mrKey == 'amr_mr') {
            return new List<Decimal>{ 82, 77, 72, 67, 61, 55 };
        }
        if (mrKey == 'cns_mr' || mrKey == 'diabetes_mr' || mrKey == 'cardio_mr' || mrKey == 'gastro_mr') {
            return new List<Decimal>{ 68, 70, 72, 73, 74, 75 };
        }
        return new List<Decimal>{ 66, 68, 70, 71, 72, 73 };
    }

    private static Map<String, DemoUserProfile> buildProfiles() {
        Map<String, DemoUserProfile> profiles = new Map<String, DemoUserProfile>();
        profiles.put('git_dm', profile(
            'git_dm', 'Peter', 'AbdelNasser Fathy Habel', 'District Manager', 'GIT',
            'GIT Cairo Central', Date.newInstance(2025, 2, 1), false,
            36, 0.90, 0.94, null, 380
        ));
        profiles.put('git_mr', profile(
            'git_mr', 'AbdelMoneim', 'Sayed AbdelMoneim Sayed Darwish', 'Medical Rep', 'GIT',
            'GIT Abbaseia-Kobbah', Date.newInstance(2025, 7, 12), false,
            169, 0.9769, 0.9620, 0.8865, 79
        ));
        profiles.put('cns_dm', profile(
            'cns_dm', 'Ahmed', 'Adel Hosny Hassan', 'District Manager', 'CNS',
            'CNS Cairo A', Date.newInstance(2026, 1, 1), false,
            271, 0.5232, 0.6667, null, 210
        ));
        profiles.put('cns_mr', profile(
            'cns_mr', 'Fatma', 'Fawzy Mohamed Mahmoud', 'Medical Rep', 'CNS',
            'CNS Helwan', Date.newInstance(2024, 1, 1), false,
            127, 0.6720, 0.8734, 0.7843, 79
        ));
        profiles.put('amr_mr', profile(
            'amr_mr', 'Amr', 'Salah', 'Medical Rep', 'CNS',
            'CNS Helwan', Date.newInstance(2025, 3, 1), false,
            118, 0.6400, 0.8200, 0.7100, 74
        ));
        profiles.put('rheum_dm', profile(
            'rheum_dm', 'Jacklyn', 'Mamdouh Aziz Loka', 'District Manager', 'RHEUMATOLOGY',
            'Rheum Giza', Date.newInstance(2024, 6, 1), false,
            21, 0.8664, 0.96, null, 59
        ));
        profiles.put('rheum_mr', profile(
            'rheum_mr', 'Donia', 'Mahmoud Mohamed Ahmed Mowafy', 'Medical Rep', 'RHEUMATOLOGY',
            'Rheum Dakahlia', Date.newInstance(2026, 1, 1), true,
            169, 1.0833, 1.00, 0.9717, 76
        ));
        profiles.put('cardio_dm', profile(
            'cardio_dm', 'Karim', 'Mohamed Nagib Mohamed El-Demerdash', 'District Manager', 'CARDIO',
            'Cardio Alex-Beheira', Date.newInstance(2020, 7, 18), false,
            35, 0.9381, 0.9818, null, 52
        ));
        profiles.put('cardio_mr', profile(
            'cardio_mr', 'Eman', 'Hamdy Shahat Esmail', 'Medical Rep', 'CARDIO',
            'Cardio Cairo West', Date.newInstance(2025, 11, 2), false,
            144, 0.7912, 0.9726, null, 73
        ));
        // Consumer Health BU — Soul Pharma distribution line (Soulfort / Genolight)
        profiles.put('chc_dm', profile(
            'chc_dm', 'Mohamed', 'ElSayed Mostafa Gaber', 'District Manager', 'CONSUMER HEALTH',
            'CHC Cairo Retail', Date.newInstance(2023, 5, 1), false,
            28, 0.8850, 0.9300, null, 64
        ));
        profiles.put('chc_mr', profile(
            'chc_mr', 'Nourhan', 'Ashraf Mostafa Hassan', 'Medical Rep', 'CONSUMER HEALTH',
            'CHC Maadi Pharmacies', Date.newInstance(2024, 8, 29), false,
            152, 0.9120, 0.8975, 0.8410, 68
        ));
        // Legacy aliases for older seed scripts
        profiles.put('diabetes_dm', profiles.get('cns_dm'));
        profiles.put('diabetes_mr', profiles.get('cns_mr'));
        profiles.put('cluster_dm', profiles.get('rheum_dm'));
        profiles.put('cluster_mr', profiles.get('rheum_mr'));
        profiles.put('gastro_dm', profiles.get('git_dm'));
        profiles.put('gastro_mr', profiles.get('git_mr'));
        return profiles;
    }

    private static DemoUserProfile profile(
        String demoUserKey,
        String firstName,
        String lastName,
        String roleLabel,
        String department,
        String areaLabel,
        Date hireDate,
        Boolean probation,
        Integer febActualVisits,
        Decimal visitAchievementPct,
        Decimal coveragePct,
        Decimal salesAchievementPct,
        Integer targetCustomers
    ) {
        DemoUserProfile p = new DemoUserProfile();
        p.demoUserKey = demoUserKey;
        p.firstName = firstName;
        p.lastName = lastName;
        p.roleLabel = roleLabel;
        p.department = department;
        p.areaLabel = areaLabel;
        p.hireDate = hireDate;
        p.probation = probation;
        p.febActualVisits = febActualVisits;
        p.visitAchievementPct = visitAchievementPct;
        p.coveragePct = coveragePct;
        p.salesAchievementPct = salesAchievementPct;
        p.targetCustomers = targetCustomers;
        return p;
    }

    private static Decimal valueOrZero(Decimal value) {
        return value == null ? 0 : value;
    }
}
