// sf apex run --file scripts/apex/reset-guest-permsets.apex --target-org pharma-prod
Id guestUserId = [
  SELECT GuestUserId
  FROM Site
  WHERE UrlPathPrefix = 'productsurvey'
  LIMIT 1
]
.GuestUserId;

Id productSurveyGuestId = [
  SELECT Id
  FROM PermissionSet
  WHERE Name = 'Product_Survey_Guest'
  LIMIT 1
]
.Id;

// Keep only Product_Survey_Guest and profile perm set
List<PermissionSetAssignment> toDelete = [
  SELECT Id
  FROM PermissionSetAssignment
  WHERE AssigneeId = :guestUserId AND PermissionSet.Name = 'Visit_Survey_Module'
];
if (!toDelete.isEmpty()) {
  delete toDelete;
  System.debug('Removed Visit_Survey_Module from guest user');
}

List<PermissionSetAssignment> existing = [
  SELECT Id
  FROM PermissionSetAssignment
  WHERE AssigneeId = :guestUserId AND PermissionSetId = :productSurveyGuestId
  LIMIT 1
];
if (existing.isEmpty()) {
  insert new PermissionSetAssignment(
    AssigneeId = guestUserId,
    PermissionSetId = productSurveyGuestId
  );
  System.debug('Assigned Product_Survey_Guest');
}

System.debug('GUEST_PERMSETS_DONE');
