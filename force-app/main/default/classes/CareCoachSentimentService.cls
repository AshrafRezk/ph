/**
 * Azure AI Language sentiment (with opinion mining) and key phrase extraction for call transcripts.
 * Runs as a Queueable because the transcript is saved first and callouts can't follow DML
 * in the same transaction.
 */
public with sharing class CareCoachSentimentService implements Queueable, Database.AllowsCallouts {
    public static final String ENGINE = 'Azure AI Language';
    public static final String ENDPOINT = 'callout:Azure_Language/language/:analyze-text?api-version=2023-04-01';
    // Azure synchronous limits: 10 documents per request, 5,120 characters per document.
    private static final Integer DOCS_PER_REQUEST = 10;
    private static final Integer MAX_DOC_CHARS = 5000;
    private static final Integer MAX_TURNS = 80;
    private static final Integer MAX_SENTENCES = 200;
    private static final Integer MAX_OPINIONS = 30;
    private static final Integer MAX_KEY_PHRASES = 15;

    private final Id interactionId;

    public CareCoachSentimentService(Id interactionId) {
        this.interactionId = interactionId;
    }

    public static Boolean isEnabled() {
        return CareCoachTelephonyController.settings().Sentiment_Enabled__c == true;
    }

    public static void enqueueIfEnabled(Id interactionId, String transcript) {
        if (interactionId == null || String.isBlank(transcript) || !isEnabled()) {
            return;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return;
        }
        System.enqueueJob(new CareCoachSentimentService(interactionId));
    }

    public void execute(QueueableContext context) {
        List<Patient_Interaction__c> rows = [
            SELECT Id, Transcript__c FROM Patient_Interaction__c WHERE Id = :interactionId LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Transcript__c)) {
            return;
        }
        Patient_Interaction__c upd = new Patient_Interaction__c(Id = interactionId);
        try {
            Result r = analyze(rows[0].Transcript__c);
            upd.AI_Sentiment__c = r.sentiment;
            upd.AI_Sentiment_Score__c = r.score;
            upd.AI_Key_Phrases__c = r.keyPhrases;
            upd.AI_Sentiment_Details__c = r.detailsJson;
        } catch (Exception e) {
            upd.AI_Sentiment_Details__c = JSON.serialize(new Map<String, Object>{
                'engine' => ENGINE,
                'error' => e.getMessage().left(500)
            });
        }
        update upd;
    }

    // ------------------------------------------------------------------ analysis

    public class Result {
        public String sentiment;
        public Integer score;
        public String keyPhrases;
        public String detailsJson;
    }

    public class Turn {
        public String speaker;
        public String text;
        Turn(String speaker, String text) {
            this.speaker = speaker;
            this.text = text;
        }
    }

    private class Tally {
        Decimal positive = 0;
        Decimal neutral = 0;
        Decimal negative = 0;
        Decimal weight = 0;

        void add(Map<String, Object> scores, Integer chars) {
            Decimal w = Math.max(chars, 1);
            positive += num(scores.get('positive')) * w;
            neutral += num(scores.get('neutral')) * w;
            negative += num(scores.get('negative')) * w;
            weight += w;
        }

        Map<String, Object> summary() {
            if (weight == 0) {
                return null;
            }
            Decimal p = (positive / weight).setScale(3);
            Decimal n = (neutral / weight).setScale(3);
            Decimal g = (negative / weight).setScale(3);
            return new Map<String, Object>{
                'sentiment' => label(p, n, g),
                'positive' => p,
                'neutral' => n,
                'negative' => g,
                'score' => ((p - g) * 100).round(System.RoundingMode.HALF_UP).intValue()
            };
        }
    }

    public static Result analyze(String transcript) {
        List<Turn> turns = parseTurns(transcript);
        Tally overall = new Tally();
        Tally patient = new Tally();
        Tally coach = new Tally();
        List<Map<String, Object>> sentences = new List<Map<String, Object>>();
        List<Map<String, Object>> opinions = new List<Map<String, Object>>();

        for (Integer start = 0; start < turns.size(); start += DOCS_PER_REQUEST) {
            List<Map<String, Object>> docs = new List<Map<String, Object>>();
            for (Integer i = start; i < Math.min(start + DOCS_PER_REQUEST, turns.size()); i++) {
                docs.add(new Map<String, Object>{ 'id' => String.valueOf(i), 'language' => 'en', 'text' => turns[i].text });
            }
            Map<String, Object> body = call('SentimentAnalysis', new Map<String, Object>{ 'opinionMining' => true }, docs);
            for (Object o : documents(body)) {
                Map<String, Object> doc = (Map<String, Object>) o;
                Turn t = turns[Integer.valueOf((String) doc.get('id'))];
                Map<String, Object> scores = (Map<String, Object>) doc.get('confidenceScores');
                overall.add(scores, t.text.length());
                if (t.speaker == 'Patient') {
                    patient.add(scores, t.text.length());
                } else {
                    coach.add(scores, t.text.length());
                }
                collectSentences(doc, t.speaker, sentences, opinions);
            }
        }

        Map<String, Object> overallSummary = overall.summary();
        Map<String, Object> patientSummary = patient.summary();
        Map<String, Object> headline = patientSummary != null ? patientSummary : overallSummary;

        Result r = new Result();
        r.sentiment = headline == null ? null : (String) headline.get('sentiment');
        r.score = headline == null ? null : (Integer) headline.get('score');
        List<String> phrases = keyPhrases(turns);
        r.keyPhrases = phrases.isEmpty() ? null : String.join(phrases, '; ').left(2000);
        r.detailsJson = JSON.serialize(new Map<String, Object>{
            'engine' => ENGINE,
            'analyzedOn' => System.now(),
            'overall' => overallSummary,
            'patient' => patientSummary,
            'coach' => coach.summary(),
            'sentences' => sentences,
            'opinions' => opinions,
            'keyPhrases' => phrases
        }).left(131072);
        return r;
    }

    public static List<Turn> parseTurns(String transcript) {
        List<Turn> turns = new List<Turn>();
        Pattern speakerLine = Pattern.compile('^\\s*([A-Za-z][A-Za-z .\\-]{0,24}):\\s*(.*)$');
        for (String raw : transcript.split('\n')) {
            String line = raw.trim();
            if (String.isBlank(line)) {
                continue;
            }
            String speaker;
            String text = line;
            Matcher m = speakerLine.matcher(line);
            if (m.matches()) {
                speaker = m.group(1).trim().toLowerCase().startsWith('patient') ? 'Patient' : 'Coach';
                text = m.group(2).trim();
            }
            if (String.isBlank(text)) {
                continue;
            }
            Turn last = turns.isEmpty() ? null : turns[turns.size() - 1];
            if (last != null && (speaker == null || speaker == last.speaker) && last.text.length() + text.length() < MAX_DOC_CHARS) {
                last.text += ' ' + text;
            } else {
                turns.add(new Turn(speaker == null ? (last == null ? 'Coach' : last.speaker) : speaker, text.left(MAX_DOC_CHARS)));
            }
            if (turns.size() >= MAX_TURNS) {
                break;
            }
        }
        return turns;
    }

    private static void collectSentences(Map<String, Object> doc, String speaker, List<Map<String, Object>> sentences, List<Map<String, Object>> opinions) {
        Object raw = doc.get('sentences');
        if (!(raw instanceof List<Object>)) {
            return;
        }
        for (Object so : (List<Object>) raw) {
            Map<String, Object> s = (Map<String, Object>) so;
            Map<String, Object> scores = (Map<String, Object>) s.get('confidenceScores');
            if (sentences.size() < MAX_SENTENCES) {
                sentences.add(new Map<String, Object>{
                    'speaker' => speaker,
                    'text' => String.valueOf(s.get('text')).left(300),
                    'sentiment' => capitalize((String) s.get('sentiment')),
                    'score' => scores == null ? 0 : ((num(scores.get('positive')) - num(scores.get('negative'))) * 100).round(System.RoundingMode.HALF_UP).intValue()
                });
            }
            Object targets = s.get('targets');
            Object assessments = s.get('assessments');
            if (!(targets instanceof List<Object>)) {
                continue;
            }
            List<Object> assessmentList = assessments instanceof List<Object> ? (List<Object>) assessments : new List<Object>();
            for (Object to : (List<Object>) targets) {
                if (opinions.size() >= MAX_OPINIONS) {
                    return;
                }
                Map<String, Object> t = (Map<String, Object>) to;
                List<String> words = new List<String>();
                Object rels = t.get('relations');
                if (rels instanceof List<Object>) {
                    for (Object ro : (List<Object>) rels) {
                        String ref = String.valueOf(((Map<String, Object>) ro).get('ref'));
                        Integer idx = Integer.valueOf(ref.substringAfterLast('/'));
                        if (idx < assessmentList.size()) {
                            words.add(String.valueOf(((Map<String, Object>) assessmentList[idx]).get('text')));
                        }
                    }
                }
                opinions.add(new Map<String, Object>{
                    'speaker' => speaker,
                    'target' => t.get('text'),
                    'sentiment' => capitalize((String) t.get('sentiment')),
                    'assessments' => String.join(words, ', ')
                });
            }
        }
    }

    private static List<String> keyPhrases(List<Turn> turns) {
        List<Map<String, Object>> docs = new List<Map<String, Object>>();
        String chunk = '';
        for (Turn t : turns) {
            if (chunk.length() + t.text.length() + 1 > MAX_DOC_CHARS && chunk.length() > 0) {
                docs.add(new Map<String, Object>{ 'id' => String.valueOf(docs.size()), 'language' => 'en', 'text' => chunk });
                chunk = '';
            }
            chunk += (chunk.length() > 0 ? ' ' : '') + t.text;
            if (docs.size() >= DOCS_PER_REQUEST) {
                break;
            }
        }
        if (chunk.length() > 0 && docs.size() < DOCS_PER_REQUEST) {
            docs.add(new Map<String, Object>{ 'id' => String.valueOf(docs.size()), 'language' => 'en', 'text' => chunk });
        }
        if (docs.isEmpty()) {
            return new List<String>();
        }
        Map<String, Integer> counts = new Map<String, Integer>();
        Map<String, String> display = new Map<String, String>();
        List<String> order = new List<String>();
        for (Object o : documents(call('KeyPhraseExtraction', null, docs))) {
            Object phrases = ((Map<String, Object>) o).get('keyPhrases');
            if (!(phrases instanceof List<Object>)) {
                continue;
            }
            for (Object p : (List<Object>) phrases) {
                String phrase = String.valueOf(p);
                String key = phrase.toLowerCase();
                if (!counts.containsKey(key)) {
                    counts.put(key, 0);
                    display.put(key, phrase);
                    order.add(key);
                }
                counts.put(key, counts.get(key) + 1);
            }
        }
        // Stable sort: most frequent first, then first-seen order.
        List<String> out = new List<String>();
        Integer maxCount = 0;
        for (Integer c : counts.values()) {
            maxCount = Math.max(maxCount, c);
        }
        for (Integer c = maxCount; c >= 1 && out.size() < MAX_KEY_PHRASES; c--) {
            for (String key : order) {
                if (counts.get(key) == c && out.size() < MAX_KEY_PHRASES) {
                    out.add(display.get(key));
                }
            }
        }
        return out;
    }

    // ------------------------------------------------------------------ HTTP

    private static Map<String, Object> call(String kind, Map<String, Object> parameters, List<Map<String, Object>> docs) {
        Map<String, Object> payload = new Map<String, Object>{
            'kind' => kind,
            'analysisInput' => new Map<String, Object>{ 'documents' => docs }
        };
        if (parameters != null) {
            payload.put('parameters', parameters);
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(60000);
        req.setBody(JSON.serialize(payload));
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CareCoachAccess.CareCoachException('Azure AI Language ' + res.getStatusCode() + ': ' + res.getBody().left(300));
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static List<Object> documents(Map<String, Object> body) {
        Map<String, Object> results = (Map<String, Object>) body.get('results');
        if (results == null || !(results.get('documents') instanceof List<Object>)) {
            return new List<Object>();
        }
        return (List<Object>) results.get('documents');
    }

    // ------------------------------------------------------------------ helpers

    private static Decimal num(Object o) {
        return o == null ? 0 : Decimal.valueOf(String.valueOf(o));
    }

    private static String label(Decimal p, Decimal n, Decimal g) {
        if (p >= 0.25 && g >= 0.25) {
            return 'Mixed';
        }
        if (p >= n && p >= g) {
            return 'Positive';
        }
        return g >= n ? 'Negative' : 'Neutral';
    }

    private static String capitalize(String s) {
        return String.isBlank(s) ? s : s.substring(0, 1).toUpperCase() + s.substring(1);
    }
}