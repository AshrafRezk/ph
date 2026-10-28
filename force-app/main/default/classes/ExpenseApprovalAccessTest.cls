@IsTest(isParallel=false)
private class ExpenseApprovalAccessTest {
    @IsTest
    static void managerApprovesAndRejectsPendingExpense() {
        UserContext ctx = createManagerAndRep();
        Id expenseId;

        System.runAs(ctx.repUser) {
            ExpenseSubmissionController.ExpenseRow row = ExpenseSubmissionController.submitExpense(
                firstActiveType(),
                250,
                Date.today(),
                'Team lunch'
            );
            expenseId = row.id;
            Assert.areEqual('Pending', row.status);
        }

        System.runAs(ctx.managerUser) {
            List<ExpenseApprovalAccess.ApprovalRow> pending =
                ExpenseApprovalAccess.getPendingApprovals(ctx.managerUser.Id);
            Assert.isTrue(pending.size() >= 1);
            Boolean foundActionable = false;
            for (ExpenseApprovalAccess.ApprovalRow row : pending) {
                if (row.expenseId == expenseId) {
                    foundActionable = row.canAct == true;
                }
            }
            Assert.isTrue(foundActionable, 'Subordinate expense should be approvable.');

            List<ExpenseApprovalAccess.ApprovalRow> team =
                ExpenseApprovalAccess.getTeamExpenses(ctx.managerUser.Id);
            Boolean listedForTeam = false;
            for (ExpenseApprovalAccess.ApprovalRow row : team) {
                if (row.expenseId == expenseId) {
                    listedForTeam = row.canAct == true;
                }
            }
            Assert.isTrue(listedForTeam, 'Team tab should list the subordinate expense.');

            ExpenseApprovalAccess.approveExpense(expenseId, ctx.managerUser.Id);
        }

        Employee_Expense__c approved = [
            SELECT Status__c
            FROM Employee_Expense__c
            WHERE Id = :expenseId
        ];
        Assert.areEqual('Approved', approved.Status__c);

        Id rejectExpenseId;
        System.runAs(ctx.repUser) {
            rejectExpenseId = ExpenseSubmissionController.submitExpense(
                firstActiveType(),
                90,
                Date.today(),
                'Taxi'
            ).id;
        }

        System.runAs(ctx.managerUser) {
            ExpenseApprovalAccess.rejectExpense(rejectExpenseId, ctx.managerUser.Id, 'Missing receipt');
        }

        Employee_Expense__c rejected = [
            SELECT Status__c, Rejection_Reason__c
            FROM Employee_Expense__c
            WHERE Id = :rejectExpenseId
        ];
        Assert.areEqual('Rejected', rejected.Status__c);
        Assert.areEqual('Missing receipt', rejected.Rejection_Reason__c);
    }

    @IsTest
    static void territoryMembersBelowViewerAppearOnTeamTab() {
        List<UserTerritory2Association> children = [
            SELECT UserId, Territory2.ParentTerritory2Id
            FROM UserTerritory2Association
            WHERE Territory2.ParentTerritory2Id != NULL AND User.IsActive = TRUE
            LIMIT 20
        ];
        Assert.isFalse(children.isEmpty(), 'Child territory assignments are required.');

        Id childId;
        Id ancestorUserId;
        for (UserTerritory2Association child : children) {
            List<UserTerritory2Association> ancestors = [
                SELECT UserId
                FROM UserTerritory2Association
                WHERE Territory2Id = :child.Territory2.ParentTerritory2Id
                AND UserId != :child.UserId
                AND User.IsActive = TRUE
                LIMIT 1
            ];
            if (!ancestors.isEmpty()) {
                childId = child.UserId;
                ancestorUserId = ancestors[0].UserId;
                break;
            }
        }
        Assert.isNotNull(ancestorUserId, 'An ancestor territory user is required.');

        Employee_Expense__c expense = new Employee_Expense__c(
            Type__c = firstActiveType(),
            Amount__c = 42,
            Expense_Date__c = Date.today(),
            Description__c = 'Territory team check',
            Status__c = 'Pending',
            OwnerId = childId
        );
        insert expense;

        Test.startTest();
        List<ExpenseApprovalAccess.ApprovalRow> team =
            ExpenseApprovalAccess.getTeamExpenses(ancestorUserId);
        ExpenseApprovalAccess.getTeamExpenses(childId);
        ExpenseApprovalAccess.getTeamExpenses(null);
        Test.stopTest();

        Boolean listed = false;
        for (ExpenseApprovalAccess.ApprovalRow row : team) {
            if (row.expenseId == expense.Id) {
                listed = true;
            }
        }
        Assert.isTrue(listed, 'A subordinate territory expense should appear for the territory above.');
    }

    private static String firstActiveType() {
        return ExpenseSubmissionController.getExpenseTypeOptions()[0].value;
    }

    private class UserContext {
        User managerUser;
        User repUser;
    }

    private static UserContext createManagerAndRep() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User managerUser = new User(
            Alias = 'expm',
            Email = 'exp.mgr.' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ExpMgr',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'exp.mgr.' + suffix + '@example.com'
        );
        User repUser = new User(
            Alias = 'expr',
            Email = 'exp.rep.' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ExpRep',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'exp.rep.' + suffix + '@example.com'
        );
        insert new List<User>{ managerUser, repUser };
        repUser.ManagerId = managerUser.Id;
        update repUser;
        assignFieldPlannerPermissionSet(repUser.Id);
        assignFieldPlannerPermissionSet(managerUser.Id);

        UserContext ctx = new UserContext();
        ctx.managerUser = managerUser;
        ctx.repUser = repUser;
        return ctx;
    }

    private static void assignFieldPlannerPermissionSet(Id userId) {
        PermissionSet ps = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Field_Planner_Module'
            LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
    }
}