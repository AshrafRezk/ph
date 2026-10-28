@IsTest
private class ClassEngineServiceTest {
    @IsTest
    static void classify_capacityMix_matchesWorkedExample() {
        List<ClassEngineService.SpecialtyQuota> specialties = lineSpecialties();
        List<ClassEngineService.ClassTarget> classes = lineClasses();
        List<ClassEngineService.AccountScoreInput> pool = buildPool();

        ClassEngineService.ClassifyResult result = ClassEngineService.classify(
            pool,
            specialties,
            classes,
            273
        );

        System.assertEquals(82, result.listSize, 'List size should be floor(273/3.3)=82');
        System.assertEquals(66, result.specialtyCounts.get('Ortho'), 'Ortho Hamilton seats');
        System.assertEquals(16, result.specialtyCounts.get('Rheumatoid'), 'Rheumatoid Hamilton seats');
        System.assertEquals(271, result.plannedVisits, 'Planned visit load');
        System.assertEquals(8, result.seatsByClass.get('A1'));
        System.assertEquals(17, result.seatsByClass.get('A3'));
        System.assertEquals(25, result.seatsByClass.get('B1'));
        System.assertEquals(8, result.seatsByClass.get('C1'));

        Map<String, String> classByName = byName(result.accounts);
        System.assertEquals('A1', classByName.get('Abdullah'));
        System.assertEquals('A1', classByName.get('Dr. Samir'));
        System.assertEquals('B1', classByName.get('Dr. Ahmed'));
    }

    @IsTest
    static void diminish_protectsTopClasses() {
        Map<String, Integer> seats = new Map<String, Integer>{
            'A1' => 8,
            'A2' => 8,
            'A3' => 17,
            'B1' => 25,
            'B2' => 8,
            'B3' => 8,
            'C1' => 8
        };
        Map<String, Decimal> grid = new Map<String, Decimal>{
            'A1' => 5,
            'A2' => 5,
            'A3' => 4,
            'B1' => 3,
            'B2' => 3,
            'B3' => 2,
            'C1' => 1
        };

        ClassEngineService.DiminishResult result = ClassEngineService.diminishVisits(seats, grid, 208);

        System.assertEquals(198, result.plannedVisits);
        System.assertEquals(5, result.appliedVisitsByClass.get('A1'));
        System.assertEquals(5, result.appliedVisitsByClass.get('A2'));
        System.assertEquals(4, result.appliedVisitsByClass.get('A3'));
        System.assertEquals(2, result.appliedVisitsByClass.get('B1'));
        System.assertEquals(0, result.appliedVisitsByClass.get('B2'));
        System.assertEquals(0, result.appliedVisitsByClass.get('B3'));
        System.assertEquals(0, result.appliedVisitsByClass.get('C1'));
    }

    @IsTest
    static void salesTwin_ranksDifferentlyFromRx() {
        List<ClassEngineService.SpecialtyQuota> specialties = lineSpecialties();
        List<ClassEngineService.ClassTarget> classes = lineClasses();
        List<ClassEngineService.AccountScoreInput> rxPool =
            new List<ClassEngineService.AccountScoreInput>();
        List<ClassEngineService.AccountScoreInput> salesPool =
            new List<ClassEngineService.AccountScoreInput>();

        for (Integer i = 0; i < 120; i++) {
            String specialty = i < 90 ? 'Ortho' : 'Rheumatoid';
            String name = 'HCP ' + i;
            Decimal rx = 100000 - i;
            Decimal sales = i * 100;
            if (i == 0) {
                name = 'Abdullah';
                rx = 180000;
                sales = 8000;
            } else if (i == 40) {
                name = 'Dr. Ahmed';
                rx = 9000;
                sales = 175000;
            } else if (i == 90) {
                name = 'Dr. Samir';
                rx = 210000;
                sales = 200000;
            }
            rxPool.add(account(name, specialty, scored(rx)));
            salesPool.add(account(name, specialty, scored(sales)));
        }

        ClassEngineService.ClassifyResult rxResult =
            ClassEngineService.classify(rxPool, specialties, classes, 273);
        ClassEngineService.ClassifyResult salesResult =
            ClassEngineService.classify(salesPool, specialties, classes, 273);

        Map<String, String> rxClass = byName(rxResult.accounts);
        Map<String, String> salesClass = byName(salesResult.accounts);
        System.assertEquals('A1', rxClass.get('Abdullah'));
        System.assertEquals('A1', rxClass.get('Dr. Samir'));
        System.assertNotEquals('A1', salesClass.get('Abdullah'));
        System.assertEquals('A1', salesClass.get('Dr. Samir'));
        System.assertNotEquals(null, salesClass.get('Dr. Ahmed'), 'Ahmed should rise on sales list');
        System.assert(
            salesClass.get('Dr. Ahmed') == 'A1' || salesClass.get('Dr. Ahmed') == 'A2',
            'Ahmed should rise on sales ranking, was ' + salesClass.get('Dr. Ahmed')
        );
    }

    @IsTest
    static void publicHoliday_blocksWorkingDay() {
        PublicHolidayService.testHolidays = new List<Public_Holiday__c>{
            new Public_Holiday__c(
                Name = 'Test Holiday',
                Holiday_Date__c = Date.newInstance(2026, 10, 3),
                Recurs_Yearly__c = false,
                Is_Active__c = true
            )
        };
        System.assertEquals(true, PublicHolidayService.isPublicHoliday(Date.newInstance(2026, 10, 3)));
        System.assertEquals(
            true,
            PublicHolidayService.datesInRange(
                    Date.newInstance(2026, 10, 3),
                    Date.newInstance(2026, 10, 3)
                )
                .contains(Date.newInstance(2026, 10, 3))
        );
        PublicHolidayService.testHolidays = null;
    }

    private static Map<String, String> byName(List<ClassEngineService.ClassifiedAccount> accounts) {
        Map<String, String> mapByName = new Map<String, String>();
        for (ClassEngineService.ClassifiedAccount row : accounts) {
            mapByName.put(row.accountName, row.classCode);
        }
        return mapByName;
    }

    private static List<ClassEngineService.SpecialtyQuota> lineSpecialties() {
        ClassEngineService.SpecialtyQuota ortho = new ClassEngineService.SpecialtyQuota();
        ortho.specialty = 'Ortho';
        ortho.listPercentage = 80;
        ClassEngineService.SpecialtyQuota rheumatoid = new ClassEngineService.SpecialtyQuota();
        rheumatoid.specialty = 'Rheumatoid';
        rheumatoid.listPercentage = 20;
        return new List<ClassEngineService.SpecialtyQuota>{ ortho, rheumatoid };
    }

    private static List<ClassEngineService.ClassTarget> lineClasses() {
        return new List<ClassEngineService.ClassTarget>{
            classTarget('A1', 10, 5),
            classTarget('A2', 10, 5),
            classTarget('A3', 20, 4),
            classTarget('B1', 30, 3),
            classTarget('B2', 10, 3),
            classTarget('B3', 10, 2),
            classTarget('C1', 10, 1)
        };
    }

    private static ClassEngineService.ClassTarget classTarget(
        String code,
        Decimal pct,
        Decimal visits
    ) {
        ClassEngineService.ClassTarget target = new ClassEngineService.ClassTarget();
        target.classCode = code;
        target.listPercentage = pct;
        target.targetMonthlyVisits = visits;
        return target;
    }

    /**
     * 90 Ortho + 30 Rheumatoid. Named doctors placed so specialty cut + rank-to-class
     * match the worked example (Abdullah/Samir A1, Ahmed B1).
     */
    private static List<ClassEngineService.AccountScoreInput> buildPool() {
        List<ClassEngineService.AccountScoreInput> pool =
            new List<ClassEngineService.AccountScoreInput>();
        // Top Ortho scores for A1–A3 (ranks among 82 after cut).
        pool.add(account('Abdullah', 'Ortho', scored(180000)));
        for (Integer i = 0; i < 32; i++) {
            pool.add(account('Ortho Top ' + i, 'Ortho', scored(170000 - i * 1000)));
        }
        // Ahmed in B1 band (~rank 40 among final 82).
        pool.add(account('Dr. Ahmed', 'Ortho', scored(9000)));
        for (Integer i = 0; i < 32; i++) {
            pool.add(account('Ortho Mid ' + i, 'Ortho', scored(8900 - i * 50)));
        }
        // Dropped Ortho (below specialty cut of 66).
        for (Integer i = 0; i < 24; i++) {
            pool.add(account('Ortho Drop ' + i, 'Ortho', scored(1000 - i)));
        }

        pool.add(account('Dr. Samir', 'Rheumatoid', scored(210000)));
        for (Integer i = 0; i < 15; i++) {
            pool.add(account('Rheuma Keep ' + i, 'Rheumatoid', scored(20000 - i * 500)));
        }
        for (Integer i = 0; i < 14; i++) {
            pool.add(account('Rheuma Drop ' + i, 'Rheumatoid', scored(500 - i)));
        }
        return pool;
    }

    private static ClassEngineService.AccountScoreInput account(
        String name,
        String specialty,
        List<ClassEngineService.ProductScoreInput> products
    ) {
        ClassEngineService.AccountScoreInput input = new ClassEngineService.AccountScoreInput();
        input.accountId = fakeId(name);
        input.accountName = name;
        input.specialty = specialty;
        input.products = products;
        return input;
    }

    private static Id fakeId(String seed) {
        Integer hash = Math.abs(seed.hashCode());
        String key = String.valueOf(hash);
        while (key.length() < 12) {
            key = '0' + key;
        }
        return Id.valueOf('001' + key.left(12));
    }

    private static List<ClassEngineService.ProductScoreInput> scored(Decimal value) {
        ClassEngineService.ProductScoreInput product = new ClassEngineService.ProductScoreInput();
        product.weightPercentage = 100;
        product.potential = value;
        product.penetration = value;
        return new List<ClassEngineService.ProductScoreInput>{ product };
    }
}