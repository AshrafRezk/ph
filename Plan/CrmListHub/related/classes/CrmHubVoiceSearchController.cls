/**
 * Thin remoting entry for Hub voice-search transcription.
 * Extension constructor required so $RemoteAction can bind on CrmHubList.
 */
public with sharing class CrmHubVoiceSearchController {
    public CrmHubVoiceSearchController(CrmHubListController controller) {
    }

    @RemoteAction
    public static Map<String, Object> transcribeHubSpeech(String audioBase64, String mimeType) {
        return CrmHubSttService.transcribe(audioBase64, mimeType);
    }
}
