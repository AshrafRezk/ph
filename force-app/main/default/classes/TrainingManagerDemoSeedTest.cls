@IsTest
private class TrainingManagerDemoSeedTest {
    private static String headOfficeJson() {
        return JSON.serialize(
            new Map<String, Object>{
                'headOffice' => new Map<String, Object>{
                    'externalId' => 'TERR_HEAD_OFFICE',
                    'name' => 'Head Office',
                    'developerName' => 'Head_Office',
                    'parentExternalId' => null,
                    'territoryType' => 'Head_Office'
                },
                'businessUnits' => new List<Object>(),
                'lines' => new List<Object>(),
                'districts' => new List<Object>(),
                'positions' => new List<Object>(),
                'bricks' => new List<Object>()
            }
        );
    }

    private static User newUser(String alias, Id profileId) {
        String unique = alias + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
            Username = unique + '@mgrdemo.test',
            Email = unique + '@mgrdemo.test',
            FirstName = 'Test',
            LastName = alias,
            Alias = alias.left(8),
            TimeZoneSidKey = 'Africa/Cairo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
    }

    @IsTest
    static void run_seedsManagerAndRepData() {
        Id profileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        User manager = newUser('mgrdemo', profileId);
        User rep = newUser('repdemo', profileId);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ manager, rep };
        }

        ZetaOrganogramTerritoryLoader.testTerritoriesJson = headOfficeJson();
        ZetaOrganogramTerritoryLoader.skipAlignmentQueue = true;
        ZetaOrganogramTerritoryLoader.loadTerritoriesOnly();
        ZetaOrganogramTerritoryLoader.seedTrainingHierarchy();

        ZetaOrganogramTerritoryLoader.TrainingLineSpec chc = ZetaOrganogramTerritoryLoader.trainingLineSpecs()[1];
        TrainingManagerDemoSeed.testManagerIdByKey = new Map<String, Id>{ chc.key => manager.Id };
        TrainingManagerDemoSeed.testRepIdsByKey = new Map<String, List<Id>>{ chc.key => new List<Id>{ rep.Id } };

        Territory2 line = [SELECT Id FROM Territory2 WHERE External_ID__c = :chc.lineExternalId LIMIT 1];
        Product2 product = new Product2(Name = 'Demo Brand', IsActive = true);
        insert product;
        String lineKey = String.valueOf(line.Id);
        insert new Promo_Grid_Product_Weight__c(
            Territory2_Id__c = lineKey,
            Product2__c = product.Id,
            Weight_Percentage__c = 100,
            Unique_Key__c = (lineKey + ':' + product.Id).left(80)
        );
        insert new Promo_Grid_Class_Targeting__c(
            Territory2_Id__c = lineKey,
            Class__c = 'A1',
            List_Percentage__c = 20,
            Target_Monthly_Visits__c = 12,
            Unique_Key__c = (lineKey + ':A1').left(40)
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<String> aligned = TrainingManagerDemoSeed.alignUsers();
            System.assert(!aligned.isEmpty());
        }

        Test.startTest();
        TrainingManagerDemoSeed.SeedResult result = TrainingManagerDemoSeed.run();
        Test.stopTest();

        System.assert(result.bookAccounts > 0, result.summary());
        System.assert(result.repCycles > 0, result.summary());
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Classification_Cycle__c
                WHERE Employee__c = :manager.Id AND Status__c = 'Draft'
            ],
            result.summary()
        );
        System.assert(
            [SELECT COUNT() FROM Classification_Cycle__c WHERE Employee__c = :rep.Id AND Status__c = 'Submitted'] > 0,
            result.summary()
        );
        System.assert(
            [SELECT COUNT() FROM Account WHERE OwnerId = :rep.Id AND Account_Stage__c = 'Pending DM'] > 0,
            result.summary()
        );
        System.assertEquals(rep.Id, [SELECT Id FROM User WHERE Id = :rep.Id AND ManagerId = :manager.Id].Id);
    }
}