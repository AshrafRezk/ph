public with sharing class PharmacySalesInsightsTypes {
    public static final String REC_ENSURE_PLAN = 'EnsurePlan';
    public static final String REC_UPDATE_PLAN_TARGET = 'UpdatePlanTarget';
    public static final String REC_CREATE_VISIT = 'CreateVisit';
    public static final String REC_UPDATE_ACCOUNT_RATING = 'UpdateAccountRating';
    public static final String REC_UPDATE_VISION = 'UpdateVision';

    public class FilterInput {
        @AuraEnabled public Date startMonth;
        @AuraEnabled public Date endMonth;
        @AuraEnabled public String dataSource;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public String productFamily;
        @AuraEnabled public Id brickId;
        @AuraEnabled public List<Id> pharmacyIds;
        @AuraEnabled public List<Id> repIds;
    }

    public class RepOption {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
        @AuraEnabled public String territoryName;
    }

    public class TerritoryOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class VisionDraft {
        @AuraEnabled public Id id;
        @AuraEnabled public String territory2Id;
        @AuraEnabled public Date effectiveMonth;
        @AuraEnabled public String visionSummary;
        @AuraEnabled public String focusTherapyAreas;
        @AuraEnabled public String focusProductFamilies;
        @AuraEnabled public String classificationVisitWeights;
    }

    public class InsightsContext {
        @AuraEnabled public List<RepOption> reps;
        @AuraEnabled public List<TerritoryOption> territories;
        @AuraEnabled public VisionDraft vision;
        @AuraEnabled public FilterInput filters;
    }

    public class TrendCard {
        @AuraEnabled public String id;
        @AuraEnabled public String category;
        @AuraEnabled public String title;
        @AuraEnabled public String metric;
        @AuraEnabled public String direction;
        @AuraEnabled public String narrative;
    }

    public class RecommendationPayload {
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id targetId;
        @AuraEnabled public Id territory2Id;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public Integer planYear;
        @AuraEnabled public Integer planMonth;
        @AuraEnabled public Decimal targetVisitFrequency;
        @AuraEnabled public DateTime visitStart;
        @AuraEnabled public DateTime visitEnd;
        @AuraEnabled public String potential;
        @AuraEnabled public String penetration;
        @AuraEnabled public String visionSummary;
        @AuraEnabled public String focusTherapyAreas;
        @AuraEnabled public String focusProductFamilies;
        @AuraEnabled public String classificationVisitWeights;
    }

    public class RecommendationRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String key;
        @AuraEnabled public String recommendationType;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public Id targetUserId;
        @AuraEnabled public String targetUserName;
        @AuraEnabled public RecommendationPayload payload;
        @AuraEnabled public Integer sortOrder;
        @AuraEnabled public Boolean selected;
    }

    public class InsightsPayload {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String headline;
        @AuraEnabled public String marketSummary;
        @AuraEnabled public String brandSummary;
        @AuraEnabled public String planSummary;
        @AuraEnabled public List<TrendCard> marketTrends;
        @AuraEnabled public List<TrendCard> brandTrends;
        @AuraEnabled public List<RecommendationRow> recommendations;
        @AuraEnabled public VisionDraft vision;
    }

    public class RecommendationEdit {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public RecommendationPayload payload;
        @AuraEnabled public Boolean selected;
    }

    public class ApplyResult {
        @AuraEnabled public Integer appliedCount;
        @AuraEnabled public Integer failedCount;
        @AuraEnabled public String message;
        @AuraEnabled public List<RecommendationRow> recommendations;
    }

    public class AnalysisContext {
        public PharmacySalesAnalyticsController.DashboardData dashboardData;
        public PharmacySalesAnalyticsController.DashboardFilterInput dashboardFilters;
        public Map<Id, String> brickNames = new Map<Id, String>();
        public Map<Id, String> brickTerritoryIds = new Map<Id, String>();
        public Map<String, Set<Id>> repsByTerritory = new Map<String, Set<Id>>();
        public Map<Id, String> repNames = new Map<Id, String>();
        public Map<Id, Decimal> brickRevenueDelta = new Map<Id, Decimal>();
        public List<PlanGapRow> planGaps = new List<PlanGapRow>();
        public List<AffiliationLink> affiliationLinks = new List<AffiliationLink>();
        public VisionDraft visionDraft;
        public Set<Id> scopedRepIds = new Set<Id>();
        public Date nextPlanMonth;
    }

    public class PlanGapRow {
        public Id employeeId;
        public String employeeName;
        public Id accountId;
        public String accountName;
        public String classification;
        public String frequencyStatus;
        public Decimal targetFrequency;
        public Decimal actualVisits;
        public Id targetId;
        public Id timeCardId;
        public String territory2Id;
    }

    public class AffiliationLink {
        public Id pharmacyId;
        public String pharmacyName;
        public Id relatedAccountId;
        public String relatedAccountName;
        public String territory2Id;
    }
}
