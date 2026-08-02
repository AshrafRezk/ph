// sf apex run --file scripts/apex/diagnose-product-survey-site.apex --target-org pharma-prod
Site s = [
  SELECT Id, Name, UrlPathPrefix, Status, GuestUserId, AdminId, SiteType, Subdomain
  FROM Site
  WHERE UrlPathPrefix = 'productsurvey'
  LIMIT 1
];
System.debug('SITE=' + JSON.serialize(s));

User guest = [
  SELECT Id, Name, IsActive, Profile.Name
  FROM User
  WHERE Id = :s.GuestUserId
  LIMIT 1
];
System.debug('GUEST=' + JSON.serialize(guest));

List<PermissionSetAssignment> psas = [
  SELECT PermissionSet.Name
  FROM PermissionSetAssignment
  WHERE AssigneeId = :s.GuestUserId
];
System.debug('PERMSETS=' + JSON.serialize(psas));

List<DomainSite> domains = [
  SELECT Id, Domain.Domain, Domain.DomainType
  FROM DomainSite
  WHERE SiteId = :s.Id
];
System.debug('DOMAINS=' + JSON.serialize(domains));
