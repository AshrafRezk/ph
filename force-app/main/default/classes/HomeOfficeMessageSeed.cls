public without sharing class HomeOfficeMessageSeed {

    public static final String WELCOME_SUBJECT = 'Welcome to Salesforce';
    public static final String WELCOME_BODY = 'Welcome to salesforce your assitant on the field!';

    public class SeedResult {
        public Integer messagesCreated = 0;
        public String message;
    }

    private class MessageSpec {
        public String subject;
        public String body;
        public String priority;
        public MessageSpec(String subject, String body, String priority) {
            this.subject = subject;
            this.body = body;
            this.priority = priority;
        }
    }

    private static List<MessageSpec> fieldGuideMessages() {
        return new List<MessageSpec>{
            new MessageSpec(
                WELCOME_SUBJECT,
                WELCOME_BODY,
                'High'
            ),
            new MessageSpec(
                'Home — start your day',
                'Today\'s visits, next-best customers, and KPIs in one view. Check Home before you hit the road.',
                'Normal'
            ),
            new MessageSpec(
                'Planner — own your cycle',
                'Schedule visits, build your route, and keep the week on track. Open Planner to plan in minutes.',
                'Normal'
            ),
            new MessageSpec(
                'Accounts — your list',
                'Search doctors, open a profile, and start a call. Your customers live on the Accounts tab.',
                'Normal'
            ),
            new MessageSpec(
                'Learning — stay sharp ;)',
                'Short modules and CLM decks between calls. A few minutes now helps the next visit ;)',
                'Normal'
            )
        };
    }

    public static SeedResult seedWelcomeToAllTerritories() {
        return seedFieldGuideMessages();
    }

    public static SeedResult seedFieldGuideMessages() {
        SeedResult result = new SeedResult();
        List<MessageSpec> specs = fieldGuideMessages();
        Set<String> subjects = new Set<String>();
        for (MessageSpec spec : specs) {
            subjects.add(spec.subject);
        }
        Map<String, Home_Office_Message__c> existingByName = new Map<String, Home_Office_Message__c>();
        for (Home_Office_Message__c row : [
            SELECT Id, Name, Message_Body__c, Is_Active__c, Published_On__c, Priority__c
            FROM Home_Office_Message__c
            WHERE Name IN :subjects
            AND Audience_Scope__c = 'All Business Units'
            WITH SYSTEM_MODE
        ]) {
            if (!existingByName.containsKey(row.Name)) {
                existingByName.put(row.Name, row);
            }
        }

        List<Home_Office_Message__c> toInsert = new List<Home_Office_Message__c>();
        List<Home_Office_Message__c> toUpdate = new List<Home_Office_Message__c>();
        Datetime now = System.now();
        for (MessageSpec spec : specs) {
            Home_Office_Message__c row = existingByName.get(spec.subject);
            if (row == null) {
                toInsert.add(
                    new Home_Office_Message__c(
                        Name = spec.subject,
                        Message_Body__c = spec.body,
                        Audience_Scope__c = 'All Business Units',
                        Priority__c = spec.priority,
                        Published_On__c = now,
                        Is_Active__c = true,
                        Author__c = UserInfo.getUserId()
                    )
                );
                continue;
            }
            row.Message_Body__c = spec.body;
            row.Priority__c = spec.priority;
            row.Is_Active__c = true;
            row.Published_On__c = now;
            toUpdate.add(row);
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
            result.messagesCreated = toInsert.size();
        }
        if (!toUpdate.isEmpty()) {
            update as system toUpdate;
        }
        result.message =
            'Home office messages for all territories: created=' +
            result.messagesCreated +
            ', refreshed=' +
            toUpdate.size() +
            '.';
        return result;
    }

    public static SeedResult seedDemoMessages() {
        SeedResult welcome = seedWelcomeToAllTerritories();
        SeedResult result = new SeedResult();
        result.messagesCreated = welcome.messagesCreated;
        Integer extraDemoCount = [
            SELECT COUNT()
            FROM Home_Office_Message__c
            WHERE Name IN (
                'Q2 Coloverin D focus — all field teams',
                'GIT BU — Coloverin line coverage push'
            )
            WITH SYSTEM_MODE
        ];
        if (extraDemoCount > 0) {
            result.message = welcome.message;
            return result;
        }

        Id gitBuId = null;
        List<Territory2> gitBu = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = 'TERR_GIT'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!gitBu.isEmpty()) {
            gitBuId = gitBu[0].Id;
        }
        List<User> admins = [
            SELECT Id
            FROM User
            WHERE Username = 'admin@pharma.eg' AND IsActive = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Id authorId = admins.isEmpty() ? UserInfo.getUserId() : admins[0].Id;

        List<Home_Office_Message__c> messages = new List<Home_Office_Message__c>{
            new Home_Office_Message__c(
                Name = 'Q2 Coloverin D focus — all field teams',
                Message_Body__c = 'Prioritize Coloverin D detailing for IBS/bloating this month. Use the Chemipharm CLM deck and capture EFFICACY/SAFETY sentiment on every call.',
                Audience_Scope__c = 'All Business Units',
                Priority__c = 'High',
                Published_On__c = System.now().addDays(-2),
                Is_Active__c = true,
                Author__c = authorId
            ),
            new Home_Office_Message__c(
                Name = 'GIT BU — Coloverin line coverage push',
                Message_Body__c = 'GIT BU: close coverage gaps on Coloverin / Coloverin D / Coloverin A / Coloverin SR before month end. DMs to review weekly coaching notes.',
                Audience_Scope__c = 'Business Unit',
                Target_Bu_Territory_Id__c = gitBuId == null ? null : String.valueOf(gitBuId),
                Priority__c = 'Normal',
                Published_On__c = System.now().addDays(-5),
                Is_Active__c = true,
                Author__c = authorId
            )
        };
        insert as system messages;
        result.messagesCreated += messages.size();
        result.message =
            welcome.message +
            ' Seeded ' +
            messages.size() +
            ' additional home office messages.';
        return result;
    }
}