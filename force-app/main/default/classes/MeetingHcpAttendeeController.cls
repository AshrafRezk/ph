public with sharing class MeetingHcpAttendeeController {
  @AuraEnabled(cacheable=true)
  public static MeetingHcpAttendeeService.MeetingHcpContext getMeetingHcpContext(Id meetingId) {
    return MeetingHcpAttendeeService.getMeetingHcpContext(meetingId);
  }

  @AuraEnabled(cacheable=true)
  public static List<MeetingHcpAttendeeService.HcpCandidate> searchTargetHcpCandidates(
    Id meetingId,
    String searchTerm
  ) {
    return MeetingHcpAttendeeService.searchTargetHcpCandidates(meetingId, searchTerm);
  }

  @AuraEnabled
  public static MeetingHcpAttendeeService.HcpAttendeeRow addHcpAttendee(Id meetingId, Id accountId) {
    return MeetingHcpAttendeeService.addHcpAttendee(meetingId, accountId);
  }

  @AuraEnabled
  public static void removeHcpAttendee(Id memberId) {
    MeetingHcpAttendeeService.removeHcpAttendee(memberId);
  }
}