// sf apex run --file scripts/apex/check-guest-class-access.apex --target-org pharma-prod
Id guestUserId = [
  SELECT GuestUserId
  FROM Site
  WHERE UrlPathPrefix = 'productsurvey'
  LIMIT 1
]
.GuestUserId;

Set<Id> permSetIds = new Set<Id>();
for (PermissionSetAssignment psa : [
  SELECT PermissionSetId
  FROM PermissionSetAssignment
  WHERE AssigneeId = :guestUserId
]) {
  permSetIds.add(psa.PermissionSetId);
}

Id controllerClassId = [SELECT Id FROM ApexClass WHERE Name = 'ProductSurveyController' LIMIT 1]
.Id;

Integer classAccessCount = [
  SELECT COUNT()
  FROM SetupEntityAccess
  WHERE ParentId IN :permSetIds AND SetupEntityId = :controllerClassId
];
System.debug('CLASS_ACCESS_COUNT=' + classAccessCount);

for (ObjectPermissions op : [
  SELECT SobjectType, PermissionsRead, PermissionsCreate
  FROM ObjectPermissions
  WHERE ParentId IN :permSetIds AND SobjectType IN ('Visit__c', 'Visit_Product_Survey_Feedback__c', 'Product2', 'User')
]) {
  System.debug(
    'OBJ=' +
      op.SobjectType +
      ' read=' +
      op.PermissionsRead +
      ' create=' +
      op.PermissionsCreate
  );
}

User siteAdmin = [SELECT Id, IsActive, Username FROM User WHERE Username = 'admin@pharma.eg' LIMIT 1];
System.debug('SITE_ADMIN=' + siteAdmin);
