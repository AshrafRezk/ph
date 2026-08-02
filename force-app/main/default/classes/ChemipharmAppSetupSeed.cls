public without sharing class ChemipharmAppSetupSeed {

    public class SeedResult {
        public Integer hireDatesSet = 0;
        public Integer timeCardsSynced = 0;
        public String message;
    }

    /**
     * Sets demo hire dates and recalculates extended KPIs on active time cards.
     * Run after three-app deploy and persona PSG assignment.
     */
    public static SeedResult finalizeOrgSetup() {
        SeedResult result = new SeedResult();

        Map<String, Id> userIds = loadDemoUserIds();
        List<User> updates = new List<User>();
        if (userIds.containsKey('git_mr')) {
            updates.add(new User(
                Id = userIds.get('git_mr'),
                Hire_Date__c = Date.today().addDays(-45)
            ));
        }
        if (userIds.containsKey('diabetes_mr')) {
            updates.add(new User(
                Id = userIds.get('diabetes_mr'),
                Hire_Date__c = Date.today().addDays(-400)
            ));
        }
        if (!updates.isEmpty()) {
            update as system updates;
            result.hireDatesSet = updates.size();
        }

        List<Employee_Time_Card__c> cards = [
            SELECT Id
            FROM Employee_Time_Card__c
            WHERE Active_Time_Card__c = true
            WITH SYSTEM_MODE
            LIMIT 500
        ];
        Set<Id> cardIds = new Map<Id, Employee_Time_Card__c>(cards).keySet();
        if (!cardIds.isEmpty()) {
            EmployeeTimeCardTerritoryService.syncTerritoryHierarchy(cardIds);
            EmployeeTimeCardMetricsService.recalcExtendedMetrics(cardIds);
            result.timeCardsSynced = cardIds.size();
        }

        result.message = 'Set ' + result.hireDatesSet + ' hire dates; synced ' +
            result.timeCardsSynced + ' active time cards.';
        return result;
    }

    private static Map<String, Id> loadDemoUserIds() {
        Map<String, Id> result = new Map<String, Id>();
        for (User u : [
            SELECT Id, Username
            FROM User
            WHERE Username LIKE '%@pharma.demo'
            AND IsActive = true
            WITH SYSTEM_MODE
        ]) {
            String key = resolveUserKey(u.Username);
            if (key != null) {
                result.put(key, u.Id);
            }
        }
        return result;
    }

    private static String resolveUserKey(String username) {
        if (String.isBlank(username)) {
            return null;
        }
        String lower = username.toLowerCase();
        for (String team : new List<String>{ 'git', 'diabetes', 'cluster', 'chc' }) {
            for (String role : new List<String>{ 'dm', 'mr' }) {
                if (lower.startsWith(team + '.' + role + '@')) {
                    return team + '_' + role;
                }
            }
        }
        return null;
    }
}
