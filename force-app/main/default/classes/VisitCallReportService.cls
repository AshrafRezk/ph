public with sharing class VisitCallReportService {

  private static final Integer ATTENDEE_PAGE_SIZE = 25;
  private static final Set<String> HCP_RECORD_TYPES = new Set<String>{
    'SDO_PersonAccounts',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact'
  };

  private static Boolean productImageUrlReadable;
  private static Boolean visitDetailSchemaReadyCached;
  private static Boolean visitDetailSchemaReadyValue;
  private static Boolean visitMessageSchemaReadyCached;
  private static Boolean visitMessageSchemaReadyValue;
  private static Boolean visitSampleSchemaReadyCached;
  private static Boolean visitSampleSchemaReadyValue;
  private static Boolean sampleInventorySchemaReadyCached;
  private static Boolean sampleInventorySchemaReadyValue;

  public class TerritoryProductOption {
    @AuraEnabled public Id productId;
    @AuraEnabled public String productName;
    @AuraEnabled public String imageUrl;
    @AuraEnabled public String productType;
    @AuraEnabled public Id parentProductId;
    @AuraEnabled public String brandName;
    @AuraEnabled public String strength;
    @AuraEnabled public String form;
    @AuraEnabled public String adoption;
    @AuraEnabled public String loyalty;
    @AuraEnabled public String productMatrixRating;
    @AuraEnabled public String targetVisitFrequency;
    @AuraEnabled public Decimal rxPerWeek;
  }

  public class AttendeeCandidate {
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public String specialty;
    @AuraEnabled public String recordTypeDeveloperName;
    @AuraEnabled public String accountTypeLabel;
    @AuraEnabled public String source;
  }

  public class AttendeeRow {
    @AuraEnabled public Id id;
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public String specialty;
    @AuraEnabled public String recordTypeDeveloperName;
    @AuraEnabled public String accountTypeLabel;
    @AuraEnabled public String role;
    @AuraEnabled public Boolean isPrimary;
    @AuraEnabled public Integer displayOrder;
  }

  public class ProductMessageRow {
    @AuraEnabled public Id id;
    @AuraEnabled public String topic;
    @AuraEnabled public String sentiment;
    @AuraEnabled public String response;
  }

  public class ProductDetailRow {
    @AuraEnabled public Id id;
    @AuraEnabled public Id productId;
    @AuraEnabled public String productName;
    @AuraEnabled public String imageUrl;
    @AuraEnabled public String productType;
    @AuraEnabled public Id parentProductId;
    @AuraEnabled public String brandName;
    @AuraEnabled public String strength;
    @AuraEnabled public String form;
    @AuraEnabled public Integer displayOrder;
    @AuraEnabled public String detailType;
    @AuraEnabled public String notes;
    @AuraEnabled public List<ProductMessageRow> messages;
  }

  public class SampleRow {
    @AuraEnabled public Id id;
    @AuraEnabled public Id productId;
    @AuraEnabled public String productName;
    @AuraEnabled public String imageUrl;
    @AuraEnabled public Id visitAttendeeId;
    @AuraEnabled public String attendeeName;
    @AuraEnabled public Decimal quantity;
    @AuraEnabled public String lotNumber;
    @AuraEnabled public Id sampleInventoryId;
    @AuraEnabled public Decimal inventoryOnHand;
    @AuraEnabled public Date inventoryExpiry;
  }

  public class SampleInventoryOption {
    @AuraEnabled public Id id;
    @AuraEnabled public Id productId;
    @AuraEnabled public String productName;
    @AuraEnabled public String imageUrl;
    @AuraEnabled public String lotNumber;
    @AuraEnabled public Decimal quantityOnHand;
    @AuraEnabled public Date expiryDate;
  }

  public class ClmSessionRow {
    @AuraEnabled public Id id;
    @AuraEnabled public Id presentationId;
    @AuraEnabled public String presentationName;
    @AuraEnabled public String status;
    @AuraEnabled public DateTime startedAt;
    @AuraEnabled public DateTime endedAt;
    @AuraEnabled public Integer slidesPresentedCount;
    @AuraEnabled public Integer totalDurationSeconds;
  }

  public class TeamMemberOption {
    @AuraEnabled public Id userId;
    @AuraEnabled public String name;
    @AuraEnabled public String role;
    @AuraEnabled public String territoryName;
    @AuraEnabled public Boolean isManager;
    @AuraEnabled public Boolean isDefault;
  }

  public class VisitHeader {
    @AuraEnabled public Id id;
    @AuraEnabled public Id visitId;
    @AuraEnabled public String name;
    @AuraEnabled public String status;
    @AuraEnabled public String visitType;
    @AuraEnabled public DateTime startDateTime;
    @AuraEnabled public DateTime endDateTime;
    // Visit calendar day (yyyy-MM-dd) and zone id in the running user's time zone,
    // so clients can build start/end from the locked date plus edited times.
    @AuraEnabled public String visitDateLocal;
    @AuraEnabled public String userTimeZone;
    @AuraEnabled public String durationLabel;
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public String accountRecordTypeName;
    @AuraEnabled public String accountRecordTypeDeveloperName;
    @AuraEnabled public String accountSpecialty;
    @AuraEnabled public String accountCity;
    @AuraEnabled public Id assignedToId;
    @AuraEnabled public String assignedToName;
    @AuraEnabled public String visitObjective;
    @AuraEnabled public String visitNotes;
    @AuraEnabled public String clmPresentation;
    @AuraEnabled public Date nextVisitDate;
    @AuraEnabled public String cancellationReason;
    @AuraEnabled public Boolean isLocked;
    @AuraEnabled public Boolean canEditSchedule;
    @AuraEnabled public Boolean canViewServiceRequests;
    @AuraEnabled public Boolean isDoubleVisit;
    @AuraEnabled public Id doubleVisitWithId;
    @AuraEnabled public String doubleVisitWithName;
    @AuraEnabled public Id defaultDoubleVisitWithId;
    @AuraEnabled public String defaultDoubleVisitWithName;
    @AuraEnabled public Id coachingEventId;
  }

  public class CallReportPayload {
    @AuraEnabled public VisitHeader visit;
    @AuraEnabled public List<AttendeeRow> attendees;
    @AuraEnabled public List<ProductDetailRow> products;
    @AuraEnabled public List<SampleRow> samples;
    @AuraEnabled public List<ClmSessionRow> clmSessions;
    @AuraEnabled public List<TeamMemberOption> teamMembers;
    @AuraEnabled public Boolean legacyMigrated;
    @AuraEnabled public Boolean alignedOnRepTerritory;
    @AuraEnabled public Boolean hasSubordinateTerritories;
    @AuraEnabled public List<String> tabKeys;
  }

  public class SaveRequest {
    @AuraEnabled public Id visitId;
    @AuraEnabled public DateTime startDateTime;
    @AuraEnabled public DateTime endDateTime;
    // When the rep captured this report on the device (offline saves sync later).
    @AuraEnabled public DateTime capturedAt;
    @AuraEnabled public String status;
    @AuraEnabled public String visitObjective;
    @AuraEnabled public String visitNotes;
    @AuraEnabled public String clmPresentation;
    @AuraEnabled public Date nextVisitDate;
    @AuraEnabled public String cancellationReason;
    @AuraEnabled public Boolean isDoubleVisit;
    @AuraEnabled public Id doubleVisitWithId;
    @AuraEnabled public List<AttendeeRow> attendees;
    @AuraEnabled public List<ProductDetailRow> products;
    @AuraEnabled public List<SampleRow> samples;
    @AuraEnabled public List<ClmSessionRow> clmSessions;
  }

  public static CallReportPayload getCallReportPayload(Id visitId) {
    if (visitId == null) {
      throw RestSafeError.make('Visit Id is required.');
    }

    Visit__c visit = queryVisit(visitId);
    VisitDoubleVisitService.Context teamContext = VisitDoubleVisitService.resolve(visit);
    CallReportPayload payload = new CallReportPayload();
    payload.visit = mapVisitHeader(visit, teamContext);
    payload.attendees = queryAttendees(visitId);
    payload.products = queryProductDetails(visitId);
    payload.samples = querySamples(visitId);
    payload.clmSessions = queryClmSessions(visitId);
    payload.teamMembers = teamContext.members;
    payload.legacyMigrated = false;
    payload.hasSubordinateTerritories = TerritoryContextService.hasSubordinateTerritories(UserInfo.getUserId());
    payload.alignedOnRepTerritory = payload.hasSubordinateTerritories == true
      ? false
      : TerritoryContextService.isAlignedOnRepTerritory();

    if (payload.attendees.isEmpty() && visit.Account__c != null) {
      payload.attendees.add(buildPrimaryAttendeeFromVisit(visit));
    }

    if (payload.products.isEmpty() && String.isNotBlank(visit.Products_Discussed__c)) {
      payload.products = migrateLegacyProducts(visit);
      payload.legacyMigrated = !payload.products.isEmpty();
    }

    payload.tabKeys = VisitTabConfigService.tabsFor(
      payload.visit == null ? null : payload.visit.accountRecordTypeDeveloperName,
      payload.visit == null ? null : payload.visit.accountRecordTypeName
    );

    return payload;
  }

  public static List<TerritoryProductOption> getTerritoryProducts(Id visitId) {
    Visit__c visit = queryVisit(visitId);
    Set<Id> territoryIds = expandTerritoryHierarchy(getUserTerritoryIds());
    Set<Id> ptaProductIds = getPtaProductIds(territoryIds);
    Set<Id> scopedIds = intersectWithAtpf(visit.Account__c, territoryIds, ptaProductIds);

    if (scopedIds.isEmpty() && !ptaProductIds.isEmpty()) {
      scopedIds = ptaProductIds;
    }
    if (scopedIds.isEmpty()) {
      return new List<TerritoryProductOption>();
    }

    scopedIds.addAll(expandDispenseRelatedProductIds(scopedIds));

    Map<Id, Account_Territory_Product_Fields__c> atpfByProduct = getAtpfByProduct(
      visit.Account__c,
      territoryIds,
      scopedIds
    );

    List<TerritoryProductOption> options = new List<TerritoryProductOption>();
    for (Product2 product : queryProductsByIds(scopedIds)) {
      TerritoryProductOption option = mapTerritoryProductOption(product);
      if (atpfByProduct.containsKey(product.Id)) {
        Account_Territory_Product_Fields__c atpf = atpfByProduct.get(product.Id);
        option.adoption = atpf.Adoption__c;
        option.loyalty = atpf.Loyalty__c;
        option.productMatrixRating = atpf.Product_Matrix_Rating__c;
        option.targetVisitFrequency = atpf.Target_Visit_Frequency__c;
        option.rxPerWeek = atpf.Rx_Per_Week__c;
      }
      options.add(option);
    }
    return options;
  }

  private static List<Account_Affiliation__c> queryAffiliationsForAccount(Id accountId) {
    Boolean filterValidated = Schema.SObjectType.Account_Affiliation__c.fields.getMap()
      .containsKey('validation_status__c');
    String validated = filterValidated ? ' AND Validation_Status__c = \'Validated\'' : '';
    String base =
      'SELECT Primary_Account__c, Related_Account__c FROM Account_Affiliation__c ' +
      'WHERE Is_Active__c = TRUE AND Outside_Territory__c = FALSE' +
      validated;
    List<Account_Affiliation__c> rows = new List<Account_Affiliation__c>();
    try {
      rows.addAll(
        (List<Account_Affiliation__c>) Database.query(
          base + ' AND Primary_Account__c = :accountId LIMIT 200'
        )
      );
      rows.addAll(
        (List<Account_Affiliation__c>) Database.query(
          base + ' AND Related_Account__c = :accountId LIMIT 200'
        )
      );
    } catch (QueryException ex) {
      if (filterValidated) {
        return queryAffiliationsWithoutValidation(accountId);
      }
      throw ex;
    }
    return rows;
  }

  private static List<Account_Affiliation__c> queryAffiliationsWithoutValidation(Id accountId) {
    List<Account_Affiliation__c> rows = new List<Account_Affiliation__c>();
    rows.addAll([
      SELECT Primary_Account__c, Related_Account__c
      FROM Account_Affiliation__c
      WHERE Primary_Account__c = :accountId
        AND Is_Active__c = TRUE
        AND Outside_Territory__c = FALSE
      LIMIT 200
    ]);
    rows.addAll([
      SELECT Primary_Account__c, Related_Account__c
      FROM Account_Affiliation__c
      WHERE Related_Account__c = :accountId
        AND Is_Active__c = TRUE
        AND Outside_Territory__c = FALSE
      LIMIT 200
    ]);
    return rows;
  }

  public static List<AttendeeCandidate> searchAttendeeCandidates(
    Id visitId,
    String searchTerm,
    Integer offset
  ) {
    Visit__c visit = queryVisit(visitId);
    Integer resolvedOffset = offset == null || offset < 0 ? 0 : offset;
    Set<Id> existingAccountIds = getExistingAttendeeAccountIds(visitId);
    Set<Id> candidateIds = new Set<Id>();
    List<AttendeeCandidate> results = new List<AttendeeCandidate>();

    Id accountId = visit.Account__c;
    if (accountId != null) {
      List<Account_Affiliation__c> affiliations = queryAffiliationsForAccount(accountId);
      for (Account_Affiliation__c aff : affiliations) {
        Id relatedId = aff.Primary_Account__c == accountId
          ? aff.Related_Account__c
          : aff.Primary_Account__c;
        if (relatedId != null) {
          candidateIds.add(relatedId);
        }
      }
    }

    Set<Id> territoryAccountIds = getTerritoryAccountIds();
    String term = String.isBlank(searchTerm) ? null : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';

    // Prefer territory accounts; when the user has no territory memberships,
    // fall back to affiliation candidates so the picker is not empty.
    Set<Id> searchScope = !territoryAccountIds.isEmpty()
      ? territoryAccountIds
      : candidateIds;

    List<Account> accounts;
    if (term != null) {
      if (searchScope.isEmpty()) {
        accounts = new List<Account>();
      } else {
        accounts = [
          SELECT Id, Name, Specialty_1__c, RecordType.DeveloperName, RecordType.Name
          FROM Account
          WHERE
            Id IN :searchScope
            AND Name LIKE :term
          WITH USER_MODE
          ORDER BY Name ASC
          LIMIT :ATTENDEE_PAGE_SIZE
          OFFSET :resolvedOffset
        ];
      }
    } else if (!candidateIds.isEmpty()) {
      accounts = [
        SELECT Id, Name, Specialty_1__c, RecordType.DeveloperName, RecordType.Name
        FROM Account
        WHERE Id IN :candidateIds
        WITH USER_MODE
        ORDER BY Name ASC
        LIMIT :ATTENDEE_PAGE_SIZE
        OFFSET :resolvedOffset
      ];
    } else if (!territoryAccountIds.isEmpty()) {
      accounts = [
        SELECT Id, Name, Specialty_1__c, RecordType.DeveloperName, RecordType.Name
        FROM Account
        WHERE Id IN :territoryAccountIds
        WITH USER_MODE
        ORDER BY Name ASC
        LIMIT :ATTENDEE_PAGE_SIZE
        OFFSET :resolvedOffset
      ];
    } else {
      accounts = new List<Account>();
    }

    for (Account account : accounts) {
      if (existingAccountIds.contains(account.Id)) {
        continue;
      }
      AttendeeCandidate candidate = mapAttendeeCandidate(account, term == null ? 'Affiliation' : 'Search');
      results.add(candidate);
    }
    return results;
  }

  public static List<SampleInventoryOption> getSampleInventoryForUser() {
    List<SampleInventoryOption> options = new List<SampleInventoryOption>();
    if (!sampleInventorySchemaReady()) {
      return options;
    }
    Id userId = UserInfo.getUserId();
    String productImageSelect = isProductImageUrlReadable()
      ? ', Product2__r.Product_Image_URL__c'
      : '';
    String inventoryFields = 'Lot_Number__c, Quantity_On_Hand__c';
    if (hasObjectField(Sample_Inventory__c.SObjectType, 'Expiry_Date__c')) {
      inventoryFields += ', Expiry_Date__c';
    }
    String typeFilter = hasObjectField(Product2.SObjectType, 'Product_Type__c')
      ? ' AND Product2__r.Product_Type__c IN (\'Sample\', \'Brand Reminder\') '
      : ' ';
    for (Sample_Inventory__c inv : Database.query(
      'SELECT Id, Product2__c, Product2__r.Name' +
      productImageSelect +
      ', ' + inventoryFields + ' ' +
      'FROM Sample_Inventory__c ' +
      'WHERE Owner_User__c = :userId AND Quantity_On_Hand__c > 0' +
      typeFilter +
      'WITH USER_MODE ORDER BY Product2__r.Name ASC, Lot_Number__c ASC'
    )) {
      SampleInventoryOption option = new SampleInventoryOption();
      option.id = inv.Id;
      option.productId = inv.Product2__c;
      option.productName = inv.Product2__r != null ? inv.Product2__r.Name : null;
      option.imageUrl = inv.Product2__r != null
        ? getProductImageUrl(inv.Product2__r)
        : null;
      option.lotNumber = inv.Lot_Number__c;
      option.quantityOnHand = inv.Quantity_On_Hand__c;
      option.expiryDate = inv.Expiry_Date__c;
      options.add(option);
    }
    return options;
  }

  public static List<ClmSessionRow> getClmPresentationsForVisit(Id visitId) {
    return queryClmSessions(visitId);
  }

  public static CallReportPayload saveCallReport(SaveRequest request) {
    if (request == null || request.visitId == null) {
      throw RestSafeError.make('Visit Id is required.');
    }

    Visit__c visit = [
      SELECT
        Id,
        Status__c,
        Start_Date__c,
        End_Date__c,
        Visit_Date__c,
        Account__c,
        Products_Discussed__c,
        Product_Details__c
      FROM Visit__c
      WHERE Id = :request.visitId
      WITH USER_MODE
      LIMIT 1
    ];

    if (visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled') {
      throw RestSafeError.make('Completed or cancelled visits cannot be edited.');
    }

    DateTime effectiveStart = request.startDateTime != null ? request.startDateTime : visit.Start_Date__c;
    DateTime effectiveEnd = request.endDateTime != null ? request.endDateTime : visit.End_Date__c;
    if (scheduleChanged(request, visit)) {
      if (!VisitActorAccess.canEditVisitSchedule()) {
        throw RestSafeError.make('Only SFE and managers can change visit start and end dates.');
      }
      if (effectiveStart == null || effectiveEnd == null) {
        throw RestSafeError.make('Start and end times are required.');
      }
      if (effectiveEnd <= effectiveStart) {
        throw RestSafeError.make('End time must be after start time.');
      }
      assertVisitDateUnchanged(visit, effectiveStart, effectiveEnd);
      visit.Start_Date__c = effectiveStart;
      visit.End_Date__c = effectiveEnd;
      visit.Visit_Date__c = effectiveStart;
    }

    validateSaveRequest(request, effectiveStart);
    if ('Completed' == request.status) {
      VisitStatusHelper.validateCompletionDay(effectiveStart, request.capturedAt);
    }

    visit.Status__c = request.status;
    visit.Visit_Objective__c = request.visitObjective;
    visit.Visit_Notes__c = request.visitNotes;
    visit.CLM_Presentation__c = request.clmPresentation;
    visit.Next_Visit_Date__c = request.nextVisitDate;
    visit.Cancellation_Reason__c = 'Cancelled' == request.status ? request.cancellationReason : null;
    applyDoubleVisitFields(visit, request);

    rollupLegacyProductFields(visit, request.products);
    update as user visit;

    saveAttendees(request.visitId, request.attendees);
    Map<Id, Id> attendeeIdByAccountId = getAttendeeIdByAccountId(request.visitId);
    resolveSampleAttendeeIds(request.samples, attendeeIdByAccountId);
    saveProductDetails(request.visitId, request.products);
    saveSamples(request.visitId, request.samples);

    if ('Completed' == request.status) {
      processSampleDistribution(request.visitId, request.samples);
    }

    return getCallReportPayload(request.visitId);
  }

  /**
   * The visit calendar day is locked on the call report: only the time of day may change.
   * Days are compared in the running user's time zone. Moving a visit to another day
   * happens in the planner (reschedule), which is gated by the Edit_Visit_Date permission.
   */
  private static void assertVisitDateUnchanged(
    Visit__c visit,
    DateTime effectiveStart,
    DateTime effectiveEnd
  ) {
    DateTime originalStart = visit.Start_Date__c != null ? visit.Start_Date__c : visit.Visit_Date__c;
    if (originalStart == null) {
      return;
    }
    Date visitDay = originalStart.date();
    Boolean startMoved = effectiveStart != null && effectiveStart.date() != visitDay;
    Boolean endMoved = effectiveEnd != null && effectiveEnd.date() != visitDay;
    if (startMoved || endMoved) {
      throw RestSafeError.make(
        'The visit date cannot be changed here. Only the start and end times can be edited. ' +
        'Use the planner to move the visit to another day.'
      );
    }
  }

  private static Boolean scheduleChanged(SaveRequest request, Visit__c visit) {
    if (request.startDateTime == null && request.endDateTime == null) {
      return false;
    }
    return request.startDateTime != visit.Start_Date__c || request.endDateTime != visit.End_Date__c;
  }

  private static void validateSaveRequest(SaveRequest request, DateTime visitStartDateTime) {
    VisitStatusHelper.validateStatusChange(
      request.status,
      visitStartDateTime,
      request.cancellationReason
    );
    if ('Completed' == request.status) {
      if (request.attendees == null || request.attendees.isEmpty()) {
        throw RestSafeError.make('Add at least one attendee before completing the visit.');
      }
      if (request.products == null || request.products.isEmpty()) {
        throw RestSafeError.make('Select at least one product before completing the visit.');
      }
      validateSamples(request.samples);
    }
    if (request.isDoubleVisit == true && request.doubleVisitWithId == null) {
      throw RestSafeError.make('Select the team member who joined this double visit.');
    }
  }

  private static void applyDoubleVisitFields(Visit__c visit, SaveRequest request) {
    if (request.isDoubleVisit == null) {
      return;
    }
    visit.Is_Double_Visit__c = request.isDoubleVisit;
    visit.Double_Visit_With__c = request.isDoubleVisit == true ? request.doubleVisitWithId : null;
  }

  private static void validateSamples(List<SampleRow> samples) {
    if (samples == null || samples.isEmpty()) {
      return;
    }
    Set<Id> inventoryIds = new Set<Id>();
    for (SampleRow row : samples) {
      if (row.productId == null) {
        throw RestSafeError.make('Select a product for each dispense line.');
      }
      if (row.quantity == null || row.quantity <= 0) {
        throw RestSafeError.make('Dispense quantity must be greater than zero.');
      }
      if (row.sampleInventoryId != null) {
        inventoryIds.add(row.sampleInventoryId);
      }
    }
    if (inventoryIds.isEmpty()) {
      return;
    }
    Map<Id, Sample_Inventory__c> inventoryById = new Map<Id, Sample_Inventory__c>([
      SELECT Id, Quantity_On_Hand__c, Expiry_Date__c, Lot_Number__c
      FROM Sample_Inventory__c
      WHERE Id IN :inventoryIds
      WITH USER_MODE
    ]);
    Map<Id, Decimal> requestedByInventory = new Map<Id, Decimal>();
    for (SampleRow row : samples) {
      if (row.sampleInventoryId == null) {
        continue;
      }
      Sample_Inventory__c inv = inventoryById.get(row.sampleInventoryId);
      if (inv == null) {
        throw RestSafeError.make('Sample inventory record not found.');
      }
      if (inv.Expiry_Date__c != null && inv.Expiry_Date__c < Date.today()) {
        throw RestSafeError.make('Cannot distribute expired sample lot ' + inv.Lot_Number__c + '.');
      }
      Decimal total = requestedByInventory.containsKey(row.sampleInventoryId)
        ? requestedByInventory.get(row.sampleInventoryId)
        : 0;
      total += row.quantity;
      requestedByInventory.put(row.sampleInventoryId, total);
      if (total > inv.Quantity_On_Hand__c) {
        throw RestSafeError.make('Insufficient sample inventory for lot ' + inv.Lot_Number__c + '.');
      }
    }
  }

  private static void processSampleDistribution(Id visitId, List<SampleRow> samples) {
    if (samples == null || samples.isEmpty()) {
      return;
    }
    Set<Id> inventoryIds = new Set<Id>();
    for (SampleRow row : samples) {
      if (row.sampleInventoryId != null) {
        inventoryIds.add(row.sampleInventoryId);
      }
    }
    if (inventoryIds.isEmpty()) {
      return;
    }

    Map<Id, Sample_Inventory__c> inventoryById = new Map<Id, Sample_Inventory__c>([
      SELECT Id, Quantity_On_Hand__c, Lot_Number__c
      FROM Sample_Inventory__c
      WHERE Id IN :inventoryIds
      WITH USER_MODE
      FOR UPDATE
    ]);

    List<Sample_Transaction__c> transactions = new List<Sample_Transaction__c>();
    for (SampleRow row : samples) {
      if (row.sampleInventoryId == null || row.quantity == null) {
        continue;
      }
      Sample_Inventory__c inv = inventoryById.get(row.sampleInventoryId);
      if (inv == null) {
        continue;
      }
      inv.Quantity_On_Hand__c = inv.Quantity_On_Hand__c - row.quantity;
      transactions.add(new Sample_Transaction__c(
        Visit__c = visitId,
        Sample_Inventory__c = inv.Id,
        Quantity__c = row.quantity,
        Transaction_Type__c = 'Distribute'
      ));
    }
    update as user inventoryById.values();
    insert as system transactions;
  }

  private static void rollupLegacyProductFields(Visit__c visit, List<ProductDetailRow> products) {
    if (products == null || products.isEmpty()) {
      visit.Products_Discussed__c = null;
      visit.Product_Details__c = null;
      return;
    }
    List<String> names = new List<String>();
    List<String> notes = new List<String>();
    for (ProductDetailRow row : products) {
      if (String.isNotBlank(row.productName)) {
        names.add(row.productName);
      }
      if (String.isNotBlank(row.notes)) {
        notes.add(row.productName + ': ' + row.notes);
      }
    }
    visit.Products_Discussed__c = String.join(names, '; ');
    visit.Product_Details__c = notes.isEmpty() ? null : String.join(notes, '\n');
  }

  private static Map<Id, Id> getAttendeeIdByAccountId(Id visitId) {
    Map<Id, Id> result = new Map<Id, Id>();
    for (Visit_Attendee__c attendee : [
      SELECT Id, Account__c
      FROM Visit_Attendee__c
      WHERE Visit__c = :visitId
      WITH USER_MODE
    ]) {
      if (attendee.Account__c != null) {
        result.put(attendee.Account__c, attendee.Id);
      }
    }
    return result;
  }

  private static void resolveSampleAttendeeIds(
    List<SampleRow> samples,
    Map<Id, Id> attendeeIdByAccountId
  ) {
    if (samples == null || attendeeIdByAccountId.isEmpty()) {
      return;
    }
    for (SampleRow row : samples) {
      if (row.visitAttendeeId == null) {
        continue;
      }
      if (attendeeIdByAccountId.containsKey(row.visitAttendeeId)) {
        row.visitAttendeeId = attendeeIdByAccountId.get(row.visitAttendeeId);
      }
    }
  }

  private static void saveAttendees(Id visitId, List<AttendeeRow> rows) {
    Map<Id, Visit_Attendee__c> existing = new Map<Id, Visit_Attendee__c>([
      SELECT Id FROM Visit_Attendee__c WHERE Visit__c = :visitId WITH USER_MODE
    ]);
    Set<Id> keepIds = new Set<Id>();
    List<Visit_Attendee__c> toUpsert = new List<Visit_Attendee__c>();

    if (rows != null) {
      Integer order = 1;
      for (AttendeeRow row : rows) {
        Visit_Attendee__c record = new Visit_Attendee__c();
        if (row.id != null && existing.containsKey(row.id)) {
          record.Id = row.id;
          keepIds.add(row.id);
        } else {
          record.Visit__c = visitId;
        }
        record.Account__c = row.accountId;
        toUpsert.add(record);
        order++;
      }
    }

    List<Visit_Attendee__c> toDelete = new List<Visit_Attendee__c>();
    for (Visit_Attendee__c record : existing.values()) {
      if (!keepIds.contains(record.Id)) {
        toDelete.add(record);
      }
    }
    if (!toDelete.isEmpty()) {
      delete as user toDelete;
    }
    if (!toUpsert.isEmpty()) {
      upsert as user toUpsert;
    }
  }

  private static void saveProductDetails(Id visitId, List<ProductDetailRow> rows) {
    if (!visitDetailSchemaReady()) {
      return;
    }
    Map<Id, Visit_Product_Detail__c> existingDetails = new Map<Id, Visit_Product_Detail__c>([
      SELECT Id FROM Visit_Product_Detail__c WHERE Visit__c = :visitId WITH USER_MODE
    ]);
    Set<Id> keepDetailIds = new Set<Id>();
    List<Visit_Product_Detail__c> detailUpserts = new List<Visit_Product_Detail__c>();

    if (rows != null) {
      Integer order = 1;
      for (ProductDetailRow row : rows) {
        Visit_Product_Detail__c detail = new Visit_Product_Detail__c();
        if (row.id != null && existingDetails.containsKey(row.id)) {
          detail.Id = row.id;
          keepDetailIds.add(row.id);
        } else {
          detail.put('Visit__c', visitId);
        }
        detail.put('Product2__c', row.productId);
        detail.put('Display_Order__c', row.displayOrder != null ? row.displayOrder : order);
        detail.put('Detail_Type__c', String.isBlank(row.detailType) ? 'Detail' : row.detailType);
        detail.put('Notes__c', row.notes);
        detailUpserts.add(detail);
        order++;
      }
    }

    List<Visit_Product_Detail__c> detailsToDelete = new List<Visit_Product_Detail__c>();
    for (Visit_Product_Detail__c detail : existingDetails.values()) {
      if (!keepDetailIds.contains(detail.Id)) {
        detailsToDelete.add(detail);
      }
    }
    if (!detailsToDelete.isEmpty()) {
      delete as user detailsToDelete;
    }
    if (!detailUpserts.isEmpty()) {
      upsert as user detailUpserts;
    }

    if (!visitMessageSchemaReady()) {
      return;
    }

    Map<Integer, Id> detailIdByOrder = new Map<Integer, Id>();
    for (SObject saved : Database.query(buildProductDetailOrderQuery(visitId))) {
      Object orderValue = saved.get('Display_Order__c');
      if (orderValue == null) {
        continue;
      }
      detailIdByOrder.put(Integer.valueOf(String.valueOf(orderValue)), (Id) saved.get('Id'));
    }

    Map<Id, Visit_Product_Message__c> existingMessages = new Map<Id, Visit_Product_Message__c>();
    for (Visit_Product_Message__c msg : [
      SELECT Id, Visit_Product_Detail__c
      FROM Visit_Product_Message__c
      WHERE Visit_Product_Detail__r.Visit__c = :visitId
      WITH USER_MODE
    ]) {
      existingMessages.put(msg.Id, msg);
    }
    Set<Id> keepMessageIds = new Set<Id>();
    List<Visit_Product_Message__c> messageUpserts = new List<Visit_Product_Message__c>();

    if (rows != null) {
      Integer order = 1;
      for (ProductDetailRow row : rows) {
        Id detailId = row.id;
        if (detailId == null && detailIdByOrder.containsKey(order)) {
          detailId = detailIdByOrder.get(order);
        }
        if (detailId == null || row.messages == null) {
          order++;
          continue;
        }
        for (ProductMessageRow msgRow : row.messages) {
          if (String.isBlank(msgRow.topic)) {
            continue;
          }
          Visit_Product_Message__c msg = new Visit_Product_Message__c();
          if (msgRow.id != null && existingMessages.containsKey(msgRow.id)) {
            msg.Id = msgRow.id;
            keepMessageIds.add(msgRow.id);
          } else {
            msg.put('Visit_Product_Detail__c', detailId);
          }
          msg.put('Topic__c', msgRow.topic);
          msg.put('Sentiment__c', String.isBlank(msgRow.sentiment) ? 'Neutral' : msgRow.sentiment);
          msg.put('Response__c', msgRow.response);
          messageUpserts.add(msg);
        }
        order++;
      }
    }

    List<Visit_Product_Message__c> messagesToDelete = new List<Visit_Product_Message__c>();
    for (Visit_Product_Message__c msg : existingMessages.values()) {
      if (!keepMessageIds.contains(msg.Id)) {
        messagesToDelete.add(msg);
      }
    }
    if (!messagesToDelete.isEmpty()) {
      delete as user messagesToDelete;
    }
    if (!messageUpserts.isEmpty()) {
      upsert as user messageUpserts;
    }
  }

  private static void saveSamples(Id visitId, List<SampleRow> rows) {
    if (!visitSampleSchemaReady()) {
      return;
    }
    Map<Id, Visit_Sample__c> existing = new Map<Id, Visit_Sample__c>([
      SELECT Id FROM Visit_Sample__c WHERE Visit__c = :visitId WITH USER_MODE
    ]);
    Set<Id> keepIds = new Set<Id>();
    List<Visit_Sample__c> toUpsert = new List<Visit_Sample__c>();

    if (rows != null) {
      for (SampleRow row : rows) {
        Visit_Sample__c record = new Visit_Sample__c();
        if (row.id != null && existing.containsKey(row.id)) {
          record.Id = row.id;
          keepIds.add(row.id);
        } else {
          record.put('Visit__c', visitId);
        }
        record.put('Product2__c', row.productId);
        record.put('Visit_Attendee__c', row.visitAttendeeId);
        record.put('Quantity__c', row.quantity);
        record.put('Lot_Number__c', row.lotNumber);
        record.put('Sample_Inventory__c', row.sampleInventoryId);
        toUpsert.add(record);
      }
    }

    List<Visit_Sample__c> toDelete = new List<Visit_Sample__c>();
    for (Visit_Sample__c record : existing.values()) {
      if (!keepIds.contains(record.Id)) {
        toDelete.add(record);
      }
    }
    if (!toDelete.isEmpty()) {
      delete as user toDelete;
    }
    if (!toUpsert.isEmpty()) {
      upsert as user toUpsert;
    }
  }

  private static Visit__c queryVisit(Id visitId) {
    List<Visit__c> visits = [
      SELECT
        Id,
        Name,
        Status__c,
        Visit_Type__c,
        Start_Date__c,
        End_Date__c,
        Visit_Date__c,
        Visit_Objective__c,
        Visit_Notes__c,
        Products_Discussed__c,
        Product_Details__c,
        CLM_Presentation__c,
        Next_Visit_Date__c,
        Cancellation_Reason__c,
        Is_Double_Visit__c,
        Double_Visit_With__c,
        Double_Visit_With__r.Name,
        Coaching_Event__c,
        Account__c,
        Account__r.Name,
        Account__r.BillingCity,
        Account__r.Specialty_1__c,
        Account__r.RecordType.Name,
        Account__r.RecordType.DeveloperName,
        Assigned_To__c,
        Assigned_To__r.Name,
        Assigned_To__r.ManagerId,
        Assigned_To__r.Manager.Name
      FROM Visit__c
      WHERE Id = :visitId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visits.isEmpty()) {
      throw RestSafeError.make('Visit not found.');
    }
    return visits[0];
  }

  private static VisitHeader mapVisitHeader(Visit__c visit, VisitDoubleVisitService.Context teamContext) {
    VisitHeader header = new VisitHeader();
    header.id = visit.Id;
    header.visitId = visit.Id;
    header.name = visit.Name;
    header.status = visit.Status__c;
    header.visitType = visit.Visit_Type__c;
    header.startDateTime = visit.Start_Date__c;
    header.endDateTime = visit.End_Date__c;
    DateTime dayAnchor = visit.Start_Date__c != null ? visit.Start_Date__c : visit.Visit_Date__c;
    header.visitDateLocal = dayAnchor == null ? null : dayAnchor.format('yyyy-MM-dd');
    header.userTimeZone = UserInfo.getTimeZone().getID();
    header.durationLabel = formatDurationLabel(visit.Start_Date__c, visit.End_Date__c);
    header.visitObjective = visit.Visit_Objective__c;
    header.visitNotes = visit.Visit_Notes__c;
    header.clmPresentation = visit.CLM_Presentation__c;
    header.nextVisitDate = visit.Next_Visit_Date__c;
    header.cancellationReason = visit.Cancellation_Reason__c;
    header.isLocked = visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled';
    header.canEditSchedule = VisitActorAccess.canEditVisitSchedule();
    header.canViewServiceRequests = VisitActorAccess.canViewServiceRequests();
    header.isDoubleVisit = visit.Is_Double_Visit__c == true;
    header.doubleVisitWithId = visit.Double_Visit_With__c;
    header.doubleVisitWithName = visit.Double_Visit_With__r != null
      ? visit.Double_Visit_With__r.Name
      : null;
    header.defaultDoubleVisitWithId = teamContext != null ? teamContext.defaultUserId : null;
    header.defaultDoubleVisitWithName = teamContext != null ? teamContext.defaultUserName : null;
    header.coachingEventId = visit.Coaching_Event__c;
    header.accountId = visit.Account__c;
    if (visit.Account__r != null) {
      header.accountName = visit.Account__r.Name;
      header.accountCity = visit.Account__r.BillingCity;
      header.accountSpecialty = MedicalSpecialtyPicklist.getLabel(
        visit.Account__r.Specialty_1__c
      );
      header.accountRecordTypeName = visit.Account__r.RecordType != null
        ? visit.Account__r.RecordType.Name
        : null;
      header.accountRecordTypeDeveloperName = visit.Account__r.RecordType != null
        ? visit.Account__r.RecordType.DeveloperName
        : null;
    }
    header.assignedToId = visit.Assigned_To__c;
    header.assignedToName = visit.Assigned_To__r != null ? visit.Assigned_To__r.Name : null;
    return header;
  }

  private static List<AttendeeRow> queryAttendees(Id visitId) {
    List<AttendeeRow> rows = new List<AttendeeRow>();
    Integer order = 0;
    for (Visit_Attendee__c record : [
      SELECT
        Id,
        Account__c,
        Account__r.Name,
        Account__r.Specialty_1__c,
        Account__r.RecordType.DeveloperName
      FROM Visit_Attendee__c
      WHERE Visit__c = :visitId
      WITH USER_MODE
      ORDER BY CreatedDate ASC
    ]) {
      order++;
      AttendeeRow row = new AttendeeRow();
      row.id = record.Id;
      row.accountId = record.Account__c;
      row.accountName = record.Account__r != null ? record.Account__r.Name : null;
      row.specialty = record.Account__r != null
        ? MedicalSpecialtyPicklist.getLabel(record.Account__r.Specialty_1__c)
        : null;
      row.recordTypeDeveloperName = record.Account__r != null &&
        record.Account__r.RecordType != null
        ? record.Account__r.RecordType.DeveloperName
        : null;
      row.accountTypeLabel = resolveAccountTypeLabel(row.recordTypeDeveloperName);
      row.role = 'Attendee';
      row.isPrimary = order == 1;
      row.displayOrder = order;
      rows.add(row);
    }
    return rows;
  }

  private static List<ProductDetailRow> queryProductDetails(Id visitId) {
    if (!visitDetailSchemaReady()) {
      return new List<ProductDetailRow>();
    }
    List<ProductDetailRow> rows = new List<ProductDetailRow>();
    Map<Id, ProductDetailRow> rowByDetailId = new Map<Id, ProductDetailRow>();

    List<SObject> detailRecords;
    try {
      detailRecords = Database.query(buildProductDetailQuery(visitId));
    } catch (QueryException e) {
      try {
        detailRecords = Database.query(buildProductDetailQueryWithoutHierarchy(visitId));
      } catch (QueryException retryEx) {
        return rows;
      }
    }

    for (SObject detail : detailRecords) {
      ProductDetailRow row = new ProductDetailRow();
      row.id = (Id) detail.get('Id');
      row.productId = (Id) detail.get('Product2__c');
      SObject product = detail.getSObject('Product2__r');
      row.productName = product != null ? (String) product.get('Name') : null;
      row.imageUrl = product != null ? getProductImageUrl((Product2) product) : null;
      applyProductHierarchyFields(row, product);
      Object displayOrder = detail.get('Display_Order__c');
      row.displayOrder = displayOrder != null ? Integer.valueOf(String.valueOf(displayOrder)) : null;
      row.detailType = (String) detail.get('Detail_Type__c');
      row.notes = (String) detail.get('Notes__c');
      row.messages = new List<ProductMessageRow>();
      rows.add(row);
      rowByDetailId.put(row.id, row);
    }

    if (!visitMessageSchemaReady()) {
      return rows;
    }

    List<SObject> messageRecords;
    try {
      messageRecords = Database.query(buildProductMessageQuery(visitId));
    } catch (QueryException e) {
      return rows;
    }

    for (SObject msg : messageRecords) {
      Id detailId = (Id) msg.get('Visit_Product_Detail__c');
      if (!rowByDetailId.containsKey(detailId)) {
        continue;
      }
      ProductMessageRow msgRow = new ProductMessageRow();
      msgRow.id = (Id) msg.get('Id');
      msgRow.topic = (String) msg.get('Topic__c');
      msgRow.sentiment = (String) msg.get('Sentiment__c');
      msgRow.response = (String) msg.get('Response__c');
      rowByDetailId.get(detailId).messages.add(msgRow);
    }
    return rows;
  }

  private static List<SampleRow> querySamples(Id visitId) {
    if (!visitSampleSchemaReady()) {
      return new List<SampleRow>();
    }
    List<SampleRow> rows = new List<SampleRow>();
    List<SObject> sampleRecords;
    try {
      sampleRecords = Database.query(buildSampleQuery(visitId));
    } catch (QueryException e) {
      return rows;
    }
    for (SObject record : sampleRecords) {
      SampleRow row = new SampleRow();
      row.id = (Id) record.get('Id');
      row.productId = (Id) record.get('Product2__c');
      SObject product = record.getSObject('Product2__r');
      row.productName = product != null ? (String) product.get('Name') : null;
      row.imageUrl = product != null ? getProductImageUrl((Product2) product) : null;
      row.visitAttendeeId = (Id) record.get('Visit_Attendee__c');
      SObject attendee = record.getSObject('Visit_Attendee__r');
      SObject attendeeAccount = attendee != null ? attendee.getSObject('Account__r') : null;
      row.attendeeName = attendeeAccount != null ? (String) attendeeAccount.get('Name') : null;
      row.quantity = (Decimal) record.get('Quantity__c');
      row.lotNumber = (String) record.get('Lot_Number__c');
      row.sampleInventoryId = (Id) record.get('Sample_Inventory__c');
      SObject inventory = record.getSObject('Sample_Inventory__r');
      row.inventoryOnHand = inventory != null ? (Decimal) inventory.get('Quantity_On_Hand__c') : null;
      row.inventoryExpiry = inventory != null ? (Date) inventory.get('Expiry_Date__c') : null;
      rows.add(row);
    }
    return rows;
  }

  private static List<ClmSessionRow> queryClmSessions(Id visitId) {
    List<ClmSessionRow> rows = new List<ClmSessionRow>();
    for (CLM_Presentation_Session__c session : [
      SELECT
        Id,
        CLM_Presentation__c,
        CLM_Presentation__r.Name,
        Status__c,
        Started_At__c,
        Ended_At__c,
        Slides_Presented_Count__c,
        Total_Duration_Seconds__c
      FROM CLM_Presentation_Session__c
      WHERE Visit__c = :visitId
      WITH USER_MODE
      ORDER BY Started_At__c DESC NULLS LAST
    ]) {
      ClmSessionRow row = new ClmSessionRow();
      row.id = session.Id;
      row.presentationId = session.CLM_Presentation__c;
      row.presentationName = session.CLM_Presentation__r != null
        ? session.CLM_Presentation__r.Name
        : null;
      row.status = session.Status__c;
      row.startedAt = session.Started_At__c;
      row.endedAt = session.Ended_At__c;
      row.slidesPresentedCount = session.Slides_Presented_Count__c != null
        ? Integer.valueOf(session.Slides_Presented_Count__c)
        : null;
      row.totalDurationSeconds = session.Total_Duration_Seconds__c != null
        ? Integer.valueOf(session.Total_Duration_Seconds__c)
        : null;
      rows.add(row);
    }
    return rows;
  }

  private static AttendeeRow buildPrimaryAttendeeFromVisit(Visit__c visit) {
    AttendeeRow row = new AttendeeRow();
    row.accountId = visit.Account__c;
    row.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
    row.specialty = visit.Account__r != null
      ? MedicalSpecialtyPicklist.getLabel(visit.Account__r.Specialty_1__c)
      : null;
    row.recordTypeDeveloperName = visit.Account__r != null &&
      visit.Account__r.RecordType != null
      ? visit.Account__r.RecordType.DeveloperName
      : null;
    row.accountTypeLabel = resolveAccountTypeLabel(row.recordTypeDeveloperName);
    row.role = 'Attendee';
    row.isPrimary = true;
    row.displayOrder = 1;
    return row;
  }

  private static List<ProductDetailRow> migrateLegacyProducts(Visit__c visit) {
    List<ProductDetailRow> rows = new List<ProductDetailRow>();
    Set<Id> territoryIds = expandTerritoryHierarchy(getUserTerritoryIds());
    Set<Id> ptaProductIds = getPtaProductIds(territoryIds);
    Set<Id> scopedIds = intersectWithAtpf(visit.Account__c, territoryIds, ptaProductIds);
    if (scopedIds.isEmpty()) {
      scopedIds = ptaProductIds;
    }

    Map<String, Product2> productByName = new Map<String, Product2>();
    if (!scopedIds.isEmpty()) {
      for (Product2 product : queryProductsByIds(scopedIds)) {
        productByName.put(product.Name.toLowerCase(), product);
      }
    }

    Integer order = 1;
    for (String token : visit.Products_Discussed__c.split(';')) {
      String name = token != null ? token.trim() : null;
      if (String.isBlank(name)) {
        continue;
      }
      ProductDetailRow row = new ProductDetailRow();
      row.productName = name;
      row.displayOrder = order;
      row.detailType = 'Detail';
      row.messages = new List<ProductMessageRow>();
      if (productByName.containsKey(name.toLowerCase())) {
        Product2 matchedProduct = productByName.get(name.toLowerCase());
        row.productId = matchedProduct.Id;
        row.imageUrl = getProductImageUrl(matchedProduct);
        applyProductHierarchyFields(row, matchedProduct);
      }
      rows.add(row);
      order++;
    }
    return rows;
  }

  private static Set<Id> getPtaProductIds(Set<Id> territoryIds) {
    Set<Id> productIds = new Set<Id>();
    if (territoryIds.isEmpty()) {
      return productIds;
    }
    Date today = Date.today();
    for (Product_Territory_Alignment__c alignment : [
      SELECT Product2_Id__c
      FROM Product_Territory_Alignment__c
      WHERE
        Territory2_Id__c IN :territoryIds
        AND Product2_Id__c != NULL
        AND Is_Active__c = TRUE
        AND (Effective_Start_Date__c = NULL OR Effective_Start_Date__c <= :today)
        AND (Effective_End_Date__c = NULL OR Effective_End_Date__c >= :today)
      WITH USER_MODE
    ]) {
      try {
        productIds.add((Id) alignment.Product2_Id__c);
      } catch (Exception ex) {
        // Skip invalid ids.
      }
    }
    return productIds;
  }

  private static Set<Id> intersectWithAtpf(
    Id accountId,
    Set<Id> territoryIds,
    Set<Id> ptaProductIds
  ) {
    if (accountId == null || territoryIds.isEmpty() || ptaProductIds.isEmpty()) {
      return new Set<Id>();
    }
    Set<String> territoryKeys = new Set<String>();
    for (Id territoryId : territoryIds) {
      territoryKeys.add(String.valueOf(territoryId));
    }
    Set<Id> atpfProductIds = new Set<Id>();
    for (Account_Territory_Product_Fields__c atpf : [
      SELECT Product2_Id__c
      FROM Account_Territory_Product_Fields__c
      WHERE
        Account__c = :accountId
        AND Territory2_Id__c IN :territoryKeys
        AND Is_Active__c = TRUE
        AND Product2_Id__c != NULL
      WITH USER_MODE
    ]) {
      try {
        Id productId = (Id) atpf.Product2_Id__c;
        if (ptaProductIds.contains(productId)) {
          atpfProductIds.add(productId);
        }
      } catch (Exception ex) {
        // Skip invalid ids.
      }
    }
    return atpfProductIds.isEmpty() ? ptaProductIds : atpfProductIds;
  }

  private static Map<Id, Account_Territory_Product_Fields__c> getAtpfByProduct(
    Id accountId,
    Set<Id> territoryIds,
    Set<Id> productIds
  ) {
    Map<Id, Account_Territory_Product_Fields__c> result = new Map<Id, Account_Territory_Product_Fields__c>();
    if (accountId == null || territoryIds.isEmpty() || productIds.isEmpty()) {
      return result;
    }
    Set<String> territoryKeys = new Set<String>();
    for (Id territoryId : territoryIds) {
      territoryKeys.add(String.valueOf(territoryId));
    }
    Set<String> productKeys = new Set<String>();
    for (Id productId : productIds) {
      productKeys.add(String.valueOf(productId));
    }
    for (Account_Territory_Product_Fields__c atpf : [
      SELECT Product2_Id__c, Adoption__c, Loyalty__c, Product_Matrix_Rating__c, Target_Visit_Frequency__c, Rx_Per_Week__c
      FROM Account_Territory_Product_Fields__c
      WHERE
        Account__c = :accountId
        AND Territory2_Id__c IN :territoryKeys
        AND Product2_Id__c IN :productKeys
        AND Is_Active__c = TRUE
      WITH USER_MODE
    ]) {
      try {
        result.put((Id) atpf.Product2_Id__c, atpf);
      } catch (Exception ex) {
        // Skip invalid ids.
      }
    }
    return result;
  }

  private static Set<Id> getExistingAttendeeAccountIds(Id visitId) {
    Set<Id> ids = new Set<Id>();
    for (Visit_Attendee__c record : [
      SELECT Account__c FROM Visit_Attendee__c WHERE Visit__c = :visitId WITH USER_MODE
    ]) {
      if (record.Account__c != null) {
        ids.add(record.Account__c);
      }
    }
    return ids;
  }

  private static AttendeeCandidate mapAttendeeCandidate(Account account, String source) {
    AttendeeCandidate candidate = new AttendeeCandidate();
    candidate.accountId = account.Id;
    candidate.accountName = account.Name;
    candidate.specialty = MedicalSpecialtyPicklist.getLabel(account.Specialty_1__c);
    candidate.recordTypeDeveloperName = account.RecordType != null
      ? account.RecordType.DeveloperName
      : null;
    candidate.accountTypeLabel = resolveAccountTypeLabel(candidate.recordTypeDeveloperName);
    candidate.source = source;
    return candidate;
  }

  private static String resolveAccountTypeLabel(String developerName) {
    if (HCP_RECORD_TYPES.contains(developerName)) {
      return 'HCP';
    }
    if (developerName == 'Institution_HCO') {
      return 'HCO';
    }
    return 'Account';
  }

  private static String formatDurationLabel(DateTime startDateTime, DateTime endDateTime) {
    if (startDateTime == null || endDateTime == null) {
      return null;
    }
    Long minutes = (endDateTime.getTime() - startDateTime.getTime()) / (1000 * 60);
    if (minutes < 60) {
      return minutes + ' min';
    }
    Long hours = minutes / 60;
    Long remainder = Math.mod(minutes, 60);
    return remainder == 0 ? hours + ' hr' : hours + ' hr ' + remainder + ' min';
  }

  private static Set<Id> getUserTerritoryIds() {
    Set<Id> territoryIds = new Set<Id>();
    for (UserTerritory2Association assignment : [
      SELECT Territory2Id
      FROM UserTerritory2Association
      WHERE UserId = :UserInfo.getUserId()
      WITH USER_MODE
    ]) {
      territoryIds.add(assignment.Territory2Id);
    }
    return territoryIds;
  }

  private static Set<Id> expandTerritoryHierarchy(Set<Id> seedTerritoryIds) {
    Set<Id> allTerritoryIds = new Set<Id>(seedTerritoryIds);
    Boolean addedChildren = true;
    while (addedChildren) {
      addedChildren = false;
      List<Territory2> children = [
        SELECT Id
        FROM Territory2
        WHERE ParentTerritory2Id IN :allTerritoryIds AND Id NOT IN :allTerritoryIds
        WITH USER_MODE
      ];
      for (Territory2 child : children) {
        allTerritoryIds.add(child.Id);
        addedChildren = true;
      }
    }
    return allTerritoryIds;
  }

  private static Set<Id> getTerritoryAccountIds() {
    Set<Id> territoryIds = expandTerritoryHierarchy(getUserTerritoryIds());
    if (territoryIds.isEmpty()) {
      return new Set<Id>();
    }
    Set<Id> accountIds = new Set<Id>();
    for (ObjectTerritory2Association association : [
      SELECT ObjectId
      FROM ObjectTerritory2Association
      WHERE Territory2Id IN :territoryIds
      WITH USER_MODE
    ]) {
      accountIds.add(association.ObjectId);
    }
    return accountIds;
  }

  private static Boolean hasObjectField(Schema.SObjectType token, String fieldApiName) {
    if (token == null || String.isBlank(fieldApiName)) {
      return false;
    }
    Map<String, Schema.SObjectField> fieldMap = token.getDescribe().fields.getMap();
    Schema.SObjectField field = fieldMap.get(fieldApiName);
    if (field == null) {
      field = fieldMap.get(fieldApiName.toLowerCase());
    }
    return field != null && field.getDescribe().isAccessible();
  }

  private static Boolean isProductImageUrlReadable() {
    if (productImageUrlReadable == null) {
      Map<String, Schema.SObjectField> fieldMap = Product2.SObjectType.getDescribe().fields.getMap();
      Schema.SObjectField imageField = fieldMap.containsKey('Product_Image_URL__c')
        ? fieldMap.get('Product_Image_URL__c')
        : fieldMap.get('product_image_url__c');
      productImageUrlReadable = imageField != null && imageField.getDescribe().isAccessible();
    }
    return productImageUrlReadable;
  }

  private static String getProductImageUrl(Product2 product) {
    return isProductImageUrlReadable() && product != null
      ? (String) product.get('Product_Image_URL__c')
      : null;
  }

  private static List<Product2> queryProductsByIds(Set<Id> productIds) {
    if (productIds == null || productIds.isEmpty()) {
      return new List<Product2>();
    }
    String imageSelect = isProductImageUrlReadable() ? ', Product_Image_URL__c' : '';
    String hierarchySelect = buildProductHierarchySelect(null);
    String soql =
      'SELECT Id, Name' +
      imageSelect +
      hierarchySelect +
      ' FROM Product2 WHERE Id IN :productIds AND IsActive = TRUE WITH USER_MODE ORDER BY Name ASC';
    try {
      return Database.query(soql);
    } catch (QueryException ex) {
      return Database.query(
        'SELECT Id, Name' +
        imageSelect +
        ' FROM Product2 WHERE Id IN :productIds AND IsActive = TRUE WITH USER_MODE ORDER BY Name ASC'
      );
    }
  }

  private static TerritoryProductOption mapTerritoryProductOption(Product2 product) {
    TerritoryProductOption option = new TerritoryProductOption();
    option.productId = product.Id;
    option.productName = product.Name;
    option.imageUrl = getProductImageUrl(product);
    applyProductHierarchyFields(option, product);
    return option;
  }

  private static void applyProductHierarchyFields(TerritoryProductOption option, Product2 product) {
    if (option == null || product == null) {
      return;
    }
    if (hasObjectField(Product2.SObjectType, 'Product_Type__c')) {
      option.productType = (String) product.get('Product_Type__c');
    }
    if (hasObjectField(Product2.SObjectType, 'Parent_Product__c')) {
      option.parentProductId = (Id) product.get('Parent_Product__c');
      SObject parent = product.getSObject('Parent_Product__r');
      if (parent != null) {
        option.brandName = (String) parent.get('Name');
      }
    }
    if (String.isBlank(option.brandName) && hasObjectField(Product2.SObjectType, 'Primary_Brand__c')) {
      option.brandName = (String) product.get('Primary_Brand__c');
    }
    if (String.isBlank(option.brandName)) {
      option.brandName = product.Name;
    }
    if (hasObjectField(Product2.SObjectType, 'Strength__c')) {
      option.strength = (String) product.get('Strength__c');
    }
    if (hasObjectField(Product2.SObjectType, 'Form__c')) {
      option.form = (String) product.get('Form__c');
    }
  }

  private static void applyProductHierarchyFields(ProductDetailRow row, SObject product) {
    if (row == null || product == null) {
      return;
    }
    if (hasObjectField(Product2.SObjectType, 'Product_Type__c')) {
      row.productType = (String) product.get('Product_Type__c');
    }
    if (hasObjectField(Product2.SObjectType, 'Parent_Product__c')) {
      row.parentProductId = (Id) product.get('Parent_Product__c');
      SObject parent = product.getSObject('Parent_Product__r');
      if (parent != null) {
        row.brandName = (String) parent.get('Name');
      }
    }
    if (String.isBlank(row.brandName) && hasObjectField(Product2.SObjectType, 'Primary_Brand__c')) {
      row.brandName = (String) product.get('Primary_Brand__c');
    }
    if (String.isBlank(row.brandName)) {
      row.brandName = (String) product.get('Name');
    }
    if (hasObjectField(Product2.SObjectType, 'Strength__c')) {
      row.strength = (String) product.get('Strength__c');
    }
    if (hasObjectField(Product2.SObjectType, 'Form__c')) {
      row.form = (String) product.get('Form__c');
    }
  }

  private static String buildProductHierarchySelect(String alias) {
    String prefix = String.isBlank(alias) ? '' : alias + '.';
    List<String> fields = new List<String>();
    if (hasObjectField(Product2.SObjectType, 'Product_Type__c')) {
      fields.add(prefix + 'Product_Type__c');
    }
    if (hasObjectField(Product2.SObjectType, 'Parent_Product__c')) {
      fields.add(prefix + 'Parent_Product__c');
      fields.add(prefix + 'Parent_Product__r.Name');
    }
    if (hasObjectField(Product2.SObjectType, 'Primary_Brand__c')) {
      fields.add(prefix + 'Primary_Brand__c');
    }
    if (hasObjectField(Product2.SObjectType, 'Strength__c')) {
      fields.add(prefix + 'Strength__c');
    }
    if (hasObjectField(Product2.SObjectType, 'Form__c')) {
      fields.add(prefix + 'Form__c');
    }
    return fields.isEmpty() ? '' : ', ' + String.join(fields, ', ');
  }

  private static Set<Id> expandDispenseRelatedProductIds(Set<Id> productIds) {
    Set<Id> expanded = new Set<Id>();
    if (productIds == null || productIds.isEmpty()) {
      return expanded;
    }
    if (
      !hasObjectField(Product2.SObjectType, 'Product_Type__c') ||
      !hasObjectField(Product2.SObjectType, 'Parent_Product__c')
    ) {
      return expanded;
    }
    Set<Id> parentIds = new Set<Id>();
    for (Product2 product : Database.query(
      'SELECT Id, Product_Type__c, Parent_Product__c FROM Product2 ' +
      'WHERE Id IN :productIds WITH USER_MODE'
    )) {
      parentIds.add(product.Id);
      if (product.Parent_Product__c != null) {
        parentIds.add(product.Parent_Product__c);
      }
    }
    if (parentIds.isEmpty()) {
      return expanded;
    }
    for (Product2 sibling : Database.query(
      'SELECT Id FROM Product2 WHERE IsActive = TRUE ' +
      'AND Product_Type__c IN (\'Sample\', \'Brand Reminder\') ' +
      'AND Parent_Product__c IN :parentIds WITH USER_MODE'
    )) {
      expanded.add(sibling.Id);
    }
    return expanded;
  }

  private static Boolean visitDetailSchemaReady() {
    if (visitDetailSchemaReadyCached == true) {
      return visitDetailSchemaReadyValue;
    }
    visitDetailSchemaReadyValue = canQueryVisitProductDetails();
    visitDetailSchemaReadyCached = true;
    return visitDetailSchemaReadyValue;
  }

  private static Boolean visitMessageSchemaReady() {
    if (visitMessageSchemaReadyCached == true) {
      return visitMessageSchemaReadyValue;
    }
    visitMessageSchemaReadyValue = visitDetailSchemaReady() && canQueryVisitProductMessages();
    visitMessageSchemaReadyCached = true;
    return visitMessageSchemaReadyValue;
  }

  private static Boolean visitSampleSchemaReady() {
    if (visitSampleSchemaReadyCached == true) {
      return visitSampleSchemaReadyValue;
    }
    visitSampleSchemaReadyValue = canQueryVisitSamples();
    visitSampleSchemaReadyCached = true;
    return visitSampleSchemaReadyValue;
  }

  private static Boolean sampleInventorySchemaReady() {
    if (sampleInventorySchemaReadyCached == true) {
      return sampleInventorySchemaReadyValue;
    }
    sampleInventorySchemaReadyValue = canQuerySampleInventory();
    sampleInventorySchemaReadyCached = true;
    return sampleInventorySchemaReadyValue;
  }

  private static Boolean canQueryVisitProductDetails() {
    try {
      Database.query(
        'SELECT Id, Product2__c, Display_Order__c, Detail_Type__c, Notes__c ' +
        'FROM Visit_Product_Detail__c LIMIT 0'
      );
      return true;
    } catch (Exception ex) {
      return false;
    }
  }

  private static Boolean canQueryVisitProductMessages() {
    try {
      Database.query(
        'SELECT Id, Visit_Product_Detail__c, Topic__c, Sentiment__c, Response__c ' +
        'FROM Visit_Product_Message__c LIMIT 0'
      );
      return true;
    } catch (Exception ex) {
      return false;
    }
  }

  private static Boolean canQuerySampleInventory() {
    try {
      String fields = 'Id, Product2__c, Lot_Number__c, Quantity_On_Hand__c';
      if (hasObjectField(Sample_Inventory__c.SObjectType, 'Expiry_Date__c')) {
        fields += ', Expiry_Date__c';
      }
      Database.query('SELECT ' + fields + ' FROM Sample_Inventory__c LIMIT 0');
      return true;
    } catch (Exception ex) {
      return false;
    }
  }

  private static Boolean canQueryVisitSamples() {
    try {
      String inventorySelect = '';
      if (hasObjectField(Sample_Inventory__c.SObjectType, 'Quantity_On_Hand__c')) {
        inventorySelect += ', Sample_Inventory__r.Quantity_On_Hand__c';
      }
      if (hasObjectField(Sample_Inventory__c.SObjectType, 'Expiry_Date__c')) {
        inventorySelect += ', Sample_Inventory__r.Expiry_Date__c';
      }
      Database.query(
        'SELECT Id, Product2__c, Quantity__c, Visit_Attendee__c, Lot_Number__c, Sample_Inventory__c' +
        inventorySelect +
        ' FROM Visit_Sample__c LIMIT 0'
      );
      return true;
    } catch (Exception ex) {
      return false;
    }
  }

  private static String buildProductDetailQuery(Id visitId) {
    String productImageSelect = isProductImageUrlReadable()
      ? ', Product2__r.Product_Image_URL__c'
      : '';
    String hierarchySelect = buildProductHierarchySelect('Product2__r');
    return 'SELECT Id, Product2__c, Product2__r.Name' +
      productImageSelect +
      hierarchySelect +
      ', Display_Order__c, Detail_Type__c, Notes__c ' +
      'FROM Visit_Product_Detail__c WHERE Visit__c = \'' +
      String.escapeSingleQuotes(String.valueOf(visitId)) +
      '\' WITH USER_MODE ORDER BY Display_Order__c ASC, CreatedDate ASC';
  }

  private static String buildProductDetailQueryWithoutHierarchy(Id visitId) {
    String productImageSelect = isProductImageUrlReadable()
      ? ', Product2__r.Product_Image_URL__c'
      : '';
    return 'SELECT Id, Product2__c, Product2__r.Name' +
      productImageSelect +
      ', Display_Order__c, Detail_Type__c, Notes__c ' +
      'FROM Visit_Product_Detail__c WHERE Visit__c = \'' +
      String.escapeSingleQuotes(String.valueOf(visitId)) +
      '\' WITH USER_MODE ORDER BY Display_Order__c ASC, CreatedDate ASC';
  }

  private static String buildProductDetailOrderQuery(Id visitId) {
    return 'SELECT Id, Display_Order__c FROM Visit_Product_Detail__c WHERE Visit__c = \'' +
      String.escapeSingleQuotes(String.valueOf(visitId)) +
      '\' WITH USER_MODE';
  }

  private static String buildProductMessageQuery(Id visitId) {
    return 'SELECT Id, Visit_Product_Detail__c, Topic__c, Sentiment__c, Response__c ' +
      'FROM Visit_Product_Message__c WHERE Visit_Product_Detail__r.Visit__c = \'' +
      String.escapeSingleQuotes(String.valueOf(visitId)) +
      '\' WITH USER_MODE ORDER BY CreatedDate ASC';
  }

  private static String buildSampleQuery(Id visitId) {
    String productImageSelect = isProductImageUrlReadable()
      ? ', Product2__r.Product_Image_URL__c'
      : '';
    String inventorySelect = '';
    if (hasObjectField(Sample_Inventory__c.SObjectType, 'Quantity_On_Hand__c')) {
      inventorySelect += ', Sample_Inventory__r.Quantity_On_Hand__c';
    }
    if (hasObjectField(Sample_Inventory__c.SObjectType, 'Expiry_Date__c')) {
      inventorySelect += ', Sample_Inventory__r.Expiry_Date__c';
    }
    return 'SELECT Id, Product2__c, Product2__r.Name' +
      productImageSelect +
      ', Visit_Attendee__c, Visit_Attendee__r.Account__r.Name, Quantity__c, Lot_Number__c, Sample_Inventory__c' +
      inventorySelect +
      ' FROM Visit_Sample__c WHERE Visit__c = \'' +
      String.escapeSingleQuotes(String.valueOf(visitId)) +
      '\' WITH USER_MODE ORDER BY CreatedDate ASC';
  }
}