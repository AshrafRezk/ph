@IsTest
private class PharmacyProximityShareServiceTest {
    @IsTest
    static void distanceWeightsFavorTheCloserPharmacy() {
        List<Decimal> shares = PharmacyProximityShareService.sharesForDistances(
            new List<Decimal>{ 80, 200, 450 }
        );
        System.assertEquals(3, shares.size());
        System.assert(shares[0] > shares[1]);
        System.assert(shares[1] > shares[2]);
        System.assertEquals(100, shares[0] + shares[1] + shares[2]);
    }

    @IsTest
    static void nearbyShareRequiresARatingAndRespectsFiveHundredMetres() {
        Id doctorRt = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account' AND IsPersonType = TRUE AND IsActive = TRUE
            LIMIT 1
        ].Id;
        Id pharmacyRt = AccountMasterImportUtil.recordTypeId('Pharmacy', false);
        Account doctor = new Account(
            RecordTypeId = doctorRt,
            FirstName = 'Ahmed',
            LastName = 'Share Test',
            BillingLatitude = 30.0444,
            BillingLongitude = 31.2357
        );
        Account unrated = new Account(
            RecordTypeId = doctorRt,
            FirstName = 'No',
            LastName = 'Rating',
            BillingLatitude = 30.0444,
            BillingLongitude = 31.2357
        );
        Account near = new Account(
            RecordTypeId = pharmacyRt,
            Name = 'Near Pharmacy Share',
            BillingLatitude = 30.0451,
            BillingLongitude = 31.2357
        );
        Account mid = new Account(
            RecordTypeId = pharmacyRt,
            Name = 'Mid Pharmacy Share',
            BillingLatitude = 30.0468,
            BillingLongitude = 31.2357
        );
        Account far = new Account(
            RecordTypeId = pharmacyRt,
            Name = 'Far Pharmacy Share',
            BillingLatitude = 30.07,
            BillingLongitude = 31.2357
        );
        insert new List<Account>{ doctor, unrated, near, mid, far };

        Product2 product = new Product2(Name = 'Empacoza Share', IsActive = true);
        insert product;
        insert new Account_Territory_Product_Fields__c(
            Account__c = doctor.Id,
            Territory2_Id__c = '0MI000000000001AAA',
            Product2_Id__c = String.valueOf(product.Id),
            Adoption__c = 'H',
            Loyalty__c = 'M',
            Rx_Per_Week__c = 4,
            Is_Active__c = true
        );

        PharmacyProximityShareService.DoctorReview blocked =
            PharmacyProximityShareService.refreshNearbyShares(unrated.Id);
        System.assertEquals(false, blocked.hasRating);
        System.assertEquals(0, blocked.pharmacies.size());

        Test.startTest();
        PharmacyProximityShareService.DoctorReview built =
            PharmacyProximityShareService.refreshNearbyShares(doctor.Id);
        Test.stopTest();

        System.assertEquals(true, built.hasRating);
        System.assert(built.ratedProducts.contains('Empacoza Share'));
        System.assertEquals(2, built.pharmacies.size(), built.message);
        System.assertEquals(100, built.shareTotal);
        System.assert(built.pharmacies[0].distanceMeters < built.pharmacies[1].distanceMeters);
        System.assert(built.pharmacies[0].orderSharePercent > built.pharmacies[1].orderSharePercent);

        String payload =
            '[{"affiliationId":"' +
            built.pharmacies[0].affiliationId +
            '","orderSharePercent":60},{"affiliationId":"' +
            built.pharmacies[1].affiliationId +
            '","orderSharePercent":40}]';
        PharmacyProximityShareService.DoctorReview saved =
            PharmacyProximityShareService.saveOrderShares(doctor.Id, payload);
        System.assertEquals(60, saved.pharmacies[0].orderSharePercent);
        System.assertEquals(40, saved.pharmacies[1].orderSharePercent);

        List<PharmacyProximityShareService.DoctorOption> found =
            PharmacyProximityShareService.searchRatedDoctors('Share Test');
        System.assertEquals(1, found.size());
    }
}
