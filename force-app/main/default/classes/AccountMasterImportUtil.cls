/**
 * Shared mapping helpers for Zeta Account master import.
 */
public with sharing class AccountMasterImportUtil {
    public static final String EXT_DOC_PREFIX = 'DOC-';
    public static final String EXT_CLINIC_PREFIX = 'CLINIC-';
    public static final String EXT_AFF_PREFIX = 'AFF-';
    public static final String COUNTRY = 'Egypt';

    private static final Map<String, String> SPECIALTY_MAP = new Map<String, String>{
        'Andro' => 'Andrology',
        'Cardio' => 'Cardiology',
        'Chest' => 'Pneumology',
        'Derma' => 'Dermatology',
        'Diabetes' => 'Diabetology',
        'ENT' => 'Otorhinolaryngology',
        'Endo' => 'Endocrinology',
        'G.P' => 'General_Practice',
        'GIT' => 'Gastroenterology',
        'Gyna' => 'Obstetrics_and_Gynaecology',
        'Hemat.' => 'Haematology',
        'Hept.' => 'Hepatology',
        'ICU' => 'Intensive_Care',
        'IM' => 'Internal_Medicine',
        'Nephro' => 'Nephrology',
        'Neuro' => 'Neurology',
        'Nutrition' => 'Nutrition_Medicine',
        'Onco' => 'Oncology',
        'Ortho' => 'Orthopaedics',
        'Pedia' => 'Paediatrics',
        'Pharmacist' => 'Clinical_Pharmacy',
        'Plastic Surgery' => 'Plastic_Surgery',
        'Psychiatry' => 'Psychiatry',
        'Rheuma' => 'Rheumatology',
        'Surgery' => 'General_Surgery',
        'Tropical' => 'Tropical_Medicine',
        'Uro' => 'Urology',
        'V.Surgery' => 'Vascular_Surgery'
    };

    public static String doctorExternalId(String doctorCode) {
        return EXT_DOC_PREFIX + normalizeCode(doctorCode);
    }

    public static String clinicExternalId(String clinicId) {
        return EXT_CLINIC_PREFIX + normalizeCode(clinicId);
    }

    public static String affiliationExternalId(String doctorCode, String relatedExternalId) {
        return EXT_AFF_PREFIX + doctorExternalId(doctorCode) + '-' + normalizeCode(relatedExternalId);
    }

    public static String normalizeCode(String value) {
        return value == null ? '' : String.valueOf(value).trim();
    }

    public static String mapSpecialty(String excelSpecialty) {
        if (String.isBlank(excelSpecialty)) {
            return null;
        }
        String key = excelSpecialty.trim();
        if (SPECIALTY_MAP.containsKey(key)) {
            return SPECIALTY_MAP.get(key);
        }
        return null;
    }

    /** Picklist value back to the master-list spelling (Internal_Medicine -> IM); null when unmapped. */
    public static String excelSpecialty(String picklistValue) {
        if (String.isBlank(picklistValue)) {
            return null;
        }
        for (String key : SPECIALTY_MAP.keySet()) {
            if (SPECIALTY_MAP.get(key) == picklistValue) {
                return key;
            }
        }
        return null;
    }

    /** Numeric prefix of a master pharmacy name ("1000000007_Name" -> 1000000007); null when absent. */
    public static String pharmacyCodeFromName(String rawName) {
        if (String.isBlank(rawName) || !rawName.contains('_')) {
            return null;
        }
        String prefix = rawName.substring(0, rawName.indexOf('_')).trim();
        return String.isNotBlank(prefix) && prefix.isNumeric() ? prefix.left(40) : null;
    }

    /** Master-list pharmacy name: "{code}_{name}" when the account carries a pharmacy code. */
    public static String pharmacyMasterName(String pharmacyCode, String name) {
        return String.isBlank(pharmacyCode) ? name : pharmacyCode + '_' + name;
    }

    public static String mapTierFromClass(String customerClass) {
        if (String.isBlank(customerClass)) {
            return null;
        }
        String upper = customerClass.trim().toUpperCase();
        for (Integer i = 0; i < upper.length(); i++) {
            String ch = upper.substring(i, i + 1);
            if (ch == 'A' || ch == 'B' || ch == 'C') {
                return ch;
            }
        }
        return null;
    }

    public static void splitPersonName(String fullName, Account person) {
        String cleaned = fullName == null ? '' : fullName.trim().replaceAll('\\s+', ' ');
        if (String.isBlank(cleaned)) {
            person.LastName = 'Unknown';
            return;
        }
        Integer space = cleaned.indexOf(' ');
        if (space <= 0) {
            person.LastName = cleaned;
            return;
        }
        person.FirstName = cleaned.substring(0, space).left(40);
        person.LastName = cleaned.substring(space + 1).left(80);
        if (String.isBlank(person.LastName)) {
            person.LastName = cleaned.left(80);
        }
    }

    public static String normalizePhone(Object raw) {
        if (raw == null) {
            return null;
        }
        String digits = String.valueOf(raw).replaceAll('[^0-9+]', '');
        if (String.isBlank(digits)) {
            return null;
        }
        if (!digits.startsWith('+') && digits.length() == 10 && digits.startsWith('1')) {
            return '+20' + digits;
        }
        if (!digits.startsWith('+') && digits.length() >= 10) {
            return '+20' + digits;
        }
        return digits.left(40);
    }

    public static Id recordTypeId(String developerName) {
        return recordTypeId(developerName, null);
    }

    /**
     * @param personOnly true = person account RT, false = business RT, null = either
     */
    public static Id recordTypeId(String developerName, Boolean personOnly) {
        String soql =
            'SELECT Id, IsPersonType FROM RecordType WHERE SobjectType = \'Account\' AND DeveloperName = :developerName AND IsActive = TRUE';
        List<RecordType> rts = Database.query(soql);
        for (RecordType rt : rts) {
            if (personOnly == true && !rt.IsPersonType) {
                continue;
            }
            if (personOnly == false && rt.IsPersonType) {
                continue;
            }
            return rt.Id;
        }
        throw new AuraHandledException(
            'Account record type not available: ' +
                developerName +
                (personOnly == true ? ' (person)' : personOnly == false ? ' (business)' : '')
        );
    }

    public static Id hcpRecordTypeId() {
        try {
            return recordTypeId('PersonAccount', true);
        } catch (Exception e) {
            try {
                return recordTypeId('SDO_PersonAccounts', true);
            } catch (Exception e2) {
                return recordTypeId('Medical_Professional_HCP', false);
            }
        }
    }

    public static Id clinicHcpRecordTypeId() {
        // Clinics are workplaces (HCO), never Medical_Professional_HCP.
        return recordTypeId('Institution_HCO', false);
    }

    private static final Set<String> LATIN_WORKPLACE = new Set<String>{
        'ABB', 'GUC', 'PGESCO', 'CPC', 'PAS', 'P.M.S', 'PMS', 'E GAS', 'EGAS', 'OGS', 'IDA', 'DMS',
        'DUSIT', 'THARWA', 'THAWRA', 'UCP', 'AUC', 'AXA', 'DOMTY', 'GASTEC', 'HYPER', 'MOPCO',
        'PETROMINT', 'PETROSENNAN', 'THERMOTECH', 'VACSERA', 'ZETCO', 'SAN MASR', 'PRIMA'
    };

    private static final List<String> WORKPLACE_PREFIXES = new List<String>{
        '\u0642\u0633\u0645', '\u0628\u0646\u0643', '\u0634\u0631\u0643\u0647', '\u0634\u0631\u0643\u0629',
        '\u0645\u0635\u0646\u0639', '\u0643\u0647\u0631\u0628\u0627\u0621', '\u0643\u0647\u0631\u0628\u0627',
        '\u062a\u0639\u0627\u0642\u062f', '\u0647\u064a\u0626\u0647', '\u0647\u064a\u0626\u0629',
        '\u0648\u0632\u0627\u0631\u0647', '\u0648\u0632\u0627\u0631\u0629', '\u062c\u0647\u0627\u0632',
        '\u0645\u0633\u062a\u0634\u0641\u0649', '\u0645\u0633\u062a\u0634\u0641\u064a',
        '\u0647\u0627\u064a\u0628\u0631', '\u0645\u0631\u0641\u0642'
    };

    /**
     * True when a Doctors.xlsx name is a workplace/HQ, not a person HCP.
     * Pure Latin/ASCII names and Latin-brand + Arabic location names are workplaces.
     */
    public static Boolean isWorkplaceDoctorName(String doctorName) {
        if (String.isBlank(doctorName)) {
            return false;
        }
        String name = doctorName.trim();
        String upper = name.toUpperCase();
        String compact = upper.replace(' ', '').replace('.', '');
        if (LATIN_WORKPLACE.contains(upper) || LATIN_WORKPLACE.contains(compact)) {
            return true;
        }
        if (isPureLatinWorkplaceName(name)) {
            return true;
        }
        if (hasLeadingLatinBrand(name)) {
            return true;
        }
        for (String prefix : WORKPLACE_PREFIXES) {
            if (name.startsWith(prefix)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isPureLatinWorkplaceName(String name) {
        if (String.isBlank(name)) {
            return false;
        }
        // Arabic letter range
        if (name.replaceAll('[\\u0600-\\u06FF]', '').length() != name.length()) {
            return false;
        }
        return Pattern.compile('^[A-Za-z0-9 .,&/+\\-\']+$').matcher(name).matches();
    }

    private static Boolean hasLeadingLatinBrand(String name) {
        Matcher m = Pattern.compile('^([A-Za-z][A-Za-z0-9.&]{1,})\\b').matcher(name);
        if (!m.find()) {
            return false;
        }
        String token = m.group(1);
        String rest = name.substring(m.end()).trim();
        String up = token.toUpperCase().replace('.', '');
        if (LATIN_WORKPLACE.contains(token.toUpperCase()) || LATIN_WORKPLACE.contains(up)) {
            return true;
        }
        // Mixed: UCP عوايد / ABB العاشر من رمضان
        if (String.isNotBlank(rest) && rest.replaceAll('[\\u0600-\\u06FF]', '').length() != rest.length()) {
            return token.length() >= 2;
        }
        return false;
    }

    /** Strip leading numeric id prefixes from Excel pharmacy names: 1000027554_Name. */
    public static String cleanPrefixedAccountName(String rawName) {
        if (String.isBlank(rawName) || !rawName.contains('_')) {
            return rawName;
        }
        Integer idx = rawName.indexOf('_');
        if (idx <= 0 || idx >= rawName.length() - 1) {
            return rawName;
        }
        String prefix = rawName.substring(0, idx);
        String rest = rawName.substring(idx + 1).trim();
        if (String.isBlank(rest) || !prefix.isNumeric()) {
            return rawName;
        }
        return rest.length() > 255 ? rest.substring(0, 255) : rest;
    }

    /** Apex-style clinic workplace name: عيادة {Doctor} - {Area}. */
    public static String clinicDisplayName(String doctorName, String area, String clinicId, String address) {
        String doc = String.isBlank(doctorName) ? ('Clinic ' + normalizeCode(clinicId)) : doctorName.trim();
        String loc = String.isBlank(area) ? '\u063a\u064a\u0631 \u0645\u062d\u062f\u062f' : area.trim();
        String base = ('\u0639\u064a\u0627\u062f\u0629 ' + doc + ' - ' + loc).left(255);
        return base;
    }

    public static Boolean isPersonRecordType(Id recordTypeId) {
        if (recordTypeId == null) {
            return false;
        }
        List<RecordType> rts = [
            SELECT IsPersonType
            FROM RecordType
            WHERE Id = :recordTypeId
            LIMIT 1
        ];
        return !rts.isEmpty() && rts[0].IsPersonType;
    }

    public static Boolean toBoolean(Object raw, Boolean defaultValue) {
        if (raw == null) {
            return defaultValue;
        }
        if (raw instanceof Boolean) {
            return (Boolean) raw;
        }
        String s = String.valueOf(raw).trim().toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') {
            return true;
        }
        if (s == 'false' || s == '0' || s == 'no') {
            return false;
        }
        return defaultValue;
    }
}