public without sharing class ProductSurveyController {
  public String visitIdParam { get; private set; }
  public String productName { get; private set; }
  public String productIdParam { get; private set; }
  public String visitFeedback { get; set; }
  public String efficacySentiment { get; set; }
  public String safetySentiment { get; set; }
  public String indicationSentiment { get; set; }
  public String sideEffectsSentiment { get; set; }
  public String usageSentiment { get; set; }
  public String errorMessage { get; private set; }
  public Boolean submitted { get; private set; }
  public Boolean invalidRequest { get; private set; }

  private Visit__c visitRecord;
  private Product2 productRecord;

  public ProductSurveyController() {
    visitIdParam = ApexPages.currentPage().getParameters().get('visitId');
    productName = ApexPages.currentPage().getParameters().get('product');
    productIdParam = ApexPages.currentPage().getParameters().get('productId');
    submitted = false;
    invalidRequest = false;
    efficacySentiment = 'Neutral';
    safetySentiment = 'Neutral';
    indicationSentiment = 'Neutral';
    sideEffectsSentiment = 'Neutral';
    usageSentiment = 'Neutral';
    loadVisit();
    loadProduct();
  }

  public String getDisplayProductName() {
    if (productRecord != null && String.isNotBlank(productRecord.Name)) {
      return productRecord.Name;
    }
    return String.isNotBlank(productName) ? productName : 'Product';
  }

  public String getProductImageUrl() {
    if (productRecord == null) {
      return null;
    }
    String fieldUrl = (String) productRecord.get('Product_Image_URL__c');
    if (String.isNotBlank(fieldUrl)) {
      return fieldUrl;
    }
    return resolveLinkedFileImageUrl(productRecord.Id);
  }

  public Boolean getHasProductImage() {
    return String.isNotBlank(getProductImageUrl());
  }

  public String getProductTherapyArea() {
    if (productRecord == null) {
      return null;
    }
    return (String) productRecord.get('Therapy_Area__c');
  }

  public String getProductInitials() {
    String name = getDisplayProductName();
    if (String.isBlank(name)) {
      return 'RX';
    }
    List<String> parts = name.trim().split('\\s+');
    if (parts.isEmpty()) {
      return 'RX';
    }
    String initials = parts[0].substring(0, 1);
    if (parts.size() > 1) {
      initials += parts[1].substring(0, 1);
    }
    return initials.toUpperCase();
  }

  public String getAccountName() {
    return visitRecord?.Account__r?.Name;
  }

  public String getRepName() {
    if (visitRecord?.Assigned_To__r == null) {
      return null;
    }
    String firstName = visitRecord.Assigned_To__r.FirstName;
    if (String.isNotBlank(firstName)) {
      return firstName;
    }
    return visitRecord.Assigned_To__r.Name;
  }

  public String getVisitDateLabel() {
    if (visitRecord?.Start_Date__c == null) {
      return null;
    }
    return visitRecord.Start_Date__c.format('MMMM d, yyyy');
  }

  public Boolean getHasVisitContext() {
    return String.isNotBlank(getAccountName()) ||
      String.isNotBlank(getRepName()) ||
      String.isNotBlank(getVisitDateLabel());
  }

  public List<SelectOption> getSentimentOptions() {
    return new List<SelectOption>{
      new SelectOption('Positive', 'Positive'),
      new SelectOption('Neutral', 'Neutral'),
      new SelectOption('Negative', 'Negative')
    };
  }

  public PageReference submitFeedback() {
    errorMessage = null;
    if (invalidRequest || visitRecord == null) {
      errorMessage = 'This survey link is not valid.';
      return null;
    }
    if (String.isBlank(getDisplayProductName())) {
      errorMessage = 'Product name is required.';
      return null;
    }

    try {
      Visit_Product_Survey_Feedback__c feedback = new Visit_Product_Survey_Feedback__c();
      feedback.Visit__c = visitRecord.Id;
      feedback.Account__c = visitRecord.Account__c;
      feedback.Product_Name__c = getDisplayProductName();
      feedback.Assigned_Rep__c = visitRecord.Assigned_To__c;
      feedback.Efficacy_Sentiment__c = efficacySentiment;
      feedback.Safety_Sentiment__c = safetySentiment;
      feedback.Indication_Sentiment__c = indicationSentiment;
      feedback.Side_Effects_Sentiment__c = sideEffectsSentiment;
      feedback.Usage_Sentiment__c = usageSentiment;
      feedback.Visit_Feedback__c = visitFeedback;
      feedback.Submitted_At__c = System.now();
      feedback.Source__c = UserInfo.getUserType() == 'Guest'
        ? 'Public Survey'
        : 'WhatsApp Survey';
      Database.insert(feedback, AccessLevel.SYSTEM_MODE);
      submitted = true;
    } catch (Exception ex) {
      errorMessage = 'Unable to save feedback. Please try again later.';
    }
    return null;
  }

  private void loadVisit() {
    if (String.isBlank(visitIdParam)) {
      invalidRequest = true;
      return;
    }
    Id visitId;
    try {
      visitId = Id.valueOf(visitIdParam);
    } catch (Exception ex) {
      invalidRequest = true;
      return;
    }

    List<Visit__c> visits = [
      SELECT
        Id,
        Account__c,
        Account__r.Name,
        Assigned_To__c,
        Assigned_To__r.Name,
        Assigned_To__r.FirstName,
        Status__c,
        Start_Date__c
      FROM Visit__c
      WHERE Id = :visitId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (visits.isEmpty() || visits[0].Status__c == 'Cancelled') {
      invalidRequest = true;
      return;
    }
    visitRecord = visits[0];
  }

  private void loadProduct() {
    if (String.isNotBlank(productIdParam)) {
      productRecord = queryProductById(productIdParam);
      if (productRecord != null && String.isBlank(productName)) {
        productName = productRecord.Name;
      }
      return;
    }
    if (String.isBlank(productName)) {
      return;
    }
    productRecord = queryProductByName(productName);
  }

  private static Product2 queryProductById(String rawProductId) {
    Id productId;
    try {
      productId = Id.valueOf(rawProductId);
    } catch (Exception ex) {
      return null;
    }
    List<Product2> products = [
      SELECT Id, Name, Product_Image_URL__c, Therapy_Area__c
      FROM Product2
      WHERE Id = :productId AND IsActive = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return products.isEmpty() ? null : products[0];
  }

  private static Product2 queryProductByName(String name) {
    String trimmed = name.trim();
    List<Product2> exact = [
      SELECT Id, Name, Product_Image_URL__c, Therapy_Area__c
      FROM Product2
      WHERE Name = :trimmed AND IsActive = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!exact.isEmpty()) {
      return exact[0];
    }
    String likePattern = '%' + trimmed + '%';
    List<Product2> fuzzy = [
      SELECT Id, Name, Product_Image_URL__c, Therapy_Area__c
      FROM Product2
      WHERE Name LIKE :likePattern AND IsActive = TRUE
      WITH SYSTEM_MODE
      ORDER BY Name ASC
      LIMIT 1
    ];
    return fuzzy.isEmpty() ? null : fuzzy[0];
  }

  private static String resolveLinkedFileImageUrl(Id productId) {
    if (productId == null) {
      return null;
    }
    List<ContentDocumentLink> links = [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :productId
      WITH SYSTEM_MODE
      ORDER BY SystemModstamp DESC
      LIMIT 5
    ];
    if (links.isEmpty()) {
      return null;
    }
    Set<Id> documentIds = new Set<Id>();
    for (ContentDocumentLink link : links) {
      documentIds.add(link.ContentDocumentId);
    }
    List<ContentVersion> versions = [
      SELECT Id, FileExtension
      FROM ContentVersion
      WHERE ContentDocumentId IN :documentIds AND IsLatest = TRUE
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
    ];
    for (ContentVersion version : versions) {
      if (isImageExtension(version.FileExtension)) {
        return buildContentVersionUrl(version.Id);
      }
    }
    return null;
  }

  private static Boolean isImageExtension(String extension) {
    if (String.isBlank(extension)) {
      return false;
    }
    String normalized = extension.toLowerCase();
    return normalized == 'png' ||
      normalized == 'jpg' ||
      normalized == 'jpeg' ||
      normalized == 'gif' ||
      normalized == 'webp' ||
      normalized == 'svg';
  }

  private static String buildContentVersionUrl(Id contentVersionId) {
    String baseUrl = Site.getBaseUrl();
    if (String.isBlank(baseUrl)) {
      baseUrl = URL.getOrgDomainUrl().toExternalForm();
    }
    return baseUrl +
      '/sfc/servlet.shepherd/version/download/' +
      String.valueOf(contentVersionId);
  }
}
