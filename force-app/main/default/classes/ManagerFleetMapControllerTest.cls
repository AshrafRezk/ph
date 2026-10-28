@IsTest
private class ManagerFleetMapControllerTest {
    @IsTest
    static void getFleetMapData_returnsPayloadForCurrentUserScope() {
        Account account = new Account(
            Name = 'Fleet Map Pharmacy',
            BillingLatitude = 30.0444,
            BillingLongitude = 31.2357
        );
        insert account;

        DateTime visitStart = DateTime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0));
        DateTime visitEnd = DateTime.newInstance(Date.today(), Time.newInstance(9, 45, 0, 0));
        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Visit_Date__c = visitStart,
            Start_Date__c = visitStart,
            End_Date__c = visitEnd,
            Status__c = 'Scheduled',
            Visit_Type__c = 'Planned (Automatically)'
        );

        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Visit_Date__c = visitStart.addHours(2),
            Start_Date__c = visitStart.addHours(2),
            End_Date__c = visitEnd.addHours(2),
            Status__c = 'Completed',
            Visit_Type__c = 'Planned (Automatically)'
        );

        RepLocationService.upsertSnapshot(30.0500, 31.2400, 15);
        ManagerFleetMapController.testEmployeeIdsOverride = new Set<Id>{ UserInfo.getUserId() };

        Test.startTest();
        ManagerFleetMapController.FleetMapPayload payload = ManagerFleetMapController.getFleetMapData(
            'ALL',
            'ALL',
            'ALL',
            Date.today()
        );
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assertEquals(Date.today(), payload.routeDate);
        System.assertEquals(1, payload.reps.size());
        ManagerFleetMapController.FleetRepRoute currentRep = payload.reps[0];
        System.assertEquals(UserInfo.getUserId(), currentRep.userId);
        System.assertEquals(2, currentRep.totalVisits);
        System.assertEquals(1, currentRep.completedVisits);
        System.assertNotEquals(null, currentRep.location);
        System.assertEquals('online', currentRep.location.status);
        System.assertEquals(1, payload.onlineCount);
    }

    @IsTest
    static void getFleetMapData_emptyScopeReturnsZeroCounts() {
        ManagerFleetMapController.testEmployeeIdsOverride = new Set<Id>();
        Test.startTest();
        ManagerFleetMapController.FleetMapPayload payload = ManagerFleetMapController.getFleetMapData(
            null,
            null,
            null,
            Date.today()
        );
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assertEquals(0, payload.reps.size());
        System.assertEquals(0, payload.onlineCount);
    }

    @IsTest
    static void getFleetMapData_offlineWhenNoSnapshot() {
        ManagerFleetMapController.testEmployeeIdsOverride = new Set<Id>{ UserInfo.getUserId() };
        Test.startTest();
        ManagerFleetMapController.FleetMapPayload payload = ManagerFleetMapController.getFleetMapData(
            'ALL',
            'ALL',
            'ALL',
            null
        );
        Test.stopTest();

        System.assertEquals(1, payload.reps.size());
        System.assertEquals(null, payload.reps[0].location);
        System.assertEquals(1, payload.offlineCount);
    }
}
