public without sharing class VisitProductSurveyFeedbackSeed {
  private static final List<String> PRODUCT_NAMES = new List<String>{
    'ZetaGluc',
    'ZetaCard',
    'ZetaOnc',
    'ZetaPain',
    'ZetaResp'
  };
  private static final List<String> SENTIMENTS = new List<String>{
    'Positive',
    'Neutral',
    'Negative'
  };

  public class SeedResult {
    public Integer feedbackCount = 0;
    public String message;
  }

  public static SeedResult seedDemoData() {
    SeedResult result = new SeedResult();
    List<Visit__c> visits = [
      SELECT Id, Account__c, Assigned_To__c, Start_Date__c
      FROM Visit__c
      WHERE Status__c = 'Completed' AND Assigned_To__c != NULL
      ORDER BY Start_Date__c DESC NULLS LAST
      LIMIT 50
    ];
    if (visits.isEmpty()) {
      result.message = 'No completed visits found. Run MedicalRep360Seed first.';
      return result;
    }

    List<Visit_Product_Survey_Feedback__c> rows = new List<Visit_Product_Survey_Feedback__c>();
    Integer targetCount = Test.isRunningTest() ? 5 : 40;
    Integer index = 0;
    for (Visit__c visit : visits) {
      if (rows.size() >= targetCount) {
        break;
      }
      rows.add(buildFeedback(visit, index++));
      if (!Test.isRunningTest() && Math.mod(index, 2) == 0) {
        rows.add(buildFeedback(visit, index++));
      }
    }

    Database.insert(rows, AccessLevel.SYSTEM_MODE);
    result.feedbackCount = rows.size();
    result.message = 'Seeded ' + rows.size() + ' product survey feedback records.';
    return result;
  }

  private static Visit_Product_Survey_Feedback__c buildFeedback(
    Visit__c visit,
    Integer index
  ) {
    String productName = PRODUCT_NAMES[Math.mod(index, PRODUCT_NAMES.size())];
    Visit_Product_Survey_Feedback__c feedback = new Visit_Product_Survey_Feedback__c();
    feedback.Visit__c = visit.Id;
    feedback.Account__c = visit.Account__c;
    feedback.Assigned_Rep__c = visit.Assigned_To__c;
    feedback.Product_Name__c = productName;
    feedback.Efficacy_Sentiment__c = SENTIMENTS[Math.mod(index, SENTIMENTS.size())];
    feedback.Safety_Sentiment__c = SENTIMENTS[Math.mod(index + 1, SENTIMENTS.size())];
    feedback.Indication_Sentiment__c = SENTIMENTS[Math.mod(index + 2, SENTIMENTS.size())];
    feedback.Side_Effects_Sentiment__c = SENTIMENTS[Math.mod(
      index + 1,
      SENTIMENTS.size()
    )];
    feedback.Usage_Sentiment__c = SENTIMENTS[Math.mod(index, SENTIMENTS.size())];
    feedback.Visit_Feedback__c =
      'Demo feedback for ' +
      productName +
      ' following visit. Helpful discussion on efficacy and patient outcomes.';
    feedback.Submitted_At__c = visit.Start_Date__c != null
      ? visit.Start_Date__c.addHours(2)
      : System.now();
    feedback.Source__c = 'WhatsApp Survey';
    return feedback;
  }
}
