@IsTest
private class ZetaOrganogramRosterLoaderTest {
    @IsTest
    static void assignsSeatAndRemovesRetiredOrganogramSeat() {
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        ZetaOrganogramTerritoryLoader.testTerritoriesJson = territoryJson(uniq);
        ZetaOrganogramTerritoryLoader.skipAlignmentQueue = true;
        ZetaOrganogramTerritoryLoader.LoadResult loaded = ZetaOrganogramTerritoryLoader.loadTerritoriesOnly();
        System.assertNotEquals(null, loaded.headOfficeId, loaded.message);

        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User person = new User(
            FirstName = 'Roster',
            LastName = 'Rep',
            Email = 'roster.' + uniq + '@zeta-pharma.com',
            Username = 'roster.' + uniq + '@zeta-pharma.com',
            Alias = 'rostert',
            CommunityNickname = ('roster' + uniq).left(40),
            EmployeeNumber = ('R' + uniq).left(20),
            TimeZoneSidKey = 'Africa/Cairo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardProfile.Id
        );
        insert person;

        Territory2 line = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :('TERR_LINE_ROSTER_' + uniq)
            LIMIT 1
        ];
        Territory2 position = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :('TERR_POS_ROSTER_' + uniq)
            LIMIT 1
        ];
        insert new UserTerritory2Association(
            UserId = person.Id,
            Territory2Id = line.Id,
            RoleInTerritory2 = 'Medical Rep'
        );

        ZetaOrganogramRosterLoader.testRosterJson =
            '{"assignments":[{"code":"' +
            person.EmployeeNumber +
            '","territoryExternalId":"TERR_POS_ROSTER_' +
            uniq +
            '","role":"Medical Rep"}]}';
        ZetaOrganogramRosterLoader.skipChain = true;

        Test.startTest();
        new ZetaOrganogramRosterLoader().execute(null);
        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM UserTerritory2Association
                WHERE UserId = :person.Id AND Territory2Id = :position.Id AND RoleInTerritory2 = 'Medical Rep'
            ]
        );
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM UserTerritory2Association
                WHERE UserId = :person.Id AND Territory2Id = :line.Id
            ]
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
                        'externalId' => 'TERR_BU_ROSTER_' + uniq,
                        'name' => 'Roster BU',
                        'developerName' => 'BU_ROSTER_' + uniq,
                        'parentExternalId' => 'TERR_HEAD_OFFICE',
                        'territoryType' => 'Business_Unit'
                    }
                },
                'lines' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_LINE_ROSTER_' + uniq,
                        'name' => 'Roster Line',
                        'developerName' => 'LINE_ROSTER_' + uniq,
                        'parentExternalId' => 'TERR_BU_ROSTER_' + uniq,
                        'territoryType' => 'Line'
                    }
                },
                'districts' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_DM_ROSTER_' + uniq,
                        'name' => 'Roster District',
                        'developerName' => 'DM_ROSTER_' + uniq,
                        'parentExternalId' => 'TERR_LINE_ROSTER_' + uniq,
                        'territoryType' => 'District'
                    }
                },
                'positions' => new List<Object>{
                    new Map<String, Object>{
                        'externalId' => 'TERR_POS_ROSTER_' + uniq,
                        'name' => 'Roster Position',
                        'developerName' => 'POS_ROSTER_' + uniq,
                        'parentExternalId' => 'TERR_DM_ROSTER_' + uniq,
                        'territoryType' => 'Position'
                    }
                },
                'bricks' => new List<Object>()
            }
        );
    }
}
