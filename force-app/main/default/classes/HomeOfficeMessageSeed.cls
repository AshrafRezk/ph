public without sharing class HomeOfficeMessageSeed {

    public class SeedResult {
        public Integer messagesCreated = 0;
        public String message;
    }

    public static SeedResult seedDemoMessages() {
        SeedResult result = new SeedResult();
        List<Home_Office_Message__c> existing = [
            SELECT Id
            FROM Home_Office_Message__c
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            result.message = 'Home office messages already seeded.';
            return result;
        }

        Id gitBuId = TerritoryModuleSeed.getTerritoryId('TERR_GIT');
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
        result.messagesCreated = messages.size();
        result.message = 'Seeded ' + result.messagesCreated + ' home office messages.';
        return result;
    }
}
