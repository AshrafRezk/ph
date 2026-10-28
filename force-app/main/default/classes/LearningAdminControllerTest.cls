@IsTest
private class LearningAdminControllerTest {
    @IsTest
    static void createAssignAndListMaterials() {
        Id courseId = LearningAdminController.createMaterial(
            'Test Course',
            'Course',
            null,
            true
        );
        Id videoId = LearningAdminController.createMaterial(
            'Test Video',
            'Video',
            courseId,
            true
        );
        Id quizId = LearningAdminController.createMaterial(
            'Test Quiz',
            'Quiz',
            courseId,
            true
        );
        System.assertNotEquals(null, courseId);
        System.assertNotEquals(null, videoId);
        System.assertNotEquals(null, quizId);

        Date startDate = Date.today();
        Date endDate = Date.today().addDays(30);
        LearningAdminController.updateMaterial(
            courseId,
            'Test Course',
            'Desc',
            true,
            30,
            'Course',
            null,
            startDate,
            endDate
        );

        LearningAdminController.AssignResult assignResult = LearningAdminController.assignToUser(
            UserInfo.getUserId(),
            courseId
        );
        System.assertNotEquals(null, assignResult.courseInstanceId);
        System.assert(assignResult.instanceCount >= 3);

        List<LearningAdminController.FilterOption> buOptions =
            LearningAdminController.getBusinessUnitFilterOptions();
        System.assert(!buOptions.isEmpty());
        System.assertEquals('All', buOptions[0].value);

        Learning_Material__c stamped = [
            SELECT Effective_Start_Date__c, Effective_End_Date__c
            FROM Learning_Material__c
            WHERE Id = :courseId
        ];
        System.assertEquals(startDate, stamped.Effective_Start_Date__c);
        System.assertEquals(endDate, stamped.Effective_End_Date__c);

        List<LearningAdminController.MaterialSummary> rows = LearningAdminController.getMaterialSummaries(
            'Test',
            'All',
            'Active',
            'All'
        );
        System.assert(rows.size() >= 3);

        List<LearningAdminController.MaterialSummary> quizzes = LearningAdminController.getMaterialSummaries(
            null,
            'Quiz',
            'All',
            'All'
        );
        Boolean foundQuiz = false;
        for (LearningAdminController.MaterialSummary row : quizzes) {
            if (row.id == quizId) {
                foundQuiz = true;
            }
        }
        System.assert(foundQuiz);

        List<LearningAdminController.AssignmentRow> assignees = LearningAdminController.getAssignments(
            courseId
        );
        System.assertEquals(1, assignees.size());
        System.assertEquals(UserInfo.getUserId(), assignees[0].userId);

        LearningAdminController.updateMaterial(
            courseId,
            'Test Course Updated',
            'Updated description',
            true,
            45,
            'Course',
            null,
            startDate,
            endDate
        );
        Learning_Material__c updated = [
            SELECT Title__c, Description__c, Duration__c
            FROM Learning_Material__c
            WHERE Id = :courseId
        ];
        System.assertEquals('Test Course Updated', updated.Title__c);
        System.assertEquals(45, updated.Duration__c);

        ContentVersion cv = new ContentVersion(
            Title = 'Sample Video',
            PathOnClient = 'sample.mp4',
            VersionData = Blob.valueOf('fake-video-bytes'),
            IsMajorVersion = true
        );
        insert cv;
        cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
        LearningAdminController.FileUploadResult uploadResult = LearningAdminController.finalizeMaterialFileUpload(
            videoId,
            cv.ContentDocumentId
        );
        System.assertNotEquals(null, uploadResult.materialUrl);
        Learning_Material__c videoAfterUpload = [
            SELECT Material_URL__c, Content_Document_Id__c
            FROM Learning_Material__c
            WHERE Id = :videoId
        ];
        System.assertEquals(String.valueOf(cv.ContentDocumentId), videoAfterUpload.Content_Document_Id__c);
        System.assertEquals(uploadResult.materialUrl, videoAfterUpload.Material_URL__c);
    }

    @IsTest
    static void updateMaterial_rejectsInvertedWindow() {
        Id courseId = LearningAdminController.createMaterial(
            'Window Guard Course',
            'Course',
            null,
            true
        );
        Boolean blocked = false;
        try {
            LearningAdminController.updateMaterial(
                courseId,
                'Window Guard Course',
                null,
                true,
                null,
                'Course',
                null,
                Date.today().addDays(5),
                Date.today()
            );
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        System.assert(blocked, 'Expected inverted availability window to be rejected.');
    }

    @IsTest
    static void saveTerritoryAlignments_createsAndClearsRows() {
        Territory2 territory = getOrCreateTestTerritory('TERR_LMS_ALIGN_TEST');
        if (territory == null) {
            return;
        }

        User runUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        List<UserTerritory2Association> existingAssoc = [
            SELECT Id
            FROM UserTerritory2Association
            WHERE Territory2Id = :territory.Id AND UserId = :runUser.Id
            LIMIT 1
        ];
        if (existingAssoc.isEmpty()) {
            insert new UserTerritory2Association(
                UserId = runUser.Id,
                Territory2Id = territory.Id,
                RoleInTerritory2 = 'Medical Rep'
            );
        }

        Id courseId = LearningAdminController.createMaterial(
            'Territory Align Course',
            'Course',
            null,
            true
        );
        LearningAdminController.createMaterial('Territory Align Video', 'Video', courseId, true);

        Test.startTest();
        LearningAdminController.TerritorySaveResult saved =
            LearningAdminController.saveTerritoryAlignments(
                courseId,
                new List<Id>{ territory.Id }
            );
        List<LearningAdminController.TerritoryTreeNode> tree =
            LearningAdminController.getTerritoryTreeForMaterial(courseId);
        LearningAdminController.TerritorySaveResult cleared =
            LearningAdminController.saveTerritoryAlignments(
                courseId,
                new List<Id>()
            );
        Test.stopTest();

        System.assertEquals(1, saved.territoryCount);
        System.assert(saved.userCount >= 1);
        System.assert(saved.instanceCount >= 1);
        System.assertEquals(0, cleared.territoryCount);

        Integer alignmentCount = [
            SELECT COUNT()
            FROM Learning_Material_Territory_Alignment__c
            WHERE Learning_Material__c = :courseId
        ];
        System.assertEquals(0, alignmentCount);

        Integer instanceCount = [
            SELECT COUNT()
            FROM Learning_Material_Instance__c
            WHERE Material__c = :courseId AND Learner__c = :runUser.Id
        ];
        System.assertEquals(
            0,
            instanceCount,
            'Clearing alignment should remove learner instances for uncovered users.'
        );
        System.assert(
            cleared.removedInstanceCount >= 1,
            'Expected removedInstanceCount when clearing territory alignment.'
        );
        System.assertNotEquals(null, tree);
    }

    private static Territory2 getOrCreateTestTerritory(String externalId) {
        List<Territory2> existing = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :externalId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return null;
        }

        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        if (models.isEmpty()) {
            return null;
        }

        Territory2 territory = new Territory2(
            Name = 'LMS Align Test Territory',
            DeveloperName = 'Lms_Align_Test_Territory',
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = externalId
        );
        insert territory;
        return territory;
    }
}