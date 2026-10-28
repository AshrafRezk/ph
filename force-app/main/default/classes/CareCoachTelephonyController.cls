/**
 * Built-in dialler support for Care Coach Co-pilot.
 * The tablet places calls itself (JsSIP over WebSocket); Salesforce only hands out the SIP
 * settings, a short-lived ticket for the transcription service, and stores the recording.
 */
public with sharing class CareCoachTelephonyController {
    public static final Integer TICKET_TTL_SECONDS = 2 * 60 * 60;
    public static final Integer MAX_RECORDING_BASE64 = 3500000;

    public class DialerConfig {
        @AuraEnabled public Boolean enabled;
        @AuraEnabled public Boolean sipConfigured;
        @AuraEnabled public String wssUrl;
        @AuraEnabled public String domain;
        @AuraEnabled public String username;
        @AuraEnabled public String password;
        @AuraEnabled public String callerId;
        @AuraEnabled public Boolean transcriptionConfigured;
        @AuraEnabled public String transcribeEndpoint;
        @AuraEnabled public String transcribeTicket;
        @AuraEnabled public Boolean sentimentEnabled;
    }

    public class RecordingResult {
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String recordingUrl;
    }

    public class RecordingAudio {
        @AuraEnabled public String fileName;
        @AuraEnabled public String mimeType;
        @AuraEnabled public String base64Data;
        @AuraEnabled public String streamUrl;
    }

    public static Care_Coach_Telephony__c settings() {
        Care_Coach_Telephony__c s = Care_Coach_Telephony__c.getInstance();
        return s == null ? new Care_Coach_Telephony__c() : s;
    }

    @AuraEnabled
    public static DialerConfig getDialerConfig() {
        CareCoachAccess.assertCanEdit();
        Care_Coach_Telephony__c s = settings();
        DialerConfig c = new DialerConfig();
        c.enabled = s.Dialler_Enabled__c != false;
        c.sipConfigured = String.isNotBlank(s.SIP_WSS_URL__c) && String.isNotBlank(s.SIP_Domain__c) && String.isNotBlank(s.SIP_Username__c);
        if (c.enabled && c.sipConfigured) {
            c.wssUrl = s.SIP_WSS_URL__c;
            c.domain = s.SIP_Domain__c;
            c.username = s.SIP_Username__c;
            c.password = s.SIP_Password__c;
            c.callerId = s.Caller_Id__c;
        }
        c.transcriptionConfigured = String.isNotBlank(s.Transcribe_Endpoint__c) && String.isNotBlank(s.Transcribe_Secret__c);
        if (c.transcriptionConfigured) {
            c.transcribeEndpoint = s.Transcribe_Endpoint__c;
            c.transcribeTicket = ticket(s.Transcribe_Secret__c, UserInfo.getUserId(), System.now().getTime() / 1000 + TICKET_TTL_SECONDS);
        }
        c.sentimentEnabled = s.Sentiment_Enabled__c == true;
        return c;
    }

    /** "<userId>.<expiryEpochSeconds>.<base64url HMAC-SHA256>" - verified by the transcription service. */
    public static String ticket(String secret, Id userId, Long expiresAt) {
        String payload = userId + '.' + expiresAt;
        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(payload), Blob.valueOf(secret));
        String sig = EncodingUtil.base64Encode(mac).replace('+', '-').replace('/', '_').replace('=', '');
        return payload + '.' + sig;
    }

    @AuraEnabled
    public static void requestSentiment(Id callId) {
        CareCoachAccess.assertCanEdit();
        if (!CareCoachSentimentService.isEnabled()) {
            throw CareCoachAccess.fail('Sentiment analysis is not enabled. Ask your admin to configure Azure AI Language.');
        }
        List<Patient_Interaction__c> rows = [
            SELECT Id, Transcript__c FROM Patient_Interaction__c WHERE Id = :callId WITH USER_MODE LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Transcript__c)) {
            throw CareCoachAccess.fail('This call has no transcript to analyse.');
        }
        update as user new Patient_Interaction__c(Id = callId, AI_Sentiment_Details__c = null);
        CareCoachSentimentService.enqueueIfEnabled(callId, rows[0].Transcript__c);
    }

    @AuraEnabled
    public static RecordingResult attachCallRecording(Id callId, String fileName, String base64Data) {
        CareCoachAccess.assertCanEdit();
        if (callId == null || String.isBlank(base64Data)) {
            throw CareCoachAccess.fail('Call and recording are required.');
        }
        if (base64Data.length() > MAX_RECORDING_BASE64) {
            throw CareCoachAccess.fail('The recording is too long to store. The transcript was saved.');
        }
        List<Patient_Interaction__c> rows = [
            SELECT Id, Recording_Consent__c FROM Patient_Interaction__c WHERE Id = :callId WITH USER_MODE LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw CareCoachAccess.fail('Call not found.');
        }
        if (rows[0].Recording_Consent__c != true) {
            throw CareCoachAccess.fail('The patient has not consented to recording.');
        }
        String name = String.isBlank(fileName) ? 'Call recording.webm' : fileName;
        ContentVersion cv = new ContentVersion(
            Title = name.substringBeforeLast('.'),
            PathOnClient = name,
            VersionData = EncodingUtil.base64Decode(base64Data),
            FirstPublishLocationId = callId,
            Description = 'Care Coach call recording'
        );
        try {
            insert as user cv;
            Patient_Interaction__c upd = new Patient_Interaction__c(
                Id = callId,
                Recording_URL__c = URL.getOrgDomainUrl().toExternalForm() + '/sfc/servlet.shepherd/version/download/' + cv.Id
            );
            update as user upd;
            RecordingResult r = new RecordingResult();
            r.contentVersionId = cv.Id;
            r.recordingUrl = upd.Recording_URL__c;
            return r;
        } catch (DmlException e) {
            throw CareCoachAccess.fail(e.getDmlMessage(0));
        }
    }

    private static final Map<String, String> AUDIO_MIME = new Map<String, String>{
        'mp3' => 'audio/mpeg',
        'm4a' => 'audio/mp4',
        'mp4' => 'audio/mp4',
        'webm' => 'audio/webm',
        'wav' => 'audio/wav',
        'ogg' => 'audio/ogg'
    };

    /**
     * Audio for the in-app player. Stored call files come back as base64; demo clips
     * hosted by the field app come back as a stream URL. The pharma company view
     * never receives a recording, because the voice identifies the patient.
     */
    @AuraEnabled
    public static RecordingAudio getCallRecording(Id interactionId) {
        if (!CareCoachAccess.hasFullAccess()) {
            throw CareCoachAccess.fail('Recordings are hidden in the pharma company view.');
        }
        if (interactionId == null) {
            throw CareCoachAccess.fail('Call is required.');
        }
        List<Patient_Interaction__c> rows = [
            SELECT Id, Recording_URL__c, Recording_Consent__c
            FROM Patient_Interaction__c
            WHERE Id = :interactionId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw CareCoachAccess.fail('Call not found.');
        }
        if (rows[0].Recording_Consent__c != true) {
            throw CareCoachAccess.fail('The patient has not consented to recording.');
        }
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :interactionId
            WITH USER_MODE
        ];
        if (!links.isEmpty()) {
            Set<Id> docs = new Set<Id>();
            for (ContentDocumentLink link : links) {
                docs.add(link.ContentDocumentId);
            }
            List<ContentVersion> versions = [
                SELECT Title, FileExtension, VersionData
                FROM ContentVersion
                WHERE ContentDocumentId IN :docs AND IsLatest = TRUE
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!versions.isEmpty()) {
                String encoded = EncodingUtil.base64Encode(versions[0].VersionData);
                if (encoded.length() > MAX_RECORDING_BASE64) {
                    throw CareCoachAccess.fail('The recording is too long to play in the app.');
                }
                RecordingAudio audio = new RecordingAudio();
                String ext = versions[0].FileExtension == null ? '' : versions[0].FileExtension.toLowerCase();
                audio.fileName = versions[0].Title + (String.isBlank(ext) ? '' : '.' + ext);
                audio.mimeType = AUDIO_MIME.containsKey(ext) ? AUDIO_MIME.get(ext) : 'audio/webm';
                audio.base64Data = encoded;
                return audio;
            }
        }
        if (CareCoachCallSamples.isAppRecording(rows[0].Recording_URL__c)) {
            RecordingAudio audio = new RecordingAudio();
            audio.streamUrl = rows[0].Recording_URL__c;
            audio.mimeType = 'audio/mpeg';
            audio.fileName = rows[0].Recording_URL__c.substringAfterLast('/');
            return audio;
        }
        throw CareCoachAccess.fail('No recording is stored for this call.');
    }
}