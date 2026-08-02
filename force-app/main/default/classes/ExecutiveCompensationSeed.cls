public without sharing class ExecutiveCompensationSeed {

    private static final List<String> REP_USER_KEYS = new List<String>{
        'git_mr', 'diabetes_mr', 'cluster_mr', 'chc_mr', 'cardio_mr', 'gastro_mr'
    };

    private static final List<String> DM_USER_KEYS = new List<String>{
        'git_dm', 'diabetes_dm', 'cluster_dm', 'chc_dm', 'cardio_dm', 'gastro_dm'
    };

    private static final Map<String, Decimal> REP_SALARIES = new Map<String, Decimal>{
        'git_mr' => 18500,
        'diabetes_mr' => 19200,
        'cluster_mr' => 17800,
        'chc_mr' => 18100,
        'cardio_mr' => 17600,
        'gastro_mr' => 17900
    };

    private static final Map<String, Decimal> DM_SALARIES = new Map<String, Decimal>{
        'git_dm' => 32000,
        'diabetes_dm' => 33500,
        'cluster_dm' => 31000,
        'chc_dm' => 32800,
        'cardio_dm' => 31500,
        'gastro_dm' => 32200
    };

    public class SeedResult {
        public Integer timeCardCount = 0;
        public Integer salaryCount = 0;
        public String message;
    }

    /**
     * Ensures current-month active time cards exist for all demo reps and district managers,
     * then populates Base_Salary__c for executive workforce views.
     */
    public static SeedResult seedCurrentMonthCompensation() {
        SeedResult result = new SeedResult();
        Map<String, Id> userIds = resolveDemoUserIds();
        if (userIds.isEmpty()) {
            result.message = 'No demo rep or DM users found.';
            return result;
        }

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        if (Test.isRunningTest()) {
            monthStart = Date.newInstance(2026, 6, 1);
        }

        Set<Id> employeeIds = new Set<Id>(userIds.values());
        Map<Id, String> rolesByUser = TerritoryHierarchyService.resolvePrimaryRoleByUser(employeeIds);
        Map<Id, Decimal> salaryByUser = buildSalaryByUser(userIds);

        for (Id employeeId : employeeIds) {
            Employee_Time_Card__c timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(
                employeeId,
                monthStart,
                true,
                true
            );
            if (timeCard != null) {
                result.timeCardCount++;
            }
        }

        List<Employee_Time_Card__c> updates = new List<Employee_Time_Card__c>();
        for (Employee_Time_Card__c card : [
            SELECT Id, Employee__c, Base_Salary__c
            FROM Employee_Time_Card__c
            WHERE Employee__c IN :employeeIds
            AND Time_Card_Month_Start_Date__c = :monthStart
            WITH SYSTEM_MODE
        ]) {
            Decimal salary = salaryByUser.get(card.Employee__c);
            if (salary == null) {
                String role = rolesByUser.get(card.Employee__c);
                salary = role != null && role.contains('Manager') ? 30000 : 18000;
            }
            if (card.Base_Salary__c != salary) {
                card.Base_Salary__c = salary;
                updates.add(card);
            }
        }

        if (!updates.isEmpty()) {
            update as system updates;
            result.salaryCount = updates.size();
        }

        result.message = 'Ensured ' + result.timeCardCount + ' time cards and updated ' +
            result.salaryCount + ' salaries for ' + monthStart.format() + '.';
        return result;
    }

    public static Decimal resolveSalaryForUser(Id employeeId, String roleLabel) {
        if (employeeId == null) {
            return null;
        }
        if (roleLabel != null && roleLabel.contains('Manager')) {
            return 30000;
        }
        return 18000;
    }

    private static Map<Id, Decimal> buildSalaryByUser(Map<String, Id> userIds) {
        Map<Id, Decimal> salaryByUser = new Map<Id, Decimal>();
        for (String key : REP_SALARIES.keySet()) {
            if (userIds.containsKey(key)) {
                salaryByUser.put(userIds.get(key), REP_SALARIES.get(key));
            }
        }
        for (String key : DM_SALARIES.keySet()) {
            if (userIds.containsKey(key)) {
                salaryByUser.put(userIds.get(key), DM_SALARIES.get(key));
            }
        }
        return salaryByUser;
    }

    private static Map<String, Id> resolveDemoUserIds() {
        Map<String, Id> result = new Map<String, Id>();
        Set<String> usernames = new Set<String>();
        for (String key : REP_USER_KEYS) {
            usernames.add(key.replace('_', '.') + '@pharma.demo');
        }
        for (String key : DM_USER_KEYS) {
            usernames.add(key.replace('_', '.') + '@pharma.demo');
        }
        for (User userRecord : [
            SELECT Id, Username
            FROM User
            WHERE Username IN :usernames AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            String key = userRecord.Username.substringBefore('@').replace('.', '_');
            result.put(key, userRecord.Id);
        }
        return result;
    }
}
