public with sharing class TimeOffRequestBulkReject {

    public class Input {
        @InvocableVariable(label='Selected record Ids (list view / multi-select)')
        public List<String> recordIds;
        @InvocableVariable(label='Record Id (record page quick action)')
        public String recordId;
        @InvocableVariable(required=true label='Rejection reason')
        public String rejectionReason;
    }

    public class Output {
        @InvocableVariable(label='Processed count')
        public Integer processedCount;
        @InvocableVariable(label='Skipped count')
        public Integer skippedCount;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='Bulk reject time off requests'
        description='Rejects selected requests in Submitted for Approval where you are the creator manager.'
    )
    public static List<Output> bulkReject(List<Input> inputs) {
        Output o = new Output();
        List<Output> out = new List<Output>{ o };
        if (inputs == null || inputs.isEmpty()) {
            o.message = 'No input.';
            return out;
        }
        Input req = inputs[0];
        TimeOffRequestBulkApproval.Result r = TimeOffRequestBulkApproval.runReject(
            TimeOffRequestBulkApproval.mergeIdInputs(req.recordIds, req.recordId),
            req.rejectionReason
        );
        o.processedCount = r.processedCount;
        o.skippedCount = r.skippedCount;
        o.message = r.message;
        return out;
    }
}