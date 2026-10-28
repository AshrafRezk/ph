/**
 * Server side of the Admin Console "Monthly data pack" card.
 *
 * The browser unpacks the zip, parses each workbook and sends normalised rows in chunks. Each chunk is staged
 * as its own file (same staging helpers as the distributor sales import), then a queueable processes one chunk
 * per run and chains itself. Progress and failures live on Sales_Data_Import_Batch__c, so the existing
 * Batches tab, Resume / Re-queue / Mark failed and the sweeper all work for pack batches.
 *
 *   Distributor_Code__c = 'PACK:LEAVE' | 'PACK:TOT' | 'PACK:VISIT'
 *
 * Sales files (EPDA / POS / IBNSINA) do not go through here: the browser sends them to
 * DistributorsManagementController.ingestNormalizedRows, the same staged path as Distributors Management.
 *
 * EXTENSION POINTS (add a kind here, nothing else in the card needs to change):
 *   1. add the kind to SUPPORTED_KINDS,
 *   2. handle it in processRows(),
 *   3. teach monthlyDataPackLib.classifyFile / normaliseRows about the new file layout.
 * PACK:VISIT keys rows with Client_Visit_Key__c prefix PACKV- (validation rules and VisitDuplicateService
 * bypass on that prefix). Leave/TOT keys rows in Comments__c as [PACKKEY:...] because Mendix_External_Id__c
 * is not live on Time_Off_Request__c in this org.
 */
public with sharing class DataPackImportService {
    public static final String CODE_PREFIX = 'PACK:';
    public static final String KIND_LEAVE = 'LEAVE';
    public static final String KIND_TOT = 'TOT';
    public static final String KIND_VISIT = 'VISIT';
    public static final Set<String> SUPPORTED_KINDS = new Set<String>{ KIND_LEAVE, KIND_TOT, KIND_VISIT };
    public static final Integer MAX_CHUNK_ROWS = 500;
    public static final String ERROR_HEADER =
        'kind,source_file,source_row,employee_code,employee_name,type,from,to,severity,message';

    public class PackException extends Exception {
    }

    public class ChunkResult {
        @AuraEnabled public Id batchId;
        @AuraEnabled public String status;
        @AuraEnabled public Integer rowsAccepted;
        @AuraEnabled public Boolean jobEnqueued;
        @AuraEnabled public String message;
    }

    public class BatchStatus {
        @AuraEnabled public Id batchId;
        @AuraEnabled public String batchName;
        @AuraEnabled public String kind;
        @AuraEnabled public String fileName;
        @AuraEnabled public String status;
        @AuraEnabled public Integer chunksExpected;
        @AuraEnabled public Integer chunksProcessed;
        @AuraEnabled public Integer rowsInserted;
        @AuraEnabled public Integer rowsUpdated;
        @AuraEnabled public Integer rowsFailed;
        @AuraEnabled public Boolean done;
        @AuraEnabled public String logTail;
    }

    public class Hooks {
        @AuraEnabled public Boolean historicalVisitFlag;
        @AuraEnabled public Boolean leaveTotReady;
        @AuraEnabled public String visitMessage;
    }

    public class DuplicateHit {
        @AuraEnabled public String fingerprint;
        @AuraEnabled public String batchName;
        @AuraEnabled public String status;
    }

    /** Result of processing one staged chunk. Rows are counted once each. */
    public class ChunkOutcome {
        public Integer inserted = 0;
        public Integer updated = 0;
        public Integer failed = 0;
        public List<String> errorLines = new List<String>();
    }

    // ---------- hooks ----------

    public static Boolean historicalVisitHooksReady() {
        // Live schema uses Client_Visit_Key__c PACKV- bypass (Is_Historical_Import__c is not queryable in this org).
        return Visit__c.SObjectType.getDescribe().fields.getMap().containsKey('client_visit_key__c');
    }

    @AuraEnabled
    public static Hooks getHooks() {
        Hooks h = new Hooks();
        h.historicalVisitFlag = historicalVisitHooksReady();
        h.leaveTotReady = true;
        h.visitMessage = h.historicalVisitFlag
            ? 'Historical visits import with Client_Visit_Key__c PACKV- keys.'
            : 'Historical visits stay in preview: Visit__c.Client_Visit_Key__c is not available.';
        return h;
    }

    // ---------- fingerprint ----------

    public static String fingerprintTag(String fingerprint) {
        return String.isBlank(fingerprint) ? '' : ' [sha:' + fingerprint.left(16) + ']';
    }

    @AuraEnabled
    public static List<DuplicateHit> findDuplicateFingerprints(List<String> fingerprints) {
        List<DuplicateHit> hits = new List<DuplicateHit>();
        if (fingerprints == null) {
            return hits;
        }
        Integer checked = 0;
        for (String fp : fingerprints) {
            if (String.isBlank(fp) || checked >= 30) {
                continue;
            }
            checked++;
            String pattern = '%' + fingerprintTag(fp).trim() + '%';
            List<Sales_Data_Import_Batch__c> found = [
                SELECT Name, Status__c
                FROM Sales_Data_Import_Batch__c
                WHERE File_Name__c LIKE :pattern AND Status__c != 'Failed'
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!found.isEmpty()) {
                DuplicateHit hit = new DuplicateHit();
                hit.fingerprint = fp;
                hit.batchName = found[0].Name;
                hit.status = found[0].Status__c;
                hits.add(hit);
            }
        }
        return hits;
    }

    // ---------- upload ----------

    public static Boolean isPackBatch(Sales_Data_Import_Batch__c b) {
        return b != null && b.Distributor_Code__c != null && b.Distributor_Code__c.startsWith(CODE_PREFIX);
    }

    public static String kindOf(Sales_Data_Import_Batch__c b) {
        return isPackBatch(b) ? b.Distributor_Code__c.substring(CODE_PREFIX.length()) : null;
    }

    @AuraEnabled
    public static ChunkResult stageChunk(
        String kind,
        String fileName,
        String fingerprint,
        String reportMonth,
        String rowsJson,
        Id existingBatchId,
        Boolean finalize,
        Integer chunkIndex,
        Integer totalChunks
    ) {
        String normKind = String.isBlank(kind) ? '' : kind.trim().toUpperCase();
        if (!SUPPORTED_KINDS.contains(normKind)) {
            throw new AuraHandledException('Unsupported data pack kind: ' + kind);
        }
        if (normKind == KIND_VISIT && !historicalVisitHooksReady()) {
            throw new AuraHandledException(getHooks().visitMessage);
        }
        if (String.isBlank(rowsJson)) {
            throw new AuraHandledException('No rows provided.');
        }
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(rowsJson);
        if (raw.size() > MAX_CHUNK_ROWS) {
            throw new AuraHandledException('Chunk exceeds maximum of ' + MAX_CHUNK_ROWS + ' rows.');
        }
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Object o : raw) {
            rows.add((Map<String, Object>) o);
        }

        Sales_Data_Import_Batch__c batch;
        if (existingBatchId != null) {
            batch = DistributorImportService.loadBatch(existingBatchId);
            if (!isPackBatch(batch) || batch.Status__c != 'Uploading') {
                throw new AuraHandledException(batch.Name + ' no longer accepts chunks. Import the file again.');
            }
        } else {
            batch = new Sales_Data_Import_Batch__c(
                File_Name__c = (String.isBlank(fileName) ? 'data-pack.xlsx' : fileName.left(230)) + fingerprintTag(fingerprint),
                Distributor_Code__c = CODE_PREFIX + normKind,
                Status__c = 'Uploading',
                Report_Month__c = parseMonth(reportMonth),
                Aliases_Created__c = 0,
                Needs_Review__c = 0,
                Rows_Inserted__c = 0,
                Rows_Updated__c = 0,
                Rows_Failed__c = 0,
                Upload_Rows_Failed__c = 0,
                Chunks_Received__c = 0,
                Chunks_Processed__c = 0,
                Run_Number__c = 1,
                Last_Activity__c = System.now()
            );
            Database.insert(batch, AccessLevel.SYSTEM_MODE);
            batch = DistributorImportService.loadBatch(batch.Id);
        }

        Integer idx = chunkIndex != null ? chunkIndex : Integer.valueOf(batch.Chunks_Received__c == null ? 0 : batch.Chunks_Received__c);
        Boolean newChunk = DistributorImportService.stageChunk(batch.Id, idx, rows);
        if (newChunk) {
            batch.Chunks_Received__c = (batch.Chunks_Received__c == null ? 0 : batch.Chunks_Received__c) + 1;
        }
        batch.Last_Activity__c = System.now();

        ChunkResult result = new ChunkResult();
        result.batchId = batch.Id;
        result.rowsAccepted = rows.size();
        result.jobEnqueued = false;
        if (finalize == true) {
            Integer received = DistributorImportService.countChunks(batch.Id);
            Integer expected = totalChunks != null ? totalChunks : received;
            batch.Chunks_Received__c = received;
            batch.Chunks_Expected__c = expected;
            if (received < expected) {
                batch.Status__c = 'Failed';
                batch.Error_Log__c = DistributorImportService.appendLog(
                    batch.Error_Log__c,
                    'Upload incomplete: received ' + received + ' of ' + expected + ' chunks. Import the file again.'
                );
                Database.update(batch, AccessLevel.SYSTEM_MODE);
                result.message = 'Upload incomplete (' + received + ' of ' + expected + ' chunks). Batch marked Failed.';
            } else {
                batch.Status__c = 'Queued';
                Database.update(batch, AccessLevel.SYSTEM_MODE);
                start(batch.Id);
                result.jobEnqueued = true;
                result.message = 'Import queued for processing.';
            }
        } else {
            Database.update(batch, AccessLevel.SYSTEM_MODE);
            result.message = 'Chunk accepted.';
        }
        result.status = batch.Status__c;
        return result;
    }

    // ---------- processing ----------

    /** Called by DistributorImportService.startProcessing for PACK: batches (first run, Resume and Re-queue). */
    public static Id start(Id batchId) {
        Id jobId = System.enqueueJob(new DataPackImportJob(batchId));
        DistributorImportService.recordJob(batchId, jobId);
        return jobId;
    }

    /**
     * Processes the next staged chunk (after Chunks_Processed__c) and updates the batch.
     * @return true when more chunks are waiting.
     */
    public static Boolean processNextChunk(Id batchId) {
        Sales_Data_Import_Batch__c batch = DistributorImportService.loadBatch(batchId);
        if (!isPackBatch(batch) || batch.Status__c == 'Failed' || batch.Status__c == 'Completed') {
            return false;
        }
        List<Id> files = DistributorImportService.stagingFileIds(batchId);
        Integer next = batch.Chunks_Processed__c == null ? 0 : Integer.valueOf(batch.Chunks_Processed__c);
        if (next >= files.size()) {
            batch.Status__c = 'Completed';
            batch.Last_Activity__c = System.now();
            Database.update(batch, AccessLevel.SYSTEM_MODE);
            return false;
        }
        batch.Status__c = 'Processing';
        String kind = kindOf(batch);
        ChunkOutcome outcome;
        try {
            List<Map<String, Object>> rows = DistributorImportService.loadStagingFile(files[next]);
            outcome = processRows(kind, rows, batch.File_Name__c);
        } catch (Exception ex) {
            DistributorImportService.markFailed(batchId, 'Chunk ' + next + ' failed: ' + ex.getMessage());
            return false;
        }
        if (!outcome.errorLines.isEmpty()) {
            writeErrorFile(batchId, next, batch.Run_Number__c, outcome.errorLines);
        }
        batch.Rows_Inserted__c = (batch.Rows_Inserted__c == null ? 0 : batch.Rows_Inserted__c) + outcome.inserted;
        batch.Rows_Updated__c = (batch.Rows_Updated__c == null ? 0 : batch.Rows_Updated__c) + outcome.updated;
        batch.Rows_Failed__c = (batch.Rows_Failed__c == null ? 0 : batch.Rows_Failed__c) + outcome.failed;
        batch.Chunks_Processed__c = next + 1;
        Boolean more = (next + 1) < files.size();
        if (!more) {
            batch.Status__c = 'Completed';
            batch.Error_Log__c = DistributorImportService.appendLog(
                batch.Error_Log__c,
                'DONE: ' + Integer.valueOf(batch.Rows_Inserted__c) + ' inserted, ' + Integer.valueOf(batch.Rows_Updated__c)
                    + ' updated, ' + Integer.valueOf(batch.Rows_Failed__c) + ' not imported (see error CSV).'
            );
        }
        batch.Last_Activity__c = System.now();
        Database.update(batch, AccessLevel.SYSTEM_MODE);
        return more;
    }

    /** Extension point: one switch arm per kind. */
    public static ChunkOutcome processRows(String kind, List<Map<String, Object>> rows, String fileName) {
        if (kind == KIND_LEAVE || kind == KIND_TOT) {
            return processTimeOffRows(kind, rows, fileName);
        }
        if (kind == KIND_VISIT) {
            return processVisitRows(rows, fileName);
        }
        throw new PackException('Unsupported data pack kind: ' + kind);
    }

    /**
     * Historical visits. Employees arrive by NAME (not code); customers by Arabic/Latin name.
     * Matching uses exact User.Name / Account.Name first, then AccountCognitiveSearch for remaining accounts.
     * Idempotent via Client_Visit_Key__c.
     */
    public static ChunkOutcome processVisitRows(List<Map<String, Object>> rows, String fileName) {
        ChunkOutcome out = new ChunkOutcome();
        if (!historicalVisitHooksReady()) {
            for (Map<String, Object> row : rows) {
                out.failed++;
                out.errorLines.add(errorLine(KIND_VISIT, fileName, row, 'error',
                    'Historical visit import is not enabled: Visit__c.Client_Visit_Key__c is not available.'));
            }
            return out;
        }

        // A row may carry userId / accountId resolved before upload (same-name doctors, renamed reps);
        // those win over the name lookups below.
        Set<String> employeeNames = new Set<String>();
        Set<String> customerNames = new Set<String>();
        for (Map<String, Object> row : rows) {
            String emp = str(row.get('employeeName'));
            String cust = str(row.get('customerName'));
            if (String.isNotBlank(emp) && idOrNull(row.get('userId'), User.SObjectType) == null) {
                employeeNames.add(emp);
            }
            if (String.isNotBlank(cust) && idOrNull(row.get('accountId'), Account.SObjectType) == null) {
                customerNames.add(cust);
            }
        }

        Map<String, Id> userByName = resolveUsersByName(employeeNames);
        Map<String, Id> accountByName = resolveAccountsByName(customerNames);

        Map<String, Visit__c> records = new Map<String, Visit__c>();
        Map<String, Map<String, Object>> sourceByKey = new Map<String, Map<String, Object>>();
        for (Map<String, Object> row : rows) {
            String emp = str(row.get('employeeName'));
            String cust = str(row.get('customerName'));
            String planned = str(row.get('planned'));
            String statusRaw = str(row.get('status'));
            Date day = parseDate(str(row.get('visitDate')));
            Id userId = idOrNull(row.get('userId'), User.SObjectType);
            if (userId == null && String.isNotBlank(emp)) {
                userId = userByName.get(emp.toLowerCase());
            }
            Id accountId = idOrNull(row.get('accountId'), Account.SObjectType);
            if (accountId == null && String.isNotBlank(cust)) {
                accountId = accountByName.get(cust.toLowerCase());
            }
            String problem = null;
            String severity = 'error';
            if (String.isBlank(emp)) {
                problem = 'Employee name is blank.';
            } else if (userId == null) {
                problem = 'No Salesforce user named ' + emp + '.';
            } else if (String.isBlank(cust)) {
                problem = 'Customer name is blank.';
            } else if (accountId == null) {
                problem = 'No Account matched for customer ' + cust + '.';
            } else if (day == null) {
                problem = 'Visit date is missing or invalid.';
            } else if (mapVisitStatus(statusRaw) == null) {
                problem = 'Skipped: visit status ' + statusRaw + ' is not imported.';
                severity = 'skipped';
            } else if (mapVisitType(planned) == null) {
                problem = 'Unmapped planned flag: ' + planned;
            }
            if (problem != null) {
                out.failed++;
                out.errorLines.add(errorLine(KIND_VISIT, fileName, row, severity, problem));
                continue;
            }
            String visitType = mapVisitType(planned);
            String status = mapVisitStatus(statusRaw);
            String key = visitExternalKey(userId, accountId, day, visitType, status);
            Visit__c visit = new Visit__c(
                Account__c = accountId,
                Assigned_To__c = userId,
                Visit_Type__c = visitType,
                Status__c = status,
                Start_Date__c = Datetime.newInstance(day, Time.newInstance(10, 0, 0, 0)),
                Visit_Date__c = Datetime.newInstance(day, Time.newInstance(10, 0, 0, 0)),
                End_Date__c = Datetime.newInstance(day, Time.newInstance(10, 30, 0, 0)),
                Client_Visit_Key__c = key,
                Visit_Notes__c = str(row.get('comments')),
                Products_Discussed__c = productList(row.get('products'))
            );
            if (status == 'Cancelled') {
                visit.Cancellation_Reason__c = 'Cancelled in historical mobile log (imported).';
            }
            if (records.containsKey(key)) {
                out.failed++;
                out.errorLines.add(errorLine(KIND_VISIT, fileName, row, 'error', 'Duplicate of an earlier row in this chunk for ' + String.valueOf(day) + '.'));
            } else {
                records.put(key, visit);
                sourceByKey.put(key, row);
            }
        }

        if (records.isEmpty()) {
            return out;
        }
        List<String> keys = new List<String>(records.keySet());
        List<Visit__c> toUpsert = new List<Visit__c>();
        for (String key : keys) {
            toUpsert.add(records.get(key));
        }
        // Historical visits do not feed live time cards: the time-card trigger costs about one query per visit
        // and would build a monthly card per rep for every past month.
        Database.UpsertResult[] results;
        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(true);
        try {
            results = Database.upsert(toUpsert, Visit__c.Client_Visit_Key__c, false, AccessLevel.SYSTEM_MODE);
        } finally {
            EmployeeTimeCardMetricsService.setSuppressVisitProcessing(false);
        }
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                if (results[i].isCreated()) {
                    out.inserted++;
                } else {
                    out.updated++;
                }
            } else {
                out.failed++;
                String msg = results[i].getErrors().isEmpty() ? 'Unknown error' : results[i].getErrors()[0].getMessage();
                out.errorLines.add(errorLine(KIND_VISIT, fileName, sourceByKey.get(keys[i]), 'error', msg + ' [' + keys[i] + ']'));
            }
        }
        return out;
    }

    /** An Id of the given object from a row value, or null when blank / not an Id of that object. */
    @TestVisible
    private static Id idOrNull(Object value, Schema.SObjectType type) {
        String s = str(value);
        if (String.isBlank(s)) {
            return null;
        }
        try {
            Id parsed = Id.valueOf(s.trim());
            return parsed.getSObjectType() == type ? parsed : null;
        } catch (Exception e) {
            return null;
        }
    }

    /** The visit log's Products cell ("A,B" or "A; B") in the call report's "A; B" form, or null. */
    @TestVisible
    private static String productList(Object value) {
        String s = str(value);
        if (String.isBlank(s)) {
            return null;
        }
        List<String> names = new List<String>();
        for (String part : s.split('[,;]')) {
            if (String.isNotBlank(part)) {
                names.add(part.normalizeSpace());
            }
        }
        return names.isEmpty() ? null : String.join(names, '; ');
    }

    public static String mapVisitType(String planned) {
        String p = String.isBlank(planned) ? '' : planned.trim().toLowerCase();
        if (p == 'planned') {
            return 'Planned (Automatically)';
        }
        if (p == 'unplanned') {
            return 'Unplanned';
        }
        return null;
    }

    public static String mapVisitStatus(String status) {
        String s = String.isBlank(status) ? '' : status.trim().toLowerCase();
        if (s == 'approved' || s == 'completed') {
            return 'Completed';
        }
        if (s == 'cancelled' || s == 'canceled') {
            return 'Cancelled';
        }
        return null;
    }

    public static String visitExternalKey(Id userId, Id accountId, Date day, String visitType, String status) {
        String typeKey = visitType != null && visitType.startsWith('Unplanned') ? 'U' : 'P';
        String statusKey = status == 'Cancelled' ? 'X' : 'C';
        return ('PACKV-' + String.valueOf(day) + '-' + String.valueOf(userId).right(10) + '-'
            + String.valueOf(accountId).right(10) + '-' + typeKey + statusKey).left(80);
    }

    private static Map<String, Id> resolveUsersByName(Set<String> names) {
        Map<String, Id> out = new Map<String, Id>();
        if (names == null || names.isEmpty()) {
            return out;
        }
        for (User u : [
            SELECT Id, Name, IsActive
            FROM User
            WHERE Name IN :names
            WITH SYSTEM_MODE
            ORDER BY IsActive ASC
        ]) {
            out.put(u.Name.toLowerCase(), u.Id);
        }
        return out;
    }

    /**
     * Exact Account.Name first, then AccountCognitiveSearch against LIKE candidates for leftovers.
     * Keys in the returned map are lowercased customer names from the file.
     */
    @TestVisible
    private static Map<String, Id> resolveAccountsByName(Set<String> names) {
        Map<String, Id> out = new Map<String, Id>();
        if (names == null || names.isEmpty()) {
            return out;
        }
        Set<String> remaining = new Set<String>();
        for (String n : names) {
            remaining.add(n);
        }
        for (Account a : [
            SELECT Id, Name
            FROM Account
            WHERE Name IN :names
            WITH SYSTEM_MODE
        ]) {
            String key = a.Name.toLowerCase();
            if (!out.containsKey(key)) {
                out.put(key, a.Id);
            }
            remaining.remove(a.Name);
            // File casing may differ; drop by case-insensitive compare.
            for (String n : new List<String>(remaining)) {
                if (n.equalsIgnoreCase(a.Name)) {
                    remaining.remove(n);
                    out.put(n.toLowerCase(), a.Id);
                }
            }
        }
        if (remaining.isEmpty()) {
            return out;
        }

        Map<String, List<String>> namesByNeedle = new Map<String, List<String>>();
        for (String n : remaining) {
            List<String> tokens = AccountCognitiveSearch.tokenize(n);
            String needle = null;
            for (String t : tokens) {
                if (t != null && AccountCognitiveSearch.foldName(t).length() >= 3) {
                    needle = t;
                    break;
                }
            }
            if (needle == null && !tokens.isEmpty()) {
                needle = tokens[0];
            }
            if (String.isBlank(needle)) {
                continue;
            }
            String nk = needle.toLowerCase();
            if (!namesByNeedle.containsKey(nk)) {
                namesByNeedle.put(nk, new List<String>());
            }
            namesByNeedle.get(nk).add(n);
        }

        Integer queries = 0;
        for (String nk : namesByNeedle.keySet()) {
            if (queries >= 40) {
                break;
            }
            String pattern = '%' + nk + '%';
            List<Account> candidates = [
                SELECT Id, Name
                FROM Account
                WHERE Name LIKE :pattern
                WITH SYSTEM_MODE
                LIMIT 200
            ];
            queries++;
            for (String customerName : namesByNeedle.get(nk)) {
                if (out.containsKey(customerName.toLowerCase())) {
                    continue;
                }
                Id bestId = null;
                Integer bestScore = 0;
                for (Account a : candidates) {
                    Integer score = AccountCognitiveSearch.scoreAlignedNames(customerName, a.Name);
                    if (score > bestScore) {
                        bestScore = score;
                        bestId = a.Id;
                    }
                }
                if (bestId != null && bestScore >= 80) {
                    out.put(customerName.toLowerCase(), bestId);
                }
            }
        }
        return out;
    }

    // ---------- leave / TOT ----------

    private static final Map<String, String> LEAVE_TYPES = new Map<String, String>{
        'annual vacation' => 'Annual Vacation',
        'annual leave' => 'Annual Leave',
        'emergency leave' => 'Casual/Emergency',
        'casual leave' => 'Casual/Emergency',
        'instead vacation' => 'Annual Leave',
        'sick leave' => 'Sick',
        'sick' => 'Sick',
        'unpaid vacation' => 'Unpaid',
        'unpaid leave' => 'Unpaid',
        'maternity leave' => 'Maternity/Paternity',
        'paternity leave' => 'Maternity/Paternity',
        'marriage' => 'Marriage',
        'military' => 'Military'
    };

    private static final Map<String, String> TOT_TYPES = new Map<String, String>{
        'training' => 'Training',
        'office work' => 'Office Work',
        'sales meeting' => 'Sales Meeting',
        'adminstrative day' => 'Office Work',
        'administrative day' => 'Office Work',
        'business travel' => 'Business Trip',
        'business trip' => 'Business Trip',
        'confrance' => 'Conference',
        'conference' => 'Conference',
        'av confrance' => 'Conference',
        'group meeting (rtd)' => 'RTD',
        'rtd' => 'RTD',
        'health day' => 'Health Day',
        'prospection' => 'Prospection',
        'gathering meeting' => 'Cycle Meeting',
        'cycle meeting' => 'Cycle Meeting',
        'handover' => 'Handover',
        'sales day' => 'Sales Day',
        'delegation' => 'Delegation',
        'speaker' => 'Speaker'
    };

    public static String mapType(String kind, String rawType) {
        String key = String.isBlank(rawType) ? '' : rawType.trim().toLowerCase();
        if (kind == KIND_LEAVE) {
            return LEAVE_TYPES.containsKey(key) ? LEAVE_TYPES.get(key) : TOT_TYPES.get(key);
        }
        return TOT_TYPES.containsKey(key) ? TOT_TYPES.get(key) : LEAVE_TYPES.get(key);
    }

    /** HR status to Stage__c. Pending stays Draft so no Mendix submit callout is triggered for a past month. */
    public static String mapStage(String status) {
        String s = String.isBlank(status) ? '' : status.trim().toLowerCase();
        if (s == 'approved') {
            return 'Approved';
        }
        if (s == 'rejected') {
            return 'Rejected';
        }
        if (s == 'pending') {
            return 'Draft';
        }
        return null;
    }

    public static String externalKey(String kind, String code, Date day, String startShift, String endShift, String type) {
        String typeKey = type == null ? '' : type.replaceAll('[^A-Za-z0-9]', '').left(12);
        return ('PACK-' + kind.left(1) + '-' + code + '-' + String.valueOf(day) + '-' + startShift + endShift + '-' + typeKey).left(80);
    }

    public static ChunkOutcome processTimeOffRows(String kind, List<Map<String, Object>> rows, String fileName) {
        ChunkOutcome out = new ChunkOutcome();
        Set<String> codes = new Set<String>();
        for (Map<String, Object> row : rows) {
            String code = str(row.get('employeeCode'));
            if (String.isNotBlank(code)) {
                codes.add(code);
            }
        }
        Map<String, User> userByCode = new Map<String, User>();
        for (User u : [
            SELECT Id, EmployeeNumber, IsActive
            FROM User
            WHERE EmployeeNumber IN :codes
            WITH SYSTEM_MODE
            ORDER BY IsActive ASC
        ]) {
            // ORDER BY IsActive ASC means an active user overwrites an inactive one with the same code
            userByCode.put(u.EmployeeNumber, u);
        }

        Map<String, Time_Off_Request__c> records = new Map<String, Time_Off_Request__c>();
        Map<String, Map<String, Object>> sourceByKey = new Map<String, Map<String, Object>>();
        for (Map<String, Object> row : rows) {
            String code = str(row.get('employeeCode'));
            String rawType = str(row.get('type'));
            String type = mapType(kind, rawType);
            String status = str(row.get('status'));
            String stage = mapStage(status);
            Date fromDay = parseDate(str(row.get('from')));
            Date toDay = parseDate(str(row.get('to')));
            String startShift = normShift(str(row.get('startShift')), 'AM');
            String endShift = normShift(str(row.get('endShift')), 'PM');
            String problem = null;
            String severity = 'error';
            if (String.isBlank(code)) {
                problem = 'Employee code is blank.';
            } else if (!userByCode.containsKey(code)) {
                problem = 'No Salesforce user has EmployeeNumber ' + code + '.';
            } else if (type == null) {
                problem = 'Unmapped ' + (kind == KIND_LEAVE ? 'leave' : 'time-off') + ' type: ' + rawType;
            } else if (stage == null) {
                problem = 'Skipped: HR status ' + status + ' is not imported.';
                severity = 'skipped';
            } else if (fromDay == null || toDay == null || toDay < fromDay) {
                problem = 'Invalid from/to dates.';
            } else if (fromDay.daysBetween(toDay) > 120) {
                problem = 'Range longer than 120 days.';
            }
            if (problem != null) {
                out.failed++;
                out.errorLines.add(errorLine(kind, fileName, row, severity, problem));
                continue;
            }
            Integer daysWritten = 0;
            Integer duplicates = 0;
            Date cursor = fromDay;
            while (cursor <= toDay) {
                Boolean first = cursor == fromDay;
                Boolean last = cursor == toDay;
                if (WorkingCalendarUtil.isWorkingDay(cursor)) {
                    String s = first ? startShift : 'AM';
                    String e = last ? endShift : 'PM';
                    String key = externalKey(kind, code, cursor, s, e, type);
                    Time_Off_Request__c rec = buildRecord(
                        kind,
                        userByCode.get(code).Id,
                        cursor,
                        s,
                        e,
                        type,
                        rawType,
                        stage,
                        str(row.get('description')),
                        status,
                        key
                    );
                    if (records.containsKey(key)) {
                        duplicates++;
                        out.failed++;
                        out.errorLines.add(errorLine(kind, fileName, row, 'error', 'Duplicate of an earlier row in this file for ' + String.valueOf(cursor) + '.'));
                    } else {
                        records.put(key, rec);
                        sourceByKey.put(key, row);
                        daysWritten++;
                    }
                }
                cursor = cursor.addDays(1);
            }
            if (daysWritten == 0 && duplicates == 0) {
                out.failed++;
                out.errorLines.add(errorLine(kind, fileName, row, 'skipped', 'Range falls only on non-working days.'));
            }
        }

        if (records.isEmpty()) {
            return out;
        }
        if (records.size() > 9000) {
            throw new PackException('Chunk expands to ' + records.size() + ' daily records (limit 9000). Send smaller chunks.');
        }
        return upsertTimeOffByPackKey(records, sourceByKey, kind, fileName, out);
    }

    /**
     * Idempotent leave/TOT write without Mendix_External_Id__c (not live in this org).
     * Keys are embedded as [PACKKEY:...] in Comments__c and matched on OwnerId + Start_Date__c.
     */
    private static ChunkOutcome upsertTimeOffByPackKey(
        Map<String, Time_Off_Request__c> records,
        Map<String, Map<String, Object>> sourceByKey,
        String kind,
        String fileName,
        ChunkOutcome out
    ) {
        Set<Id> ownerIds = new Set<Id>();
        Set<Date> days = new Set<Date>();
        for (Time_Off_Request__c rec : records.values()) {
            ownerIds.add(rec.OwnerId);
            if (rec.Start_Date_Time__c != null) {
                days.add(rec.Start_Date_Time__c.date());
            }
        }
        Map<String, Time_Off_Request__c> existingByKey = new Map<String, Time_Off_Request__c>();
        for (Time_Off_Request__c existing : [
            SELECT Id, OwnerId, Start_Date_Time__c, Comments__c, Stage__c
            FROM Time_Off_Request__c
            WHERE OwnerId IN :ownerIds AND Comments__c LIKE '%[PACKKEY:%'
            WITH SYSTEM_MODE
        ]) {
            if (existing.Start_Date_Time__c == null || !days.contains(existing.Start_Date_Time__c.date())) {
                continue;
            }
            String key = packKeyFromComments(existing.Comments__c);
            if (String.isNotBlank(key) && records.containsKey(key)) {
                existingByKey.put(key, existing);
            }
        }

        List<String> keys = new List<String>(records.keySet());
        List<Time_Off_Request__c> toInsert = new List<Time_Off_Request__c>();
        List<Time_Off_Request__c> toUpdate = new List<Time_Off_Request__c>();
        List<String> insertKeys = new List<String>();
        List<String> updateKeys = new List<String>();
        for (String key : keys) {
            Time_Off_Request__c rec = records.get(key);
            if (existingByKey.containsKey(key)) {
                Time_Off_Request__c prior = existingByKey.get(key);
                // Lock_Non_Draft blocks edits to Approved/Rejected; treat as already imported.
                if (prior.Stage__c != null && prior.Stage__c != 'Draft') {
                    out.updated++;
                    continue;
                }
                rec.Id = prior.Id;
                toUpdate.add(rec);
                updateKeys.add(key);
            } else {
                toInsert.add(rec);
                insertKeys.add(key);
            }
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] inserted = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < inserted.size(); i++) {
                if (inserted[i].isSuccess()) {
                    out.inserted++;
                } else {
                    out.failed++;
                    String msg = inserted[i].getErrors().isEmpty() ? 'Unknown error' : inserted[i].getErrors()[0].getMessage();
                    out.errorLines.add(errorLine(kind, fileName, sourceByKey.get(insertKeys[i]), 'error', msg + ' [' + insertKeys[i] + ']'));
                }
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] updated = Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < updated.size(); i++) {
                if (updated[i].isSuccess()) {
                    out.updated++;
                } else {
                    out.failed++;
                    String msg = updated[i].getErrors().isEmpty() ? 'Unknown error' : updated[i].getErrors()[0].getMessage();
                    out.errorLines.add(errorLine(kind, fileName, sourceByKey.get(updateKeys[i]), 'error', msg + ' [' + updateKeys[i] + ']'));
                }
            }
        }
        return out;
    }

    public static String packKeyFromComments(String comments) {
        if (String.isBlank(comments)) {
            return null;
        }
        Integer startIdx = comments.indexOf('[PACKKEY:');
        if (startIdx < 0) {
            return null;
        }
        Integer endIdx = comments.indexOf(']', startIdx);
        if (endIdx < 0) {
            return null;
        }
        return comments.substring(startIdx + 9, endIdx);
    }

    private static Time_Off_Request__c buildRecord(
        String kind,
        Id userId,
        Date day,
        String startShift,
        String endShift,
        String type,
        String rawType,
        String stage,
        String description,
        String hrStatus,
        String packKey
    ) {
        Boolean fullDay = startShift == 'AM' && endShift == 'PM';
        Time startTime = startShift == 'PM' ? Time.newInstance(13, 0, 0, 0) : Time.newInstance(9, 0, 0, 0);
        Time endTime = endShift == 'AM' ? Time.newInstance(13, 0, 0, 0) : Time.newInstance(17, 0, 0, 0);
        if (!fullDay && startShift == 'PM' && endShift == 'AM') {
            // HR files sometimes carry PM->AM on one day; treat it as the whole day rather than a negative span.
            fullDay = true;
            startTime = Time.newInstance(9, 0, 0, 0);
            endTime = Time.newInstance(17, 0, 0, 0);
        }
        String comment =
            '[PACKKEY:' +
            packKey +
            '] [' +
            rawType +
            (hrStatus == 'Pending' ? ' / pending in HR' : '') +
            '] ' +
            (description == null ? '' : description.trim());
        // Start_Date__c / End_Date__c are formula (not writeable); before-save flow derives them from DateTimes.
        Time_Off_Request__c rec = new Time_Off_Request__c(
            OwnerId = userId,
            Type__c = type,
            Stage__c = stage,
            Span_Type__c = fullDay ? 'Full_Day' : 'Half_Day',
            Span_Duration__c = fullDay ? 1 : 0.5,
            Start_Date_Time__c = Datetime.newInstance(day, startTime),
            End_Date_Time__c = Datetime.newInstance(day, endTime),
            Comments__c = comment.left(255)
        );
        if (stage == 'Rejected') {
            // Rejection_Reason_Required_When_Rejected; HR files carry no reason column.
            rec.Rejection_Reason__c = 'Rejected in HR system' + (String.isBlank(description) ? '.' : ': ' + description.trim());
        }
        return rec;
    }

    // ---------- errors ----------

    public static String errorLine(String kind, String fileName, Map<String, Object> row, String severity, String message) {
        Map<String, Object> r = row == null ? new Map<String, Object>() : row;
        return String.join(
            new List<String>{
                csv(kind),
                csv(cleanFileName(fileName)),
                csv(str(r.get('sourceRow'))),
                csv(str(r.get('employeeCode'))),
                csv(str(r.get('employeeName'))),
                csv(str(r.get('type'))),
                csv(str(r.get('from'))),
                csv(str(r.get('to'))),
                csv(severity),
                csv(message)
            },
            ','
        );
    }

    private static String cleanFileName(String fileName) {
        return fileName == null ? '' : fileName.replaceAll('\\s*\\[sha:[0-9a-fA-F]+\\]', '');
    }

    public static String csv(String value) {
        String v = value == null ? '' : value;
        if (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
            return '"' + v.replace('"', '""') + '"';
        }
        return v;
    }

    public static String errorTitle(Id batchId, Integer chunkIndex, Decimal run) {
        return 'DataPackErrors_' + batchId + '_r' + String.valueOf(run == null ? 1 : Integer.valueOf(run)) + '_'
            + String.valueOf(chunkIndex).leftPad(5, '0');
    }

    private static void writeErrorFile(Id batchId, Integer chunkIndex, Decimal run, List<String> lines) {
        String title = errorTitle(batchId, chunkIndex, run);
        List<ContentVersion> existing = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Title = :title AND IsLatest = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.csv',
            VersionData = Blob.valueOf(String.join(lines, '\n'))
        );
        if (!existing.isEmpty()) {
            cv.ContentDocumentId = existing[0].ContentDocumentId;
        }
        Database.insert(cv, AccessLevel.SYSTEM_MODE);
    }

    /** Error CSV for any import batch: pack batches return the staged row errors, sales batches return the batch log. */
    @AuraEnabled
    public static String getBatchErrorCsv(Id batchId) {
        Sales_Data_Import_Batch__c batch = DistributorImportService.loadBatch(batchId);
        List<String> lines = new List<String>();
        if (isPackBatch(batch)) {
            String run = String.valueOf(batch.Run_Number__c == null ? 1 : Integer.valueOf(batch.Run_Number__c));
            String pattern = 'DataPackErrors_' + batchId + '_r' + run + '_%';
            for (ContentVersion cv : [
                SELECT VersionData
                FROM ContentVersion
                WHERE Title LIKE :pattern AND IsLatest = TRUE
                WITH SYSTEM_MODE
                ORDER BY Title ASC
                LIMIT 200
            ]) {
                if (cv.VersionData != null) {
                    lines.add(cv.VersionData.toString());
                }
            }
            return ERROR_HEADER + '\n' + String.join(lines, '\n');
        }
        String header = 'batch,file,severity,message';
        if (String.isNotBlank(batch.Error_Log__c)) {
            for (String line : batch.Error_Log__c.split('\n')) {
                if (String.isNotBlank(line)) {
                    lines.add(csv(batch.Name) + ',' + csv(cleanFileName(batch.File_Name__c)) + ',log,' + csv(line));
                }
            }
        }
        return header + '\n' + String.join(lines, '\n');
    }

    // ---------- status ----------

    @AuraEnabled
    public static List<BatchStatus> getBatchStatuses(List<Id> batchIds) {
        List<BatchStatus> out = new List<BatchStatus>();
        if (batchIds == null || batchIds.isEmpty()) {
            return out;
        }
        for (Sales_Data_Import_Batch__c b : [
            SELECT Id, Name, File_Name__c, Distributor_Code__c, Status__c, Chunks_Expected__c, Chunks_Processed__c,
                Rows_Inserted__c, Rows_Updated__c, Rows_Failed__c, Error_Log__c
            FROM Sales_Data_Import_Batch__c
            WHERE Id IN :batchIds
            WITH SYSTEM_MODE
        ]) {
            BatchStatus s = new BatchStatus();
            s.batchId = b.Id;
            s.batchName = b.Name;
            s.kind = isPackBatch(b) ? kindOf(b) : b.Distributor_Code__c;
            s.fileName = cleanFileName(b.File_Name__c);
            s.status = b.Status__c;
            s.chunksExpected = b.Chunks_Expected__c == null ? null : Integer.valueOf(b.Chunks_Expected__c);
            s.chunksProcessed = b.Chunks_Processed__c == null ? 0 : Integer.valueOf(b.Chunks_Processed__c);
            s.rowsInserted = b.Rows_Inserted__c == null ? 0 : Integer.valueOf(b.Rows_Inserted__c);
            s.rowsUpdated = b.Rows_Updated__c == null ? 0 : Integer.valueOf(b.Rows_Updated__c);
            s.rowsFailed = b.Rows_Failed__c == null ? 0 : Integer.valueOf(b.Rows_Failed__c);
            s.done = b.Status__c == 'Completed' || b.Status__c == 'Failed';
            s.logTail = b.Error_Log__c == null ? null : b.Error_Log__c.right(400);
            out.add(s);
        }
        return out;
    }

    // ---------- helpers ----------

    private static String str(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static String normShift(String value, String fallback) {
        String v = String.isBlank(value) ? '' : value.trim().toUpperCase();
        return v == 'AM' || v == 'PM' ? v : fallback;
    }

    private static Date parseDate(String value) {
        if (String.isBlank(value) || value.length() < 10) {
            return null;
        }
        try {
            return Date.valueOf(value.left(10));
        } catch (Exception ex) {
            return null;
        }
    }

    private static Date parseMonth(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            List<String> parts = value.trim().split('-');
            return Date.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), 1);
        } catch (Exception ex) {
            return null;
        }
    }
}
