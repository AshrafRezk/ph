@IsTest
private class BrickVisitSummaryBatchTest {
    private static Id personRecordTypeId() {
        List<RecordType> types = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account' AND IsPersonType = TRUE AND IsActive = TRUE
            LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }

    private static Visit__c visit(Id accountId, Datetime at, String status) {
        return new Visit__c(
            Account__c = accountId,
            Assigned_To__c = UserInfo.getUserId(),
            Visit_Date__c = at,
            Start_Date__c = at,
            End_Date__c = at.addMinutes(30),
            Status__c = status,
            Visit_Type__c = 'Planned (Automatically)'
        );
    }

    @IsTest
    static void countsCompletedDoctorVisitsPerBrickRepAndMonth() {
        Id personType = personRecordTypeId();
        if (personType == null) {
            return;
        }
        Brick__c brick = new Brick__c(Name = 'BVS 702', External_ID__c = 'BRICK_BVS_702', Brick_Level__c = '702', Is_Active__c = true);
        insert brick;
        Account doctor = new Account(LastName = 'BVS Doctor', RecordTypeId = personType, Brick__c = brick.Id, Brick_702__c = brick.Id);
        Account pharmacy = new Account(Name = 'BVS Pharmacy', Brick__c = brick.Id, Brick_702__c = brick.Id);
        insert new List<Account>{ doctor, pharmacy };

        Date month = Date.today().toStartOfMonth();
        Datetime at = Datetime.newInstance(month.addDays(2), Time.newInstance(10, 0, 0, 0));
        Database.insert(
            new List<Visit__c>{
                visit(doctor.Id, at, 'Completed'),
                visit(doctor.Id, at.addDays(1), 'Completed'),
                visit(doctor.Id, at.addDays(2), 'Cancelled'),
                visit(pharmacy.Id, at, 'Completed')
            },
            AccessLevel.SYSTEM_MODE
        );
        // A row from an earlier run that no longer has visits is removed.
        Id otherUser = [SELECT Id FROM User WHERE IsActive = TRUE AND Id != :UserInfo.getUserId() LIMIT 1].Id;
        insert new Brick_Visit_Summary__c(
            Brick__c = brick.Id,
            Visitor__c = otherUser,
            Month__c = month,
            Doctor_Visits__c = 5,
            Unique_Key__c = BrickVisitSummaryBatch.key(brick.Id, otherUser, month)
        );

        Test.startTest();
        Database.executeBatch(new BrickVisitSummaryBatch(month, 1), BrickVisitSummaryBatch.SCOPE_SIZE);
        Test.stopTest();

        List<Brick_Visit_Summary__c> rows = [
            SELECT Visitor__c, Month__c, Doctor_Visits__c, Unique_Key__c
            FROM Brick_Visit_Summary__c
            WHERE Brick__c = :brick.Id
        ];
        System.assertEquals(1, rows.size(), 'stale row removed, one row for the rep');
        System.assertEquals(UserInfo.getUserId(), rows[0].Visitor__c);
        System.assertEquals(month, rows[0].Month__c);
        System.assertEquals(2, rows[0].Doctor_Visits__c, 'completed doctor visits only');
        System.assertEquals(BrickVisitSummaryBatch.key(brick.Id, UserInfo.getUserId(), month), rows[0].Unique_Key__c);
    }

    @IsTest
    static void schedulesTheBatch() {
        Test.startTest();
        System.schedule('BVS test', '0 0 2 * * ?', new BrickVisitSummaryBatch());
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = 'BVS test']);
    }
}
