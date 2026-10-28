@IsTest(SeeAllData = false)
private class Product2CatalogServiceTest {
    @IsTest
    static void isBrandManagerRole_matchesBrandValues() {
        Assert.isTrue(Product2CatalogService.isBrandManagerRole('brand'));
        Assert.isTrue(Product2CatalogService.isBrandManagerRole('Brand Manager'));
        Assert.isFalse(Product2CatalogService.isBrandManagerRole('Medical Rep'));
    }

    @IsTest
    static void applyBrandReminderOwnership_setsOwnerFromLineAssignment() {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User' OR Name = 'Standard'
            LIMIT 1
        ];
        User brandManager = new User(
            Alias = 'bmgr',
            Email = 'brand.manager@test.example',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Brand Manager Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'brand.manager.test'
                + String.valueOf(Math.abs(Crypto.getRandomInteger()))
                + '@pharma.test.example'
        );
        insert brandManager;

        List<Territory2> lines = [
            SELECT Id, Name, External_ID__c
            FROM Territory2
            WHERE Territory_Type__c = 'Line'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (lines.isEmpty()) {
            return;
        }

        insert new UserTerritory2Association(
            Territory2Id = lines[0].Id,
            UserId = brandManager.Id,
            RoleInTerritory2 = 'brand'
        );

        Product2 brand = new Product2(
            Name = 'Owner Brand',
            ProductCode = 'OWNBR',
            External_ID__c = 'OWNBR_EXT',
            Product_Type__c = 'Brand',
            Sales_Line__c = lines[0].Name,
            IsActive = true
        );
        insert brand;

        Product2 detail = new Product2(
            Name = 'Owner Detail',
            ProductCode = 'OWNDET',
            External_ID__c = 'OWNDET_EXT',
            Product_Type__c = 'Detail',
            Parent_Product__c = brand.Id,
            Sales_Line__c = lines[0].Name,
            IsActive = true
        );
        insert detail;

        Product2 reminder = new Product2(
            Name = 'Owner Reminder',
            ProductCode = 'OWNREM',
            External_ID__c = 'OWNREM_EXT',
            Product_Type__c = 'Brand Reminder',
            Parent_Product__c = detail.Id,
            Sales_Line__c = lines[0].Name,
            IsActive = true
        );

        Test.startTest();
        insert reminder;
        Test.stopTest();

        Product2 saved = [
            SELECT Brand_Manager__c
            FROM Product2
            WHERE Id = :reminder.Id
        ];
        Assert.areEqual(brandManager.Id, saved.Brand_Manager__c);
    }
}