/**
 * Read API for the offline app. Delegates to the same controllers the
 * Workforce and My Team Lightning pages use, so offline matches Salesforce.
 */
@RestResource(urlMapping='/management/v1/*')
global with sharing class ManagementOfflineRestService {
    @HttpGet
    global static void doGet() {
        RestResponse res = RestContext.response;
        try {
            String path = requestPath();
            Map<String, String> params = RestContext.request.params;
            if (path == 'business-units') {
                writeJson(res, 200, TerritoryHierarchyService.getBusinessUnitOptions());
            } else if (path == 'lines') {
                writeJson(res, 200, TerritoryHierarchyService.getLineOptions(optionalId(params.get('businessUnitTerritoryId'))));
            } else if (path == 'districts') {
                writeJson(res, 200, TerritoryHierarchyService.getDistrictOptions(optionalId(params.get('lineTerritoryId'))));
            } else if (path == 'team-kpis') {
                writeJson(
                    res,
                    200,
                    ManagementKpiController.getTeamKpis(
                        params.get('buTerritoryId'),
                        params.get('lineTerritoryId'),
                        params.get('districtTerritoryId'),
                        params.get('periodMonthKey')
                    )
                );
            } else if (path == 'workforce-roster') {
                writeJson(
                    res,
                    200,
                    ManagementKpiController.getWorkforceRoster(
                        params.get('workforceType'),
                        params.get('buTerritoryId'),
                        params.get('lineTerritoryId'),
                        params.get('districtTerritoryId')
                    )
                );
            } else if (path == 'product-performance') {
                writeJson(
                    res,
                    200,
                    ManagementKpiController.getExecutiveBuProductPerformance(
                        params.get('buTerritoryId'),
                        params.get('lineTerritoryId'),
                        params.get('districtTerritoryId')
                    )
                );
            } else if (path == 'rep-accounts') {
                writeJson(
                    res,
                    200,
                    ManagementKpiController.getRepAccountKpiDrillDown(
                        optionalId(params.get('repUserId')),
                        params.get('periodMonthKey')
                    )
                );
            } else if (path == 'my-team') {
                writeJson(res, 200, MyTeamController.getMyTeamTree());
            } else if (path == 'pending-meetings') {
                writeJson(res, 200, MeetingPlannerController.getPendingMeetingApprovals());
            } else if (path == 'pending-time-off') {
                writeJson(res, 200, TimeOffRequestController.getPendingApprovals());
            } else {
                writeJson(res, 404, new Map<String, String>{ 'message' => 'Unknown path: ' + path });
            }
        } catch (Exception ex) {
            writeJson(res, 400, new Map<String, String>{ 'message' => ex.getMessage() });
        }
    }

    private static String requestPath() {
        String uri = RestContext.request.requestURI == null ? '' : RestContext.request.requestURI;
        String path = uri.substringAfter('/management/v1/');
        Integer query = path.indexOf('?');
        if (query >= 0) {
            path = path.substring(0, query);
        }
        return path;
    }

    private static Id optionalId(String raw) {
        if (String.isBlank(raw) || raw == 'ALL' || raw == 'null') {
            return null;
        }
        try {
            return (Id) raw;
        } catch (Exception ex) {
            return null;
        }
    }

    private static void writeJson(RestResponse res, Integer statusCode, Object payload) {
        res.statusCode = statusCode;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(payload));
    }
}