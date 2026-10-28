/**
 * Add and edit Product2 rows from Admin Console → Products Manager.
 * Catalog shape: Brand → Detail → Sample / Brand Reminder, linked by Parent_Product__c.
 * Product code and external id are fixed after creation: sales imports and distributor
 * product mapping match on them. Products are deactivated, never deleted.
 */
public with sharing class ProductEditorController {
    @TestVisible static final Set<String> TYPES = new Set<String>{ 'Brand', 'Detail', 'Sample', 'Brand Reminder' };
    /** Which parent types each product type may sit under (empty = top level). */
    @TestVisible static final Map<String, Set<String>> ALLOWED_PARENTS = new Map<String, Set<String>>{
        'Brand' => new Set<String>(),
        'Detail' => new Set<String>{ 'Brand' },
        'Sample' => new Set<String>{ 'Brand', 'Detail' },
        'Brand Reminder' => new Set<String>{ 'Brand', 'Detail' }
    };

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String productType;

        Option(String label, String value, String productType) {
            this.label = label;
            this.value = value;
            this.productType = productType;
        }
    }

    public class EditorOptions {
        @AuraEnabled public List<Option> productTypes = new List<Option>();
        @AuraEnabled public List<Option> parents = new List<Option>();
        @AuraEnabled public List<Option> salesLines = new List<Option>();
        @AuraEnabled public List<Option> reminderKinds = new List<Option>();
    }

    public class ProductForm {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String productType { get; set; }
        @AuraEnabled public Id parentId { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public String externalId { get; set; }
        @AuraEnabled public String salesLine { get; set; }
        @AuraEnabled public String therapyArea { get; set; }
        @AuraEnabled public String strength { get; set; }
        @AuraEnabled public String form { get; set; }
        @AuraEnabled public String salesUnit { get; set; }
        @AuraEnabled public Decimal boxQuantity { get; set; }
        @AuraEnabled public String reminderKind { get; set; }
        @AuraEnabled public String imageUrl { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Decimal publicPrice { get; set; }
        @AuraEnabled public Boolean showInHcpApp { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
    }

    @AuraEnabled
    public static EditorOptions getEditorOptions() {
        EditorOptions options = new EditorOptions();
        for (Schema.PicklistEntry entry : Product2.Product_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && TYPES.contains(entry.getValue())) {
                options.productTypes.add(new Option(entry.getLabel(), entry.getValue(), null));
            }
        }
        for (Schema.PicklistEntry entry : Product2.Brand_Reminder_Kind__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.reminderKinds.add(new Option(entry.getLabel(), entry.getValue(), null));
            }
        }
        for (Product2 parent : [
            SELECT Id, Name, Product_Type__c
            FROM Product2
            WHERE IsActive = TRUE AND Product_Type__c IN ('Brand', 'Detail')
            WITH USER_MODE
            ORDER BY Name ASC
        ]) {
            options.parents.add(new Option(parent.Name, parent.Id, parent.Product_Type__c));
        }
        for (AggregateResult row : [
            SELECT Sales_Line__c line
            FROM Product2
            WHERE Sales_Line__c != NULL
            WITH USER_MODE
            GROUP BY Sales_Line__c
            ORDER BY Sales_Line__c ASC
        ]) {
            String line = (String) row.get('line');
            options.salesLines.add(new Option(line, line, null));
        }
        return options;
    }

    @AuraEnabled
    public static ProductForm getProduct(Id productId) {
        if (productId == null) {
            throw new AuraHandledException('Choose a product.');
        }
        List<Product2> rows = [
            SELECT Id, Name, Product_Type__c, Parent_Product__c, ProductCode, External_ID__c, Sales_Line__c,
                Therapy_Area__c, Strength__c, Form__c, Sales_Unit__c, Box_Quantity__c, Brand_Reminder_Kind__c,
                Product_Image_URL__c, Description, Show_In_HCP_App__c, IsActive
            FROM Product2
            WHERE Id = :productId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Product not found.');
        }
        Product2 p = rows[0];
        ProductForm form = new ProductForm();
        form.id = p.Id;
        form.name = p.Name;
        form.productType = p.Product_Type__c;
        form.parentId = p.Parent_Product__c;
        form.productCode = p.ProductCode;
        form.externalId = p.External_ID__c;
        form.salesLine = p.Sales_Line__c;
        form.therapyArea = p.Therapy_Area__c;
        form.strength = p.Strength__c;
        form.form = p.Form__c;
        form.salesUnit = p.Sales_Unit__c;
        form.boxQuantity = p.Box_Quantity__c;
        form.reminderKind = p.Brand_Reminder_Kind__c;
        form.imageUrl = p.Product_Image_URL__c;
        form.description = p.Description;
        form.showInHcpApp = p.Show_In_HCP_App__c;
        form.isActive = p.IsActive;
        Id standardId = standardPricebookId();
        List<PricebookEntry> prices = [
            SELECT UnitPrice
            FROM PricebookEntry
            WHERE Product2Id = :p.Id AND Pricebook2Id = :standardId
            WITH USER_MODE
            LIMIT 1
        ];
        form.publicPrice = prices.isEmpty() ? null : prices[0].UnitPrice;
        return form;
    }

    /** Creates or updates the product (and its standard public price). Returns the product id. */
    @AuraEnabled
    public static Id saveProduct(ProductForm form) {
        if (form == null) {
            throw new AuraHandledException('Nothing to save.');
        }
        String name = trimmed(form.name);
        String productType = trimmed(form.productType);
        if (String.isBlank(name)) {
            throw new AuraHandledException('Enter the product name.');
        }
        if (!TYPES.contains(productType)) {
            throw new AuraHandledException('Choose a product type: Brand, Detail, Sample or Brand Reminder.');
        }
        if (form.boxQuantity != null && form.boxQuantity < 0) {
            throw new AuraHandledException('Box quantity cannot be negative.');
        }
        if (form.publicPrice != null && form.publicPrice < 0) {
            throw new AuraHandledException('Public price cannot be negative.');
        }

        Product2 parent = loadParent(form.parentId, productType, form.id);
        Boolean isNew = form.id == null;
        Product2 product = isNew ? new Product2() : loadExisting(form.id);

        if (isNew) {
            String code = trimmed(form.productCode);
            if (String.isBlank(code)) {
                throw new AuraHandledException('Enter the product code.');
            }
            String externalId = String.isBlank(form.externalId) ? code : trimmed(form.externalId);
            assertCodesFree(code, externalId);
            product.ProductCode = code;
            product.External_ID__c = externalId;
        }

        product.Name = name;
        product.Product_Type__c = productType;
        product.Parent_Product__c = parent == null ? null : parent.Id;
        product.Primary_Brand__c = primaryBrand(product, parent, name, productType);
        product.Sales_Line__c = trimmed(form.salesLine);
        product.Therapy_Area__c = trimmed(form.therapyArea);
        product.Strength__c = trimmed(form.strength);
        product.Form__c = trimmed(form.form);
        product.Sales_Unit__c = trimmed(form.salesUnit);
        product.Box_Quantity__c = form.boxQuantity;
        product.Brand_Reminder_Kind__c = productType == 'Brand Reminder' ? trimmed(form.reminderKind) : null;
        product.Product_Image_URL__c = trimmed(form.imageUrl);
        product.Description = trimmed(form.description);
        product.Show_In_HCP_App__c = form.showInHcpApp == true;
        product.IsActive = form.isActive != false;

        try {
            if (isNew) {
                insert as user product;
            } else {
                update as user product;
            }
            savePublicPrice(product.Id, form.publicPrice);
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
        return product.Id;
    }

    private static Product2 loadExisting(Id productId) {
        List<Product2> rows = [
            SELECT Id, ProductCode, External_ID__c, Primary_Brand__c
            FROM Product2
            WHERE Id = :productId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Product not found. Refresh and try again.');
        }
        return rows[0];
    }

    private static Product2 loadParent(Id parentId, String productType, Id selfId) {
        Set<String> allowed = ALLOWED_PARENTS.get(productType);
        if (parentId == null) {
            if (!allowed.isEmpty()) {
                throw new AuraHandledException('Choose the ' + String.join(new List<String>(allowed), ' or ') + ' this ' + productType + ' belongs to.');
            }
            return null;
        }
        if (allowed.isEmpty()) {
            throw new AuraHandledException('A Brand is top level and has no parent.');
        }
        if (parentId == selfId) {
            throw new AuraHandledException('A product cannot be its own parent.');
        }
        List<Product2> rows = [
            SELECT Id, Name, Product_Type__c, Primary_Brand__c
            FROM Product2
            WHERE Id = :parentId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty() || !allowed.contains(rows[0].Product_Type__c)) {
            throw new AuraHandledException('A ' + productType + ' must sit under a ' + String.join(new List<String>(allowed), ' or ') + '.');
        }
        return rows[0];
    }

    private static void assertCodesFree(String code, String externalId) {
        List<Product2> clashes = [
            SELECT Name, ProductCode, External_ID__c
            FROM Product2
            WHERE ProductCode = :code OR External_ID__c = :externalId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!clashes.isEmpty()) {
            throw new AuraHandledException(
                'Code ' + (clashes[0].ProductCode == code ? code : externalId) + ' is already used by ' + clashes[0].Name + '.'
            );
        }
    }

    /** Keeps the catalog convention: Primary_Brand__c is the brand's name across the family. */
    private static String primaryBrand(Product2 product, Product2 parent, String name, String productType) {
        if (productType == 'Brand') {
            return name;
        }
        if (parent != null) {
            return String.isNotBlank(parent.Primary_Brand__c) ? parent.Primary_Brand__c : parent.Name;
        }
        return product.Primary_Brand__c;
    }

    private static void savePublicPrice(Id productId, Decimal price) {
        if (price == null) {
            return;
        }
        Id standardId = standardPricebookId();
        List<PricebookEntry> entries = [
            SELECT Id, UnitPrice, IsActive
            FROM PricebookEntry
            WHERE Product2Id = :productId AND Pricebook2Id = :standardId
            WITH USER_MODE
            LIMIT 1
        ];
        if (entries.isEmpty()) {
            insert as user new PricebookEntry(Pricebook2Id = standardId, Product2Id = productId, UnitPrice = price, IsActive = true);
        } else if (entries[0].UnitPrice != price || entries[0].IsActive != true) {
            entries[0].UnitPrice = price;
            entries[0].IsActive = true;
            update as user entries[0];
        }
    }

    private static Id standardPricebookId() {
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        List<Pricebook2> books = [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE WITH USER_MODE LIMIT 1];
        if (books.isEmpty()) {
            throw new AuraHandledException('The standard price book is missing, so the public price was not saved.');
        }
        return books[0].Id;
    }

    private static String trimmed(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}
