/**
 * Backfills User.Hire_Date__c, Resignation_Date__c and Last_Work_Day__c from the HR master, matched on
 * User.EmployeeNumber. The master ships as the ZetaHrUserDates static resource
 * ([{"code":"493","hire":"2022-02-01","resign":"","last":""}, ...]); re-upload the resource and run
 *   HrUserDatesLoader.loadFromStaticResource();
 * whenever HR sends a new file. Blank HR dates never overwrite a date already on the user, except that a
 * blank resignation/last day clears a stale one only when clearBlanks is true.
 */
public with sharing class HrUserDatesLoader {
    public class HrRow {
        public String code;
        public String hire;
        public String resign;
        public String last;
        public HrRow(String code, String hire, String resign, String last) {
            this.code = code;
            this.hire = hire;
            this.resign = resign;
            this.last = last;
        }
    }

    public class LoadResult {
        @AuraEnabled public Integer rowsRead = 0;
        @AuraEnabled public Integer usersMatched = 0;
        @AuraEnabled public Integer usersUpdated = 0;
        @AuraEnabled public Integer noUser = 0;
        @AuraEnabled public Integer errors = 0;
        @AuraEnabled public List<String> messages = new List<String>();
    }

    public static LoadResult loadFromStaticResource() {
        return loadFromStaticResource(false);
    }

    public static LoadResult loadFromStaticResource(Boolean clearBlanks) {
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'ZetaHrUserDates'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (resources.isEmpty()) {
            LoadResult empty = new LoadResult();
            empty.messages.add('Static resource ZetaHrUserDates not found.');
            return empty;
        }
        List<HrRow> rows = new List<HrRow>();
        for (Object o : (List<Object>) JSON.deserializeUntyped(resources[0].Body.toString())) {
            Map<String, Object> m = (Map<String, Object>) o;
            rows.add(new HrRow(str(m.get('code')), str(m.get('hire')), str(m.get('resign')), str(m.get('last'))));
        }
        return apply(rows, clearBlanks);
    }

    public static LoadResult apply(List<HrRow> rows, Boolean clearBlanks) {
        LoadResult result = new LoadResult();
        result.rowsRead = rows == null ? 0 : rows.size();
        if (rows == null || rows.isEmpty()) {
            return result;
        }
        Set<String> codes = new Set<String>();
        for (HrRow r : rows) {
            if (String.isNotBlank(r.code)) {
                codes.add(r.code);
            }
        }
        Map<String, User> byCode = new Map<String, User>();
        for (User u : [
            SELECT Id, EmployeeNumber, IsActive, Hire_Date__c, Resignation_Date__c, Last_Work_Day__c
            FROM User
            WHERE EmployeeNumber IN :codes
            WITH SYSTEM_MODE
            ORDER BY IsActive ASC
        ]) {
            byCode.put(u.EmployeeNumber, u); // active user wins over an inactive duplicate
        }
        Map<Id, User> changed = new Map<Id, User>();
        for (HrRow r : rows) {
            User u = byCode.get(r.code);
            if (u == null) {
                result.noUser++;
                continue;
            }
            result.usersMatched++;
            Date hire = parse(r.hire);
            Date resign = parse(r.resign);
            Date last = parse(r.last);
            User patch = changed.containsKey(u.Id) ? changed.get(u.Id) : new User(Id = u.Id);
            Boolean dirty = changed.containsKey(u.Id);
            if (hire != null && u.Hire_Date__c != hire) {
                patch.Hire_Date__c = hire;
                dirty = true;
            }
            if ((resign != null || clearBlanks == true) && u.Resignation_Date__c != resign) {
                patch.Resignation_Date__c = resign;
                dirty = true;
            }
            if ((last != null || clearBlanks == true) && u.Last_Work_Day__c != last) {
                patch.Last_Work_Day__c = last;
                dirty = true;
            }
            if (dirty) {
                changed.put(u.Id, patch);
            }
        }
        if (!changed.isEmpty()) {
            Database.SaveResult[] saves = Database.update(changed.values(), false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < saves.size(); i++) {
                if (saves[i].isSuccess()) {
                    result.usersUpdated++;
                } else {
                    result.errors++;
                    if (result.messages.size() < 20) {
                        result.messages.add(saves[i].getErrors()[0].getMessage());
                    }
                }
            }
        }
        return result;
    }

    private static String str(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static Date parse(String value) {
        if (String.isBlank(value) || value.length() < 10) {
            return null;
        }
        try {
            return Date.valueOf(value.left(10));
        } catch (Exception ex) {
            return null;
        }
    }
}
