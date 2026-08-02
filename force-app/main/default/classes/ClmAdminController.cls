public with sharing class ClmAdminController {

    public class PresentationRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String formatType;
        @AuraEnabled public String productName;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Id productId;
        @AuraEnabled public String products;
        @AuraEnabled public Datetime lastUpdated;
        @AuraEnabled public Integer slideCount;
        @AuraEnabled public String territoryIdsJson;
        @AuraEnabled public Boolean allowUnaligned;
    }

    public class SequenceInput {
        @AuraEnabled public Id id;
        @AuraEnabled public Integer sequenceOrder;
        @AuraEnabled public String sequenceName;
        @AuraEnabled public String fileName;
        @AuraEnabled public String productNames;
        @AuraEnabled public String messageNames;
        @AuraEnabled public Boolean isMandatory;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public String htmlEntryPoint;
        @AuraEnabled public String slideImageUrl;
        @AuraEnabled public String thumbnailContentVersionId;
    }

    public class PresentationFinalizeInput {
        @AuraEnabled public Id presentationId;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String formatType;
        @AuraEnabled public Id productId;
        @AuraEnabled public String products;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String playerGesture;
        @AuraEnabled public String pinchZoom;
        @AuraEnabled public String doubleTapZoom;
        @AuraEnabled public String tags;
        @AuraEnabled public String publicContentUrl;
        @AuraEnabled public Boolean allowEmail;
        @AuraEnabled public String territoryIdsJson;
        @AuraEnabled public Boolean allowUnaligned;
    }

    public class TerritoryNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id parentId;
        @AuraEnabled public Boolean hasChildren;
    }

    public class TerritoryProductAlignment {
        @AuraEnabled public String territoryId;
        @AuraEnabled public Boolean hasAlignedProducts;
        @AuraEnabled public String alignedProductNames;
        @AuraEnabled public Integer alignedProductCount;
    }

    public class RatingLayoutRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Integer accountCount;
        @AuraEnabled public Integer territoryCount;
        @AuraEnabled public Integer productCount;
        @AuraEnabled public Integer toolsCount;
        @AuraEnabled public Integer teamCount;
        @AuraEnabled public String fieldsJson;
    }

    public class RatingFieldCatalogEntry {
        @AuraEnabled public String sectionKey;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String label;
        @AuraEnabled public String dataType;
        @AuraEnabled public String widget;
        @AuraEnabled public Boolean readOnly;
        @AuraEnabled public List<Map<String, String>> options;
    }

    public class UploadResult {
        @AuraEnabled public Id presentationId;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public Integer pageCount;
        @AuraEnabled public List<SequenceInput> sequences;
    }

    public class SequenceImageInput {
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public String base64Png;
        @AuraEnabled public String fileName;
    }

    @AuraEnabled(cacheable=true)
    public static List<PresentationRow> getPresentations(String statusFilter) {
        String soql = 'SELECT Id, Name, Status__c, Format__c, Product__c, Product__r.Name, Product__r.Product_Image_URL__c, Products__c, Slide_Count__c, ' +
            'Territory_Ids__c, Allow_Unaligned__c, LastModifiedDate FROM CLM_Presentation__c';
        if (String.isNotBlank(statusFilter) && statusFilter != 'All') {
            soql += ' WHERE Status__c = :statusFilter';
        }
        soql += ' WITH USER_MODE ORDER BY LastModifiedDate DESC LIMIT 200';

        List<PresentationRow> rows = new List<PresentationRow>();
        for (CLM_Presentation__c pres : Database.query(soql)) {
            PresentationRow row = new PresentationRow();
            row.id = pres.Id;
            row.name = pres.Name;
            row.status = pres.Status__c;
            row.formatType = pres.Format__c;
            row.productName = pres.Product__r?.Name;
            row.imageUrl = pres.Product__r?.Product_Image_URL__c;
            row.productId = pres.Product__c;
            row.products = pres.Products__c;
            row.lastUpdated = pres.LastModifiedDate;
            row.slideCount = pres.Slide_Count__c != null ? Integer.valueOf(pres.Slide_Count__c) : 0;
            row.territoryIdsJson = pres.Territory_Ids__c;
            row.allowUnaligned = pres.Allow_Unaligned__c == true;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static UploadResult createPresentationDraft(
        String fileName,
        String formatType,
        String base64Data,
        Integer pageCount
    ) {
        if (String.isBlank(fileName) || String.isBlank(base64Data)) {
            throw new AuraHandledException('File name and content are required.');
        }

        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Name = fileName,
            Status__c = 'Draft',
            Format__c = String.isBlank(formatType) ? 'PDF' : formatType,
            Player_Gesture__c = 'Tap Bottom',
            Pinch_Zoom__c = 'Enabled',
            Double_Tap_Zoom__c = 'Enabled'
        );
        insert as user presentation;

        Blob fileBlob = EncodingUtil.base64Decode(base64Data);
        ContentVersion version = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName,
            VersionData = fileBlob,
            IsMajorVersion = true
        );
        insert as user version;

        version = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            WITH USER_MODE
            LIMIT 1
        ];

        Integer resolvedPageCount = resolvePageCount(formatType, fileBlob, pageCount);

        presentation.Content_Document_Id__c = version.ContentDocumentId;
        presentation.Slide_Count__c = resolvedPageCount;
        update as user presentation;

        ClmContentService.linkContentDocumentToPresentation(
            version.ContentDocumentId,
            presentation.Id
        );

        delete as user [
            SELECT Id
            FROM CLM_Sequence__c
            WHERE CLM_Presentation__c = :presentation.Id
            WITH USER_MODE
        ];

        List<SequenceInput> sequences = buildDefaultSequences(
            presentation.Id,
            fileName,
            formatType,
            resolvedPageCount
        );
        sequences = getSequences(presentation.Id);

        UploadResult result = new UploadResult();
        result.presentationId = presentation.Id;
        result.contentDocumentId = version.ContentDocumentId;
        result.contentVersionId = version.Id;
        result.pageCount = resolvedPageCount;
        result.sequences = sequences;
        return result;
    }

    @AuraEnabled
    public static List<SequenceInput> attachSlideImages(
        Id presentationId,
        List<SequenceImageInput> images
    ) {
        if (presentationId == null || images == null || images.isEmpty()) {
            return getSequences(presentationId);
        }

        Map<Integer, CLM_Sequence__c> sequencesByPage = new Map<Integer, CLM_Sequence__c>();
        for (CLM_Sequence__c seq : [
            SELECT Id, Sequence_Order__c, Page_Number__c
            FROM CLM_Sequence__c
            WHERE CLM_Presentation__c = :presentationId
            WITH USER_MODE
            ORDER BY Sequence_Order__c ASC
        ]) {
            Integer pageNumber = seq.Page_Number__c != null
                ? Integer.valueOf(seq.Page_Number__c)
                : Integer.valueOf(seq.Sequence_Order__c);
            sequencesByPage.put(pageNumber, seq);
        }

        List<CLM_Sequence__c> updates = new List<CLM_Sequence__c>();
        for (SequenceImageInput image : images) {
            if (image == null || image.pageNumber == null || String.isBlank(image.base64Png)) {
                continue;
            }
            CLM_Sequence__c sequence = sequencesByPage.get(image.pageNumber);
            if (sequence == null) {
                continue;
            }

            String imageName = String.isNotBlank(image.fileName)
                ? image.fileName
                : 'slide-' + image.pageNumber + '.png';
            ContentVersion imageVersion = new ContentVersion(
                Title = imageName,
                PathOnClient = imageName,
                VersionData = EncodingUtil.base64Decode(image.base64Png),
                IsMajorVersion = true
            );
            insert as user imageVersion;

            imageVersion = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :imageVersion.Id
                WITH USER_MODE
                LIMIT 1
            ];

            sequence.Thumbnail_Content_Version_Id__c = imageVersion.Id;
            sequence.Slide_Image_URL__c = ClmContentService.buildSlideImageUrl(imageVersion.Id);
            updates.add(sequence);
            ClmContentService.linkContentDocumentToPresentation(
                imageVersion.ContentDocumentId,
                presentationId
            );
        }

        if (!updates.isEmpty()) {
            update as user updates;
        }
        return getSequences(presentationId);
    }

    private static Integer resolvePageCount(String formatType, Blob fileBlob, Integer pageCount) {
        if (pageCount != null && pageCount > 0) {
            return pageCount;
        }
        if ('PDF'.equalsIgnoreCase(formatType)) {
            return ClmPdfParser.getPageCount(fileBlob);
        }
        return 1;
    }

    @AuraEnabled
    public static List<SequenceInput> generateSequencesFromPageCount(
        Id presentationId,
        String fileName,
        Integer pageCount
    ) {
        if (presentationId == null) {
            throw new AuraHandledException('Presentation Id is required.');
        }
        Integer count = pageCount != null && pageCount > 0 ? pageCount : 1;
        delete as user [
            SELECT Id
            FROM CLM_Sequence__c
            WHERE CLM_Presentation__c = :presentationId
            WITH USER_MODE
        ];
        List<SequenceInput> sequences = buildDefaultSequences(presentationId, fileName, 'PDF', count);
        upsertSequences(presentationId, sequences);
        update as user new CLM_Presentation__c(
            Id = presentationId,
            Slide_Count__c = count
        );
        return getSequences(presentationId);
    }

    @AuraEnabled
    public static List<SequenceInput> getSequences(Id presentationId) {
        List<SequenceInput> results = new List<SequenceInput>();
        if (presentationId == null) {
            return results;
        }
        for (CLM_Sequence__c seq : [
            SELECT Id, Sequence_Order__c, Sequence_Name__c, File_Name__c, Product_Names__c,
                   Message_Names__c, Is_Mandatory__c, Page_Number__c, HTML_Entry_Point__c,
                   Slide_Image_URL__c, Thumbnail_Content_Version_Id__c
            FROM CLM_Sequence__c
            WHERE CLM_Presentation__c = :presentationId
            WITH USER_MODE
            ORDER BY Sequence_Order__c ASC NULLS LAST
        ]) {
            SequenceInput input = new SequenceInput();
            input.id = seq.Id;
            input.sequenceOrder = seq.Sequence_Order__c != null ? Integer.valueOf(seq.Sequence_Order__c) : null;
            input.sequenceName = seq.Sequence_Name__c;
            input.fileName = seq.File_Name__c;
            input.productNames = seq.Product_Names__c;
            input.messageNames = seq.Message_Names__c;
            input.isMandatory = seq.Is_Mandatory__c == true;
            input.pageNumber = seq.Page_Number__c != null ? Integer.valueOf(seq.Page_Number__c) : null;
            input.htmlEntryPoint = seq.HTML_Entry_Point__c;
            input.slideImageUrl = seq.Slide_Image_URL__c;
            input.thumbnailContentVersionId = seq.Thumbnail_Content_Version_Id__c;
            results.add(input);
        }
        return results;
    }

    @AuraEnabled
    public static List<SequenceInput> saveSequences(Id presentationId, List<SequenceInput> sequences) {
        if (presentationId == null) {
            throw new AuraHandledException('Presentation Id is required.');
        }
        upsertSequences(presentationId, sequences);
        Integer count = sequences != null ? sequences.size() : 0;
        update as user new CLM_Presentation__c(
            Id = presentationId,
            Slide_Count__c = count
        );
        return getSequences(presentationId);
    }

    @AuraEnabled(cacheable=true)
    public static PresentationRow getPresentationDraft(Id presentationId) {
        if (presentationId == null) {
            return null;
        }
        return getPresentationRow(presentationId);
    }

    @AuraEnabled
    public static PresentationRow finalizePresentation(
        Id presentationId,
        String name,
        String status,
        String formatType,
        Id productId,
        String products,
        Date startDate,
        Date endDate,
        String playerGesture,
        String pinchZoom,
        String doubleTapZoom,
        String tags,
        String publicContentUrl,
        Boolean allowEmail,
        String territoryIdsJson,
        Boolean allowUnaligned
    ) {
        if (presentationId == null) {
            throw new AuraHandledException('Presentation Id is required.');
        }
        if (String.isBlank(name)) {
            throw new AuraHandledException('Presentation name is required.');
        }

        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Id = presentationId,
            Name = name,
            Status__c = String.isBlank(status) ? 'Available' : status,
            Format__c = formatType,
            Product__c = productId,
            Products__c = products,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Player_Gesture__c = playerGesture,
            Pinch_Zoom__c = pinchZoom,
            Double_Tap_Zoom__c = doubleTapZoom,
            Tags__c = tags,
            Public_Content_URL__c = publicContentUrl,
            Allow_Email__c = allowEmail == true,
            Territory_Ids__c = territoryIdsJson,
            Allow_Unaligned__c = allowUnaligned == true
        );
        update as user presentation;
        return getPresentationRow(presentation.Id);
    }

    @AuraEnabled
    public static void deactivatePresentation(Id presentationId) {
        if (presentationId == null) {
            throw new AuraHandledException('Presentation Id is required.');
        }
        update as user new CLM_Presentation__c(
            Id = presentationId,
            Status__c = 'Deactivated'
        );
    }

    @AuraEnabled
    public static void saveTerritoryTargeting(Id presentationId, String territoryIdsJson, Boolean allowUnaligned) {
        if (presentationId == null) {
            throw new AuraHandledException('Presentation Id is required.');
        }
        update as user new CLM_Presentation__c(
            Id = presentationId,
            Territory_Ids__c = territoryIdsJson,
            Allow_Unaligned__c = allowUnaligned == true
        );
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryNode> getTerritories() {
        List<TerritoryNode> nodes = new List<TerritoryNode>();
        Map<Id, Integer> childCounts = new Map<Id, Integer>();
        String pharmaPrefix = TerritoryModuleCleanup.PHARMA_EXTERNAL_ID_PREFIX + '%';
        for (AggregateResult agg : [
            SELECT ParentTerritory2Id parentId, COUNT(Id) childCount
            FROM Territory2
            WHERE ParentTerritory2Id != NULL
                AND External_ID__c LIKE :pharmaPrefix
            WITH USER_MODE
            GROUP BY ParentTerritory2Id
        ]) {
            childCounts.put((Id) agg.get('parentId'), (Integer) agg.get('childCount'));
        }
        for (Territory2 territory : [
            SELECT Id, Name, ParentTerritory2Id
            FROM Territory2
            WHERE External_ID__c LIKE :pharmaPrefix
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 500
        ]) {
            TerritoryNode node = new TerritoryNode();
            node.id = territory.Id;
            node.name = territory.Name;
            node.parentId = territory.ParentTerritory2Id;
            node.hasChildren = childCounts.containsKey(territory.Id);
            nodes.add(node);
        }
        return nodes;
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryProductAlignment> getTerritoryProductAlignments(String productIdsJson) {
        Set<String> productIdStrings = new Set<String>();
        if (String.isNotBlank(productIdsJson)) {
            try {
                List<Object> rawIds = (List<Object>) JSON.deserializeUntyped(productIdsJson);
                for (Object rawId : rawIds) {
                    if (rawId != null) {
                        productIdStrings.add(String.valueOf(rawId));
                    }
                }
            } catch (Exception ex) {
                productIdStrings = new Set<String>();
            }
        }

        Map<String, String> productNamesById = new Map<String, String>();
        if (!productIdStrings.isEmpty()) {
            for (Product2 product : [
                SELECT Id, Name
                FROM Product2
                WHERE Id IN :productIdStrings
                WITH USER_MODE
            ]) {
                productNamesById.put(String.valueOf(product.Id), product.Name);
            }
        }

        Map<String, Set<String>> namesByTerritory = new Map<String, Set<String>>();
        if (!productIdStrings.isEmpty()) {
            for (Product_Territory_Alignment__c alignment : [
                SELECT Territory2_Id__c, Product2_Id__c
                FROM Product_Territory_Alignment__c
                WHERE Product2_Id__c IN :productIdStrings
                    AND Is_Active__c = TRUE
                    AND Territory2_Id__c != NULL
                WITH USER_MODE
            ]) {
                String territoryId = alignment.Territory2_Id__c;
                String productName = productNamesById.get(alignment.Product2_Id__c);
                if (String.isBlank(territoryId) || String.isBlank(productName)) {
                    continue;
                }
                if (!namesByTerritory.containsKey(territoryId)) {
                    namesByTerritory.put(territoryId, new Set<String>());
                }
                namesByTerritory.get(territoryId).add(productName);
            }
        }

        List<TerritoryProductAlignment> results = new List<TerritoryProductAlignment>();
        String pharmaPrefix = TerritoryModuleCleanup.PHARMA_EXTERNAL_ID_PREFIX + '%';
        for (Territory2 territory : [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c LIKE :pharmaPrefix
            WITH USER_MODE
            LIMIT 500
        ]) {
            String territoryKey = String.valueOf(territory.Id);
            Set<String> alignedNames = namesByTerritory.get(territoryKey);
            TerritoryProductAlignment row = new TerritoryProductAlignment();
            row.territoryId = territoryKey;
            row.hasAlignedProducts = alignedNames != null && !alignedNames.isEmpty();
            if (row.hasAlignedProducts) {
                List<String> sortedNames = new List<String>(alignedNames);
                sortedNames.sort();
                row.alignedProductNames = String.join(sortedNames, ', ');
                row.alignedProductCount = sortedNames.size();
            } else {
                row.alignedProductNames = '';
                row.alignedProductCount = 0;
            }
            results.add(row);
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<RatingLayoutRow> getRatingLayouts() {
        List<RatingLayoutRow> rows = new List<RatingLayoutRow>();
        for (CLM_Rating_Layout__c layout : [
            SELECT Id, Name, Status__c, Fields_JSON__c, Account_Count__c, Territory_Count__c,
                   Product_Count__c, Tools_Count__c, Team_Count__c
            FROM CLM_Rating_Layout__c
            WITH USER_MODE
            ORDER BY Name ASC
        ]) {
            rows.add(mapRatingLayout(layout));
        }
        return rows;
    }

    @AuraEnabled
    public static RatingLayoutRow saveRatingLayout(RatingLayoutRow layout) {
        if (layout == null || String.isBlank(layout.name)) {
            throw new AuraHandledException('Layout name is required.');
        }
        String normalizedJson = ClmRatingLayoutService.normalizeFieldsJson(layout.fieldsJson);
        ClmRatingLayoutService.SectionCounts counts = ClmRatingLayoutService.countSections(normalizedJson);
        CLM_Rating_Layout__c record = new CLM_Rating_Layout__c(
            Id = layout.id,
            Name = layout.name,
            Status__c = String.isBlank(layout.status) ? 'Draft' : layout.status,
            Fields_JSON__c = normalizedJson,
            Account_Count__c = counts.accountCount,
            Territory_Count__c = counts.territoryCount,
            Product_Count__c = counts.productCount,
            Tools_Count__c = layout.toolsCount != null ? layout.toolsCount : 0,
            Team_Count__c = layout.teamCount != null ? layout.teamCount : 0
        );
        upsert as user record;
        return mapRatingLayout([
            SELECT Id, Name, Status__c, Fields_JSON__c, Account_Count__c, Territory_Count__c,
                   Product_Count__c, Tools_Count__c, Team_Count__c
            FROM CLM_Rating_Layout__c
            WHERE Id = :record.Id
            WITH USER_MODE
            LIMIT 1
        ]);
    }

    @AuraEnabled(cacheable=true)
    public static List<RatingFieldCatalogEntry> getRatingFieldCatalog() {
        List<RatingFieldCatalogEntry> rows = new List<RatingFieldCatalogEntry>();
        for (ClmRatingLayoutService.CatalogField field : ClmRatingLayoutService.getFieldCatalog()) {
            RatingFieldCatalogEntry row = new RatingFieldCatalogEntry();
            row.sectionKey = field.sectionKey;
            row.objectApiName = field.objectApiName;
            row.fieldApiName = field.fieldApiName;
            row.label = field.label;
            row.dataType = field.dataType;
            row.widget = field.widget;
            row.readOnly = field.readOnly;
            row.options = field.options;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static String getRatingLayoutPreviewSample() {
        return ClmRatingLayoutService.getPreviewSampleValuesJson();
    }

    @AuraEnabled
    public static void deployRatingLayout(Id layoutId) {
        if (layoutId == null) {
            throw new AuraHandledException('Layout Id is required.');
        }
        CLM_Rating_Layout__c targetLayout = [
            SELECT Id, Fields_JSON__c
            FROM CLM_Rating_Layout__c
            WHERE Id = :layoutId
            WITH USER_MODE
            LIMIT 1
        ];
        String targetVariant = ClmRatingLayoutService.resolveLayoutVariant(targetLayout.Fields_JSON__c);

        List<CLM_Rating_Layout__c> toDemote = new List<CLM_Rating_Layout__c>();
        for (CLM_Rating_Layout__c layout : [
            SELECT Id, Fields_JSON__c
            FROM CLM_Rating_Layout__c
            WHERE Status__c = 'Deployed' AND Id != :layoutId
            WITH USER_MODE
        ]) {
            String layoutVariant = ClmRatingLayoutService.resolveLayoutVariant(layout.Fields_JSON__c);
            if (layoutVariant == targetVariant) {
                layout.Status__c = 'Draft';
                toDemote.add(layout);
            }
        }
        if (!toDemote.isEmpty()) {
            update as user toDemote;
        }
        update as user new CLM_Rating_Layout__c(
            Id = layoutId,
            Status__c = 'Deployed'
        );
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getProductOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (Product2 product : [
            SELECT Id, Name
            FROM Product2
            WHERE IsActive = TRUE
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 200
        ]) {
            options.add(new Map<String, String>{
                'label' => product.Name,
                'value' => product.Id
            });
        }
        return options;
    }

    private static void upsertSequences(Id presentationId, List<SequenceInput> sequences) {
        if (sequences == null) {
            sequences = new List<SequenceInput>();
        }

        Set<Id> payloadIds = new Set<Id>();
        for (SequenceInput input : sequences) {
            if (input != null && input.id != null) {
                payloadIds.add(input.id);
            }
        }

        List<CLM_Sequence__c> orphans = new List<CLM_Sequence__c>();
        for (CLM_Sequence__c existing : [
            SELECT Id
            FROM CLM_Sequence__c
            WHERE CLM_Presentation__c = :presentationId
            WITH USER_MODE
        ]) {
            if (!payloadIds.contains(existing.Id)) {
                orphans.add(existing);
            }
        }
        if (!orphans.isEmpty()) {
            delete as user orphans;
        }

        List<CLM_Sequence__c> rows = new List<CLM_Sequence__c>();
        Integer order = 1;
        for (SequenceInput input : sequences) {
            if (input == null) {
                continue;
            }
            Integer resolvedOrder = input.sequenceOrder != null ? input.sequenceOrder : order;
            Integer resolvedPage = input.pageNumber != null ? input.pageNumber : resolvedOrder;
            String resolvedName = String.isNotBlank(input.sequenceName)
                ? input.sequenceName
                : 'Slide ' + resolvedOrder;
            rows.add(new CLM_Sequence__c(
                Id = input.id,
                CLM_Presentation__c = presentationId,
                Sequence_Order__c = resolvedOrder,
                Sequence_Name__c = resolvedName,
                Name = resolvedName,
                File_Name__c = input.fileName,
                Product_Names__c = input.productNames,
                Message_Names__c = input.messageNames,
                Is_Mandatory__c = input.isMandatory == true,
                Page_Number__c = resolvedPage,
                HTML_Entry_Point__c = input.htmlEntryPoint,
                Slide_Image_URL__c = input.slideImageUrl,
                Thumbnail_Content_Version_Id__c = input.thumbnailContentVersionId
            ));
            order++;
        }
        if (!rows.isEmpty()) {
            upsert as user rows;
        }
    }

    private static List<SequenceInput> buildDefaultSequences(
        Id presentationId,
        String fileName,
        String formatType,
        Integer count
    ) {
        List<SequenceInput> sequences = new List<SequenceInput>();
        List<CLM_Sequence__c> rows = new List<CLM_Sequence__c>();
        for (Integer i = 1; i <= count; i++) {
            CLM_Sequence__c row = new CLM_Sequence__c(
                CLM_Presentation__c = presentationId,
                Sequence_Order__c = i,
                Sequence_Name__c = 'Slide ' + i,
                Name = 'Slide ' + i,
                File_Name__c = fileName,
                Page_Number__c = i,
                HTML_Entry_Point__c = formatType == 'HTML' || formatType == 'ZIP' ? 'index.html' : null
            );
            rows.add(row);
        }
        if (!rows.isEmpty()) {
            insert as user rows;
        }
        for (CLM_Sequence__c row : rows) {
            SequenceInput input = new SequenceInput();
            input.id = row.Id;
            input.sequenceOrder = Integer.valueOf(row.Sequence_Order__c);
            input.sequenceName = row.Sequence_Name__c;
            input.fileName = row.File_Name__c;
            input.pageNumber = Integer.valueOf(row.Page_Number__c);
            input.htmlEntryPoint = row.HTML_Entry_Point__c;
            sequences.add(input);
        }
        return sequences;
    }

    private static PresentationRow getPresentationRow(Id presentationId) {
        CLM_Presentation__c pres = [
            SELECT Id, Name, Status__c, Format__c, Product__c, Product__r.Name, Product__r.Product_Image_URL__c,
                   Products__c, Slide_Count__c, Territory_Ids__c, Allow_Unaligned__c, LastModifiedDate
            FROM CLM_Presentation__c
            WHERE Id = :presentationId
            WITH USER_MODE
            LIMIT 1
        ];
        PresentationRow row = new PresentationRow();
        row.id = pres.Id;
        row.name = pres.Name;
        row.status = pres.Status__c;
        row.formatType = pres.Format__c;
        row.productName = pres.Product__r?.Name;
        row.imageUrl = pres.Product__r?.Product_Image_URL__c;
        row.productId = pres.Product__c;
        row.products = pres.Products__c;
        row.slideCount = pres.Slide_Count__c != null ? Integer.valueOf(pres.Slide_Count__c) : 0;
        row.territoryIdsJson = pres.Territory_Ids__c;
        row.allowUnaligned = pres.Allow_Unaligned__c == true;
        row.lastUpdated = pres.LastModifiedDate;
        return row;
    }

    private static RatingLayoutRow mapRatingLayout(CLM_Rating_Layout__c layout) {
        RatingLayoutRow row = new RatingLayoutRow();
        row.id = layout.Id;
        row.name = layout.Name;
        row.status = layout.Status__c;
        row.fieldsJson = layout.Fields_JSON__c;
        row.accountCount = layout.Account_Count__c != null ? Integer.valueOf(layout.Account_Count__c) : 0;
        row.territoryCount = layout.Territory_Count__c != null ? Integer.valueOf(layout.Territory_Count__c) : 0;
        row.productCount = layout.Product_Count__c != null ? Integer.valueOf(layout.Product_Count__c) : 0;
        row.toolsCount = layout.Tools_Count__c != null ? Integer.valueOf(layout.Tools_Count__c) : 0;
        row.teamCount = layout.Team_Count__c != null ? Integer.valueOf(layout.Team_Count__c) : 0;
        return row;
    }
}
