/**
 * One-time (or on-demand) backfill of Employee_Time_Card_Day_Entry__c.Day_Definition__c
 * from each employee's User.Department (AM: Fri/Sat, PM: Thu/Fri weekends).
 *
 * Usage:
 *   Database.executeBatch(new EmployeeTimeCardDayDefinitionBatch(), 200);
 */
public with sharing class EmployeeTimeCardDayDefinitionBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Date__c, Day_Definition__c, Employee_Time_Card__r.Employee__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Date__c != NULL
              AND Employee_Time_Card__r.Employee__c != NULL
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        Set<Id> employeeIds = new Set<Id>();
        for (SObject so : scope) {
            Employee_Time_Card_Day_Entry__c entry = (Employee_Time_Card_Day_Entry__c) so;
            employeeIds.add(entry.Employee_Time_Card__r.Employee__c);
        }

        Map<Id, String> departmentByEmployee = new Map<Id, String>();
        for (User u : [SELECT Id, Department FROM User WHERE Id IN :employeeIds]) {
            departmentByEmployee.put(u.Id, u.Department);
        }

        List<Employee_Time_Card_Day_Entry__c> toUpdate = new List<Employee_Time_Card_Day_Entry__c>();
        for (SObject so : scope) {
            Employee_Time_Card_Day_Entry__c entry = (Employee_Time_Card_Day_Entry__c) so;
            String department = departmentByEmployee.get(entry.Employee_Time_Card__r.Employee__c);
            String definition = EmployeeTimeCardFlowHelper.getDayDefinition(entry.Date__c, department);
            if (entry.Day_Definition__c != definition) {
                entry.Day_Definition__c = definition;
                toUpdate.add(entry);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    public void finish(Database.BatchableContext bc) {
    }
}