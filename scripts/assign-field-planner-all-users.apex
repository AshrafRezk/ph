// Assign Field Planner Module to all active users whose license supports Apex class access.
PermissionSet ps = [
    SELECT Id
    FROM PermissionSet
    WHERE Name = 'Field_Planner_Module'
    LIMIT 1
];

Set<Id> alreadyAssigned = new Set<Id>();
for (PermissionSetAssignment psa : [
    SELECT AssigneeId
    FROM PermissionSetAssignment
    WHERE PermissionSetId = :ps.Id
]) {
    alreadyAssigned.add(psa.AssigneeId);
}

List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
Integer skippedPlatform = 0;

for (User u : [
    SELECT Id, Profile.UserLicense.Name
    FROM User
    WHERE IsActive = TRUE AND UserType IN ('Standard', 'CsnOnly')
]) {
    if (alreadyAssigned.contains(u.Id)) {
        continue;
    }
    if (u.Profile.UserLicense.Name == 'Salesforce Platform') {
        skippedPlatform++;
        continue;
    }
    assignments.add(new PermissionSetAssignment(
        PermissionSetId = ps.Id,
        AssigneeId = u.Id
    ));
}

Integer successCount = 0;
Integer failCount = 0;
for (Database.SaveResult sr : Database.insert(assignments, false)) {
    if (sr.isSuccess()) {
        successCount++;
    } else {
        failCount++;
    }
}

System.debug(
    'Field_Planner_Module: assigned=' + successCount +
    ', failed=' + failCount +
    ', skipped_platform=' + skippedPlatform +
    ', already_had=' + alreadyAssigned.size()
);
