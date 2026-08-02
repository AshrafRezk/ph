/**
 * @description Thin remoting façade for CRM Hub Home (page extension + @RemoteAction).
 */
public without sharing class CrmHubHomeController {
    public static final String HUB_ACCESS_FULL = 'Full Hub Access';
    public static final String HUB_ACCESS_PARTIAL = 'Partial Hub Access';

    @TestVisible
    private static final Set<String> FULL_HUB_USERNAMES = new Set<String>{
        'mariam.mamdouh@cloudastick.org',
        'mina@cloudastick.com',
        'ashraf@cloudastick.com'
    };

    @TestVisible
    private static String hubAccessModeOverride;

    @TestVisible
    private static Boolean forceFailure;

    /** @description VF extension constructor (required for remoting catalog on CrmHubList). */
    public CrmHubHomeController(CrmHubListController parent) {
    }

    /**
     * @description Home tab KPIs: this week vs last week (Sun–Sat), Me + Company, score, leaderboard.
     */
    @RemoteAction
    public static Map<String, Object> fetchHubHomeStats() {
        try {
            if (forceFailure == true) {
                throw new CalloutException('forced home failure');
            }
            Boolean full = resolveHubAccessMode() == HUB_ACCESS_FULL;
            return CrmHubHomeStatsService.buildHomeStats(full);
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'error' => e.getMessage() };
        }
    }

    @TestVisible
    private static String resolveHubAccessMode() {
        if (hubAccessModeOverride != null) {
            return hubAccessModeOverride;
        }
        String username = UserInfo.getUserName();
        if (String.isNotBlank(username) && FULL_HUB_USERNAMES.contains(username.toLowerCase())) {
            return HUB_ACCESS_FULL;
        }
        User u = [
            SELECT Hub_Access__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (u.Hub_Access__c == HUB_ACCESS_FULL) {
            return HUB_ACCESS_FULL;
        }
        return HUB_ACCESS_PARTIAL;
    }
}
