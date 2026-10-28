trigger EmployeeExpenseSubmissionTrigger on Employee_Expense__c (after insert, after update) {
    DistrictManagerNotifier.onExpenses(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}