@RestResource(urlMapping='/osr/v1/outbox')
global with sharing class OsrOutboxService {
    global class OutboxAction {
        public String clientId;
        public String op;
        public String objectApi;
        public String recordId;
        public Map<String, Object> payload;
        public Integer attempts;
    }
    global class OutboxRequest {
        public List<OutboxAction> actions;
    }
    global class OutboxResult {
        public String clientId;
        public String status; // synced | failed | conflict
        public String error;
        public String serverId;
        public Map<String, Object> serverRecord;
        public Map<String, Object> clientRecord;
    }
    global class OutboxResponse {
        public List<OutboxResult> results;
    }

    @HttpPost
    global static void apply() {
        writeJson(buildResponse());
    }

    public static OutboxResponse buildResponse() {
        OutboxRequest req = (OutboxRequest) JSON.deserialize(
            RestContext.request.requestBody.toString(),
            OutboxRequest.class
        );
        OutboxResponse res = new OutboxResponse();
        res.results = new List<OutboxResult>();
        if (req == null || req.actions == null) {
            return res;
        }
        for (OutboxAction action : req.actions) {
            res.results.add(processOne(action));
        }
        return res;
    }

    private static void writeJson(Object value) {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(value));
    }

    private static OutboxResult processOne(OutboxAction action) {
        OutboxResult r = new OutboxResult();
        r.clientId = action.clientId;
        r.clientRecord = action.payload;
        try {
            String op = action.op == null ? '' : action.op.toLowerCase();
            if (op == 'create' || op == 'update' || op == 'visit.upsert') {
                r = upsertRecord(action, r);
            } else if (op == 'delete') {
                deleteRecord(action);
                r.status = 'synced';
            } else if (op == 'location.upsert') {
                upsertRepLocation(action);
                r.status = 'synced';
            } else if (op == 'clm.session' || op == 'apex-action') {
                // Defer to existing ClmOfflineSyncController patterns when present in org
                r.status = 'synced';
                r.error = 'Named action acknowledged (wire org handler)';
            } else if (op == 'planner.reschedule') {
                rescheduleVisits(action);
                r.status = 'synced';
            } else {
                r.status = 'failed';
                r.error = 'Unknown op: ' + action.op;
            }
        } catch (DmlException dml) {
            r.status = 'failed';
            r.error = dml.getMessage();
        } catch (Exception e) {
            r.status = 'failed';
            r.error = e.getMessage();
        }
        return r;
    }

    private static OutboxResult upsertRecord(OutboxAction action, OutboxResult r) {
        if (String.isBlank(action.objectApi) || !Schema.getGlobalDescribe().containsKey(action.objectApi)) {
            r.status = 'failed';
            r.error = 'Unknown object';
            return r;
        }
        Map<String, Object> payload = action.payload == null ? new Map<String, Object>() : action.payload;
        String recordId = action.recordId;
        if (String.isBlank(recordId) && payload.containsKey('Id')) {
            recordId = String.valueOf(payload.get('Id'));
        }
        Boolean isLocal = String.isNotBlank(recordId) && recordId.startsWith('local_');

        SObjectType t = Schema.getGlobalDescribe().get(action.objectApi);
        Map<String, Schema.SObjectField> fmap = t.getDescribe().fields.getMap();

        if (!isLocal && String.isNotBlank(recordId)) {
            List<SObject> existing = Database.query(
                'SELECT Id, SystemModstamp FROM ' +
                String.escapeSingleQuotes(action.objectApi) +
                ' WHERE Id = \'' +
                String.escapeSingleQuotes(recordId) +
                '\' LIMIT 1'
            );
            if (!existing.isEmpty() && payload.containsKey('SystemModstamp')) {
                Datetime clientStamp = tryParse((String) payload.get('SystemModstamp'));
                Datetime serverStamp = (Datetime) existing[0].get('SystemModstamp');
                if (clientStamp != null && serverStamp != null && serverStamp > clientStamp) {
                    r.status = 'conflict';
                    r.error = 'Server version newer';
                    r.serverRecord = existing[0].getPopulatedFieldsAsMap();
                    return r;
                }
            }
        }

        SObject sob = t.newSObject();
        for (String key : payload.keySet()) {
            if (key == 'Id' || key.startsWith('_')) {
                continue;
            }
            if (!fmap.containsKey(key)) {
                continue;
            }
            sob.put(key, payload.get(key));
        }
        if (!isLocal && String.isNotBlank(recordId)) {
            sob.put('Id', recordId);
            update sob;
            r.serverId = recordId;
        } else {
            insert sob;
            r.serverId = sob.Id;
        }
        r.status = 'synced';
        return r;
    }

    private static void deleteRecord(OutboxAction action) {
        if (String.isBlank(action.objectApi) || String.isBlank(action.recordId)) {
            return;
        }
        if (action.recordId.startsWith('local_')) {
            return;
        }
        Database.delete(Id.valueOf(action.recordId), false);
        if (Schema.getGlobalDescribe().containsKey('Offline_Tombstone__c')) {
            SObject tomb = Schema.getGlobalDescribe().get('Offline_Tombstone__c').newSObject();
            tomb.put('Object_API__c', action.objectApi);
            tomb.put('Record_Id__c', action.recordId);
            tomb.put('Deleted_At__c', Datetime.now());
            insert tomb;
        }
    }

    private static void upsertRepLocation(OutboxAction action) {
        Map<String, Object> payload = action.payload == null ? new Map<String, Object>() : action.payload;
        Decimal lat = toDecimal(payload.get('latitude'));
        Decimal lon = toDecimal(payload.get('longitude'));
        if (lat == null || lon == null) {
            throw new AuraHandledException('latitude and longitude are required for location.upsert');
        }
        Decimal accuracy = toDecimal(payload.get('accuracyMeters'));
        String source = payload.containsKey('source') ? String.valueOf(payload.get('source')) : 'Mobile';
        String deviceModel = payload.containsKey('deviceModel') ? String.valueOf(payload.get('deviceModel')) : null;
        String deviceOs = payload.containsKey('deviceOs') ? String.valueOf(payload.get('deviceOs')) : null;
        String appVersion = payload.containsKey('appVersion') ? String.valueOf(payload.get('appVersion')) : null;
        String deviceId = payload.containsKey('deviceId') ? String.valueOf(payload.get('deviceId')) : null;
        if (!Schema.getGlobalDescribe().containsKey('Rep_Location_Snapshot__c')) {
            throw new AuraHandledException('Rep_Location_Snapshot__c not available');
        }
        Id userId = UserInfo.getUserId();
        List<SObject> existing = Database.query(
            'SELECT Id FROM Rep_Location_Snapshot__c WHERE User__c = \'' +
                String.escapeSingleQuotes(String.valueOf(userId)) +
                '\' LIMIT 1'
        );
        SObject snap = Schema.getGlobalDescribe().get('Rep_Location_Snapshot__c').newSObject();
        if (!existing.isEmpty()) {
            snap.put('Id', existing[0].Id);
        } else {
            snap.put('User__c', userId);
        }
        Map<String, Schema.SObjectField> fmap = Schema.getGlobalDescribe()
            .get('Rep_Location_Snapshot__c')
            .getDescribe()
            .fields.getMap();
        snap.put('Latitude__c', lat);
        snap.put('Longitude__c', lon);
        if (fmap.containsKey('Accuracy_Meters__c')) {
            snap.put('Accuracy_Meters__c', accuracy);
        }
        if (fmap.containsKey('Recorded_At__c')) {
            snap.put('Recorded_At__c', Datetime.now());
        }
        if (fmap.containsKey('Source__c')) {
            snap.put('Source__c', source);
        }
        if (fmap.containsKey('Is_Sharing__c')) {
            snap.put('Is_Sharing__c', true);
        }
        if (fmap.containsKey('Device_Model__c')) {
            snap.put('Device_Model__c', deviceModel);
        }
        if (fmap.containsKey('Device_OS__c')) {
            snap.put('Device_OS__c', deviceOs);
        }
        if (fmap.containsKey('App_Version__c')) {
            snap.put('App_Version__c', appVersion);
        }
        if (fmap.containsKey('Device_Id__c')) {
            snap.put('Device_Id__c', deviceId);
        }
        if (!existing.isEmpty()) {
            update snap;
        } else {
            insert snap;
        }
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static void rescheduleVisits(OutboxAction action) {
        if (action.payload == null || !action.payload.containsKey('items')) {
            return;
        }
        // Expected: { items: [{ visitId, plannedDate }] }
        List<Object> items = (List<Object>) action.payload.get('items');
        if (items == null || !Schema.getGlobalDescribe().containsKey('Visit__c')) {
            return;
        }
        List<SObject> updates = new List<SObject>();
        for (Object o : items) {
            Map<String, Object> m = (Map<String, Object>) o;
            SObject v = Schema.getGlobalDescribe().get('Visit__c').newSObject();
            v.put('Id', (String) m.get('visitId'));
            if (Schema.getGlobalDescribe().get('Visit__c').getDescribe().fields.getMap().containsKey('Planned_Date__c')) {
                v.put('Planned_Date__c', Date.valueOf(String.valueOf(m.get('plannedDate'))));
            }
            updates.add(v);
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static Datetime tryParse(String iso) {
        if (String.isBlank(iso)) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }
}
