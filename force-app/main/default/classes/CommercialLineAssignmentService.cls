/**
 * Applies the October product-line list from ZetaProductListSeed.
 * Only the packs named for GIT-SALES, NEUROSCIENCE-I, and NEUROSCIENCE-II are updated.
 */
public without sharing class CommercialLineAssignmentService {
    private static final String RESOURCE_ZETA = 'ZetaProductListSeed';
    private static final Set<String> REALIGNED_PRODUCT_CODES = new Set<String>{
        'DU60', 'ZX10', 'ZX20', 'ZX25', 'ZX40', 'ZX50',
        'VOT5', 'VOT10', 'VOT15', 'VOT20',
        'EP100', 'EPS5',
        'N2014', 'N40',
        'NP20', 'NP40', 'NPC2014', 'NPC4014',
        'V1014', 'V2014',
        'M01', 'MH100',
        'B110', 'B1',
        'PR1', 'PR2',
        'UB56'
    };

    public class Result {
        @AuraEnabled public Integer productsUpdated;
        @AuraEnabled public Integer missingCodes;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static Result applyRealignedSalesLines() {
        Map<String, String> lineByCode = linesFromSeed();
        Result result = new Result();
        result.productsUpdated = 0;
        result.missingCodes = 0;
        if (lineByCode.isEmpty()) {
            result.message = 'No realigned product rows were found in the product list.';
            return result;
        }
        List<Product2> products = [
            SELECT Id, ProductCode, Sales_Line__c
            FROM Product2
            WHERE ProductCode IN :lineByCode.keySet()
            WITH SYSTEM_MODE
        ];
        List<Product2> updates = new List<Product2>();
        Set<String> found = new Set<String>();
        for (Product2 product : products) {
            if (String.isBlank(product.ProductCode)) {
                continue;
            }
            String code = product.ProductCode.trim().toUpperCase();
            found.add(code);
            String lineName = lineByCode.get(code);
            if (lineName != null && product.Sales_Line__c != lineName) {
                product.Sales_Line__c = lineName;
                updates.add(product);
            }
        }
        if (!updates.isEmpty()) {
            update as system updates;
        }
        result.productsUpdated = updates.size();
        Integer missing = lineByCode.size() - found.size();
        result.missingCodes = missing < 0 ? 0 : missing;
        result.message =
            'Updated ' +
            result.productsUpdated +
            ' products. ' +
            result.missingCodes +
            ' codes from the list are not in the catalog yet.';
        return result;
    }

    @TestVisible
    private static Map<String, String> linesFromSeed() {
        Map<String, String> lineByCode = new Map<String, String>();
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = :RESOURCE_ZETA
            LIMIT 1
        ];
        if (resources.isEmpty() || resources[0].Body == null) {
            return lineByCode;
        }
        List<String> lines = resources[0].Body.toString().split('\\r?\\n');
        if (lines.size() < 2) {
            return lineByCode;
        }
        for (Integer i = 1; i < lines.size(); i++) {
            List<String> cols = parseCsvLine(lines[i]);
            if (cols.size() < 5) {
                continue;
            }
            String code = cols[4] == null ? '' : cols[4].trim().toUpperCase();
            String lineName = cols[1] == null ? '' : cols[1].trim();
            if (REALIGNED_PRODUCT_CODES.contains(code) && String.isNotBlank(lineName)) {
                lineByCode.put(code, lineName);
            }
        }
        return lineByCode;
    }

    private static List<String> parseCsvLine(String line) {
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
