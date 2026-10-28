String username = 'david.badie@zeta-pharma.com';
String firstName = 'David';
String lastName = 'Badie';
String password = firstName + '@demo1';

User template = [
    SELECT Id, ProfileId, TimeZoneSidKey, LocaleSidKey, LanguageLocaleKey, EmailEncodingKey
    FROM User
    WHERE Username = 'bassant.bahaaelden@zetapharma.net'
    LIMIT 1
];

List<User> existing = [
    SELECT Id, Username FROM User WHERE Username = :username LIMIT 1
];

Database.DMLOptions opts = new Database.DMLOptions();
opts.EmailHeader.triggerUserEmail = false;
opts.EmailHeader.triggerOtherEmail = false;
opts.optAllOrNone = true;

User trainee;
if (!existing.isEmpty()) {
    trainee = existing[0];
    trainee.FirstName = firstName;
    trainee.LastName = lastName;
    trainee.Email = username;
    trainee.IsActive = true;
    trainee.Title = 'Medical Rep';
    trainee.TimeZoneSidKey = template.TimeZoneSidKey;
    trainee.LocaleSidKey = template.LocaleSidKey;
    trainee.LanguageLocaleKey = template.LanguageLocaleKey;
    trainee.EmailEncodingKey = template.EmailEncodingKey;
    trainee.ProfileId = template.ProfileId;
    Database.update(trainee, opts);
    System.debug('UPDATED ' + trainee.Id + ' ' + trainee.Username);
} else {
    trainee = new User(
        Username = username,
        Email = username,
        FirstName = firstName,
        LastName = lastName,
        Alias = 'dbadie',
        CommunityNickname = ('DavidBadie' + String.valueOf(DateTime.now().getTime())).left(40),
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
}

Set<Id> alreadyPs = new Set<Id>();
Set<Id> alreadyPsg = new Set<Id>();
for (PermissionSetAssignment psa : [
    SELECT PermissionSetId, PermissionSetGroupId
    FROM PermissionSetAssignment
    WHERE AssigneeId = :trainee.Id
]) {
    if (psa.PermissionSetGroupId != null) {
        alreadyPsg.add(psa.PermissionSetGroupId);
    } else {
        alreadyPs.add(psa.PermissionSetId);
    }
}

List<PermissionSetAssignment> toAssign = new List<PermissionSetAssignment>();
for (PermissionSetAssignment psa : [
    SELECT PermissionSetId, PermissionSetGroupId, PermissionSet.IsOwnedByProfile
    FROM PermissionSetAssignment
    WHERE AssigneeId = :template.Id
]) {
    if (psa.PermissionSet.IsOwnedByProfile) {
        continue;
    }
    if (psa.PermissionSetGroupId != null) {
        if (alreadyPsg.contains(psa.PermissionSetGroupId)) {
            continue;
        }
        toAssign.add(new PermissionSetAssignment(
            AssigneeId = trainee.Id,
            PermissionSetGroupId = psa.PermissionSetGroupId
        ));
        alreadyPsg.add(psa.PermissionSetGroupId);
    } else {
        if (alreadyPs.contains(psa.PermissionSetId)) {
            continue;
        }
        toAssign.add(new PermissionSetAssignment(
            AssigneeId = trainee.Id,
            PermissionSetId = psa.PermissionSetId
        ));
        alreadyPs.add(psa.PermissionSetId);
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

try {
    System.setPassword(trainee.Id, password);
    System.debug('PASSWORD OK ' + trainee.Username + ' | ' + password);
} catch (Exception e) {
    System.debug('PASSWORD FAIL firstname: ' + e.getMessage());
    password = lastName + '@demo1';
    try {
        System.setPassword(trainee.Id, password);
        System.debug('PASSWORD OK fallback ' + trainee.Username + ' | ' + password);
    } catch (Exception e2) {
        System.debug('PASSWORD FAIL fallback: ' + e2.getMessage());
    }
}

User verify = [
    SELECT Name, Username, Email, IsActive, Profile.Name, LastPasswordChangeDate
    FROM User
    WHERE Id = :trainee.Id
];
System.debug(
    'VERIFY ' + verify.Name +
    ' | username=' + verify.Username +
    ' | email=' + verify.Email +
    ' | active=' + verify.IsActive +
    ' | profile=' + verify.Profile.Name +
    ' | lastPwd=' + String.valueOf(verify.LastPasswordChangeDate)
);
