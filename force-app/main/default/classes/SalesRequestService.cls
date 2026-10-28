/**
 * Sales Requests raised by a rep during a Visit (e.g. a doctor requests a
 * device). Each request is routed to the requester's District Manager
 * (User.ManagerId) for approval. The DM approves, or rejects with a reason.
 */
public with sharing class SalesRequestService {
    public class RequestInput {
        @AuraEnabled public Id visitId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String requestType;
        @AuraEnabled public String itemName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String details;
    }

    public class RequestView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String requestType;
        @AuraEnabled public String itemName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String details;
        @AuraEnabled public String status;
        @AuraEnabled public String rejectionReason;
        @AuraEnabled public String requestedByName;
        @AuraEnabled public String managerName;
        @AuraEnabled public Datetime decisionDate;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Boolean canApprove;
    }

    @AuraEnabled(cacheable=false)
    public static List<RequestView> getRequestsForVisit(Id visitId) {
        if (visitId == null) {
            return new List<RequestView>();
        }
        List<Sales_Request__c> rows = [
            SELECT Id, Name, Request_Type__c, Item_Name__c, Quantity__c, Details__c,
                   Status__c, Rejection_Reason__c, Requested_By__r.Name, Manager__c,
                   Manager__r.Name, Decision_Date__c, CreatedDate
            FROM Sales_Request__c
            WHERE Visit__c = :visitId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ];
        List<RequestView> views = new List<RequestView>();
        for (Sales_Request__c r : rows) {
            views.add(toView(r));
        }
        return views;
    }

    @AuraEnabled
    public static RequestView createRequest(RequestInput input) {
        if (input == null || String.isBlank(input.itemName)) {
            throw badRequest('Item requested is required.');
        }
        // Route to the requester's District Manager.
        Id managerId = currentUserManagerId();
        Sales_Request__c req = new Sales_Request__c(
            Visit__c = input.visitId,
            Account__c = input.accountId,
            Request_Type__c = String.isBlank(input.requestType) ? 'Device' : input.requestType,
            Item_Name__c = input.itemName,
            Quantity__c = input.quantity,
            Details__c = input.details,
            Requested_By__c = UserInfo.getUserId(),
            Manager__c = managerId,
            Status__c = 'Pending Approval'
        );
        insert as user req;
        return toView(requeryOne(req.Id));
    }

    @AuraEnabled
    public static RequestView approve(Id requestId) {
        Sales_Request__c req = forDecision(requestId);
        req.Status__c = 'Approved';
        req.Rejection_Reason__c = null;
        req.Decision_Date__c = Datetime.now();
        update as user req;
        return toView(requeryOne(req.Id));
    }

    @AuraEnabled
    public static RequestView reject(Id requestId, String reason) {
        if (String.isBlank(reason)) {
            throw badRequest('A rejection reason is required.');
        }
        Sales_Request__c req = forDecision(requestId);
        req.Status__c = 'Rejected';
        req.Rejection_Reason__c = reason;
        req.Decision_Date__c = Datetime.now();
        update as user req;
        return toView(requeryOne(req.Id));
    }

    // --- helpers ---

    private static Sales_Request__c forDecision(Id requestId) {
        if (requestId == null) {
            throw badRequest('Request id is required.');
        }
        Sales_Request__c req = requeryOne(requestId);
        if (req == null) {
            throw badRequest('Request not found.');
        }
        if (req.Manager__c != UserInfo.getUserId()) {
            throw badRequest('Only the assigned District Manager can approve or reject this request.');
        }
        if (req.Status__c != 'Pending Approval') {
            throw badRequest('This request has already been ' + req.Status__c.toLowerCase() + '.');
        }
        return req;
    }

    private static Id currentUserManagerId() {
        List<User> users = [
            SELECT ManagerId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].ManagerId;
    }

    private static Sales_Request__c requeryOne(Id requestId) {
        List<Sales_Request__c> rows = [
            SELECT Id, Name, Request_Type__c, Item_Name__c, Quantity__c, Details__c,
                   Status__c, Rejection_Reason__c, Requested_By__r.Name, Manager__c,
                   Manager__r.Name, Decision_Date__c, CreatedDate
            FROM Sales_Request__c
            WHERE Id = :requestId
            WITH USER_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static RequestView toView(Sales_Request__c r) {
        RequestView v = new RequestView();
        v.id = r.Id;
        v.name = r.Name;
        v.requestType = r.Request_Type__c;
        v.itemName = r.Item_Name__c;
        v.quantity = r.Quantity__c;
        v.details = r.Details__c;
        v.status = r.Status__c;
        v.rejectionReason = r.Rejection_Reason__c;
        v.requestedByName = r.Requested_By__r != null ? r.Requested_By__r.Name : null;
        v.managerName = r.Manager__r != null ? r.Manager__r.Name : null;
        v.decisionDate = r.Decision_Date__c;
        v.createdDate = r.CreatedDate;
        v.canApprove = r.Status__c == 'Pending Approval' && r.Manager__c == UserInfo.getUserId();
        return v;
    }

    private static AuraHandledException badRequest(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}