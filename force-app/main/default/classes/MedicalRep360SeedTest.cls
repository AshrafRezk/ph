@IsTest
private class MedicalRep360SeedTest {

    @IsTest
    static void seedDemoData_returnsResultMessage() {
        Test.startTest();
        MedicalRep360Seed.SeedResult result = MedicalRep360Seed.seedDemoData();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(String.isNotBlank(result.message));
    }

    @IsTest
    static void monthlyVolumes_useZetaDemoProfiles() {
        System.assertEquals(127, ChemipharmDemoDataProfiles.getMonthlyVisitVolume('diabetes_mr', 1));
        System.assertEquals(0, ChemipharmDemoDataProfiles.getMonthlyVisitVolume('chc_mr', 1));
    }

    @IsTest
    static void amrCoachingScores_declineOverSixMonths() {
        List<Decimal> scores = ChemipharmDemoDataProfiles.getCoachingScores('amr_mr');
        System.assertEquals(6, scores.size());
        System.assert(scores[0] > scores[5], 'Amr should decline from Jan to Jun');
    }

    @IsTest
    static void mapFrequencyPicklist_mapsWeekly() {
        System.assertEquals(4, EmployeeTimeCardService.mapFrequencyPicklist('Weekly'));
    }
}
