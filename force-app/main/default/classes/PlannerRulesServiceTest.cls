@IsTest
private class PlannerRulesServiceTest {
    @IsTest
    static void getAndSaveRule_roundTripsWorkingDaysAndPolicies() {
        PlannerRulesService.Rule loaded = PlannerRulesService.getRule();
        System.assertNotEquals(null, loaded);
        System.assertEquals(true, loaded.workingDayNumbers.contains(6), 'Sat is a working day by default');
        System.assertEquals(PlannerRulesService.BLOCK, loaded.visitTotOverlap);

        PlannerRulesService.Rule input = new PlannerRulesService.Rule();
        input.workingDays = 'SUN,MON,TUE,WED,THU';
        input.visitTotOverlap = PlannerRulesService.WARN;
        input.visitVisitOverlap = PlannerRulesService.ALLOW;
        input.visitMeetingOverlap = PlannerRulesService.BLOCK;
        input.totMeetingOverlap = PlannerRulesService.ALLOW;
        input.visitHolidayOverlap = PlannerRulesService.WARN;
        input.meetingHolidayOverlap = PlannerRulesService.ALLOW;
        input.weekendPlanning = PlannerRulesService.WARN;

        Test.startTest();
        PlannerRulesService.Rule saved = PlannerRulesService.saveRule(input);
        Test.stopTest();

        System.assertEquals(PlannerRulesService.WARN, saved.visitTotOverlap);
        System.assertEquals(PlannerRulesService.ALLOW, saved.visitVisitOverlap);
        System.assert(saved.workingDays.contains('SUN'));
        System.assertEquals(false, PlannerRulesService.workingDaySet().contains(6), 'Sat no longer working');
        System.assertEquals(true, PlannerRulesService.workingDaySet().contains(4), 'Thu is working');
        System.assertEquals('Org', saved.scopeLevel);
    }

    @IsTest
    static void orgLineUserCascade_andExceptionCrud() {
        PlannerRulesService.Rule org = new PlannerRulesService.Rule();
        org.workingDays = 'SAT,SUN,MON,TUE,WED';
        org.visitTotOverlap = PlannerRulesService.BLOCK;
        org.visitVisitOverlap = PlannerRulesService.BLOCK;
        org.visitMeetingOverlap = PlannerRulesService.BLOCK;
        org.totMeetingOverlap = PlannerRulesService.WARN;
        org.visitHolidayOverlap = PlannerRulesService.BLOCK;
        org.meetingHolidayOverlap = PlannerRulesService.WARN;
        org.weekendPlanning = PlannerRulesService.BLOCK;
        PlannerRulesService.saveRuleForScope(org, 'Org', 'ORG');

        PlannerRulesService.Rule line = new PlannerRulesService.Rule();
        line.workingDays = 'SUN,MON,TUE,WED,THU';
        line.visitTotOverlap = PlannerRulesService.WARN;
        line.visitVisitOverlap = PlannerRulesService.ALLOW;
        line.visitMeetingOverlap = PlannerRulesService.WARN;
        line.totMeetingOverlap = PlannerRulesService.ALLOW;
        line.visitHolidayOverlap = PlannerRulesService.WARN;
        line.meetingHolidayOverlap = PlannerRulesService.ALLOW;
        line.weekendPlanning = PlannerRulesService.ALLOW;
        PlannerRulesService.Rule savedLine = PlannerRulesService.saveRuleForScope(line, 'Line', 'DIAB-I');
        System.assertEquals('Line', savedLine.scopeLevel);
        System.assertEquals('DIAB-I', savedLine.scopeKey);

        PlannerRulesService.Rule userRule = new PlannerRulesService.Rule();
        userRule.workingDays = 'SAT,SUN,MON,TUE,WED,FRI';
        userRule.visitTotOverlap = PlannerRulesService.ALLOW;
        userRule.visitVisitOverlap = PlannerRulesService.ALLOW;
        userRule.visitMeetingOverlap = PlannerRulesService.ALLOW;
        userRule.totMeetingOverlap = PlannerRulesService.ALLOW;
        userRule.visitHolidayOverlap = PlannerRulesService.ALLOW;
        userRule.meetingHolidayOverlap = PlannerRulesService.ALLOW;
        userRule.weekendPlanning = PlannerRulesService.ALLOW;
        String userKey = String.valueOf(UserInfo.getUserId());
        PlannerRulesService.Rule savedUser = PlannerRulesService.saveRuleForScope(
            userRule,
            'User',
            userKey
        );
        System.assertEquals('User', savedUser.scopeLevel);

        Test.startTest();
        PlannerRulesService.Rule resolved = PlannerRulesService.resolveRuleForUser(UserInfo.getUserId());
        System.assertEquals(PlannerRulesService.ALLOW, resolved.weekendPlanning);
        List<PlannerRulesService.ScopeSummary> listed = PlannerRulesService.listScopedRules('All');
        System.assert(listed.size() >= 2, 'Line and user exceptions should list');
        System.assertNotEquals(null, PlannerRulesService.listLineOptions());
        System.assertNotEquals(null, PlannerRulesService.searchUsersForException(UserInfo.getName().left(2)));
        PlannerRulesService.Rule loadedLine = PlannerRulesService.getRuleForScope('Line', 'DIAB-I');
        System.assertEquals('DIAB-I', loadedLine.scopeKey);
        PlannerRulesService.deleteScopedRule(savedUser.id);
        Test.stopTest();
        List<PlannerRulesService.ScopeSummary> after = PlannerRulesService.listScopedRules('User');
        for (PlannerRulesService.ScopeSummary row : after) {
            System.assertNotEquals(userKey, row.scopeKey);
        }
    }

    @IsTest
    static void enforce_allowWarnBlock() {
        PlannerRulesService.clearCache();
        PlannerRulesService.Rule input = new PlannerRulesService.Rule();
        input.workingDays = 'SAT,SUN,MON,TUE,WED';
        input.visitTotOverlap = PlannerRulesService.ALLOW;
        input.visitVisitOverlap = PlannerRulesService.WARN;
        input.visitMeetingOverlap = PlannerRulesService.BLOCK;
        input.totMeetingOverlap = PlannerRulesService.WARN;
        input.visitHolidayOverlap = PlannerRulesService.BLOCK;
        input.meetingHolidayOverlap = PlannerRulesService.WARN;
        input.weekendPlanning = PlannerRulesService.BLOCK;
        PlannerRulesService.saveRule(input);

        System.assertEquals(false, PlannerRulesService.enforce('Visit_Tot', 'ignored', false));
        System.assertEquals(PlannerRulesService.WARN, PlannerRulesService.policy('Visit_Visit'));
        System.assertEquals(PlannerRulesService.BLOCK, PlannerRulesService.policy('Visit_Meeting'));
        System.assertEquals(
            true,
            PlannerRulesService.isWarningMessage(PlannerRulesService.WARN_PREFIX + ' slot taken')
        );

        Boolean warned = false;
        try {
            PlannerRulesService.enforce('Visit_Visit', 'slot taken', false);
        } catch (AuraHandledException e) {
            warned = true;
        }
        System.assertEquals(true, warned, 'Warn without ack should throw');
        System.assertEquals(false, PlannerRulesService.enforce('Visit_Visit', 'slot taken', true));

        Boolean blocked = false;
        try {
            PlannerRulesService.enforce('Visit_Meeting', 'meeting clash', false);
        } catch (AuraHandledException e) {
            blocked = true;
        }
        System.assertEquals(true, blocked, 'Block should throw');
    }

    @IsTest
    static void lineTitleScope_savesAndLists() {
        String combo = PlannerRulesService.composeLineTitleKey('CHC', 'Medical Rep');
        System.assertEquals('CHC||Medical Rep', combo);
        System.assertEquals(2, PlannerRulesService.parseLineTitleKey(combo).size());

        PlannerRulesService.Rule lineTitle = new PlannerRulesService.Rule();
        lineTitle.workingDays = 'SUN,MON,TUE,WED,THU';
        lineTitle.weekendPlanning = PlannerRulesService.WARN;
        lineTitle.visitTotOverlap = PlannerRulesService.BLOCK;
        lineTitle.visitVisitOverlap = PlannerRulesService.BLOCK;
        lineTitle.visitMeetingOverlap = PlannerRulesService.BLOCK;
        lineTitle.totMeetingOverlap = PlannerRulesService.WARN;
        lineTitle.visitHolidayOverlap = PlannerRulesService.BLOCK;
        lineTitle.meetingHolidayOverlap = PlannerRulesService.WARN;
        PlannerRulesService.Rule saved = PlannerRulesService.saveRuleForScope(
            lineTitle,
            PlannerRulesService.SCOPE_LINE_TITLE,
            combo
        );
        System.assertEquals(PlannerRulesService.SCOPE_LINE_TITLE, saved.scopeLevel);
        System.assertEquals(combo, saved.scopeKey);
        System.assert(saved.scopeLabel.contains('CHC'));
        System.assert(saved.scopeLabel.contains('Medical Rep'));

        Boolean found = false;
        for (PlannerRulesService.ScopeSummary row : PlannerRulesService.listScopedRules('All')) {
            if (row.scopeLevel == PlannerRulesService.SCOPE_LINE_TITLE && row.scopeKey == combo) {
                found = true;
            }
        }
        System.assertEquals(true, found, 'Line+Title exception should list');
        PlannerRulesService.deleteScopedRule(saved.id);
    }

    @IsTest
    static void weekend_isOneDefinitionForPlannerAndTimeCards() {
        Date thursday = Date.newInstance(2026, 5, 14);
        Date friday = Date.newInstance(2026, 5, 15);
        Date saturday = Date.newInstance(2026, 5, 16);

        // Department presets (AM = Fri+Sat weekend, PM = Thu+Fri) — shared by planner and time cards.
        System.assertEquals(false, PlannerRulesService.isWeekendDay(thursday, 'AM'));
        System.assertEquals(true, PlannerRulesService.isWeekendDay(friday, 'AM'));
        System.assertEquals(true, PlannerRulesService.isWeekendDay(saturday, 'AM'));
        System.assertEquals(true, PlannerRulesService.isWeekendDay(thursday, 'PM'));
        System.assertEquals(true, PlannerRulesService.isWeekendDay(friday, 'PM'));
        System.assertEquals(false, PlannerRulesService.isWeekendDay(saturday, 'PM'));
        System.assertEquals(
            PlannerRulesService.isWeekendDay(thursday, 'AM'),
            EmployeeTimeCardFlowHelper.isWeekendDay(thursday, 'AM')
        );
        System.assertEquals(
            PlannerRulesService.isWeekendDay(saturday, 'PM'),
            EmployeeTimeCardFlowHelper.isWeekendDay(saturday, 'PM')
        );
    }

    @IsTest
    static void saveRuleForScopes_appliesOneSettingToSeveralPositions() {
        PlannerRulesService.Rule input = new PlannerRulesService.Rule();
        input.workingDays = 'SUN,MON,TUE,WED,THU';
        input.visitTotOverlap = PlannerRulesService.BLOCK;
        input.visitVisitOverlap = PlannerRulesService.BLOCK;
        input.visitMeetingOverlap = PlannerRulesService.WARN;
        input.totMeetingOverlap = PlannerRulesService.WARN;
        input.visitHolidayOverlap = PlannerRulesService.BLOCK;
        input.meetingHolidayOverlap = PlannerRulesService.WARN;
        input.weekendPlanning = PlannerRulesService.BLOCK;

        Test.startTest();
        PlannerRulesService.Rule first = PlannerRulesService.saveRuleForScopes(
            input,
            'Title',
            new List<String>{ 'Medical Representative', ' District Sales Manager ', 'Medical Representative', '' }
        );
        PlannerRulesService.Rule lineTitle = PlannerRulesService.saveRuleForScopes(
            input,
            'Line_Title',
            new List<String>{ 'CHC||Medical Representative', 'CHC||Senior Medical Representative' }
        );
        Test.stopTest();

        System.assertEquals('Medical Representative', first.scopeKey);
        System.assertEquals('CHC||Medical Representative', lineTitle.scopeKey);
        List<Planner_Rule__c> titles = [
            SELECT Scope_Key__c, Working_Days__c
            FROM Planner_Rule__c
            WHERE Scope_Level__c = 'Title'
            ORDER BY Scope_Key__c
        ];
        System.assertEquals(2, titles.size(), 'Duplicates and blanks are ignored.');
        System.assertEquals('District Sales Manager', titles[0].Scope_Key__c);
        for (Planner_Rule__c row : titles) {
            System.assertEquals('SUN,MON,TUE,WED,THU', row.Working_Days__c);
        }
        System.assertEquals(2, [SELECT COUNT() FROM Planner_Rule__c WHERE Scope_Level__c = 'Line_Title']);
    }

    @IsTest
    static void saveRuleForScopes_refusesEmptyOrBadSelectionWithoutSavingAny() {
        PlannerRulesService.Rule input = new PlannerRulesService.Rule();
        input.workingDays = 'SUN,MON,TUE,WED,THU';
        Integer before = [SELECT COUNT() FROM Planner_Rule__c];
        List<String> errors = new List<String>();
        try {
            PlannerRulesService.saveRuleForScopes(input, 'Title', new List<String>());
        } catch (AuraHandledException ex) {
            errors.add('empty');
        }
        try {
            // Second key is not a valid line+title pair, so the first must roll back too.
            PlannerRulesService.saveRuleForScopes(
                input,
                'Line_Title',
                new List<String>{ 'CHC||Medical Representative', 'CHC' }
            );
        } catch (AuraHandledException ex) {
            errors.add('bad');
        }
        List<String> tooMany = new List<String>();
        for (Integer i = 0; i <= PlannerRulesService.MAX_SCOPE_KEYS_PER_SAVE; i++) {
            tooMany.add('Title ' + i);
        }
        try {
            PlannerRulesService.saveRuleForScopes(input, 'Title', tooMany);
        } catch (AuraHandledException ex) {
            errors.add('tooMany');
        }
        System.assertEquals(new List<String>{ 'empty', 'bad', 'tooMany' }, errors);
        System.assertEquals(before, [SELECT COUNT() FROM Planner_Rule__c]);
    }

    @IsTest
    static void savedOrgRuleOverridesDepartmentPresets() {
        PlannerRulesService.Rule input = new PlannerRulesService.Rule();
        input.workingDays = 'SUN,MON,TUE,WED,THU';
        input.visitTotOverlap = PlannerRulesService.BLOCK;
        input.visitVisitOverlap = PlannerRulesService.BLOCK;
        input.visitMeetingOverlap = PlannerRulesService.WARN;
        input.totMeetingOverlap = PlannerRulesService.WARN;
        input.visitHolidayOverlap = PlannerRulesService.BLOCK;
        input.meetingHolidayOverlap = PlannerRulesService.WARN;
        input.weekendPlanning = PlannerRulesService.BLOCK;
        PlannerRulesService.saveRule(input);
        PlannerRulesService.clearCache();

        Date thursday = Date.newInstance(2026, 5, 14);
        Date saturday = Date.newInstance(2026, 5, 16);
        // PM used to force Sat-Wed; the saved Org rule (Sun-Thu) now decides.
        System.assertEquals(false, PlannerRulesService.isWeekendDay(thursday, 'PM'));
        System.assertEquals(true, PlannerRulesService.isWeekendDay(saturday, 'PM'));
        System.assertEquals(false, PlannerRulesService.isWeekendDay(thursday, 'AM'));

        User me = [SELECT Id, Department FROM User WHERE Id = :UserInfo.getUserId()];
        me.Department = 'PM';
        update me;
        PlannerRulesService.clearCache();
        System.assertEquals(
            new Set<Integer>{ 0, 1, 2, 3, 4 },
            new Set<Integer>(PlannerRulesService.resolveRuleForUser(me.Id).workingDayNumbers)
        );
        System.assertEquals('Sunday through Thursday', PlannerRulesService.workingDaysLabelForUser(me.Id));
    }

    @IsTest
    static void policyForUser_readsTheGivenUsersRule() {
        User rep = new User(
            FirstName = 'Rule',
            LastName = 'Rep',
            Email = 'rule.rep@example.com',
            Username = 'rule.rep.' + System.currentTimeMillis() + '@example.com',
            Alias = 'rulerep',
            TimeZoneSidKey = 'Africa/Cairo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId()
        );
        insert rep;
        PlannerRulesService.Rule input = new PlannerRulesService.Rule();
        input.workingDays = 'SUN,MON,TUE,WED,THU';
        input.visitTotOverlap = PlannerRulesService.BLOCK;
        input.visitVisitOverlap = PlannerRulesService.ALLOW;
        input.visitMeetingOverlap = PlannerRulesService.WARN;
        input.totMeetingOverlap = PlannerRulesService.WARN;
        input.visitHolidayOverlap = PlannerRulesService.BLOCK;
        input.meetingHolidayOverlap = PlannerRulesService.WARN;
        input.weekendPlanning = PlannerRulesService.BLOCK;
        PlannerRulesService.saveRuleForScope(input, 'User', String.valueOf(rep.Id));
        PlannerRulesService.clearCache();

        System.assertEquals(PlannerRulesService.ALLOW, PlannerRulesService.policyForUser('Visit_Visit', rep.Id));
        System.assertEquals(PlannerRulesService.BLOCK, PlannerRulesService.policy('Visit_Visit'));
        System.assertEquals(true, PlannerRulesService.isWorkingDayForUser(Date.newInstance(2026, 5, 14), rep.Id));
        System.assertEquals('Saturday through Wednesday', PlannerRulesService.workingDaysLabelForUser(UserInfo.getUserId()));
    }
}
