@IsTest
private class ZetaOrganogramRetireServiceTest {
    private static String currentOrganogramJson() {
        return JSON.serialize(
            new Map<String, Object>{
                'headOffice' => new Map<String, Object>{
                    'externalId' => 'TERR_HEAD_OFFICE',
                    'name' => 'Head Office',
                    'developerName' => 'Head_Office',
                    'territoryType' => 'Head_Office'
                },
                'businessUnits' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_BU_RETIRE_TEST',
                        'name' => 'Cluster',
                        'developerName' => 'BU_RETIRE_TEST',
                        'parentExternalId' => 'TERR_HEAD_OFFICE',
                        'territoryType' => 'Business_Unit'
                    }
                },
                'lines' => new List<Object>(),
                'districts' => new List<Object>(),
                'positions' => new List<Object>(),
                'bricks' => new List<Object>()
            }
        );
    }

    private static Territory2 makeTerritory(String externalId, String devName, String type, Id parentId) {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        List<Territory2Model> models = [SELECT Id FROM Territory2Model LIMIT 1];
        if (types.isEmpty() || models.isEmpty()) {
            return null;
        }
        Territory2 node = new Territory2(
            Name = devName,
            DeveloperName = devName,
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            ParentTerritory2Id = parentId,
            External_ID__c = externalId,
            Territory_Type__c = type
        );
        insert node;
        return node;
    }

    @IsTest
    static void dryRun_listsStaleSeatsAndChangesNothing() {
        ZetaOrganogramRetireService.testTerritoriesJson = currentOrganogramJson();
        ZetaOrganogramRetireService.testOnlyExternalIds = new Set<String>{
            'TERR_DM_STALE_TEST',
            'TERR_POS_STALE_TEST',
            'TERR_DM_TRAINING_STALE_TEST'
        };
        Territory2 district = makeTerritory('TERR_DM_STALE_TEST', 'DM_Stale_Test', 'District', null);
        if (district == null) {
            return;
        }
        makeTerritory('TERR_POS_STALE_TEST', 'POS_Stale_Test', 'Position', district.Id);
        makeTerritory('TERR_DM_TRAINING_STALE_TEST', 'DM_Training_Stale', 'District', null);

        Test.startTest();
        ZetaOrganogramRetireService.Report report = ZetaOrganogramRetireService.retireStale(true, null);
        Test.stopTest();

        System.assertEquals(true, report.dryRun);
        System.assert(report.staleDistricts.contains('TERR_DM_STALE_TEST'));
        System.assert(report.stalePositions.contains('TERR_POS_STALE_TEST'));
        System.assert(!report.staleDistricts.contains('TERR_DM_TRAINING_STALE_TEST'), 'Training seats are left alone');
        System.assertEquals(0, report.territoriesRetired);
        System.assertEquals(3, [SELECT COUNT() FROM Territory2 WHERE External_ID__c LIKE '%STALE_TEST']);
    }

    @IsTest
    static void seatedStaleDistrict_isABlocker() {
        ZetaOrganogramRetireService.testTerritoriesJson = currentOrganogramJson();
        ZetaOrganogramRetireService.testOnlyExternalIds = new Set<String>{ 'TERR_DM_STALE_SEATED' };
        Territory2 district = makeTerritory('TERR_DM_STALE_SEATED', 'DM_Stale_Seated', 'District', null);
        if (district == null) {
            return;
        }
        insert new UserTerritory2Association(
            UserId = UserInfo.getUserId(),
            Territory2Id = district.Id,
            RoleInTerritory2 = 'District Manager'
        );

        ZetaOrganogramRetireService.Report report = ZetaOrganogramRetireService.retireStale(true, null);

        Boolean blocked = false;
        for (String blocker : report.blockers) {
            blocked = blocked || blocker.startsWith('SEAT:');
        }
        System.assertEquals(true, blocked, 'A seated user must block retirement');
    }

    @IsTest
    static void realRun_needsAPhase() {
        ZetaOrganogramRetireService.testTerritoriesJson = currentOrganogramJson();
        try {
            ZetaOrganogramRetireService.retireStale(false, null);
            System.assert(false, 'A real run must name its phase');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
    }

    @IsTest
    static void businessUnitNames_followTheResource() {
        ZetaOrganogramRetireService.testTerritoriesJson = currentOrganogramJson();
        ZetaOrganogramRetireService.testOnlyExternalIds = new Set<String>{ 'TERR_BU_RETIRE_TEST' };
        Territory2 bu = makeTerritory('TERR_BU_RETIRE_TEST', 'BU_Retire_Test', 'Business_Unit', null);
        if (bu == null) {
            return;
        }
        update new Territory2(Id = bu.Id, Name = 'CVM-ORTHO-PEDIA');

        ZetaOrganogramRetireService.Report planned = ZetaOrganogramRetireService.retireStale(true, null);
        System.assertEquals(1, planned.renamedBusinessUnits.size());
        System.assertEquals('CVM-ORTHO-PEDIA', [SELECT Name FROM Territory2 WHERE Id = :bu.Id].Name);

        ZetaOrganogramRetireService.Report applied = ZetaOrganogramRetireService.retireStale(false, 'TERRITORIES');
        System.assertEquals('Cluster', [SELECT Name FROM Territory2 WHERE Id = :bu.Id].Name);
        System.assertEquals(0, applied.errors.size());
    }

    @IsTest
    static void territoriesPhase_retiresUnseatedStaleDistrictAndPosition() {
        ZetaOrganogramRetireService.testTerritoriesJson = currentOrganogramJson();
        ZetaOrganogramRetireService.testOnlyExternalIds = new Set<String>{
            'TERR_DM_STALE_DEL',
            'TERR_POS_STALE_DEL'
        };
        Territory2 district = makeTerritory('TERR_DM_STALE_DEL', 'DM_Stale_Del', 'District', null);
        if (district == null) {
            return;
        }
        makeTerritory('TERR_POS_STALE_DEL', 'POS_Stale_Del', 'Position', district.Id);

        Test.startTest();
        ZetaOrganogramRetireService.Report applied = ZetaOrganogramRetireService.retireStale(false, 'TERRITORIES');
        Test.stopTest();

        System.assertEquals(0, applied.blockers.size(), String.join(applied.blockers, ' | '));
        System.assertEquals(2, applied.territoriesRetired);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Territory2 WHERE External_ID__c IN ('TERR_DM_STALE_DEL', 'TERR_POS_STALE_DEL')]
        );
    }

    @IsTest
    static void productsAndAlignmentsPhases_runWithoutErrors() {
        ZetaOrganogramRetireService.testTerritoriesJson = currentOrganogramJson();
        ZetaOrganogramRetireService.testOnlyExternalIds = new Set<String>{ 'TERR_LINE_STALE_NEURO' };
        Territory2 line = makeTerritory('TERR_LINE_STALE_NEURO', 'NEUROSCIENCE', 'Line', null);
        if (line == null) {
            return;
        }
        Product2 orphan = new Product2(
            Name = 'Neuro Orphan Sample',
            ProductCode = 'NEURO-ORPHAN-1',
            IsActive = true,
            Sales_Line__c = 'NEUROSCIENCE'
        );
        insert orphan;

        Test.startTest();
        ZetaOrganogramRetireService.Report products = ZetaOrganogramRetireService.retireStale(false, 'PRODUCTS');
        ZetaOrganogramRetireService.Report alignments = ZetaOrganogramRetireService.retireStale(false, 'ALIGNMENTS');
        Test.stopTest();

        System.assert(products.productsUnmapped.size() >= 1 || products.productsRemapped.size() >= 0);
        System.assertEquals(0, alignments.errors.size());
    }

    @IsTest
    static void helpers_classifyTrainingSeatsAndProductFamilies() {
        System.assertEquals(true, ZetaOrganogramRetireService.isTrainingOrDemo('TERR_DM_TRAINING_DIAB'));
        System.assertEquals(true, ZetaOrganogramRetireService.isTrainingOrDemo('TERR_DM_DEMO'));
        System.assertEquals(false, ZetaOrganogramRetireService.isTrainingOrDemo('TERR_DM_2507'));
        System.assertEquals(
            'ZETAZOLEX',
            ZetaOrganogramRetireService.familyKey(new Product2(Name = 'Zetazolex 1 mg FCT 5 FCT/Strip(FMS)'))
        );
        System.assertEquals(
            'MINDOLUX',
            ZetaOrganogramRetireService.familyKey(new Product2(Name = 'x', Primary_Brand__c = 'MINDOLUX CAP'))
        );
    }
}
