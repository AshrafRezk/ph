@IsTest
private class ClmContentDownloadServiceTest {

    @TestSetup
    static void createHttpTestVersion() {
        insert new ContentVersion(
            Title = 'clm-http-test',
            PathOnClient = 'clm-http-test.zip',
            VersionData = Blob.valueOf('0123456789'),
            IsMajorVersion = true
        );
    }

    private static ContentVersion getHttpTestVersion() {
        return [
            SELECT Id, ContentDocumentId, ContentSize
            FROM ContentVersion
            WHERE Title = 'clm-http-test'
            LIMIT 1
        ];
    }

    private static ContentVersion insertSampleVersion(Blob payload) {
        ContentVersion version = new ContentVersion(
            Title = 'clm-chunk.zip',
            PathOnClient = 'clm-chunk.zip',
            VersionData = payload,
            IsMajorVersion = true
        );
        insert version;
        return [
            SELECT Id, ContentDocumentId, ContentSize
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];
    }

    @IsTest
    static void getContentChunk_returnsFirstAndSecondSlices() {
        Blob payload = Blob.valueOf('0123456789ABCDEFGHIJ');
        ContentVersion version = insertSampleVersion(payload);

        Test.startTest();
        ClmContentDownloadService.ContentChunkResult first = ClmContentDownloadService.getContentChunk(
            version.ContentDocumentId,
            0
        );
        ClmContentDownloadService.ContentChunkResult second = ClmContentDownloadService.getContentChunk(
            version.ContentDocumentId,
            first.bytesRead
        );
        Test.stopTest();

        System.assertEquals(payload.size(), first.totalSize);
        System.assertEquals(0, first.offset);
        System.assertEquals(true, first.done);
        System.assertEquals(EncodingUtil.base64Encode(payload), first.base64Data);
        System.assertEquals(true, second.done);
        System.assertEquals(0, second.bytesRead);
    }

    @IsTest
    static void getContentChunk_acceptsContentVersionIdAndPartialOffset() {
        Blob payload = Blob.valueOf('0123456789ABCDEFGHIJ');
        ContentVersion version = insertSampleVersion(payload);

        Test.startTest();
        ClmContentDownloadService.ContentChunkResult mid = ClmContentDownloadService.getContentChunk(
            String.valueOf(version.Id),
            5
        );
        ClmContentDownloadService.ContentChunkResult fromNullOffset = ClmContentDownloadService.getContentChunk(
            version.ContentDocumentId,
            null
        );
        Test.stopTest();

        System.assertEquals(5, mid.offset);
        System.assertEquals(
            EncodingUtil.base64Encode(Blob.valueOf('56789ABCDEFGHIJ')),
            mid.base64Data
        );
        System.assertEquals(true, mid.done);
        System.assertEquals(0, fromNullOffset.offset);
    }

    @IsTest
    static void getContentChunk_returnsEmptyWhenOffsetPastEnd() {
        ContentVersion version = insertSampleVersion(Blob.valueOf('abc'));

        Test.startTest();
        ClmContentDownloadService.ContentChunkResult pastEnd = ClmContentDownloadService.getContentChunk(
            version.ContentDocumentId,
            100
        );
        Test.stopTest();

        System.assertEquals(3, pastEnd.totalSize);
        System.assertEquals(100, pastEnd.offset);
        System.assertEquals(0, pastEnd.bytesRead);
        System.assertEquals('', pastEnd.base64Data);
        System.assertEquals(true, pastEnd.done);
    }

    @IsTest
    static void getContentChunk_rejectsMissingAndUnknownDocument() {
        Boolean missingThrew = false;
        Boolean unknownThrew = false;

        Test.startTest();
        try {
            ClmContentDownloadService.getContentChunk(null, 0);
        } catch (AuraHandledException ex) {
            missingThrew = true;
            System.assertNotEquals(null, ex.getMessage());
        }
        try {
            ClmContentDownloadService.getContentChunk('069000000000000AAA', 0);
        } catch (AuraHandledException ex) {
            unknownThrew = true;
            System.assertNotEquals(null, ex.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, missingThrew);
        System.assertEquals(true, unknownThrew);
    }

    @IsTest
    static void sliceBlob_handlesEdgeCases() {
        Blob payload = Blob.valueOf('0123456789');

        System.assertEquals(0, ClmContentDownloadService.sliceBlob(null, 0, 3).size());
        System.assertEquals(0, ClmContentDownloadService.sliceBlob(Blob.valueOf(''), 0, 3).size());
        System.assertEquals(0, ClmContentDownloadService.sliceBlob(payload, 99, 3).size());
        System.assertEquals(0, ClmContentDownloadService.sliceBlob(payload, 0, 0).size());
        System.assertEquals(
            Blob.valueOf('234'),
            ClmContentDownloadService.sliceBlob(payload, 2, 3)
        );
        System.assertEquals(
            Blob.valueOf('89'),
            ClmContentDownloadService.sliceBlob(payload, 8, 10)
        );
    }

    @IsTest
    static void fetchVersionBytesForTest_returnsEmptyWhenVersionMissing() {
        Test.startTest();
        Blob missing = ClmContentDownloadService.fetchVersionBytesForTest(
            '068000000000000AAA',
            0,
            10
        );
        Test.stopTest();
        System.assertEquals(0, missing.size());
    }

    @IsTest
    static void getContentChunk_normalizesNegativeOffset() {
        ContentVersion version = insertSampleVersion(Blob.valueOf('abc'));

        Test.startTest();
        ClmContentDownloadService.ContentChunkResult result = ClmContentDownloadService.getContentChunk(
            version.ContentDocumentId,
            -3
        );
        Test.stopTest();

        System.assertEquals(0, result.offset);
        System.assertEquals(EncodingUtil.base64Encode(Blob.valueOf('abc')), result.base64Data);
    }

    @IsTest
    static void requestRange_returns206Body() {
        Test.setMock(HttpCalloutMock.class, new Range206Mock());

        Test.startTest();
        Blob chunk = ClmContentDownloadService.requestRange(
            'https://example.my.salesforce.com/services/data/v62.0/sobjects/ContentVersion/068xx/VersionData',
            0,
            4,
            5,
            5
        );
        Test.stopTest();

        System.assertEquals(Blob.valueOf('chunk'), chunk);
    }

    @IsTest
    static void requestRange_returnsFull200BodyFromStart() {
        Test.setMock(HttpCalloutMock.class, new Full200Mock());

        Test.startTest();
        Blob chunk = ClmContentDownloadService.requestRange(
            'https://example.my.salesforce.com/services/data/v62.0/sobjects/ContentVersion/068xx/VersionData',
            0,
            4,
            5,
            5
        );
        Test.stopTest();

        System.assertEquals(Blob.valueOf('01234'), chunk);
    }

    @IsTest
    static void requestRange_slicesSmall200Response() {
        Test.setMock(HttpCalloutMock.class, new Full200Mock());

        Test.startTest();
        Blob chunk = ClmContentDownloadService.requestRange(
            'https://example.my.salesforce.com/sfc/servlet.shepherd/version/download/068xx',
            2,
            4,
            2,
            5
        );
        Test.stopTest();

        System.assertEquals(Blob.valueOf('23'), chunk);
    }

    @IsTest
    static void requestRange_throwsOnFailureStatus() {
        Test.setMock(HttpCalloutMock.class, new Error404Mock());
        Boolean threw = false;

        Test.startTest();
        try {
            ClmContentDownloadService.requestRange(
                'https://example.my.salesforce.com/services/data/v62.0/sobjects/ContentVersion/068xx/VersionData',
                0,
                4,
                5,
                5000000
            );
        } catch (ClmPdfViewerController.ClmViewerException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('HTTP 404'));
        }
        Test.stopTest();

        System.assertEquals(true, threw);
    }

    @IsTest
    static void getContentChunk_usesHttpWhenTestFlagEnabled() {
        ContentVersion version = getHttpTestVersion();
        ClmContentDownloadService.useHttpInTest = true;
        Test.setMock(HttpCalloutMock.class, new Range206Mock());

        Test.startTest();
        ClmContentDownloadService.ContentChunkResult result = ClmContentDownloadService.getContentChunk(
            version.ContentDocumentId,
            0
        );
        Test.stopTest();

        ClmContentDownloadService.useHttpInTest = false;
        System.assertEquals(Blob.valueOf('chunk').size(), result.bytesRead);
        System.assertEquals(EncodingUtil.base64Encode(Blob.valueOf('chunk')), result.base64Data);
    }

    @IsTest
    static void fetchVersionBytes_throwsWhenAllEndpointsFail() {
        ContentVersion version = getHttpTestVersion();
        ClmContentDownloadService.useHttpInTest = true;
        Test.setMock(HttpCalloutMock.class, new Error404Mock());
        Boolean threw = false;

        Test.startTest();
        try {
            ClmContentDownloadService.fetchVersionBytes(
                version.Id,
                version.ContentDocumentId,
                0,
                3,
                6000000
            );
        } catch (ClmPdfViewerController.ClmViewerException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('HTTP 404'));
        }
        Test.stopTest();

        ClmContentDownloadService.useHttpInTest = false;
        System.assertEquals(true, threw);
    }

    @IsTest
    static void fetchVersionBytes_fallsBackToSecondEndpoint() {
        ContentVersion version = getHttpTestVersion();
        ClmContentDownloadService.useHttpInTest = true;
        Test.setMock(HttpCalloutMock.class, new RestFailShepherd206Mock());

        Test.startTest();
        Blob chunk = ClmContentDownloadService.fetchVersionBytes(
            version.Id,
            version.ContentDocumentId,
            0,
            5,
            10
        );
        Test.stopTest();

        ClmContentDownloadService.useHttpInTest = false;
        System.assertEquals(Blob.valueOf('chunk'), chunk);
    }

    private class Range206Mock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(206);
            res.setBodyAsBlob(Blob.valueOf('chunk'));
            return res;
        }
    }

    private class Full200Mock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBodyAsBlob(Blob.valueOf('01234'));
            return res;
        }
    }

    private class Error404Mock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            return res;
        }
    }

    private class RestFailShepherd206Mock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint();
            if (endpoint.contains('VersionData')) {
                res.setStatusCode(500);
                return res;
            }
            if (endpoint.contains('/sfc/servlet.shepherd/')) {
                res.setStatusCode(206);
                res.setBodyAsBlob(Blob.valueOf('chunk'));
                return res;
            }
            res.setStatusCode(404);
            return res;
        }
    }

    @IsTest
    static void parseRangeResponse_accepts200ChunkWithMatchingLength() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBodyAsBlob(Blob.valueOf('cde'));

        Test.startTest();
        Blob chunk = ClmContentDownloadService.parseRangeResponse(res, 2, 3, 10);
        Test.stopTest();

        System.assertEquals(Blob.valueOf('cde'), chunk);
    }
}