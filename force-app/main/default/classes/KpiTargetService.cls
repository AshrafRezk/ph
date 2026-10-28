/**
 * Editable SFE KPI targets with configurable count sources.
 * Scorecards read targets in realtime; Admin Console owns the catalog.
 */
public with sharing class KpiTargetService {
    public class TargetRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String roleKey;
        @AuraEnabled public String metricKey;
        @AuraEnabled public String metricLabel;
        @AuraEnabled public Decimal targetPercent;
        @AuraEnabled public String name;
        @AuraEnabled public String period;
        @AuraEnabled public String scopeLevel;
        @AuraEnabled public String scopeKey;
        @AuraEnabled public String countSource;
        @AuraEnabled public String countSourceLabel;
        @AuraEnabled public String countNumerator;
        @AuraEnabled public String countDenominator;
        @AuraEnabled public Boolean isCustom;
    }

    public class CountSourceOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String numerator;
        @AuraEnabled public String denominator;
        public CountSourceOption(String value, String label, String numerator, String denominator) {
            this.value = value;
            this.label = label;
            this.numerator = numerator;
            this.denominator = denominator;
        }
    }

    public class Catalog {
        @AuraEnabled public List<TargetRow> rows;
        @AuraEnabled public List<CountSourceOption> countSources;
        @AuraEnabled public List<String> roleKeys;
        @AuraEnabled public List<MetricPreset> metricPresets;
        /** True when no KPI_Target__c rows exist yet. Reads never seed; an admin runs seedFrameworkDefaults. */
        @AuraEnabled public Boolean needsSeed;
    }

    public class MetricPreset {
        @AuraEnabled public String metricKey;
        @AuraEnabled public String metricLabel;
        @AuraEnabled public String countSource;
        public MetricPreset(String metricKey, String metricLabel, String countSource) {
            this.metricKey = metricKey;
            this.metricLabel = metricLabel;
            this.countSource = countSource;
        }
    }

    private static final Map<String, Decimal> FRAMEWORK_DEFAULTS = new Map<String, Decimal>{
        'MSR|Sales_Achievement' => 100,
        'MSR|Coverage' => 90,
        'MSR|Right_Frequency' => 90,
        'MSR|Daily_Call_Rate' => 90,
        'MSR|Quiz' => 85,
        'DSM|Sales_Achievement' => 100,
        'DSM|Coverage' => 100,
        'DSM|Right_Frequency' => 80,
        'DSM|Reps_At_90' => 70,
        'DSM|Quiz' => 80,
        'DSM|KOL_Coverage' => 90,
        'DSM|Field_Working_Days' => 100,
        'DSM|Double_Visit_Coverage' => 90,
        'ASM|Sales_Achievement' => 100,
        'ASM|Coverage' => 80,
        'ASM|Right_Frequency' => 80,
        'ASM|Reps_At_90' => 70,
        'ASM|Quiz' => 80,
        'ASM|KOL_Coverage' => 90,
        'ASM|Field_Working_Days' => 100,
        'NSM|Sales_Achievement' => 100,
        'NSM|Coverage' => 80,
        'NSM|Right_Frequency' => 80,
        'NSM|Reps_At_90' => 70,
        'NSM|Quiz' => 90,
        'NSM|KOL_Coverage' => 90,
        'NSM|Field_Working_Days' => 100,
        'BM|Sales_Achievement' => 100,
        'BM|Quiz' => 100,
        'BM|KOL_Coverage' => 90,
        'BM|Field_Working_Days' => 90,
        'BM|Regions_Visited' => 80,
        'DSM|Team_Double_Visit_Coverage' => 90,
        'CHC_MSR|Sales_Achievement' => 100,
        'CHC_MSR|Coverage' => 90,
        'CHC_MSR|Daily_Call_Rate' => 90,
        'CHC_MSR|Active_Pharmacies' => 75,
        'CHC_MSR|Pharmacy_Frequency' => 90,
        'CHC_MSR|Quiz' => 85,
        'CHC_SS|Sales_Achievement' => 100,
        'CHC_SS|Active_Pharmacies' => 75,
        'CHC_SS|Pharmacy_Frequency' => 75,
        'CHC_SS|Field_Working_Days' => 100,
        'CHC_SS|Quiz' => 80
    };

    private static final Map<String, String> METRIC_LABELS = new Map<String, String>{
        'Sales_Achievement' => 'Sales Achievement',
        'Coverage' => 'Coverage',
        'Right_Frequency' => 'Right Frequency',
        'Daily_Call_Rate' => 'Daily Call Rate',
        'Quiz' => 'Quizzes',
        'Reps_At_90' => 'Percent employees at 90% sales',
        'KOL_Coverage' => 'KOL Coverage',
        'Field_Working_Days' => 'Field Working Days',
        'Double_Visit_Coverage' => 'Double Visit Coverage',
        'Team_Double_Visit_Coverage' => 'Team Double-Visit Coverage (reps coached)',
        'Regions_Visited' => 'Regions Visited',
        'Active_Pharmacies' => 'Active Pharmacies',
        'Pharmacy_Frequency' => 'Pharmacy Sales Frequency'
    };

    private static final Map<String, String> METRIC_TO_SOURCE = new Map<String, String>{
        'Sales_Achievement' => 'Sales_Achievement',
        'Coverage' => 'Visit_Coverage',
        'Right_Frequency' => 'Visit_Frequency',
        'Daily_Call_Rate' => 'Daily_Call_Rate',
        'Quiz' => 'Quiz_Score',
        'Reps_At_90' => 'Team_Reps_At_90',
        'KOL_Coverage' => 'KOL_Coverage',
        'Field_Working_Days' => 'Field_Working_Days',
        'Double_Visit_Coverage' => 'Double_Visit',
        'Team_Double_Visit_Coverage' => 'Team_Double_Visit',
        'Regions_Visited' => 'Regions_Visited',
        'Active_Pharmacies' => 'Active_Pharmacies',
        'Pharmacy_Frequency' => 'Pharmacy_Frequency'
    };

    private static Map<String, Decimal> targetCache;

    @AuraEnabled
    public static Catalog getCatalog() {
        Catalog catalog = new Catalog();
        catalog.rows = listTargets();
        catalog.countSources = listCountSources();
        catalog.metricPresets = listMetricPresets();
        catalog.needsSeed = catalog.rows.isEmpty();
        Set<String> roles = new Set<String>{ 'MSR', 'DSM', 'ASM', 'NSM', 'BM', 'CHC_MSR', 'CHC_SS' };
        for (TargetRow row : catalog.rows) {
            if (String.isNotBlank(row.roleKey)) {
                roles.add(row.roleKey);
            }
        }
        List<String> roleKeys = new List<String>(roles);
        roleKeys.sort();
        catalog.roleKeys = roleKeys;
        return catalog;
    }

    @AuraEnabled(cacheable=true)
    public static List<CountSourceOption> listCountSources() {
        return new List<CountSourceOption>{
            new CountSourceOption(
                'Visit_Coverage',
                'Visit coverage',
                'Accounts with ≥1 Valid/Completed visit in period',
                'Active target-list accounts for the rep'
            ),
            new CountSourceOption(
                'Visit_Frequency',
                'Visit frequency',
                'Actual Valid visits on each target account',
                'Planned visits/month on Account Territory Fields'
            ),
            new CountSourceOption(
                'Daily_Call_Rate',
                'Daily call rate',
                'Completed visits in the period',
                'Available field working days (after holidays / TOT / leave)'
            ),
            new CountSourceOption(
                'Sales_Achievement',
                'Sales achievement',
                'Sell-out / withdrawals credited to the rep or team',
                'Sales target for the same period'
            ),
            new CountSourceOption(
                'Field_Working_Days',
                'Field working days',
                'Days with field activity (visits / meetings / coaching)',
                'Planned field days for the role (after holidays / TOT)'
            ),
            new CountSourceOption(
                'Double_Visit',
                'Double visit coverage (accounts)',
                'Accounts with required dual visits completed',
                'Accounts that require a double visit'
            ),
            new CountSourceOption(
                'Team_Double_Visit',
                'Team double-visit coverage (DM coaching)',
                'Distinct team reps the DM double-visited / coached with in the period',
                'Total active team reps under the DM'
            ),
            new CountSourceOption(
                'Regions_Visited',
                'Regions / districts visited (Brand Manager)',
                'Distinct districts (regions) the BM visited in the period',
                'Total active districts under the BM line'
            ),
            new CountSourceOption(
                'KOL_Coverage',
                'KOL coverage',
                'KOL accounts visited',
                'KOL accounts on the target list'
            ),
            new CountSourceOption(
                'Quiz_Score',
                'Quiz / learning',
                'Quiz scores completed in the period',
                'Assigned quiz materials'
            ),
            new CountSourceOption(
                'Active_Pharmacies',
                'Active pharmacies',
                'Pharmacies with sell-out in the period',
                'Assigned pharmacies in territory'
            ),
            new CountSourceOption(
                'Pharmacy_Frequency',
                'Pharmacy sales frequency',
                'Pharmacy touches / sell-out events',
                'Target pharmacy frequency'
            ),
            new CountSourceOption(
                'Team_Reps_At_90',
                'Team % at 90% sales',
                'Reps at or above 90% sales achievement',
                'Reps in the manager scope'
            ),
            new CountSourceOption(
                'Custom_Report',
                'Custom report / formula',
                'Define numerator below',
                'Define denominator below'
            ),
            new CountSourceOption(
                'Manual',
                'Manual (not auto-counted)',
                'Entered or imported manually',
                'n/a'
            )
        };
    }

    @AuraEnabled(cacheable=true)
    public static List<TargetRow> listTargets() {
        // Read only. Seeding and metadata backfill happen in admin actions, never here:
        // this method is cacheable, and DML in a cacheable read fails the screen.
        List<TargetRow> rows = new List<TargetRow>();
        Boolean hasPeriod = hasField('Period__c');
        Boolean hasScope = hasField('Scope_Level__c');
        Boolean hasLabel = hasField('Metric_Label__c');
        Boolean hasSource = hasField('Count_Source__c');
        Boolean hasNum = hasField('Count_Numerator__c');
        Boolean hasDen = hasField('Count_Denominator__c');
        String selectFields =
            'Id, Name, Role__c, Metric__c, Target_Percent__c'
            + (hasPeriod ? ', Period__c' : '')
            + (hasScope ? ', Scope_Level__c, Scope_Key__c' : '')
            + (hasLabel ? ', Metric_Label__c' : '')
            + (hasSource ? ', Count_Source__c' : '')
            + (hasNum ? ', Count_Numerator__c' : '')
            + (hasDen ? ', Count_Denominator__c' : '');
        Map<String, CountSourceOption> sourceByKey = sourceMap();
        for (KPI_Target__c rec : Database.query(
            'SELECT '
                + selectFields
                + ' FROM KPI_Target__c WITH SYSTEM_MODE ORDER BY Role__c, Metric__c'
        )) {
            rows.add(toRow(rec, hasPeriod, hasScope, hasLabel, hasSource, hasNum, hasDen, sourceByKey));
        }
        return rows;
    }

    @AuraEnabled
    public static List<TargetRow> addTarget(
        String roleKey,
        String metricKey,
        String metricLabel,
        Decimal targetPercent,
        String period,
        String scopeLevel,
        String scopeKey,
        String countSource,
        String countNumerator,
        String countDenominator
    ) {
        if (String.isBlank(roleKey) || String.isBlank(metricKey) || targetPercent == null) {
            throw new AuraHandledException('Role, metric key, and target percent are required.');
        }
        ensureDefaults();
        String cleanMetric = sanitizeMetricKey(metricKey);
        String label = String.isBlank(metricLabel)
            ? (METRIC_LABELS.containsKey(cleanMetric) ? METRIC_LABELS.get(cleanMetric) : cleanMetric.replace('_', ' '))
            : metricLabel.trim();
        CountSourceOption source = resolveSource(countSource, cleanMetric);
        KPI_Target__c row = new KPI_Target__c(
            Name = (roleKey.trim() + ' · ' + label).left(80),
            Role__c = roleKey.trim(),
            Metric__c = cleanMetric,
            Target_Percent__c = targetPercent
        );
        applyOptionalFields(row, label, period, scopeLevel, scopeKey, source, countNumerator, countDenominator);
        insert as system row;
        clearCache();
        return listTargets();
    }

    @AuraEnabled
    public static List<TargetRow> saveTargets(String payloadJson) {
        ensureDefaults();
        backfillCountMetadata();
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(payloadJson);
        List<KPI_Target__c> toUpdate = new List<KPI_Target__c>();
        Boolean hasLabel = hasField('Metric_Label__c');
        Boolean hasSource = hasField('Count_Source__c');
        Boolean hasNum = hasField('Count_Numerator__c');
        Boolean hasDen = hasField('Count_Denominator__c');
        Boolean hasPeriod = hasField('Period__c');
        Boolean hasScope = hasField('Scope_Level__c');
        for (Object item : raw) {
            Map<String, Object> m = (Map<String, Object>) item;
            Id recordId = (Id) String.valueOf(m.get('id'));
            Decimal pct = m.get('targetPercent') == null
                ? null
                : Decimal.valueOf(String.valueOf(m.get('targetPercent')));
            if (recordId == null) {
                continue;
            }
            if (pct == null) {
                // A cleared % used to skip the whole row (and its source edits) while still reporting success.
                throw new AuraHandledException('Every KPI target needs a % between 0 and 100. Fill in or restore the empty value.');
            }
            if (pct < 0 || pct > 100) {
                throw new AuraHandledException('KPI targets must be between 0 and 100%.');
            }
            KPI_Target__c row = new KPI_Target__c(Id = recordId, Target_Percent__c = pct);
            if (hasLabel && m.containsKey('metricLabel') && m.get('metricLabel') != null) {
                row.put('Metric_Label__c', String.valueOf(m.get('metricLabel')).left(80));
            }
            if (hasPeriod && m.containsKey('period') && m.get('period') != null) {
                row.put('Period__c', String.valueOf(m.get('period')));
            }
            if (hasScope) {
                if (m.containsKey('scopeLevel') && m.get('scopeLevel') != null) {
                    row.put('Scope_Level__c', String.valueOf(m.get('scopeLevel')));
                }
                if (m.containsKey('scopeKey')) {
                    row.put('Scope_Key__c', m.get('scopeKey') == null ? null : String.valueOf(m.get('scopeKey')));
                }
            }
            if (hasSource && m.containsKey('countSource') && m.get('countSource') != null) {
                CountSourceOption source = resolveSource(String.valueOf(m.get('countSource')), null);
                row.put('Count_Source__c', source.value);
                if (hasNum) {
                    String num = m.get('countNumerator') == null ? source.numerator : String.valueOf(m.get('countNumerator'));
                    row.put('Count_Numerator__c', num == null ? null : num.left(255));
                }
                if (hasDen) {
                    String den = m.get('countDenominator') == null ? source.denominator : String.valueOf(m.get('countDenominator'));
                    row.put('Count_Denominator__c', den == null ? null : den.left(255));
                }
            } else {
                if (hasNum && m.containsKey('countNumerator') && m.get('countNumerator') != null) {
                    row.put('Count_Numerator__c', String.valueOf(m.get('countNumerator')).left(255));
                }
                if (hasDen && m.containsKey('countDenominator') && m.get('countDenominator') != null) {
                    row.put('Count_Denominator__c', String.valueOf(m.get('countDenominator')).left(255));
                }
            }
            toUpdate.add(row);
        }
        if (!toUpdate.isEmpty()) {
            update as system toUpdate;
        }
        clearCache();
        return listTargets();
    }

    @AuraEnabled
    public static List<TargetRow> deleteTarget(Id targetId) {
        if (targetId == null) {
            throw new AuraHandledException('Target id is required.');
        }
        delete as system [SELECT Id FROM KPI_Target__c WHERE Id = :targetId];
        clearCache();
        return listTargets();
    }

    @AuraEnabled
    public static List<TargetRow> resetToFrameworkDefaults() {
        delete as system [SELECT Id FROM KPI_Target__c];
        clearCache();
        ensureDefaults();
        return listTargets();
    }

    /** Admin action: seed the framework rows when the table is empty, then fill count metadata. */
    @AuraEnabled
    public static List<TargetRow> seedFrameworkDefaults() {
        ensureDefaults();
        backfillCountMetadata();
        clearCache();
        return listTargets();
    }

    /** Pure read. Falls back to the framework default when no row exists. Never performs DML. */
    public static Decimal targetFor(String roleKey, String metricKey) {
        String role = String.isBlank(roleKey) ? 'DSM' : roleKey;
        String metric = String.isBlank(metricKey) ? 'Coverage' : metricKey;
        String key = role + '|' + metric;
        Map<String, Decimal> cache = targetMap();
        if (cache.containsKey(key)) {
            return cache.get(key);
        }
        return FRAMEWORK_DEFAULTS.containsKey(key) ? FRAMEWORK_DEFAULTS.get(key) : 80;
    }

    @TestVisible
    static void clearCache() {
        targetCache = null;
    }

    private static List<MetricPreset> listMetricPresets() {
        List<MetricPreset> presets = new List<MetricPreset>();
        for (String key : METRIC_LABELS.keySet()) {
            presets.add(new MetricPreset(key, METRIC_LABELS.get(key), METRIC_TO_SOURCE.get(key)));
        }
        return presets;
    }

    private static Map<String, Decimal> targetMap() {
        if (targetCache != null) {
            return targetCache;
        }
        targetCache = new Map<String, Decimal>();
        for (KPI_Target__c rec : [
            SELECT Role__c, Metric__c, Target_Percent__c
            FROM KPI_Target__c
        ]) {
            targetCache.put(rec.Role__c + '|' + rec.Metric__c, rec.Target_Percent__c);
        }
        return targetCache;
    }

    private static void ensureDefaults() {
        Integer count = [SELECT COUNT() FROM KPI_Target__c];
        if (count > 0) {
            return;
        }
        List<KPI_Target__c> seed = new List<KPI_Target__c>();
        Map<String, CountSourceOption> sources = sourceMap();
        for (String key : FRAMEWORK_DEFAULTS.keySet()) {
            List<String> parts = key.split('\\|');
            String metric = parts[1];
            String label = METRIC_LABELS.containsKey(metric) ? METRIC_LABELS.get(metric) : metric;
            String sourceKey = METRIC_TO_SOURCE.containsKey(metric) ? METRIC_TO_SOURCE.get(metric) : 'Manual';
            CountSourceOption source = sources.containsKey(sourceKey) ? sources.get(sourceKey) : sources.get('Manual');
            KPI_Target__c row = new KPI_Target__c(
                Name = parts[0] + ' · ' + label,
                Role__c = parts[0],
                Metric__c = metric,
                Target_Percent__c = FRAMEWORK_DEFAULTS.get(key)
            );
            applyOptionalFields(row, label, 'Monthly', 'Org', null, source, null, null);
            seed.add(row);
        }
        insert as system seed;
        clearCache();
    }

    private static void backfillCountMetadata() {
        if (!hasField('Count_Source__c')) {
            return;
        }
        Boolean hasLabel = hasField('Metric_Label__c');
        Boolean hasNum = hasField('Count_Numerator__c');
        Boolean hasDen = hasField('Count_Denominator__c');
        String selectFields = 'Id, Metric__c, Count_Source__c'
            + (hasLabel ? ', Metric_Label__c' : '')
            + (hasNum ? ', Count_Numerator__c' : '')
            + (hasDen ? ', Count_Denominator__c' : '');
        List<KPI_Target__c> dirty = new List<KPI_Target__c>();
        Map<String, CountSourceOption> sources = sourceMap();
        for (KPI_Target__c rec : Database.query(
            'SELECT ' + selectFields + ' FROM KPI_Target__c WHERE Count_Source__c = NULL WITH SYSTEM_MODE LIMIT 200'
        )) {
            String sourceKey = METRIC_TO_SOURCE.containsKey(rec.Metric__c)
                ? METRIC_TO_SOURCE.get(rec.Metric__c)
                : 'Manual';
            CountSourceOption source = sources.containsKey(sourceKey) ? sources.get(sourceKey) : sources.get('Manual');
            rec.put('Count_Source__c', source.value);
            if (hasLabel && String.isBlank((String) rec.get('Metric_Label__c'))) {
                rec.put(
                    'Metric_Label__c',
                    METRIC_LABELS.containsKey(rec.Metric__c)
                        ? METRIC_LABELS.get(rec.Metric__c)
                        : rec.Metric__c
                );
            }
            if (hasNum && String.isBlank((String) rec.get('Count_Numerator__c'))) {
                rec.put('Count_Numerator__c', source.numerator);
            }
            if (hasDen && String.isBlank((String) rec.get('Count_Denominator__c'))) {
                rec.put('Count_Denominator__c', source.denominator);
            }
            dirty.add(rec);
        }
        if (!dirty.isEmpty()) {
            update as system dirty;
        }
    }

    private static void applyOptionalFields(
        KPI_Target__c row,
        String label,
        String period,
        String scopeLevel,
        String scopeKey,
        CountSourceOption source,
        String countNumerator,
        String countDenominator
    ) {
        if (hasField('Metric_Label__c')) {
            row.put('Metric_Label__c', label == null ? null : label.left(80));
        }
        if (hasField('Period__c')) {
            row.put('Period__c', String.isBlank(period) ? 'Monthly' : period);
        }
        if (hasField('Scope_Level__c')) {
            row.put('Scope_Level__c', String.isBlank(scopeLevel) ? 'Org' : scopeLevel);
            row.put('Scope_Key__c', scopeKey);
        }
        if (hasField('Count_Source__c') && source != null) {
            row.put('Count_Source__c', source.value);
            if (hasField('Count_Numerator__c')) {
                String num = String.isBlank(countNumerator) ? source.numerator : countNumerator;
                row.put('Count_Numerator__c', num == null ? null : num.left(255));
            }
            if (hasField('Count_Denominator__c')) {
                String den = String.isBlank(countDenominator) ? source.denominator : countDenominator;
                row.put('Count_Denominator__c', den == null ? null : den.left(255));
            }
        }
    }

    private static TargetRow toRow(
        KPI_Target__c rec,
        Boolean hasPeriod,
        Boolean hasScope,
        Boolean hasLabel,
        Boolean hasSource,
        Boolean hasNum,
        Boolean hasDen,
        Map<String, CountSourceOption> sourceByKey
    ) {
        TargetRow row = new TargetRow();
        row.id = rec.Id;
        row.roleKey = rec.Role__c;
        row.metricKey = rec.Metric__c;
        String storedLabel = hasLabel ? (String) rec.get('Metric_Label__c') : null;
        row.metricLabel = String.isNotBlank(storedLabel)
            ? storedLabel
            : (METRIC_LABELS.containsKey(rec.Metric__c) ? METRIC_LABELS.get(rec.Metric__c) : rec.Metric__c);
        row.targetPercent = rec.Target_Percent__c;
        row.name = rec.Name;
        row.period = hasPeriod ? (String) rec.get('Period__c') : 'Monthly';
        row.scopeLevel = hasScope ? (String) rec.get('Scope_Level__c') : 'Org';
        row.scopeKey = hasScope ? (String) rec.get('Scope_Key__c') : null;
        row.countSource = hasSource ? (String) rec.get('Count_Source__c') : null;
        if (String.isBlank(row.countSource)) {
            row.countSource = METRIC_TO_SOURCE.containsKey(rec.Metric__c)
                ? METRIC_TO_SOURCE.get(rec.Metric__c)
                : 'Manual';
        }
        CountSourceOption source = sourceByKey.containsKey(row.countSource)
            ? sourceByKey.get(row.countSource)
            : null;
        row.countSourceLabel = source != null ? source.label : row.countSource;
        row.countNumerator = hasNum
            ? (String) rec.get('Count_Numerator__c')
            : (source != null ? source.numerator : null);
        row.countDenominator = hasDen
            ? (String) rec.get('Count_Denominator__c')
            : (source != null ? source.denominator : null);
        row.isCustom = !METRIC_LABELS.containsKey(rec.Metric__c);
        return row;
    }

    private static CountSourceOption resolveSource(String countSource, String metricKey) {
        Map<String, CountSourceOption> sources = sourceMap();
        if (String.isNotBlank(countSource) && sources.containsKey(countSource)) {
            return sources.get(countSource);
        }
        if (String.isNotBlank(metricKey) && METRIC_TO_SOURCE.containsKey(metricKey)) {
            String mapped = METRIC_TO_SOURCE.get(metricKey);
            if (sources.containsKey(mapped)) {
                return sources.get(mapped);
            }
        }
        return sources.get('Manual');
    }

    private static Map<String, CountSourceOption> sourceMap() {
        Map<String, CountSourceOption> out = new Map<String, CountSourceOption>();
        for (CountSourceOption option : listCountSources()) {
            out.put(option.value, option);
        }
        return out;
    }

    private static String sanitizeMetricKey(String raw) {
        String cleaned = raw.trim().replaceAll('[^A-Za-z0-9_]+', '_');
        if (String.isBlank(cleaned)) {
            throw new AuraHandledException('Metric key must contain letters or numbers.');
        }
        return cleaned.left(40);
    }

    private static Boolean hasField(String apiName) {
        return Schema.SObjectType.KPI_Target__c.fields.getMap().containsKey(apiName);
    }
}
