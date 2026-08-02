@IsTest
private class RatingValidityFallbackTest {
    @IsTest
    static void build_returnsOfflineEstimate_forHcpRatings() {
        RatingValidityTypes.ValidationContext context = new RatingValidityTypes.ValidationContext();
        context.accountVariant = ClmRatingLayoutService.VARIANT_HCP;
        context.territoryRatings = new Map<String, Object>{
            'Potential__c' => 'A',
            'Penetration__c' => '2',
            'Matrix_Rating__c' => 'a2',
            'Classification__c' => 'A',
            'Is_KOL__c' => true,
            'KOL_In_What__c' => 'High Prescriber'
        };

        Test.startTest();
        RatingValidityTypes.RatingValidityResult result = RatingValidityFallback.build(context);
        Test.stopTest();

        System.assertEquals(true, result.usedFallback);
        System.assertEquals(RatingValidityTypes.SOURCE_FALLBACK, result.source);
        System.assertNotEquals(null, result.validityScore);
        System.assert(result.validityScore >= 0 && result.validityScore <= 100);
        System.assert(!result.reasons.isEmpty());
        System.assertEquals(RatingValidityFallback.FALLBACK_MESSAGE, result.fallbackMessage);
    }

    @IsTest
    static void build_penalizesKolWithLowPotential_forHcp() {
        RatingValidityTypes.ValidationContext context = new RatingValidityTypes.ValidationContext();
        context.accountVariant = ClmRatingLayoutService.VARIANT_HCP;
        context.territoryRatings = new Map<String, Object>{
            'Potential__c' => 'C',
            'Penetration__c' => '1',
            'Is_KOL__c' => true,
            'KOL_In_What__c' => 'High Prescriber'
        };

        Test.startTest();
        RatingValidityTypes.RatingValidityResult result = RatingValidityFallback.build(context);
        Test.stopTest();

        System.assert(result.validityScore < 70);
    }

    @IsTest
    static void build_penalizesHcoKolConflict() {
        RatingValidityTypes.ValidationContext context = new RatingValidityTypes.ValidationContext();
        context.accountVariant = ClmRatingLayoutService.VARIANT_HCO;
        context.territoryRatings = new Map<String, Object>{
            'Potential__c' => 'C',
            'Penetration__c' => '1',
            'Has_KOLs__c' => true,
            'KOL_Profile__c' => 'Academic Leaders'
        };

        Test.startTest();
        RatingValidityTypes.RatingValidityResult result = RatingValidityFallback.build(context);
        Test.stopTest();

        System.assert(result.validityScore < 70);
        System.assert(result.summary.contains('Offline'));
    }
}
