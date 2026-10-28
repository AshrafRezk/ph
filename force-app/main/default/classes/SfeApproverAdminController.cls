/**
 * Admin Console > SFE Approvers: who approves Class Engine cycles and new accounts at Pending SFE,
 * per business unit or line (SFE_Approver_Assignment__c). One row per approver.
 * Editing needs create, edit, and delete on SFE Approvers and edit access to its fields (Pharma_SFE_App).
 */
public with sharing class SfeApproverAdminController {
    public class Setup {
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public List<String> businessUnits;
        @AuraEnabled public List<Row> rows;
    }

    public class Row {
        @AuraEnabled public Id id;
        @AuraEnabled public Id approverId;
        @AuraEnabled public String approverName;
        @AuraEnabled public String approverTitle;
        @AuraEnabled public Boolean allLines;
        @AuraEnabled public List<String> lines;
        @AuraEnabled public Boolean classification;
        @AuraEnabled public Boolean newAccounts;
        @AuraEnabled public Boolean isActive;
    }

    @AuraEnabled
    public static Setup getSetup() {
        try {
            Setup setup = new Setup();
            setup.canEdit = canEdit();
            setup.businessUnits = businessUnitNames();
            setup.rows = new List<Row>();
            for (SFE_Approver_Assignment__c record : [
                SELECT
                    Id,
                    Approver__c,
                    Approver__r.Name,
                    Approver__r.Title,
                    All_Lines__c,
                    Lines__c,
                    Approves_Classification__c,
                    Approves_New_Accounts__c,
                    Is_Active__c
                FROM SFE_Approver_Assignment__c
                WITH SYSTEM_MODE
                ORDER BY Approver__r.Name ASC, CreatedDate ASC
                LIMIT 500
            ]) {
                setup.rows.add(toRow(record));
            }
            return setup;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    /** Unsaved row for a picked user: both approvals on, no lines yet. */
    @AuraEnabled
    public static Row newRow(Id userId) {
        try {
            requireEdit();
            List<User> users = [
                SELECT Id, Name, Title, IsActive
                FROM User
                WHERE Id = :userId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (users.isEmpty()) {
                throw new SetupException('User not found.');
            }
            if (!users[0].IsActive) {
                throw new SetupException(users[0].Name + ' is an inactive user.');
            }
            Row row = new Row();
            row.approverId = users[0].Id;
            row.approverName = users[0].Name;
            row.approverTitle = users[0].Title;
            row.allLines = false;
            row.lines = new List<String>();
            row.classification = true;
            row.newAccounts = true;
            row.isActive = true;
            return row;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    /** Replaces the whole table: rows missing from rowsJson are deleted. */
    @AuraEnabled
    public static Setup saveRows(String rowsJson) {
        try {
            requireEdit();
            List<Row> input = String.isBlank(rowsJson)
                ? new List<Row>()
                : (List<Row>) JSON.deserialize(rowsJson, List<Row>.class);
            Map<Id, User> approvers = loadApprovers(input);
            Map<String, String> knownLines = knownLineNames();
            Map<Id, SFE_Approver_Assignment__c> existing = new Map<Id, SFE_Approver_Assignment__c>([
                SELECT Id
                FROM SFE_Approver_Assignment__c
                WITH SYSTEM_MODE
                LIMIT 500
            ]);

            List<SFE_Approver_Assignment__c> upserts = new List<SFE_Approver_Assignment__c>();
            Set<Id> kept = new Set<Id>();
            Set<Id> seenApprovers = new Set<Id>();
            for (Row row : input) {
                User approver = row == null || row.approverId == null ? null : approvers.get(row.approverId);
                if (approver == null) {
                    throw new SetupException('Choose a user for every SFE approver row.');
                }
                if (!seenApprovers.add(approver.Id)) {
                    throw new SetupException(approver.Name + ' is listed twice. Keep one row per approver.');
                }
                Boolean active = row.isActive != false;
                if (active && !approver.IsActive) {
                    throw new SetupException(approver.Name + ' is an inactive user. Turn the row off or remove it.');
                }
                Boolean classification = row.classification == true;
                Boolean newAccounts = row.newAccounts == true;
                if (!classification && !newAccounts) {
                    throw new SetupException('Choose Class Engine, New accounts, or both for ' + approver.Name + '.');
                }
                Boolean allLines = row.allLines == true;
                List<String> lines = allLines ? new List<String>() : canonicalLines(row.lines, knownLines);
                if (!allLines && lines.isEmpty()) {
                    throw new SetupException('Pick All lines or at least one business unit for ' + approver.Name + '.');
                }
                String joined = String.join(lines, ';');
                if (joined.length() > 255) {
                    throw new SetupException('Too many lines for ' + approver.Name + '. Pick business units or All lines.');
                }
                SFE_Approver_Assignment__c record = new SFE_Approver_Assignment__c(
                    Approver__c = approver.Id,
                    All_Lines__c = allLines,
                    Lines__c = allLines ? null : joined,
                    Approves_Classification__c = classification,
                    Approves_New_Accounts__c = newAccounts,
                    Is_Active__c = active
                );
                if (row.id != null && existing.containsKey(row.id)) {
                    record.Id = row.id;
                    kept.add(row.id);
                }
                upserts.add(record);
            }

            List<SFE_Approver_Assignment__c> removals = new List<SFE_Approver_Assignment__c>();
            for (Id recordId : existing.keySet()) {
                if (!kept.contains(recordId)) {
                    removals.add(new SFE_Approver_Assignment__c(Id = recordId));
                }
            }
            if (!removals.isEmpty()) {
                delete as user removals;
            }
            if (!upserts.isEmpty()) {
                upsert as user upserts;
            }
            SfeApproverService.clearCache();
            return getSetup();
        } catch (Exception e) {
            throw fail(e);
        }
    }

    private static Row toRow(SFE_Approver_Assignment__c record) {
        Row row = new Row();
        row.id = record.Id;
        row.approverId = record.Approver__c;
        row.approverName = record.Approver__r == null ? null : record.Approver__r.Name;
        row.approverTitle = record.Approver__r == null ? null : record.Approver__r.Title;
        row.allLines = record.All_Lines__c == true;
        row.lines = SfeApproverService.splitLines(record.Lines__c);
        row.classification = record.Approves_Classification__c == true;
        row.newAccounts = record.Approves_New_Accounts__c == true;
        row.isActive = record.Is_Active__c == true;
        return row;
    }

    private static Map<Id, User> loadApprovers(List<Row> input) {
        Set<Id> userIds = new Set<Id>();
        for (Row row : input) {
            if (row != null && row.approverId != null) {
                userIds.add(row.approverId);
            }
        }
        return new Map<Id, User>([
            SELECT Id, Name, IsActive
            FROM User
            WHERE Id IN :userIds
            WITH SYSTEM_MODE
        ]);
    }

    /** Business unit and line names in the active territory model, keyed by lower case. */
    private static Map<String, String> knownLineNames() {
        Map<String, String> byKey = new Map<String, String>();
        for (Territory2 territory : [
            SELECT Name
            FROM Territory2
            WHERE Territory_Type__c IN ('Business_Unit', 'Line') AND Territory2Model.State = 'Active'
            WITH SYSTEM_MODE
        ]) {
            if (territory.Name != null) {
                byKey.put(territory.Name.trim().toLowerCase(), territory.Name.trim());
            }
        }
        return byKey;
    }

    private static List<String> canonicalLines(List<String> raw, Map<String, String> knownLines) {
        List<String> lines = new List<String>();
        Set<String> seen = new Set<String>();
        for (String value : raw == null ? new List<String>() : raw) {
            String key = value == null ? '' : value.trim().toLowerCase();
            if (String.isBlank(key) || !seen.add(key)) {
                continue;
            }
            if (!knownLines.containsKey(key)) {
                throw new SetupException(value.trim() + ' is not a business unit or line in the active territory model.');
            }
            lines.add(knownLines.get(key));
        }
        return lines;
    }

    private static List<String> businessUnitNames() {
        List<String> names = new List<String>();
        Set<String> seen = new Set<String>();
        for (Territory2 territory : [
            SELECT Name
            FROM Territory2
            WHERE Territory_Type__c = 'Business_Unit' AND Territory2Model.State = 'Active'
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ]) {
            if (territory.Name != null && seen.add(territory.Name.trim().toLowerCase())) {
                names.add(territory.Name.trim());
            }
        }
        return names;
    }

    private static Boolean canEdit() {
        Schema.DescribeSObjectResult describe = SFE_Approver_Assignment__c.SObjectType.getDescribe();
        if (!describe.isCreateable() || !describe.isUpdateable() || !describe.isDeletable()) {
            return false;
        }
        for (Schema.SObjectField field : new List<Schema.SObjectField>{
            SFE_Approver_Assignment__c.Approver__c,
            SFE_Approver_Assignment__c.All_Lines__c,
            SFE_Approver_Assignment__c.Lines__c,
            SFE_Approver_Assignment__c.Approves_Classification__c,
            SFE_Approver_Assignment__c.Approves_New_Accounts__c,
            SFE_Approver_Assignment__c.Is_Active__c
        }) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (!fieldDescribe.isCreateable() || !fieldDescribe.isUpdateable()) {
                return false;
            }
        }
        return true;
    }

    private static void requireEdit() {
        if (!canEdit()) {
            throw new SetupException('You need the SFE Co-pilot permission set to change SFE approvers.');
        }
    }

    public class SetupException extends Exception {}

    private static AuraHandledException fail(Exception e) {
        String message = e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage();
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
