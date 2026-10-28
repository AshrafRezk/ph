/**
 * BRD 5.4.1(3) — Duplicate Visit Restriction During First Coverage Cycle for HCP.
 * The first coverage cycle for a rep+HCP is the 1-week window that starts on the day of
 * their earliest non-cancelled visit. Inside that window a rep may hold only one visit
 * (planned or unplanned) for the HCP; after it, the rule no longer applies. A second
 * visit in the window needs an approved First Cycle Exception
 * (First_Cycle_Exception_Approved__c). Cancelled visits never count.
 * Runs on insert and on update when a visit is moved (start, account or rep changed).
 */
public with sharing class VisitDuplicateService {
    @TestVisible
    private static Integer firstCycleDays = 7;

    private static final Set<String> HCP_RECORD_TYPES = new Set<String>{
        'SDO_PersonAccounts', 'Medical_Professional_HCP', 'PersonAccount', 'Business_Contact'
    };

    public static void enforceFirstCycleRule(List<Visit__c> newVisits) {
        enforceFirstCycleRule(newVisits, null);
    }

    public static void enforceFirstCycleRule(List<Visit__c> newVisits, Map<Id, Visit__c> oldMap) {
        // Candidates: have account + rep + start, and not exception-approved.
        List<Visit__c> candidates = new List<Visit__c>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> repIds = new Set<Id>();
        for (Visit__c v : newVisits) {
            if (v.Account__c == null || v.Assigned_To__c == null || v.Start_Date__c == null) {
                continue;
            }
            if (v.First_Cycle_Exception_Approved__c == true || v.Status__c == VisitStatusHelper.STATUS_CANCELLED) {
                continue;
            }
            Visit__c prior = oldMap == null || v.Id == null ? null : oldMap.get(v.Id);
            if (prior != null && !isMoved(prior, v)) {
                continue;
            }
            // Monthly data pack historical rows (Client_Visit_Key__c PACKV-...); first-cycle rules do not apply.
            if (v.Client_Visit_Key__c != null && v.Client_Visit_Key__c.startsWith('PACKV-')) {
                continue;
            }
            candidates.add(v);
            accountIds.add(v.Account__c);
            repIds.add(v.Assigned_To__c);
        }
        if (candidates.isEmpty()) {
            return;
        }

        // Which candidate accounts are HCPs?
        Set<Id> hcpAccounts = new Set<Id>();
        for (Account a : [
            SELECT Id, RecordType.DeveloperName FROM Account WHERE Id IN :accountIds
        ]) {
            if (a.RecordType != null && HCP_RECORD_TYPES.contains(a.RecordType.DeveloperName)) {
                hcpAccounts.add(a.Id);
            }
        }
        if (hcpAccounts.isEmpty()) {
            return;
        }

        // Existing visits for the same rep+HCP (exclude the records being saved).
        Set<Id> newIds = new Set<Id>();
        for (Visit__c v : newVisits) {
            if (v.Id != null) {
                newIds.add(v.Id);
            }
        }
        Map<String, List<DateTime>> existingByKey = new Map<String, List<DateTime>>();
        for (Visit__c e : [
            SELECT Id, Account__c, Assigned_To__c, Start_Date__c
            FROM Visit__c
            WHERE Account__c IN :hcpAccounts
              AND Assigned_To__c IN :repIds
              AND Start_Date__c != null
              AND Status__c != 'Cancelled'
              AND Id NOT IN :newIds
        ]) {
            String key = e.Assigned_To__c + '|' + e.Account__c;
            if (!existingByKey.containsKey(key)) {
                existingByKey.put(key, new List<DateTime>());
            }
            existingByKey.get(key).add(e.Start_Date__c);
        }

        for (Visit__c v : candidates) {
            if (!hcpAccounts.contains(v.Account__c)) {
                continue;
            }
            String key = v.Assigned_To__c + '|' + v.Account__c;
            List<DateTime> priorStarts = existingByKey.get(key);
            if (priorStarts == null) {
                continue;
            }
            Date candidateDay = v.Start_Date__c.date();
            Date cycleStart = candidateDay;
            for (DateTime prior : priorStarts) {
                if (prior.date() < cycleStart) {
                    cycleStart = prior.date();
                }
            }
            Date cycleEnd = cycleStart.addDays(firstCycleDays);
            if (candidateDay >= cycleEnd) {
                continue;
            }
            for (DateTime prior : priorStarts) {
                if (prior.date() >= cycleStart && prior.date() < cycleEnd) {
                    v.addError(
                        'This HCP already has a visit within the first coverage cycle (' +
                        firstCycleDays + ' days). An approved First Cycle Exception is required to add another visit.'
                    );
                    break;
                }
            }
        }
    }

    private static Boolean isMoved(Visit__c prior, Visit__c current) {
        return prior.Start_Date__c != current.Start_Date__c
            || prior.Account__c != current.Account__c
            || prior.Assigned_To__c != current.Assigned_To__c
            || (prior.Status__c == VisitStatusHelper.STATUS_CANCELLED
                && current.Status__c != VisitStatusHelper.STATUS_CANCELLED);
    }
}
