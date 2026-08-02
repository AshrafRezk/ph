/**
 * Misr Radiology Center — commission calculations from time card sold/target fields.
 */
public with sharing class MisrRadiologyCommissionService {

    public class ServiceFieldMapping {
        public String serviceKey;
        public String soldField;
        public String targetField;
    }

    public class ServiceCommissionRow {
        @AuraEnabled public String serviceKey;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal sold;
        @AuraEnabled public Decimal target;
        @AuraEnabled public Decimal achievementPercent;
        @AuraEnabled public Decimal projectedSold;
        @AuraEnabled public Decimal projectedAchievementPercent;
        @AuraEnabled public Decimal commissionRate;
        @AuraEnabled public Decimal commission;
        @AuraEnabled public Decimal projectedCommission;
        @AuraEnabled public String paceStatus;
        @AuraEnabled public Integer sortOrder;
    }

    public class CommissionTotals {
        @AuraEnabled public Decimal totalSold;
        @AuraEnabled public Decimal totalTarget;
        @AuraEnabled public Decimal totalAchievementPercent;
        @AuraEnabled public Decimal currentCommission;
        @AuraEnabled public Decimal projectedSold;
        @AuraEnabled public Decimal projectedAchievementPercent;
        @AuraEnabled public Decimal projectedCommission;
    }

    public class CommissionDetailResult {
        @AuraEnabled public Id timeCardId;
        @AuraEnabled public Integer year;
        @AuraEnabled public Integer month;
        @AuraEnabled public Boolean hasTimeCard;
        @AuraEnabled public Decimal paceRatio;
        @AuraEnabled public Integer elapsedWorkingDays;
        @AuraEnabled public Integer totalWorkingDays;
        @AuraEnabled public List<ServiceCommissionRow> services;
        @AuraEnabled public CommissionTotals totals;
        @AuraEnabled public String payrollMonthName;
    }

    public class MonthOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class FilterOptionsResult {
        @AuraEnabled public List<MonthOption> monthOptions;
        @AuraEnabled public String defaultMonthValue;
    }

    private static final Integer MONTH_LOOKBACK = 12;

    private static final Map<String, ServiceFieldMapping> FIELD_BY_KEY = buildFieldMap();

    private static Map<String, ServiceFieldMapping> buildFieldMap() {
        Map<String, ServiceFieldMapping> result = new Map<String, ServiceFieldMapping>();
        addMapping(result, 'mri', 'MR_MRI_Sold__c', 'MR_MRI_Target__c');
        addMapping(result, 'totum_mri', 'MR_Totum_MRI_Sold__c', 'MR_Totum_MRI_Target__c');
        addMapping(result, 'pet_mri', 'MR_PET_MRI_Sold__c', 'MR_PET_MRI_Target__c');
        addMapping(result, 'ct_scan', 'MR_CT_Scan_Sold__c', 'MR_CT_Scan_Target__c');
        addMapping(result, 'pet_ct', 'MR_PET_CT_Sold__c', 'MR_PET_CT_Target__c');
        addMapping(result, 'ultrasound', 'MR_Ultrasound_Sold__c', 'MR_Ultrasound_Target__c');
        addMapping(result, 'digital_xray', 'MR_Digital_XRay_Sold__c', 'MR_Digital_XRay_Target__c');
        addMapping(result, 'fluoroscopy', 'MR_Fluoroscopy_Sold__c', 'MR_Fluoroscopy_Target__c');
        addMapping(result, 'breast_imaging', 'MR_Breast_Imaging_Sold__c', 'MR_Breast_Imaging_Target__c');
        addMapping(result, 'dexa', 'MR_DEXA_Sold__c', 'MR_DEXA_Target__c');
        addMapping(result, 'isotope', 'MR_Isotope_Sold__c', 'MR_Isotope_Target__c');
        addMapping(result, 'womens_health', 'MR_Womens_Health_Sold__c', 'MR_Womens_Health_Target__c');
        addMapping(result, 'dental_imaging', 'MR_Dental_Imaging_Sold__c', 'MR_Dental_Imaging_Target__c');
        addMapping(result, 'other_services', 'MR_Other_Services_Sold__c', 'MR_Other_Services_Target__c');
        return result;
    }

    private static void addMapping(
        Map<String, ServiceFieldMapping> result,
        String key,
        String soldField,
        String targetField
    ) {
        ServiceFieldMapping mapping = new ServiceFieldMapping();
        mapping.serviceKey = key;
        mapping.soldField = soldField;
        mapping.targetField = targetField;
        result.put(key, mapping);
    }

    public static FilterOptionsResult getFilterOptions() {
        FilterOptionsResult result = new FilterOptionsResult();
        result.monthOptions = new List<MonthOption>();
        Date cursor = Date.today().toStartOfMonth();
        for (Integer i = 0; i < MONTH_LOOKBACK; i++) {
            MonthOption option = new MonthOption();
            option.value = formatMonthValue(cursor);
            option.label = formatMonthLabel(cursor);
            result.monthOptions.add(option);
            cursor = cursor.addMonths(-1);
        }
        result.defaultMonthValue = result.monthOptions.isEmpty()
            ? null
            : result.monthOptions[0].value;
        return result;
    }

    public static CommissionDetailResult getCommissionDetail(Id employeeId, Integer year, Integer month) {
        CommissionDetailResult result = new CommissionDetailResult();
        result.services = new List<ServiceCommissionRow>();
        result.totals = new CommissionTotals();

        if (employeeId == null || year == null || month == null) {
            result.hasTimeCard = false;
            return result;
        }

        Date monthStart = Date.newInstance(year, month, 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        result.year = year;
        result.month = month;
        result.payrollMonthName = payrollMonthName(year, month);

        Employee_Time_Card__c card = queryTimeCard(employeeId, monthStart);
        if (card == null) {
            result.hasTimeCard = false;
            return result;
        }

        result.hasTimeCard = true;
        result.timeCardId = card.Id;

        Decimal paceRatio = computePaceRatio(card, monthStart, monthEnd, Date.today());
        result.paceRatio = paceRatio;
        WorkingDayCounts counts = countWorkingDays(card, monthStart, monthEnd, Date.today());
        result.elapsedWorkingDays = counts.elapsed;
        result.totalWorkingDays = counts.total;

        List<Misr_Radiology_Service__mdt> serviceDefs = [
            SELECT Service_Key__c, Label__c, Commission_Rate__c, Sort_Order__c
            FROM Misr_Radiology_Service__mdt
            ORDER BY Sort_Order__c ASC, Label__c ASC
        ];

        Decimal totalSold = 0;
        Decimal totalTarget = 0;
        Decimal totalCommission = 0;
        Decimal totalProjectedSold = 0;
        Decimal totalProjectedCommission = 0;

        for (Misr_Radiology_Service__mdt def : serviceDefs) {
            ServiceFieldMapping mapping = FIELD_BY_KEY.get(def.Service_Key__c);
            if (mapping == null) {
                continue;
            }

            Decimal sold = readDecimal(card, mapping.soldField);
            Decimal target = readDecimal(card, mapping.targetField);
            Decimal rate = nvl(def.Commission_Rate__c);
            Decimal achievementFactor = achievementFactor(sold, target);
            Decimal commission = sold * (rate / 100) * achievementFactor;

            Decimal projectedSold = paceRatio > 0 ? sold / paceRatio : sold;
            Decimal projectedAchievementFactor = achievementFactor(projectedSold, target);
            Decimal projectedCommission = projectedSold * (rate / 100) * projectedAchievementFactor;

            ServiceCommissionRow row = new ServiceCommissionRow();
            row.serviceKey = def.Service_Key__c;
            row.label = def.Label__c;
            row.sold = sold;
            row.target = target;
            row.achievementPercent = achievementPercent(sold, target);
            row.projectedSold = projectedSold;
            row.projectedAchievementPercent = achievementPercent(projectedSold, target);
            row.commissionRate = rate;
            row.commission = commission;
            row.projectedCommission = projectedCommission;
            row.paceStatus = paceStatusFromProjected(row.projectedAchievementPercent);
            row.sortOrder = def.Sort_Order__c != null ? def.Sort_Order__c.intValue() : 0;
            result.services.add(row);

            totalSold += sold;
            totalTarget += target;
            totalCommission += commission;
            totalProjectedSold += projectedSold;
            totalProjectedCommission += projectedCommission;
        }

        result.totals.totalSold = totalSold;
        result.totals.totalTarget = totalTarget;
        result.totals.totalAchievementPercent = achievementPercent(totalSold, totalTarget);
        result.totals.currentCommission = totalCommission;
        result.totals.projectedSold = totalProjectedSold;
        result.totals.projectedAchievementPercent = achievementPercent(totalProjectedSold, totalTarget);
        result.totals.projectedCommission = totalProjectedCommission;
        return result;
    }

    @TestVisible
    private static Decimal achievementFactor(Decimal sold, Decimal target) {
        Decimal safeSold = nvl(sold);
        Decimal safeTarget = nvl(target);
        if (safeTarget <= 0) {
            return 0;
        }
        Decimal ratio = safeSold / safeTarget;
        return ratio > 1 ? 1 : ratio;
    }

    @TestVisible
    private static Decimal achievementPercent(Decimal sold, Decimal target) {
        Decimal safeTarget = nvl(target);
        if (safeTarget <= 0) {
            return 0;
        }
        return (nvl(sold) / safeTarget) * 100;
    }

    private static String paceStatusFromProjected(Decimal projectedAchPercent) {
        Decimal pct = nvl(projectedAchPercent);
        if (pct >= 100) {
            return 'ahead';
        }
        if (pct >= 90) {
            return 'on_track';
        }
        if (pct >= 50) {
            return 'behind';
        }
        return 'critical';
    }

    private static Employee_Time_Card__c queryTimeCard(Id employeeId, Date monthStart) {
        List<String> fields = new List<String>{
            'Id',
            'Employee__c',
            'Time_Card_Month_Start_Date__c',
            'Time_Card_Month_End_Date__c'
        };
        for (ServiceFieldMapping mapping : FIELD_BY_KEY.values()) {
            fields.add(mapping.soldField);
            fields.add(mapping.targetField);
        }

        String soql =
            'SELECT ' +
            String.join(fields, ', ') +
            ' FROM Employee_Time_Card__c' +
            ' WHERE Employee__c = :employeeId' +
            ' AND Time_Card_Month_Start_Date__c = :monthStart' +
            ' WITH USER_MODE' +
            ' LIMIT 1';
        List<Employee_Time_Card__c> cards = Database.query(soql);
        return cards.isEmpty() ? null : cards[0];
    }

    private class WorkingDayCounts {
        public Integer elapsed;
        public Integer total;
    }

    private static WorkingDayCounts countWorkingDays(
        Employee_Time_Card__c card,
        Date monthStart,
        Date monthEnd,
        Date asOfDate
    ) {
        WorkingDayCounts counts = new WorkingDayCounts();
        counts.elapsed = 0;
        counts.total = 0;

        List<Employee_Time_Card_Day_Entry__c> dayEntries = [
            SELECT Date__c, Calendar_Working_Days__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c = :card.Id
                AND Date__c >= :monthStart
                AND Date__c <= :monthEnd
            WITH USER_MODE
        ];

        if (!dayEntries.isEmpty()) {
            for (Employee_Time_Card_Day_Entry__c entry : dayEntries) {
                Integer calDays = entry.Calendar_Working_Days__c != null
                    ? entry.Calendar_Working_Days__c.intValue()
                    : 0;
                counts.total += calDays;
                if (entry.Date__c != null && entry.Date__c <= asOfDate) {
                    counts.elapsed += calDays;
                }
            }
        } else if (monthStart != null && monthEnd != null) {
            Date cursor = monthStart;
            while (cursor <= monthEnd) {
                if (!isWeekend(cursor)) {
                    counts.total++;
                    if (cursor <= asOfDate) {
                        counts.elapsed++;
                    }
                }
                cursor = cursor.addDays(1);
            }
        }

        if (counts.elapsed < 1) {
            counts.elapsed = 1;
        }
        if (counts.total < counts.elapsed) {
            counts.total = counts.elapsed;
        }
        return counts;
    }

    private static Decimal computePaceRatio(
        Employee_Time_Card__c card,
        Date monthStart,
        Date monthEnd,
        Date asOfDate
    ) {
        WorkingDayCounts counts = countWorkingDays(card, monthStart, monthEnd, asOfDate);
        if (counts.total <= 0) {
            return 1;
        }
        if (asOfDate >= monthEnd) {
            return 1;
        }
        return Decimal.valueOf(counts.elapsed) / Decimal.valueOf(counts.total);
    }

    private static Boolean isWeekend(Date d) {
        Integer dayOfWeek = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(d), 7);
        return dayOfWeek == 5 || dayOfWeek == 6;
    }

    private static Decimal readDecimal(SObject record, String fieldApi) {
        Object raw = record.get(fieldApi);
        return raw == null ? 0 : Decimal.valueOf(String.valueOf(raw));
    }

    private static Decimal nvl(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String formatMonthValue(Date monthStart) {
        return String.valueOf(monthStart.year()) + '-' + String.valueOf(monthStart.month());
    }

    private static String formatMonthLabel(Date monthStart) {
        return DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0))
            .format('MMMM yyyy');
    }

    private static String payrollMonthName(Integer year, Integer month) {
        Integer payrollYear = year;
        Integer payrollMonth = month + 1;
        if (payrollMonth > 12) {
            payrollMonth = 1;
            payrollYear += 1;
        }
        Date payrollDate = Date.newInstance(payrollYear, payrollMonth, 1);
        return DateTime.newInstance(payrollDate, Time.newInstance(0, 0, 0, 0)).format('MMMM');
    }

    public static Date parseMonthValue(String monthValue) {
        if (String.isBlank(monthValue) || !monthValue.contains('-')) {
            return Date.today().toStartOfMonth();
        }
        List<String> parts = monthValue.split('-');
        if (parts.size() != 2) {
            return Date.today().toStartOfMonth();
        }
        return Date.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), 1);
    }
}
