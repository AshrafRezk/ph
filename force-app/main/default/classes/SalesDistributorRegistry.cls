/**
 * Admin-managed distributor list. Seeds IBNSINA / Sofico / … plus Zeta Direct.
 */
public with sharing class SalesDistributorRegistry {
    public class DistributorOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String code;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean isDirect;
        @AuraEnabled public String adapterKey;
        @AuraEnabled public Boolean isActive;
    }

    @AuraEnabled(cacheable=true)
    public static List<DistributorOption> listDistributors(Boolean activeOnly) {
        ensureDefaults();
        String soql =
            'SELECT Id, Name, Code__c, Is_Direct__c, Adapter_Key__c, Is_Active__c'
            + ' FROM Sales_Distributor__c';
        if (activeOnly == true) {
            soql += ' WHERE Is_Active__c = TRUE';
        }
        soql += ' WITH SYSTEM_MODE ORDER BY Name ASC LIMIT 200';
        List<DistributorOption> rows = new List<DistributorOption>();
        for (Sales_Distributor__c rec : Database.query(soql)) {
            rows.add(toOption(rec));
        }
        return rows;
    }

    @AuraEnabled
    public static DistributorOption upsertDistributor(
        String code,
        String name,
        Boolean isDirect,
        String adapterKey,
        Boolean isActive
    ) {
        if (String.isBlank(code) || String.isBlank(name)) {
            throw new AuraHandledException('Code and name are required.');
        }
        List<Sales_Distributor__c> existing = [
            SELECT Id, Name, Code__c, Is_Direct__c, Adapter_Key__c, Is_Active__c
            FROM Sales_Distributor__c
            WHERE Code__c = :code.trim()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Sales_Distributor__c row = existing.isEmpty()
            ? new Sales_Distributor__c(Code__c = code.trim())
            : existing[0];
        row.Name = name.trim();
        row.Is_Direct__c = isDirect == true;
        row.Adapter_Key__c = String.isBlank(adapterKey) ? code.trim() : adapterKey.trim();
        row.Is_Active__c = isActive != false;
        upsert as system row;
        return toOption(row);
    }

    @AuraEnabled
    public static void ensureDefaults() {
        Map<String, String> seeds = new Map<String, String>{
            'IBNSINA' => 'IBNSINA',
            'Sofico' => 'Sofico',
            'Egydrug' => 'Egydrug',
            'POS' => 'POS',
            'Elezaby' => 'Elezaby',
            'EPDA' => 'EPDA',
            'Direct' => 'Direct'
        };
        Set<String> existing = new Set<String>();
        for (Sales_Distributor__c row : [
            SELECT Code__c
            FROM Sales_Distributor__c
            WHERE Code__c IN :seeds.keySet()
            WITH SYSTEM_MODE
        ]) {
            existing.add(row.Code__c);
        }
        List<Sales_Distributor__c> toInsert = new List<Sales_Distributor__c>();
        for (String code : seeds.keySet()) {
            if (existing.contains(code)) {
                continue;
            }
            toInsert.add(
                new Sales_Distributor__c(
                    Name = code == 'Direct' ? 'Zeta Direct' : code,
                    Code__c = code,
                    Adapter_Key__c = seeds.get(code),
                    Is_Direct__c = code == 'Direct',
                    Is_Active__c = true
                )
            );
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }
    }

    private static DistributorOption toOption(Sales_Distributor__c rec) {
        DistributorOption option = new DistributorOption();
        option.id = rec.Id;
        option.code = rec.Code__c;
        option.name = rec.Name;
        option.isDirect = rec.Is_Direct__c == true;
        option.adapterKey = rec.Adapter_Key__c;
        option.isActive = rec.Is_Active__c == true;
        return option;
    }
}
