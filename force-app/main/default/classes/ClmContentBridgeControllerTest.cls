@IsTest
private class ClmContentBridgeControllerTest {

    private static Blob zipLikeBlob(String suffix) {
        return EncodingUtil.convertFromHex(
            '504B0304' + EncodingUtil.convertToHex(Blob.valueOf(suffix))
        );
    }

    @IsTest
    static void splitBase64Chunks_roundTripsContent() {
        Blob payload = Blob.valueOf('0123456789ABCDEFGHIJ');

        Test.startTest();
        List<String> chunks = ClmContentBridgeController.splitBase64Chunks(payload);
        Test.stopTest();

        System.assertEquals(1, chunks.size());
        System.assertEquals(EncodingUtil.base64Encode(payload), chunks[0]);
    }

    @IsTest
    static void loadPresentationBlobFromVersionTable_returnsLatestVersion() {
        ContentVersion version = new ContentVersion(
            Title = 'bridge.zip',
            PathOnClient = 'bridge.zip',
            VersionData = Blob.valueOf('PK bridge zip'),
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
        Blob body = ClmContentBridgeController.loadPresentationBlobFromVersionTable(
            version.ContentDocumentId,
            version.Id
        );
        Test.stopTest();

        System.assertEquals(
            EncodingUtil.base64Encode(Blob.valueOf('PK bridge zip')),
            EncodingUtil.base64Encode(body)
        );
    }

    @IsTest
    static void looksLikeLoginHtml_detectsHtmlResponses() {
        System.assertEquals(
            true,
            ClmContentBridgeController.looksLikeLoginHtml(Blob.valueOf('<!DOCTYPE html><html'))
        );
        System.assertEquals(
            false,
            ClmContentBridgeController.looksLikeLoginHtml(zipLikeBlob('zip'))
        );
    }

    @IsTest
    static void controller_loadsInsertedPresentation() {
        ContentVersion version = new ContentVersion(
            Title = 'bridge-page.zip',
            PathOnClient = 'bridge-page.zip',
            VersionData = zipLikeBlob('bridge-page'),
            IsMajorVersion = true
        );
        insert version;
        version = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        PageReference pageRef = Page.ClmContentBridge;
        pageRef.getParameters().put('docId', version.ContentDocumentId);
        pageRef.getParameters().put('versionId', version.Id);
        pageRef.getParameters().put('requestId', 'req_bridge_ok');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        ClmContentBridgeController controller = new ClmContentBridgeController();
        Test.stopTest();

        System.assertEquals(false, controller.getHasError());
        System.assertEquals(zipLikeBlob('bridge-page').size(), controller.totalBytes);
        System.assertNotEquals(0, controller.base64Chunks.size());
    }

    @IsTest
    static void controller_surfacesMissingFileError() {
        PageReference pageRef = Page.ClmContentBridge;
        pageRef.getParameters().put('docId', '069000000000000AAA');
        pageRef.getParameters().put('requestId', 'req_test');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        ClmContentBridgeController controller = new ClmContentBridgeController();
        Test.stopTest();

        System.assertEquals(true, controller.getHasError());
        System.assertNotEquals(null, controller.errorMessage);
    }
}