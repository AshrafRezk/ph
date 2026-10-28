@IsTest
private class ZetaOrganogramAlignmentRetireBatchTest {
    @IsTest
    static void retiresAlignmentMissingFromTheFile() {
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        ZetaOrganogramTerritoryLoader.testTerritoriesJson = territoryJson(uniq);
        ZetaOrganogramTerritoryLoader.skipAlignmentQueue = true;
        System.assertNotEquals(null, ZetaOrganogramTerritoryLoader.loadTerritoriesOnly().headOfficeId);
        System.assertEquals(1, ZetaOrganogramTerritoryLoader.loadBricksOnly().bricksUpserted);

        Id brickId = [
            SELECT Id
            FROM Brick__c
            WHERE External_ID__c = :('BRICK_RETIRE_' + uniq)
            LIMIT 1
        ].Id;
        Id territoryId = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :('TERR_POS_RETIRE_' + uniq)
            LIMIT 1
        ].Id;
        String keepKey = 'BRICK_RETIRE_' + uniq + '|TERR_POS_RETIRE_' + uniq;
        String dropKey = 'BRICK_RETIRE_OLD_' + uniq + '|TERR_POS_RETIRE_' + uniq;
        insert new List<Brick_Territory_Alignment__c>{
            new Brick_Territory_Alignment__c(
                Brick__c = brickId,
                External_ID__c = keepKey,
                Territory_External_ID__c = 'TERR_POS_RETIRE_' + uniq,
                Territory2_Id__c = String.valueOf(territoryId),
                Share__c = 1,
                Is_Active__c = true
            ),
            new Brick_Territory_Alignment__c(
                Brick__c = brickId,
                External_ID__c = dropKey,
                Territory_External_ID__c = 'TERR_POS_RETIRE_' + uniq,
                Territory2_Id__c = String.valueOf(territoryId),
                Share__c = 1,
                Is_Active__c = true
            )
        };

        ZetaOrganogramAlignmentRetireBatch.testKeepExternalIdsJson = JSON.serialize(new List<String>{ keepKey });

        Test.startTest();
        Database.executeBatch(new ZetaOrganogramAlignmentRetireBatch(), 50);
        Test.stopTest();

        System.assertEquals(
            true,
            [SELECT Is_Active__c FROM Brick_Territory_Alignment__c WHERE External_ID__c = :keepKey].Is_Active__c
        );
        System.assertEquals(
            false,
            [SELECT Is_Active__c FROM Brick_Territory_Alignment__c WHERE External_ID__c = :dropKey].Is_Active__c
        );
    }

    private static String territoryJson(String uniq) {
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
                        'externalId' => 'TERR_BU_RETIRE_' + uniq,
                        'name' => 'Retire BU',
                        'developerName' => 'BU_RETIRE_' + uniq,
                        'parentExternalId' => 'TERR_HEAD_OFFICE',
                        'territoryType' => 'Business_Unit'
                    }
                },
                'lines' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_LINE_RETIRE_' + uniq,
                        'name' => 'Retire Line',
                        'developerName' => 'LINE_RETIRE_' + uniq,
                        'parentExternalId' => 'TERR_BU_RETIRE_' + uniq,
                        'territoryType' => 'Line'
                    }
                },
                'districts' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_DM_RETIRE_' + uniq,
                        'name' => 'Retire District',
                        'developerName' => 'DM_RETIRE_' + uniq,
                        'parentExternalId' => 'TERR_LINE_RETIRE_' + uniq,
                        'territoryType' => 'District'
                    }
                },
                'positions' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_POS_RETIRE_' + uniq,
                        'name' => 'Retire Position',
                        'developerName' => 'POS_RETIRE_' + uniq,
                        'parentExternalId' => 'TERR_DM_RETIRE_' + uniq,
                        'territoryType' => 'Position'
                    }
                },
                'bricks' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'BRICK_RETIRE_' + uniq,
                        'name' => 'Retire Brick',
                        'dataSource' => 'IQVIA IMS',
                        'isActive' => true,
                        'brickLevel' => '702',
                        'brickCode' => 'Retire',
                        'accountSelectable' => true
                    }
                }
            }
        );
    }
}
