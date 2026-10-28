/**
 * Who may act at the later approval stages (Field Intelligence, BU) shared by the
 * new-account path and the out-of-target proposal queue.
 */
public with sharing class StageApproverAccess {
  private static final List<String> FI_TITLE_KEYWORDS = new List<String>{ 'field intelligence' };
  private static final List<String> BU_TITLE_KEYWORDS = new List<String>{ 'business unit' };

  public static Boolean canActAsFi() {
    return canAct(FI_TITLE_KEYWORDS);
  }

  public static Boolean canActAsBu() {
    return canAct(BU_TITLE_KEYWORDS);
  }

  // The matching title, any new-account SFE approver, or an admin.
  private static Boolean canAct(List<String> titleKeywords) {
    Id userId = UserInfo.getUserId();
    if (SfeApproverService.isSystemAdministrator() || SfeApproverService.isApprover(userId, SfeApproverService.NEW_ACCOUNTS)) {
      return true;
    }
    return titleMatches(userId, titleKeywords);
  }

  public static Boolean titleMatches(Id userId, List<String> titleKeywords) {
    String title = [SELECT Title FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1].Title;
    String normalized = title == null ? '' : title.toLowerCase();
    for (String keyword : titleKeywords) {
      if (normalized.contains(keyword)) {
        return true;
      }
    }
    return false;
  }
}
