@IsTest
private class CareCoachTests {
    private static final String COACH_ALIAS = 'pspcoach';
    private static final String COMPANY_ALIAS = 'pspmah';

    @TestSetup
    static void setup() {
        User coach = makeUser(COACH_ALIAS, new List<String>{ 'PSP_Care_Coach' });
        makeUser(COMPANY_ALIAS, new List<String>{ 'PSP_Pharma_Company_Viewer' });

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Product2 erbitux = new Product2(Name = 'Erbitux', ProductCode = 'PSP-ERBITUX', IsActive = true, Therapy_Area__c = 'Oncology');
            Product2 rebif = new Product2(Name = 'Rebif', ProductCode = 'PSP-REBIF', IsActive = true, Therapy_Area__c = 'Neurology');
            insert new List<Product2>{ erbitux, rebif };

            List<Patient__c> patients = new List<Patient__c>();
            for (Integer i = 0; i < 6; i++) {
                patients.add(new Patient__c(
                    OwnerId = coach.Id,
                    First_Name__c = 'Mona' + i,
                    Last_Name__c = 'Hassan',
                    Phone__c = '+20 100 555 000' + i,
                    Mobile__c = '+20 111 555 000' + i,
                    Email__c = 'mona' + i + '@example.com',
                    Birthdate__c = Date.today().addYears(-40),
                    Gender__c = 'Female',
                    Status__c = Math.mod(i, 2) == 0 ? 'Ongoing' : 'Pending',
                    Primary_Product__c = Math.mod(i, 2) == 0 ? erbitux.Id : rebif.Id,
                    Care_Coach__c = coach.Id,
                    Enrollment_Date__c = Date.today(),
                    External_Id__c = 'TEST-' + i
                ));
            }
            insert patients;

            insert new Patient_Interaction__c(
                Patient__c = patients[0].Id,
                Care_Coach__c = coach.Id,
                Product__c = erbitux.Id,
                Status__c = 'Reached',
                Type__c = 'Call',
                Direction__c = 'Outbound',
                Interaction_Reason__c = 'Adherence check',
                Start__c = System.now().addDays(-1),
                Notes__c = 'Called back on +20 100 555 0000',
                Transcript__c = 'Coach: How are you?\nPatient: I missed a dose and I have a rash, call me on +20 100 555 0000.'
            );
            insert new Patient_Order__c(
                Patient__c = patients[0].Id,
                Product__c = erbitux.Id,
                Quantity__c = 2,
                Status__c = 'Delivered',
                Order_Date__c = Date.today(),
                Delivery_Address__c = '12 Nile St'
            );
            insert new Care_Script__c(
                Title__c = 'Managing acneiform rash',
                Question__c = 'What can I do about the rash?',
                Answer__c = '<p>Moisturise daily.</p>',
                Product__c = erbitux.Id,
                Category__c = 'Side effects',
                Publication_Status__c = 'Published',
                Validation_Status__c = 'Validated'
            );
        }
    }

    static User makeUser(String alias, List<String> permSets) {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias,
            Email = alias + '@psp.test',
            EmailEncodingKey = 'UTF-8',
            LastName = alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = prof.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = alias + '.' + System.currentTimeMillis() + '@psp.test'
        );
        insert u;
        List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
        for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN :permSets]) {
            psas.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
        }
        insert psas;
        return u;
    }

    static User coach() {
        return [SELECT Id FROM User WHERE Alias = :COACH_ALIAS AND Email = 'pspcoach@psp.test' LIMIT 1];
    }

    static User company() {
        return [SELECT Id FROM User WHERE Alias = :COMPANY_ALIAS AND Email = 'pspmah@psp.test' LIMIT 1];
    }

    static Patient__c firstPatient() {
        return [SELECT Id, Primary_Product__c FROM Patient__c WHERE External_Id__c = 'TEST-0'];
    }

    @IsTest
    static void pspViewShowsIdentityAndPreviewMasksIt() {
        Id pid = firstPatient().Id;
        System.runAs(coach()) {
            System.assert(CareCoachAccess.hasFullAccess(), 'Coach permission set grants full access');
            CareCoachPatientService.Patient360 psp = CareCoachPatientService.getPatient360(pid, 'psp');
            System.assertEquals(false, psp.masked);
            System.assertEquals('Mona0 Hassan', psp.patient.core.displayName);
            System.assertNotEquals(null, psp.patient.core.phone);
            System.assertEquals('12 Nile St', psp.orders[0].deliveryAddress);

            CareCoachPatientService.Patient360 preview = CareCoachPatientService.getPatient360(pid, 'company');
            System.assertEquals(true, preview.masked);
            System.assertEquals(null, preview.patient.core.phone);
            System.assertEquals(null, preview.patient.birthdate);
            System.assert(preview.patient.core.displayName.startsWith('M.H.'), preview.patient.core.displayName);
            System.assertEquals(null, preview.orders[0].deliveryAddress);
        }
    }

    @IsTest
    static void companyUserGetsDeidentifiedDataOnly() {
        Id pid = firstPatient().Id;
        System.runAs(company()) {
            System.assertEquals(false, CareCoachAccess.hasFullAccess());
            System.assertEquals('company', CareCoachAccess.resolveMode('psp'));
            System.assertEquals('all', CareCoachAccess.resolveScope('mine'));

            CareCoachPatientService.PatientPage page = CareCoachPatientService.getPatients('{"mode":"psp"}');
            System.assertEquals(true, page.masked);
            System.assertEquals(6, page.total, 'Company viewer sees all PSP patients');
            for (CareCoachPatientService.PatientRow r : page.rows) {
                System.assertEquals(null, r.phone);
                System.assertEquals(null, r.email);
                System.assert(!r.displayName.contains('Mona'));
            }

            CareCoachPatientService.Patient360 view = CareCoachPatientService.getPatient360(pid, 'psp');
            System.assertEquals(true, view.masked);
            System.assertEquals(false, view.canEdit);
            System.assertEquals(40, view.patient.core.age);
            System.assertEquals('Female', view.patient.core.gender);
            System.assertEquals(1, view.interactions.size());
            System.assert(!view.interactions[0].transcript.contains('555'), 'Phone numbers must be redacted');
            System.assert(!view.interactions[0].notes.contains('555'));
            System.assertEquals(1, view.orders.size());

            Boolean blocked = false;
            try {
                CareCoachPatientService.updatePatientStatus(pid, 'Ongoing', null);
            } catch (AuraHandledException e) {
                blocked = true;
            }
            System.assert(blocked, 'Company view must be read-only');

            Boolean fieldHidden = false;
            try {
                Patient__c leaked = [SELECT Phone__c FROM Patient__c WHERE Id = :pid WITH USER_MODE];
            } catch (QueryException e) {
                fieldHidden = true;
            }
            System.assert(fieldHidden, 'Field-level security hides patient contact details from the company');
        }
    }

    @IsTest
    static void coachScopeIsForcedToOwnPatients() {
        System.runAs(coach()) {
            CareCoachAccess.supervisorOverride = false;
            System.assertEquals('mine', CareCoachAccess.resolveScope('all'));
            CareCoachPatientService.PatientPage page = CareCoachPatientService.getPatients(
                '{"mode":"psp","scope":"all","search":"Mona","status":"Ongoing"}'
            );
            System.assertEquals('mine', page.scope);
            System.assertEquals(3, page.total);
            System.assertEquals(3, page.statusCounts.get('Pending'));
            CareCoachPatientService.FilterOptions opts = CareCoachPatientService.getFilterOptions();
            System.assertEquals(2, opts.products.size());
            System.assertEquals(1, opts.coaches.size());
            System.assert(CareCoachAccess.getContext().hasFullAccess);
        }
    }

    @IsTest
    static void logInteractionAnalysesTranscriptAndSchedulesFollowUp() {
        Id pid = firstPatient().Id;
        System.runAs(coach()) {
            Test.startTest();
            CareCoachPatientService.InteractionRow row = CareCoachPatientService.logInteraction(
                pid,
                JSON.serialize(new Map<String, Object>{
                    'status' => 'Reached',
                    'reason' => 'Side effect report',
                    'transcript' => 'Coach: Any issues?\nPatient: I forgot two doses and skipped another because I cannot afford the next box. The injection site redness is worse and I am worried.',
                    'followUpDate' => Date.today().addDays(3),
                    'durationMinutes' => 12
                })
            );
            Test.stopTest();
            System.assertEquals('High', row.aiRisk);
            System.assertEquals('Negative', row.aiSentiment);
            System.assert(row.aiSideEffects.contains('Injection-site reaction'));
            System.assertEquals(CareCoachCallAnalysisService.HEURISTIC_ENGINE, row.aiEngine);
        }
        Patient__c p = [SELECT Last_Call_Status__c, Next_Call_Date__c, Adherence_Level__c FROM Patient__c WHERE Id = :pid];
        System.assertEquals('Reached', p.Last_Call_Status__c);
        System.assertNotEquals(null, p.Next_Call_Date__c);
        System.assertEquals('High risk', p.Adherence_Level__c);
    }

    @IsTest
    static void heuristicRecognisesPositiveCall() {
        CareCoachCallAnalysisService.Analysis a = CareCoachCallAnalysisService.heuristic(
            'Coach: How is the pen?\nPatient: Great, no problem at all, I feel better and take every dose on time. Thank you.',
            'Follow up',
            'Rebif'
        );
        System.assertEquals('Low', a.adherenceRisk);
        System.assertEquals('Positive', a.sentiment);
        System.assertEquals(null, a.sideEffects);
    }

    @IsTest
    static void analyzeExistingInteraction() {
        Patient_Interaction__c i = [SELECT Id FROM Patient_Interaction__c LIMIT 1];
        System.runAs(coach()) {
            CareCoachCallAnalysisService.Analysis a = CareCoachCallAnalysisService.analyze(i.Id);
            System.assertNotEquals(null, a.summary);
        }
        System.assertNotEquals(null, [SELECT AI_Analyzed_On__c FROM Patient_Interaction__c WHERE Id = :i.Id].AI_Analyzed_On__c);
    }

    @IsTest
    static void plannerCallLifecycle() {
        Patient__c p = firstPatient();
        Datetime start = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(11, 0, 0, 0));
        System.runAs(coach()) {
            CareCoachPlannerController.PlannerCall call = CareCoachPlannerController.scheduleCall(p.Id, start, 20, 'Adherence check', 'Outbound', 'Check pen');
            System.assertEquals('Planned', call.status);

            call = CareCoachPlannerController.rescheduleCall(call.id, start.addHours(2), null);
            System.assertEquals(start.addHours(2), call.startTime);

            CareCoachPlannerController.PlannerData data = CareCoachPlannerController.getPlannerData(Date.today(), 7, 'psp');
            System.assert(!data.patients.isEmpty());
            Boolean found = false;
            for (CareCoachPlannerController.PlannerCall c : data.calls) {
                found = found || c.id == call.id;
            }
            System.assert(found, 'Scheduled call should be on the planner');
            System.assert(!data.timeOffTypes.isEmpty());
            System.assert(!data.outcomes.isEmpty());

            CareCoachPatientService.InteractionRow done = CareCoachPlannerController.completeCall(
                call.id,
                JSON.serialize(new Map<String, Object>{ 'status' => 'Reached', 'transcript' => 'Patient: All good, thank you.', 'followUpDate' => Date.today().addDays(14) })
            );
            System.assertEquals('Reached', done.status);
            System.assertEquals(1, [SELECT COUNT() FROM Patient_Interaction__c WHERE Patient__c = :p.Id AND Status__c = 'Planned']);

            CareCoachPlannerController.PlannerCall other = CareCoachPlannerController.scheduleCall(p.Id, start.addDays(1), null, null, null, null);
            CareCoachPlannerController.deleteCall(other.id);
            System.assertEquals(0, [SELECT COUNT() FROM Patient_Interaction__c WHERE Id = :other.id]);
        }
    }

    @IsTest
    static void plannerTimeOffLifecycle() {
        String typeValue = Time_Off_Request__c.Type__c.getDescribe().getPicklistValues()[0].getValue();
        Datetime start = Datetime.newInstance(Date.today().addDays(20), Time.newInstance(10, 0, 0, 0));
        System.runAs(coach()) {
            CareCoachPlannerController.PlannerTimeOff t = CareCoachPlannerController.createTimeOff(typeValue, 'Hours', '2', start, 'Training', false);
            System.assertEquals('Draft', t.stage);
            t = CareCoachPlannerController.updateTimeOff(t.id, typeValue, 'Full_Day', null, start, 'All day');
            System.assertEquals('Full_Day', t.spanType);
            t = CareCoachPlannerController.setTimeOffStage(t.id, 'Submitted for Approval');
            System.assertEquals('Submitted for Approval', t.stage);
            t = CareCoachPlannerController.moveTimeOff(t.id, start.addDays(2));
            System.assertEquals('Submitted for Approval', t.stage);
            System.assertEquals(start.date().addDays(2), t.startTime.date());
            t = CareCoachPlannerController.setTimeOffStage(t.id, 'Draft');
            t = CareCoachPlannerController.updateTimeOff(t.id, typeValue, 'Hours', '2', start, 'Training');
            t = CareCoachPlannerController.moveTimeOff(t.id, start.addHours(3));
            System.assertEquals(start.addHours(3), t.startTime);
            System.assertEquals(start.addHours(5), t.endTime);
            CareCoachPlannerController.deleteTimeOff(t.id);
            System.assertEquals(0, [SELECT COUNT() FROM Time_Off_Request__c WHERE Id = :t.id]);
        }
    }

    @IsTest
    static void ordersAndStatusChanges() {
        Patient__c p = firstPatient();
        System.runAs(coach()) {
            CareCoachPatientService.OrderRow o = CareCoachPatientService.createOrder(p.Id, p.Primary_Product__c, 3, null, 'Refill');
            System.assertEquals('Requested', o.status);
            System.assertEquals(3, o.quantity);

            Boolean needsReason = false;
            try {
                CareCoachPatientService.updatePatientStatus(p.Id, 'Dropped (Stopped)', null);
            } catch (AuraHandledException e) {
                needsReason = true;
            }
            System.assert(needsReason);
            CareCoachPatientService.updatePatientStatus(p.Id, 'Dropped (Stopped)', 'Side effects');
        }
        System.assertEquals('Dropped', [SELECT Status_Group__c FROM Patient__c WHERE Id = :p.Id].Status_Group__c);
    }

    @IsTest
    static void ordersBoardShowsLineItemsAndMovesStatus() {
        Patient__c p = firstPatient();
        System.runAs(coach()) {
            CareCoachPatientService.OrderRow created = CareCoachPatientService.createOrder(p.Id, p.Primary_Product__c, 2, 'Home Delivery', 'Refill');
            CareCoachOrderService.OrderBoard board = CareCoachOrderService.getOrders('psp', 'mine', 30);
            System.assert(board.canEdit);
            CareCoachOrderService.OrderCard card;
            for (CareCoachOrderService.OrderCard c : board.orders) {
                if (c.id == created.id) {
                    card = c;
                }
            }
            System.assertNotEquals(null, card);
            System.assert(card.items.size() > 1, 'Medicine plus supplies');
            System.assertEquals(2, card.items[0].quantity);
            System.assertEquals(Date.today().addDays(3), card.promisedDate);
            System.assert(card.orderTotal > 0);
            System.assert(card.patientName.contains('Mona'));

            CareCoachOrderService.OrderCard moved = CareCoachOrderService.updateOrderStatus(created.id, 'Delivered', 'EGX1');
            System.assertEquals('Delivered', moved.status);
            System.assertEquals(Date.today(), moved.deliveryDate);
            System.assertEquals('EGX1', moved.trackingNumber);
        }
        System.runAs(company()) {
            CareCoachOrderService.OrderBoard board = CareCoachOrderService.getOrders('psp', 'all', null);
            System.assert(board.masked);
            System.assert(!board.canEdit);
            System.assert(!board.orders.isEmpty());
            for (CareCoachOrderService.OrderCard c : board.orders) {
                System.assert(!c.patientName.contains('Mona'));
                System.assertEquals(null, c.deliveryAddress);
            }
            Boolean blocked = false;
            try {
                CareCoachOrderService.updateOrderStatus(board.orders[0].id, 'Cancelled', null);
            } catch (Exception e) {
                blocked = true;
            }
            System.assert(blocked);
        }
    }

    @IsTest
    static void backfillAddsItemsToOldOrders() {
        Test.startTest();
        Database.executeBatch(new CareCoachOrderItemBackfill(), 200);
        Test.stopTest();
        Patient_Order__c o = [SELECT Promised_Date__c, Line_Count__c, Total_Units__c FROM Patient_Order__c LIMIT 1];
        System.assertNotEquals(null, o.Promised_Date__c);
        System.assert(o.Line_Count__c > 1);
        System.assert(o.Total_Units__c >= 2);
    }

    @IsTest
    static void updateInteractionLinksKnowledgeAndHidesRecording() {
        Patient__c p = firstPatient();
        Care_Script__c script = [SELECT Id, Title__c FROM Care_Script__c LIMIT 1];
        System.runAs(coach()) {
            CareCoachPatientService.InteractionRow created = CareCoachPatientService.logInteraction(
                p.Id,
                JSON.serialize(new Map<String, Object>{
                    'status' => 'Reached',
                    'notes' => 'First note',
                    'transcript' => 'Coach: Hello\nPatient: تمام',
                    'language' => 'Arabic (Egypt)',
                    'recordingConsent' => true
                })
            );
            System.assertEquals('Arabic (Egypt)', created.language);
            CareCoachPatientService.InteractionRow updated = CareCoachPatientService.updateInteraction(
                created.id,
                JSON.serialize(new Map<String, Object>{
                    'status' => 'Call back',
                    'reason' => 'Follow up',
                    'notes' => 'هكلمه بكرة',
                    'scriptId' => script.Id,
                    'language' => 'Arabic (Egypt)',
                    'adverseEvent' => false
                })
            );
            System.assertEquals('Call back', updated.status);
            System.assertEquals(script.Id, updated.scriptId);
            System.assertEquals('هكلمه بكرة', updated.notes);
            System.assert(updated.transcript.contains('تمام'));

            Integer changed = CareCoachCallSamples.applyToRecentCalls();
            System.assert(changed > 0);
            Patient_Interaction__c sample = [
                SELECT Language__c, Recording_URL__c, Care_Script__c, Transcript__c
                FROM Patient_Interaction__c
                WHERE Recording_URL__c != NULL
                ORDER BY Start__c DESC NULLS LAST
                LIMIT 1
            ];
            System.assert(sample.Recording_URL__c.contains('/media/calls/'));
            System.assert(sample.Transcript__c.contains('Patient:'));
        }
        System.runAs(company()) {
            Boolean hidden = false;
            try {
                CareCoachTelephonyController.getCallRecording([SELECT Id FROM Patient_Interaction__c LIMIT 1].Id);
            } catch (Exception e) {
                hidden = true;
            }
            System.assert(hidden);
        }
    }

    @IsTest
    static void onboardingControllerCoversPage() {
        Patient__c p = firstPatient();
        p.Onboarding_Token__c = 'tok-page-1-long-enough';
        update p;

        PageReference missingPage = Page.PatientOnboarding;
        missingPage.getParameters().put('t', 'missing');
        Test.setCurrentPage(missingPage);
        PatientOnboardingController missing = new PatientOnboardingController();
        System.assertEquals(true, missing.invalid);
        missing.save();
        System.assertEquals(false, missing.submitted);

        PageReference page = Page.PatientOnboarding;
        page.getParameters().put('t', 'tok-page-1-long-enough');
        Test.setCurrentPage(page);
        PatientOnboardingController c = new PatientOnboardingController();
        System.assertEquals(false, c.invalid);
        c.form.consent = true;
        c.form.diagnosis = 'Relapsing-remitting multiple sclerosis';
        c.save();
        System.assertEquals(true, c.submitted);
        System.assertEquals(null, c.message);
    }

    @IsTest
    static void homeDataForCoachAndCompany() {
        System.runAs(coach()) {
            CareCoachHomeController.HomeData mine = CareCoachHomeController.getHomeData('psp', 'mine', null);
            System.assertEquals(false, mine.masked);
            System.assertEquals(6, mine.totalPatients);
            System.assertEquals(4, mine.kpis.size());
            System.assertEquals(3, mine.kpis[0].value);
            System.assertEquals(5, mine.board.size());
            System.assertEquals(6, mine.months.size());
            System.assertEquals(1, mine.calls.size());
        }
        System.runAs(company()) {
            CareCoachHomeController.HomeData view = CareCoachHomeController.getHomeData('psp', null, null);
            System.assertEquals(true, view.masked);
            System.assertEquals('all', view.scope);
            System.assertEquals(6, view.totalPatients);
            System.assertEquals(1, view.coaches.size());
            for (CareCoachHomeController.BoardColumn c : view.board) {
                for (CareCoachPatientService.PatientRow r : c.patients) {
                    System.assertEquals(null, r.phone);
                }
            }
        }
    }

    @IsTest
    static void catalogProductsAndScripts() {
        System.runAs(coach()) {
            CareCoachAccess.supervisorOverride = true;
            List<CareCoachCatalogController.TherapyGroup> groups = CareCoachCatalogController.getProducts('all');
            System.assertEquals(2, groups.size());
            Integer patients = 0;
            for (CareCoachCatalogController.TherapyGroup g : groups) {
                for (CareCoachCatalogController.ProductCard c : g.products) {
                    patients += c.totalPatients;
                }
            }
            System.assertEquals(6, patients);

            List<CareCoachCatalogController.ScriptRow> scripts = CareCoachCatalogController.getScripts('rash', null, 'Side effects', true);
            System.assertEquals(1, scripts.size());
            CareCoachCatalogController.ScriptRow s = CareCoachCatalogController.getScript(scripts[0].id);
            System.assert(s.answer.contains('Moisturise'));
            System.assertEquals(1, CareCoachCatalogController.markHelpful(s.id));
        }
    }

    @IsTest
    static void previewReadsEgyptianCall() {
        System.runAs(coach()) {
            CareCoachCallAnalysisService.Analysis rash = CareCoachCallAnalysisService.preview(
                'Patient: والله فيه طفح خفيف على وشي ومش مريحني.'
            );
            System.assert(rash.sideEffects.contains('Skin rash'), rash.sideEffects);
            System.assert(rash.nextBestAction.contains('side-effect'), rash.nextBestAction);
            System.assertEquals('Negative', rash.sentiment);

            CareCoachCallAnalysisService.Analysis dose = CareCoachCallAnalysisService.preview('Heard: نسيت جرعة أول امبارح');
            System.assert(dose.nextBestAction.contains('SMS'), dose.nextBestAction);
        }
    }

    @IsTest
    static void redactStripsContactDetails() {
        String out = CareCoachAccess.redact('Reach me at 01001234567 or a.b@test.com');
        System.assert(!out.contains('0100'));
        System.assert(!out.contains('@test.com'));
        System.assertEquals(null, CareCoachAccess.redact(null));
    }
}