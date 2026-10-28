@IsTest
private class CareCoachDemoSeedTest {
    @IsTest
    static void seedsPatientsJourneysAndPlanner() {
        Map<String, Id> products = CareCoachDemoSeed.upsertProducts();
        CareCoachDemoSeed.seedScripts(products);
        System.assertEquals(4, products.size(), 'Four Merck PSP products');
        System.assert([SELECT COUNT() FROM Care_Script__c] >= 15, 'Care scripts seeded');

        CareCoachDemoSeed seed = new CareCoachDemoSeed(0.06, 4);
        List<Integer> chunks = new List<Integer>();
        for (Integer i : seed.start(null)) {
            chunks.add(i);
        }
        Test.startTest();
        seed.execute(null, chunks);
        seed.execute(null, new List<Integer>{ chunks[0] });
        seed.finish(null);
        CareCoachDemoSeed.seedPlanner();
        Test.stopTest();

        Integer patients = [SELECT COUNT() FROM Patient__c WHERE External_Id__c LIKE 'SEED-%'];
        System.assertEquals(seed.patientsCreated, patients, 'Re-running a chunk does not duplicate patients');
        System.assert(patients > 60, 'Patients seeded: ' + patients);
        System.assert([SELECT COUNT() FROM Patient__c WHERE Primary_Product__r.ProductCode = 'PSP-ERBITUX'] > patients / 2, 'Erbitux dominates enrolment');
        System.assert([SELECT COUNT() FROM Patient_Interaction__c WHERE AI_Sentiment__c != NULL] > 0, 'Transcripts analysed');
        System.assert([SELECT COUNT() FROM Patient_Interaction__c WHERE Status__c = 'Planned'] > 0, 'Planned calls created');
        System.assert([SELECT COUNT() FROM Patient_Order__c] > 0, 'Orders created');
        System.assert([SELECT COUNT() FROM Patient_Therapy__c] == patients, 'One therapy per patient');
        System.assert([SELECT COUNT() FROM Patient__c WHERE Status_Group__c = 'Ongoing'] > 0, 'Ongoing patients');
        System.assert([SELECT COUNT() FROM Patient__c WHERE Last_Call_Date__c != NULL] > 0, 'Call roll-ups applied');
    }

    @IsTest
    static void kickoffAssignsCoachPermissions() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            System.enqueueJob(new CareCoachDemoSeed.Kickoff(0.1, 1));
            Test.stopTest();
        }
        System.assert([
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSet.Name = 'PSP_Care_Coach'
        ] == 1, 'Running user becomes a care coach');
    }

    @IsTest
    static void runCreatesCatalogue() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            CareCoachDemoSeed.run(0.1, 1);
            Test.stopTest();
        }
        System.assertEquals(4, [SELECT COUNT() FROM Product2 WHERE ProductCode LIKE 'PSP-%']);
    }

    @IsTest
    static void purgeRemovesSeededPatients() {
        Map<String, Id> products = CareCoachDemoSeed.upsertProducts();
        insert new Patient__c(External_Id__c = 'SEED-TEST-1', First_Name__c = 'Test', Last_Name__c = 'Seed', Primary_Product__c = products.get('PSP-REBIF'));
        insert new Patient__c(External_Id__c = 'MANUAL-1', First_Name__c = 'Keep', Last_Name__c = 'Me');
        Test.startTest();
        CareCoachDemoSeed.purge();
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Patient__c WHERE External_Id__c LIKE 'SEED-%']);
        System.assertEquals(1, [SELECT COUNT() FROM Patient__c]);
    }
}