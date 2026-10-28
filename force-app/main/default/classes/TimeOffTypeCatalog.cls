/**
 * Canonical TOT type catalogue shared by Apex services and Mendix mapping.
 * Legacy API values remain supported for existing records / tests.
 */
public with sharing class TimeOffTypeCatalog {
    public class TypeDefinition {
        public String apiValue;
        public String label;
        public String mendixTypeCode;
        public Boolean blocksVisits;
        public Boolean requiresApproval;
        public Boolean countsAsTot;

        public TypeDefinition(
            String apiValue,
            String label,
            String mendixTypeCode,
            Boolean blocksVisits,
            Boolean requiresApproval,
            Boolean countsAsTot
        ) {
            this.apiValue = apiValue;
            this.label = label;
            this.mendixTypeCode = mendixTypeCode;
            this.blocksVisits = blocksVisits;
            this.requiresApproval = requiresApproval;
            this.countsAsTot = countsAsTot;
        }
    }

    private static final Map<String, TypeDefinition> BY_API = new Map<String, TypeDefinition>{
        'Annual Leave' => new TypeDefinition('Annual Leave', 'Annual Leave', 'ANNUAL_LEAVE', true, true, true),
        'Business Trip' => new TypeDefinition('Business Trip', 'Business Trip', 'BUSINESS_TRIP', true, true, true),
        'Sick' => new TypeDefinition('Sick', 'Sick', 'SICK', true, true, true),
        'Training' => new TypeDefinition('Training', 'Training', 'TRAINING', true, true, true),
        'Casual/Emergency' => new TypeDefinition('Casual/Emergency', 'Casual/Emergency', 'CASUAL_EMERGENCY', true, true, true),
        'Health Day' => new TypeDefinition('Health Day', 'Health Day', 'HEALTH_DAY', true, true, true),
        'Maternity/Paternity' => new TypeDefinition(
            'Maternity/Paternity',
            'Maternity/Paternity',
            'MATERNITY_PATERNITY',
            true,
            true,
            true
        ),
        'Office Work' => new TypeDefinition('Office Work', 'Office Work', 'OFFICE_WORK', false, true, true),
        'Marriage' => new TypeDefinition('Marriage', 'Marriage', 'MARRIAGE', true, true, true),
        'Cycle Meeting' => new TypeDefinition('Cycle Meeting', 'Cycle Meeting', 'CYCLE_MEETING', true, true, true),
        'Unpaid' => new TypeDefinition('Unpaid', 'Unpaid', 'UNPAID', true, true, true),
        'Sales Meeting' => new TypeDefinition('Sales Meeting', 'Sales Meeting', 'SALES_MEETING', true, true, true),
        'Military' => new TypeDefinition('Military', 'Military', 'MILITARY', true, true, true),
        'Prospection' => new TypeDefinition('Prospection', 'Prospection', 'PROSPECTION', true, true, true),
        'Handover' => new TypeDefinition('Handover', 'Handover', 'HANDOVER', true, true, true),
        'Sales Day' => new TypeDefinition('Sales Day', 'Sales Day', 'SALES_DAY', true, true, true),
        'Delegation' => new TypeDefinition('Delegation', 'Delegation', 'DELEGATION', true, true, true),
        'RTD' => new TypeDefinition('RTD', 'RTD', 'RTD', true, true, true),
        'Speaker' => new TypeDefinition('Speaker', 'Speaker', 'SPEAKER', true, true, true),
        'Conference' => new TypeDefinition('Conference', 'Conference', 'CONFERENCE', true, true, true),
        'Annual Vacation' => new TypeDefinition('Annual Vacation', 'Annual Vacation', 'ANNUAL_LEAVE', true, true, true),
        // Legacy values retained for existing data and tests
        'Holiday' => new TypeDefinition('Holiday', 'Holiday (Legacy)', 'ANNUAL_LEAVE', true, true, true),
        'Sick Leave' => new TypeDefinition('Sick Leave', 'Sick Leave (Legacy)', 'SICK', true, true, true),
        'Event' => new TypeDefinition('Event', 'Event (Legacy)', 'EVENT', true, true, true),
        'Travelling' => new TypeDefinition('Travelling', 'Travelling (Legacy)', 'BUSINESS_TRIP', true, true, true)
    };

    public static final List<String> UI_TYPE_VALUES = new List<String>{
        'Annual Leave',
        'Business Trip',
        'Sick',
        'Training',
        'Casual/Emergency',
        'Health Day',
        'Maternity/Paternity',
        'Office Work',
        'Marriage',
        'Cycle Meeting',
        'Unpaid',
        'Sales Meeting',
        'Military',
        'Prospection',
        'Handover',
        'Sales Day',
        'Delegation',
        'RTD',
        'Speaker'
    };

    public static TypeDefinition getDefinition(String apiValue) {
        if (String.isBlank(apiValue)) {
            return null;
        }
        return BY_API.get(apiValue);
    }

    public static Boolean blocksVisits(String apiValue) {
        TypeDefinition defn = getDefinition(apiValue);
        return defn == null ? true : defn.blocksVisits;
    }

    public static String mendixCode(String apiValue) {
        TypeDefinition defn = getDefinition(apiValue);
        return defn == null ? apiValue : defn.mendixTypeCode;
    }

    public static Boolean isKnownType(String apiValue) {
        return BY_API.containsKey(apiValue);
    }
}