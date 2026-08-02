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
            System.assert(ex.getMessage().contains('required'));
        }
        System.assertEquals(true, threw, 'Expected missing document validation.');
    }
}
