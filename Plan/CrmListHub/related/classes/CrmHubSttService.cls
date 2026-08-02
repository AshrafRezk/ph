/**
 * Hub voice-search STT via ElevenLabs Scribe (browser Web Speech is unreliable in SF).
 */
public without sharing class CrmHubSttService {
    private static final String STT_ENDPOINT = 'https://api.elevenlabs.io/v1/speech-to-text';
    private static final String STT_MODEL = 'scribe_v1';
    private static final Integer MAX_AUDIO_BYTES = 3 * 1024 * 1024;

    @TestVisible
    private static String apiKeyOverride;
    @TestVisible
    private static String testTranscriptOverride;
    @TestVisible
    private static Boolean skipCallout;

    public static Map<String, Object> transcribe(String audioBase64, String mimeType) {
        if (String.isBlank(audioBase64)) {
            return result(false, null, 'Nothing to transcribe.');
        }
        String key = resolveApiKey();
        if (String.isBlank(key)) {
            return result(false, null, 'Speech-to-text is not configured (ElevenLabs API key).');
        }

        Blob audio;
        try {
            audio = EncodingUtil.base64Decode(audioBase64.trim());
        } catch (Exception e) {
            return result(false, null, 'Invalid audio payload.');
        }
        if (audio == null || audio.size() == 0) {
            return result(false, null, 'Empty audio.');
        }
        if (audio.size() > MAX_AUDIO_BYTES) {
            return result(false, null, 'Recording too long. Tap Stop sooner and try again.');
        }

        String safeMime = String.isBlank(mimeType) ? 'audio/webm' : mimeType.trim();
        if (safeMime.contains(';')) {
            safeMime = safeMime.substringBefore(';').trim();
        }

        if (Test.isRunningTest() && String.isNotBlank(testTranscriptOverride)) {
            return result(true, testTranscriptOverride.trim(), null);
        }
        if (Test.isRunningTest() && skipCallout == true) {
            return result(true, 'test transcript', null);
        }

        try {
            String text = callElevenLabsStt(key, audio, safeMime);
            if (String.isBlank(text)) {
                return result(false, null, 'Could not understand that. Please try again.');
            }
            return result(true, text.trim(), null);
        } catch (Exception e) {
            return result(false, null, e.getMessage());
        }
    }

    private static String callElevenLabsStt(String apiKey, Blob audio, String mimeType) {
        String boundary = 'CrmHubStt' + String.valueOf(Crypto.getRandomLong()).replace('-', 'n');
        String fileName = mimeType.contains('mp4') || mimeType.contains('m4a')
            ? 'speech.m4a'
            : (mimeType.contains('ogg') ? 'speech.ogg' : 'speech.webm');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(STT_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('xi-api-key', apiKey);
        req.setHeader('Accept', 'application/json');
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        req.setTimeout(120000);
        req.setBodyAsBlob(
            buildMultipart(
                boundary,
                new Map<String, String>{ 'model_id' => STT_MODEL },
                'file',
                fileName,
                mimeType,
                audio
            )
        );

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            String detail = res.getBody();
            if (String.isNotBlank(detail) && detail.length() > 240) {
                detail = detail.substring(0, 240);
            }
            throw new CalloutException(
                'Speech-to-text failed (' +
                    res.getStatusCode() +
                    ')' +
                    (String.isBlank(detail) ? '.' : ': ' + detail)
            );
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (parsed == null) {
            return null;
        }
        Object text = parsed.get('text');
        return text == null ? null : String.valueOf(text).trim();
    }

    /** Multipart form with binary file via hex concat (safe for Blob bodies). */
    @TestVisible
    private static Blob buildMultipart(
        String boundary,
        Map<String, String> fields,
        String fileField,
        String fileName,
        String mimeType,
        Blob fileBody
    ) {
        String header = '';
        if (fields != null) {
            for (String key : fields.keySet()) {
                header +=
                    '--' +
                    boundary +
                    '\r\nContent-Disposition: form-data; name="' +
                    key +
                    '"\r\n\r\n' +
                    fields.get(key) +
                    '\r\n';
            }
        }
        header +=
            '--' +
            boundary +
            '\r\nContent-Disposition: form-data; name="' +
            fileField +
            '"; filename="' +
            fileName +
            '"\r\nContent-Type: ' +
            mimeType +
            '\r\n\r\n';
        String footer = '\r\n--' + boundary + '--\r\n';
        return EncodingUtil.convertFromHex(
            EncodingUtil.convertToHex(Blob.valueOf(header)) +
                EncodingUtil.convertToHex(fileBody) +
                EncodingUtil.convertToHex(Blob.valueOf(footer))
        );
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

    private static Map<String, Object> result(Boolean success, String transcript, String error) {
        Map<String, Object> out = new Map<String, Object>{ 'success' => success };
        if (String.isNotBlank(transcript)) {
            out.put('transcript', transcript);
        }
        if (String.isNotBlank(error)) {
            out.put('error', error);
        }
        return out;
    }
}
