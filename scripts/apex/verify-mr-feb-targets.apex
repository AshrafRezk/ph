Map<String, String> mrTerr = new Map<String, String>{
    'git_mr' => 'TERR_GIT_DM_1_MR_1',
    'diabetes_mr' => 'TERR_DIABETES_DM_1_MR_1',
    'cluster_mr' => 'TERR_CLUSTER_DM_1_MR_1',
    'chc_mr' => 'TERR_CHC_DM_1_MR_1',
    'cardio_mr' => 'TERR_CARDIO_DM_1_MR_1',
    'gastro_mr' => 'TERR_GASTRO_DM_1_MR_1'
};
Date febStart = Date.newInstance(2026, 2, 1);
for (String mrKey : mrTerr.keySet()) {
    Id userId = [SELECT Id FROM User WHERE Username = :mrKey.replace('_', '.') + '@pharma.demo' LIMIT 1].Id;
    Id terrId = [SELECT Id FROM Territory2 WHERE External_ID__c = :mrTerr.get(mrKey) LIMIT 1].Id;
    Integer atf = [SELECT COUNT() FROM Account_Territory_Fields__c WHERE Is_Active__c = true AND Territory2_Id__c = :String.valueOf(terrId)];
    Employee_Time_Card__c c = [SELECT Id, Target_Customers__c FROM Employee_Time_Card__c WHERE Employee__c = :userId AND Time_Card_Month_Start_Date__c = :febStart LIMIT 1];
    Integer childTargets = [SELECT COUNT() FROM Employee_Time_Card_Account_Target__c WHERE Employee_Time_Card__c = :c.Id];
    System.debug(mrKey + ' hcpAtf=' + atf + ' childTargets=' + childTargets + ' rollup=' + c.Target_Customers__c.intValue());
}
