@IsTest
private class ProductEditorControllerTest {
    private static ProductEditorController.ProductForm form(String name, String productType, String code, Id parentId) {
        ProductEditorController.ProductForm f = new ProductEditorController.ProductForm();
        f.name = name;
        f.productType = productType;
        f.productCode = code;
        f.parentId = parentId;
        f.isActive = true;
        return f;
    }

    @IsTest
    static void createsBrandDetailAndSampleFamily() {
        Id brandId = ProductEditorController.saveProduct(form('EDITORBRAND', 'Brand', 'EDB', null));

        ProductEditorController.ProductForm detail = form('EDITORBRAND 10 MG 30 TAB', 'Detail', 'EDB1', brandId);
        detail.salesLine = 'CVM-I';
        detail.strength = '10 MG';
        detail.form = 'Tablet';
        detail.boxQuantity = 30;
        detail.publicPrice = 85.5;
        Id detailId = ProductEditorController.saveProduct(detail);

        Id sampleId = ProductEditorController.saveProduct(form('Editorbrand 10 mg 5 tab (FMS)', 'Sample', '990001', detailId));

        Product2 savedDetail = [
            SELECT ProductCode, External_ID__c, Primary_Brand__c, Parent_Product__c, Sales_Line__c, IsActive
            FROM Product2 WHERE Id = :detailId
        ];
        Assert.areEqual('EDB1', savedDetail.ProductCode);
        Assert.areEqual('EDB1', savedDetail.External_ID__c, 'External id defaults to the product code');
        Assert.areEqual('EDITORBRAND', savedDetail.Primary_Brand__c);
        Assert.areEqual(brandId, savedDetail.Parent_Product__c);
        Assert.areEqual('CVM-I', savedDetail.Sales_Line__c);
        Assert.areEqual(85.5, ProductEditorController.getProduct(detailId).publicPrice);
        Assert.areEqual('EDITORBRAND', [SELECT Primary_Brand__c FROM Product2 WHERE Id = :sampleId].Primary_Brand__c);
    }

    @IsTest
    static void editKeepsCodesAndUpdatesPrice() {
        Id brandId = ProductEditorController.saveProduct(form('KEEPBRAND', 'Brand', 'KPB', null));
        ProductEditorController.ProductForm detail = form('KEEPBRAND 5 MG', 'Detail', 'KPB1', brandId);
        detail.publicPrice = 10;
        Id detailId = ProductEditorController.saveProduct(detail);

        ProductEditorController.ProductForm edit = ProductEditorController.getProduct(detailId);
        edit.name = 'KEEPBRAND 5 MG 20 TAB';
        edit.productCode = 'CHANGED';
        edit.externalId = 'CHANGED';
        edit.publicPrice = 12.25;
        edit.isActive = false;
        ProductEditorController.saveProduct(edit);

        Product2 saved = [SELECT Name, ProductCode, External_ID__c, IsActive FROM Product2 WHERE Id = :detailId];
        Assert.areEqual('KEEPBRAND 5 MG 20 TAB', saved.Name);
        Assert.areEqual('KPB1', saved.ProductCode, 'Codes are fixed after creation');
        Assert.areEqual('KPB1', saved.External_ID__c);
        Assert.isFalse(saved.IsActive);
        Assert.areEqual(12.25, [SELECT UnitPrice FROM PricebookEntry WHERE Product2Id = :detailId].UnitPrice);
    }

    @IsTest
    static void refusesBadInput() {
        Id brandId = ProductEditorController.saveProduct(form('RULEBRAND', 'Brand', 'RUB', null));
        List<ProductEditorController.ProductForm> bad = new List<ProductEditorController.ProductForm>{
            form('', 'Brand', 'X1', null),
            form('No type', 'Widget', 'X2', null),
            form('Orphan detail', 'Detail', 'X3', null),
            form('Brand with parent', 'Brand', 'X4', brandId),
            form('Duplicate code', 'Brand', 'RUB', null),
            form('No code', 'Brand', '', null)
        };
        ProductEditorController.ProductForm negative = form('Negative', 'Detail', 'X5', brandId);
        negative.publicPrice = -1;
        bad.add(negative);
        for (ProductEditorController.ProductForm f : bad) {
            try {
                ProductEditorController.saveProduct(f);
                Assert.fail('Expected refusal for ' + f.name);
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
        Id detailId = ProductEditorController.saveProduct(form('RULEBRAND 1 MG', 'Detail', 'RUB1', brandId));
        try {
            ProductEditorController.saveProduct(form('Detail under detail', 'Detail', 'X6', detailId));
            Assert.fail('A Detail must sit under a Brand');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void optionsListTypesParentsAndLines() {
        ProductEditorController.ProductForm brand = form('OPTBRAND', 'Brand', 'OPB', null);
        brand.salesLine = 'GIT-I';
        ProductEditorController.saveProduct(brand);

        ProductEditorController.EditorOptions options = ProductEditorController.getEditorOptions();
        Assert.isTrue(options.productTypes.size() >= 4);
        Boolean foundParent = false;
        for (ProductEditorController.Option o : options.parents) {
            foundParent = foundParent || o.label == 'OPTBRAND';
        }
        Assert.isTrue(foundParent);
        Boolean foundLine = false;
        for (ProductEditorController.Option o : options.salesLines) {
            foundLine = foundLine || o.value == 'GIT-I';
        }
        Assert.isTrue(foundLine);
        Assert.isFalse(options.reminderKinds.isEmpty());
    }

    @IsTest
    static void getProductRejectsMissing() {
        try {
            ProductEditorController.getProduct(null);
            Assert.fail('Expected refusal');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        try {
            ProductEditorController.saveProduct(null);
            Assert.fail('Expected refusal');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }
}
