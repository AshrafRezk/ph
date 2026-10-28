@IsTest
private class ZetaOrganogramTerritoryLoaderTest {
    private static String miniPayloadJson() {
        return JSON.serialize(
            new Map<String, Object>{
                'headOffice' => new Map<String, Object>{
                    'externalId' => 'TERR_HEAD_OFFICE',
                    'name' => 'Head Office',
                    'developerName' => 'Head_Office',
                    'parentExternalId' => null,
                    'territoryType' => 'Head_Office'
                },
                'businessUnits' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_BU_TEST_1',
                        'name' => 'TEST-BU',
                        'developerName' => 'BU_TEST_1',
                        'parentExternalId' => 'TERR_HEAD_OFFICE',
                        'territoryType' => 'Business_Unit'
                    }
                },
                'lines' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_LINE_TEST_1',
                        'name' => 'TEST-LINE',
                        'developerName' => 'LINE_TEST_1',
                        'parentExternalId' => 'TERR_BU_TEST_1',
                        'territoryType' => 'Line'
                    }
                },
                'districts' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_DM_TEST_1',
                        'name' => 'TEST DISTRICT',
                        'developerName' => 'DM_TEST_1',
                        'parentExternalId' => 'TERR_LINE_TEST_1',
                        'territoryType' => 'District'
                    }
                },
                'positions' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_POS_TEST_1',
                        'name' => 'TEST POSITION',
                        'developerName' => 'POS_TEST_1',
                        'parentExternalId' => 'TERR_DM_TEST_1',
                        'territoryType' => 'Position'
                    }
                },
                'bricks' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'BRICK_TEST_ORG_1',
                        'name' => 'Test Brick Org 1',
                        'dataSource' => 'IQVIA IMS',
                        'isActive' => true,
                        'brickLevel' => '702',
                        'brickCode' => 'Test Brick Org 1',
                        'parentExternalId' => null,
                        'accountSelectable' => true
                    }
                }
            }
        );
    }

    @IsTest
    static void alignmentResourceNames_areConfigured() {
        List<String> names = ZetaOrganogramTerritoryLoader.alignmentResourceNames();
        System.assertEquals(6, names.size());
        System.assert(names[0].startsWith('ZetaOrganogramAlignments'));
    }

    @IsTest
    static void loadTerritoriesAndBricks_withInjectedPayload() {
        ZetaOrganogramTerritoryLoader.testTerritoriesJson = miniPayloadJson();
        ZetaOrganogramTerritoryLoader.skipAlignmentQueue = true;

        ZetaOrganogramTerritoryLoader.LoadResult terrResult =
            ZetaOrganogramTerritoryLoader.loadTerritoriesOnly();
        System.assertNotEquals(null, terrResult.headOfficeId, terrResult.message);
        System.assertEquals(1, terrResult.businessUnitsUpserted, terrResult.message);
        System.assertEquals(1, terrResult.linesUpserted, terrResult.message);
        System.assertEquals(1, terrResult.districtsUpserted, terrResult.message);
        System.assertEquals(1, terrResult.positionsUpserted, terrResult.message);

        ZetaOrganogramTerritoryLoader.LoadResult brickResult =
            ZetaOrganogramTerritoryLoader.loadBricksAndQueueAlignments();
        System.assertEquals(1, brickResult.bricksUpserted, brickResult.message);

        ZetaOrganogramAlignmentBatch.testAlignmentsJson = JSON.serialize(
            new Map<String, Object>{
                'alignments' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'BRICK_TEST_ORG_1|TERR_POS_TEST_1',
                        'brickExternalId' => 'BRICK_TEST_ORG_1',
                        'territoryExternalId' => 'TERR_POS_TEST_1',
                        'share' => 1,
                        'isActive' => true
                    },
                    new Map<String, Object>{
                        'externalId' => 'BRICK_MISSING|TERR_POS_TEST_1',
                        'brickExternalId' => 'BRICK_DOES_NOT_EXIST',
                        'territoryExternalId' => 'TERR_POS_TEST_1',
                        'share' => 0.5,
                        'isActive' => true
                    }
                }
            }
        );

        Test.startTest();
        ZetaOrganogramTerritoryLoader.skipAlignmentQueue = false;
        ZetaOrganogramTerritoryLoader.LoadResult queued =
            ZetaOrganogramTerritoryLoader.loadTerritoriesAndQueueAlignments();
        Database.executeBatch(new ZetaOrganogramAlignmentBatch('ZetaOrganogramAlignments01'), 50);
        Test.stopTest();

        System.assertNotEquals(null, queued.message);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Brick_Territory_Alignment__c
                WHERE External_ID__c = 'BRICK_TEST_ORG_1|TERR_POS_TEST_1'
            ]
        );
    }

    @IsTest
    static void seedTrainingHierarchy_createsBuLineAndRep() {
        ZetaOrganogramTerritoryLoader.testTerritoriesJson = miniPayloadJson();
        ZetaOrganogramTerritoryLoader.skipAlignmentQueue = true;
        ZetaOrganogramTerritoryLoader.LoadResult loaded =
            ZetaOrganogramTerritoryLoader.loadTerritoriesOnly();
        System.assertNotEquals(null, loaded.headOfficeId, loaded.message);

        Test.startTest();
        ZetaOrganogramTerritoryLoader.LoadResult training =
            ZetaOrganogramTerritoryLoader.seedTrainingHierarchy();
        Test.stopTest();

        System.assertEquals(1, training.businessUnitsUpserted, training.message);
        System.assertEquals(5, training.linesUpserted, training.message);
        System.assertEquals(4, training.districtsUpserted, training.message);
        System.assertEquals(5, training.positionsUpserted, training.message);
        // Count only the seats this loader owns. The org may hold other TERR_DM_TRAINING* seats.
        Set<String> trainingDistrictIds = new Set<String>();
        Set<String> trainingLineIds = new Set<String>{ ZetaOrganogramTerritoryLoader.TRAINING_LINE_EXT };
        Set<String> trainingPositionIds = new Set<String>{ ZetaOrganogramTerritoryLoader.TRAINING_REP_EXT };
        for (ZetaOrganogramTerritoryLoader.TrainingLineSpec spec : ZetaOrganogramTerritoryLoader.trainingLineSpecs()) {
            trainingDistrictIds.add(spec.districtExternalId);
            trainingLineIds.add(spec.lineExternalId);
            trainingPositionIds.add(spec.positionExternalId);
        }
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Territory2
                WHERE External_ID__c = :ZetaOrganogramTerritoryLoader.TRAINING_BU_EXT
                WITH SYSTEM_MODE
            ]
        );
        System.assertEquals(
            5,
            [
                SELECT COUNT()
                FROM Territory2
                WHERE External_ID__c IN :trainingLineIds
                WITH SYSTEM_MODE
            ]
        );
        System.assertEquals(
            4,
            [
                SELECT COUNT()
                FROM Territory2
                WHERE External_ID__c IN :trainingDistrictIds
                WITH SYSTEM_MODE
            ]
        );
        System.assertEquals(
            5,
            [
                SELECT COUNT()
                FROM Territory2
                WHERE External_ID__c IN :trainingPositionIds
                WITH SYSTEM_MODE
            ]
        );

        List<String> managerMessages = ZetaOrganogramTerritoryLoader.assignTrainingLineManagers();
        System.assertEquals(4, managerMessages.size(), String.join(managerMessages, ' | '));
    }
}