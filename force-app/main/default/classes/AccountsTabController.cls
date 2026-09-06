public with sharing class AccountsTabController {
  private static final Decimal ON_TRACK_THRESHOLD = 90;
  private static final Decimal CRITICAL_THRESHOLD = 50;
  private static final String FILTER_ALL = 'All';
  private static final String SCOPE_IN = 'in';
  private static final String SCOPE_OUT = 'out';
  private static final String SCOPE_BOTH = 'both';
  private static final String SORT_CLASSIFICATION = 'classification';
  private static final String SORT_AGENTFORCE = 'agentforceScore';
  private static final String SORT_NAME = 'name';
  private static final String SORT_HEALTH = 'health';
  private static final String SORT_GAP = 'gap';
  private static final String SORT_VISITS = 'visits';
  private static final String SORT_LAST_VISIT = 'lastVisit';
  private static final Integer DEFAULT_PAGE_SIZE = 10;
  private static final Integer MAX_PAGE_SIZE = 50;
  private static final Integer MAX_MAP_POINTS = 2000;
  private static final Integer MAX_SORT_SCAN = 5000;
  private static final String RECORD_TYPE_HCO = 'Institution_HCO';
  private static final String RECORD_TYPE_HCP = 'HCP';
  private static final String RECORD_TYPE_PHARMACY = 'Pharmacy';
  private static final Set<String> HCP_RECORD_TYPES = new Set<String>{
    'SDO_PersonAccounts',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact'
  };
  private static final Set<String> PLANNER_ACCOUNT_RECORD_TYPES = new Set<String>{
    'SDO_PersonAccounts',
    'Institution_HCO',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact',
    'Pharmacy'
  };

  @TestVisible
  private static Boolean forceTerritoryScope = false;

  public class RecordTypeFilterOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public RecordTypeFilterOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class CreateRecordTypeOption {
    @AuraEnabled
    public Id recordTypeId;
    @AuraEnabled
    public String developerName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String iconName;
    @AuraEnabled
    public Boolean isPersonAccount;
  }

  public class MasterSearchRow implements Comparable {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String accountNumber;
    @AuraEnabled
    public String brickName;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public String specialty;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String recordTypeLabel;
    @AuraEnabled
    public String matchKind;
    @AuraEnabled
    public Integer score;
    @AuraEnabled
    public Boolean isPersonAccount;

    public Integer compareTo(Object other) {
      MasterSearchRow that = (MasterSearchRow) other;
      Integer scoreA = this.score == null ? 0 : this.score;
      Integer scoreB = that.score == null ? 0 : that.score;
      if (scoreA == scoreB) {
        return (this.name == null ? '' : this.name).compareTo(that.name == null ? '' : that.name);
      }
      return scoreA > scoreB ? -1 : 1;
    }
  }

  public class MapPlaceRow {
    @AuraEnabled
    public String placeId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String address;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public Id brickId;
    @AuraEnabled
    public String brickName;
    @AuraEnabled
    public Id brick148Id;
    @AuraEnabled
    public Id brick702Id;
    @AuraEnabled
    public String provider;
    @AuraEnabled
    public String staticMapUrl;
    @AuraEnabled
    public String placeKind;
    @AuraEnabled
    public String placeKindLabel;
    @AuraEnabled
    public Decimal rating;
    @AuraEnabled
    public Integer ratingCount;
    @AuraEnabled
    public Boolean isKol;
    @AuraEnabled
    public Integer starCount;
  }

  public class MapPlaceGeoFilter {
    @AuraEnabled
    public Id zoneBrickId;
    @AuraEnabled
    public Id brick148Id;
    @AuraEnabled
    public Id brick702Id;
    @AuraEnabled
    public String area;
  }

  public class MapPlaceSearchResult {
    @AuraEnabled
    public List<MapPlaceRow> places;
    @AuraEnabled
    public Decimal centerLat;
    @AuraEnabled
    public Decimal centerLng;
    @AuraEnabled
    public Integer radiusMeters;
  }

  public class WizardCreateInput {
    @AuraEnabled
    public Id recordTypeId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String firstName;
    @AuraEnabled
    public String lastName;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String whatsappNumber;
    @AuraEnabled
    public String clinicPhone;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String specialty1;
    @AuraEnabled
    public String specialty2;
    @AuraEnabled
    public String specialty3;
    @AuraEnabled
    public String pharmacyType;
    @AuraEnabled
    public String institutionType;
    @AuraEnabled
    public String street;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public String building;
    @AuraEnabled
    public String governorate;
    @AuraEnabled
    public String landmark;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public Id brickId;
    @AuraEnabled
    public Id brick148Id;
    @AuraEnabled
    public Id brick702Id;
    @AuraEnabled
    public String placeId;
  }

  public class WizardCreateResult {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer dataQualityScore;
  }

  public class WizardPickOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public WizardPickOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class WizardBrickOption {
    @AuraEnabled
    public Id brickId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String level;
    @AuraEnabled
    public Id parentBrickId;
    @AuraEnabled
    public Id zoneBrickId;
    @AuraEnabled
    public String governorate;
    @AuraEnabled
    public String city;
  }

  public class WizardCreateOptions {
    @AuraEnabled
    public List<WizardPickOption> specialtyOptions;
    @AuraEnabled
    public List<WizardPickOption> pharmacyTypeOptions;
    @AuraEnabled
    public List<WizardPickOption> institutionTypeOptions;
    @AuraEnabled
    public List<WizardPickOption> governorateOptions;
    @AuraEnabled
    public List<WizardPickOption> areaOptions;
    @AuraEnabled
    public List<WizardBrickOption> bricks70;
    @AuraEnabled
    public List<WizardBrickOption> bricks148;
    @AuraEnabled
    public List<WizardBrickOption> bricks702;
  }

  public class KolUpdateResult {
    @AuraEnabled
    public Boolean isKol;
    @AuraEnabled
    public String territoryName;
    @AuraEnabled
    public String message;
  }

  public class AccountsTabQuery {
    @AuraEnabled
    public String scope;
    @AuraEnabled
    public String searchTerm;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String classification;
    @AuraEnabled
    public String sortBy;
    @AuraEnabled
    public String sortDirection;
    @AuraEnabled
    public Integer offset;
    @AuraEnabled
    public Integer pageSize;
    @AuraEnabled
    public Date monthStart;
    @AuraEnabled
    public Id contextUserId;
    @AuraEnabled
    public List<String> accountIds;
    @AuraEnabled
    public Id brickId;
    @AuraEnabled
    public String specialtyFilter;
  }

  public class AccountsTabPage {
    @AuraEnabled
    public List<AccountsTabRow> rows;
    @AuraEnabled
    public Integer totalCount;
    @AuraEnabled
    public Integer inPlanCount;
    @AuraEnabled
    public Integer outPlanCount;
    @AuraEnabled
    public Integer behindPaceCount;
    @AuraEnabled
    public Boolean hasTimeCard;
    @AuraEnabled
    public String monthLabel;
    @AuraEnabled
    public List<FilterCount> recordTypeCounts;
    @AuraEnabled
    public Integer mapEligibleCount;
  }

  public class FilterCount {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    @AuraEnabled
    public Integer count;
  }

  public class AccountsTabRow {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String accountUrl;
    @AuraEnabled
    public String specialty;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String recordTypeName;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String accountSubtype;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public String classification;
    @AuraEnabled
    public String matrixRating;
    @AuraEnabled
    public String potential;
    @AuraEnabled
    public String penetration;
    @AuraEnabled
    public Boolean isKol;
    @AuraEnabled
    public Boolean inPlanCycle;
    @AuraEnabled
    public String planCycleLabel;
    @AuraEnabled
    public Decimal targetVisits;
    @AuraEnabled
    public Decimal actualVisits;
    @AuraEnabled
    public Decimal visitGap;
    @AuraEnabled
    public Decimal reachPercent;
    @AuraEnabled
    public Decimal projectedPercent;
    @AuraEnabled
    public String paceStatus;
    @AuraEnabled
    public String paceStatusLabel;
    @AuraEnabled
    public String frequencyStatus;
    @AuraEnabled
    public Decimal agentforceScore;
    @AuraEnabled
    public String agentforceRisk;
    @AuraEnabled
    public Integer classificationRank;
    @AuraEnabled
    public String pinKind;
    @AuraEnabled
    public DateTime lastVisitDate;
    @AuraEnabled
    public DateTime nextVisitDate;
    @AuraEnabled
    public Integer plannedVisits;
    @AuraEnabled
    public String addressLine;
    @AuraEnabled
    public Id brickId;
    @AuraEnabled
    public String brickName;
    @AuraEnabled
    public Decimal healthScore;
    @AuraEnabled
    public String healthStatus;
    @AuraEnabled
    public List<String> healthRecommendations;
    @AuraEnabled
    public String lastVisitDisplay;
    @AuraEnabled
    public String nextVisitDisplay;
  }

  public class HealthVisitHistoryItem {
    @AuraEnabled
    public Id visitId;
    @AuraEnabled
    public String dateDisplay;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String visitType;
  }

  public class HealthAffiliationItem {
    @AuraEnabled
    public Id affiliationId;
    @AuraEnabled
    public Id relatedAccountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String relationType;
    @AuraEnabled
    public String role;
    @AuraEnabled
    public String accountType;
  }

  public class AccountHealthInsight {
    @AuraEnabled
    public List<HealthVisitHistoryItem> history;
    @AuraEnabled
    public List<HealthAffiliationItem> affiliations;
  }

  @AuraEnabled(cacheable=true)
  // Backward-compatibility: some org/test flows still call the older
  // `getRecordTypeOptions()` name.
  public static List<RecordTypeFilterOption> getRecordTypeOptions() {
    return getAccountsTabRecordTypeOptions();
  }

  @AuraEnabled(cacheable=true)
  public static List<RecordTypeFilterOption> getAccountsTabRecordTypeOptions() {
    return new List<RecordTypeFilterOption>{
      new RecordTypeFilterOption('All Record Types', FILTER_ALL),
      new RecordTypeFilterOption('Institution (HCO)', RECORD_TYPE_HCO),
      new RecordTypeFilterOption('Medical Professional (HCP)', RECORD_TYPE_HCP),
      new RecordTypeFilterOption('Pharmacies', RECORD_TYPE_PHARMACY)
    };
  }

  @AuraEnabled(cacheable=true)
  public static List<CreateRecordTypeOption> getCreateableAccountRecordTypes() {
    Map<String, String> labelsByDevName = new Map<String, String>{
      'PersonAccount' => 'HCP (Medical Professional)',
      'Medical_Professional_HCP' => 'HCP (Organization)',
      'Institution_HCO' => 'HCO (Institution)',
      'Pharmacy' => 'Pharmacy',
      'Business_Contact' => 'Business Contact',
      'SDO_PersonAccounts' => 'HCP (Person Account)'
    };
    Map<String, String> descriptionsByDevName = new Map<String, String>{
      'PersonAccount' => 'Doctors and specialists as person accounts.',
      'Medical_Professional_HCP' => 'Polyclinics, clinics, and similar HCP business accounts.',
      'Institution_HCO' => 'Hospitals, contract institutions, and other healthcare organizations.',
      'Pharmacy' => 'Retail, hospital, specialty, and chain pharmacies.',
      'Business_Contact' => 'Create a business contact person account.',
      'SDO_PersonAccounts' => 'Doctors and specialists as person accounts.'
    };
    Map<String, String> iconsByDevName = new Map<String, String>{
      'PersonAccount' => 'standard:person_account',
      'Medical_Professional_HCP' => 'standard:person_account',
      'Institution_HCO' => 'standard:account',
      'Pharmacy' => 'standard:household',
      'Business_Contact' => 'standard:contact',
      'SDO_PersonAccounts' => 'standard:person_account'
    };
    List<String> preferredOrder = new List<String>{
      'PersonAccount',
      'Medical_Professional_HCP',
      'Institution_HCO',
      'Pharmacy',
      'Business_Contact',
      'SDO_PersonAccounts'
    };

    Map<String, Schema.RecordTypeInfo> availableByDevName = new Map<String, Schema.RecordTypeInfo>();
    for (Schema.RecordTypeInfo info : Account.SObjectType.getDescribe().getRecordTypeInfos()) {
      if (info == null || !info.isAvailable() || info.isMaster()) {
        continue;
      }
      String developerName = info.getDeveloperName();
      if (String.isBlank(developerName) || !labelsByDevName.containsKey(developerName)) {
        continue;
      }
      availableByDevName.put(developerName, info);
    }
    if (availableByDevName.containsKey('PersonAccount')) {
      availableByDevName.remove('SDO_PersonAccounts');
    }

    Set<Id> personTypeIds = new Set<Id>();
    for (RecordType personType : [
      SELECT Id
      FROM RecordType
      WHERE SobjectType = 'Account' AND IsPersonType = TRUE
    ]) {
      personTypeIds.add(personType.Id);
    }

    List<CreateRecordTypeOption> options = new List<CreateRecordTypeOption>();
    for (String developerName : preferredOrder) {
      Schema.RecordTypeInfo info = availableByDevName.get(developerName);
      if (info == null) {
        continue;
      }
      CreateRecordTypeOption option = new CreateRecordTypeOption();
      option.recordTypeId = info.getRecordTypeId();
      option.developerName = developerName;
      option.label = labelsByDevName.get(developerName);
      option.description = descriptionsByDevName.get(developerName);
      option.iconName = iconsByDevName.get(developerName);
      option.isPersonAccount = personTypeIds.contains(info.getRecordTypeId());
      options.add(option);
    }
    return options;
  }

  @AuraEnabled
  public static List<MasterSearchRow> searchMasterList(
    String searchTerm,
    Id recordTypeId,
    Boolean cognitive
  ) {
    return searchMasterListWithFilters(searchTerm, recordTypeId, cognitive, null, null, null);
  }

  @AuraEnabled
  public static List<MasterSearchRow> searchMasterListWithFilters(
    String searchTerm,
    Id recordTypeId,
    Boolean cognitive,
    Id brick148Id,
    Id brick702Id,
    String specialtyFilter
  ) {
    Boolean hasTerm = String.isNotBlank(searchTerm) && searchTerm.trim().length() >= 2;
    Boolean hasFilter =
      brick148Id != null ||
      brick702Id != null ||
      String.isNotBlank(specialtyFilter);
    if (recordTypeId == null || (!hasTerm && !hasFilter)) {
      return new List<MasterSearchRow>();
    }
    List<String> tokens = hasTerm
      ? AccountCognitiveSearch.tokenize(searchTerm)
      : new List<String>();
    if (hasTerm && tokens.isEmpty() && !hasFilter) {
      return new List<MasterSearchRow>();
    }

    String soql = masterListSelectClause() + 'WHERE RecordTypeId = :recordTypeId ';
    if (cognitive == true && hasTerm) {
      List<String> ors = nameVariantOrs(AccountCognitiveSearch.expandQuery(searchTerm));
      ors.addAll(masterFieldMatchOrs(tokens));
      if (ors.isEmpty()) {
        return new List<MasterSearchRow>();
      }
      soql += 'AND (' + String.join(ors, ' OR ') + ') ';
    } else if (hasTerm) {
      soql = appendMasterTokenSearchClauses(soql, tokens);
    }
    soql = appendMasterFilterClauses(soql, brick148Id, brick702Id, specialtyFilter);
    soql += cognitive == true ? 'ORDER BY Name LIMIT 200' : 'ORDER BY Name LIMIT 25';

    List<Account> accounts = Database.query(soql, AccessLevel.SYSTEM_MODE);
    List<MasterSearchRow> rows = new List<MasterSearchRow>();
    for (Account account : accounts) {
      MasterSearchRow row = toMasterRow(account, cognitive == true ? 'cognitive' : 'master');
      if (cognitive == true) {
        Integer scored = AccountCognitiveSearch.scoreName(searchTerm, account.Name);
        row.score = scored == null || scored < 1 ? 50 : scored;
      } else {
        row.score = 100;
      }
      rows.add(row);
    }
    if (cognitive == true) {
      rows.sort();
      if (rows.size() > 15) {
        List<MasterSearchRow> limited = new List<MasterSearchRow>();
        for (Integer i = 0; i < 15; i++) {
          limited.add(rows[i]);
        }
        return limited;
      }
    }
    return rows;
  }

  public static List<MapPlaceRow> searchMapPlaces(String searchTerm, String recordTypeDeveloperName) {
    MapPlaceSearchResult result = searchMapPlaces(searchTerm, recordTypeDeveloperName, null);
    return result == null || result.places == null ? new List<MapPlaceRow>() : result.places;
  }

  @AuraEnabled
  public static MapPlaceSearchResult searchMapPlaces(
    String searchTerm,
    String recordTypeDeveloperName,
    MapPlaceGeoFilter geoFilter
  ) {
    MapPlaceSearchResult payload = new MapPlaceSearchResult();
    payload.places = new List<MapPlaceRow>();
    AccountMapsPlacesService.PlaceGeoBias bias = toPlaceGeoBias(geoFilter);
    if (bias != null) {
      payload.centerLat = bias.latitude;
      payload.centerLng = bias.longitude;
      payload.radiusMeters = bias.radiusMeters;
    }
    if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
      return payload;
    }
    for (AccountMapsPlacesService.PlaceCandidate place : AccountMapsPlacesService.searchPlaces(
      searchTerm,
      recordTypeDeveloperName,
      bias
    )) {
      MapPlaceRow row = new MapPlaceRow();
      row.placeId = place.placeId;
      row.name = place.name;
      row.address = place.address;
      row.phone = place.phone;
      row.latitude = place.latitude;
      row.longitude = place.longitude;
      row.provider = 'Cloudastick Map Intelligence';
      row.staticMapUrl = place.staticMapUrl;
      row.placeKind = place.placeKind;
      row.placeKindLabel = place.placeKindLabel;
      row.rating = place.rating;
      row.ratingCount = place.ratingCount;
      row.isKol = false;
      row.starCount = ratingToStars(place.rating);
      Brick__c brick = matchBrickForPlace(place.address);
      if (brick != null) {
        row.brickId = brick.Id;
        row.brickName = String.isNotBlank(brick.Brick_Code__c)
          ? brick.Brick_Code__c + ' — ' + brick.Name
          : brick.Name;
        if (brick.Brick_Level__c == '702') {
          row.brick702Id = brick.Id;
          row.brick148Id = brick.Parent_Brick__c;
        } else if (brick.Brick_Level__c == '148') {
          row.brick148Id = brick.Id;
        }
      }
      payload.places.add(row);
    }
    attachMapPlaceKol(payload.places);
    return payload;
  }

  private static Integer ratingToStars(Decimal rating) {
    if (rating == null) {
      return 0;
    }
    Integer stars = rating.setScale(0, RoundingMode.HALF_UP).intValue();
    if (stars < 0) {
      return 0;
    }
    return stars > 5 ? 5 : stars;
  }

  private static void attachMapPlaceKol(List<MapPlaceRow> places) {
    if (places == null || places.isEmpty()) {
      return;
    }
    Set<String> placeIds = new Set<String>();
    Set<String> names = new Set<String>();
    for (MapPlaceRow row : places) {
      if (String.isNotBlank(row.placeId) && !row.placeId.startsWith('osm:') && !row.placeId.startsWith('overpass:')) {
        placeIds.add(row.placeId);
      }
      if (String.isNotBlank(row.name)) {
        names.add(row.name.trim());
      }
    }
    if (placeIds.isEmpty() && names.isEmpty()) {
      return;
    }
    Map<String, Id> accountByPlaceId = new Map<String, Id>();
    Map<String, Id> accountByName = new Map<String, Id>();
    Set<Id> accountIds = new Set<Id>();
    List<Account> matches = new List<Account>();
    if (!placeIds.isEmpty()) {
      matches.addAll([
        SELECT Id, Name, Maps_Place_Id__c
        FROM Account
        WHERE Maps_Place_Id__c IN :placeIds
        WITH SYSTEM_MODE
        LIMIT 200
      ]);
    }
    if (!names.isEmpty()) {
      matches.addAll([
        SELECT Id, Name, Maps_Place_Id__c
        FROM Account
        WHERE Name IN :names
        WITH SYSTEM_MODE
        LIMIT 200
      ]);
    }
    for (Account acct : matches) {
      accountIds.add(acct.Id);
      if (String.isNotBlank(acct.Maps_Place_Id__c)) {
        accountByPlaceId.put(acct.Maps_Place_Id__c, acct.Id);
      }
      if (String.isNotBlank(acct.Name)) {
        accountByName.put(acct.Name.trim().toLowerCase(), acct.Id);
      }
    }
    if (accountIds.isEmpty()) {
      return;
    }
    Set<Id> kolAccountIds = new Set<Id>();
    for (Account_Territory_Fields__c atf : [
      SELECT Account__c
      FROM Account_Territory_Fields__c
      WHERE Account__c IN :accountIds AND Is_Active__c = TRUE AND Is_KOL__c = TRUE
      WITH SYSTEM_MODE
    ]) {
      kolAccountIds.add(atf.Account__c);
    }
    for (MapPlaceRow row : places) {
      Id accountId = String.isNotBlank(row.placeId) ? accountByPlaceId.get(row.placeId) : null;
      if (accountId == null && String.isNotBlank(row.name)) {
        accountId = accountByName.get(row.name.trim().toLowerCase());
      }
      if (accountId != null && kolAccountIds.contains(accountId)) {
        row.isKol = true;
        if (row.starCount == null || row.starCount < 5) {
          row.starCount = 5;
        }
      }
    }
  }

  @AuraEnabled(cacheable=true)
  public static WizardCreateOptions getWizardCreateOptions() {
    WizardCreateOptions options = new WizardCreateOptions();
    options.specialtyOptions = picklistOptions(Account.Specialty_1__c);
    options.pharmacyTypeOptions = picklistOptions(Account.Pharmacy_Type__c);
    options.institutionTypeOptions = picklistOptions(Account.Institution_Type__c);
    options.governorateOptions = new List<WizardPickOption>();
    options.areaOptions = new List<WizardPickOption>();
    for (String gov : AccountCreateQualityService.EGYPT_GOVERNORATES) {
      WizardPickOption govOption = new WizardPickOption(gov, gov);
      options.governorateOptions.add(govOption);
      options.areaOptions.add(govOption);
    }
    options.bricks70 = new List<WizardBrickOption>();
    options.bricks148 = new List<WizardBrickOption>();
    options.bricks702 = new List<WizardBrickOption>();
    try {
      for (Brick__c brick : [
        SELECT
          Id,
          Name,
          Brick_Code__c,
          Brick_Level__c,
          Parent_Brick__c,
          Parent_Brick__r.Parent_Brick__c,
          City__c,
          Governorate__c
        FROM Brick__c
        WHERE Is_Active__c = TRUE AND Brick_Level__c IN ('70', '148', '702')
        WITH SYSTEM_MODE
        ORDER BY Name
      ]) {
        WizardBrickOption option = new WizardBrickOption();
        option.brickId = brick.Id;
        option.level = brick.Brick_Level__c;
        option.parentBrickId = brick.Parent_Brick__c;
        option.city = brick.City__c;
        option.governorate = brick.Governorate__c;
        option.label = String.isNotBlank(brick.Brick_Code__c)
          ? brick.Brick_Code__c + ' — ' + brick.Name
          : brick.Name;
        if (brick.Brick_Level__c == '70') {
          option.zoneBrickId = brick.Id;
          options.bricks70.add(option);
        } else if (brick.Brick_Level__c == '148') {
          option.zoneBrickId = brick.Parent_Brick__c;
          options.bricks148.add(option);
        } else {
          option.zoneBrickId = brick.Parent_Brick__r == null
            ? null
            : brick.Parent_Brick__r.Parent_Brick__c;
          options.bricks702.add(option);
        }
      }
    } catch (Exception ex) {
      // Brick query is optional when FLS is missing; comboboxes stay empty.
    }
    return options;
  }

  @AuraEnabled
  public static AccountCreateQualityService.QualityScore scoreCreateDraft(WizardCreateInput input) {
    return AccountCreateQualityService.evaluate(input);
  }

  @AuraEnabled
  public static WizardCreateResult createAccountFromWizard(WizardCreateInput input) {
    if (input == null || input.recordTypeId == null) {
      throw new AuraHandledException('Select a record type before saving.');
    }
    if (input.brick702Id == null && input.brickId != null) {
      input.brick702Id = input.brickId;
    }
    AccountCreateQualityService.assertCanSave(input);
    AccountCreateQualityService.QualityScore quality = AccountCreateQualityService.evaluate(input);

    Boolean isPerson = AccountMasterImportUtil.isPersonRecordType(input.recordTypeId);
    Account acct = new Account(RecordTypeId = input.recordTypeId);
    if (isPerson) {
      if (String.isBlank(input.lastName) && String.isNotBlank(input.name)) {
        AccountMasterImportUtil.splitPersonName(input.name, acct);
      } else {
        acct.FirstName = input.firstName;
        acct.LastName = String.isBlank(input.lastName) ? 'Unknown' : input.lastName;
      }
      if (String.isBlank(acct.LastName)) {
        throw new AuraHandledException('Last name is required for a person account.');
      }
    } else {
      acct.Name = input.name.trim();
    }

    String phone = AccountCreateQualityService.normalizeEgyptPhone(input.phone);
    String whatsapp = AccountCreateQualityService.normalizeEgyptPhone(input.whatsappNumber);
    String clinic = AccountCreateQualityService.normalizeEgyptPhone(input.clinicPhone);
    String primaryPhone = String.isNotBlank(phone)
      ? phone
      : (String.isNotBlank(whatsapp) ? whatsapp : clinic);
    acct.Phone = primaryPhone;
    if (isPerson && Schema.SObjectType.Account.fields.getMap().containsKey('PersonMobilePhone')) {
      acct.put('PersonMobilePhone', String.isNotBlank(whatsapp) ? whatsapp : primaryPhone);
    }
    putIfField('WhatsApp_Number__c', acct, whatsapp);
    putIfField('Clinic_Phone__c', acct, clinic);
    if (isPerson && Schema.SObjectType.Account.fields.getMap().containsKey('PersonEmail')) {
      acct.put('PersonEmail', input.email);
    } else {
      putIfField('Email__c', acct, input.email);
    }
    putIfField('Specialty_1__c', acct, input.specialty1);
    putIfField('Specialty_2__c', acct, input.specialty2);
    putIfField('Specialty_3__c', acct, input.specialty3);
    putIfField('Pharmacy_Type__c', acct, input.pharmacyType);
    putIfField('Institution_Type__c', acct, input.institutionType);
    putIfField('Building__c', acct, input.building);
    putIfField('Governorate__c', acct, input.governorate);
    putIfField('Landmark__c', acct, input.landmark);
    if (quality != null && quality.score != null) {
      putIfField('Data_Quality_Score__c', acct, Decimal.valueOf(quality.score));
    }

    acct.BillingStreet = input.street;
    acct.BillingCity = input.city;
    acct.BillingState = input.governorate;
    acct.BillingCountry = String.isBlank(input.country) ? AccountMasterImportUtil.COUNTRY : input.country;
    acct.BillingLatitude = input.latitude;
    acct.BillingLongitude = input.longitude;
    if (input.brick702Id != null) {
      acct.Brick__c = input.brick702Id;
    } else if (input.brickId != null) {
      acct.Brick__c = input.brickId;
    }
    putIfField('Brick_148__c', acct, input.brick148Id);
    putIfField('Brick_702__c', acct, input.brick702Id);
    if (String.isNotBlank(input.placeId)) {
      putIfField('Maps_Place_Id__c', acct, input.placeId);
    }
    if (String.isNotBlank(primaryPhone)) {
      putIfField('Maps_Phone_Number__c', acct, primaryPhone);
    }
    putIfField('Account_Stage__c', acct, 'Draft');

    try {
      insert acct;
    } catch (DmlException ex) {
      throw new AuraHandledException(
        String.isBlank(ex.getDmlMessage(0)) ? 'Could not create the account.' : ex.getDmlMessage(0)
      );
    }
    WizardCreateResult result = new WizardCreateResult();
    result.accountId = acct.Id;
    result.dataQualityScore = quality.score;
    result.message = 'Account created.';
    return result;
  }

  private static List<WizardPickOption> picklistOptions(Schema.SObjectField field) {
    List<WizardPickOption> options = new List<WizardPickOption>();
    if (field == null) {
      return options;
    }
    for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
      if (entry.isActive()) {
        options.add(new WizardPickOption(entry.getLabel(), entry.getValue()));
      }
    }
    return options;
  }

  private static void putIfField(String fieldName, Account acct, Object value) {
    if (value == null) {
      return;
    }
    if (value instanceof String && String.isBlank((String) value)) {
      return;
    }
    if (Schema.SObjectType.Account.fields.getMap().containsKey(fieldName)) {
      acct.put(fieldName, value);
    }
  }

  @AuraEnabled
  public static KolUpdateResult setAccountKol(Id accountId, Boolean isKol) {
    if (accountId == null) {
      throw new AuraHandledException('Account is required.');
    }

    Id userId = UserInfo.getUserId();
    Account_Territory_Fields__c atf = resolveKolAtf(accountId, userId);
    if (atf == null) {
      throw new AuraHandledException(
        'No territory is available. Switch to a territory and try again.'
      );
    }

    Boolean nextIsKol = isKol == true;
    atf.Is_KOL__c = nextIsKol;
    try {
      if (atf.Id == null) {
        Database.insert(atf, AccessLevel.SYSTEM_MODE);
      } else {
        Database.update(atf, AccessLevel.SYSTEM_MODE);
      }
    } catch (Exception ex) {
      throw new AuraHandledException(
        String.isBlank(ex.getMessage())
          ? 'Could not update KOL for this territory.'
          : ex.getMessage()
      );
    }

    String territoryName = territoryNameForId(atf.Territory2_Id__c);
    String territoryLabel = String.isBlank(territoryName) ? 'this territory' : territoryName;
    KolUpdateResult result = new KolUpdateResult();
    result.isKol = nextIsKol;
    result.territoryName = territoryName;
    result.message = nextIsKol
      ? 'Marked as KOL for ' + territoryLabel + '.'
      : 'Removed KOL for ' + territoryLabel + '.';
    return result;
  }

  @AuraEnabled
  public static AccountHealthInsight getAccountHealthInsight(Id accountId) {
    if (accountId == null) {
      throw new AuraHandledException('Account Id is required.');
    }
    AccountHealthInsight insight = new AccountHealthInsight();
    insight.history = loadHealthVisitHistory(accountId);
    insight.affiliations = loadHealthAffiliations(accountId);
    return insight;
  }

  @AuraEnabled
  public static AccountsTabPage getAccountsTabPage(
    String scope,
    String searchTerm,
    String recordTypeDeveloperName,
    String classification,
    String sortBy,
    String sortDirection,
    Integer offset,
    Integer pageSize,
    Date monthStart,
    Id contextUserId,
    List<String> accountIds,
    Id brickId,
    String specialtyFilter
  ) {
    AccountsTabQuery query = toQuery(
      scope,
      searchTerm,
      recordTypeDeveloperName,
      classification,
      sortBy,
      sortDirection,
      offset,
      pageSize,
      monthStart,
      contextUserId,
      accountIds
    );
    query.brickId = brickId;
    query.specialtyFilter = specialtyFilter;
    return buildPage(query, false);
  }

  // Backward-compatibility wrapper: some org test flows call the older
  // method name `getAccountsPage(AccountsTabQuery)`.
  @AuraEnabled
  public static AccountsTabPage getAccountsPage(AccountsTabQuery query) {
    if (query == null) {
      return new AccountsTabPage();
    }
    return buildPage(query, false);
  }

  @AuraEnabled
  public static AccountsTabPage getAccountsTabMapPoints(
    String scope,
    String searchTerm,
    String recordTypeDeveloperName,
    String classification,
    String sortBy,
    String sortDirection,
    Integer offset,
    Integer pageSize,
    Date monthStart,
    Id contextUserId,
    List<String> accountIds,
    Id brickId,
    String specialtyFilter
  ) {
    AccountsTabQuery query = toQuery(
      scope,
      searchTerm,
      recordTypeDeveloperName,
      classification,
      sortBy,
      sortDirection,
      offset,
      pageSize,
      monthStart,
      contextUserId,
      accountIds
    );
    query.brickId = brickId;
    query.specialtyFilter = specialtyFilter;
    return buildPage(query, true);
  }

  private static AccountsTabQuery toQuery(
    String scope,
    String searchTerm,
    String recordTypeDeveloperName,
    String classification,
    String sortBy,
    String sortDirection,
    Integer offset,
    Integer pageSize,
    Date monthStart,
    Id contextUserId,
    List<String> accountIds
  ) {
    AccountsTabQuery query = new AccountsTabQuery();
    query.scope = scope;
    query.searchTerm = searchTerm;
    query.recordTypeDeveloperName = recordTypeDeveloperName;
    query.classification = classification;
    query.sortBy = sortBy;
    query.sortDirection = sortDirection;
    query.offset = offset;
    query.pageSize = pageSize;
    query.monthStart = monthStart;
    query.contextUserId = contextUserId;
    query.accountIds = accountIds;
    return query;
  }

  private static AccountsTabPage buildPage(AccountsTabQuery query, Boolean mapMode) {
    AccountsTabPage result = new AccountsTabPage();
    result.rows = new List<AccountsTabRow>();
    result.totalCount = 0;
    result.inPlanCount = 0;
    result.outPlanCount = 0;
    result.behindPaceCount = 0;
    result.hasTimeCard = false;
    result.recordTypeCounts = new List<FilterCount>();

    if (query == null) {
      query = new AccountsTabQuery();
    }

    Id userId = query.contextUserId != null ? query.contextUserId : UserInfo.getUserId();
    Date monthStart = query.monthStart != null
      ? Date.newInstance(query.monthStart.year(), query.monthStart.month(), 1)
      : Date.today().toStartOfMonth();
    Date monthEnd = monthStart.addMonths(1).addDays(-1);
    result.monthLabel = monthStart.format();

    String scope = normalizeScope(query.scope);
    String sortBy = String.isBlank(query.sortBy) ? SORT_AGENTFORCE : query.sortBy;
    Boolean sortAsc = 'asc'.equalsIgnoreCase(query.sortDirection);
    Integer pageSize = Math.min(
      query.pageSize == null ? DEFAULT_PAGE_SIZE : query.pageSize,
      mapMode ? MAX_MAP_POINTS : MAX_PAGE_SIZE
    );
    Integer rowOffset = query.offset == null || query.offset < 0 ? 0 : query.offset;

    Set<Id> territoryIds = expandTerritoryHierarchy(getUserTerritoryIds(userId));
    Set<String> territoryIdStrings = new Set<String>();
    for (Id territoryId : territoryIds) {
      territoryIdStrings.add(String.valueOf(territoryId));
    }

    if (territoryIds.isEmpty() && !hasFullAccountAccess()) {
      return result;
    }

    Set<Id> accountIdFilter = resolveAccountIdsFilter(query.accountIds);
    Set<String> recordTypes = resolveRecordTypeFilter(query.recordTypeDeveloperName);
    String classificationFilter = resolveClassificationFilter(query.classification);
    String searchTerm = String.isBlank(query.searchTerm) ? null : query.searchTerm.trim();
    List<String> searchTokens = tokenizeSearch(searchTerm);

    List<Employee_Time_Card__c> cards = [
      SELECT Id
      FROM Employee_Time_Card__c
      WHERE Employee__c = :userId AND Time_Card_Month_Start_Date__c = :monthStart
      WITH USER_MODE
      LIMIT 1
    ];
    Id timeCardId = cards.isEmpty() ? null : cards[0].Id;
    result.hasTimeCard = timeCardId != null;

    WorkingDaysSummary workingDays = timeCardId != null
      ? computeWorkingDays(timeCardId, Date.today())
      : new WorkingDaysSummary();

    Integer territoryAtfCount = 0;
    if (!territoryIdStrings.isEmpty()) {
      territoryAtfCount = [
        SELECT COUNT()
        FROM Account_Territory_Fields__c
        WHERE
          Is_Active__c = TRUE
          AND Territory2_Id__c IN :territoryIdStrings
          AND Account__c != NULL
        WITH SYSTEM_MODE
      ];
    }

    // Head Office / admin: page Accounts directly unless the switcher pinned a territory.
    Boolean useFullAccountQuery =
      !forceTerritoryScope &&
      !TerritoryContextService.hasSelectedTerritory() &&
      userId == UserInfo.getUserId() &&
      hasFullAccountAccess();

    Set<Id> scopedAccountIds = null;
    if (SCOPE_IN.equals(scope)) {
      scopedAccountIds = loadTimeCardTargetAccountIds(timeCardId);
      if (scopedAccountIds.isEmpty()) {
        result.recordTypeCounts = emptyRecordTypeCounts(0);
        return result;
      }
    } else if (!useFullAccountQuery) {
      if (territoryIdStrings.isEmpty()) {
        result.recordTypeCounts = emptyRecordTypeCounts(0);
        return result;
      }
      // Cap well under the 50k governor so COUNT + ATF + page queries cannot hit 50001.
      if (territoryAtfCount > 20000) {
        throw new AuraHandledException(
          'This territory has too many accounts to load at once. Assign Head Office access or narrow with a saved list.'
        );
      }
      scopedAccountIds = loadTerritoryAccountIdsCapped(territoryIdStrings, 20000);
      if (scopedAccountIds.isEmpty()) {
        result.recordTypeCounts = emptyRecordTypeCounts(0);
        return result;
      }
    }

    if (accountIdFilter != null) {
      if (scopedAccountIds == null) {
        scopedAccountIds = accountIdFilter;
      } else {
        scopedAccountIds.retainAll(accountIdFilter);
        if (scopedAccountIds.isEmpty()) {
          result.recordTypeCounts = emptyRecordTypeCounts(0);
          return result;
        }
      }
    }

    if (classificationFilter != null && !territoryIdStrings.isEmpty()) {
      Set<Id> classifiedIds = loadClassifiedAccountIds(
        territoryIdStrings,
        classificationFilter,
        scopedAccountIds
      );
      scopedAccountIds = classifiedIds;
      if (scopedAccountIds.isEmpty()) {
        result.recordTypeCounts = emptyRecordTypeCounts(0);
        return result;
      }
    }

    Integer fetchLimit = pageSize;
    Integer fetchOffset = rowOffset;
    Boolean geocodedOnly = mapMode == true;
    Boolean nameSort = SORT_NAME.equals(sortBy);
    Boolean scanThenPage = mapMode != true && nameSort != true;
    if (scanThenPage) {
      Integer scopedSize = scopedAccountIds == null ? MAX_SORT_SCAN : scopedAccountIds.size();
      fetchLimit = Math.max(pageSize, Math.min(scopedSize, MAX_SORT_SCAN));
      fetchOffset = 0;
    }

    List<Account> pageAccounts = queryAccountsPage(
      recordTypes,
      scopedAccountIds,
      searchTokens,
      geocodedOnly,
      fetchLimit,
      fetchOffset,
      query.brickId,
      query.specialtyFilter,
      nameSort,
      sortAsc
    );
    result.totalCount = countAccounts(
      recordTypes,
      scopedAccountIds,
      searchTokens,
      geocodedOnly,
      query.brickId,
      query.specialtyFilter
    );
    result.mapEligibleCount = mapMode
      ? result.totalCount
      : countAccounts(recordTypes, scopedAccountIds, searchTokens, true, query.brickId, query.specialtyFilter);
    result.recordTypeCounts = buildRecordTypeCountsAggregate(
      recordTypes,
      scopedAccountIds,
      searchTokens
    );

    // Without a time card, every account is out of plan at the territory level.
    if (timeCardId == null) {
      result.outPlanCount = result.totalCount;
      result.inPlanCount = 0;
      result.behindPaceCount = 0;
    }

    if (pageAccounts.isEmpty()) {
      return result;
    }

    Set<Id> pageAccountIds = new Map<Id, Account>(pageAccounts).keySet();
    Map<Id, Account_Territory_Fields__c> bestAtfByAccount = loadAtfForAccounts(
      pageAccountIds,
      territoryIdStrings
    );

    Map<Id, Employee_Time_Card_Account_Target__c> targetByAccount = new Map<Id, Employee_Time_Card_Account_Target__c>();
    if (timeCardId != null) {
      for (Employee_Time_Card_Account_Target__c target : [
        SELECT
          Account__c,
          Target_Visit_Frequency__c,
          Actual_Visits__c,
          Frequency_Status__c,
          Reach_Percent__c,
          Potentiality__c
        FROM Employee_Time_Card_Account_Target__c
        WHERE Employee_Time_Card__c = :timeCardId AND Account__c IN :pageAccountIds
        WITH USER_MODE
      ]) {
        targetByAccount.put(target.Account__c, target);
      }
      // Approximate plan counts from targets when we did not filter to in-plan only.
      if (!SCOPE_IN.equals(scope) && !SCOPE_OUT.equals(scope)) {
        result.inPlanCount = [
          SELECT COUNT()
          FROM Employee_Time_Card_Account_Target__c
          WHERE Employee_Time_Card__c = :timeCardId AND Account__c != NULL
          WITH USER_MODE
        ];
        result.outPlanCount = Math.max(0, result.totalCount - result.inPlanCount);
      } else if (SCOPE_IN.equals(scope)) {
        result.inPlanCount = result.totalCount;
        result.outPlanCount = 0;
      } else if (SCOPE_OUT.equals(scope)) {
        result.inPlanCount = 0;
        result.outPlanCount = result.totalCount;
      }
    }

    Map<Id, Integer> futureVisitsByAccount = loadFutureVisitCounts(pageAccountIds, userId, monthEnd);
    Map<Id, Integer> completedVisitsByAccount = loadCompletedVisitCounts(
      pageAccountIds,
      userId,
      monthStart,
      monthEnd
    );
    Map<Id, DateTime> lastVisitByAccount = loadLastVisitDates(pageAccountIds, userId);
    Map<Id, DateTime> nextVisitByAccount = loadNextVisitDates(pageAccountIds, userId, monthEnd);
    Map<String, Decimal> targetFrequencyByKey = loadTargetFrequencies(bestAtfByAccount.values());

    List<AccountsTabRow> pageRows = new List<AccountsTabRow>();
    for (Account account : pageAccounts) {
      Boolean inPlan = targetByAccount.containsKey(account.Id);
      if (SCOPE_OUT.equals(scope) && inPlan) {
        continue;
      }
      if (SCOPE_IN.equals(scope) && !inPlan) {
        continue;
      }

      Account_Territory_Fields__c atf = bestAtfByAccount.get(account.Id);
      if (atf == null) {
        atf = new Account_Territory_Fields__c(
          Account__c = account.Id,
          Is_Active__c = true
        );
      }

      AccountsTabRow row = buildRow(
        account,
        atf,
        inPlan,
        targetByAccount.get(account.Id),
        targetFrequencyByKey,
        completedVisitsByAccount.get(account.Id),
        futureVisitsByAccount.get(account.Id),
        lastVisitByAccount.get(account.Id),
        nextVisitByAccount.get(account.Id),
        workingDays,
        timeCardId != null
      );
      pageRows.add(row);
      if (timeCardId != null && (row.paceStatus == 'behind' || row.paceStatus == 'critical')) {
        result.behindPaceCount++;
      }
    }

    sortRows(pageRows, sortBy, sortAsc);
    result.rows = scanThenPage ? sliceRows(pageRows, rowOffset, pageSize) : pageRows;
    return result;
  }

  private static final String HEAD_OFFICE_EXTERNAL_ID = 'TERR_HEAD_OFFICE';

  private static Boolean hasFullAccountAccess() {
    if (isSystemAdministrator()) {
      return true;
    }
    Id headOfficeId = getHeadOfficeTerritoryId();
    if (headOfficeId == null) {
      return false;
    }
    for (UserTerritory2Association assignment : [
      SELECT Id
      FROM UserTerritory2Association
      WHERE UserId = :UserInfo.getUserId() AND Territory2Id = :headOfficeId
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      return true;
    }
    return false;
  }

  private static Boolean isSystemAdministrator() {
    User currentUser = [
      SELECT Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH USER_MODE
      LIMIT 1
    ];
    return currentUser.Profile.Name == 'System Administrator';
  }

  private static Id getHeadOfficeTerritoryId() {
    List<Territory2> territories = [
      SELECT Id
      FROM Territory2
      WHERE External_ID__c = :HEAD_OFFICE_EXTERNAL_ID
      WITH USER_MODE
      LIMIT 1
    ];
    return territories.isEmpty() ? null : territories[0].Id;
  }

  private static Set<Id> loadTimeCardTargetAccountIds(Id timeCardId) {
    Set<Id> accountIds = new Set<Id>();
    if (timeCardId == null) {
      return accountIds;
    }
    for (Employee_Time_Card_Account_Target__c target : [
      SELECT Account__c
      FROM Employee_Time_Card_Account_Target__c
      WHERE Employee_Time_Card__c = :timeCardId AND Account__c != NULL
      WITH USER_MODE
    ]) {
      accountIds.add(target.Account__c);
    }
    return accountIds;
  }

  private static Set<Id> loadTerritoryAccountIdsCapped(
    Set<String> territoryIdStrings,
    Integer rowLimit
  ) {
    Set<Id> accountIds = new Set<Id>();
    if (territoryIdStrings == null || territoryIdStrings.isEmpty()) {
      return accountIds;
    }
    Integer lim = rowLimit == null || rowLimit < 1 ? 20000 : rowLimit;
    for (Account_Territory_Fields__c atf : [
      SELECT Account__c
      FROM Account_Territory_Fields__c
      WHERE
        Is_Active__c = TRUE
        AND Territory2_Id__c IN :territoryIdStrings
        AND Account__c != NULL
      WITH SYSTEM_MODE
      LIMIT :lim
    ]) {
      accountIds.add(atf.Account__c);
    }
    return accountIds;
  }

  private static Set<Id> loadClassifiedAccountIds(
    Set<String> territoryIdStrings,
    String classificationFilter,
    Set<Id> scopedAccountIds
  ) {
    Set<Id> classifiedIds = new Set<Id>();
    // Never scan the full 92k ATF set — page-safe classification uses a hard cap.
    Integer lim = scopedAccountIds != null ? Math.min(20000, scopedAccountIds.size() + 1) : 20000;
    for (Account_Territory_Fields__c atf : [
      SELECT Account__c, Matrix_Rating__c, Classification__c, Potential__c
      FROM Account_Territory_Fields__c
      WHERE
        Is_Active__c = TRUE
        AND Territory2_Id__c IN :territoryIdStrings
        AND Account__c != NULL
      WITH SYSTEM_MODE
      LIMIT :lim
    ]) {
      if (scopedAccountIds != null && !scopedAccountIds.contains(atf.Account__c)) {
        continue;
      }
      if (matchesClassification(atf, classificationFilter)) {
        classifiedIds.add(atf.Account__c);
      }
    }
    return classifiedIds;
  }

  private static String appendTokenSearchClauses(String soql, List<String> searchTokens) {
    if (searchTokens == null || searchTokens.isEmpty()) {
      return soql;
    }
    for (String token : searchTokens) {
      if (String.isBlank(token)) {
        continue;
      }
      List<String> ors = nameVariantOrs(AccountCognitiveSearch.expandToken(token));
      String orig = String.escapeSingleQuotes(token);
      ors.add('External_ID__c LIKE \'%' + orig + '%\'');
      ors.add('BillingCity LIKE \'%' + orig + '%\'');
      ors.add('BillingStreet LIKE \'%' + orig + '%\'');
      ors.add('Specialty_1__c LIKE \'%' + orig + '%\'');
      ors.add('Brick__r.Name LIKE \'%' + orig + '%\'');
      ors.add('Brick__r.Brick_Code__c LIKE \'%' + orig + '%\'');
      soql += 'AND (' + String.join(ors, ' OR ') + ') ';
    }
    return soql;
  }

  private static String appendMasterTokenSearchClauses(String soql, List<String> searchTokens) {
    if (searchTokens == null || searchTokens.isEmpty()) {
      return soql;
    }
    for (String token : searchTokens) {
      if (String.isBlank(token)) {
        continue;
      }
      List<String> ors = nameVariantOrs(AccountCognitiveSearch.expandToken(token));
      ors.addAll(masterFieldMatchOrs(new List<String>{ token }));
      if (ors.isEmpty()) {
        continue;
      }
      soql += 'AND (' + String.join(ors, ' OR ') + ') ';
    }
    return soql;
  }

  private static String appendMasterFilterClauses(
    String soql,
    Id brick148Id,
    Id brick702Id,
    String specialtyFilter
  ) {
    if (brick148Id != null) {
      String idVal = String.escapeSingleQuotes(String.valueOf(brick148Id));
      List<String> brickOrs = new List<String>{ 'Brick__c = \'' + idVal + '\'' };
      if (accountHasField('Brick_148__c')) {
        brickOrs.add('Brick_148__c = \'' + idVal + '\'');
      }
      if (accountHasField('Brick_702__c')) {
        brickOrs.add('Brick_702__r.Parent_Brick__c = \'' + idVal + '\'');
      }
      soql += 'AND (' + String.join(brickOrs, ' OR ') + ') ';
    }
    if (brick702Id != null) {
      String idVal = String.escapeSingleQuotes(String.valueOf(brick702Id));
      List<String> brickOrs = new List<String>{ 'Brick__c = \'' + idVal + '\'' };
      if (accountHasField('Brick_702__c')) {
        brickOrs.add('Brick_702__c = \'' + idVal + '\'');
      }
      soql += 'AND (' + String.join(brickOrs, ' OR ') + ') ';
    }
    if (String.isNotBlank(specialtyFilter)) {
      String specialtyApi = MedicalSpecialtyPicklist.resolveApiValue(specialtyFilter);
      String esc = String.escapeSingleQuotes(specialtyApi);
      List<String> specOrs = new List<String>();
      for (String fieldName : specialtyFieldApiNames()) {
        specOrs.add(fieldName + ' = \'' + esc + '\'');
      }
      if (!specOrs.isEmpty()) {
        soql += 'AND (' + String.join(specOrs, ' OR ') + ') ';
      }
    }
    return soql;
  }

  private static List<String> masterFieldMatchOrs(List<String> tokens) {
    List<String> ors = new List<String>();
    Set<String> seen = new Set<String>();
    if (tokens == null) {
      return ors;
    }
    for (String token : tokens) {
      if (String.isBlank(token)) {
        continue;
      }
      for (String variant : AccountCognitiveSearch.expandTokenForFieldSearch(token)) {
        if (String.isBlank(variant) || variant.length() < 2) {
          continue;
        }
        String esc = String.escapeSingleQuotes(variant);
        String key = esc.toLowerCase();
        if (seen.contains(key)) {
          continue;
        }
        seen.add(key);
        ors.addAll(likeClausesForMasterFields(esc));
      }
    }
    return ors;
  }

  private static List<String> likeClausesForMasterFields(String esc) {
    List<String> clauses = new List<String>{
      'External_ID__c LIKE \'%' + esc + '%\'',
      'Phone LIKE \'%' + esc + '%\'',
      'BillingCity LIKE \'%' + esc + '%\'',
      'BillingStreet LIKE \'%' + esc + '%\'',
      'BillingCountry LIKE \'%' + esc + '%\'',
      'Brick__r.Name LIKE \'%' + esc + '%\'',
      'Brick__r.Brick_Code__c LIKE \'%' + esc + '%\''
    };
    addLikeIfField(clauses, 'PersonMobilePhone', esc);
    addLikeIfField(clauses, 'WhatsApp_Number__c', esc);
    addLikeIfField(clauses, 'Clinic_Phone__c', esc);
    addLikeIfField(clauses, 'Maps_Phone_Number__c', esc);
    addLikeIfField(clauses, 'Governorate__c', esc);
    addLikeIfField(clauses, 'Landmark__c', esc);
    addLikeIfField(clauses, 'Building__c', esc);
    if (accountHasField('Brick_148__c')) {
      clauses.add('Brick_148__r.Name LIKE \'%' + esc + '%\'');
      clauses.add('Brick_148__r.Brick_Code__c LIKE \'%' + esc + '%\'');
    }
    if (accountHasField('Brick_702__c')) {
      clauses.add('Brick_702__r.Name LIKE \'%' + esc + '%\'');
      clauses.add('Brick_702__r.Brick_Code__c LIKE \'%' + esc + '%\'');
    }
    for (String fieldName : specialtyFieldApiNames()) {
      clauses.add(fieldName + ' LIKE \'%' + esc + '%\'');
    }
    return clauses;
  }

  private static void addLikeIfField(List<String> clauses, String fieldName, String esc) {
    if (accountHasField(fieldName)) {
      clauses.add(fieldName + ' LIKE \'%' + esc + '%\'');
    }
  }

  private static String masterListSelectClause() {
    List<String> fields = new List<String>{
      'Id',
      'Name',
      'FirstName',
      'LastName',
      'External_ID__c',
      'Phone',
      'BillingStreet',
      'BillingCity',
      'BillingCountry',
      'Brick__c',
      'Brick__r.Name',
      'Brick__r.Brick_Code__c',
      'RecordType.Name',
      'IsPersonAccount'
    };
    addSelectIfField(fields, 'PersonMobilePhone');
    addSelectIfField(fields, 'WhatsApp_Number__c');
    addSelectIfField(fields, 'Clinic_Phone__c');
    addSelectIfField(fields, 'Maps_Phone_Number__c');
    addSelectIfField(fields, 'Governorate__c');
    addSelectIfField(fields, 'Landmark__c');
    addSelectIfField(fields, 'Building__c');
    fields.addAll(specialtyFieldApiNames());
    if (accountHasField('Brick_148__c')) {
      fields.add('Brick_148__c');
      fields.add('Brick_148__r.Name');
      fields.add('Brick_148__r.Brick_Code__c');
    }
    if (accountHasField('Brick_702__c')) {
      fields.add('Brick_702__c');
      fields.add('Brick_702__r.Name');
      fields.add('Brick_702__r.Brick_Code__c');
    }
    return 'SELECT ' + String.join(fields, ', ') + ' FROM Account ';
  }

  private static void addSelectIfField(List<String> fields, String fieldName) {
    if (accountHasField(fieldName)) {
      fields.add(fieldName);
    }
  }

  private static Boolean accountHasField(String fieldName) {
    if (String.isBlank(fieldName)) {
      return false;
    }
    Map<String, Schema.SObjectField> fields = Schema.SObjectType.Account.fields.getMap();
    if (!fields.containsKey(fieldName)) {
      return false;
    }
    Schema.DescribeFieldResult describe = fields.get(fieldName).getDescribe();
    return describe != null && describe.isAccessible() && describe.isFilterable();
  }

  private static List<String> specialtyFieldCache;

  private static List<String> specialtyFieldApiNames() {
    if (specialtyFieldCache != null) {
      return specialtyFieldCache;
    }
    List<String> preferred = new List<String>{
      'Specialty_1__c',
      'Sub_Specialty__c',
      'Specialty_2__c',
      'Specialty_3__c',
      'Specialty_4__c',
      'Specialty_5__c'
    };
    Map<String, Schema.SObjectField> fields = Schema.SObjectType.Account.fields.getMap();
    List<String> found = new List<String>();
    Set<String> seen = new Set<String>();
    for (String name : preferred) {
      if (!fields.containsKey(name)) {
        continue;
      }
      String apiName = fields.get(name).getDescribe().getName();
      found.add(apiName);
      seen.add(apiName.toLowerCase());
    }
    List<String> extras = new List<String>();
    for (String key : fields.keySet()) {
      if (!key.contains('specialty') || seen.contains(key)) {
        continue;
      }
      Schema.DescribeFieldResult describe = fields.get(key).getDescribe();
      Schema.DisplayType fieldType = describe.getType();
      if (
        fieldType != Schema.DisplayType.PICKLIST &&
        fieldType != Schema.DisplayType.MULTIPICKLIST &&
        fieldType != Schema.DisplayType.STRING &&
        fieldType != Schema.DisplayType.TEXTAREA
      ) {
        continue;
      }
      extras.add(describe.getName());
      seen.add(key);
    }
    extras.sort();
    found.addAll(extras);
    specialtyFieldCache = found;
    return specialtyFieldCache;
  }

  private static List<String> nameVariantOrs(List<String> variants) {
    List<String> ors = new List<String>();
    Set<String> seen = new Set<String>();
    if (variants == null) {
      return ors;
    }
    for (String variant : variants) {
      if (String.isBlank(variant) || variant.length() < 2) {
        continue;
      }
      String esc = String.escapeSingleQuotes(variant);
      String key = esc.toLowerCase();
      if (seen.contains(key)) {
        continue;
      }
      seen.add(key);
      ors.add('Name LIKE \'%' + esc + '%\'');
      ors.add('FirstName LIKE \'%' + esc + '%\'');
      ors.add('LastName LIKE \'%' + esc + '%\'');
    }
    return ors;
  }

  private static MasterSearchRow toMasterRow(Account account, String matchKind) {
    MasterSearchRow row = new MasterSearchRow();
    row.accountId = account.Id;
    row.name = account.Name;
    row.accountNumber = account.External_ID__c;
    row.location = buildAddressLine(account.BillingStreet, account.BillingCity);
    if (String.isBlank(row.location)) {
      row.location = account.BillingCountry;
    }
    row.phone = account.Phone;
    if (
      Schema.SObjectType.Account.fields.getMap().containsKey('PersonMobilePhone') &&
      account.get('PersonMobilePhone') != null
    ) {
      row.phone = String.valueOf(account.get('PersonMobilePhone'));
    }
    row.specialty = joinAccountSpecialties(account);
    row.recordTypeLabel = account.RecordType == null ? null : account.RecordType.Name;
    row.matchKind = matchKind;
    row.isPersonAccount = account.IsPersonAccount == true;
    row.brickName = resolveMasterBrickName(account);
    return row;
  }

  private static String resolveMasterBrickName(Account account) {
    if (account.Brick__r != null) {
      return formatBrickName(account.Brick__r.Brick_Code__c, account.Brick__r.Name);
    }
    if (accountHasField('Brick_702__c') && account.getSObject('Brick_702__r') != null) {
      Brick__c brick702 = (Brick__c) account.getSObject('Brick_702__r');
      return formatBrickName(brick702.Brick_Code__c, brick702.Name);
    }
    if (accountHasField('Brick_148__c') && account.getSObject('Brick_148__r') != null) {
      Brick__c brick148 = (Brick__c) account.getSObject('Brick_148__r');
      return formatBrickName(brick148.Brick_Code__c, brick148.Name);
    }
    return null;
  }

  private static String formatBrickName(String code, String name) {
    if (String.isNotBlank(code) && String.isNotBlank(name)) {
      return code + ' — ' + name;
    }
    return name;
  }

  private static String joinAccountSpecialties(Account account) {
    List<String> labels = new List<String>();
    Set<String> seen = new Set<String>();
    for (String fieldName : specialtyFieldApiNames()) {
      Object raw = account.get(fieldName);
      if (raw == null) {
        continue;
      }
      String apiValue = String.valueOf(raw);
      if (String.isBlank(apiValue)) {
        continue;
      }
      String label = MedicalSpecialtyPicklist.getLabel(apiValue);
      String display = String.isNotBlank(label) ? label : apiValue;
      String key = display.toLowerCase();
      if (seen.contains(key)) {
        continue;
      }
      seen.add(key);
      labels.add(display);
    }
    return labels.isEmpty() ? null : String.join(labels, ' · ');
  }

  private static AccountMapsPlacesService.PlaceGeoBias toPlaceGeoBias(
    MapPlaceGeoFilter geoFilter
  ) {
    if (geoFilter == null) {
      return null;
    }
    if (
      geoFilter.zoneBrickId == null &&
      geoFilter.brick148Id == null &&
      geoFilter.brick702Id == null &&
      String.isBlank(geoFilter.area)
    ) {
      return null;
    }
    AccountMapsPlacesService.PlaceGeoBias bias = new AccountMapsPlacesService.PlaceGeoBias();
    bias.areaName = String.isBlank(geoFilter.area) ? null : geoFilter.area.trim();
    Set<Id> brickIds = new Set<Id>();
    if (geoFilter.zoneBrickId != null) {
      brickIds.add(geoFilter.zoneBrickId);
    }
    if (geoFilter.brick148Id != null) {
      brickIds.add(geoFilter.brick148Id);
    }
    if (geoFilter.brick702Id != null) {
      brickIds.add(geoFilter.brick702Id);
    }
    if (!brickIds.isEmpty()) {
      try {
        Map<Id, Brick__c> bricks = new Map<Id, Brick__c>(
          [
            SELECT Id, Name, Brick_Level__c, City__c, Governorate__c
            FROM Brick__c
            WHERE Id IN :brickIds
            WITH SYSTEM_MODE
          ]
        );
        Brick__c zone = geoFilter.zoneBrickId == null ? null : bricks.get(geoFilter.zoneBrickId);
        Brick__c brick148 = geoFilter.brick148Id == null ? null : bricks.get(geoFilter.brick148Id);
        Brick__c brick702 = geoFilter.brick702Id == null ? null : bricks.get(geoFilter.brick702Id);
        if (zone != null) {
          bias.zoneName = zone.Name;
        }
        if (brick702 != null) {
          bias.brickName = brick702.Name;
          if (String.isBlank(bias.areaName) && String.isNotBlank(brick702.City__c)) {
            bias.areaName = brick702.City__c;
          }
        } else if (brick148 != null) {
          bias.brickName = brick148.Name;
        }
      } catch (Exception ex) {
        // Brick labels are optional when FLS is missing.
      }
    }
    applyAccountCentroidSample(bias, geoFilter);
    if (geoFilter.brick702Id != null) {
      bias.radiusMeters = 8000;
    } else if (geoFilter.brick148Id != null) {
      bias.radiusMeters = 18000;
    } else if (geoFilter.zoneBrickId != null) {
      bias.radiusMeters = 40000;
    } else {
      bias.radiusMeters = 55000;
    }
    return AccountMapsPlacesService.completeGeoBias(bias);
  }

  private static void applyAccountCentroidSample(
    AccountMapsPlacesService.PlaceGeoBias bias,
    MapPlaceGeoFilter geoFilter
  ) {
    if (bias == null || geoFilter == null) {
      return;
    }
    Set<Id> sampleIds = new Set<Id>();
    try {
      if (geoFilter.brick702Id != null) {
        sampleIds.add(geoFilter.brick702Id);
      } else if (geoFilter.brick148Id != null) {
        sampleIds.add(geoFilter.brick148Id);
        for (Brick__c child : [
          SELECT Id
          FROM Brick__c
          WHERE Parent_Brick__c = :geoFilter.brick148Id
          WITH SYSTEM_MODE
          LIMIT 40
        ]) {
          sampleIds.add(child.Id);
        }
      } else if (geoFilter.zoneBrickId != null) {
        sampleIds.add(geoFilter.zoneBrickId);
        for (Brick__c child : [
          SELECT Id
          FROM Brick__c
          WHERE
            Parent_Brick__c = :geoFilter.zoneBrickId
            OR Parent_Brick__r.Parent_Brick__c = :geoFilter.zoneBrickId
          WITH SYSTEM_MODE
          LIMIT 80
        ]) {
          sampleIds.add(child.Id);
        }
      }
      if (sampleIds.isEmpty()) {
        return;
      }
      Decimal latSum = 0;
      Decimal lonSum = 0;
      Integer count = 0;
      for (Account acct : [
        SELECT BillingLatitude, BillingLongitude
        FROM Account
        WHERE
          Brick__c IN :sampleIds
          AND BillingLatitude != NULL
          AND BillingLongitude != NULL
        WITH SYSTEM_MODE
        LIMIT 25
      ]) {
        latSum += acct.BillingLatitude;
        lonSum += acct.BillingLongitude;
        count++;
      }
      if (count > 0) {
        bias.latitude = latSum / count;
        bias.longitude = lonSum / count;
      }
    } catch (Exception ex) {
      // Centroid sample is optional; name-based bias still applies.
    }
  }

  private static Brick__c matchBrickForPlace(String address) {
    if (String.isBlank(address)) {
      return null;
    }
    String cityHint = address.contains(',')
      ? address.substring(0, address.indexOf(',')).trim()
      : address.trim();
    if (cityHint.length() < 3) {
      return null;
    }
    String likeHint = '%' + cityHint.left(40) + '%';
    try {
      List<Brick__c> bricks = [
        SELECT Id, Name, Brick_Code__c, Brick_Level__c, Parent_Brick__c, City__c, Governorate__c
        FROM Brick__c
        WHERE
          Is_Active__c = TRUE
          AND (City__c = :cityHint OR Name LIKE :likeHint OR Governorate__c LIKE :likeHint)
        WITH USER_MODE
        LIMIT 1
      ];
      return bricks.isEmpty() ? null : bricks[0];
    } catch (Exception ex) {
      return null;
    }
  }

  private static List<Account> queryAccountsPage(
    Set<String> recordTypes,
    Set<Id> scopedAccountIds,
    List<String> searchTokens,
    Boolean geocodedOnly,
    Integer lim,
    Integer rowOffset,
    Id brickId,
    String specialtyFilter,
    Boolean nameSort,
    Boolean sortAsc
  ) {
    String soql =
      'SELECT Id, Name, Specialty_1__c, Institution_Type__c, BillingStreet, BillingCity, BillingLatitude, BillingLongitude, ' +
      'Brick__c, Brick__r.Name, Brick__r.Brick_Code__c, ' +
      'RecordType.Name, RecordType.DeveloperName FROM Account ' +
      'WHERE RecordType.DeveloperName IN :recordTypes ';
    if (scopedAccountIds != null) {
      soql += 'AND Id IN :scopedAccountIds ';
    }
    if (brickId != null) {
      soql += 'AND Brick__c = :brickId ';
    }
    if (String.isNotBlank(specialtyFilter) && !FILTER_ALL.equals(specialtyFilter)) {
      soql += 'AND Specialty_1__c = :specialtyFilter ';
    }
    soql = appendTokenSearchClauses(soql, searchTokens);
    if (geocodedOnly == true) {
      soql += 'AND BillingLatitude != NULL AND BillingLongitude != NULL ';
    }
    String direction = nameSort == true && sortAsc != true ? 'DESC' : 'ASC';
    soql += 'ORDER BY Name ' + direction + ' LIMIT :lim OFFSET :rowOffset';
    return Database.query(soql, AccessLevel.USER_MODE);
  }

  private static Integer countAccounts(
    Set<String> recordTypes,
    Set<Id> scopedAccountIds,
    List<String> searchTokens,
    Boolean geocodedOnly,
    Id brickId,
    String specialtyFilter
  ) {
    String soql = 'SELECT COUNT() FROM Account WHERE RecordType.DeveloperName IN :recordTypes ';
    if (scopedAccountIds != null) {
      soql += 'AND Id IN :scopedAccountIds ';
    }
    if (brickId != null) {
      soql += 'AND Brick__c = :brickId ';
    }
    if (String.isNotBlank(specialtyFilter) && !FILTER_ALL.equals(specialtyFilter)) {
      soql += 'AND Specialty_1__c = :specialtyFilter ';
    }
    soql = appendTokenSearchClauses(soql, searchTokens);
    if (geocodedOnly == true) {
      soql += 'AND BillingLatitude != NULL AND BillingLongitude != NULL ';
    }
    return Database.countQuery(soql, AccessLevel.USER_MODE);
  }

  private static Map<Id, Account_Territory_Fields__c> loadAtfForAccounts(
    Set<Id> accountIds,
    Set<String> territoryIdStrings
  ) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new Map<Id, Account_Territory_Fields__c>();
    }
    List<Account_Territory_Fields__c> atfRecords;
    if (territoryIdStrings == null || territoryIdStrings.isEmpty()) {
      atfRecords = [
        SELECT
          Id,
          Account__c,
          Classification__c,
          Matrix_Rating__c,
          Potential__c,
          Penetration__c,
          Is_KOL__c,
          Territory2_Id__c
        FROM Account_Territory_Fields__c
        WHERE Is_Active__c = TRUE AND Account__c IN :accountIds
        WITH SYSTEM_MODE
      ];
    } else {
      atfRecords = [
        SELECT
          Id,
          Account__c,
          Classification__c,
          Matrix_Rating__c,
          Potential__c,
          Penetration__c,
          Is_KOL__c,
          Territory2_Id__c
        FROM Account_Territory_Fields__c
        WHERE
          Is_Active__c = TRUE
          AND Account__c IN :accountIds
          AND Territory2_Id__c IN :territoryIdStrings
        WITH SYSTEM_MODE
      ];
    }
    return pickBestAtfPerAccount(atfRecords);
  }

  private static Account_Territory_Fields__c resolveKolAtf(Id accountId, Id userId) {
    Set<Id> territoryIds = expandTerritoryHierarchy(getUserTerritoryIds(userId));
    Set<String> territoryIdStrings = new Set<String>();
    for (Id territoryId : territoryIds) {
      territoryIdStrings.add(String.valueOf(territoryId));
    }

    if (!territoryIdStrings.isEmpty()) {
      Map<Id, Account_Territory_Fields__c> existingByAccount = pickBestAtfPerAccount([
        SELECT
          Id,
          Account__c,
          Is_KOL__c,
          Territory2_Id__c,
          Classification__c,
          Potential__c,
          Penetration__c
        FROM Account_Territory_Fields__c
        WHERE
          Account__c = :accountId
          AND Is_Active__c = TRUE
          AND Territory2_Id__c IN :territoryIdStrings
        WITH SYSTEM_MODE
      ]);
      if (existingByAccount.containsKey(accountId)) {
        return existingByAccount.get(accountId);
      }
    }

    Id createForTerritoryId = TerritoryContextService.getSelectedTerritoryId();
    Set<Id> switchable = TerritoryContextService.getSwitchableTerritoryIds(userId);
    if (createForTerritoryId == null || !switchable.contains(createForTerritoryId)) {
      createForTerritoryId = null;
      for (Id assignedId : TerritoryContextService.getAssignedTerritoryIds(userId)) {
        createForTerritoryId = assignedId;
        break;
      }
    }
    if (createForTerritoryId == null) {
      return null;
    }
    return new Account_Territory_Fields__c(
      Account__c = accountId,
      Territory2_Id__c = String.valueOf(createForTerritoryId),
      Is_Active__c = true
    );
  }

  private static String territoryNameForId(String territoryIdValue) {
    if (String.isBlank(territoryIdValue)) {
      return null;
    }
    try {
      Id territoryId = (Id) territoryIdValue;
      List<Territory2> territories = [
        SELECT Name
        FROM Territory2
        WHERE Id = :territoryId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      return territories.isEmpty() ? null : territories[0].Name;
    } catch (Exception ex) {
      return null;
    }
  }

  private static List<FilterCount> emptyRecordTypeCounts(Integer total) {
    List<FilterCount> counts = new List<FilterCount>();
    FilterCount allEntry = new FilterCount();
    allEntry.label = 'All';
    allEntry.value = FILTER_ALL;
    allEntry.count = total;
    counts.add(allEntry);
    return counts;
  }

  private static List<FilterCount> buildRecordTypeCountsAggregate(
    Set<String> recordTypes,
    Set<Id> scopedAccountIds,
    List<String> searchTokens
  ) {
    String soql =
      'SELECT RecordType.DeveloperName developerName, COUNT(Id) cnt FROM Account ' +
      'WHERE RecordType.DeveloperName IN :recordTypes ';
    if (scopedAccountIds != null) {
      soql += 'AND Id IN :scopedAccountIds ';
    }
    soql = appendTokenSearchClauses(soql, searchTokens);
    soql += 'GROUP BY RecordType.DeveloperName';

    Map<String, Integer> countsByKey = new Map<String, Integer>();
    Integer total = 0;
    for (AggregateResult agg : Database.query(soql, AccessLevel.USER_MODE)) {
      String developerName = (String) agg.get('developerName');
      Integer cnt = Integer.valueOf(agg.get('cnt'));
      String key = canonicalRecordTypeFilterKey(developerName);
      countsByKey.put(key, (countsByKey.containsKey(key) ? countsByKey.get(key) : 0) + cnt);
      total += cnt;
    }

    List<FilterCount> counts = emptyRecordTypeCounts(total);
    for (String key : new List<String>{ RECORD_TYPE_HCO, RECORD_TYPE_HCP, RECORD_TYPE_PHARMACY }) {
      if (countsByKey.containsKey(key)) {
        FilterCount entry = new FilterCount();
        entry.label = canonicalRecordTypeFilterLabel(key);
        entry.value = key;
        entry.count = countsByKey.get(key);
        counts.add(entry);
      }
    }
    return counts;
  }

  private static AccountsTabRow buildRow(
    Account account,
    Account_Territory_Fields__c atf,
    Boolean inPlan,
    Employee_Time_Card_Account_Target__c target,
    Map<String, Decimal> targetFrequencyByKey,
    Integer completedVisits,
    Integer futureVisits,
    DateTime lastVisitDate,
    DateTime nextVisitDate,
    WorkingDaysSummary workingDays,
    Boolean hasTimeCard
  ) {
    AccountsTabRow row = new AccountsTabRow();
    row.accountId = account.Id;
    row.accountName = account.Name;
    row.accountUrl = '/' + String.valueOf(account.Id);
    row.specialty = MedicalSpecialtyPicklist.getLabel(account.Specialty_1__c);
    row.city = account.BillingCity;
    row.addressLine = buildAddressLine(account.BillingStreet, account.BillingCity);
    row.brickId = account.Brick__c;
    if (account.Brick__r != null) {
      row.brickName = String.isNotBlank(account.Brick__r.Brick_Code__c)
        ? account.Brick__r.Brick_Code__c + ' — ' + account.Brick__r.Name
        : account.Brick__r.Name;
    }
    row.recordTypeName = account.RecordType?.Name;
    row.recordTypeDeveloperName = account.RecordType?.DeveloperName;
    row.accountSubtype = account.Institution_Type__c;
    row.latitude = account.BillingLatitude;
    row.longitude = account.BillingLongitude;
    row.classification = String.isNotBlank(atf.Classification__c)
      ? atf.Classification__c
      : resolvePotentiality(atf);
    row.matrixRating = atf.Matrix_Rating__c;
    row.potential = atf.Potential__c;
    row.penetration = atf.Penetration__c;
    row.isKol = atf.Is_KOL__c == true;
    row.inPlanCycle = inPlan;
    row.planCycleLabel = inPlan ? 'In' : 'Out';
    row.classificationRank = classificationRank(row.classification);
    row.pinKind = resolvePinKind(row.recordTypeDeveloperName, row.recordTypeName);

    Integer completed = completedVisits == null ? 0 : completedVisits;
    Integer future = futureVisits == null ? 0 : futureVisits;
    row.plannedVisits = future;
    row.lastVisitDate = lastVisitDate;
    row.nextVisitDate = nextVisitDate;

    if (inPlan && target != null) {
      row.targetVisits = nvl(target.Target_Visit_Frequency__c);
      row.actualVisits = nvl(target.Actual_Visits__c);
      row.reachPercent = toDisplayPercent(target.Reach_Percent__c);
      row.frequencyStatus = target.Frequency_Status__c;
    } else if (!inPlan) {
      row.targetVisits = null;
      row.actualVisits = completed;
      row.reachPercent = null;
      row.frequencyStatus = null;
    } else {
      String freqKey = String.valueOf(account.Id) + ':' + atf.Territory2_Id__c;
      row.targetVisits = targetFrequencyByKey.containsKey(freqKey)
        ? targetFrequencyByKey.get(freqKey)
        : 1;
      row.actualVisits = completed;
      row.reachPercent = row.targetVisits > 0
        ? (row.actualVisits / row.targetVisits) * 100
        : 0;
      row.frequencyStatus = null;
    }

    if (!inPlan) {
      row.visitGap = null;
      row.projectedPercent = null;
      row.paceStatus = 'na';
      row.paceStatusLabel = paceStatusLabel(row.paceStatus);
      applyHealthMetrics(row, lastVisitDate, nextVisitDate);
      applyAgentforceScore(row);
      return row;
    }

    row.visitGap = Math.max(0, nvl(row.targetVisits) - nvl(row.actualVisits));

    if (hasTimeCard && workingDays.paceRatio > 0 && row.targetVisits > 0) {
      Decimal projectedVisits = row.actualVisits / workingDays.paceRatio;
      row.projectedPercent = (projectedVisits / row.targetVisits) * 100;
      row.paceStatus = paceStatusFromProjected(row.projectedPercent);
    } else if (hasTimeCard && row.targetVisits > 0 && row.actualVisits > 0) {
      row.projectedPercent = 100;
      row.paceStatus = 'ahead';
    } else if (!hasTimeCard) {
      row.projectedPercent = null;
      row.paceStatus = 'na';
    } else {
      row.projectedPercent = 0;
      row.paceStatus = row.targetVisits > 0 ? 'critical' : 'na';
    }

    row.paceStatusLabel = paceStatusLabel(row.paceStatus);
    applyHealthMetrics(row, lastVisitDate, nextVisitDate);
    applyAgentforceScore(row);
    return row;
  }

  private static void applyHealthMetrics(
    AccountsTabRow row,
    DateTime lastVisitDate,
    DateTime nextVisitDate
  ) {
    row.lastVisitDisplay = formatVisitDate(lastVisitDate);
    row.nextVisitDisplay = formatVisitDate(nextVisitDate);
    row.healthRecommendations = new List<String>();

    if (row.pinKind != 'hcp') {
      row.healthScore = null;
      row.healthStatus = 'na';
      return;
    }

    Decimal visitScore = 40;
    if (row.inPlanCycle && row.targetVisits != null && row.targetVisits > 0) {
      Decimal ratio = Math.min(1, nvl(row.actualVisits) / row.targetVisits);
      visitScore = ratio * 40;
    } else if (!row.inPlanCycle && row.actualVisits != null && row.actualVisits > 0) {
      visitScore = 25;
    }

    Decimal recencyScore = 30;
    if (lastVisitDate == null) {
      recencyScore = 0;
      row.healthRecommendations.add('Schedule first visit — no completed calls on record.');
    } else {
      Integer daysSince = lastVisitDate.date().daysBetween(Date.today());
      if (daysSince <= 14) {
        recencyScore = 30;
      } else if (daysSince <= 30) {
        recencyScore = 20;
        row.healthRecommendations.add('Last visit was ' + daysSince + ' days ago — plan a follow-up.');
      } else if (daysSince <= 60) {
        recencyScore = 10;
        row.healthRecommendations.add('Account is going cold — prioritize a visit.');
      } else {
        recencyScore = 0;
        row.healthRecommendations.add('No recent engagement — urgent visit recommended.');
      }
    }

    Decimal paceScore = 20;
    if (row.paceStatus == 'ahead' || row.paceStatus == 'on_track') {
      paceScore = 20;
    } else if (row.paceStatus == 'behind') {
      paceScore = 10;
      row.healthRecommendations.add('Visit pace is behind — add calls to your planner.');
    } else if (row.paceStatus == 'critical') {
      paceScore = 0;
      row.healthRecommendations.add('Critical visit gap — plan immediately.');
    } else if (row.paceStatus == 'na') {
      paceScore = 10;
    }

    Decimal feedbackScore = 10;
    if (row.frequencyStatus == 'RCF' || row.frequencyStatus == 'MCF') {
      feedbackScore = 10;
    } else if (row.frequencyStatus == 'LCF') {
      feedbackScore = 3;
    }

    row.healthScore = visitScore + recencyScore + paceScore + feedbackScore;
    if (row.healthScore >= 70) {
      row.healthStatus = 'healthy';
    } else if (row.healthScore >= 40) {
      row.healthStatus = 'warning';
    } else {
      row.healthStatus = 'unhealthy';
    }

    if (nextVisitDate == null && row.inPlanCycle) {
      row.healthRecommendations.add('No upcoming visit planned — use Next Best Action.');
    }
    if (row.healthRecommendations.size() > 2) {
      row.healthRecommendations = new List<String>{
        row.healthRecommendations[0],
        row.healthRecommendations[1]
      };
    }
  }

  private static String formatVisitDate(DateTime value) {
    if (value == null) {
      return '—';
    }
    return value.format('MMM d, yyyy');
  }

  private static List<HealthVisitHistoryItem> loadHealthVisitHistory(Id accountId) {
    List<HealthVisitHistoryItem> history = new List<HealthVisitHistoryItem>();
    for (Visit__c visit : [
      SELECT Id, Start_Date__c, Status__c, Visit_Type__c
      FROM Visit__c
      WHERE Account__c = :accountId AND Status__c != 'Cancelled'
      WITH USER_MODE
      ORDER BY Start_Date__c DESC NULLS LAST
      LIMIT 8
    ]) {
      HealthVisitHistoryItem item = new HealthVisitHistoryItem();
      item.visitId = visit.Id;
      item.dateDisplay = formatVisitDate(visit.Start_Date__c);
      item.status = String.isBlank(visit.Status__c) ? 'Unknown' : visit.Status__c;
      item.visitType = String.isBlank(visit.Visit_Type__c) ? 'Visit' : visit.Visit_Type__c;
      history.add(item);
    }
    return history;
  }

  private static List<HealthAffiliationItem> loadHealthAffiliations(Id accountId) {
    List<HealthAffiliationItem> affiliations = new List<HealthAffiliationItem>();
    for (Account_Affiliation__c affiliation : [
      SELECT
        Id,
        Affiliation_Type__c,
        Role__c,
        Primary_Account__c,
        Primary_Account__r.Name,
        Primary_Account__r.RecordType.Name,
        Related_Account__c,
        Related_Account__r.Name,
        Related_Account__r.RecordType.Name
      FROM Account_Affiliation__c
      WHERE
        Is_Active__c = TRUE
        AND (Primary_Account__c = :accountId OR Related_Account__c = :accountId)
      WITH USER_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 8
    ]) {
      Boolean relatedIsOther = affiliation.Related_Account__c != null
        && affiliation.Related_Account__c != accountId;
      Id otherId = relatedIsOther
        ? affiliation.Related_Account__c
        : affiliation.Primary_Account__c;
      String otherName = relatedIsOther
        ? affiliation.Related_Account__r.Name
        : affiliation.Primary_Account__r.Name;
      String otherType = relatedIsOther
        ? affiliation.Related_Account__r.RecordType.Name
        : affiliation.Primary_Account__r.RecordType.Name;
      if (otherId == null || String.isBlank(otherName)) {
        continue;
      }
      HealthAffiliationItem item = new HealthAffiliationItem();
      item.affiliationId = affiliation.Id;
      item.relatedAccountId = otherId;
      item.name = otherName;
      item.relationType = String.isBlank(affiliation.Affiliation_Type__c)
        ? 'Affiliate'
        : affiliation.Affiliation_Type__c;
      item.role = affiliation.Role__c;
      item.accountType = otherType;
      affiliations.add(item);
    }
    return affiliations;
  }

  private static void applyAgentforceScore(AccountsTabRow row) {
    Decimal visitGapRatio = (row.targetVisits != null && row.targetVisits > 0)
      ? Math.max(0, nvl(row.visitGap)) / row.targetVisits
      : 0;
    Decimal paceRiskRatio;
    if (row.projectedPercent == null) {
      // Out of plan / unknown pace used to default to 100% (score 200 for every class B).
      // Derive risk from health so same-class rows still differ.
      paceRiskRatio = row.healthScore == null
        ? 0.25
        : Math.max(0, Math.min(1, (100 - row.healthScore) / 100));
    } else {
      paceRiskRatio = Math.max(0, Math.min(1, (100 - row.projectedPercent) / 100));
    }
    Decimal healthRisk = row.healthScore == null
      ? 10
      : Math.max(0, 100 - row.healthScore);
    row.agentforceScore = (
      Decimal.valueOf(row.classificationRank == null ? 0 : row.classificationRank) * 100 +
      visitGapRatio * 50 +
      paceRiskRatio * 50 +
      healthRisk * 0.1
    ).setScale(1);
    row.agentforceRisk = agentforceRiskLabel(row.paceStatus);
  }

  private static String agentforceRiskLabel(String paceStatus) {
    if (paceStatus == 'critical') {
      return 'High';
    }
    if (paceStatus == 'behind') {
      return 'Med';
    }
    if (paceStatus == 'na') {
      return 'Low';
    }
    return 'Low';
  }

  private static String paceStatusLabel(String paceStatus) {
    if (paceStatus == 'ahead') {
      return 'Ahead';
    }
    if (paceStatus == 'on_track') {
      return 'On Track';
    }
    if (paceStatus == 'behind') {
      return 'Behind';
    }
    if (paceStatus == 'critical') {
      return 'Critical';
    }
    return 'N/A';
  }

  private static Map<Id, Account_Territory_Fields__c> pickBestAtfPerAccount(
    List<Account_Territory_Fields__c> atfRecords
  ) {
    Map<Id, Account_Territory_Fields__c> bestByAccount = new Map<Id, Account_Territory_Fields__c>();
    for (Account_Territory_Fields__c atf : atfRecords) {
      if (atf.Account__c == null) {
        continue;
      }
      if (!bestByAccount.containsKey(atf.Account__c)) {
        bestByAccount.put(atf.Account__c, atf);
        continue;
      }
      Account_Territory_Fields__c existing = bestByAccount.get(atf.Account__c);
      if (classificationRank(resolvePotentiality(atf)) >
          classificationRank(resolvePotentiality(existing))) {
        bestByAccount.put(atf.Account__c, atf);
      }
    }
    return bestByAccount;
  }

  private static Map<String, Decimal> loadTargetFrequencies(
    List<Account_Territory_Fields__c> atfRecords
  ) {
    Set<String> accountIdStrings = new Set<String>();
    Set<String> territoryIds = new Set<String>();
    for (Account_Territory_Fields__c atf : atfRecords) {
      accountIdStrings.add(String.valueOf(atf.Account__c));
      territoryIds.add(atf.Territory2_Id__c);
    }
    Map<String, Decimal> result = new Map<String, Decimal>();
    if (territoryIds.isEmpty()) {
      return result;
    }
    for (Account_Territory_Product_Fields__c atpf : [
      SELECT Account__c, Territory2_Id__c, Target_Visit_Frequency__c
      FROM Account_Territory_Product_Fields__c
      WHERE Territory2_Id__c IN :territoryIds AND Is_Active__c = TRUE
      WITH SYSTEM_MODE
    ]) {
      String key = String.valueOf(atpf.Account__c) + ':' + atpf.Territory2_Id__c;
      if (!accountIdStrings.contains(String.valueOf(atpf.Account__c))) {
        continue;
      }
      Decimal mapped = EmployeeTimeCardService.mapFrequencyPicklist(
        atpf.Target_Visit_Frequency__c
      );
      if (!result.containsKey(key) || mapped > result.get(key)) {
        result.put(key, mapped);
      }
    }
    return result;
  }

  private static Map<Id, Integer> loadFutureVisitCounts(
    Set<Id> accountIds,
    Id userId,
    Date monthEnd
  ) {
    Map<Id, Integer> counts = new Map<Id, Integer>();
    for (AggregateResult agg : [
      SELECT Account__c accountId, COUNT(Id) visitCount
      FROM Visit__c
      WHERE
        Account__c IN :accountIds
        AND Assigned_To__c = :userId
        AND Start_Date__c >= :DateTime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0))
        AND Start_Date__c <= :DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0))
        AND Status__c IN ('Draft', 'Scheduled', 'Rescheduled')
      WITH USER_MODE
      GROUP BY Account__c
    ]) {
      counts.put((Id) agg.get('accountId'), (Integer) agg.get('visitCount'));
    }
    return counts;
  }

  private static Map<Id, Integer> loadCompletedVisitCounts(
    Set<Id> accountIds,
    Id userId,
    Date monthStart,
    Date monthEnd
  ) {
    Map<Id, Integer> counts = new Map<Id, Integer>();
    for (AggregateResult agg : [
      SELECT Account__c accountId, COUNT(Id) visitCount
      FROM Visit__c
      WHERE
        Account__c IN :accountIds
        AND Assigned_To__c = :userId
        AND Start_Date__c >= :DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0))
        AND Start_Date__c <= :DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0))
        AND Status__c = 'Completed'
      WITH USER_MODE
      GROUP BY Account__c
    ]) {
      counts.put((Id) agg.get('accountId'), (Integer) agg.get('visitCount'));
    }
    return counts;
  }

  private static List<AccountsTabRow> sliceRows(
    List<AccountsTabRow> rows,
    Integer rowOffset,
    Integer pageSize
  ) {
    List<AccountsTabRow> sliced = new List<AccountsTabRow>();
    if (rows == null || rows.isEmpty() || pageSize == null || pageSize <= 0) {
      return sliced;
    }
    Integer startIdx = rowOffset == null || rowOffset < 0 ? 0 : rowOffset;
    if (startIdx >= rows.size()) {
      return sliced;
    }
    Integer endIdx = Math.min(startIdx + pageSize, rows.size());
    for (Integer i = startIdx; i < endIdx; i++) {
      sliced.add(rows[i]);
    }
    return sliced;
  }

  private static void sortRows(List<AccountsTabRow> rows, String sortBy, Boolean sortAsc) {
    if (rows == null || rows.isEmpty()) {
      return;
    }
    if (SORT_NAME.equals(sortBy)) {
      rows.sort(new NameComparator(sortAsc));
    } else if (SORT_CLASSIFICATION.equals(sortBy)) {
      rows.sort(new ClassificationComparator(sortAsc));
    } else if (SORT_HEALTH.equals(sortBy)) {
      rows.sort(new HealthComparator(sortAsc));
    } else if (SORT_GAP.equals(sortBy)) {
      rows.sort(new GapComparator(sortAsc));
    } else if (SORT_VISITS.equals(sortBy)) {
      rows.sort(new VisitsComparator(sortAsc));
    } else if (SORT_LAST_VISIT.equals(sortBy)) {
      rows.sort(new LastVisitComparator(sortAsc));
    } else {
      rows.sort(new AgentforceScoreComparator(sortAsc));
    }
  }

  @AuraEnabled
  public static String exportAccountsCsv(
    String scope,
    String searchTerm,
    String recordTypeDeveloperName,
    String classification,
    String sortBy,
    String sortDirection,
    Date monthStart,
    Id contextUserId,
    Id brickId,
    String specialtyFilter
  ) {
    AccountsTabQuery query = toQuery(
      scope,
      searchTerm,
      recordTypeDeveloperName,
      classification,
      sortBy,
      sortDirection,
      0,
      MAX_PAGE_SIZE,
      monthStart,
      contextUserId,
      null
    );
    query.brickId = brickId;
    query.specialtyFilter = specialtyFilter;
    query.pageSize = MAX_PAGE_SIZE;
    query.offset = 0;

    AccountsTabPage page = buildPage(query, false);
    List<String> lines = new List<String>{
      'Account,Class,Plan,Actual Visits,Target Visits,Gap,Health,Last Visit,Next Visit,Specialty,Address,Brick'
    };
    for (AccountsTabRow row : page.rows) {
      lines.add(
        csvEscape(row.accountName) + ',' +
        csvEscape(row.classification) + ',' +
        csvEscape(row.planCycleLabel) + ',' +
        csvEscape(String.valueOf(row.actualVisits)) + ',' +
        csvEscape(String.valueOf(row.targetVisits)) + ',' +
        csvEscape(String.valueOf(row.visitGap)) + ',' +
        csvEscape(row.healthStatus) + ',' +
        csvEscape(row.lastVisitDisplay) + ',' +
        csvEscape(row.nextVisitDisplay) + ',' +
        csvEscape(row.specialty) + ',' +
        csvEscape(row.addressLine) + ',' +
        csvEscape(row.brickName)
      );
    }
    return String.join(lines, '\n');
  }

  private static String csvEscape(String value) {
    if (value == null) {
      return '';
    }
    String escaped = value.replace('"', '""');
    if (escaped.contains(',') || escaped.contains('"') || escaped.contains('\n')) {
      return '"' + escaped + '"';
    }
    return escaped;
  }

  private static List<FilterCount> buildRecordTypeCountsFromRows(List<AccountsTabRow> rows) {
    Map<String, FilterCount> countsByKey = new Map<String, FilterCount>();
    Integer totalCount = rows == null ? 0 : rows.size();
    if (rows != null) {
      for (AccountsTabRow row : rows) {
        String filterKey = canonicalRecordTypeFilterKey(row.recordTypeDeveloperName);
        if (!countsByKey.containsKey(filterKey)) {
          FilterCount entry = new FilterCount();
          entry.label = canonicalRecordTypeFilterLabel(filterKey);
          entry.value = filterKey;
          entry.count = 0;
          countsByKey.put(filterKey, entry);
        }
        countsByKey.get(filterKey).count++;
      }
    }

    List<FilterCount> counts = new List<FilterCount>();
    FilterCount allEntry = new FilterCount();
    allEntry.label = 'All';
    allEntry.value = FILTER_ALL;
    allEntry.count = totalCount;
    counts.add(allEntry);

    for (String key : new List<String>{
      RECORD_TYPE_HCO,
      RECORD_TYPE_HCP,
      RECORD_TYPE_PHARMACY
    }) {
      if (countsByKey.containsKey(key)) {
        counts.add(countsByKey.get(key));
      }
    }
    return counts;
  }

  private static String canonicalRecordTypeFilterKey(String developerName) {
    if (RECORD_TYPE_HCO.equals(developerName)) {
      return RECORD_TYPE_HCO;
    }
    if (RECORD_TYPE_PHARMACY.equals(developerName)) {
      return RECORD_TYPE_PHARMACY;
    }
    if (HCP_RECORD_TYPES.contains(developerName)) {
      return RECORD_TYPE_HCP;
    }
    return String.isBlank(developerName) ? 'Unknown' : developerName;
  }

  private static String canonicalRecordTypeFilterLabel(String filterKey) {
    if (RECORD_TYPE_HCO.equals(filterKey)) {
      return 'Institution (HCO)';
    }
    if (RECORD_TYPE_HCP.equals(filterKey)) {
      return 'Medical Professional (HCP)';
    }
    if (RECORD_TYPE_PHARMACY.equals(filterKey)) {
      return 'Pharmacies';
    }
    return filterKey;
  }

  private static Map<Id, DateTime> loadLastVisitDates(Set<Id> accountIds, Id userId) {
    Map<Id, DateTime> result = new Map<Id, DateTime>();
    if (accountIds == null || accountIds.isEmpty()) {
      return result;
    }
    for (AggregateResult agg : [
      SELECT Account__c accountId, MAX(Start_Date__c) lastVisit
      FROM Visit__c
      WHERE
        Account__c IN :accountIds
        AND Assigned_To__c = :userId
        AND Status__c = 'Completed'
      WITH USER_MODE
      GROUP BY Account__c
    ]) {
      result.put((Id) agg.get('accountId'), (DateTime) agg.get('lastVisit'));
    }
    return result;
  }

  private static Map<Id, DateTime> loadNextVisitDates(
    Set<Id> accountIds,
    Id userId,
    Date monthEnd
  ) {
    Map<Id, DateTime> result = new Map<Id, DateTime>();
    if (accountIds == null || accountIds.isEmpty()) {
      return result;
    }
    DateTime rangeStart = DateTime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
    DateTime rangeEnd = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
    for (AggregateResult agg : [
      SELECT Account__c accountId, MIN(Start_Date__c) nextVisit
      FROM Visit__c
      WHERE
        Account__c IN :accountIds
        AND Assigned_To__c = :userId
        AND Start_Date__c >= :rangeStart
        AND Start_Date__c <= :rangeEnd
        AND Status__c IN ('Draft', 'Scheduled', 'Rescheduled')
      WITH USER_MODE
      GROUP BY Account__c
    ]) {
      result.put((Id) agg.get('accountId'), (DateTime) agg.get('nextVisit'));
    }
    return result;
  }

  private static String buildAddressLine(String street, String city) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(street)) {
      parts.add(street.trim());
    }
    if (String.isNotBlank(city)) {
      parts.add(city.trim());
    }
    return String.join(parts, ', ');
  }

  private static String normalizeScope(String scope) {
    if (String.isBlank(scope)) {
      return SCOPE_BOTH;
    }
    String normalized = scope.toLowerCase();
    if (normalized == SCOPE_IN || normalized == SCOPE_OUT || normalized == SCOPE_BOTH) {
      return normalized;
    }
    return SCOPE_BOTH;
  }

  private static Set<String> resolveRecordTypeFilter(String recordTypeDeveloperName) {
    if (String.isBlank(recordTypeDeveloperName) || FILTER_ALL.equals(recordTypeDeveloperName)) {
      return PLANNER_ACCOUNT_RECORD_TYPES;
    }
    if (
      RECORD_TYPE_HCP.equals(recordTypeDeveloperName) ||
      HCP_RECORD_TYPES.contains(recordTypeDeveloperName)
    ) {
      return HCP_RECORD_TYPES;
    }
    if (RECORD_TYPE_HCO.equals(recordTypeDeveloperName)) {
      return new Set<String>{ RECORD_TYPE_HCO };
    }
    if (RECORD_TYPE_PHARMACY.equals(recordTypeDeveloperName)) {
      return new Set<String>{ RECORD_TYPE_PHARMACY };
    }
    if (PLANNER_ACCOUNT_RECORD_TYPES.contains(recordTypeDeveloperName)) {
      return new Set<String>{ recordTypeDeveloperName };
    }
    return PLANNER_ACCOUNT_RECORD_TYPES;
  }

  private static String resolveClassificationFilter(String classification) {
    if (String.isBlank(classification) || FILTER_ALL.equals(classification)) {
      return null;
    }
    return classification;
  }

  private static Set<Id> resolveAccountIdsFilter(List<String> rawAccountIds) {
    if (rawAccountIds == null || rawAccountIds.isEmpty()) {
      return null;
    }
    Set<Id> accountIds = new Set<Id>();
    for (String rawAccountId : rawAccountIds) {
      if (String.isBlank(rawAccountId)) {
        continue;
      }
      try {
        accountIds.add((Id) rawAccountId.trim());
      } catch (Exception ex) {
        continue;
      }
    }
    return accountIds.isEmpty() ? null : accountIds;
  }

  private static Boolean matchesRecordType(String developerName, Set<String> recordTypes) {
    return developerName != null && recordTypes.contains(developerName);
  }

  private static Boolean matchesClassification(
    Account_Territory_Fields__c atf,
    String classification
  ) {
    if (classification.length() == 1) {
      return classification.equalsIgnoreCase(resolvePotentiality(atf));
    }
    return classification.equalsIgnoreCase(atf.Matrix_Rating__c);
  }

  private static Boolean matchesSearch(
    Account account,
    Account_Territory_Fields__c atf,
    String rawTerm
  ) {
    List<String> tokens = tokenizeSearch(rawTerm);
    if (tokens.isEmpty()) {
      return true;
    }
    String haystack = buildSearchHaystack(account, atf);
    String foldedHaystack = AccountCognitiveSearch.foldName(haystack);
    for (String token : tokens) {
      if (!AccountCognitiveSearch.tokenMatchesHaystack(haystack, foldedHaystack, token)) {
        return false;
      }
    }
    return true;
  }

  private static List<String> tokenizeSearch(String rawTerm) {
    return AccountCognitiveSearch.tokenize(rawTerm);
  }

  private static String buildSearchHaystack(
    Account account,
    Account_Territory_Fields__c atf
  ) {
    List<String> parts = new List<String>();
    if (account.Name != null) {
      parts.add(account.Name.toLowerCase());
    }
    if (account.Brick__r != null) {
      if (account.Brick__r.Name != null) {
        parts.add(account.Brick__r.Name.toLowerCase());
      }
      if (account.Brick__r.Brick_Code__c != null) {
        parts.add(account.Brick__r.Brick_Code__c.toLowerCase());
      }
    }
    if (account.BillingCity != null) {
      parts.add(account.BillingCity.toLowerCase());
    }
    if (account.BillingStreet != null) {
      parts.add(account.BillingStreet.toLowerCase());
    }
    if (account.Specialty_1__c != null) {
      parts.addAll(MedicalSpecialtyPicklist.getSearchTokens(account.Specialty_1__c));
    }
    if (account.RecordType?.Name != null) {
      parts.add(account.RecordType.Name.toLowerCase());
    }
    if (account.RecordType?.DeveloperName != null) {
      parts.add(account.RecordType.DeveloperName.toLowerCase());
    }
    if (atf != null) {
      if (atf.Classification__c != null) {
        parts.add(atf.Classification__c.toLowerCase());
      }
      if (atf.Matrix_Rating__c != null) {
        parts.add(atf.Matrix_Rating__c.toLowerCase());
      }
      if (atf.Potential__c != null) {
        parts.add(atf.Potential__c.toLowerCase());
      }
    }
    return String.join(parts, ' ');
  }

  private static String resolvePotentiality(Account_Territory_Fields__c atf) {
    if (String.isNotBlank(atf.Classification__c)) {
      return atf.Classification__c;
    }
    if (String.isNotBlank(atf.Potential__c)) {
      return atf.Potential__c;
    }
    return 'Not Rated';
  }

  private static Integer classificationRank(String classification) {
    if (classification == 'A') {
      return 3;
    }
    if (classification == 'B') {
      return 2;
    }
    if (classification == 'C') {
      return 1;
    }
    return 0;
  }

  private static String resolvePinKind(String recordTypeDeveloperName, String recordTypeName) {
    Set<String> hcpTypes = new Set<String>{
      'SDO_PersonAccounts',
      'Medical_Professional_HCP',
      'PersonAccount',
      'Business_Contact'
    };
    Set<String> hcoTypes = new Set<String>{ 'Institution_HCO', 'Pharmacy' };
    if (hcpTypes.contains(recordTypeDeveloperName)) {
      return 'hcp';
    }
    if (hcoTypes.contains(recordTypeDeveloperName)) {
      return 'hco';
    }
    String label = (recordTypeName == null ? '' : recordTypeName).toLowerCase();
    if (
      label.contains('hcp') ||
      label.contains('professional') ||
      label.contains('person')
    ) {
      return 'hcp';
    }
    if (
      label.contains('hco') ||
      label.contains('institution') ||
      label.contains('pharmacy')
    ) {
      return 'hco';
    }
    return 'hcp';
  }

    private static Set<Id> getUserTerritoryIds(Id userId) {
        return TerritoryContextService.getEffectiveTerritoryIds(userId);
    }

  private static Set<Id> expandTerritoryHierarchy(Set<Id> rootTerritoryIds) {
    Set<Id> expanded = new Set<Id>();
    if (rootTerritoryIds == null || rootTerritoryIds.isEmpty()) {
      return expanded;
    }
    expanded.addAll(rootTerritoryIds);
    List<Id> frontier = new List<Id>(rootTerritoryIds);
    while (!frontier.isEmpty()) {
      List<Id> nextFrontier = new List<Id>();
      for (Territory2 child : [
        SELECT Id
        FROM Territory2
        WHERE ParentTerritory2Id IN :frontier
        WITH SYSTEM_MODE
      ]) {
        if (!expanded.contains(child.Id)) {
          expanded.add(child.Id);
          nextFrontier.add(child.Id);
        }
      }
      frontier = nextFrontier;
    }
    return expanded;
  }

  private static String paceStatusFromProjected(Decimal projectedPercent) {
    if (projectedPercent >= 100) {
      return 'ahead';
    }
    if (projectedPercent >= ON_TRACK_THRESHOLD) {
      return 'on_track';
    }
    if (projectedPercent >= CRITICAL_THRESHOLD) {
      return 'behind';
    }
    return 'critical';
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private static Decimal toDisplayPercent(Decimal percentFieldValue) {
    if (percentFieldValue == null) {
      return null;
    }
    if (percentFieldValue > 100) {
      return percentFieldValue / 100;
    }
    if (percentFieldValue <= 1) {
      return percentFieldValue * 100;
    }
    return percentFieldValue;
  }

  private class WorkingDaysSummary {
    public Integer elapsedWorkingDays = 0;
    public Integer totalWorkingDays = 0;
    public Decimal paceRatio = 0;
  }

  private static WorkingDaysSummary computeWorkingDays(Id timeCardId, Date asOfDate) {
    WorkingDaysSummary summary = new WorkingDaysSummary();
    for (Employee_Time_Card_Day_Entry__c entry : [
      SELECT Date__c, Calendar_Working_Days__c
      FROM Employee_Time_Card_Day_Entry__c
      WHERE Employee_Time_Card__c = :timeCardId
      WITH USER_MODE
      ORDER BY Date__c ASC
    ]) {
      Integer calDays = nvl(entry.Calendar_Working_Days__c).intValue();
      summary.totalWorkingDays += calDays;
      if (entry.Date__c != null && entry.Date__c <= asOfDate) {
        summary.elapsedWorkingDays += calDays;
      }
    }
    if (summary.totalWorkingDays > 0) {
      summary.paceRatio =
        Decimal.valueOf(summary.elapsedWorkingDays) /
        Decimal.valueOf(summary.totalWorkingDays);
    }
    return summary;
  }

  private class NameComparator implements System.Comparator<AccountsTabRow> {
    private Boolean ascending;

    NameComparator(Boolean ascending) {
      this.ascending = ascending == true;
    }

    public Integer compare(AccountsTabRow a, AccountsTabRow b) {
      String nameA = a.accountName == null ? '' : a.accountName;
      String nameB = b.accountName == null ? '' : b.accountName;
      Integer result = nameA.compareTo(nameB);
      return ascending ? result : -result;
    }
  }

  private class ClassificationComparator implements System.Comparator<AccountsTabRow> {
    private Boolean ascending;

    ClassificationComparator(Boolean ascending) {
      this.ascending = ascending == true;
    }

    public Integer compare(AccountsTabRow a, AccountsTabRow b) {
      Integer rankA = a.classificationRank == null ? 0 : a.classificationRank;
      Integer rankB = b.classificationRank == null ? 0 : b.classificationRank;
      if (rankA == rankB) {
        String nameA = a.accountName == null ? '' : a.accountName;
        String nameB = b.accountName == null ? '' : b.accountName;
        return nameA.compareTo(nameB);
      }
      return ascending ? rankA - rankB : rankB - rankA;
    }
  }

  private class AgentforceScoreComparator implements System.Comparator<AccountsTabRow> {
    private Boolean ascending;

    AgentforceScoreComparator(Boolean ascending) {
      this.ascending = ascending == true;
    }

    public Integer compare(AccountsTabRow a, AccountsTabRow b) {
      Decimal scoreA = a.agentforceScore == null ? 0 : a.agentforceScore;
      Decimal scoreB = b.agentforceScore == null ? 0 : b.agentforceScore;
      if (scoreA == scoreB) {
        String nameA = a.accountName == null ? '' : a.accountName;
        String nameB = b.accountName == null ? '' : b.accountName;
        return nameA.compareTo(nameB);
      }
      if (scoreA > scoreB) {
        return ascending ? 1 : -1;
      }
      return ascending ? -1 : 1;
    }
  }

  private class HealthComparator implements System.Comparator<AccountsTabRow> {
    private Boolean ascending;
    HealthComparator(Boolean ascending) { this.ascending = ascending == true; }
    public Integer compare(AccountsTabRow a, AccountsTabRow b) {
      Decimal scoreA = a.healthScore == null ? -1 : a.healthScore;
      Decimal scoreB = b.healthScore == null ? -1 : b.healthScore;
      if (scoreA == scoreB) {
        return (a.accountName == null ? '' : a.accountName).compareTo(b.accountName == null ? '' : b.accountName);
      }
      return ascending ? (scoreA > scoreB ? 1 : -1) : (scoreA > scoreB ? -1 : 1);
    }
  }

  private class GapComparator implements System.Comparator<AccountsTabRow> {
    private Boolean ascending;
    GapComparator(Boolean ascending) { this.ascending = ascending == true; }
    public Integer compare(AccountsTabRow a, AccountsTabRow b) {
      Decimal gapA = a.visitGap == null ? -1 : a.visitGap;
      Decimal gapB = b.visitGap == null ? -1 : b.visitGap;
      if (gapA == gapB) {
        return (a.accountName == null ? '' : a.accountName).compareTo(b.accountName == null ? '' : b.accountName);
      }
      return ascending ? (gapA > gapB ? 1 : -1) : (gapA > gapB ? -1 : 1);
    }
  }

  private class VisitsComparator implements System.Comparator<AccountsTabRow> {
    private Boolean ascending;
    VisitsComparator(Boolean ascending) { this.ascending = ascending == true; }
    public Integer compare(AccountsTabRow a, AccountsTabRow b) {
      Decimal visitsA = a.actualVisits == null ? 0 : a.actualVisits;
      Decimal visitsB = b.actualVisits == null ? 0 : b.actualVisits;
      if (visitsA == visitsB) {
        return (a.accountName == null ? '' : a.accountName).compareTo(b.accountName == null ? '' : b.accountName);
      }
      return ascending ? (visitsA > visitsB ? 1 : -1) : (visitsA > visitsB ? -1 : 1);
    }
  }

  private class LastVisitComparator implements System.Comparator<AccountsTabRow> {
    private Boolean ascending;
    LastVisitComparator(Boolean ascending) { this.ascending = ascending == true; }
    public Integer compare(AccountsTabRow a, AccountsTabRow b) {
      Long timeA = a.lastVisitDate == null ? 0 : a.lastVisitDate.getTime();
      Long timeB = b.lastVisitDate == null ? 0 : b.lastVisitDate.getTime();
      if (timeA == timeB) {
        return (a.accountName == null ? '' : a.accountName).compareTo(b.accountName == null ? '' : b.accountName);
      }
      return ascending ? (timeA > timeB ? 1 : -1) : (timeA > timeB ? -1 : 1);
    }
  }
}
