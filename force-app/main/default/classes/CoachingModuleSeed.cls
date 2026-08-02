public with sharing class CoachingModuleSeed {

    public class SeedResult {
        public Id templateId;
        public Id eventId;
        public String message;
    }

    /**
     * Seeds pharma field coaching template and a demo event.
     * Run: CoachingModuleSeed.seedDemoData(null, null);
     * Or pass existing User Ids for Employee (rep) and Manager (DM).
     */
    public static SeedResult seedDemoData(Id employeeUserId, Id managerUserId) {
        SeedResult result = new SeedResult();

        String templateJson = getPharmaTemplateJson();

        Coaching_Template__c template = new Coaching_Template__c(
            Template_Title__c = 'Pharma Field Coaching — Core & Selling Skills',
            Template_Type__c = 'Field Coaching',
            Is_Active__c = true,
            Passing_Score__c = 70,
            Description__c = 'Pharma field coaching — Core Values and Selling Skills competencies.',
            Questions_JSON__c = templateJson
        );
        insert template;
        result.templateId = template.Id;

        Id repId = employeeUserId;
        Id mgrId = managerUserId;

        if (repId == null || mgrId == null) {
            List<User> users = [
                SELECT Id, Username
                FROM User
                WHERE IsActive = true
                WITH USER_MODE
                ORDER BY CreatedDate ASC
                LIMIT 10
            ];
            if (users.size() >= 2) {
                if (repId == null) {
                    repId = users[0].Id;
                }
                if (mgrId == null) {
                    mgrId = users[1].Id;
                }
            } else if (!users.isEmpty()) {
                if (repId == null) {
                    repId = users[0].Id;
                }
                if (mgrId == null) {
                    mgrId = users[0].Id;
                }
            }
        }

        String partialResponses =
            '{"version":"1.0","templateVersion":"1.2","answers":[' +
            '{"questionId":"q1","managerValue":5,"managerScore":5,"managerLabel":"Most of times",' +
            '"managerComments":"Consistently energetic on calls",' +
            '"employeeValue":6,"employeeScore":6,"employeeLabel":"All the times",' +
            '"employeeComments":"I bring high energy to every visit"},' +
            '{"questionId":"q2","managerValue":5,"managerScore":5,"managerLabel":"Most of times",' +
            '"employeeValue":5,"employeeScore":5,"employeeLabel":"Most of times"}' +
            '],"computedAt":"2026-06-15T10:30:00Z"}';

        CoachingScoringService.ScoreResult scores =
            CoachingScoringService.computeScores(templateJson, partialResponses);

        Coaching_Event__c event = new Coaching_Event__c(
            Coaching_Template__c = template.Id,
            Employee__c = repId,
            Manager__c = mgrId,
            Status__c = 'Draft',
            Event_Start__c = System.now(),
            Event_End__c = System.now().addDays(2),
            Responses_JSON__c = partialResponses,
            Manager_Total_Score__c = scores.managerTotalScore,
            Employee_Total_Score__c = scores.employeeTotalScore,
            Section_Scores_JSON__c = scores.sectionScoresJson
        );
        insert event;
        result.eventId = event.Id;
        result.message = 'Seeded template ' + template.Id + ' and event ' + event.Id;
        return result;
    }

    private static String getPharmaTemplateJson() {
        return '{"version":"1.2","totalQuestions":6,"totalPoints":36,"questions":[' +
            buildQuestion('q1', 'Core Values', 'Enthusiasm / Willingness to Work', 1) + ',' +
            buildQuestion('q2', 'Core Values', 'Creativity', 2) + ',' +
            buildQuestion('q3', 'Selling Skills', 'Visit Planning', 3) + ',' +
            buildQuestion('q4', 'Selling Skills', 'Overcoming HCP Objections', 4) + ',' +
            buildQuestion('q5', 'Selling Skills', 'Probing for Insights', 5) + ',' +
            buildQuestion('q6', 'Selling Skills', 'Closing', 6) +
            ']}';
    }

    private static String buildQuestion(String id, String section, String question, Integer sortOrder) {
        return '{' +
            '"id":"' + id + '",' +
            '"section":"' + section + '",' +
            '"respondent":"both",' +
            '"question":"' + question + '",' +
            '"type":"scale",' +
            '"scaleMin":1,"scaleMax":6,' +
            '"scaleMinLabel":"Never","scaleMaxLabel":"All the times",' +
            '"scalePoints":[' +
            '{"value":1,"weight":1,"label":"Never"},' +
            '{"value":2,"weight":2,"label":"Rarely"},' +
            '{"value":3,"weight":3,"label":"Sometimes"},' +
            '{"value":4,"weight":4,"label":"Often"},' +
            '{"value":5,"weight":5,"label":"Most of times"},' +
            '{"value":6,"weight":6,"label":"All the times"}' +
            '],"points":6,"sortOrder":' + sortOrder +
            '}';
    }
}
