/**
 * KOL coverage computation split into Single-Visit (SV) and Double-Visit (DV)
 * matrices, with automatic manager coverage: when a manager (DM/RM/NSM) is the
 * Double_Visit_With__c on a rep's KOL visit, that KOL counts toward the MANAGER's
 * coverage as a single visit (no separate manager visit entry).
 *
 * KOL accounts are defined per territory via Account_Territory_Fields__c.Is_KOL__c.
 */
public with sharing class VisitOwnershipService {
    public class KolCoverage {
        @AuraEnabled public Integer kolTargetCount = 0;
        @AuraEnabled public Integer svVisitedCount = 0;
        @AuraEnabled public Integer dvVisitedCount = 0;
        @AuraEnabled public Decimal svCoveragePercent = 0;
        @AuraEnabled public Decimal dvCoveragePercent = 0;
    }

    @AuraEnabled(cacheable=true)
    public static KolCoverage getKolCoverage(Id userId, Date startDate, Date endDate) {
        Id targetUser = userId == null ? UserInfo.getUserId() : userId;
        Date fromDate = startDate == null ? Date.today().toStartOfMonth() : startDate;
        Date toDate = endDate == null ? fromDate.addMonths(1).addDays(-1) : endDate;
        DateTime fromDt = DateTime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0));
        DateTime toDt = DateTime.newInstance(toDate.addDays(1), Time.newInstance(0, 0, 0, 0));

        Set<Id> kolAccounts = kolAccountsForUser(targetUser);
        if (kolAccounts.isEmpty()) {
            return new KolCoverage();
        }
        return coverageFor(kolAccounts, targetUser, fromDt, toDt);
    }

    @TestVisible
    private static KolCoverage coverageFor(
        Set<Id> kolAccounts,
        Id targetUser,
        DateTime fromDt,
        DateTime toDt
    ) {
        List<Visit__c> owned = [
            SELECT Account__c, Is_Double_Visit__c
            FROM Visit__c
            WHERE Assigned_To__c = :targetUser
              AND Account__c IN :kolAccounts
              AND Start_Date__c >= :fromDt
              AND Start_Date__c < :toDt
            WITH USER_MODE
        ];
        List<Visit__c> managerCredit = [
            SELECT Account__c, Is_Double_Visit__c
            FROM Visit__c
            WHERE Double_Visit_With__c = :targetUser
              AND Account__c IN :kolAccounts
              AND Start_Date__c >= :fromDt
              AND Start_Date__c < :toDt
            WITH USER_MODE
        ];
        return computeCoverage(kolAccounts, owned, managerCredit);
    }

    private static Set<Id> kolAccountsForUser(Id userId) {
        Set<String> territoryIds = new Set<String>();
        try {
            for (UserTerritory2Association a : [
                SELECT Territory2Id FROM UserTerritory2Association WHERE UserId = :userId
            ]) {
                territoryIds.add(String.valueOf(a.Territory2Id));
            }
        } catch (Exception e) {
            // Territory management may be disabled.
        }
        Set<Id> accounts = new Set<Id>();
        if (territoryIds.isEmpty()) {
            return accounts;
        }
        for (Account_Territory_Fields__c atf : [
            SELECT Account__c FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :territoryIds
              AND Is_KOL__c = TRUE
              AND Is_Active__c = TRUE
        ]) {
            if (atf.Account__c != null) {
                accounts.add(atf.Account__c);
            }
        }
        return accounts;
    }

    // Pure, testable: SV = owned single visits UNION manager-credit (auto single);
    // DV = owned double visits. Counted as distinct KOL accounts.
    @TestVisible
    private static KolCoverage computeCoverage(
        Set<Id> kolAccounts,
        List<Visit__c> ownedVisits,
        List<Visit__c> managerCreditVisits
    ) {
        Set<Id> svAccounts = new Set<Id>();
        Set<Id> dvAccounts = new Set<Id>();
        for (Visit__c v : ownedVisits) {
            if (v.Account__c == null || !kolAccounts.contains(v.Account__c)) {
                continue;
            }
            if (v.Is_Double_Visit__c == true) {
                dvAccounts.add(v.Account__c);
            } else {
                svAccounts.add(v.Account__c);
            }
        }
        for (Visit__c v : managerCreditVisits) {
            if (v.Account__c != null && kolAccounts.contains(v.Account__c)) {
                svAccounts.add(v.Account__c); // manager credit counts as single
            }
        }

        KolCoverage c = new KolCoverage();
        c.kolTargetCount = kolAccounts.size();
        c.svVisitedCount = svAccounts.size();
        c.dvVisitedCount = dvAccounts.size();
        if (c.kolTargetCount > 0) {
            c.svCoveragePercent = (Decimal.valueOf(c.svVisitedCount) / c.kolTargetCount * 100).setScale(1);
            c.dvCoveragePercent = (Decimal.valueOf(c.dvVisitedCount) / c.kolTargetCount * 100).setScale(1);
        }
        return c;
    }
}