// sf apex run --file scripts/apex/assign-product-survey-guest-access.apex --target-org pharma-prod
Id guestUserId = [
  SELECT GuestUserId
  FROM Site
  WHERE UrlPathPrefix = 'productsurvey'
  LIMIT 1
]
.GuestUserId;

PermissionSet ps = [
  SELECT Id, Name
  FROM PermissionSet
  WHERE Name = 'Product_Survey_Guest'
  LIMIT 1
];

List<PermissionSetAssignment> existing = [
  SELECT Id
  FROM PermissionSetAssignment
  WHERE AssigneeId = :guestUserId AND PermissionSetId = :ps.Id
  LIMIT 1
];

if (existing.isEmpty()) {
  insert new PermissionSetAssignment(
    AssigneeId = guestUserId,
    PermissionSetId = ps.Id
  );
  System.debug('Assigned ' + ps.Name + ' to guest user ' + guestUserId);
} else {
  System.debug('Guest user already has ' + ps.Name);
}

String url = VisitSurveyLinkController.buildSurveyUrl(
  [SELECT Id FROM Visit__c WHERE Status__c != 'Cancelled' ORDER BY CreatedDate DESC LIMIT 1]
  .Id,
  'Empacoza 10 mg'
);
System.debug('DEMO_URL=' + url);
