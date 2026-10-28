public with sharing class ClmContentDownloadService {

    private static final Integer CHUNK_SIZE_BYTES = 2500000;
    private static final Integer MAX_IN_MEMORY_SLICE_BYTES = 5200000;
    private static final String API_VERSION = 'v62.0';

    public class ContentChunkResult {
        @AuraEnabled public Integer totalSize;
        @AuraEnabled public Integer offset;
        @AuraEnabled public Integer bytesRead;
        @AuraEnabled public String base64Data;
        @AuraEnabled public Boolean done;
    }

    private class EndpointAttempt {
        public String url;
        public Boolean useAuth;
    }

    private class VersionInfo {
        public Id versionId;
        public Id contentDocumentId;
        public Integer totalSize;
    }

    @AuraEnabled(cacheable=false)
    public static ContentChunkResult getContentChunk(String contentDocumentId, Integer byteOffset) {
        try {
            return loadContentChunk(contentDocumentId, byteOffset);
        } catch (ClmPdfViewerController.ClmViewerException error) {
            throw new AuraHandledException(error.getMessage());
        }
    }

    @TestVisible
    private static ContentChunkResult loadContentChunk(String contentDocumentId, Integer byteOffset) {
        if (String.isBlank(contentDocumentId)) {
            throw new ClmPdfViewerController.ClmViewerException('Presentation file is missing.');
        }
        Integer offset = byteOffset == null || byteOffset < 0 ? 0 : byteOffset;

        VersionInfo versionInfo = resolveLatestVersion(contentDocumentId);
        if (versionInfo.totalSize <= 0) {
            throw new ClmPdfViewerController.ClmViewerException('Presentation file is empty or unavailable.');
        }
        if (offset >= versionInfo.totalSize) {
            ContentChunkResult empty = new ContentChunkResult();
            empty.totalSize = versionInfo.totalSize;
            empty.offset = offset;
            empty.bytesRead = 0;
            empty.base64Data = '';
            empty.done = true;
            return empty;
        }

        Integer endByte = Math.min(offset + CHUNK_SIZE_BYTES - 1, versionInfo.totalSize - 1);
        Integer length = endByte - offset + 1;
        Blob chunk = fetchVersionBytes(
            versionInfo.versionId,
            versionInfo.contentDocumentId,
            offset,
            length,
            versionInfo.totalSize
        );

        ContentChunkResult result = new ContentChunkResult();
        result.totalSize = versionInfo.totalSize;
        result.offset = offset;
        result.bytesRead = chunk == null ? 0 : chunk.size();
        result.base64Data = chunk == null || chunk.size() == 0 ? '' : EncodingUtil.base64Encode(chunk);
        result.done = offset + result.bytesRead >= versionInfo.totalSize;
        return result;
    }

    private static VersionInfo resolveLatestVersion(String fileId) {
        String idValue = String.valueOf(fileId).trim();
        List<ContentVersion> versions;
        if (idValue.startsWith('068')) {
            versions = [
                SELECT Id, ContentSize, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :idValue
                WITH USER_MODE
                LIMIT 1
            ];
        } else {
            versions = [
                SELECT Id, ContentSize, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId = :idValue AND IsLatest = true
                WITH USER_MODE
                LIMIT 1
            ];
        }
        if (versions.isEmpty()) {
            throw new ClmPdfViewerController.ClmViewerException(
                'Presentation file not found or not accessible. Confirm the deck is shared to your territory.'
            );
        }
        VersionInfo info = new VersionInfo();
        info.versionId = versions[0].Id;
        info.contentDocumentId = versions[0].ContentDocumentId;
        info.totalSize = versions[0].ContentSize != null ? Integer.valueOf(versions[0].ContentSize) : 0;
        return info;
    }

    @TestVisible
    private static Boolean useHttpInTest = false;

    @TestVisible
    private static Blob fetchVersionBytes(
        Id contentVersionId,
        Id contentDocumentId,
        Integer startByte,
        Integer length,
        Integer totalSize
    ) {
        if (Test.isRunningTest() && useHttpInTest != true) {
            return fetchVersionBytesForTest(contentVersionId, startByte, length);
        }

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        Integer endByte = startByte + length - 1;
        List<EndpointAttempt> attempts = buildDownloadAttempts(
            baseUrl,
            contentVersionId,
            contentDocumentId
        );

        String lastError = 'Unable to stream presentation file.';
        for (EndpointAttempt attempt : attempts) {
            if (String.isBlank(attempt.url)) {
                continue;
            }
            try {
                return requestRange(attempt.url, startByte, endByte, length, totalSize, attempt.useAuth);
            } catch (ClmPdfViewerController.ClmViewerException ex) {
                lastError = ex.getMessage();
            }
        }

        if (totalSize != null && totalSize <= MAX_IN_MEMORY_SLICE_BYTES) {
            try {
                return fetchVersionBytesForTest(contentVersionId, startByte, length);
            } catch (Exception ex) {
                lastError = ex.getMessage();
            }
        }

        throw new ClmPdfViewerController.ClmViewerException(lastError);
    }

    @TestVisible
    private static List<EndpointAttempt> buildDownloadAttempts(
        String baseUrl,
        Id contentVersionId,
        Id contentDocumentId
    ) {
        List<EndpointAttempt> attempts = new List<EndpointAttempt>();
        String publicUrl = resolvePublicDownloadUrl(contentVersionId);
        if (String.isNotBlank(publicUrl)) {
            EndpointAttempt publicAttempt = new EndpointAttempt();
            publicAttempt.url = publicUrl;
            publicAttempt.useAuth = false;
            attempts.add(publicAttempt);
        }

        EndpointAttempt versionAttempt = new EndpointAttempt();
        versionAttempt.url =
            baseUrl +
            '/sfc/servlet.shepherd/version/download/' +
            String.valueOf(contentVersionId);
        versionAttempt.useAuth = true;
        attempts.add(versionAttempt);

        if (contentDocumentId != null) {
            EndpointAttempt documentAttempt = new EndpointAttempt();
            documentAttempt.url =
                baseUrl +
                '/sfc/servlet.shepherd/document/download/' +
                String.valueOf(contentDocumentId);
            documentAttempt.useAuth = true;
            attempts.add(documentAttempt);
        }

        EndpointAttempt restAttempt = new EndpointAttempt();
        restAttempt.url =
            baseUrl +
            '/services/data/' +
            API_VERSION +
            '/sobjects/ContentVersion/' +
            String.valueOf(contentVersionId) +
            '/VersionData';
        restAttempt.useAuth = true;
        attempts.add(restAttempt);

        return attempts;
    }

    @TestVisible
    private static String resolvePublicDownloadUrl(Id contentVersionId) {
        List<ContentDistribution> distributions = [
            SELECT ContentDownloadUrl, DistributionPublicUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :contentVersionId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (distributions.isEmpty()) {
            return null;
        }
        return pickDistributionUrl(distributions[0]);
    }

    private static String pickDistributionUrl(ContentDistribution distribution) {
        if (distribution == null) {
            return null;
        }
        if (String.isNotBlank(distribution.ContentDownloadUrl)) {
            return distribution.ContentDownloadUrl;
        }
        return distribution.DistributionPublicUrl;
    }

    @TestVisible
    private static Blob requestRange(
        String endpoint,
        Integer startByte,
        Integer endByte,
        Integer length,
        Integer totalSize
    ) {
        return requestRange(endpoint, startByte, endByte, length, totalSize, true);
    }

    @TestVisible
    private static Blob requestRange(
        String endpoint,
        Integer startByte,
        Integer endByte,
        Integer length,
        Integer totalSize,
        Boolean useAuth
    ) {
        HttpResponse response = sendRangeRequest(endpoint, startByte, endByte, useAuth);
        try {
            return parseRangeResponse(response, startByte, length, totalSize);
        } catch (ClmPdfViewerController.ClmViewerException firstPass) {
            if (!useAuth) {
                throw firstPass;
            }
            HttpResponse oauthResponse = sendRangeRequest(endpoint, startByte, endByte, false, true);
            return parseRangeResponse(oauthResponse, startByte, length, totalSize);
        }
    }

    private static HttpResponse sendRangeRequest(
        String endpoint,
        Integer startByte,
        Integer endByte,
        Boolean useAuth
    ) {
        return sendRangeRequest(endpoint, startByte, endByte, useAuth, false);
    }

    private static HttpResponse sendRangeRequest(
        String endpoint,
        Integer startByte,
        Integer endByte,
        Boolean useAuth,
        Boolean oauthHeader
    ) {
        HttpRequest rangeRequest = new HttpRequest();
        rangeRequest.setEndpoint(endpoint);
        rangeRequest.setMethod('GET');
        rangeRequest.setTimeout(120000);
        rangeRequest.setHeader('Accept', 'application/octet-stream');
        rangeRequest.setHeader('Range', 'bytes=' + startByte + '-' + endByte);
        if (useAuth) {
            String sessionId = UserInfo.getSessionId();
            rangeRequest.setHeader(
                'Authorization',
                (oauthHeader ? 'OAuth ' : 'Bearer ') + sessionId
            );
        }
        return new Http().send(rangeRequest);
    }

    @TestVisible
    private static Blob parseRangeResponse(
        HttpResponse rangeResponse,
        Integer startByte,
        Integer length,
        Integer totalSize
    ) {
        Integer status = rangeResponse.getStatusCode();
        if (status == 206) {
            return rangeResponse.getBodyAsBlob();
        }
        if (status != 200) {
            throw new ClmPdfViewerController.ClmViewerException(
                'Unable to stream presentation file (HTTP ' + status + ').'
            );
        }

        Blob body = rangeResponse.getBodyAsBlob();
        if (body == null || body.size() == 0) {
            throw new ClmPdfViewerController.ClmViewerException('Unable to stream presentation file (empty body).');
        }
        if (body.size() == length) {
            return body;
        }
        if (startByte == 0 && body.size() <= length) {
            return body;
        }
        if (startByte + length <= body.size() && body.size() <= MAX_IN_MEMORY_SLICE_BYTES) {
            return sliceBlob(body, startByte, length);
        }
        if (totalSize != null && body.size() == totalSize && totalSize <= MAX_IN_MEMORY_SLICE_BYTES) {
            return sliceBlob(body, startByte, length);
        }
        throw new ClmPdfViewerController.ClmViewerException(
            'Unable to stream presentation file (HTTP 200).'
        );
    }

    @TestVisible
    private static Blob fetchVersionBytesForTest(Id contentVersionId, Integer startByte, Integer length) {
        List<ContentVersion> versions = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            return Blob.valueOf('');
        }
        return sliceBlob(versions[0].VersionData, startByte, length);
    }

    @TestVisible
    private static Blob sliceBlob(Blob source, Integer startByte, Integer length) {
        if (source == null || source.size() == 0) {
            return Blob.valueOf('');
        }
        Integer safeStart = startByte == null || startByte < 0 ? 0 : startByte;
        if (safeStart >= source.size()) {
            return Blob.valueOf('');
        }
        Integer safeLength = length == null || length < 1 ? 0 : length;
        Integer maxLength = source.size() - safeStart;
        Integer take = Math.min(safeLength, maxLength);
        if (take <= 0) {
            return Blob.valueOf('');
        }

        String hex = EncodingUtil.convertToHex(source);
        Integer hexStart = safeStart * 2;
        Integer hexEnd = hexStart + take * 2;
        if (hexEnd > hex.length()) {
            hexEnd = hex.length();
        }
        if (hexStart >= hexEnd) {
            return Blob.valueOf('');
        }
        return EncodingUtil.convertFromHex(hex.substring(hexStart, hexEnd));
    }
}