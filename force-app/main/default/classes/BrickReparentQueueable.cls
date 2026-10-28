/**
 * After a 702 brick moves to another 148 brick, moves the 148 brick of the accounts in that 702 with it
 * (Account validation rule Brick_702_Matches_148). Pages through the accounts by Id.
 */
public with sharing class BrickReparentQueueable implements Queueable {
    @TestVisible
    private static Integer pageSize = 2000;

    private final Id brick702Id;
    private final Id afterAccountId;

    public BrickReparentQueueable(Id brick702Id, Id afterAccountId) {
        this.brick702Id = brick702Id;
        this.afterAccountId = afterAccountId;
    }

    public void execute(QueueableContext ctx) {
        List<Brick__c> bricks = [SELECT Parent_Brick__c FROM Brick__c WHERE Id = :brick702Id WITH SYSTEM_MODE];
        if (bricks.isEmpty()) {
            return;
        }
        Id parent148 = bricks[0].Parent_Brick__c;
        List<Account> accounts = afterAccountId == null
            ? [
                  SELECT Id, Brick_148__c
                  FROM Account
                  WHERE Brick_702__c = :brick702Id
                  WITH SYSTEM_MODE
                  ORDER BY Id
                  LIMIT :pageSize
              ]
            : [
                  SELECT Id, Brick_148__c
                  FROM Account
                  WHERE Brick_702__c = :brick702Id AND Id > :afterAccountId
                  WITH SYSTEM_MODE
                  ORDER BY Id
                  LIMIT :pageSize
              ];
        List<Account> moved = new List<Account>();
        for (Account a : accounts) {
            if (a.Brick_148__c != parent148) {
                moved.add(new Account(Id = a.Id, Brick_148__c = parent148));
            }
        }
        if (!moved.isEmpty()) {
            Database.update(moved, false, AccessLevel.SYSTEM_MODE);
        }
        if (accounts.size() == pageSize && !Test.isRunningTest()) {
            System.enqueueJob(new BrickReparentQueueable(brick702Id, accounts[accounts.size() - 1].Id));
        }
    }
}
