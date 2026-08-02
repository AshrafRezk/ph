// Updates demo user names and hire dates from ChemipharmDemoDataProfiles (setup objects only).
List<User> updates = new List<User>();
for (String key : ChemipharmDemoDataProfiles.getAllDemoUserKeys()) {
    ChemipharmDemoDataProfiles.DemoUserProfile profile = ChemipharmDemoDataProfiles.getUserProfile(key);
    if (profile == null) {
        continue;
    }
    String username = key.replace('_', '.') + '@pharma.demo';
    List<User> users = [
        SELECT Id, FirstName, LastName, Title, Department, Hire_Date__c
        FROM User
        WHERE Username = :username
        LIMIT 1
    ];
    if (users.isEmpty()) {
        continue;
    }
    User u = users[0];
    u.FirstName = profile.firstName;
    u.LastName = profile.lastName;
    u.Title = profile.roleLabel;
    u.Department = profile.department;
    if (profile.hireDate != null && key.endsWith('_mr')) {
        u.Hire_Date__c = profile.hireDate;
    }
    updates.add(u);
}
if (!updates.isEmpty()) {
    update updates;
}
Integer managerAssignments = TerritoryModuleSeed.assignDemoUserManagersFromOrg();
System.debug('Updated ' + updates.size() + ' demo users from Zeta Demo Data profiles.');
System.debug('Assigned ' + managerAssignments + ' demo MR manager links.');
