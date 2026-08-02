// sf apex run --file scripts/apex/enable-guest-profile-page-access.apex --target-org pharma-prod
Profile guestProfile = [
  SELECT Id
  FROM Profile
  WHERE Name = 'Product Survey Profile'
  LIMIT 1
];

Map<String, Id> pageIds = new Map<String, Id>();
for (ApexPage p : [
  SELECT Id, Name
  FROM ApexPage
  WHERE Name IN ('ProductSurvey', 'ProductSurveyPing')
]) {
  pageIds.put(p.Name, p.Id);
}

Id controllerId = [SELECT Id FROM ApexClass WHERE Name = 'ProductSurveyController' LIMIT 1]
.Id;

Set<Id> existing = new Set<Id>();
for (SetupEntityAccess sea : [
  SELECT SetupEntityId
  FROM SetupEntityAccess
  WHERE ParentId = :guestProfile.Id
]) {
  existing.add(sea.SetupEntityId);
}

List<SetupEntityAccess> toInsert = new List<SetupEntityAccess>();
for (Id entityId : pageIds.values()) {
  if (!existing.contains(entityId)) {
    toInsert.add(
      new SetupEntityAccess(ParentId = guestProfile.Id, SetupEntityId = entityId)
    );
  }
}
if (!existing.contains(controllerId)) {
  toInsert.add(
    new SetupEntityAccess(ParentId = guestProfile.Id, SetupEntityId = controllerId)
  );
}

System.debug('EXISTING_ON_PROFILE=' + existing.size());
System.debug('TO_INSERT=' + toInsert.size());
if (!toInsert.isEmpty()) {
  try {
    insert toInsert;
    System.debug('INSERTED_PROFILE_ACCESS=' + toInsert.size());
  } catch (Exception ex) {
    System.debug('INSERT_FAILED=' + ex.getMessage());
  }
}
