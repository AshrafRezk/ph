/**
 * CRM Hub briefing digests: audience-aware dense rules + optional Agentforce Prompt Template.
 * Speaks a short scriptText; shows a longer digestText on screen.
 *
 * Setup (Agentforce): In Prompt Builder create a Flex template, then set Custom Label
 * CRM_Hub_Briefing_Prompt_Template to that template's API name (or leave "none" for dense-only).
 * Expected input names: Audience, AudienceKey, AudienceGuidance, Preset, BusinessContext,
 * CrmFacts, DenseFallback, MaxDigestChars, Instructions.
 */
public without sharing class CrmHubBriefingNarrative {
    public static final Integer MAX_SPEECH_CHARS = 500;
    public static final Integer MAX_DIGEST_CHARS = 1600;
    public static final String AUDIENCE_SALES = 'sales';
    public static final String AUDIENCE_CEO = 'ceo';
    public static final String AUDIENCE_HR = 'hr';
    public static final String AUDIENCE_OPS = 'ops';

    @TestVisible
    private static String narrativeOverride;
    @TestVisible
    private static Boolean forceDenseOnly = false;
    @TestVisible
    private static String promptTemplateApiNameOverride;
    @TestVisible
    private static String testAgentforceResponseOverride;
    @TestVisible
    private static Boolean skipConnectApi = false;

    /**
     * Build digest (on-screen) + spoken script. Prefer Agentforce when configured.
     */
    public static Map<String, String> buildBriefingTexts(Map<String, Object> payload, String preset) {
        String audience = normalizeAudience(payload == null ? null : (String) payload.get('audience'));
        if (payload != null) {
            payload.put('audience', audience);
            payload.put('audienceLabel', audienceLabel(audience));
            payload.put('audienceGuidance', audienceGuidance(audience));
        }

        if (String.isNotBlank(narrativeOverride)) {
            String ov = stripFiller(narrativeOverride);
            return textsOf(truncateTo(ov, MAX_DIGEST_CHARS), truncateTo(ov, MAX_SPEECH_CHARS), 'override');
        }

        String denseDigest = buildDenseTemplate(payload, preset, MAX_DIGEST_CHARS);
        String denseSpeech = truncateTo(denseDigest, MAX_SPEECH_CHARS);

        if (forceDenseOnly) {
            return textsOf(denseDigest, denseSpeech, 'dense');
        }

        try {
            String ai = invokeAgentforce(payload, preset, denseDigest);
            if (String.isNotBlank(ai)) {
                String cleaned = stripFiller(ai);
                String digest = truncateTo(cleaned, MAX_DIGEST_CHARS);
                String speech = truncateTo(cleaned, MAX_SPEECH_CHARS);
                return textsOf(digest, speech, 'agentforce');
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Agentforce briefing narrative failed: ' + e.getMessage());
        }
        return textsOf(denseDigest, denseSpeech, 'dense');
    }

    /** @deprecated Prefer buildBriefingTexts; kept for callers that need spoken-only. */
    public static String buildSpokenScript(Map<String, Object> payload, String preset) {
        return buildBriefingTexts(payload, preset).get('scriptText');
    }

    public static String normalizeAudience(String raw) {
        String a = String.isBlank(raw) ? AUDIENCE_SALES : raw.trim().toLowerCase();
        if (
            a == AUDIENCE_SALES ||
            a == AUDIENCE_CEO ||
            a == AUDIENCE_HR ||
            a == AUDIENCE_OPS
        ) {
            return a;
        }
        return AUDIENCE_SALES;
    }

    public static String audienceLabel(String audience) {
        String a = normalizeAudience(audience);
        if (a == AUDIENCE_CEO) {
            return 'CEO';
        }
        if (a == AUDIENCE_HR) {
            return 'HR manager';
        }
        if (a == AUDIENCE_OPS) {
            return 'Operations manager';
        }
        return 'Sales manager';
    }

    public static String audienceGuidance(String audience) {
        String a = normalizeAudience(audience);
        String focusRule =
            ' Always end with concrete Focus today recommendations from CrmFacts.actions.focusToday (use those reasons verbatim; never invent records).';
        if (a == AUDIENCE_CEO) {
            return 'Frame for a CEO: revenue risk and upside, concentration, win/loss movement, and hiring only as capacity leverage. Be concise and decision-oriented.' +
                focusRule;
        }
        if (a == AUDIENCE_HR) {
            return 'Frame for an HR manager: positions, job applications, contracts, hiring velocity, bottlenecks, and recruiting pipeline health. Applicants usually arrive as Leads — recommend Create Job Application when a lead on an open position looks legit; then prioritize screening interview dates on open applications.' +
                focusRule;
        }
        if (a == AUDIENCE_OPS) {
            return 'Frame for an operations manager: overdue work, delivery blockers, ownership gaps, meetings today, and SLA-style urgency.' +
                focusRule;
        }
        return 'Frame for a Sales manager: pipeline dollars, stage movement, AE ownership, next steps, stale deals, and what needs action today.' +
            focusRule;
    }

    private static Map<String, String> textsOf(String digest, String speech, String source) {
        return new Map<String, String>{
            'digestText' => digest,
            'scriptText' => speech,
            'narrativeSource' => source
        };
    }

    private static String resolveBriefingPromptTemplateName() {
        if (promptTemplateApiNameOverride != null) {
            return promptTemplateApiNameOverride.trim();
        }
        try {
            String fromLabel = System.Label.CRM_Hub_Briefing_Prompt_Template;
            return String.isBlank(fromLabel) ? 'none' : fromLabel.trim();
        } catch (Exception e) {
            return 'none';
        }
    }

    /**
     * Agentforce / Einstein Prompt Template. Returns null when disabled or unavailable.
     */
    @TestVisible
    private static String invokeAgentforce(
        Map<String, Object> payload,
        String preset,
        String denseFallback
    ) {
        if (String.isNotBlank(testAgentforceResponseOverride)) {
            return testAgentforceResponseOverride;
        }
        String templateApiName = resolveBriefingPromptTemplateName();
        if (String.isBlank(templateApiName) || templateApiName.equalsIgnoreCase('none')) {
            return null;
        }
        if (Test.isRunningTest() || skipConnectApi == true) {
            System.debug(
                LoggingLevel.INFO,
                'Agentforce template ' + templateApiName + ' skipped in test / override.'
            );
            return null;
        }

        String audience = normalizeAudience(payload == null ? null : (String) payload.get('audience'));
        String factsJson = compactFactsJson(payload, preset);
        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
        putWrapped(inputParams, 'Input:Audience', audienceLabel(audience));
        putWrapped(inputParams, 'Input:AudienceKey', audience);
        putWrapped(inputParams, 'Input:AudienceGuidance', audienceGuidance(audience));
        putWrapped(inputParams, 'Input:Preset', String.isBlank(preset) ? 'everything' : preset);
        putWrapped(
            inputParams,
            'Input:BusinessContext',
            payload == null || payload.get('businessContext') == null
                ? 'Cloudastick is a Salesforce consulting and delivery partner.'
                : String.valueOf(payload.get('businessContext'))
        );
        putWrapped(inputParams, 'Input:CrmFacts', factsJson);
        putWrapped(inputParams, 'Input:DenseFallback', denseFallback);
        putWrapped(inputParams, 'Input:MaxDigestChars', String.valueOf(MAX_DIGEST_CHARS));
        putWrapped(
            inputParams,
            'Input:Instructions',
            'Write an informative CRM briefing for the stated audience. Use ONLY facts from CrmFacts / DenseFallback. ' +
                'No greetings, no filler, no invented numbers or names. Prefer decisions and risks. ' +
                'Include a Focus today section using actions.focusToday reasons when present. Soft cap ' +
                MAX_DIGEST_CHARS +
                ' characters.'
        );

        ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        promptInput.isPreview = false;
        promptInput.inputParams = inputParams;
        promptInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        promptInput.additionalConfig.applicationName = 'PromptBuilderPreview';

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
            templateApiName,
            promptInput
        );
        if (output == null || output.generations == null || output.generations.isEmpty()) {
            return null;
        }
        ConnectApi.EinsteinLLMGenerationItemOutput first = output.generations[0];
        return first == null ? null : first.text;
    }

    private static void putWrapped(
        Map<String, ConnectApi.WrappedValue> inputParams,
        String key,
        String value
    ) {
        ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
        wrapped.value = value == null ? '' : value;
        inputParams.put(key, wrapped);
    }

    @TestVisible
    private static String compactFactsJson(Map<String, Object> payload, String preset) {
        if (payload == null) {
            return '{}';
        }
        Map<String, Object> slim = new Map<String, Object>{
            'audience' => payload.get('audience'),
            'preset' => String.isBlank(preset) ? payload.get('mode') : preset,
            'startDate' => payload.get('startDate'),
            'endDate' => payload.get('endDate'),
            'objects' => payload.get('objects'),
            'actions' => payload.get('actions'),
            'insights' => payload.get('insights')
        };
        String json = JSON.serialize(slim);
        if (json.length() > 12000) {
            return json.substring(0, 12000);
        }
        return json;
    }

    @TestVisible
    public static String buildDenseTemplate(Map<String, Object> payload, String preset) {
        return buildDenseTemplate(payload, preset, MAX_DIGEST_CHARS);
    }

    @TestVisible
    public static String buildDenseTemplate(Map<String, Object> payload, String preset, Integer maxChars) {
        if (payload == null) {
            return 'No briefing data.';
        }
        String audience = normalizeAudience((String) payload.get('audience'));
        String mode = String.isBlank(preset) ? 'everything' : preset;
        List<String> lines = new List<String>();
        lines.add(audienceLabel(audience) + ' briefing.');

        List<Object> objects = (List<Object>) payload.get('objects');
        Map<String, Object> actions = (Map<String, Object>) payload.get('actions');
        Map<String, Object> insights = (Map<String, Object>) payload.get('insights');

        Boolean wantSalesLens = audience == AUDIENCE_SALES || audience == AUDIENCE_CEO;
        Boolean wantHrLens = audience == AUDIENCE_HR;
        Boolean wantOpsLens = audience == AUDIENCE_OPS || audience == AUDIENCE_SALES;

        if (mode != 'actToday' && objects != null) {
            for (Object raw : objects) {
                Map<String, Object> row = (Map<String, Object>) raw;
                if (row == null) {
                    continue;
                }
                String api = String.valueOf(row.get('api'));
                if (wantHrLens && !isHrObject(api)) {
                    continue;
                }
                if (audience == AUDIENCE_CEO && isHrObject(api)) {
                    // CEO: only a light hiring signal later
                    continue;
                }
                if (audience == AUDIENCE_OPS && isHrObject(api)) {
                    continue;
                }
                String label = (String) row.get('label');
                Integer createdTotal = toInt(row.get('createdTotal'));
                Integer modifiedTotal = toInt(row.get('modifiedTotal'));
                List<Object> highlights = (List<Object>) row.get('highlights');
                List<Object> recentModified = (List<Object>) row.get('recentModified');

                if (mode != 'moved' && createdTotal > 0) {
                    lines.add(createdTotal + ' new ' + label + '.');
                    appendNamedHighlights(lines, highlights, audience == AUDIENCE_CEO ? 1 : 2, audience);
                }
                if (mode != 'headlines' && modifiedTotal > 0) {
                    lines.add(modifiedTotal + ' updated ' + label + '.');
                    appendNamedHighlights(
                        lines,
                        recentModified != null ? recentModified : highlights,
                        audience == AUDIENCE_CEO ? 1 : 2,
                        audience
                    );
                }
                if (wantHrLens && api == 'Job_Application__c') {
                    appendPositionRollups(lines, (List<Object>) row.get('createdByPosition'));
                }
            }
        }

        if (wantSalesLens && insights != null) {
            Decimal pipeline = toDecimal(insights.get('pipelineAmount'));
            if (pipeline != null && pipeline > 0) {
                if (audience == AUDIENCE_CEO) {
                    lines.add('Pipeline exposure about ' + formatMoney(pipeline) + '.');
                } else {
                    lines.add('Touched pipeline about ' + formatMoney(pipeline) + '.');
                }
            }
            appendDealList(lines, (List<Object>) insights.get('closingThisWeek'), 'Closing this week', audience);
            appendDealList(
                lines,
                (List<Object>) insights.get('topDeals'),
                audience == AUDIENCE_CEO ? 'Largest open bets' : 'Top open deals',
                audience
            );
            List<Object> stages = (List<Object>) insights.get('opportunityStages');
            if (stages != null && !stages.isEmpty() && audience != AUDIENCE_CEO) {
                List<String> bits = new List<String>();
                Integer n = 0;
                for (Object sRaw : stages) {
                    if (n >= 3) {
                        break;
                    }
                    Map<String, Object> s = (Map<String, Object>) sRaw;
                    bits.add(String.valueOf(s.get('count')) + ' in ' + String.valueOf(s.get('name')));
                    n++;
                }
                if (!bits.isEmpty()) {
                    lines.add('Stage mix: ' + String.join(bits, ', ') + '.');
                }
            }
            List<Object> leadStatuses = (List<Object>) insights.get('leadStatuses');
            if (leadStatuses != null && !leadStatuses.isEmpty() && audience == AUDIENCE_SALES) {
                List<String> bits = new List<String>();
                Integer n = 0;
                for (Object sRaw : leadStatuses) {
                    if (n >= 3) {
                        break;
                    }
                    Map<String, Object> s = (Map<String, Object>) sRaw;
                    bits.add(String.valueOf(s.get('count')) + ' ' + String.valueOf(s.get('name')));
                    n++;
                }
                if (!bits.isEmpty()) {
                    lines.add('Lead statuses: ' + String.join(bits, ', ') + '.');
                }
            }
        }

        if (audience == AUDIENCE_CEO && objects != null) {
            Integer hiringSignal = 0;
            for (Object raw : objects) {
                Map<String, Object> row = (Map<String, Object>) raw;
                if (row == null) {
                    continue;
                }
                if (isHrObject(String.valueOf(row.get('api')))) {
                    hiringSignal += toInt(row.get('createdTotal')) + toInt(row.get('modifiedTotal'));
                }
            }
            if (hiringSignal > 0) {
                lines.add('Hiring capacity signal: ' + hiringSignal + ' HR records moved in range.');
            }
        }

        if (
            (mode == 'everything' || mode == 'actToday') &&
            actions != null &&
            (wantOpsLens || audience == AUDIENCE_CEO || audience == AUDIENCE_SALES)
        ) {
            Integer overdueCount = toInt(actions.get('overdueTaskCount'));
            Integer dueTodayCount = toInt(actions.get('dueTodayTaskCount'));
            List<Object> overdue = (List<Object>) actions.get('overdueTasks');
            List<Object> dueToday = (List<Object>) actions.get('dueTodayTasks');
            List<Object> events = (List<Object>) actions.get('eventsToday');
            List<Object> closing = (List<Object>) actions.get('oppsClosingToday');
            List<Object> nextAction = (List<Object>) actions.get('oppsNextActionDue');
            List<Object> stale = (List<Object>) actions.get('staleOpps');

            if (overdueCount == null || overdueCount == 0) {
                overdueCount = overdue == null ? 0 : overdue.size();
            }
            if (dueTodayCount == null || dueTodayCount == 0) {
                dueTodayCount = dueToday == null ? 0 : dueToday.size();
            }
            if (overdueCount > 0 && (wantOpsLens || audience == AUDIENCE_SALES)) {
                lines.add(
                    overdueCount +
                        ' overdue task' +
                        (overdueCount == 1 ? '' : 's') +
                        namedSample(overdue, 2) +
                        '.'
                );
            }
            if (dueTodayCount > 0 && (wantOpsLens || audience == AUDIENCE_SALES)) {
                lines.add(
                    dueTodayCount +
                        ' task' +
                        (dueTodayCount == 1 ? '' : 's') +
                        ' due today' +
                        namedSample(dueToday, 2) +
                        '.'
                );
            }
            if (events != null && !events.isEmpty() && wantOpsLens) {
                lines.add(
                    events.size() +
                        ' meeting' +
                        (events.size() == 1 ? '' : 's') +
                        ' today' +
                        namedSample(events, 2) +
                        '.'
                );
            }
            if (wantSalesLens) {
                appendDealList(lines, closing, 'Closing today', audience);
                appendDealList(lines, nextAction, 'Next-action due', audience);
                appendDealList(lines, stale, 'Stale deals', audience);
            }
        }

        appendFocusToday(lines, actions, audience);

        if (lines.size() <= 1) {
            return truncateTo(
                'Quiet window — no material CRM movement for a ' + audienceLabel(audience) + ' lens.',
                maxChars
            );
        }
        return truncateTo(String.join(lines, ' ').replaceAll('\\s+', ' ').trim(), maxChars);
    }

    @TestVisible
    private static void appendFocusToday(
        List<String> lines,
        Map<String, Object> actions,
        String audience
    ) {
        if (lines == null || actions == null) {
            return;
        }
        List<Object> focus = (List<Object>) actions.get('focusToday');
        if (focus == null || focus.isEmpty()) {
            return;
        }
        Integer maxN = audience == AUDIENCE_CEO ? 3 : 4;
        List<String> bits = new List<String>();
        Integer n = 0;
        for (Object raw : focus) {
            if (n >= maxN) {
                break;
            }
            Map<String, Object> item = (Map<String, Object>) raw;
            if (item == null) {
                continue;
            }
            String reason = item.get('reason') == null ? null : String.valueOf(item.get('reason')).trim();
            if (String.isBlank(reason)) {
                String title = item.get('title') == null ? null : String.valueOf(item.get('title')).trim();
                String recordName = item.get('recordName') == null
                    ? null
                    : String.valueOf(item.get('recordName')).trim();
                if (String.isNotBlank(title) && String.isNotBlank(recordName)) {
                    reason = title + ': ' + recordName + '.';
                } else if (String.isNotBlank(title)) {
                    reason = title + '.';
                }
            }
            if (String.isBlank(reason)) {
                continue;
            }
            if (!reason.endsWith('.') && !reason.endsWith('!') && !reason.endsWith('?')) {
                reason = reason + '.';
            }
            bits.add(reason);
            n++;
        }
        if (!bits.isEmpty()) {
            lines.add('Focus today: ' + String.join(bits, ' '));
        }
    }

    private static Boolean isHrObject(String api) {
        return api == 'Job_Application__c' ||
            api == 'Position__c' ||
            api == 'Employment_Contract__c';
    }

    private static void appendPositionRollups(List<String> lines, List<Object> byPosition) {
        if (byPosition == null || byPosition.isEmpty()) {
            return;
        }
        List<String> bits = new List<String>();
        Integer n = 0;
        for (Object raw : byPosition) {
            if (n >= 3) {
                break;
            }
            Map<String, Object> row = (Map<String, Object>) raw;
            if (row == null) {
                continue;
            }
            bits.add(String.valueOf(row.get('count')) + ' for ' + String.valueOf(row.get('name')));
            n++;
        }
        if (!bits.isEmpty()) {
            lines.add('Apps by position: ' + String.join(bits, ', ') + '.');
        }
    }

    private static void appendNamedHighlights(
        List<String> lines,
        List<Object> items,
        Integer maxN,
        String audience
    ) {
        if (items == null || items.isEmpty() || lines == null) {
            return;
        }
        List<String> names = new List<String>();
        Integer n = 0;
        for (Object raw : items) {
            if (n >= maxN) {
                break;
            }
            Map<String, Object> item = (Map<String, Object>) raw;
            String bit = describeItem(item, audience);
            if (String.isNotBlank(bit)) {
                names.add(bit);
                n++;
            }
        }
        if (!names.isEmpty()) {
            lines.add('Including ' + String.join(names, '; ') + '.');
        }
    }

    private static void appendDealList(
        List<String> lines,
        List<Object> deals,
        String label,
        String audience
    ) {
        if (deals == null || deals.isEmpty()) {
            return;
        }
        List<String> bits = new List<String>();
        Integer n = 0;
        Integer maxN = audience == AUDIENCE_CEO ? 2 : 3;
        for (Object raw : deals) {
            if (n >= maxN) {
                break;
            }
            String bit = describeItem((Map<String, Object>) raw, audience);
            if (String.isNotBlank(bit)) {
                bits.add(bit);
                n++;
            }
        }
        if (!bits.isEmpty()) {
            lines.add(label + ': ' + String.join(bits, '; ') + '.');
        }
    }

    private static String namedSample(List<Object> items, Integer maxN) {
        if (items == null || items.isEmpty()) {
            return '';
        }
        List<String> names = new List<String>();
        Integer n = 0;
        for (Object raw : items) {
            if (n >= maxN) {
                break;
            }
            Map<String, Object> item = (Map<String, Object>) raw;
            String name = item == null ? null : (String) item.get('name');
            if (String.isNotBlank(name)) {
                names.add(name);
                n++;
            }
        }
        return names.isEmpty() ? '' : ': ' + String.join(names, ', ');
    }

    private static String describeItem(Map<String, Object> item, String audience) {
        if (item == null) {
            return '';
        }
        String name = (String) item.get('name');
        if (String.isBlank(name)) {
            return '';
        }
        List<String> bits = new List<String>{ name };
        if (item.get('account') != null) {
            bits.add('at ' + String.valueOf(item.get('account')));
        }
        if (item.get('company') != null) {
            bits.add('at ' + String.valueOf(item.get('company')));
        }
        Decimal amt = toDecimal(item.get('amount'));
        if (amt != null && amt > 0) {
            bits.add(formatMoney(amt));
        }
        if (item.get('stage') != null) {
            bits.add(String.valueOf(item.get('stage')));
        }
        if (item.get('status') != null) {
            bits.add(String.valueOf(item.get('status')));
        }
        if (audience == AUDIENCE_SALES || audience == AUDIENCE_OPS) {
            if (item.get('primaryAe') != null) {
                bits.add('AE ' + String.valueOf(item.get('primaryAe')));
            }
            if (item.get('nextStep') != null) {
                bits.add('next ' + String.valueOf(item.get('nextStep')));
            }
        }
        return String.join(bits, ', ');
    }

    private static String stripFiller(String text) {
        if (String.isBlank(text)) {
            return text;
        }
        String t = text.trim();
        t = t.replaceAll('(?i)^(good\\s+(morning|afternoon|evening)|hi|hello)[^.!]*[.!]\\s*', '');
        t = t.replaceAll(
            '(?i)\\b(let\'?s dive in|hope you(?:\'re| are) well|in conclusion|that\'?s your briefing)[^.!]*[.!]\\s*',
            ''
        );
        return t.trim();
    }

    public static String truncateDense(String text) {
        return truncateTo(text, MAX_SPEECH_CHARS);
    }

    public static String truncateTo(String text, Integer maxChars) {
        if (String.isBlank(text)) {
            return text;
        }
        Integer cap = maxChars == null || maxChars < 40 ? MAX_SPEECH_CHARS : maxChars;
        String t = text.replaceAll('\\s+', ' ').trim();
        if (t.length() <= cap) {
            return t;
        }
        String cut = t.substring(0, cap);
        Integer lastStop = Math.max(
            Math.max(cut.lastIndexOf('.'), cut.lastIndexOf('!')),
            cut.lastIndexOf('?')
        );
        if (lastStop > 120) {
            return cut.substring(0, lastStop + 1).trim();
        }
        Integer lastSpace = cut.lastIndexOf(' ');
        return (lastSpace > 80 ? cut.substring(0, lastSpace) : cut).trim();
    }

    private static Integer toInt(Object v) {
        if (v == null) {
            return 0;
        }
        if (v instanceof Integer) {
            return (Integer) v;
        }
        if (v instanceof Decimal) {
            return ((Decimal) v).intValue();
        }
        try {
            return Integer.valueOf(String.valueOf(v));
        } catch (Exception e) {
            return 0;
        }
    }

    private static Decimal toDecimal(Object v) {
        if (v == null) {
            return null;
        }
        if (v instanceof Decimal) {
            return (Decimal) v;
        }
        if (v instanceof Integer) {
            return Decimal.valueOf((Integer) v);
        }
        try {
            return Decimal.valueOf(String.valueOf(v));
        } catch (Exception e) {
            return null;
        }
    }

    private static String formatMoney(Decimal amount) {
        if (amount == null) {
            return '';
        }
        return '$' + String.valueOf(amount.setScale(0, RoundingMode.HALF_UP).format());
    }
}
