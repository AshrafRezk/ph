/**
 * Keeps Account 148 / 702 brick lookups in parent-child order and copies
 * the selected 702 (or 148) onto Brick__c for territory alignment.
 */
public with sharing class AccountBrickDependency {
  public static void apply(List<Account> newRows, Map<Id, Account> oldMap) {
    if (newRows == null || newRows.isEmpty()) {
      return;
    }
    Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
    if (
      !accountFields.containsKey('Brick_148__c') ||
      !accountFields.containsKey('Brick_702__c')
    ) {
      return;
    }

    Set<Id> brickIds = new Set<Id>();
    for (Account row : newRows) {
      Id brick702 = (Id) row.get('Brick_702__c');
      Id brick148 = (Id) row.get('Brick_148__c');
      if (brick702 != null) {
        brickIds.add(brick702);
      }
      if (brick148 != null) {
        brickIds.add(brick148);
      }
    }
    if (brickIds.isEmpty()) {
      syncAlignmentBrick(newRows);
      return;
    }

    Map<Id, Brick__c> bricks = new Map<Id, Brick__c>(
      [
        SELECT Id, Parent_Brick__c, Brick_Level__c
        FROM Brick__c
        WHERE Id IN :brickIds
        WITH SYSTEM_MODE
      ]
    );

    for (Account row : newRows) {
      Account prior = oldMap == null ? null : oldMap.get(row.Id);
      Id brick702 = (Id) row.get('Brick_702__c');
      Id brick148 = (Id) row.get('Brick_148__c');
      Boolean brick148Changed = prior == null || (Id) prior.get('Brick_148__c') != brick148;
      Boolean brick702Changed = prior == null || (Id) prior.get('Brick_702__c') != brick702;

      if (brick702 != null) {
        Brick__c micro = bricks.get(brick702);
        Id parent148 = micro == null ? null : micro.Parent_Brick__c;
        if (parent148 != null) {
          if (brick148 == null) {
            row.put('Brick_148__c', parent148);
            brick148 = parent148;
          } else if (parent148 != brick148) {
            if (brick148Changed && !brick702Changed) {
              row.put('Brick_702__c', null);
              brick702 = null;
            } else {
              row.put('Brick_148__c', parent148);
              brick148 = parent148;
            }
          }
        }
      }
    }
    syncAlignmentBrick(newRows);
  }

  private static void syncAlignmentBrick(List<Account> newRows) {
    if (!Schema.SObjectType.Account.fields.getMap().containsKey('Brick__c')) {
      return;
    }
    for (Account row : newRows) {
      Id brick702 = (Id) row.get('Brick_702__c');
      Id brick148 = (Id) row.get('Brick_148__c');
      if (brick702 != null) {
        row.put('Brick__c', brick702);
      } else if (brick148 != null) {
        row.put('Brick__c', brick148);
      }
    }
  }
}