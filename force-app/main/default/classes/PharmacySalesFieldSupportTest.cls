@IsTest
private class PharmacySalesFieldSupportTest {
  @IsTest
  static void fieldHelpersAndBrickContext() {
    System.assertEquals(false, PharmacySalesFieldSupport.hasField(null, 'Name'));
    System.assertEquals(false, PharmacySalesFieldSupport.hasField(Account.SObjectType, null));
    System.assertEquals(true, PharmacySalesFieldSupport.hasField(Account.SObjectType, 'Name'));

    String selectFields = PharmacySalesFieldSupport.selectClause(
      Account.SObjectType,
      new List<String>{ 'Id', 'Name', 'Does_Not_Exist__c' }
    );
    System.assert(selectFields.contains('Id'));
    System.assert(selectFields.contains('Name'));

    Account sample = new Account(Name = 'Support Test Pharmacy');
    insert sample;
    System.assertEquals(sample.Name, PharmacySalesFieldSupport.getFieldValue(sample, 'Name'));
    PharmacySalesFieldSupport.putFieldValue(sample, 'Name', 'Renamed Support Pharmacy');
    System.assertEquals('Renamed Support Pharmacy', sample.Name);

    Test.startTest();
    PharmacySalesFieldSupport.BrickContext context = PharmacySalesFieldSupport.loadBrickContext();
    Map<Id, Decimal> prices = PharmacySalesFieldSupport.loadStandardPrices(new Set<Id>());
    List<Pharmacy_Sales_Withdrawal__c> rows = PharmacySalesFieldSupport.queryWithdrawals(
      Date.today().toStartOfMonth(),
      Date.today().toStartOfMonth().addMonths(1).addDays(-1),
      'All',
      null,
      new List<Id>(),
      context
    );
    Test.stopTest();

    System.assertNotEquals(null, context);
    System.assertNotEquals(null, context.brickNames);
    System.assertNotEquals(null, prices);
    System.assertNotEquals(null, rows);

    Pharmacy_Sales_Withdrawal__c stub = new Pharmacy_Sales_Withdrawal__c();
    System.assertEquals(null, PharmacySalesFieldSupport.resolveBrickId(stub, context));
    System.assertEquals('', PharmacySalesFieldSupport.resolveBrickName(stub, context));
    System.assertEquals(0, PharmacySalesFieldSupport.resolveRevenue(stub, prices));
    System.assertEquals(null, PharmacySalesFieldSupport.resolveUnitPrice(stub, prices));
  }

  @IsTest
  static void queryWithdrawals_filtersAndResolvesPopulatedRows() {
    Account pharmacy = new Account(Name = 'Support Filter Pharmacy');
    Database.insert(pharmacy, AccessLevel.SYSTEM_MODE);

    Brick__c brick = new Brick__c(Name = 'Support Filter Brick', Is_Active__c = true);
    Database.insert(brick, AccessLevel.SYSTEM_MODE);
    Database.insert(
      new Brick_Pharmacy__c(
        Brick__c = brick.Id,
        Pharmacy_Account__c = pharmacy.Id,
        Unique_Key__c = brick.Id + ':' + pharmacy.Id,
        Is_Active__c = true
      ),
      AccessLevel.SYSTEM_MODE
    );

    Product2 product = new Product2(
      Name = 'Support Filter Product',
      ProductCode = 'SFS-1',
      IsActive = true
    );
    Database.insert(product, AccessLevel.SYSTEM_MODE);

    Date month = Date.today().toStartOfMonth();
    Pharmacy_Sales_Withdrawal__c withdrawal = new Pharmacy_Sales_Withdrawal__c(
      Data_Source__c = 'IbnSina',
      Report_Month__c = month,
      Pharmacy_Account__c = pharmacy.Id,
      Brick__c = brick.Id,
      Product2_Id__c = String.valueOf(product.Id),
      Quantity_Withdrawn__c = 10,
      Unit_Price__c = 15,
      Unique_Key__c = 'SFS_' + pharmacy.Id + '_' + product.Id
    );
    Database.insert(withdrawal, AccessLevel.SYSTEM_MODE);

    PharmacySalesFieldSupport.BrickContext context = PharmacySalesFieldSupport.loadBrickContext();
    Map<Id, Decimal> prices = PharmacySalesFieldSupport.loadStandardPrices(new Set<Id>{ product.Id });

    Test.startTest();
    List<Pharmacy_Sales_Withdrawal__c> bySource = PharmacySalesFieldSupport.queryWithdrawals(
      month,
      month.addMonths(1).addDays(-1),
      'IbnSina',
      brick.Id,
      new List<Id>{ pharmacy.Id },
      context
    );
    List<Pharmacy_Sales_Withdrawal__c> byAll = PharmacySalesFieldSupport.queryWithdrawals(
      month,
      month.addMonths(1).addDays(-1),
      'All',
      null,
      new List<Id>{ pharmacy.Id },
      context
    );
    Test.stopTest();

    System.assertNotEquals(null, bySource);
    System.assertNotEquals(null, byAll);
    System.assertEquals(brick.Id, PharmacySalesFieldSupport.resolveBrickId(withdrawal, context));
    System.assertEquals(brick.Name, PharmacySalesFieldSupport.resolveBrickName(withdrawal, context));
    Decimal revenue = PharmacySalesFieldSupport.resolveRevenue(withdrawal, prices);
    System.assert(revenue >= 0);
    PharmacySalesFieldSupport.resolveUnitPrice(withdrawal, prices);
    PharmacySalesFieldSupport.putFieldValue(null, 'Name', 'x');
    System.assertEquals(null, PharmacySalesFieldSupport.getFieldValue(null, 'Name'));
    System.assertEquals(null, PharmacySalesFieldSupport.getFieldValue(pharmacy, 'Does_Not_Exist__c'));
  }
}