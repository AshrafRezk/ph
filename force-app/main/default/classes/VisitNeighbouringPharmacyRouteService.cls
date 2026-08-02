public with sharing class VisitNeighbouringPharmacyRouteService {
  private static final String OSM_EXTERNAL_PREFIX = 'OSM:';
  private static final Integer DEFAULT_VISIT_DURATION_MINUTES = 60;
  private static final String PENDING_APPROVAL_STATUS = 'Pending Approval';

  @TestVisible
  private static Boolean forceLiveGeocodeInTest = false;

  public class AddPharmacyResult {
    @AuraEnabled public Id accountId;
    @AuraEnabled public Id visitId;
    @AuraEnabled public String accountName;
    @AuraEnabled public Boolean createdAccount;
    @AuraEnabled public DateTime visitStart;
    @AuraEnabled public DateTime visitEnd;
  }

  private class PharmacyAddress {
    public String street;
    public String city;
    public String state;
    public String postalCode;
    public String country;
  }

  @AuraEnabled
  public static AddPharmacyResult addExternalPharmacyToRoute(
    Id currentVisitId,
    String externalId,
    String name,
    String street,
    String city,
    String state,
    String postalCode,
    String country,
    String phone,
    Decimal latitude,
    Decimal longitude
  ) {
    if (currentVisitId == null) {
      throw new AuraHandledException('Visit Id is required.');
    }
    if (String.isBlank(externalId)) {
      throw new AuraHandledException('Pharmacy identifier is required.');
    }
    if (String.isBlank(name)) {
      throw new AuraHandledException('Pharmacy name is required.');
    }
    if (latitude == null || longitude == null) {
      throw new AuraHandledException('Pharmacy location is required.');
    }

    List<Visit__c> visits = [
      SELECT Id, Start_Date__c, End_Date__c, Assigned_To__c, Status__c
      FROM Visit__c
      WHERE Id = :currentVisitId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visits.isEmpty()) {
      throw new AuraHandledException('Visit not found.');
    }

    Visit__c currentVisit = visits[0];
    if (currentVisit.End_Date__c == null || currentVisit.Start_Date__c == null) {
      throw new AuraHandledException('Current visit must have start and end times.');
    }
    if (currentVisit.Assigned_To__c == null) {
      throw new AuraHandledException('Current visit must have an assigned rep.');
    }

    Id pharmacyRtId = resolvePharmacyRecordTypeId();
    if (pharmacyRtId == null) {
      throw new AuraHandledException('Pharmacy account record type is not configured.');
    }

    String externalKey = buildOsmExternalKey(externalId);
    PharmacyAddress address = resolvePharmacyAddress(
      street,
      city,
      state,
      postalCode,
      country,
      latitude,
      longitude
    );
    ResolvedPharmacyAccount resolvedAccount = resolveOrCreatePharmacyAccount(
      pharmacyRtId,
      externalKey,
      name.trim(),
      address,
      phone,
      latitude,
      longitude
    );

    DateTime[] visitWindow = resolveNextVisitWindow(currentVisit);
    Visit__c followUpVisit = new Visit__c();
    followUpVisit.Account__c = resolvedAccount.account.Id;
    followUpVisit.Assigned_To__c = currentVisit.Assigned_To__c;
    followUpVisit.Status__c = 'Draft';
    followUpVisit.Visit_Type__c = 'Planned (Automatically)';
    followUpVisit.Start_Date__c = visitWindow[0];
    followUpVisit.End_Date__c = visitWindow[1];
    followUpVisit.Visit_Date__c = visitWindow[0];
    insert as user followUpVisit;

    AddPharmacyResult result = new AddPharmacyResult();
    result.accountId = resolvedAccount.account.Id;
    result.visitId = followUpVisit.Id;
    result.accountName = resolvedAccount.account.Name;
    result.createdAccount = resolvedAccount.created;
    result.visitStart = followUpVisit.Start_Date__c;
    result.visitEnd = followUpVisit.End_Date__c;
    return result;
  }

  private class ResolvedPharmacyAccount {
    public Account account;
    public Boolean created;
  }

  private static ResolvedPharmacyAccount resolveOrCreatePharmacyAccount(
    Id pharmacyRtId,
    String externalKey,
    String name,
    PharmacyAddress address,
    String phone,
    Decimal latitude,
    Decimal longitude
  ) {
    ResolvedPharmacyAccount resolved = new ResolvedPharmacyAccount();
    List<Account> existing = [
      SELECT
        Id,
        Name,
        BillingStreet,
        BillingCity,
        BillingState,
        BillingPostalCode,
        BillingCountry,
        Phone,
        BillingLatitude,
        BillingLongitude
      FROM Account
      WHERE External_ID__c = :externalKey
      WITH USER_MODE
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      Account existingAccount = existing[0];
      Account toUpdate = buildAccountWithAddress(
        existingAccount.Id,
        pharmacyRtId,
        externalKey,
        name,
        address,
        phone,
        latitude,
        longitude,
        existingAccount,
        false
      );
      update as user toUpdate;
      resolved.account = [
        SELECT Id, Name
        FROM Account
        WHERE Id = :existingAccount.Id
        WITH USER_MODE
        LIMIT 1
      ];
      resolved.created = false;
      return resolved;
    }

    Account pharmacy = buildAccountWithAddress(
      null,
      pharmacyRtId,
      externalKey,
      name,
      address,
      phone,
      latitude,
      longitude,
      null,
      true
    );
    insert as user pharmacy;

    resolved.account = pharmacy;
    resolved.created = true;
    return resolved;
  }

  private static Account buildAccountWithAddress(
    Id accountId,
    Id pharmacyRtId,
    String externalKey,
    String name,
    PharmacyAddress address,
    String phone,
    Decimal latitude,
    Decimal longitude,
    Account existingAccount,
    Boolean isCreate
  ) {
    Account pharmacy = accountId == null ? new Account() : new Account(Id = accountId);
    if (isCreate) {
      pharmacy.RecordTypeId = pharmacyRtId;
      pharmacy.Name = name.length() > 255 ? name.substring(0, 255) : name;
      pharmacy.External_ID__c = externalKey;
    }

    pharmacy.BillingStreet = chooseAddressValue(
      address.street,
      existingAccount?.BillingStreet
    );
    pharmacy.BillingCity = chooseAddressValue(address.city, existingAccount?.BillingCity);
    pharmacy.BillingState = chooseAddressValue(
      address.state,
      existingAccount?.BillingState
    );
    pharmacy.BillingPostalCode = chooseAddressValue(
      address.postalCode,
      existingAccount?.BillingPostalCode
    );
    pharmacy.BillingCountry = chooseAddressValue(
      address.country,
      existingAccount?.BillingCountry
    );
    pharmacy.Phone = String.isBlank(phone)
      ? existingAccount?.Phone
      : phone;
    pharmacy.BillingLatitude = latitude;
    pharmacy.BillingLongitude = longitude;
    pharmacy.Data_Team_Approval_Status__c = PENDING_APPROVAL_STATUS;
    return pharmacy;
  }

  @TestVisible
  private static String chooseAddressValue(String incoming, String existing) {
    return String.isBlank(incoming) ? existing : incoming;
  }

  @TestVisible
  private static PharmacyAddress resolvePharmacyAddress(
    String street,
    String city,
    String state,
    String postalCode,
    String country,
    Decimal latitude,
    Decimal longitude
  ) {
    PharmacyAddress address = new PharmacyAddress();
    address.street = trimToNull(street);
    address.city = trimToNull(city);
    address.state = trimToNull(state);
    address.postalCode = trimToNull(postalCode);
    address.country = trimToNull(country);

    if (address.street == null) {
      PharmacyAddress geocoded = reverseGeocode(latitude, longitude);
      if (geocoded != null) {
        address.street = coalesce(address.street, geocoded.street);
        address.city = coalesce(address.city, geocoded.city);
        address.state = coalesce(address.state, geocoded.state);
        address.postalCode = coalesce(address.postalCode, geocoded.postalCode);
        address.country = coalesce(address.country, geocoded.country);
      }
    }
    return address;
  }

  @TestVisible
  private static PharmacyAddress reverseGeocode(Decimal latitude, Decimal longitude) {
    if (latitude == null || longitude == null) {
      return null;
    }
    if (Test.isRunningTest() && forceLiveGeocodeInTest != true) {
      return getTestGeocodeResult();
    }

    try {
      HttpRequest request = new HttpRequest();
      request.setEndpoint(
        'https://nominatim.openstreetmap.org/reverse?lat=' +
          latitude +
          '&lon=' +
          longitude +
          '&format=json&addressdetails=1'
      );
      request.setMethod('GET');
      request.setHeader('User-Agent', 'PharmaCloud-NeighbouringPharmacies/1.0');
      request.setTimeout(15000);
      HttpResponse response = new Http().send(request);
      if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
        return null;
      }
      return parseNominatimResponse(response.getBody());
    } catch (Exception e) {
      return null;
    }
  }

  @TestVisible
  private static PharmacyAddress parseNominatimResponse(String responseBody) {
    if (String.isBlank(responseBody)) {
      return null;
    }
    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      responseBody
    );
    Map<String, Object> addressMap = (Map<String, Object>) parsed.get('address');
    if (addressMap == null) {
      return null;
    }

    PharmacyAddress address = new PharmacyAddress();
    address.street = buildStreetFromNominatim(addressMap);
    address.city = firstNonBlank(
      addressMap,
      new List<String>{
        'city',
        'town',
        'village',
        'suburb',
        'municipality',
        'county'
      }
    );
    address.state = firstNonBlank(
      addressMap,
      new List<String>{ 'state', 'region', 'province' }
    );
    address.postalCode = firstNonBlank(addressMap, new List<String>{ 'postcode' });
    address.country = firstNonBlank(addressMap, new List<String>{ 'country' });
    return address;
  }

  @TestVisible
  private static String buildStreetFromNominatim(Map<String, Object> addressMap) {
    String houseNumber = firstNonBlank(addressMap, new List<String>{ 'house_number' });
    String road = firstNonBlank(
      addressMap,
      new List<String>{ 'road', 'pedestrian', 'footway', 'residential' }
    );
    if (String.isBlank(road)) {
      return null;
    }
    return String.isBlank(houseNumber) ? road : houseNumber + ' ' + road;
  }

  @TestVisible
  private static String firstNonBlank(
    Map<String, Object> values,
    List<String> keys
  ) {
    for (String key : keys) {
      if (values.containsKey(key) && values.get(key) != null) {
        String value = String.valueOf(values.get(key)).trim();
        if (String.isNotBlank(value)) {
          return value;
        }
      }
    }
    return null;
  }

  @TestVisible
  private static String coalesce(String primary, String fallback) {
    return String.isBlank(primary) ? fallback : primary;
  }

  @TestVisible
  private static String trimToNull(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    return value.trim();
  }

  @TestVisible
  private static PharmacyAddress getTestGeocodeResult() {
    PharmacyAddress address = new PharmacyAddress();
    address.street = '12 Geocode Street';
    address.city = 'Cairo';
    address.state = 'Cairo Governorate';
    address.postalCode = '11511';
    address.country = 'Egypt';
    return address;
  }

  @TestVisible
  private static DateTime[] resolveNextVisitWindow(Visit__c currentVisit) {
    Integer durationSeconds = visitDurationSeconds(currentVisit);
    Date visitDay = currentVisit.Start_Date__c.date();
    DateTime cursor = currentVisit.End_Date__c;

    List<Visit__c> laterVisits = [
      SELECT Start_Date__c, End_Date__c
      FROM Visit__c
      WHERE
        Assigned_To__c = :currentVisit.Assigned_To__c
        AND Id != :currentVisit.Id
        AND Start_Date__c >= :visitDay
        AND Start_Date__c < :visitDay.addDays(1)
        AND End_Date__c > :cursor
      WITH USER_MODE
      ORDER BY Start_Date__c ASC
    ];

    for (Visit__c laterVisit : laterVisits) {
      DateTime proposedEnd = cursor.addSeconds(durationSeconds);
      if (laterVisit.Start_Date__c >= proposedEnd) {
        break;
      }
      cursor = laterVisit.End_Date__c;
    }

    return new DateTime[] { cursor, cursor.addSeconds(durationSeconds) };
  }

  @TestVisible
  private static Integer visitDurationSeconds(Visit__c visit) {
    if (visit.Start_Date__c != null && visit.End_Date__c != null) {
      Long durationMs = visit.End_Date__c.getTime() - visit.Start_Date__c.getTime();
      if (durationMs > 0) {
        return (Integer) (durationMs / 1000);
      }
    }
    return DEFAULT_VISIT_DURATION_MINUTES * 60;
  }

  @TestVisible
  private static String buildOsmExternalKey(String externalId) {
    String trimmed = externalId.trim();
    if (trimmed.startsWith(OSM_EXTERNAL_PREFIX)) {
      return trimmed.length() > 255 ? trimmed.substring(0, 255) : trimmed;
    }
    String key = OSM_EXTERNAL_PREFIX + trimmed;
    return key.length() > 255 ? key.substring(0, 255) : key;
  }

  private static Id resolvePharmacyRecordTypeId() {
    List<RecordType> types = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Pharmacy'
      WITH USER_MODE
      LIMIT 1
    ];
    return types.isEmpty() ? null : types[0].Id;
  }
}
