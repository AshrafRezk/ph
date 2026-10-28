/**
 * Meeting money flow (BRD 5.4.5): deposit or actual cost with invoice, the re-approval
 * threshold, accounting payments, send back, close, and cancel.
 * Runs without sharing; every entry point checks owner, accounting, or super-user access.
 */
public without sharing class MeetingFinanceService {
    public static final String PAYMENT_NOT_STARTED = 'Not Started';
    public static final String PAYMENT_ACTUAL_ENTERED = 'Actual Cost Entered';
    public static final String PAYMENT_IN_ACCOUNTING = 'In Accounting';
    public static final String PAYMENT_RETURNED = 'Returned to Business';
    public static final String PAYMENT_PARTIAL = 'Partial Paid';
    public static final String PAYMENT_PAID = 'Paid';

    public static final String STATUS_INCOMPLETE = 'Incomplete';
    public static final String STATUS_CLOSED = 'Closed';
    public static final String STATUS_CANCELLED = 'Cancelled';

    private static final Set<String> CANCELLABLE = new Set<String>{
        'Draft', 'PendingApproval', 'Approved', 'Rejected'
    };

    public class FinanceException extends Exception {}

    @TestVisible
    private static Decimal thresholdOverride;

    public static Decimal reapprovalThresholdPct() {
        if (thresholdOverride != null) {
            return thresholdOverride;
        }
        Meeting_Lifecycle_Setting__mdt setting = Meeting_Lifecycle_Setting__mdt.getInstance('Default');
        return setting?.Reapproval_Threshold_Pct__c == null ? 10 : setting.Reapproval_Threshold_Pct__c;
    }

    public static String currencyCode() {
        Meeting_Lifecycle_Setting__mdt setting = Meeting_Lifecycle_Setting__mdt.getInstance('Default');
        return String.isBlank(setting?.Currency_Code__c) ? 'EGP' : setting.Currency_Code__c;
    }

    public static Boolean isAccounting() {
        return FeatureManagement.checkPermission('Meeting_Accounting');
    }

    // ---------------------------------------------------------------- requester actions

    public static void markExecuted(Id meetingId) {
        Meeting__c meeting = requireOwner(meetingId);
        if (meeting.Status__c != MeetingApprovalChainService.STATUS_APPROVED) {
            throw new FinanceException('Only approved meetings can be marked as held.');
        }
        if (meeting.Start_Date_Time__c != null && meeting.Start_Date_Time__c.date() > Date.today()) {
            throw new FinanceException('You can mark the meeting as held on or after its start date.');
        }
        String fromStatus = meeting.Status__c;
        meeting.Status__c = MeetingApprovalChainService.STATUS_CONCLUDED;
        update meeting;
        MeetingHistoryService.writeTransition(meetingId, fromStatus, meeting.Status__c, 'execute', 'Meeting held');
    }

    public static void submitDeposit(Id meetingId, Decimal amount, String fileName, String base64Data) {
        Meeting__c meeting = requireOwner(meetingId);
        if (meeting.Approval_Status__c != MeetingApprovalChainService.APPROVAL_FULLY_APPROVED) {
            throw new FinanceException('A deposit can be requested only after the meeting is fully approved.');
        }
        if (!MeetingTypeService.forMeeting(meeting).allowDeposit) {
            throw new FinanceException(meeting.Activity_Type__c + ' meetings do not take deposits.');
        }
        if (meeting.Actual_Cost__c != null) {
            throw new FinanceException('The actual cost is already entered, so no new deposit can be added.');
        }
        Boolean resubmitting = meeting.Payment_Status__c == PAYMENT_RETURNED;
        if (meeting.Deposit_Amount__c != null && !resubmitting) {
            throw new FinanceException('A deposit is already recorded for this meeting.');
        }
        requirePositive(amount);
        requireInvoice(meeting, fileName, base64Data);

        String fromPayment = meeting.Payment_Status__c;
        meeting.Deposit_Amount__c = amount;
        meeting.Payment_Status__c = PAYMENT_IN_ACCOUNTING;
        update meeting;
        MeetingHistoryService.writeTransition(meetingId, fromPayment, PAYMENT_IN_ACCOUNTING, 'deposit',
            'Deposit ' + MeetingApprovalChainService.formatAmount(amount) + ' sent to accounting');
    }

    public static void submitActualCost(Id meetingId, Decimal amount, String fileName, String base64Data) {
        Meeting__c meeting = requireOwner(meetingId);
        Boolean executed = meeting.Status__c == MeetingApprovalChainService.STATUS_CONCLUDED
            || meeting.Status__c == STATUS_INCOMPLETE;
        if (!executed) {
            throw new FinanceException('Mark the meeting as held before entering the actual cost.');
        }
        Boolean firstEntry = meeting.Actual_Cost__c == null;
        if (!firstEntry && meeting.Payment_Status__c != PAYMENT_RETURNED) {
            throw new FinanceException('The actual cost is already with approvers or accounting.');
        }
        if (amount == null || amount < 0) {
            throw new FinanceException('Enter the actual cost.');
        }
        requireInvoice(meeting, fileName, base64Data);

        Decimal baseline = meeting.Approved_Planned_Cost__c != null
            ? meeting.Approved_Planned_Cost__c
            : (meeting.Planned_Cost__c == null ? 0 : meeting.Planned_Cost__c);
        Decimal increasePct = increasePct(baseline, amount);
        Decimal threshold = reapprovalThresholdPct();
        String fromPayment = meeting.Payment_Status__c;
        meeting.Actual_Cost__c = amount;

        if (increasePct >= threshold) {
            MeetingApprovalChainService.startRound(meeting, amount);
            meeting.Payment_Status__c = PAYMENT_ACTUAL_ENTERED;
            update meeting;
            MeetingHistoryService.writeTransition(meetingId, fromPayment, PAYMENT_ACTUAL_ENTERED, 'actual-cost-reapproval',
                'Actual cost ' + MeetingApprovalChainService.formatAmount(amount) + ' is ' +
                increasePct.setScale(1) + '% over plan; approval restarted');
            return;
        }

        Decimal paid = meeting.Paid_Amount__c == null ? 0 : meeting.Paid_Amount__c;
        meeting.Payment_Status__c = amount - paid <= 0 ? PAYMENT_PAID : PAYMENT_IN_ACCOUNTING;
        update meeting;
        MeetingHistoryService.writeTransition(meetingId, fromPayment, meeting.Payment_Status__c, 'actual-cost',
            'Actual cost ' + MeetingApprovalChainService.formatAmount(amount) + ' entered');
    }

    public static void closeMeeting(Id meetingId) {
        Meeting__c meeting = requireOwner(meetingId);
        if (meeting.Payment_Status__c != PAYMENT_PAID || meeting.Actual_Cost__c == null) {
            throw new FinanceException('A meeting can be closed only after the actual cost is fully paid.');
        }
        if (meeting.Status__c != MeetingApprovalChainService.STATUS_CONCLUDED && meeting.Status__c != STATUS_INCOMPLETE) {
            throw new FinanceException('Only held meetings can be closed.');
        }
        String fromStatus = meeting.Status__c;
        meeting.Status__c = STATUS_CLOSED;
        update meeting;
        MeetingHistoryService.writeTransition(meetingId, fromStatus, STATUS_CLOSED, 'close', 'Meeting closed');
    }

    public static void cancelMeeting(Id meetingId, String reason) {
        if (String.isBlank(reason)) {
            throw new FinanceException('A cancellation reason is required.');
        }
        Meeting__c meeting = requireOwner(meetingId);
        if (!CANCELLABLE.contains(meeting.Status__c)) {
            throw new FinanceException('Only meetings that have not been held can be cancelled.');
        }
        if (meeting.Paid_Amount__c != null && meeting.Paid_Amount__c > 0) {
            throw new FinanceException('Accounting has already paid against this meeting. Ask accounting before cancelling.');
        }
        MeetingApprovalChainService.skipOpenSteps(meetingId, 'Meeting cancelled');
        String fromStatus = meeting.Status__c;
        meeting.Status__c = STATUS_CANCELLED;
        meeting.Current_Approver__c = null;
        update meeting;
        MeetingHistoryService.writeTransition(meetingId, fromStatus, STATUS_CANCELLED, 'cancel', reason.trim());
    }

    // ---------------------------------------------------------------- accounting actions

    public static void recordPayment(Id meetingId, Decimal amount, Date paidOn, String reference) {
        requireAccounting();
        Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
        if (meeting.Payment_Status__c != PAYMENT_IN_ACCOUNTING && meeting.Payment_Status__c != PAYMENT_PARTIAL) {
            throw new FinanceException('This meeting is not waiting for payment.');
        }
        requirePositive(amount);
        Decimal due = amountDue(meeting);
        Decimal paid = meeting.Paid_Amount__c == null ? 0 : meeting.Paid_Amount__c;
        Decimal remaining = due - paid;
        if (amount > remaining) {
            throw new FinanceException(
                'Payment is more than the remaining ' + MeetingApprovalChainService.formatAmount(remaining) + '.'
            );
        }
        insert new Meeting_Payment__c(
            Meeting__c = meetingId,
            Amount__c = amount,
            Paid_On__c = paidOn == null ? Date.today() : paidOn,
            Reference__c = MeetingApprovalChainService.trimTo(reference, 80),
            Payment_For__c = meeting.Actual_Cost__c != null ? 'Actual Cost' : 'Deposit'
        );

        String fromPayment = meeting.Payment_Status__c;
        Boolean fullyPaid = paid + amount >= due;
        meeting.Payment_Status__c = fullyPaid ? PAYMENT_PAID : PAYMENT_PARTIAL;
        if (meeting.Actual_Cost__c != null) {
            if (!fullyPaid) {
                meeting.Status__c = STATUS_INCOMPLETE;
            } else if (meeting.Status__c == STATUS_INCOMPLETE) {
                meeting.Status__c = MeetingApprovalChainService.STATUS_CONCLUDED;
            }
        }
        update meeting;
        MeetingHistoryService.writeTransition(meetingId, fromPayment, meeting.Payment_Status__c, 'payment',
            'Paid ' + MeetingApprovalChainService.formatAmount(amount) +
            (String.isBlank(reference) ? '' : ' (ref ' + reference.trim() + ')'));
    }

    public static void sendBack(Id meetingId, String notes) {
        requireAccounting();
        if (String.isBlank(notes)) {
            throw new FinanceException('Tell the requester what to fix.');
        }
        Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
        if (meeting.Payment_Status__c != PAYMENT_IN_ACCOUNTING && meeting.Payment_Status__c != PAYMENT_PARTIAL) {
            throw new FinanceException('Only meetings in accounting can be sent back.');
        }
        String fromPayment = meeting.Payment_Status__c;
        String stamp = System.now().format('yyyy-MM-dd HH:mm') + ' ' + UserInfo.getName() + ': ' + notes.trim();
        meeting.Accounting_Notes__c = MeetingApprovalChainService.trimTo(
            String.isBlank(meeting.Accounting_Notes__c) ? stamp : stamp + '\n' + meeting.Accounting_Notes__c,
            5000
        );
        meeting.Payment_Status__c = PAYMENT_RETURNED;
        update meeting;
        MeetingHistoryService.writeTransition(meetingId, fromPayment, PAYMENT_RETURNED, 'send-back', notes.trim());
    }

    // ---------------------------------------------------------------- helpers

    public static Decimal amountDue(Meeting__c meeting) {
        if (meeting.Actual_Cost__c != null) {
            return meeting.Actual_Cost__c;
        }
        return meeting.Deposit_Amount__c == null ? 0 : meeting.Deposit_Amount__c;
    }

    public static Decimal increasePct(Decimal baseline, Decimal amount) {
        if (baseline == null || baseline <= 0) {
            return amount != null && amount > 0 ? 100 : 0;
        }
        return ((amount - baseline) / baseline) * 100;
    }

    public static Id saveInvoice(Id meetingId, String fileName, String base64Data) {
        if (String.isBlank(base64Data)) {
            return null;
        }
        String name = String.isBlank(fileName) ? 'Invoice' : fileName.trim();
        ContentVersion version = new ContentVersion(
            Title = name.contains('.') ? name.substringBeforeLast('.') : name,
            PathOnClient = name.contains('.') ? name : name + '.pdf',
            VersionData = EncodingUtil.base64Decode(base64Data),
            FirstPublishLocationId = meetingId
        );
        insert version;
        return version.Id;
    }

    public static Integer invoiceCount(Id meetingId) {
        return [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :meetingId];
    }

    private static void requireInvoice(Meeting__c meeting, String fileName, String base64Data) {
        saveInvoice(meeting.Id, fileName, base64Data);
        if (MeetingTypeService.forMeeting(meeting).requireInvoice && invoiceCount(meeting.Id) == 0) {
            throw new FinanceException('Attach the invoice before sending the cost.');
        }
    }

    private static void requirePositive(Decimal amount) {
        if (amount == null || amount <= 0) {
            throw new FinanceException('Enter an amount greater than zero.');
        }
    }

    private static Meeting__c requireOwner(Id meetingId) {
        Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
        if (meeting.OwnerId != UserInfo.getUserId() && !MeetingApprovalChainService.isSuperUser()) {
            throw new FinanceException('Only the meeting owner can do this.');
        }
        return meeting;
    }

    private static void requireAccounting() {
        if (!isAccounting() && !MeetingApprovalChainService.isSuperUser()) {
            throw new FinanceException('You need the Meeting Accounting permission.');
        }
    }
}
