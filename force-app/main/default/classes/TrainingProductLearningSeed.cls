/**
 * Four product courses for the training organogram, assigned to every active user
 * on the training territories and their child territories.
 *
 * Run: TrainingProductLearningSeed.run();
 * Idempotent: courses are matched by title, existing learner progress is left as-is.
 */
public without sharing class TrainingProductLearningSeed {
    public class SeedResult {
        public Integer courses = 0;
        public Integer territories = 0;
        public Integer users = 0;
        public Integer instancesCreated = 0;
        public Integer alignments = 0;
        public List<String> messages = new List<String>();

        public String summary() {
            return 'courses=' + courses +
                ' territories=' + territories +
                ' users=' + users +
                ' instancesCreated=' + instancesCreated +
                ' alignments=' + alignments +
                (messages.isEmpty() ? '' : ' | ' + String.join(messages, ' | '));
        }
    }

    private class CourseSpec {
        String title;
        String productName;
        String lineName;
        String lesson;
    }

    public static SeedResult run() {
        SeedResult result = new SeedResult();
        List<CourseSpec> specs = courseSpecs();
        Map<String, Learning_Material__c> materialsByTitle = loadMaterials(specs);
        List<Id> courseIds = new List<Id>();
        Integer courseIndex = 0;
        for (CourseSpec spec : specs) {
            courseIds.add(ensureCourse(spec, materialsByTitle));
            courseIndex++;
        }
        result.courses = courseIds.size();

        Set<Id> territoryIds = trainingTerritoryIds();
        result.territories = territoryIds.size();
        if (territoryIds.isEmpty()) {
            result.messages.add('No training territories found.');
            return result;
        }

        Set<Id> userIds = new Set<Id>();
        for (UserTerritory2Association member : [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE Territory2Id IN :territoryIds AND User.IsActive = TRUE AND UserId != NULL
            WITH SYSTEM_MODE
        ]) {
            userIds.add(member.UserId);
        }
        result.users = userIds.size();
        result.alignments = ensureAlignments(courseIds, territoryIds);
        result.instancesCreated = assignCourses(courseIds, userIds);
        result.messages.add('Assigned ' + result.courses + ' product courses to ' + result.users + ' training users.');
        return result;
    }

    private static List<CourseSpec> courseSpecs() {
        return new List<CourseSpec>{
            spec(
                'DOZOVA Ashwagandha 600 — CHC',
                'DOZOVA Ashwagandha 600 mg 30 capsules',
                'CHC',
                'Open with the pack: DOZOVA Ashwagandha 600 mg, 30 capsules. ' +
                    'State who you are calling on, the one message for this visit, and the pack the HCP should remember. ' +
                    'Close only after the HCP can repeat the brand and the pack.'
            ),
            spec(
                'EMPACOZA 25 mg — Diabetes',
                'EMPACOZA 25 mg 30 tablets',
                'Diabetes',
                'Open with the pack: EMPACOZA 25 mg, 30 tablets. ' +
                    'Use it on diabetes calls when this is the priority brand. ' +
                    'State the pack, the call objective, and the single message you want the HCP to keep. ' +
                    'Close only after the HCP can repeat the brand and the pack.'
            ),
            spec(
                'NEXICURE 40 mg — GIT',
                'NEXICURE 40 mg 20 tablets',
                'GIT',
                'Open with the pack: NEXICURE 40 mg, 20 tablets. ' +
                    'Use it on gastroenterology calls when this is the priority brand. ' +
                    'State the pack, the call objective, and the single message you want the HCP to keep. ' +
                    'Close only after the HCP can repeat the brand and the pack.'
            ),
            spec(
                'NEXIBRONCH Syrup — Pedia',
                'NEXIBRONCH Syrup 200 ml',
                'Pedia',
                'Open with the pack: NEXIBRONCH Syrup, 200 ml. ' +
                    'Use it on paediatric calls when this is the priority brand. ' +
                    'State the pack, the call objective, and the single message you want the HCP to keep. ' +
                    'Close only after the HCP can repeat the brand and the pack.'
            )
        };
    }

    private static CourseSpec spec(String title, String productName, String lineName, String lesson) {
        CourseSpec spec = new CourseSpec();
        spec.title = title;
        spec.productName = productName;
        spec.lineName = lineName;
        spec.lesson = lesson;
        return spec;
    }

    private static Map<String, Learning_Material__c> loadMaterials(List<CourseSpec> specs) {
        Set<String> titles = new Set<String>();
        for (CourseSpec spec : specs) {
            titles.add(spec.title);
            titles.add(lessonTitle(spec));
            titles.add(quizTitle(spec));
        }
        Map<String, Learning_Material__c> byTitle = new Map<String, Learning_Material__c>();
        for (Learning_Material__c material : [
            SELECT Id, Title__c, Material_Type__c, Parent_Material__c
            FROM Learning_Material__c
            WHERE Title__c IN :titles
            WITH SYSTEM_MODE
        ]) {
            byTitle.put(material.Title__c, material);
        }
        return byTitle;
    }

    private static Id ensureCourse(CourseSpec spec, Map<String, Learning_Material__c> byTitle) {
        Learning_Material__c course = byTitle.get(spec.title);
        if (course == null) {
            course = new Learning_Material__c(
                Title__c = spec.title,
                Material_Type__c = 'Course'
            );
        }
        course.Active__c = true;
        course.Category__c = 'Sales';
        course.Issue_Certificate__c = true;
        course.Description__c =
            spec.lineName + ' detailing course for ' + spec.productName +
            '. Assigned to the training territories.';
        upsert as system course;
        byTitle.put(spec.title, course);

        Learning_Material__c lesson = byTitle.get(lessonTitle(spec));
        if (lesson == null) {
            lesson = new Learning_Material__c(
                Title__c = lessonTitle(spec),
                Material_Type__c = 'Lesson'
            );
        }
        lesson.Parent_Material__c = course.Id;
        lesson.Active__c = true;
        lesson.Duration__c = 10;
        lesson.Description__c = spec.lesson;
        upsert as system lesson;
        byTitle.put(lesson.Title__c, lesson);

        Learning_Material__c quiz = byTitle.get(quizTitle(spec));
        if (quiz == null) {
            quiz = new Learning_Material__c(
                Title__c = quizTitle(spec),
                Material_Type__c = 'Quiz'
            );
        }
        quiz.Parent_Material__c = course.Id;
        quiz.Active__c = true;
        quiz.Passing_Score__c = 70;
        quiz.Quiz_Time_Limit_Minutes__c = 10;
        quiz.Show_Results__c = true;
        quiz.Max_Attempts__c = 3;
        quiz.Description__c = 'Check that you can name the pack and the close for ' + spec.productName + '.';
        quiz.Quiz_Questions__c = quizJson(spec);
        upsert as system quiz;
        byTitle.put(quiz.Title__c, quiz);
        return course.Id;
    }

    private static String lessonTitle(CourseSpec spec) {
        return spec.title + ' — Key messages';
    }

    private static String quizTitle(CourseSpec spec) {
        return spec.title + ' — Knowledge check';
    }

    private static String quizJson(CourseSpec spec) {
        List<String> packs = new List<String>{
            'DOZOVA Ashwagandha 600 mg 30 capsules',
            'EMPACOZA 25 mg 30 tablets',
            'NEXICURE 40 mg 20 tablets',
            'NEXIBRONCH Syrup 200 ml'
        };
        Integer correct = packs.indexOf(spec.productName);
        if (correct < 0) {
            correct = 0;
        }
        Map<String, Object> payload = new Map<String, Object>{
            'version' => '1.1',
            'totalQuestions' => 2,
            'totalPoints' => 2,
            'questions' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'q1',
                    'question' => 'Which pack is this course built around?',
                    'type' => 'single-choice',
                    'options' => packs,
                    'correctAnswer' => correct,
                    'points' => 1,
                    'explanation' => spec.productName
                },
                new Map<String, Object>{
                    'id' => 'q2',
                    'question' => 'When is this module complete?',
                    'type' => 'single-choice',
                    'options' => new List<String>{
                        'After you can state the pack and the call message',
                        'Before you open the detail aid',
                        'Only after a manager joins the call'
                    },
                    'correctAnswer' => 0,
                    'points' => 1,
                    'explanation' => 'Close the module once the pack and the call message are clear.'
                }
            }
        };
        return JSON.serialize(payload);
    }

    private static Set<Id> trainingTerritoryIds() {
        Set<Id> roots = new Set<Id>();
        for (Territory2 territory : [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c LIKE '%TRAINING%'
            WITH SYSTEM_MODE
        ]) {
            roots.add(territory.Id);
        }
        if (roots.isEmpty()) {
            return roots;
        }
        return TerritoryHierarchyService.expandTerritoryHierarchy(roots);
    }

    private static Integer ensureAlignments(List<Id> courseIds, Set<Id> territoryIds) {
        Set<String> territoryKeys = new Set<String>();
        for (Id territoryId : territoryIds) {
            territoryKeys.add(String.valueOf(territoryId));
        }
        Set<String> existing = new Set<String>();
        for (Learning_Material_Territory_Alignment__c alignment : [
            SELECT Learning_Material__c, Territory2_Id__c
            FROM Learning_Material_Territory_Alignment__c
            WHERE Learning_Material__c IN :courseIds AND Territory2_Id__c IN :territoryKeys
            WITH SYSTEM_MODE
        ]) {
            existing.add(String.valueOf(alignment.Learning_Material__c) + ':' + alignment.Territory2_Id__c);
        }
        List<Learning_Material_Territory_Alignment__c> toInsert =
            new List<Learning_Material_Territory_Alignment__c>();
        for (Id courseId : courseIds) {
            for (Id territoryId : territoryIds) {
                String key = String.valueOf(courseId) + ':' + String.valueOf(territoryId);
                if (existing.contains(key)) {
                    continue;
                }
                toInsert.add(new Learning_Material_Territory_Alignment__c(
                    Learning_Material__c = courseId,
                    Territory2_Id__c = String.valueOf(territoryId),
                    Is_Active__c = true
                ));
            }
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }
        return toInsert.size();
    }

    private static Integer assignCourses(List<Id> courseIds, Set<Id> userIds) {
        if (userIds.isEmpty() || courseIds.isEmpty()) {
            return 0;
        }
        Map<Id, List<Learning_Material__c>> childrenByCourse = new Map<Id, List<Learning_Material__c>>();
        Set<Id> materialIds = new Set<Id>(courseIds);
        for (Learning_Material__c child : [
            SELECT Id, Parent_Material__c
            FROM Learning_Material__c
            WHERE Parent_Material__c IN :courseIds AND Active__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            materialIds.add(child.Id);
            if (!childrenByCourse.containsKey(child.Parent_Material__c)) {
                childrenByCourse.put(child.Parent_Material__c, new List<Learning_Material__c>());
            }
            childrenByCourse.get(child.Parent_Material__c).add(child);
        }

        Set<String> existing = new Set<String>();
        for (Learning_Material_Instance__c inst : [
            SELECT Learner__c, Material__c
            FROM Learning_Material_Instance__c
            WHERE Learner__c IN :userIds AND Material__c IN :materialIds
            WITH SYSTEM_MODE
        ]) {
            existing.add(instanceKey(inst.Learner__c, inst.Material__c));
        }

        List<Id> sortedUsers = new List<Id>(userIds);
        sortedUsers.sort();
        Map<Id, Integer> indexByUser = new Map<Id, Integer>();
        for (Integer i = 0; i < sortedUsers.size(); i++) {
            indexByUser.put(sortedUsers[i], i);
        }

        List<Learning_Material_Instance__c> toInsert = new List<Learning_Material_Instance__c>();
        Integer courseIndex = 0;
        for (Id courseId : courseIds) {
            List<Learning_Material__c> children = childrenByCourse.containsKey(courseId)
                ? childrenByCourse.get(courseId)
                : new List<Learning_Material__c>();
            for (Id userId : sortedUsers) {
                Integer bucket = Math.mod(indexByUser.get(userId) + courseIndex, 3);
                addInstance(toInsert, existing, userId, courseId, bucket, true);
                for (Learning_Material__c child : children) {
                    addInstance(toInsert, existing, userId, child.Id, bucket, false);
                }
            }
            courseIndex++;
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }
        return toInsert.size();
    }

    private static void addInstance(
        List<Learning_Material_Instance__c> toInsert,
        Set<String> existing,
        Id userId,
        Id materialId,
        Integer bucket,
        Boolean isCourse
    ) {
        String key = instanceKey(userId, materialId);
        if (existing.contains(key)) {
            return;
        }
        existing.add(key);
        Learning_Material_Instance__c inst = new Learning_Material_Instance__c(
            Learner__c = userId,
            Material__c = materialId,
            Status__c = 'Not Started',
            Progress__c = 0,
            Attempt_Number__c = 0
        );
        if (bucket == 1) {
            inst.Status__c = isCourse ? 'In Progress' : 'Not Started';
            inst.Progress__c = isCourse ? 40 : 0;
            if (isCourse) {
                inst.Started_On__c = Datetime.now().addDays(-2);
            }
        } else if (bucket == 2) {
            inst.Status__c = 'Completed';
            inst.Progress__c = 100;
            inst.Started_On__c = Datetime.now().addDays(-5);
            inst.Completed_On__c = Datetime.now().addDays(-1);
            if (!isCourse) {
                inst.Score__c = 100;
                inst.Attempt_Number__c = 1;
            }
        }
        toInsert.add(inst);
    }

    private static String instanceKey(Id userId, Id materialId) {
        return String.valueOf(userId) + ':' + String.valueOf(materialId);
    }
}