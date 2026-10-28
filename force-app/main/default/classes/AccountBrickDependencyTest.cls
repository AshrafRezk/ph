@IsTest
private class AccountBrickDependencyTest {
  @IsTest
  static void apply_fills148From702Parent() {
    BrickPair pair = seedPair('FILL');
    Account row = new Account(Name = 'Dep Fill 148', Brick_702__c = pair.brick702.Id);

    Test.startTest();
    AccountBrickDependency.apply(new List<Account>{ row }, null);
    Test.stopTest();

    System.assertEquals(pair.brick148.Id, row.Brick_148__c);
    System.assertEquals(pair.brick702.Id, row.Brick_702__c);
    System.assertEquals(pair.brick702.Id, row.Brick__c);
  }

  @IsTest
  static void apply_clears702When148Changes() {
    BrickPair first = seedPair('A');
    Brick__c second148 = new Brick__c(
      Name = 'BRICK1 DEP B',
      External_ID__c = 'BRICK148_DEP_B',
      Brick_Level__c = '148',
      Is_Active__c = true,
      Account_Selectable__c = true
    );
    insert second148;

    Account existing = new Account(
      Id = '001000000000001AAA',
      Brick_148__c = first.brick148.Id,
      Brick_702__c = first.brick702.Id
    );
    Account updated = new Account(
      Id = existing.Id,
      Name = 'Dep Brick Change',
      Brick_148__c = second148.Id,
      Brick_702__c = first.brick702.Id
    );

    Test.startTest();
    AccountBrickDependency.apply(
      new List<Account>{ updated },
      new Map<Id, Account>{ existing.Id => existing }
    );
    Test.stopTest();

    System.assertEquals(second148.Id, updated.Brick_148__c);
    System.assertEquals(null, updated.Brick_702__c);
    System.assertEquals(second148.Id, updated.Brick__c);
  }

  @IsTest
  static void trigger_insertsMatchingPair() {
    BrickPair pair = seedPair('INS');
    Account row = new Account(
      Name = 'Dep Brick Insert',
      Brick_148__c = pair.brick148.Id,
      Brick_702__c = pair.brick702.Id
    );

    Test.startTest();
    insert row;
    Test.stopTest();

    Account saved = [
      SELECT Brick__c, Brick_148__c, Brick_702__c
      FROM Account
      WHERE Id = :row.Id
    ];
    System.assertEquals(pair.brick148.Id, saved.Brick_148__c);
    System.assertEquals(pair.brick702.Id, saved.Brick_702__c);
    System.assertEquals(pair.brick702.Id, saved.Brick__c);
  }

  private class BrickPair {
    Brick__c brick148;
    Brick__c brick702;
  }

  private static BrickPair seedPair(String token) {
    BrickPair pair = new BrickPair();
    pair.brick148 = new Brick__c(
      Name = 'BRICK1 DEP ' + token,
      External_ID__c = ('BRICK148_DEP_' + token).left(80),
      Brick_Level__c = '148',
      Is_Active__c = true,
      Account_Selectable__c = true
    );
    pair.brick702 = new Brick__c(
      Name = 'Dep Neighborhood ' + token,
      External_ID__c = ('BRICK_DEP_' + token + '_702').left(80),
      Brick_Level__c = '702',
      Is_Active__c = true,
      Account_Selectable__c = true
    );
    insert new List<Brick__c>{ pair.brick148, pair.brick702 };
    pair.brick702.Parent_Brick__c = pair.brick148.Id;
    update pair.brick702;
    return pair;
  }
}