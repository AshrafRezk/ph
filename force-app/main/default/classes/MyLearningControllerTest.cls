@IsTest
private class MyLearningControllerTest {
    @IsTest
    static void courseProgressQuizAndCertificate() {
        Id courseId = LearningAdminController.createMaterial(
            'Cert Course',
            'Course',
            null,
            true
        );
        update new Learning_Material__c(
            Id = courseId,
            Issue_Certificate__c = true,
            Description__c = 'Course description'
        );
        Id videoId = LearningAdminController.createMaterial(
            'Cert Video',
            'Video',
            courseId,
            true
        );
        update new Learning_Material__c(
            Id = videoId,
            Material_URL__c = 'https://www.youtube.com/watch?v=soH2Siy_ho4',
            Description__c = 'Watch this intro video carefully.'
        );
        Id lessonId = LearningAdminController.createMaterial(
            'Cert Lesson',
            'Lesson',
            courseId,
            true
        );
        update new Learning_Material__c(
            Id = lessonId,
            Description__c = 'Read this lesson body before the quiz.'
        );
        Id quizId = LearningAdminController.createMaterial(
            'Cert Quiz',
            'Quiz',
            courseId,
            true
        );
        update new Learning_Material__c(
            Id = quizId,
            Passing_Score__c = 50,
            Quiz_Questions__c = JSON.serialize(
                new Map<String, Object>{
                    'version' => '1.1',
                    'totalQuestions' => 1,
                    'totalPoints' => 1,
                    'questions' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 'q1',
                            'question' => '2+2?',
                            'type' => 'single-choice',
                            'options' => new List<String>{ '3', '4', '5' },
                            'correctAnswer' => 1,
                            'points' => 1,
                            'explanation' => 'Four'
                        }
                    }
                }
            )
        );

        LearningAdminController.AssignResult assignResult = LearningAdminController.assignToUser(
            UserInfo.getUserId(),
            courseId
        );

        List<MyLearningController.CourseCard> courses = MyLearningController.getMyCourses();
        System.assertEquals(1, courses.size());

        MyLearningController.CoursePlayerDto player = MyLearningController.openCourse(
            assignResult.courseInstanceId,
            null
        );
        System.assertEquals(3, player.curriculum.size());
        System.assertNotEquals(null, player.selectedInstanceId);

        Id videoInstanceId;
        Id quizInstanceId;
        Id lessonInstanceId;
        String lessonDescription;
        for (MyLearningController.CurriculumItem item : player.curriculum) {
            if (item.materialType == 'Video') {
                videoInstanceId = item.instanceId;
                System.assertEquals('Watch this intro video carefully.', item.description);
            }
            if (item.materialType == 'Quiz') {
                quizInstanceId = item.instanceId;
            }
            if (item.materialType == 'Lesson') {
                lessonInstanceId = item.instanceId;
                lessonDescription = item.description;
            }
        }
        System.assertNotEquals(null, videoInstanceId);
        System.assertNotEquals(null, quizInstanceId);
        System.assertNotEquals(null, lessonInstanceId);
        System.assertEquals('Read this lesson body before the quiz.', lessonDescription);

        System.assert(player.curriculum.size() >= 2, 'Need at least two curriculum items for sequence checks.');
        Id secondInstanceId = player.curriculum[1].instanceId;
        System.assertNotEquals(null, secondInstanceId);

        Boolean secondBlocked = false;
        try {
            MyLearningController.startLesson(secondInstanceId);
            System.assert(false, 'Expected startLesson on the second item to throw.');
        } catch (Exception ex) {
            secondBlocked = true;
        }
        System.assert(
            secondBlocked,
            'Expected startLesson on the second item to fail while the first is incomplete.'
        );

        MyLearningController.EngagementResult engagement;
        for (MyLearningController.CurriculumItem item : player.curriculum) {
            if (item.materialType == 'Quiz') {
                continue;
            }
            // Complete non-quiz items in curriculum order so sequence checks pass.
            MyLearningController.startLesson(item.instanceId);
            if (item.materialType == 'Video') {
                engagement = MyLearningController.recordItemEngagement(item.instanceId, 50, 30);
                System.assertEquals(50, engagement.watchPercent);
                System.assertEquals(false, engagement.completed);
                System.assertEquals(false, engagement.unlockedNext);
                System.assert(engagement.timeTakenMinutes > 0);

                engagement = MyLearningController.recordItemEngagement(item.instanceId, 85, 20);
                System.assertEquals(true, engagement.unlockedNext);
                System.assertEquals(true, engagement.completed);
                System.assertNotEquals(null, engagement.player);
                System.assert(engagement.player.progress >= 33);
            } else {
                MyLearningController.markLessonComplete(item.instanceId);
            }
        }

        MyLearningController.startLesson(quizInstanceId);

        MyLearningController.QuizTakeDto quiz = MyLearningController.getQuizForTake(quizInstanceId);
        System.assertEquals(1, quiz.questions.size());
        System.assertEquals(true, quiz.canAttempt);

        MyLearningController.QuizSubmitResult submit = MyLearningController.submitQuiz(
            quizInstanceId,
            JSON.serialize(new Map<String, Object>{ 'q1' => 1 }),
            5
        );
        System.assertEquals(true, submit.passed);
        System.assertEquals(true, submit.courseCompleted);
        System.assertEquals(true, submit.canShowCertificate);

        MyLearningController.CertificateDto cert = MyLearningController.getCertificate(
            assignResult.courseInstanceId
        );
        System.assert(cert.renderedHtml.contains('Cert Course'));
        System.assert(cert.renderedHtml.contains(UserInfo.getName()));
    }

    @IsTest
    static void availabilityWindow_hidesAndBlocksCourse() {
        Id courseId = LearningAdminController.createMaterial(
            'Future Window Course',
            'Course',
            null,
            true
        );
        LearningAdminController.updateMaterial(
            courseId,
            'Future Window Course',
            null,
            true,
            null,
            'Course',
            null,
            Date.today().addDays(7),
            Date.today().addDays(30)
        );
        LearningAdminController.AssignResult assignResult = LearningAdminController.assignToUser(
            UserInfo.getUserId(),
            courseId
        );

        List<MyLearningController.CourseCard> courses = MyLearningController.getMyCourses();
        for (MyLearningController.CourseCard card : courses) {
            System.assertNotEquals(
                assignResult.courseInstanceId,
                card.instanceId,
                'Future-window course should be hidden from My Learning.'
            );
        }

        Boolean blocked = false;
        try {
            MyLearningController.openCourse(assignResult.courseInstanceId, null);
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        System.assert(blocked, 'Expected openCourse to reject out-of-window course.');

        Id alwaysCourseId = LearningAdminController.createMaterial(
            'Always Available Course',
            'Course',
            null,
            true
        );
        LearningAdminController.assignToUser(UserInfo.getUserId(), alwaysCourseId);
        Boolean foundAlways = false;
        for (MyLearningController.CourseCard card : MyLearningController.getMyCourses()) {
            if (card.materialId == alwaysCourseId) {
                foundAlways = true;
            }
        }
        System.assert(foundAlways, 'Null dates should remain visible.');

        Id expiredCourseId = LearningAdminController.createMaterial(
            'Expired Incomplete Course',
            'Course',
            null,
            true
        );
        LearningAdminController.updateMaterial(
            expiredCourseId,
            'Expired Incomplete Course',
            null,
            true,
            null,
            'Course',
            null,
            Date.today().addDays(-30),
            Date.today().addDays(-1)
        );
        LearningAdminController.AssignResult expiredAssign = LearningAdminController.assignToUser(
            UserInfo.getUserId(),
            expiredCourseId
        );

        MyLearningController.CourseCard missedCard;
        for (MyLearningController.CourseCard card : MyLearningController.getMyCourses()) {
            if (card.instanceId == expiredAssign.courseInstanceId) {
                missedCard = card;
            }
        }
        System.assertNotEquals(null, missedCard, 'Expired incomplete course should appear.');
        System.assertEquals('Missed', missedCard.status);
        System.assertEquals(false, missedCard.canAccess);

        Boolean missedBlocked = false;
        try {
            MyLearningController.openCourse(expiredAssign.courseInstanceId, null);
        } catch (AuraHandledException ex) {
            missedBlocked = true;
        }
        System.assert(missedBlocked, 'Expected openCourse to reject missed course.');

        MyLearningController.LearningDashboardDto stats = MyLearningController.getMyLearningStats();
        System.assert(stats.missedCount >= 1, 'Dashboard should count missed courses.');
    }

    @IsTest
    static void dashboardStatsAndCourseSort() {
        Date endFar = Date.today().addDays(30);
        Date endMid = Date.today().addDays(14);
        Date endSoon = Date.today().addDays(5);

        Id inProgressCourseId = LearningAdminController.createMaterial(
            'In Progress Course',
            'Course',
            null,
            true
        );
        LearningAdminController.updateMaterial(
            inProgressCourseId,
            'In Progress Course',
            null,
            true,
            null,
            'Course',
            null,
            Date.today().addDays(-1),
            endFar
        );
        Id inProgressVideoId = LearningAdminController.createMaterial(
            'IP Video',
            'Video',
            inProgressCourseId,
            true
        );
        update new Learning_Material__c(
            Id = inProgressVideoId,
            Material_URL__c = 'https://www.youtube.com/watch?v=abc'
        );

        Id notStartedMidId = LearningAdminController.createMaterial(
            'Not Started Mid',
            'Course',
            null,
            true
        );
        LearningAdminController.updateMaterial(
            notStartedMidId,
            'Not Started Mid',
            null,
            true,
            null,
            'Course',
            null,
            Date.today().addDays(-1),
            endMid
        );

        Id notStartedSoonId = LearningAdminController.createMaterial(
            'Not Started Soon',
            'Course',
            null,
            true
        );
        LearningAdminController.updateMaterial(
            notStartedSoonId,
            'Not Started Soon',
            null,
            true,
            null,
            'Course',
            null,
            Date.today().addDays(-1),
            endSoon
        );

        LearningAdminController.AssignResult ipAssign = LearningAdminController.assignToUser(
            UserInfo.getUserId(),
            inProgressCourseId
        );
        LearningAdminController.assignToUser(UserInfo.getUserId(), notStartedMidId);
        LearningAdminController.assignToUser(UserInfo.getUserId(), notStartedSoonId);

        MyLearningController.CoursePlayerDto player = MyLearningController.openCourse(
            ipAssign.courseInstanceId,
            null
        );
        Id videoInstanceId;
        for (MyLearningController.CurriculumItem item : player.curriculum) {
            if (item.materialType == 'Video') {
                videoInstanceId = item.instanceId;
            }
        }
        MyLearningController.startLesson(videoInstanceId);
        MyLearningController.recordItemEngagement(videoInstanceId, 10, 3600);

        List<MyLearningController.CourseCard> courses = MyLearningController.getMyCourses();
        System.assertEquals(3, courses.size(), 'Expected three visible courses.');
        System.assertEquals('In Progress Course', courses[0].title);
        System.assertEquals('In Progress', courses[0].status);
        System.assertEquals(endFar, courses[0].effectiveEndDate);
        System.assertEquals('Not Started Mid', courses[1].title);
        System.assertEquals(endMid, courses[1].effectiveEndDate);
        System.assertEquals('Not Started Soon', courses[2].title);
        System.assertEquals(endSoon, courses[2].effectiveEndDate);

        MyLearningController.LearningDashboardDto stats = MyLearningController.getMyLearningStats();
        System.assertEquals(1, stats.inProgressCount);
        System.assertEquals(2, stats.notStartedCount);
        System.assertEquals(0, stats.completedCount);
        System.assertEquals(0, stats.missedCount);
        System.assertEquals(1, stats.dueSoonCount);
        System.assertEquals(0, stats.completionRate);
        System.assert(stats.totalStudyMinutes > 0, 'Study minutes should accumulate from engagement.');
        System.assert(stats.totalStudyHours > 0, 'Study hours should be derived from minutes.');
    }

    @IsTest
    static void getTeamLearning_returnsSubordinateCourseAndHidesOwn() {
        User rep = createLearningRep();
        Territory2 district;
        Territory2 position;
        Id courseId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            district = createLearningTerritory('Learning District', null);
            position = district == null
                ? null
                : createLearningTerritory('Learning Position', district.Id);
            if (district != null && position != null) {
                insert new UserTerritory2Association(
                    UserId = UserInfo.getUserId(),
                    Territory2Id = district.Id,
                    RoleInTerritory2 = 'District Manager'
                );
                insert new UserTerritory2Association(
                    UserId = rep.Id,
                    Territory2Id = position.Id,
                    RoleInTerritory2 = 'Medical Rep'
                );
                courseId = LearningAdminController.createMaterial(
                    'Team Visible Course',
                    'Course',
                    null,
                    true
                );
                LearningAdminController.assignToUser(UserInfo.getUserId(), courseId);
                LearningAdminController.assignToUser(rep.Id, courseId);
            }
        }
        if (district == null || position == null) {
            MyLearningController.TeamLearningPage emptyPage = MyLearningController.getTeamLearning();
            System.assertNotEquals(null, emptyPage);
            System.assertNotEquals(null, emptyPage.rows);
            return;
        }

        Test.startTest();
        MyLearningController.TeamLearningPage page = MyLearningController.getTeamLearning();
        Test.stopTest();

        System.assertEquals(true, page.isManager);
        Boolean foundRep = false;
        for (MyLearningController.TeamCourseRow row : page.rows) {
            System.assertNotEquals(UserInfo.getUserId(), row.learnerId);
            if (row.learnerId == rep.Id && row.title == 'Team Visible Course') {
                foundRep = true;
                System.assertEquals('Not Started', row.status);
                System.assert(row.territoryName != null && row.territoryName.contains('Learning Position'));
            }
        }
        System.assert(foundRep, 'The subordinate course should appear on the team list.');
    }

    private static Territory2 createLearningTerritory(String name, Id parentId) {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        if (types.isEmpty() || models.isEmpty()) {
            return null;
        }
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Territory2 territory = new Territory2(
            Name = name,
            DeveloperName = 'LearnTeam_' + suffix,
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = 'TERR_LEARN_TEAM_' + suffix,
            ParentTerritory2Id = parentId
        );
        insert territory;
        return territory;
    }

    private static User createLearningRep() {
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniq = 'learnrep' + String.valueOf(Datetime.now().getTime());
        User rep = new User(
            Alias = 'lrnrep',
            Email = uniq + '@example.com.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Learning Rep',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = uniq + '@example.com.invalid'
        );
        insert rep;
        return rep;
    }
}