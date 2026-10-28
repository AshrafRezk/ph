@IsTest(isParallel=false)
private class TotTeamCoverageServiceTest {
    @IsTest
    static void computeDayTotals_availableAndFlags() {
        TotTeamCoverageService.DayTotals under = TotTeamCoverageService.computeDayTotals(22, 1.5);
        Assert.areEqual(20.5, under.availableWorkingDays);
        Assert.isFalse(under.frequencyImpacted);
        Assert.isFalse(under.longTermLeave);

        TotTeamCoverageService.DayTotals underThreshold = TotTeamCoverageService.computeDayTotals(22, 4);
        Assert.areEqual(18, underThreshold.availableWorkingDays);
        Assert.isFalse(underThreshold.frequencyImpacted);

        TotTeamCoverageService.DayTotals over = TotTeamCoverageService.computeDayTotals(22, 7);
        Assert.areEqual(15, over.availableWorkingDays);
        Assert.isTrue(over.frequencyImpacted);
        Assert.areEqual(
            'TOT >= 7 days — target calls pro-rated to the working days left',
            TotTeamCoverageService.frequencyStatusLabel(true)
        );

        TotTeamCoverageService.DayTotals longLeave = TotTeamCoverageService.computeDayTotals(60, 45);
        Assert.isTrue(longLeave.longTermLeave);
        Assert.areEqual(0, TotTeamCoverageService.computeDayTotals(5, 9).availableWorkingDays);
    }

    @IsTest
    static void totAdjustedCoverage_proratesDenominator() {
        // 80 visited of 100 target, half month available → expected capacity 50 → 160%
        Decimal adjusted = TotTeamCoverageService.totAdjustedCoverage(80, 100, 0.5);
        Assert.areEqual(1.6, adjusted);
        Assert.areEqual(0, TotTeamCoverageService.totAdjustedCoverage(10, 0, 1));
    }

    @IsTest
    static void getTeamCoverage_andRollup_withTimeCard() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User managerUser = new User(
            Alias = 'tcvm',
            Email = 'tot.cov.mgr.' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'CovMgr',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'tot.cov.mgr.' + suffix + '@example.com'
        );
        User repUser = new User(
            Alias = 'tcvr',
            Email = 'tot.cov.rep.' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'CovRep',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'tot.cov.rep.' + suffix + '@example.com'
        );
        insert new List<User>{ managerUser, repUser };
        repUser.ManagerId = managerUser.Id;
        update repUser;

        Date monthStart = Date.today().toStartOfMonth();
        Employee_Time_Card__c card = new Employee_Time_Card__c(
            Employee__c = repUser.Id,
            Time_Card_Month_Start_Date__c = monthStart,
            Time_Card_Month_End_Date__c = monthStart.addMonths(1).addDays(-1),
            Active_Time_Card__c = true,
            Unique_Identifier__c = String.valueOf(repUser.Id) + ':totcov:' + String.valueOf(monthStart)
        );
        insert card;

        insert new List<Employee_Time_Card_Day_Entry__c>{
            new Employee_Time_Card_Day_Entry__c(
                Employee_Time_Card__c = card.Id,
                Date__c = monthStart,
                Calendar_Working_Days__c = 1,
                TOT_Days__c = 0
            ),
            new Employee_Time_Card_Day_Entry__c(
                Employee_Time_Card__c = card.Id,
                Date__c = monthStart.addDays(1),
                Calendar_Working_Days__c = 1,
                TOT_Days__c = 1
            ),
            new Employee_Time_Card_Day_Entry__c(
                Employee_Time_Card__c = card.Id,
                Date__c = monthStart.addDays(2),
                Calendar_Working_Days__c = 1,
                TOT_Days__c = 2
            )
        };

        Test.startTest();
        TotTeamCoverageService.rollupTimeCardWorkingDays(new Set<Id>{ card.Id });
        TotTeamCoverageService.TeamCoverageSummary summary;
        System.runAs(managerUser) {
            summary = TotTeamCoverageController.getTeamCoverageFrequencyForScope('ALL', 'ALL', 'ALL');
        }
        Assert.isNotNull(TerritoryHierarchyService.getBusinessUnitOptions());
        Assert.isNotNull(TerritoryHierarchyService.getLineOptions(null));
        Assert.isNotNull(TerritoryHierarchyService.getDistrictOptions(null));
        Test.stopTest();

        Employee_Time_Card__c rolled = [
            SELECT
                Calendar_Working_Days_Total__c,
                TOT_Days_Total__c,
                Available_Working_Days__c
            FROM Employee_Time_Card__c
            WHERE Id = :card.Id
        ];
        Assert.areEqual(3, rolled.Calendar_Working_Days_Total__c);
        Assert.areEqual(3, rolled.TOT_Days_Total__c);
        Assert.areEqual(0, rolled.Available_Working_Days__c);

        Assert.isNotNull(summary);
    }
}