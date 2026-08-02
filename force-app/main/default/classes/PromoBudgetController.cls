public with sharing class PromoBudgetController {

    public class BudgetRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String businessUnit;
        @AuraEnabled public String department;
        @AuraEnabled public String fiscalYear;
        @AuraEnabled public Decimal allocated;
        @AuraEnabled public Decimal spent;
        @AuraEnabled public Decimal remaining;
        @AuraEnabled public Decimal utilizationPercent;
        @AuraEnabled public List<LineRow> lines;
    }

    public class LineRow {
        @AuraEnabled public String brand;
        @AuraEnabled public String campaign;
        @AuraEnabled public String projectName;
        @AuraEnabled public String territory;
        @AuraEnabled public Decimal amount;
    }

    @AuraEnabled(cacheable=true)
    public static List<BudgetRow> getBudgets(String businessUnit) {
        String bu = String.isBlank(businessUnit) || businessUnit == 'ALL' ? null : businessUnit;
        String soql = 'SELECT Id, Name, Business_Unit__c, Department__c, Fiscal_Year__c,'
            + ' Allocated_Amount__c, Spent_Amount__c, Remaining_Amount__c'
            + ' FROM Promo_Budget__c WHERE Id != null';
        if (bu != null) {
            soql += ' AND Business_Unit__c = :bu';
        }
        soql += ' ORDER BY Business_Unit__c, Department__c LIMIT 100';

        List<Promo_Budget__c> budgets = Database.query(soql);
        Set<Id> budgetIds = new Map<Id, Promo_Budget__c>(budgets).keySet();
        Map<Id, List<LineRow>> linesByBudget = loadLines(budgetIds);

        List<BudgetRow> rows = new List<BudgetRow>();
        for (Promo_Budget__c b : budgets) {
            BudgetRow row = new BudgetRow();
            row.id = b.Id;
            row.name = b.Name;
            row.businessUnit = b.Business_Unit__c;
            row.department = b.Department__c;
            row.fiscalYear = b.Fiscal_Year__c;
            row.allocated = b.Allocated_Amount__c;
            row.spent = b.Spent_Amount__c;
            row.remaining = b.Remaining_Amount__c;
            Decimal alloc = b.Allocated_Amount__c == null ? 0 : b.Allocated_Amount__c;
            Decimal spent = b.Spent_Amount__c == null ? 0 : b.Spent_Amount__c;
            row.utilizationPercent = alloc > 0 ? (spent / alloc) * 100 : 0;
            row.lines = linesByBudget.containsKey(b.Id) ? linesByBudget.get(b.Id) : new List<LineRow>();
            rows.add(row);
        }
        return rows;
    }

    private static Map<Id, List<LineRow>> loadLines(Set<Id> budgetIds) {
        Map<Id, List<LineRow>> result = new Map<Id, List<LineRow>>();
        if (budgetIds.isEmpty()) {
            return result;
        }
        for (Promo_Budget_Line__c line : [
            SELECT Promo_Budget__c, Brand__c, Campaign__c, Pharma_Project__c,
                Pharma_Project__r.Name, Territory__c, Amount__c
            FROM Promo_Budget_Line__c
            WHERE Promo_Budget__c IN :budgetIds
            WITH SYSTEM_MODE
        ]) {
            if (!result.containsKey(line.Promo_Budget__c)) {
                result.put(line.Promo_Budget__c, new List<LineRow>());
            }
            LineRow row = new LineRow();
            row.brand = line.Brand__c;
            row.campaign = line.Campaign__c;
            row.projectName = line.Pharma_Project__r != null ? line.Pharma_Project__r.Name : null;
            row.territory = line.Territory__c;
            row.amount = line.Amount__c;
            result.get(line.Promo_Budget__c).add(row);
        }
        return result;
    }
}
