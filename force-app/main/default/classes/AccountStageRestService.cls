/**
 * Field app (salesforceoffline.com) account close-out actions, through AccountStageService so the
 * "only SFE, Field Intelligence, BU or admins" rule applies online as well as in the offline outbox.
 * GET  /account-stage/v1/permissions?accountId=  → { canMarkInactive, canMarkDuplicate }
 * POST /account-stage/v1/mark-inactive  { accountId, reason }
 * POST /account-stage/v1/mark-duplicate { accountId, duplicateOfId }
 */
@RestResource(urlMapping='/account-stage/v1/*')
global with sharing class AccountStageRestService {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        try {
            if (path(req) == 'permissions') {
                AccountStageService.StageView view = AccountStageService.getStage((Id) req.params.get('accountId'));
                write(res, 200, new Map<String, Object>{
                    'canMarkInactive' => view.canMarkInactive == true,
                    'canMarkDuplicate' => view.canMarkDuplicate == true
                });
            } else {
                write(res, 404, new Map<String, String>{ 'message' => 'Unknown path: ' + path(req) });
            }
        } catch (Exception e) {
            write(res, 400, new Map<String, String>{ 'message' => e.getMessage() });
        }
    }

    @HttpPost
    global static void post() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        try {
            Map<String, Object> body = req.requestBody == null || req.requestBody.size() == 0
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
            Id accountId = toId(body.get('accountId'));
            String p = path(req);
            if (p == 'mark-inactive') {
                write(res, 200, AccountStageService.markInactive(accountId, (String) body.get('reason')));
            } else if (p == 'mark-duplicate') {
                write(res, 200, AccountStageService.markDuplicate(accountId, toId(body.get('duplicateOfId'))));
            } else {
                write(res, 404, new Map<String, String>{ 'message' => 'Unknown path: ' + p });
            }
        } catch (Exception e) {
            write(res, 400, new Map<String, String>{ 'message' => e.getMessage() });
        }
    }

    private static String path(RestRequest req) {
        return req.requestURI.substringAfter('/account-stage/v1/').substringBefore('?');
    }

    private static Id toId(Object raw) {
        return raw == null || String.isBlank(String.valueOf(raw)) ? null : (Id) String.valueOf(raw);
    }

    private static void write(RestResponse res, Integer status, Object body) {
        res.statusCode = status;
        res.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
