@IsTest
private class ProductSurveyControllerTest {
  @TestSetup
  static void setupData() {
    Account acct = new Account(Name = 'Survey HCO', BillingCity = 'Cairo');
    insert acct;
    insert new Visit__c(
      Account__c = acct.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Status__c = 'Completed',
      Start_Date__c = DateTime.now().addDays(-1),
      End_Date__c = DateTime.now().addDays(-1).addHours(1)
    );
    insert new Product2(
      Name = 'ZetaMed',
      IsActive = true,
      Product_Image_URL__c = 'https://example.com/zetamed.png',
      Therapy_Area__c = 'Diabetes'
    );
  }

  @IsTest
  static void submitsFeedbackFromVisualforcePage() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    PageReference pageRef = Page.ProductSurvey;
    pageRef.getParameters().put('visitId', visit.Id);
    pageRef.getParameters().put('product', 'ZetaMed');
    Test.setCurrentPage(pageRef);

    ProductSurveyController controller = new ProductSurveyController();
    controller.efficacySentiment = 'Positive';
    controller.visitFeedback = 'Great discussion';

    Test.startTest();
    controller.submitFeedback();
    Test.stopTest();

    System.assertEquals(true, controller.submitted);
    List<Visit_Product_Survey_Feedback__c> rows = [
      SELECT Product_Name__c, Visit_Feedback__c, Efficacy_Sentiment__c
      FROM Visit_Product_Survey_Feedback__c
    ];
    System.assertEquals(1, rows.size());
    System.assertEquals('ZetaMed', rows[0].Product_Name__c);
    System.assertEquals('Great discussion', rows[0].Visit_Feedback__c);
  }

  @IsTest
  static void loadsProductImageFromCatalog() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    PageReference pageRef = Page.ProductSurvey;
    pageRef.getParameters().put('visitId', visit.Id);
    pageRef.getParameters().put('product', 'ZetaMed');
    Test.setCurrentPage(pageRef);

    ProductSurveyController controller = new ProductSurveyController();
    System.assertEquals(false, controller.invalidRequest);
    System.assertEquals(true, controller.getHasProductImage());
    System.assertEquals(
      'https://example.com/zetamed.png',
      controller.getProductImageUrl()
    );
    System.assertEquals('Diabetes', controller.getProductTherapyArea());
    System.assertEquals('Z', controller.getProductInitials());
  }

  @IsTest
  static void rejectsInvalidVisit() {
    PageReference pageRef = Page.ProductSurvey;
    pageRef.getParameters().put('visitId', 'invalid');
    Test.setCurrentPage(pageRef);

    ProductSurveyController controller = new ProductSurveyController();
    System.assertEquals(true, controller.invalidRequest);
  }

  @IsTest
  static void guestUserCanSubmitFeedback() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Id guestUserId = [
      SELECT GuestUserId
      FROM Site
      WHERE UrlPathPrefix = 'productsurvey'
      LIMIT 1
    ]
    .GuestUserId;
    User guest = [SELECT Id FROM User WHERE Id = :guestUserId];

    System.runAs(guest) {
      PageReference pageRef = Page.ProductSurvey;
      pageRef.getParameters().put('visitId', visit.Id);
      pageRef.getParameters().put('product', 'Empacoza 10 mg');
      Test.setCurrentPage(pageRef);

      ProductSurveyController controller = new ProductSurveyController();
      System.assertEquals(false, controller.invalidRequest, 'Guest should load visit');
      controller.efficacySentiment = 'Positive';
      controller.safetySentiment = 'Negative';
      controller.visitFeedback = 'Guest submission';

      Test.startTest();
      controller.submitFeedback();
      Test.stopTest();

      String outcome = 'submitted=' + controller.submitted +
        ' invalid=' + controller.invalidRequest +
        ' error=' + controller.errorMessage;
      System.assertEquals(true, controller.submitted, outcome);
    }
  }
}
