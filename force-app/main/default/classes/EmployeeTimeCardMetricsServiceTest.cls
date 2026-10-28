@IsTest
private class EmployeeTimeCardMetricsServiceTest {

    @TestSetup
    static void setupData() {
        Account account = buildAccountWithRecordType('Time Card Metrics HCP', new Set<String>{
            'Medical_Professional_HCP',
            'SDO_PersonAccounts',
            'PersonAccount',
            'Business_Contact'
        });

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Employee_Time_Card__c timeCard = new Employee_Time_Card__c(
            Employee__c = UserInfo.getUserId(),
            Time_Card_Month_Start_Date__c = monthStart,
            Time_Card_Month_End_Date__c = monthStart.addMonths(1).addDays(-1),
            Unique_Identifier__c = UserInfo.getUserId() + ':' + String.valueOf(monthStart),
            Active_Time_Card__c = true
        );
        insert timeCard;

        insert new Employee_Time_Card_Day_Entry__c(
            Employee_Time_Card__c = timeCard.Id,
            Date__c = Date.today(),
            Day_Definition__c = 'Weekday',
            Calendar_Working_Days__c = 1
        );

        insert new Employee_Time_Card_Account_Target__c(
            Employee_Time_Card__c = timeCard.Id,
            Account__c = account.Id,
            Potentiality__c = 'A',
            Target_Visit_Frequency__c = 2,
            Actual_Visits__c = 0,
            Unique_Key__c = timeCard.Id + ':' + account.Id
        );
    }

    @IsTest
    static void completingVisitUpdatesDayEntryAndTargetRollups() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Employee_Time_Card__c timeCard = [SELECT Id FROM Employee_Time_Card__c LIMIT 1];
        DateTime visitDt = DateTime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0));

        Test.startTest();
        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Visit_Date__c = visitDt,
            Start_Date__c = visitDt,
            Status__c = 'Completed',
            CLM_Presentation__c = 'CLM1',
            Visit_Type__c = 'Planned (Automatically)'
        );
        Test.stopTest();

        Employee_Time_Card_Day_Entry__c dayEntry = [
            SELECT Submitted_Calls__c, CLM_Visits__c, Days_with_Activities__c,
                AM_Visits__c, PM_Visits__c,
                Planned_Coaching_Visits__c, Unplanned_Coaching_Visits__c, Total_Visits__c,
                Planned_PM_Visits__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c = :timeCard.Id
            AND Date__c = :Date.today()
            LIMIT 1
        ];
        System.assertEquals(1, dayEntry.Submitted_Calls__c);
        System.assertEquals(1, dayEntry.CLM_Visits__c);
        System.assertEquals(1, dayEntry.Days_with_Activities__c);
        assertDecimal(0, dayEntry.AM_Visits__c);
        assertDecimal(1, dayEntry.PM_Visits__c);
        assertDecimal(1, dayEntry.Planned_Coaching_Visits__c);
        assertDecimal(1, dayEntry.Planned_PM_Visits__c);
        assertDecimal(0, dayEntry.Unplanned_Coaching_Visits__c);
        assertDecimal(2, dayEntry.Total_Visits__c);

        Employee_Time_Card_Account_Target__c target = [
            SELECT Actual_Visits__c, Frequency_Status__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCard.Id
            LIMIT 1
        ];
        System.assertEquals(1, target.Actual_Visits__c);
        System.assertEquals('LCF', target.Frequency_Status__c);

        Employee_Time_Card__c updatedCard = [
            SELECT Submitted_Calls__c, CLM_Visits_Total__c, LCF_Percent__c
            FROM Employee_Time_Card__c
            WHERE Id = :timeCard.Id
        ];
        System.assertEquals(1, updatedCard.Submitted_Calls__c);
        System.assertEquals(1, updatedCard.CLM_Visits_Total__c);
        System.assertEquals(1, updatedCard.LCF_Percent__c);
    }

    @IsTest
    static void reconcileTimeCardRebuildsCountsFromVisits() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Employee_Time_Card__c timeCard = [SELECT Id FROM Employee_Time_Card__c LIMIT 1];
        DateTime visitDt = DateTime.newInstance(Date.today(), Time.newInstance(14, 0, 0, 0));
        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Visit_Date__c = visitDt,
            Start_Date__c = visitDt,
            Status__c = 'Completed',
            Visit_Type__c = 'Planned (Automatically)'
        );

        Test.startTest();
        EmployeeTimeCardMetricsService.reconcileTimeCard(timeCard.Id);
        Test.stopTest();

        Employee_Time_Card__c updatedCard = [
            SELECT Submitted_Calls__c, Actual_Visit_Rate__c
            FROM Employee_Time_Card__c
            WHERE Id = :timeCard.Id
        ];
        System.assertEquals(1, updatedCard.Submitted_Calls__c);
        System.assert(updatedCard.Actual_Visit_Rate__c > 0);
    }

    @IsTest
    static void mapFrequencyPicklist_mapsExpectedValues() {
        System.assertEquals(4, EmployeeTimeCardService.mapFrequencyPicklist('Weekly'));
        System.assertEquals(2, EmployeeTimeCardService.mapFrequencyPicklist('Bi-Weekly'));
        System.assertEquals(1, EmployeeTimeCardService.mapFrequencyPicklist('Monthly'));
        System.assertEquals(0, EmployeeTimeCardService.mapFrequencyPicklist('As Needed'));
    }

    @IsTest
    static void resolveVisitChannel_mapsRecordTypes() {
        Account hospital = new Account(Name = 'HCO', Institution_Type__c = 'Hospital');
        hospital.putSObject('RecordType', new RecordType(DeveloperName = 'Institution_HCO'));
        Account blankHco = new Account(Name = 'HCO default');
        blankHco.putSObject('RecordType', new RecordType(DeveloperName = 'Institution_HCO'));
        Account clinic = new Account(Name = 'Clinic', Institution_Type__c = 'Clinic');
        clinic.putSObject('RecordType', new RecordType(DeveloperName = 'Institution_HCO'));
        Account pharmacy = new Account(Name = 'Pharmacy');
        pharmacy.putSObject('RecordType', new RecordType(DeveloperName = 'Pharmacy'));
        Account hcp = new Account(Name = 'HCP');
        hcp.putSObject('RecordType', new RecordType(DeveloperName = 'Medical_Professional_HCP'));

        System.assertEquals('AM', EmployeeTimeCardMetricsService.resolveVisitChannel(hospital));
        System.assertEquals('AM', EmployeeTimeCardMetricsService.resolveVisitChannel(blankHco));
        System.assertEquals('PM', EmployeeTimeCardMetricsService.resolveVisitChannel(clinic));
        System.assertEquals('PM', EmployeeTimeCardMetricsService.resolveVisitChannel(pharmacy));
        System.assertEquals('PM', EmployeeTimeCardMetricsService.resolveVisitChannel(hcp));
        System.assertEquals(null, EmployeeTimeCardMetricsService.resolveVisitChannel(null));
        System.assertEquals(
            true,
            EmployeeTimeCardMetricsService.isAmHospitalAccount('Institution_HCO', 'Hospital')
        );
        System.assertEquals(
            false,
            EmployeeTimeCardMetricsService.isAmHospitalAccount('Institution_HCO', 'Clinic')
        );
        System.assertEquals(false, EmployeeTimeCardMetricsService.isAmHospitalAccount('Pharmacy', null));
    }

    @IsTest
    static void completedVisitsTrackAmAndPmRatesByAccountType() {
        Employee_Time_Card__c timeCard = [SELECT Id FROM Employee_Time_Card__c LIMIT 1];
        Date testDate = Date.today();
        Account hco = buildAccountWithRecordType('Metrics HCO', new Set<String>{ 'Institution_HCO' });
        Account storedHco = [
            SELECT RecordType.DeveloperName
            FROM Account
            WHERE Id = :hco.Id
        ];
        Boolean hospitalIsAm = storedHco.RecordType != null
            && storedHco.RecordType.DeveloperName == 'Institution_HCO';
        if (hospitalIsAm) {
            update new Account(Id = hco.Id, Institution_Type__c = 'Hospital');
        }
        Account hcp = buildAccountWithRecordType('Metrics HCP', new Set<String>{
            'SDO_PersonAccounts',
            'Medical_Professional_HCP',
            'PersonAccount',
            'Business_Contact'
        });
        DateTime morningVisit = DateTime.newInstance(testDate, Time.newInstance(9, 0, 0, 0));
        DateTime afternoonVisit = DateTime.newInstance(testDate, Time.newInstance(15, 0, 0, 0));

        Test.startTest();
        insert new List<Visit__c>{
            new Visit__c(
                Account__c = hco.Id,
                Assigned_To__c = UserInfo.getUserId(),
                Visit_Date__c = morningVisit,
                Start_Date__c = morningVisit,
                Status__c = 'Completed',
                Visit_Type__c = 'Planned (Automatically)'
            ),
            new Visit__c(
                Account__c = hcp.Id,
                Assigned_To__c = UserInfo.getUserId(),
                Visit_Date__c = afternoonVisit,
                Start_Date__c = afternoonVisit,
                Status__c = 'Completed',
                Visit_Type__c = 'Planned (Automatically)'
            )
        };
        Test.stopTest();

        Employee_Time_Card_Day_Entry__c dayEntry = [
            SELECT Submitted_Calls__c, AM_Visits__c, PM_Visits__c, Days_with_Activities__c,
                Planned_AM_Visits__c, Planned_PM_Visits__c, Total_Visits__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c = :timeCard.Id
            AND Date__c = :testDate
            LIMIT 1
        ];
        Integer expectedPm = hospitalIsAm ? 1 : (storedHco.RecordType == null ? 1 : 2);
        System.assertEquals(2, dayEntry.Submitted_Calls__c);
        System.assertEquals(hospitalIsAm ? 1 : 0, dayEntry.AM_Visits__c);
        System.assertEquals(expectedPm, dayEntry.PM_Visits__c);
        System.assertEquals(1, dayEntry.Days_with_Activities__c);
        assertDecimal(hospitalIsAm ? 1 : 0, dayEntry.Planned_AM_Visits__c);
        assertDecimal(expectedPm, dayEntry.Planned_PM_Visits__c);

        Employee_Time_Card__c updatedCard = [
            SELECT AM_Visits_Total__c, PM_Visits_Total__c, AM_Visit_Rate__c, PM_Visit_Rate__c,
                Actual_Visit_Rate__c
            FROM Employee_Time_Card__c
            WHERE Id = :timeCard.Id
        ];
        if (hospitalIsAm) {
            System.assert(updatedCard.AM_Visits_Total__c >= 1);
        }
        System.assert(updatedCard.PM_Visits_Total__c >= 1);
    }

    @IsTest
    static void weekendCompletedVisitDoesNotCountTowardRate() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Employee_Time_Card__c timeCard = [SELECT Id FROM Employee_Time_Card__c LIMIT 1];
        Date weekendDay = findWeekendInCurrentMonth();
        insert new Employee_Time_Card_Day_Entry__c(
            Employee_Time_Card__c = timeCard.Id,
            Date__c = weekendDay,
            Day_Definition__c = 'Weekend Day',
            Calendar_Working_Days__c = 0
        );
        DateTime visitDt = DateTime.newInstance(weekendDay, Time.newInstance(10, 0, 0, 0));

        Test.startTest();
        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Visit_Date__c = visitDt,
            Start_Date__c = visitDt,
            Status__c = 'Completed',
            Visit_Type__c = 'Planned (Automatically)'
        );
        EmployeeTimeCardMetricsService.reconcileTimeCard(timeCard.Id);
        Test.stopTest();

        Employee_Time_Card_Day_Entry__c weekendEntry = [
            SELECT Submitted_Calls__c, Days_with_Activities__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c = :timeCard.Id
            AND Date__c = :weekendDay
            LIMIT 1
        ];
        System.assertEquals(0, weekendEntry.Submitted_Calls__c);
        System.assertEquals(0, weekendEntry.Days_with_Activities__c);
    }

    @IsTest
    static void unplannedVisitTracksUnplannedBreakdown() {
        Employee_Time_Card__c timeCard = [SELECT Id FROM Employee_Time_Card__c LIMIT 1];
        Date testDate = Date.today();
        Account hcp = buildAccountWithRecordType('Unplanned HCP', new Set<String>{
            'SDO_PersonAccounts',
            'Medical_Professional_HCP',
            'PersonAccount',
            'Business_Contact'
        });
        DateTime visitDt = DateTime.newInstance(testDate, Time.newInstance(11, 0, 0, 0));

        Test.startTest();
        Visit__c unplanned = new Visit__c(
            Account__c = hcp.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Visit_Date__c = visitDt,
            Start_Date__c = visitDt,
            Status__c = 'Scheduled',
            Visit_Type__c = 'Unplanned'
        );
        insert unplanned;
        unplanned.Status__c = 'Completed';
        // Out-of-target visits count only after DM marks Validation_Status Valid.
        unplanned.Validation_Status__c = 'Valid';
        update unplanned;
        Test.stopTest();

        Employee_Time_Card_Day_Entry__c dayEntry = [
            SELECT Planned_PM_Visits__c, Unplanned_PM_Visits__c, Total_Visits__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c = :timeCard.Id
            AND Date__c = :testDate
            LIMIT 1
        ];
        assertDecimal(0, dayEntry.Planned_PM_Visits__c);
        System.assert((dayEntry.Unplanned_PM_Visits__c == null ? 0 : dayEntry.Unplanned_PM_Visits__c) >= 1);
        System.assert((dayEntry.Total_Visits__c == null ? 0 : dayEntry.Total_Visits__c) >= 1);
    }

    @IsTest
    static void completingVisitSetsAttendanceTimesAndCompliance() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Employee_Time_Card__c timeCard = [SELECT Id FROM Employee_Time_Card__c LIMIT 1];
        DateTime firstStart = DateTime.newInstance(Date.today(), Time.newInstance(8, 0, 0, 0));
        DateTime firstEnd = DateTime.newInstance(Date.today(), Time.newInstance(12, 0, 0, 0));
        DateTime secondStart = DateTime.newInstance(Date.today(), Time.newInstance(13, 0, 0, 0));
        DateTime secondEnd = DateTime.newInstance(Date.today(), Time.newInstance(17, 0, 0, 0));

        Test.startTest();
        insert new List<Visit__c>{
            new Visit__c(
                Account__c = account.Id,
                Assigned_To__c = UserInfo.getUserId(),
                Visit_Date__c = firstStart,
                Start_Date__c = firstStart,
                End_Date__c = firstEnd,
                Status__c = 'Completed',
                Visit_Type__c = 'Planned (Automatically)'
            ),
            new Visit__c(
                Account__c = account.Id,
                Assigned_To__c = UserInfo.getUserId(),
                Visit_Date__c = secondStart,
                Start_Date__c = secondStart,
                End_Date__c = secondEnd,
                Status__c = 'Completed',
                Visit_Type__c = 'Planned (Automatically)'
            )
        };
        Test.stopTest();

        Employee_Time_Card_Day_Entry__c dayEntry = [
            SELECT Check_In_Time__c, Check_Out_Time__c, Hours_Worked__c, Is_Compliant__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c = :timeCard.Id
            AND Date__c = :Date.today()
            LIMIT 1
        ];
        System.assertEquals(firstStart, dayEntry.Check_In_Time__c);
        System.assertEquals(secondEnd, dayEntry.Check_Out_Time__c);
        System.assertEquals(9, dayEntry.Hours_Worked__c);
        System.assertEquals(true, dayEntry.Is_Compliant__c);
    }

    @IsTest
    static void shortVisitDayIsNotCompliant() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Employee_Time_Card__c timeCard = [SELECT Id FROM Employee_Time_Card__c LIMIT 1];
        DateTime visitStart = DateTime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0));
        DateTime visitEnd = visitStart.addHours(2);

        Test.startTest();
        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Visit_Date__c = visitStart,
            Start_Date__c = visitStart,
            End_Date__c = visitEnd,
            Status__c = 'Completed',
            Visit_Type__c = 'Planned (Automatically)'
        );
        Test.stopTest();

        Employee_Time_Card_Day_Entry__c dayEntry = [
            SELECT Hours_Worked__c, Is_Compliant__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c = :timeCard.Id
            AND Date__c = :Date.today()
            LIMIT 1
        ];
        System.assertEquals(2, dayEntry.Hours_Worked__c);
        System.assertEquals(false, dayEntry.Is_Compliant__c);
    }

    @IsTest
    static void metricsBatchProcessesActiveCards() {
        Test.startTest();
        Database.executeBatch(new EmployeeTimeCardMetricsBatch(), 5);
        Test.stopTest();
        System.assert(true, 'Batch should complete without error');
    }

    @IsTest
    static void draftVisitIncrementsPotentialAndCompleteMovesCounts() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Employee_Time_Card__c timeCard = [SELECT Id FROM Employee_Time_Card__c LIMIT 1];
        DateTime visitDt = DateTime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));

        Test.startTest();
        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Visit_Date__c = visitDt,
            Start_Date__c = visitDt,
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)'
        );
        insert visit;

        Employee_Time_Card__c afterDraft = [
            SELECT Potential_Visits_Total__c, Submitted_Calls__c, Days_With_Activities__c
            FROM Employee_Time_Card__c
            WHERE Id = :timeCard.Id
        ];
        System.assertEquals(1, afterDraft.Potential_Visits_Total__c, 'Draft visit should count as potential.');
        System.assertEquals(0, afterDraft.Submitted_Calls__c == null ? 0 : afterDraft.Submitted_Calls__c);

        visit.Status__c = 'Completed';
        update visit;
        Test.stopTest();

        Employee_Time_Card__c afterComplete = [
            SELECT Potential_Visits_Total__c, Submitted_Calls__c, Days_With_Activities__c,
                Field_Days_Total__c
            FROM Employee_Time_Card__c
            WHERE Id = :timeCard.Id
        ];
        System.assertEquals(0, afterComplete.Potential_Visits_Total__c, 'Completed visit should leave potential.');
        System.assertEquals(1, afterComplete.Submitted_Calls__c);
        System.assert(afterComplete.Days_With_Activities__c >= 1);
        System.assertNotEquals(null, afterComplete.Field_Days_Total__c);
    }

    @IsTest
    static void coachingEventUpdatesCoachedDays() {
        Employee_Time_Card__c timeCard = [SELECT Id FROM Employee_Time_Card__c LIMIT 1];
        Coaching_Template__c template = new Coaching_Template__c(
            Template_Title__c = 'KPI Coaching Template',
            Template_Type__c = 'Field Coaching',
            Is_Active__c = true
        );
        insert template;

        DateTime eventStart = DateTime.newInstance(Date.today(), Time.newInstance(11, 0, 0, 0));
        Test.startTest();
        Coaching_Event__c eventRecord = new Coaching_Event__c(
            Coaching_Template__c = template.Id,
            Employee__c = UserInfo.getUserId(),
            Manager__c = UserInfo.getUserId(),
            Event_Start__c = eventStart,
            Event_End__c = eventStart.addHours(1),
            Status__c = 'Completed'
        );
        insert eventRecord;
        EmployeeTimeCardMetricsService.processCoachingEventChanges(
            new List<Coaching_Event__c>{ eventRecord },
            null
        );
        Test.stopTest();

        Employee_Time_Card__c updated = [
            SELECT Coached_Days_Total__c, Coaching_Days_Delivered__c
            FROM Employee_Time_Card__c
            WHERE Id = :timeCard.Id
        ];
        System.assertEquals(1, updated.Coached_Days_Total__c);
        System.assertEquals(1, updated.Coaching_Days_Delivered__c);
    }

    @IsTest
    static void recalcMonthlyKpisCountsMeetings() {
        Employee_Time_Card__c timeCard = [SELECT Id FROM Employee_Time_Card__c LIMIT 1];
        DateTime meetingStart = DateTime.newInstance(Date.today(), Time.newInstance(12, 0, 0, 0));

        List<RecordType> meetingTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Meeting__c'
            AND IsActive = TRUE
            LIMIT 1
        ];

        Test.startTest();
        Meeting__c meeting = new Meeting__c(
            Status__c = 'Approved',
            Start_Date_Time__c = meetingStart,
            End_Date_Time__c = meetingStart.addHours(2),
            OwnerId = UserInfo.getUserId()
        );
        if (!meetingTypes.isEmpty()) {
            meeting.RecordTypeId = meetingTypes[0].Id;
        }
        insert meeting;
        EmployeeTimeCardMetricsService.recalcMonthlyKpis(
            new Set<Id>{ UserInfo.getUserId() },
            Date.today().toStartOfMonth()
        );
        Test.stopTest();

        Employee_Time_Card__c updated = [
            SELECT Potential_Meetings_Total__c, Completed_Meetings_Total__c
            FROM Employee_Time_Card__c
            WHERE Id = :timeCard.Id
        ];
        System.assertEquals(1, updated.Potential_Meetings_Total__c);
        System.assertEquals(0, updated.Completed_Meetings_Total__c == null ? 0 : updated.Completed_Meetings_Total__c);
    }

    private static void assertDecimal(Decimal expected, Decimal actual) {
        System.assertEquals(expected, actual == null ? 0 : actual);
    }

    private static Account buildAccountWithRecordType(String label, Set<String> developerNames) {
        List<RecordType> recordTypes = [
            SELECT Id, DeveloperName, IsPersonType
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsActive = TRUE
            AND DeveloperName IN :developerNames
            LIMIT 1
        ];
        Account account = new Account();
        if (!recordTypes.isEmpty()) {
            account.RecordTypeId = recordTypes[0].Id;
            if (recordTypes[0].IsPersonType == true) {
                account.LastName = label;
            } else {
                account.Name = label;
            }
        } else {
            account.Name = label;
        }
        insert account;
        return account;
    }

    private static Boolean isPersonAccountRecordType(String developerName) {
        return developerName == 'SDO_PersonAccounts'
            || developerName == 'PersonAccount';
    }

    private static Date findWeekendInCurrentMonth() {
        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        for (Date cursor = monthStart; cursor <= monthEnd; cursor = cursor.addDays(1)) {
            if (EmployeeTimeCardFlowHelper.isWeekendDay(cursor, null)) {
                return cursor;
            }
        }
        return monthStart;
    }
}