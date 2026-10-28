@IsTest(isParallel=false)
private class ExpenseSubmissionControllerTest {
    @IsTest
    static void submitExpense_createsPendingRecordForManager() {
        UserContext ctx = createManagerAndRep();
        Date expenseDate = Date.today().addDays(-1);
        String typeValue = firstActiveType();

        ExpenseSubmissionController.ExpenseRow row;
        System.runAs(ctx.repUser) {
            Test.startTest();
            row = ExpenseSubmissionController.submitExpense(
                typeValue,
                125.50,
                expenseDate,
                'Lunch with HCP'
            );
            Test.stopTest();
        }

        Assert.isNotNull(row.id);
        Assert.areEqual(125.50, row.amount);
        Assert.areEqual(expenseDate, row.expenseDate);
        Assert.areEqual('Pending', row.status);
        Assert.areEqual('Lunch with HCP', row.description);
    }

    @IsTest
    static void getMyExpenses_returnsCurrentUserRecords() {
        UserContext ctx = createManagerAndRep();
        String typeValue = firstActiveType();
        System.runAs(ctx.repUser) {
            ExpenseSubmissionController.submitExpense(typeValue, 42, Date.today(), 'Taxi to site visit');
        }

        List<ExpenseSubmissionController.ExpenseRow> rows;
        System.runAs(ctx.repUser) {
            Test.startTest();
            rows = ExpenseSubmissionController.getMyExpenses(5);
            Test.stopTest();
        }

        Assert.isTrue(rows.size() >= 1);
    }

    @IsTest
    static void getExpenseFormContext_returnsRouteAndAttendees() {
        UserContext ctx = createManagerAndRep();
        ctx.repUser.Title = 'Medical Rep';
        ctx.managerUser.Title = 'District Manager';
        update new List<User>{ ctx.repUser, ctx.managerUser };

        Account clinic = new Account(
            Name = 'Expense Route Clinic',
            BillingCity = 'Cairo',
            BillingLatitude = 30.0444,
            BillingLongitude = 31.2357
        );
        insert clinic;

        ExpenseSubmissionController.FormContext context;
        System.runAs(ctx.repUser) {
            insert new Visit__c(
                Account__c = clinic.Id,
                Assigned_To__c = ctx.repUser.Id,
                Visit_Date__c = Date.today(),
                Start_Date__c = Datetime.newInstance(Date.today(), Time.newInstance(9, 30, 0, 0)),
                End_Date__c = Datetime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0)),
                Status__c = 'Draft',
                Visit_Type__c = 'Planned (Automatically)'
            );
            insert new Time_Off_Request__c(
                Type__c = 'Holiday',
                Span_Type__c = 'Full_Day',
                Span_Duration__c = 1,
                Stage__c = 'Draft',
                Start_Date_Time__c = Datetime.newInstance(Date.today(), Time.newInstance(12, 0, 0, 0)),
                End_Date_Time__c = Datetime.newInstance(Date.today(), Time.newInstance(13, 0, 0, 0))
            );
            Test.startTest();
            context = ExpenseSubmissionController.getExpenseFormContext(Date.today());
            Test.stopTest();
        }

        Assert.isNotNull(context);
        Assert.isTrue(context.stops.size() >= 1, 'The day should include the visit or time off.');
        Assert.isTrue(context.attendees.size() >= 1);

        Territory2 parent = expenseTerritory('Expense District', null);
        if (parent == null) {
            return;
        }
        Territory2 child = expenseTerritory('Expense Position', parent.Id);
        insert new List<UserTerritory2Association>{
            new UserTerritory2Association(
                UserId = ctx.repUser.Id,
                Territory2Id = parent.Id,
                RoleInTerritory2 = 'Medical Rep'
            ),
            new UserTerritory2Association(
                UserId = ctx.managerUser.Id,
                Territory2Id = child == null ? parent.Id : child.Id,
                RoleInTerritory2 = 'District Manager'
            )
        };
        System.runAs(ctx.repUser) {
            context = ExpenseSubmissionController.getExpenseFormContext(null);
        }
        Assert.isTrue(context.attendees.size() >= 1);
    }

    @IsTest
    static void getExpenseTypeOptions_returnsActiveValues() {
        Test.startTest();
        List<ExpenseSubmissionController.PicklistOption> options =
            ExpenseSubmissionController.getExpenseTypeOptions();
        Test.stopTest();

        Assert.isTrue(options.size() > 0);
    }

    @IsTest
    static void submitExpense_conferenceEventLabel() {
        if (!hasActiveType('Conference_Event')) {
            return;
        }
        UserContext ctx = createManagerAndRep();
        ExpenseSubmissionController.ExpenseRow row;
        System.runAs(ctx.repUser) {
            Test.startTest();
            row = ExpenseSubmissionController.submitExpense('Conference_Event', 900, Date.today(), null);
            Test.stopTest();
        }

        Assert.areEqual('Conference / Event', row.typeLabel);
    }

    @IsTest
    static void submitExpense_rejectsInvalidInput() {
        UserContext ctx = createManagerAndRep();
        Boolean threw = false;
        System.runAs(ctx.repUser) {
            Test.startTest();
            try {
                ExpenseSubmissionController.submitExpense('Invalid', 10, Date.today(), null);
            } catch (AuraHandledException ex) {
                threw = true;
            }
            Test.stopTest();
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void getExpenseDetail_returnsOwnedRecord() {
        UserContext ctx = createManagerAndRep();
        Id expenseId;
        System.runAs(ctx.repUser) {
            expenseId = ExpenseSubmissionController.submitExpense(
                firstActiveType(),
                50,
                Date.today(),
                'Detail test'
            ).id;
        }

        ExpenseSubmissionController.ExpenseRow detail;
        System.runAs(ctx.repUser) {
            Test.startTest();
            detail = ExpenseSubmissionController.getExpenseDetail(expenseId);
            Test.stopTest();
        }
        Assert.areEqual('Detail test', detail.description);
        Assert.areEqual('Pending', detail.status);
    }

    @IsTest
    static void updateAndDelete_ownerCanChangeOpenExpense() {
        UserContext ctx = createManagerAndRep();
        Id expenseId;
        System.runAs(ctx.repUser) {
            expenseId = ExpenseSubmissionController.submitExpense(
                firstActiveType(),
                50,
                Date.today(),
                'Before edit'
            ).id;
            Test.startTest();
            ExpenseSubmissionController.ExpenseRow updated = ExpenseSubmissionController.updateMyExpense(
                expenseId,
                firstActiveType(),
                75,
                Date.today(),
                'After edit'
            );
            Assert.areEqual(75, updated.amount);
            Assert.areEqual('After edit', updated.description);
            Assert.areEqual(firstActiveType(), updated.typeValue);
            ExpenseSubmissionController.deleteMyExpense(expenseId);
            Test.stopTest();
        }
        Integer remaining = [SELECT COUNT() FROM Employee_Expense__c WHERE Id = :expenseId];
        Assert.areEqual(0, remaining);
    }

    @IsTest
    static void submitExpense_rejectsZeroAmount() {
        UserContext ctx = createManagerAndRep();
        Boolean threw = false;
        System.runAs(ctx.repUser) {
            Test.startTest();
            try {
                ExpenseSubmissionController.submitExpense(firstActiveType(), 0, Date.today(), null);
            } catch (AuraHandledException ex) {
                threw = true;
            }
            Test.stopTest();
        }
        Assert.isTrue(threw);
    }

    private static String firstActiveType() {
        List<ExpenseSubmissionController.PicklistOption> options =
            ExpenseSubmissionController.getExpenseTypeOptions();
        Assert.isTrue(options.size() > 0, 'Expected at least one active expense type.');
        return options[0].value;
    }

    private static Boolean hasActiveType(String typeValue) {
        for (ExpenseSubmissionController.PicklistOption option : ExpenseSubmissionController.getExpenseTypeOptions()) {
            if (option.value == typeValue) {
                return true;
            }
        }
        return false;
    }

    private class UserContext {
        User managerUser;
        User repUser;
    }

    private static Territory2 expenseTerritory(String name, Id parentId) {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        if (types.isEmpty() || models.isEmpty()) {
            return null;
        }
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Territory2 territory = new Territory2(
            Name = name,
            DeveloperName = 'ExpenseTerr_' + suffix,
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            ParentTerritory2Id = parentId
        );
        if (Schema.SObjectType.Territory2.fields.getMap().containsKey('External_ID__c')) {
            territory.put('External_ID__c', 'TERR_EXPENSE_' + suffix);
        }
        insert territory;
        return territory;
    }

    private static UserContext createManagerAndRep() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User managerUser = new User(
            Alias = 'exsm',
            Email = 'exp.sub.mgr.' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'SubMgr',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'exp.sub.mgr.' + suffix + '@example.com'
        );
        User repUser = new User(
            Alias = 'exsr',
            Email = 'exp.sub.rep.' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'SubRep',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'exp.sub.rep.' + suffix + '@example.com'
        );
        insert new List<User>{ managerUser, repUser };
        repUser.ManagerId = managerUser.Id;
        update repUser;
        assignFieldPlannerPermissionSet(repUser.Id);

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