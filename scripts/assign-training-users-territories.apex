Map<String, String> usernameToTerritoryDevName = new Map<String, String>{
    'bassant.bahaaelden@zetapharma.net' => 'POS_TRAINING_DIAB_CAIRO',
    'nada.wael@zetapharma.net' => 'POS_TRAINING_CHC_CAIRO',
    'omar.mohsen@zetapharma.net' => 'POS_TRAINING_GIT_CAIRO',
    'gassem.gamal@zetapharma.net' => 'POS_TRAINING_PEDIA_CAIRO',
    'mohamed.rafek@zeta-pharma.com' => 'POS_TRAINING_DIAB_CAIRO',
    'aya.adel@zeta-pharma.com' => 'POS_TRAINING_CHC_CAIRO',
    'manar.saleh@zeta-pharma.com' => 'POS_TRAINING_GIT_CAIRO',
    'hamsa.diaaeldin@zeta-pharma.com' => 'POS_TRAINING_PEDIA_CAIRO',
    'david.badie@zeta-pharma.com' => 'POS_TRAINING_REP'
};

Set<String> usernames = usernameToTerritoryDevName.keySet();
Map<String, User> usersByUsername = new Map<String, User>();
for (User person : [
    SELECT Id, Name, Username
    FROM User
    WHERE Username IN :usernames
]) {
    usersByUsername.put(person.Username.toLowerCase(), person);
}

Set<String> territoryDevNames = new Set<String>(usernameToTerritoryDevName.values());
Map<String, Territory2> territoriesByDevName = new Map<String, Territory2>();
for (Territory2 territory : [
    SELECT Id, Name, DeveloperName
    FROM Territory2
    WHERE DeveloperName IN :territoryDevNames
]) {
    territoriesByDevName.put(territory.DeveloperName, territory);
}

Set<Id> userIds = new Set<Id>();
for (User person : usersByUsername.values()) {
    userIds.add(person.Id);
}
Set<String> existingKeys = new Set<String>();
for (UserTerritory2Association assignment : [
    SELECT UserId, Territory2Id
    FROM UserTerritory2Association
    WHERE UserId IN :userIds
]) {
    existingKeys.add(String.valueOf(assignment.UserId) + ':' + String.valueOf(assignment.Territory2Id));
}

List<UserTerritory2Association> toInsert = new List<UserTerritory2Association>();
for (String username : usernameToTerritoryDevName.keySet()) {
    User person = usersByUsername.get(username.toLowerCase());
    Territory2 territory = territoriesByDevName.get(usernameToTerritoryDevName.get(username));
    if (person == null) {
        System.debug('MISSING USER ' + username);
        continue;
    }
    if (territory == null) {
        System.debug('MISSING TERRITORY ' + usernameToTerritoryDevName.get(username) + ' for ' + username);
        continue;
    }
    String key = String.valueOf(person.Id) + ':' + String.valueOf(territory.Id);
    if (existingKeys.contains(key)) {
        System.debug('ALREADY ASSIGNED ' + person.Name + ' -> ' + territory.Name);
        continue;
    }
    toInsert.add(new UserTerritory2Association(
        UserId = person.Id,
        Territory2Id = territory.Id,
        RoleInTerritory2 = 'Medical Rep'
    ));
    System.debug('ASSIGN ' + person.Name + ' -> ' + territory.Name);
}

if (!toInsert.isEmpty()) {
    Integer ok = 0;
    Integer fail = 0;
    for (Database.SaveResult sr : Database.insert(toInsert, false)) {
        if (sr.isSuccess()) {
            ok++;
        } else {
            fail++;
            System.debug('ASSIGN FAIL ' + sr.getErrors()[0].getMessage());
        }
    }
    System.debug('Assigned ok=' + ok + ' fail=' + fail);
} else {
    System.debug('No new territory assignments needed.');
}
