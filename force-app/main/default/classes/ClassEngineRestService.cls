/**
 * REST facade for the Class Engine tab used by the offline PWA.
 */
@RestResource(urlMapping='/class-engine/v1/*')
global with sharing class ClassEngineRestService {
    global class ErrorResponse {
        public String message;
        public ErrorResponse(String message) {
            this.message = message;
        }
    }

    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        try {
            String path = restPath(req);
            if (path == 'page' || path == '') {
                writeJson(
                    res,
                    200,
                    ClassEngineController.getPage(
                        blankToNullId(req.params.get('employeeId')),
                        req.params.get('quarter'),
                        blankToNullId(req.params.get('territoryId'))
                    )
                );
                return;
            }
            writeJson(res, 404, new ErrorResponse('Unknown GET path: ' + path));
        } catch (Exception e) {
            writeJson(res, 400, new ErrorResponse(userMessage(e)));
        }
    }

    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        try {
            String path = restPath(req);
            String body = req.requestBody == null ? '{}' : req.requestBody.toString();
            Map<String, Object> payload = parseJsonMap(body);

            if (path == 'save-ratings') {
                ClassEngineController.saveProductRatings(
                    blankToNullId(stringFrom(payload.get('accountId'))),
                    blankToNullId(stringFrom(payload.get('territoryId'))),
                    blankToNullId(stringFrom(payload.get('product2Id'))),
                    toDecimal(payload.get('potential')),
                    toDecimal(payload.get('penetration'))
                );
                writeJson(res, 200, new Map<String, Object>{ 'ok' => true });
                return;
            }
            if (path == 'classify') {
                writeJson(
                    res,
                    200,
                    ClassEngineController.classify(
                        blankToNullId(stringFrom(payload.get('employeeId'))),
                        stringFrom(payload.get('quarter')),
                        blankToNullId(stringFrom(payload.get('territoryId')))
                    )
                );
                return;
            }
            if (path == 'save-chosen') {
                writeJson(
                    res,
                    200,
                    ClassEngineController.saveChosenClasses(
                        blankToNullId(stringFrom(payload.get('cycleId'))),
                        parseChosenUpdates(payload.get('updates'))
                    )
                );
                return;
            }
            if (path == 'submit') {
                writeJson(
                    res,
                    200,
                    ClassEngineController.submitCycle(
                        blankToNullId(stringFrom(payload.get('cycleId'))),
                        stringFrom(payload.get('quarter'))
                    )
                );
                return;
            }
            if (path == 'approve') {
                writeJson(
                    res,
                    200,
                    ClassEngineController.approveCycle(
                        blankToNullId(stringFrom(payload.get('cycleId'))),
                        parseChosenUpdates(payload.get('managerOverrides'))
                    )
                );
                return;
            }
            if (path == 'reject') {
                writeJson(
                    res,
                    200,
                    ClassEngineController.rejectCycle(
                        blankToNullId(stringFrom(payload.get('cycleId'))),
                        stringFrom(payload.get('reason'))
                    )
                );
                return;
            }
            writeJson(res, 404, new ErrorResponse('Unknown POST path: ' + path));
        } catch (Exception e) {
            writeJson(res, 400, new ErrorResponse(userMessage(e)));
        }
    }

    private static List<ClassEngineController.ChosenClassUpdate> parseChosenUpdates(Object raw) {
        if (raw == null) {
            return new List<ClassEngineController.ChosenClassUpdate>();
        }
        return (List<ClassEngineController.ChosenClassUpdate>) JSON.deserialize(
            JSON.serialize(raw),
            List<ClassEngineController.ChosenClassUpdate>.class
        );
    }

    private static String restPath(RestRequest req) {
        String uri = req.requestURI == null ? '' : req.requestURI;
        Integer idx = uri.indexOf('/class-engine/v1/');
        if (idx < 0) {
            return '';
        }
        String path = uri.substring(idx + '/class-engine/v1/'.length());
        Integer q = path.indexOf('?');
        if (q >= 0) {
            path = path.substring(0, q);
        }
        if (path.startsWith('/')) {
            path = path.substring(1);
        }
        return path;
    }

    private static void writeJson(RestResponse res, Integer statusCode, Object body) {
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(body));
    }

    private static Map<String, Object> parseJsonMap(String body) {
        if (String.isBlank(body)) {
            return new Map<String, Object>();
        }
        Object parsed = JSON.deserializeUntyped(body);
        if (parsed instanceof Map<String, Object>) {
            return (Map<String, Object>) parsed;
        }
        return new Map<String, Object>();
    }

    private static String stringFrom(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Id blankToNullId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Decimal toDecimal(Object value) {
        if (value == null || value == '') {
            return null;
        }
        return Decimal.valueOf(String.valueOf(value));
    }

    private static String userMessage(Exception e) {
        if (e instanceof AuraHandledException) {
            return e.getMessage();
        }
        return e.getMessage();
    }
}