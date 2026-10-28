/**
 * Per-month planned visits for a doctor on a territory (Account_Month_Frequency__c).
 * Managers set them in Class Engine (Team target list, class cycle approval); time-card sync
 * uses them before the doctor's default visits per month (Call_Plan_Visits_Per_Month__c).
 * Always read and written in system mode: callers check who may change what.
 */
public without sharing class AccountMonthFrequencyService {
    public static final String SOURCE_MANAGER = 'Manager';
    public static final String SOURCE_CLASS_CYCLE = 'Class Cycle';

    /** "accountId:territoryId", the same key time-card sync uses for default frequencies. */
    public static String accountKey(Id accountId, String territoryId) {
        return String.valueOf(accountId) + ':' + territoryId;
    }

    public static String uniqueKey(Id accountId, String territoryId, Date monthStart) {
        return accountKey(accountId, territoryId) + ':' + String.valueOf(monthStart);
    }

    /** Rows for these territories and months, by unique key. */
    public static Map<String, Account_Month_Frequency__c> load(Set<String> territoryIds, Set<Date> months) {
        Map<String, Account_Month_Frequency__c> byKey = new Map<String, Account_Month_Frequency__c>();
        if (territoryIds == null || territoryIds.isEmpty() || months == null || months.isEmpty()) {
            return byKey;
        }
        for (Account_Month_Frequency__c row : [
            SELECT Id, Unique_Key__c, Account__c, Account_Territory_Fields__c, Territory2_Id__c, Month_Start__c,
                Frequency__c, Baseline_Frequency__c, Source__c, Rep__c, Set_By__c
            FROM Account_Month_Frequency__c
            WHERE Territory2_Id__c IN :territoryIds AND Month_Start__c IN :months
            WITH SYSTEM_MODE
        ]) {
            byKey.put(row.Unique_Key__c, row);
        }
        return byKey;
    }

    /** Month visits by "accountId:territoryId" for one month, for the given target-list rows. */
    public static Map<String, Decimal> frequenciesForMonth(List<Account_Territory_Fields__c> atfRecords, Date monthStart) {
        Map<String, Decimal> result = new Map<String, Decimal>();
        if (atfRecords == null || atfRecords.isEmpty() || monthStart == null) {
            return result;
        }
        Set<String> territoryIds = new Set<String>();
        for (Account_Territory_Fields__c atf : atfRecords) {
            if (String.isNotBlank(atf.Territory2_Id__c)) {
                territoryIds.add(atf.Territory2_Id__c);
            }
        }
        for (Account_Month_Frequency__c row : load(territoryIds, new Set<Date>{ monthStart.toStartOfMonth() }).values()) {
            if (row.Frequency__c != null && row.Account__c != null) {
                result.put(accountKey(row.Account__c, row.Territory2_Id__c), row.Frequency__c);
            }
        }
        return result;
    }

    public static Account_Month_Frequency__c newRow(
        Account_Territory_Fields__c atf,
        Id repId,
        Date monthStart,
        Decimal frequency,
        Decimal baseline,
        String source
    ) {
        Date month = monthStart.toStartOfMonth();
        return new Account_Month_Frequency__c(
            Name = ('Visits ' + String.valueOf(month).left(7) + ' ' + String.valueOf(atf.Account__c)).left(80),
            Unique_Key__c = uniqueKey(atf.Account__c, atf.Territory2_Id__c, month),
            Account__c = atf.Account__c,
            Account_Territory_Fields__c = atf.Id,
            Territory2_Id__c = atf.Territory2_Id__c,
            Month_Start__c = month,
            Frequency__c = frequency,
            Baseline_Frequency__c = baseline,
            Source__c = source,
            Rep__c = repId,
            Set_By__c = UserInfo.getUserId()
        );
    }

    public static void save(List<Account_Month_Frequency__c> rows) {
        if (rows != null && !rows.isEmpty()) {
            upsert as system rows Unique_Key__c;
        }
    }
}
