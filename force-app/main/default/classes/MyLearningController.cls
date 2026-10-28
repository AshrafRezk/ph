public with sharing class MyLearningController {
    // BRD §5.6: a video counts as watched (and unlocks the next one) at this percentage.
    private static final Integer VIDEO_UNLOCK_PERCENT = 85;

    public class CourseCard {
        @AuraEnabled public Id instanceId;
        @AuraEnabled public Id materialId;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public Boolean issueCertificate;
        @AuraEnabled public Boolean canShowCertificate;
        @AuraEnabled public Date effectiveEndDate;
        @AuraEnabled public Boolean canAccess;
    }

    public class LearningDashboardDto {
        @AuraEnabled public Integer notStartedCount;
        @AuraEnabled public Integer inProgressCount;
        @AuraEnabled public Integer completedCount;
        @AuraEnabled public Integer missedCount;
        @AuraEnabled public Decimal totalStudyMinutes;
        @AuraEnabled public Decimal totalStudyHours;
        @AuraEnabled public Decimal completionRate;
        @AuraEnabled public Integer certificatesEarned;
        @AuraEnabled public Decimal averageScore;
        @AuraEnabled public Integer dueSoonCount;
    }

    public class CurriculumItem {
        @AuraEnabled public Id materialId;
        @AuraEnabled public Id instanceId;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String materialType;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String materialUrl;
        @AuraEnabled public Decimal duration;
        @AuraEnabled public Boolean completed;
        @AuraEnabled public Integer sortOrder;
        @AuraEnabled public Decimal watchPercent;
        @AuraEnabled public Decimal timeTakenMinutes;
    }

    public class EngagementResult {
        @AuraEnabled public Decimal watchPercent;
        @AuraEnabled public Decimal timeTakenMinutes;
        @AuraEnabled public Boolean completed;
        @AuraEnabled public Boolean unlockedNext;
        @AuraEnabled public CoursePlayerDto player;
    }

    public class CoursePlayerDto {
        @AuraEnabled public Id courseInstanceId;
        @AuraEnabled public Id courseMaterialId;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public Boolean issueCertificate;
        @AuraEnabled public Boolean canShowCertificate;
        @AuraEnabled public List<CurriculumItem> curriculum;
        @AuraEnabled public Id selectedInstanceId;
    }

    public class QuizQuestionDto {
        @AuraEnabled public String id;
        @AuraEnabled public String question;
        @AuraEnabled public String type;
        @AuraEnabled public List<String> options;
        @AuraEnabled public Decimal points;
        @AuraEnabled public Integer scaleMin;
        @AuraEnabled public Integer scaleMax;
        @AuraEnabled public String scaleMinLabel;
        @AuraEnabled public String scaleMaxLabel;
    }

    public class QuizTakeDto {
        @AuraEnabled public Id instanceId;
        @AuraEnabled public Id materialId;
        @AuraEnabled public String title;
        @AuraEnabled public Decimal passingScore;
        @AuraEnabled public Decimal timeLimitMinutes;
        @AuraEnabled public Decimal maxAttempts;
        @AuraEnabled public Decimal attemptNumber;
        @AuraEnabled public Boolean showResults;
        @AuraEnabled public Boolean canAttempt;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal lastScore;
        @AuraEnabled public List<QuizQuestionDto> questions;
    }

    public class QuizSubmitResult {
        @AuraEnabled public Decimal score;
        @AuraEnabled public Decimal earnedPoints;
        @AuraEnabled public Decimal totalPoints;
        @AuraEnabled public Boolean passed;
        @AuraEnabled public Boolean showResults;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal courseProgress;
        @AuraEnabled public Boolean courseCompleted;
        @AuraEnabled public Boolean canShowCertificate;
        @AuraEnabled public Map<String, Object> questionResults;
    }

    public class CertificateDto {
        @AuraEnabled public String learnerName;
        @AuraEnabled public String courseTitle;
        @AuraEnabled public String completedOn;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String logoUrl;
        @AuraEnabled public String templateHtml;
        @AuraEnabled public String renderedHtml;
    }

    public class TeamCourseRow {
        @AuraEnabled public Id instanceId;
        @AuraEnabled public Id learnerId;
        @AuraEnabled public String learnerName;
        @AuraEnabled public String territoryName;
        @AuraEnabled public String title;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public Date effectiveEndDate;
    }

    public class TeamLearningPage {
        @AuraEnabled public Boolean isManager;
        @AuraEnabled public List<TeamCourseRow> rows;
    }

    private static final Set<String> MANAGER_ROLES = new Set<String>{
        'District Manager',
        'Region Manager',
        'Line Manager',
        'NSM',
        'National Sales Manager',
        'Area Manager',
        'Business Unit Manager',
        'Brand Manager',
        'Trainer'
    };

    @AuraEnabled(cacheable=true)
    public static List<CourseCard> getMyCourses() {
        Id userId = UserInfo.getUserId();
        Date today = Date.today();
        List<CourseCard> cards = new List<CourseCard>();
        for (Learning_Material_Instance__c inst : [
            SELECT
                Id,
                Status__c,
                Progress__c,
                Score__c,
                Completed_On__c,
                Material__c,
                Material__r.Title__c,
                Material__r.Description__c,
                Material__r.Material_Type__c,
                Material__r.Issue_Certificate__c,
                Material__r.Effective_Start_Date__c,
                Material__r.Effective_End_Date__c
            FROM Learning_Material_Instance__c
            WHERE
                Learner__c = :userId
                AND Material__r.Material_Type__c = 'Course'
                AND (
                    Material__r.Effective_Start_Date__c = NULL
                    OR Material__r.Effective_Start_Date__c <= :today
                )
        ]) {
            CourseCard card = new CourseCard();
            card.instanceId = inst.Id;
            card.materialId = inst.Material__c;
            card.title = inst.Material__r.Title__c;
            card.description = inst.Material__r.Description__c;
            card.progress = inst.Progress__c == null ? 0 : inst.Progress__c;
            card.issueCertificate = inst.Material__r.Issue_Certificate__c == true;
            card.effectiveEndDate = inst.Material__r.Effective_End_Date__c;
            Boolean missed = isMissedCourse(
                inst.Material__r.Effective_End_Date__c,
                inst.Status__c
            );
            card.status = missed ? 'Missed' : normalizeCourseStatus(inst.Status__c);
            card.canAccess = !missed;
            card.canShowCertificate =
                card.issueCertificate && card.status == 'Completed';
            cards.add(card);
        }
        cards.sort(new CourseCardComparator());
        return cards;
    }

    /**
     * Courses assigned to people on territories under the viewer's manager assignments.
     * Reps get an empty page. Managers also keep their own courses via getMyCourses.
     */
    @AuraEnabled(cacheable=true)
    public static TeamLearningPage getTeamLearning() {
        TeamLearningPage page = new TeamLearningPage();
        page.isManager = false;
        page.rows = new List<TeamCourseRow>();

        Id userId = UserInfo.getUserId();
        Set<Id> roots = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId = :userId AND Territory2Id != NULL AND RoleInTerritory2 != NULL
            WITH SYSTEM_MODE
        ]) {
            if (MANAGER_ROLES.contains(assignment.RoleInTerritory2)) {
                roots.add(assignment.Territory2Id);
            }
        }
        if (roots.isEmpty()) {
            return page;
        }
        page.isManager = true;

        Set<Id> tree = TerritoryHierarchyService.expandTerritoryHierarchy(roots);
        Map<Id, List<String>> territoryNamesByUser = new Map<Id, List<String>>();
        Set<Id> subordinateIds = new Set<Id>();
        for (UserTerritory2Association member : [
            SELECT UserId, Territory2.Name
            FROM UserTerritory2Association
            WHERE Territory2Id IN :tree AND UserId != :userId AND User.IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            if (member.UserId == null) {
                continue;
            }
            subordinateIds.add(member.UserId);
            if (!territoryNamesByUser.containsKey(member.UserId)) {
                territoryNamesByUser.put(member.UserId, new List<String>());
            }
            String territoryName = member.Territory2 == null ? null : member.Territory2.Name;
            List<String> names = territoryNamesByUser.get(member.UserId);
            if (String.isNotBlank(territoryName) && !names.contains(territoryName)) {
                names.add(territoryName);
            }
        }
        if (subordinateIds.isEmpty()) {
            return page;
        }

        Date today = Date.today();
        for (Learning_Material_Instance__c inst : [
            SELECT
                Id,
                Status__c,
                Progress__c,
                Learner__c,
                Learner__r.Name,
                Material__r.Title__c,
                Material__r.Effective_End_Date__c
            FROM Learning_Material_Instance__c
            WHERE
                Learner__c IN :subordinateIds
                AND Material__r.Material_Type__c = 'Course'
                AND (
                    Material__r.Effective_Start_Date__c = NULL
                    OR Material__r.Effective_Start_Date__c <= :today
                )
            ORDER BY Learner__r.Name, Material__r.Title__c
        ]) {
            TeamCourseRow row = new TeamCourseRow();
            row.instanceId = inst.Id;
            row.learnerId = inst.Learner__c;
            row.learnerName = inst.Learner__r == null ? null : inst.Learner__r.Name;
            List<String> names = territoryNamesByUser.get(inst.Learner__c);
            row.territoryName = names == null || names.isEmpty() ? null : String.join(names, ', ');
            row.title = inst.Material__r.Title__c;
            row.progress = inst.Progress__c == null ? 0 : inst.Progress__c;
            row.effectiveEndDate = inst.Material__r.Effective_End_Date__c;
            Boolean missed = isMissedCourse(
                inst.Material__r.Effective_End_Date__c,
                inst.Status__c
            );
            row.status = missed ? 'Missed' : normalizeCourseStatus(inst.Status__c);
            page.rows.add(row);
        }
        return page;
    }

    @AuraEnabled(cacheable=true)
    public static LearningDashboardDto getMyLearningStats() {
        Id userId = UserInfo.getUserId();
        Date today = Date.today();
        Date dueSoonCutoff = today.addDays(7);

        LearningDashboardDto stats = new LearningDashboardDto();
        stats.notStartedCount = 0;
        stats.inProgressCount = 0;
        stats.completedCount = 0;
        stats.missedCount = 0;
        stats.certificatesEarned = 0;
        stats.dueSoonCount = 0;
        stats.totalStudyMinutes = 0;
        stats.averageScore = null;

        Decimal scoreSum = 0;
        Integer scoreCount = 0;

        for (Learning_Material_Instance__c inst : [
            SELECT
                Status__c,
                Score__c,
                Material__r.Issue_Certificate__c,
                Material__r.Effective_End_Date__c
            FROM Learning_Material_Instance__c
            WHERE
                Learner__c = :userId
                AND Material__r.Material_Type__c = 'Course'
                AND (
                    Material__r.Effective_Start_Date__c = NULL
                    OR Material__r.Effective_Start_Date__c <= :today
                )
        ]) {
            Boolean missed = isMissedCourse(
                inst.Material__r.Effective_End_Date__c,
                inst.Status__c
            );
            String status = missed
                ? 'Missed'
                : normalizeCourseStatus(inst.Status__c);
            if (status == 'In Progress') {
                stats.inProgressCount++;
            } else if (status == 'Completed') {
                stats.completedCount++;
                if (inst.Score__c != null) {
                    scoreSum += inst.Score__c;
                    scoreCount++;
                }
            } else if (status == 'Missed') {
                stats.missedCount++;
            } else {
                stats.notStartedCount++;
            }

            if (
                inst.Material__r.Issue_Certificate__c == true
                && status == 'Completed'
            ) {
                stats.certificatesEarned++;
            }

            if (
                status != 'Completed'
                && status != 'Missed'
                && inst.Material__r.Effective_End_Date__c != null
                && inst.Material__r.Effective_End_Date__c >= today
                && inst.Material__r.Effective_End_Date__c <= dueSoonCutoff
            ) {
                stats.dueSoonCount++;
            }
        }

        Integer totalAssigned =
            stats.notStartedCount +
            stats.inProgressCount +
            stats.completedCount +
            stats.missedCount;
        stats.completionRate = totalAssigned == 0
            ? 0
            : ((Decimal) stats.completedCount / (Decimal) totalAssigned * 100)
                  .setScale(0);
        stats.averageScore = scoreCount == 0
            ? null
            : (scoreSum / scoreCount).setScale(0);

        for (AggregateResult ar : [
            SELECT SUM(Time_Taken_Minutes__c) totalMinutes
            FROM Learning_Material_Instance__c
            WHERE
                Learner__c = :userId
                AND Material__r.Material_Type__c != 'Course'
                AND Time_Taken_Minutes__c != NULL
        ]) {
            stats.totalStudyMinutes = (Decimal) ar.get('totalMinutes');
        }
        stats.totalStudyHours = stats.totalStudyMinutes == null
            ? 0
            : (stats.totalStudyMinutes / 60).setScale(1);
        if (stats.totalStudyMinutes == null) {
            stats.totalStudyMinutes = 0;
        }

        return stats;
    }

    @AuraEnabled
    public static CoursePlayerDto openCourse(Id courseInstanceId, Id selectedMaterialId) {
        Id userId = UserInfo.getUserId();
        Learning_Material_Instance__c courseInst = [
            SELECT
                Id,
                Status__c,
                Progress__c,
                Learner__c,
                Material__c,
                Material__r.Title__c,
                Material__r.Description__c,
                Material__r.Issue_Certificate__c,
                Material__r.Effective_Start_Date__c,
                Material__r.Effective_End_Date__c,
                Started_On__c
            FROM Learning_Material_Instance__c
            WHERE Id = :courseInstanceId AND Learner__c = :userId
            LIMIT 1
        ];
        assertCourseAccessible(
            courseInst.Material__r.Effective_Start_Date__c,
            courseInst.Material__r.Effective_End_Date__c,
            courseInst.Status__c
        );

        ensureChildInstances(userId, courseInst.Material__c);

        if (courseInst.Started_On__c == null) {
            courseInst.Started_On__c = System.now();
            if (courseInst.Status__c == null || courseInst.Status__c == 'Not Started') {
                courseInst.Status__c = 'In Progress';
            }
            update courseInst;
        }

        List<Learning_Material__c> children = [
            SELECT
                Id,
                Title__c,
                Description__c,
                Material_Type__c,
                Material_URL__c,
                Content_Document_Id__c,
                Duration__c,
                CreatedDate
            FROM Learning_Material__c
            WHERE Parent_Material__c = :courseInst.Material__c AND Active__c = true
            ORDER BY CreatedDate ASC, Id ASC
        ];

        Map<Id, Learning_Material_Instance__c> byMaterial = loadInstancesByMaterial(
            userId,
            collectIds(children, courseInst.Material__c)
        );

        CoursePlayerDto dto = new CoursePlayerDto();
        dto.courseInstanceId = courseInst.Id;
        dto.courseMaterialId = courseInst.Material__c;
        dto.title = courseInst.Material__r.Title__c;
        dto.description = courseInst.Material__r.Description__c;
        dto.status = courseInst.Status__c;
        dto.progress = courseInst.Progress__c == null ? 0 : courseInst.Progress__c;
        dto.issueCertificate = courseInst.Material__r.Issue_Certificate__c == true;
        dto.canShowCertificate = dto.issueCertificate && courseInst.Status__c == 'Completed';
        dto.curriculum = new List<CurriculumItem>();

        Integer order = 0;
        for (Learning_Material__c child : children) {
            Learning_Material_Instance__c childInst = byMaterial.get(child.Id);
            CurriculumItem item = new CurriculumItem();
            item.materialId = child.Id;
            item.instanceId = childInst != null ? childInst.Id : null;
            item.title = child.Title__c;
            item.description = child.Description__c;
            item.materialType = child.Material_Type__c;
            item.status = childInst != null ? childInst.Status__c : 'Not Started';
            item.progress = childInst != null && childInst.Progress__c != null
                ? childInst.Progress__c
                : 0;
            item.score = childInst != null ? childInst.Score__c : null;
            item.materialUrl = child.Material_URL__c;
            item.duration = child.Duration__c;
            item.completed = item.status == 'Completed';
            item.watchPercent = childInst != null && childInst.Watch_Percent__c != null
                ? childInst.Watch_Percent__c
                : 0;
            item.timeTakenMinutes = childInst != null ? childInst.Time_Taken_Minutes__c : null;
            item.sortOrder = order++;
            dto.curriculum.add(item);
            if (
                selectedMaterialId != null &&
                child.Id == selectedMaterialId &&
                item.instanceId != null
            ) {
                dto.selectedInstanceId = item.instanceId;
            }
        }

        if (dto.selectedInstanceId == null && !dto.curriculum.isEmpty()) {
            for (CurriculumItem item : dto.curriculum) {
                if (!item.completed && item.instanceId != null) {
                    dto.selectedInstanceId = item.instanceId;
                    break;
                }
            }
            if (dto.selectedInstanceId == null) {
                dto.selectedInstanceId = dto.curriculum[0].instanceId;
            }
        }

        dto.progress = rollupCourseProgress(courseInst.Id);
        courseInst = [
            SELECT Status__c, Progress__c, Material__r.Issue_Certificate__c
            FROM Learning_Material_Instance__c
            WHERE Id = :courseInst.Id
        ];
        dto.status = courseInst.Status__c;
        dto.progress = courseInst.Progress__c == null ? 0 : courseInst.Progress__c;
        dto.canShowCertificate =
            courseInst.Material__r.Issue_Certificate__c == true &&
            courseInst.Status__c == 'Completed';
        return dto;
    }

    @AuraEnabled
    public static CurriculumItem startLesson(Id instanceId) {
        Learning_Material_Instance__c inst = requireOwnInstance(instanceId);
        assertPriorItemsComplete(inst);
        if (inst.Started_On__c == null) {
            inst.Started_On__c = System.now();
        }
        if (inst.Status__c == null || inst.Status__c == 'Not Started') {
            inst.Status__c = 'In Progress';
        }
        update inst;
        rollupCourseProgress(findCourseInstanceId(inst));
        return toCurriculumItem(inst);
    }

    @TestVisible
    static void assertPriorItemsComplete(Learning_Material_Instance__c inst) {
        Id parentId = inst.Material__r.Parent_Material__c;
        if (parentId == null) {
            return;
        }
        List<Learning_Material__c> siblings = [
            SELECT Id, Material_Type__c
            FROM Learning_Material__c
            WHERE Parent_Material__c = :parentId AND Active__c = true
            ORDER BY CreatedDate ASC, Id ASC
        ];
        if (siblings.isEmpty()) {
            return;
        }
        Set<Id> siblingIds = new Set<Id>();
        for (Learning_Material__c sibling : siblings) {
            siblingIds.add(sibling.Id);
        }
        Map<Id, Learning_Material_Instance__c> byMaterial = new Map<Id, Learning_Material_Instance__c>();
        for (Learning_Material_Instance__c row : [
            SELECT Id, Material__c, Status__c, Watch_Percent__c, Material__r.Material_Type__c
            FROM Learning_Material_Instance__c
            WHERE Learner__c = :inst.Learner__c AND Material__c IN :siblingIds
        ]) {
            byMaterial.put(row.Material__c, row);
        }
        for (Learning_Material__c sibling : siblings) {
            if (sibling.Id == inst.Material__c) {
                break;
            }
            Learning_Material_Instance__c prior = byMaterial.get(sibling.Id);
            if (!isSequenceItemDone(prior)) {
                throw new AuraHandledException('Finish the previous item first.');
            }
        }
    }

    @TestVisible
    static Boolean isSequenceItemDone(Learning_Material_Instance__c prior) {
        if (prior == null) {
            return false;
        }
        if (prior.Status__c == 'Completed') {
            return true;
        }
        if (
            prior.Material__r.Material_Type__c == 'Video' &&
            prior.Watch_Percent__c != null &&
            prior.Watch_Percent__c >= VIDEO_UNLOCK_PERCENT
        ) {
            return true;
        }
        return false;
    }

    @AuraEnabled
    public static CoursePlayerDto markLessonComplete(Id instanceId) {
        Learning_Material_Instance__c inst = requireOwnInstance(instanceId);
        if (inst.Material__r.Material_Type__c == 'Quiz') {
            throw new AuraHandledException('Complete quizzes by submitting the exam.');
        }
        if (inst.Started_On__c == null) {
            inst.Started_On__c = System.now();
        }
        inst.Status__c = 'Completed';
        inst.Progress__c = 100;
        if (inst.Watch_Percent__c == null || inst.Watch_Percent__c < 100) {
            inst.Watch_Percent__c = 100;
        }
        inst.Completed_On__c = System.now();
        update inst;

        Id courseInstanceId = findCourseInstanceId(inst);
        rollupCourseProgress(courseInstanceId);
        return openCourse(courseInstanceId, inst.Material__c);
    }

    @AuraEnabled
    public static EngagementResult recordItemEngagement(
        Id instanceId,
        Decimal watchPercent,
        Decimal secondsSpent
    ) {
        Learning_Material_Instance__c inst = requireOwnInstance(instanceId);
        EngagementResult result = new EngagementResult();

        if (inst.Started_On__c == null) {
            inst.Started_On__c = System.now();
        }
        if (inst.Status__c == null || inst.Status__c == 'Not Started') {
            inst.Status__c = 'In Progress';
        }

        Decimal incomingWatch = watchPercent == null ? 0 : watchPercent;
        if (incomingWatch < 0) {
            incomingWatch = 0;
        }
        if (incomingWatch > 100) {
            incomingWatch = 100;
        }
        Decimal currentWatch = inst.Watch_Percent__c == null ? 0 : inst.Watch_Percent__c;
        if (incomingWatch > currentWatch) {
            inst.Watch_Percent__c = incomingWatch;
        }

        Decimal addSeconds = secondsSpent == null ? 0 : secondsSpent;
        if (addSeconds < 0) {
            addSeconds = 0;
        }
        if (addSeconds > 3600) {
            addSeconds = 3600;
        }
        if (addSeconds > 0) {
            Decimal existingMinutes = inst.Time_Taken_Minutes__c == null
                ? 0
                : inst.Time_Taken_Minutes__c;
            Decimal addMinutes = (addSeconds / 60).setScale(1);
            Decimal nextMinutes = existingMinutes + addMinutes;
            if (nextMinutes > 9999) {
                nextMinutes = 9999;
            }
            inst.Time_Taken_Minutes__c = nextMinutes;
        }

        Boolean isVideo = inst.Material__r.Material_Type__c == 'Video';
        Decimal effectiveWatch = inst.Watch_Percent__c == null ? 0 : inst.Watch_Percent__c;
        Boolean shouldComplete =
            isVideo &&
            effectiveWatch >= VIDEO_UNLOCK_PERCENT &&
            inst.Status__c != 'Completed';

        if (shouldComplete) {
            inst.Status__c = 'Completed';
            inst.Progress__c = 100;
            inst.Completed_On__c = System.now();
        } else if (isVideo && inst.Status__c != 'Completed') {
            inst.Progress__c = effectiveWatch.setScale(0);
        }

        update inst;

        Id courseInstanceId = findCourseInstanceId(inst);
        rollupCourseProgress(courseInstanceId);

        result.watchPercent = inst.Watch_Percent__c == null ? 0 : inst.Watch_Percent__c;
        result.timeTakenMinutes = inst.Time_Taken_Minutes__c;
        result.completed = inst.Status__c == 'Completed';
        result.unlockedNext = isVideo
            ? (result.completed || result.watchPercent >= VIDEO_UNLOCK_PERCENT)
            : true;

        if (shouldComplete || result.completed) {
            result.player = openCourse(courseInstanceId, inst.Material__c);
        }
        return result;
    }

    @AuraEnabled
    public static QuizTakeDto getQuizForTake(Id instanceId) {
        Learning_Material_Instance__c inst = requireOwnInstance(instanceId);
        if (inst.Material__r.Material_Type__c != 'Quiz') {
            throw new AuraHandledException('Material is not a quiz.');
        }

        QuizTakeDto dto = new QuizTakeDto();
        dto.instanceId = inst.Id;
        dto.materialId = inst.Material__c;
        dto.title = inst.Material__r.Title__c;
        dto.passingScore = inst.Material__r.Passing_Score__c;
        dto.timeLimitMinutes = inst.Material__r.Quiz_Time_Limit_Minutes__c;
        dto.maxAttempts = inst.Material__r.Max_Attempts__c;
        dto.attemptNumber = inst.Attempt_Number__c == null ? 0 : inst.Attempt_Number__c;
        dto.showResults = inst.Material__r.Show_Results__c == true;
        dto.status = inst.Status__c;
        dto.lastScore = inst.Score__c;
        dto.canAttempt =
            inst.Status__c != 'Completed' &&
            (dto.maxAttempts == null || dto.attemptNumber < dto.maxAttempts);
        dto.questions = new List<QuizQuestionDto>();

        Map<String, Object> quiz = parseQuizJson(inst.Material__r.Quiz_Questions__c);
        List<Object> questions = (List<Object>) quiz.get('questions');
        if (questions == null) {
            return dto;
        }
        for (Object qObj : questions) {
            Map<String, Object> q = (Map<String, Object>) qObj;
            QuizQuestionDto qd = new QuizQuestionDto();
            qd.id = (String) q.get('id');
            qd.question = (String) q.get('question');
            qd.type = (String) q.get('type');
            qd.points = toDecimal(q.get('points'), 1);
            Object opts = q.get('options');
            qd.options = new List<String>();
            if (opts instanceof List<Object>) {
                for (Object o : (List<Object>) opts) {
                    qd.options.add(String.valueOf(o));
                }
            }
            if (qd.type == 'scale') {
                qd.scaleMin = toInteger(q.get('scaleMin'), 1);
                qd.scaleMax = toInteger(q.get('scaleMax'), 5);
                qd.scaleMinLabel = (String) q.get('scaleMinLabel');
                qd.scaleMaxLabel = (String) q.get('scaleMaxLabel');
            }
            dto.questions.add(qd);
        }

        return dto;
    }

    @AuraEnabled
    public static QuizSubmitResult submitQuiz(Id instanceId, String answersJson, Decimal timeTakenMinutes) {
        Learning_Material_Instance__c inst = requireOwnInstance(instanceId);
        if (inst.Material__r.Material_Type__c != 'Quiz') {
            throw new AuraHandledException('Material is not a quiz.');
        }

        Decimal attemptNumber = inst.Attempt_Number__c == null ? 0 : inst.Attempt_Number__c;
        Decimal maxAttempts = inst.Material__r.Max_Attempts__c;
        if (inst.Status__c == 'Completed') {
            throw new AuraHandledException('This quiz is already completed.');
        }
        if (maxAttempts != null && attemptNumber >= maxAttempts) {
            throw new AuraHandledException('Maximum attempts reached.');
        }

        Map<String, Object> answers = String.isBlank(answersJson)
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(answersJson);
        Map<String, Object> quiz = parseQuizJson(inst.Material__r.Quiz_Questions__c);
        List<Object> questions = (List<Object>) quiz.get('questions');

        Decimal earned = 0;
        Decimal total = 0;
        Map<String, Object> questionResults = new Map<String, Object>();

        if (questions != null) {
            for (Object qObj : questions) {
                Map<String, Object> q = (Map<String, Object>) qObj;
                String qid = (String) q.get('id');
                Decimal points = toDecimal(q.get('points'), 1);
                total += points;
                Object given = answers.get(qid);
                Boolean correct = isAnswerCorrect(q, given);
                if (correct) {
                    earned += points;
                }
                questionResults.put(
                    qid,
                    new Map<String, Object>{
                        'correct' => correct,
                        'correctAnswer' => q.get('correctAnswer') != null
                            ? q.get('correctAnswer')
                            : q.get('correctAnswers'),
                        'explanation' => q.get('explanation'),
                        'points' => points,
                        'earned' => correct ? points : 0
                    }
                );
            }
        }

        Decimal scorePct = total > 0 ? ((earned / total) * 100).setScale(1) : 0;
        Decimal passing = inst.Material__r.Passing_Score__c == null
            ? 70
            : inst.Material__r.Passing_Score__c;
        Boolean passed = scorePct >= passing;

        inst.Attempt_Number__c = attemptNumber + 1;
        inst.Score__c = scorePct;
        inst.Time_Taken_Minutes__c = timeTakenMinutes;
        if (inst.Started_On__c == null) {
            inst.Started_On__c = System.now();
        }
        if (passed) {
            inst.Status__c = 'Completed';
            inst.Progress__c = 100;
            inst.Completed_On__c = System.now();
        } else {
            inst.Status__c = 'In Progress';
            inst.Progress__c = scorePct;
        }
        update inst;

        Id courseInstanceId = findCourseInstanceId(inst);
        Decimal courseProgress = rollupCourseProgress(courseInstanceId);
        Learning_Material_Instance__c courseInst = [
            SELECT Status__c, Material__r.Issue_Certificate__c
            FROM Learning_Material_Instance__c
            WHERE Id = :courseInstanceId
        ];

        QuizSubmitResult result = new QuizSubmitResult();
        result.score = scorePct;
        result.earnedPoints = earned;
        result.totalPoints = total;
        result.passed = passed;
        result.showResults = inst.Material__r.Show_Results__c == true;
        result.status = inst.Status__c;
        result.courseProgress = courseProgress;
        result.courseCompleted = courseInst.Status__c == 'Completed';
        result.canShowCertificate =
            courseInst.Material__r.Issue_Certificate__c == true &&
            courseInst.Status__c == 'Completed';
        result.questionResults = result.showResults ? questionResults : null;
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static CertificateDto getCertificate(Id courseInstanceId) {
        Id userId = UserInfo.getUserId();
        Learning_Material_Instance__c courseInst = [
            SELECT
                Id,
                Status__c,
                Score__c,
                Completed_On__c,
                Material__r.Title__c,
                Material__r.Issue_Certificate__c,
                Material__r.Certificate_Logo_URL__c,
                Material__r.Certificate_Template__c,
                Learner__r.Name
            FROM Learning_Material_Instance__c
            WHERE Id = :courseInstanceId AND Learner__c = :userId
            LIMIT 1
        ];
        if (
            courseInst.Status__c != 'Completed' ||
            courseInst.Material__r.Issue_Certificate__c != true
        ) {
            throw new AuraHandledException('Certificate is not available yet.');
        }

        CertificateDto dto = new CertificateDto();
        dto.learnerName = courseInst.Learner__r.Name;
        dto.courseTitle = courseInst.Material__r.Title__c;
        dto.completedOn = courseInst.Completed_On__c == null
            ? ''
            : courseInst.Completed_On__c.format();
        dto.score = courseInst.Score__c;
        dto.logoUrl = courseInst.Material__r.Certificate_Logo_URL__c;
        dto.templateHtml = courseInst.Material__r.Certificate_Template__c;
        dto.renderedHtml = renderCertificate(dto);
        return dto;
    }

    @TestVisible
    static String renderCertificate(CertificateDto dto) {
        String html = dto.templateHtml;
        if (String.isBlank(html)) {
            String logo = String.isBlank(dto.logoUrl)
                ? ''
                : '<img src="' +
                  escapeHtml(dto.logoUrl) +
                  '" alt="Logo" style="max-height:72px;margin-bottom:16px;" />';
            html =
                '<div style="border:8px solid #0b3d5c;padding:40px;text-align:center;font-family:Georgia,serif;color:#0b3d5c;">' +
                logo +
                '<div style="font-size:14px;letter-spacing:3px;text-transform:uppercase;">Certificate of Completion</div>' +
                '<div style="font-size:28px;margin:18px 0 8px;font-weight:700;">{{LearnerName}}</div>' +
                '<div style="font-size:16px;margin-bottom:12px;">has successfully completed</div>' +
                '<div style="font-size:22px;font-weight:600;margin-bottom:18px;">{{CourseTitle}}</div>' +
                '<div style="font-size:14px;">Completed on {{CompletedOn}}</div>' +
                '</div>';
        }
        html = html.replace('{{LearnerName}}', escapeHtml(nullToEmpty(dto.learnerName)));
        html = html.replace('{{CourseTitle}}', escapeHtml(nullToEmpty(dto.courseTitle)));
        html = html.replace('{{CompletedOn}}', escapeHtml(nullToEmpty(dto.completedOn)));
        html = html.replace(
            '{{Score}}',
            dto.score == null ? '' : String.valueOf(dto.score)
        );
        html = html.replace('{{LogoUrl}}', escapeHtml(nullToEmpty(dto.logoUrl)));
        return html;
    }

    static void ensureChildInstances(Id userId, Id courseMaterialId) {
        List<Learning_Material__c> children = [
            SELECT Id
            FROM Learning_Material__c
            WHERE Parent_Material__c = :courseMaterialId AND Active__c = true
        ];
        if (children.isEmpty()) {
            return;
        }
        Set<Id> childIds = new Set<Id>();
        for (Learning_Material__c c : children) {
            childIds.add(c.Id);
        }
        Set<Id> existing = new Set<Id>();
        for (Learning_Material_Instance__c inst : [
            SELECT Material__c
            FROM Learning_Material_Instance__c
            WHERE Learner__c = :userId AND Material__c IN :childIds
        ]) {
            existing.add(inst.Material__c);
        }
        List<Learning_Material_Instance__c> toInsert = new List<Learning_Material_Instance__c>();
        for (Id childId : childIds) {
            if (!existing.contains(childId)) {
                toInsert.add(
                    new Learning_Material_Instance__c(
                        Learner__c = userId,
                        Material__c = childId,
                        Status__c = 'Not Started',
                        Progress__c = 0,
                        Attempt_Number__c = 0
                    )
                );
            }
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    static Decimal rollupCourseProgress(Id courseInstanceId) {
        if (courseInstanceId == null) {
            return 0;
        }
        Learning_Material_Instance__c courseInst = [
            SELECT Id, Material__c, Learner__c, Status__c, Progress__c, Started_On__c, Completed_On__c, Score__c
            FROM Learning_Material_Instance__c
            WHERE Id = :courseInstanceId
            LIMIT 1
        ];
        List<Learning_Material__c> children = [
            SELECT Id
            FROM Learning_Material__c
            WHERE Parent_Material__c = :courseInst.Material__c AND Active__c = true
        ];
        if (children.isEmpty()) {
            return courseInst.Progress__c == null ? 0 : courseInst.Progress__c;
        }
        Set<Id> childIds = new Set<Id>();
        for (Learning_Material__c c : children) {
            childIds.add(c.Id);
        }
        Integer completed = 0;
        Decimal quizScoreSum = 0;
        Integer quizScoreCount = 0;
        for (Learning_Material_Instance__c childInst : [
            SELECT Status__c, Score__c, Material__r.Material_Type__c
            FROM Learning_Material_Instance__c
            WHERE Learner__c = :courseInst.Learner__c AND Material__c IN :childIds
        ]) {
            if (childInst.Status__c == 'Completed') {
                completed++;
            }
            if (
                childInst.Material__r.Material_Type__c == 'Quiz' &&
                childInst.Score__c != null
            ) {
                quizScoreSum += childInst.Score__c;
                quizScoreCount++;
            }
        }
        Decimal progress = ((Decimal) completed / (Decimal) children.size() * 100)
            .setScale(0);
        courseInst.Progress__c = progress;
        if (progress >= 100) {
            courseInst.Status__c = 'Completed';
            if (courseInst.Completed_On__c == null) {
                courseInst.Completed_On__c = System.now();
            }
        } else if (courseInst.Status__c == 'Not Started' || courseInst.Status__c == null) {
            courseInst.Status__c = 'In Progress';
        } else if (courseInst.Status__c == 'Completed' && progress < 100) {
            courseInst.Status__c = 'In Progress';
            courseInst.Completed_On__c = null;
        }
        if (quizScoreCount > 0) {
            courseInst.Score__c = (quizScoreSum / quizScoreCount).setScale(1);
        }
        if (courseInst.Started_On__c == null) {
            courseInst.Started_On__c = System.now();
        }
        update courseInst;
        return progress;
    }

    static Learning_Material_Instance__c requireOwnInstance(Id instanceId) {
        Id userId = UserInfo.getUserId();
        List<Learning_Material_Instance__c> rows = [
            SELECT
                Id,
                Status__c,
                Progress__c,
                Score__c,
                Started_On__c,
                Completed_On__c,
                Attempt_Number__c,
                Time_Taken_Minutes__c,
                Watch_Percent__c,
                Learner__c,
                Material__c,
                Material__r.Title__c,
                Material__r.Description__c,
                Material__r.Material_Type__c,
                Material__r.Material_URL__c,
                Material__r.Content_Document_Id__c,
                Material__r.Duration__c,
                Material__r.Parent_Material__c,
                Material__r.Passing_Score__c,
                Material__r.Quiz_Time_Limit_Minutes__c,
                Material__r.Max_Attempts__c,
                Material__r.Show_Results__c,
                Material__r.Randomize_Questions__c,
                Material__r.Quiz_Questions__c,
                Material__r.Issue_Certificate__c,
                Material__r.Effective_Start_Date__c,
                Material__r.Effective_End_Date__c
            FROM Learning_Material_Instance__c
            WHERE Id = :instanceId AND Learner__c = :userId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Learning assignment not found.');
        }
        Learning_Material_Instance__c inst = rows[0];
        // Gate on the course material availability window.
        if (inst.Material__r.Material_Type__c == 'Course') {
            assertCourseAccessible(
                inst.Material__r.Effective_Start_Date__c,
                inst.Material__r.Effective_End_Date__c,
                inst.Status__c
            );
        } else {
            Id courseMaterialId = inst.Material__r.Parent_Material__c;
            if (courseMaterialId != null) {
                Learning_Material__c courseMaterial = [
                    SELECT Effective_Start_Date__c, Effective_End_Date__c
                    FROM Learning_Material__c
                    WHERE Id = :courseMaterialId
                    LIMIT 1
                ];
                String courseStatus = null;
                List<Learning_Material_Instance__c> courseRows = [
                    SELECT Status__c
                    FROM Learning_Material_Instance__c
                    WHERE Learner__c = :userId AND Material__c = :courseMaterialId
                    LIMIT 1
                ];
                if (!courseRows.isEmpty()) {
                    courseStatus = courseRows[0].Status__c;
                }
                assertCourseAccessible(
                    courseMaterial.Effective_Start_Date__c,
                    courseMaterial.Effective_End_Date__c,
                    courseStatus
                );
            } else {
                assertCourseAccessible(
                    inst.Material__r.Effective_Start_Date__c,
                    inst.Material__r.Effective_End_Date__c,
                    inst.Status__c
                );
            }
        }
        return inst;
    }

    static void assertWithinAvailabilityWindow(Date startDate, Date endDate) {
        assertCourseAccessible(startDate, endDate, null);
    }

    static void assertCourseAccessible(Date startDate, Date endDate, String status) {
        Date today = Date.today();
        if (status == 'Completed') {
            return;
        }
        if (startDate != null && startDate > today) {
            throw new AuraHandledException('This course is not currently available.');
        }
        if (endDate != null && endDate < today) {
            throw new AuraHandledException(
                'This course has ended and was not completed.'
            );
        }
    }

    static Boolean isMissedCourse(Date endDate, String status) {
        return endDate != null &&
            endDate < Date.today() &&
            status != 'Completed';
    }

    static Id findCourseInstanceId(Learning_Material_Instance__c inst) {
        Id courseMaterialId = inst.Material__r.Material_Type__c == 'Course'
            ? inst.Material__c
            : inst.Material__r.Parent_Material__c;
        if (courseMaterialId == null) {
            return inst.Id;
        }
        List<Learning_Material_Instance__c> courseRows = [
            SELECT Id
            FROM Learning_Material_Instance__c
            WHERE Learner__c = :inst.Learner__c AND Material__c = :courseMaterialId
            LIMIT 1
        ];
        return courseRows.isEmpty() ? inst.Id : courseRows[0].Id;
    }

    static Map<Id, Learning_Material_Instance__c> loadInstancesByMaterial(
        Id userId,
        Set<Id> materialIds
    ) {
        Map<Id, Learning_Material_Instance__c> byMaterial = new Map<Id, Learning_Material_Instance__c>();
        for (Learning_Material_Instance__c inst : [
            SELECT
                Id,
                Material__c,
                Status__c,
                Progress__c,
                Score__c,
                Watch_Percent__c,
                Time_Taken_Minutes__c,
                Material__r.Title__c,
                Material__r.Description__c,
                Material__r.Material_Type__c,
                Material__r.Material_URL__c,
                Material__r.Duration__c
            FROM Learning_Material_Instance__c
            WHERE Learner__c = :userId AND Material__c IN :materialIds
        ]) {
            byMaterial.put(inst.Material__c, inst);
        }
        return byMaterial;
    }

    static Set<Id> collectIds(List<Learning_Material__c> children, Id courseId) {
        Set<Id> ids = new Set<Id>{ courseId };
        for (Learning_Material__c c : children) {
            ids.add(c.Id);
        }
        return ids;
    }

    static CurriculumItem toCurriculumItem(Learning_Material_Instance__c inst) {
        CurriculumItem item = new CurriculumItem();
        item.materialId = inst.Material__c;
        item.instanceId = inst.Id;
        item.title = inst.Material__r.Title__c;
        item.description = inst.Material__r.Description__c;
        item.materialType = inst.Material__r.Material_Type__c;
        item.status = inst.Status__c;
        item.progress = inst.Progress__c;
        item.score = inst.Score__c;
        item.materialUrl = inst.Material__r.Material_URL__c;
        item.duration = inst.Material__r.Duration__c;
        item.completed = inst.Status__c == 'Completed';
        item.watchPercent = inst.Watch_Percent__c == null ? 0 : inst.Watch_Percent__c;
        item.timeTakenMinutes = inst.Time_Taken_Minutes__c;
        return item;
    }

    static Map<String, Object> parseQuizJson(String raw) {
        if (String.isBlank(raw)) {
            return new Map<String, Object>{ 'questions' => new List<Object>() };
        }
        Object parsed = JSON.deserializeUntyped(raw);
        if (parsed instanceof Map<String, Object>) {
            return (Map<String, Object>) parsed;
        }
        throw new AuraHandledException('Invalid quiz JSON.');
    }

    static Boolean isAnswerCorrect(Map<String, Object> question, Object given) {
        String type = (String) question.get('type');
        if (type == 'multiple-choice') {
            Set<Integer> expected = new Set<Integer>();
            Object ca = question.get('correctAnswers');
            if (ca instanceof List<Object>) {
                for (Object o : (List<Object>) ca) {
                    expected.add(toInteger(o, -1));
                }
            }
            Set<Integer> actual = new Set<Integer>();
            if (given instanceof List<Object>) {
                for (Object o : (List<Object>) given) {
                    actual.add(toInteger(o, -2));
                }
            } else if (given != null) {
                actual.add(toInteger(given, -2));
            }
            return expected.equals(actual);
        }
        if (type == 'scale') {
            // Scale questions are reflective Â always credit full points when answered.
            return given != null;
        }
        Integer expected = toInteger(question.get('correctAnswer'), -1);
        Integer actual = toInteger(given, -2);
        return expected == actual;
    }

    static Decimal toDecimal(Object value, Decimal fallback) {
        if (value == null) {
            return fallback;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return fallback;
        }
    }

    static Integer toInteger(Object value, Integer fallback) {
        if (value == null) {
            return fallback;
        }
        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).intValue();
        }
        try {
            return Integer.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return fallback;
        }
    }

    static String nullToEmpty(String value) {
        return value == null ? '' : value;
    }

    static String normalizeCourseStatus(String status) {
        if (
            status == 'In Progress' ||
            status == 'Completed' ||
            status == 'Missed'
        ) {
            return status;
        }
        return 'Not Started';
    }

    static Integer courseStatusSortOrder(String status) {
        String normalized = normalizeCourseStatus(status);
        if (normalized == 'In Progress') {
            return 0;
        }
        if (normalized == 'Not Started') {
            return 1;
        }
        if (normalized == 'Completed') {
            return 2;
        }
        return 3; // Missed last
    }

    private class CourseCardComparator implements Comparator<CourseCard> {
        public Integer compare(CourseCard a, CourseCard b) {
            Integer statusCmp =
                courseStatusSortOrder(a.status) - courseStatusSortOrder(b.status);
            if (statusCmp != 0) {
                return statusCmp;
            }

            if (a.effectiveEndDate == null && b.effectiveEndDate == null) {
                return nullToEmpty(a.title).toLowerCase().compareTo(nullToEmpty(b.title).toLowerCase());
            }
            if (a.effectiveEndDate == null) {
                return 1;
            }
            if (b.effectiveEndDate == null) {
                return -1;
            }
            if (a.effectiveEndDate > b.effectiveEndDate) {
                return -1;
            }
            if (a.effectiveEndDate < b.effectiveEndDate) {
                return 1;
            }
            return nullToEmpty(a.title).toLowerCase().compareTo(nullToEmpty(b.title).toLowerCase());
        }
    }

    static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }
        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;');
    }
}