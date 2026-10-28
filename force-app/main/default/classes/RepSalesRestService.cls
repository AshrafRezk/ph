/**
 * Field app (salesforceoffline.com) access to the rep Home "Sales vs Target" card.
 * GET /rep-sales/v1/summary?monthsBack=3        → RepSalesTargetController.getMySalesVsTarget
 * GET /rep-sales/v1/bricks?month=2026-09&product= → RepSalesTargetController.getMySalesByBrick
 */
@RestResource(urlMapping='/rep-sales/v1/*')
global with sharing class RepSalesRestService {
    @HttpGet
    global static void get() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        String path = req.requestURI.substringAfter('/rep-sales/v1/').substringBefore('?');
        try {
            if (path == 'summary') {
                String raw = req.params.get('monthsBack');
                Integer monthsBack = String.isBlank(raw) ? null : Integer.valueOf(raw);
                write(res, 200, RepSalesTargetController.getMySalesVsTarget(monthsBack));
            } else if (path == 'bricks') {
                write(res, 200, RepSalesTargetController.getMySalesByBrick(req.params.get('month'), req.params.get('product')));
            } else {
                write(res, 404, new Map<String, String>{ 'message' => 'Unknown path: ' + path });
            }
        } catch (Exception e) {
            write(res, 400, new Map<String, String>{ 'message' => e.getMessage() });
        }
    }

    private static void write(RestResponse res, Integer status, Object body) {
        res.statusCode = status;
        res.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
