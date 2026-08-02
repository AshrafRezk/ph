@IsTest
private class RatingValidityServiceTest {
    @IsTest
    static void validate_usesFallbackWhenEinsteinUnavailable() {
        Account account = new Account(Name = 'Validity Fallback Test');
        insert account;

        RatingValidityEinsteinClient.testForceFailure = true;
        RatingValidityEinsteinClient.testResponseJson = null;

        String liveRatingsJson = JSON.serialize(
            new Map<String, Object>{
                'territory' => new Map<String, Object>{
                    'Potential__c' => 'B',
                    'Penetration__c' => '2'
                },
                'products' => new List<Object>()
            }
        );

        Test.startTest();
        RatingValidityTypes.RatingValidityResult result =
            RatingValidityService.validate(account.Id, liveRatingsJson);
        Test.stopTest();

        System.assertEquals(true, result.usedFallback);
        System.assertEquals(RatingValidityTypes.SOURCE_FALLBACK, result.source);
        System.assertNotEquals(null, result.fallbackMessage);
    }

    @IsTest
    static void validate_usesAgentforceWhenEinsteinSucceeds() {
        Account account = new Account(Name = 'Validity Agentforce Test');
        insert account;

        RatingValidityEinsteinClient.testForceFailure = false;
        RatingValidityEinsteinClient.testResponseJson = JSON.serialize(
            new Map<String, Object>{
                'validityScore' => 82,
                'summary' => 'Ratings align with public profile.',
                'reasons' => new List<String>{ 'Specialty matches', 'KOL signals align' }
            }
        );

        String liveRatingsJson = JSON.serialize(
            new Map<String, Object>{
                'territory' => new Map<String, Object>{
                    'Potential__c' => 'A',
                    'Penetration__c' => '2',
                    'Is_KOL__c' => true
                },
                'products' => new List<Object>()
            }
        );

        Test.startTest();
        RatingValidityTypes.RatingValidityResult result =
            RatingValidityService.validate(account.Id, liveRatingsJson);
        Test.stopTest();

        System.assertEquals(false, result.usedFallback);
        System.assertEquals(RatingValidityTypes.SOURCE_AGENTFORCE, result.source);
        System.assertEquals(82, result.validityScore);
        System.assertEquals('Ratings align with public profile.', result.summary);
        System.assertEquals(2, result.reasons.size());
    }

    @IsTest
    static void hasMeaningfulRatings_detectsTerritoryAndProductValues() {
        String territoryOnly = JSON.serialize(
            new Map<String, Object>{
                'territory' => new Map<String, Object>{ 'Potential__c' => 'A' },
                'products' => new List<Object>()
            }
        );
        System.assertEquals(true, RatingValidityService.hasMeaningfulRatings(territoryOnly));

        String productOnly = JSON.serialize(
            new Map<String, Object>{
                'territory' => new Map<String, Object>(),
                'products' => new List<Object>{
                    new Map<String, Object>{
                        'product2Id' => '01t000000000001AAA',
                        'values' => new Map<String, Object>{ 'Adoption__c' => 'H' }
                    }
                }
            }
        );
        System.assertEquals(true, RatingValidityService.hasMeaningfulRatings(productOnly));
        System.assertEquals(false, RatingValidityService.hasMeaningfulRatings(''));
    }
}
