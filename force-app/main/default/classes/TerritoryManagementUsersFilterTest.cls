@IsTest
private class TerritoryManagementUsersFilterTest {
    private static User makeUser(String alias, String title, Date hire) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
        return new User(
            Alias = alias,
            Email = alias + uniq + '@zeta-pharma.com',
            Username = alias + uniq + '@zeta-pharma.com.test',
            LastName = alias,
            Title = title,
            TimeZoneSidKey = 'Africa/Cairo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id,
            Hire_Date__c = hire,
            Resignation_Date__c = hire == null ? null : hire.addYears(4),
            Last_Work_Day__c = hire == null ? null : hire.addYears(4).addDays(30)
        );
    }

    @IsTest
    static void titleOptionsStayCompleteWhenATitleIsSelected() {
        Database.insert(
            new List<User>{
                makeUser('tfa', 'Zeta Filter Title A', Date.newInstance(2022, 2, 1)),
                makeUser('tfb', 'Zeta Filter Title B', null)
            },
            AccessLevel.SYSTEM_MODE
        );
        TerritoryManagementController.UserQueryRequest all = new TerritoryManagementController.UserQueryRequest();
        all.includeInactive = true;
        all.pageSize = 500;
        TerritoryManagementController.ManagedUsersPage unfiltered = TerritoryManagementController.queryManagedUsers(all);
        System.assert(unfiltered.titleOptions.contains('Zeta Filter Title A'));
        System.assert(unfiltered.titleOptions.contains('Zeta Filter Title B'));

        TerritoryManagementController.UserQueryRequest filtered = new TerritoryManagementController.UserQueryRequest();
        filtered.includeInactive = true;
        filtered.pageSize = 500;
        filtered.titleFilter = 'Zeta Filter Title A';
        TerritoryManagementController.ManagedUsersPage page = TerritoryManagementController.queryManagedUsers(filtered);

        System.assertEquals(1, page.users.size(), 'only the selected title is listed');
        System.assertEquals('Zeta Filter Title A', page.users[0].title);
        System.assert(page.titleOptions.contains('Zeta Filter Title B'), 'other titles stay selectable: ' + page.titleOptions);
        System.assertEquals(unfiltered.titleOptions.size(), page.titleOptions.size());
        // HR dates flow to the Users view
        System.assertEquals(Date.newInstance(2022, 2, 1), page.users[0].hireDate);
        System.assertEquals(Date.newInstance(2026, 2, 1), page.users[0].resignationDate);
        System.assertEquals(Date.newInstance(2026, 3, 3), page.users[0].lastWorkDay);

        filtered.titleFilter = 'All';
        System.assertEquals(unfiltered.totalCount, TerritoryManagementController.queryManagedUsers(filtered).totalCount);
    }

    @IsTest
    static void searchMatchesAcrossFieldsAndPages() {
        Database.insert(
            new List<User>{
                makeUser('sfa', 'Zeta Search Alpha', Date.newInstance(2021, 1, 2)),
                makeUser('sfb', 'Zeta Search Beta', null)
            },
            AccessLevel.SYSTEM_MODE
        );

        TerritoryManagementController.UserQueryRequest byTitle = new TerritoryManagementController.UserQueryRequest();
        byTitle.includeInactive = true;
        byTitle.pageSize = 25;
        byTitle.searchTerm = 'zeta search alpha';
        TerritoryManagementController.ManagedUsersPage alpha = TerritoryManagementController.queryManagedUsers(byTitle);
        System.assertEquals(1, alpha.totalCount, 'every search word must match');
        System.assertEquals('Zeta Search Alpha', alpha.users[0].title);
        System.assertEquals(false, alpha.hasMore);
        System.assert(
            alpha.titleOptions.contains('Zeta Search Beta'),
            'search must leave the other titles selectable: ' + alpha.titleOptions
        );

        TerritoryManagementController.UserQueryRequest cased = new TerritoryManagementController.UserQueryRequest();
        cased.includeInactive = true;
        cased.pageSize = 50;
        cased.titleFilter = 'ZETA SEARCH ALPHA';
        TerritoryManagementController.ManagedUsersPage casedPage = TerritoryManagementController.queryManagedUsers(cased);
        System.assertEquals(1, casedPage.totalCount);
        System.assertEquals('Zeta Search Alpha', casedPage.users[0].title);

        TerritoryManagementController.UserQueryRequest byDomain = new TerritoryManagementController.UserQueryRequest();
        byDomain.includeInactive = true;
        byDomain.pageSize = 1;
        byDomain.pageNumber = 1;
        byDomain.searchTerm = 'zeta-pharma.com';
        TerritoryManagementController.ManagedUsersPage first = TerritoryManagementController.queryManagedUsers(byDomain);
        System.assert(first.totalCount >= 2, 'domain search should find both new users');
        System.assertEquals(1, first.users.size());
        System.assertEquals(true, first.hasMore);
        System.assertEquals(1, first.pageNumber);

        byDomain.pageNumber = 2;
        TerritoryManagementController.ManagedUsersPage second = TerritoryManagementController.queryManagedUsers(byDomain);
        System.assertEquals(1, second.users.size());
        System.assertNotEquals(first.users[0].id, second.users[0].id);

        byDomain.pageNumber = first.totalCount + 25;
        TerritoryManagementController.ManagedUsersPage clamped = TerritoryManagementController.queryManagedUsers(byDomain);
        System.assertEquals(first.totalCount, clamped.pageNumber, 'a page past the end clamps to the last page');
        System.assertEquals(1, clamped.users.size());
        System.assertEquals(false, clamped.hasMore);

        TerritoryManagementController.UserQueryRequest none = new TerritoryManagementController.UserQueryRequest();
        none.includeInactive = true;
        none.searchTerm = 'zzzz-no-such-zeta-user';
        System.assertEquals(0, TerritoryManagementController.queryManagedUsers(none).totalCount);

        TerritoryManagementController.UserQueryRequest missingLine = new TerritoryManagementController.UserQueryRequest();
        missingLine.includeInactive = true;
        missingLine.lineFilter = 'No Such Zeta Line XYZ';
        System.assertEquals(0, TerritoryManagementController.queryManagedUsers(missingLine).totalCount);
    }

    @IsTest
    static void jsonRequestKeepsSearchAndPage() {
        TerritoryManagementController.ManagedUsersPage page = TerritoryManagementController.queryManagedUsersJson(
            '{"searchTerm":"zzzz-json-no-such-user","includeInactive":true,"pageSize":5,"pageNumber":9,"activeFilter":"All"}'
        );
        System.assertEquals(0, page.totalCount);
        System.assertEquals('zzzz-json-no-such-user', page.appliedSearchTerm);
        System.assertEquals(1, page.pageNumber, 'a page past an empty result clamps to page 1');

        TerritoryManagementController.ManagedUsersPage paged = TerritoryManagementController.queryManagedUsersJson(
            '{"includeInactive":true,"pageSize":1,"pageNumber":2,"activeFilter":"All"}'
        );
        System.assertEquals(1, paged.users.size());
        System.assertEquals(2, paged.pageNumber);
        System.assert(paged.totalCount > 1);
    }
}
