@IsTest
private class TerritoryAlignmentModuleSeedTest {

    @IsTest
    static void seedDemoData_createsLayoutsAndRatings() {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return;
        }

        Territory2Model model = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        Territory2 territory = new Territory2(
            Name = 'Rating Seed Territory',
            DeveloperName = 'Rating_Seed_Territory',
            Territory2ModelId = model.Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = 'TERR_RATING_SEED_MR'
        );
        insert territory;

        Id personRtId = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account'
                AND DeveloperName = 'SDO_PersonAccounts'
                AND IsActive = true
            LIMIT 1
        ].Id;

        Account hcp = new Account(
            RecordTypeId = personRtId,
            FirstName = 'Rating',
            LastName = 'Seed HCP',
            External_ID__c = 'DEMO_HCP_RATING_TEST',
            Account_Status__c = 'Active'
        );
        insert hcp;

        insert new ObjectTerritory2Association(
            ObjectId = hcp.Id,
            Territory2Id = territory.Id,
            AssociationCause = 'Territory2Manual'
        );

        Product2 product = new Product2(
            Name = 'Rating Seed Product',
            IsActive = true,
            ProductCode = 'RSP-001'
        );
        insert product;

        Test.startTest();
        TerritoryAlignmentModuleSeed.SeedResult result = TerritoryAlignmentModuleSeed.seedDemoData();
        Test.stopTest();

        System.assertNotEquals(null, result.message);
        System.assertEquals(2, [
            SELECT COUNT()
            FROM Account_Rating_Layout__c
            WHERE External_Id__c LIKE 'DEMO_%'
        ]);
        System.assert([
            SELECT COUNT()
            FROM Account_Territory_Fields__c
            WHERE Account__c = :hcp.Id
        ] > 0);
    }
}
