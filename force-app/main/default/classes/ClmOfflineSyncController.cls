public with sharing class ClmOfflineSyncController {

    public class OfflineActionInput {
        @AuraEnabled public String actionType;
        @AuraEnabled public String clientActionKey;
        @AuraEnabled public String clientSessionKey;
        @AuraEnabled public String clientVisitKey;
        @AuraEnabled public String clientCoachingKey;
        @AuraEnabled public Id visitId;
        @AuraEnabled public Id presentationId;
        @AuraEnabled public String startedAtIso;
        @AuraEnabled public Id sequenceId;
        @AuraEnabled public Decimal dwellSeconds;
        @AuraEnabled public Boolean trackingPaused;
        @AuraEnabled public String responsesJson;
        @AuraEnabled public String ratingsJson;
        @AuraEnabled public Id layoutId;
        @AuraEnabled public String endedAtIso;
        @AuraEnabled public Decimal slidesPresentedCount;
        @AuraEnabled public Decimal totalDurationSeconds;
        @AuraEnabled public String callReportJson;
        @AuraEnabled public String payloadJson;
    }

    public class OfflineSyncResult {
        @AuraEnabled public Map<String, String> sessionIdByClientKey;
        @AuraEnabled public Map<String, String> visitIdByClientKey;
        @AuraEnabled public Map<String, String> coachingIdByClientKey;
        @AuraEnabled public List<String> failedClientKeys;
        @AuraEnabled public List<String> errorMessages;
    }

    @AuraEnabled
    public static OfflineSyncResult syncOfflineActions(List<OfflineActionInput> actions) {
        OfflineSyncResult result = new OfflineSyncResult();
        result.sessionIdByClientKey = new Map<String, String>();
        result.visitIdByClientKey = new Map<String, String>();
        result.coachingIdByClientKey = new Map<String, String>();
        result.failedClientKeys = new List<String>();
        result.errorMessages = new List<String>();

        if (actions == null || actions.isEmpty()) {
            return result;
        }

        for (OfflineActionInput action : actions) {
            if (action == null || String.isBlank(action.actionType)) {
                continue;
            }
            try {
                processAction(action, result);
            } catch (Exception ex) {
                String key = failureKey(action);
                result.failedClientKeys.add(key);
                result.errorMessages.add(action.actionType + ': ' + ex.getMessage());
            }
        }
        return result;
    }

    private static String failureKey(OfflineActionInput action) {
        if (String.isNotBlank(action.clientActionKey)) {
            return action.clientActionKey;
        }
        if (String.isNotBlank(action.clientSessionKey)) {
            return action.clientSessionKey;
        }
        if (String.isNotBlank(action.clientVisitKey)) {
            return action.clientVisitKey;
        }
        if (String.isNotBlank(action.clientCoachingKey)) {
            return action.clientCoachingKey;
        }
        return action.actionType;
    }

    private static void processAction(OfflineActionInput action, OfflineSyncResult result) {
        String actionType = action.actionType.toUpperCase();
        if (actionType == 'START_SESSION') {
            handleStartSession(action, result);
        } else if (actionType == 'START_ADHOC_SESSION') {
            handleStartAdHocSession(action, result);
        } else if (actionType == 'LOG_SLIDE_EVENT') {
            handleLogSlideEvent(action);
        } else if (actionType == 'SAVE_MESSAGE_RESPONSES') {
            handleSaveMessageResponses(action);
        } else if (actionType == 'SAVE_VISIT_RATINGS') {
            handleSaveVisitRatings(action, result);
        } else if (actionType == 'COMPLETE_SESSION') {
            handleCompleteSession(action);
        } else if (actionType == 'CANCEL_SESSION') {
            handleCancelSession(action);
        } else if (actionType == 'SAVE_CALL_REPORT') {
            handleSaveCallReport(action, result);
        } else if (actionType == 'UPSERT_VISIT') {
            handleUpsertVisit(action, result);
        } else if (actionType == 'RESCHEDULE_VISITS') {
            handleRescheduleVisits(action, result);
        } else if (actionType == 'CREATE_COACHING_EVENT') {
            handleCreateCoachingEvent(action, result);
        } else if (actionType == 'SUBMIT_COACHING_REVIEW') {
            handleSubmitCoachingReview(action, result);
        } else if (actionType == 'UPSERT_REP_LOCATION') {
            handleUpsertRepLocation(action);
        } else {
            throw new AuraHandledException('Unsupported action type: ' + action.actionType);
        }
    }

    private static void handleStartSession(OfflineActionInput action, OfflineSyncResult result) {
        if (String.isBlank(action.clientSessionKey)) {
            throw new AuraHandledException('Client session key is required.');
        }
        Id visitId = resolveVisitId(action, result);
        if (visitId == null || action.presentationId == null) {
            throw new AuraHandledException('Visit and presentation are required.');
        }

        Id existingId = ClmMetricsController.resolveSessionId(action.clientSessionKey);
        if (existingId != null) {
            result.sessionIdByClientKey.put(action.clientSessionKey, String.valueOf(existingId));
            return;
        }

        Visit__c visit = [
            SELECT Id, Status__c
            FROM Visit__c
            WHERE Id = :visitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled') {
            throw new AuraHandledException('Cannot start CLM on a completed or cancelled visit.');
        }

        List<CLM_Presentation__c> presentations = [
            SELECT Id, Name, Slide_Count__c, Format__c, Content_Document_Id__c,
                   Product__r.Name, Product__r.Product_Image_URL__c
            FROM CLM_Presentation__c
            WHERE Id = :action.presentationId AND Status__c = 'Available'
            WITH USER_MODE
            LIMIT 1
        ];
        if (presentations.isEmpty()) {
            throw new AuraHandledException('Presentation is not available.');
        }

        Datetime startedAt = parseIsoDatetime(action.startedAtIso);
        ClmMetricsController.SessionSummary session = ClmMetricsController.insertSessionForVisit(
            visitId,
            presentations[0],
            false,
            action.clientSessionKey,
            startedAt
        );
        result.sessionIdByClientKey.put(action.clientSessionKey, String.valueOf(session.id));
    }

    private static void handleStartAdHocSession(OfflineActionInput action, OfflineSyncResult result) {
        if (String.isBlank(action.clientSessionKey)) {
            throw new AuraHandledException('Client session key is required.');
        }
        if (action.presentationId == null) {
            throw new AuraHandledException('Presentation is required.');
        }

        Id existingId = ClmMetricsController.resolveSessionId(action.clientSessionKey);
        if (existingId != null) {
            result.sessionIdByClientKey.put(action.clientSessionKey, String.valueOf(existingId));
            if (String.isNotBlank(action.clientVisitKey)) {
                CLM_Presentation_Session__c existingSession = [
                    SELECT Visit__c
                    FROM CLM_Presentation_Session__c
                    WHERE Id = :existingId
                    WITH USER_MODE
                    LIMIT 1
                ];
                result.visitIdByClientKey.put(
                    action.clientVisitKey,
                    String.valueOf(existingSession.Visit__c)
                );
            }
            return;
        }

        List<CLM_Presentation__c> presentations = [
            SELECT Id, Name, Slide_Count__c
            FROM CLM_Presentation__c
            WHERE Id = :action.presentationId AND Status__c = 'Available'
            WITH USER_MODE
            LIMIT 1
        ];
        if (presentations.isEmpty()) {
            throw new AuraHandledException('Presentation is not available.');
        }

        DateTime now = parseIsoDatetime(action.startedAtIso);
        Visit__c visit = new Visit__c(
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = now,
            End_Date__c = now.addHours(1),
            Visit_Date__c = now,
            Status__c = 'Draft',
            Visit_Type__c = 'Unplanned',
            Client_Visit_Key__c = action.clientVisitKey
        );
        insert as user visit;

        if (String.isNotBlank(action.clientVisitKey)) {
            result.visitIdByClientKey.put(action.clientVisitKey, String.valueOf(visit.Id));
        }

        ClmMetricsController.SessionSummary session = ClmMetricsController.insertSessionForVisit(
            visit.Id,
            presentations[0],
            false,
            action.clientSessionKey,
            now
        );
        result.sessionIdByClientKey.put(action.clientSessionKey, String.valueOf(session.id));
    }

    private static void handleSaveCallReport(OfflineActionInput action, OfflineSyncResult result) {
        if (String.isBlank(action.callReportJson)) {
            throw new AuraHandledException('Call report payload is required.');
        }

        VisitCallReportService.SaveRequest request = parseCallReportRequest(action.callReportJson);
        Id visitId = request.visitId != null ? request.visitId : resolveVisitId(action, result);
        if (visitId == null) {
            throw new AuraHandledException('Visit is required for call report sync.');
        }
        request.visitId = visitId;

        VisitCallReportService.saveCallReport(request);
        result.visitIdByClientKey.put(String.valueOf(request.visitId), String.valueOf(request.visitId));
    }

    private static void handleUpsertVisit(OfflineActionInput action, OfflineSyncResult result) {
        Map<String, Object> payload = parsePayloadMap(action.payloadJson);
        Id existingVisitId = null;
        if (payload.containsKey('visitId') && payload.get('visitId') != null) {
            existingVisitId = (Id) String.valueOf(payload.get('visitId'));
        }
        if (existingVisitId == null && action.visitId != null) {
            existingVisitId = action.visitId;
        }

        if (existingVisitId == null && String.isNotBlank(action.clientVisitKey)) {
            Id mapped = resolveVisitIdByClientKey(action.clientVisitKey);
            if (mapped != null) {
                existingVisitId = mapped;
                result.visitIdByClientKey.put(action.clientVisitKey, String.valueOf(mapped));
                return;
            }
        }

        Id accountId = payload.get('accountId') == null
            ? null
            : (Id) String.valueOf(payload.get('accountId'));
        Id zetaProjectId = payload.get('zetaProjectId') == null
            ? null
            : (Id) String.valueOf(payload.get('zetaProjectId'));
        DateTime startDt = parseIsoDatetime((String) payload.get('startDateTime'));
        DateTime endDt = parseIsoDatetime((String) payload.get('endDateTime'));
        String status = (String) payload.get('status');
        String visitType = (String) payload.get('visitType');
        String cancellationReason = (String) payload.get('cancellationReason');
        String visitObjective = (String) payload.get('visitObjective');

        FieldPlannerController.VisitSummary saved = FieldPlannerController.upsertVisit(
            existingVisitId,
            accountId,
            startDt,
            endDt,
            status,
            visitType,
            cancellationReason,
            zetaProjectId,
            visitObjective
        );

        if (saved != null && saved.id != null) {
            if (String.isNotBlank(action.clientVisitKey)) {
                Visit__c keyUpdate = new Visit__c(
                    Id = saved.id,
                    Client_Visit_Key__c = action.clientVisitKey
                );
                update as user keyUpdate;
                result.visitIdByClientKey.put(action.clientVisitKey, String.valueOf(saved.id));
            }
            result.visitIdByClientKey.put(String.valueOf(saved.id), String.valueOf(saved.id));
        }
    }

    private static void handleRescheduleVisits(OfflineActionInput action, OfflineSyncResult result) {
        Map<String, Object> payload = parsePayloadMap(action.payloadJson);
        List<Object> visitIdsRaw = (List<Object>) payload.get('visitIds');
        List<Object> startsRaw = (List<Object>) payload.get('startDateTimes');
        List<Object> endsRaw = (List<Object>) payload.get('endDateTimes');
        if (visitIdsRaw == null || startsRaw == null || endsRaw == null) {
            throw new AuraHandledException('Reschedule lists are required.');
        }

        List<Id> visitIds = new List<Id>();
        List<DateTime> starts = new List<DateTime>();
        List<DateTime> ends = new List<DateTime>();
        for (Integer i = 0; i < visitIdsRaw.size(); i++) {
            String rawId = String.valueOf(visitIdsRaw[i]);
            Id visitId = resolveVisitIdFromRaw(rawId, action, result);
            if (visitId == null) {
                throw new AuraHandledException('Visit not found for reschedule: ' + rawId);
            }
            visitIds.add(visitId);
            starts.add(parseIsoDatetime(String.valueOf(startsRaw[i])));
            ends.add(parseIsoDatetime(String.valueOf(endsRaw[i])));
        }

        List<FieldPlannerController.VisitSummary> updated =
            FieldPlannerController.rescheduleVisits(visitIds, starts, ends);
        for (FieldPlannerController.VisitSummary row : updated) {
            result.visitIdByClientKey.put(String.valueOf(row.id), String.valueOf(row.id));
        }
    }

    private static void handleCreateCoachingEvent(OfflineActionInput action, OfflineSyncResult result) {
        if (String.isNotBlank(action.clientCoachingKey)) {
            Id existing = resolveCoachingIdByClientKey(action.clientCoachingKey);
            if (existing != null) {
                result.coachingIdByClientKey.put(action.clientCoachingKey, String.valueOf(existing));
                return;
            }
        }

        Map<String, Object> payload = parsePayloadMap(action.payloadJson);
        Id visitId = resolveVisitId(action, result);
        if (visitId == null && payload.get('visitId') != null) {
            visitId = (Id) String.valueOf(payload.get('visitId'));
        }
        Id templateId = payload.get('templateId') == null
            ? null
            : (Id) String.valueOf(payload.get('templateId'));
        Boolean prefill = payload.get('prefillFromVisit') == null
            ? true
            : Boolean.valueOf(String.valueOf(payload.get('prefillFromVisit')));

        if (visitId == null || templateId == null) {
            throw new AuraHandledException('Visit and template are required for coaching.');
        }

        VisitCoachingController.CreateResult created =
            VisitCoachingController.createVisitCoachingEvent(visitId, templateId, prefill);

        if (created != null && created.coachingEventId != null) {
            if (String.isNotBlank(action.clientCoachingKey)) {
                Coaching_Event__c keyUpdate = new Coaching_Event__c(
                    Id = created.coachingEventId,
                    Client_Coaching_Key__c = action.clientCoachingKey
                );
                update as user keyUpdate;
                result.coachingIdByClientKey.put(
                    action.clientCoachingKey,
                    String.valueOf(created.coachingEventId)
                );
            }
            result.coachingIdByClientKey.put(
                String.valueOf(created.coachingEventId),
                String.valueOf(created.coachingEventId)
            );
        }
    }

    private static void handleSubmitCoachingReview(OfflineActionInput action, OfflineSyncResult result) {
        Map<String, Object> payload = parsePayloadMap(action.payloadJson);
        Id coachingEventId = null;
        if (payload.get('coachingEventId') != null) {
            String raw = String.valueOf(payload.get('coachingEventId'));
            if (raw.startsWith('local_') || raw.startsWith('coaching_')) {
                if (String.isNotBlank(action.clientCoachingKey)) {
                    coachingEventId = resolveCoachingIdByClientKey(action.clientCoachingKey);
                    if (coachingEventId == null) {
                        coachingEventId = result.coachingIdByClientKey.containsKey(action.clientCoachingKey)
                            ? (Id) result.coachingIdByClientKey.get(action.clientCoachingKey)
                            : null;
                    }
                }
            } else {
                coachingEventId = (Id) raw;
            }
        }
        if (coachingEventId == null && String.isNotBlank(action.clientCoachingKey)) {
            coachingEventId = resolveCoachingIdByClientKey(action.clientCoachingKey);
            if (coachingEventId == null && result.coachingIdByClientKey.containsKey(action.clientCoachingKey)) {
                coachingEventId = (Id) result.coachingIdByClientKey.get(action.clientCoachingKey);
            }
        }
        if (coachingEventId == null) {
            throw new AuraHandledException('Coaching event is required for submit.');
        }

        VisitCoachingController.submitForManagerReview(coachingEventId);
        result.coachingIdByClientKey.put(String.valueOf(coachingEventId), String.valueOf(coachingEventId));
        if (String.isNotBlank(action.clientCoachingKey)) {
            result.coachingIdByClientKey.put(action.clientCoachingKey, String.valueOf(coachingEventId));
        }
    }

    private static void handleUpsertRepLocation(OfflineActionInput action) {
        Map<String, Object> payload = parsePayloadMap(action.payloadJson);
        Decimal lat = payload.get('latitude') == null
            ? null
            : Decimal.valueOf(String.valueOf(payload.get('latitude')));
        Decimal lon = payload.get('longitude') == null
            ? null
            : Decimal.valueOf(String.valueOf(payload.get('longitude')));
        Decimal accuracy = payload.get('accuracyMeters') == null
            ? null
            : Decimal.valueOf(String.valueOf(payload.get('accuracyMeters')));
        String source = payload.containsKey('source') ? String.valueOf(payload.get('source')) : 'Browser';
        String deviceModel = payload.containsKey('deviceModel')
            ? String.valueOf(payload.get('deviceModel'))
            : null;
        String deviceOs = payload.containsKey('deviceOs') ? String.valueOf(payload.get('deviceOs')) : null;
        String appVersion = payload.containsKey('appVersion')
            ? String.valueOf(payload.get('appVersion'))
            : null;
        String deviceId = payload.containsKey('deviceId') ? String.valueOf(payload.get('deviceId')) : null;
        RepLocationService.upsertSnapshotFull(
            lat,
            lon,
            accuracy,
            source,
            deviceModel,
            deviceOs,
            appVersion,
            deviceId
        );
    }

    private static VisitCallReportService.SaveRequest parseCallReportRequest(String jsonValue) {
        return (VisitCallReportService.SaveRequest) JSON.deserialize(
            jsonValue,
            VisitCallReportService.SaveRequest.class
        );
    }

    private static Map<String, Object> parsePayloadMap(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            return new Map<String, Object>();
        }
        Object raw = JSON.deserializeUntyped(payloadJson);
        if (!(raw instanceof Map<String, Object>)) {
            throw new AuraHandledException('Invalid payload JSON.');
        }
        return (Map<String, Object>) raw;
    }

    private static Id resolveVisitId(OfflineActionInput action, OfflineSyncResult result) {
        if (action.visitId != null) {
            return action.visitId;
        }
        if (String.isNotBlank(action.clientVisitKey)) {
            if (result.visitIdByClientKey.containsKey(action.clientVisitKey)) {
                return (Id) result.visitIdByClientKey.get(action.clientVisitKey);
            }
            return resolveVisitIdByClientKey(action.clientVisitKey);
        }
        return null;
    }

    private static Id resolveVisitIdFromRaw(
        String rawId,
        OfflineActionInput action,
        OfflineSyncResult result
    ) {
        if (String.isBlank(rawId)) {
            return null;
        }
        if (rawId.startsWith('local_') || rawId.startsWith('visit_')) {
            if (result.visitIdByClientKey.containsKey(rawId)) {
                return (Id) result.visitIdByClientKey.get(rawId);
            }
            return resolveVisitIdByClientKey(rawId);
        }
        try {
            return (Id) rawId;
        } catch (Exception ex) {
            return resolveVisitIdByClientKey(rawId);
        }
    }

    private static Id resolveVisitIdByClientKey(String clientVisitKey) {
        if (String.isBlank(clientVisitKey)) {
            return null;
        }
        List<Visit__c> visits = [
            SELECT Id
            FROM Visit__c
            WHERE Client_Visit_Key__c = :clientVisitKey
            WITH USER_MODE
            LIMIT 1
        ];
        return visits.isEmpty() ? null : visits[0].Id;
    }

    private static Id resolveCoachingIdByClientKey(String clientCoachingKey) {
        if (String.isBlank(clientCoachingKey)) {
            return null;
        }
        List<Coaching_Event__c> events = [
            SELECT Id
            FROM Coaching_Event__c
            WHERE Client_Coaching_Key__c = :clientCoachingKey
            WITH USER_MODE
            LIMIT 1
        ];
        return events.isEmpty() ? null : events[0].Id;
    }

    private static void handleLogSlideEvent(OfflineActionInput action) {
        Id sessionId = requireSessionId(action.clientSessionKey);
        ClmMetricsController.logSlideEvent(
            sessionId,
            action.sequenceId,
            action.dwellSeconds,
            action.trackingPaused
        );
    }

    private static void handleSaveMessageResponses(OfflineActionInput action) {
        Id sessionId = requireSessionId(action.clientSessionKey);
        List<ClmMetricsController.MessageResponseInput> responses =
            parseMessageResponses(action.responsesJson);
        ClmMetricsController.saveMessageResponses(sessionId, responses);
    }

    private static void handleSaveVisitRatings(OfflineActionInput action, OfflineSyncResult result) {
        Id sessionId = requireSessionId(action.clientSessionKey);
        Id visitId = resolveVisitId(action, result);
        if (visitId == null) {
            throw new AuraHandledException('Visit is required for ratings.');
        }
        List<ClmMetricsController.VisitRatingFieldInput> values = parseRatingValues(action.ratingsJson);
        ClmMetricsController.saveVisitRatings(visitId, sessionId, action.layoutId, values);
    }

    private static void handleCompleteSession(OfflineActionInput action) {
        Id sessionId = requireSessionId(action.clientSessionKey);
        ClmMetricsController.completeSession(sessionId);
        if (action.slidesPresentedCount != null || action.totalDurationSeconds != null) {
            CLM_Presentation_Session__c session = new CLM_Presentation_Session__c(Id = sessionId);
            if (action.slidesPresentedCount != null) {
                session.Slides_Presented_Count__c = action.slidesPresentedCount;
            }
            if (action.totalDurationSeconds != null) {
                session.Total_Duration_Seconds__c = action.totalDurationSeconds;
            }
            if (String.isNotBlank(action.endedAtIso)) {
                session.Ended_At__c = parseIsoDatetime(action.endedAtIso);
            }
            update as user session;
        }
    }

    private static void handleCancelSession(OfflineActionInput action) {
        Id sessionId = requireSessionId(action.clientSessionKey);
        ClmMetricsController.cancelSession(sessionId);
    }

    private static Id requireSessionId(String clientSessionKey) {
        Id sessionId = ClmMetricsController.resolveSessionId(clientSessionKey);
        if (sessionId == null) {
            throw new AuraHandledException('Session not found for client key: ' + clientSessionKey);
        }
        return sessionId;
    }

    private static Datetime parseIsoDatetime(String isoValue) {
        if (String.isBlank(isoValue)) {
            return System.now();
        }
        try {
            if (isoValue.startsWith('"')) {
                return (Datetime) JSON.deserialize(isoValue, Datetime.class);
            }
            return (Datetime) JSON.deserialize('"' + isoValue + '"', Datetime.class);
        } catch (Exception ex) {
            return System.now();
        }
    }

    private static List<ClmMetricsController.MessageResponseInput> parseMessageResponses(String jsonValue) {
        List<ClmMetricsController.MessageResponseInput> results =
            new List<ClmMetricsController.MessageResponseInput>();
        if (String.isBlank(jsonValue)) {
            return results;
        }
        Object raw = JSON.deserializeUntyped(jsonValue);
        if (!(raw instanceof List<Object>)) {
            return results;
        }
        for (Object item : (List<Object>) raw) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> row = (Map<String, Object>) item;
            ClmMetricsController.MessageResponseInput input = new ClmMetricsController.MessageResponseInput();
            input.productName = (String) row.get('productName');
            input.messageName = (String) row.get('messageName');
            input.sentiment = (String) row.get('sentiment');
            Object sortOrder = row.get('sortOrder');
            if (sortOrder != null) {
                input.sortOrder = Integer.valueOf(String.valueOf(sortOrder));
            }
            results.add(input);
        }
        return results;
    }

    private static List<ClmMetricsController.VisitRatingFieldInput> parseRatingValues(String jsonValue) {
        List<ClmMetricsController.VisitRatingFieldInput> results =
            new List<ClmMetricsController.VisitRatingFieldInput>();
        if (String.isBlank(jsonValue)) {
            return results;
        }
        Object raw = JSON.deserializeUntyped(jsonValue);
        if (!(raw instanceof List<Object>)) {
            return results;
        }
        for (Object item : (List<Object>) raw) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> row = (Map<String, Object>) item;
            ClmMetricsController.VisitRatingFieldInput input = new ClmMetricsController.VisitRatingFieldInput();
            input.objectApiName = (String) row.get('objectApiName');
            input.fieldApiName = (String) row.get('fieldApiName');
            Object valueJson = row.get('valueJson');
            input.valueJson = valueJson == null ? null : String.valueOf(valueJson);
            results.add(input);
        }
        return results;
    }
}
