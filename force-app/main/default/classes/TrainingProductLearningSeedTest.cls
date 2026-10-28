@IsTest
private class TrainingProductLearningSeedTest {
    @IsTest
    static void run_assignsProductCoursesOnTrainingTerritory() {
        User learner = createLearner();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Territory2 territory = createTrainingTerritory();
            if (territory == null) {
                TrainingProductLearningSeed.SeedResult skipped = TrainingProductLearningSeed.run();
                System.assertEquals(4, skipped.courses);
                return;
            }
            insert new List<UserTerritory2Association>{
                new UserTerritory2Association(
                    UserId = UserInfo.getUserId(),
                    Territory2Id = territory.Id,
                    RoleInTerritory2 = 'District Manager'
                ),
                new UserTerritory2Association(
                    UserId = learner.Id,
                    Territory2Id = territory.Id,
                    RoleInTerritory2 = 'Medical Rep'
                )
            };

            Test.startTest();
            TrainingProductLearningSeed.SeedResult result = TrainingProductLearningSeed.run();
            TrainingProductLearningSeed.SeedResult again = TrainingProductLearningSeed.run();
            Test.stopTest();

            System.assertEquals(4, result.courses, result.summary());
            System.assert(result.users >= 2, result.summary());
            System.assert(result.instancesCreated > 0, result.summary());
            System.assertEquals(0, again.instancesCreated, 'A second run should not duplicate assignments.');
            Integer materials = [
                SELECT COUNT()
                FROM Learning_Material__c
                WHERE Title__c IN (
                    'DOZOVA Ashwagandha 600 — CHC',
                    'EMPACOZA 25 mg — Diabetes',
                    'NEXICURE 40 mg — GIT',
                    'NEXIBRONCH Syrup — Pedia'
                )
            ];
            System.assertEquals(4, materials);
        }
    }

    private static Territory2 createTrainingTerritory() {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        if (types.isEmpty() || models.isEmpty()) {
            return null;
        }
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Territory2 territory = new Territory2(
            Name = 'Learning Seed Territory',
            DeveloperName = 'LearnSeed_' + suffix,
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = 'TERR_TRAINING_SEED_' + suffix
        );
        insert territory;
        return territory;
    }

    private static User createLearner() {
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniq = 'learnseed' + String.valueOf(Datetime.now().getTime());
        User learner = new User(
            Alias = 'lrnseed',
            Email = uniq + '@example.com.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Learning Seed',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = uniq + '@example.com.invalid'
        );
        insert learner;
        return learner;
    }
}