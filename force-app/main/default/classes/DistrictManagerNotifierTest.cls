@IsTest
private class DistrictManagerNotifierTest {
    @IsTest
    static void recipients_includeManagerWhenNoTerritoryDm() {
        UserContext ctx = createManagerAndRep();
        Set<Id> recipients = DistrictManagerNotifier.recipientsFor(ctx.repUser.Id, ctx.managerUser.Id);
        System.assert(recipients.contains(ctx.managerUser.Id));
        System.assert(!recipients.contains(ctx.repUser.Id));
    }

    @IsTest
    static void expenseInsert_notifiesWithoutThrowing() {
        UserContext ctx = createManagerAndRep();
        Employee_Expense__c expense = new Employee_Expense__c(
            OwnerId = ctx.repUser.Id,
            Type__c = firstExpenseType(),
            Amount__c = 25,
            Expense_Date__c = Date.today(),
            Description__c = 'Taxi',
            Manager__c = ctx.managerUser.Id,
            Status__c = 'Pending'
        );
        Test.startTest();
        insert expense;
        Test.stopTest();
        System.assertEquals(
            'Pending',
            [SELECT Status__c FROM Employee_Expense__c WHERE Id = :expense.Id].Status__c
        );
    }

    @IsTest
    static void accountPendingDm_notifiesWithoutThrowing() {
        Account acct = new Account(Name = 'DM Bell Account ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
        insert acct;
        Test.startTest();
        AccountStageService.StageView view = AccountStageService.advance(acct.Id);
        Test.stopTest();
        System.assertEquals('Pending DM', view.currentApi);
    }

    private class UserContext {
        User managerUser;
        User repUser;
    }

    private static UserContext createManagerAndRep() {
        Profile profile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User managerUser = new User(
            Alias = 'dmbm',
            Email = 'dm.bell.mgr.' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'BellMgr',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'dm.bell.mgr.' + suffix + '@example.com'
        );
        User repUser = new User(
            Alias = 'dmbr',
            Email = 'dm.bell.rep.' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'BellRep',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'dm.bell.rep.' + suffix + '@example.com'
        );
        insert new List<User>{ managerUser, repUser };
        repUser.ManagerId = managerUser.Id;
        update repUser;
        UserContext ctx = new UserContext();
        ctx.managerUser = managerUser;
        ctx.repUser = repUser;
        return ctx;
    }

    private static String firstExpenseType() {
        for (Schema.PicklistEntry entry : Employee_Expense__c.Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }
}