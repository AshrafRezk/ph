public with sharing class ClmContentBridgeController {

    private static final Integer RAW_CHUNK_BYTES = 240000;

    public String docId { get; private set; }
    public String versionId { get; private set; }
    public String requestId { get; private set; }
    public Integer totalBytes { get; private set; }
    public String errorMessage { get; private set; }
    public List<String> base64Chunks { get; private set; }
    public List<ChunkRow> chunkRows { get; private set; }

    public class ChunkRow {
        public Integer index { get; private set; }
        public String base64 { get; private set; }

        public ChunkRow(Integer rowIndex, String encoded) {
            index = rowIndex;
            base64 = encoded;
        }
    }

    public Boolean getHasError() {
        return String.isNotBlank(errorMessage);
    }

    public ClmContentBridgeController() {
        docId = ApexPages.currentPage().getParameters().get('docId');
        versionId = ApexPages.currentPage().getParameters().get('versionId');
        requestId = ApexPages.currentPage().getParameters().get('requestId');
        if (String.isBlank(requestId)) {
            requestId = String.isNotBlank(docId) ? docId : ('req_' + String.valueOf(System.now().getTime()));
        }
        base64Chunks = new List<String>();
        chunkRows = new List<ChunkRow>();

        try {
            Blob content = loadPresentationBlob(docId, versionId);
            totalBytes = content.size();
            base64Chunks = splitBase64Chunks(content);
            for (Integer i = 0; i < base64Chunks.size(); i++) {
                chunkRows.add(new ChunkRow(i, base64Chunks[i]));
            }
        } catch (Exception ex) {
            errorMessage = ex.getMessage();
            totalBytes = 0;
        }
    }

    @TestVisible
    private static Blob loadPresentationBlob(String contentDocumentId, String contentVersionId) {
        List<String> paths = new List<String>();
        if (String.isNotBlank(contentVersionId)) {
            paths.add('/sfc/servlet.shepherd/version/download/' + contentVersionId.trim());
        }
        if (String.isNotBlank(contentDocumentId)) {
            paths.add('/sfc/servlet.shepherd/document/download/' + contentDocumentId.trim());
        }
        if (paths.isEmpty()) {
            throw new ClmPdfViewerController.ClmViewerException('Missing presentation file.');
        }

        for (String path : paths) {
            try {
                Blob body = new PageReference(path).getContent();
                if (isUsableContent(body)) {
                    return body;
                }
            } catch (Exception ex) {
                /* try next source */
            }
        }

        return loadPresentationBlobFromVersionTable(contentDocumentId, contentVersionId);
    }

    @TestVisible
    private static Blob loadPresentationBlobFromVersionTable(
        String contentDocumentId,
        String contentVersionId
    ) {
        List<ContentVersion> versions;
        if (String.isNotBlank(contentVersionId) && String.valueOf(contentVersionId).startsWith('068')) {
            versions = [
                SELECT VersionData
                FROM ContentVersion
                WHERE Id = :contentVersionId.trim()
                WITH USER_MODE
                LIMIT 1
            ];
        } else if (String.isNotBlank(contentDocumentId)) {
            versions = [
                SELECT VersionData
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId.trim() AND IsLatest = true
                WITH USER_MODE
                LIMIT 1
            ];
        } else {
            throw new ClmPdfViewerController.ClmViewerException('Missing presentation file.');
        }
        if (versions.isEmpty() || versions[0].VersionData == null || versions[0].VersionData.size() == 0) {
            throw new ClmPdfViewerController.ClmViewerException(
                'Presentation file not found or not accessible.'
            );
        }
        return versions[0].VersionData;
    }

    @TestVisible
    private static Boolean isUsableContent(Blob body) {
        if (body == null || body.size() == 0) {
            return false;
        }
        return !looksLikeLoginHtml(body);
    }

    @TestVisible
    private static Boolean looksLikeLoginHtml(Blob body) {
        String hex = EncodingUtil.convertToHex(body);
        if (hex.length() < 8) {
            return false;
        }
        String head = hex.substring(0, Math.min(24, hex.length())).toLowerCase();
        return head.startsWith('3c21444f4354') || head.startsWith('3c68746d6c') || head.startsWith('3c484541');
    }

    @TestVisible
    private static List<String> splitBase64Chunks(Blob content) {
        List<String> chunks = new List<String>();
        if (content == null || content.size() == 0) {
            return chunks;
        }
        String hex = EncodingUtil.convertToHex(content);
        Integer size = content.size();
        for (Integer offset = 0; offset < size; offset += RAW_CHUNK_BYTES) {
            Integer take = Math.min(RAW_CHUNK_BYTES, size - offset);
            Integer hexStart = offset * 2;
            Integer hexEnd = hexStart + take * 2;
            String partHex = hex.substring(hexStart, hexEnd);
            chunks.add(EncodingUtil.base64Encode(EncodingUtil.convertFromHex(partHex)));
        }
        return chunks;
    }
}