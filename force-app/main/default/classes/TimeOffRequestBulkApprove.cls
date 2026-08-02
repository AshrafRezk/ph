public with sharing class TimeOffRequestBulkApprove {

    public class Input {
        @InvocableVariable(label='Selected record Ids (list view / multi-select)')
        public List<String> recordIds;
        @InvocableVariable(label='Record Id (record page quick action)')
        public String recordId;
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
        label='Bulk approve time off requests'
        description='Approves selected requests in Submitted for Approval where you are the creator manager.'
    )
    public static List<Output> bulkApprove(List<Input> inputs) {
        Output o = new Output();
        List<Output> out = new List<Output>{ o };
        if (inputs == null || inputs.isEmpty()) {
            o.message = 'No input.';
            return out;
        }
        TimeOffRequestBulkApproval.Result r = TimeOffRequestBulkApproval.runApprove(
            TimeOffRequestBulkApproval.mergeIdInputs(inputs[0].recordIds, inputs[0].recordId)
        );
        o.processedCount = r.processedCount;
        o.skippedCount = r.skippedCount;
        o.message = r.message;
        return out;
    }
}