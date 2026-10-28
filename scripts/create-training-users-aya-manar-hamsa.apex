class Spec {
    String username;
    String firstName;
    String lastName;
    String alias;
    Spec(String username, String firstName, String lastName, String alias) {
        this.username = username;
        this.firstName = firstName;
        this.lastName = lastName;
        this.alias = alias;
    }
}

List<Spec> specs = new List<Spec>{
    new Spec('aya.adel@zeta-pharma.com', 'Aya', 'Adel', 'ayaadel'),
    new Spec('manar.saleh@zeta-pharma.com', 'Manar', 'Saleh', 'msaleh'),
    new Spec('hamsa.diaaeldin@zeta-pharma.com', 'Hamsa', 'Diaaeldin', 'hdiaael')
};

User template = [
    SELECT
        Id,
        ProfileId,
        TimeZoneSidKey,
        LocaleSidKey,
        LanguageLocaleKey,
        EmailEncodingKey
    FROM User
    WHERE Username = 'bassant.bahaaelden@zetapharma.net'
    LIMIT 1
];

Set<String> usernames = new Set<String>();
for (Spec spec : specs) {
    usernames.add(spec.username);
}

Map<String, User> existingByUsername = new Map<String, User>();
for (User person : [
    SELECT Id, Name, Username, Email, IsActive, FirstName, LastName
    FROM User
    WHERE Username IN :usernames
]) {
    existingByUsername.put(person.Username.toLowerCase(), person);
}

Database.DMLOptions opts = new Database.DMLOptions();
opts.EmailHeader.triggerUserEmail = false;
opts.EmailHeader.triggerOtherEmail = false;
opts.optAllOrNone = true;

List<User> created = new List<User>();
Map<String, User> usersByUsername = new Map<String, User>();
for (Spec spec : specs) {
    User trainee = existingByUsername.get(spec.username.toLowerCase());
    if (trainee != null) {
        trainee.FirstName = spec.firstName;
        trainee.LastName = spec.lastName;
        trainee.Email = spec.username;
        trainee.IsActive = true;
        trainee.Title = 'Medical Rep';
        trainee.TimeZoneSidKey = template.TimeZoneSidKey;
        trainee.LocaleSidKey = template.LocaleSidKey;
        trainee.LanguageLocaleKey = template.LanguageLocaleKey;
        trainee.EmailEncodingKey = template.EmailEncodingKey;
        trainee.ProfileId = template.ProfileId;
        Database.update(trainee, opts);
        System.debug('UPDATED ' + trainee.Id + ' ' + trainee.Username);
        usersByUsername.put(spec.username.toLowerCase(), trainee);
        continue;
    }
    trainee = new User(
        Username = spec.username,
        Email = spec.username,
        FirstName = spec.firstName,
        LastName = spec.lastName,
        Alias = spec.alias,
        CommunityNickname = (spec.firstName + spec.lastName + String.valueOf(DateTime.now().getTime())).left(40),
        Title = 'Medical Rep',
        TimeZoneSidKey = template.TimeZoneSidKey,
        LocaleSidKey = template.LocaleSidKey,
        LanguageLocaleKey = template.LanguageLocaleKey,
        EmailEncodingKey = template.EmailEncodingKey,
        ProfileId = template.ProfileId,
        IsActive = true
    );
    Database.insert(trainee, opts);
    System.debug('CREATED ' + trainee.Id + ' ' + trainee.Username);
    created.add(trainee);
    usersByUsername.put(spec.username.toLowerCase(), trainee);
}

List<PermissionSetAssignment> templateAssignments = [
    SELECT PermissionSetId, PermissionSetGroupId, PermissionSet.IsOwnedByProfile
    FROM PermissionSetAssignment
    WHERE AssigneeId = :template.Id
];

Set<Id> assigneeIds = new Set<Id>();
for (User person : usersByUsername.values()) {
    assigneeIds.add(person.Id);
}

Map<Id, Set<Id>> alreadyPs = new Map<Id, Set<Id>>();
Map<Id, Set<Id>> alreadyPsg = new Map<Id, Set<Id>>();
for (Id userId : assigneeIds) {
    alreadyPs.put(userId, new Set<Id>());
    alreadyPsg.put(userId, new Set<Id>());
}
for (PermissionSetAssignment psa : [
    SELECT AssigneeId, PermissionSetId, PermissionSetGroupId
    FROM PermissionSetAssignment
    WHERE AssigneeId IN :assigneeIds
]) {
    if (psa.PermissionSetGroupId != null) {
        alreadyPsg.get(psa.AssigneeId).add(psa.PermissionSetGroupId);
    } else {
        alreadyPs.get(psa.AssigneeId).add(psa.PermissionSetId);
    }
}

List<PermissionSetAssignment> toAssign = new List<PermissionSetAssignment>();
for (User person : usersByUsername.values()) {
    Set<Id> havePs = alreadyPs.get(person.Id);
    Set<Id> havePsg = alreadyPsg.get(person.Id);
    for (PermissionSetAssignment psa : templateAssignments) {
        if (psa.PermissionSet.IsOwnedByProfile) {
            continue;
        }
        if (psa.PermissionSetGroupId != null) {
            if (havePsg.contains(psa.PermissionSetGroupId)) {
                continue;
            }
            toAssign.add(new PermissionSetAssignment(
                AssigneeId = person.Id,
                PermissionSetGroupId = psa.PermissionSetGroupId
            ));
            havePsg.add(psa.PermissionSetGroupId);
        } else {
            if (havePs.contains(psa.PermissionSetId)) {
                continue;
            }
            toAssign.add(new PermissionSetAssignment(
                AssigneeId = person.Id,
                PermissionSetId = psa.PermissionSetId
            ));
            havePs.add(psa.PermissionSetId);
        }
    }
}

Integer psOk = 0;
Integer psFail = 0;
if (!toAssign.isEmpty()) {
    for (Database.SaveResult sr : Database.insert(toAssign, false)) {
        if (sr.isSuccess()) {
            psOk++;
        } else {
            psFail++;
            System.debug('PERM FAIL ' + sr.getErrors()[0].getMessage());
        }
    }
}
System.debug('Permission assignments ok=' + psOk + ' fail=' + psFail);

for (Spec spec : specs) {
    User trainee = usersByUsername.get(spec.username.toLowerCase());
    String password = spec.firstName + '@demo1';
    try {
        System.setPassword(trainee.Id, password);
        System.debug('PASSWORD OK ' + trainee.Username + ' | ' + password);
    } catch (Exception e) {
        System.debug('PASSWORD FAIL firstname ' + trainee.Username + ': ' + e.getMessage());
        password = spec.lastName + '@demo1';
        try {
            System.setPassword(trainee.Id, password);
            System.debug('PASSWORD OK fallback ' + trainee.Username + ' | ' + password);
        } catch (Exception e2) {
            System.debug('PASSWORD FAIL fallback ' + trainee.Username + ': ' + e2.getMessage());
        }
    }
}

for (User verify : [
    SELECT Id, Name, Username, Email, IsActive, Profile.Name, LastPasswordChangeDate
    FROM User
    WHERE Username IN :usernames
    ORDER BY Name
]) {
    System.debug(
        'VERIFY ' + verify.Name +
        ' | username=' + verify.Username +
        ' | email=' + verify.Email +
        ' | active=' + verify.IsActive +
        ' | profile=' + verify.Profile.Name +
        ' | lastPwd=' + String.valueOf(verify.LastPasswordChangeDate)
    );
}
