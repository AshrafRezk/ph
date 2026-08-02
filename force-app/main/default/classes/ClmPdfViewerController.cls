public with sharing class ClmPdfViewerController {

    @AuraEnabled(cacheable=false)
    public static String getPdfBase64ForPlayer(String contentDocumentId) {
        return loadPdfBase64(contentDocumentId);
    }

    @RemoteAction
    public static String getPdfBase64(String contentDocumentId) {
        return loadPdfBase64(contentDocumentId);
    }

    private static String loadPdfBase64(String contentDocumentId) {
        if (String.isBlank(contentDocumentId)) {
            throw new AuraHandledException('Presentation file is missing. Ask your admin to re-upload the deck.');
        }

        List<ContentVersion> versions = [
            SELECT VersionData, ContentSize
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            throw new AuraHandledException(
                'Presentation file not found or not accessible. Confirm the deck is shared to your territory.'
            );
        }

        Blob versionData = versions[0].VersionData;
        if (versionData == null || versionData.size() == 0) {
            throw new AuraHandledException('Presentation file is empty or unavailable.');
        }

        return EncodingUtil.base64Encode(versionData);
    }
}
