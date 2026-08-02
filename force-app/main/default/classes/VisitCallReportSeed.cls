public without sharing class VisitCallReportSeed {

    private static final List<String> MR_USER_KEYS = new List<String>{
        'git_mr',
        'diabetes_mr',
        'cluster_mr',
        'chc_mr',
        'cardio_mr',
        'gastro_mr'
    };

    public class SeedResult {
        public Integer visitCount;
        public Integer attendeeCount;
        public Integer productDetailCount;
        public Integer sampleInventoryCount;
        public Date weekStart;
        public Date weekEnd;
        public String message;
    }

    /**
     * Seeds planner-visible visits for the current week and next week for demo MR users.
     * Delegates to PlannerCalendarSeed for territory-aligned accounts, products, CLMs, and TOTs.
     */
    public static SeedResult seedCurrentAndNextWeekVisits() {
        PlannerCalendarSeed.SeedResult calendarResult = PlannerCalendarSeed.seedCurrentAndNextWeek();

        SeedResult result = new SeedResult();
        result.visitCount = calendarResult.visitCount;
        result.attendeeCount = calendarResult.attendeeCount;
        result.productDetailCount = calendarResult.productDetailCount;
        result.weekStart = calendarResult.weekStart;
        result.weekEnd = calendarResult.weekEnd;
        result.sampleInventoryCount = 0;

        Map<String, Id> userIds = resolveUserIds();
        if (!userIds.isEmpty()) {
            List<Product2> products = [
                SELECT Id, Name
                FROM Product2
                WHERE IsActive = TRUE
                WITH SYSTEM_MODE
                ORDER BY Name ASC
                LIMIT 10
            ];
            result.sampleInventoryCount = seedSampleInventory(new Set<Id>(userIds.values()), products);
        }

        result.message = calendarResult.message;
        if (result.sampleInventoryCount > 0) {
            result.message += ' Sample inventory rows: ' + result.sampleInventoryCount + '.';
        }
        return result;
    }

    private static Integer seedSampleInventory(Set<Id> repIds, List<Product2> products) {
        if (products.isEmpty()) {
            return 0;
        }

        List<Sample_Inventory__c> inventory = new List<Sample_Inventory__c>();
        Integer lotCounter = 1;
        for (Id repId : repIds) {
            for (Product2 product : products) {
                if (inventory.size() >= 20) {
                    break;
                }
                inventory.add(new Sample_Inventory__c(
                    Product2__c = product.Id,
                    Lot_Number__c = 'LOT-' + String.valueOf(lotCounter).leftPad(3, '0'),
                    Quantity_On_Hand__c = 25,
                    Expiry_Date__c = Date.today().addMonths(9),
                    Owner_User__c = repId
                ));
                lotCounter++;
            }
        }

        if (inventory.isEmpty()) {
            return 0;
        }
        insert as system inventory;
        return inventory.size();
    }

    private static Map<String, Id> resolveUserIds() {
        Map<String, Id> result = new Map<String, Id>();
        Set<String> usernames = new Set<String>();
        for (String mrKey : MR_USER_KEYS) {
            usernames.add(mrKey.replace('_', '.') + '@pharma.demo');
        }
        for (User u : [
            SELECT Id, Username
            FROM User
            WHERE Username IN :usernames AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            String key = u.Username.substringBefore('@').replace('.', '_');
            result.put(key, u.Id);
        }
        return result;
    }
}
