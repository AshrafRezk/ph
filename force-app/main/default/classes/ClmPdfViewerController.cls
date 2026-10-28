public with sharing class ClmPdfViewerController {

    @AuraEnabled(cacheable=true)
    public static String resolveContentDocumentId(String salesforceFileId) {
        if (String.isBlank(salesforceFileId)) {
            return null;
        }
        String idValue = String.valueOf(salesforceFileId).trim();
        if (idValue.startsWith('069')) {
            return idValue;
        }
        if (idValue.startsWith('068')) {
            List<ContentVersion> versions = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :idValue
                WITH USER_MODE
                LIMIT 1
            ];
            return versions.isEmpty() ? null : String.valueOf(versions[0].ContentDocumentId);
        }
        return null;
    }

    @AuraEnabled(cacheable=false)
    public static String getPdfBase64ForPlayer(String contentDocumentId) {
        try {
            return loadPdfBase64(contentDocumentId);
        } catch (ClmViewerException error) {
            throw new AuraHandledException(error.getMessage());
        }
    }

    @RemoteAction
    public static String getPdfBase64(String contentDocumentId) {
        return loadPdfBase64(contentDocumentId);
    }

    private static String loadPdfBase64(String contentDocumentId) {
        if (String.isBlank(contentDocumentId)) {
            throw new ClmViewerException('Presentation file is missing. Ask your admin to re-upload the deck.');
        }

        Boolean isVersionId = String.valueOf(contentDocumentId).startsWith('068');
        List<ContentVersion> sizes = isVersionId
            ? [
                SELECT ContentSize
                FROM ContentVersion
                WHERE Id = :contentDocumentId
                WITH USER_MODE
                LIMIT 1
            ]
            : [
                SELECT ContentSize
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
                WITH USER_MODE
                LIMIT 1
            ];
        if (sizes.isEmpty()) {
            throw new ClmViewerException(
                'Presentation file not found or not accessible. Confirm the deck is shared to your territory.'
            );
        }
        Decimal contentSize = sizes[0].ContentSize;
        if (contentSize != null && contentSize > 4500000) {
            throw new ClmViewerException(
                'This presentation is too large to load through Apex (' +
                String.valueOf((contentSize / 1048576).setScale(1)) +
                ' MB). The mobile client downloads large decks from Files directly.'
            );
        }

        List<ContentVersion> versions = isVersionId
            ? [
                SELECT VersionData
                FROM ContentVersion
                WHERE Id = :contentDocumentId
                WITH USER_MODE
                LIMIT 1
            ]
            : [
                SELECT VersionData
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
                WITH USER_MODE
                LIMIT 1
            ];
        Blob versionData = versions.isEmpty() ? null : versions[0].VersionData;
        if (versionData == null || versionData.size() == 0) {
            throw new ClmViewerException('Presentation file is empty or unavailable.');
        }

        return EncodingUtil.base64Encode(versionData);
    }

    public class ClmViewerException extends Exception {}
}