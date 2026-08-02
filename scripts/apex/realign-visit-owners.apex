List<String> mrKeys = new List<String>{
    'git_mr', 'diabetes_mr', 'cluster_mr', 'chc_mr', 'cardio_mr', 'gastro_mr'
};
Integer total = 0;
for (String mrKey : mrKeys) {
    List<User> users = [
        SELECT Id
        FROM User
        WHERE Username = :(mrKey.replace('_', '.') + '@pharma.demo')
        LIMIT 1
    ];
    if (users.isEmpty()) {
        continue;
    }
    VisitOwnershipService.RepairResult result =
        VisitOwnershipService.realignAssignedVisitOwners(new Set<Id>{ users[0].Id });
    total += result.updatedCount;
    System.debug(mrKey + ': ' + result.message);
}
System.debug('TOTAL updated=' + total);
