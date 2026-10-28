@IsTest
private class MeetingLifecycleTest {
    private static final String INVOICE = EncodingUtil.base64Encode(Blob.valueOf('invoice'));

    @TestSetup
    static void setup() {
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User bum = makeUser(admin.Id, 'mlbum', 'Business Unit Manager', null);
        insert bum;
        User nsm = makeUser(admin.Id, 'mlnsm', 'National Sales Manager', bum.Id);
        insert nsm;
        User am = makeUser(admin.Id, 'mlam', 'Area Manager', nsm.Id);
        insert am;
        User dm = makeUser(admin.Id, 'mldm', 'District Manager', am.Id);
        insert dm;
        User rep = makeUser(admin.Id, 'mlrep', 'Medical Rep', dm.Id);
        User accountant = makeUser(admin.Id, 'mlacct', 'Accountant', null);
        insert new List<User>{ rep, accountant };

        PermissionSet ps = new PermissionSet(Name = 'Meeting_Accounting_Test', Label = 'Meeting Accounting Test');
        insert ps;
        CustomPermission permission = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'Meeting_Accounting' LIMIT 1];
        insert new SetupEntityAccess(ParentId = ps.Id, SetupEntityId = permission.Id);
        insert new PermissionSetAssignment(PermissionSetId = ps.Id, AssigneeId = accountant.Id);
    }

    private static User makeUser(Id profileId, String alias, String title, Id managerId) {
        return new User(
            Alias = alias,
            Email = alias + '@zeta.test',
            EmailEncodingKey = 'UTF-8',
            LastName = alias,
            FirstName = 'Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileId,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = alias + '.' + Crypto.getRandomInteger() + '@zeta.meetings.test',
            Title = title,
            ManagerId = managerId
        );
    }

    private static User userByAlias(String alias) {
        return [SELECT Id, Name FROM User WHERE Alias = :alias AND Email = :(alias + '@zeta.test') LIMIT 1];
    }

    private static void useSalesRules() {
        MeetingApprovalChainService.rulesOverride = new List<Meeting_Approval_Rule__mdt>{
            rule('Sales', 1, 'District Manager', 'Chain Role', 'District Manager;DM', null, false),
            rule('Sales', 2, 'Area Manager', 'Chain Role', 'Area Manager;AM', null, false),
            rule('Sales', 3, 'National Sales Manager', 'Chain Role', 'National Sales Manager;NSM', null, false),
            rule('Sales', 4, 'Business Unit Manager', 'Chain Role', 'Business Unit Manager;BUM', 5000, true),
            rule('Sales', 5, 'CEO', 'Title', 'Chief Meeting Officer Test', 250000, false)
        };
    }

    private static Meeting_Approval_Rule__mdt rule(
        String department, Integer order, String label, String source, String values, Decimal minAmount, Boolean strict
    ) {
        return new Meeting_Approval_Rule__mdt(
            DeveloperName = department + '_' + order,
            Department__c = department,
            Step_Order__c = order,
            Role_Label__c = label,
            Approver_Source__c = source,
            Role_Values__c = values,
            Min_Amount__c = minAmount,
            Strictly_Greater__c = strict,
            Is_Active__c = true
        );
    }

    private static Id createMeeting(String department, String activityType, DateTime startAt) {
        Map<String, Object> payload = new Map<String, Object>{
            'title' => 'Cardio evening',
            'department' => department,
            'activityType' => activityType,
            'startDateTime' => startAt,
            'endDateTime' => startAt.addHours(3),
            'venue' => 'Cairo Marriott',
            'agenda' => 'Talks',
            'estimatedParticipants' => 20
        };
        return MeetingLifecycleController.saveMeeting(JSON.serialize(payload));
    }

    private static Id addService(Id meetingId, Decimal unitCost, Decimal quantity) {
        Meeting_Service__c service = new Meeting_Service__c(Name = 'Venue hire', Department__c = 'All');
        Meeting_Vendor__c vendor = new Meeting_Vendor__c(Name = 'Marriott', Category__c = 'Venue');
        insert service;
        insert vendor;
        MeetingLifecycleController.addServiceItem(meetingId, service.Id, vendor.Id, 'Ballroom', quantity, unitCost);
        return service.Id;
    }

    private static Meeting__c reload(Id meetingId) {
        return MeetingApprovalChainService.loadMeeting(meetingId);
    }

    private static Integer approveAll(Id meetingId) {
        Integer approvals = 0;
        for (Integer i = 0; i < 10; i++) {
            Meeting__c meeting = reload(meetingId);
            if (meeting.Approval_Status__c != MeetingApprovalChainService.APPROVAL_IN_APPROVAL) {
                break;
            }
            System.runAs(new User(Id = meeting.Current_Approver__c)) {
                MeetingApprovalChainService.approve(meetingId, 'Looks good');
            }
            approvals++;
        }
        return approvals;
    }

    private static Id approvedMeeting(User rep, DateTime startAt, Decimal unitCost) {
        Id meetingId;
        System.runAs(rep) {
            meetingId = createMeeting('Sales', 'Training', startAt);
            addService(meetingId, unitCost, 2);
            MeetingLifecycleController.submitMeeting(meetingId);
        }
        approveAll(meetingId);
        return meetingId;
    }

    // ---------------------------------------------------------------- chain

    @IsTest
    static void deployedRulesFollowDepartmentAndAmount() {
        Assert.areEqual(4, MeetingApprovalChainService.rulesFor('Sales', 5000).size(), 'BU is added only above 5,000');
        Assert.areEqual(5, MeetingApprovalChainService.rulesFor('Sales', 5000.01).size());
        Assert.areEqual(6, MeetingApprovalChainService.rulesFor('Sales', 250000).size(), 'CEO joins at 250,000');
        Assert.areEqual(3, MeetingApprovalChainService.rulesFor('Marketing', 1000).size());
        Assert.areEqual(4, MeetingApprovalChainService.rulesFor('Marketing', 250000).size());
        Assert.areEqual(1, MeetingApprovalChainService.rulesFor('Medical', 1000).size());
        Assert.areEqual(2, MeetingApprovalChainService.rulesFor('Medical', 300000).size());
        Assert.areEqual(2, MeetingApprovalChainService.rulesFor('L&D', 300000).size());
    }

    @IsTest
    static void salesChainRoutesThroughLineAndApproves() {
        useSalesRules();
        User rep = userByAlias('mlrep');
        User dm = userByAlias('mldm');
        Id meetingId;
        Test.startTest();
        System.runAs(rep) {
            meetingId = createMeeting('Sales', 'Training', System.now().addDays(5));
            addService(meetingId, 3000, 2);
            MeetingLifecycleController.Workspace ws = MeetingLifecycleController.submitMeeting(meetingId);
            Assert.areEqual('waiting', ws.meeting.stage);
        }
        Meeting__c submitted = reload(meetingId);
        Assert.areEqual('PendingApproval', submitted.Status__c);
        Assert.areEqual(dm.Id, submitted.Current_Approver__c);
        Assert.areEqual(6000, submitted.Planned_Cost__c);

        List<Meeting_Approval_Step__c> steps = [
            SELECT Approver_Role__c, Status__c FROM Meeting_Approval_Step__c WHERE Meeting__c = :meetingId ORDER BY Step_Number__c
        ];
        Assert.areEqual(4, steps.size(), 'DM, AM, NSM, BU; CEO is below threshold');
        Assert.areEqual('Pending', steps[0].Status__c);

        System.runAs(dm) {
            MeetingLifecycleController.HomeData home = MeetingLifecycleController.getHome();
            Assert.areEqual(1, home.approvals.size());
            Assert.areEqual(1, MeetingApprovalAccess.getPendingApprovals(dm.Id).size());
            MeetingPlannerController.approveMeetingPlan(meetingId);
        }
        Integer remaining = approveAll(meetingId);
        Test.stopTest();

        Assert.areEqual(3, remaining);
        Meeting__c approved = reload(meetingId);
        Assert.areEqual('Approved', approved.Status__c);
        Assert.areEqual('Fully Approved', approved.Approval_Status__c);
        Assert.areEqual(6000, approved.Approved_Planned_Cost__c);
        Assert.isNull(approved.Current_Approver__c);
    }

    @IsTest
    static void rejectionReturnsMeetingToDraft() {
        useSalesRules();
        User rep = userByAlias('mlrep');
        User dm = userByAlias('mldm');
        Id meetingId;
        System.runAs(rep) {
            meetingId = createMeeting('Sales', 'Training', System.now().addDays(5));
            MeetingLifecycleController.submitMeeting(meetingId);
        }
        Test.startTest();
        System.runAs(dm) {
            try {
                MeetingLifecycleController.rejectMeeting(meetingId, '');
                Assert.fail('Reason is required');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('reason'));
            }
            MeetingPlannerController.rejectMeetingPlan(meetingId, 'Budget too high');
        }
        Test.stopTest();
        Meeting__c rejected = reload(meetingId);
        Assert.areEqual('Draft', rejected.Status__c);
        Assert.areEqual('Rejected', rejected.Approval_Status__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Meeting_Approval_Step__c WHERE Meeting__c = :meetingId AND Status__c IN ('Waiting', 'Pending')]);
    }

    @IsTest
    static void wrongApproverCannotDecide() {
        useSalesRules();
        User rep = userByAlias('mlrep');
        User nsm = userByAlias('mlnsm');
        Id meetingId;
        System.runAs(rep) {
            meetingId = createMeeting('Sales', 'Training', System.now().addDays(5));
            MeetingLifecycleController.submitMeeting(meetingId);
        }
        System.runAs(nsm) {
            try {
                MeetingLifecycleController.approveMeeting(meetingId, null);
                Assert.fail('Only the current approver can approve');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('another approver'));
            }
        }
    }

    @IsTest
    static void medicalChainUsesManagerAndFallsBackWhenEmpty() {
        User rep = userByAlias('mlrep');
        User dm = userByAlias('mldm');
        Id meetingId;
        System.runAs(rep) {
            meetingId = createMeeting('Medical', 'Webinar', System.now().addDays(5));
            MeetingLifecycleController.submitMeeting(meetingId);
        }
        Assert.areEqual(dm.Id, reload(meetingId).Current_Approver__c);

        MeetingApprovalChainService.rulesOverride = new List<Meeting_Approval_Rule__mdt>{
            rule('Marketing', 1, 'Brand Manager', 'Chain Role', 'Nobody Has This Title', null, false)
        };
        Id marketingId;
        System.runAs(rep) {
            marketingId = createMeeting('Marketing', 'Seminar', System.now().addDays(6));
            MeetingLifecycleController.submitMeeting(marketingId);
        }
        Assert.areEqual(dm.Id, reload(marketingId).Current_Approver__c, 'Falls back to the requester manager');
        Assert.areEqual(1, [SELECT COUNT() FROM Meeting_Approval_Step__c WHERE Meeting__c = :marketingId AND Status__c = 'Skipped']);
    }

    @IsTest
    static void speakerMeetingNeedsTargetHcp() {
        User rep = userByAlias('mlrep');
        System.runAs(rep) {
            Id meetingId = createMeeting('Sales', 'Speaker Meeting', System.now().addDays(5));
            Assert.areEqual('Speaker_Meeting', [SELECT RecordType.DeveloperName FROM Meeting__c WHERE Id = :meetingId].RecordType.DeveloperName);
            MeetingLifecycleController.Workspace ws = MeetingLifecycleController.getWorkspace(meetingId);
            Assert.isTrue(ws.requiresHcp);
            Assert.isTrue(ws.submitBlocker.contains('HCP'));
            Boolean blocked = false;
            try {
                MeetingLifecycleController.submitMeeting(meetingId);
            } catch (AuraHandledException e) {
                blocked = true;
            }
            Assert.isTrue(blocked, 'HCP attendee is required');
            Assert.areEqual('Draft', reload(meetingId).Status__c);
        }
    }

    // ---------------------------------------------------------------- money

    @IsTest
    static void depositThenActualCostUnderThresholdGoesToAccounting() {
        useSalesRules();
        User rep = userByAlias('mlrep');
        User accountant = userByAlias('mlacct');
        Id meetingId = approvedMeeting(rep, System.now().addHours(-2), 1500);

        Test.startTest();
        System.runAs(rep) {
            try {
                MeetingLifecycleController.submitDeposit(meetingId, 1000, null, null);
                Assert.fail('Invoice required');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('invoice'));
            }
            MeetingLifecycleController.submitDeposit(meetingId, 1000, 'deposit.pdf', INVOICE);
            try {
                MeetingLifecycleController.submitDeposit(meetingId, 500, 'deposit2.pdf', INVOICE);
                Assert.fail('Only one deposit');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('already'));
            }
        }
        System.runAs(accountant) {
            Assert.isTrue(MeetingLifecycleController.getHome().isAccounting);
            Assert.isFalse(MeetingLifecycleController.getAccountingQueue().isEmpty());
            MeetingLifecycleController.recordPayment(meetingId, 1000, Date.today(), 'DEP-1');
        }
        Assert.areEqual('Paid', reload(meetingId).Payment_Status__c);

        System.runAs(rep) {
            MeetingLifecycleController.markExecuted(meetingId);
            MeetingLifecycleController.submitActualCost(meetingId, 3200, 'final.pdf', INVOICE);
            try {
                MeetingLifecycleController.submitDeposit(meetingId, 100, 'late.pdf', INVOICE);
                Assert.fail('No deposit after actual cost');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('actual cost'));
            }
        }
        Meeting__c withActual = reload(meetingId);
        Assert.areEqual('In Accounting', withActual.Payment_Status__c, '6.7% over plan goes straight to accounting');
        Assert.areEqual(2200, withActual.Remaining_Amount__c);

        System.runAs(accountant) {
            try {
                MeetingLifecycleController.recordPayment(meetingId, 5000, null, null);
                Assert.fail('Cannot overpay');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('remaining'));
            }
            MeetingLifecycleController.recordPayment(meetingId, 1200, null, 'PAY-1');
        }
        Meeting__c partial = reload(meetingId);
        Assert.areEqual('Partial Paid', partial.Payment_Status__c);
        Assert.areEqual('Incomplete', partial.Status__c);
        Assert.areEqual(1000, partial.Remaining_Amount__c);

        System.runAs(accountant) {
            MeetingLifecycleController.recordPayment(meetingId, 1000, null, 'PAY-2');
        }
        Meeting__c paid = reload(meetingId);
        Assert.areEqual('Paid', paid.Payment_Status__c);
        Assert.areEqual('Concluded', paid.Status__c);

        System.runAs(rep) {
            MeetingLifecycleController.Workspace ws = MeetingLifecycleController.closeMeeting(meetingId);
            Assert.areEqual('Closed', ws.meeting.status);
            Assert.areEqual(3, ws.payments.size());
            Assert.isFalse(ws.files.isEmpty());
            Assert.isFalse(ws.history.isEmpty());
        }
        Test.stopTest();
    }

    @IsTest
    static void actualCostOverThresholdRestartsApproval() {
        useSalesRules();
        User rep = userByAlias('mlrep');
        User accountant = userByAlias('mlacct');
        Id meetingId = approvedMeeting(rep, System.now().addHours(-2), 1500);
        System.runAs(rep) {
            MeetingFinanceService.markExecuted(meetingId);
        }

        Test.startTest();
        System.runAs(rep) {
            MeetingLifecycleController.submitActualCost(meetingId, 3600, 'final.pdf', INVOICE);
        }
        Meeting__c reapproval = reload(meetingId);
        Assert.areEqual('Actual Cost Entered', reapproval.Payment_Status__c);
        Assert.areEqual('In Approval', reapproval.Approval_Status__c);
        Assert.areEqual(2, reapproval.Approval_Round__c);

        System.runAs(new User(Id = reapproval.Current_Approver__c)) {
            MeetingLifecycleController.rejectMeeting(meetingId, 'Explain the overrun');
        }
        Meeting__c returned = reload(meetingId);
        Assert.areEqual('Returned to Business', returned.Payment_Status__c);
        Assert.areEqual('Concluded', returned.Status__c);

        System.runAs(rep) {
            MeetingLifecycleController.submitActualCost(meetingId, 3500, null, null);
        }
        Assert.areEqual(3, reload(meetingId).Approval_Round__c);
        approveAll(meetingId);
        Meeting__c approved = reload(meetingId);
        Assert.areEqual('In Accounting', approved.Payment_Status__c);
        Assert.areEqual('Fully Approved', approved.Approval_Status__c);
        Test.stopTest();

        System.runAs(accountant) {
            MeetingLifecycleController.sendBackToBusiness(meetingId, 'Invoice is unreadable');
        }
        Meeting__c sentBack = reload(meetingId);
        Assert.areEqual('Returned to Business', sentBack.Payment_Status__c);
        Assert.isTrue(sentBack.Accounting_Notes__c.contains('unreadable'));
    }

    @IsTest
    static void accountingActionsNeedPermission() {
        useSalesRules();
        User rep = userByAlias('mlrep');
        Id meetingId = approvedMeeting(rep, System.now().addHours(-2), 1500);
        System.runAs(rep) {
            MeetingLifecycleController.submitDeposit(meetingId, 1000, 'deposit.pdf', INVOICE);
            try {
                MeetingLifecycleController.recordPayment(meetingId, 100, null, null);
                Assert.fail('Accounting permission required');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Accounting'));
            }
            try {
                MeetingLifecycleController.getAccountingQueue();
                Assert.fail('Accounting permission required');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e);
            }
        }
    }

    @IsTest
    static void cancelSkipsOpenSteps() {
        useSalesRules();
        User rep = userByAlias('mlrep');
        System.runAs(rep) {
            Id meetingId = createMeeting('Sales', 'Conference', System.now().addDays(9));
            MeetingLifecycleController.submitMeeting(meetingId);
            try {
                MeetingLifecycleController.cancelMeeting(meetingId, ' ');
                Assert.fail('Reason required');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e);
            }
            MeetingLifecycleController.Workspace ws = MeetingLifecycleController.cancelMeeting(meetingId, 'Speaker unavailable');
            Assert.areEqual('Cancelled', ws.meeting.status);
            Assert.areEqual('closed', ws.meeting.stage);
            Assert.areEqual(0, [SELECT COUNT() FROM Meeting_Approval_Step__c WHERE Meeting__c = :meetingId AND Status__c IN ('Waiting', 'Pending')]);
        }
    }

    @IsTest
    static void brandChainHonorariumAndRepCharge() {
        useSalesRules();
        User rep = userByAlias('mlrep');
        System.runAs(rep) {
            Id meetingId = createMeeting('Sales', 'Training', System.now().addDays(4));
            MeetingLifecycleController.Workspace preview = MeetingLifecycleController.getWorkspace(meetingId);
            Assert.isTrue(preview.approvalPreview, 'Draft shows the approval chain before submit');
            Assert.isFalse(preview.steps.isEmpty(), 'Approval chain lists the approvers');

            Product2 brand = new Product2(Name = 'Lifecycle Brand', IsActive = true);
            insert brand;
            MeetingLifecycleController.Workspace branded = MeetingLifecycleController.setMeetingBrand(meetingId, brand.Id);
            Assert.areEqual(brand.Id, branded.brandId);

            MeetingHcpAttendeeService.seedRequiredHcpAttendeeForTest(meetingId);
            Id hcpId = [
                SELECT Customer__c FROM Meeting_Member__c
                WHERE Meeting__c = :meetingId AND Customer__c != NULL
                LIMIT 1
            ].Customer__c;
            update new Account(Id = hcpId, Honorarium_Fee__c = 1500);

            List<MeetingLifecycleController.PersonRow> found = MeetingLifecycleController.searchPeople(meetingId, 'hcp', 'Meeting Test');
            Assert.isFalse(found.isEmpty(), 'Cognitive search finds the aligned or target HCP');

            Meeting_Service__c honorarium = new Meeting_Service__c(Name = 'Speaker honorarium', Department__c = 'All');
            insert honorarium;
            Boolean needsSpeaker = false;
            try {
                MeetingLifecycleController.addServiceItem(meetingId, honorarium.Id, null, null, 1, 10, null, null);
            } catch (Exception ex) {
                needsSpeaker = true;
            }
            Assert.isTrue(needsSpeaker, 'Honorarium requires an HCP');

            MeetingLifecycleController.addServiceItem(meetingId, honorarium.Id, null, null, 1, 10, hcpId, rep.Id);
            MeetingLifecycleController.Workspace ws = MeetingLifecycleController.getWorkspace(meetingId);
            MeetingLifecycleController.ServiceRow line;
            for (MeetingLifecycleController.ServiceRow row : ws.services) {
                if (row.serviceName == 'Speaker honorarium') {
                    line = row;
                }
            }
            Assert.isNotNull(line);
            Assert.areEqual(1500, line.unitCost);
            Assert.areEqual(rep.Name, line.chargedToName);
            Assert.isNotNull(line.speakerName);
        }
    }

    // ---------------------------------------------------------------- workspace and invitations

    @IsTest
    static void workspaceEditsAttendeesAndInvitations() {
        User rep = userByAlias('mlrep');
        User accountant = userByAlias('mlacct');
        Test.startTest();
        System.runAs(rep) {
            Id meetingId = createMeeting('L&D', 'Training', System.now().addHours(-1));
            Map<String, Object> edit = new Map<String, Object>{
                'id' => meetingId,
                'title' => 'Updated training',
                'department' => 'L&D',
                'activityType' => 'Training',
                'startDateTime' => System.now().addHours(-1),
                'endDateTime' => System.now().addHours(2),
                'venue' => 'HQ'
            };
            MeetingLifecycleController.saveMeeting(JSON.serialize(edit));
            Id serviceId = addService(meetingId, 250, 4);
            MeetingLifecycleController.Workspace ws = MeetingLifecycleController.getWorkspace(meetingId);
            Assert.areEqual('Updated training', ws.meeting.title);
            Assert.areEqual(1, ws.services.size());
            MeetingLifecycleController.removeServiceItem(ws.services[0].id);

            Assert.isFalse(MeetingLifecycleController.searchPeople(meetingId, 'employee', 'mlacct').isEmpty());
            MeetingLifecycleController.searchPeople(meetingId, 'hcp', 'zz');
            MeetingLifecycleController.addAttendee(meetingId, 'employee', accountant.Id, null);
            MeetingLifecycleController.addAttendee(meetingId, 'guest', null, 'Dr. Guest');
            try {
                MeetingLifecycleController.addAttendee(meetingId, 'employee', accountant.Id, null);
                Assert.fail('Duplicate colleague');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e);
            }

            ws = MeetingLifecycleController.inviteAttendees(meetingId);
            Assert.areEqual(2, ws.invitations.size());
            ws = MeetingLifecycleController.addGuestInvitation(meetingId, 'Walk-in Pharmacist', '01001234567', 'walkin@example.com');
            Assert.areEqual(3, ws.invitations.size());

            MeetingInvitationService.InvitationRow guest;
            for (MeetingInvitationService.InvitationRow row : ws.invitations) {
                Assert.isNotNull(row.code);
                Assert.areEqual(MeetingInvitationService.TEST_SITE_BASE + '/?c=' + row.code, row.link);
                if (row.guestName == 'Walk-in Pharmacist') {
                    guest = row;
                }
            }
            MeetingInvitationService.InvitationRow sent = MeetingLifecycleController.markInvitationSent(guest.id, null);
            Assert.areEqual('Sent', sent.status);
            Assert.isTrue(sent.whatsappUrl.startsWith('https://wa.me/201001234567?text='));
            Assert.areEqual('walkin@example.com', sent.email);
            MeetingInvitationService.InvitationRow emailed = MeetingLifecycleController.sendInvitationEmail(guest.id, 'pharmacist@example.com');
            Assert.areEqual('pharmacist@example.com', emailed.email);
            Assert.areEqual('Sent', emailed.status);

            Id memberId;
            for (MeetingLifecycleController.MemberRow member : ws.members) {
                if (member.kind == 'guest') {
                    memberId = member.id;
                }
            }
            MeetingLifecycleController.setInvitationActive(guest.id, false);
            MeetingLifecycleController.removeAttendee(memberId);
            Assert.areEqual(2, MeetingLifecycleController.getWorkspace(meetingId).invitations.size());
            Assert.isNotNull(MeetingLifecycleController.getOptions().departments);
        }
        Test.stopTest();
    }

    @IsTest
    static void publicPageShowsLivePassAndDoorScanChecksIn() {
        useSalesRules();
        User rep = userByAlias('mlrep');
        User accountant = userByAlias('mlacct');
        Id meetingId = approvedMeeting(rep, System.now().addMinutes(-30), 500);
        Id futureId;
        System.runAs(rep) {
            MeetingLifecycleController.addAttendee(meetingId, 'employee', accountant.Id, null);
            MeetingLifecycleController.inviteAttendees(meetingId);
            futureId = createMeeting('Medical', 'Webinar', System.now().addDays(10));
            MeetingLifecycleController.addGuestInvitation(futureId, 'Dr. Future', null, null);
        }
        Meeting_Invitation__c today = [
            SELECT Code__c, Meeting_Member__c, Qr_Secret__c, Email__c FROM Meeting_Invitation__c WHERE Meeting__c = :meetingId LIMIT 1
        ];
        Meeting_Invitation__c later = [SELECT Code__c, Qr_Secret__c FROM Meeting_Invitation__c WHERE Meeting__c = :futureId LIMIT 1];
        Assert.areEqual(64, today.Qr_Secret__c.length());
        Assert.isNotNull(today.Email__c, 'Colleague email is copied to the invitation');

        Test.startTest();
        Test.setCurrentPage(Page.m);
        ApexPages.currentPage().getParameters().put('c', today.Code__c);
        ApexPages.currentPage().getHeaders().put('User-Agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Mobile');
        MeetingCheckInController page = new MeetingCheckInController();
        page.logScan();
        Assert.isFalse(page.invalid);
        Assert.isTrue(page.showQr);
        Assert.isTrue(page.doorOpen);
        Assert.areEqual(today.Qr_Secret__c, page.qrSecret);
        Assert.areEqual(today.Code__c, page.code, 'The page signs the QR with the invitation code');
        Assert.areEqual('ZM1', page.tokenPrefix);
        Assert.isTrue(page.serverMillis > 0);
        Assert.areEqual(60, page.tokenStepSeconds);
        Assert.areEqual('Awaiting your reply', page.statusLabel);
        Assert.areEqual('Not Sent', MeetingCheckInController.currentStatus(today.Code__c));

        Long step = MeetingInvitationService.tokenStep(System.now().getTime());
        String live = MeetingInvitationService.buildToken(today.Qr_Secret__c, today.Code__c, step - 1);
        String stale = MeetingInvitationService.buildToken(today.Qr_Secret__c, today.Code__c, step - 3);
        String forged = MeetingInvitationService.buildToken('0000', today.Code__c, step);
        String otherMeeting = MeetingInvitationService.buildToken(later.Qr_Secret__c, later.Code__c, step);
        System.runAs(rep) {
            Assert.areEqual('invalid', MeetingLifecycleController.scanAttendee(meetingId, 'https://example.com').outcome);
            Assert.areEqual('invalid', MeetingLifecycleController.scanAttendee(meetingId, forged).outcome);
            Assert.areEqual('expired', MeetingLifecycleController.scanAttendee(meetingId, stale).outcome);
            Assert.areEqual('other_meeting', MeetingLifecycleController.scanAttendee(meetingId, otherMeeting).outcome);
            MeetingInvitationService.ScanResult ok = MeetingLifecycleController.scanAttendee(meetingId, live);
            Assert.areEqual('checked_in', ok.outcome);
            Assert.isTrue(ok.ok);
            Assert.areEqual(1, ok.checkedInCount);
            Assert.areEqual('already', MeetingLifecycleController.scanAttendee(meetingId, live).outcome);
        }
        Assert.areEqual('Checked In', MeetingCheckInController.currentStatus(today.Code__c));
        Assert.areEqual('Invalid', MeetingCheckInController.currentStatus('nope'));

        MeetingCheckInController after = new MeetingCheckInController();
        Assert.isTrue(after.checkedIn);
        Assert.isTrue(after.showQr, 'Checked-in guests can still open the entry pass');

        update new Meeting_Invitation__c(Id = later.Id, Qr_Secret__c = null);
        ApexPages.currentPage().getParameters().put('c', later.Code__c);
        MeetingCheckInController futurePage = new MeetingCheckInController();
        futurePage.logScan();
        Assert.isFalse(String.isBlank(futurePage.qrSecret), 'Older invitations get a signing key on first open');
        Assert.isTrue(futurePage.canConfirm);
        Assert.isFalse(futurePage.doorOpen);
        Assert.isNotNull(futurePage.qrLibScript);
        Assert.isNotNull(futurePage.logoDataUri);

        ApexPages.currentPage().getParameters().put('s', '1');
        MeetingCheckInController poll = new MeetingCheckInController();
        poll.logScan();
        Assert.isTrue(poll.statusOnly);
        Assert.areEqual('Not Sent', poll.status);

        ApexPages.currentPage().getParameters().remove('s');
        Assert.isTrue(futurePage.hasCalendar);
        Assert.isTrue(futurePage.googleCalendarUrl.startsWith('https://calendar.google.com/calendar/render?action=TEMPLATE'));
        Assert.areEqual('text/html', futurePage.contentType);
        Assert.areEqual('./?c=' + later.Code__c + '&a=confirm', futurePage.confirmUrl);
        Assert.areEqual('./?c=' + later.Code__c + '&f=ics', futurePage.icsUrl);
        Assert.areEqual('./?f=manifest&c=' + later.Code__c, futurePage.manifestUrl);

        ApexPages.currentPage().getParameters().put('f', 'manifest');
        MeetingCheckInController manifestPage = new MeetingCheckInController();
        manifestPage.logScan();
        Assert.areEqual('application/manifest+json', manifestPage.contentType);
        Map<String, Object> manifest = (Map<String, Object>) JSON.deserializeUntyped(manifestPage.manifestJson);
        Assert.areEqual('Zeta Pharma', manifest.get('name'));
        Assert.areEqual('./?c=' + later.Code__c, manifest.get('start_url'));
        Assert.areEqual(3, ((List<Object>) manifest.get('icons')).size());

        ApexPages.currentPage().getParameters().put('f', 'sw');
        MeetingCheckInController swPage = new MeetingCheckInController();
        Assert.areEqual('text/javascript', swPage.contentType);
        Assert.isTrue(swPage.swScript.contains('caches.open'));

        ApexPages.currentPage().getParameters().put('f', 'ics');
        MeetingCheckInController icsPage = new MeetingCheckInController();
        icsPage.logScan();
        Assert.areEqual('text/calendar', icsPage.contentType);
        String ics = icsPage.icsText;
        Assert.isTrue(ics.startsWith('BEGIN:VCALENDAR'));
        Assert.isTrue(ics.contains('TRIGGER:-P1D'));
        Assert.isTrue(ics.contains('TRIGGER:-PT2H'));
        Assert.areEqual('a\\, b\\; c\\nd', MeetingCheckInController.icsEscape('a, b; c\nd'));
        ApexPages.currentPage().getParameters().remove('f');
        ApexPages.currentPage().getParameters().put('a', 'confirm');
        MeetingCheckInController confirmed = new MeetingCheckInController();
        confirmed.logScan();
        Assert.areEqual('Confirmed', confirmed.status);
        Assert.areEqual('Attending', confirmed.statusLabel);
        Assert.isFalse(confirmed.canConfirm);
        ApexPages.currentPage().getParameters().remove('a');
        System.runAs(rep) {
            Assert.isTrue(MeetingLifecycleController.getWorkspace(futureId).actions.canScan, 'Draft meetings with invitations can be scanned');
            String laterLive = MeetingInvitationService.buildToken(futurePage.qrSecret, later.Code__c, step);
            MeetingInvitationService.ScanResult early = MeetingLifecycleController.scanAttendee(futureId, laterLive);
            Assert.areEqual('closed', early.outcome);
            Assert.isTrue(early.message.startsWith('Door check-in opens '), early.message);
        }

        ApexPages.currentPage().getParameters().put('c', today.Code__c.toUpperCase() + 'x');
        Assert.isTrue(new MeetingCheckInController().invalid);
        Test.stopTest();

        Assert.areEqual('Attended', [SELECT Attendance_Status__c FROM Meeting_Member__c WHERE Id = :today.Meeting_Member__c].Attendance_Status__c);
        Assert.areEqual(3, [SELECT COUNT() FROM Meeting_QR_Scan__c WHERE Is_Bot__c = false], 'Status polls are not logged as visits');
        Assert.areEqual('Tablet', MeetingCheckInController.device('Mozilla/5.0 (iPad; CPU OS 17_0)'));
        Assert.areEqual('Android', MeetingCheckInController.os('Mozilla/5.0 (Linux; Android 14) Mobile'));
        Assert.isTrue(MeetingCheckInController.buildScan(today.Id, 'WhatsApp/2.23').Is_Bot__c);
    }

    @IsTest
    static void attendanceMarksInvitationCheckedIn() {
        useSalesRules();
        User rep = userByAlias('mlrep');
        User accountant = userByAlias('mlacct');
        Id meetingId = approvedMeeting(rep, System.now().addMinutes(-30), 500);
        System.runAs(rep) {
            MeetingLifecycleController.addAttendee(meetingId, 'employee', accountant.Id, null);
            MeetingLifecycleController.inviteAttendees(meetingId);
            Id memberId = [SELECT Id FROM Meeting_Member__c WHERE Meeting__c = :meetingId AND Colleague__c = :accountant.Id].Id;
            MeetingLifecycleController.setAttendance(memberId, 'Attended');
        }
        Assert.areEqual('Checked In', [SELECT Status__c FROM Meeting_Invitation__c WHERE Meeting__c = :meetingId].Status__c);
        System.runAs(accountant) {
            Assert.isNotNull(MeetingLifecycleController.getWorkspace(meetingId), 'Attending colleagues can open the meeting');
        }
    }

    @IsTest
    static void helpersFormatAndMap() {
        Assert.areEqual('201001234567', MeetingInvitationService.digits('01001234567'));
        Assert.areEqual('201001234567', MeetingInvitationService.digits('00201001234567'));
        Assert.areEqual('', MeetingInvitationService.digits(null));
        Assert.areEqual(0, MeetingFinanceService.increasePct(0, 0));
        Assert.areEqual(100, MeetingFinanceService.increasePct(0, 10));
        Assert.areEqual(10, MeetingFinanceService.increasePct(100, 110));
        Assert.isNull(MeetingLifecycleController.recordTypeFor(null));
        Assert.isNotNull(MeetingLifecycleController.recordTypeFor('KOL Roundtable'));
        Assert.areEqual('EGP', MeetingFinanceService.currencyCode());
        Assert.areEqual(10, MeetingFinanceService.reapprovalThresholdPct());
        Assert.areEqual('ready', MeetingLifecycleController.stageOf(new Meeting__c(Status__c = 'Approved')));
        Assert.areEqual('cost', MeetingLifecycleController.stageOf(new Meeting__c(Status__c = 'Concluded')));
        Assert.areEqual('draft', MeetingLifecycleController.stageOf(new Meeting__c(Status__c = 'Draft')));
    }
}
