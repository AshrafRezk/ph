trigger DistributorSelloutAliasTrigger on Distributor_Sellout_Alias__c(before insert, before update) {
    DistributorSelloutBrickPlacement.apply(Trigger.new, Trigger.oldMap);
}
