/**
 * @description Data-completeness scoring for duplicate candidate ranking in CRM Hub.
 */
public with sharing class HubRecordCompletenessScore {
  public class Factor {
    public String label;
    public Integer delta;
    public String polarity;

    public Factor(String label, Integer delta) {
      this.label = label;
      this.delta = delta;
      if (delta > 0) {
        this.polarity = '+';
      } else if (delta < 0) {
        this.polarity = '-';
      } else {
        this.polarity = '0';
      }
    }

    public Map<String, Object> toMap() {
      return new Map<String, Object>{
        'label' => label,
        'delta' => delta,
        'polarity' => polarity
      };
    }
  }

  public class Result {
    public Integer score;
    public String band;
    public Integer filledFieldCount;
    public Integer totalScorableFields;
    public List<Factor> factors;

    public Result(Integer score, String band, Integer filled, Integer total, List<Factor> factors) {
      this.score = score;
      this.band = band;
      this.filledFieldCount = filled;
      this.totalScorableFields = total;
      this.factors = factors == null ? new List<Factor>() : factors;
    }

    public Map<String, Object> toMap() {
      List<Map<String, Object>> factorMaps = new List<Map<String, Object>>();
      for (Factor f : factors) {
        factorMaps.add(f.toMap());
      }
      return new Map<String, Object>{
        'completenessScore' => score,
        'completenessBand' => band,
        'filledFieldCount' => filledFieldCount,
        'totalScorableFields' => totalScorableFields,
        'factors' => factorMaps
      };
    }
  }

  public static Result scoreRecord(SObject rec, String objectApi) {
    if (rec == null || String.isBlank(objectApi)) {
      return finalizeScore(0, 0, 0, new List<Factor>());
    }
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApi)
      .getDescribe()
      .fields.getMap();
    List<Factor> factors = new List<Factor>();
    Integer filled = 0;
    Integer total = 0;

    for (Schema.SObjectField token : fieldMap.values()) {
      Schema.DescribeFieldResult fd = token.getDescribe();
      if (!isScorableField(fd)) {
        continue;
      }
      total++;
      Object val;
      try {
        val = rec.get(fd.getName());
      } catch (SObjectException e) {
        // Field not in queried row — skip without failing score.
        total--;
        continue;
      }
      if (isPopulated(val, fd.getName(), objectApi)) {
        filled++;
        Integer weight = fieldWeight(fd.getName(), objectApi);
        if (weight > 0) {
          factors.add(new Factor('Has ' + fd.getLabel(), weight));
        }
      } else if (isImportantField(fd.getName(), objectApi)) {
        factors.add(new Factor('Missing ' + fd.getLabel(), -3));
      }
    }

    Integer pct = total == 0 ? 0 : Math.round((Decimal.valueOf(filled) / Decimal.valueOf(total)) * 100);
    return finalizeScore(pct, filled, total, factors);
  }

  @TestVisible
  private static Boolean isScorableField(Schema.DescribeFieldResult fd) {
    if (fd.isCalculated() || fd.isAutoNumber() || fd.isDeprecatedAndHidden()) {
      return false;
    }
    Schema.DisplayType dt = fd.getType();
    if (dt == Schema.DisplayType.ID || dt == Schema.DisplayType.BASE64) {
      return false;
    }
    return true;
  }

  @TestVisible
  private static Boolean isPopulated(Object val, String fieldApi, String objectApi) {
    if (val == null) {
      return false;
    }
    if (val instanceof String) {
      String s = ((String) val).trim();
      if (String.isBlank(s) || s == 'null') {
        return false;
      }
      if ('Name'.equalsIgnoreCase(fieldApi) || fieldApi.endsWith('Name__c')) {
        if (Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', s)) {
          return false;
        }
      }
    }
    return true;
  }

  @TestVisible
  private static Boolean isImportantField(String fieldApi, String objectApi) {
    Set<String> important = importantFieldsFor(objectApi);
    return important.contains(fieldApi);
  }

  @TestVisible
  private static Integer fieldWeight(String fieldApi, String objectApi) {
    Set<String> important = importantFieldsFor(objectApi);
    return important.contains(fieldApi) ? 5 : 1;
  }

  @TestVisible
  private static Set<String> importantFieldsFor(String objectApi) {
    if ('Contact'.equals(objectApi) || 'Lead'.equals(objectApi)) {
      return new Set<String>{
        'Name',
        'Email',
        'Phone',
        'Title',
        'Company',
        'AccountId',
        'TrailheadProfileURL__c',
        'Link_to_CV__c'
      };
    }
    if ('Account'.equals(objectApi)) {
      return new Set<String>{ 'Name', 'Website', 'Phone', 'Industry', 'BillingStreet', 'BillingCity' };
    }
    if ('Job_Application__c'.equals(objectApi)) {
      return new Set<String>{
        'Name',
        'ApplicantName__c',
        'Status__c',
        'Lead__c',
        'Contact__c',
        'Position__c'
      };
    }
    return new Set<String>{ 'Name' };
  }

  @TestVisible
  private static Result finalizeScore(Integer pct, Integer filled, Integer total, List<Factor> factors) {
    Integer clamped = Math.max(0, Math.min(100, pct));
    String band;
    if (clamped >= 75) {
      band = 'Strong';
    } else if (clamped >= 55) {
      band = 'Promising';
    } else if (clamped >= 35) {
      band = 'Watch';
    } else {
      band = 'Risk';
    }
    return new Result(clamped, band, filled, total, factors);
  }
}
