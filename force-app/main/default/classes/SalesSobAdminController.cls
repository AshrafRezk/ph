/**
 * Super-admin editor for share of business.
 * Default covers the sales module. Item covers one product.
 * Pharmacy mapping is intentionally not handled here.
 */
public with sharing class SalesSobAdminController {
    public class SobItem {
        @AuraEnabled public Id id;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal percent;
    }

    public class EditorState {
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public Decimal defaultPercent;
        @AuraEnabled public List<SobItem> items;
        @AuraEnabled public String note;
    }

    public class ProductOption {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
    }

    @AuraEnabled(cacheable=false)
    public static EditorState getEditorState() {
        EditorState state = new EditorState();
        state.canEdit = FieldBookAccess.canAdministerSales();
        state.note = 'Pharmacy mapping is a later step. This screen sets the module SOB and the SOB for one product.';
        state.items = new List<SobItem>();
        for (Sales_SOB_Target__c row : [
            SELECT Id, Scope__c, SOB_Percent__c, Product__c, Product__r.Name
            FROM Sales_SOB_Target__c
            WITH SYSTEM_MODE
            ORDER BY Scope__c, Product__r.Name
        ]) {
            if (row.Scope__c == 'Default') {
                state.defaultPercent = row.SOB_Percent__c;
                continue;
            }
            SobItem item = new SobItem();
            item.id = row.Id;
            item.productId = row.Product__c;
            item.productName = row.Product__r == null ? null : row.Product__r.Name;
            item.percent = row.SOB_Percent__c;
            state.items.add(item);
        }
        return state;
    }

    @AuraEnabled
    public static EditorState saveDefaultSob(Decimal percent) {
        FieldBookAccess.assertCanAdministerSales();
        assertPercent(percent);
        upsertTarget('DEFAULT', 'Default', null, percent);
        return getEditorState();
    }

    @AuraEnabled
    public static EditorState saveItemSob(Id productId, Decimal percent) {
        FieldBookAccess.assertCanAdministerSales();
        if (productId == null) {
            throw new AuraHandledException('Choose a product.');
        }
        assertPercent(percent);
        upsertTarget('ITEM:' + String.valueOf(productId), 'Item', productId, percent);
        return getEditorState();
    }

    @AuraEnabled
    public static EditorState clearItemSob(Id productId) {
        FieldBookAccess.assertCanAdministerSales();
        if (productId == null) {
            throw new AuraHandledException('Choose a product.');
        }
        List<Sales_SOB_Target__c> rows = [
            SELECT Id
            FROM Sales_SOB_Target__c
            WHERE Unique_Key__c = :('ITEM:' + String.valueOf(productId))
            WITH SYSTEM_MODE
        ];
        if (!rows.isEmpty()) {
            delete as system rows;
        }
        return getEditorState();
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductOption> searchProducts(String term) {
        String likeTerm = String.isBlank(term) ? '%' : '%' + term.trim() + '%';
        List<ProductOption> options = new List<ProductOption>();
        for (Product2 product : [
            SELECT Id, Name, ProductCode
            FROM Product2
            WHERE IsActive = TRUE AND (Name LIKE :likeTerm OR ProductCode LIKE :likeTerm)
            WITH USER_MODE
            ORDER BY Name
            LIMIT 30
        ]) {
            ProductOption option = new ProductOption();
            option.productId = product.Id;
            option.productName = product.Name;
            option.productCode = product.ProductCode;
            options.add(option);
        }
        return options;
    }

    private static void upsertTarget(String uniqueKey, String scope, Id productId, Decimal percent) {
        List<Sales_SOB_Target__c> existing = [
            SELECT Id
            FROM Sales_SOB_Target__c
            WHERE Unique_Key__c = :uniqueKey
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Sales_SOB_Target__c row = existing.isEmpty()
            ? new Sales_SOB_Target__c(Unique_Key__c = uniqueKey)
            : existing[0];
        row.Scope__c = scope;
        row.Product__c = productId;
        row.SOB_Percent__c = percent;
        if (row.Id == null) {
            insert as system row;
        } else {
            update as system row;
        }
    }

    private static void assertPercent(Decimal percent) {
        if (percent == null || percent < 0 || percent > 100) {
            throw new AuraHandledException('SOB percent must be between 0 and 100.');
        }
    }
}
