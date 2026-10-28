/**
 * Short demo calls the app can actually play: Egyptian colloquial Arabic and one English
 * follow-up. The audio files are served by the field app at MEDIA_BASE.
 */
public with sharing class CareCoachCallSamples {
    public static final String MEDIA_BASE = 'https://www.salesforceoffline.com/media/calls/';
    public static final String LANG_AR = 'Arabic (Egypt)';
    public static final String LANG_EN = 'English';

    public static String recordingUrl(String fileName) {
        return MEDIA_BASE + fileName;
    }

    public static Boolean isAppRecording(String url) {
        return String.isNotBlank(url) && url.startsWith(MEDIA_BASE);
    }

    public static String fileFor(Boolean arabic, String tone) {
        if (!arabic) {
            return 'en-follow-up.mp3';
        }
        if (tone == 'sideEffects' || tone == 'serious' || tone == 'stopped') {
            return 'ar-eg-side-effect.mp3';
        }
        if (tone == 'adherence' || tone == 'cost') {
            return 'ar-eg-adherence.mp3';
        }
        return 'ar-eg-refill.mp3';
    }

    public static String categoryFor(String tone) {
        if (tone == 'sideEffects' || tone == 'serious' || tone == 'stopped') {
            return 'Side effects';
        }
        if (tone == 'adherence') {
            return 'Adherence';
        }
        if (tone == 'cost') {
            return 'Access & reimbursement';
        }
        if (tone == 'education') {
            return 'Disease education';
        }
        return 'Administration';
    }

    /** Coach:/Patient: lines. Wording matches the mp3 of the same name, word for word. */
    public static String transcript(Boolean arabic, String tone) {
        if (!arabic) {
            return 'Coach: Hello, this is your care coach from the patient support programme. Is this a good time?\n' +
                'Patient: Yes, go ahead.\n' +
                'Coach: How have you been since the last dose?\n' +
                'Patient: Pretty well. I took it on time and I have no new side effects.\n' +
                'Coach: Glad to hear that. Your next refill is on track, and I will call you again next month.\n' +
                'Patient: Thank you, that helps.';
        }
        if (tone == 'sideEffects' || tone == 'serious' || tone == 'stopped') {
            return 'Coach: ألو يا أستاذ، أنا من برنامج إربيتوكس. عامل إيه من آخر جرعة؟\n' +
                'Patient: والله فيه طفح خفيف على وشي من بعد الجلسة، ومش مريحني.\n' +
                'Coach: ده عرض معروف مع إربيتوكس. رطب بشرتك مرتين في اليوم، وابعد عن الشمس. لو الطفح زاد أو فيه ضيق تنفس، كلمني فوراً وهبلّغ الطبيب.\n' +
                'Patient: حاضر. دلوقتي خفيف، بس هتابع وأكلمك لو زاد.';
        }
        if (tone == 'adherence' || tone == 'cost') {
            return 'Coach: ألو، أنا كوتش البرنامج. حابة أسأل: الجرعات ماشية مظبوط؟\n' +
                'Patient: بصراحة نسيت جرعة أول امبارح، وبعديها رجعت أخد في الميعاد.\n' +
                'Coach: ولا يهمك، متزودش الجرعة. ظبط منبّه على الموبايل قبل الميعاد بنص ساعة، وهكلمك الأسبوع الجاي نتطمن.\n' +
                'Patient: ماشي، هظبط المنبّه. شكراً.';
        }
        return 'Coach: ألو، مساء الخير. معاكِ كوتش الرعاية من برنامج دعم مرضى ريباف. الوقت مناسب نتكلم دقيقتين؟\n' +
            'Patient: أيوه يا فندم، اتفضلي.\n' +
            'Coach: حابة أطمن على الحقن. آخر جرعة كانت امتى؟\n' +
            'Patient: حقنة امبارح خدتها في ميعادها، بس العلبة خلصت ومحتاج تجديد.\n' +
            'Coach: تمام. هطلع طلب توصيل للبيت، وهيوصلك خلال تلات أيام. هبعتلك رسالة فيها رقم التتبع.\n' +
            'Patient: شكراً يا فندم، كده تمام.';
    }

    public static String notes(Boolean arabic, String tone) {
        if (!arabic) {
            return 'Patient doing well, adherent, no new concerns.';
        }
        if (tone == 'sideEffects' || tone == 'serious' || tone == 'stopped') {
            return 'طفح خفيف بعد الجرعة. اتشرحت تعليمات الترطيب، وهيتبلّغ الطبيب لو زاد.';
        }
        if (tone == 'adherence' || tone == 'cost') {
            return 'فاتته جرعة. اتفقنا على منبّه قبل الميعاد، من غير ما يزوّد الجرعة.';
        }
        return 'المريض ملتزم. العلبة خلصت، وطلعنا طلب توصيل للبيت.';
    }

    /**
     * Rewrites the latest reached calls so the app has Egyptian Arabic conversations,
     * playable recordings and a linked knowledge article. Safe to run more than once.
     */
    public static Integer applyToRecentCalls() {
        List<Patient_Interaction__c> calls = new List<Patient_Interaction__c>();
        for (Patient_Interaction__c row : [
            SELECT Id, Product__c, Product__r.Name, Transcript__c
            FROM Patient_Interaction__c
            WHERE Status__c = 'Reached' AND Type__c = 'Call'
            ORDER BY Start__c DESC
            LIMIT 400
        ]) {
            if (String.isBlank(row.Transcript__c)) {
                continue;
            }
            calls.add(row);
            if (calls.size() == 200) {
                break;
            }
        }
        Map<String, Id> scripts = scriptIds();
        Integer n = 0;
        for (Patient_Interaction__c i : calls) {
            Boolean arabic = Math.mod(n, 4) != 0;
            String tone = toneAt(n);
            i.Language__c = arabic ? LANG_AR : LANG_EN;
            i.Transcript__c = transcript(arabic, tone);
            i.Notes__c = notes(arabic, tone);
            i.Recording_URL__c = recordingUrl(fileFor(arabic, tone));
            i.Recording_Consent__c = true;
            i.Care_Script__c = scriptId(scripts, i.Product__c, categoryFor(tone));
            i.AI_Summary__c = null;
            i.AI_Sentiment__c = null;
            i.AI_Adherence_Risk__c = null;
            i.AI_Risk_Score__c = null;
            i.AI_Side_Effects_Flagged__c = null;
            i.AI_Topics__c = null;
            i.AI_Next_Best_Action__c = null;
            i.AI_Sentiment_Details__c = null;
            i.AI_Key_Phrases__c = null;
            i.AI_Sentiment_Score__c = null;
            n++;
        }
        if (!calls.isEmpty()) {
            update calls;
        }
        return calls.size();
    }

    private static String toneAt(Integer n) {
        List<String> tones = new List<String>{ 'refill', 'sideEffects', 'adherence', 'positive' };
        return tones[Math.mod(n, tones.size())];
    }

    public static Map<String, Id> scriptIds() {
        Map<String, Id> out = new Map<String, Id>();
        for (Care_Script__c s : [
            SELECT Id, Product__c, Category__c
            FROM Care_Script__c
            WHERE Publication_Status__c = 'Published'
        ]) {
            String key = String.valueOf(s.Product__c) + '|' + s.Category__c;
            if (!out.containsKey(key)) {
                out.put(key, s.Id);
            }
        }
        return out;
    }

    public static Id scriptId(Map<String, Id> scripts, Id productId, String category) {
        Id specific = scripts.get(String.valueOf(productId) + '|' + category);
        return specific == null ? scripts.get('null|' + category) : specific;
    }
}