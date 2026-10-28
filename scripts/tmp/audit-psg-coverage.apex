Id fieldRepPsgId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'Pharma_Field_Rep_PSG' LIMIT 1].Id;
Id dmPsgId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'Pharma_District_Manager_PSG' LIMIT 1].Id;
Id adminPsgId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = 'Pharma_Admin' LIMIT 1].Id;

Map<Id, User> seated = new Map<Id, User>([
  SELECT Id, Name, Username, Title, EmployeeNumber, Profile.Name, IsActive
  FROM User
  WHERE IsActive = TRUE
    AND Id IN (SELECT UserId FROM UserTerritory2Association WHERE IsActive = TRUE)
    AND Profile.UserType = 'Standard'
]);

Map<Id, Set<Id>> psgByUser = new Map<Id, Set<Id>>();
for (PermissionSetAssignment psa : [
  SELECT AssigneeId, PermissionSetGroupId
  FROM PermissionSetAssignment
  WHERE AssigneeId IN :seated.keySet() AND PermissionSetGroupId != null
]) {
  if (!psgByUser.containsKey(psa.AssigneeId)) {
    psgByUser.put(psa.AssigneeId, new Set<Id>());
  }
  psgByUser.get(psa.AssigneeId).add(psa.PermissionSetGroupId);
}

Integer withRep = 0;
Integer withDm = 0;
Integer withAdmin = 0;
Integer missing = 0;
List<String> missingLines = new List<String>();
List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();

for (User u : seated.values()) {
  Set<Id> groups = psgByUser.containsKey(u.Id) ? psgByUser.get(u.Id) : new Set<Id>();
  Boolean hasRep = groups.contains(fieldRepPsgId);
  Boolean hasDm = groups.contains(dmPsgId);
  Boolean hasAdmin = groups.contains(adminPsgId);
  if (hasRep) withRep++;
  if (hasDm) withDm++;
  if (hasAdmin) withAdmin++;

  String title = u.Title == null ? '' : u.Title.trim().toLowerCase();
  Boolean looksManager =
    title.contains('district') ||
    title.contains('supervisor') ||
    title.contains('area sales') ||
    title.contains('region') ||
    title.contains('national sales') ||
    title.contains('business unit manager') ||
    title.contains('line sales manager') ||
    title.contains('field force supervisor');
  Boolean looksRep =
    title.contains('medical representative') ||
    title.contains('senior medical representative') ||
    title.contains('sales representative') ||
    title == 'medical rep';

  if (!hasRep && !hasDm && !hasAdmin) {
    missing++;
    missingLines.add(
      String.valueOf(u.EmployeeNumber) +
      ' | ' +
      u.Name +
      ' | ' +
      String.valueOf(u.Title) +
      ' | ' +
      u.Profile.Name +
      ' | ' +
      u.Username
    );
    Id target = looksManager ? dmPsgId : fieldRepPsgId;
    toInsert.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetGroupId = target));
  } else if (looksManager && !hasDm && !hasAdmin) {
    // Manager title but only rep PSG — upgrade with DM PSG as well (safe; DM includes manager apps)
    toInsert.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetGroupId = dmPsgId));
  } else if (looksRep && !hasRep && !hasDm && !hasAdmin) {
    toInsert.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetGroupId = fieldRepPsgId));
  }
}

System.debug('SEATED_ACTIVE=' + seated.size());
System.debug('WITH_REP_PSG=' + withRep);
System.debug('WITH_DM_PSG=' + withDm);
System.debug('WITH_ADMIN_PSG=' + withAdmin);
System.debug('MISSING_FIELD_PSG=' + missing);
System.debug('TO_INSERT=' + toInsert.size());
for (Integer i = 0; i < Math.min(50, missingLines.size()); i++) {
  System.debug('MISSING|' + missingLines[i]);
}

if (!toInsert.isEmpty()) {
  Database.SaveResult[] results = Database.insert(toInsert, false);
  Integer ok = 0;
  Integer fail = 0;
  for (Database.SaveResult sr : results) {
    if (sr.isSuccess()) {
      ok++;
    } else {
      fail++;
      System.debug('INSERT_FAIL|' + sr.getErrors());
    }
  }
  System.debug('INSERT_OK=' + ok + ' INSERT_FAIL=' + fail);
}

// Pick validation users: active UT2A with ATF on primary territory
List<UserTerritory2Association> utas = [
  SELECT UserId, User.Name, User.Username, User.Title, User.EmployeeNumber, Territory2Id, Territory2.Name, RoleInTerritory2
  FROM UserTerritory2Association
  WHERE IsActive = TRUE
    AND User.IsActive = TRUE
    AND User.Profile.UserType = 'Standard'
  ORDER BY User.Name
  LIMIT 5000
];
Map<Id, Integer> atfByTerr = new Map<Id, Integer>();
for (AggregateResult ar : [
  SELECT Territory2_Id__c tid, COUNT(Id) cnt
  FROM Account_Territory_Fields__c
  WHERE Is_Active__c = true
  GROUP BY Territory2_Id__c
]) {
  atfByTerr.put((Id) ar.get('tid'), (Integer) ar.get('cnt'));
}

Integer printedRep = 0;
Integer printedMgr = 0;
for (UserTerritory2Association uta : utas) {
  Integer cnt = atfByTerr.containsKey(uta.Territory2Id) ? atfByTerr.get(uta.Territory2Id) : 0;
  if (cnt < 30) {
    continue;
  }
  String title = uta.User.Title == null ? '' : uta.User.Title.toLowerCase();
  Boolean isMgr =
    title.contains('district') ||
    title.contains('supervisor') ||
    title.contains('area sales') ||
    title.contains('region') ||
    title.contains('national sales') ||
    title.contains('business unit') ||
    title.contains('line sales') ||
    title.contains('field force');
  Boolean isRep =
    title.contains('medical representative') ||
    title.contains('sales representative') ||
    title == 'medical rep';
  if (!isMgr && !isRep) {
    continue;
  }
  if (isMgr && printedMgr >= 8) {
    continue;
  }
  if (isRep && printedRep >= 12) {
    continue;
  }
  System.debug(
    (isMgr ? 'MGR|' : 'REP|') +
      uta.User.EmployeeNumber +
      '|' +
      uta.User.Name +
      '|' +
      uta.User.Title +
      '|' +
      uta.Territory2.Name +
      '|' +
      cnt +
      '|' +
      uta.User.Username
  );
  if (isMgr) {
    printedMgr++;
  } else {
    printedRep++;
  }
  if (printedRep >= 12 && printedMgr >= 8) {
    break;
  }
}
System.debug('CANDIDATES_REP=' + printedRep + ' CANDIDATES_MGR=' + printedMgr);
