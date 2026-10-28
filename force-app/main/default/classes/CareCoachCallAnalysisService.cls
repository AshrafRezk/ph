/**
 * AI analysis of care coach call transcripts.
 * Tries the Einstein prompt template PSP_Call_Transcript_Analysis when available,
 * otherwise falls back to a deterministic clinical-keyword analyzer.
 */
public with sharing class CareCoachCallAnalysisService {
    public static final String PROMPT_TEMPLATE = 'PSP_Call_Transcript_Analysis';
    public static final String HEURISTIC_ENGINE = 'Care Coach Insight Engine v1';

    public class Analysis {
        @AuraEnabled public String summary;
        @AuraEnabled public String sentiment;
        @AuraEnabled public String adherenceRisk;
        @AuraEnabled public Integer riskScore;
        @AuraEnabled public String sideEffects;
        @AuraEnabled public String topics;
        @AuraEnabled public String nextBestAction;
        @AuraEnabled public String engine;
    }

    private static final Map<String, String> SIDE_EFFECTS = new Map<String, String>{
        'injection site' => 'Injection-site reaction',
        'redness' => 'Injection-site reaction',
        'bruis' => 'Injection-site reaction',
        'flu-like' => 'Flu-like symptoms',
        'fever' => 'Fever',
        'chills' => 'Flu-like symptoms',
        'fatigue' => 'Fatigue',
        'tired all' => 'Fatigue',
        'headache' => 'Headache',
        'rash' => 'Skin rash',
        'acne' => 'Acneiform rash',
        'dry skin' => 'Dry skin',
        'itch' => 'Pruritus',
        'nail' => 'Nail changes',
        'diarrh' => 'Diarrhoea',
        'nausea' => 'Nausea',
        'vomit' => 'Vomiting',
        'mouth sore' => 'Mucositis',
        'cramp' => 'Muscle cramps',
        'joint pain' => 'Arthralgia',
        'swelling' => 'Swelling',
        'depress' => 'Low mood',
        'low mood' => 'Low mood',
        'liver' => 'Liver enzyme change',
        'lymphocyte' => 'Low lymphocyte count',
        'infection' => 'Infection',
        'shingles' => 'Herpes zoster',
        'hip pain' => 'Hip / knee pain',
        'knee pain' => 'Hip / knee pain',
        'طفح' => 'Skin rash',
        'حكة' => 'Pruritus',
        'صداع' => 'Headache',
        'غثيان' => 'Nausea',
        'إعياء' => 'Fatigue',
        'تعبان' => 'Fatigue'
    };
    private static final List<String> SERIOUS = new List<String>{
        'hospital', 'emergency', 'severe', 'anaphyla', 'breath', 'faint', 'seizure', 'allergic',
        'ضيق تنفس', 'مستشفى', 'حساسية'
    };
    private static final List<String> RISK_SIGNALS = new List<String>{
        'missed', 'forgot', 'skipped', 'skip', 'stopped', 'stop taking', 'quit', 'afford', 'expensive',
        'ran out', 'out of stock', 'afraid', 'scared', 'tired of', 'switch', 'not sure', 'delay',
        'postpone', 'travel', 'no one to', 'too far', 'lost my',
        'نسيت', 'فاتت', 'مش قادر', 'غالي'
    };
    private static final List<String> POSITIVE = new List<String>{
        'better', 'good', 'great', 'thank', 'improv', 'no problem', 'on track', 'fine', 'happy',
        'comfortable', 'confident', 'easier', 'helpful', 'relieved', 'every dose', 'on time',
        'تمام', 'كويس', 'شكرا', 'ملتزم', 'في الميعاد'
    };
    private static final List<String> NEGATIVE = new List<String>{
        'worse', 'pain', 'angry', 'frustrat', 'worried', 'bad', 'difficult', 'upset', 'afraid',
        'scared', 'hate', 'annoy', 'struggl', 'overwhelm', 'confus',
        'مش مريح', 'وحش', 'قلقان'
    };
    private static final Map<String, List<String>> TOPICS = new Map<String, List<String>>{
        'Administration & technique' => new List<String>{ 'injection', 'pen', 'auto-injector', 'rebismart', 'easypod', 'needle', 'dose', 'حقن', 'حقنة', 'إبرة' },
        'Side effects' => new List<String>{ 'side effect', 'rash', 'redness', 'fever', 'fatigue', 'headache', 'diarrh', 'nausea', 'طفح', 'حكة', 'صداع' },
        'Supply & orders' => new List<String>{ 'order', 'refill', 'delivery', 'pharmacy', 'stock', 'box', 'pack', 'تجديد', 'توصيل', 'علبة خلصت', 'صيدلية' },
        'Access & cost' => new List<String>{ 'insurance', 'cost', 'price', 'afford', 'reimburs', 'coverage', 'غالي' },
        'Monitoring & labs' => new List<String>{ 'mri', 'scan', 'lab', 'blood test', 'magnesium', 'lymphocyte', 'x-ray' },
        'HCP follow-up' => new List<String>{ 'doctor', 'physician', 'appointment', 'clinic', 'oncologist', 'neurologist', 'endocrinologist', 'طبيب', 'دكتور' },
        'Growth tracking' => new List<String>{ 'height', 'growth', 'centimet', 'school' },
        'Infusion schedule' => new List<String>{ 'infusion', 'cycle', 'chemo', 'weekly session' },
        'Emotional wellbeing' => new List<String>{ 'anxious', 'worried', 'stress', 'mood', 'family' }
    };

    @AuraEnabled
    public static Analysis analyze(Id interactionId) {
        CareCoachAccess.assertCanEdit();
        Patient_Interaction__c i = [
            SELECT Id, Patient__c, Transcript__c, Interaction_Reason__c, Status__c, Product__r.Name
            FROM Patient_Interaction__c
            WHERE Id = :interactionId
            WITH USER_MODE
            LIMIT 1
        ];
        if (String.isBlank(i.Transcript__c)) {
            throw CareCoachAccess.fail('Add a transcript before running AI analysis.');
        }
        Analysis a = tryPromptTemplate(i);
        if (a == null) {
            a = heuristic(i.Transcript__c, i.Interaction_Reason__c, i.Product__r?.Name);
        }
        apply(i, a);
        update as user CareCoachPatientService.updatableCopy(i);
        CareCoachPatientService.refreshPatientFromCalls(new Set<Id>{ i.Patient__c });
        return a;
    }

    /** Live coaching card while a call is still being recorded. No DML. */
    @AuraEnabled
    public static Analysis preview(String transcript) {
        CareCoachAccess.assertCanEdit();
        if (String.isBlank(transcript)) {
            throw CareCoachAccess.fail('Nothing to analyse yet.');
        }
        return heuristic(transcript, 'Live call', null);
    }

    /** In-memory analysis (no DML). Used when logging calls and by the demo seed. */
    public static void applyAnalysis(List<Patient_Interaction__c> rows, Boolean allowLlm) {
        for (Patient_Interaction__c i : rows) {
            if (String.isBlank(i.Transcript__c)) {
                continue;
            }
            Analysis a = allowLlm ? tryPromptTemplate(i) : null;
            if (a == null) {
                a = heuristic(i.Transcript__c, i.Interaction_Reason__c, null);
            }
            apply(i, a);
        }
    }

    private static void apply(Patient_Interaction__c i, Analysis a) {
        i.AI_Summary__c = a.summary;
        i.AI_Sentiment__c = a.sentiment;
        i.AI_Adherence_Risk__c = a.adherenceRisk;
        i.AI_Risk_Score__c = a.riskScore;
        i.AI_Side_Effects_Flagged__c = String.isBlank(a.sideEffects) ? null : a.sideEffects.abbreviate(255);
        i.AI_Topics__c = String.isBlank(a.topics) ? null : a.topics.abbreviate(255);
        i.AI_Next_Best_Action__c = a.nextBestAction;
        i.AI_Analyzed_On__c = System.now();
        i.AI_Engine__c = a.engine;
    }

    /**
     * Einstein generative AI is not enabled in every org, so the LLM call lives in an optional
     * Callable class (CareCoachEinsteinBridge) that is only deployed where ConnectApi.EinsteinLLM exists.
     * It receives 'analyze' with {template, transcript, reason} and returns the model's JSON text.
     */
    private static Analysis tryPromptTemplate(Patient_Interaction__c i) {
        if (Test.isRunningTest()) {
            return null;
        }
        Type bridgeType = Type.forName('CareCoachEinsteinBridge');
        if (bridgeType == null) {
            return null;
        }
        try {
            Callable bridge = (Callable) bridgeType.newInstance();
            Object text = bridge.call('analyze', new Map<String, Object>{
                'template' => PROMPT_TEMPLATE,
                'transcript' => i.Transcript__c,
                'reason' => i.Interaction_Reason__c
            });
            if (text == null || String.isBlank(String.valueOf(text))) {
                return null;
            }
            Analysis a = (Analysis) JSON.deserialize(String.valueOf(text), Analysis.class);
            if (a == null || String.isBlank(a.summary)) {
                return null;
            }
            a.engine = 'Einstein (' + PROMPT_TEMPLATE + ')';
            if (a.riskScore == null) {
                a.riskScore = a.adherenceRisk == 'High' ? 75 : (a.adherenceRisk == 'Medium' ? 45 : 20);
            }
            return a;
        } catch (Exception e) {
            return null;
        }
    }

    public static Analysis heuristic(String transcript, String reason, String productName) {
        String patientText = patientSpeech(transcript).toLowerCase();

        List<String> effects = new List<String>();
        for (String key : SIDE_EFFECTS.keySet()) {
            String label = SIDE_EFFECTS.get(key);
            if (patientText.contains(key) && !effects.contains(label) && !negated(patientText, key)) {
                effects.add(label);
            }
        }
        Boolean seriousFlag = false;
        for (String s : SERIOUS) {
            if (patientText.contains(s)) {
                seriousFlag = true;
            }
        }
        Integer risk = countHits(patientText, RISK_SIGNALS);
        Integer pos = countHits(patientText, POSITIVE);
        Integer neg = countHits(patientText, NEGATIVE);

        List<String> topicHits = new List<String>();
        String whole = transcript.toLowerCase();
        for (String topic : TOPICS.keySet()) {
            for (String k : TOPICS.get(topic)) {
                if (whole.contains(k)) {
                    topicHits.add(topic);
                    break;
                }
            }
        }

        Integer score = 20 + risk * 14 + effects.size() * 7 + neg * 6 - pos * 5 + (seriousFlag ? 25 : 0);
        score = Math.max(0, Math.min(100, score));

        Analysis a = new Analysis();
        a.engine = HEURISTIC_ENGINE;
        a.riskScore = score;
        a.adherenceRisk = score >= 60 ? 'High' : (score >= 35 ? 'Medium' : 'Low');
        a.sentiment = (pos - neg >= 2) ? 'Positive' : ((neg - pos >= 1) ? 'Negative' : 'Neutral');
        a.sideEffects = effects.isEmpty() ? null : String.join(effects, ', ') + (seriousFlag ? ' (possible serious AE)' : '');
        a.topics = topicHits.isEmpty() ? null : String.join(topicHits, ', ');

        List<String> summary = new List<String>();
        summary.add((String.isBlank(reason) ? 'Care coach call' : reason) + (String.isBlank(productName) ? '' : ' - ' + productName) + '.');
        summary.add(effects.isEmpty()
            ? 'Patient reported no new side effects.'
            : 'Patient reported ' + String.join(effects, ', ').toLowerCase() + (seriousFlag ? ', with signs that may need urgent medical review.' : '.'));
        if (risk > 0) {
            summary.add('Adherence barriers mentioned (' + risk + ' signal' + (risk == 1 ? '' : 's') + '), e.g. ' + firstSignal(patientText) + '.');
        } else {
            summary.add('Patient appears adherent to the prescribed schedule.');
        }
        summary.add('Overall tone: ' + a.sentiment.toLowerCase() + '.');
        if (!topicHits.isEmpty()) {
            summary.add('Topics: ' + a.topics + '.');
        }
        a.summary = String.join(summary, ' ');
        a.nextBestAction = nextBestAction(a, patientText, seriousFlag, effects);
        return a;
    }

    private static String nextBestAction(Analysis a, String text, Boolean isSerious, List<String> effects) {
        List<String> actions = new List<String>();
        if (isSerious) {
            actions.add('Report to pharmacovigilance within 24h and advise the patient to contact their physician today.');
        } else if (!effects.isEmpty()) {
            actions.add('Share the side-effect management script and check symptoms again in 3 days.');
        }
        if (text.contains('afford') || text.contains('expensive') || text.contains('insurance')) {
            actions.add('Refer to the access & reimbursement programme.');
        }
        if (text.contains('ran out') || text.contains('out of stock') || text.contains('order') || text.contains('خلصت') || text.contains('تجديد') || text.contains('توصيل')) {
            actions.add('Confirm the next order and delivery date.');
        }
        if (text.contains('missed') || text.contains('forgot') || text.contains('skip') || text.contains('نسيت') || text.contains('فاتت')) {
            actions.add('Reinforce the dosing schedule and enrol the patient in SMS reminders.');
        }
        if (text.contains('afraid') || text.contains('scared') || text.contains('needle')) {
            actions.add('Offer a refresher injection-training session.');
        }
        if (actions.isEmpty()) {
            actions.add(a.adherenceRisk == 'Low'
                ? 'Continue routine follow-up in 2 weeks.'
                : 'Schedule a supportive check-in call within 1 week.');
        }
        return String.join(actions, ' ');
    }

    private static String patientSpeech(String transcript) {
        List<String> lines = new List<String>();
        Boolean labelled = false;
        for (String line : transcript.split('\n')) {
            String t = line.trim();
            if (t.toLowerCase().startsWith('patient:') || t.toLowerCase().startsWith('caregiver:') || t.toLowerCase().startsWith('heard:')) {
                labelled = true;
                lines.add(t.substringAfter(':'));
            } else if (t.toLowerCase().startsWith('coach:')) {
                labelled = true;
            }
        }
        return labelled ? String.join(lines, ' ') : transcript;
    }

    private static Boolean negated(String text, String key) {
        Integer idx = text.indexOf(key);
        if (idx < 0) {
            return false;
        }
        String before = text.substring(Math.max(0, idx - 18), idx);
        return before.contains('no ') || before.contains('not ') || before.contains('without') || before.contains('any ');
    }

    private static Integer countHits(String text, List<String> words) {
        Integer n = 0;
        for (String w : words) {
            if (text.contains(w)) {
                n++;
            }
        }
        return n;
    }

    private static String firstSignal(String text) {
        for (String w : RISK_SIGNALS) {
            if (text.contains(w)) {
                return '"' + w + '"';
            }
        }
        return 'schedule concerns';
    }
}