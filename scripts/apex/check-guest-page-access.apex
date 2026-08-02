// sf apex run --file scripts/apex/check-guest-page-access.apex --target-org pharma-prod
Id guestUserId = [
  SELECT GuestUserId
  FROM Site
  WHERE UrlPathPrefix = 'productsurvey'
  LIMIT 1
]
.GuestUserId;

Set<Id> permSetIds = new Set<Id>();
for (PermissionSetAssignment psa : [
  SELECT PermissionSetId, PermissionSet.Name
  FROM PermissionSetAssignment
  WHERE AssigneeId = :guestUserId
]) {
  System.debug('ASSIGNED=' + psa.PermissionSet.Name);
  permSetIds.add(psa.PermissionSetId);
}

Map<Id, String> pageNames = new Map<Id, String>();
for (ApexPage p : [
  SELECT Id, Name
  FROM ApexPage
  WHERE Name IN ('ProductSurvey', 'ProductSurveyPing')
]) {
  pageNames.put(p.Id, p.Name);
}

for (SetupEntityAccess sea : [
  SELECT ParentId, SetupEntityId
  FROM SetupEntityAccess
  WHERE ParentId IN :permSetIds AND SetupEntityId IN :pageNames.keySet()
]) {
  System.debug(
    'PAGE_ACCESS parent=' +
      sea.ParentId +
      ' page=' +
      pageNames.get(sea.SetupEntityId)
  );
}

Profile guestProfile = [
  SELECT Id, Name
  FROM Profile
  WHERE Name = 'Product Survey Profile'
  LIMIT 1
];
System.debug('PROFILE_ID=' + guestProfile.Id);

for (FieldPermissions fp : [
  SELECT Field, PermissionsRead, PermissionsEdit
  FROM FieldPermissions
  WHERE ParentId IN :permSetIds
  LIMIT 5
]) {
  System.debug('FIELD=' + fp.Field);
}
