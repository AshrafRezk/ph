/**
 * Assign Representative / Manager / SFE access packs.
 * - Reps & managers → Standard User + Pharma Field Rep / District Manager PSG
 * - SFE / CRM admin titles → System Administrator + Pharma Admin PSG + Pharma_SFE_App
 * Also sets today's shared OTP (fill in sharedOtp below) on the training cohort.
 */
Id standardProfileId = [
    SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1
].Id;
Id adminProfileId = [
    SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1
].Id;

Id fieldRepPsgId = [
    SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'Pharma_Field_Rep_PSG' LIMIT 1
].Id;
Id dmPsgId = [
    SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'Pharma_District_Manager_PSG' LIMIT 1
].Id;
Id adminPsgId = [
    SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'Pharma_Admin' LIMIT 1
].Id;
Id sfeAppPsId = [
    SELECT Id FROM PermissionSet WHERE Name = 'Pharma_SFE_App' LIMIT 1
].Id;

Set<String> trainingUsernames = new Set<String>{
    'bassant.bahaaelden@zetapharma.net',
    'nada.wael@zetapharma.net',
    'Nada.wael@zetapharma.net',
    'omar.mohsen@zetapharma.net',
    'Omar.mohsen@zetapharma.net',
    'gassem.gamal@zetapharma.net',
    'mohamed.rafek@zeta-pharma.com',
    'aya.adel@zeta-pharma.com',
    'manar.saleh@zeta-pharma.com',
    'hamsa.diaaeldin@zeta-pharma.com',
    'david.badie@zeta-pharma.com'
};

List<User> users = [
    SELECT Id, Name, Username, Title, ProfileId, Profile.Name, IsActive
    FROM User
    WHERE IsActive = TRUE
        AND Profile.UserType = 'Standard'
        AND (
            Title != null
            OR Username IN :trainingUsernames
        )
];

List<User> profileUpdates = new List<User>();
List<PermissionSetAssignment> psaInserts = new List<PermissionSetAssignment>();
Set<String> existingKeys = new Set<String>();
for (PermissionSetAssignment psa : [
    SELECT AssigneeId, PermissionSetId, PermissionSetGroupId
    FROM PermissionSetAssignment
    WHERE AssigneeId IN :new Map<Id, User>(users).keySet()
]) {
    if (psa.PermissionSetGroupId != null) {
        existingKeys.add(String.valueOf(psa.AssigneeId) + ':' + String.valueOf(psa.PermissionSetGroupId));
    }
    if (psa.PermissionSetId != null) {
        existingKeys.add(String.valueOf(psa.AssigneeId) + ':' + String.valueOf(psa.PermissionSetId));
    }
}

Integer repCount = 0;
Integer mgrCount = 0;
Integer sfeCount = 0;
Integer skipped = 0;

for (User u : users) {
    String title = u.Title == null ? '' : u.Title.trim().toLowerCase();
    Boolean isTraining = false;
    for (String uname : trainingUsernames) {
        if (u.Username != null && u.Username.equalsIgnoreCase(uname)) {
            isTraining = true;
            break;
        }
    }

    Boolean isSfe =
        title.contains('sfe') ||
        title.contains('crm specialist') ||
        title.contains('crm & sfe') ||
        title.contains('senior analyst crm') ||
        title == 'crm specialist' ||
        (isTraining && (
            u.Username.toLowerCase().contains('david.badie') ||
            u.Username.toLowerCase().contains('hamsa.') ||
            u.Username.toLowerCase().contains('manar.') ||
            u.Username.toLowerCase().contains('aya.adel')
        ));

    Boolean isManager =
        !isSfe && (
            title.contains('district') ||
            title.contains('supervisor') ||
            title.contains('area sales') ||
            title.contains('region') ||
            title.contains('national sales') ||
            title.contains('business unit manager') ||
            title.contains('line sales manager') ||
            title.contains('field force supervisor')
        );

    Boolean isRep =
        !isSfe &&
        !isManager && (
            title.contains('medical representative') ||
            title.contains('senior medical representative') ||
            title.contains('sales representative') ||
            title == 'medical rep' ||
            (isTraining && (
                u.Username.toLowerCase().contains('bassant.bahaa') ||
                u.Username.toLowerCase().contains('nada.wael') ||
                u.Username.toLowerCase().contains('omar.mohsen') ||
                u.Username.toLowerCase().contains('gassem.') ||
                u.Username.toLowerCase().contains('mohamed.rafek')
            ))
        );

    if (!isSfe && !isManager && !isRep) {
        skipped++;
        continue;
    }

    Id targetProfile = isSfe ? adminProfileId : standardProfileId;
    Id targetPsg = isSfe ? adminPsgId : (isManager ? dmPsgId : fieldRepPsgId);

    if (u.ProfileId != targetProfile) {
        profileUpdates.add(new User(Id = u.Id, ProfileId = targetProfile));
    }

    String psgKey = String.valueOf(u.Id) + ':' + String.valueOf(targetPsg);
    if (!existingKeys.contains(psgKey) && targetPsg != null) {
        psaInserts.add(
            new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetGroupId = targetPsg)
        );
        existingKeys.add(psgKey);
    }

    if (isSfe && sfeAppPsId != null) {
        String psKey = String.valueOf(u.Id) + ':' + String.valueOf(sfeAppPsId);
        if (!existingKeys.contains(psKey)) {
            psaInserts.add(
                new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = sfeAppPsId)
            );
            existingKeys.add(psKey);
        }
    }

    if (isSfe) {
        sfeCount++;
    } else if (isManager) {
        mgrCount++;
    } else {
        repCount++;
    }
}

if (!profileUpdates.isEmpty()) {
    Database.SaveResult[] profileResults = Database.update(profileUpdates, false);
    Integer ok = 0;
    Integer fail = 0;
    for (Database.SaveResult sr : profileResults) {
        if (sr.isSuccess()) {
            ok++;
        } else {
            fail++;
            System.debug('Profile fail ' + sr.getId() + ' ' + sr.getErrors());
        }
    }
    System.debug('Profile updates ok=' + ok + ' fail=' + fail);
}

if (!psaInserts.isEmpty()) {
    Database.SaveResult[] psaResults = Database.insert(psaInserts, false);
    Integer ok = 0;
    Integer fail = 0;
    for (Database.SaveResult sr : psaResults) {
        if (sr.isSuccess()) {
            ok++;
        } else {
            fail++;
            System.debug('PSA fail ' + sr.getErrors());
        }
    }
    System.debug('PSA inserts ok=' + ok + ' fail=' + fail);
}

System.debug(
    'Seats classified rep=' +
        repCount +
        ' manager=' +
        mgrCount +
        ' sfe=' +
        sfeCount +
        ' skipped=' +
        skipped
);

// Shared OTP for today's training cohort
String sharedOtp = 'REPLACE_WITH_SHARED_OTP';
List<User> trainingUsers = [
    SELECT Id, Name, Username, IsActive
    FROM User
    WHERE IsActive = TRUE AND Username IN :trainingUsernames
];
Integer otpOk = 0;
Integer otpFail = 0;
for (User tu : trainingUsers) {
    try {
        System.setPassword(tu.Id, sharedOtp);
        otpOk++;
        System.debug('OTP OK ' + tu.Username);
    } catch (Exception ex) {
        otpFail++;
        System.debug('OTP FAIL ' + tu.Username + ' ' + ex.getMessage());
    }
}
System.debug('OTP set ok=' + otpOk + ' fail=' + otpFail + ' password=' + sharedOtp);
