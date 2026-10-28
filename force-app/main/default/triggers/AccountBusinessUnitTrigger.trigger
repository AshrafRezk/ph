trigger AccountBusinessUnitTrigger on Account_Business_Unit__c (
  before insert,
  before update
) {
  AccountBusinessUnitService.stampAndValidate(Trigger.new, Trigger.oldMap);
}