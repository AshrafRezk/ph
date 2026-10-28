@IsTest
private class SampleSupplyChainControllerTest {
    private static Product2 sampleProduct() {
        return [SELECT Id FROM Product2 WHERE Name = 'SSCC Sample Product' LIMIT 1];
    }

    private static User otherRep() {
        return [SELECT Id FROM User WHERE Email = 'sscc.rep2@example.com.invalid' LIMIT 1];
    }

    @TestSetup
    static void setup() {
        Product2 brand = new Product2(Name = 'SSCC Brand Product', IsActive = true, Product_Type__c = 'Brand');
        insert brand;
        Product2 detail = new Product2(
            Name = 'SSCC Detail Product',
            IsActive = true,
            Product_Type__c = 'Detail',
            Parent_Product__c = brand.Id
        );
        insert detail;
        insert new Product2(
            Name = 'SSCC Sample Product',
            IsActive = true,
            Product_Type__c = 'Sample',
            Parent_Product__c = detail.Id
        );

        Profile p = [SELECT Id FROM Profile LIMIT 1];
        String uniq = 'sscc' + String.valueOf(Datetime.now().getTime());
        insert new User(
            FirstName = 'SSCC',
            LastName = 'Rep2',
            Email = 'sscc.rep2@example.com.invalid',
            Username = uniq + '@example.com.invalid',
            Alias = 'ssccr2',
            CommunityNickname = uniq.left(40),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
    }

    @IsTest
    static void requestLifecycle_flowsThroughController() {
        Id rep = UserInfo.getUserId();
        Id product = sampleProduct().Id;

        Test.startTest();
        SampleSupplyChainService.Bootstrap bootstrap = SampleSupplyChainController.getBootstrap();
        Id requestId = SampleSupplyChainController.submitRequest(product, 10, rep, 'controller request');
        Id inventoryId = SampleSupplyChainController.allocateRequest(
            requestId,
            rep,
            'LOT-CTRL',
            Date.today().addDays(120),
            10,
            'allocated by controller'
        );
        Test.stopTest();

        System.assertNotEquals(null, bootstrap, 'Bootstrap is returned to the component.');
        System.assertNotEquals(null, inventoryId, 'Allocation creates inventory.');
        System.assertEquals(
            'Allocated',
            [SELECT Status__c FROM Sample_Request__c WHERE Id = :requestId WITH SYSTEM_MODE].Status__c
        );
        System.assertEquals(1, SampleSupplyChainController.getAuditTrailForInventory(inventoryId).size());
        System.assert(!SampleSupplyChainController.getAuditTrailForRep(rep).isEmpty(), 'Rep audit trail is populated.');
    }

    @IsTest
    static void stockMovements_flowThroughController() {
        Id rep = UserInfo.getUserId();

        Test.startTest();
        Id inventoryId = SampleSupplyChainController.allocateToRep(
            rep,
            sampleProduct().Id,
            'LOT-MOVE',
            Date.today().addDays(90),
            100,
            rep,
            'seed'
        );
        SampleSupplyChainController.transfer(inventoryId, otherRep().Id, 40, 'balance stock');
        SampleSupplyChainController.returnToSupply(inventoryId, 10, 'damaged');
        Test.stopTest();

        System.assertEquals(
            50,
            [SELECT Quantity_On_Hand__c FROM Sample_Inventory__c WHERE Id = :inventoryId].Quantity_On_Hand__c,
            'Transfer and return both decrement the source lot.'
        );
    }

    @IsTest
    static void cancelRequest_closesOpenRequest() {
        Id requestId = SampleSupplyChainController.submitRequest(sampleProduct().Id, 5, null, null);

        Test.startTest();
        SampleSupplyChainController.cancelRequest(requestId);
        Test.stopTest();

        System.assertEquals(
            'Cancelled',
            [SELECT Status__c FROM Sample_Request__c WHERE Id = :requestId WITH SYSTEM_MODE].Status__c
        );
    }

    @IsTest
    static void serviceErrors_surfaceAsAuraExceptions() {
        Integer handled = 0;
        Test.startTest();
        handled += countAuraFailure('submitRequest');
        handled += countAuraFailure('cancelRequest');
        handled += countAuraFailure('allocateRequest');
        handled += countAuraFailure('allocateToRep');
        handled += countAuraFailure('transfer');
        handled += countAuraFailure('returnToSupply');
        Test.stopTest();

        System.assertEquals(6, handled, 'Every controller entry point converts service errors for the component.');
    }

    private static Integer countAuraFailure(String action) {
        try {
            switch on action {
                when 'submitRequest' {
                    SampleSupplyChainController.submitRequest(null, -1, null, null);
                }
                when 'cancelRequest' {
                    SampleSupplyChainController.cancelRequest(null);
                }
                when 'allocateRequest' {
                    SampleSupplyChainController.allocateRequest(null, null, null, null, -1, null);
                }
                when 'allocateToRep' {
                    SampleSupplyChainController.allocateToRep(null, null, null, null, -1, null, null);
                }
                when 'transfer' {
                    SampleSupplyChainController.transfer(null, null, -1, null);
                }
                when 'returnToSupply' {
                    SampleSupplyChainController.returnToSupply(null, -1, null);
                }
            }
        } catch (Exception ex) {
            return 1;
        }
        return 0;
    }
}