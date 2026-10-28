@IsTest
private class PromoGridTransferServiceTest {
    @TestSetup
    static void setup() {
        insert new List<Product2>{
            new Product2(
                Name = 'Promo Transfer Product A',
                IsActive = true,
                ProductCode = 'PG_XFER_A',
                Sales_Line__c = 'PGXFER-LINE'
            ),
            new Product2(
                Name = 'Promo Transfer Product B',
                IsActive = true,
                ProductCode = 'PG_XFER_B',
                Sales_Line__c = 'PGXFER-LINE'
            ),
            new Product2(
                Name = 'Promo Transfer Product C',
                IsActive = true,
                ProductCode = 'PG_XFER_C',
                Sales_Line__c = 'PGXFER-LINE-2'
            )
        };
    }

    @IsTest
    static void export_includesLinesProductsAndEmptyClasses() {
        Territory2 line = getOrCreateLineTerritory('TERR_LINE_PGXFER', 'PGXFER-LINE');
        if (line == null) {
            return;
        }

        Test.startTest();
        PromoGridTransferService.ExportPayload blank = PromoGridTransferService.getPromoGridExport(false);
        PromoGridTransferService.ExportPayload withValues = PromoGridTransferService.getPromoGridExport(true);
        Test.stopTest();

        System.assertNotEquals(null, blank);
        System.assertNotEquals(null, blank.lines);
        System.assert(!blank.classCodes.isEmpty());
        System.assert(!blank.specialtyLabels.isEmpty());

        PromoGridTransferService.ExportLine found = findExportLine(blank.lines, 'PGXFER-LINE');
        System.assertNotEquals(null, found, 'Expected PGXFER-LINE in export');
        System.assert(found.products.size() >= 2, 'Expected line products pre-filled');
        System.assertEquals(9, found.classes.size(), 'Expected A1–C3 class rows');
        for (PromoGridTransferService.ExportClassRow classRow : found.classes) {
            System.assertEquals(null, classRow.listPercentage);
        }

        System.assertEquals(true, withValues.includeValues);
    }

    @IsTest
    static void preview_reportsUnknownLineAndOverHundred() {
        Territory2 line = getOrCreateLineTerritory('TERR_LINE_PGXFER', 'PGXFER-LINE');
        if (line == null) {
            return;
        }
        List<PromoGridAdminController.PicklistOption> specialties =
            PromoGridAdminController.getSpecialtyOptions();
        System.assert(!specialties.isEmpty());

        PromoGridTransferService.ImportLine unknown = new PromoGridTransferService.ImportLine();
        unknown.lineName = 'NO-SUCH-LINE';
        unknown.products = new List<PromoGridTransferService.ImportProductRow>();
        PromoGridTransferService.ImportProductRow unknownProduct =
            new PromoGridTransferService.ImportProductRow();
        unknownProduct.excelRow = 2;
        unknownProduct.productCode = 'PG_XFER_A';
        unknownProduct.weightPercentage = 100;
        unknown.products.add(unknownProduct);

        PromoGridTransferService.ImportLine over = new PromoGridTransferService.ImportLine();
        over.lineName = 'PGXFER-LINE';
        over.products = new List<PromoGridTransferService.ImportProductRow>();
        PromoGridTransferService.ImportProductRow productA =
            new PromoGridTransferService.ImportProductRow();
        productA.excelRow = 3;
        productA.productCode = 'PG_XFER_A';
        productA.weightPercentage = 60;
        PromoGridTransferService.ImportProductRow productB =
            new PromoGridTransferService.ImportProductRow();
        productB.excelRow = 4;
        productB.productCode = 'PG_XFER_B';
        productB.weightPercentage = 50;
        over.products.add(productA);
        over.products.add(productB);

        Test.startTest();
        PromoGridTransferService.ImportResult result = PromoGridTransferService.previewPromoGridImport(
            new List<PromoGridTransferService.ImportLine>{ unknown, over }
        );
        Test.stopTest();

        System.assertEquals(0, result.readyCount);
        System.assertEquals(2, result.skippedCount);
        System.assert(result.messages.size() >= 2);
        Boolean foundUnknown = false;
        Boolean foundOver = false;
        for (String message : result.messages) {
            if (message.contains('Unknown line')) {
                foundUnknown = true;
            }
            if (message.contains('over 100')) {
                foundOver = true;
            }
        }
        System.assert(foundUnknown, 'Expected unknown-line error');
        System.assert(foundOver, 'Expected over-100% error');
    }

    @IsTest
    static void previewJson_keepsLineNamesFromTheWorkbook() {
        Territory2 line = getOrCreateLineTerritory('TERR_LINE_PGXFER', 'PGXFER-LINE');
        if (line == null) {
            return;
        }
        // Same shape the LWC builds from the exported workbook.
        String linesJson =
            '[{"lineName":"PGXFER-LINE","products":[' +
            '{"excelRow":2,"productCode":"PG_XFER_A","productName":null,"weightPercentage":60},' +
            '{"excelRow":3,"productCode":"PG_XFER_B","productName":null,"weightPercentage":40}],' +
            '"specialties":[],"classes":[]}]';

        Test.startTest();
        PromoGridTransferService.ImportResult result = PromoGridTransferService.previewPromoGridImportJson(linesJson);
        PromoGridTransferService.ImportResult empty = PromoGridTransferService.previewPromoGridImportJson(null);
        Test.stopTest();

        System.assertEquals(1, result.lines.size());
        System.assertEquals('PGXFER-LINE', result.lines[0].lineName);
        System.assertEquals(1, result.readyCount);
        System.assertEquals(0, result.skippedCount);
        System.assertEquals(0, empty.lines.size());
    }

    @IsTest
    static void preview_warnsUnderHundredAndRejectsBadLookups() {
        Territory2 line = getOrCreateLineTerritory('TERR_LINE_PGXFER', 'PGXFER-LINE');
        if (line == null) {
            return;
        }

        PromoGridTransferService.ImportLine under = buildProductLine(
            'PGXFER-LINE',
            new List<String>{ 'PG_XFER_A' },
            new List<Decimal>{ 40 }
        );

        PromoGridTransferService.ImportLine badProduct = new PromoGridTransferService.ImportLine();
        badProduct.lineName = 'PGXFER-LINE';
        badProduct.products = new List<PromoGridTransferService.ImportProductRow>();
        PromoGridTransferService.ImportProductRow missing =
            new PromoGridTransferService.ImportProductRow();
        missing.excelRow = 8;
        missing.productCode = 'NO_SUCH_CODE';
        missing.weightPercentage = 100;
        badProduct.products.add(missing);

        PromoGridTransferService.ImportLine badSpecialty = new PromoGridTransferService.ImportLine();
        badSpecialty.lineName = 'PGXFER-LINE';
        badSpecialty.specialties = new List<PromoGridTransferService.ImportSpecialtyRow>();
        PromoGridTransferService.ImportSpecialtyRow specialtyRow =
            new PromoGridTransferService.ImportSpecialtyRow();
        specialtyRow.excelRow = 9;
        specialtyRow.specialty = 'Not A Real Specialty';
        specialtyRow.listPercentage = 100;
        badSpecialty.specialties.add(specialtyRow);

        PromoGridTransferService.ImportLine badClass = new PromoGridTransferService.ImportLine();
        badClass.lineName = 'PGXFER-LINE';
        badClass.classes = new List<PromoGridTransferService.ImportClassRow>();
        PromoGridTransferService.ImportClassRow classRow = new PromoGridTransferService.ImportClassRow();
        classRow.excelRow = 10;
        classRow.classCode = 'Z9';
        classRow.listPercentage = 100;
        badClass.classes.add(classRow);

        Test.startTest();
        PromoGridTransferService.ImportResult underResult =
            PromoGridTransferService.previewPromoGridImport(
                new List<PromoGridTransferService.ImportLine>{ under }
            );
        PromoGridTransferService.ImportResult badResult =
            PromoGridTransferService.previewPromoGridImport(
                new List<PromoGridTransferService.ImportLine>{ badProduct, badSpecialty, badClass }
            );
        Test.stopTest();

        System.assertEquals(1, underResult.readyCount);
        System.assertEquals(1, underResult.warningCount);
        System.assert(underResult.messages[0].contains('under 100'));

        System.assertEquals(0, badResult.readyCount);
        System.assertEquals(3, badResult.skippedCount);
    }

    @IsTest
    static void apply_replacesActiveSectionsAndSkipsErrorLines() {
        Territory2 line = getOrCreateLineTerritory('TERR_LINE_PGXFER', 'PGXFER-LINE');
        Territory2 line2 = getOrCreateLineTerritory('TERR_LINE_PGXFER2', 'PGXFER-LINE-2');
        if (line == null || line2 == null) {
            return;
        }

        Product2 productA = [
            SELECT Id
            FROM Product2
            WHERE ProductCode = 'PG_XFER_A'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Product2 productB = [
            SELECT Id
            FROM Product2
            WHERE ProductCode = 'PG_XFER_B'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Product2 productC = [
            SELECT Id
            FROM Product2
            WHERE ProductCode = 'PG_XFER_C'
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        String territoryKey = String.valueOf(line.Id);
        String territoryKey2 = String.valueOf(line2.Id);
        List<PromoGridAdminController.PicklistOption> specialties =
            PromoGridAdminController.getSpecialtyOptions();
        String specialtyValue = specialties[0].value;
        String specialtyLabel = specialties[0].label;

        insert as system new List<Promo_Grid_Product_Weight__c>{
            new Promo_Grid_Product_Weight__c(
                Territory2_Id__c = territoryKey,
                Product2__c = productA.Id,
                Weight_Percentage__c = 70,
                Unique_Key__c = territoryKey + ':' + String.valueOf(productA.Id)
            ),
            new Promo_Grid_Product_Weight__c(
                Territory2_Id__c = territoryKey,
                Product2__c = productB.Id,
                Weight_Percentage__c = 30,
                Unique_Key__c = territoryKey + ':' + String.valueOf(productB.Id)
            ),
            new Promo_Grid_Product_Weight__c(
                Territory2_Id__c = territoryKey2,
                Product2__c = productC.Id,
                Weight_Percentage__c = 100,
                Unique_Key__c = territoryKey2 + ':' + String.valueOf(productC.Id)
            )
        };
        insert as system new Promo_Grid_Specialty_Focus__c(
            Territory2_Id__c = territoryKey,
            Specialty__c = specialtyValue,
            List_Percentage__c = 100,
            Unique_Key__c = PromoGridAdminController.buildSpecialtyKey(territoryKey, specialtyValue)
        );
        insert as system new Promo_Grid_Class_Targeting__c(
            Territory2_Id__c = territoryKey,
            Class__c = 'A1',
            List_Percentage__c = 100,
            Target_Monthly_Visits__c = 4,
            Unique_Key__c = territoryKey + ':A1'
        );

        PromoGridTransferService.ImportLine good = new PromoGridTransferService.ImportLine();
        good.lineName = 'PGXFER-LINE';
        good.products = new List<PromoGridTransferService.ImportProductRow>();
        PromoGridTransferService.ImportProductRow keepA =
            new PromoGridTransferService.ImportProductRow();
        keepA.excelRow = 2;
        keepA.productCode = 'PG_XFER_A';
        keepA.weightPercentage = 100;
        good.products.add(keepA);
        good.specialties = new List<PromoGridTransferService.ImportSpecialtyRow>();
        PromoGridTransferService.ImportSpecialtyRow specialtyRow =
            new PromoGridTransferService.ImportSpecialtyRow();
        specialtyRow.excelRow = 2;
        specialtyRow.specialty = specialtyLabel;
        specialtyRow.listPercentage = 55;
        good.specialties.add(specialtyRow);
        if (specialties.size() > 1) {
            PromoGridTransferService.ImportSpecialtyRow specialtyRow2 =
                new PromoGridTransferService.ImportSpecialtyRow();
            specialtyRow2.excelRow = 3;
            specialtyRow2.specialty = specialties[1].label;
            specialtyRow2.listPercentage = 45;
            good.specialties.add(specialtyRow2);
        }
        good.classes = new List<PromoGridTransferService.ImportClassRow>();
        PromoGridTransferService.ImportClassRow classA1 =
            new PromoGridTransferService.ImportClassRow();
        classA1.excelRow = 2;
        classA1.classCode = 'A1';
        classA1.listPercentage = 60;
        classA1.targetMonthlyVisits = 6;
        PromoGridTransferService.ImportClassRow classA2 =
            new PromoGridTransferService.ImportClassRow();
        classA2.excelRow = 3;
        classA2.classCode = 'A2';
        classA2.listPercentage = 40;
        classA2.targetMonthlyVisits = 2;
        good.classes.add(classA1);
        good.classes.add(classA2);

        PromoGridTransferService.ImportLine bad = new PromoGridTransferService.ImportLine();
        bad.lineName = 'PGXFER-LINE-2';
        bad.products = new List<PromoGridTransferService.ImportProductRow>();
        PromoGridTransferService.ImportProductRow badProduct =
            new PromoGridTransferService.ImportProductRow();
        badProduct.excelRow = 5;
        badProduct.productCode = 'NOPE';
        badProduct.weightPercentage = 100;
        bad.products.add(badProduct);

        PromoGridTransferService.ImportLine blankSection = new PromoGridTransferService.ImportLine();
        blankSection.lineName = 'PGXFER-LINE-2';
        blankSection.products = new List<PromoGridTransferService.ImportProductRow>();
        PromoGridTransferService.ImportProductRow blankRow =
            new PromoGridTransferService.ImportProductRow();
        blankRow.excelRow = 6;
        blankRow.productCode = 'PG_XFER_C';
        blankRow.weightPercentage = null;
        blankSection.products.add(blankRow);

        Test.startTest();
        PromoGridTransferService.ImportResult blocked = PromoGridTransferService.applyPromoGridImport(
            new List<PromoGridTransferService.ImportLine>{ good, bad }
        );
        System.assertEquals(0, blocked.appliedCount, 'A file with an error line must not apply anything');
        System.assertEquals(1, blocked.skippedCount);
        System.assert(blocked.messages[0].startsWith('Nothing was imported'), blocked.messages[0]);
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Promo_Grid_Product_Weight__c WHERE Territory2_Id__c = :territoryKey WITH SYSTEM_MODE],
            'Valid line must stay untouched while the file has errors'
        );

        PromoGridTransferService.ImportResult result = PromoGridTransferService.applyPromoGridImport(
            new List<PromoGridTransferService.ImportLine>{ good }
        );
        Test.stopTest();

        System.assertEquals(1, result.appliedCount, 'The fixed file should apply');
        System.assertEquals(0, result.skippedCount);

        List<Promo_Grid_Product_Weight__c> lineWeights = [
            SELECT Product2__c, Weight_Percentage__c
            FROM Promo_Grid_Product_Weight__c
            WHERE Territory2_Id__c = :territoryKey
            WITH SYSTEM_MODE
        ];
        System.assertEquals(1, lineWeights.size(), 'Product B should be removed');
        System.assertEquals(productA.Id, lineWeights[0].Product2__c);
        System.assertEquals(
            100,
            PromoGridAdminController.displayPercent(lineWeights[0].Weight_Percentage__c)
        );

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Promo_Grid_Product_Weight__c
                WHERE Territory2_Id__c = :territoryKey2
                WITH SYSTEM_MODE
            ],
            'Error line should keep existing rows'
        );

        List<Promo_Grid_Specialty_Focus__c> specialtyRows = [
            SELECT Specialty__c, List_Percentage__c
            FROM Promo_Grid_Specialty_Focus__c
            WHERE Territory2_Id__c = :territoryKey
            WITH SYSTEM_MODE
        ];
        System.assert(specialtyRows.size() >= 1);

        List<Promo_Grid_Class_Targeting__c> classRows = [
            SELECT Class__c, List_Percentage__c, Target_Monthly_Visits__c
            FROM Promo_Grid_Class_Targeting__c
            WHERE Territory2_Id__c = :territoryKey
            WITH SYSTEM_MODE
            ORDER BY Class__c
        ];
        System.assertEquals(2, classRows.size());
        System.assertEquals('A1', classRows[0].Class__c);
        System.assertEquals(6, classRows[0].Target_Monthly_Visits__c);
    }

    @IsTest
    static void apply_leavesBlankSectionsUntouched() {
        Territory2 line = getOrCreateLineTerritory('TERR_LINE_PGXFER', 'PGXFER-LINE');
        if (line == null) {
            return;
        }
        Product2 productA = [
            SELECT Id
            FROM Product2
            WHERE ProductCode = 'PG_XFER_A'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        String territoryKey = String.valueOf(line.Id);
        insert as system new Promo_Grid_Product_Weight__c(
            Territory2_Id__c = territoryKey,
            Product2__c = productA.Id,
            Weight_Percentage__c = 100,
            Unique_Key__c = territoryKey + ':' + String.valueOf(productA.Id)
        );
        insert as system new Promo_Grid_Class_Targeting__c(
            Territory2_Id__c = territoryKey,
            Class__c = 'B1',
            List_Percentage__c = 100,
            Target_Monthly_Visits__c = 3,
            Unique_Key__c = territoryKey + ':B1'
        );

        List<PromoGridAdminController.PicklistOption> specialties =
            PromoGridAdminController.getSpecialtyOptions();
        PromoGridTransferService.ImportLine importLine = new PromoGridTransferService.ImportLine();
        importLine.lineName = 'pgxfer line';
        importLine.specialties = new List<PromoGridTransferService.ImportSpecialtyRow>();
        PromoGridTransferService.ImportSpecialtyRow specialtyRow =
            new PromoGridTransferService.ImportSpecialtyRow();
        specialtyRow.excelRow = 2;
        specialtyRow.specialty = specialties[0].value;
        specialtyRow.listPercentage = 100;
        importLine.specialties.add(specialtyRow);
        importLine.products = new List<PromoGridTransferService.ImportProductRow>();
        importLine.classes = new List<PromoGridTransferService.ImportClassRow>();

        Test.startTest();
        PromoGridTransferService.ImportResult result = PromoGridTransferService.applyPromoGridImport(
            new List<PromoGridTransferService.ImportLine>{ importLine }
        );
        Test.stopTest();

        System.assertEquals(1, result.appliedCount);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Promo_Grid_Product_Weight__c
                WHERE Territory2_Id__c = :territoryKey
                WITH SYSTEM_MODE
            ],
            'Blank products section must stay untouched'
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Promo_Grid_Class_Targeting__c
                WHERE Territory2_Id__c = :territoryKey AND Class__c = 'B1'
                WITH SYSTEM_MODE
            ],
            'Blank classes section must stay untouched'
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Promo_Grid_Specialty_Focus__c
                WHERE Territory2_Id__c = :territoryKey
                WITH SYSTEM_MODE
            ]
        );
    }

    @IsTest
    static void preview_detectsDuplicateProductWithinLine() {
        Territory2 line = getOrCreateLineTerritory('TERR_LINE_PGXFER', 'PGXFER-LINE');
        if (line == null) {
            return;
        }
        PromoGridTransferService.ImportLine importLine = new PromoGridTransferService.ImportLine();
        importLine.lineName = 'PGXFER-LINE';
        importLine.products = new List<PromoGridTransferService.ImportProductRow>();
        PromoGridTransferService.ImportProductRow first =
            new PromoGridTransferService.ImportProductRow();
        first.excelRow = 2;
        first.productCode = 'PG_XFER_A';
        first.weightPercentage = 50;
        PromoGridTransferService.ImportProductRow second =
            new PromoGridTransferService.ImportProductRow();
        second.excelRow = 3;
        second.productCode = 'PG_XFER_A';
        second.weightPercentage = 50;
        importLine.products.add(first);
        importLine.products.add(second);

        Test.startTest();
        PromoGridTransferService.ImportResult result = PromoGridTransferService.previewPromoGridImport(
            new List<PromoGridTransferService.ImportLine>{ importLine }
        );
        Test.stopTest();

        System.assertEquals(0, result.readyCount);
        System.assert(result.messages[0].contains('duplicate product'));
    }

    private static PromoGridTransferService.ImportLine buildProductLine(
        String lineName,
        List<String> productCodes,
        List<Decimal> percentages
    ) {
        PromoGridTransferService.ImportLine importLine = new PromoGridTransferService.ImportLine();
        importLine.lineName = lineName;
        importLine.products = new List<PromoGridTransferService.ImportProductRow>();
        for (Integer i = 0; i < productCodes.size(); i++) {
            PromoGridTransferService.ImportProductRow row =
                new PromoGridTransferService.ImportProductRow();
            row.excelRow = i + 2;
            row.productCode = productCodes[i];
            row.weightPercentage = percentages[i];
            importLine.products.add(row);
        }
        return importLine;
    }

    private static PromoGridTransferService.ExportLine findExportLine(
        List<PromoGridTransferService.ExportLine> lines,
        String lineName
    ) {
        for (PromoGridTransferService.ExportLine line : lines) {
            if (line.lineName == lineName) {
                return line;
            }
        }
        return null;
    }

    private static Territory2 getOrCreateLineTerritory(String externalId, String name) {
        List<Territory2> existing = [
            SELECT Id, Name, External_ID__c, Territory_Type__c
            FROM Territory2
            WHERE External_ID__c = :externalId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            Territory2 line = existing[0];
            if (line.Territory_Type__c != 'Line' || line.Name != name) {
                line.Territory_Type__c = 'Line';
                line.Name = name;
                // Territory2 is a setup object: write it in its own context to avoid MIXED_DML.
                System.runAs(new User(Id = UserInfo.getUserId())) {
                    update line;
                }
            }
            return line;
        }

        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return null;
        }
        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE State = 'Active'
            LIMIT 1
        ];
        if (models.isEmpty()) {
            models = [SELECT Id FROM Territory2Model LIMIT 1];
        }
        if (models.isEmpty()) {
            return null;
        }

        Territory2 territory = new Territory2(
            Name = name,
            DeveloperName = 'Line_PgXfer_' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = externalId,
            Territory_Type__c = 'Line'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert territory;
        }
        return territory;
    }
}
