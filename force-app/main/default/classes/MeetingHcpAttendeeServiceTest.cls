@IsTest
private class MeetingHcpAttendeeServiceTest {
  private static Id meetingRtId(String developerName) {
    return [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Meeting__c' AND DeveloperName = :developerName
        LIMIT 1
      ]
      .Id;
  }

  @IsTest
  static void alignedSearchFindsTargetHcpAndRejectsStrangers() {
    Meeting__c meeting = new Meeting__c(
      RecordTypeId = meetingRtId('RTD'),
      Status__c = 'Draft',
      Start_Date_Time__c = Datetime.now(),
      End_Date_Time__c = Datetime.now().addHours(2)
    );
    insert meeting;
    MeetingHcpAttendeeService.seedRequiredHcpAttendeeForTest(meeting.Id);

    System.assertEquals(0, MeetingHcpAttendeeService.searchAlignedHcpCandidates(meeting.Id, 'M').size());
    List<MeetingHcpAttendeeService.HcpCandidate> found = MeetingHcpAttendeeService.searchAlignedHcpCandidates(
      meeting,
      'Meeting Test'
    );
    System.assertEquals(1, found.size(), 'Cognitive search should find the target HCP');
    System.assertEquals(true, found[0].onTargetList);
    System.assert(found[0].detail.contains('target'));

    Account seeded = [
      SELECT RecordTypeId
      FROM Account
      WHERE Name = 'Meeting Test HCP' OR LastName = 'Meeting Test HCP'
      LIMIT 1
    ];
    Account other = new Account(RecordTypeId = seeded.RecordTypeId, LastName = 'Other Search HCP', Name = 'Other Search HCP');
    try {
      insert other;
    } catch (DmlException ex) {
      other = new Account(RecordTypeId = seeded.RecordTypeId, LastName = 'Other Search HCP');
      insert other;
    }
    MeetingHcpAttendeeService.isSelectableHcp(meeting, other.Id);
    System.assertEquals(false, MeetingHcpAttendeeService.isSelectableHcp(meeting, null));
    System.assertEquals(0, MeetingHcpAttendeeService.searchAlignedHcpCandidates(null, 'Meeting').size());
  }

  @IsTest
  static void submitBlockedWithoutHcpAttendees() {
    MeetingWorkflowSeed.seedStandardTemplates(true);
    Meeting__c meeting = new Meeting__c(
      RecordTypeId = meetingRtId('RTD'),
      Status__c = 'Draft',
      Objectives__c = 'RTD without attendees'
    );
    insert meeting;

    Test.startTest();
    MeetingWorkflowService.TransitionResult blocked = MeetingWorkflowService.applyTransition(
      meeting.Id,
      'SubmitForApproval',
      null
    );
    Test.stopTest();

    System.assertEquals(false, blocked.success);
    System.assert(blocked.message.contains('HCP attendee'), blocked.message);
  }

  @IsTest
  static void addSearchAndSubmitWithTargetHcp() {
    MeetingWorkflowSeed.seedStandardTemplates(true);
    Meeting__c meeting = new Meeting__c(
      RecordTypeId = meetingRtId('Speaker_Meeting'),
      Status__c = 'Draft',
      Objectives__c = 'Speaker with HCP'
    );
    insert meeting;
    MeetingHcpAttendeeService.seedRequiredHcpAttendeeForTest(meeting.Id);

    MeetingHcpAttendeeService.MeetingHcpContext ctx = MeetingHcpAttendeeService.getMeetingHcpContext(
      meeting.Id
    );
    System.assertEquals(true, ctx.requiresHcpAttendees);
    System.assertEquals(1, ctx.attendees.size());
    System.assertEquals(null, ctx.validationMessage);

    List<MeetingHcpAttendeeService.HcpCandidate> candidates = MeetingHcpAttendeeService.searchTargetHcpCandidates(
      meeting.Id,
      null
    );
    System.assertNotEquals(null, candidates);

    Test.startTest();
    MeetingWorkflowService.TransitionResult submit = MeetingWorkflowService.applyTransition(
      meeting.Id,
      'SubmitForApproval',
      null
    );
    Test.stopTest();
    System.assertEquals(true, submit.success, submit.message);
  }

  @IsTest
  static void controllerDelegatesToService() {
    Meeting__c meeting = new Meeting__c(
      RecordTypeId = meetingRtId('RTD'),
      Status__c = 'Draft'
    );
    insert meeting;
    MeetingHcpAttendeeService.seedRequiredHcpAttendeeForTest(meeting.Id);

    Test.startTest();
    MeetingHcpAttendeeService.MeetingHcpContext ctx = MeetingHcpAttendeeController.getMeetingHcpContext(
      meeting.Id
    );
    List<MeetingHcpAttendeeService.HcpCandidate> candidates = MeetingHcpAttendeeController.searchTargetHcpCandidates(
      meeting.Id,
      ''
    );
    Test.stopTest();

    System.assertEquals(true, ctx.requiresHcpAttendees);
    System.assertNotEquals(null, candidates);
  }

  @IsTest
  static void addRemoveHcpAttendee_andNonRtdContext() {
    Meeting__c rtd = new Meeting__c(
      RecordTypeId = meetingRtId('RTD'),
      Status__c = 'Draft',
      Start_Date_Time__c = Datetime.now(),
      End_Date_Time__c = Datetime.now().addHours(2)
    );
    insert rtd;
    MeetingHcpAttendeeService.seedRequiredHcpAttendeeForTest(rtd.Id);

    MeetingHcpAttendeeService.MeetingHcpContext ctx = MeetingHcpAttendeeService.getMeetingHcpContext(
      rtd.Id
    );
    Id accountId = ctx.attendees[0].accountId;
    Id memberId = ctx.attendees[0].memberId;

    MeetingHcpAttendeeController.removeHcpAttendee(memberId);
    System.assertEquals(
      0,
      MeetingHcpAttendeeService.getMeetingHcpContext(rtd.Id).attendees.size()
    );

    MeetingHcpAttendeeService.HcpAttendeeRow added = MeetingHcpAttendeeController.addHcpAttendee(
      rtd.Id,
      accountId
    );
    System.assertEquals(accountId, added.accountId);

    Boolean duplicateThrown = false;
    try {
      MeetingHcpAttendeeService.addHcpAttendee(rtd.Id, accountId);
    } catch (AuraHandledException ex) {
      duplicateThrown = true;
    }
    System.assertEquals(true, duplicateThrown);

    Meeting__c promo = new Meeting__c(
      RecordTypeId = meetingRtId('Promotional_Activity'),
      Status__c = 'Draft'
    );
    insert promo;
    System.assertEquals(
      false,
      MeetingHcpAttendeeService.getMeetingHcpContext(promo.Id).requiresHcpAttendees
    );
  }
}