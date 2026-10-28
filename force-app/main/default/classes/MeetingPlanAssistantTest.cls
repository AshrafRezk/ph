@IsTest
private class MeetingPlanAssistantTest {
    static Id webinar(String title, DateTime startAt, Integer participants) {
        return MeetingLifecycleController.saveMeeting(JSON.serialize(new Map<String, Object>{
            'title' => title,
            'department' => 'Medical',
            'activityType' => 'Webinar',
            'startDateTime' => startAt,
            'endDateTime' => startAt.addHours(2),
            'venue' => 'Cairo',
            'estimatedParticipants' => participants
        }));
    }

    @TestSetup
    static void setup() {
        Id hcp = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Medical_Professional_HCP').getRecordTypeId();
        Account cardioA = new Account(Name = 'Dr. Amal', RecordTypeId = hcp, Specialty_1__c = 'Cardiology', Tier__c = 'A');
        Account cardioB = new Account(Name = 'Dr. Bassem', RecordTypeId = hcp, Specialty_1__c = 'Cardiology');
        Account paeds = new Account(Name = 'Dr. Carine', RecordTypeId = hcp, Specialty_1__c = 'Paediatrics');
        insert new List<Account>{ cardioA, cardioB, paeds };

        Meeting_Service__c catering = new Meeting_Service__c(Name = 'Catering', Department__c = 'All');
        Meeting_Service__c screens = new Meeting_Service__c(Name = 'Screens', Department__c = 'All');
        insert new List<Meeting_Service__c>{ catering, screens };
        Meeting_Vendor__c nile = new Meeting_Vendor__c(Name = 'Nile Catering', Category__c = 'Catering');
        insert nile;

        List<Id> past = new List<Id>{
            webinar('Past one', System.now().addDays(-60), 10),
            webinar('Past two', System.now().addDays(-50), 10),
            webinar('Past three', System.now().addDays(-45), 10)
        };
        List<Decimal> unitCosts = new List<Decimal>{ 100, 120, 140 };
        for (Integer i = 0; i < past.size(); i++) {
            MeetingLifecycleController.addServiceItem(past[i], catering.Id, nile.Id, null, 10, unitCosts[i]);
        }
        MeetingLifecycleController.addServiceItem(past[0], screens.Id, null, null, 1, 900);

        Id attendee = Schema.SObjectType.Meeting_Member__c.getRecordTypeInfosByDeveloperName().get('Attendee').getRecordTypeId();
        insert new List<Meeting_Member__c>{
            member(past[0], cardioA.Id, 'Attended', attendee),
            member(past[1], cardioA.Id, 'Attended', attendee),
            member(past[0], cardioB.Id, 'Did Not Attend', attendee),
            member(past[2], paeds.Id, 'Attended', attendee)
        };

        List<Decimal> costs = new List<Decimal>{ 10000, 15000, 20000 };
        List<Meeting__c> updates = new List<Meeting__c>();
        for (Integer i = 0; i < past.size(); i++) {
            updates.add(new Meeting__c(Id = past[i], Status__c = 'Concluded', Actual_Cost__c = costs[i], Final_Participants__c = 10));
        }
        update updates;
    }

    static Meeting_Member__c member(Id meetingId, Id accountId, String attendance, Id recordTypeId) {
        return new Meeting_Member__c(
            Meeting__c = meetingId, Customer__c = accountId, RecordTypeId = recordTypeId,
            Type__c = 'Participant', Status__c = 'Invited', Attendance_Status__c = attendance
        );
    }

    static Map<String, Account> accounts() {
        Map<String, Account> byName = new Map<String, Account>();
        for (Account a : [SELECT Id, Name FROM Account WHERE Name LIKE 'Dr. %']) {
            byName.put(a.Name, a);
        }
        return byName;
    }

    @IsTest
    static void ranksInviteesFromPastAttendance() {
        Id draftId = webinar('New cardio webinar', System.now().addDays(20), 20);
        Test.startTest();
        MeetingPlanAssistant.Suggestions result = MeetingPlanAssistant.suggest(draftId);
        Test.stopTest();

        Assert.areEqual(3, result.similarCount);
        Assert.isTrue(result.basis.startsWith('Based on 3 past'));
        Assert.areEqual(3, result.invitees.size());
        Assert.areEqual('Dr. Amal', result.invitees[0].name, 'Usual specialty, always attends, tier A');
        Assert.areEqual(80, result.invitees[0].score);
        Assert.isTrue(result.invitees[0].reason.contains('attended 2 of 2'));
        Assert.areEqual('Dr. Carine', result.invitees[1].name);
        Assert.areEqual('Dr. Bassem', result.invitees[2].name, 'Invited before but never came');
    }

    @IsTest
    static void skipsPeopleAlreadyOnTheMeeting() {
        Id draftId = webinar('Second webinar', System.now().addDays(20), 20);
        Id attendeeType = Schema.SObjectType.Meeting_Member__c.getRecordTypeInfosByDeveloperName()
            .get('Attendee')
            .getRecordTypeId();
        insert member(draftId, accounts().get('Dr. Amal').Id, 'Invited', attendeeType);
        MeetingPlanAssistant.Suggestions result = MeetingPlanAssistant.suggest(draftId);
        for (MeetingPlanAssistant.InviteeSuggestion row : result.invitees) {
            Assert.areNotEqual('Dr. Amal', row.name);
        }
    }

    @IsTest
    static void suggestsServicesAndBudget() {
        Id draftId = webinar('Budget webinar', System.now().addDays(20), 20);
        MeetingPlanAssistant.Suggestions result = MeetingPlanAssistant.suggest(draftId);

        Assert.areEqual('Catering', result.services[0].serviceName, 'Most used service first');
        Assert.areEqual(3, result.services[0].usedIn);
        Assert.areEqual('Nile Catering', result.services[0].vendorName);
        Assert.areEqual(120, result.services[0].unitCost, 'Median unit cost');
        Assert.areEqual(20, result.services[0].quantity, 'One per guest, scaled to 20 guests');
        Assert.areEqual(2400, result.services[0].amount);

        MeetingPlanAssistant.BudgetSuggestion budget = result.budget;
        Assert.areEqual(1250, budget.perAttendeeLow);
        Assert.areEqual(1500, budget.perAttendeeTypical);
        Assert.areEqual(1750, budget.perAttendeeHigh);
        Assert.areEqual(25000, budget.low);
        Assert.areEqual(35000, budget.high);
        Assert.areEqual('none', budget.verdict);

        Meeting_Service__c catering = [SELECT Id FROM Meeting_Service__c WHERE Name = 'Catering'];
        MeetingLifecycleController.addServiceItem(draftId, catering.Id, null, null, 1, 60000);
        MeetingPlanAssistant.Suggestions after = MeetingPlanAssistant.suggest(draftId);
        Assert.areEqual('above', after.budget.verdict);
        for (MeetingPlanAssistant.ServiceSuggestion row : after.services) {
            Assert.areNotEqual('Catering', row.serviceName, 'Services already planned are not suggested again');
        }
    }

    @IsTest
    static void onlyTheOwnerSeesSuggestions() {
        Id draftId = webinar('Private webinar', System.now().addDays(20), 20);
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User other = new User(
            Alias = 'mpaoth', Email = 'mpaoth@zeta.test', EmailEncodingKey = 'UTF-8', LastName = 'Other',
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = standard.Id, TimeZoneSidKey = 'Africa/Cairo',
            Username = 'mpaoth.' + Crypto.getRandomInteger() + '@zeta.meetings.test'
        );
        insert other;
        System.runAs(other) {
            try {
                MeetingPlanAssistant.suggest(draftId);
                Assert.fail('Another user must not see the suggestions');
            } catch (AuraHandledException e) {
                Assert.isTrue(String.isNotBlank(e.getMessage()));
            }
        }
    }

    @IsTest
    static void percentileInterpolates() {
        List<Decimal> values = new List<Decimal>{ 4, 1, 3, 2 };
        Assert.areEqual(1.75, MeetingPlanAssistant.percentile(values, 0.25));
        Assert.areEqual(2.5, MeetingPlanAssistant.percentile(values, 0.5));
        Assert.isNull(MeetingPlanAssistant.percentile(new List<Decimal>(), 0.5));
        Assert.isNull(MeetingPlanAssistant.budget(new Meeting__c(), new List<Meeting__c>()));
    }
}
