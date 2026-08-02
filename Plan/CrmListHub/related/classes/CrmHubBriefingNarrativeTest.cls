@IsTest
private class CrmHubBriefingNarrativeTest {
    private static Map<String, Object> samplePayload(String audience) {
        return new Map<String, Object>{
            'audience' => audience,
            'startDate' => String.valueOf(Date.today()),
            'endDate' => String.valueOf(Date.today()),
            'objects' => new List<Object>{
                new Map<String, Object>{
                    'api' => 'Opportunity',
                    'label' => 'Opportunities',
                    'createdTotal' => 2,
                    'modifiedTotal' => 3,
                    'highlights' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'Acme Renewal',
                            'account' => 'Acme',
                            'amount' => 50000,
                            'stage' => 'Negotiation',
                            'primaryAe' => 'Alex',
                            'nextStep' => 'Send SOW'
                        }
                    }
                },
                new Map<String, Object>{
                    'api' => 'Job_Application__c',
                    'label' => 'Job Applications',
                    'createdTotal' => 4,
                    'modifiedTotal' => 1,
                    'highlights' => new List<Object>(),
                    'createdByPosition' => new List<Object>{
                        new Map<String, Object>{ 'name' => 'Consultant', 'count' => 3 }
                    }
                }
            },
            'insights' => new Map<String, Object>{
                'pipelineAmount' => 120000,
                'closingThisWeek' => new List<Object>(),
                'topDeals' => new List<Object>{
                    new Map<String, Object>{
                        'name' => 'Mega Deal',
                        'amount' => 90000,
                        'stage' => 'Proposal'
                    }
                },
                'opportunityStages' => new List<Object>{
                    new Map<String, Object>{ 'name' => 'Proposal', 'count' => 4 }
                },
                'leadStatuses' => new List<Object>()
            },
            'actions' => new Map<String, Object>{
                'overdueTaskCount' => 2,
                'dueTodayTaskCount' => 1,
                'overdueTasks' => new List<Object>{
                    new Map<String, Object>{ 'name' => 'Call CFO' }
                },
                'dueTodayTasks' => new List<Object>(),
                'eventsToday' => new List<Object>{
                    new Map<String, Object>{ 'name' => 'Standup' }
                },
                'oppsClosingToday' => new List<Object>(),
                'oppsNextActionDue' => new List<Object>(),
                'staleOpps' => new List<Object>(),
                'focusToday' => new List<Object>(),
                'focusTodayCount' => 0
            }
        };
    }

    private static Map<String, Object> hrFocusPayload() {
        Map<String, Object> payload = samplePayload('hr');
        Map<String, Object> actions = (Map<String, Object>) payload.get('actions');
        actions.put(
            'focusToday',
            new List<Object>{
                new Map<String, Object>{
                    'kind' => 'hr_screening_gap',
                    'title' => 'Schedule screening',
                    'reason' =>
                        'Schedule screening interview for Ada Lovelace on open position Consultant.',
                    'recordName' => 'Ada Lovelace',
                    'objectApi' => 'Job_Application__c'
                }
            }
        );
        actions.put('focusTodayCount', 1);
        return payload;
    }

    @IsTest
    static void truncatesAndBuildsDenseScript() {
        Map<String, Object> payload = samplePayload('sales');
        CrmHubBriefingNarrative.forceDenseOnly = true;
        Test.startTest();
        Map<String, String> texts = CrmHubBriefingNarrative.buildBriefingTexts(payload, 'everything');
        Test.stopTest();
        System.assert(String.isNotBlank(texts.get('digestText')));
        System.assert(String.isNotBlank(texts.get('scriptText')));
        System.assert(texts.get('scriptText').length() <= CrmHubBriefingNarrative.MAX_SPEECH_CHARS);
        System.assert(texts.get('digestText').length() <= CrmHubBriefingNarrative.MAX_DIGEST_CHARS);
        System.assert(!texts.get('digestText').toLowerCase().contains('good morning'));
        System.assert(texts.get('digestText').contains('Sales manager'));
        System.assertEquals('dense', texts.get('narrativeSource'));
    }

    @IsTest
    static void audienceFramingDiffers() {
        CrmHubBriefingNarrative.forceDenseOnly = true;
        String sales = CrmHubBriefingNarrative.buildDenseTemplate(samplePayload('sales'), 'everything');
        String ceo = CrmHubBriefingNarrative.buildDenseTemplate(samplePayload('ceo'), 'everything');
        String hr = CrmHubBriefingNarrative.buildDenseTemplate(samplePayload('hr'), 'everything');
        String ops = CrmHubBriefingNarrative.buildDenseTemplate(samplePayload('ops'), 'actToday');
        System.assert(sales.contains('Sales manager'));
        System.assert(ceo.contains('CEO'));
        System.assert(hr.contains('HR manager'));
        System.assert(hr.contains('Job Applications') || hr.contains('Apps by position'));
        System.assert(ops.contains('Operations') || ops.contains('overdue') || ops.contains('meeting'));
        System.assert(ceo.contains('Pipeline exposure') || ceo.contains('Largest open bets') || ceo.contains('Hiring capacity'));
    }

    @IsTest
    static void hrFocusTodayAppearsInDigest() {
        CrmHubBriefingNarrative.forceDenseOnly = true;
        String digest = CrmHubBriefingNarrative.buildDenseTemplate(hrFocusPayload(), 'everything');
        System.assert(digest.contains('Focus today'), 'Expected Focus today section: ' + digest);
        System.assert(
            digest.contains('Schedule screening interview'),
            'Expected screening recommendation: ' + digest
        );
        System.assert(
            CrmHubBriefingNarrative.audienceGuidance('hr').contains('Focus today'),
            'Audience guidance should require Focus today'
        );
    }

    @IsTest
    static void truncateDenseCutsAtSentence() {
        String longText = '';
        for (Integer i = 0; i < 40; i++) {
            longText += 'Deal ' + i + ' is hot. ';
        }
        String cut = CrmHubBriefingNarrative.truncateDense(longText);
        System.assert(cut.length() <= CrmHubBriefingNarrative.MAX_SPEECH_CHARS);
        String digestCut = CrmHubBriefingNarrative.truncateTo(longText, CrmHubBriefingNarrative.MAX_DIGEST_CHARS);
        System.assert(digestCut.length() <= CrmHubBriefingNarrative.MAX_DIGEST_CHARS);
    }

    @IsTest
    static void usesNarrativeOverrideAndNullPayload() {
        CrmHubBriefingNarrative.narrativeOverride =
            'Pipeline is 1.2M. Two overdue tasks. Acme closes Friday.';
        CrmHubBriefingNarrative.promptTemplateApiNameOverride = 'none';
        Test.startTest();
        String overridden = CrmHubBriefingNarrative.buildSpokenScript(
            new Map<String, Object>(),
            'actToday'
        );
        String empty = CrmHubBriefingNarrative.buildDenseTemplate(null, null);
        String agent = CrmHubBriefingNarrative.invokeAgentforce(
            new Map<String, Object>(),
            'everything',
            'fallback'
        );
        CrmHubBriefingNarrative.promptTemplateApiNameOverride = 'Hub_Briefing_Flex';
        String agentNamed = CrmHubBriefingNarrative.invokeAgentforce(
            new Map<String, Object>(),
            'everything',
            'fallback'
        );
        Test.stopTest();
        System.assertEquals(
            'Pipeline is 1.2M. Two overdue tasks. Acme closes Friday.',
            overridden
        );
        System.assertEquals('No briefing data.', empty);
        System.assertEquals(null, agent);
        System.assertEquals(null, agentNamed);
    }

    @IsTest
    static void agentforceOverrideProducesDigest() {
        CrmHubBriefingNarrative.forceDenseOnly = false;
        CrmHubBriefingNarrative.narrativeOverride = null;
        CrmHubBriefingNarrative.promptTemplateApiNameOverride = 'Hub_Briefing_Flex';
        CrmHubBriefingNarrative.testAgentforceResponseOverride =
            'Sales focus: Acme Renewal at 50k needs SOW this week. Watch stale pipeline.';
        CrmHubBriefingNarrative.skipConnectApi = true;
        Test.startTest();
        Map<String, String> texts = CrmHubBriefingNarrative.buildBriefingTexts(
            samplePayload('sales'),
            'everything'
        );
        Test.stopTest();
        System.assertEquals('agentforce', texts.get('narrativeSource'));
        System.assert(texts.get('digestText').contains('Acme Renewal'));
        System.assert(texts.get('scriptText').length() <= CrmHubBriefingNarrative.MAX_SPEECH_CHARS);
    }

    @IsTest
    static void normalizeAudienceDefaults() {
        System.assertEquals('sales', CrmHubBriefingNarrative.normalizeAudience(null));
        System.assertEquals('ceo', CrmHubBriefingNarrative.normalizeAudience('CEO'));
        System.assertEquals('sales', CrmHubBriefingNarrative.normalizeAudience('unknown'));
    }
}
