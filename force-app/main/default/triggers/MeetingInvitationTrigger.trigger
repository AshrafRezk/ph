trigger MeetingInvitationTrigger on Meeting_Invitation__c (before insert) {
    MeetingInvitationService.assignCodes(Trigger.new);
}
