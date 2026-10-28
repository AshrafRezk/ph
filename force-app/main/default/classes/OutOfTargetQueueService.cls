/**
 * End-of-month: accounts visited outside the target list this quarter → DM → FI → BU optional → classify.
 */
public with sharing class OutOfTargetQueueService {
    public class ProposalRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id repId;
        @AuraEnabled public String repName;
        @AuraEnabled public String status;
        @AuraEnabled public Date targetMonth;
        @AuraEnabled public Decimal visitCount;
    }

    @AuraEnabled
    public static List<ProposalRow> buildQueueForRep(Id repId, Date quarterStart, Date nextMonthStart) {
        if (repId == null) {
            repId = UserInfo.getUserId();
        }
        Date qStart = quarterStart == null ? Date.today().toStartOfMonth().addMonths(-2) : quarterStart;
        Date qEnd = qStart.addMonths(3).addDays(-1);
        Date targetMonth = nextMonthStart == null ? Date.today().toStartOfMonth().addMonths(1) : nextMonthStart;

        Set<Id> assignedTerritoryIds = TerritoryContextService.getAssignedTerritoryIds(repId);
        Set<Id> targetAccountIds = new Set<Id>();
        if (!assignedTerritoryIds.isEmpty()) {
            for (Account_Territory_Fields__c atf : [
                SELECT Account__c
                FROM Account_Territory_Fields__c
                WHERE Is_Active__c = TRUE AND Territory2_Id__c IN :assignedTerritoryIds
                WITH SYSTEM_MODE
                LIMIT 5000
            ]) {
                targetAccountIds.add(atf.Account__c);
            }
        }

        Datetime rangeStart = Datetime.newInstance(qStart, Time.newInstance(0, 0, 0, 0));
        Datetime rangeEnd = Datetime.newInstance(qEnd, Time.newInstance(23, 59, 59, 0));

        // Only DM-validated out-of-target visits enter the end-of-month target proposal queue.
        Set<String> validStatuses = new Set<String>{ 'Valid', 'Validated' };
        Map<Id, Integer> visitCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Account__c acct, COUNT(Id) cnt
            FROM Visit__c
            WHERE
                Assigned_To__c = :repId
                AND Status__c = 'Completed'
                AND Account__c != NULL
                AND Validation_Status__c IN :validStatuses
                AND Visit_Date__c >= :rangeStart
                AND Visit_Date__c <= :rangeEnd
            WITH SYSTEM_MODE
            GROUP BY Account__c
            LIMIT 2000
        ]) {
            Id accountId = (Id) ar.get('acct');
            if (targetAccountIds.contains(accountId)) {
                continue;
            }
            visitCounts.put(accountId, (Integer) ar.get('cnt'));
        }

        Set<Id> existingAccounts = new Set<Id>();
        for (Out_Of_Target_Proposal__c existing : [
            SELECT Account__c
            FROM Out_Of_Target_Proposal__c
            WHERE
                Rep__c = :repId
                AND Target_Month__c = :targetMonth
                AND Account__c IN :visitCounts.keySet()
            WITH SYSTEM_MODE
        ]) {
            existingAccounts.add(existing.Account__c);
        }

        List<Out_Of_Target_Proposal__c> toInsert = new List<Out_Of_Target_Proposal__c>();
        for (Id accountId : visitCounts.keySet()) {
            if (existingAccounts.contains(accountId)) {
                continue;
            }
            toInsert.add(
                new Out_Of_Target_Proposal__c(
                    Name = ('OOT ' + String.valueOf(targetMonth) + ' ' + String.valueOf(accountId)).left(80),
                    Account__c = accountId,
                    Rep__c = repId,
                    Status__c = 'Pending DM',
                    Target_Month__c = targetMonth,
                    Visit_Count__c = visitCounts.get(accountId)
                )
            );
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }
        return listProposals(repId, 'Pending DM');
    }

    @AuraEnabled
    public static List<ProposalRow> listProposals(Id repId, String status) {
        String soql =
            'SELECT Id, Name, Account__c, Account__r.Name, Rep__c, Rep__r.Name, Status__c,'
            + ' Target_Month__c, Visit_Count__c FROM Out_Of_Target_Proposal__c WHERE Id != null';
        if (repId != null) {
            soql += ' AND Rep__c = :repId';
        }
        if (String.isNotBlank(status) && status != 'All') {
            soql += ' AND Status__c = :status';
        }
        soql += ' WITH SYSTEM_MODE ORDER BY LastModifiedDate DESC LIMIT 500';
        List<ProposalRow> rows = new List<ProposalRow>();
        for (Out_Of_Target_Proposal__c rec : Database.query(soql)) {
            ProposalRow row = new ProposalRow();
            row.id = rec.Id;
            row.accountId = rec.Account__c;
            row.accountName = rec.Account__r != null ? rec.Account__r.Name : null;
            row.repId = rec.Rep__c;
            row.repName = rec.Rep__r != null ? rec.Rep__r.Name : null;
            row.status = rec.Status__c;
            row.targetMonth = rec.Target_Month__c;
            row.visitCount = rec.Visit_Count__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static void advanceStatus(Id proposalId, String nextStatus) {
        if (proposalId == null || String.isBlank(nextStatus)) {
            throw new AuraHandledException('Proposal and status are required.');
        }
        Out_Of_Target_Proposal__c row = [
            SELECT Id, Status__c, Rep__c
            FROM Out_Of_Target_Proposal__c
            WHERE Id = :proposalId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Set<String> allowed = new Set<String>{
            'Pending DM',
            'Pending FI',
            'Pending BU',
            'Approved',
            'Rejected'
        };
        if (!allowed.contains(nextStatus)) {
            throw new AuraHandledException('Invalid status.');
        }
        // Enforce the DM -> FI -> BU sequence; Approved and Rejected are final.
        Map<String, Set<String>> nextAllowed = new Map<String, Set<String>>{
            'Pending DM' => new Set<String>{ 'Pending FI', 'Rejected' },
            'Pending FI' => new Set<String>{ 'Pending BU', 'Rejected' },
            'Pending BU' => new Set<String>{ 'Approved', 'Rejected' }
        };
        String current = String.isBlank(row.Status__c) ? 'Pending DM' : row.Status__c;
        if (!nextAllowed.containsKey(current) || !nextAllowed.get(current).contains(nextStatus)) {
            throw new AuraHandledException('A proposal at "' + current + '" cannot move to "' + nextStatus + '".');
        }
        assertCanActAt(current, row.Rep__c);
        row.Status__c = nextStatus;
        update as system row;
    }

    private static void assertCanActAt(String stage, Id repId) {
        Boolean allowed;
        if (stage == 'Pending DM') {
            allowed = SfeApproverService.isSystemAdministrator()
                || (repId != UserInfo.getUserId() && FieldPlannerController.canViewBookOf(repId));
        } else if (stage == 'Pending FI') {
            allowed = StageApproverAccess.canActAsFi();
        } else {
            allowed = StageApproverAccess.canActAsBu();
        }
        if (!allowed) {
            throw new AuraHandledException('You are not the approver for a proposal at "' + stage + '".');
        }
    }
}
