@IsTest
private class SalesRequestServiceTest {
    private static User makeUser(String alias, Id managerId) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = alias + Datetime.now().getTime();
        User u = new User(
            Alias = alias.left(8),
            Email = uniq + '@example.com',
            Username = uniq + '@example.com.zetatest',
            LastName = 'Test' + alias,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            ProfileId = p.Id,
            ManagerId = managerId
        );
        insert u;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Sales_Request_Access' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        return u;
    }

    private static SalesRequestService.RequestInput sampleInput() {
        SalesRequestService.RequestInput inp = new SalesRequestService.RequestInput();
        inp.requestType = 'Device';
        inp.itemName = 'Glucose monitor';
        inp.quantity = 2;
        inp.details = 'Dr requested a demo unit.';
        return inp;
    }

    @IsTest
    static void createRoutesToManagerAndApprove() {
        User manager = makeUser('mgr', null);
        User rep = makeUser('rep', manager.Id);

        Id reqId;
        System.runAs(rep) {
            SalesRequestService.RequestView v = SalesRequestService.createRequest(sampleInput());
            System.assertEquals('Pending Approval', v.status, 'New request should be pending');
            reqId = v.id;
        }

        Sales_Request__c stored = [
            SELECT Manager__c, Requested_By__c, Status__c FROM Sales_Request__c WHERE Id = :reqId
        ];
        System.assertEquals(manager.Id, stored.Manager__c, 'Should route to rep manager');
        System.assertEquals(rep.Id, stored.Requested_By__c, 'Requested_By should be the rep');

        System.runAs(manager) {
            SalesRequestService.RequestView v = SalesRequestService.approve(reqId);
            System.assertEquals('Approved', v.status, 'Manager approve should set Approved');
            System.assertNotEquals(null, v.decisionDate, 'Decision date set');
        }
    }

    @IsTest
    static void rejectRequiresReason() {
        User manager = makeUser('mgr', null);
        User rep = makeUser('rep', manager.Id);
        Id reqId;
        System.runAs(rep) {
            reqId = SalesRequestService.createRequest(sampleInput()).id;
        }

        System.runAs(manager) {
            Boolean threw = false;
            try {
                SalesRequestService.reject(reqId, '');
            } catch (Exception e) {
                threw = true;
            }
            System.assert(threw, 'Reject without reason should fail');

            SalesRequestService.RequestView v = SalesRequestService.reject(reqId, 'Not in budget');
            System.assertEquals('Rejected', v.status);
            System.assertEquals('Not in budget', v.rejectionReason);
        }
    }

    @IsTest
    static void nonManagerCannotApprove() {
        User manager = makeUser('mgr', null);
        User rep = makeUser('rep', manager.Id);
        User other = makeUser('oth', null);
        Id reqId;
        System.runAs(rep) {
            reqId = SalesRequestService.createRequest(sampleInput()).id;
        }
        System.runAs(other) {
            Boolean threw = false;
            try {
                SalesRequestService.approve(reqId);
            } catch (Exception e) {
                threw = true;
            }
            System.assert(threw, 'Only the assigned DM may approve');
        }
    }

    @IsTest
    static void listForVisitReturnsRows() {
        User manager = makeUser('mgr', null);
        User rep = makeUser('rep', manager.Id);
        System.runAs(rep) {
            SalesRequestService.createRequest(sampleInput());
            List<SalesRequestService.RequestView> all = SalesRequestService.getRequestsForVisit(null);
            System.assertEquals(0, all.size(), 'Null visit returns empty');
        }
    }
}