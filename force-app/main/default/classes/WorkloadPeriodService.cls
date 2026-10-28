/**
 * Serves the admin-configurable Workload Period Mapping (Account record type /
 * kind -> AM or PM) used by the planner + KPIs to classify visit workload.
 */
public with sharing class WorkloadPeriodService {
    public class Mapping {
        @AuraEnabled public String accountKind;
        @AuraEnabled public String recordTypeDeveloperName;
        @AuraEnabled public String period;
    }

    @AuraEnabled(cacheable=true)
    public static List<Mapping> getWorkloadPeriodMappings() {
        List<Mapping> out = new List<Mapping>();
        for (Workload_Period_Mapping__mdt m : Workload_Period_Mapping__mdt.getAll().values()) {
            Mapping x = new Mapping();
            x.accountKind = m.Account_Kind__c;
            x.recordTypeDeveloperName = m.Record_Type_Developer_Name__c;
            x.period = m.Period__c;
            out.add(x);
        }
        return out;
    }
}