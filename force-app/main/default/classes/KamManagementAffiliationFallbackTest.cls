@IsTest
private class KamManagementAffiliationFallbackTest {
    @IsTest
    static void dashboard_populatesFromAffiliationsWhenNoAccountPlans() {
        Account keyAccount = new Account(Name = 'KAM Fallback Hospital');
        Account stakeholder = new Account(Name = 'KAM Fallback Stakeholder');
        Database.insert(new List<Account>{ keyAccount, stakeholder }, AccessLevel.SYSTEM_MODE);
        Database.insert(
            new Account_Affiliation__c(
                Primary_Account__c = keyAccount.Id,
                Related_Account__c = stakeholder.Id,
                Affiliation_Type__c = 'Practice',
                Role__c = 'Physician',
                Is_Active__c = true,
                External_ID__c = 'kam_fb_' + keyAccount.Id
            ),
            AccessLevel.SYSTEM_MODE
        );

        if (Schema.sObjectType.Visit__c.isCreateable()) {
            Database.insert(
                new Visit__c(
                    Account__c = keyAccount.Id,
                    Status__c = 'Completed',
                    Visit_Date__c = Datetime.now().addDays(-2)
                ),
                AccessLevel.SYSTEM_MODE
            );
        }

        Test.startTest();
        KamManagementService.DashboardPayload dashboard = KamManagementService.buildDashboard('All');
        Test.stopTest();

        System.assertNotEquals(null, dashboard);
        System.assert(dashboard.portfolio.accountsTracked > 0, 'Expected affiliation-backed portfolio');
        Boolean found = false;
        for (KamManagementService.AccountTableRow row : dashboard.topAccounts) {
            if (row.accountId == keyAccount.Id) {
                found = true;
                break;
            }
        }
        System.assertEquals(true, found, 'Expected fallback hospital in top accounts');
        System.assert(dashboard.planBuckets.size() > 0, 'Expected plan buckets');
        System.assert(dashboard.stakeholderRoles.size() > 0, 'Expected role segments');
    }
}