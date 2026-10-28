@IsTest
private class AccountHcpGeocodeBatchTest {
    @IsTest
    static void copiesWorkplaceCoordinatesOntoHcp() {
        Id hcpRtId = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account' AND IsPersonType = TRUE AND IsActive = TRUE
            LIMIT 1
        ].Id;
        Id hcoRtId = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account' AND DeveloperName = 'Institution_HCO' AND IsActive = TRUE
            LIMIT 1
        ].Id;

        Account clinic = new Account(
            RecordTypeId = hcoRtId,
            Name = 'Clinic With Geo',
            BillingCity = 'Cairo',
            BillingCountry = 'Egypt',
            BillingLatitude = 30.0444,
            BillingLongitude = 31.2357
        );
        Account hcp = new Account(
            RecordTypeId = hcpRtId,
            FirstName = 'Geo',
            LastName = 'Doctor'
        );
        insert as system new List<Account>{ clinic, hcp };
        insert as system new Account_Affiliation__c(
            Primary_Account__c = hcp.Id,
            Related_Account__c = clinic.Id,
            Affiliation_Type__c = 'Practice',
            Is_Active__c = true,
            Is_Primary__c = true
        );

        Test.startTest();
        Id jobId = AccountHcpGeocodeFromAffiliationBatch.run();
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        Account updated = [
            SELECT BillingLatitude, BillingLongitude, BillingCountry
            FROM Account
            WHERE Id = :hcp.Id
        ];
        System.assertEquals(30.0444, updated.BillingLatitude);
        System.assertEquals(31.2357, updated.BillingLongitude);
        System.assertEquals('Egypt', updated.BillingCountry);
    }
}