/**
 * Idempotent demo meetings for Mendix integration testing.
 * Run: MeetingDemoSeed.seed();
 * Keys use Unique_Integration_ID__c prefix MX-DEMO-.
 */
public without sharing class MeetingDemoSeed {
  public class SeedResult {
    public Integer meetingsCreated = 0;
    public Integer meetingsSkipped = 0;
    public Integer expensesCreated = 0;
    public Integer attachmentsCreated = 0;
    public String message;
  }

  private class ExpenseSpec {
    public String recordType;
    public String type;
    public Decimal amount;
    public String status;
    public String integrationStatus;
    public String comments;
    public Boolean attachInvoice;

    public ExpenseSpec(
      String recordType,
      String type,
      Decimal amount,
      String status,
      String integrationStatus,
      String comments,
      Boolean attachInvoice
    ) {
      this.recordType = recordType;
      this.type = type;
      this.amount = amount;
      this.status = status;
      this.integrationStatus = integrationStatus;
      this.comments = comments;
      this.attachInvoice = attachInvoice;
    }
  }

  private class MeetingSpec {
    public String recordType;
    public String status;
    public String meetingId;
    public String uniqueIntegrationId;
    public String title;
    public String deliveryFormat;
    public Decimal totalEstimated;
    public Decimal totalActual;
    public Integer dayOffset;
    public List<ExpenseSpec> expenses;
    public Boolean attachInvoiceOnMeeting;

    public MeetingSpec(
      String recordType,
      String status,
      String meetingId,
      String title,
      String deliveryFormat,
      Decimal totalEstimated,
      Decimal totalActual,
      Integer dayOffset,
      List<ExpenseSpec> expenses,
      Boolean attachInvoiceOnMeeting
    ) {
      this.recordType = recordType;
      this.status = status;
      this.meetingId = meetingId;
      this.uniqueIntegrationId = 'MX-DEMO-' + recordType;
      this.title = title;
      this.deliveryFormat = deliveryFormat;
      this.totalEstimated = totalEstimated;
      this.totalActual = totalActual;
      this.dayOffset = dayOffset;
      this.expenses = expenses;
      this.attachInvoiceOnMeeting = attachInvoiceOnMeeting;
    }
  }

  public static SeedResult seed() {
    SeedResult result = new SeedResult();
    Map<String, Id> meetingRtByDevName = loadRecordTypes('Meeting__c');
    Map<String, Id> expenseRtByDevName = loadRecordTypes('Meeting_Expense__c');
    Blob invoiceBody = loadInvoiceBody();

    Set<String> integrationIds = new Set<String>();
    for (MeetingSpec spec : buildSpecs()) {
      integrationIds.add(spec.uniqueIntegrationId);
    }

    Map<String, Meeting__c> existingByIntegration = new Map<String, Meeting__c>();
    for (Meeting__c existing : [
      SELECT Id, Unique_Integration_ID__c
      FROM Meeting__c
      WHERE Unique_Integration_ID__c IN :integrationIds
      WITH SYSTEM_MODE
    ]) {
      existingByIntegration.put(existing.Unique_Integration_ID__c, existing);
    }

    for (MeetingSpec spec : buildSpecs()) {
      if (existingByIntegration.containsKey(spec.uniqueIntegrationId)) {
        result.meetingsSkipped++;
        continue;
      }
      Id meetingRtId = meetingRtByDevName.get(spec.recordType);
      if (meetingRtId == null) {
        result.message =
          'Missing Meeting record type: ' +
          spec.recordType +
          '. Created=' +
          result.meetingsCreated;
        return result;
      }

      DateTime startDt = DateTime.newInstance(
        Date.today().addDays(spec.dayOffset),
        Time.newInstance(9, 0, 0, 0)
      );
      DateTime endDt = startDt.addHours(3);

      Meeting__c meeting = new Meeting__c(
        RecordTypeId = meetingRtId,
        Status__c = spec.status,
        Meeting_ID__c = spec.meetingId,
        Unique_Integration_ID__c = spec.uniqueIntegrationId,
        Objectives__c = spec.title,
        Delivery_Format__c = spec.deliveryFormat,
        Start_Date_Time__c = startDt,
        End_Date_Time__c = endDt,
        Total_Estimated_Expenses__c = spec.totalEstimated,
        Total_Actual_Expenses__c = spec.totalActual
      );
      insert as system meeting;
      result.meetingsCreated++;

      Id invoiceTargetId = meeting.Id;
      for (ExpenseSpec expenseSpec : spec.expenses) {
        Id expenseRtId = expenseRtByDevName.get(expenseSpec.recordType);
        if (expenseRtId == null) {
          continue;
        }
        Meeting_Expense__c expense = new Meeting_Expense__c(
          Meeting__c = meeting.Id,
          RecordTypeId = expenseRtId,
          Type__c = expenseSpec.type,
          Amount__c = expenseSpec.amount,
          Currency_Code__c = 'EGP',
          Status__c = expenseSpec.status,
          Integration_Status__c = expenseSpec.integrationStatus,
          Date_Time__c = startDt,
          Comments__c = expenseSpec.comments
        );
        insert as system expense;
        result.expensesCreated++;
        if (expenseSpec.attachInvoice == true) {
          invoiceTargetId = expense.Id;
        }
      }

      Boolean needsInvoice =
        spec.attachInvoiceOnMeeting == true || hasInvoiceExpense(spec.expenses);
      if (needsInvoice && invoiceBody != null) {
        createInvoiceFile(invoiceTargetId, invoiceBody, spec.meetingId);
        result.attachmentsCreated++;
      }
    }

    result.message =
      'Demo meetings created=' +
      result.meetingsCreated +
      ', skipped=' +
      result.meetingsSkipped +
      ', expenses=' +
      result.expensesCreated +
      ', attachments=' +
      result.attachmentsCreated;
    return result;
  }

  private static Boolean hasInvoiceExpense(List<ExpenseSpec> expenses) {
    for (ExpenseSpec expense : expenses) {
      if (expense.attachInvoice == true) {
        return true;
      }
    }
    return false;
  }

  private static List<MeetingSpec> buildSpecs() {
    return new List<MeetingSpec>{
      new MeetingSpec(
        'Speaker_Meeting',
        'Approved',
        'MTG-DEMO-SPEAKER',
        'Demo Speaker Meeting — Cairo',
        'Out-of-office',
        8500,
        9200,
        7,
        new List<ExpenseSpec>{
          new ExpenseSpec('Estimate', 'Meal', 8500, 'Approved', 'Not Sent', 'Estimated catering', false),
          new ExpenseSpec('Actual', 'Meal', 9200, 'Approved', 'Ready', 'Venue catering invoice', true)
        },
        false
      ),
      new MeetingSpec(
        'Regional_Standalone',
        'Pending GPM Approval',
        'MTG-DEMO-REGIONAL',
        'Demo Regional Standalone — Alexandria',
        'Out-of-office',
        15000,
        0,
        10,
        new List<ExpenseSpec>{
          new ExpenseSpec('Estimate', 'Venue', 15000, 'Submitted', 'Ready', 'Hotel ballroom estimate', true)
        },
        false
      ),
      new MeetingSpec(
        'National_Standalone',
        'Draft',
        'MTG-DEMO-NATIONAL',
        'Demo National Standalone — Giza',
        'In-office',
        4200,
        0,
        14,
        new List<ExpenseSpec>{
          new ExpenseSpec('Estimate', 'Travel', 4200, 'Draft', 'Not Sent', 'Speaker travel estimate', false)
        },
        false
      ),
      new MeetingSpec(
        'Advisory_Board',
        'Closed',
        'MTG-DEMO-ADBOARD',
        'Demo Advisory Board — Cairo HO',
        'In-office',
        25000,
        27500,
        -5,
        new List<ExpenseSpec>{
          new ExpenseSpec('Estimate', 'Honoraria', 25000, 'Approved', 'Not Sent', 'Advisor honoraria estimate', false),
          new ExpenseSpec('Actual', 'Honoraria', 27500, 'Approved', 'Ready', 'Advisor honoraria invoice', true)
        },
        false
      ),
      new MeetingSpec(
        'RTD',
        'Pending NLM Approval',
        'MTG-DEMO-RTD',
        'Demo RTD — Delta district',
        'Out-of-office',
        3500,
        0,
        3,
        new List<ExpenseSpec>{
          new ExpenseSpec('Estimate', 'Meal', 3500, 'Submitted', 'Ready', 'RTD lunch estimate', true)
        },
        false
      ),
      new MeetingSpec(
        'AV_Action',
        'Approved',
        'MTG-DEMO-AV',
        'Demo AV / Action — Virtual studio',
        'Remote',
        6000,
        6400,
        5,
        new List<ExpenseSpec>{
          new ExpenseSpec('Estimate', 'AV', 6000, 'Approved', 'Not Sent', 'AV production estimate', false),
          new ExpenseSpec('Actual', 'AV', 6400, 'Approved', 'Ready', 'AV production invoice', true)
        },
        false
      ),
      new MeetingSpec(
        'Promotional_Activity',
        'Concluded',
        'MTG-DEMO-PROMO',
        'Demo Promotional Activity — Pharmacy week',
        'Out-of-office',
        0,
        2800,
        -2,
        new List<ExpenseSpec>{
          new ExpenseSpec('Actual', 'Materials', 2800, 'Approved', 'Ready', 'Promo materials invoice', true)
        },
        false
      )
    };
  }

  private static Map<String, Id> loadRecordTypes(String sobjectType) {
    Map<String, Id> byDevName = new Map<String, Id>();
    for (RecordType rt : [
      SELECT Id, DeveloperName
      FROM RecordType
      WHERE SObjectType = :sobjectType AND IsActive = TRUE
      WITH SYSTEM_MODE
    ]) {
      byDevName.put(rt.DeveloperName, rt.Id);
    }
    return byDevName;
  }

  private static Blob loadInvoiceBody() {
    List<StaticResource> resources = [
      SELECT Body
      FROM StaticResource
      WHERE Name = 'Sample_Meeting_Invoice'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!resources.isEmpty() && resources[0].Body != null) {
      return resources[0].Body;
    }
    // Fallback tiny PDF for tests if static resource is not deployed yet.
    return Blob.valueOf('%PDF-1.4 demo invoice');
  }

  private static void createInvoiceFile(Id linkedEntityId, Blob body, String meetingId) {
    ContentVersion version = new ContentVersion(
      Title = 'eta-invoice-744J0JNJYYQDS2KNVFPTAZVK10',
      PathOnClient = 'eta-invoice-744J0JNJYYQDS2KNVFPTAZVK10.pdf',
      VersionData = body,
      FirstPublishLocationId = linkedEntityId,
      Description = 'Sample ETA invoice for ' + meetingId
    );
    insert as system version;
  }
}