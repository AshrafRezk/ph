/**
 * Loads Product2 catalog rows from Pharma_Onboarding_Data_Collection_Template CSV
 * (or legacy ZetaProductListSeed columns). Upserts on External_ID__c and builds
 * Brand → Detail hierarchy; optional Sample / Brand Reminder rows from template.
 */
public with sharing class PharmaProductOnboardingService {
    public class SeedResult {
        @AuraEnabled public Integer brandsUpserted;
        @AuraEnabled public Integer productsUpserted;
        @AuraEnabled public Integer skippedRows;
        @AuraEnabled public String message;
    }

    private static final String BRAND_PREFIX = 'BRAND_';
    private static final String RESOURCE_PHARMA = 'Pharma_Onboarding_Data_Collection_Template';
    private static final String RESOURCE_ZETA = 'ZetaProductListSeed';

    @AuraEnabled
    public static SeedResult seedFromStaticResource() {
        List<String> lines = readStaticResourceLines(RESOURCE_PHARMA);
        if (lines.isEmpty()) {
            lines = readStaticResourceLines(RESOURCE_ZETA);
        }
        if (lines.isEmpty()) {
            SeedResult empty = new SeedResult();
            empty.brandsUpserted = 0;
            empty.productsUpserted = 0;
            empty.skippedRows = 0;
            empty.message = 'No onboarding CSV static resource found.';
            return empty;
        }
        return importCsvLines(lines);
    }

    @AuraEnabled
    public static SeedResult seedFromCsv(String csvContent) {
        if (String.isBlank(csvContent)) {
            throw new AuraHandledException('CSV content is required.');
        }
        List<String> lines = new List<String>();
        for (String line : csvContent.split('\\r?\\n')) {
            if (String.isNotBlank(line)) {
                lines.add(line);
            }
        }
        return importCsvLines(lines);
    }

    private static SeedResult importCsvLines(List<String> lines) {
        SeedResult result = new SeedResult();
        result.skippedRows = 0;
        if (lines.isEmpty()) {
            result.brandsUpserted = 0;
            result.productsUpserted = 0;
            result.message = 'No data rows.';
            return result;
        }

        List<String> headerCols = parseCsvLine(lines[0]);
        Map<String, Integer> columnIndex = buildColumnIndex(headerCols);
        Boolean extendedFormat = columnIndex.containsKey('product_type');

        Set<String> primaryBrands = new Set<String>();
        List<List<String>> dataRows = new List<List<String>>();
        for (Integer i = 1; i < lines.size(); i++) {
            List<String> cols = parseCsvLine(lines[i]);
            if (cols.isEmpty()) {
                continue;
            }
            String primaryBrand = valueAt(cols, columnIndex, extendedFormat, 'primary_brand', 2);
            if (String.isNotBlank(primaryBrand)) {
                primaryBrands.add(primaryBrand.trim());
            }
            dataRows.add(cols);
        }

        List<Product2> brands = new List<Product2>();
        for (String primaryBrand : primaryBrands) {
            brands.add(buildBrandProduct(primaryBrand));
        }
        Integer brandOk = 0;
        if (!brands.isEmpty()) {
            Database.UpsertResult[] brandResults = Database.upsert(
                brands,
                Product2.External_ID__c,
                false,
                AccessLevel.SYSTEM_MODE
            );
            for (Database.UpsertResult ur : brandResults) {
                if (ur.isSuccess()) {
                    brandOk++;
                }
            }
        }
        result.brandsUpserted = brandOk;

        Map<String, Id> idByExternal = loadProductsByExternalId();
        List<Product2> detailProducts = new List<Product2>();
        List<Product2> childProducts = new List<Product2>();
        Map<String, String> parentExternalByChildExternal = new Map<String, String>();
        for (List<String> cols : dataRows) {
            String productType = resolveProductType(cols, columnIndex, extendedFormat);
            if (productType == 'Brand') {
                continue;
            }
            Product2 rowProduct = rowToProduct(cols, columnIndex, extendedFormat, idByExternal);
            if (rowProduct == null) {
                result.skippedRows++;
                continue;
            }
            if (rowProduct.Product_Type__c == 'Detail') {
                detailProducts.add(rowProduct);
            } else if (
                rowProduct.Product_Type__c == 'Sample'
                || rowProduct.Product_Type__c == 'Brand Reminder'
            ) {
                String parentExternal = resolveParentExternal(cols, columnIndex, extendedFormat, productType);
                parentExternalByChildExternal.put(rowProduct.External_ID__c, parentExternal);
                childProducts.add(rowProduct);
            } else {
                result.skippedRows++;
            }
        }

        Integer productOk = upsertProducts(detailProducts, result);
        idByExternal = loadProductsByExternalId();
        rebindChildParents(childProducts, parentExternalByChildExternal, idByExternal);
        productOk += upsertProducts(childProducts, result);
        result.productsUpserted = productOk;
        result.message =
            'Brands upserted: '
            + result.brandsUpserted
            + '; products upserted: '
            + result.productsUpserted
            + '; skipped: '
            + result.skippedRows;
        return result;
    }

    private static Integer upsertProducts(List<Product2> products, SeedResult result) {
        if (products == null || products.isEmpty()) {
            return 0;
        }
        Integer ok = 0;
        Database.UpsertResult[] productResults = Database.upsert(
            products,
            Product2.External_ID__c,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Database.UpsertResult ur : productResults) {
            if (ur.isSuccess()) {
                ok++;
            } else {
                result.skippedRows++;
            }
        }
        return ok;
    }

    private static void rebindChildParents(
        List<Product2> childProducts,
        Map<String, String> parentExternalByChildExternal,
        Map<String, Id> idByExternal
    ) {
        for (Product2 child : childProducts) {
            String parentExternal = parentExternalByChildExternal.get(child.External_ID__c);
            child.Parent_Product__c = resolveExternalId(parentExternal, idByExternal);
        }
    }

    private static Id resolveExternalId(String externalKey, Map<String, Id> idByExternal) {
        if (String.isBlank(externalKey) || idByExternal == null) {
            return null;
        }
        if (idByExternal.containsKey(externalKey)) {
            return idByExternal.get(externalKey);
        }
        return idByExternal.get(externalKey.toUpperCase());
    }

    private static String resolveProductType(
        List<String> cols,
        Map<String, Integer> columnIndex,
        Boolean extendedFormat
    ) {
        String productType = valueAt(cols, columnIndex, extendedFormat, 'product_type', null);
        if (String.isBlank(productType)) {
            return 'Detail';
        }
        return productType.trim();
    }

    private static String resolveParentExternal(
        List<String> cols,
        Map<String, Integer> columnIndex,
        Boolean extendedFormat,
        String productType
    ) {
        String parentExternal = valueAt(cols, columnIndex, extendedFormat, 'parent_external_id', null);
        if (String.isBlank(parentExternal)) {
            String primaryBrand = valueAt(cols, columnIndex, extendedFormat, 'primary_brand', 2);
            if (productType == 'Detail' && String.isNotBlank(primaryBrand)) {
                parentExternal = brandExternalId(primaryBrand);
            }
        }
        return parentExternal;
    }

    private static Product2 rowToProduct(
        List<String> cols,
        Map<String, Integer> columnIndex,
        Boolean extendedFormat,
        Map<String, Id> idByExternal
    ) {
        String productType = valueAt(cols, columnIndex, extendedFormat, 'product_type', null);
        if (String.isBlank(productType)) {
            productType = 'Detail';
        }
        productType = productType.trim();
        if (productType.equalsIgnoreCase('Brand')) {
            return null;
        }

        String zetaCode = valueAt(cols, columnIndex, extendedFormat, 'zeta_code', 4);
        if (String.isBlank(zetaCode)) {
            return null;
        }
        zetaCode = zetaCode.trim();
        if (zetaCode.equalsIgnoreCase('Zeta_Code') || zetaCode.equalsIgnoreCase('Zeta Code')) {
            return null;
        }

        String mendixId = valueAt(cols, columnIndex, extendedFormat, 'mendix_external_id', null);
        String externalId = String.isNotBlank(mendixId) ? mendixId.trim() : zetaCode;

        String name = valueAt(cols, columnIndex, extendedFormat, 'zeta_name', 5);
        if (String.isBlank(name)) {
            name = zetaCode;
        }

        String primaryBrand = valueAt(cols, columnIndex, extendedFormat, 'primary_brand', 2);
        String parentExternal = valueAt(cols, columnIndex, extendedFormat, 'parent_external_id', null);
        if (String.isBlank(parentExternal) && String.isNotBlank(primaryBrand)) {
            parentExternal = brandExternalId(primaryBrand);
        }
        if (productType == 'Detail' && String.isBlank(parentExternal)) {
            return null;
        }
        if ((productType == 'Sample' || productType == 'Brand Reminder') && String.isBlank(parentExternal)) {
            return null;
        }

        Id parentId = resolveExternalId(parentExternal, idByExternal);

        Product2 product = new Product2();
        product.External_ID__c = externalId;
        product.ProductCode = zetaCode;
        product.Name = name.trim();
        product.Product_Type__c = productType;
        product.Primary_Brand__c = primaryBrand;
        product.Sales_Unit__c = valueAt(cols, columnIndex, extendedFormat, 'unit', 0);
        product.Sales_Line__c = valueAt(cols, columnIndex, extendedFormat, 'line', 1);
        product.Mirror_Line__c = valueAt(cols, columnIndex, extendedFormat, 'mirror_line', null);
        product.Strength__c = valueAt(cols, columnIndex, extendedFormat, 'strength', 6);
        product.Form__c = valueAt(cols, columnIndex, extendedFormat, 'form', 7);
        product.Unit_of_Measure__c = valueAt(cols, columnIndex, extendedFormat, 'unit_of_measure', 8);
        product.Quantity_Per_Unit__c = parseDecimal(valueAt(cols, columnIndex, extendedFormat, 'quantity_per_unit', 9));
        product.Box_Quantity__c = parseDecimal(valueAt(cols, columnIndex, extendedFormat, 'box_quantity', 10));
        product.Brand_Reminder_Kind__c = valueAt(
            cols,
            columnIndex,
            extendedFormat,
            'brand_reminder_kind',
            null
        );
        String activeRaw = valueAt(cols, columnIndex, extendedFormat, 'is_active', 11);
        product.IsActive = String.isBlank(activeRaw) || activeRaw.equalsIgnoreCase('Yes') || activeRaw == '1';

        if (productType != 'Brand') {
            product.Parent_Product__c = parentId;
        }

        return product;
    }

    private static Product2 buildBrandProduct(String primaryBrand) {
        String trimmed = primaryBrand.trim();
        Product2 brand = new Product2();
        brand.Name = trimmed;
        brand.Product_Type__c = 'Brand';
        brand.Primary_Brand__c = trimmed;
        brand.External_ID__c = brandExternalId(trimmed);
        brand.ProductCode = brand.External_ID__c;
        brand.IsActive = true;
        return brand;
    }

    @TestVisible
    static String brandExternalId(String primaryBrand) {
        String normalized = primaryBrand == null ? '' : primaryBrand.trim().toUpperCase();
        normalized = normalized.replaceAll('[^A-Z0-9]+', '_');
        normalized = normalized.replaceAll('^_+|_+$', '');
        return BRAND_PREFIX + normalized;
    }

    private static Map<String, Id> loadProductsByExternalId() {
        Map<String, Id> byExternal = new Map<String, Id>();
        for (Product2 product : [
            SELECT Id, External_ID__c
            FROM Product2
            WHERE External_ID__c != NULL
            WITH SYSTEM_MODE
            LIMIT 50000
        ]) {
            byExternal.put(product.External_ID__c, product.Id);
            byExternal.put(product.External_ID__c.toUpperCase(), product.Id);
        }
        return byExternal;
    }

    private static Map<String, Integer> buildColumnIndex(List<String> headerCols) {
        Map<String, Integer> index = new Map<String, Integer>();
        for (Integer i = 0; i < headerCols.size(); i++) {
            String key = normalizeHeaderKey(headerCols[i]);
            if (String.isNotBlank(key)) {
                index.put(key, i);
            }
        }
        return index;
    }

    private static String normalizeHeaderKey(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        return raw.trim().toLowerCase().replaceAll('[\\s\\-]+', '_');
    }

    private static String valueAt(
        List<String> cols,
        Map<String, Integer> columnIndex,
        Boolean extendedFormat,
        String headerKey,
        Integer legacyIndex
    ) {
        if (extendedFormat && columnIndex.containsKey(headerKey)) {
            Integer idx = columnIndex.get(headerKey);
            return idx != null && idx < cols.size() ? cols[idx] : null;
        }
        if (legacyIndex != null && legacyIndex < cols.size()) {
            return cols[legacyIndex];
        }
        if (columnIndex.containsKey(headerKey)) {
            Integer idx = columnIndex.get(headerKey);
            return idx != null && idx < cols.size() ? cols[idx] : null;
        }
        return null;
    }

    private static Decimal parseDecimal(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            return Decimal.valueOf(raw.trim());
        } catch (Exception ex) {
            return null;
        }
    }

    private static List<String> readStaticResourceLines(String resourceName) {
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = :resourceName
            LIMIT 1
        ];
        if (resources.isEmpty() || resources[0].Body == null) {
            return new List<String>();
        }
        List<String> lines = new List<String>();
        for (String line : resources[0].Body.toString().split('\\r?\\n')) {
            if (String.isNotBlank(line)) {
                lines.add(line);
            }
        }
        return lines;
    }

    @TestVisible
    static List<String> parseCsvLine(String line) {
        List<String> result = new List<String>();
        if (line == null) {
            return result;
        }
        Boolean inQuotes = false;
        String current = '';
        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            if (ch == '"') {
                inQuotes = !inQuotes;
            } else if (ch == ',' && !inQuotes) {
                result.add(current);
                current = '';
            } else {
                current += ch;
            }
        }
        result.add(current);
        return result;
    }
}