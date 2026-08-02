public with sharing class PharmacySalesDataAdminController {
    private static final Integer MAX_IMPORT_ROWS = 5000;
    private static final String F_BRICK = 'Brick' + '__c';
    private static final String F_IS_ACTIVE = 'Is_Active' + '__c';
    private static final String F_UNIQUE_KEY = 'Unique_Key' + '__c';
    private static final String F_UNIT_PRICE = 'Unit_Price' + '__c';
    private static final String F_REVENUE = 'Revenue' + '__c';
    private static final String F_IMPORT_BATCH = 'Import_Batch' + '__c';
    private static final String F_EXTERNAL_ID = 'External_ID' + '__c';
    private static final String F_FILE_NAME = 'File_Name' + '__c';
    private static final String F_ROWS_INSERTED = 'Rows_Inserted' + '__c';
    private static final String F_ROWS_UPDATED = 'Rows_Updated' + '__c';
    private static final String F_ROWS_FAILED = 'Rows_Failed' + '__c';
    private static final String F_ERROR_LOG = 'Error_Log' + '__c';
    private static final String R_BRICK = 'Brick' + '__r';
    private static final String CSV_TEMPLATE =
        'data_source,report_month,pharmacy_external_id,product_external_id,quantity_withdrawn,unit_price,external_id\n' +
        'IbnSina,2026-01,PHARM_EL_EZABY_MAADI,ZETA_EMPACOZA_10MG,120,180,\n' +
        'Pharmaoverseas,2026-01,PHARM_SEIF,ZETA_DOZOVA_NAD_300,80,320,';

    public class ImportPreviewRow {
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public String dataSource;
        @AuraEnabled public String reportMonth;
        @AuraEnabled public String pharmacyExternalId;
        @AuraEnabled public String productExternalId;
        @AuraEnabled public Decimal quantityWithdrawn;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public String externalId;
        @AuraEnabled public String validationMessage;
        @AuraEnabled public Boolean isValid;
    }

    public class ImportResult {
        @AuraEnabled public Id batchId;
        @AuraEnabled public Integer rowsInserted;
        @AuraEnabled public Integer rowsUpdated;
        @AuraEnabled public Integer rowsFailed;
        @AuraEnabled public String errorLog;
        @AuraEnabled public List<ImportPreviewRow> previewRows;
    }

    public class WithdrawalViewerRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String reportMonth;
        @AuraEnabled public String dataSource;
        @AuraEnabled public String pharmacyName;
        @AuraEnabled public String brickName;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public Id importBatchId;
    }

    public class ImportBatchRow {
        @AuraEnabled public Id batchId;
        @AuraEnabled public String fileName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Integer rowsInserted;
        @AuraEnabled public Integer rowsUpdated;
        @AuraEnabled public Integer rowsFailed;
    }

    public class BrickSummaryRow {
        @AuraEnabled public Id brickId;
        @AuraEnabled public String brickName;
        @AuraEnabled public Integer pharmacyCount;
        @AuraEnabled public Boolean isActive;
    }

    public class BrickPharmacyRow {
        @AuraEnabled public Id membershipId;
        @AuraEnabled public Id pharmacyId;
        @AuraEnabled public String pharmacyName;
        @AuraEnabled public Boolean isActive;
    }

    public class PharmacyOption {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
    }

    @AuraEnabled
    public static String getCsvTemplate() {
        return CSV_TEMPLATE;
    }

    @AuraEnabled
    public static ImportResult previewSalesDataCsv(String csvContent) {
        ImportResult result = new ImportResult();
        List<ImportPreviewRow> parsed = parseCsv(csvContent, true);
        Integer previewCount = Math.min(10, parsed.size());
        List<ImportPreviewRow> preview = new List<ImportPreviewRow>();
        for (Integer i = 0; i < previewCount; i++) {
            preview.add(parsed[i]);
        }
        result.previewRows = preview;
        result.rowsFailed = countInvalid(parsed);
        return result;
    }

    @AuraEnabled
    public static ImportResult importSalesDataCsv(String csvContent, String fileName) {
        if (String.isBlank(csvContent)) {
            throw new AuraHandledException('CSV content is required.');
        }

        List<ImportPreviewRow> parsed = parseCsv(csvContent, true);
        if (parsed.size() > MAX_IMPORT_ROWS) {
            throw new AuraHandledException('Import exceeds the maximum of ' + MAX_IMPORT_ROWS + ' rows.');
        }

        Map<String, Id> pharmacyByExtId = loadPharmacyIdsByExternalId(parsed);
        Map<String, Id> productByExtId = loadProductIdsByExternalId(parsed);
        Map<Id, Id> brickByPharmacy = loadBrickByPharmacy(pharmacyByExtId.values());
        Map<Id, Decimal> unitPriceByProduct = loadStandardPrices(new Set<Id>(productByExtId.values()));

        Sales_Data_Import_Batch__c batch;
        if (hasField(Sales_Data_Import_Batch__c.SObjectType, F_FILE_NAME)) {
            batch = new Sales_Data_Import_Batch__c();
            setFieldIfPresent(batch, F_FILE_NAME, String.isBlank(fileName) ? 'upload.csv' : fileName);
            insert as user batch;
        }

        List<String> errors = new List<String>();
        List<Pharmacy_Sales_Withdrawal__c> recordsToSave = new List<Pharmacy_Sales_Withdrawal__c>();
        Integer failed = 0;
        Boolean supportsUniqueKey = hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, F_UNIQUE_KEY);

        for (ImportPreviewRow row : parsed) {
            if (!row.isValid) {
                failed++;
                errors.add('Row ' + row.rowNumber + ': ' + row.validationMessage);
                continue;
            }
            Id pharmacyId = pharmacyByExtId.get(row.pharmacyExternalId);
            Id productId = productByExtId.get(row.productExternalId);
            Date reportMonth = parseReportMonth(row.reportMonth);
            Decimal unitPrice = row.unitPrice != null ? row.unitPrice : unitPriceByProduct.get(productId);

            Pharmacy_Sales_Withdrawal__c record = new Pharmacy_Sales_Withdrawal__c(
                Data_Source__c = row.dataSource,
                Report_Month__c = reportMonth,
                Pharmacy_Account__c = pharmacyId,
                Product2_Id__c = String.valueOf(productId),
                Quantity_Withdrawn__c = row.quantityWithdrawn
            );
            setFieldIfPresent(record, F_BRICK, brickByPharmacy.get(pharmacyId));
            setFieldIfPresent(record, F_UNIT_PRICE, unitPrice);
            if (batch != null) {
                setFieldIfPresent(record, F_IMPORT_BATCH, batch.Id);
            }
            if (String.isNotBlank(row.externalId)) {
                setFieldIfPresent(record, F_EXTERNAL_ID, row.externalId);
            }
            if (supportsUniqueKey) {
                setFieldIfPresent(
                    record,
                    F_UNIQUE_KEY,
                    buildUniqueKey(row.dataSource, reportMonth, pharmacyId, productId)
                );
            }
            recordsToSave.add(record);
        }

        Integer inserted = 0;
        Integer updated = 0;
        if (!recordsToSave.isEmpty()) {
            if (supportsUniqueKey) {
                Schema.SObjectField uniqueKeyField = Pharmacy_Sales_Withdrawal__c.SObjectType
                    .getDescribe()
                    .fields
                    .getMap()
                    .get(F_UNIQUE_KEY.toLowerCase());
                Database.UpsertResult[] results = Database.upsert(
                    recordsToSave,
                    uniqueKeyField,
                    false,
                    AccessLevel.USER_MODE
                );
                for (Integer i = 0; i < results.size(); i++) {
                    Database.UpsertResult ur = results[i];
                    if (ur.isSuccess()) {
                        if (ur.isCreated()) {
                            inserted++;
                        } else {
                            updated++;
                        }
                    } else {
                        failed++;
                        String msg = 'Row upsert failed: ';
                        for (Database.Error err : ur.getErrors()) {
                            msg += err.getMessage() + ' ';
                        }
                        errors.add(msg);
                    }
                }
            } else {
                Database.SaveResult[] results = Database.insert(recordsToSave, false, AccessLevel.USER_MODE);
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        inserted++;
                    } else {
                        failed++;
                        String msg = 'Row insert failed: ';
                        for (Database.Error err : results[i].getErrors()) {
                            msg += err.getMessage() + ' ';
                        }
                        errors.add(msg);
                    }
                }
            }
        }

        if (batch != null) {
            setFieldIfPresent(batch, F_ROWS_INSERTED, inserted);
            setFieldIfPresent(batch, F_ROWS_UPDATED, updated);
            setFieldIfPresent(batch, F_ROWS_FAILED, failed);
            setFieldIfPresent(
                batch,
                F_ERROR_LOG,
                errors.isEmpty() ? null : String.join(errors, '\n').left(131000)
            );
            update as user batch;
        }

        ImportResult result = new ImportResult();
        result.batchId = batch != null ? batch.Id : null;
        result.rowsInserted = inserted;
        result.rowsUpdated = updated;
        result.rowsFailed = failed;
        result.errorLog = batch != null ? (String) batch.get(F_ERROR_LOG) : null;
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<WithdrawalViewerRow> getWithdrawalRows(
        Date startMonth,
        Date endMonth,
        String dataSource,
        Id brickId,
        Integer rowLimit
    ) {
        Integer limitSize = rowLimit == null || rowLimit <= 0 ? 200 : Math.min(rowLimit, 500);
        Date start = startMonth == null ? Date.today().toStartOfMonth().addMonths(-3) : startMonth.toStartOfMonth();
        Date endMonthResolved = endMonth == null ? Date.today().toStartOfMonth() : endMonth.toStartOfMonth();

        List<String> selectFields = new List<String>{
            'Id',
            'Report_Month__c',
            'Data_Source__c',
            'Pharmacy_Account__r.Name',
            'Product2_Id__c',
            'Quantity_Withdrawn__c'
        };
        if (hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, F_BRICK)) {
            selectFields.add(F_BRICK);
            if (hasRelationship(Pharmacy_Sales_Withdrawal__c.SObjectType, R_BRICK)) {
                selectFields.add(R_BRICK + '.Name');
            }
        }
        if (hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, F_UNIT_PRICE)) {
            selectFields.add(F_UNIT_PRICE);
        }
        if (hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, F_REVENUE)) {
            selectFields.add(F_REVENUE);
        }
        if (hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, F_IMPORT_BATCH)) {
            selectFields.add(F_IMPORT_BATCH);
        }

        String soql = 'SELECT ' + String.join(selectFields, ', ') +
            ' FROM Pharmacy_Sales_Withdrawal__c WHERE Report_Month__c >= :start AND Report_Month__c <= :endMonthResolved';
        if (String.isNotBlank(dataSource) && dataSource != 'All') {
            soql += ' AND Data_Source__c = :dataSource';
        }
        if (brickId != null && hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, F_BRICK)) {
            soql += ' AND ' + F_BRICK + ' = :brickId';
        }
        soql += ' WITH USER_MODE ORDER BY Report_Month__c DESC LIMIT :limitSize';

        List<Pharmacy_Sales_Withdrawal__c> rows = Database.query(soql);
        Map<Id, String> brickNamesById = loadBrickNames(rows);
        Set<Id> productIds = new Set<Id>();
        for (Pharmacy_Sales_Withdrawal__c row : rows) {
            if (String.isNotBlank(row.Product2_Id__c)) {
                productIds.add((Id) row.Product2_Id__c);
            }
        }
        Map<Id, Product2> productsById = new Map<Id, Product2>([
            SELECT Id, Name
            FROM Product2
            WHERE Id IN :productIds
            WITH USER_MODE
        ]);

        List<WithdrawalViewerRow> result = new List<WithdrawalViewerRow>();
        for (Pharmacy_Sales_Withdrawal__c row : rows) {
            WithdrawalViewerRow view = new WithdrawalViewerRow();
            view.recordId = row.Id;
            view.reportMonth = formatReportMonth(row.Report_Month__c);
            view.dataSource = row.Data_Source__c;
            view.pharmacyName = row.Pharmacy_Account__r.Name;
            if (hasRelationship(Pharmacy_Sales_Withdrawal__c.SObjectType, R_BRICK)) {
                SObject brickRef = row.getSObject(R_BRICK);
                view.brickName = brickRef != null ? (String) brickRef.get('Name') : '';
            } else if (hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, F_BRICK)) {
                Id resolvedBrickId = (Id) row.get(F_BRICK);
                view.brickName = resolvedBrickId != null ? brickNamesById.get(resolvedBrickId) : '';
            } else {
                view.brickName = '';
            }
            Product2 product = productsById.get((Id) row.Product2_Id__c);
            view.productName = product != null ? product.Name : '';
            view.quantity = row.Quantity_Withdrawn__c;
            view.unitPrice = hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, F_UNIT_PRICE)
                ? (Decimal) row.get(F_UNIT_PRICE)
                : null;
            view.revenue = hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, F_REVENUE)
                ? (Decimal) row.get(F_REVENUE)
                : null;
            view.importBatchId = hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, F_IMPORT_BATCH)
                ? (Id) row.get(F_IMPORT_BATCH)
                : null;
            result.add(view);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<ImportBatchRow> getImportBatches(Integer rowLimit) {
        Integer limitSize = rowLimit == null || rowLimit <= 0 ? 20 : Math.min(rowLimit, 100);
        List<ImportBatchRow> rows = new List<ImportBatchRow>();
        if (!hasField(Sales_Data_Import_Batch__c.SObjectType, F_FILE_NAME)) {
            return rows;
        }

        List<String> selectFields = new List<String>{ 'Id', 'CreatedDate', F_FILE_NAME };
        if (hasField(Sales_Data_Import_Batch__c.SObjectType, F_ROWS_INSERTED)) {
            selectFields.add(F_ROWS_INSERTED);
        }
        if (hasField(Sales_Data_Import_Batch__c.SObjectType, F_ROWS_UPDATED)) {
            selectFields.add(F_ROWS_UPDATED);
        }
        if (hasField(Sales_Data_Import_Batch__c.SObjectType, F_ROWS_FAILED)) {
            selectFields.add(F_ROWS_FAILED);
        }

        String soql = 'SELECT ' + String.join(selectFields, ', ') +
            ' FROM Sales_Data_Import_Batch__c WITH USER_MODE ORDER BY CreatedDate DESC LIMIT :limitSize';
        for (Sales_Data_Import_Batch__c batch : Database.query(soql)) {
            ImportBatchRow row = new ImportBatchRow();
            row.batchId = batch.Id;
            row.fileName = (String) batch.get(F_FILE_NAME);
            row.createdDate = batch.CreatedDate;
            row.rowsInserted = batch.get(F_ROWS_INSERTED) == null
                ? 0
                : Integer.valueOf(String.valueOf(batch.get(F_ROWS_INSERTED)));
            row.rowsUpdated = batch.get(F_ROWS_UPDATED) == null
                ? 0
                : Integer.valueOf(String.valueOf(batch.get(F_ROWS_UPDATED)));
            row.rowsFailed = batch.get(F_ROWS_FAILED) == null
                ? 0
                : Integer.valueOf(String.valueOf(batch.get(F_ROWS_FAILED)));
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static void deleteWithdrawalRows(List<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return;
        }
        delete as user [
            SELECT Id
            FROM Pharmacy_Sales_Withdrawal__c
            WHERE Id IN :recordIds
            WITH USER_MODE
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<BrickSummaryRow> getBrickSummaries() {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        String membershipSoql = 'SELECT ' + F_BRICK + ' brickId, COUNT(Id) cnt FROM Brick_Pharmacy__c';
        if (hasField(Brick_Pharmacy__c.SObjectType, F_IS_ACTIVE)) {
            membershipSoql += ' WHERE ' + F_IS_ACTIVE + ' = TRUE';
        }
        membershipSoql += ' WITH USER_MODE GROUP BY ' + F_BRICK;
        for (AggregateResult ar : Database.query(membershipSoql)) {
            counts.put((Id) ar.get('brickId'), (Integer) ar.get('cnt'));
        }

        List<String> brickFields = new List<String>{ 'Id', 'Name' };
        if (hasField(Brick__c.SObjectType, F_IS_ACTIVE)) {
            brickFields.add(F_IS_ACTIVE);
        }
        String brickSoql = 'SELECT ' + String.join(brickFields, ', ') +
            ' FROM Brick__c WITH USER_MODE ORDER BY Name';

        List<BrickSummaryRow> rows = new List<BrickSummaryRow>();
        for (Brick__c brick : Database.query(brickSoql)) {
            BrickSummaryRow row = new BrickSummaryRow();
            row.brickId = brick.Id;
            row.brickName = brick.Name;
            row.pharmacyCount = counts.containsKey(brick.Id) ? counts.get(brick.Id) : 0;
            row.isActive = hasField(Brick__c.SObjectType, F_IS_ACTIVE)
                ? (Boolean) brick.get(F_IS_ACTIVE)
                : true;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<BrickPharmacyRow> getBrickPharmacies(Id brickId) {
        if (brickId == null) {
            return new List<BrickPharmacyRow>();
        }
        List<String> membershipFields = new List<String>{
            'Id',
            'Pharmacy_Account__c',
            'Pharmacy_Account__r.Name'
        };
        if (hasField(Brick_Pharmacy__c.SObjectType, F_IS_ACTIVE)) {
            membershipFields.add(F_IS_ACTIVE);
        }
        String membershipSoql = 'SELECT ' + String.join(membershipFields, ', ') +
            ' FROM Brick_Pharmacy__c WHERE ' + F_BRICK + ' = :brickId WITH USER_MODE ORDER BY Pharmacy_Account__r.Name';

        List<BrickPharmacyRow> rows = new List<BrickPharmacyRow>();
        for (Brick_Pharmacy__c membership : Database.query(membershipSoql)) {
            BrickPharmacyRow row = new BrickPharmacyRow();
            row.membershipId = membership.Id;
            row.pharmacyId = membership.Pharmacy_Account__c;
            row.pharmacyName = membership.Pharmacy_Account__r.Name;
            row.isActive = hasField(Brick_Pharmacy__c.SObjectType, F_IS_ACTIVE)
                ? (Boolean) membership.get(F_IS_ACTIVE)
                : true;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<PharmacyOption> searchPharmacyOptions(String searchTerm) {
        String term = String.isBlank(searchTerm) ? '%' : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        List<PharmacyOption> options = new List<PharmacyOption>();
        for (Account pharmacy : [
            SELECT Id, Name
            FROM Account
            WHERE Name LIKE :term
            WITH USER_MODE
            ORDER BY Name
            LIMIT 25
        ]) {
            PharmacyOption option = new PharmacyOption();
            option.value = pharmacy.Id;
            option.label = pharmacy.Name;
            options.add(option);
        }
        return options;
    }

    @AuraEnabled
    public static Id addPharmacyToBrick(Id brickId, Id pharmacyId) {
        if (brickId == null || pharmacyId == null) {
            throw new AuraHandledException('Brick and pharmacy are required.');
        }
        Brick_Pharmacy__c membership = new Brick_Pharmacy__c(
            Brick__c = brickId,
            Pharmacy_Account__c = pharmacyId
        );
        setFieldIfPresent(membership, F_IS_ACTIVE, true);
        insert as user membership;
        syncAccountBrickLookup(pharmacyId, brickId);
        return membership.Id;
    }

    private static void syncAccountBrickLookup(Id pharmacyId, Id brickId) {
        if (!hasField(Account.SObjectType, 'Brick__c')) {
            return;
        }
        update as user new Account(Id = pharmacyId, Brick__c = brickId);
    }

    @AuraEnabled
    public static void removePharmacyFromBrick(Id membershipId) {
        if (membershipId == null) {
            return;
        }
        delete as user [
            SELECT Id
            FROM Brick_Pharmacy__c
            WHERE Id = :membershipId
            WITH USER_MODE
        ];
    }

    @AuraEnabled
    public static PharmacySalesDataSeed.SeedResult seedDemoData() {
        return PharmacySalesDataSeed.seedDemoData();
    }

    private static List<ImportPreviewRow> parseCsv(String csvContent, Boolean validate) {
        List<ImportPreviewRow> rows = new List<ImportPreviewRow>();
        if (String.isBlank(csvContent)) {
            return rows;
        }
        List<String> lines = csvContent.replace('\r\n', '\n').replace('\r', '\n').split('\n');
        if (lines.isEmpty()) {
            return rows;
        }

        Map<String, Integer> headerIndex = parseHeader(lines[0]);
        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i];
            if (String.isBlank(line)) {
                continue;
            }
            List<String> cells = parseCsvLine(line);
            ImportPreviewRow row = new ImportPreviewRow();
            row.rowNumber = i + 1;
            row.dataSource = cellValue(cells, headerIndex, 'data_source');
            row.reportMonth = cellValue(cells, headerIndex, 'report_month');
            row.pharmacyExternalId = cellValue(cells, headerIndex, 'pharmacy_external_id');
            row.productExternalId = cellValue(cells, headerIndex, 'product_external_id');
            row.externalId = cellValue(cells, headerIndex, 'external_id');
            String qtyRaw = cellValue(cells, headerIndex, 'quantity_withdrawn');
            String priceRaw = cellValue(cells, headerIndex, 'unit_price');
            row.quantityWithdrawn = String.isBlank(qtyRaw) ? null : Decimal.valueOf(qtyRaw);
            row.unitPrice = String.isBlank(priceRaw) ? null : Decimal.valueOf(priceRaw);
            if (validate) {
                row.validationMessage = validateRow(row);
                row.isValid = String.isBlank(row.validationMessage);
            } else {
                row.isValid = true;
            }
            rows.add(row);
        }
        return rows;
    }

    private static Map<String, Integer> parseHeader(String headerLine) {
        Map<String, Integer> headerIndex = new Map<String, Integer>();
        List<String> headers = parseCsvLine(headerLine);
        for (Integer i = 0; i < headers.size(); i++) {
            headerIndex.put(headers[i].trim().toLowerCase(), i);
        }
        return headerIndex;
    }

    private static List<String> parseCsvLine(String line) {
        List<String> cells = new List<String>();
        Boolean inQuotes = false;
        String current = '';
        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            if (ch == '"') {
                inQuotes = !inQuotes;
            } else if (ch == ',' && !inQuotes) {
                cells.add(current.trim());
                current = '';
            } else {
                current += ch;
            }
        }
        cells.add(current.trim());
        return cells;
    }

    private static String cellValue(List<String> cells, Map<String, Integer> headerIndex, String column) {
        if (!headerIndex.containsKey(column)) {
            return null;
        }
        Integer idx = headerIndex.get(column);
        if (idx >= cells.size()) {
            return null;
        }
        return cells[idx];
    }

    private static String validateRow(ImportPreviewRow row) {
        if (String.isBlank(row.dataSource)) {
            return 'data_source is required.';
        }
        if (row.dataSource != 'IbnSina' && row.dataSource != 'Pharmaoverseas') {
            return 'data_source must be IbnSina or Pharmaoverseas.';
        }
        if (String.isBlank(row.reportMonth)) {
            return 'report_month is required.';
        }
        try {
            parseReportMonth(row.reportMonth);
        } catch (Exception e) {
            return 'report_month must be YYYY-MM or YYYY-MM-DD.';
        }
        if (String.isBlank(row.pharmacyExternalId)) {
            return 'pharmacy_external_id is required.';
        }
        if (String.isBlank(row.productExternalId)) {
            return 'product_external_id is required.';
        }
        if (row.quantityWithdrawn == null || row.quantityWithdrawn <= 0) {
            return 'quantity_withdrawn must be greater than zero.';
        }
        return null;
    }

    private static Integer countInvalid(List<ImportPreviewRow> rows) {
        Integer count = 0;
        for (ImportPreviewRow row : rows) {
            if (!row.isValid) {
                count++;
            }
        }
        return count;
    }

    private static Map<String, Id> loadPharmacyIdsByExternalId(List<ImportPreviewRow> rows) {
        Set<String> extIds = new Set<String>();
        for (ImportPreviewRow row : rows) {
            if (String.isNotBlank(row.pharmacyExternalId)) {
                extIds.add(row.pharmacyExternalId);
            }
        }
        Map<String, Id> result = new Map<String, Id>();
        if (extIds.isEmpty()) {
            return result;
        }
        for (Account pharmacy : [
            SELECT Id, External_ID__c
            FROM Account
            WHERE External_ID__c IN :extIds
            WITH USER_MODE
        ]) {
            result.put(pharmacy.External_ID__c, pharmacy.Id);
        }
        for (ImportPreviewRow row : rows) {
            if (row.isValid && !result.containsKey(row.pharmacyExternalId)) {
                row.isValid = false;
                row.validationMessage = 'Unknown pharmacy_external_id: ' + row.pharmacyExternalId;
            }
        }
        return result;
    }

    private static Map<String, Id> loadProductIdsByExternalId(List<ImportPreviewRow> rows) {
        Set<String> extIds = new Set<String>();
        for (ImportPreviewRow row : rows) {
            if (String.isNotBlank(row.productExternalId)) {
                extIds.add(row.productExternalId);
            }
        }
        Map<String, Id> result = new Map<String, Id>();
        if (extIds.isEmpty()) {
            return result;
        }
        for (Product2 product : [
            SELECT Id, External_ID__c
            FROM Product2
            WHERE External_ID__c IN :extIds
            WITH USER_MODE
        ]) {
            result.put(product.External_ID__c, product.Id);
        }
        for (ImportPreviewRow row : rows) {
            if (row.isValid && !result.containsKey(row.productExternalId)) {
                row.isValid = false;
                row.validationMessage = 'Unknown product_external_id: ' + row.productExternalId;
            }
        }
        return result;
    }

    private static Map<Id, Id> loadBrickByPharmacy(List<Id> pharmacyIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (pharmacyIds == null || pharmacyIds.isEmpty()) {
            return result;
        }
        String membershipSoql = 'SELECT Pharmacy_Account__c, ' + F_BRICK + ' FROM Brick_Pharmacy__c' +
            ' WHERE Pharmacy_Account__c IN :pharmacyIds';
        if (hasField(Brick_Pharmacy__c.SObjectType, F_IS_ACTIVE)) {
            membershipSoql += ' AND ' + F_IS_ACTIVE + ' = TRUE';
        }
        membershipSoql += ' WITH USER_MODE';
        for (Brick_Pharmacy__c membership : Database.query(membershipSoql)) {
            if (!result.containsKey(membership.Pharmacy_Account__c)) {
                result.put(membership.Pharmacy_Account__c, (Id) membership.get(F_BRICK));
            }
        }
        return result;
    }

    private static Map<Id, Decimal> loadStandardPrices(Set<Id> productIds) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        if (productIds == null || productIds.isEmpty()) {
            return result;
        }
        Id standardPricebookId = [
            SELECT Id
            FROM Pricebook2
            WHERE IsStandard = TRUE
            WITH USER_MODE
            LIMIT 1
        ].Id;
        for (PricebookEntry pbe : [
            SELECT Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
            AND Product2Id IN :productIds
            AND IsActive = TRUE
            WITH USER_MODE
        ]) {
            result.put(pbe.Product2Id, pbe.UnitPrice);
        }
        return result;
    }

    private static Date parseReportMonth(String raw) {
        String value = raw.trim();
        if (value.length() == 7) {
            List<String> parts = value.split('-');
            return Date.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), 1);
        }
        return Date.valueOf(value);
    }

    private static String formatReportMonth(Date monthDate) {
        if (monthDate == null) {
            return '';
        }
        Datetime monthDatetime = Datetime.newInstance(monthDate.year(), monthDate.month(), monthDate.day());
        return monthDatetime.format('MMM yyyy');
    }

    private static String buildUniqueKey(String dataSource, Date reportMonth, Id pharmacyId, Id productId) {
        String monthKey = String.valueOf(reportMonth.year()) + '-' +
            String.valueOf(reportMonth.month()).leftPad(2, '0');
        return dataSource + '_' + monthKey + '_' + String.valueOf(pharmacyId) + '_' + String.valueOf(productId);
    }

    private static Boolean hasField(Schema.SObjectType typeToken, String fieldApiName) {
        return PharmacySalesSchemaUtil.hasField(typeToken, fieldApiName);
    }

    private static Boolean hasRelationship(Schema.SObjectType typeToken, String relationshipApiName) {
        return PharmacySalesSchemaUtil.hasRelationship(typeToken, relationshipApiName);
    }

    private static void setFieldIfPresent(SObject record, String fieldApiName, Object value) {
        if (hasField(record.getSObjectType(), fieldApiName)) {
            record.put(fieldApiName, value);
        }
    }

    private static Map<Id, String> loadBrickNames(List<Pharmacy_Sales_Withdrawal__c> rows) {
        Map<Id, String> brickNamesById = new Map<Id, String>();
        if (!hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, F_BRICK)) {
            return brickNamesById;
        }

        Set<Id> brickIds = new Set<Id>();
        for (Pharmacy_Sales_Withdrawal__c row : rows) {
            Id resolvedBrickId = (Id) row.get(F_BRICK);
            if (resolvedBrickId != null) {
                brickIds.add(resolvedBrickId);
            }
        }
        if (brickIds.isEmpty()) {
            return brickNamesById;
        }

        for (Brick__c brick : [
            SELECT Id, Name
            FROM Brick__c
            WHERE Id IN :brickIds
            WITH USER_MODE
        ]) {
            brickNamesById.put(brick.Id, brick.Name);
        }
        return brickNamesById;
    }
}
