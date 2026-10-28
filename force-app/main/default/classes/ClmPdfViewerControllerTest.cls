@IsTest
private class ClmPdfViewerControllerTest {

    @IsTest
    static void getPdfBase64ForPlayer_returnsEncodedContent() {
        ContentVersion version = new ContentVersion(
            Title = 'clm-test.pdf',
            PathOnClient = 'clm-test.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 clm viewer test'),
            IsMajorVersion = true
        );
        insert version;

        version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        Test.startTest();
        String encoded = ClmPdfViewerController.getPdfBase64ForPlayer(version.ContentDocumentId);
        Test.stopTest();

        System.assertEquals(
            EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 clm viewer test')),
            encoded
        );
    }

    @IsTest
    static void getPdfBase64_returnsEncodedContent() {
        ContentVersion version = new ContentVersion(
            Title = 'clm-test.pdf',
            PathOnClient = 'clm-test.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 clm viewer test'),
            IsMajorVersion = true
        );
        insert version;

        version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        Test.startTest();
        String encoded = ClmPdfViewerController.getPdfBase64(version.ContentDocumentId);
        Test.stopTest();

        System.assertNotEquals(null, encoded);
        System.assert(
            Blob.valueOf('%PDF-1.4 clm viewer test').size() > 0,
            'Expected source PDF content to exist.'
        );
        System.assertEquals(
            EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 clm viewer test')),
            encoded
        );
    }

    @IsTest
    static void getPdfBase64_rejectsMissingDocument() {
        Boolean threw = false;
        try {
            ClmPdfViewerController.getPdfBase64ForPlayer(null);
        } catch (AuraHandledException ex) {
            threw = true;
            System.assertNotEquals(null, ex.getMessage());
        }
        System.assertEquals(true, threw, 'Expected missing document validation.');
    }

    @IsTest
    static void resolveContentDocumentId_mapsVersionToDocument() {
        ContentVersion version = new ContentVersion(
            Title = 'clm-resolve.pdf',
            PathOnClient = 'clm-resolve.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 resolve test'),
            IsMajorVersion = true
        );
        insert version;

        version = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        Test.startTest();
        String resolved = ClmPdfViewerController.resolveContentDocumentId(String.valueOf(version.Id));
        Test.stopTest();

        System.assertEquals(String.valueOf(version.ContentDocumentId), resolved);
    }

    @IsTest
    static void getPdfBase64ForPlayer_acceptsContentVersionId() {
        ContentVersion version = new ContentVersion(
            Title = 'clm-version-id.pdf',
            PathOnClient = 'clm-version-id.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 clm version id test'),
            IsMajorVersion = true
        );
        insert version;

        Test.startTest();
        String encoded = ClmPdfViewerController.getPdfBase64ForPlayer(String.valueOf(version.Id));
        Test.stopTest();

        System.assertEquals(
            EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 clm version id test')),
            encoded
        );
    }
}