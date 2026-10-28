@IsTest
private class RepSalesTargetControllerTest {
    private class Seed {
        Brick__c brick;
        Product2 product;
        Product2 otherLine;
        Territory2 seat;
        Date month;
    }

    /** A seat territory for the running user, one account in one brick, one aligned product. */
    private static Seed seed() {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        List<Territory2Model> models = [SELECT Id FROM Territory2Model WHERE State = 'Active' LIMIT 1];
        if (types.isEmpty() || models.isEmpty()) {
            return null;
        }
        String uniq = 'rst' + String.valueOf(Datetime.now().getTime());
        Territory2 seat = new Territory2(
            Name = 'RST Seat ' + uniq,
            DeveloperName = 'RST_Seat_' + uniq,
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = 'TERR_POS_RST_' + uniq
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert seat;
            insert new UserTerritory2Association(UserId = UserInfo.getUserId(), Territory2Id = seat.Id);
        }

        Seed s = new Seed();
        s.seat = seat;
        Brick__c parent = new Brick__c(
            Name = 'RST 148 ' + uniq,
            External_ID__c = ('BRICK148_RST_' + uniq).left(80),
            Brick_Level__c = '148',
            Is_Active__c = true,
            Account_Selectable__c = true
        );
        insert parent;
        s.brick = new Brick__c(
            Name = 'RST 702 ' + uniq,
            External_ID__c = ('BRICK_RST_' + uniq + '_702').left(80),
            Brick_Level__c = '702',
            Parent_Brick__c = parent.Id,
            Is_Active__c = true,
            Account_Selectable__c = true
        );
        insert s.brick;

        Account pharmacy = new Account(Name = 'RST Pharmacy ' + uniq, Brick_702__c = s.brick.Id, Brick__c = s.brick.Id);
        insert pharmacy;
        insert new Account_Territory_Fields__c(Account__c = pharmacy.Id, Territory2_Id__c = String.valueOf(seat.Id), Is_Active__c = true);

        s.product = new Product2(Name = 'RST Brand ' + uniq, IsActive = true);
        Product2 otherLine = new Product2(Name = 'RST Other ' + uniq, IsActive = true);
        s.otherLine = otherLine;
        insert new List<Product2>{ s.product, otherLine };
        insert new Product_Territory_Alignment__c(
            Product2_Id__c = String.valueOf(s.product.Id),
            Territory2_Id__c = String.valueOf(seat.Id),
            Is_Active__c = true,
            Effective_Start_Date__c = Date.today()
        );

        s.month = Date.newInstance(2026, 9, 1);
        insert new List<Pharmacy_Sales_Withdrawal__c>{
            line(s, s.product.Id, 40, false, 'R'),
            line(s, s.product.Id, 25, true, 'T'),
            line(s, otherLine.Id, 99, false, 'O')
        };
        return s;
    }

    private static Pharmacy_Sales_Withdrawal__c line(Seed s, Id productId, Decimal qty, Boolean tender, String tag) {
        return new Pharmacy_Sales_Withdrawal__c(
            Data_Source__c = 'IbnSina',
            Report_Month__c = s.month,
            Brick__c = s.brick.Id,
            Product2_Id__c = String.valueOf(productId),
            Quantity_Withdrawn__c = qty,
            Unit_Price__c = 10,
            Is_Tender__c = tender,
            Unique_Key__c = 'RST_' + tag + '_' + s.brick.Id
        );
    }

    @IsTest
    static void salesInMyBricksExcludeTenderAndOtherLines() {
        Seed s = seed();
        if (s == null) {
            return;
        }

        Test.startTest();
        RepSalesTargetController.Payload p = RepSalesTargetController.getMySalesVsTarget(3);
        Test.stopTest();

        System.assertEquals(1, p.brickCount);
        System.assertEquals(3, p.months.size());
        RepSalesTargetController.MonthRow latest = p.months[2];
        System.assertEquals('2026-09', latest.monthKey);
        System.assertEquals(40, latest.quantity, 'tender and other-line products are left out');
        System.assertEquals(false, p.hasTargets);
        System.assertEquals(null, latest.achievementPercent);
        System.assertEquals(1, p.latestMonthProducts.size());
    }

    @IsTest
    static void targetIsProductTargetTimesBrickShare() {
        Seed s = seed();
        if (s == null) {
            return;
        }
        insert new Sales_Item_Target__c(Product__c = s.product.Id, Report_Month__c = s.month, Original_Target__c = 200);
        insert new Sales_Brick_Share__c(Brick__c = s.brick.Id, Product__c = s.product.Id, Target_Contribution_Pct__c = 40);

        Test.startTest();
        RepSalesTargetController.Payload p = RepSalesTargetController.getMySalesVsTarget(1);
        Test.stopTest();

        System.assertEquals(true, p.hasTargets);
        System.assertEquals(80, p.months[0].targetQuantity, '200 x 40%');
        System.assertEquals(50.0, p.months[0].achievementPercent, '40 of 80');
        System.assertEquals(80, p.latestMonthProducts[0].targetQuantity);
    }

    @IsTest
    static void noTerritoryGivesAMessage() {
        Test.startTest();
        RepSalesTargetController.Payload p = RepSalesTargetController.getMySalesVsTarget(null);
        Test.stopTest();
        System.assertNotEquals(null, p.message);
    }

    @IsTest
    static void oversizedScopeGivesAMessageInsteadOfFailing() {
        Seed s = seed();
        if (s == null) {
            return;
        }
        Test.startTest();
        RepSalesTargetController.rowBudgetOverride = 1;
        RepSalesTargetController.Payload p = RepSalesTargetController.getMySalesVsTarget(3);
        Test.stopTest();
        System.assertNotEquals(null, p.message);
        System.assertEquals(0, p.months.size());
    }

    @IsTest
    static void brickViewShowsMyBricksWithTargetsAndProductFilter() {
        Seed s = seed();
        if (s == null) {
            return;
        }
        insert new Sales_Item_Target__c(Product__c = s.product.Id, Report_Month__c = s.month, Original_Target__c = 200);
        insert new Sales_Brick_Share__c(Brick__c = s.brick.Id, Product__c = s.product.Id, Target_Contribution_Pct__c = 40);

        Test.startTest();
        RepSalesTargetController.BrickPayload latest = RepSalesTargetController.getMySalesByBrick(null, null);
        RepSalesTargetController.BrickPayload oneProduct = RepSalesTargetController.getMySalesByBrick('2026-09', String.valueOf(s.product.Id));
        RepSalesTargetController.BrickPayload emptyMonth = RepSalesTargetController.getMySalesByBrick('2026-07', null);
        Test.stopTest();

        System.assertEquals('2026-09', latest.monthKey, 'latest month with sales');
        System.assertEquals(1, latest.bricks.size());
        System.assertEquals(40, latest.bricks[0].quantity, 'tender and other-line products left out');
        System.assertEquals(80, latest.bricks[0].targetQuantity, '200 x 40%');
        System.assertEquals(50.0, latest.bricks[0].achievementPercent);
        System.assertEquals(true, latest.shapesIncluded);
        System.assertNotEquals(null, latest.bricks[0].name);
        System.assertEquals(1, latest.products.size());
        System.assertEquals(s.product.Name, oneProduct.productName);
        System.assertEquals(40, oneProduct.totalQuantity);
        System.assertEquals(0, emptyMonth.totalQuantity, 'a month without sales still lists the bricks');
        System.assertEquals(1, emptyMonth.bricks.size());
    }

    @IsTest
    static void brickViewWithoutTerritoryGivesAMessage() {
        Test.startTest();
        RepSalesTargetController.BrickPayload p = RepSalesTargetController.getMySalesByBrick('bad', 'bad');
        Test.stopTest();
        System.assertNotEquals(null, p.message);
        System.assertEquals(0, p.bricks.size());
    }

    private static User fieldUser(String tag) {
        User me = [SELECT ProfileId, TimeZoneSidKey, LocaleSidKey, EmailEncodingKey, LanguageLocaleKey FROM User WHERE Id = :UserInfo.getUserId()];
        String uniq = tag + String.valueOf(Datetime.now().getTime()).right(8);
        return new User(
            ProfileId = me.ProfileId,
            LastName = 'RST ' + tag,
            Alias = uniq.left(8),
            Email = uniq + '@rst.example.com',
            Username = uniq + '@rst.example.com',
            TimeZoneSidKey = me.TimeZoneSidKey,
            LocaleSidKey = me.LocaleSidKey,
            EmailEncodingKey = me.EmailEncodingKey,
            LanguageLocaleKey = me.LanguageLocaleKey
        );
    }

    /** A rep seat aligned to one product, held by a new user. */
    private static User repOnLine(Seed s, Id productId, String tag) {
        User u = fieldUser(tag);
        Territory2 seat = new Territory2(
            Name = 'RST ' + tag + ' ' + u.Alias,
            DeveloperName = 'RST_' + tag + '_' + u.Alias,
            Territory2ModelId = s.seat.Territory2ModelId,
            Territory2TypeId = s.seat.Territory2TypeId,
            External_ID__c = 'TERR_POS_RST_' + tag + '_' + u.Alias
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            insert seat;
            insert new UserTerritory2Association(UserId = u.Id, Territory2Id = seat.Id);
        }
        insert new Product_Territory_Alignment__c(
            Product2_Id__c = String.valueOf(productId),
            Territory2_Id__c = String.valueOf(seat.Id),
            Is_Active__c = true,
            Effective_Start_Date__c = Date.today()
        );
        return u;
    }

    private static Brick_Visit_Summary__c visits(Id brickId, Id userId, Date month, Integer count) {
        return new Brick_Visit_Summary__c(
            Brick__c = brickId,
            Visitor__c = userId,
            Month__c = month,
            Doctor_Visits__c = count,
            Unique_Key__c = BrickVisitSummaryBatch.key(brickId, userId, month)
        );
    }

    @IsTest
    static void shareSplitsBrickSalesByVisitsOfRepsOnTheProductLine() {
        Seed s = seed();
        if (s == null) {
            return;
        }
        User sameLine = repOnLine(s, s.product.Id, 'same');
        User otherLine = repOnLine(s, s.otherLine.Id, 'other');
        insert new List<Brick_Visit_Summary__c>{
            visits(s.brick.Id, UserInfo.getUserId(), s.month, 30),
            visits(s.brick.Id, sameLine.Id, s.month, 90),
            visits(s.brick.Id, otherLine.Id, s.month, 200)
        };

        Test.startTest();
        RepSalesTargetController.Payload p = RepSalesTargetController.getMySalesVsTarget(1);
        RepSalesTargetController.BrickPayload b = RepSalesTargetController.getMySalesByBrick('2026-09', String.valueOf(s.product.Id));
        Test.stopTest();

        System.assertEquals(true, p.shareAvailable);
        // 30 of the 120 visits by reps carrying the product; the other line's 200 visits don't count.
        System.assertEquals(10, p.months[0].shareQuantity, '25% of 40 units');
        System.assertEquals(100, p.months[0].shareRevenue, '25% of EGP 400');
        System.assertEquals(25.0, p.months[0].sharePercent);
        System.assertEquals(10, p.latestMonthProducts[0].shareQuantity);
        System.assertEquals(25.0, p.sharePercent);

        System.assertEquals(true, b.shareAvailable);
        System.assertEquals(10, b.shareQuantity);
        System.assertEquals(30, b.bricks[0].myVisits);
        System.assertEquals(120, b.bricks[0].allVisits);
        System.assertEquals(25.0, b.bricks[0].sharePercent);
    }

    @IsTest
    static void noVisitSummaryMeansNoShareYet() {
        Seed s = seed();
        if (s == null) {
            return;
        }
        Test.startTest();
        RepSalesTargetController.Payload p = RepSalesTargetController.getMySalesVsTarget(1);
        Test.stopTest();
        System.assertEquals(false, p.shareAvailable);
        System.assertEquals(null, p.months[0].shareQuantity);
        System.assertEquals(40, p.months[0].quantity, 'sales still show');
    }

    @IsTest
    static void visitedBricksCountWhenThereIsNoTargetList() {
        Seed s = seed();
        if (s == null) {
            return;
        }
        delete [SELECT Id FROM Account_Territory_Fields__c];
        insert visits(s.brick.Id, UserInfo.getUserId(), s.month, 12);

        Test.startTest();
        RepSalesTargetController.Payload p = RepSalesTargetController.getMySalesVsTarget(1);
        Test.stopTest();

        System.assertEquals(1, p.brickCount, 'brick of the visited doctors');
        System.assertEquals(1, p.visitedBrickCount);
        System.assertEquals(40, p.months[0].quantity);
        System.assertEquals(40, p.months[0].shareQuantity, 'the only visitor in the brick');
    }

    @IsTest
    static void territoryWithNobodyAndNoTargetListSaysSo() {
        Seed s = seed();
        if (s == null) {
            return;
        }
        delete [SELECT Id FROM Account_Territory_Fields__c];
        Test.startTest();
        RepSalesTargetController.Payload p = RepSalesTargetController.getMySalesVsTarget(1);
        Test.stopTest();
        System.assertEquals(0, p.brickCount);
        System.assert(p.message.contains('No bricks found'), p.message);
    }
}
