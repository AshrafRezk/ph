@IsTest
private class SeatChangeServiceTest {
    private static final String DIST = 'TERR_DM_SCTEST';
    private static final String POS_A = 'TERR_POS_SCTEST_A';
    private static final String POS_B = 'TERR_POS_SCTEST_B';
    private static final String POS_E = 'TERR_POS_SCTEST_E';
    private static final String LINE = 'TERR_LINE_SCTEST';

    @TestSetup
    static void setup() {
        Territory2Model model = [SELECT Id FROM Territory2Model WHERE DeveloperName = 'Current_FY' LIMIT 1];
        Territory2Type type = [SELECT Id FROM Territory2Type LIMIT 1];
        Territory2 line = new Territory2(
            Name = 'SC Test Line', DeveloperName = 'SC_Test_Line', External_ID__c = LINE, Territory_Type__c = 'Line',
            Territory2ModelId = model.Id, Territory2TypeId = type.Id
        );
        insert line;
        Territory2 district = new Territory2(
            Name = 'SC Test District', DeveloperName = 'SC_Test_District', External_ID__c = DIST,
            Territory_Type__c = 'District', ParentTerritory2Id = line.Id,
            Territory2ModelId = model.Id, Territory2TypeId = type.Id
        );
        insert district;
        insert new List<Territory2>{
            new Territory2(
                Name = 'SC Test Position A', DeveloperName = 'SC_Test_Position_A', External_ID__c = POS_A,
                ParentTerritory2Id = district.Id, Territory2ModelId = model.Id, Territory2TypeId = type.Id
            ),
            new Territory2(
                Name = 'SC Test Position B', DeveloperName = 'SC_Test_Position_B', External_ID__c = POS_B,
                ParentTerritory2Id = district.Id, Territory2ModelId = model.Id, Territory2TypeId = type.Id
            ),
            new Territory2(
                Name = 'SC Test Position E', DeveloperName = 'SC_Test_Position_E', External_ID__c = POS_E,
                ParentTerritory2Id = district.Id, Territory2ModelId = model.Id, Territory2TypeId = type.Id
            )
        };
        List<Territory2> positions = [SELECT Id FROM Territory2 WHERE ParentTerritory2Id = :district.Id];
        for (Territory2 position : positions) {
            position.Territory_Type__c = 'Position';
        }
        update positions;

        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> people = new List<User>();
        for (String alias : new List<String>{ 'screp', 'scdm', 'scnew' }) {
            people.add(new User(
                Alias = alias, LastName = 'SeatTest ' + alias, Email = alias + '@seatchange.test',
                Username = alias + '.' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@seatchange.test',
                EmployeeNumber = 'SC-' + alias, ProfileId = standard.Id, EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', TimeZoneSidKey = 'Africa/Cairo',
                Title = 'Medical Representative'
            ));
        }
        insert people;
        Map<String, Id> territoryIds = territoryIds();
        insert new List<UserTerritory2Association>{
            new UserTerritory2Association(UserId = people[0].Id, Territory2Id = territoryIds.get(POS_A), RoleInTerritory2 = 'Medical Rep'),
            new UserTerritory2Association(UserId = people[1].Id, Territory2Id = territoryIds.get(DIST), RoleInTerritory2 = 'District Manager')
        };
    }

    private static Map<String, Id> territoryIds() {
        Map<String, Id> ids = new Map<String, Id>();
        for (Territory2 territory : [SELECT Id, External_ID__c FROM Territory2 WHERE External_ID__c LIKE 'TERR_%SCTEST%']) {
            ids.put(territory.External_ID__c, territory.Id);
        }
        return ids;
    }

    private static User person(String alias) {
        return [SELECT Id, Name, Username, Title FROM User WHERE Alias = :alias LIMIT 1];
    }

    private static Map<String, String> seatsOf(Id userId) {
        Map<String, String> seats = new Map<String, String>();
        for (UserTerritory2Association link : [
            SELECT Territory2.External_ID__c, RoleInTerritory2 FROM UserTerritory2Association WHERE UserId = :userId
        ]) {
            seats.put(link.Territory2.External_ID__c, link.RoleInTerritory2);
        }
        return seats;
    }

    private static String promotionJson(Id userId, String externalId, Date effective) {
        SeatChangeService.PromotionRequest request = new SeatChangeService.PromotionRequest();
        request.userId = userId;
        request.territoryExternalId = externalId;
        request.role = 'District Manager';
        request.newTitle = 'District Manager';
        request.effectiveDate = String.valueOf(effective);
        request.releaseOtherSeats = true;
        request.replaceSameRole = true;
        return JSON.serialize(request);
    }

    @IsTest
    static void promotionDatedTodayMovesPersonAndReplacesHolder() {
        User rep = person('screp');
        User dm = person('scdm');

        Test.startTest();
        SeatChangeService.SubmitResult result = SeatChangeService.promoteUser(promotionJson(rep.Id, DIST, Date.today()));
        Test.stopTest();

        System.assertEquals(1, result.applied, String.join(result.messages, ' '));
        Map<String, String> repSeats = seatsOf(rep.Id);
        System.assertEquals('District Manager', repSeats.get(DIST));
        System.assert(!repSeats.containsKey(POS_A), 'Rep should leave the old position.');
        System.assert(!seatsOf(dm.Id).containsKey(DIST), 'Old DM should be replaced.');
        System.assertEquals('District Manager', person('screp').Title);
        Seat_Change__c log = [SELECT Status__c, Previous_Seats__c, Source__c FROM Seat_Change__c WHERE User__c = :rep.Id];
        System.assertEquals('Applied', log.Status__c);
        System.assertEquals('Promotion', log.Source__c);
        System.assert(log.Previous_Seats__c.contains('SC Test Position A'));
    }

    @IsTest
    static void futurePromotionIsScheduledThenAppliedOnItsDate() {
        User rep = person('screp');
        SeatChangeService.SubmitResult result = SeatChangeService.promoteUser(promotionJson(rep.Id, DIST, Date.today().addDays(10)));
        System.assertEquals(1, result.scheduled);
        System.assertEquals(0, result.applied);
        System.assert(seatsOf(rep.Id).containsKey(POS_A), 'Nothing moves before the date.');
        System.assert(!SeatChangeService.getScheduledChanges(null).isEmpty());
        System.assertEquals(1, SeatChangeService.getScheduledChanges(rep.Id).size());

        Seat_Change__c scheduled = [SELECT Id FROM Seat_Change__c WHERE User__c = :rep.Id];
        scheduled.Effective_Date__c = Date.today();
        update scheduled;

        User admin = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        Test.startTest();
        System.runAs(admin) {
            System.assertEquals(1, SeatChangeService.applyDueChanges());
        }
        Test.stopTest();

        System.assertEquals('District Manager', seatsOf(rep.Id).get(DIST));
        System.assertEquals('Applied', [SELECT Status__c FROM Seat_Change__c WHERE Id = :scheduled.Id].Status__c);
        System.assertEquals(1, SeatChangeService.getSeatHistory(rep.Id).size());
    }

    @IsTest
    static void scheduledChangeCanBeCancelled() {
        User rep = person('screp');
        SeatChangeService.promoteUser(promotionJson(rep.Id, POS_B, Date.today().addDays(3)));
        Seat_Change__c scheduled = [SELECT Id FROM Seat_Change__c WHERE User__c = :rep.Id];
        SeatChangeService.cancelScheduledChange(scheduled.Id);
        System.assertEquals('Cancelled', [SELECT Status__c FROM Seat_Change__c WHERE Id = :scheduled.Id].Status__c);
        Boolean refused = false;
        try {
            SeatChangeService.cancelScheduledChange(scheduled.Id);
        } catch (AuraHandledException ex) {
            refused = true;
        }
        System.assert(refused, 'A cancelled change cannot be cancelled again.');
    }

    @IsTest
    static void uploadPreviewsThenAppliesSeatHolders() {
        User rep = person('screp');
        User dm = person('scdm');
        User newcomer = person('scnew');
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            // newcomer takes position B by username
            new Map<String, Object>{ 'rowNumber' => 2, 'territoryExternalId' => POS_B, 'title' => 'Medical Rep', 'holderUsername' => newcomer.Username },
            // district: DM keeps the seat, rep added as Area Manager by employee code
            new Map<String, Object>{ 'rowNumber' => 3, 'territoryExternalId' => DIST, 'title' => 'District Manager', 'holderUsername' => dm.Username },
            new Map<String, Object>{ 'rowNumber' => 4, 'territoryExternalId' => DIST, 'title' => 'Area Manager', 'employeeCode' => 'SC-screp' },
            // rep leaves position A
            new Map<String, Object>{ 'rowNumber' => 5, 'territoryExternalId' => POS_A, 'holderUsername' => rep.Username, 'remove' => 'Y' },
            // errors
            new Map<String, Object>{ 'rowNumber' => 6, 'territoryExternalId' => 'TERR_POS_DOES_NOT_EXIST', 'holder' => 'Someone' },
            new Map<String, Object>{ 'rowNumber' => 7, 'territoryExternalId' => POS_B, 'holderUsername' => 'nobody@seatchange.test', 'effectiveDate' => '31/02/2026' }
        };
        String rowsJson = JSON.serialize(rows);

        SeatChangeService.UploadPreview preview = SeatChangeService.previewOrganogramUpload(rowsJson, false);
        System.assertEquals(6, preview.rowCount);
        System.assertEquals(2, preview.errorCount, JSON.serialize(preview.lines));
        System.assertEquals(1, preview.assignCount, 'Only the rep joins the district; position B row is in error.');
        System.assertEquals(1, preview.removeCount, 'Rep leaves position A.');
        System.assertEquals(1, preview.unchangedCount);

        Test.startTest();
        SeatChangeService.SubmitResult result = SeatChangeService.applyOrganogramUpload(rowsJson, false);
        Test.stopTest();

        System.assertEquals(2, result.applied, String.join(result.messages, ' '));
        Map<String, String> repSeats = seatsOf(rep.Id);
        System.assertEquals('Area Manager', repSeats.get(DIST));
        System.assert(!repSeats.containsKey(POS_A));
        System.assertEquals('District Manager', seatsOf(dm.Id).get(DIST));
        System.assertEquals(2, [SELECT COUNT() FROM Seat_Change__c WHERE Source__c = 'Organogram Upload']);
    }

    @IsTest
    static void uploadCanReleaseOtherSeatsAndScheduleByDate() {
        User rep = person('screp');
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'rowNumber' => 2, 'territoryExternalId' => POS_B, 'holder' => rep.Name, 'effectiveDate' => String.valueOf(Date.today().addDays(5)) }
        };
        SeatChangeService.UploadPreview preview = SeatChangeService.previewOrganogramUpload(JSON.serialize(rows), true);
        System.assertEquals(1, preview.assignCount);
        System.assertEquals(1, preview.removeCount, 'Rep leaves position A for the new seat.');
        System.assertEquals(2, preview.scheduledCount);

        SeatChangeService.SubmitResult result = SeatChangeService.applyOrganogramUpload(JSON.serialize(rows), true);
        System.assertEquals(2, result.scheduled);
        System.assert(seatsOf(rep.Id).containsKey(POS_A), 'Nothing moves before the date.');
    }

    @IsTest
    static void uploadReplacesSameTitleAndChangesPositions() {
        User rep = person('screp');
        User newcomer = person('scnew');
        Map<String, Id> ids = territoryIds();
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            // a new position under a district that is created further down the same file
            new Map<String, Object>{ 'rowNumber' => 2, 'territoryName' => 'SC Test Position C', 'level' => 'Position',
                'parentExternalId' => 'TERR_DM_SCTEST_NEW', 'holderUserId' => newcomer.Id },
            new Map<String, Object>{ 'rowNumber' => 3, 'territoryExternalId' => 'TERR_DM_SCTEST_NEW', 'territoryName' => 'SC Test District New',
                'level' => 'District', 'parentExternalId' => LINE },
            // newcomer takes position A: the rep (same title) is replaced
            new Map<String, Object>{ 'rowNumber' => 4, 'territoryId' => ids.get(POS_A), 'territoryExternalId' => POS_A,
                'title' => 'Medical Rep', 'holderUserId' => newcomer.Id },
            // position B renamed and moved to the new district
            new Map<String, Object>{ 'rowNumber' => 5, 'territoryId' => ids.get(POS_B), 'territoryName' => 'SC Test Position B2',
                'parentExternalId' => 'TERR_DM_SCTEST_NEW' },
            // position E removed
            new Map<String, Object>{ 'rowNumber' => 6, 'territoryExternalId' => POS_E, 'remove' => 'yes' }
        };
        String rowsJson = JSON.serialize(rows);
        SeatChangeService.UploadPreview preview = SeatChangeService.previewOrganogramUpload(rowsJson, false);
        System.assertEquals(0, preview.errorCount, JSON.serialize(preview.lines));
        System.assertEquals(2, preview.createCount);
        System.assertEquals(1, preview.renameCount);
        System.assertEquals(1, preview.moveCount);
        System.assertEquals(1, preview.deletePositionCount);
        System.assertEquals(2, preview.assignCount);
        System.assertEquals(1, preview.removeCount, 'The rep is replaced in position A.');

        Test.startTest();
        SeatChangeService.SubmitResult result = SeatChangeService.applyOrganogramUpload(rowsJson, false);
        Test.stopTest();

        System.assertEquals(0, result.failed, String.join(result.messages, ' '));
        Territory2 newDistrict = [SELECT Id, ParentTerritory2.External_ID__c, Territory_Type__c FROM Territory2 WHERE External_ID__c = 'TERR_DM_SCTEST_NEW'];
        System.assertEquals(LINE, newDistrict.ParentTerritory2.External_ID__c);
        Territory2 positionC = [SELECT Id, Territory_Type__c, ParentTerritory2Id FROM Territory2 WHERE External_ID__c = 'TERR_POS_SC_TEST_POSITION_C'];
        System.assertEquals(newDistrict.Id, positionC.ParentTerritory2Id);
        Territory2 positionB = [SELECT Name, ParentTerritory2Id FROM Territory2 WHERE External_ID__c = :POS_B];
        System.assertEquals('SC Test Position B2', positionB.Name);
        System.assertEquals(newDistrict.Id, positionB.ParentTerritory2Id);
        System.assertEquals(0, [SELECT COUNT() FROM Territory2 WHERE External_ID__c = :POS_E]);
        Map<String, String> newcomerSeats = seatsOf(newcomer.Id);
        System.assert(newcomerSeats.containsKey(POS_A) && newcomerSeats.containsKey('TERR_POS_SC_TEST_POSITION_C'), String.valueOf(newcomerSeats));
        System.assert(!seatsOf(rep.Id).containsKey(POS_A), 'Rep was replaced.');
    }

    @IsTest
    static void uploadRejectsUnsafeStructureRows() {
        User rep = person('screp');
        User newcomer = person('scnew');
        Map<String, Id> ids = territoryIds();
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            // the district still has positions under it
            new Map<String, Object>{ 'rowNumber' => 2, 'territoryExternalId' => DIST, 'remove' => 'Y' },
            // lines are not created here
            new Map<String, Object>{ 'rowNumber' => 3, 'territoryName' => 'New Line', 'level' => 'Line', 'parentExternalId' => DIST },
            // a position cannot sit under a position
            new Map<String, Object>{ 'rowNumber' => 4, 'territoryName' => 'Nested', 'level' => 'Position', 'parentExternalId' => POS_A },
            // bad and mismatched Territory Ids, unknown user Id
            new Map<String, Object>{ 'rowNumber' => 5, 'territoryId' => 'not-an-id', 'holder' => 'x' },
            new Map<String, Object>{ 'rowNumber' => 6, 'territoryId' => ids.get(POS_A), 'territoryExternalId' => POS_B },
            new Map<String, Object>{ 'rowNumber' => 7, 'territoryExternalId' => POS_B, 'holderUserId' => UserInfo.getOrganizationId() },
            // removing a position later is not supported
            new Map<String, Object>{ 'rowNumber' => 8, 'territoryExternalId' => POS_E, 'remove' => 'Y',
                'effectiveDate' => String.valueOf(Date.today().addDays(3)) },
            // a position moved under the wrong kind of parent
            new Map<String, Object>{ 'rowNumber' => 9, 'territoryExternalId' => POS_A, 'parentExternalId' => LINE },
            // no territory at all
            new Map<String, Object>{ 'rowNumber' => 10, 'holder' => 'Someone' },
            // removing someone who is not there is not an error
            new Map<String, Object>{ 'rowNumber' => 11, 'territoryExternalId' => LINE, 'holderUserId' => newcomer.Id, 'remove' => 'Y' }
        };
        SeatChangeService.UploadPreview preview = SeatChangeService.previewOrganogramUpload(JSON.serialize(rows), false);
        System.assertEquals(9, preview.errorCount, JSON.serialize(preview.lines));
        System.assertEquals(1, preview.unchangedCount, 'Removing someone who is not in the seat changes nothing.');
        System.assertEquals(0, preview.deletePositionCount + preview.createCount + preview.moveCount);
        System.assert(seatsOf(rep.Id).containsKey(POS_A));
        System.assertEquals('Position', SeatChangeService.toTerritoryType('Medical Rep'));
        System.assertEquals('Other', SeatChangeService.toTerritoryType('Marketing Seat'));
        System.assertEquals(null, SeatChangeService.toTerritoryType('Region'));
        System.assertEquals('TERR_DM_CAIRO_EAST', SeatChangeService.newExternalId('District', ' Cairo - East '));
        System.assertEquals('BM_X', SeatChangeService.developerNameFor('TERR_BM__X_'));
        System.assertEquals('T_1A', SeatChangeService.developerNameFor('TERR_1A'));
    }

    @IsTest
    static void userEditorLoadsAndSavesEveryField() {
        User rep = person('screp');
        User dm = person('scdm');
        UserEditorController.UserDetails details = UserEditorController.getUserEditDetails(rep.Id);
        System.assertEquals(1, details.seats.size());
        System.assertEquals(POS_A, details.seats[0].externalId);

        UserEditorController.UserForm form = new UserEditorController.UserForm();
        form.userId = rep.Id;
        form.firstName = 'Seat';
        form.lastName = 'Tester';
        form.email = 'screp@seatchange.test';
        form.username = rep.Username;
        form.title = 'Senior Medical Representative';
        form.department = 'Sales';
        form.division = 'GIT I';
        form.employeeNumber = 'SC-9999';
        form.mobilePhone = '01000000000';
        form.phone = '0225555555';
        form.managerId = dm.Id;
        form.hireDate = '2024-01-16';

        Test.startTest();
        UserEditorController.saveUserDetails(JSON.serialize(form));
        Test.stopTest();

        User saved = [SELECT LastName, Title, Division, EmployeeNumber, MobilePhone, ManagerId FROM User WHERE Id = :rep.Id];
        System.assertEquals('Tester', saved.LastName);
        System.assertEquals('GIT I', saved.Division);
        System.assertEquals('SC-9999', saved.EmployeeNumber);
        System.assertEquals(dm.Id, saved.ManagerId);

        form.managerId = rep.Id;
        Boolean refused = false;
        try {
            UserEditorController.saveUserDetails(JSON.serialize(form));
        } catch (AuraHandledException ex) {
            refused = true;
        }
        System.assert(refused, 'Own manager is refused.');
    }

    @IsTest
    static void guardsAndDateParsing() {
        System.assertEquals(Date.newInstance(2026, 11, 1), SeatChangeService.parseDate('2026-11-01'));
        System.assertEquals(Date.newInstance(2026, 11, 1), SeatChangeService.parseDate('1/11/2026'));
        System.assertEquals(null, SeatChangeService.parseDate('31/02/2026'));
        System.assertEquals(null, SeatChangeService.parseDate('next week'));
        System.assertEquals('District Manager', SeatChangeService.defaultTitle('District'));
        System.assertEquals('Business Unit Manager', SeatChangeService.defaultTitle('Business_Unit'));
        System.assertEquals('National Sales Manager', SeatChangeService.defaultTitle('Line'));
        System.assert(SeatChangeService.isOrganogramSeat(POS_A));
        System.assert(!SeatChangeService.isOrganogramSeat('TERR_POS_TRAINING_REP'));

        Boolean missingTarget = false;
        try {
            SeatChangeService.promoteUser(promotionJson(person('screp').Id, 'TERR_NOPE', Date.today()));
        } catch (AuraHandledException ex) {
            missingTarget = true;
        }
        System.assert(missingTarget);

        Boolean noManageUsers = false;
        System.runAs(person('scnew')) {
            try {
                SeatChangeService.promoteUser(promotionJson(person('screp').Id, DIST, Date.today()));
            } catch (AuraHandledException ex) {
                noManageUsers = true;
            }
        }
        System.assert(noManageUsers, 'Users without Manage Users cannot move people.');
    }

    @IsTest
    static void dailyJobSchedulesAndRuns() {
        Test.startTest();
        SeatChangeJob.schedule('Seat change job test');
        Id jobId = SeatChangeJob.schedule('Seat change job test');
        new SeatChangeJob().execute((SchedulableContext) null);
        new SeatChangeJob.ApplyDue().execute(null);
        Test.stopTest();
        System.assertNotEquals(null, jobId);
        new SeatChangeLogJob(new List<Seat_Change__c>()).execute(null);
    }
}
