/**
 * Calculates walk-in achievement percentages on Employee_Time_Card__c
 * without AssignedUserTargetRevenue__c.
 */
public without sharing class EmployeeTimeCardAchievementService {

    public class Request {
        @InvocableVariable(required=true label='Employee Time Card Id')
        public Id employeeTimeCardId;
    }

    @InvocableMethod(
        label='Recalculate Walk-in Achievements'
        description='Sets Walk_in_Revenue_Ach__c and Walk_in_Visits_Ach__c from actual / target on the time card.'
    )
    public static void recalculateAchievementsInvocable(List<Request> requests) {
        if (requests == null) {
            return;
        }
        Set<Id> cardIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.employeeTimeCardId != null) {
                cardIds.add(req.employeeTimeCardId);
            }
        }
        recalculateAchievements(cardIds);
    }

    public static void recalculateAchievements(Set<Id> employeeTimeCardIds) {
        if (employeeTimeCardIds == null || employeeTimeCardIds.isEmpty()) {
            return;
        }

        List<Employee_Time_Card__c> cards = [
            SELECT
                Id,
                Walk_in_Revenue__c,
                Walk_in_Revenue_Target__c,
                Walk_in_Visits__c,
                Walk_in_Visits_Target__c
            FROM Employee_Time_Card__c
            WHERE Id IN :employeeTimeCardIds
        ];

        List<Employee_Time_Card__c> updates = new List<Employee_Time_Card__c>();
        for (Employee_Time_Card__c card : cards) {
            updates.add(buildAchievementUpdate(card));
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    public static Employee_Time_Card__c buildAchievementUpdate(Employee_Time_Card__c card) {
        Employee_Time_Card__c updateRec = new Employee_Time_Card__c(Id = card.Id);
        updateRec.Walk_in_Revenue_Ach__c = achievementPercent(
            card.Walk_in_Revenue__c,
            card.Walk_in_Revenue_Target__c
        );
        updateRec.Walk_in_Visits_Ach__c = achievementPercent(
            card.Walk_in_Visits__c,
            card.Walk_in_Visits_Target__c
        );
        return updateRec;
    }

    public static Decimal achievementPercent(Decimal actual, Decimal target) {
        if (target == null || target == 0) {
            return 0;
        }
        if (actual == null) {
            actual = 0;
        }
        return ((actual / target) * 100).setScale(5);
    }
}
