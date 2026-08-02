@IsTest
private class ClmAdminControllerTest {

    @IsTest
    static void createPresentationDraft_andFinalize() {
        String base64Pdf = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 test'));

        Test.startTest();
        ClmAdminController.UploadResult upload = ClmAdminController.createPresentationDraft(
            'demo.pdf',
            'PDF',
            base64Pdf,
            3
        );
        List<ClmAdminController.SequenceInput> sequences = ClmAdminController.generateSequencesFromPageCount(
            upload.presentationId,
            'demo.pdf',
            3
        );

        ClmAdminController.PresentationRow row = ClmAdminController.finalizePresentation(
            upload.presentationId,
            'Allergy',
            'Available',
            'PDF',
            null,
            null,
            null,
            null,
            'Tap Bottom',
            'Enabled',
            'Enabled',
            null,
            null,
            false,
            '[]',
            true
        );
        Test.stopTest();

        System.assertEquals('Allergy', row.name);
        System.assertEquals(3, sequences.size());
        System.assertEquals(3, row.slideCount);
    }

    @IsTest
    static void attachSlideImages_setsThumbnailOnFirstSlide() {
        String base64Pdf = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 test'));
        String base64Png = EncodingUtil.base64Encode(Blob.valueOf('89504e470d0a1a0a'));

        ClmAdminController.UploadResult upload = ClmAdminController.createPresentationDraft(
            'demo.pdf',
            'PDF',
            base64Pdf,
            2
        );

        ClmAdminController.SequenceImageInput image = new ClmAdminController.SequenceImageInput();
        image.pageNumber = 1;
        image.base64Png = base64Png;
        image.fileName = 'slide-1.png';

        Test.startTest();
        List<ClmAdminController.SequenceInput> sequences = ClmAdminController.attachSlideImages(
            upload.presentationId,
            new List<ClmAdminController.SequenceImageInput>{ image }
        );
        Test.stopTest();

        System.assertEquals(2, sequences.size());
        System.assertNotEquals(null, sequences[0].thumbnailContentVersionId);
        System.assertNotEquals(null, sequences[0].slideImageUrl);
    }

    @IsTest
    static void saveSequences_updatesSlideCount() {
        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Name = 'Draft Pres',
            Status__c = 'Draft',
            Format__c = 'HTML'
        );
        insert presentation;

        ClmAdminController.SequenceInput seq = new ClmAdminController.SequenceInput();
        seq.sequenceOrder = 1;
        seq.sequenceName = 'Home';
        seq.fileName = 'index.html';
        seq.messageNames = 'EFFICACY';

        Test.startTest();
        List<ClmAdminController.SequenceInput> saved = ClmAdminController.saveSequences(
            presentation.Id,
            new List<ClmAdminController.SequenceInput>{ seq }
        );
        Test.stopTest();

        CLM_Presentation__c stored = [
            SELECT Slide_Count__c
            FROM CLM_Presentation__c
            WHERE Id = :presentation.Id
        ];
        System.assertEquals(1, stored.Slide_Count__c);
        System.assertEquals(1, saved.size());
        System.assertNotEquals(null, saved[0].id);
    }

    @IsTest
    static void saveSequences_roundTripsSlideMetadata() {
        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Name = 'Metadata Pres',
            Status__c = 'Draft',
            Format__c = 'PDF'
        );
        insert presentation;

        ClmAdminController.SequenceInput seq = new ClmAdminController.SequenceInput();
        seq.sequenceOrder = 1;
        seq.sequenceName = 'Intro';
        seq.fileName = 'deck.pdf';
        seq.pageNumber = 1;
        seq.productNames = 'Empacoza';
        seq.messageNames = 'EFFICACY; SAFETY';
        seq.isMandatory = true;

        Test.startTest();
        List<ClmAdminController.SequenceInput> saved = ClmAdminController.saveSequences(
            presentation.Id,
            new List<ClmAdminController.SequenceInput>{ seq }
        );
        Test.stopTest();

        System.assertEquals(1, saved.size());
        System.assertEquals('Empacoza', saved[0].productNames);
        System.assertEquals('EFFICACY; SAFETY', saved[0].messageNames);
        System.assertEquals(true, saved[0].isMandatory);

        CLM_Sequence__c stored = [
            SELECT Product_Names__c, Message_Names__c, Is_Mandatory__c
            FROM CLM_Sequence__c
            WHERE CLM_Presentation__c = :presentation.Id
            LIMIT 1
        ];
        System.assertEquals('Empacoza', stored.Product_Names__c);
        System.assertEquals('EFFICACY; SAFETY', stored.Message_Names__c);
        System.assertEquals(true, stored.Is_Mandatory__c);
    }

    @IsTest
    static void saveSequences_withoutIdsDoesNotDuplicateExistingRows() {
        String base64Pdf = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 test'));

        ClmAdminController.UploadResult upload = ClmAdminController.createPresentationDraft(
            'demo.pdf',
            'PDF',
            base64Pdf,
            3
        );
        System.assertEquals(3, [
            SELECT COUNT()
            FROM CLM_Sequence__c
            WHERE CLM_Presentation__c = :upload.presentationId
        ]);

        List<ClmAdminController.SequenceInput> payload = new List<ClmAdminController.SequenceInput>();
        for (Integer i = 1; i <= 3; i++) {
            ClmAdminController.SequenceInput seq = new ClmAdminController.SequenceInput();
            seq.sequenceOrder = i;
            seq.sequenceName = 'Slide ' + i;
            seq.fileName = 'demo.pdf';
            seq.pageNumber = i;
            seq.productNames = 'Product ' + i;
            payload.add(seq);
        }

        Test.startTest();
        ClmAdminController.saveSequences(upload.presentationId, payload);
        ClmAdminController.saveSequences(upload.presentationId, payload);
        Test.stopTest();

        System.assertEquals(3, [
            SELECT COUNT()
            FROM CLM_Sequence__c
            WHERE CLM_Presentation__c = :upload.presentationId
        ]);
    }

    @IsTest
    static void saveSequences_deletesSequencesRemovedFromPayload() {
        String base64Pdf = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 test'));

        ClmAdminController.UploadResult upload = ClmAdminController.createPresentationDraft(
            'demo.pdf',
            'PDF',
            base64Pdf,
            3
        );
        List<ClmAdminController.SequenceInput> existing = ClmAdminController.getSequences(upload.presentationId);
        System.assertEquals(3, existing.size());

        Test.startTest();
        ClmAdminController.saveSequences(
            upload.presentationId,
            new List<ClmAdminController.SequenceInput>{ existing[0], existing[1] }
        );
        Test.stopTest();

        System.assertEquals(2, [
            SELECT COUNT()
            FROM CLM_Sequence__c
            WHERE CLM_Presentation__c = :upload.presentationId
        ]);
        CLM_Presentation__c presentation = [
            SELECT Slide_Count__c
            FROM CLM_Presentation__c
            WHERE Id = :upload.presentationId
        ];
        System.assertEquals(2, presentation.Slide_Count__c);
    }

    @IsTest
    static void ratingLayout_saveAndDeploy() {
        ClmAdminController.RatingLayoutRow layout = new ClmAdminController.RatingLayoutRow();
        layout.name = 'Phoenix Ratings';
        layout.status = 'Draft';
        layout.fieldsJson = '[{"key":"speaker","label":"Speaker","type":"toggle"}]';

        Test.startTest();
        ClmAdminController.RatingLayoutRow saved = ClmAdminController.saveRatingLayout(layout);
        List<ClmAdminController.RatingFieldCatalogEntry> catalog = ClmAdminController.getRatingFieldCatalog();
        ClmAdminController.deployRatingLayout(saved.id);
        Test.stopTest();

        CLM_Rating_Layout__c stored = [
            SELECT Status__c, Territory_Count__c, Fields_JSON__c
            FROM CLM_Rating_Layout__c
            WHERE Id = :saved.id
        ];
        System.assertEquals('Deployed', stored.Status__c);
        System.assert(stored.Fields_JSON__c.contains('"version"'));
        System.assert(!catalog.isEmpty());
    }

    @IsTest
    static void getPresentationDraft_returnsStoredProducts() {
        Product2 product = new Product2(Name = 'Empacoza', IsActive = true);
        insert product;

        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Name = 'Empacoza Deck',
            Status__c = 'Draft',
            Format__c = 'PDF',
            Product__c = product.Id,
            Products__c = '{"productIds":["' + product.Id + '"],"productNames":["Empacoza"]}'
        );
        insert presentation;

        Test.startTest();
        ClmAdminController.PresentationRow draft = ClmAdminController.getPresentationDraft(presentation.Id);
        Test.stopTest();

        System.assertEquals('Empacoza Deck', draft.name);
        System.assertEquals(product.Id, draft.productId);
        System.assert(draft.products.contains('Empacoza'));
    }

    @IsTest
    static void getTerritoryProductAlignments_returnsAlignedProductNames() {
        Product2 product = new Product2(Name = 'Empacoza Align Test', IsActive = true);
        insert product;

        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        Territory2Model model = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        if (types.isEmpty() || model == null) {
            return;
        }

        Territory2 territory = new Territory2(
            Name = 'CLM Align Test Territory',
            DeveloperName = 'CLM_Align_Test',
            Territory2ModelId = model.Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = 'TERR_CLM_ALIGN_TEST'
        );
        insert territory;

        insert new Product_Territory_Alignment__c(
            Product2_Id__c = String.valueOf(product.Id),
            Territory2_Id__c = String.valueOf(territory.Id),
            Is_Active__c = true,
            Effective_Start_Date__c = Date.today()
        );

        String productIdsJson = JSON.serialize(new List<Id>{ product.Id });

        Test.startTest();
        List<ClmAdminController.TerritoryProductAlignment> rows =
            ClmAdminController.getTerritoryProductAlignments(productIdsJson);
        Test.stopTest();

        Map<String, ClmAdminController.TerritoryProductAlignment> byTerritory = new Map<String, ClmAdminController.TerritoryProductAlignment>();
        for (ClmAdminController.TerritoryProductAlignment row : rows) {
            byTerritory.put(row.territoryId, row);
        }

        System.assertEquals(true, byTerritory.get(String.valueOf(territory.Id)).hasAlignedProducts);
        System.assert(byTerritory.get(String.valueOf(territory.Id)).alignedProductNames.contains('Empacoza'));
    }

    @IsTest
    static void deactivatePresentation_setsStatus() {
        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Name = 'To Deactivate',
            Status__c = 'Available',
            Format__c = 'PDF'
        );
        insert presentation;

        Test.startTest();
        ClmAdminController.deactivatePresentation(presentation.Id);
        Test.stopTest();

        CLM_Presentation__c stored = [SELECT Status__c FROM CLM_Presentation__c WHERE Id = :presentation.Id];
        System.assertEquals('Deactivated', stored.Status__c);
    }
}
