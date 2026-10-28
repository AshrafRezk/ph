/**
 * Loads historical Visits and TOT from Excel/CSV staging until Mendix TOT is ready.
 * Expects Diabetes and Neuroscience as separate files (caller passes lineKey).
 */
public with sharing class HistoricalVisitTotImportService {
    public class ImportResult {
        @AuraEnabled public Integer visitRows;
        @AuraEnabled public Integer totRows;
        @AuraEnabled public Integer errors;
        @AuraEnabled public List<String> messages;
    }

    public class VisitStagingRow {
        @AuraEnabled public String employeeNumber;
        @AuraEnabled public String accountExternalId;
        @AuraEnabled public String visitDate;
        @AuraEnabled public String visitType;
        @AuraEnabled public String status;
        @AuraEnabled public String lineKey;
    }

    public class TotStagingRow {
        @AuraEnabled public String employeeNumber;
        @AuraEnabled public String startDate;
        @AuraEnabled public String endDate;
        @AuraEnabled public String totType;
        @AuraEnabled public String status;
        @AuraEnabled public String lineKey;
    }

    @AuraEnabled
    public static ImportResult importVisitsJson(String payloadJson) {
        ImportResult result = new ImportResult();
        result.visitRows = 0;
        result.totRows = 0;
        result.errors = 0;
        result.messages = new List<String>();
        if (String.isBlank(payloadJson)) {
            result.messages.add('No visit payload.');
            return result;
        }
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(payloadJson);
        Map<String, Id> userByEmployee = loadUsersByEmployeeNumber();
        for (Object item : raw) {
            Map<String, Object> m = (Map<String, Object>) item;
            String emp = stringVal(m.get('employeeNumber'));
            String accountExt = stringVal(m.get('accountExternalId'));
            String dateText = stringVal(m.get('visitDate'));
            Id userId = userByEmployee.get(emp);
            if (userId == null || String.isBlank(accountExt) || String.isBlank(dateText)) {
                result.errors++;
                continue;
            }
            List<Account> accounts = [
                SELECT Id
                FROM Account
                WHERE External_ID__c = :accountExt
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (accounts.isEmpty()) {
                result.errors++;
                continue;
            }
            Date visitDay = Date.valueOf(dateText);
            Visit__c visit = new Visit__c(
                Account__c = accounts[0].Id,
                Assigned_To__c = userId,
                Status__c = String.isBlank(stringVal(m.get('status'))) ? 'Completed' : stringVal(m.get('status')),
                Visit_Type__c = String.isBlank(stringVal(m.get('visitType')))
                    ? 'Planned'
                    : stringVal(m.get('visitType')),
                Visit_Date__c = Datetime.newInstance(visitDay, Time.newInstance(10, 0, 0, 0))
            );
            try {
                insert as system visit;
                result.visitRows++;
            } catch (Exception ex) {
                result.errors++;
                if (result.messages.size() < 20) {
                    result.messages.add(ex.getMessage());
                }
            }
        }
        result.messages.add('Imported ' + result.visitRows + ' visits with ' + result.errors + ' errors.');
        return result;
    }

    @AuraEnabled
    public static ImportResult importTotJson(String payloadJson) {
        ImportResult result = new ImportResult();
        result.visitRows = 0;
        result.totRows = 0;
        result.errors = 0;
        result.messages = new List<String>();
        if (String.isBlank(payloadJson)) {
            result.messages.add('No TOT payload. Mendix TOTs are not the source — use Excel.');
            return result;
        }
        // Time_Off_Request__c shape varies; stage as JSON audit until field map is confirmed with Zeta file.
        result.messages.add(
            'TOT Excel received ('
                + ((List<Object>) JSON.deserializeUntyped(payloadJson)).size()
                + ' rows). Map columns after Zeta sends Diabetes / Neuroscience files.'
        );
        result.totRows = ((List<Object>) JSON.deserializeUntyped(payloadJson)).size();
        return result;
    }

    private static Map<String, Id> loadUsersByEmployeeNumber() {
        Map<String, Id> byEmp = new Map<String, Id>();
        for (User u : [
            SELECT Id, EmployeeNumber
            FROM User
            WHERE IsActive = TRUE AND EmployeeNumber != NULL
            WITH SYSTEM_MODE
            LIMIT 5000
        ]) {
            byEmp.put(u.EmployeeNumber, u.Id);
        }
        return byEmp;
    }

    private static String stringVal(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }
}
