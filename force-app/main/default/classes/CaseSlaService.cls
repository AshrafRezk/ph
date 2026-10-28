public with sharing class CaseSlaService {
    public static final Integer DEFAULT_SLA_HOURS = 24;

    public static void applyStageTiming(Case caseRecord) {
        if (
            !hasSlaFields() ||
            caseRecord == null ||
            caseRecord.IsClosed ||
            caseRecord.Status == 'Closed'
        ) {
            return;
        }

        Datetime now = System.now();
        caseRecord.put('Stage_Start_Time__c', now);
        caseRecord.put('Stage_Due__c', now.addHours(DEFAULT_SLA_HOURS));
    }

    public static void handleBeforeInsert(List<Case> cases) {
        for (Case caseRecord : cases) {
            if (caseRecord.get('Stage_Start_Time__c') == null) {
                applyStageTiming(caseRecord);
            }
        }
    }

    public static void handleBeforeUpdate(List<Case> cases, Map<Id, Case> oldMap) {
        for (Case caseRecord : cases) {
            Case oldCase = oldMap.get(caseRecord.Id);
            if (oldCase == null) {
                continue;
            }
            if (caseRecord.Status != oldCase.Status && !caseRecord.IsClosed) {
                applyStageTiming(caseRecord);
            }
        }
    }

    public static SlaMilestoneView buildMilestoneView(
        Datetime stageStart,
        Datetime stageDue,
        Boolean isClosed
    ) {
        SlaMilestoneView view = new SlaMilestoneView();
        view.isClosed = isClosed == true;

        if (stageStart == null) {
            view.statusLabel = 'NOT STARTED';
            view.statusVariant = 'base';
            view.elapsedLabel = '—';
            view.dueInLabel = '—';
            return view;
        }

        Datetime now = System.now();
        Long elapsedMinutes = Math.max(0, (now.getTime() - stageStart.getTime()) / 60000);
        view.elapsedLabel = 'Elapsed: ' + formatDuration(elapsedMinutes);

        if (view.isClosed) {
            view.statusLabel = 'COMPLETED';
            view.statusVariant = 'base';
            view.dueInLabel = null;
            return view;
        }

        if (stageDue == null) {
            view.statusLabel = 'ON TRACK';
            view.statusVariant = 'success';
            view.dueInLabel = '—';
            return view;
        }

        Long dueInMinutes = (stageDue.getTime() - now.getTime()) / 60000;
        if (dueInMinutes < 0) {
            view.statusLabel = 'VIOLATED';
            view.statusVariant = 'error';
            view.dueInLabel = 'Overdue by: ' + formatDuration(Math.abs(dueInMinutes));
            return view;
        }

        Long totalMinutes = Math.max(1, (stageDue.getTime() - stageStart.getTime()) / 60000);
        if (dueInMinutes <= totalMinutes * 0.2) {
            view.statusLabel = 'AT RISK';
            view.statusVariant = 'warning';
        } else {
            view.statusLabel = 'ON TRACK';
            view.statusVariant = 'success';
        }
        view.dueInLabel = 'Due in: ' + formatDuration(dueInMinutes);
        return view;
    }

    private static String formatDuration(Long totalMinutes) {
        Long hours = totalMinutes / 60;
        Long minutes = Math.mod(totalMinutes, 60);
        if (hours > 0) {
            return hours + 'h ' + minutes + 'm';
        }
        return minutes + 'm';
    }

    private static Boolean hasSlaFields() {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Case.fields.getMap();
        return fields.containsKey('Stage_Start_Time__c') && fields.containsKey('Stage_Due__c');
    }

    public class SlaMilestoneView {
        @AuraEnabled
        public String statusLabel;
        @AuraEnabled
        public String statusVariant;
        @AuraEnabled
        public String elapsedLabel;
        @AuraEnabled
        public String dueInLabel;
        @AuraEnabled
        public Boolean isClosed;
    }
}