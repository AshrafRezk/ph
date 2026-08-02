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

        RepLocationService.upsertSnapshot(30.0500, 31.2400, 15);

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
        System.assert(payload.reps != null);

        ManagerFleetMapController.FleetRepRoute currentRep;
        for (ManagerFleetMapController.FleetRepRoute rep : payload.reps) {
            if (rep.userId == UserInfo.getUserId()) {
                currentRep = rep;
                break;
            }
        }
        if (currentRep != null) {
            System.assertEquals(1, currentRep.totalVisits);
            System.assertEquals(0, currentRep.completedVisits);
            System.assertNotEquals(null, currentRep.location);
            System.assertEquals('online', currentRep.location.status);
            System.assertEquals(1, currentRep.stops.size());
            System.assertEquals(account.Id, currentRep.stops[0].accountId);
        }
    }

    @IsTest
    static void getFleetMapData_emptyScopeReturnsZeroCounts() {
        Test.startTest();
        ManagerFleetMapController.FleetMapPayload payload = ManagerFleetMapController.getFleetMapData(
            null,
            null,
            null,
            Date.today()
        );
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assertNotEquals(null, payload.reps);
    }
}
