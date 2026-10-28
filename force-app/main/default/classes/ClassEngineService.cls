/**
 * Promo Grid Class Engine: score territory accounts, apply specialty quotas and
 * class seats, diminish visits for leave/holidays, and apply approved cycles.
 */
public with sharing class ClassEngineService {
    private static final List<String> CLASS_PRIORITY = new List<String>{
        'A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'
    };
    private static final List<String> DIMINISH_ORDER = new List<String>{
        'C3', 'C2', 'C1', 'B3', 'B2', 'B1', 'A3', 'A2', 'A1'
    };

    public class ProductWeight {
        @AuraEnabled public Id product2Id;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal weightPercentage;
    }

    public class SpecialtyQuota {
        @AuraEnabled public String specialty;
        @AuraEnabled public Decimal listPercentage;
    }

    public class ClassTarget {
        @AuraEnabled public String classCode;
        @AuraEnabled public Decimal listPercentage;
        @AuraEnabled public Decimal targetMonthlyVisits;
    }

    public class ProductScoreInput {
        @AuraEnabled public Id product2Id;
        @AuraEnabled public Decimal potential;
        @AuraEnabled public Decimal penetration;
        @AuraEnabled public Decimal weightPercentage;
    }

    public class AccountScoreInput {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String specialty;
        @AuraEnabled public List<ProductScoreInput> products;
    }

    public class ClassifiedAccount {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String specialty;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String classCode;
        @AuraEnabled public Decimal gridFrequency;
        @AuraEnabled public Integer sortOrder;
    }

    public class ClassifyResult {
        @AuraEnabled public Integer capacityVisits;
        @AuraEnabled public Integer plannedVisits;
        @AuraEnabled public Integer listSize;
        @AuraEnabled public List<ClassifiedAccount> accounts;
        @AuraEnabled public Map<String, Integer> seatsByClass;
        @AuraEnabled public Map<String, Integer> specialtyCounts;
    }

    public class DiminishResult {
        @AuraEnabled public Integer capacityVisits;
        @AuraEnabled public Integer plannedVisits;
        @AuraEnabled public Map<String, Decimal> appliedVisitsByClass;
    }

    /** Weighted score: Σ (weight% / 100 × potential × share) where share = penetration/potential. */
    public static Decimal scoreAccount(List<ProductScoreInput> products) {
        Decimal total = 0;
        if (products == null) {
            return total;
        }
        for (ProductScoreInput product : products) {
            if (product == null || product.weightPercentage == null) {
                continue;
            }
            Decimal potential = product.potential == null ? 0 : product.potential;
            Decimal penetration = product.penetration == null ? 0 : product.penetration;
            Decimal share = potential == 0 ? 0 : (penetration / potential);
            total += (product.weightPercentage / 100) * potential * share;
        }
        return total;
    }

    public static ClassifyResult classify(
        List<AccountScoreInput> pool,
        List<SpecialtyQuota> specialties,
        List<ClassTarget> classTargets,
        Integer capacityVisits
    ) {
        ClassifyResult result = new ClassifyResult();
        result.capacityVisits = capacityVisits == null ? 0 : capacityVisits;
        result.accounts = new List<ClassifiedAccount>();
        result.seatsByClass = new Map<String, Integer>();
        result.specialtyCounts = new Map<String, Integer>();

        if (pool == null || pool.isEmpty() || classTargets == null || classTargets.isEmpty()) {
            result.listSize = 0;
            result.plannedVisits = 0;
            return result;
        }

        Decimal avgFreq = weightedAverageFrequency(classTargets);
        Integer n = avgFreq > 0
            ? Integer.valueOf(Math.floor(result.capacityVisits / avgFreq))
            : pool.size();
        n = Math.max(0, Math.min(n, pool.size()));

        Map<Id, Decimal> scoreByAccount = new Map<Id, Decimal>();
        for (AccountScoreInput account : pool) {
            scoreByAccount.put(account.accountId, scoreAccount(account.products));
        }

        List<AccountScoreInput> selected = selectBySpecialtyQuotas(pool, specialties, scoreByAccount, n);
        result.listSize = selected.size();
        for (AccountScoreInput account : selected) {
            String specialty = String.isBlank(account.specialty) ? 'Other' : account.specialty;
            Integer count = result.specialtyCounts.containsKey(specialty)
                ? result.specialtyCounts.get(specialty)
                : 0;
            result.specialtyCounts.put(specialty, count + 1);
        }

        Map<String, Decimal> visitsByClass = new Map<String, Decimal>();
        Map<String, Integer> seats = allocateClassSeats(classTargets, selected.size(), visitsByClass);
        result.seatsByClass.putAll(seats);

        selected.sort(new AccountScoreComparator(scoreByAccount));
        Integer index = 0;
        Integer planned = 0;
        for (String classCode : CLASS_PRIORITY) {
            Integer seatCount = seats.containsKey(classCode) ? seats.get(classCode) : 0;
            Decimal freq = visitsByClass.containsKey(classCode) ? visitsByClass.get(classCode) : 0;
            for (Integer i = 0; i < seatCount && index < selected.size(); i++) {
                AccountScoreInput source = selected[index];
                ClassifiedAccount row = new ClassifiedAccount();
                row.accountId = source.accountId;
                row.accountName = source.accountName;
                row.specialty = source.specialty;
                row.score = scoreByAccount.get(source.accountId);
                row.classCode = classCode;
                row.gridFrequency = freq;
                row.sortOrder = index + 1;
                result.accounts.add(row);
                planned += freq == null ? 0 : freq.intValue();
                index++;
            }
        }
        result.plannedVisits = planned;
        return result;
    }

    public static DiminishResult diminishVisits(
        Map<String, Integer> seatsByClass,
        Map<String, Decimal> gridVisitsByClass,
        Integer capacityVisits
    ) {
        DiminishResult result = new DiminishResult();
        result.capacityVisits = capacityVisits == null ? 0 : capacityVisits;
        result.appliedVisitsByClass = new Map<String, Decimal>();
        if (seatsByClass == null || gridVisitsByClass == null) {
            result.plannedVisits = 0;
            return result;
        }
        for (String classCode : seatsByClass.keySet()) {
            Decimal grid = gridVisitsByClass.containsKey(classCode) ? gridVisitsByClass.get(classCode) : 0;
            result.appliedVisitsByClass.put(classCode, grid);
        }

        Integer planned = sumPlanned(seatsByClass, result.appliedVisitsByClass);
        for (String classCode : DIMINISH_ORDER) {
            while (planned > result.capacityVisits) {
                if (!result.appliedVisitsByClass.containsKey(classCode)) {
                    break;
                }
                Decimal current = result.appliedVisitsByClass.get(classCode);
                if (current == null || current <= 0) {
                    break;
                }
                result.appliedVisitsByClass.put(classCode, current - 1);
                planned = sumPlanned(seatsByClass, result.appliedVisitsByClass);
            }
            if (planned <= result.capacityVisits) {
                break;
            }
        }
        result.plannedVisits = planned;
        return result;
    }

    public static Id resolveLineTerritoryId(Id territoryId) {
        if (territoryId == null) {
            return null;
        }
        Id cursor = territoryId;
        Integer guard = 0;
        while (cursor != null && guard < 20) {
            List<Territory2> rows = Database.query(
                'SELECT Id, ParentTerritory2Id, Territory_Type__c FROM Territory2 WHERE Id = :cursor LIMIT 1'
            );
            if (rows.isEmpty()) {
                return null;
            }
            Territory2 territory = rows[0];
            String typeValue = (String) territory.get('Territory_Type__c');
            if (typeValue == 'Line') {
                return territory.Id;
            }
            cursor = territory.ParentTerritory2Id;
            guard++;
        }
        return null;
    }

    public static Decimal resolveDailyVisitRate(Id territoryId) {
        if (territoryId == null) {
            return 1;
        }
        // One resolver: territory call rate, then the Line, BU and Org Call Rate Rules.
        Decimal rate = CallRateRuleService.resolveForTerritory(territoryId).call;
        return rate != null && rate > 0 ? rate : 1;
    }

    private static Decimal weightedAverageFrequency(List<ClassTarget> classTargets) {
        Decimal weighted = 0;
        Decimal totalPct = 0;
        for (ClassTarget target : classTargets) {
            if (target == null || target.listPercentage == null || target.targetMonthlyVisits == null) {
                continue;
            }
            weighted += (target.listPercentage / 100) * target.targetMonthlyVisits;
            totalPct += target.listPercentage;
        }
        return totalPct == 0 ? 0 : weighted;
    }

    private static List<AccountScoreInput> selectBySpecialtyQuotas(
        List<AccountScoreInput> pool,
        List<SpecialtyQuota> specialties,
        Map<Id, Decimal> scoreByAccount,
        Integer n
    ) {
        if (n <= 0) {
            return new List<AccountScoreInput>();
        }
        if (specialties == null || specialties.isEmpty()) {
            List<AccountScoreInput> sorted = new List<AccountScoreInput>(pool);
            sorted.sort(new AccountScoreComparator(scoreByAccount));
            List<AccountScoreInput> top = new List<AccountScoreInput>();
            for (Integer i = 0; i < n && i < sorted.size(); i++) {
                top.add(sorted[i]);
            }
            return top;
        }

        Map<String, List<AccountScoreInput>> bySpecialty = new Map<String, List<AccountScoreInput>>();
        for (AccountScoreInput account : pool) {
            for (SpecialtyQuota quota : specialties) {
                if (String.isBlank(quota.specialty)) {
                    continue;
                }
                if (specialtyMatches(account.specialty, quota.specialty)) {
                    if (!bySpecialty.containsKey(quota.specialty)) {
                        bySpecialty.put(quota.specialty, new List<AccountScoreInput>());
                    }
                    bySpecialty.get(quota.specialty).add(account);
                }
            }
        }

        Map<String, Integer> quotas = hamiltonAllocate(specialties, n);
        List<AccountScoreInput> selected = new List<AccountScoreInput>();
        Set<Id> selectedIds = new Set<Id>();
        for (SpecialtyQuota quota : specialties) {
            Integer seats = quotas.containsKey(quota.specialty) ? quotas.get(quota.specialty) : 0;
            List<AccountScoreInput> candidates = bySpecialty.containsKey(quota.specialty)
                ? bySpecialty.get(quota.specialty)
                : new List<AccountScoreInput>();
            candidates.sort(new AccountScoreComparator(scoreByAccount));
            Integer taken = 0;
            for (AccountScoreInput candidate : candidates) {
                if (taken >= seats) {
                    break;
                }
                if (selectedIds.contains(candidate.accountId)) {
                    continue;
                }
                selected.add(candidate);
                selectedIds.add(candidate.accountId);
                taken++;
            }
        }
        return selected;
    }

    private static Map<String, Integer> allocateClassSeats(
        List<ClassTarget> classTargets,
        Integer n,
        Map<String, Decimal> visitsByClass
    ) {
        List<SpecialtyQuota> asQuotas = new List<SpecialtyQuota>();
        for (ClassTarget target : classTargets) {
            SpecialtyQuota quota = new SpecialtyQuota();
            quota.specialty = target.classCode;
            quota.listPercentage = target.listPercentage;
            asQuotas.add(quota);
            visitsByClass.put(
                target.classCode,
                target.targetMonthlyVisits == null ? 0 : target.targetMonthlyVisits
            );
        }
        // Higher class wins remainder ties (A1 before C1).
        return hamiltonAllocateOrdered(asQuotas, n, CLASS_PRIORITY);
    }

    private static Map<String, Integer> hamiltonAllocate(List<SpecialtyQuota> quotas, Integer n) {
        List<String> order = new List<String>();
        for (SpecialtyQuota quota : quotas) {
            order.add(quota.specialty);
        }
        return hamiltonAllocateOrdered(quotas, n, order);
    }

    private static Map<String, Integer> hamiltonAllocateOrdered(
        List<SpecialtyQuota> quotas,
        Integer n,
        List<String> preferredOrder
    ) {
        Map<String, Integer> seats = new Map<String, Integer>();
        Map<String, Decimal> remainders = new Map<String, Decimal>();
        Integer assigned = 0;
        Map<String, Decimal> pctByKey = new Map<String, Decimal>();
        for (SpecialtyQuota quota : quotas) {
            pctByKey.put(quota.specialty, quota.listPercentage == null ? 0 : quota.listPercentage);
        }
        for (String key : preferredOrder) {
            if (!pctByKey.containsKey(key)) {
                continue;
            }
            Decimal raw = (pctByKey.get(key) / 100) * n;
            Integer floorSeat = Integer.valueOf(Math.floor(raw));
            seats.put(key, floorSeat);
            remainders.put(key, raw - floorSeat);
            assigned += floorSeat;
        }
        Integer remaining = n - assigned;
        List<String> remainderOrder = new List<String>(preferredOrder);
        remainderOrder.sort(new RemainderComparator(remainders, preferredOrder));
        for (String key : remainderOrder) {
            if (remaining <= 0) {
                break;
            }
            if (!seats.containsKey(key)) {
                continue;
            }
            seats.put(key, seats.get(key) + 1);
            remaining--;
        }
        return seats;
    }

    private static Integer sumPlanned(
        Map<String, Integer> seatsByClass,
        Map<String, Decimal> visitsByClass
    ) {
        Integer total = 0;
        for (String classCode : seatsByClass.keySet()) {
            Integer seats = seatsByClass.get(classCode) == null ? 0 : seatsByClass.get(classCode);
            Decimal visits = visitsByClass.containsKey(classCode) ? visitsByClass.get(classCode) : 0;
            if (visits == null) {
                visits = 0;
            }
            total += seats * visits.intValue();
        }
        return total;
    }

    private static Boolean specialtyMatches(String accountSpecialty, String gridSpecialty) {
        if (String.isBlank(accountSpecialty) || String.isBlank(gridSpecialty)) {
            return false;
        }
        return accountSpecialty.trim().equalsIgnoreCase(gridSpecialty.trim());
    }

    private class AccountScoreComparator implements Comparator<AccountScoreInput> {
        private Map<Id, Decimal> scoreByAccount;
        AccountScoreComparator(Map<Id, Decimal> scoreByAccount) {
            this.scoreByAccount = scoreByAccount;
        }
        public Integer compare(AccountScoreInput a, AccountScoreInput b) {
            Decimal scoreA = scoreByAccount.containsKey(a.accountId) ? scoreByAccount.get(a.accountId) : 0;
            Decimal scoreB = scoreByAccount.containsKey(b.accountId) ? scoreByAccount.get(b.accountId) : 0;
            if (scoreA == scoreB) {
                return 0;
            }
            return scoreA > scoreB ? -1 : 1;
        }
    }

    private class RemainderComparator implements Comparator<String> {
        private Map<String, Decimal> remainders;
        private List<String> preferredOrder;
        RemainderComparator(Map<String, Decimal> remainders, List<String> preferredOrder) {
            this.remainders = remainders;
            this.preferredOrder = preferredOrder;
        }
        public Integer compare(String a, String b) {
            Decimal remA = remainders.containsKey(a) ? remainders.get(a) : 0;
            Decimal remB = remainders.containsKey(b) ? remainders.get(b) : 0;
            if (remA != remB) {
                return remA > remB ? -1 : 1;
            }
            Integer idxA = preferredOrder.indexOf(a);
            Integer idxB = preferredOrder.indexOf(b);
            if (idxA == idxB) {
                return 0;
            }
            if (idxA < 0) {
                return 1;
            }
            if (idxB < 0) {
                return -1;
            }
            return idxA < idxB ? -1 : 1;
        }
    }
}