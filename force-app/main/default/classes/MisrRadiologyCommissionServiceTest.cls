@IsTest
private class MisrRadiologyCommissionServiceTest {

    @IsTest
    static void achievementFactor_capsAtOne() {
        System.assertEquals(0.8, MisrRadiologyCommissionService.achievementFactor(80000, 100000));
        System.assertEquals(1, MisrRadiologyCommissionService.achievementFactor(120000, 100000));
        System.assertEquals(0, MisrRadiologyCommissionService.achievementFactor(50000, 0));
    }

    @IsTest
    static void achievementPercent_calculatesCorrectly() {
        System.assertEquals(80, MisrRadiologyCommissionService.achievementPercent(80000, 100000));
        System.assertEquals(0, MisrRadiologyCommissionService.achievementPercent(50000, 0));
    }

    @IsTest
    static void getCommissionDetail_returnsProportionalCommission() {
        Date monthStart = Date.newInstance(2026, 6, 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        Employee_Time_Card__c timeCard = new Employee_Time_Card__c(
            Employee__c = UserInfo.getUserId(),
            Time_Card_Month_Start_Date__c = monthStart,
            Time_Card_Month_End_Date__c = monthEnd,
            Active_Time_Card__c = true,
            Unique_Identifier__c = UserInfo.getUserId() + ':2026-6-1',
            Territory__c = 'Misr Radiology Test',
            MR_MRI_Sold__c = 80000,
            MR_MRI_Target__c = 100000
        );
        insert timeCard;

        Test.startTest();
        MisrRadiologyCommissionService.CommissionDetailResult detail = MisrRadiologyCommissionService.getCommissionDetail(
            UserInfo.getUserId(),
            2026,
            6
        );
        Test.stopTest();

        System.assertEquals(true, detail.hasTimeCard);
        System.assertNotEquals(null, detail.services);
        System.assert(detail.services.size() > 0, 'Expected service rows from custom metadata.');

        MisrRadiologyCommissionService.ServiceCommissionRow mriRow;
        for (MisrRadiologyCommissionService.ServiceCommissionRow row : detail.services) {
            if (row.serviceKey == 'mri') {
                mriRow = row;
                break;
            }
        }
        System.assertNotEquals(null, mriRow, 'MRI row should be present.');
        System.assertEquals(80000, mriRow.sold);
        System.assertEquals(100000, mriRow.target);
        System.assertEquals(80, mriRow.achievementPercent);
        System.assertEquals(3200, mriRow.commission, '80k sold at 5% with 80% achievement factor = 3,200 EGP.');
    }

    @IsTest
    static void getFilterOptions_returnsRecentMonths() {
        MisrRadiologyCommissionService.FilterOptionsResult options = MisrRadiologyCommissionService.getFilterOptions();
        System.assertNotEquals(null, options.monthOptions);
        System.assert(options.monthOptions.size() > 0);
        System.assertNotEquals(null, options.defaultMonthValue);
    }

    @IsTest
    static void controller_getCommissionDetail_delegatesToService() {
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        insert new Employee_Time_Card__c(
            Employee__c = UserInfo.getUserId(),
            Time_Card_Month_Start_Date__c = monthStart,
            Time_Card_Month_End_Date__c = monthEnd,
            Active_Time_Card__c = true,
            Unique_Identifier__c = UserInfo.getUserId() + ':' + String.valueOf(monthStart),
            Territory__c = 'Misr Radiology Controller Test',
            MR_CT_Scan_Sold__c = 50000,
            MR_CT_Scan_Target__c = 100000
        );

        String monthValue = String.valueOf(monthStart.year()) + '-' + String.valueOf(monthStart.month());
        MisrRadiologyCommissionService.CommissionDetailResult detail = MisrRadiologyCommissionController.getCommissionDetail(
            monthValue
        );
        System.assertEquals(true, detail.hasTimeCard);
    }
}
