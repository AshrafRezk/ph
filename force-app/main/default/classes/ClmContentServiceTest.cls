@IsTest
private class ClmContentServiceTest {

    @IsTest
    static void linkContentDocumentToPresentation_createsViewerLink() {
        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Name = 'Content Link Test',
            Status__c = 'Draft',
            Format__c = 'PDF'
        );
        insert presentation;

        ContentVersion version = new ContentVersion(
            Title = 'link-test.pdf',
            PathOnClient = 'link-test.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'),
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
        ClmContentService.linkContentDocumentToPresentation(
            version.ContentDocumentId,
            presentation.Id
        );
        ClmContentService.linkContentDocumentToPresentation(
            version.ContentDocumentId,
            presentation.Id
        );
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id, ShareType
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :version.ContentDocumentId
              AND LinkedEntityId = :presentation.Id
        ];
        System.assertEquals(1, links.size(), 'Expected one presentation content link.');
        System.assertEquals('V', links[0].ShareType);
    }

    @IsTest
    static void buildDocumentDownloadUrl_returnsShepherdPath() {
        String docId = '069000000000001AAA';
        String url = ClmContentService.buildDocumentDownloadUrl(docId);
        System.assertEquals('/sfc/servlet.shepherd/document/download/' + docId, url);
        System.assertEquals(null, ClmContentService.buildDocumentDownloadUrl(null));
    }

    @IsTest
    static void buildContentUrl_usesRenditionNotDownload() {
        String versionId = '068000000000001AAA';
        String slideUrl = ClmContentService.buildSlideImageUrl(versionId);
        System.assert(slideUrl.contains('renditionDownload'), 'Slide URL should use rendition.');
        System.assert(slideUrl.contains('ORIGINAL_Png'), 'Slide URL should request PNG rendition.');
        System.assert(!slideUrl.contains('/download/'), 'Slide URL should not use download servlet.');

        String thumbUrl = ClmContentService.buildThumbnailUrl(versionId);
        System.assert(thumbUrl.contains('THUMB720BY480'), 'Thumbnail URL should use thumb rendition.');

        String normalized = ClmContentService.normalizeContentUrl(
            '/sfc/servlet.shepherd/version/download/' + versionId
        );
        System.assertEquals(slideUrl, normalized);

        String built = ClmContentService.buildContentUrl(versionId, null);
        System.assertEquals(thumbUrl, built);
    }
}
