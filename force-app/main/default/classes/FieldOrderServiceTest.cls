@IsTest
private class FieldOrderServiceTest {
    @IsTest
    static void createOutsideVisitAndSkipFullCycle() {
        FieldAppFeatureController.getFeatureCatalog();

        Account account = new Account(Name = 'Field Order Pharmacy');
        insert account;

        Product2 product = new Product2(Name = 'Order Product A', IsActive = true);
        insert product;

        FieldOrderService.CreateContext ctx =
            FieldOrderService.getCreateContext(account.Id, null);
        System.assertEquals(true, ctx.ordersEnabled);
        System.assertEquals(account.Id, ctx.defaultAccountId);

        FieldOrderService.LineInput line = new FieldOrderService.LineInput();
        line.productId = product.Id;
        line.quantity = 5;

        FieldOrderService.OrderInput input = new FieldOrderService.OrderInput();
        input.accountId = account.Id;
        input.orderType = 'Direct';
        input.source = 'Home';
        input.submitNow = true;
        input.lines = new List<FieldOrderService.LineInput>{ line };

        Test.startTest();
        FieldOrderService.OrderView created = FieldOrderService.saveAndSubmit(input);
        Test.stopTest();

        System.assertEquals(true, created.skipFullApproval);
        System.assertEquals('Pending Finance', created.status);
        System.assertEquals(null, created.visitId);
        System.assertEquals(5, created.totalQuantity);

        List<FieldOrderService.OrderView> mine = FieldOrderService.getMyOrders(10);
        System.assert(!mine.isEmpty());
        System.assert(!FieldOrderService.getMyOpenOrders().isEmpty());
        System.assert(!FieldOrderService.getFinanceQueue(10).isEmpty());

        FieldOrderService.OrderView paid = FieldOrderService.markPaid(created.id);
        System.assertEquals('Collected', paid.status);

        FieldOrderService.OrderView settled = FieldOrderService.markSettled(created.id);
        System.assertEquals('Settled', settled.status);
    }

    @IsTest
    static void forceDistributorOver200AndDraftWithoutVisit() {
        FieldAppFeatureController.getFeatureCatalog();

        Account account = new Account(Name = 'Bulk Order Chain');
        insert account;
        Product2 product = new Product2(Name = 'Bulk SKU', IsActive = true);
        insert product;

        FieldOrderService.LineInput line = new FieldOrderService.LineInput();
        line.productId = product.Id;
        line.quantity = 250;

        FieldOrderService.OrderInput input = new FieldOrderService.OrderInput();
        input.accountId = account.Id;
        input.orderType = 'Direct';
        input.distributorName = 'Ibn Sina';
        input.source = 'Account';
        input.submitNow = false;
        input.lines = new List<FieldOrderService.LineInput>{ line };

        FieldOrderService.OrderView draft = FieldOrderService.saveAndSubmit(input);
        System.assertEquals('Draft', draft.status);
        System.assertEquals('Distributor', draft.orderType);
        System.assertEquals(false, draft.skipFullApproval);

        List<FieldOrderService.OrderView> forAccount =
            FieldOrderService.getOrdersForAccount(account.Id);
        System.assertEquals(1, forAccount.size());
        System.assertEquals(0, FieldOrderService.getOrdersForVisit(null).size());
        System.assertEquals(0, FieldOrderService.getApprovalQueue(5).size());
        System.assertEquals(0, FieldOrderService.getApproverQueue().size());
    }

    @IsTest
    static void submitFullCycleAndApproveAsAdmin() {
        FieldAppFeatureController.getFeatureCatalog();
        Account account = new Account(Name = 'DM Cycle Pharmacy');
        insert account;
        Product2 product = new Product2(Name = 'Cycle SKU', IsActive = true);
        insert product;

        User manager = new User(
            FirstName = 'DM',
            LastName = 'Manager',
            Email = 'dm.manager@example.com',
            Username = 'dm.manager.' + System.currentTimeMillis() + '@example.com',
            Alias = 'dmman',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId()
        );
        insert manager;
        User me = [SELECT Id, ManagerId FROM User WHERE Id = :UserInfo.getUserId()];
        me.ManagerId = manager.Id;
        update me;

        FieldOrderService.LineInput line = new FieldOrderService.LineInput();
        line.productId = product.Id;
        line.quantity = 25;

        FieldOrderService.OrderInput input = new FieldOrderService.OrderInput();
        input.accountId = account.Id;
        input.orderType = 'Direct';
        input.source = 'Home';
        input.submitNow = true;
        input.lines = new List<FieldOrderService.LineInput>{ line };

        FieldOrderService.OrderView created = FieldOrderService.saveAndSubmit(input);
        System.assertEquals('Pending DM', created.status);

        Field_Order__c order = [
            SELECT Id, Current_Approver__c FROM Field_Order__c WHERE Id = :created.id
        ];
        order.Current_Approver__c = UserInfo.getUserId();
        update order;

        FieldOrderService.OrderView approved =
            FieldOrderService.decideApproval(created.id, true, 'OK');
        System.assertNotEquals('Pending DM', approved.status);

        FieldOrderService.OrderView rejectedDraft = FieldOrderService.saveAndSubmit(input);
        Field_Order__c rejectRow = [
            SELECT Id FROM Field_Order__c WHERE Id = :rejectedDraft.id
        ];
        rejectRow.Current_Approver__c = UserInfo.getUserId();
        rejectRow.Status__c = 'Pending DM';
        update rejectRow;
        FieldOrderService.OrderView rejected =
            FieldOrderService.decideApproval(rejectRow.Id, false, 'Too much');
        System.assertEquals('Rejected', rejected.status);
    }

    @IsTest
    static void focLineSendsSampleRequestAndStoresLineDiscount() {
        FieldAppFeatureController.getFeatureCatalog();
        Account account = new Account(Name = 'FOC Pharmacy');
        insert account;
        Product2 product = new Product2(Name = 'FOC SKU', IsActive = true);
        insert product;

        FieldOrderService.getCreateContext(null, null);

        FieldOrderService.LineInput line = new FieldOrderService.LineInput();
        line.productId = product.Id;
        line.quantity = 3;
        line.discountPercent = 10;
        line.foc = true;

        FieldOrderService.OrderInput input = new FieldOrderService.OrderInput();
        input.accountId = account.Id;
        input.orderType = 'Direct';
        input.source = 'Home';
        input.submitNow = true;
        input.lines = new List<FieldOrderService.LineInput>{ line };

        Test.startTest();
        FieldOrderService.OrderView created = FieldOrderService.saveAndSubmit(input);
        Test.stopTest();

        System.assertEquals(1, created.lines.size());
        System.assertEquals(true, created.lines[0].foc);
        System.assertEquals(10, created.lines[0].discountPercent);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Field_Request__c WHERE Request_Type__c = 'Sample' AND Product__c = :product.Id]
        );

        FieldOrderService.LineInput bad = new FieldOrderService.LineInput();
        bad.productId = product.Id;
        bad.quantity = 1;
        bad.discountPercent = 150;
        FieldOrderService.OrderInput badInput = new FieldOrderService.OrderInput();
        badInput.accountId = account.Id;
        badInput.orderType = 'Direct';
        badInput.lines = new List<FieldOrderService.LineInput>{ bad };
        Boolean rejected = false;
        try {
            FieldOrderService.saveAndSubmit(badInput);
        } catch (Exception ex) {
            rejected = true;
        }
        System.assertEquals(true, rejected);
    }

    private static User orderUser(String alias, Id managerId, Boolean admin) {
        Id profileId = admin
            ? UserInfo.getProfileId()
            : [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;
        User u = new User(
            FirstName = 'Order',
            LastName = alias,
            Email = alias + '@example.com',
            Username = alias + '.' + System.currentTimeMillis() + '@example.com',
            Alias = alias,
            TimeZoneSidKey = 'Africa/Cairo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId,
            ManagerId = managerId
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            if (!admin) {
                PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Field_Workflow_Access' LIMIT 1];
                insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
            }
        }
        return u;
    }

    @IsTest
    static void yasserAndFinanceStepsNeedTheNamedApprover() {
        FieldAppFeatureController.getFeatureCatalog();
        User buHead = orderUser('ordbu', null, false);
        User dm = orderUser('orddm', buHead.Id, false);
        User yasser = orderUser('ordyas', null, false);
        User finance = orderUser('ordfin', null, false);
        FieldOrderService.approverOverrideByStep = new Map<String, Id>{
            'Yasser' => yasser.Id,
            'Finance' => finance.Id
        };
        Account account = new Account(Name = 'Named Approver Pharmacy');
        insert account;
        Field_Order__c order = new Field_Order__c(
            Account__c = account.Id,
            Order_Type__c = 'Direct',
            Requested_By__c = UserInfo.getUserId(),
            Total_Quantity__c = 50,
            Status__c = 'Pending BU',
            Current_Approver__c = buHead.Id
        );
        insert order;

        Test.startTest();
        FieldOrderService.OrderView afterBu;
        System.runAs(buHead) {
            afterBu = FieldOrderService.approve(order.Id, 'BU ok');
        }
        System.assertEquals('Pending Yasser', afterBu.status);
        System.assertEquals(
            yasser.Id,
            [SELECT Current_Approver__c FROM Field_Order__c WHERE Id = :order.Id].Current_Approver__c
        );

        // A manager in the requester's chain is no longer enough for the Yasser step.
        Boolean dmBlocked = false;
        System.runAs(dm) {
            try {
                FieldOrderService.approve(order.Id, 'not mine');
            } catch (AuraHandledException e) {
                dmBlocked = true;
            }
        }
        System.assert(dmBlocked, 'Only the named Yasser approver can approve');

        FieldOrderService.OrderView afterYasser;
        System.runAs(yasser) {
            afterYasser = FieldOrderService.approve(order.Id, 'Yasser ok');
        }
        System.assertEquals('Pending Finance', afterYasser.status);

        Boolean yasserBlockedOnFinance = false;
        System.runAs(yasser) {
            try {
                FieldOrderService.markPaid(order.Id);
            } catch (AuraHandledException e) {
                yasserBlockedOnFinance = true;
            }
        }
        System.assert(yasserBlockedOnFinance, 'Finance step needs the Finance approver');

        FieldOrderService.OrderView approved;
        System.runAs(finance) {
            approved = FieldOrderService.approve(order.Id, 'Finance ok');
        }
        Test.stopTest();
        System.assertEquals('Approved', approved.status);
    }

    @IsTest
    static void unnamedStepWaitsForSfe() {
        FieldAppFeatureController.getFeatureCatalog();
        FieldOrderService.approverOverrideByStep = new Map<String, Id>();
        User other = orderUser('ordoth', null, false);
        Account account = new Account(Name = 'Unnamed Step Pharmacy');
        insert account;
        Field_Order__c order = new Field_Order__c(
            Account__c = account.Id,
            Order_Type__c = 'Direct',
            Requested_By__c = UserInfo.getUserId(),
            Total_Quantity__c = 50,
            Status__c = 'Pending Yasser'
        );
        insert order;
        Test.startTest();
        Boolean blocked = false;
        System.runAs(other) {
            try {
                FieldOrderService.approve(order.Id, 'try');
            } catch (AuraHandledException e) {
                blocked = true;
            }
        }
        Test.stopTest();
        System.assert(blocked, 'No one but the named approver (or an admin) can approve');
        System.assert(
            FieldOrderService.getMyOrders(5)[0].routingHint.contains('Yasser'),
            'Hint tells the rep the step is waiting for a named approver'
        );
    }
}
