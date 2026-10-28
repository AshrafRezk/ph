/**
 * Idempotent worked example for distributor digestion (Oct 14 meeting order):
 * doctor class change, affiliated pharmacies on one brick, ceiling split to bulk,
 * bulk share, and original/buffer target with shortage.
 */
public with sharing class SalesDigestionExampleService {
    private static final String KEY_PREFIX = 'DIGEST_EX_';
    private static final String SALES_LINE = 'GIT';
    private static final Decimal RAW_CEILING_PHARMACY = 250;
    private static final Decimal RAW_EXCLUDED_PHARMACY = 100;
    private static final Decimal ORIGINAL_TARGET = 700;
    private static final Decimal BUFFER_TARGET = 1000;
    private static final Decimal ATTAINED = 850;

    private static Decimal ceilingCap() {
        SalesPolicyService.Policy policy = SalesPolicyService.getOrgPolicy();
        return policy.ceilingCap == null ? 200 : policy.ceilingCap;
    }

    private static Decimal actualSharePct() {
        SalesPolicyService.Policy policy = SalesPolicyService.getOrgPolicy();
        // Policy stores a percent (100 means 100%). Keep it a percent here; /100 happens once, in the bulk-share maths.
        return policy.actualSharePct == null ? 100 : policy.actualSharePct;
    }

    private static Decimal targetSharePct() {
        SalesPolicyService.Policy policy = SalesPolicyService.getOrgPolicy();
        return policy.targetSharePct == null ? 50 : policy.targetSharePct;
    }

    public class DigestionExample {
        @AuraEnabled public Boolean seeded;
        @AuraEnabled public String message;
        @AuraEnabled public String doctorName;
        @AuraEnabled public String productName;
        @AuraEnabled public String brickName;
        @AuraEnabled public String lastMonthClass;
        @AuraEnabled public String thisMonthClass;
        @AuraEnabled public String reportMonthLabel;
        @AuraEnabled public Decimal ceilingCap;
        @AuraEnabled public Decimal totalBulk;
        @AuraEnabled public Decimal actualSharePct;
        @AuraEnabled public Decimal targetSharePct;
        @AuraEnabled public Decimal averageSharePct;
        @AuraEnabled public Decimal bulkShareQty;
        @AuraEnabled public Decimal originalTarget;
        @AuraEnabled public Decimal bufferTarget;
        @AuraEnabled public Decimal attained;
        @AuraEnabled public Decimal effectiveTargetShortageOff;
        @AuraEnabled public Decimal effectiveTargetShortageOn;
        @AuraEnabled public List<PharmacyStep> pharmacies;
        @AuraEnabled public List<String> steps;
    }

    public class PharmacyStep {
        @AuraEnabled public String pharmacyName;
        @AuraEnabled public Boolean excludeFromCeiling;
        @AuraEnabled public Decimal rawQty;
        @AuraEnabled public Decimal retainedQty;
        @AuraEnabled public Decimal bulkQty;
        @AuraEnabled public String note;
    }

    @AuraEnabled
    public static DigestionExample seedExample() {
        FieldBookAccess.assertCanAdministerSales();
        SeedContext ctx = upsertSeedRecords();
        DigestionExample example = buildExample(ctx);
        example.seeded = true;
        example.message =
            'Digestion example loaded for ' +
            example.reportMonthLabel +
            '. Re-run is safe; keys are stable.';
        return example;
    }

    @AuraEnabled
    public static DigestionExample getExample() {
        FieldBookAccess.assertCanAdministerSales();
        List<Account> doctors = [
            SELECT Id, Name
            FROM Account
            WHERE External_ID__c = :KEY_PREFIX + 'DOC'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (doctors.isEmpty()) {
            DigestionExample empty = new DigestionExample();
            empty.seeded = false;
            empty.message = 'No digestion example yet. Press Load example.';
            empty.pharmacies = new List<PharmacyStep>();
            empty.steps = stepLabels();
            return empty;
        }
        SeedContext ctx = loadExistingContext();
        DigestionExample example = buildExample(ctx);
        example.seeded = true;
        example.message = 'Showing the saved digestion example.';
        return example;
    }

    private class SeedContext {
        public Account doctor;
        public Account pharmacyCeil;
        public Account pharmacyExcl;
        public Product2 product;
        public Brick__c brick;
        public Date thisMonth;
        public Date lastMonth;
        public String lastClass;
        public String thisClass;
        public Decimal totalBulk;
        public List<PharmacyStep> pharmacySteps;
    }

    private static SeedContext upsertSeedRecords() {
        SeedContext ctx = new SeedContext();
        ctx.thisMonth = Date.today().toStartOfMonth();
        ctx.lastMonth = ctx.thisMonth.addMonths(-1);
        ctx.lastClass = 'B1';
        ctx.thisClass = 'A2';

        Id pharmacyRt = recordTypeId('Pharmacy');

        Account doctor = new Account(
            Name = 'Ahmed Digestion Example Doctor',
            External_ID__c = KEY_PREFIX + 'DOC'
        );
        Database.upsert(doctor, Account.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        List<Account> doctorRows = [
            SELECT Id, Name
            FROM Account
            WHERE External_ID__c = :KEY_PREFIX + 'DOC'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (doctorRows.isEmpty()) {
            throw new AuraHandledException('Could not create the digestion example doctor account.');
        }
        ctx.doctor = doctorRows[0];

        Account pharmacyCeil = new Account(
            Name = 'Digestion Private Pharmacy',
            External_ID__c = KEY_PREFIX + 'PHARM_CEIL',
            Type = 'Pharmacy',
            Pharmacy_Type__c = 'Retail',
            Exclude_From_Item_Ceiling__c = false
        );
        if (pharmacyRt != null) {
            pharmacyCeil.RecordTypeId = pharmacyRt;
        }
        Account pharmacyExcl = new Account(
            Name = 'Digestion Excluded Pharmacy',
            External_ID__c = KEY_PREFIX + 'PHARM_EXCL',
            Type = 'Pharmacy',
            Pharmacy_Type__c = 'Retail',
            Exclude_From_Item_Ceiling__c = true
        );
        if (pharmacyRt != null) {
            pharmacyExcl.RecordTypeId = pharmacyRt;
        }
        Database.upsert(
            new List<Account>{ pharmacyCeil, pharmacyExcl },
            Account.External_ID__c,
            false,
            AccessLevel.SYSTEM_MODE
        );
        Map<String, Account> pharmaciesByExt = new Map<String, Account>();
        for (Account row : [
            SELECT Id, Name, External_ID__c, Exclude_From_Item_Ceiling__c
            FROM Account
            WHERE External_ID__c IN :new Set<String>{ KEY_PREFIX + 'PHARM_CEIL', KEY_PREFIX + 'PHARM_EXCL' }
            WITH SYSTEM_MODE
        ]) {
            pharmaciesByExt.put(row.External_ID__c, row);
        }
        ctx.pharmacyCeil = pharmaciesByExt.get(KEY_PREFIX + 'PHARM_CEIL');
        ctx.pharmacyExcl = pharmaciesByExt.get(KEY_PREFIX + 'PHARM_EXCL');
        if (ctx.pharmacyCeil == null || ctx.pharmacyExcl == null) {
            throw new AuraHandledException('Could not create the digestion example pharmacies.');
        }

        Product2 product = new Product2(
            Name = 'Nexicure Digestion Example',
            ProductCode = KEY_PREFIX + 'NEX',
            External_ID__c = KEY_PREFIX + 'NEX',
            IsActive = true,
            Family = 'GIT',
            Sales_Line__c = SALES_LINE
        );
        Database.upsert(product, Product2.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        List<Product2> productRows = [
            SELECT Id, Name, Sales_Line__c
            FROM Product2
            WHERE External_ID__c = :KEY_PREFIX + 'NEX'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (productRows.isEmpty()) {
            throw new AuraHandledException('Could not create the digestion example product.');
        }
        ctx.product = productRows[0];

        Brick__c brick = new Brick__c(
            Name = 'Digestion Example Brick',
            Brick_Code__c = KEY_PREFIX + 'BRICK',
            Is_Active__c = true
        );
        List<Brick__c> existingBricks = [
            SELECT Id, Name, Brick_Code__c
            FROM Brick__c
            WHERE Brick_Code__c = :KEY_PREFIX + 'BRICK'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (existingBricks.isEmpty()) {
            insert as system brick;
        } else {
            brick = existingBricks[0];
            brick.Name = 'Digestion Example Brick';
            brick.Is_Active__c = true;
            update as system brick;
        }
        ctx.brick = brick;

        upsertAffiliations(ctx);
        upsertBrickPharmacies(ctx);
        upsertSnapshots(ctx);
        upsertCeiling(ctx);
        ctx.pharmacySteps = upsertWithdrawals(ctx);
        upsertBrickShare(ctx);
        upsertItemTarget(ctx);
        ctx.totalBulk = 0;
        for (PharmacyStep step : ctx.pharmacySteps) {
            ctx.totalBulk += step.bulkQty == null ? 0 : step.bulkQty;
        }
        return ctx;
    }

    private static SeedContext loadExistingContext() {
        SeedContext ctx = new SeedContext();
        ctx.thisMonth = Date.today().toStartOfMonth();
        ctx.lastMonth = ctx.thisMonth.addMonths(-1);
        ctx.lastClass = 'B1';
        ctx.thisClass = 'A2';
        ctx.doctor = [
            SELECT Id, Name
            FROM Account
            WHERE External_ID__c = :KEY_PREFIX + 'DOC'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Map<String, Account> pharmaciesByExt = new Map<String, Account>();
        for (Account row : [
            SELECT Id, Name, External_ID__c, Exclude_From_Item_Ceiling__c
            FROM Account
            WHERE External_ID__c IN :new Set<String>{ KEY_PREFIX + 'PHARM_CEIL', KEY_PREFIX + 'PHARM_EXCL' }
            WITH SYSTEM_MODE
        ]) {
            pharmaciesByExt.put(row.External_ID__c, row);
        }
        ctx.pharmacyCeil = pharmaciesByExt.get(KEY_PREFIX + 'PHARM_CEIL');
        ctx.pharmacyExcl = pharmaciesByExt.get(KEY_PREFIX + 'PHARM_EXCL');
        ctx.product = [
            SELECT Id, Name, Sales_Line__c
            FROM Product2
            WHERE External_ID__c = :KEY_PREFIX + 'NEX'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        ctx.brick = [
            SELECT Id, Name, Brick_Code__c
            FROM Brick__c
            WHERE Brick_Code__c = :KEY_PREFIX + 'BRICK'
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        List<HCP_Product_Rating_Snapshot__c> snaps = [
            SELECT Classification__c, Snapshot_Month__c
            FROM HCP_Product_Rating_Snapshot__c
            WHERE External_ID__c IN :new Set<String>{ KEY_PREFIX + 'HPRS_PREV', KEY_PREFIX + 'HPRS_CUR' }
            WITH SYSTEM_MODE
        ];
        for (HCP_Product_Rating_Snapshot__c snap : snaps) {
            if (snap.Snapshot_Month__c == ctx.lastMonth) {
                ctx.lastClass = snap.Classification__c;
            } else if (snap.Snapshot_Month__c == ctx.thisMonth) {
                ctx.thisClass = snap.Classification__c;
            }
        }

        ctx.pharmacySteps = new List<PharmacyStep>();
        ctx.totalBulk = 0;
        for (Pharmacy_Sales_Withdrawal__c row : [
            SELECT
                Pharmacy_Account__r.Name,
                Pharmacy_Account__r.Exclude_From_Item_Ceiling__c,
                Quantity_Withdrawn__c,
                Quantity_Retained__c,
                Quantity_To_Bulk__c
            FROM Pharmacy_Sales_Withdrawal__c
            WHERE Unique_Key__c LIKE :(KEY_PREFIX + '%')
            WITH SYSTEM_MODE
            ORDER BY Pharmacy_Account__r.Name
        ]) {
            PharmacyStep step = new PharmacyStep();
            step.pharmacyName = row.Pharmacy_Account__r.Name;
            step.excludeFromCeiling = row.Pharmacy_Account__r.Exclude_From_Item_Ceiling__c == true;
            step.rawQty = row.Quantity_Withdrawn__c;
            step.retainedQty = row.Quantity_Retained__c;
            step.bulkQty = row.Quantity_To_Bulk__c;
            step.note = step.excludeFromCeiling
                ? 'Does not enter the ceiling — full quantity stays on the pharmacy.'
                : 'Ceiling ' + String.valueOf(ceilingCap()) + ' keeps ' +
                  String.valueOf(step.retainedQty) +
                  '; excess goes to bulk.';
            ctx.pharmacySteps.add(step);
            ctx.totalBulk += step.bulkQty == null ? 0 : step.bulkQty;
        }
        return ctx;
    }

    private static void upsertAffiliations(SeedContext ctx) {
        List<Account_Affiliation__c> rows = new List<Account_Affiliation__c>{
            new Account_Affiliation__c(
                Primary_Account__c = ctx.doctor.Id,
                Related_Account__c = ctx.pharmacyCeil.Id,
                Affiliation_Type__c = 'Affiliate',
                External_ID__c = KEY_PREFIX + 'AFF_CEIL',
                Is_Active__c = true,
                Is_Primary__c = true
            ),
            new Account_Affiliation__c(
                Primary_Account__c = ctx.doctor.Id,
                Related_Account__c = ctx.pharmacyExcl.Id,
                Affiliation_Type__c = 'Affiliate',
                External_ID__c = KEY_PREFIX + 'AFF_EXCL',
                Is_Active__c = true,
                Is_Primary__c = false
            )
        };
        Database.upsert(rows, Account_Affiliation__c.External_ID__c, false, AccessLevel.SYSTEM_MODE);
    }

    private static void upsertBrickPharmacies(SeedContext ctx) {
        List<Brick_Pharmacy__c> rows = new List<Brick_Pharmacy__c>{
            new Brick_Pharmacy__c(
                Brick__c = ctx.brick.Id,
                Pharmacy_Account__c = ctx.pharmacyCeil.Id,
                Is_Active__c = true,
                Unique_Key__c = String.valueOf(ctx.brick.Id) + '|' + String.valueOf(ctx.pharmacyCeil.Id)
            ),
            new Brick_Pharmacy__c(
                Brick__c = ctx.brick.Id,
                Pharmacy_Account__c = ctx.pharmacyExcl.Id,
                Is_Active__c = true,
                Unique_Key__c = String.valueOf(ctx.brick.Id) + '|' + String.valueOf(ctx.pharmacyExcl.Id)
            )
        };
        Database.upsert(rows, Brick_Pharmacy__c.Unique_Key__c, false, AccessLevel.SYSTEM_MODE);
    }

    private static void upsertSnapshots(SeedContext ctx) {
        List<HCP_Product_Rating_Snapshot__c> rows = new List<HCP_Product_Rating_Snapshot__c>{
            new HCP_Product_Rating_Snapshot__c(
                Account__c = ctx.doctor.Id,
                Product__c = ctx.product.Id,
                Snapshot_Month__c = ctx.lastMonth,
                Classification__c = ctx.lastClass,
                Classification_Score__c = 4,
                External_ID__c = KEY_PREFIX + 'HPRS_PREV'
            ),
            new HCP_Product_Rating_Snapshot__c(
                Account__c = ctx.doctor.Id,
                Product__c = ctx.product.Id,
                Snapshot_Month__c = ctx.thisMonth,
                Classification__c = ctx.thisClass,
                Classification_Score__c = 8,
                External_ID__c = KEY_PREFIX + 'HPRS_CUR'
            )
        };
        Database.upsert(
            rows,
            HCP_Product_Rating_Snapshot__c.External_ID__c,
            false,
            AccessLevel.SYSTEM_MODE
        );
    }

    private static void upsertCeiling(SeedContext ctx) {
        Item_Ceiling__c ceiling = new Item_Ceiling__c(
            Product__c = ctx.product.Id,
            Sales_Line__c = SALES_LINE,
            Role__c = 'Private',
            Cap_Quantity__c = ceilingCap(),
            Unique_Key__c = KEY_PREFIX + 'CEIL_PRIVATE'
        );
        Database.upsert(ceiling, Item_Ceiling__c.Unique_Key__c, false, AccessLevel.SYSTEM_MODE);
    }

    private static List<PharmacyStep> upsertWithdrawals(SeedContext ctx) {
        String monthKey =
            String.valueOf(ctx.thisMonth.year()) +
            '-' +
            String.valueOf(ctx.thisMonth.month()).leftPad(2, '0');

        Decimal retainCeil = Math.min(RAW_CEILING_PHARMACY, ceilingCap());
        Decimal bulkCeil = RAW_CEILING_PHARMACY - retainCeil;
        Decimal retainExcl = RAW_EXCLUDED_PHARMACY;
        Decimal bulkExcl = 0;

        List<Pharmacy_Sales_Withdrawal__c> rows = new List<Pharmacy_Sales_Withdrawal__c>{
            new Pharmacy_Sales_Withdrawal__c(
                Unique_Key__c =
                    'Direct|' + monthKey + '|' + ctx.pharmacyCeil.Id + '|' + ctx.product.Id,
                Data_Source__c = 'Direct',
                Report_Month__c = ctx.thisMonth,
                Pharmacy_Account__c = ctx.pharmacyCeil.Id,
                Product2_Id__c = String.valueOf(ctx.product.Id),
                Brick__c = ctx.brick.Id,
                Quantity_Withdrawn__c = RAW_CEILING_PHARMACY,
                Quantity_Retained__c = retainCeil,
                Quantity_To_Bulk__c = bulkCeil,
                Unit_Price__c = 10
            ),
            new Pharmacy_Sales_Withdrawal__c(
                Unique_Key__c =
                    'Direct|' + monthKey + '|' + ctx.pharmacyExcl.Id + '|' + ctx.product.Id,
                Data_Source__c = 'Direct',
                Report_Month__c = ctx.thisMonth,
                Pharmacy_Account__c = ctx.pharmacyExcl.Id,
                Product2_Id__c = String.valueOf(ctx.product.Id),
                Brick__c = ctx.brick.Id,
                Quantity_Withdrawn__c = RAW_EXCLUDED_PHARMACY,
                Quantity_Retained__c = retainExcl,
                Quantity_To_Bulk__c = bulkExcl,
                Unit_Price__c = 10
            )
        };
        Database.upsert(
            rows,
            Pharmacy_Sales_Withdrawal__c.Unique_Key__c,
            false,
            AccessLevel.SYSTEM_MODE
        );

        List<PharmacyStep> steps = new List<PharmacyStep>();
        PharmacyStep ceilStep = new PharmacyStep();
        ceilStep.pharmacyName = ctx.pharmacyCeil.Name;
        ceilStep.excludeFromCeiling = false;
        ceilStep.rawQty = RAW_CEILING_PHARMACY;
        ceilStep.retainedQty = retainCeil;
        ceilStep.bulkQty = bulkCeil;
        ceilStep.note =
            'Ceiling ' +
            String.valueOf(ceilingCap()) +
            ' keeps ' +
            String.valueOf(retainCeil) +
            '; ' +
            String.valueOf(bulkCeil) +
            ' go to bulk.';
        steps.add(ceilStep);

        PharmacyStep exclStep = new PharmacyStep();
        exclStep.pharmacyName = ctx.pharmacyExcl.Name;
        exclStep.excludeFromCeiling = true;
        exclStep.rawQty = RAW_EXCLUDED_PHARMACY;
        exclStep.retainedQty = retainExcl;
        exclStep.bulkQty = bulkExcl;
        exclStep.note = 'Does not enter the ceiling — full quantity stays on the pharmacy.';
        steps.add(exclStep);
        return steps;
    }

    private static void upsertBrickShare(SeedContext ctx) {
        Sales_Brick_Share__c share = new Sales_Brick_Share__c(
            Brick__c = ctx.brick.Id,
            Product__c = ctx.product.Id,
            Sales_Line__c = SALES_LINE,
            Actual_Contribution_Pct__c = actualSharePct(),
            Target_Contribution_Pct__c = targetSharePct(),
            Unique_Key__c = KEY_PREFIX + 'SHARE'
        );
        Database.upsert(share, Sales_Brick_Share__c.Unique_Key__c, false, AccessLevel.SYSTEM_MODE);
    }

    private static void upsertItemTarget(SeedContext ctx) {
        String monthKey =
            String.valueOf(ctx.thisMonth.year()) +
            '-' +
            String.valueOf(ctx.thisMonth.month()).leftPad(2, '0');
        Sales_Item_Target__c target = new Sales_Item_Target__c(
            Product__c = ctx.product.Id,
            Report_Month__c = ctx.thisMonth,
            Original_Target__c = ORIGINAL_TARGET,
            Buffer_Target__c = BUFFER_TARGET,
            Attained__c = ATTAINED,
            Shortage_Induced__c = false,
            Unique_Key__c = KEY_PREFIX + 'TARGET_' + monthKey
        );
        Database.upsert(target, Sales_Item_Target__c.Unique_Key__c, false, AccessLevel.SYSTEM_MODE);
    }

    private static DigestionExample buildExample(SeedContext ctx) {
        DigestionExample example = new DigestionExample();
        example.doctorName = ctx.doctor == null ? null : ctx.doctor.Name;
        example.productName = ctx.product == null ? null : ctx.product.Name;
        example.brickName = ctx.brick == null ? null : ctx.brick.Name;
        example.lastMonthClass = ctx.lastClass;
        example.thisMonthClass = ctx.thisClass;
        example.reportMonthLabel =
            ctx.thisMonth == null
                ? null
                : String.valueOf(ctx.thisMonth.year()) +
                  '-' +
                  String.valueOf(ctx.thisMonth.month()).leftPad(2, '0');
        example.ceilingCap = ceilingCap();
        example.pharmacies = ctx.pharmacySteps == null ? new List<PharmacyStep>() : ctx.pharmacySteps;
        example.totalBulk = ctx.totalBulk == null ? 0 : ctx.totalBulk;
        example.actualSharePct = actualSharePct();
        example.targetSharePct = targetSharePct();
        example.averageSharePct = (actualSharePct() + targetSharePct()) / 2;
        example.bulkShareQty = (example.averageSharePct / 100) * example.totalBulk;
        example.originalTarget = ORIGINAL_TARGET;
        example.bufferTarget = BUFFER_TARGET;
        example.attained = ATTAINED;
        example.effectiveTargetShortageOff = BUFFER_TARGET;
        example.effectiveTargetShortageOn = ATTAINED;
        example.steps = stepLabels();
        return example;
    }

    private static List<String> stepLabels() {
        return new List<String>{
            '1. Doctor class this month versus last month (absolute movement)',
            '2. Affiliated pharmacies on the brick',
            '3. Distributor quantity on each pharmacy (subtype + brick)',
            '4. Item ceiling: keep up to the cap; excess moves to bulk',
            '5. Pharmacies marked “Does not enter the ceiling” keep the full quantity',
            '6. Bulk share = average of actual and target contribution × bulk quantity',
            '7. Effective target = buffer when shortage is off; attained when shortage is on'
        };
    }

    private static Id recordTypeId(String developerName) {
        for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (info.isAvailable() && info.getDeveloperName() == developerName) {
                return info.getRecordTypeId();
            }
        }
        return null;
    }
}
