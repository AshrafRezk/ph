/**
 * Field app (salesforceoffline.com) DM team target list, through TeamTargetListController so the
 * same team and limit rules apply online.
 * GET  /team-targets/v1/list?repId=&quarter=Q4-2026
 * POST /team-targets/v1/frequency { atfId, frequency, monthStart: "2026-11-01", quarter }
 * POST /team-targets/v1/remove    { atfId }
 * POST /team-targets/v1/propose   { repId, accountId }
 */
@RestResource(urlMapping='/team-targets/v1/*')
global with sharing class TeamTargetListRestService {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        try {
            if (path(req) == 'list') {
                write(res, 200, TeamTargetListController.getTeamTargets(toId(req.params.get('repId')), req.params.get('quarter')));
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
            String p = path(req);
            if (p == 'frequency') {
                Object raw = body.get('frequency');
                Decimal frequency = raw == null ? null : Decimal.valueOf(String.valueOf(raw));
                Object month = body.get('monthStart');
                write(
                    res,
                    200,
                    TeamTargetListController.setFrequency(
                        toId(body.get('atfId')),
                        frequency,
                        month == null || String.isBlank(String.valueOf(month)) ? null : Date.valueOf(String.valueOf(month)),
                        (String) body.get('quarter')
                    )
                );
            } else if (p == 'remove') {
                write(res, 200, TeamTargetListController.removeFromTargetList(toId(body.get('atfId'))));
            } else if (p == 'propose') {
                write(res, 200, TeamTargetListController.proposeForTargetList(toId(body.get('repId')), toId(body.get('accountId'))));
            } else {
                write(res, 404, new Map<String, String>{ 'message' => 'Unknown path: ' + p });
            }
        } catch (Exception e) {
            write(res, 400, new Map<String, String>{ 'message' => e.getMessage() });
        }
    }

    private static String path(RestRequest req) {
        return req.requestURI.substringAfter('/team-targets/v1/').substringBefore('?');
    }

    private static Id toId(Object raw) {
        return raw == null || String.isBlank(String.valueOf(raw)) ? null : (Id) String.valueOf(raw);
    }

    private static void write(RestResponse res, Integer status, Object body) {
        res.statusCode = status;
        res.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
