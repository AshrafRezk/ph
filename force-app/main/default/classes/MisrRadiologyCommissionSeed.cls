public without sharing class MisrRadiologyCommissionSeed {

  public class SeedResult {
    public Integer timeCardCount = 0;
    public Integer fieldUpdateCount = 0;
    public String message;
  }

  private static final Map<String, Decimal> DEMO_SOLD = new Map<String, Decimal>{
    'MR_MRI_Sold__c' => 85000,
    'MR_Totum_MRI_Sold__c' => 42000,
    'MR_PET_MRI_Sold__c' => 31000,
    'MR_CT_Scan_Sold__c' => 120000,
    'MR_PET_CT_Sold__c' => 56000,
    'MR_Ultrasound_Sold__c' => 28000,
    'MR_Digital_XRay_Sold__c' => 15000,
    'MR_Fluoroscopy_Sold__c' => 12000,
    'MR_Breast_Imaging_Sold__c' => 22000,
    'MR_DEXA_Sold__c' => 9000,
    'MR_Isotope_Sold__c' => 18000,
    'MR_Womens_Health_Sold__c' => 14000,
    'MR_Dental_Imaging_Sold__c' => 8000,
    'MR_Other_Services_Sold__c' => 6000
  };

  private static final Map<String, String> SOLD_TO_TARGET_FIELD = new Map<String, String>{
    'MR_MRI_Sold__c' => 'MR_MRI_Target__c',
    'MR_Totum_MRI_Sold__c' => 'MR_Totum_MRI_Target__c',
    'MR_PET_MRI_Sold__c' => 'MR_PET_MRI_Target__c',
    'MR_CT_Scan_Sold__c' => 'MR_CT_Scan_Target__c',
    'MR_PET_CT_Sold__c' => 'MR_PET_CT_Target__c',
    'MR_Ultrasound_Sold__c' => 'MR_Ultrasound_Target__c',
    'MR_Digital_XRay_Sold__c' => 'MR_Digital_XRay_Target__c',
    'MR_Fluoroscopy_Sold__c' => 'MR_Fluoroscopy_Target__c',
    'MR_Breast_Imaging_Sold__c' => 'MR_Breast_Imaging_Target__c',
    'MR_DEXA_Sold__c' => 'MR_DEXA_Target__c',
    'MR_Isotope_Sold__c' => 'MR_Isotope_Target__c',
    'MR_Womens_Health_Sold__c' => 'MR_Womens_Health_Target__c',
    'MR_Dental_Imaging_Sold__c' => 'MR_Dental_Imaging_Target__c',
    'MR_Other_Services_Sold__c' => 'MR_Other_Services_Target__c'
  };

  /**
   * Seeds Misr Radiology sold/target values on the current user's monthly time card.
   */
  public static SeedResult seedDemoData() {
    return seedDemoDataForUser(UserInfo.getUserId());
  }

  public static SeedResult seedDemoDataForUser(Id employeeId) {
    SeedResult result = new SeedResult();
    if (employeeId == null) {
      result.message = 'Employee user id is required.';
      return result;
    }

    Date monthStart = Date.today().toStartOfMonth();
    Employee_Time_Card__c timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(
      employeeId,
      monthStart,
      true,
      true
    );
    if (timeCard == null) {
      result.message = 'Could not create or find a time card for the current month.';
      return result;
    }
    result.timeCardCount = 1;

    Employee_Time_Card__c updateCard = new Employee_Time_Card__c(Id = timeCard.Id);
    Integer fieldCount = 0;
    for (String soldField : DEMO_SOLD.keySet()) {
      String targetField = SOLD_TO_TARGET_FIELD.get(soldField);
      Decimal sold = DEMO_SOLD.get(soldField);
      Decimal target = sold * 1.25;
      updateCard.put(soldField, sold);
      updateCard.put(targetField, target);
      fieldCount += 2;
    }
    update as system updateCard;
    result.fieldUpdateCount = fieldCount;
    result.message = 'Seeded Misr Radiology sold/target values on time card ' + timeCard.Id;
    return result;
  }
}
