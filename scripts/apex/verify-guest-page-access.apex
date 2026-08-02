// sf apex run --file scripts/apex/verify-guest-page-access.apex --target-org pharma-prod
PermissionSet ps = [
  SELECT Id
  FROM PermissionSet
  WHERE ProfileId IN (SELECT Id FROM Profile WHERE Name = 'Product Survey Profile')
  LIMIT 1
];
Set<Id> pageIds = new Map<Id, ApexPage>([
  SELECT Id, Name
  FROM ApexPage
  WHERE Name IN (
    'Unauthorized',
    'Exception',
    'InMaintenance',
    'ProductSurvey',
    'ProductSurveyPing'
  )
]).keySet();
Integer count = [
  SELECT COUNT()
  FROM SetupEntityAccess
  WHERE ParentId = :ps.Id AND SetupEntityId IN :pageIds
];
System.debug('PROFILE_PERMSET_PAGE_COUNT=' + count);
