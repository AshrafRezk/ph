@IsTest
private class MeetingTypeServiceTest {
    @TestSetup
    static void setup() {
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User dm = makeUser(admin.Id, 'mtdm', 'District Manager', null);
        insert dm;
        User rep = makeUser(admin.Id, 'mtrep', 'Medical Rep', dm.Id);
        User trainer = makeUser(admin.Id, 'mtld', 'L&D Manager', dm.Id);
        insert new List<User>{ rep, trainer };
        MeetingSetupController.seedDefaults();
    }

    private static User makeUser(Id profileId, String alias, String title, Id managerId) {
        return new User(
            Alias = alias, Email = alias + '@zeta.test', EmailEncodingKey = 'UTF-8', LastName = alias, FirstName = 'Test',
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = profileId, TimeZoneSidKey = 'Africa/Cairo',
            Username = alias + '.' + Crypto.getRandomInteger() + '@zeta.meetingtypes.test', Title = title, ManagerId = managerId
        );
    }

    private static User userByAlias(String alias) {
        return [SELECT Id, Name, Title FROM User WHERE Alias = :alias AND Email = :(alias + '@zeta.test') LIMIT 1];
    }

    private static Id createMeeting(String department, String activityType) {
        DateTime startAt = DateTime.now().addDays(7);
        return MeetingLifecycleController.saveMeeting(JSON.serialize(new Map<String, Object>{
            'title' => 'Type test',
            'department' => department,
            'activityType' => activityType,
            'startDateTime' => startAt,
            'endDateTime' => startAt.addHours(2)
        }));
    }

    private static String errorOf(String department, String activityType) {
        try {
            createMeeting(department, activityType);
        } catch (Exception e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void defaultsFollowTheBrd() {
        MeetingTypeService.TypeConfig rtd = MeetingTypeService.forType('KOL Roundtable');
        Assert.isTrue(rtd.configured);
        Assert.isTrue(rtd.requireTargetHcps, 'RTD takes HCPs from the target list');
        Assert.isTrue(rtd.requireBrand);
        MeetingTypeService.TypeConfig training = MeetingTypeService.forType('Training');
        Assert.areEqual(new List<String>{ 'L&D' }, training.departments);
        Assert.isFalse(training.allowHcps, 'L&D training is for employees');
        Assert.isFalse(training.showInvitations);
        Assert.areEqual(80, training.minAttendancePct.intValue());
        MeetingTypeService.TypeConfig webinar = MeetingTypeService.forType('Webinar');
        Assert.isTrue(webinar.showInvitations);
        Assert.isFalse(webinar.allowDoorScan, 'Online sessions have no door');
        Assert.isFalse(webinar.allowDeposit);
        Assert.isFalse(MeetingApprovalChainService.usesMetadataRules(), 'Seeding copies the metadata chain into levels');
    }

    @IsTest
    static void repSeesOnlyTypesOpenToTheirTitle() {
        User rep = userByAlias('mtrep');
        Set<String> types = new Set<String>();
        System.runAs(rep) {
            for (MeetingTypeService.TypeConfig config : MeetingLifecycleController.getOptions().types) {
                types.add(config.activityType);
            }
            Assert.isTrue(errorOf('Medical', 'Advisory Board').contains('Only'), 'Advisory Board is for managers');
            Assert.isTrue(errorOf('Sales', 'Webinar').contains('Marketing, Medical only'));
            Assert.isNull(errorOf('Sales', 'KOL Roundtable'));
        }
        Assert.isTrue(types.contains('KOL Roundtable'));
        Assert.isFalse(types.contains('Advisory Board'));
        Assert.isFalse(types.contains('Training'));

        System.runAs(userByAlias('mtdm')) {
            Assert.isNull(errorOf('Medical', 'Advisory Board'));
        }
        System.runAs(userByAlias('mtld')) {
            Assert.isNull(errorOf('L&D', 'Training'));
        }
    }

    @IsTest
    static void territoryListIncludesChildTerritories() {
        Meeting_Type__c symposium = [SELECT Id FROM Meeting_Type__c WHERE Activity_Type__c = 'Symposium'];
        symposium.Territories__c = 'Diab T';
        symposium.Creator_Titles__c = null;
        symposium.Creator_Permission_Sets__c = null;
        update symposium;
        User rep = userByAlias('mtrep');
        MeetingTypeService.UserContext diab = new MeetingTypeService.UserContext();
        diab.territoryKeys = new Set<String>{ 'diab t cairo', 'diab t dm', 'diab t', 'head office' };
        MeetingTypeService.UserContext other = new MeetingTypeService.UserContext();
        other.territoryKeys = new Set<String>{ 'git t cairo', 'git t', 'head office' };
        MeetingTypeService.TypeConfig config = MeetingTypeService.forType('Symposium');
        Assert.isNull(MeetingTypeService.blockReason(config, diab));
        Assert.isTrue(MeetingTypeService.blockReason(config, other).startsWith('Only for territories'));

        MeetingTypeService.contextOverride = new Map<Id, MeetingTypeService.UserContext>{ rep.Id => other };
        System.runAs(rep) {
            Assert.isTrue(errorOf('Marketing', 'Symposium').contains('Diab T'));
        }
    }

    @IsTest
    static void trainingScreenIsForEmployeesWithAttendance() {
        User trainer = userByAlias('mtld');
        User rep = userByAlias('mtrep');
        System.runAs(trainer) {
            Id meetingId = createMeeting('L&D', 'Training');
            MeetingLifecycleController.Workspace ws = MeetingLifecycleController.getWorkspace(meetingId);
            Assert.isFalse(ws.typeConfig.allowHcps);
            Assert.isFalse(ws.actions.canInvite, 'Training has no invitations');
            try {
                MeetingLifecycleController.addAttendee(meetingId, 'hcp', rep.Id, null);
                Assert.fail('HCPs are blocked');
            } catch (Exception e) {
                Assert.isTrue(e.getMessage().contains('HCPs cannot'));
            }
            try {
                MeetingLifecycleController.inviteAttendees(meetingId);
                Assert.fail('Invitations are blocked');
            } catch (Exception e) {
                Assert.isTrue(e.getMessage().contains('do not use invitations'));
            }
            MeetingLifecycleController.addAttendee(meetingId, 'employee', rep.Id, null);
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
            Assert.isTrue(MeetingTypeService.attendanceProblem(meeting).contains('1 not marked'));
            Meeting_Member__c member = [SELECT Id FROM Meeting_Member__c WHERE Meeting__c = :meetingId AND Colleague__c = :rep.Id];
            member.Attendance_Status__c = 'Attended';
            update member;
            Assert.isNull(MeetingTypeService.attendanceProblem(meeting));
            Assert.areEqual(100, MeetingLifecycleController.getWorkspace(meetingId).attendancePct.intValue());
        }
    }

    @IsTest
    static void rtdNeedsBrandAndHcpBeforeSubmit() {
        System.runAs(userByAlias('mtrep')) {
            Id meetingId = createMeeting('Sales', 'KOL Roundtable');
            MeetingLifecycleController.Workspace ws = MeetingLifecycleController.getWorkspace(meetingId);
            Assert.isTrue(ws.requiresHcp);
            Assert.isTrue(ws.submitBlocker.contains('brand'), ws.submitBlocker);
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
            meeting.Brand__c = null;
            Assert.isNotNull(MeetingTypeService.submitProblem(meeting));
        }
    }

    @IsTest
    static void typeChainReplacesDepartmentChain() {
        User dm = userByAlias('mtdm');
        MeetingApprovalChainService.levelsOverride = new List<Meeting_Approval_Level__c>{
            level('Medical', null, 1, 'Medical Manager', 'Manager', null),
            level('Medical', null, 2, 'CEO', 'Title', 250000),
            level('Medical', 'Advisory Board', 1, 'Medical Director', 'Specific User', null)
        };
        MeetingApprovalChainService.levelsOverride[2].Approver__c = dm.Id;
        Assert.areEqual(1, MeetingApprovalChainService.rulesFor('Medical', 'Seminar', 1000).size());
        Assert.areEqual(2, MeetingApprovalChainService.rulesFor('Medical', 'Seminar', 300000).size());
        List<Meeting_Approval_Level__c> board = MeetingApprovalChainService.rulesFor('Medical', 'Advisory Board', 300000);
        Assert.areEqual(1, board.size());
        Assert.areEqual('Medical Director', board[0].Role_Label__c);

        User rep = userByAlias('mtrep');
        Meeting__c draft = new Meeting__c(OwnerId = rep.Id, Originating_Department__c = 'Medical', Activity_Type__c = 'Advisory Board');
        List<Meeting_Approval_Step__c> steps = MeetingApprovalChainService.buildSteps(draft, 1000, 1);
        Assert.areEqual(dm.Id, steps[0].Approver__c, 'Specific User step goes to the named approver');
    }

    private static Meeting_Approval_Level__c level(String department, String types, Integer order, String label, String source, Decimal minAmount) {
        return new Meeting_Approval_Level__c(
            Department__c = department, Activity_Types__c = types, Step_Order__c = order, Role_Label__c = label,
            Role_Values__c = label, Approver_Source__c = source, Min_Amount__c = minAmount, Is_Active__c = true
        );
    }

    @IsTest
    static void setupConsoleEditsTypesAndLevels() {
        MeetingSetupController.Setup setup = MeetingSetupController.getSetup();
        Assert.isTrue(setup.canEdit);
        Assert.isFalse(setup.types.isEmpty());
        Assert.isFalse(setup.levels.isEmpty());

        MeetingTypeService.TypeConfig webinar = MeetingTypeService.forType('Webinar');
        webinar.territories = new List<String>{ 'GIT T' };
        webinar.allowDeposit = true;
        MeetingSetupController.saveType(JSON.serialize(webinar));
        Meeting_Type__c saved = [SELECT Territories__c, Allow_Deposit__c FROM Meeting_Type__c WHERE Activity_Type__c = 'Webinar'];
        Assert.areEqual('GIT T', saved.Territories__c);
        Assert.isTrue(saved.Allow_Deposit__c);

        Integer before = [SELECT COUNT() FROM Meeting_Approval_Level__c];
        MeetingSetupController.LevelRow row = new MeetingSetupController.LevelRow();
        row.department = 'Medical';
        row.activityTypes = new List<String>{ 'Advisory Board' };
        row.stepOrder = 1;
        row.roleLabel = 'Medical Director';
        row.approverSource = 'Specific User';
        row.approverId = userByAlias('mtdm').Id;
        MeetingSetupController.saveLevel(JSON.serialize(row));
        Meeting_Approval_Level__c created = [SELECT Id, Approver__c FROM Meeting_Approval_Level__c WHERE Activity_Types__c = 'Advisory Board'];
        Assert.areEqual(before + 1, [SELECT COUNT() FROM Meeting_Approval_Level__c]);
        MeetingSetupController.deleteLevel(created.Id);
        Assert.areEqual(before, [SELECT COUNT() FROM Meeting_Approval_Level__c]);

        try {
            row.approverId = null;
            MeetingSetupController.saveLevel(JSON.serialize(row));
            Assert.fail('Specific User needs an approver');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Choose the approver'));
        }

        User rep = userByAlias('mtrep');
        MeetingSetupController.Preview preview = MeetingSetupController.preview(rep.Id, 'Sales', 'KOL Roundtable', 1000);
        Assert.areEqual('Medical Rep', preview.user.title);
        Boolean boardBlocked = false;
        for (MeetingTypeService.Eligibility item : preview.types) {
            if (item.config.activityType == 'Advisory Board') {
                boardBlocked = !item.allowed;
            }
        }
        Assert.isTrue(boardBlocked);
        Assert.isTrue(!preview.steps.isEmpty() || preview.chainError != null);
        Assert.isFalse(MeetingSetupController.searchUsers('mtrep').isEmpty());
        Assert.isNotNull(MeetingSetupController.loadDefaults());
    }

    @IsTest
    static void unconfiguredOrgKeepsBuiltInRules() {
        MeetingTypeService.recordsOverride = new List<Meeting_Type__c>();
        MeetingTypeService.clearCache();
        Assert.isFalse(MeetingTypeService.isSetUp());
        Assert.isTrue(MeetingTypeService.forType('Speaker Meeting').requireTargetHcps);
        Assert.isFalse(MeetingTypeService.forType('Seminar').requireTargetHcps);
        Assert.isFalse(MeetingTypeService.allTypes().isEmpty());
        Assert.isFalse(MeetingTypeService.creatableTypes(UserInfo.getUserId()).isEmpty());
        MeetingTypeService.UserContext ctx = MeetingTypeService.contextFor(UserInfo.getUserId());
        Assert.isNotNull(ctx.userId);
    }
}
