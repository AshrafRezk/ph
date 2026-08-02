// One-time: assign Visit Survey Module to Product Survey guest user.
// sf apex run --file scripts/apex/setup-product-survey-guest.apex --target-org pharma-prod

Id guestUserId = [
  SELECT GuestUserId
  FROM Site
  WHERE UrlPathPrefix = 'productsurvey'
  LIMIT 1
]
.GuestUserId;
Id permSetId = [
  SELECT Id
  FROM PermissionSet
  WHERE Name = 'Visit_Survey_Module'
  LIMIT 1
]
.Id;

List<PermissionSetAssignment> existing = [
  SELECT Id
  FROM PermissionSetAssignment
  WHERE AssigneeId = :guestUserId AND PermissionSetId = :permSetId
  LIMIT 1
];
if (existing.isEmpty()) {
  insert new PermissionSetAssignment(
    AssigneeId = guestUserId,
    PermissionSetId = permSetId
  );
  System.debug('Assigned Visit_Survey_Module to Product Survey guest user.');
} else {
  System.debug('Visit_Survey_Module already assigned to guest user.');
}

List<Visit__c> visits = [
  SELECT Id, Account__r.Name
  FROM Visit__c
  WHERE Status__c = 'Completed'
  ORDER BY Start_Date__c DESC
  LIMIT 1
];
if (!visits.isEmpty()) {
  String url =
    'https://pharmaceuticals.my.salesforce-sites.com/productsurvey/ProductSurvey?visitId=' +
    visits[0].Id +
    '&product=ZetaGluc';
  System.debug('Demo URL: ' + url);
  System.debug('Visit HCP: ' + visits[0].Account__r.Name);
}
