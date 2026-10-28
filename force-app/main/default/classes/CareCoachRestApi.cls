/**
 * Apex REST bridge for the offline field app (salesforceoffline.com).
 * GET  /services/apexrest/carecoach/v1/{method}?p={json}  read methods (cached offline by the app)
 * POST /services/apexrest/carecoach/v1/{method}  body {json}  write methods
 * Each method maps 1:1 to the @AuraEnabled method the Care Coach LWCs call in Lightning,
 * so masking, sharing and FLS behave exactly as they do in the org.
 */
@RestResource(urlMapping='/carecoach/v1/*')
global with sharing class CareCoachRestApi {
    private static final Set<String> READ_METHODS = new Set<String>{
        'getContext',
        'getFilterOptions',
        'getPatients',
        'getPatient360',
        'getHomeData',
        'getPlannerData',
        'getProducts',
        'getOrders',
        'getCallRecording',
        'getScripts',
        'getScript'
    };

    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        String raw = req.params.get('p');
        respond(methodName(req), String.isBlank(raw) ? null : raw, true);
    }

    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        String raw = req.requestBody == null ? null : req.requestBody.toString();
        respond(methodName(req), raw, false);
    }

    private static String methodName(RestRequest req) {
        return req.requestURI.substringAfterLast('/').substringBefore('?');
    }

    private static void respond(String method, String rawParams, Boolean isRead) {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        Savepoint sp = isRead ? null : Database.setSavepoint();
        try {
            if (isRead != READ_METHODS.contains(method)) {
                throw new CareCoachAccess.CareCoachException(
                    (isRead ? 'Use POST for ' : 'Use GET for ') + method + '.'
                );
            }
            Map<String, Object> params = String.isBlank(rawParams)
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(rawParams);
            Object result = dispatch(method, params);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(result == null ? 'null' : JSON.serialize(result, true));
        } catch (Exception e) {
            if (sp != null) {
                Database.rollback(sp);
            }
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'message' => e.getMessage() }));
        }
    }

    @TestVisible
    private static Object dispatch(String method, Map<String, Object> p) {
        switch on method {
            when 'getContext' {
                return CareCoachAccess.getContext();
            }
            when 'getFilterOptions' {
                return CareCoachPatientService.getFilterOptions();
            }
            when 'getPatients' {
                return CareCoachPatientService.getPatients(strVal(p, 'filtersJson'));
            }
            when 'getPatient360' {
                return CareCoachPatientService.getPatient360(idVal(p, 'patientId'), strVal(p, 'mode'));
            }
            when 'logInteraction' {
                return CareCoachPatientService.logInteraction(idVal(p, 'patientId'), strVal(p, 'payloadJson'));
            }
            when 'updateInteraction' {
                return CareCoachPatientService.updateInteraction(idVal(p, 'interactionId'), strVal(p, 'payloadJson'));
            }
            when 'getCallRecording' {
                return CareCoachTelephonyController.getCallRecording(idVal(p, 'interactionId'));
            }
            when 'createOrder' {
                return CareCoachPatientService.createOrder(
                    idVal(p, 'patientId'),
                    idVal(p, 'productId'),
                    intVal(p, 'quantity'),
                    strVal(p, 'channel'),
                    strVal(p, 'notes')
                );
            }
            when 'updatePatientStatus' {
                CareCoachPatientService.updatePatientStatus(idVal(p, 'patientId'), strVal(p, 'status'), strVal(p, 'dropReason'));
                return null;
            }
            when 'analyze' {
                return CareCoachCallAnalysisService.analyze(idVal(p, 'interactionId'));
            }
            when 'preview' {
                return CareCoachCallAnalysisService.preview(strVal(p, 'transcript'));
            }
            when 'getHomeData' {
                return CareCoachHomeController.getHomeData(strVal(p, 'mode'), strVal(p, 'scope'), strVal(p, 'coachId'));
            }
            when 'getPlannerData' {
                return CareCoachPlannerController.getPlannerData(dateVal(p, 'startDate'), intVal(p, 'days'), strVal(p, 'mode'));
            }
            when 'scheduleCall' {
                return CareCoachPlannerController.scheduleCall(
                    idVal(p, 'patientId'),
                    dtVal(p, 'startTime'),
                    intVal(p, 'durationMinutes'),
                    strVal(p, 'reason'),
                    strVal(p, 'direction'),
                    strVal(p, 'notes')
                );
            }
            when 'rescheduleCall' {
                return CareCoachPlannerController.rescheduleCall(idVal(p, 'callId'), dtVal(p, 'startTime'), intVal(p, 'durationMinutes'));
            }
            when 'deleteCall' {
                CareCoachPlannerController.deleteCall(idVal(p, 'callId'));
                return null;
            }
            when 'completeCall' {
                return CareCoachPlannerController.completeCall(idVal(p, 'callId'), strVal(p, 'payloadJson'));
            }
            when 'createTimeOff' {
                return CareCoachPlannerController.createTimeOff(
                    strVal(p, 'typeValue'),
                    strVal(p, 'spanType'),
                    strVal(p, 'durationHours'),
                    dtVal(p, 'startTime'),
                    strVal(p, 'comments'),
                    boolVal(p, 'submit')
                );
            }
            when 'updateTimeOff' {
                return CareCoachPlannerController.updateTimeOff(
                    idVal(p, 'timeOffId'),
                    strVal(p, 'typeValue'),
                    strVal(p, 'spanType'),
                    strVal(p, 'durationHours'),
                    dtVal(p, 'startTime'),
                    strVal(p, 'comments')
                );
            }
            when 'setTimeOffStage' {
                return CareCoachPlannerController.setTimeOffStage(idVal(p, 'timeOffId'), strVal(p, 'stage'));
            }
            // POST so SIP credentials and the transcription ticket are never cached offline.
            when 'getDialerConfig' {
                return CareCoachTelephonyController.getDialerConfig();
            }
            when 'attachCallRecording' {
                return CareCoachTelephonyController.attachCallRecording(idVal(p, 'callId'), strVal(p, 'fileName'), strVal(p, 'base64Data'));
            }
            when 'requestSentiment' {
                CareCoachTelephonyController.requestSentiment(idVal(p, 'callId'));
                return null;
            }
            when 'moveTimeOff' {
                return CareCoachPlannerController.moveTimeOff(idVal(p, 'timeOffId'), dtVal(p, 'startTime'));
            }
            when 'deleteTimeOff' {
                CareCoachPlannerController.deleteTimeOff(idVal(p, 'timeOffId'));
                return null;
            }
            when 'getProducts' {
                return CareCoachCatalogController.getProducts(strVal(p, 'scope'));
            }
            when 'getOrders' {
                return CareCoachOrderService.getOrders(strVal(p, 'mode'), strVal(p, 'scope'), intVal(p, 'days'));
            }
            when 'updateOrderStatus' {
                return CareCoachOrderService.updateOrderStatus(idVal(p, 'orderId'), strVal(p, 'status'), strVal(p, 'trackingNumber'));
            }
            when 'getScripts' {
                return CareCoachCatalogController.getScripts(
                    strVal(p, 'search'),
                    strVal(p, 'productId'),
                    strVal(p, 'category'),
                    boolVal(p, 'publishedOnly')
                );
            }
            when 'getScript' {
                return CareCoachCatalogController.getScript(idVal(p, 'scriptId'));
            }
            when 'markHelpful' {
                return CareCoachCatalogController.markHelpful(idVal(p, 'scriptId'));
            }
            when else {
                throw new CareCoachAccess.CareCoachException('Unknown Care Coach method: ' + method);
            }
        }
    }

    private static String strVal(Map<String, Object> p, String key) {
        Object v = p.get(key);
        if (v == null) {
            return null;
        }
        if (v instanceof String) {
            return (String) v;
        }
        return v instanceof Map<String, Object> || v instanceof List<Object> ? JSON.serialize(v) : String.valueOf(v);
    }

    private static Id idVal(Map<String, Object> p, String key) {
        String v = strVal(p, key);
        return String.isBlank(v) ? null : Id.valueOf(v);
    }

    private static Integer intVal(Map<String, Object> p, String key) {
        String v = strVal(p, key);
        return String.isBlank(v) ? null : Decimal.valueOf(v).intValue();
    }

    private static Boolean boolVal(Map<String, Object> p, String key) {
        Object v = p.get(key);
        if (v == null) {
            return null;
        }
        return v instanceof Boolean ? (Boolean) v : Boolean.valueOf(String.valueOf(v));
    }

    private static Date dateVal(Map<String, Object> p, String key) {
        String v = strVal(p, key);
        return String.isBlank(v) ? null : Date.valueOf(v.left(10));
    }

    private static Datetime dtVal(Map<String, Object> p, String key) {
        String v = strVal(p, key);
        if (String.isBlank(v)) {
            return null;
        }
        return (Datetime) JSON.deserialize('"' + v + '"', Datetime.class);
    }
}