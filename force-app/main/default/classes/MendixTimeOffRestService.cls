@RestResource(urlMapping='/mendix/v1/time-off/*')
global with sharing class MendixTimeOffRestService {
    @HttpPost
    global static void closeTimeOff() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        try {
            String body = req.requestBody == null ? null : req.requestBody.toString();
            if (String.isBlank(body)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('{"error":"Request body is required."}');
                return;
            }
            MendixSyncService.ClosurePayload payload = (MendixSyncService.ClosurePayload) JSON.deserialize(
                body,
                MendixSyncService.ClosurePayload.class
            );
            Time_Off_Request__c updated = MendixSyncService.applyClosure(payload);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(
                JSON.serialize(
                    new Map<String, Object>{
                        'id' => updated.Id,
                        'stage' => updated.Stage__c,
                        'mendixExternalId' => updated.Mendix_External_Id__c
                    }
                )
            );
        } catch (Exception ex) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'error' => ex.getMessage() }));
        }
    }
}