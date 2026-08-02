@IsTest
private class ChemipharmDemoDataProfilesTest {

    @IsTest
    static void getUserProfile_returnsCnsMr() {
        ChemipharmDemoDataProfiles.DemoUserProfile profile = ChemipharmDemoDataProfiles.getUserProfile('cns_mr');
        System.assertNotEquals(null, profile);
        System.assertEquals('Fatma', profile.firstName);
        System.assertEquals('Fawzy Mohamed Mahmoud', profile.lastName);
        System.assertEquals(127, profile.febActualVisits);
        System.assertEquals(Date.newInstance(2024, 1, 1), profile.hireDate);
    }

    @IsTest
    static void getMonthlyVisitVolume_variesAroundFebBaseline() {
        System.assertEquals(127, ChemipharmDemoDataProfiles.getMonthlyVisitVolume('cns_mr', 1));
        System.assert(ChemipharmDemoDataProfiles.getMonthlyVisitVolume('chc_mr', 1) > 0);
        System.assert(ChemipharmDemoDataProfiles.getMonthlyVisitVolume('git_mr', 0) > 0);
    }

    @IsTest
    static void resolveDemoUserKeyFromUsername_mapsPharmaDemoUser() {
        System.assertEquals(
            'cns_mr',
            ChemipharmDemoDataProfiles.resolveDemoUserKeyFromUsername('diabetes.mr@pharma.demo')
        );
    }

    @IsTest
    static void cnsSalesTotals_stillExposedForLegacyCallers() {
        System.assertEquals(736560.0, ChemipharmDemoDataProfiles.getDiabetesSalesTargetEgp());
        System.assert(ChemipharmDemoDataProfiles.getDiabetesSalesActualEgp() > 600000);
    }

    @IsTest
    static void getCoachingScores_returnsTieredProgression() {
        List<Decimal> high = ChemipharmDemoDataProfiles.getCoachingScores('git_mr');
        List<Decimal> low = ChemipharmDemoDataProfiles.getCoachingScores('chc_mr');
        System.assertEquals(6, high.size());
        System.assert(high[5] > low[5]);
    }
}
