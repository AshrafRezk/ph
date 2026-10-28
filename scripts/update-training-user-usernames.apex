Map<String, String> targetByOldUsername = new Map<String, String>{
    'omar@zetapharma.net' => 'Omar.mohsen@zetapharma.net',
    'nada.wael@zetapharma.net' => 'Nada.wael@zetapharma.net',
    'bassant.bahaaelden@zetapharma.net' => 'bassant.bahaaelden@zetapharma.net',
    'gassem@zetapharma.net' => 'gassem.gamal@zetapharma.net'
};

Set<String> oldUsernames = targetByOldUsername.keySet();
Set<String> targetUsernames = new Set<String>(targetByOldUsername.values());
for (String v : targetByOldUsername.values()) {
    targetUsernames.add(v.toLowerCase());
}

// Free the inactive duplicate occupying gassem.gamal@zetapharma.net
List<User> blockers = [
    SELECT Id, Name, Username, Email, IsActive
    FROM User
    WHERE Username IN ('gassem.gamal@zetapharma.net', 'Omar.mohsen@zetapharma.net', 'Nada.wael@zetapharma.net')
    AND Username NOT IN :oldUsernames
];
for (User blocker : blockers) {
    String freed = blocker.Username;
    String localPart = freed.substringBefore('@');
    String domain = freed.substringAfter('@');
    String newUsername = localPart + '.inactive.' + String.valueOf(DateTime.now().getTime()) + '@' + domain;
    blocker.Username = newUsername;
    System.debug('FREE ' + blocker.Name + ' ' + freed + ' -> ' + newUsername + ' (active=' + blocker.IsActive + ')');
}
if (!blockers.isEmpty()) {
    Database.DMLOptions freeOpts = new Database.DMLOptions();
    freeOpts.EmailHeader.triggerUserEmail = false;
    freeOpts.EmailHeader.triggerOtherEmail = false;
    freeOpts.optAllOrNone = true;
    Database.update(blockers, freeOpts);
}

List<User> users = [
    SELECT Id, Name, FirstName, LastName, Username, Email, IsActive
    FROM User
    WHERE Username IN :oldUsernames
];
System.debug('Found ' + users.size() + ' training users to remap.');

Database.DMLOptions opts = new Database.DMLOptions();
opts.EmailHeader.triggerUserEmail = false;
opts.EmailHeader.triggerOtherEmail = false;
opts.EmailHeader.triggerAutoResponseEmail = false;
opts.optAllOrNone = false;

List<User> toUpdate = new List<User>();
for (User u : users) {
    String target = targetByOldUsername.get(u.Username.toLowerCase());
    if (String.isBlank(target)) {
        target = targetByOldUsername.get(u.Username);
    }
    if (String.isBlank(target)) {
        System.debug('SKIP unmatched: ' + u.Username);
        continue;
    }
    System.debug('SET ' + u.Name + ' Username/Email ' + u.Username + ' / ' + u.Email + ' -> ' + target);
    u.Username = target;
    u.Email = target;
    toUpdate.add(u);
}

if (!toUpdate.isEmpty()) {
    Database.SaveResult[] results = Database.update(toUpdate, opts);
    for (Integer i = 0; i < results.size(); i++) {
        User u = toUpdate[i];
        if (results[i].isSuccess()) {
            System.debug('OK update ' + u.Name + ' -> ' + u.Username);
        } else {
            for (Database.Error err : results[i].getErrors()) {
                System.debug('FAIL update ' + u.Name + ': ' + err.getStatusCode() + ' ' + err.getMessage());
            }
        }
    }
}

for (User u : [
    SELECT Id, Name, Username, Email, IsActive
    FROM User
    WHERE Id IN :toUpdate
]) {
    System.debug('VERIFY ' + u.Name + ' | username=' + u.Username + ' | email=' + u.Email + ' | active=' + u.IsActive);
}
