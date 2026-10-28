/**
 * Wave B/C UAT access fixes (27 Oct 2026): another user's book, KOL list, account stages,
 * out-of-target queue, target-list rule, and the create-wizard duplicate warning.
 */
@IsTest
private class UatWaveBcAccessTest {
  private static User makeUser(String alias, String title) {
    Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    String suffix = alias + String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User u = new User(
      Alias = alias.left(8),
      Email = 'uat.' + suffix + '@test.example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'UAT ' + alias,
      Title = title,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standard.Id,
      TimeZoneSidKey = 'Africa/Cairo',
      Username = 'uat.' + suffix + '@test.example.com'
    );
    insert u;
    return u;
  }

  @IsTest
  static void repCannotOpenAnotherRepsBook() {
    User rep = makeUser('repa', 'Medical Representative');
    User other = makeUser('repb', 'Medical Representative');
    System.runAs(rep) {
      System.assertEquals(true, FieldPlannerController.canViewBookOf(rep.Id), 'Own book is always visible.');
      System.assertEquals(false, FieldPlannerController.canViewBookOf(other.Id), 'Another rep is outside the team.');
      Boolean blocked = false;
      try {
        AccountsTabController.exportAccountsCsv('Both', null, 'All', 'All', 'name', 'asc', null, other.Id, null, null);
      } catch (AuraHandledException ex) {
        blocked = true;
      }
      System.assertEquals(true, blocked, 'Export with another rep\'s id must be refused.');
    }
  }

  @IsTest
  static void managerSeesDirectReportBook() {
    User dm = makeUser('dma', 'District Sales Manager');
    User rep = makeUser('repc', 'Medical Representative');
    rep.ManagerId = dm.Id;
    update rep;
    System.runAs(dm) {
      System.assertEquals(true, FieldPlannerController.canViewBookOf(rep.Id), 'A DM reads a direct report\'s book.');
    }
  }

  @IsTest
  static void repCannotChangeKolList() {
    User rep = makeUser('repk', 'Medical Representative');
    Account acct = new Account(Name = 'UAT KOL Account');
    insert acct;
    System.runAs(rep) {
      Boolean blocked = false;
      try {
        AccountsTabController.setAccountKol(acct.Id, true);
      } catch (AuraHandledException ex) {
        blocked = true;
      }
      System.assertEquals(true, blocked, 'Reps must not toggle KOL.');
    }
  }

  @IsTest
  static void fiAndBuStagesNeedTheirApprover() {
    User rep = makeUser('repf', 'Medical Representative');
    User fi = makeUser('fia', 'Field Intelligence Trainer');
    User bu = makeUser('bua', 'Business Unit Manager');
    System.runAs(rep) {
      System.assertEquals(false, StageApproverAccess.canActAsFi());
      System.assertEquals(false, StageApproverAccess.canActAsBu());
    }
    System.runAs(fi) {
      System.assertEquals(true, StageApproverAccess.canActAsFi());
      System.assertEquals(false, StageApproverAccess.canActAsBu());
    }
    System.runAs(bu) {
      System.assertEquals(true, StageApproverAccess.canActAsBu());
    }
  }

  @IsTest
  static void accountAtFiCannotBeAdvancedByRep() {
    User rep = makeUser('repg', 'Medical Representative');
    Account acct = new Account(Name = 'UAT FI Stage', Account_Stage__c = AccountStageService.STAGE_FI);
    insert acct;
    System.runAs(rep) {
      Boolean blocked = false;
      try {
        AccountStageService.advance(acct.Id);
      } catch (Exception ex) {
        blocked = true;
      }
      System.assertEquals(true, blocked, 'Only FI may move an account out of FI Validation.');
    }
  }

  @IsTest
  static void outOfTargetProposalNeedsStageApprover() {
    User rep = makeUser('repo', 'Medical Representative');
    Account acct = new Account(Name = 'UAT OOT Account');
    insert acct;
    Out_Of_Target_Proposal__c proposal = new Out_Of_Target_Proposal__c(
      Name = 'UAT OOT',
      Account__c = acct.Id,
      Rep__c = rep.Id,
      Status__c = 'Pending FI',
      Target_Month__c = Date.today().toStartOfMonth()
    );
    insert proposal;
    System.runAs(rep) {
      Boolean blocked = false;
      try {
        OutOfTargetQueueService.advanceStatus(proposal.Id, 'Pending BU');
      } catch (AuraHandledException ex) {
        blocked = true;
      }
      System.assertEquals(true, blocked, 'A rep cannot pass the FI step.');
    }
  }

  @IsTest
  static void onlySfeCanSaveTheTargetListRule() {
    User dm = makeUser('dmr', 'District Sales Manager');
    System.runAs(dm) {
      Boolean blocked = false;
      try {
        TargetGovernanceService.saveOrgRule(new TargetGovernanceService.RuleSettings());
      } catch (AuraHandledException ex) {
        blocked = true;
      }
      System.assertEquals(true, blocked, 'A DM cannot change the org target-list rule.');
    }
  }

  @IsTest
  static void dmCannotEditFrequencyOutsideTeam() {
    User dm = makeUser('dmf', 'District Sales Manager');
    Account acct = new Account(Name = 'UAT Freq Account');
    insert acct;
    Account_Territory_Fields__c atf = new Account_Territory_Fields__c(
      Account__c = acct.Id,
      Territory2_Id__c = '0MI000000000001',
      Is_Active__c = true,
      Call_Plan_Visits_Per_Month__c = 4
    );
    insert atf;
    System.runAs(dm) {
      Boolean blocked = false;
      try {
        TargetGovernanceService.setAccountFrequency(atf.Id, 4);
      } catch (AuraHandledException ex) {
        blocked = true;
      }
      System.assertEquals(true, blocked, 'A DM only edits frequency inside their own territories.');
    }
  }

  @IsTest
  static void draftDuplicateIsFoundByNameAndPhone() {
    insert new Account(Name = 'Saydaleyat El Nour Pharmacy', Phone = '+201005551234', BillingCity = 'Cairo');
    Account draft = new Account(Name = 'Saydaleyat El Nour Pharmacy', Phone = '+201005551234', BillingCity = 'Cairo');
    Test.startTest();
    List<AccountDuplicateCheckService.MatchRow> matches = AccountDuplicateCheckService.findLikelyDuplicatesForDraft(draft);
    Test.stopTest();
    System.assert(!matches.isEmpty(), 'Same name and phone must be flagged before save.');
    System.assertEquals(
      0,
      AccountDuplicateCheckService.findLikelyDuplicatesForDraft(new Account(Name = 'Completely Different Clinic')).size(),
      'An unrelated name is not a duplicate.'
    );
  }
}
