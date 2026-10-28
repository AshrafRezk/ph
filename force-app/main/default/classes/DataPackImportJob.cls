/** One staged chunk per run; chains itself while chunks remain. Progress lives on Sales_Data_Import_Batch__c. */
public with sharing class DataPackImportJob implements Queueable {
    private final Id batchId;

    public DataPackImportJob(Id batchId) {
        this.batchId = batchId;
    }

    public void execute(QueueableContext context) {
        Boolean more = false;
        try {
            more = DataPackImportService.processNextChunk(batchId);
        } catch (Exception ex) {
            DistributorImportService.markFailed(batchId, 'Data pack job failed: ' + ex.getMessage());
            return;
        }
        enqueueNextIfNeeded(more);
    }

    @TestVisible
    private void enqueueNextIfNeeded(Boolean more) {
        if (!more) {
            return;
        }
        // Tests cover this method; live chaining is skipped under Test.isRunningTest to avoid stack-depth limits.
        if (Test.isRunningTest()) {
            return;
        }
        Id next = System.enqueueJob(new DataPackImportJob(batchId));
        DistributorImportService.recordJob(batchId, next);
    }
}
