@IsTest
private class TrainingRepSampleSeedTest {
    @IsTest
    static void assignUsersToTrainingRep_returnsResult() {
        Test.startTest();
        TrainingRepSampleSeed.AssignResult result = TrainingRepSampleSeed.assignUsersToTrainingRep();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(String.isNotBlank(result.message), 'Assign result should include a message.');
    }

    @IsTest
    static void seedTrainingList_returnsResult() {
        Test.startTest();
        TrainingRepSampleSeed.SeedResult result = TrainingRepSampleSeed.seedTrainingList();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(String.isNotBlank(result.message), 'Seed result should include a message.');
    }

    @IsTest
    static void seedHelpers_createTrainingSampleRows() {
        TrainingRepSampleSeed.RecordTypeIds rts = TrainingRepSampleSeed.resolveRecordTypes();
        if (rts.personRtId == null) {
            return;
        }

        Test.startTest();
        List<Product2> products = TrainingRepSampleSeed.ensureTrainingProducts();
        TrainingRepSampleSeed.SeedResult gridResult = new TrainingRepSampleSeed.SeedResult();
        TrainingRepSampleSeed.seedPromoGrid(UserInfo.getUserId(), products, gridResult);
        Map<String, Account> hcos = rts.hcoRtId == null
            ? new Map<String, Account>()
            : TrainingRepSampleSeed.upsertHcos(rts.hcoRtId);
        Map<String, Account> hcps = TrainingRepSampleSeed.upsertHcps(rts.personRtId);
        Map<String, Account> pharmacies = rts.pharmacyRtId == null
            ? new Map<String, Account>()
            : TrainingRepSampleSeed.upsertPharmacies(rts.pharmacyRtId);
        String territoryKey = String.valueOf(UserInfo.getUserId());
        Integer atfCount = TrainingRepSampleSeed.ensureAccountTerritoryFields(hcps, territoryKey);
        Integer atpfCount = TrainingRepSampleSeed.ensureAccountTerritoryProductFields(
            hcps,
            territoryKey,
            products
        );
        TrainingRepSampleSeed.ensureAffiliations(hcps, hcos);
        TrainingRepSampleSeed.ensurePharmacyAffiliations(hcps, pharmacies);
        Test.stopTest();

        System.assert(!products.isEmpty(), 'Expected training products.');
        System.assertEquals(2, products.size(), 'Generic training line should have 2 products.');
        List<Product2> withDispense = TrainingRepSampleSeed.expandWithDispenseProducts(products);
        Boolean sawSample = false;
        Boolean sawReminder = false;
        for (Product2 row : withDispense) {
            if (row.Product_Type__c == 'Sample') {
                sawSample = true;
            }
            if (row.Product_Type__c == 'Brand Reminder') {
                sawReminder = true;
            }
        }
        System.assert(sawSample, 'Expected Sample children related to training details.');
        System.assert(sawReminder, 'Expected Brand Reminder children related to training details.');
        System.assert(TrainingRepSampleSeed.linkPresentationsToTrainingTerritories() >= 0);
        System.assert(gridResult.promoClassCount > 0, 'Expected promo grid class segments.');
        System.assertEquals(2, gridResult.promoWeightCount, 'Expected 2 product weights.');
        if (!hcps.isEmpty()) {
            System.assert(atfCount > 0, 'Expected account territory ratings.');
        }
        System.assert(atpfCount >= 0, 'Product ratings should run without error.');

        List<Product2> diabProducts = TrainingRepSampleSeed.ensureProductsForLine('DIAB');
        System.assertEquals(2, diabProducts.size(), 'Diabetes training line should have 2 products.');
        TrainingRepSampleSeed.SeedResult diabGrid = new TrainingRepSampleSeed.SeedResult();
        TrainingRepSampleSeed.seedPromoGrid(UserInfo.getUserId(), diabProducts, diabGrid);
        System.assertEquals(2, diabGrid.promoWeightCount, 'Diabetes promo grid should weight 2 products.');

        Employee_Time_Card_Account_Target__c target = new Employee_Time_Card_Account_Target__c(
            Target_Visit_Frequency__c = 4
        );
        System.assertEquals(0, TrainingRepSampleSeed.resolveTrainingVisitCount(0, target), 'First account stays remaining.');
        System.assertEquals(1, TrainingRepSampleSeed.resolveTrainingVisitCount(1, target), 'Second account is partially covered.');

        TrainingRepSampleSeed.SeedResult activity = TrainingRepSampleSeed.seedTrainingPlannerActivity();
        System.assertNotEquals(null, activity);
        System.assert(String.isNotBlank(activity.message), 'Activity seed should return a message.');

        Date today = TrainingRepSampleSeed.trainingLocalToday();
        Date planDay = TrainingRepSampleSeed.resolveTodayPlanDay(
            new List<Date>{ today, today.addDays(1) },
            new Set<Date>()
        );
        System.assertEquals(today, planDay, 'Today should be preferred for plan day.');
        Map<String, List<Employee_Time_Card_Account_Target__c>> byClass =
            new Map<String, List<Employee_Time_Card_Account_Target__c>>{
                'A' => new List<Employee_Time_Card_Account_Target__c>{ target },
                'B' => new List<Employee_Time_Card_Account_Target__c>(),
                'C' => new List<Employee_Time_Card_Account_Target__c>()
            };
        System.assertEquals(
            1,
            TrainingRepSampleSeed.pickAccountsForTodayPlan(byClass).size(),
            'Expected one today-plan account from class A.'
        );

        Account sampleAccount = new Account(Name = 'Training Seed Visit Account');
        insert sampleAccount;
        Employee_Time_Card_Account_Target__c seededTarget = new Employee_Time_Card_Account_Target__c(
            Account__c = sampleAccount.Id,
            Target_Visit_Frequency__c = 2
        );
        Map<String, List<Employee_Time_Card_Account_Target__c>> visitTargets =
            new Map<String, List<Employee_Time_Card_Account_Target__c>>{
                'A' => new List<Employee_Time_Card_Account_Target__c>{ seededTarget, seededTarget },
                'B' => new List<Employee_Time_Card_Account_Target__c>{ seededTarget },
                'C' => new List<Employee_Time_Card_Account_Target__c>{ seededTarget }
            };
        List<Date> working = new List<Date>{ Date.today().addDays(-2), Date.today(), Date.today().addDays(2) };
        List<Visit__c> built = TrainingRepSampleSeed.buildUserVisits(
            UserInfo.getUserId(),
            visitTargets,
            new List<Date>(),
            working,
            new Set<Date>()
        );
        System.assert(!built.isEmpty(), 'Expected completed/today/draft visits from builder.');
        Boolean sawScheduled = false;
        Boolean sawDraft = false;
        for (Visit__c row : built) {
            if (row.Status__c == 'Scheduled') {
                sawScheduled = true;
            }
            if (row.Status__c == 'Draft') {
                sawDraft = true;
            }
        }
        System.assert(sawScheduled, 'Expected Scheduled today-plan visits.');
        System.assert(sawDraft, 'Expected Draft potential visits.');
    }

    @IsTest
    static void seedTrainingLineProductsAndActivity_returnsResult() {
        Test.startTest();
        TrainingRepSampleSeed.SeedResult lineProducts = TrainingRepSampleSeed.seedTrainingLineProductsAndActivity();
        Test.stopTest();

        System.assertNotEquals(null, lineProducts);
        System.assert(String.isNotBlank(lineProducts.message), 'Line product seed should return a message.');
    }
}