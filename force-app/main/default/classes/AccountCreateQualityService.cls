/**
 * New Account wizard: required-field validation and live Data Quality Score.
 *
 * Score (0-100), documented for the LWC progress ring:
 *   Required bundle (all of the following) = 45  -> Fair / save enabled
 *     name, classification (Specialty 1 / Pharmacy Type / Institution Type),
 *     148 brick, 702 brick, at least 1 unique phone, detailed address, map pin,
 *     building, governorate, landmark (alama momayaza)
 *   Bonuses (duplicate phones never count):
 *     +12 2nd unique phone channel
 *     +10 3rd unique phone channel
 *     +12 Specialty 2 (HCP only)
 *     +10 Specialty 3 (HCP only)
 *     +11 email
 *   Cap 100. Labels: Fair < 50, Good 50-74, Excellent >= 75.
 *
 * Phone lookup is Cloudastick Map Intelligence (Google Places + Nominatim),
 * not Truecaller / Getcontact.
 */
public with sharing class AccountCreateQualityService {
  public static final Integer BASELINE_SCORE = 45;
  public static final Integer BONUS_PHONE_2 = 12;
  public static final Integer BONUS_PHONE_3 = 10;
  public static final Integer BONUS_SPECIALTY_2 = 12;
  public static final Integer BONUS_SPECIALTY_3 = 10;
  public static final Integer BONUS_EMAIL = 11;

  private static final Set<String> HCP_RECORD_TYPES = new Set<String>{
    'SDO_PersonAccounts',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact'
  };
  private static final Set<String> PHARMACY_RECORD_TYPES = new Set<String>{ 'Pharmacy' };
  private static final Set<String> HCO_RECORD_TYPES = new Set<String>{ 'Institution_HCO' };

  public static final List<String> EGYPT_GOVERNORATES = new List<String>{
    'Cairo',
    'Giza',
    'Alexandria',
    'Qalyubia',
    'Sharqia',
    'Dakahlia',
    'Beheira',
    'Monufia',
    'Gharbia',
    'Kafr El Sheikh',
    'Damietta',
    'Port Said',
    'Ismailia',
    'Suez',
    'North Sinai',
    'South Sinai',
    'Fayoum',
    'Beni Suef',
    'Minya',
    'Assiut',
    'Sohag',
    'Qena',
    'Luxor',
    'Aswan',
    'Red Sea',
    'New Valley',
    'Matrouh'
  };

  public class QualityScore {
    @AuraEnabled
    public Integer score;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean canSave;
    @AuraEnabled
    public List<String> missingRequired;
    @AuraEnabled
    public List<String> extrasToImprove;
    @AuraEnabled
    public Boolean duplicatePhones;
    @AuraEnabled
    public String duplicatePhoneMessage;
    @AuraEnabled
    public Integer uniquePhoneCount;
  }

  public static QualityScore evaluate(AccountsTabController.WizardCreateInput input) {
    QualityScore result = new QualityScore();
    result.missingRequired = new List<String>();
    result.extrasToImprove = new List<String>();
    result.score = 0;
    result.uniquePhoneCount = 0;
    result.duplicatePhones = false;
    if (input == null) {
      result.missingRequired.add('Record type');
      result.label = 'Fair';
      result.canSave = false;
      return result;
    }

    String developerName = recordTypeDeveloperName(input.recordTypeId);
    Boolean isPerson = input.recordTypeId != null &&
      AccountMasterImportUtil.isPersonRecordType(input.recordTypeId);
    Boolean isHcp = HCP_RECORD_TYPES.contains(developerName);
    Boolean isPharmacy = PHARMACY_RECORD_TYPES.contains(developerName);
    Boolean isHco = HCO_RECORD_TYPES.contains(developerName);

    Boolean hasName = isPerson
      ? String.isNotBlank(input.lastName)
      : String.isNotBlank(input.name);
    if (!hasName) {
      result.missingRequired.add(isPerson ? 'Last name' : 'Name');
    }

    Boolean hasClassification = false;
    if (isHcp) {
      hasClassification = String.isNotBlank(input.specialty1);
      if (!hasClassification) {
        result.missingRequired.add('Specialty 1');
      }
    } else if (isPharmacy) {
      hasClassification = String.isNotBlank(input.pharmacyType);
      if (!hasClassification) {
        result.missingRequired.add('Pharmacy type');
      }
    } else if (isHco) {
      hasClassification = String.isNotBlank(input.institutionType);
      if (!hasClassification) {
        result.missingRequired.add('Institution type');
      }
    } else {
      hasClassification =
        String.isNotBlank(input.specialty1) ||
        String.isNotBlank(input.pharmacyType) ||
        String.isNotBlank(input.institutionType);
      if (!hasClassification) {
        result.missingRequired.add('Specialty or type');
      }
    }

    if (input.brick148Id == null) {
      result.missingRequired.add('148 brick');
    }
    if (input.brick702Id == null) {
      result.missingRequired.add('702 brick');
    }
    if (String.isBlank(input.street)) {
      result.missingRequired.add('Detailed address');
    }
    if (input.latitude == null || input.longitude == null) {
      result.missingRequired.add('Map pin');
    }
    if (String.isBlank(input.building)) {
      result.missingRequired.add('Building');
    }
    if (String.isBlank(input.governorate)) {
      result.missingRequired.add('Governorate');
    }
    if (String.isBlank(input.landmark)) {
      result.missingRequired.add('????? ?????');
    }

    List<String> uniquePhones = uniqueNormalizedPhones(
      input.whatsappNumber,
      input.phone,
      input.clinicPhone
    );
    result.uniquePhoneCount = uniquePhones.size();
    result.duplicatePhones = hasDuplicatePhones(
      input.whatsappNumber,
      input.phone,
      input.clinicPhone
    );
    if (result.duplicatePhones) {
      result.duplicatePhoneMessage =
        'The same number is in more than one field. Duplicates do not raise the data quality score.';
    }
    if (uniquePhones.isEmpty()) {
      result.missingRequired.add('At least one contact number (WhatsApp, phone, or clinic)');
    }

    result.canSave = result.missingRequired.isEmpty();
    if (result.canSave) {
      result.score = BASELINE_SCORE;
      if (result.uniquePhoneCount >= 2) {
        result.score += BONUS_PHONE_2;
      } else {
        result.extrasToImprove.add('Add a second unique phone channel (+12)');
      }
      if (result.uniquePhoneCount >= 3) {
        result.score += BONUS_PHONE_3;
      } else if (result.uniquePhoneCount >= 2) {
        result.extrasToImprove.add('Add a third unique phone channel (+10)');
      }
      if (isHcp) {
        if (String.isNotBlank(input.specialty2)) {
          result.score += BONUS_SPECIALTY_2;
        } else {
          result.extrasToImprove.add('Add a second specialty (+12)');
        }
        if (String.isNotBlank(input.specialty3)) {
          result.score += BONUS_SPECIALTY_3;
        } else {
          result.extrasToImprove.add('Add a third specialty (+10)');
        }
      }
      if (String.isNotBlank(input.email)) {
        result.score += BONUS_EMAIL;
      } else {
        result.extrasToImprove.add('Add an email (+11)');
      }
      if (result.score > 100) {
        result.score = 100;
      }
    } else {
      Integer filled = 10 - result.missingRequired.size();
      if (filled < 0) {
        filled = 0;
      }
      result.score = (filled * BASELINE_SCORE) / 10;
    }

    if (result.score >= 75) {
      result.label = 'Excellent';
    } else if (result.score >= 50) {
      result.label = 'Good';
    } else {
      result.label = 'Fair';
    }
    return result;
  }

  public static void assertCanSave(AccountsTabController.WizardCreateInput input) {
    QualityScore score = evaluate(input);
    if (!score.canSave) {
      throw new AuraHandledException(
        'Complete required fields before saving: ' + String.join(score.missingRequired, ', ') + '.'
      );
    }
  }

  public static String normalizeEgyptPhone(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String digits = raw.replaceAll('[^0-9]', '');
    if (digits.length() < 8) {
      return raw.trim().left(40);
    }
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('20') && digits.length() >= 11) {
      return ('+' + digits).left(40);
    }
    if (digits.startsWith('0') && digits.length() >= 9) {
      return ('+20' + digits.substring(1)).left(40);
    }
    if (digits.startsWith('1') && digits.length() == 10) {
      return ('+20' + digits).left(40);
    }
    return ('+20' + digits).left(40);
  }

  public static String phoneDigits(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String digits = raw.replaceAll('[^0-9]', '');
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('20') && digits.length() >= 11) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('0') && digits.length() >= 9) {
      digits = digits.substring(1);
    }
    return String.isBlank(digits) ? null : digits;
  }

  public static Boolean looksLikePhoneQuery(String query) {
    if (String.isBlank(query)) {
      return false;
    }
    String digits = query.replaceAll('[^0-9]', '');
    if (digits.length() < 8) {
      return false;
    }
    String stripped = query.replaceAll('[\\s().+\\-]', '');
    return Pattern.matches('^[0-9]+$', stripped);
  }

  public static List<String> uniqueNormalizedPhones(String whatsapp, String phone, String clinic) {
    List<String> unique = new List<String>();
    Set<String> seen = new Set<String>();
    for (String raw : new List<String>{ whatsapp, phone, clinic }) {
      String digits = phoneDigits(raw);
      if (String.isBlank(digits) || seen.contains(digits)) {
        continue;
      }
      seen.add(digits);
      unique.add(digits);
    }
    return unique;
  }

  public static Boolean hasDuplicatePhones(String whatsapp, String phone, String clinic) {
    List<String> filled = new List<String>();
    for (String raw : new List<String>{ whatsapp, phone, clinic }) {
      String digits = phoneDigits(raw);
      if (String.isNotBlank(digits)) {
        filled.add(digits);
      }
    }
    return filled.size() > uniqueNormalizedPhones(whatsapp, phone, clinic).size();
  }

  public static List<String> egyptPhoneSearchQueries(String raw) {
    List<String> queries = new List<String>();
    if (!looksLikePhoneQuery(raw)) {
      return queries;
    }
    String e164 = normalizeEgyptPhone(raw);
    String digits = phoneDigits(raw);
    if (String.isNotBlank(e164)) {
      queries.add(e164);
    }
    if (String.isNotBlank(e164) && e164.startsWith('+')) {
      queries.add(e164.substring(1));
    }
    if (String.isNotBlank(digits)) {
      queries.add('0' + digits);
      queries.add(digits);
    }
    return queries;
  }

  public static Boolean phonesMatch(String left, String right) {
    String a = phoneDigits(left);
    String b = phoneDigits(right);
    if (String.isBlank(a) || String.isBlank(b)) {
      return false;
    }
    if (a == b) {
      return true;
    }
    Integer take = Math.min(a.length(), b.length());
    if (take < 8) {
      return false;
    }
    return a.right(8) == b.right(8);
  }

  public static String recordTypeDeveloperName(Id recordTypeId) {
    if (recordTypeId == null) {
      return null;
    }
    for (Schema.RecordTypeInfo info : Account.SObjectType.getDescribe().getRecordTypeInfos()) {
      if (info.getRecordTypeId() == recordTypeId) {
        return info.getDeveloperName();
      }
    }
    return null;
  }

  public static Boolean isHcpRecordType(String developerName) {
    return HCP_RECORD_TYPES.contains(developerName);
  }

  public static Boolean isPharmacyRecordType(String developerName) {
    return PHARMACY_RECORD_TYPES.contains(developerName);
  }

  public static Boolean isHcoRecordType(String developerName) {
    return HCO_RECORD_TYPES.contains(developerName);
  }
}
