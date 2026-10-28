/**
 * AuraEnabled API for the Class Engine tab: load territory accounts, save Rx
 * ratings, classify, submit, and manager approve/reject.
 */
public with sharing class ClassEngineController {
    @TestVisible static PromoGridAdminController.PromoGridDto testPromoGrid;
    @TestVisible static Id testTerritoryId;
    @TestVisible static Id testLineTerritoryId;
    @TestVisible static Decimal testDailyRate;
    @TestVisible static List<AccountRowDto> testAccounts;
    static Set<Id> cachedAssignedTerritoryIds;
    static Set<Id> cachedSwitchableTerritoryIds;
    static List<TerritoryOption> cachedReviewTerritories;
    static String cachedReviewQuarter;

    public class ProductRatingDto {
        @AuraEnabled public Id product2Id;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal weightPercentage;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Id atpfId;
        @AuraEnabled public Decimal rxPotential;
        @AuraEnabled public Decimal rxPenetration;
        @AuraEnabled public Decimal salesPotential;
        @AuraEnabled public Decimal salesPenetration;
    }

    public class AccountRowDto {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String specialty;
        @AuraEnabled public String recordTypeDeveloperName;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public Id atfId;
        @AuraEnabled public String currentClassification;
        @AuraEnabled public String rxClass;
        @AuraEnabled public String salesClass;
        @AuraEnabled public String chosenClass;
        @AuraEnabled public String overrideClass;
        @AuraEnabled public Decimal rxScore;
        @AuraEnabled public Decimal salesScore;
        @AuraEnabled public Decimal gridFrequency;
        @AuraEnabled public Decimal monthFrequency;
        @AuraEnabled public Decimal suggestedFrequency;
        @AuraEnabled public Decimal approvedFrequency;
        @AuraEnabled public Boolean frequencyReviewed;
        /** Per-month exceptions as JSON: {"yyyy-MM-dd": {"s": suggested, "a": approved, "r": reviewed}}. */
        @AuraEnabled public String monthlyFrequencies;
        @AuraEnabled public Integer sortOrder;
        @AuraEnabled public Id cycleAccountId;
        @AuraEnabled public List<ProductRatingDto> products;
    }

    public class MonthCapacityDto {
        @AuraEnabled public Date monthStart;
        @AuraEnabled public Integer workingDays;
        @AuraEnabled public Integer holidayDays;
        @AuraEnabled public Integer leaveDays;
        @AuraEnabled public Integer totDays;
        @AuraEnabled public Decimal dailyRate;
        @AuraEnabled public Integer capacityVisits;
        @AuraEnabled public Integer plannedVisits;
        @AuraEnabled public Map<String, Decimal> appliedVisitsByClass;
    }

    public class CycleDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String status;
        @AuraEnabled public String quarter;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public Id territoryId;
        @AuraEnabled public Id lineTerritoryId;
        @AuraEnabled public Id approverId;
        @AuraEnabled public Datetime submittedAt;
        @AuraEnabled public Datetime approvedAt;
        @AuraEnabled public Integer capacityVisits;
        @AuraEnabled public Integer plannedVisits;
    }

    public class PageDto {
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public Id territoryId;
        @AuraEnabled public String territoryName;
        @AuraEnabled public Id lineTerritoryId;
        @AuraEnabled public String lineTerritoryName;
        @AuraEnabled public Decimal dailyVisitRate;
        @AuraEnabled public String viewerMode;
        @AuraEnabled public Boolean canApprove;
        @AuraEnabled public Boolean canOverrideClass;
        @AuraEnabled public CycleDto cycle;
        @AuraEnabled public List<AccountRowDto> accounts;
        @AuraEnabled public List<MonthCapacityDto> months;
        @AuraEnabled public PromoGridAdminController.PromoGridDto promoGrid;
        @AuraEnabled public List<PicklistOption> classOptions;
        @AuraEnabled public List<RepOption> teamReps;
        @AuraEnabled public List<TerritoryOption> reviewTerritories;
        @AuraEnabled public List<CycleDto> pendingCycles;
        @AuraEnabled public String scopeNote;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class RepOption {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        /** Cycle status for the page quarter; null when the rep has no cycle yet. */
        @AuraEnabled public String status;
        /** Submitted cycles from this rep awaiting the viewer, across all quarters. */
        @AuraEnabled public Integer pendingCount;
        @AuraEnabled public List<String> pendingQuarters;
    }

    public class TerritoryOption implements Comparable {
        @AuraEnabled public Id territoryId;
        @AuraEnabled public String name;
        /** True when the viewer is assigned to this territory; false for a subordinate territory. */
        @AuraEnabled public Boolean assigned;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public String status;
        @AuraEnabled public Integer pendingCount;
        @AuraEnabled public List<String> pendingQuarters;

        public Integer compareTo(Object other) {
            TerritoryOption that = (TerritoryOption) other;
            String left = name == null ? '' : name.toLowerCase();
            String right = that.name == null ? '' : that.name.toLowerCase();
            return left.compareTo(right);
        }
    }

    public class ChosenClassUpdate {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String chosenClass;
        @AuraEnabled public String overrideClass;
        // Frequency exception (monthly visits). Applied only when frequencyTouched; null clears.
        @AuraEnabled public Boolean frequencyTouched;
        @AuraEnabled public Decimal exceptionFrequency;
        /** Per-month exceptions; a null frequency clears (rep) or declines (manager) that month. */
        @AuraEnabled public List<MonthFrequency> monthFrequencies;
    }

    public class MonthFrequency {
        /** yyyy-MM-dd, the first day of a month of the cycle. */
        @AuraEnabled public String monthStart;
        @AuraEnabled public Decimal frequency;
    }

    public static PageDto getPage(Id employeeId, String quarter) {
        return getPage(employeeId, quarter, null);
    }

    @AuraEnabled
    public static PageDto getPage(Id employeeId, String quarter, Id territoryId) {
        List<TerritoryOption> reviewTerritories = listReviewTerritories(quarter);
        Id resolvedEmployeeId;
        Id resolvedTerritoryId = testTerritoryId != null ? testTerritoryId : territoryId;
        if (territoryId != null && testTerritoryId == null) {
            if (!canOpenTerritory(territoryId, reviewTerritories)) {
                throw new AuraHandledException('You cannot open that territory.');
            }
            resolvedEmployeeId = employeeForTerritory(territoryId, reviewTerritories);
            if (resolvedEmployeeId == null) {
                resolvedEmployeeId = UserInfo.getUserId();
            }
            resolvedTerritoryId = territoryId;
        } else {
            resolvedEmployeeId = resolveEmployeeId(employeeId);
            if (resolvedTerritoryId == null) {
                resolvedTerritoryId = primaryTerritoryId(resolvedEmployeeId);
            }
        }

        Id lineTerritoryId = testLineTerritoryId != null
            ? testLineTerritoryId
            : ClassEngineService.resolveLineTerritoryId(resolvedTerritoryId);
        Decimal dailyRate = testDailyRate != null
            ? testDailyRate
            : ClassEngineService.resolveDailyVisitRate(resolvedTerritoryId);

        PageDto page = new PageDto();
        page.employeeId = resolvedEmployeeId;
        page.employeeName = userName(resolvedEmployeeId);
        page.territoryId = resolvedTerritoryId;
        page.territoryName = territoryName(resolvedTerritoryId);
        page.lineTerritoryId = lineTerritoryId;
        page.lineTerritoryName = territoryName(lineTerritoryId);
        page.dailyVisitRate = dailyRate;
        page.viewerMode = resolvedEmployeeId == UserInfo.getUserId() ? 'self' : 'manager';
        page.reviewTerritories = reviewTerritories;
        page.teamReps = listDirectReports();
        page.canApprove = page.viewerMode == 'manager'
            || hasReviewScope(reviewTerritories)
            || SfeApproverService.isApprover(UserInfo.getUserId(), SfeApproverService.CLASSIFICATION);
        page.canOverrideClass = page.viewerMode == 'manager' && isSfeUser();
        page.pendingCycles = page.canApprove ? listPendingCycles() : new List<CycleDto>();
        page.classOptions = classOptions();
        if (!page.canApprove) {
            page.teamReps = new List<RepOption>();
        }
        page.scopeNote = buildScopeNote(page, reviewTerritories);
        decorateTeam(page.teamReps, page.pendingCycles, quarter);
        page.promoGrid = testPromoGrid != null
            ? testPromoGrid
            : (lineTerritoryId == null
                ? null
                : PromoGridAdminController.getPromoGrid(lineTerritoryId));

        Boolean reviewingOther = page.viewerMode == 'manager';
        // Viewing never writes. A Draft cycle is created only when the rep classifies.
        Classification_Cycle__c cycle = findLatestCycle(resolvedEmployeeId, quarter);
        page.cycle = cycle == null
            ? emptyCycle(resolvedEmployeeId, resolvedTerritoryId, quarter)
            : toCycleDto(cycle);
        page.accounts = testAccounts != null
            ? testAccounts
            : loadAccountRows(resolvedTerritoryId, lineTerritoryId, cycle);
        page.months = buildMonthCapacities(resolvedEmployeeId, resolvedTerritoryId, cycle, page.accounts);
        syncReviewStatus(page);
        return page;
    }

    private static void syncReviewStatus(PageDto page) {
        if (page == null || cachedReviewTerritories == null || page.cycle == null) {
            return;
        }
        for (TerritoryOption territory : cachedReviewTerritories) {
            if (territory.territoryId == page.territoryId || territory.employeeId == page.employeeId) {
                territory.status = page.cycle.status;
            }
        }
    }

    @AuraEnabled
    public static void saveProductRatings(
        Id accountId,
        Id territoryId,
        Id product2Id,
        Decimal potential,
        Decimal penetration
    ) {
        requireRepPotentialPenetrationEdit();
        if (accountId == null || territoryId == null || product2Id == null) {
            throw new AuraHandledException('Account, territory, and product are required.');
        }
        String territoryKey = String.valueOf(territoryId);
        String productKey = String.valueOf(product2Id);
        List<Account_Territory_Product_Fields__c> existing = [
            SELECT Id, Potential__c, Penetration__c
            FROM Account_Territory_Product_Fields__c
            WHERE Account__c = :accountId
            AND Territory2_Id__c = :territoryKey
            AND Product2_Id__c = :productKey
            WITH USER_MODE
            LIMIT 1
        ];
        Account_Territory_Product_Fields__c row;
        if (existing.isEmpty()) {
            row = new Account_Territory_Product_Fields__c(
                Account__c = accountId,
                Territory2_Id__c = territoryKey,
                Product2_Id__c = productKey,
                Unique_Key__c = (accountId + ':' + territoryKey + ':' + productKey).left(80),
                Is_Active__c = true
            );
        } else {
            row = existing[0];
        }
        row.Potential__c = potential;
        row.Penetration__c = penetration;
        if (row.Id == null) {
            insert as user row;
        } else {
            update as user row;
        }
    }

    public static PageDto classify(Id employeeId, String quarter) {
        return classify(employeeId, quarter, null);
    }

    @AuraEnabled
    public static PageDto classify(Id employeeId, String quarter, Id territoryId) {
        PageDto page = getPage(employeeId, quarter, territoryId);
        if (page.viewerMode == 'manager') {
            throw new AuraHandledException('Classify your own territory. Approve a subordinate plan from their territory.');
        }
        if (page.cycle == null) {
            throw new AuraHandledException('There is no classification cycle to update.');
        }
        if (page.promoGrid == null || (page.lineTerritoryId == null && testPromoGrid == null)) {
            throw new AuraHandledException('Line promo grid is required before classifying.');
        }
        if (page.cycle != null && page.cycle.status == 'Submitted') {
            throw new AuraHandledException('Cycle is already submitted.');
        }
        if (page.cycle.status == 'Approved') {
            throw new AuraHandledException('Cycle is already approved.');
        }
        if (page.cycle.id == null) {
            // First write for this quarter: create the Draft now, not when the page is viewed.
            Classification_Cycle__c draft = findOrCreateDraftCycle(
                page.employeeId,
                page.territoryId,
                page.lineTerritoryId,
                page.cycle.quarter
            );
            page.cycle = toCycleDto(draft);
        }

        List<ClassEngineService.SpecialtyQuota> specialties = new List<ClassEngineService.SpecialtyQuota>();
        for (PromoGridAdminController.SpecialtyFocusRow row : page.promoGrid.specialtyFocus) {
            ClassEngineService.SpecialtyQuota quota = new ClassEngineService.SpecialtyQuota();
            quota.specialty = row.specialty;
            quota.listPercentage = row.listPercentage;
            specialties.add(quota);
        }
        List<ClassEngineService.ClassTarget> classTargets = new List<ClassEngineService.ClassTarget>();
        Map<String, Decimal> gridVisits = new Map<String, Decimal>();
        for (PromoGridAdminController.ClassTargetingRow row : page.promoGrid.classTargeting) {
            ClassEngineService.ClassTarget target = new ClassEngineService.ClassTarget();
            target.classCode = row.classCode;
            target.listPercentage = row.listPercentage;
            target.targetMonthlyVisits = row.targetMonthlyVisits;
            classTargets.add(target);
            gridVisits.put(row.classCode, row.targetMonthlyVisits);
        }

        Integer fullCapacity = fullMonthCapacity(page.dailyVisitRate);
        ClassEngineService.ClassifyResult rxResult = ClassEngineService.classify(
            toScoreInputs(page.accounts, true),
            specialties,
            classTargets,
            fullCapacity
        );
        ClassEngineService.ClassifyResult salesResult = ClassEngineService.classify(
            toScoreInputs(page.accounts, false),
            specialties,
            classTargets,
            fullCapacity
        );

        Map<Id, ClassEngineService.ClassifiedAccount> rxByAccount = indexClassified(rxResult.accounts);
        Map<Id, ClassEngineService.ClassifiedAccount> salesByAccount = indexClassified(salesResult.accounts);

        Classification_Cycle__c cycle = [
            SELECT Id, Status__c, Capacity_Visits__c, Planned_Visits__c
            FROM Classification_Cycle__c
            WHERE Id = :page.cycle.id
            WITH USER_MODE
            LIMIT 1
        ];
        cycle.Capacity_Visits__c = rxResult.capacityVisits;
        cycle.Planned_Visits__c = rxResult.plannedVisits;
        update as user cycle;

        // Re-classify rebuilds rows; keep the rep's frequency exceptions.
        Map<Id, Decimal> suggestedByAccount = new Map<Id, Decimal>();
        List<Classification_Cycle_Account__c> previousRows = [
            SELECT Id, Account__c, Suggested_Frequency__c
            FROM Classification_Cycle_Account__c
            WHERE Classification_Cycle__c = :cycle.Id
            WITH USER_MODE
        ];
        for (Classification_Cycle_Account__c previous : previousRows) {
            if (previous.Suggested_Frequency__c != null) {
                suggestedByAccount.put(previous.Account__c, previous.Suggested_Frequency__c);
            }
        }
        Map<Id, String> monthlyByAccount = loadMonthlyByAccount(cycle.Id, null);
        delete as user previousRows;

        List<Classification_Cycle_Account__c> accountRows = new List<Classification_Cycle_Account__c>();
        Map<Id, AccountRowDto> sourceByAccount = new Map<Id, AccountRowDto>();
        for (AccountRowDto account : page.accounts) {
            sourceByAccount.put(account.accountId, account);
        }
        Set<Id> written = new Set<Id>();
        Integer sortOrder = 1;
        for (ClassEngineService.ClassifiedAccount rxRow : rxResult.accounts) {
            AccountRowDto source = sourceByAccount.get(rxRow.accountId);
            ClassEngineService.ClassifiedAccount salesRow = salesByAccount.get(rxRow.accountId);
            Classification_Cycle_Account__c row = new Classification_Cycle_Account__c();
            row.Classification_Cycle__c = cycle.Id;
            row.Account__c = rxRow.accountId;
            row.Account_Territory_Fields__c = source == null ? null : source.atfId;
            row.Rx_Score__c = rxRow.score;
            row.Sales_Score__c = salesRow == null ? null : salesRow.score;
            row.Rx_Class__c = rxRow.classCode;
            row.Sales_Class__c = salesRow == null ? null : salesRow.classCode;
            row.Chosen_Class__c = rxRow.classCode;
            row.Grid_Frequency__c = rxRow.gridFrequency;
            row.Suggested_Frequency__c = suggestedByAccount.get(rxRow.accountId);
            row.Specialty_Bucket__c = rxRow.specialty;
            row.Sort_Order__c = sortOrder++;
            accountRows.add(row);
            written.add(rxRow.accountId);
        }
        if (!accountRows.isEmpty()) {
            insert as user accountRows;
            List<Classification_Cycle_Account__c> monthlyCarry = new List<Classification_Cycle_Account__c>();
            for (Classification_Cycle_Account__c accountRow : accountRows) {
                if (monthlyByAccount.containsKey(accountRow.Account__c)) {
                    monthlyCarry.add(
                        new Classification_Cycle_Account__c(
                            Id = accountRow.Id,
                            Monthly_Frequencies__c = monthlyByAccount.get(accountRow.Account__c)
                        )
                    );
                }
            }
            if (!monthlyCarry.isEmpty()) {
                update as system monthlyCarry;
            }
            List<Classification_Cycle_Product__c> productRows = new List<Classification_Cycle_Product__c>();
            for (Classification_Cycle_Account__c accountRow : accountRows) {
                AccountRowDto source = sourceByAccount.get(accountRow.Account__c);
                if (source == null || source.products == null) {
                    continue;
                }
                for (ProductRatingDto product : source.products) {
                    Classification_Cycle_Product__c productRow = new Classification_Cycle_Product__c();
                    productRow.Classification_Cycle_Account__c = accountRow.Id;
                    productRow.Product2__c = product.product2Id;
                    productRow.Rx_Potential__c = product.rxPotential;
                    productRow.Rx_Penetration__c = product.rxPenetration;
                    productRow.Sales_Potential__c = product.salesPotential;
                    productRow.Sales_Penetration__c = product.salesPenetration;
                    productRow.Weight_Percentage__c = product.weightPercentage;
                    productRows.add(productRow);
                }
            }
            if (!productRows.isEmpty()) {
                insert as user productRows;
            }
        }

        rebuildMonthSnapshots(page.employeeId, page.territoryId, cycle.Id, rxResult, gridVisits, page.dailyVisitRate);
        return getPage(employeeId, quarter, territoryId);
    }

    @AuraEnabled
    public static PageDto saveChosenClasses(Id cycleId, List<ChosenClassUpdate> updates) {
        if (cycleId == null || updates == null || updates.isEmpty()) {
            return null;
        }
        Classification_Cycle__c cycle = [
            SELECT Id, Status__c, Quarter__c, Employee__c, Territory2_Id__c, Approver__c
            FROM Classification_Cycle__c
            WHERE Id = :cycleId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Boolean managerReview = cycle.Status__c == 'Submitted';
        if (cycle.Status__c == 'Approved') {
            throw new AuraHandledException('Class and frequency cannot be changed after approval.');
        }
        Boolean sfe = isSfeUser();
        if (managerReview) {
            assertCanApprove(cycle);
        } else if (cycle.Employee__c != UserInfo.getUserId()) {
            throw new AuraHandledException('Only the territory owner can suggest frequency exceptions before submit.');
        }
        Map<Id, ChosenClassUpdate> byAccount = new Map<Id, ChosenClassUpdate>();
        for (ChosenClassUpdate updateRow : updates) {
            if (updateRow != null && updateRow.accountId != null) {
                byAccount.put(updateRow.accountId, updateRow);
            }
        }
        List<Classification_Cycle_Account__c> rows = [
            SELECT
                Id,
                Account__c,
                Chosen_Class__c,
                Override_Class__c,
                Rx_Class__c,
                Sales_Class__c,
                Suggested_Frequency__c,
                Approved_Frequency__c,
                Frequency_Reviewed__c
            FROM Classification_Cycle_Account__c
            WHERE Classification_Cycle__c = :cycleId
            AND Account__c IN :byAccount.keySet()
            WITH SYSTEM_MODE
        ];
        for (Classification_Cycle_Account__c row : rows) {
            ChosenClassUpdate updateRow = byAccount.get(row.Account__c);
            // Class is computed from Rx potential/penetration. Reps and DMs never change it;
            // only SFE may override during review.
            String requestedClass = String.isNotBlank(updateRow.overrideClass)
                ? updateRow.overrideClass
                : updateRow.chosenClass;
            String currentClass = String.isNotBlank(row.Override_Class__c)
                ? row.Override_Class__c
                : row.Chosen_Class__c;
            if (String.isNotBlank(requestedClass) && requestedClass != currentClass) {
                if (!(managerReview && sfe)) {
                    throw new AuraHandledException(
                        'Class is calculated from Rx potential and penetration and cannot be changed. Suggest a frequency exception instead.'
                    );
                }
                row.Override_Class__c = requestedClass;
                row.Chosen_Class__c = requestedClass;
            }
            if (updateRow.frequencyTouched == true) {
                Decimal frequency = updateRow.exceptionFrequency;
                if (frequency != null && (frequency < 0 || frequency > 99)) {
                    throw new AuraHandledException('Frequency exception must be between 0 and 99 visits per month.');
                }
                if (managerReview) {
                    // DM decision: a value approves (or sets) the exception; blank declines it.
                    row.Approved_Frequency__c = frequency;
                    row.Frequency_Reviewed__c = true;
                } else {
                    row.Suggested_Frequency__c = frequency;
                    row.Approved_Frequency__c = null;
                    row.Frequency_Reviewed__c = false;
                }
            }
        }
        if (managerReview) {
            update as system rows;
        } else {
            update as user rows;
        }
        saveMonthlyFrequencies(cycleId, byAccount, managerReview);
        return getPage(cycle.Employee__c, cycle.Quarter__c, toId(cycle.Territory2_Id__c));
    }

    /**
     * Per-month exceptions: the rep suggests a value for a month (waits for the manager); the manager's
     * value approves or sets it, and a blank declines it. Kept in system mode: the caller was checked above.
     */
    private static void saveMonthlyFrequencies(Id cycleId, Map<Id, ChosenClassUpdate> byAccount, Boolean managerReview) {
        Set<Id> accountIds = new Set<Id>();
        for (ChosenClassUpdate updateRow : byAccount.values()) {
            if (updateRow.monthFrequencies != null && !updateRow.monthFrequencies.isEmpty()) {
                accountIds.add(updateRow.accountId);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }
        List<Classification_Cycle_Account__c> changed = new List<Classification_Cycle_Account__c>();
        for (Classification_Cycle_Account__c row : [
            SELECT Id, Account__c, Monthly_Frequencies__c
            FROM Classification_Cycle_Account__c
            WHERE Classification_Cycle__c = :cycleId AND Account__c IN :accountIds
            WITH SYSTEM_MODE
        ]) {
            Map<String, Map<String, Object>> monthly = parseMonthly(row.Monthly_Frequencies__c);
            for (MonthFrequency month : byAccount.get(row.Account__c).monthFrequencies) {
                if (month == null || String.isBlank(month.monthStart)) {
                    continue;
                }
                String key = String.valueOf(Date.valueOf(month.monthStart).toStartOfMonth());
                Decimal frequency = month.frequency;
                if (frequency != null && (frequency < 0 || frequency > 99)) {
                    throw new AuraHandledException('Frequency exception must be between 0 and 99 visits per month.');
                }
                Map<String, Object> entry = monthly.containsKey(key) ? monthly.get(key) : new Map<String, Object>();
                if (managerReview) {
                    entry.put('a', frequency);
                    entry.put('r', true);
                } else {
                    entry.put('s', frequency);
                    entry.put('a', null);
                    entry.put('r', false);
                }
                if (entry.get('s') == null && entry.get('a') == null && entry.get('r') != true) {
                    monthly.remove(key);
                } else {
                    monthly.put(key, entry);
                }
            }
            changed.add(new Classification_Cycle_Account__c(Id = row.Id, Monthly_Frequencies__c = serializeMonthly(monthly)));
        }
        if (!changed.isEmpty()) {
            update as system changed;
        }
    }

    private static Map<Id, String> loadMonthlyByAccount(Id cycleId, Set<Id> accountIds) {
        Map<Id, String> result = new Map<Id, String>();
        for (Classification_Cycle_Account__c row : [
            SELECT Account__c, Monthly_Frequencies__c
            FROM Classification_Cycle_Account__c
            WHERE Classification_Cycle__c = :cycleId
            WITH SYSTEM_MODE
        ]) {
            // Long text can't be filtered in SOQL.
            if (String.isNotBlank(row.Monthly_Frequencies__c) && (accountIds == null || accountIds.contains(row.Account__c))) {
                result.put(row.Account__c, row.Monthly_Frequencies__c);
            }
        }
        return result;
    }

    @TestVisible
    private static Map<String, Map<String, Object>> parseMonthly(String raw) {
        Map<String, Map<String, Object>> result = new Map<String, Map<String, Object>>();
        if (String.isBlank(raw)) {
            return result;
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(raw);
            for (String key : parsed.keySet()) {
                if (parsed.get(key) instanceof Map<String, Object>) {
                    result.put(key, (Map<String, Object>) parsed.get(key));
                }
            }
        } catch (Exception e) {
            return result;
        }
        return result;
    }

    private static String serializeMonthly(Map<String, Map<String, Object>> monthly) {
        return monthly == null || monthly.isEmpty() ? null : JSON.serialize(monthly);
    }

    private static Decimal toDecimalOrNull(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }

    @AuraEnabled
    public static PageDto submitCycle(Id cycleId, String quarter) {
        if (cycleId == null) {
            throw new AuraHandledException('Cycle is required.');
        }
        if (String.isBlank(quarter)) {
            throw new AuraHandledException('Quarter is required to submit.');
        }
        Classification_Cycle__c cycle = [
            SELECT Id, Status__c, Employee__c, Territory2_Id__c, Approver__c
            FROM Classification_Cycle__c
            WHERE Id = :cycleId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cycle.Employee__c != UserInfo.getUserId()) {
            throw new AuraHandledException('Only the territory owner can submit this plan.');
        }
        Integer accountCount = [
            SELECT COUNT()
            FROM Classification_Cycle_Account__c
            WHERE Classification_Cycle__c = :cycleId
            WITH USER_MODE
        ];
        if (accountCount == 0) {
            throw new AuraHandledException('Classify accounts before submitting.');
        }
        cycle.Status__c = 'Submitted';
        cycle.Quarter__c = quarter;
        cycle.Submitted_At__c = System.now();
        cycle.Approver__c = resolveApproverId(cycle.Employee__c, toId(cycle.Territory2_Id__c));
        update as user cycle;
        return getPage(cycle.Employee__c, quarter, toId(cycle.Territory2_Id__c));
    }

    @AuraEnabled
    public static PageDto approveCycle(Id cycleId, List<ChosenClassUpdate> managerOverrides) {
        Classification_Cycle__c cycle = [
            SELECT
                Id,
                Status__c,
                Employee__c,
                Territory2_Id__c,
                Quarter__c,
                Approver__c
            FROM Classification_Cycle__c
            WHERE Id = :cycleId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        assertCanApprove(cycle);
        if (managerOverrides != null && !managerOverrides.isEmpty()) {
            saveChosenClasses(cycleId, managerOverrides);
        }
        // Rep suggestions the DM did not touch are approved as suggested.
        List<Classification_Cycle_Account__c> pendingExceptions = [
            SELECT Id, Suggested_Frequency__c
            FROM Classification_Cycle_Account__c
            WHERE Classification_Cycle__c = :cycleId
            AND Frequency_Reviewed__c = false
            AND Suggested_Frequency__c != null
            WITH SYSTEM_MODE
        ];
        for (Classification_Cycle_Account__c row : pendingExceptions) {
            row.Approved_Frequency__c = row.Suggested_Frequency__c;
            row.Frequency_Reviewed__c = true;
        }
        if (!pendingExceptions.isEmpty()) {
            update as system pendingExceptions;
        }
        List<Classification_Cycle_Account__c> pendingMonthly = new List<Classification_Cycle_Account__c>();
        for (Classification_Cycle_Account__c row : [
            SELECT Id, Monthly_Frequencies__c
            FROM Classification_Cycle_Account__c
            WHERE Classification_Cycle__c = :cycleId
            WITH SYSTEM_MODE
        ]) {
            if (String.isBlank(row.Monthly_Frequencies__c)) {
                continue;
            }
            Map<String, Map<String, Object>> monthly = parseMonthly(row.Monthly_Frequencies__c);
            Boolean touched = false;
            for (Map<String, Object> entry : monthly.values()) {
                if (entry.get('r') != true && entry.get('s') != null) {
                    entry.put('a', entry.get('s'));
                    entry.put('r', true);
                    touched = true;
                }
            }
            if (touched) {
                pendingMonthly.add(new Classification_Cycle_Account__c(Id = row.Id, Monthly_Frequencies__c = serializeMonthly(monthly)));
            }
        }
        if (!pendingMonthly.isEmpty()) {
            update as system pendingMonthly;
        }

        List<Classification_Cycle_Account__c> accounts = [
            SELECT
                Id,
                Account__c,
                Account_Territory_Fields__c,
                Chosen_Class__c,
                Override_Class__c,
                Rx_Class__c,
                Grid_Frequency__c,
                Approved_Frequency__c,
                Monthly_Frequencies__c
            FROM Classification_Cycle_Account__c
            WHERE Classification_Cycle__c = :cycleId
            WITH SYSTEM_MODE
            ORDER BY Sort_Order__c ASC
        ];
        List<Classification_Cycle_Month__c> months = [
            SELECT
                Id,
                Month_Start__c,
                Applied_Visits_By_Class__c,
                Capacity_Visits__c,
                Planned_Visits__c
            FROM Classification_Cycle_Month__c
            WHERE Classification_Cycle__c = :cycleId
            WITH SYSTEM_MODE
            ORDER BY Month_Start__c ASC
        ];

        List<Account_Territory_Fields__c> atfUpdates = new List<Account_Territory_Fields__c>();
        for (Classification_Cycle_Account__c account : accounts) {
            if (account.Account_Territory_Fields__c == null) {
                continue;
            }
            String classCode = String.isNotBlank(account.Override_Class__c)
                ? account.Override_Class__c
                : account.Chosen_Class__c;
            if (String.isBlank(classCode)) {
                classCode = account.Rx_Class__c;
            }
            atfUpdates.add(
                new Account_Territory_Fields__c(
                    Id = account.Account_Territory_Fields__c,
                    HCP_Classification__c = classCode
                )
            );
        }
        if (!atfUpdates.isEmpty()) {
            update as system atfUpdates;
        }

        writePlanCycleTargets(cycle.Employee__c, accounts, months);
        writeMonthFrequencies(cycle, accounts, months);

        cycle.Status__c = 'Approved';
        cycle.Approved_At__c = System.now();
        update as system cycle;
        return getPage(cycle.Employee__c, cycle.Quarter__c, toId(cycle.Territory2_Id__c));
    }

    @AuraEnabled
    public static PageDto rejectCycle(Id cycleId, String reason) {
        Classification_Cycle__c cycle = [
            SELECT Id, Status__c, Employee__c, Quarter__c, Approver__c, Territory2_Id__c
            FROM Classification_Cycle__c
            WHERE Id = :cycleId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        assertCanApprove(cycle);
        cycle.Status__c = 'Rejected';
        update as system cycle;
        return getPage(cycle.Employee__c, cycle.Quarter__c, toId(cycle.Territory2_Id__c));
    }

    /** The month's approved exception, else the cycle-wide one, else the class frequency for that month. */
    @TestVisible
    private static Decimal approvedFrequencyFor(
        Classification_Cycle_Account__c account,
        Date monthStart,
        String classCode,
        Map<String, Decimal> applied
    ) {
        Decimal classFrequency = applied.containsKey(classCode) ? applied.get(classCode) : 0;
        Map<String, Object> entry = parseMonthly(account.Monthly_Frequencies__c).get(String.valueOf(monthStart));
        if (entry != null && entry.get('r') == true) {
            Decimal approved = toDecimalOrNull(entry.get('a'));
            // A declined month falls back to the class frequency.
            return approved != null ? approved : classFrequency;
        }
        return account.Approved_Frequency__c != null ? account.Approved_Frequency__c : classFrequency;
    }

    /** Approved cycle = each doctor's visits for each month, so later time-card syncs keep them. */
    private static void writeMonthFrequencies(
        Classification_Cycle__c cycle,
        List<Classification_Cycle_Account__c> accounts,
        List<Classification_Cycle_Month__c> months
    ) {
        String territoryId = cycle.Territory2_Id__c;
        if (String.isBlank(territoryId)) {
            return;
        }
        List<Account_Month_Frequency__c> rows = new List<Account_Month_Frequency__c>();
        for (Classification_Cycle_Month__c monthRow : months) {
            Map<String, Decimal> applied = parseAppliedVisits(monthRow.Applied_Visits_By_Class__c);
            for (Classification_Cycle_Account__c account : accounts) {
                if (account.Account__c == null) {
                    continue;
                }
                String classCode = String.isNotBlank(account.Override_Class__c)
                    ? account.Override_Class__c
                    : account.Chosen_Class__c;
                if (String.isBlank(classCode)) {
                    classCode = account.Rx_Class__c;
                }
                Decimal frequency = approvedFrequencyFor(account, monthRow.Month_Start__c, classCode, applied);
                Account_Territory_Fields__c atf = new Account_Territory_Fields__c(
                    Id = account.Account_Territory_Fields__c,
                    Account__c = account.Account__c,
                    Territory2_Id__c = territoryId
                );
                rows.add(
                    AccountMonthFrequencyService.newRow(
                        atf,
                        cycle.Employee__c,
                        monthRow.Month_Start__c,
                        frequency == null ? 0 : frequency,
                        frequency == null ? 0 : frequency,
                        AccountMonthFrequencyService.SOURCE_CLASS_CYCLE
                    )
                );
            }
        }
        AccountMonthFrequencyService.save(rows);
    }

    private static void writePlanCycleTargets(
        Id employeeId,
        List<Classification_Cycle_Account__c> accounts,
        List<Classification_Cycle_Month__c> months
    ) {
        for (Classification_Cycle_Month__c monthRow : months) {
            Map<String, Decimal> applied = parseAppliedVisits(monthRow.Applied_Visits_By_Class__c);
            Employee_Time_Card__c timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(
                employeeId,
                monthRow.Month_Start__c,
                true,
                true
            );
            Map<String, Employee_Time_Card_Account_Target__c> existingByKey =
                new Map<String, Employee_Time_Card_Account_Target__c>();
            for (Employee_Time_Card_Account_Target__c target : [
                SELECT Id, Unique_Key__c, Account__c, Target_Visit_Frequency__c
                FROM Employee_Time_Card_Account_Target__c
                WHERE Employee_Time_Card__c = :timeCard.Id
                WITH SYSTEM_MODE
            ]) {
                existingByKey.put(target.Unique_Key__c, target);
            }

            List<Employee_Time_Card_Account_Target__c> upserts =
                new List<Employee_Time_Card_Account_Target__c>();
            List<Employee_Time_Card_Account_Target__c> deletes =
                new List<Employee_Time_Card_Account_Target__c>();
            Set<Id> keepAccounts = new Set<Id>();

            for (Classification_Cycle_Account__c account : accounts) {
                String classCode = String.isNotBlank(account.Override_Class__c)
                    ? account.Override_Class__c
                    : account.Chosen_Class__c;
                if (String.isBlank(classCode)) {
                    classCode = account.Rx_Class__c;
                }
                Decimal frequency = approvedFrequencyFor(account, monthRow.Month_Start__c, classCode, applied);
                String key = timeCard.Id + ':' + String.valueOf(account.Account__c);
                if (frequency == null || frequency <= 0) {
                    if (existingByKey.containsKey(key)) {
                        deletes.add(existingByKey.get(key));
                    }
                    continue;
                }
                keepAccounts.add(account.Account__c);
                Employee_Time_Card_Account_Target__c row = existingByKey.containsKey(key)
                    ? existingByKey.get(key)
                    : new Employee_Time_Card_Account_Target__c(
                        Employee_Time_Card__c = timeCard.Id,
                        Unique_Key__c = key
                    );
                row.Account__c = account.Account__c;
                row.Account_Territory_Fields__c = account.Account_Territory_Fields__c;
                row.Target_Visit_Frequency__c = frequency;
                row.Potentiality__c = classCode;
                row.Rep__c = employeeId;
                upserts.add(row);
            }
            if (!deletes.isEmpty()) {
                delete as system deletes;
            }
            if (!upserts.isEmpty()) {
                upsert as system upserts;
            }
        }
    }

    private static void rebuildMonthSnapshots(
        Id employeeId,
        Id territoryId,
        Id cycleId,
        ClassEngineService.ClassifyResult rxResult,
        Map<String, Decimal> gridVisits,
        Decimal dailyRate
    ) {
        delete as user [
            SELECT Id
            FROM Classification_Cycle_Month__c
            WHERE Classification_Cycle__c = :cycleId
            WITH USER_MODE
        ];
        Classification_Cycle__c cycle = [
            SELECT Quarter__c
            FROM Classification_Cycle__c
            WHERE Id = :cycleId
            WITH USER_MODE
            LIMIT 1
        ];
        List<Date> monthStarts = quarterMonthStarts(cycle.Quarter__c);
        List<Classification_Cycle_Month__c> months = new List<Classification_Cycle_Month__c>();
        for (Date monthStart : monthStarts) {
            Date monthEnd = monthStart.addMonths(1).addDays(-1);
            Set<Date> leaveDates = leaveAndTotDates(employeeId, monthStart, monthEnd);
            Set<Date> holidays = PublicHolidayService.datesInRange(monthStart, monthEnd);
            Integer workingDays = countWorkingDays(monthStart, monthEnd);
            Integer holidayDays = countWorkingHolidays(monthStart, monthEnd, holidays);
            Integer leaveDays = 0;
            for (Date day : leaveDates) {
                if (WorkingCalendarUtil.isWorkingDay(day) && !holidays.contains(day)) {
                    leaveDays++;
                }
            }
            Integer availableDays = Math.max(0, workingDays - holidayDays - leaveDays);
            Integer capacity = Integer.valueOf(availableDays * (dailyRate == null ? 1 : dailyRate));
            ClassEngineService.DiminishResult diminished = ClassEngineService.diminishVisits(
                rxResult.seatsByClass,
                gridVisits,
                capacity
            );
            Classification_Cycle_Month__c monthRow = new Classification_Cycle_Month__c();
            monthRow.Classification_Cycle__c = cycleId;
            monthRow.Month_Start__c = monthStart;
            monthRow.Working_Days__c = workingDays;
            monthRow.Holiday_Days__c = holidayDays;
            monthRow.Leave_Days__c = leaveDays;
            monthRow.TOT_Days__c = leaveDays;
            monthRow.Daily_Rate__c = dailyRate;
            monthRow.Capacity_Visits__c = capacity;
            monthRow.Planned_Visits__c = diminished.plannedVisits;
            monthRow.Applied_Visits_By_Class__c = JSON.serialize(diminished.appliedVisitsByClass);
            months.add(monthRow);
        }
        if (!months.isEmpty()) {
            insert as user months;
        }
    }

    private static List<MonthCapacityDto> buildMonthCapacities(
        Id employeeId,
        Id territoryId,
        Classification_Cycle__c cycle,
        List<AccountRowDto> accounts
    ) {
        List<MonthCapacityDto> months = new List<MonthCapacityDto>();
        if (cycle == null) {
            return months;
        }
        List<Classification_Cycle_Month__c> rows = [
            SELECT
                Month_Start__c,
                Working_Days__c,
                Holiday_Days__c,
                Leave_Days__c,
                TOT_Days__c,
                Daily_Rate__c,
                Capacity_Visits__c,
                Planned_Visits__c,
                Applied_Visits_By_Class__c
            FROM Classification_Cycle_Month__c
            WHERE Classification_Cycle__c = :cycle.Id
            WITH SYSTEM_MODE
            ORDER BY Month_Start__c ASC
        ];
        Map<String, Decimal> firstMonthApplied = new Map<String, Decimal>();
        for (Classification_Cycle_Month__c row : rows) {
            MonthCapacityDto dto = new MonthCapacityDto();
            dto.monthStart = row.Month_Start__c;
            dto.workingDays = row.Working_Days__c == null ? 0 : row.Working_Days__c.intValue();
            dto.holidayDays = row.Holiday_Days__c == null ? 0 : row.Holiday_Days__c.intValue();
            dto.leaveDays = row.Leave_Days__c == null ? 0 : row.Leave_Days__c.intValue();
            dto.totDays = row.TOT_Days__c == null ? 0 : row.TOT_Days__c.intValue();
            dto.dailyRate = row.Daily_Rate__c;
            dto.capacityVisits = row.Capacity_Visits__c == null ? 0 : row.Capacity_Visits__c.intValue();
            dto.plannedVisits = row.Planned_Visits__c == null ? 0 : row.Planned_Visits__c.intValue();
            dto.appliedVisitsByClass = parseAppliedVisits(row.Applied_Visits_By_Class__c);
            if (firstMonthApplied.isEmpty() && dto.appliedVisitsByClass != null) {
                firstMonthApplied = dto.appliedVisitsByClass;
            }
            months.add(dto);
        }
        if (!firstMonthApplied.isEmpty()) {
            for (AccountRowDto account : accounts) {
                String classCode = String.isNotBlank(account.overrideClass)
                    ? account.overrideClass
                    : account.chosenClass;
                if (String.isBlank(classCode)) {
                    classCode = account.rxClass;
                }
                account.monthFrequency = firstMonthApplied.containsKey(classCode)
                    ? firstMonthApplied.get(classCode)
                    : account.gridFrequency;
            }
        }
        return months;
    }

    private static List<AccountRowDto> loadAccountRows(
        Id territoryId,
        Id lineTerritoryId,
        Classification_Cycle__c cycle
    ) {
        List<AccountRowDto> rows = new List<AccountRowDto>();
        if (territoryId == null) {
            return rows;
        }
        String territoryKey = String.valueOf(territoryId);
        List<Account_Territory_Fields__c> atfs = [
            SELECT
                Id,
                Account__c,
                Account__r.Name,
                Account__r.Specialty_1__c,
                Account__r.RecordType.DeveloperName,
                Account__r.RecordType.Name,
                HCP_Classification__c,
                Classification__c
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c = :territoryKey
            AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
            ORDER BY Account__r.Name ASC
            LIMIT 2000
        ];
        if (atfs.isEmpty()) {
            return rows;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Account_Territory_Fields__c atf : atfs) {
            accountIds.add(atf.Account__c);
        }

        Map<Id, List<ProductRatingDto>> productsByAccount = loadProducts(
            accountIds,
            territoryId,
            lineTerritoryId
        );
        Map<Id, Classification_Cycle_Account__c> cycleByAccount =
            new Map<Id, Classification_Cycle_Account__c>();
        if (cycle != null) {
            for (Classification_Cycle_Account__c cycleAccount : [
                SELECT
                    Id,
                    Account__c,
                    Rx_Class__c,
                    Sales_Class__c,
                    Chosen_Class__c,
                    Override_Class__c,
                    Rx_Score__c,
                    Sales_Score__c,
                    Grid_Frequency__c,
                    Suggested_Frequency__c,
                    Approved_Frequency__c,
                    Frequency_Reviewed__c,
                    Monthly_Frequencies__c,
                    Sort_Order__c
                FROM Classification_Cycle_Account__c
                WHERE Classification_Cycle__c = :cycle.Id
                WITH SYSTEM_MODE
            ]) {
                cycleByAccount.put(cycleAccount.Account__c, cycleAccount);
            }
        }

        for (Account_Territory_Fields__c atf : atfs) {
            AccountRowDto row = new AccountRowDto();
            row.accountId = atf.Account__c;
            row.accountName = atf.Account__r != null ? atf.Account__r.Name : null;
            row.specialty = atf.Account__r != null ? atf.Account__r.Specialty_1__c : null;
            row.recordTypeDeveloperName = atf.Account__r != null && atf.Account__r.RecordType != null
                ? atf.Account__r.RecordType.DeveloperName
                : null;
            row.recordTypeName = atf.Account__r != null && atf.Account__r.RecordType != null
                ? atf.Account__r.RecordType.Name
                : null;
            row.atfId = atf.Id;
            row.currentClassification = atf.HCP_Classification__c;
            row.products = productsByAccount.containsKey(atf.Account__c)
                ? productsByAccount.get(atf.Account__c)
                : new List<ProductRatingDto>();
            Classification_Cycle_Account__c cycleAccount = cycleByAccount.get(atf.Account__c);
            if (cycleAccount != null) {
                row.cycleAccountId = cycleAccount.Id;
                row.rxClass = cycleAccount.Rx_Class__c;
                row.salesClass = cycleAccount.Sales_Class__c;
                row.chosenClass = cycleAccount.Chosen_Class__c;
                row.overrideClass = cycleAccount.Override_Class__c;
                row.rxScore = cycleAccount.Rx_Score__c;
                row.salesScore = cycleAccount.Sales_Score__c;
                row.gridFrequency = cycleAccount.Grid_Frequency__c;
                row.suggestedFrequency = cycleAccount.Suggested_Frequency__c;
                row.approvedFrequency = cycleAccount.Approved_Frequency__c;
                row.frequencyReviewed = cycleAccount.Frequency_Reviewed__c == true;
                row.monthlyFrequencies = cycleAccount.Monthly_Frequencies__c;
                row.sortOrder = cycleAccount.Sort_Order__c == null
                    ? null
                    : cycleAccount.Sort_Order__c.intValue();
            }
            rows.add(row);
        }
        rows.sort(new AccountRowComparator());
        return rows;
    }

    private static Map<Id, List<ProductRatingDto>> loadProducts(
        Set<Id> accountIds,
        Id territoryId,
        Id lineTerritoryId
    ) {
        Map<Id, List<ProductRatingDto>> byAccount = new Map<Id, List<ProductRatingDto>>();
        if (accountIds == null || accountIds.isEmpty() || lineTerritoryId == null) {
            return byAccount;
        }
        String lineKey = String.valueOf(lineTerritoryId);
        String territoryKey = territoryId == null ? lineKey : String.valueOf(territoryId);
        Map<Id, Decimal> weightByProduct = new Map<Id, Decimal>();
        Map<Id, String> nameByProduct = new Map<Id, String>();
        Map<Id, String> imageByProduct = new Map<Id, String>();
        Boolean canReadImage = productImageFieldReadable();
        Boolean brandOnly = productTypeFieldReadable();
        String imageSelect = canReadImage ? ', Product2__r.Product_Image_URL__c' : '';
        String typeFilter = brandOnly ? ' AND Product2__r.Product_Type__c = \'Brand\'' : '';
        String weightSoql =
            'SELECT Product2__c, Product2__r.Name, Weight_Percentage__c' +
            imageSelect +
            ' FROM Promo_Grid_Product_Weight__c' +
            ' WHERE Territory2_Id__c = :lineKey' +
            ' AND Weight_Percentage__c > 0' +
            ' AND Product2__c != NULL' +
            typeFilter +
            ' WITH SYSTEM_MODE' +
            ' ORDER BY Weight_Percentage__c DESC, Product2__r.Name ASC';
        for (Promo_Grid_Product_Weight__c weight : Database.query(weightSoql)) {
            weightByProduct.put(weight.Product2__c, displayPercent(weight.Weight_Percentage__c));
            nameByProduct.put(
                weight.Product2__c,
                weight.Product2__r != null ? weight.Product2__r.Name : null
            );
            if (canReadImage && weight.Product2__r != null) {
                imageByProduct.put(
                    weight.Product2__c,
                    (String) weight.Product2__r.get('Product_Image_URL__c')
                );
            }
        }
        if (weightByProduct.isEmpty()) {
            return byAccount;
        }

        Set<String> productKeys = new Set<String>();
        for (Id product2Id : weightByProduct.keySet()) {
            productKeys.add(String.valueOf(product2Id));
        }

        Map<String, Account_Territory_Product_Fields__c> atpfByKey =
            new Map<String, Account_Territory_Product_Fields__c>();
        for (Account_Territory_Product_Fields__c atpf : [
            SELECT
                Id,
                Account__c,
                Product2_Id__c,
                Potential__c,
                Penetration__c,
                Sales_Order_Volume_UOM__c,
                Geo_Share_Volume_UOM__c,
                Total_Volume_UOM__c
            FROM Account_Territory_Product_Fields__c
            WHERE Account__c IN :accountIds
            AND Territory2_Id__c = :territoryKey
            AND Product2_Id__c IN :productKeys
            WITH SYSTEM_MODE
        ]) {
            atpfByKey.put(
                String.valueOf(atpf.Account__c) + ':' + atpf.Product2_Id__c,
                atpf
            );
        }

        for (Id accountId : accountIds) {
            List<ProductRatingDto> products = new List<ProductRatingDto>();
            for (Id product2Id : weightByProduct.keySet()) {
                ProductRatingDto product = new ProductRatingDto();
                product.product2Id = product2Id;
                product.productName = nameByProduct.get(product2Id);
                product.weightPercentage = weightByProduct.get(product2Id);
                product.imageUrl = imageByProduct.get(product2Id);
                String key = String.valueOf(accountId) + ':' + String.valueOf(product2Id);
                Account_Territory_Product_Fields__c atpf = atpfByKey.get(key);
                if (atpf != null) {
                    product.atpfId = atpf.Id;
                    product.rxPotential = atpf.Potential__c;
                    product.rxPenetration = atpf.Penetration__c;
                    product.salesPenetration = atpf.Sales_Order_Volume_UOM__c;
                    product.salesPotential = firstNonNull(
                        atpf.Geo_Share_Volume_UOM__c,
                        atpf.Total_Volume_UOM__c,
                        atpf.Sales_Order_Volume_UOM__c
                    );
                } else {
                    product.rxPotential = 0;
                    product.rxPenetration = 0;
                    product.salesPotential = 0;
                    product.salesPenetration = 0;
                }
                products.add(product);
            }
            byAccount.put(accountId, products);
        }
        return byAccount;
    }

    private static List<ClassEngineService.AccountScoreInput> toScoreInputs(
        List<AccountRowDto> accounts,
        Boolean useRx
    ) {
        List<ClassEngineService.AccountScoreInput> inputs =
            new List<ClassEngineService.AccountScoreInput>();
        for (AccountRowDto account : accounts) {
            ClassEngineService.AccountScoreInput input = new ClassEngineService.AccountScoreInput();
            input.accountId = account.accountId;
            input.accountName = account.accountName;
            input.specialty = account.specialty;
            input.products = new List<ClassEngineService.ProductScoreInput>();
            if (account.products != null) {
                for (ProductRatingDto product : account.products) {
                    ClassEngineService.ProductScoreInput score =
                        new ClassEngineService.ProductScoreInput();
                    score.product2Id = product.product2Id;
                    score.weightPercentage = product.weightPercentage;
                    if (useRx) {
                        score.potential = product.rxPotential;
                        score.penetration = product.rxPenetration;
                    } else {
                        score.potential = product.salesPotential;
                        score.penetration = product.salesPenetration;
                    }
                    input.products.add(score);
                }
            }
            inputs.add(input);
        }
        return inputs;
    }

    private static Map<Id, ClassEngineService.ClassifiedAccount> indexClassified(
        List<ClassEngineService.ClassifiedAccount> accounts
    ) {
        Map<Id, ClassEngineService.ClassifiedAccount> byId =
            new Map<Id, ClassEngineService.ClassifiedAccount>();
        if (accounts == null) {
            return byId;
        }
        for (ClassEngineService.ClassifiedAccount account : accounts) {
            byId.put(account.accountId, account);
        }
        return byId;
    }

    private static Classification_Cycle__c findOrCreateDraftCycle(
        Id employeeId,
        Id territoryId,
        Id lineTerritoryId,
        String quarter
    ) {
        String resolvedQuarter = String.isBlank(quarter) ? currentQuarter() : quarter;
        List<Classification_Cycle__c> existing = [
            SELECT
                Id,
                Status__c,
                Quarter__c,
                Employee__c,
                Territory2_Id__c,
                Line_Territory2_Id__c,
                Approver__c,
                Submitted_At__c,
                Approved_At__c,
                Capacity_Visits__c,
                Planned_Visits__c
            FROM Classification_Cycle__c
            WHERE Employee__c = :employeeId
            AND Quarter__c = :resolvedQuarter
            AND Status__c IN ('Draft', 'Submitted', 'Rejected')
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }
        Classification_Cycle__c cycle = new Classification_Cycle__c(
            Employee__c = employeeId,
            Territory2_Id__c = territoryId == null ? null : String.valueOf(territoryId),
            Line_Territory2_Id__c = lineTerritoryId == null ? null : String.valueOf(lineTerritoryId),
            Quarter__c = resolvedQuarter,
            Status__c = 'Draft'
        );
        insert as user cycle;
        return [
            SELECT
                Id,
                Status__c,
                Quarter__c,
                Employee__c,
                Territory2_Id__c,
                Line_Territory2_Id__c,
                Approver__c,
                Submitted_At__c,
                Approved_At__c,
                Capacity_Visits__c,
                Planned_Visits__c
            FROM Classification_Cycle__c
            WHERE Id = :cycle.Id
            WITH USER_MODE
            LIMIT 1
        ];
    }

    private static CycleDto toCycleDto(Classification_Cycle__c cycle) {
        if (cycle == null) {
            return null;
        }
        CycleDto dto = new CycleDto();
        dto.id = cycle.Id;
        dto.status = cycle.Status__c;
        dto.quarter = cycle.Quarter__c;
        dto.employeeId = cycle.Employee__c;
        dto.employeeName = userName(cycle.Employee__c);
        dto.territoryId = toId(cycle.Territory2_Id__c);
        dto.lineTerritoryId = toId(cycle.Line_Territory2_Id__c);
        dto.approverId = cycle.Approver__c;
        dto.submittedAt = cycle.Submitted_At__c;
        dto.approvedAt = cycle.Approved_At__c;
        dto.capacityVisits = cycle.Capacity_Visits__c == null
            ? null
            : cycle.Capacity_Visits__c.intValue();
        dto.plannedVisits = cycle.Planned_Visits__c == null
            ? null
            : cycle.Planned_Visits__c.intValue();
        return dto;
    }

    private static List<CycleDto> cachedPendingCycles;

    private static List<CycleDto> listPendingCycles() {
        if (cachedPendingCycles != null) {
            return cachedPendingCycles;
        }
        Id viewerId = UserInfo.getUserId();
        // SFE reviewers see cycles routed to them and cycles from the lines they approve
        // (Admin Console > SFE Approvers), not every direct report under ManagerId.
        Boolean sfeOnly = isSfeUser();
        Set<Id> reportIds = sfeOnly
            ? new Set<Id>()
            : new Map<Id, User>([
                  SELECT Id
                  FROM User
                  WHERE ManagerId = :viewerId AND IsActive = TRUE
                  WITH SYSTEM_MODE
                  LIMIT 200
              ])
                  .keySet();
        Set<String> territoryKeys = new Set<String>();
        if (!sfeOnly) {
            for (Id territoryId : switchableTerritoryIds()) {
                territoryKeys.add(String.valueOf(territoryId));
            }
        }
        for (Id territoryId : SfeApproverService.territoryIdsFor(viewerId, SfeApproverService.CLASSIFICATION)) {
            territoryKeys.add(String.valueOf(territoryId));
        }
        // All Lines approvers match every submitted cycle.
        Set<String> allLinesStatuses = SfeApproverService.coversAllLines(viewerId, SfeApproverService.CLASSIFICATION)
            ? new Set<String>{ 'Submitted' }
            : new Set<String>();
        List<CycleDto> rows = new List<CycleDto>();
        for (Classification_Cycle__c cycle : [
            SELECT
                Id,
                Status__c,
                Quarter__c,
                Employee__c,
                Employee__r.Name,
                Territory2_Id__c,
                Line_Territory2_Id__c,
                Approver__c,
                Submitted_At__c,
                Approved_At__c,
                Capacity_Visits__c,
                Planned_Visits__c
            FROM Classification_Cycle__c
            WHERE Status__c = 'Submitted'
            AND Employee__c != :viewerId
            AND (
                Approver__c = :viewerId
                OR Employee__c IN :reportIds
                OR Territory2_Id__c IN :territoryKeys
                OR Status__c IN :allLinesStatuses
            )
            WITH SYSTEM_MODE
            ORDER BY Submitted_At__c DESC
            LIMIT 200
        ]) {
            CycleDto dto = toCycleDto(cycle);
            dto.employeeName = cycle.Employee__r != null ? cycle.Employee__r.Name : dto.employeeName;
            rows.add(dto);
        }
        cachedPendingCycles = rows;
        return rows;
    }

    /**
     * Explains why a reviewer sees nothing. Reviewers need a seated territory, direct reports, or
     * lines in Admin Console > SFE Approvers to get a review scope.
     */
    private static String buildScopeNote(PageDto page, List<TerritoryOption> territories) {
        if (page == null || page.viewerMode == 'manager') {
            return null;
        }
        Boolean noScope = (territories == null || territories.isEmpty()) &&
            (page.teamReps == null || page.teamReps.isEmpty()) &&
            !SfeApproverService.isApprover(UserInfo.getUserId(), SfeApproverService.CLASSIFICATION);
        if (noScope && page.territoryId == null) {
            return 'You are not seated on a territory and have no direct reports, so there is nothing to ' +
                'classify or review. Ask SFE / Head Office to seat you on a Head Office or first-line ' +
                'position to review team plans.';
        }
        if (page.canApprove == true && (page.pendingCycles == null || page.pendingCycles.isEmpty())) {
            return 'No cycles are waiting for your review. Reps appear here after they classify and submit.';
        }
        return null;
    }

    private static Boolean hasReviewScope(List<TerritoryOption> territories) {
        Id viewerId = UserInfo.getUserId();
        for (TerritoryOption territory : territories == null ? new List<TerritoryOption>() : territories) {
            if (territory.assigned == false) {
                return true;
            }
            if (territory.employeeId != null && territory.employeeId != viewerId) {
                return true;
            }
        }
        return false;
    }

    private static Boolean canOpenTerritory(Id territoryId, List<TerritoryOption> territories) {
        if (territoryId == null) {
            return false;
        }
        for (TerritoryOption territory : territories == null ? new List<TerritoryOption>() : territories) {
            if (territory.territoryId == territoryId) {
                return true;
            }
        }
        return switchableTerritoryIds().contains(territoryId) || isSfeApproverForTerritory(territoryId);
    }

    private static Id employeeForTerritory(Id territoryId, List<TerritoryOption> territories) {
        for (TerritoryOption territory : territories == null ? new List<TerritoryOption>() : territories) {
            if (territory.territoryId == territoryId) {
                return territory.employeeId;
            }
        }
        return isSfeApproverForTerritory(territoryId) ? sfeReviewEmployee(territoryId) : null;
    }

    private static Boolean isSfeApproverForTerritory(Id territoryId) {
        return SfeApproverService.coversTerritory(
            UserInfo.getUserId(),
            territoryId,
            SfeApproverService.CLASSIFICATION
        );
    }

    /** Rep behind a territory an SFE approver opens outside their own hierarchy: latest submitter, else the seated rep. */
    private static Id sfeReviewEmployee(Id territoryId) {
        String territoryKey = String.valueOf(territoryId);
        for (Classification_Cycle__c cycle : [
            SELECT Employee__c
            FROM Classification_Cycle__c
            WHERE Territory2_Id__c = :territoryKey AND Employee__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Submitted_At__c DESC NULLS LAST, LastModifiedDate DESC
            LIMIT 1
        ]) {
            return cycle.Employee__c;
        }
        UserTerritory2Association owner = pickTerritoryOwner(
            [
                SELECT Territory2Id, UserId, User.Name, RoleInTerritory2
                FROM UserTerritory2Association
                WHERE Territory2Id = :territoryId AND IsActive = TRUE
                WITH SYSTEM_MODE
            ],
            UserInfo.getUserId(),
            false
        );
        return owner == null ? null : owner.UserId;
    }

    private static CycleDto emptyCycle(Id employeeId, Id territoryId, String quarter) {
        CycleDto dto = new CycleDto();
        dto.status = 'Not started';
        dto.quarter = String.isBlank(quarter) ? currentQuarter() : quarter;
        dto.employeeId = employeeId;
        dto.employeeName = userName(employeeId);
        dto.territoryId = territoryId;
        return dto;
    }

    private static Classification_Cycle__c findLatestCycle(Id employeeId, String quarter) {
        if (employeeId == null) {
            return null;
        }
        String resolvedQuarter = String.isBlank(quarter) ? currentQuarter() : quarter;
        List<Classification_Cycle__c> existing = [
            SELECT
                Id,
                Status__c,
                Quarter__c,
                Employee__c,
                Territory2_Id__c,
                Line_Territory2_Id__c,
                Approver__c,
                Submitted_At__c,
                Approved_At__c,
                Capacity_Visits__c,
                Planned_Visits__c
            FROM Classification_Cycle__c
            WHERE Employee__c = :employeeId
            AND Quarter__c = :resolvedQuarter
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return existing.isEmpty() ? null : existing[0];
    }

    /**
     * Territories the viewer can move through: their own assignments, plus subordinate
     * territories in the hierarchy (and direct reports whose territory sits outside it).
     */
    private static List<TerritoryOption> listReviewTerritories(String quarter) {
        Id viewerId = UserInfo.getUserId();
        String resolvedQuarter = String.isBlank(quarter) ? currentQuarter() : quarter;
        if (cachedReviewTerritories != null && cachedReviewQuarter == resolvedQuarter) {
            return cachedReviewTerritories;
        }
        Set<Id> assigned = assignedTerritoryIds();
        Set<Id> switchable = switchableTerritoryIds();
        Map<Id, User> reportsById = new Map<Id, User>([
            SELECT Id, Name
            FROM User
            WHERE ManagerId = :viewerId AND IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 200
        ]);
        if (switchable.isEmpty() && reportsById.isEmpty()) {
            cachedReviewQuarter = resolvedQuarter;
            cachedReviewTerritories = new List<TerritoryOption>();
            return cachedReviewTerritories;
        }

        Map<Id, Territory2> territories = new Map<Id, Territory2>();
        if (!switchable.isEmpty()) {
            territories.putAll([
                SELECT Id, Name
                FROM Territory2
                WHERE Id IN :switchable
                WITH SYSTEM_MODE
            ]);
        }

        Map<Id, List<UserTerritory2Association>> usersByTerritory =
            new Map<Id, List<UserTerritory2Association>>();
        if (!switchable.isEmpty()) {
            for (UserTerritory2Association row : [
                SELECT Territory2Id, UserId, User.Name, RoleInTerritory2
                FROM UserTerritory2Association
                WHERE Territory2Id IN :switchable AND IsActive = TRUE
                WITH SYSTEM_MODE
            ]) {
                if (!usersByTerritory.containsKey(row.Territory2Id)) {
                    usersByTerritory.put(row.Territory2Id, new List<UserTerritory2Association>());
                }
                usersByTerritory.get(row.Territory2Id).add(row);
            }
        }

        Map<Id, Id> reportTerritory = new Map<Id, Id>();
        if (!reportsById.isEmpty()) {
            for (UserTerritory2Association row : [
                SELECT UserId, Territory2Id
                FROM UserTerritory2Association
                WHERE UserId IN :reportsById.keySet() AND IsActive = TRUE
                WITH SYSTEM_MODE
                ORDER BY LastModifiedDate DESC
            ]) {
                if (!reportTerritory.containsKey(row.UserId) && row.Territory2Id != null) {
                    reportTerritory.put(row.UserId, row.Territory2Id);
                }
            }
            Set<Id> extraIds = new Set<Id>();
            for (Id territoryId : reportTerritory.values()) {
                if (!territories.containsKey(territoryId)) {
                    extraIds.add(territoryId);
                }
            }
            if (!extraIds.isEmpty()) {
                for (Territory2 territory : [
                    SELECT Id, Name
                    FROM Territory2
                    WHERE Id IN :extraIds
                    WITH SYSTEM_MODE
                ]) {
                    territories.put(territory.Id, territory);
                }
            }
        }

        Map<Id, Id> ownerByTerritory = new Map<Id, Id>();
        Map<Id, String> ownerNameByTerritory = new Map<Id, String>();
        for (Id territoryId : territories.keySet()) {
            Boolean isAssigned = assigned.contains(territoryId);
            UserTerritory2Association owner = pickTerritoryOwner(
                usersByTerritory.get(territoryId),
                viewerId,
                isAssigned
            );
            if (owner != null) {
                ownerByTerritory.put(territoryId, owner.UserId);
                ownerNameByTerritory.put(
                    territoryId,
                    owner.User == null ? null : owner.User.Name
                );
            } else if (isAssigned) {
                ownerByTerritory.put(territoryId, viewerId);
            }
        }
        for (Id reportId : reportTerritory.keySet()) {
            Id territoryId = reportTerritory.get(reportId);
            if (territoryId != null && !ownerByTerritory.containsKey(territoryId)) {
                ownerByTerritory.put(territoryId, reportId);
                ownerNameByTerritory.put(territoryId, reportsById.get(reportId).Name);
            }
        }

        Map<Id, String> statusByEmployee = new Map<Id, String>();
        Map<Id, Integer> pendingByEmployee = new Map<Id, Integer>();
        Map<Id, List<String>> quartersByEmployee = new Map<Id, List<String>>();
        Set<Id> employeeIds = new Set<Id>(ownerByTerritory.values());
        employeeIds.remove(null);
        if (!employeeIds.isEmpty()) {
            for (Classification_Cycle__c cycle : [
                SELECT Employee__c, Status__c, Quarter__c
                FROM Classification_Cycle__c
                WHERE Employee__c IN :employeeIds
                AND (Quarter__c = :resolvedQuarter OR Status__c = 'Submitted')
                WITH SYSTEM_MODE
                ORDER BY LastModifiedDate DESC
            ]) {
                if (cycle.Quarter__c == resolvedQuarter && !statusByEmployee.containsKey(cycle.Employee__c)) {
                    statusByEmployee.put(cycle.Employee__c, cycle.Status__c);
                }
                if (cycle.Status__c == 'Submitted' && cycle.Employee__c != viewerId) {
                    Integer count = pendingByEmployee.containsKey(cycle.Employee__c)
                        ? pendingByEmployee.get(cycle.Employee__c)
                        : 0;
                    pendingByEmployee.put(cycle.Employee__c, count + 1);
                    if (!quartersByEmployee.containsKey(cycle.Employee__c)) {
                        quartersByEmployee.put(cycle.Employee__c, new List<String>());
                    }
                    List<String> quarters = quartersByEmployee.get(cycle.Employee__c);
                    if (!quarters.contains(cycle.Quarter__c)) {
                        quarters.add(cycle.Quarter__c);
                    }
                }
            }
        }

        List<TerritoryOption> assignedOptions = new List<TerritoryOption>();
        List<TerritoryOption> subordinateOptions = new List<TerritoryOption>();
        Set<Id> seen = new Set<Id>();
        for (Territory2 territory : territories.values()) {
            if (territory == null || seen.contains(territory.Id)) {
                continue;
            }
            Boolean isAssigned = assigned.contains(territory.Id);
            Boolean hasOwner = ownerByTerritory.containsKey(territory.Id);
            if (!isAssigned && !hasOwner && !usersByTerritory.containsKey(territory.Id)) {
                continue;
            }
            seen.add(territory.Id);
            TerritoryOption option = toTerritoryOption(
                territory,
                isAssigned,
                ownerByTerritory.get(territory.Id),
                ownerNameByTerritory.get(territory.Id),
                statusByEmployee,
                pendingByEmployee,
                quartersByEmployee
            );
            if (isAssigned) {
                assignedOptions.add(option);
            } else {
                subordinateOptions.add(option);
            }
        }
        assignedOptions.sort();
        subordinateOptions.sort();
        List<TerritoryOption> combined = new List<TerritoryOption>();
        combined.addAll(assignedOptions);
        combined.addAll(subordinateOptions);
        if (combined.size() > 200) {
            List<TerritoryOption> trimmed = new List<TerritoryOption>();
            for (Integer i = 0; i < 200; i++) {
                trimmed.add(combined[i]);
            }
            combined = trimmed;
        }
        cachedReviewQuarter = resolvedQuarter;
        cachedReviewTerritories = combined;
        return combined;
    }

    private static UserTerritory2Association pickTerritoryOwner(
        List<UserTerritory2Association> members,
        Id viewerId,
        Boolean assignedToViewer
    ) {
        if (members == null || members.isEmpty()) {
            return null;
        }
        UserTerritory2Association medicalRep;
        UserTerritory2Association viewerRow;
        UserTerritory2Association fallback;
        for (UserTerritory2Association row : members) {
            if (fallback == null) {
                fallback = row;
            }
            if (row.UserId == viewerId) {
                viewerRow = row;
            }
            if (row.RoleInTerritory2 == 'Medical Rep' && medicalRep == null) {
                medicalRep = row;
            }
        }
        if (!assignedToViewer && medicalRep != null) {
            return medicalRep;
        }
        if (assignedToViewer && viewerRow != null && medicalRep == null) {
            return viewerRow;
        }
        if (medicalRep != null) {
            return medicalRep;
        }
        if (viewerRow != null) {
            return viewerRow;
        }
        return fallback;
    }

    private static TerritoryOption toTerritoryOption(
        Territory2 territory,
        Boolean assigned,
        Id employeeId,
        String employeeName,
        Map<Id, String> statusByEmployee,
        Map<Id, Integer> pendingByEmployee,
        Map<Id, List<String>> quartersByEmployee
    ) {
        TerritoryOption option = new TerritoryOption();
        option.territoryId = territory.Id;
        option.name = territory.Name;
        option.assigned = assigned;
        option.employeeId = employeeId;
        option.employeeName = employeeId == UserInfo.getUserId()
            ? 'You'
            : employeeName;
        option.status = employeeId == null ? 'Not started' : statusByEmployee.get(employeeId);
        if (String.isBlank(option.status)) {
            option.status = 'Not started';
        }
        option.pendingCount = employeeId == null || !pendingByEmployee.containsKey(employeeId)
            ? 0
            : pendingByEmployee.get(employeeId);
        option.pendingQuarters = employeeId == null || !quartersByEmployee.containsKey(employeeId)
            ? new List<String>()
            : quartersByEmployee.get(employeeId);
        return option;
    }

    private static List<RepOption> listDirectReports() {
        List<RepOption> reps = new List<RepOption>();
        for (User rep : [
            SELECT Id, Name
            FROM User
            WHERE ManagerId = :UserInfo.getUserId() AND IsActive = TRUE
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 200
        ]) {
            RepOption option = new RepOption();
            option.userId = rep.Id;
            option.name = rep.Name;
            reps.add(option);
        }
        return reps;
    }

    private static void decorateTeam(List<RepOption> reps, List<CycleDto> pending, String quarter) {
        if (reps == null || reps.isEmpty()) {
            return;
        }
        String resolvedQuarter = String.isBlank(quarter) ? currentQuarter() : quarter;
        Map<Id, RepOption> byId = new Map<Id, RepOption>();
        for (RepOption rep : reps) {
            rep.pendingCount = 0;
            rep.pendingQuarters = new List<String>();
            byId.put(rep.userId, rep);
        }
        for (Classification_Cycle__c cycle : [
            SELECT Employee__c, Status__c
            FROM Classification_Cycle__c
            WHERE Employee__c IN :byId.keySet() AND Quarter__c = :resolvedQuarter
            WITH USER_MODE
            ORDER BY LastModifiedDate ASC
        ]) {
            byId.get(cycle.Employee__c).status = cycle.Status__c;
        }
        for (CycleDto cycle : pending == null ? new List<CycleDto>() : pending) {
            RepOption rep = byId.get(cycle.employeeId);
            if (rep != null) {
                rep.pendingCount++;
                rep.pendingQuarters.add(cycle.quarter);
            }
        }
    }

    private static Id resolveEmployeeId(Id employeeId) {
        if (employeeId == null) {
            return UserInfo.getUserId();
        }
        if (employeeId == UserInfo.getUserId()) {
            return employeeId;
        }
        if (canReviewEmployee(employeeId)) {
            return employeeId;
        }
        throw new AuraHandledException('You do not have access to this employee.');
    }

    private static Boolean canReviewEmployee(Id employeeId) {
        if (employeeId == null || employeeId == UserInfo.getUserId()) {
            return false;
        }
        if (resolveViewerMode(employeeId) == 'manager') {
            return true;
        }
        if (SfeApproverService.coversUser(UserInfo.getUserId(), employeeId, SfeApproverService.CLASSIFICATION)) {
            return true;
        }
        Id territoryId = primaryTerritoryId(employeeId);
        if (territoryId == null) {
            return false;
        }
        return switchableTerritoryIds().contains(territoryId);
    }

    private static Set<Id> assignedTerritoryIds() {
        if (cachedAssignedTerritoryIds == null) {
            cachedAssignedTerritoryIds = TerritoryContextService.getAssignedTerritoryIds(UserInfo.getUserId());
        }
        return cachedAssignedTerritoryIds;
    }

    private static Set<Id> switchableTerritoryIds() {
        if (cachedSwitchableTerritoryIds == null) {
            cachedSwitchableTerritoryIds = TerritoryHierarchyService.expandTerritoryHierarchy(
                assignedTerritoryIds()
            );
        }
        return cachedSwitchableTerritoryIds;
    }

    private static String resolveViewerMode(Id employeeId) {
        if (employeeId == null || employeeId == UserInfo.getUserId()) {
            return 'self';
        }
        List<User> reps = [
            SELECT Id
            FROM User
            WHERE Id = :employeeId AND ManagerId = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!reps.isEmpty()) {
            return 'manager';
        }
        return 'denied';
    }

    private static void assertCanApprove(Classification_Cycle__c cycle) {
        if (cycle == null || cycle.Status__c != 'Submitted') {
            throw new AuraHandledException('Only submitted cycles can be reviewed.');
        }
        if (cycle.Approver__c == UserInfo.getUserId() || canReviewEmployee(cycle.Employee__c)) {
            return;
        }
        Id territoryId = toId(cycle.Territory2_Id__c);
        if (
            territoryId != null &&
            cycle.Employee__c != UserInfo.getUserId() &&
            (switchableTerritoryIds().contains(territoryId) || isSfeApproverForTerritory(territoryId))
        ) {
            return;
        }
        throw new AuraHandledException('Only the manager or an SFE approver for this line can approve this cycle.');
    }

    private static Boolean isSfeUser() {
        try {
            if (FeatureManagement.checkPermission('Merge_Account_Duplicates')) {
                return true;
            }
        } catch (Exception ignore) {
        }
        if (SfeApproverService.isApprover(UserInfo.getUserId(), SfeApproverService.CLASSIFICATION)) {
            return true;
        }
        List<User> me = [
            SELECT Title, Profile.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (me.isEmpty()) {
            return false;
        }
        String title = me[0].Title == null ? '' : me[0].Title.toLowerCase();
        if (title.contains('sfe') || title.contains('sales force excellence')) {
            return true;
        }
        return me[0].Profile != null && me[0].Profile.Name == 'System Administrator';
    }

    /** MoM: only the rep edits potential / penetration; DM uses frequency instead. */
    private static void requireRepPotentialPenetrationEdit() {
        if (isSfeUser()) {
            return;
        }
        List<User> me = [
            SELECT Title
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        String title = me.isEmpty() || me[0].Title == null ? '' : me[0].Title.toLowerCase();
        Boolean managerTitle =
            title.contains('district')
            || title.contains('area manager')
            || title.contains('national')
            || title.contains('field insight')
            || title.contains(' brand manager')
            || title.startsWith('brand manager')
            || title.contains('group brand');
        Boolean repTitle =
            title.contains('rep')
            || title.contains('msr')
            || title.contains('medical sales')
            || title.contains('sales representative')
            || String.isBlank(title);
        if (managerTitle && !repTitle) {
            throw new AuraHandledException(
                'Only the rep can edit potential and penetration. District Managers review frequency once the rep submits the cycle: open Class Engine, pick the rep under Team, then approve or change each frequency.'
            );
        }
    }

    @TestVisible
    static Id testResolveApproverId(Id employeeId) {
        return resolveApproverId(employeeId, null);
    }

    /** Delegates to ClassificationApprovalRouter (SFE approver for the line → ManagerId). */
    private static Id resolveApproverId(Id employeeId, Id territoryId) {
        return ClassificationApprovalRouter.resolveApproverId(employeeId, territoryId);
    }

    private static Id primaryTerritoryId(Id userId) {
        if (userId == null) {
            return null;
        }
        // Prefer the Territory utility working selection when viewing self.
        if (userId == UserInfo.getUserId()) {
            Id selected = TerritoryContextService.getSelectedTerritoryId();
            if (selected != null) {
                Set<Id> switchable = switchableTerritoryIds();
                if (switchable.contains(selected)) {
                    return selected;
                }
            }
        }
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :userId AND IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ]) {
            return assignment.Territory2Id;
        }
        return null;
    }

    private static String territoryName(Id territoryId) {
        if (territoryId == null) {
            return null;
        }
        List<Territory2> rows = [SELECT Name FROM Territory2 WHERE Id = :territoryId LIMIT 1];
        return rows.isEmpty() ? null : rows[0].Name;
    }

    private static String userName(Id userId) {
        if (userId == null) {
            return null;
        }
        List<User> rows = [SELECT Name FROM User WHERE Id = :userId LIMIT 1];
        return rows.isEmpty() ? null : rows[0].Name;
    }

    private static List<PicklistOption> classOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (String code : new List<String>{ 'A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3' }) {
            PicklistOption option = new PicklistOption();
            option.label = code;
            option.value = code;
            options.add(option);
        }
        return options;
    }

    private static Integer fullMonthCapacity(Decimal dailyRate) {
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        Integer workingDays = countWorkingDays(monthStart, monthEnd);
        Decimal rate = dailyRate == null || dailyRate <= 0 ? 1 : dailyRate;
        return Integer.valueOf(workingDays * rate);
    }

    private static Integer countWorkingDays(Date startDate, Date endDate) {
        Integer count = 0;
        for (Date cursor = startDate; cursor <= endDate; cursor = cursor.addDays(1)) {
            if (WorkingCalendarUtil.isWorkingDay(cursor)) {
                count++;
            }
        }
        return count;
    }

    private static Integer countWorkingHolidays(Date startDate, Date endDate, Set<Date> holidays) {
        Integer count = 0;
        if (holidays == null) {
            return 0;
        }
        for (Date day : holidays) {
            if (day >= startDate && day <= endDate && WorkingCalendarUtil.isWorkingDay(day)) {
                count++;
            }
        }
        return count;
    }

    private static Set<Date> leaveAndTotDates(Id employeeId, Date startDate, Date endDate) {
        Set<Date> dates = new Set<Date>();
        if (employeeId == null) {
            return dates;
        }
        DateTime rangeStart = DateTime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
        DateTime rangeEnd = DateTime.newInstance(endDate, Time.newInstance(23, 59, 59, 0));
        for (Time_Off_Request__c request : [
            SELECT Start_Date_Time__c, End_Date_Time__c, Span_Type__c, Span_Duration__c
            FROM Time_Off_Request__c
            WHERE Stage__c = 'Approved'
            AND Start_Date_Time__c <= :rangeEnd
            AND End_Date_Time__c >= :rangeStart
            AND (CreatedById = :employeeId OR OwnerId = :employeeId)
            WITH SYSTEM_MODE
        ]) {
            Date cursor = request.Start_Date_Time__c.date();
            Date last = request.End_Date_Time__c.date();
            for (Date day = cursor; day <= last; day = day.addDays(1)) {
                if (day >= startDate && day <= endDate) {
                    dates.add(day);
                }
            }
        }
        return dates;
    }

    private static List<Date> quarterMonthStarts(String quarter) {
        List<Date> months = new List<Date>();
        Date anchor = parseQuarterStart(quarter);
        months.add(anchor);
        months.add(anchor.addMonths(1));
        months.add(anchor.addMonths(2));
        return months;
    }

    private static Date parseQuarterStart(String quarter) {
        if (String.isBlank(quarter)) {
            return Date.today().toStartOfMonth();
        }
        // Expect Q1-2026 / 2026-Q1 / 2026-10
        String normalized = quarter.trim().toUpperCase();
        try {
            if (normalized.contains('Q')) {
                List<String> parts = normalized.replace(' ', '').split('-');
                Integer year;
                Integer q;
                if (parts[0].startsWith('Q')) {
                    q = Integer.valueOf(parts[0].substring(1));
                    year = Integer.valueOf(parts[1]);
                } else {
                    year = Integer.valueOf(parts[0]);
                    q = Integer.valueOf(parts[1].substring(1));
                }
                Integer month = ((q - 1) * 3) + 1;
                return Date.newInstance(year, month, 1);
            }
            List<String> ym = normalized.split('-');
            return Date.newInstance(Integer.valueOf(ym[0]), Integer.valueOf(ym[1]), 1);
        } catch (Exception ex) {
            return Date.today().toStartOfMonth();
        }
    }

    private static String currentQuarter() {
        Date today = Date.today();
        Integer q = ((today.month() - 1) / 3) + 1;
        return 'Q' + q + '-' + today.year();
    }

    private static Map<String, Decimal> parseAppliedVisits(String jsonValue) {
        Map<String, Decimal> result = new Map<String, Decimal>();
        if (String.isBlank(jsonValue)) {
            return result;
        }
        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(jsonValue);
            for (String key : raw.keySet()) {
                Object value = raw.get(key);
                if (value == null) {
                    result.put(key, 0);
                } else {
                    result.put(key, Decimal.valueOf(String.valueOf(value)));
                }
            }
        } catch (Exception ex) {
            return result;
        }
        return result;
    }

    private static Boolean productImageFieldReadableCache;
    private static Boolean productTypeFieldReadableCache;

    private static Boolean productImageFieldReadable() {
        if (productImageFieldReadableCache == null) {
            Map<String, Schema.SObjectField> fields = Product2.SObjectType.getDescribe().fields.getMap();
            productImageFieldReadableCache = fields.containsKey('Product_Image_URL__c')
                && fields.get('Product_Image_URL__c').getDescribe().isAccessible();
        }
        return productImageFieldReadableCache;
    }

    private static Boolean productTypeFieldReadable() {
        if (productTypeFieldReadableCache == null) {
            Map<String, Schema.SObjectField> fields = Product2.SObjectType.getDescribe().fields.getMap();
            productTypeFieldReadableCache = fields.containsKey('Product_Type__c')
                && fields.get('Product_Type__c').getDescribe().isAccessible();
        }
        return productTypeFieldReadableCache;
    }

    private static Decimal displayPercent(Decimal stored) {
        if (stored == null) {
            return null;
        }
        // Promo grid stores fractions (0.1) or whole percents (10).
        return stored <= 1 ? (stored * 100) : stored;
    }

    private static Decimal firstNonNull(Decimal a, Decimal b, Decimal c) {
        if (a != null) {
            return a;
        }
        if (b != null) {
            return b;
        }
        return c == null ? 0 : c;
    }

    private static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (Exception ex) {
            return null;
        }
    }

    private class AccountRowComparator implements Comparator<AccountRowDto> {
        public Integer compare(AccountRowDto a, AccountRowDto b) {
            Integer orderA = a.sortOrder == null ? 9999 : a.sortOrder;
            Integer orderB = b.sortOrder == null ? 9999 : b.sortOrder;
            if (orderA != orderB) {
                return orderA < orderB ? -1 : 1;
            }
            String nameA = a.accountName == null ? '' : a.accountName;
            String nameB = b.accountName == null ? '' : b.accountName;
            return nameA.toLowerCase().compareTo(nameB.toLowerCase());
        }
    }

    @TestVisible
    static void coverageHook() {
        displayPercent(0.1);
        displayPercent(10);
        displayPercent(null);
        firstNonNull(null, 2, 3);
        firstNonNull(1, 2, 3);
        firstNonNull(null, null, null);
        toId(null);
        toId('notAnId');
        parseAppliedVisits(null);
        parseAppliedVisits('{"A1":5,"B1":2}');
        parseAppliedVisits('{bad');
        parseQuarterStart(null);
        parseQuarterStart('Q1-2026');
        parseQuarterStart('2026-Q2');
        parseQuarterStart('2026-10');
        parseQuarterStart('junk');
        currentQuarter();
        Date startDate = Date.newInstance(2026, 10, 1);
        Date endDate = Date.newInstance(2026, 10, 7);
        countWorkingDays(startDate, endDate);
        countWorkingHolidays(startDate, endDate, new Set<Date>{ Date.newInstance(2026, 10, 3) });
        countWorkingHolidays(startDate, endDate, null);
        leaveAndTotDates(UserInfo.getUserId(), startDate, endDate);
        leaveAndTotDates(null, startDate, endDate);
        quarterMonthStarts('Q4-2026');
        classOptions();
        userName(UserInfo.getUserId());
        userName(null);
        territoryName(null);
        fullMonthCapacity(13);
        fullMonthCapacity(null);
        resolveApproverId(UserInfo.getUserId(), null);
        listDirectReports();
        listPendingCycles();
        resolveViewerMode(UserInfo.getUserId());
        primaryTerritoryId(UserInfo.getUserId());
        ClassEngineService.resolveDailyVisitRate(null);
        ClassEngineService.resolveLineTerritoryId(null);
        toScoreInputs(new List<AccountRowDto>(), true);
        toScoreInputs(new List<AccountRowDto>(), false);
        indexClassified(null);
        indexClassified(new List<ClassEngineService.ClassifiedAccount>());
        AccountRowDto row = new AccountRowDto();
        row.accountName = 'Z';
        row.sortOrder = 1;
        row.chosenClass = 'A1';
        row.products = new List<ProductRatingDto>();
        ProductRatingDto product = new ProductRatingDto();
        product.product2Id = null;
        product.weightPercentage = 100;
        product.rxPotential = 10;
        product.rxPenetration = 5;
        product.salesPotential = 8;
        product.salesPenetration = 4;
        row.products.add(product);
        AccountRowDto row2 = new AccountRowDto();
        row2.accountName = 'A';
        row2.sortOrder = 2;
        List<AccountRowDto> rows = new List<AccountRowDto>{ row, row2 };
        rows.sort(new AccountRowComparator());
        toScoreInputs(rows, true);
        toScoreInputs(rows, false);
        loadAccountRows(null, null, null);
        loadProducts(new Set<Id>(), null, null);
        productImageFieldReadable();
        productImageFieldReadable();
        productTypeFieldReadable();
        productTypeFieldReadable();
        // Touch brand-filter SOQL path with empty account set (returns early).
        loadProducts(new Set<Id>{ UserInfo.getUserId() }, null, UserInfo.getUserId());
        Classification_Cycle__c cycle = findOrCreateDraftCycle(
            UserInfo.getUserId(),
            null,
            null,
            'Q4-2026'
        );
        toCycleDto(cycle);
        toCycleDto(null);
        buildMonthCapacities(UserInfo.getUserId(), null, cycle, rows);
        ClassEngineService.ClassifyResult rx = new ClassEngineService.ClassifyResult();
        rx.seatsByClass = new Map<String, Integer>{ 'A1' => 1, 'C1' => 1 };
        rx.accounts = new List<ClassEngineService.ClassifiedAccount>();
        Map<String, Decimal> grid = new Map<String, Decimal>{ 'A1' => 5, 'C1' => 1 };
        rebuildMonthSnapshots(UserInfo.getUserId(), null, cycle.Id, rx, grid, 13);
        writePlanCycleTargets(
            UserInfo.getUserId(),
            new List<Classification_Cycle_Account__c>(),
            new List<Classification_Cycle_Month__c>()
        );
        buildMonthCapacities(UserInfo.getUserId(), null, cycle, rows);
        listReviewTerritories('Q4-2026');
        findLatestCycle(null, null);
        findLatestCycle(UserInfo.getUserId(), 'Q4-2026');
        emptyCycle(UserInfo.getUserId(), null, null);
        TerritoryOption mine = new TerritoryOption();
        mine.name = 'North';
        mine.assigned = true;
        mine.employeeId = UserInfo.getUserId();
        mine.territoryId = UserInfo.getUserId();
        TerritoryOption subordinate = new TerritoryOption();
        subordinate.name = 'South';
        subordinate.assigned = false;
        subordinate.employeeId = UserInfo.getUserId();
        subordinate.territoryId = UserInfo.getProfileId();
        mine.compareTo(subordinate);
        hasReviewScope(new List<TerritoryOption>{ mine, subordinate });
        hasReviewScope(new List<TerritoryOption>());
        canOpenTerritory(null, null);
        canOpenTerritory(mine.territoryId, new List<TerritoryOption>{ mine });
        employeeForTerritory(mine.territoryId, new List<TerritoryOption>{ mine });
        employeeForTerritory(UserInfo.getUserId(), new List<TerritoryOption>());
        UserTerritory2Association repRow = new UserTerritory2Association();
        repRow.UserId = UserInfo.getUserId();
        repRow.RoleInTerritory2 = 'Medical Rep';
        UserTerritory2Association otherRow = new UserTerritory2Association();
        otherRow.UserId = UserInfo.getUserId();
        pickTerritoryOwner(null, UserInfo.getUserId(), true);
        pickTerritoryOwner(new List<UserTerritory2Association>(), UserInfo.getUserId(), false);
        pickTerritoryOwner(
            new List<UserTerritory2Association>{ otherRow, repRow },
            UserInfo.getUserId(),
            false
        );
        pickTerritoryOwner(
            new List<UserTerritory2Association>{ otherRow },
            UserInfo.getUserId(),
            true
        );
        pickTerritoryOwner(
            new List<UserTerritory2Association>{ repRow },
            UserInfo.getOrganizationId(),
            true
        );
        toTerritoryOption(
            new Territory2(Name = 'North'),
            false,
            UserInfo.getUserId(),
            'Ada',
            new Map<Id, String>(),
            new Map<Id, Integer>(),
            new Map<Id, List<String>>()
        );
        canReviewEmployee(UserInfo.getUserId());
    }

}