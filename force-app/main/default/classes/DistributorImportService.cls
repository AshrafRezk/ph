/**
 * Lifecycle for Sales_Data_Import_Batch__c (distributor sales import).
 *
 *   Uploading -> Queued -> Processing -> Completed
 *                  \________________\_____ Failed (browser, user or sweeper)
 *
 * - The browser stages every chunk as its OWN ContentVersion (DistributorImport_<batchId>_<00000>),
 *   so earlier chunks are never read back and rewritten.
 * - Job_Id__c holds the async job working on the batch.
 * - Chunks_Processed__c is a watermark: Resume continues from it; Re-queue bumps Run_Number__c and restarts.
 * - The sweeper marks batches Failed when nothing has happened for STALE_MINUTES and no job is active.
 */
public with sharing class DistributorImportService {
    public static final Integer STALE_MINUTES = 30;
    private static final Set<String> ACTIVE_JOB_STATUSES = new Set<String>{
        'Holding',
        'Queued',
        'Preparing',
        'Processing'
    };

    public class ImportException extends Exception {
    }

    // ---------- staging files ----------

    public static String chunkPrefix(Id batchId) {
        return 'DistributorImport_' + batchId + '_';
    }

    public static String chunkTitle(Id batchId, Integer chunkIndex) {
        return chunkPrefix(batchId) + String.valueOf(chunkIndex).leftPad(5, '0');
    }

    /** Legacy (pre-chunked) single staging file title. */
    public static String legacyTitle(Id batchId) {
        return 'DistributorImport_' + batchId;
    }

    /**
     * Writes one chunk as its own file. Re-sending the same chunk index (a browser retry) replaces that file only.
     * @return true when a new chunk file was created, false when an existing chunk was replaced.
     */
    public static Boolean stageChunk(Id batchId, Integer chunkIndex, List<Map<String, Object>> rows) {
        String title = chunkTitle(batchId, chunkIndex);
        List<ContentVersion> existing = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Title = :title AND IsLatest = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.json',
            VersionData = Blob.valueOf(JSON.serialize(rows == null ? new List<Object>() : rows))
        );
        if (!existing.isEmpty()) {
            cv.ContentDocumentId = existing[0].ContentDocumentId;
        }
        Database.insert(cv, AccessLevel.SYSTEM_MODE);
        return existing.isEmpty();
    }

    public static Integer countChunks(Id batchId) {
        String pattern = chunkPrefix(batchId) + '%';
        return [
            SELECT COUNT()
            FROM ContentVersion
            WHERE Title LIKE :pattern AND IsLatest = TRUE
            WITH SYSTEM_MODE
        ];
    }

    /**
     * Staging file Ids for a batch in chunk order. Falls back to the single legacy file for batches
     * uploaded before chunked staging (SDIB-00001..00011).
     */
    public static List<Id> stagingFileIds(Id batchId) {
        String pattern = chunkPrefix(batchId) + '%';
        List<Id> ids = new List<Id>();
        for (ContentVersion cv : [
            SELECT Id
            FROM ContentVersion
            WHERE Title LIKE :pattern AND IsLatest = TRUE
            WITH SYSTEM_MODE
            ORDER BY Title ASC
            LIMIT 2000
        ]) {
            ids.add(cv.Id);
        }
        if (!ids.isEmpty()) {
            return ids;
        }
        String legacy = legacyTitle(batchId);
        for (ContentVersion cv : [
            SELECT Id
            FROM ContentVersion
            WHERE Title = :legacy AND IsLatest = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ]) {
            ids.add(cv.Id);
        }
        if (ids.isEmpty()) {
            Sales_Data_Import_Batch__c b = [
                SELECT ContentVersion_Id__c
                FROM Sales_Data_Import_Batch__c
                WHERE Id = :batchId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (String.isNotBlank(b.ContentVersion_Id__c)) {
                for (ContentVersion cv : [
                    SELECT Id
                    FROM ContentVersion
                    WHERE Id = :b.ContentVersion_Id__c
                    WITH SYSTEM_MODE
                    LIMIT 1
                ]) {
                    ids.add(cv.Id);
                }
            }
        }
        return ids;
    }

    public static List<Map<String, Object>> loadStagingFile(Id contentVersionId) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        List<ContentVersion> cvs = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Id = :contentVersionId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (cvs.isEmpty() || cvs[0].VersionData == null) {
            return rows;
        }
        Object parsed = JSON.deserializeUntyped(cvs[0].VersionData.toString());
        if (parsed instanceof List<Object>) {
            for (Object o : (List<Object>) parsed) {
                rows.add((Map<String, Object>) o);
            }
        }
        return rows;
    }

    // ---------- jobs ----------

    public static Boolean isJobActive(String jobId) {
        if (String.isBlank(jobId)) {
            return false;
        }
        try {
            Id parsed = Id.valueOf(jobId);
            Integer n = [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE Id = :parsed AND Status IN :ACTIVE_JOB_STATUSES
            ];
            return n > 0;
        } catch (Exception e) {
            return false;
        }
    }

    /** Starts the geocode / match job for this batch only; the withdrawal queueable is chained from its finish(). */
    public static Id startProcessing(Id batchId) {
        // Monthly data pack batches (PACK:LEAVE / PACK:TOT / PACK:VISIT) have their own processor.
        if (DataPackImportService.isPackBatch(loadBatch(batchId))) {
            return DataPackImportService.start(batchId);
        }
        Integer scopeSize = DistributorGeocodeService.hasGoogleApiKey() ? 20 : 1;
        // No pharmacy accounts are created from distributor clients: sales are placed by the client's
        // location, and a CRM pharmacy link is optional. Auto-create made duplicate pharmacies.
        Id jobId = Database.executeBatch(new DistributorSalesImportBatch(batchId, false), scopeSize);
        recordJob(batchId, jobId);
        return jobId;
    }

    public static void recordJob(Id batchId, Id jobId) {
        Database.update(
            new Sales_Data_Import_Batch__c(Id = batchId, Job_Id__c = jobId, Last_Activity__c = System.now()),
            AccessLevel.SYSTEM_MODE
        );
    }

    public static void heartbeat(Id batchId) {
        Database.update(new Sales_Data_Import_Batch__c(Id = batchId, Last_Activity__c = System.now()), AccessLevel.SYSTEM_MODE);
    }

    public static String appendLog(String existing, String addition) {
        String merged = (String.isBlank(existing) ? '' : existing + '\n') + addition;
        // keep the newest text when the log gets long
        return merged.length() > 120000 ? merged.right(120000) : merged;
    }

    // ---------- actions (Batches tab, browser, sweeper) ----------

    /** Marks a batch Failed and stops its job. Completed batches are left alone. */
    public static Sales_Data_Import_Batch__c markFailed(Id batchId, String reason) {
        Sales_Data_Import_Batch__c b = loadBatch(batchId);
        if (b.Status__c == 'Completed') {
            return b;
        }
        if (String.isNotBlank(b.Job_Id__c)) {
            try {
                System.abortJob(Id.valueOf(b.Job_Id__c));
            } catch (Exception e) {
                // already finished, or not abortable (queueable)
            }
        }
        b.Status__c = 'Failed';
        b.Last_Activity__c = System.now();
        b.Error_Log__c = appendLog(
            b.Error_Log__c,
            'FAILED ' + System.now().format('yyyy-MM-dd HH:mm') + ': ' + (String.isBlank(reason) ? 'Marked failed.' : reason)
        );
        Database.update(b, AccessLevel.SYSTEM_MODE);
        return b;
    }

    /** Continue from the last fully processed chunk. */
    public static Sales_Data_Import_Batch__c resume(Id batchId) {
        Sales_Data_Import_Batch__c b = requireRestartable(batchId);
        b.Status__c = 'Queued';
        b.Error_Log__c = appendLog(
            b.Error_Log__c,
            'RESUME ' + System.now().format('yyyy-MM-dd HH:mm') + ': continuing from chunk ' + processed(b)
        );
        b.Last_Activity__c = System.now();
        Database.update(b, AccessLevel.SYSTEM_MODE);
        startProcessing(b.Id);
        return b;
    }

    /** Restart from chunk 0. Run_Number__c changes, so rows written by the previous run are overwritten, not added to. */
    public static Sales_Data_Import_Batch__c requeue(Id batchId) {
        Sales_Data_Import_Batch__c b = requireRestartable(batchId);
        b.Status__c = 'Queued';
        b.Run_Number__c = (b.Run_Number__c == null ? 1 : b.Run_Number__c) + 1;
        b.Chunks_Processed__c = 0;
        b.Rows_Inserted__c = 0;
        b.Rows_Updated__c = 0;
        b.Rows_Failed__c = b.Upload_Rows_Failed__c == null ? 0 : b.Upload_Rows_Failed__c;
        b.Error_Log__c = appendLog(
            b.Error_Log__c,
            'RE-QUEUE ' + System.now().format('yyyy-MM-dd HH:mm') + ': restarting from chunk 0 (run ' + b.Run_Number__c + ')'
        );
        b.Last_Activity__c = System.now();
        Database.update(b, AccessLevel.SYSTEM_MODE);
        startProcessing(b.Id);
        return b;
    }

    private static Integer processed(Sales_Data_Import_Batch__c b) {
        return b.Chunks_Processed__c == null ? 0 : Integer.valueOf(b.Chunks_Processed__c);
    }

    private static Sales_Data_Import_Batch__c requireRestartable(Id batchId) {
        Sales_Data_Import_Batch__c b = loadBatch(batchId);
        if (b.Status__c == 'Uploading') {
            throw new ImportException(
                b.Name + ' is still uploading. If the browser stopped, mark it failed and import the file again.'
            );
        }
        if (b.Status__c == 'Completed') {
            throw new ImportException(b.Name + ' is already completed.');
        }
        if (isJobActive(b.Job_Id__c)) {
            throw new ImportException(b.Name + ' still has a running job (' + b.Job_Id__c + '). Mark it failed first to stop it.');
        }
        List<Id> files = stagingFileIds(b.Id);
        if (files.isEmpty()) {
            throw new ImportException(b.Name + ' has no staged rows to process. Import the file again.');
        }
        if (b.Chunks_Expected__c != null && files.size() < b.Chunks_Expected__c) {
            throw new ImportException(
                b.Name + ' is missing staged chunks (' + files.size() + ' of ' + Integer.valueOf(b.Chunks_Expected__c) + '). Import the file again.'
            );
        }
        return b;
    }

    public static Sales_Data_Import_Batch__c loadBatch(Id batchId) {
        List<Sales_Data_Import_Batch__c> rows = [
            SELECT
                Id,
                Name,
                File_Name__c,
                Distributor_Code__c,
                Report_Month__c,
                Status__c,
                Error_Log__c,
                Job_Id__c,
                Chunks_Expected__c,
                Chunks_Received__c,
                Chunks_Processed__c,
                Run_Number__c,
                Rows_Inserted__c,
                Rows_Updated__c,
                Rows_Failed__c,
                Upload_Rows_Failed__c,
                Aliases_Created__c,
                Needs_Review__c,
                Last_Activity__c,
                ContentVersion_Id__c
            FROM Sales_Data_Import_Batch__c
            WHERE Id = :batchId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new ImportException('Import batch not found.');
        }
        return rows[0];
    }

    // ---------- sweeper ----------

    /**
     * Fails batches that have had no activity for staleMinutes and have no active job:
     * Uploading (browser went away) and Queued/Processing (job died).
     * @return number of batches marked Failed
     */
    public static Integer sweep(Integer staleMinutes) {
        Integer minutes = staleMinutes == null || staleMinutes < 1 ? STALE_MINUTES : staleMinutes;
        Datetime cutoff = System.now().addMinutes(-minutes);
        Integer failed = 0;
        for (Sales_Data_Import_Batch__c b : [
            SELECT Id, Name, Status__c, Job_Id__c, Last_Activity__c, LastModifiedDate
            FROM Sales_Data_Import_Batch__c
            WHERE Status__c IN ('Uploading', 'Queued', 'Processing')
            ORDER BY CreatedDate ASC
            LIMIT 200
        ]) {
            Datetime last = b.Last_Activity__c != null ? b.Last_Activity__c : b.LastModifiedDate;
            if (last >= cutoff) {
                continue;
            }
            if (b.Status__c != 'Uploading' && isJobActive(b.Job_Id__c)) {
                continue;
            }
            String reason = b.Status__c == 'Uploading'
                ? 'Upload stalled: no chunk received for ' + minutes + ' minutes. Import the file again.'
                : 'Processing stalled: no progress for ' + minutes + ' minutes and no active job. Use Resume or Re-queue.';
            markFailed(b.Id, reason);
            failed++;
        }
        return failed;
    }
}
