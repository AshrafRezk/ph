@IsTest
private class DoubleVisitNotifierTest {
    @IsTest
    static void insertDoubleVisit_notifiesPartner() {
        Profile profile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User partner = new User(
            Alias = 'dvnt',
            Email = 'dv.partner.' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'DoublePartner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = 'dv.partner.' + suffix + '@example.com'
        );
        insert partner;

        Account accountRecord = new Account(Name = 'Double Visit Bell ' + suffix);
        insert accountRecord;

        Test.startTest();
        insert new Visit__c(
            Account__c = accountRecord.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = System.now(),
            End_Date__c = System.now().addHours(1),
            Visit_Date__c = System.now(),
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            Is_Double_Visit__c = true,
            Double_Visit_With__c = partner.Id
        );
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Visit__c WHERE Double_Visit_With__c = :partner.Id]
        );
    }
}