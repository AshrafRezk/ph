@IsTest
private class DistributorSelloutRematchServiceTest {
    private static Account pharmacy(String name, Decimal lat, Decimal lng) {
        Account a = new Account(Name = name, BillingLatitude = lat, BillingLongitude = lng);
        for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (info.isAvailable() && info.getDeveloperName() == 'Pharmacy') {
                a.RecordTypeId = info.getRecordTypeId();
            }
        }
        return a;
    }

    private static Distributor_Sellout_Alias__c alias(String clientCode, String name, String brick, Decimal lat, Decimal lng) {
        return new Distributor_Sellout_Alias__c(
            Distributor_Code__c = 'IBNSINA',
            Distributor_Client_Code__c = clientCode,
            Distributor_Client_Name__c = name,
            Brick_Code__c = brick,
            Latitude__c = lat,
            Longitude__c = lng,
            Status__c = 'Unmatched',
            Unique_Key__c = 'IBNSINA|' + clientCode
        );
    }

    @IsTest
    static void brickAndArabicSpellingConfirm_nameOnlyOnlySuggests() {
        Account inBrick = pharmacy('صيدلية أحمد حسن', null, null);
        Account elsewhere = pharmacy('Mostafa Wahba Pharmacy', null, null);
        Account decoy = pharmacy('Ahmed Hussein Pharmacy', null, null);
        insert as system new List<Account>{ inBrick, elsewhere, decoy };

        Brick__c brick = new Brick__c(Name = 'Rematch Brick', Brick_Code__c = 'RM-1', Is_Active__c = true);
        insert as system brick;
        insert as system new Brick_Pharmacy__c(
            Brick__c = brick.Id,
            Pharmacy_Account__c = inBrick.Id,
            Unique_Key__c = brick.Id + ':' + inBrick.Id,
            Is_Active__c = true
        );

        insert as system new List<Distributor_Sellout_Alias__c>{
            alias('C1', 'Ahmed Hassan Pharmacy', 'RM-1', null, null),
            alias('C2', 'Wahba Mostafa', 'NOPE', null, null),
            alias('C3', 'Totally Different Name', 'RM-1', null, null)
        };

        Test.startTest();
        DistributorSelloutRematchService.RematchResult res = DistributorSelloutRematchService.rematch('IBNSINA', 50);
        Test.stopTest();

        System.assertEquals(3, res.examined);
        System.assertEquals(null, res.errors, res.message);
        Map<String, Distributor_Sellout_Alias__c> byCode = new Map<String, Distributor_Sellout_Alias__c>();
        for (Distributor_Sellout_Alias__c a : [
            SELECT Distributor_Client_Code__c, Pharmacy_Account__c, Status__c, Match_Method__c
            FROM Distributor_Sellout_Alias__c
            WHERE Distributor_Code__c = 'IBNSINA'
        ]) {
            byCode.put(a.Distributor_Client_Code__c, a);
        }
        // Same brick + the Arabic/English spelling of the same name: confirmed to the brick pharmacy, not the Hussein decoy.
        System.assertEquals(inBrick.Id, byCode.get('C1').Pharmacy_Account__c);
        System.assertEquals('Confirmed', byCode.get('C1').Status__c);
        System.assertEquals('BrickCode', byCode.get('C1').Match_Method__c);
        // No brick corroboration: never auto-confirmed.
        System.assertNotEquals('Confirmed', byCode.get('C2').Status__c);
        // Unrelated name stays unmatched.
        System.assertEquals(null, byCode.get('C3').Pharmacy_Account__c);
        System.assertEquals('Unmatched', byCode.get('C3').Status__c);
    }

    @IsTest
    static void confirmedAliasesAreNeverTouched() {
        Account a = pharmacy('Keep Pharmacy', null, null);
        insert as system a;
        Distributor_Sellout_Alias__c rejected = alias('R1', 'Keep Pharmacy', null, null, null);
        rejected.Status__c = 'Rejected';
        insert as system rejected;

        DistributorSelloutRematchService.RematchResult res = DistributorSelloutRematchService.rematch('IBNSINA', null);
        System.assertEquals(0, res.examined);
        System.assertEquals(null, [SELECT Pharmacy_Account__c FROM Distributor_Sellout_Alias__c WHERE Id = :rejected.Id].Pharmacy_Account__c);
    }

    @IsTest
    static void cleanNameDropsPharmacyFiller() {
        System.assertEquals('', DistributorSelloutRematchService.cleanName(null));
        System.assert(!DistributorSelloutRematchService.cleanName('Wahba Pharmacy').contains('PHARMACY'));
        System.assert(!DistributorSelloutRematchService.cleanName('صيدلية وهبة').contains('صيدلية'));
    }
}
