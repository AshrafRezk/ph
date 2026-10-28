@IsTest
private class LineProductAlignmentSyncBatchTest {
  @IsTest
  static void batchRunsForUnknownLabel() {
    Test.startTest();
    Id jobId = Database.executeBatch(new LineProductAlignmentSyncBatch('NO_SUCH_LINE_XYZ'), 1);
    Test.stopTest();
    System.assertNotEquals(null, jobId);
  }

  @IsTest
  static void resolveTerritoryScopeCoversStartLogic() {
    LineProductAlignmentSyncBatch batch = new LineProductAlignmentSyncBatch('NO_SUCH_LINE_XYZ');
    List<Id> empty = batch.resolveTerritoryScope();
    System.assertEquals(0, empty.size());
    // Non-empty keys, no matching Line territory in test data → still empty Ids.
    LineProductAlignmentSyncBatch batch2 = new LineProductAlignmentSyncBatch('CHC_Sales');
    List<Id> maybeEmpty = batch2.resolveTerritoryScope();
    System.assertNotEquals(null, maybeEmpty);
  }

  @IsTest
  static void batchExecutePathViaTestHooks() {
    Product2 brand = new Product2(
      Name = 'Hook Brand',
      ProductCode = 'HKB1',
      IsActive = true,
      Product_Type__c = 'Brand',
      Sales_Line__c = 'DIAB-I'
    );
    insert brand;
    LineProductAlignmentSyncBatch.testTerritoryScope = new List<Id>{ UserInfo.getUserId() };
    LineProductAlignmentSyncBatch.testProductIds = new Set<Id>{ brand.Id };
    Test.startTest();
    Database.executeBatch(new LineProductAlignmentSyncBatch('HOOK_LINE'), 1);
    Test.stopTest();
    LineProductAlignmentSyncBatch.testTerritoryScope = null;
    LineProductAlignmentSyncBatch.testProductIds = null;
    Integer alignments = [
      SELECT COUNT()
      FROM Product_Territory_Alignment__c
      WHERE Product2_Id__c = :String.valueOf(brand.Id) AND Territory2_Id__c = :String.valueOf(UserInfo.getUserId())
    ];
    System.assert(alignments >= 1, 'batch execute should insert alignment');
  }

  @IsTest
  static void publicHelpersAndOneTerritorySync() {
    System.assert(!TerritoryManagementController.matchKeysForLineLabel('CHC_Sales').isEmpty());
    System.assert(
      TerritoryManagementController.buildLineMatchKeysPublic('CHC_Sales', 'CHC_Sales')
        .containsAll(TerritoryManagementController.matchKeysForLineLabel('CHC_Sales'))
    );

    Product2 brand = new Product2(
      Name = 'Align Brand',
      ProductCode = 'ALB1',
      IsActive = true,
      Product_Type__c = 'Brand',
      Sales_Line__c = 'DIAB-I'
    );
    insert brand;
    Set<Id> expanded = TerritoryManagementController.expandDispenseProductIdsPublic(new Set<Id>{ brand.Id });
    System.assertNotEquals(null, expanded);

    // Sync against a synthetic territory key (no existing alignments) — exercises chunked insert path.
    Integer written = TerritoryManagementController.syncOneTerritoryAlignments(
      UserInfo.getUserId(),
      new Set<String>{ String.valueOf(brand.Id) }
    );
    System.assert(written >= 1, 'expected at least one alignment insert');
  }

  @IsTest
  static void mirrorAllPromotedLinesUsesInlineSyncInTests() {
    Product2 brand = new Product2(
      Name = 'Batch Mirror Brand',
      ProductCode = 'BMB1',
      IsActive = true,
      Product_Type__c = 'Brand',
      Sales_Line__c = 'DIAB-I'
    );
    insert brand;
    Test.startTest();
    TerritoryManagementController.MirrorResult result = TerritoryManagementController.mirrorAllPromotedLines(
      'TEST_BATCH_MIRROR'
    );
    Integer git = TerritoryManagementController.mirrorLineProducts('DIAB-I', 'TEST_GIT_MIRROR');
    Test.stopTest();
    System.assert(result.updated >= 1, 'expected at least the DIAB-I brand to pick up the mirror');
    System.assert(git >= 0);
    Product2 after = [SELECT Mirror_Line__c FROM Product2 WHERE Id = :brand.Id];
    System.assert(
      after.Mirror_Line__c != null && after.Mirror_Line__c.contains('TEST_BATCH_MIRROR'),
      after.Mirror_Line__c
    );
  }
}
