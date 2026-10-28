@IsTest
private class KpiTargetServiceTest {
    @IsTest
    static void catalogAddSaveDeleteAndCountSource_roundTrip() {
        KpiTargetService.seedFrameworkDefaults();
        Test.startTest();
        KpiTargetService.Catalog catalog = KpiTargetService.getCatalog();
        System.assert(catalog.rows.size() > 0, 'Defaults should be seeded by the admin action');
        System.assertEquals(false, catalog.needsSeed);
        System.assert(catalog.countSources.size() > 0, 'Count sources expected');
        System.assert(catalog.roleKeys.size() > 0, 'Roles expected');

        Decimal coverage = KpiTargetService.targetFor('MSR', 'Coverage');
        System.assert(coverage > 0);

        List<KpiTargetService.TargetRow> afterAdd = KpiTargetService.addTarget(
            'DSM',
            'Sample_Drop_Rate',
            'Sample drop rate',
            88,
            'Monthly',
            'Org',
            null,
            'Custom_Report',
            'Samples dropped on Valid visits',
            'Planned sample drops'
        );
        Boolean found = false;
        Id customId;
        for (KpiTargetService.TargetRow row : afterAdd) {
            if (row.metricKey == 'Sample_Drop_Rate') {
                found = true;
                customId = row.id;
                System.assertEquals('Custom_Report', row.countSource);
                System.assertEquals('Sample drop rate', row.metricLabel);
            }
        }
        System.assertEquals(true, found, 'Custom metric should be added');

        String payload =
            '[{"id":"' +
            customId +
            '","targetPercent":91,"metricLabel":"Sample drop rate","period":"Quarterly","scopeLevel":"Org","countSource":"Custom_Report","countNumerator":"A","countDenominator":"B"}]';
        List<KpiTargetService.TargetRow> saved = KpiTargetService.saveTargets(payload);
        System.assert(saved.size() >= afterAdd.size() - 1);

        List<KpiTargetService.TargetRow> afterDelete = KpiTargetService.deleteTarget(customId);
        for (KpiTargetService.TargetRow row : afterDelete) {
            System.assertNotEquals('Sample_Drop_Rate', row.metricKey);
        }
        Test.stopTest();
    }

    @IsTest
    static void reads_neverPerformDml_andFallBackToFrameworkDefaults() {
        Integer dmlBefore = Limits.getDmlStatements();
        KpiTargetService.Catalog catalog = KpiTargetService.getCatalog();
        List<KpiTargetService.TargetRow> rows = KpiTargetService.listTargets();
        Decimal coverage = KpiTargetService.targetFor('MSR', 'Coverage');
        System.assertEquals(dmlBefore, Limits.getDmlStatements(), 'Reads must not run DML');
        System.assertEquals(0, [SELECT COUNT() FROM KPI_Target__c], 'Reads must not seed rows');
        System.assertEquals(true, catalog.needsSeed);
        System.assertEquals(0, rows.size());
        System.assertEquals(90, coverage, 'Framework default is used until rows are seeded');
    }

    @IsTest
    static void saveTargets_seedsMissingRowsBeforeUpdating() {
        KpiTargetService.seedFrameworkDefaults();
        KpiTargetService.TargetRow first = KpiTargetService.listTargets()[0];
        String payload = '[{"id":"' + first.id + '","targetPercent":77}]';
        KpiTargetService.saveTargets(payload);
        System.assertEquals(
            77,
            [SELECT Target_Percent__c FROM KPI_Target__c WHERE Id = :first.id].Target_Percent__c
        );
    }

    @IsTest
    static void resetToFrameworkDefaults_restoresSeed() {
        KpiTargetService.seedFrameworkDefaults();
        Test.startTest();
        List<KpiTargetService.TargetRow> reset = KpiTargetService.resetToFrameworkDefaults();
        Test.stopTest();
        System.assert(reset.size() > 10, 'Framework seed should reload');
    }
}
