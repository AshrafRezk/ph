@IsTest
private class SampleSupplyChainServiceTest {
    private static Product2 sampleProduct() {
        return [SELECT Id FROM Product2 WHERE Name = 'SSC Sample Product' LIMIT 1];
    }

    private static Product2 reminderProduct() {
        return [SELECT Id FROM Product2 WHERE Name = 'SSC Brand Reminder' LIMIT 1];
    }

    private static User rep2() {
        return [SELECT Id FROM User WHERE Email = 'ssc.rep2@example.com.invalid' LIMIT 1];
    }

    @TestSetup
    static void setup() {
        Product2 brand = new Product2(
            Name = 'SSC Brand Product',
            IsActive = true,
            Product_Type__c = 'Brand'
        );
        insert brand;
        Product2 detail = new Product2(
            Name = 'SSC Detail Product',
            IsActive = true,
            Product_Type__c = 'Detail',
            Parent_Product__c = brand.Id
        );
        insert detail;
        insert new List<Product2>{
            new Product2(
                Name = 'SSC Sample Product',
                IsActive = true,
                Product_Type__c = 'Sample',
                Parent_Product__c = detail.Id
            ),
            new Product2(
                Name = 'SSC Brand Reminder',
                IsActive = true,
                Product_Type__c = 'Brand Reminder',
                Parent_Product__c = detail.Id
            )
        };
        Profile p = [SELECT Id FROM Profile LIMIT 1];
        String uniq = 'ssc' + String.valueOf(Datetime.now().getTime());
        insert new User(
            FirstName = 'SSC',
            LastName = 'Rep2',
            Email = 'ssc.rep2@example.com.invalid',
            Username = uniq + '@example.com.invalid',
            Alias = 'sscr2',
            CommunityNickname = uniq.left(40),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
    }

    @IsTest
    static void allocate_incrementsInventoryAndLogsAudit() {
        Id rep = UserInfo.getUserId();
        Id prod = sampleProduct().Id;
        Date expiry = Date.today().addDays(180);

        Test.startTest();
        Sample_Inventory__c inv = SampleSupplyChainService.allocateToRep(rep, prod, 'LOT-A', expiry, 100, rep, 'BR-123');
        SampleSupplyChainService.allocateToRep(rep, prod, 'LOT-A', expiry, 50, rep, 'BR-124');
        Test.stopTest();

        Sample_Inventory__c reloaded = [
            SELECT Quantity_On_Hand__c, Expiry_Date__c, Lot_Number__c FROM Sample_Inventory__c WHERE Id = :inv.Id
        ];
        System.assertEquals(150, reloaded.Quantity_On_Hand__c, 'Second allocation increments the same lot');
        System.assertEquals(expiry, reloaded.Expiry_Date__c, 'Allocated lot carries expiry');

        List<SampleSupplyChainService.AuditRow> audit = SampleSupplyChainService.getAuditTrailForInventory(inv.Id);
        System.assertEquals(2, audit.size(), 'Both allocations are on the audit trail');
        System.assertEquals('Allocation', audit[0].transactionType);
        System.assertEquals(rep, audit[0].requestedById, 'Requester captured for audit');
        System.assertNotEquals(null, audit[0].notes);
    }

    @IsTest
    static void transfer_movesStockBetweenRepsWithPairedLedger() {
        Id rep1 = UserInfo.getUserId();
        Id rep2Id = rep2().Id;
        Id prod = sampleProduct().Id;
        Sample_Inventory__c inv = SampleSupplyChainService.allocateToRep(
            rep1,
            prod,
            'LOT-B',
            Date.today().addDays(90),
            100,
            rep1,
            'seed'
        );

        Test.startTest();
        SampleSupplyChainService.transfer(inv.Id, rep2Id, 40, 'balance stock');
        Test.stopTest();

        Sample_Inventory__c source = [SELECT Quantity_On_Hand__c FROM Sample_Inventory__c WHERE Id = :inv.Id];
        System.assertEquals(60, source.Quantity_On_Hand__c, 'Source decremented');
        Sample_Inventory__c dest = [
            SELECT Quantity_On_Hand__c, Expiry_Date__c
            FROM Sample_Inventory__c
            WHERE Owner_User__c = :rep2Id AND Lot_Number__c = 'LOT-B'
        ];
        System.assertEquals(40, dest.Quantity_On_Hand__c, 'Destination credited');

        Integer outCount = [
            SELECT COUNT()
            FROM Sample_Transaction__c
            WHERE Transaction_Type__c = 'Transfer Out'
        ];
        Integer inCount = [SELECT COUNT() FROM Sample_Transaction__c WHERE Transaction_Type__c = 'Transfer In'];
        System.assertEquals(1, outCount);
        System.assertEquals(1, inCount);
    }

    @IsTest
    static void returnToSupply_decrementsAndLogsReturn() {
        Id rep = UserInfo.getUserId();
        Sample_Inventory__c inv = SampleSupplyChainService.allocateToRep(
            rep,
            sampleProduct().Id,
            'LOT-C',
            Date.today().addDays(30),
            20,
            rep,
            'seed'
        );

        Test.startTest();
        SampleSupplyChainService.returnToSupply(inv.Id, 5, 'damaged');
        Test.stopTest();

        Sample_Inventory__c reloaded = [SELECT Quantity_On_Hand__c FROM Sample_Inventory__c WHERE Id = :inv.Id];
        System.assertEquals(15, reloaded.Quantity_On_Hand__c);
        System.assertEquals(1, [SELECT COUNT() FROM Sample_Transaction__c WHERE Transaction_Type__c = 'Return']);
    }

    @IsTest
    static void request_submitAllocateAndClose() {
        Id rep = UserInfo.getUserId();
        Id prod = reminderProduct().Id;

        Test.startTest();
        Sample_Request__c request = SampleSupplyChainService.submitRequest(prod, 10, rep, 'Q4 BR pack');
        SampleSupplyChainService.allocateRequest(
            request.Id,
            rep,
            'LOT-BR',
            Date.today().addDays(120),
            4,
            'first drop'
        );
        SampleSupplyChainService.allocateRequest(
            request.Id,
            rep2().Id,
            'LOT-BR',
            Date.today().addDays(120),
            6,
            'balance'
        );
        Test.stopTest();

        Sample_Request__c reloaded = [
            SELECT Status__c, Quantity_Allocated__c, Request_Type__c, Requested_By__c
            FROM Sample_Request__c
            WHERE Id = :request.Id
            WITH SYSTEM_MODE
        ];
        System.assertEquals('Allocated', reloaded.Status__c);
        System.assertEquals(10, reloaded.Quantity_Allocated__c);
        System.assertEquals('Brand Reminder', reloaded.Request_Type__c);
        System.assertEquals(UserInfo.getUserId(), reloaded.Requested_By__c);

        System.assertEquals(2, [SELECT COUNT() FROM Sample_Inventory__c WHERE Lot_Number__c = 'LOT-BR']);
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Sample_Transaction__c WHERE Sample_Request__c = :request.Id]
        );
    }

    @IsTest
    static void request_cancelAndGuardrails() {
        Id prod = sampleProduct().Id;
        Sample_Request__c request = SampleSupplyChainService.submitRequest(prod, 5, null, null);

        SampleSupplyChainService.cancelRequest(request.Id);
        System.assertEquals(
            'Cancelled',
            [SELECT Status__c FROM Sample_Request__c WHERE Id = :request.Id WITH SYSTEM_MODE].Status__c
        );

        try {
            SampleSupplyChainService.allocateRequest(
                request.Id,
                UserInfo.getUserId(),
                'LOT-X',
                Date.today().addDays(10),
                1,
                null
            );
            System.assert(false, 'Cancelled request should not allocate');
        } catch (SampleSupplyChainService.SampleSupplyChainException ex) {
            System.assert(ex.getMessage().contains('not open'));
        }

        Product2 detail = [SELECT Id FROM Product2 WHERE Name = 'SSC Detail Product' LIMIT 1];
        try {
            SampleSupplyChainService.submitRequest(detail.Id, 1, null, null);
            System.assert(false, 'Detail products should be rejected');
        } catch (SampleSupplyChainService.SampleSupplyChainException ex) {
            System.assert(ex.getMessage().contains('Sample and Brand Reminder'));
        }
    }

    @IsTest
    static void bootstrap_returnsCatalogAndStock() {
        SampleSupplyChainService.submitRequest(sampleProduct().Id, 3, UserInfo.getUserId(), 'boot');
        SampleSupplyChainService.allocateToRep(
            UserInfo.getUserId(),
            sampleProduct().Id,
            'LOT-BOOT',
            Date.today().addDays(40),
            3,
            UserInfo.getUserId(),
            'boot'
        );

        Test.startTest();
        SampleSupplyChainService.Bootstrap data = SampleSupplyChainService.getBootstrap();
        Test.stopTest();

        System.assert(!data.products.isEmpty(), 'Sample and BR products listed');
        System.assert(!data.reps.isEmpty(), 'At least the running user is a fallback rep');
        System.assert(!data.requests.isEmpty());
        System.assert(!data.inventory.isEmpty());
    }

    @IsTest
    static void guardrails_rejectBadInput() {
        Id rep = UserInfo.getUserId();
        Id prod = sampleProduct().Id;
        Sample_Inventory__c inv = SampleSupplyChainService.allocateToRep(
            rep,
            prod,
            'LOT-D',
            Date.today().addDays(10),
            5,
            rep,
            'seed'
        );

        assertThrows(new AllocZeroQty(rep, prod));
        assertThrows(new AllocExpired(rep, prod));
        assertThrows(new TransferTooMuch(inv.Id, rep2().Id));
        assertThrows(new ReturnTooMuch(inv.Id));

        try {
            SampleSupplyChainService.transfer(inv.Id, rep, 1, null);
            System.assert(false, 'Expected same-owner transfer to fail');
        } catch (SampleSupplyChainService.SampleSupplyChainException ex) {
            System.assert(ex.getMessage().contains('current owner'));
        }
    }

    private interface ThrowingAction {
        void run();
    }
    private static void assertThrows(ThrowingAction action) {
        try {
            action.run();
            System.assert(false, 'Expected SampleSupplyChainException');
        } catch (SampleSupplyChainService.SampleSupplyChainException ex) {
            System.assert(ex.getMessage() != null);
        }
    }
    private class AllocZeroQty implements ThrowingAction {
        Id r;
        Id p;
        AllocZeroQty(Id r, Id p) {
            this.r = r;
            this.p = p;
        }
        public void run() {
            SampleSupplyChainService.allocateToRep(r, p, 'LOT-Z', Date.today().addDays(5), 0, r, null);
        }
    }
    private class AllocExpired implements ThrowingAction {
        Id r;
        Id p;
        AllocExpired(Id r, Id p) {
            this.r = r;
            this.p = p;
        }
        public void run() {
            SampleSupplyChainService.allocateToRep(r, p, 'LOT-Z', Date.today().addDays(-1), 5, r, null);
        }
    }
    private class TransferTooMuch implements ThrowingAction {
        Id inv;
        Id to;
        TransferTooMuch(Id inv, Id to) {
            this.inv = inv;
            this.to = to;
        }
        public void run() {
            SampleSupplyChainService.transfer(inv, to, 9999, null);
        }
    }
    private class ReturnTooMuch implements ThrowingAction {
        Id inv;
        ReturnTooMuch(Id inv) {
            this.inv = inv;
        }
        public void run() {
            SampleSupplyChainService.returnToSupply(inv, 9999, null);
        }
    }

    @IsTest
    static void controller_requestAllocateTransferReturn() {
        Id rep = UserInfo.getUserId();
        Id prod = sampleProduct().Id;
        Test.startTest();
        SampleSupplyChainService.Bootstrap boot = SampleSupplyChainController.getBootstrap();
        Id requestId = SampleSupplyChainController.submitRequest(prod, 30, rep, 'ctrl');
        Id invId = SampleSupplyChainController.allocateRequest(
            requestId,
            rep,
            'LOT-E',
            Date.today().addDays(60),
            30,
            'ctrl-alloc'
        );
        SampleSupplyChainController.allocateToRep(
            rep2().Id,
            prod,
            'LOT-DIRECT',
            Date.today().addDays(90),
            8,
            rep,
            'direct'
        );
        SampleSupplyChainController.transfer(invId, rep2().Id, 10, 'ctrl-transfer');
        SampleSupplyChainController.returnToSupply(invId, 5, 'ctrl-return');
        List<SampleSupplyChainService.AuditRow> byRep = SampleSupplyChainController.getAuditTrailForRep(rep);
        List<SampleSupplyChainService.AuditRow> byInv = SampleSupplyChainController.getAuditTrailForInventory(invId);
        SampleSupplyChainController.cancelRequest(
            SampleSupplyChainController.submitRequest(prod, 2, null, 'to-cancel')
        );
        Test.stopTest();

        System.assertNotEquals(null, boot);
        System.assertNotEquals(null, invId);
        System.assert(!byRep.isEmpty());
        System.assert(!byInv.isEmpty());

        try {
            SampleSupplyChainController.allocateToRep(
                rep,
                prod,
                'LOT-BAD',
                Date.today().addDays(-1),
                1,
                rep,
                'expired'
            );
            System.assert(false, 'Expected expired allocation to fail');
        } catch (Exception ex) {
            System.assert(true);
        }

        try {
            SampleSupplyChainController.returnToSupply(invId, 9999, null);
            System.assert(false, 'Expected controller to surface an error');
        } catch (Exception ex) {
            System.assert(true);
        }
    }
}