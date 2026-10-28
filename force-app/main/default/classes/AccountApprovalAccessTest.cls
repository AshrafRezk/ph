@IsTest
private class AccountApprovalAccessTest {
    @IsTest
    static void isTerritoryManager_handlesNullUserId() {
        System.assertEquals(false, AccountApprovalAccess.isTerritoryManager(null));
    }

    @IsTest
    static void trainerTerritoryRoleCountsAsAccountApprover() {
        VisitActorAccess.testCanViewServiceRequests = false;
        List<Territory2> territories = [SELECT Id FROM Territory2 LIMIT 1];
        if (territories.isEmpty()) {
            return;
        }
        insert new UserTerritory2Association(
            UserId = UserInfo.getUserId(),
            Territory2Id = territories[0].Id,
            RoleInTerritory2 = 'Trainer'
        );

        Test.startTest();
        System.assertEquals(true, AccountApprovalAccess.isTerritoryManager());
        Test.stopTest();

        VisitActorAccess.testCanViewServiceRequests = null;
    }

    @IsTest
    static void approveAndReject_requireAccountId() {
        VisitActorAccess.testCanViewServiceRequests = true;
        Boolean approveFailed = false;
        Boolean rejectFailed = false;
        Test.startTest();
        try {
            AccountApprovalAccess.approveAccount(null);
        } catch (AuraHandledException ex) {
            approveFailed = true;
        }
        try {
            AccountApprovalAccess.rejectAccount(null, 'Reason');
        } catch (AuraHandledException ex) {
            rejectFailed = true;
        }
        Test.stopTest();
        System.assertEquals(true, approveFailed);
        System.assertEquals(true, rejectFailed);
        VisitActorAccess.testCanViewServiceRequests = null;
    }

    @IsTest
    static void repSeesOwnPendingWithoutActions() {
        VisitActorAccess.testCanViewServiceRequests = false;
        Account pending = new Account(
            Name = 'My Pending Account',
            Account_Stage__c = AccountStageService.STAGE_DM
        );
        insert pending;

        Test.startTest();
        List<AccountApprovalAccess.ApprovalRow> rows = AccountApprovalAccess.getPendingApprovals();
        Test.stopTest();

        System.assertEquals(false, AccountApprovalAccess.isTerritoryManager());
        System.assertEquals(1, rows.size());
        System.assertEquals(pending.Id, rows[0].accountId);
        System.assertEquals(false, rows[0].canAct);
        System.assertEquals(true, rows[0].createdByMe);
        System.assertEquals('Pending DM', rows[0].stageLabel);
        VisitActorAccess.testCanViewServiceRequests = null;
    }

    @IsTest
    static void nonManagerGetsEmptyQueue() {
        VisitActorAccess.testCanViewServiceRequests = false;
        Test.startTest();
        System.assertEquals(false, AccountApprovalAccess.isTerritoryManager());
        System.assertEquals(0, AccountApprovalAccess.getPendingApprovals().size());
        System.assertEquals(0, AccountApprovalAccess.getPendingApprovalCount());
        Test.stopTest();
        VisitActorAccess.testCanViewServiceRequests = null;
    }

    @IsTest
    static void approveAccount_rejectsWhenNotPendingDm() {
        VisitActorAccess.testCanViewServiceRequests = true;
        AccountApprovalAccess.testTeamRepIds = new Set<Id>{ UserInfo.getUserId() };
        Account active = new Account(
            Name = 'Already Active',
            Account_Stage__c = AccountStageService.STAGE_ACTIVE
        );
        insert active;

        Boolean failed = false;
        Test.startTest();
        try {
            AccountApprovalAccess.approveAccount(active.Id);
        } catch (AuraHandledException ex) {
            failed = true;
        }
        Test.stopTest();
        System.assertEquals(true, failed);
        VisitActorAccess.testCanViewServiceRequests = null;
        AccountApprovalAccess.testTeamRepIds = null;
    }

    @IsTest
    static void managerSeesPendingTeamAccounts() {
        VisitActorAccess.testCanViewServiceRequests = true;
        AccountApprovalAccess.testTeamRepIds = new Set<Id>{ UserInfo.getUserId() };

        Account pending = new Account(
            Name = 'Pending DM Account',
            Account_Stage__c = AccountStageService.STAGE_DM
        );
        insert pending;

        Test.startTest();
        List<AccountApprovalAccess.ApprovalRow> rows = AccountApprovalAccess.getPendingApprovals();
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(pending.Id, rows[0].accountId);
        System.assertEquals(true, rows[0].createdByMe);
        System.assertEquals(false, rows[0].canAct);
        System.assertEquals('Pending DM', rows[0].stageLabel);

        VisitActorAccess.testCanViewServiceRequests = null;
        AccountApprovalAccess.testTeamRepIds = null;
    }

    @IsTest
    static void managerApprovesToSfe() {
        VisitActorAccess.testCanViewServiceRequests = true;
        AccountApprovalAccess.testTeamRepIds = new Set<Id>{ UserInfo.getUserId() };

        Account pending = new Account(
            Name = 'Approve Me',
            Account_Stage__c = AccountStageService.STAGE_DM
        );
        insert pending;

        Test.startTest();
        AccountApprovalAccess.approveAccount(pending.Id);
        Test.stopTest();

        Account refreshed = [
            SELECT Account_Stage__c, Account_Status__c
            FROM Account
            WHERE Id = :pending.Id
        ];
        System.assertEquals(AccountStageService.STAGE_SFE, refreshed.Account_Stage__c);

        VisitActorAccess.testCanViewServiceRequests = null;
        AccountApprovalAccess.testTeamRepIds = null;
    }

    @IsTest
    static void managerRejectReturnsToDraft() {
        VisitActorAccess.testCanViewServiceRequests = true;
        AccountApprovalAccess.testTeamRepIds = new Set<Id>{ UserInfo.getUserId() };

        Account pending = new Account(
            Name = 'Reject Me',
            Account_Stage__c = AccountStageService.STAGE_DM
        );
        insert pending;

        Test.startTest();
        AccountApprovalAccess.rejectAccount(pending.Id, 'Incomplete address');
        Test.stopTest();

        Account refreshed = [SELECT Account_Stage__c FROM Account WHERE Id = :pending.Id];
        System.assertEquals(AccountStageService.STAGE_DRAFT, refreshed.Account_Stage__c);

        VisitActorAccess.testCanViewServiceRequests = null;
        AccountApprovalAccess.testTeamRepIds = null;
    }

    @IsTest
    static void nonManagerCannotApprove() {
        VisitActorAccess.testCanViewServiceRequests = false;
        Account pending = new Account(
            Name = 'Protected',
            Account_Stage__c = AccountStageService.STAGE_DM
        );
        insert pending;

        Boolean failed = false;
        Test.startTest();
        try {
            AccountApprovalAccess.approveAccount(pending.Id);
        } catch (AuraHandledException ex) {
            failed = true;
        }
        Test.stopTest();
        System.assertEquals(true, failed);
        VisitActorAccess.testCanViewServiceRequests = null;
    }

    @IsTest
    static void loadPendingTeamAccountIds_returnsMatchingAccounts() {
        VisitActorAccess.testCanViewServiceRequests = true;
        AccountApprovalAccess.testTeamRepIds = new Set<Id>{ UserInfo.getUserId() };
        Account pending = new Account(
            Name = 'Pending Id Set',
            Account_Stage__c = AccountStageService.STAGE_DM
        );
        insert pending;

        Test.startTest();
        Set<Id> ids = AccountApprovalAccess.loadPendingTeamAccountIds();
        Test.stopTest();

        System.assert(ids.contains(pending.Id));
        VisitActorAccess.testCanViewServiceRequests = null;
        AccountApprovalAccess.testTeamRepIds = null;
    }

    @IsTest
    static void rejectAccount_requiresReasonForWrongStage() {
        VisitActorAccess.testCanViewServiceRequests = true;
        AccountApprovalAccess.testTeamRepIds = new Set<Id>{ UserInfo.getUserId() };
        Account draft = new Account(
            Name = 'Not Pending',
            Account_Stage__c = AccountStageService.STAGE_DRAFT
        );
        insert draft;

        Boolean failed = false;
        Test.startTest();
        try {
            AccountApprovalAccess.rejectAccount(draft.Id, 'Too early');
        } catch (AuraHandledException ex) {
            failed = true;
        }
        Test.stopTest();
        System.assertEquals(true, failed);
        VisitActorAccess.testCanViewServiceRequests = null;
        AccountApprovalAccess.testTeamRepIds = null;
    }

    @IsTest
    static void getPendingApprovalCount_matchesQueueSize() {
        VisitActorAccess.testCanViewServiceRequests = true;
        AccountApprovalAccess.testTeamRepIds = new Set<Id>{ UserInfo.getUserId() };
        insert new Account(
            Name = 'Count Me',
            Account_Stage__c = AccountStageService.STAGE_DM
        );

        Test.startTest();
        Integer count = AccountApprovalAccess.getPendingApprovalCount();
        Test.stopTest();

        System.assertEquals(1, count);
        VisitActorAccess.testCanViewServiceRequests = null;
        AccountApprovalAccess.testTeamRepIds = null;
    }

    @IsTest
    static void approveAccount_rejectsWrongTeamSubmitter() {
        VisitActorAccess.testCanViewServiceRequests = true;
        AccountApprovalAccess.testTeamRepIds = new Set<Id>();
        Account pending = new Account(
            Name = 'Other Team',
            Account_Stage__c = AccountStageService.STAGE_DM
        );
        insert pending;

        Boolean failed = false;
        Test.startTest();
        try {
            AccountApprovalAccess.approveAccount(pending.Id);
        } catch (AuraHandledException ex) {
            failed = true;
        }
        Test.stopTest();
        System.assertEquals(true, failed);
        VisitActorAccess.testCanViewServiceRequests = null;
        AccountApprovalAccess.testTeamRepIds = null;
    }

    @IsTest
    static void submitNewAccountForApproval_advancesDraft() {
        Account draft = new Account(
            Name = 'Draft Submit',
            Account_Stage__c = AccountStageService.STAGE_DRAFT
        );
        insert draft;

        Test.startTest();
        AccountApprovalAccess.submitNewAccountForApproval(draft.Id);
        Test.stopTest();

        Account refreshed = [SELECT Account_Stage__c FROM Account WHERE Id = :draft.Id];
        System.assertEquals(AccountStageService.STAGE_DM, refreshed.Account_Stage__c);
    }

    @IsTest
    static void submitNewAccountForApproval_noOpWhenNotDraft() {
        Account pending = new Account(
            Name = 'Already Pending',
            Account_Stage__c = AccountStageService.STAGE_DM
        );
        insert pending;

        Test.startTest();
        AccountApprovalAccess.submitNewAccountForApproval(pending.Id);
        Test.stopTest();

        Account refreshed = [SELECT Account_Stage__c FROM Account WHERE Id = :pending.Id];
        System.assertEquals(AccountStageService.STAGE_DM, refreshed.Account_Stage__c);
    }

    @IsTest
    static void managerWithNoTeamRepsStillSeesOwnAccount() {
        VisitActorAccess.testCanViewServiceRequests = true;
        AccountApprovalAccess.testTeamRepIds = new Set<Id>();
        Account mine = new Account(
            Name = 'Orphan Pending',
            Account_Stage__c = AccountStageService.STAGE_DM
        );
        insert mine;

        Test.startTest();
        List<AccountApprovalAccess.ApprovalRow> rows = AccountApprovalAccess.getPendingApprovals();
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(mine.Id, rows[0].accountId);
        System.assertEquals(true, rows[0].createdByMe);
        System.assertEquals(false, rows[0].canAct);
        System.assertEquals('Pending DM', rows[0].stageLabel);

        VisitActorAccess.testCanViewServiceRequests = null;
        AccountApprovalAccess.testTeamRepIds = null;
    }

    @IsTest
    static void submitNewAccountForApproval_requiresAccountId() {
        Boolean failed = false;
        Test.startTest();
        try {
            AccountApprovalAccess.submitNewAccountForApproval(null);
        } catch (AuraHandledException ex) {
            failed = true;
        }
        Test.stopTest();
        System.assertEquals(true, failed);
    }

    @IsTest
    static void pendingQueue_populatesSpecialtyAndCity() {
        VisitActorAccess.testCanViewServiceRequests = true;
        AccountApprovalAccess.testTeamRepIds = new Set<Id>{ UserInfo.getUserId() };
        insert new Account(
            Name = 'Cardio Pending',
            Account_Stage__c = AccountStageService.STAGE_DM,
            BillingCity = 'Cairo'
        );

        Test.startTest();
        List<AccountApprovalAccess.ApprovalRow> rows = AccountApprovalAccess.getPendingApprovals();
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals('Cairo', rows[0].city);
        VisitActorAccess.testCanViewServiceRequests = null;
        AccountApprovalAccess.testTeamRepIds = null;
    }

    @IsTest
    static void rejectAccount_requiresNonBlankReason() {
        VisitActorAccess.testCanViewServiceRequests = true;
        AccountApprovalAccess.testTeamRepIds = new Set<Id>{ UserInfo.getUserId() };
        Account pending = new Account(
            Name = 'Reject Reason',
            Account_Stage__c = AccountStageService.STAGE_DM
        );
        insert pending;

        Boolean failed = false;
        Test.startTest();
        try {
            AccountApprovalAccess.rejectAccount(pending.Id, '   ');
        } catch (AuraHandledException ex) {
            failed = true;
        }
        Test.stopTest();
        System.assertEquals(true, failed);
        VisitActorAccess.testCanViewServiceRequests = null;
        AccountApprovalAccess.testTeamRepIds = null;
    }

    @IsTest
    static void nurtureIndex_groupsByWhoActsNext() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User rep = new User(
            Alias = ('nr' + suffix).left(8),
            Email = 'nurture.rep+' + suffix + '@test.example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Nurture Rep',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = 'nurture.rep+' + suffix + '@test.example.com'
        );
        insert rep;

        Id teamPendingId;
        System.runAs(rep) {
            Account teamPending = new Account(
                Name = 'Rep Pending',
                Account_Stage__c = AccountStageService.STAGE_DM
            );
            insert teamPending;
            teamPendingId = teamPending.Id;
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Account ownPending = new Account(
                Name = 'Mine Pending',
                Account_Stage__c = AccountStageService.STAGE_DM
            );
            insert ownPending;

            VisitActorAccess.testCanViewServiceRequests = true;
            AccountApprovalAccess.testTeamRepIds = new Set<Id>{ rep.Id };

            Test.startTest();
            AccountApprovalAccess.NurtureIndex beforeApprove = AccountApprovalAccess.loadNurtureIndex();
            System.assert(beforeApprove.withManager.contains(ownPending.Id), 'Own submission waits on the manager.');
            System.assertEquals(false, beforeApprove.needsYou.contains(ownPending.Id));
            System.assert(beforeApprove.needsYou.contains(teamPendingId), 'Rep submission needs the manager.');

            AccountApprovalAccess.approveAccount(teamPendingId);
            AccountApprovalAccess.NurtureIndex afterApprove = AccountApprovalAccess.loadNurtureIndex();
            Test.stopTest();

            System.assertEquals(false, afterApprove.needsYou.contains(teamPendingId));
            System.assert(afterApprove.withSfe.contains(teamPendingId));
            System.assert(afterApprove.sfeAdvancedByMe.contains(teamPendingId));
            Account refreshed = [SELECT Account_Stage__c FROM Account WHERE Id = :teamPendingId];
            System.assertEquals(AccountStageService.STAGE_SFE, refreshed.Account_Stage__c);

            VisitActorAccess.testCanViewServiceRequests = null;
            AccountApprovalAccess.testTeamRepIds = null;
        }
    }

    @IsTest
    static void queueShowsMyAccountsAndTheirStatus() {
        VisitActorAccess.testCanViewServiceRequests = false;
        Account draft = new Account(Name = 'Mine Draft', Account_Stage__c = AccountStageService.STAGE_DRAFT);
        Account sfe = new Account(Name = 'Mine SFE', Account_Stage__c = AccountStageService.STAGE_SFE);
        Account active = new Account(Name = 'Mine Active', Account_Stage__c = AccountStageService.STAGE_ACTIVE);
        insert new List<Account>{ draft, sfe, active };

        Test.startTest();
        List<AccountApprovalAccess.ApprovalRow> rows = AccountApprovalAccess.getPendingApprovals();
        Test.stopTest();

        Map<Id, AccountApprovalAccess.ApprovalRow> byId = new Map<Id, AccountApprovalAccess.ApprovalRow>();
        for (AccountApprovalAccess.ApprovalRow row : rows) {
            byId.put(row.accountId, row);
        }
        System.assertEquals(true, byId.containsKey(draft.Id));
        System.assertEquals(true, byId.containsKey(sfe.Id));
        System.assertEquals(false, byId.containsKey(active.Id), 'Active accounts have left nurturing.');
        System.assertEquals(true, byId.get(draft.Id).createdByMe);
        System.assertEquals('Draft', byId.get(draft.Id).stageLabel);
        System.assertEquals(false, byId.get(draft.Id).canAct);
        System.assertEquals('Pending SFE', byId.get(sfe.Id).stageLabel);
        System.assert(rows.size() >= 2);
        VisitActorAccess.testCanViewServiceRequests = null;
    }

    @IsTest
    static void managerCanActOnTeammateSubmission() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User rep = new User(
            Alias = ('tm' + suffix).left(8),
            Email = 'team.rep+' + suffix + '@test.example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Team Rep',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = 'team.rep+' + suffix + '@test.example.com'
        );
        insert rep;

        Id teamPendingId;
        System.runAs(rep) {
            Account teamPending = new Account(
                Name = 'Teammate Pending',
                Account_Stage__c = AccountStageService.STAGE_DM
            );
            insert teamPending;
            teamPendingId = teamPending.Id;
        }

        Account mine = new Account(Name = 'Manager Draft', Account_Stage__c = AccountStageService.STAGE_DRAFT);
        insert mine;

        VisitActorAccess.testCanViewServiceRequests = true;
        AccountApprovalAccess.testTeamRepIds = new Set<Id>{ rep.Id };

        Test.startTest();
        List<AccountApprovalAccess.ApprovalRow> rows = AccountApprovalAccess.getPendingApprovals();
        Test.stopTest();

        AccountApprovalAccess.ApprovalRow teamRow;
        AccountApprovalAccess.ApprovalRow mineRow;
        for (AccountApprovalAccess.ApprovalRow row : rows) {
            if (row.accountId == teamPendingId) {
                teamRow = row;
            }
            if (row.accountId == mine.Id) {
                mineRow = row;
            }
        }
        System.assertNotEquals(null, teamRow);
        System.assertEquals(false, teamRow.createdByMe);
        System.assertEquals(true, teamRow.canAct);
        System.assertEquals('Pending DM', teamRow.stageLabel);
        System.assertNotEquals(null, mineRow);
        System.assertEquals(true, mineRow.createdByMe);
        System.assertEquals(false, mineRow.canAct);
        System.assertEquals('Draft', mineRow.stageLabel);

        VisitActorAccess.testCanViewServiceRequests = null;
        AccountApprovalAccess.testTeamRepIds = null;
    }

    @IsTest
    static void sfeApproverActsOnPendingSfeFromTheirLine() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        SfeApproverTestData.assign(new List<SFE_Approver_Assignment__c>{
            SfeApproverTestData.row(data.businessUnitSfe.Id, data.businessUnit.Name, false)
        });
        Account fromLine = new Account(Name = 'SFE Line Pending', Account_Stage__c = AccountStageService.STAGE_SFE);
        Account fromOtherLine = new Account(Name = 'SFE Other Line Pending', Account_Stage__c = AccountStageService.STAGE_SFE);
        System.runAs(data.rep) {
            insert fromLine;
        }
        System.runAs(data.otherRep) {
            insert fromOtherLine;
        }

        System.runAs(data.businessUnitSfe) {
            VisitActorAccess.testCanViewServiceRequests = false;
            Test.startTest();
            List<AccountApprovalAccess.ApprovalRow> rows = AccountApprovalAccess.getPendingApprovals();
            AccountApprovalAccess.approveAccount(fromLine.Id);
            Test.stopTest();

            Map<Id, AccountApprovalAccess.ApprovalRow> byId = new Map<Id, AccountApprovalAccess.ApprovalRow>();
            for (AccountApprovalAccess.ApprovalRow row : rows) {
                byId.put(row.accountId, row);
            }
            System.assert(byId.containsKey(fromLine.Id), 'The business unit SFE sees Pending SFE accounts from their line.');
            System.assertEquals(true, byId.get(fromLine.Id).canAct);
            System.assertEquals(AccountApprovalAccess.STEP_SFE, byId.get(fromLine.Id).reviewStep);
            System.assertEquals(false, byId.containsKey(fromOtherLine.Id));
            VisitActorAccess.testCanViewServiceRequests = null;
        }

        Account approved = [SELECT Account_Stage__c FROM Account WHERE Id = :fromLine.Id];
        System.assertEquals(AccountStageService.STAGE_FI, approved.Account_Stage__c, 'SFE approval moves the account to FI validation.');
    }

    @IsTest
    static void sfeRejectSendsBackToDmAndOtherLinesAreBlocked() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        SfeApproverTestData.assign(new List<SFE_Approver_Assignment__c>{
            SfeApproverTestData.row(data.businessUnitSfe.Id, data.businessUnit.Name, false)
        });
        Account fromLine = new Account(Name = 'SFE Reject Pending', Account_Stage__c = AccountStageService.STAGE_SFE);
        Account fromOtherLine = new Account(Name = 'SFE Blocked Pending', Account_Stage__c = AccountStageService.STAGE_SFE);
        System.runAs(data.rep) {
            insert fromLine;
        }
        System.runAs(data.otherRep) {
            insert fromOtherLine;
        }

        Boolean blocked = false;
        System.runAs(data.businessUnitSfe) {
            Test.startTest();
            AccountApprovalAccess.rejectAccount(fromLine.Id, 'Wrong specialty');
            try {
                AccountApprovalAccess.approveAccount(fromOtherLine.Id);
            } catch (AuraHandledException ex) {
                blocked = ex.getMessage().contains('SFE approvers');
            }
            Test.stopTest();
        }

        System.assertEquals(
            AccountStageService.STAGE_DM,
            [SELECT Account_Stage__c FROM Account WHERE Id = :fromLine.Id].Account_Stage__c
        );
        System.assert(blocked, 'Another business unit is not this SFE\'s to approve.');
        System.assertEquals(
            AccountStageService.STAGE_SFE,
            [SELECT Account_Stage__c FROM Account WHERE Id = :fromOtherLine.Id].Account_Stage__c
        );
    }
}