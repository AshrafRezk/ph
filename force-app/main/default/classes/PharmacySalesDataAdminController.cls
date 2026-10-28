/**
 * Backend for the sales-data admin screen: CSV load, viewer, and demo seed.
 * Share-of-business edits live in SalesSobAdminController.
 */
public with sharing class PharmacySalesDataAdminController {
    private static final String TEMPLATE =
        'Data_Source,Report_Month,Pharmacy_External_Id,Product_External_Id,Quantity,Unit_Price\n' +
        'IbnSina,2026-10,PHARM-001,PROD-001,12,25.50\n';
    private static final Set<String> SOURCES = new Set<String>{
        'IbnSina', 'Pharmaoverseas', 'Sofico', 'Egydrug', 'POS', 'Elezaby', 'Ebda', 'Direct'
    };

    public class PreviewRow {
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public String dataSource;
        @AuraEnabled public String reportMonth;
        @AuraEnabled public String pharmacyExternalId;
        @AuraEnabled public String productExternalId;
        @AuraEnabled public Decimal quantityWithdrawn;
        @AuraEnabled public Boolean isValid;
        @AuraEnabled public String validationMessage;
    }

    public class ImportResult {
        @AuraEnabled public Integer rowsInserted;
        @AuraEnabled public Integer rowsUpdated;
        @AuraEnabled public Integer rowsFailed;
        @AuraEnabled public String errorLog;
        @AuraEnabled public List<PreviewRow> previewRows;
    }

    public class WithdrawalRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String reportMonth;
        @AuraEnabled public String dataSource;
        @AuraEnabled public String pharmacyName;
        @AuraEnabled public String brickName;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal revenue;
    }

    public class BatchRow {
        @AuraEnabled public Id batchId;
        @AuraEnabled public String fileName;
        @AuraEnabled public Integer rowsInserted;
        @AuraEnabled public Integer rowsUpdated;
        @AuraEnabled public Integer rowsFailed;
    }

    public class SeedResult {
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static String getCsvTemplate() {
        FieldBookAccess.assertCanAdministerSales();
        return TEMPLATE;
    }

    @AuraEnabled
    public static ImportResult previewSalesDataCsv(String csvContent) {
        FieldBookAccess.assertCanAdministerSales();
        ImportResult result = new ImportResult();
        result.previewRows = parse(csvContent);
        result.rowsInserted = 0;
        result.rowsUpdated = 0;
        result.rowsFailed = countInvalid(result.previewRows);
        return result;
    }

    @AuraEnabled
    public static ImportResult importSalesDataCsv(String csvContent, String fileName) {
        FieldBookAccess.assertCanAdministerSales();
        List<PreviewRow> rows = parse(csvContent);
        ImportResult result = new ImportResult();
        result.previewRows = rows;
        result.rowsInserted = 0;
        result.rowsUpdated = 0;
        result.rowsFailed = 0;
        List<String> errors = new List<String>();

        Map<String, Account> pharmacies = loadPharmacies(rows);
        Map<String, Product2> products = loadProducts(rows);
        List<Pharmacy_Sales_Withdrawal__c> ready = new List<Pharmacy_Sales_Withdrawal__c>();
        List<String> keys = new List<String>();

        for (PreviewRow row : rows) {
            if (row.isValid != true) {
                result.rowsFailed++;
                errors.add('Row ' + row.rowNumber + ': ' + row.validationMessage);
                continue;
            }
            Account pharmacy = pharmacies.get(row.pharmacyExternalId);
            Product2 product = products.get(row.productExternalId);
            if (pharmacy == null) {
                result.rowsFailed++;
                errors.add('Row ' + row.rowNumber + ': pharmacy ' + row.pharmacyExternalId + ' was not found.');
                continue;
            }
            if (product == null) {
                result.rowsFailed++;
                errors.add('Row ' + row.rowNumber + ': product ' + row.productExternalId + ' was not found.');
                continue;
            }
            Date month = parseMonth(row.reportMonth);
            String key = row.dataSource + '|' + monthKey(month) + '|' + pharmacy.Id + '|' + product.Id;
            if (key.length() > 120) {
                key = key.substring(0, 120);
            }
            Pharmacy_Sales_Withdrawal__c withdrawal = new Pharmacy_Sales_Withdrawal__c(
                Unique_Key__c = key,
                Data_Source__c = row.dataSource,
                Report_Month__c = month,
                Pharmacy_Account__c = pharmacy.Id,
                Product2_Id__c = String.valueOf(product.Id),
                Product__c = product.Id,
                Quantity_Withdrawn__c = row.quantityWithdrawn
            );
            if (PharmacySalesFieldSupport.hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Unit_Price__c')) {
                // Unit price is optional on the CSV. Quantity is the required measure.
            }
            ready.add(withdrawal);
            keys.add(key);
        }

        Map<String, Id> existing = new Map<String, Id>();
        if (!keys.isEmpty()) {
            for (Pharmacy_Sales_Withdrawal__c current : [
                SELECT Id, Unique_Key__c
                FROM Pharmacy_Sales_Withdrawal__c
                WHERE Unique_Key__c IN :keys
                WITH SYSTEM_MODE
            ]) {
                existing.put(current.Unique_Key__c, current.Id);
            }
        }
        for (Pharmacy_Sales_Withdrawal__c withdrawal : ready) {
            if (existing.containsKey(withdrawal.Unique_Key__c)) {
                withdrawal.Id = existing.get(withdrawal.Unique_Key__c);
                result.rowsUpdated++;
            } else {
                result.rowsInserted++;
            }
        }
        if (!ready.isEmpty()) {
            Database.upsert(ready, false, AccessLevel.SYSTEM_MODE);
        }

        Sales_Data_Import_Batch__c batch = new Sales_Data_Import_Batch__c(
            File_Name__c = String.isBlank(fileName) ? 'sales.csv' : fileName.left(80),
            Status__c = result.rowsFailed > 0 && ready.isEmpty() ? 'Failed' : 'Completed',
            Rows_Inserted__c = result.rowsInserted,
            Rows_Updated__c = result.rowsUpdated,
            Rows_Failed__c = result.rowsFailed
        );
        insert as system batch;
        result.errorLog = errors.isEmpty() ? null : String.join(errors, '\n');
        return result;
    }

    @AuraEnabled
    public static List<WithdrawalRow> getWithdrawalRows(
        Date startMonth,
        Date endMonth,
        String dataSource,
        Id brickId,
        Integer rowLimit
    ) {
        FieldBookAccess.assertCanAdministerSales();
        Date startAt = startMonth == null ? Date.today().addMonths(-11).toStartOfMonth() : startMonth.toStartOfMonth();
        Date endAt = endMonth == null ? Date.today().toStartOfMonth().addMonths(1).addDays(-1) : endMonth;
        Integer lim = rowLimit == null || rowLimit < 1 ? 200 : Math.min(rowLimit, 500);
        PharmacySalesFieldSupport.BrickContext bricks = PharmacySalesFieldSupport.loadBrickContext();
        List<Pharmacy_Sales_Withdrawal__c> source = PharmacySalesFieldSupport.queryWithdrawals(
            startAt,
            endAt,
            dataSource,
            brickId,
            null,
            bricks
        );
        Set<Id> productIds = new Set<Id>();
        for (Pharmacy_Sales_Withdrawal__c row : source) {
            Id productId = parseId(row.Product2_Id__c);
            if (productId != null) {
                productIds.add(productId);
            }
        }
        Map<Id, Product2> products = productIds.isEmpty()
            ? new Map<Id, Product2>()
            : new Map<Id, Product2>([
                SELECT Id, Name FROM Product2 WHERE Id IN :productIds WITH SYSTEM_MODE
            ]);
        Map<Id, Decimal> prices = PharmacySalesFieldSupport.loadStandardPrices(productIds);
        List<WithdrawalRow> rows = new List<WithdrawalRow>();
        for (Pharmacy_Sales_Withdrawal__c row : source) {
            if (rows.size() >= lim) {
                break;
            }
            WithdrawalRow view = new WithdrawalRow();
            view.recordId = row.Id;
            view.reportMonth = row.Report_Month__c == null ? '' : String.valueOf(row.Report_Month__c);
            view.dataSource = row.Data_Source__c;
            view.pharmacyName = row.Pharmacy_Account__r == null ? '' : row.Pharmacy_Account__r.Name;
            view.brickName = PharmacySalesFieldSupport.resolveBrickName(row, bricks);
            Id productId = parseId(row.Product2_Id__c);
            view.productName = productId != null && products.containsKey(productId) ? products.get(productId).Name : '';
            view.quantity = row.Quantity_Withdrawn__c;
            view.revenue = PharmacySalesFieldSupport.resolveRevenue(row, prices);
            rows.add(view);
        }
        return rows;
    }

    @AuraEnabled
    public static List<BatchRow> getImportBatches(Integer rowLimit) {
        FieldBookAccess.assertCanAdministerSales();
        Integer lim = rowLimit == null || rowLimit < 1 ? 20 : Math.min(rowLimit, 100);
        List<BatchRow> rows = new List<BatchRow>();
        for (Sales_Data_Import_Batch__c batch : [
            SELECT Id, File_Name__c, Rows_Inserted__c, Rows_Updated__c, Rows_Failed__c
            FROM Sales_Data_Import_Batch__c
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT :lim
        ]) {
            BatchRow view = new BatchRow();
            view.batchId = batch.Id;
            view.fileName = batch.File_Name__c;
            view.rowsInserted = batch.Rows_Inserted__c == null ? 0 : Integer.valueOf(batch.Rows_Inserted__c);
            view.rowsUpdated = batch.Rows_Updated__c == null ? 0 : Integer.valueOf(batch.Rows_Updated__c);
            view.rowsFailed = batch.Rows_Failed__c == null ? 0 : Integer.valueOf(batch.Rows_Failed__c);
            rows.add(view);
        }
        return rows;
    }

    @AuraEnabled
    public static void deleteWithdrawalRows(List<Id> recordIds) {
        FieldBookAccess.assertCanAdministerSales();
        if (recordIds == null || recordIds.isEmpty()) {
            return;
        }
        delete as system [
            SELECT Id FROM Pharmacy_Sales_Withdrawal__c WHERE Id IN :recordIds WITH SYSTEM_MODE
        ];
    }

    @AuraEnabled
    public static SeedResult seedDemoData() {
        FieldBookAccess.assertCanAdministerSales();
        Account pharmacy = new Account(Name = 'Demo Pharmacy SOB', External_ID__c = 'DEMO-PHARM-SOB');
        Database.upsert(pharmacy, Account.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        Product2 product = new Product2(
            Name = 'Demo SOB Product',
            ProductCode = 'DEMO-SOB',
            External_ID__c = 'DEMO-PROD-SOB',
            IsActive = true,
            Family = 'GIT'
        );
        Database.upsert(product, Product2.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        Date month = Date.today().toStartOfMonth();
        Pharmacy_Sales_Withdrawal__c withdrawal = new Pharmacy_Sales_Withdrawal__c(
            Unique_Key__c = 'Direct|' + monthKey(month) + '|' + pharmacy.Id + '|' + product.Id,
            Data_Source__c = 'Direct',
            Report_Month__c = month,
            Pharmacy_Account__c = pharmacy.Id,
            Product2_Id__c = String.valueOf(product.Id),
            Quantity_Withdrawn__c = 8,
            Unit_Price__c = 10
        );
        Database.upsert(withdrawal, Pharmacy_Sales_Withdrawal__c.Unique_Key__c, false, AccessLevel.SYSTEM_MODE);
        SeedResult result = new SeedResult();
        result.message = 'Demo pharmacy, product, and one withdrawal are ready for ' + String.valueOf(month) + '.';
        return result;
    }

    @AuraEnabled
    public static SalesDigestionExampleService.DigestionExample seedDigestionExample() {
        return SalesDigestionExampleService.seedExample();
    }

    @AuraEnabled
    public static SalesDigestionExampleService.DigestionExample getDigestionExample() {
        return SalesDigestionExampleService.getExample();
    }

    private static List<PreviewRow> parse(String csvContent) {
        List<PreviewRow> rows = new List<PreviewRow>();
        if (String.isBlank(csvContent)) {
            return rows;
        }
        List<String> lines = csvContent.replace('\r\n', '\n').replace('\r', '\n').split('\n');
        Integer rowNumber = 0;
        for (Integer i = 0; i < lines.size(); i++) {
            String line = lines[i] == null ? '' : lines[i].trim();
            if (String.isBlank(line)) {
                continue;
            }
            if (i == 0 && line.toLowerCase().startsWith('data_source')) {
                continue;
            }
            rowNumber++;
            List<String> cells = splitCsv(line);
            PreviewRow row = new PreviewRow();
            row.rowNumber = rowNumber;
            row.dataSource = cell(cells, 0);
            row.reportMonth = cell(cells, 1);
            row.pharmacyExternalId = cell(cells, 2);
            row.productExternalId = cell(cells, 3);
            row.quantityWithdrawn = parseDecimal(cell(cells, 4));
            row.isValid = true;
            List<String> problems = new List<String>();
            if (!SOURCES.contains(row.dataSource)) {
                problems.add('unknown data source');
            }
            if (parseMonth(row.reportMonth) == null) {
                problems.add('month must be YYYY-MM');
            }
            if (String.isBlank(row.pharmacyExternalId) || String.isBlank(row.productExternalId)) {
                problems.add('pharmacy and product external ids are required');
            }
            if (row.quantityWithdrawn == null || row.quantityWithdrawn < 0) {
                problems.add('quantity is required');
            }
            if (!problems.isEmpty()) {
                row.isValid = false;
                row.validationMessage = String.join(problems, '; ');
            }
            if (rows.size() < 50) {
                rows.add(row);
            }
        }
        return rows;
    }

    private static Map<String, Account> loadPharmacies(List<PreviewRow> rows) {
        Set<String> keys = new Set<String>();
        for (PreviewRow row : rows) {
            if (row.isValid == true && String.isNotBlank(row.pharmacyExternalId)) {
                keys.add(row.pharmacyExternalId);
            }
        }
        Map<String, Account> byKey = new Map<String, Account>();
        if (keys.isEmpty()) {
            return byKey;
        }
        for (Account pharmacy : [
            SELECT Id, External_ID__c
            FROM Account
            WHERE External_ID__c IN :keys
            WITH SYSTEM_MODE
        ]) {
            byKey.put(pharmacy.External_ID__c, pharmacy);
        }
        return byKey;
    }

    private static Map<String, Product2> loadProducts(List<PreviewRow> rows) {
        Set<String> keys = new Set<String>();
        for (PreviewRow row : rows) {
            if (row.isValid == true && String.isNotBlank(row.productExternalId)) {
                keys.add(row.productExternalId);
            }
        }
        Map<String, Product2> byKey = new Map<String, Product2>();
        if (keys.isEmpty()) {
            return byKey;
        }
        for (Product2 product : [
            SELECT Id, External_ID__c
            FROM Product2
            WHERE External_ID__c IN :keys
            WITH SYSTEM_MODE
        ]) {
            byKey.put(product.External_ID__c, product);
        }
        return byKey;
    }

    private static Integer countInvalid(List<PreviewRow> rows) {
        Integer failed = 0;
        for (PreviewRow row : rows) {
            if (row.isValid != true) {
                failed++;
            }
        }
        return failed;
    }

    private static List<String> splitCsv(String line) {
        List<String> cells = new List<String>();
        String current = '';
        Boolean quoted = false;
        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            if (ch == '"') {
                quoted = !quoted;
            } else if (ch == ',' && !quoted) {
                cells.add(current.trim());
                current = '';
            } else {
                current += ch;
            }
        }
        cells.add(current.trim());
        return cells;
    }

    private static String cell(List<String> cells, Integer index) {
        return cells.size() > index && cells[index] != null ? cells[index].trim() : '';
    }

    private static Decimal parseDecimal(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            return Decimal.valueOf(raw);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Date parseMonth(String raw) {
        if (String.isBlank(raw) || raw.length() < 7) {
            return null;
        }
        try {
            Integer year = Integer.valueOf(raw.substring(0, 4));
            Integer month = Integer.valueOf(raw.substring(5, 7));
            return Date.newInstance(year, month, 1);
        } catch (Exception ex) {
            return null;
        }
    }

    private static String monthKey(Date value) {
        return String.valueOf(value.year()) + '-' + String.valueOf(value.month()).leftPad(2, '0');
    }

    private static Id parseId(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            return (Id) raw;
        } catch (Exception ex) {
            return null;
        }
    }
}
