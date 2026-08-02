/**
 * ElevenLabs Smart Briefing TTS with per-user daily credit + script-hash audio cache.
 */
public without sharing class CrmHubTtsService {
    public static final Integer SMART_CREDITS_PER_DAY = 1;
    /** Premade "Sarah" — works on free ElevenLabs API keys (Rachel library voice does not). */
    private static final String DEFAULT_VOICE_ID = 'EXAVITQu4vr4xnSDxMaL';
    private static final String ELEVEN_MODEL = 'eleven_flash_v2_5';

    @TestVisible
    private static String apiKeyOverride;
    @TestVisible
    private static String voiceIdOverride;
    @TestVisible
    private static Blob testSpeechBodyOverride;
    @TestVisible
    private static Boolean skipCallout;

    public class CreditStatus {
        public Boolean smartUsedToday;
        public Integer smartCreditsRemaining;
        public Boolean elevenLabsConfigured;
    }

    public static CreditStatus getCreditStatus() {
        CreditStatus status = new CreditStatus();
        status.elevenLabsConfigured = String.isNotBlank(resolveApiKey());
        status.smartUsedToday = hasUsedSmartToday(UserInfo.getUserId(), Date.today());
        status.smartCreditsRemaining = status.smartUsedToday ? 0 : SMART_CREDITS_PER_DAY;
        return status;
    }

    public static Map<String, Object> synthesize(String text, Boolean useSmart) {
        String trimmed = text == null ? '' : text.trim();
        if (String.isBlank(trimmed)) {
            return voiceResult(false, 'webspeech', 'browser', 'Nothing to speak.', null, null, getCreditStatus());
        }
        if (trimmed.length() > CrmHubBriefingNarrative.MAX_SPEECH_CHARS) {
            trimmed = CrmHubBriefingNarrative.truncateDense(trimmed);
        }
        CreditStatus credits = getCreditStatus();
        if (useSmart != true) {
            return voiceResult(false, 'webspeech', 'browser', null, null, null, credits);
        }
        if (!credits.elevenLabsConfigured) {
            return voiceResult(
                false,
                'webspeech',
                'browser',
                'Smart voice is not configured.',
                null,
                null,
                credits
            );
        }
        if (credits.smartCreditsRemaining <= 0) {
            return voiceResult(
                false,
                'webspeech',
                'browser',
                '1 Smart Briefing per day. Come back tomorrow, or use standard voice anytime.',
                null,
                null,
                credits
            );
        }

        String hash = EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(trimmed))
        );
        Map<String, Object> cached = loadCachedAudio(hash);
        if (cached != null) {
            markSmartUsed(UserInfo.getUserId(), Date.today());
            credits = getCreditStatus();
            cached.put('success', true);
            cached.put('engine', 'elevenlabs');
            cached.put('source', 'cache');
            cached.put('voiceMode', 'smart');
            putCredits(cached, credits);
            return cached;
        }

        try {
            Blob audio = callElevenLabs(trimmed);
            if (audio == null || audio.size() == 0) {
                return voiceResult(
                    false,
                    'webspeech',
                    'browser',
                    'ElevenLabs returned empty audio.',
                    null,
                    null,
                    credits
                );
            }
            storeCachedAudio(hash, audio, 'audio/mpeg');
            markSmartUsed(UserInfo.getUserId(), Date.today());
            credits = getCreditStatus();
            Map<String, Object> out = voiceResult(
                true,
                'elevenlabs',
                null,
                null,
                'audio/mpeg',
                EncodingUtil.base64Encode(audio),
                credits
            );
            out.put('source', 'elevenlabs');
            out.put('voiceMode', 'smart');
            out.put('scriptHash', hash);
            return out;
        } catch (Exception e) {
            return voiceResult(false, 'webspeech', 'browser', e.getMessage(), null, null, credits);
        }
    }

    private static Blob callElevenLabs(String text) {
        if (Test.isRunningTest() && testSpeechBodyOverride != null) {
            return testSpeechBodyOverride;
        }
        if (Test.isRunningTest() && skipCallout == true) {
            return Blob.valueOf('test-mp3');
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.elevenlabs.io/v1/text-to-speech/' + resolveVoiceId());
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'audio/mpeg');
        req.setHeader('xi-api-key', resolveApiKey());
        req.setTimeout(120000);
        req.setBody(
            JSON.serialize(
                new Map<String, Object>{
                    'text' => text,
                    'model_id' => ELEVEN_MODEL,
                    'voice_settings' => new Map<String, Object>{
                        'stability' => 0.4,
                        'similarity_boost' => 0.8
                    }
                }
            )
        );
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            String detail = res.getBody();
            if (String.isNotBlank(detail) && detail.length() > 240) {
                detail = detail.substring(0, 240);
            }
            throw new CalloutException(
                'ElevenLabs TTS failed (' +
                    res.getStatusCode() +
                    ')' +
                    (String.isBlank(detail) ? '.' : ': ' + detail)
            );
        }
        return res.getBodyAsBlob();
    }

    private static Map<String, Object> loadCachedAudio(String hash) {
        List<Hub_Briefing_Tts_Cache__c> rows = [
            SELECT Id, Mime_Type__c, Content_Version_Id__c
            FROM Hub_Briefing_Tts_Cache__c
            WHERE Script_Hash__c = :hash
            LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Content_Version_Id__c)) {
            return null;
        }
        List<ContentVersion> versions = [
            SELECT Id, VersionData
            FROM ContentVersion
            WHERE Id = :rows[0].Content_Version_Id__c
            LIMIT 1
        ];
        if (versions.isEmpty() || versions[0].VersionData == null) {
            return null;
        }
        return new Map<String, Object>{
            'mimeType' => String.isBlank(rows[0].Mime_Type__c) ? 'audio/mpeg' : rows[0].Mime_Type__c,
            'audioBase64' => EncodingUtil.base64Encode(versions[0].VersionData)
        };
    }

    private static void storeCachedAudio(String hash, Blob audio, String mimeType) {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'HubBriefingTTS_' + hash.substring(0, Math.min(24, hash.length()));
        cv.PathOnClient = hash + '.mp3';
        cv.VersionData = audio;
        cv.IsMajorVersion = true;
        insert cv;
        cv = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        List<Hub_Briefing_Tts_Cache__c> existing = [
            SELECT Id
            FROM Hub_Briefing_Tts_Cache__c
            WHERE Script_Hash__c = :hash
            LIMIT 1
        ];
        Hub_Briefing_Tts_Cache__c row = existing.isEmpty()
            ? new Hub_Briefing_Tts_Cache__c(Name = hash.left(80), Script_Hash__c = hash)
            : existing[0];
        row.Mime_Type__c = mimeType;
        row.Content_Version_Id__c = cv.Id;
        upsert row Script_Hash__c;
    }

    @TestVisible
    private static Boolean hasUsedSmartToday(Id userId, Date usageDate) {
        String userKey = String.valueOf(userId);
        List<Hub_Briefing_Credit__c> rows = [
            SELECT Id, Used_Smart__c
            FROM Hub_Briefing_Credit__c
            WHERE User_Id__c = :userKey AND Usage_Date__c = :usageDate
            LIMIT 1
        ];
        return !rows.isEmpty() && rows[0].Used_Smart__c == true;
    }

    @TestVisible
    private static void markSmartUsed(Id userId, Date usageDate) {
        String userKey = String.valueOf(userId);
        String key = userKey + '_' + String.valueOf(usageDate);
        List<Hub_Briefing_Credit__c> rows = [
            SELECT Id, Used_Smart__c
            FROM Hub_Briefing_Credit__c
            WHERE User_Id__c = :userKey AND Usage_Date__c = :usageDate
            LIMIT 1
        ];
        Hub_Briefing_Credit__c row = rows.isEmpty()
            ? new Hub_Briefing_Credit__c(
                  Name = key.left(80),
                  User_Id__c = userKey,
                  Usage_Date__c = usageDate,
                  Used_Smart__c = true
              )
            : rows[0];
        row.Used_Smart__c = true;
        upsert row;
    }

    private static String resolveApiKey() {
        if (apiKeyOverride != null) {
            return apiKeyOverride.trim();
        }
        Cloudastick_API_Config__mdt cfg = CloudastickApiConfig.getDefault();
        return cfg == null || String.isBlank(cfg.ElevenLabs_API_Key__c)
            ? ''
            : cfg.ElevenLabs_API_Key__c.trim();
    }

    private static String resolveVoiceId() {
        if (String.isNotBlank(voiceIdOverride)) {
            return voiceIdOverride.trim();
        }
        Cloudastick_API_Config__mdt cfg = CloudastickApiConfig.getDefault();
        if (cfg != null && String.isNotBlank(cfg.ElevenLabs_Voice_Id__c)) {
            return cfg.ElevenLabs_Voice_Id__c.trim();
        }
        return DEFAULT_VOICE_ID;
    }

    private static Map<String, Object> voiceResult(
        Boolean success,
        String engine,
        String fallback,
        String error,
        String mimeType,
        String audioBase64,
        CreditStatus credits
    ) {
        Map<String, Object> out = new Map<String, Object>{
            'success' => success,
            'engine' => engine,
            'voiceMode' => success ? 'smart' : 'standard'
        };
        if (String.isNotBlank(fallback)) {
            out.put('fallback', fallback);
        }
        if (String.isNotBlank(error)) {
            out.put('error', error);
        }
        if (String.isNotBlank(mimeType)) {
            out.put('mimeType', mimeType);
        }
        if (String.isNotBlank(audioBase64)) {
            out.put('audioBase64', audioBase64);
        }
        putCredits(out, credits);
        return out;
    }

    private static void putCredits(Map<String, Object> out, CreditStatus credits) {
        if (credits == null) {
            return;
        }
        out.put('smartUsedToday', credits.smartUsedToday);
        out.put('smartCreditsRemaining', credits.smartCreditsRemaining);
        out.put('elevenLabsConfigured', credits.elevenLabsConfigured);
    }
}
