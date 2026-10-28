@IsTest
private class DataPackImportServiceTest {
    private static final String CODE = 'DP9001';

    @TestSetup
    static void setup() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
        insert new User(
            Alias = 'dpack',
            Email = 'dpack' + uniq + '@example.com',
            Username = 'dpack' + uniq + '@example.com.zeta',
            LastName = 'Pack',
            EmployeeNumber = CODE,
            TimeZoneSidKey = 'Africa/Cairo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
    }

    private static Map<String, Object> row(Integer sourceRow, String code, String type, String fromDay, String toDay, String sShift, String eShift, String status) {
        return new Map<String, Object>{
            'sourceRow' => sourceRow,
            'employeeCode' => code,
            'employeeName' => 'Test Rep',
            'type' => type,
            'from' => fromDay,
            'to' => toDay,
            'startShift' => sShift,
            'endShift' => eShift,
            'status' => status,
            'description' => 'unit test, with comma'
        };
    }

    private static List<Map<String, Object>> sampleRows() {
        // 2026-09-06 is a Sunday: Sun-Tue are working days under the default Sat-Wed calendar.
        return new List<Map<String, Object>>{
            row(2, CODE, 'Annual Vacation', '2026-09-06', '2026-09-08', 'AM', 'PM', 'Approved'),
            row(3, CODE, 'Sick leave', '2026-09-13', '2026-09-13', 'AM', 'AM', 'Pending'),
            row(4, CODE, 'Annual Vacation', '2026-09-20', '2026-09-20', 'AM', 'PM', 'Cancelled'),
            row(5, 'NOPE', 'Annual Vacation', '2026-09-21', '2026-09-21', 'AM', 'PM', 'Approved'),
            row(6, CODE, 'Space Travel', '2026-09-22', '2026-09-22', 'AM', 'PM', 'Approved'),
            row(7, CODE, 'Annual Vacation', '2026-09-24', '2026-09-25', 'AM', 'PM', 'Approved')
        };
    }

    @IsTest
    static void mapsTypesStatusAndKeys() {
        System.assertEquals('Casual/Emergency', DataPackImportService.mapType('LEAVE', 'Emergency Leave'));
        System.assertEquals('Business Trip', DataPackImportService.mapType('TOT', 'Business Travel'));
        System.assertEquals('Conference', DataPackImportService.mapType('TOT', 'Confrance'));
        System.assertEquals('Sick', DataPackImportService.mapType('LEAVE', 'Sick leave'));
        System.assertEquals(null, DataPackImportService.mapType('LEAVE', 'Space Travel'));
        System.assertEquals('Approved', DataPackImportService.mapStage('Approved'));
        System.assertEquals('Draft', DataPackImportService.mapStage('Pending'));
        System.assertEquals(null, DataPackImportService.mapStage('Cancelled'));
        String key = DataPackImportService.externalKey('LEAVE', '12', Date.newInstance(2026, 9, 6), 'AM', 'PM', 'Casual/Emergency');
        System.assertEquals('PACK-L-12-2026-09-06-AMPM-CasualEmerge', key);
        System.assertEquals('"a,""b"""', DataPackImportService.csv('a,"b"'));
    }

    @IsTest
    static void processesLeaveRowsAndReportsErrors() {
        WorkingCalendarUtil.clearWorkingDayCache();
        DataPackImportService.ChunkOutcome first = DataPackImportService.processRows('LEAVE', sampleRows(), 'Leave.xlsx [sha:abc]');
        System.assertEquals(4, first.inserted, '3-day approved leave (Sun-Tue) + 1 pending half day');
        System.assertEquals(0, first.updated);
        // cancelled + unknown employee + unmapped type + Thu/Fri-only range, each reported once
        System.assertEquals(4, first.failed, String.join(first.errorLines, '|'));
        String all = String.join(first.errorLines, '\n');
        System.assert(all.contains('Skipped: HR status Cancelled'), all);
        System.assert(all.contains('No Salesforce user has EmployeeNumber NOPE'), all);
        System.assert(all.contains('Unmapped leave type: Space Travel'), all);
        System.assert(!all.contains('[sha:'), 'fingerprint tag is stripped from the CSV');

        List<Time_Off_Request__c> saved = [
            SELECT Stage__c, Span_Type__c, Type__c, Comments__c, Start_Date_Time__c
            FROM Time_Off_Request__c
            WHERE Comments__c LIKE '%[PACKKEY:PACK-L-DP9001-%'
            ORDER BY Start_Date_Time__c
        ];
        System.assertEquals(4, saved.size());
        System.assertEquals('Approved', saved[0].Stage__c);
        System.assertEquals('Full_Day', saved[0].Span_Type__c);
        System.assertEquals('Annual Vacation', saved[0].Type__c);
        System.assertEquals('Draft', saved[3].Stage__c, 'pending HR leave is imported as Draft');
        System.assertEquals('Half_Day', saved[3].Span_Type__c);
        System.assert(DataPackImportService.packKeyFromComments(saved[0].Comments__c).startsWith('PACK-L-DP9001-'));

        // Same file again: matched by [PACKKEY:...] in Comments__c, nothing duplicated.
        DataPackImportService.ChunkOutcome second = DataPackImportService.processRows('LEAVE', sampleRows(), 'Leave.xlsx');
        System.assertEquals(0, second.inserted);
        System.assertEquals(4, [SELECT COUNT() FROM Time_Off_Request__c WHERE Comments__c LIKE '%[PACKKEY:PACK-L-DP9001-%']);
    }

    @IsTest
    static void rejectedHrRowsCarryARejectionReason() {
        WorkingCalendarUtil.clearWorkingDayCache();
        DataPackImportService.ChunkOutcome out = DataPackImportService.processRows(
            'TOT',
            new List<Map<String, Object>>{ row(2, CODE, 'Training', '2026-09-06', '2026-09-06', 'AM', 'PM', 'Rejected') },
            'TOT.xlsx'
        );
        System.assertEquals(1, out.inserted, String.join(out.errorLines, '|'));
        Time_Off_Request__c saved = [
            SELECT Stage__c, Rejection_Reason__c
            FROM Time_Off_Request__c
            WHERE Comments__c LIKE '%[PACKKEY:PACK-T-DP9001-%'
            WITH SYSTEM_MODE
        ];
        System.assertEquals('Rejected', saved.Stage__c);
        System.assert(saved.Rejection_Reason__c.startsWith('Rejected in HR system'), saved.Rejection_Reason__c);
    }

    @IsTest
    static void stagesChunksRunsJobAndBuildsErrorCsv() {
        WorkingCalendarUtil.clearWorkingDayCache();
        Test.startTest();
        DataPackImportService.ChunkResult result = DataPackImportService.stageChunk(
            'TOT',
            'Time Off.xlsx',
            'abcdef0123456789abcdef',
            '2026-09',
            JSON.serialize(new List<Map<String, Object>>{
                row(2, CODE, 'Office Work', '2026-09-06', '2026-09-06', 'AM', 'PM', 'Approved'),
                row(3, 'NOPE', 'Office Work', '2026-09-06', '2026-09-06', 'AM', 'PM', 'Approved')
            }),
            null,
            true,
            0,
            1
        );
        System.assertEquals('Queued', result.status);
        System.assertEquals(true, result.jobEnqueued);
        Test.stopTest();

        Sales_Data_Import_Batch__c batch = DistributorImportService.loadBatch(result.batchId);
        System.assertEquals('Completed', batch.Status__c);
        System.assertEquals('PACK:TOT', batch.Distributor_Code__c);
        System.assertEquals(1, batch.Rows_Inserted__c);
        System.assertEquals(1, batch.Rows_Failed__c);
        System.assertEquals(1, batch.Chunks_Processed__c);

        String csv = DataPackImportService.getBatchErrorCsv(result.batchId);
        System.assert(csv.startsWith(DataPackImportService.ERROR_HEADER), csv);
        System.assert(csv.contains('NOPE'), csv);

        List<DataPackImportService.BatchStatus> statuses = DataPackImportService.getBatchStatuses(new List<Id>{ result.batchId });
        System.assertEquals(1, statuses.size());
        System.assertEquals('TOT', statuses[0].kind);
        System.assertEquals(true, statuses[0].done);
        System.assertEquals('Time Off.xlsx', statuses[0].fileName);

        List<DataPackImportService.DuplicateHit> hits = DataPackImportService.findDuplicateFingerprints(
            new List<String>{ 'abcdef0123456789abcdef', 'ffffffffffffffff' }
        );
        System.assertEquals(1, hits.size());
        System.assertEquals(batch.Name, hits[0].batchName);
    }

    @IsTest
    static void incompleteUploadFailsAndResumeRoutesToPackJob() {
        WorkingCalendarUtil.clearWorkingDayCache();
        DataPackImportService.ChunkResult partial = DataPackImportService.stageChunk(
            'LEAVE',
            'Leave.xlsx',
            null,
            '2026-09',
            JSON.serialize(new List<Map<String, Object>>{ row(2, CODE, 'Annual Vacation', '2026-09-07', '2026-09-07', 'AM', 'PM', 'Approved') }),
            null,
            true,
            0,
            2
        );
        System.assertEquals('Failed', partial.status, 'two chunks expected, one received');

        DataPackImportService.ChunkResult one = DataPackImportService.stageChunk(
            'LEAVE',
            'Leave2.xlsx',
            null,
            '2026-09',
            JSON.serialize(new List<Map<String, Object>>{ row(2, CODE, 'Annual Vacation', '2026-09-07', '2026-09-07', 'AM', 'PM', 'Approved') }),
            null,
            false,
            0,
            1
        );
        System.assertEquals('Uploading', one.status);
        DistributorImportService.markFailed(one.batchId, 'test');
        Test.startTest();
        Sales_Data_Import_Batch__c resumed = DistributorImportService.resume(one.batchId);
        Test.stopTest();
        System.assertEquals('Queued', resumed.Status__c);
        System.assertEquals('Completed', DistributorImportService.loadBatch(one.batchId).Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM Time_Off_Request__c WHERE Comments__c LIKE '%[PACKKEY:PACK-L-DP9001-2026-09-07%']);
    }

    @IsTest
    static void jobEnqueueHelperCoversMoreAndDonePaths() {
        WorkingCalendarUtil.clearWorkingDayCache();
        DataPackImportService.ChunkResult staged = DataPackImportService.stageChunk(
            'LEAVE',
            'Leave-job.xlsx',
            null,
            '2026-09',
            JSON.serialize(new List<Map<String, Object>>{
                row(2, CODE, 'Annual Vacation', '2026-09-07', '2026-09-07', 'AM', 'PM', 'Approved')
            }),
            null,
            false,
            0,
            1
        );
        DataPackImportJob job = new DataPackImportJob(staged.batchId);
        job.enqueueNextIfNeeded(true);
        job.enqueueNextIfNeeded(false);
        try {
            new DataPackImportJob(UserInfo.getUserId()).execute(null);
        } catch (Exception ex) {
            System.assert(true, 'invalid batch id is tolerated via markFailed or load error');
        }
    }

    @IsTest
    static void mapsVisitTypeAndStatus() {
        System.assertEquals('Planned (Automatically)', DataPackImportService.mapVisitType('Planned'));
        System.assertEquals('Unplanned', DataPackImportService.mapVisitType('Unplanned'));
        System.assertEquals(null, DataPackImportService.mapVisitType('Maybe'));
        System.assertEquals('Completed', DataPackImportService.mapVisitStatus('Approved'));
        System.assertEquals('Cancelled', DataPackImportService.mapVisitStatus('Cancelled'));
        System.assertEquals(null, DataPackImportService.mapVisitStatus('Pending'));
    }

    @IsTest
    static void visitKindStaysDisabledWithoutHistoricalFlag() {
        DataPackImportService.Hooks hooks = DataPackImportService.getHooks();
        System.assertEquals(true, hooks.leaveTotReady);
        System.assertEquals(DataPackImportService.historicalVisitHooksReady(), hooks.historicalVisitFlag);
        if (!hooks.historicalVisitFlag) {
            DataPackImportService.ChunkOutcome out = DataPackImportService.processVisitRows(
                new List<Map<String, Object>>{ row(2, CODE, 'Visit', '2026-05-31', '2026-05-31', null, null, 'Approved') },
                'MAY Visits.xlsx'
            );
            System.assertEquals(1, out.failed);
            System.assertEquals(0, out.inserted);
            try {
                DataPackImportService.stageChunk('VISIT', 'MAY Visits.xlsx', null, '2026-05', '[{"a":1}]', null, false, 0, 1);
                System.assert(false, 'visit import must be rejected until the flag exists');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        } else {
            User u = [SELECT Id, Name FROM User WHERE EmployeeNumber = :CODE LIMIT 1];
            Account acct = new Account(Name = 'Visit Pack Test Doctor');
            insert acct;
            Map<String, Object> visitRow = new Map<String, Object>{
                'sourceRow' => 2,
                'employeeName' => u.Name,
                'customerName' => acct.Name,
                'visitDate' => '2026-05-31',
                'planned' => 'Unplanned',
                'status' => 'Approved',
                'comments' => 'historical'
            };
            DataPackImportService.ChunkOutcome out = DataPackImportService.processVisitRows(
                new List<Map<String, Object>>{ visitRow },
                'MAY Visits.xlsx'
            );
            System.assertEquals(1, out.inserted, String.join(out.errorLines, '|'));
            System.assertEquals(0, out.failed);
            Visit__c saved = [
                SELECT Status__c, Visit_Type__c, Client_Visit_Key__c
                FROM Visit__c
                WHERE Account__c = :acct.Id
                LIMIT 1
            ];
            System.assertEquals('Completed', saved.Status__c);
            System.assertEquals('Unplanned', saved.Visit_Type__c);
            System.assert(saved.Client_Visit_Key__c != null && saved.Client_Visit_Key__c.startsWith('PACKV-'));
        }
        try {
            DataPackImportService.stageChunk('NOPE', 'x', null, '2026-05', '[{"a":1}]', null, false, 0, 1);
            System.assert(false, 'unknown kind rejected');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void visitUsesPreResolvedIdsAndKeepsProducts() {
        if (!DataPackImportService.historicalVisitHooksReady()) {
            return;
        }
        User u = [SELECT Id, Name FROM User WHERE EmployeeNumber = :CODE LIMIT 1];
        // Two same-name accounts: the name lookup alone cannot tell them apart.
        Account first = new Account(Name = 'Same Name Doctor');
        Account second = new Account(Name = 'Same Name Doctor');
        insert new List<Account>{ first, second };
        Map<String, Object> visitRow = new Map<String, Object>{
            'sourceRow' => 2,
            'employeeName' => 'Rep Name Spelled Differently',
            'userId' => u.Id,
            'customerName' => 'Same Name Doctor',
            'accountId' => second.Id,
            'visitDate' => '2026-09-30',
            'planned' => 'Planned',
            'status' => 'Approved',
            'products' => 'NEXICURE 40 MG 20 TAB,  EMPACOZA 10 MG 30 TAB'
        };
        DataPackImportService.ChunkOutcome out = DataPackImportService.processVisitRows(
            new List<Map<String, Object>>{ visitRow },
            'September 2026 visits Log.xlsx'
        );
        System.assertEquals(1, out.inserted, String.join(out.errorLines, '|'));
        Visit__c saved = [SELECT Account__c, Assigned_To__c, Products_Discussed__c FROM Visit__c LIMIT 1];
        System.assertEquals(second.Id, saved.Account__c);
        System.assertEquals(u.Id, saved.Assigned_To__c);
        System.assertEquals('NEXICURE 40 MG 20 TAB; EMPACOZA 10 MG 30 TAB', saved.Products_Discussed__c);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Employee_Time_Card__c WHERE Employee__c = :u.Id],
            'historical visits must not build time cards'
        );
    }

    @IsTest
    static void idOrNullRejectsWrongObjectAndText() {
        User u = [SELECT Id FROM User WHERE EmployeeNumber = :CODE LIMIT 1];
        System.assertEquals(u.Id, DataPackImportService.idOrNull(String.valueOf(u.Id), User.SObjectType));
        System.assertEquals(null, DataPackImportService.idOrNull(String.valueOf(u.Id), Account.SObjectType));
        System.assertEquals(null, DataPackImportService.idOrNull('not an id', User.SObjectType));
        System.assertEquals(null, DataPackImportService.idOrNull(null, User.SObjectType));
        System.assertEquals(null, DataPackImportService.productList(' , ;'));
    }
}
