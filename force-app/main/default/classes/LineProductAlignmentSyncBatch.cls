/**
 * Syncs Product_Territory_Alignment__c for a sales/mirror line under the 10k DML row limit.
 * Expands matching Line territories into hierarchy Ids, then syncs one territory per execute.
 */
public with sharing class LineProductAlignmentSyncBatch implements Database.Batchable<Id>, Database.Stateful {
  private final String lineLabel;
  private Integer territoriesSynced = 0;
  private Integer alignmentsWritten = 0;
  private Set<Id> productIds = new Set<Id>();

  /** Test hook: when set, start() returns this scope and uses testProductIds. */
  @TestVisible
  private static List<Id> testTerritoryScope;
  @TestVisible
  private static Set<Id> testProductIds;

  public LineProductAlignmentSyncBatch(String lineLabel) {
    this.lineLabel = lineLabel;
  }

  public Iterable<Id> start(Database.BatchableContext bc) {
    if (Test.isRunningTest() && testTerritoryScope != null) {
      productIds = testProductIds == null ? new Set<Id>() : testProductIds;
      return testTerritoryScope;
    }
    return resolveTerritoryScope();
  }

  @TestVisible
  private List<Id> resolveTerritoryScope() {
    Set<String> wanted = TerritoryManagementController.matchKeysForLineLabel(lineLabel);
    List<Id> territoryIds = new List<Id>();
    if (wanted.isEmpty()) {
      return territoryIds;
    }
    Set<Id> lineIds = new Set<Id>();
    for (Territory2 line : [
      SELECT Id, Name, External_ID__c
      FROM Territory2
      WHERE Territory_Type__c = 'Line'
      WITH SYSTEM_MODE
      LIMIT 500
    ]) {
      Set<String> lineKeys = TerritoryManagementController.buildLineMatchKeysPublic(
        line.Name,
        line.External_ID__c
      );
      for (String key : lineKeys) {
        if (wanted.contains(key)) {
          lineIds.add(line.Id);
          break;
        }
      }
    }
    if (lineIds.isEmpty()) {
      return territoryIds;
    }
    Id firstLineId = new List<Id>(lineIds)[0];
    productIds = TerritoryManagementController.collectLineProductIdsPublic(firstLineId);
    for (Id lineId : lineIds) {
      if (lineId != firstLineId) {
        productIds.addAll(TerritoryManagementController.collectLineProductIdsPublic(lineId));
      }
    }
    productIds.addAll(TerritoryManagementController.expandDispenseProductIdsPublic(productIds));
    territoryIds.addAll(TerritoryHierarchyService.expandTerritoryHierarchy(lineIds));
    return territoryIds;
  }

  public void execute(Database.BatchableContext bc, List<Id> scope) {
    if (scope == null || scope.isEmpty() || productIds == null || productIds.isEmpty()) {
      return;
    }
    Set<String> keepProductKeys = new Set<String>();
    for (Id productId : productIds) {
      keepProductKeys.add(String.valueOf(productId));
    }
    for (Id territoryId : scope) {
      alignmentsWritten += TerritoryManagementController.syncOneTerritoryAlignments(
        territoryId,
        keepProductKeys
      );
      territoriesSynced++;
    }
  }

  public void finish(Database.BatchableContext bc) {
    System.debug(
      LoggingLevel.INFO,
      'LineProductAlignmentSyncBatch label=' +
        lineLabel +
        ' territories=' +
        territoriesSynced +
        ' alignmentsWritten=' +
        alignmentsWritten
    );
  }
}
