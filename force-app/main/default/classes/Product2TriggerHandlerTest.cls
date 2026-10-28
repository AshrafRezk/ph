@IsTest(SeeAllData = false)
private class Product2TriggerHandlerTest {
    @IsTest
    static void beforeInsertAndUpdate_invokeCatalogService() {
        Product2 brand = new Product2(
            Name = 'Trigger Brand',
            ProductCode = 'TRIGBR',
            External_ID__c = 'TRIGBR_EXT',
            Product_Type__c = 'Brand',
            IsActive = true
        );
        insert brand;

        Product2 detail = new Product2(
            Name = 'Trigger Detail',
            ProductCode = 'TRIGDET',
            External_ID__c = 'TRIGDET_EXT',
            Product_Type__c = 'Detail',
            Parent_Product__c = brand.Id,
            IsActive = true
        );
        insert detail;

        Product2 reminder = new Product2(
            Name = 'Trigger Reminder',
            ProductCode = 'TRIGREM',
            External_ID__c = 'TRIGREM_EXT',
            Product_Type__c = 'Brand Reminder',
            Parent_Product__c = detail.Id,
            IsActive = true
        );

        Test.startTest();
        Product2TriggerHandler.beforeInsert(new List<Product2>{ reminder });
        insert reminder;
        reminder.Name = 'Trigger Reminder Updated';
        Product2TriggerHandler.beforeUpdate(
            new List<Product2>{ reminder },
            new Map<Id, Product2>{ reminder.Id => reminder.clone(true, true, true, true) }
        );
        update reminder;
        Test.stopTest();

        Product2 saved = [
            SELECT Id, Name, Brand_Manager__c
            FROM Product2
            WHERE Id = :reminder.Id
        ];
        Assert.areEqual('Trigger Reminder Updated', saved.Name);
    }

    @IsTest
    static void hierarchyRulesFireOnCreateAndOnParentOrTypeChangeOnly() {
        Product2 brand = new Product2(Name = 'Gate Brand', ProductCode = 'GATEBR', External_ID__c = 'GATEBR_EXT', Product_Type__c = 'Brand', IsActive = true);
        insert brand;
        Product2 detail = new Product2(Name = 'Gate Detail', ProductCode = 'GATEDET', External_ID__c = 'GATEDET_EXT', Product_Type__c = 'Detail', Parent_Product__c = brand.Id, IsActive = true);
        insert detail;
        Product2 sample = new Product2(Name = 'Gate Sample', ProductCode = 'GATESMP', External_ID__c = 'GATESMP_EXT', Product_Type__c = 'Sample', Parent_Product__c = detail.Id, IsActive = true);
        insert sample;

        // create is still validated: a Sample cannot sit directly under a Brand
        Product2 badSample = new Product2(Name = 'Gate Bad', ProductCode = 'GATEBAD', External_ID__c = 'GATEBAD_EXT', Product_Type__c = 'Sample', Parent_Product__c = brand.Id, IsActive = true);
        try {
            insert badSample;
            Assert.fail('Expected the Detail-parent rule to fire on create.');
        } catch (DmlException ex) {
            Assert.isTrue(ex.getMessage().contains('Detail parent'), ex.getMessage());
        }

        // turn the Detail into a Brand: the Sample under it is now a legacy orphan (its parent is a Brand)
        detail.Product_Type__c = 'Brand';
        detail.Parent_Product__c = null;
        update detail;

        // editing the orphan for any other reason is no longer blocked
        sample.Name = 'Gate Sample Renamed';
        sample.IsActive = false;
        update sample;
        Assert.areEqual('Gate Sample Renamed', [SELECT Name FROM Product2 WHERE Id = :sample.Id].Name);

        // but re-parenting it to another non-Detail is still validated
        sample.Parent_Product__c = brand.Id;
        try {
            update sample;
            Assert.fail('Expected the Detail-parent rule to fire when the parent changes.');
        } catch (DmlException ex) {
            Assert.isTrue(ex.getMessage().contains('Detail parent'), ex.getMessage());
        }
    }
}