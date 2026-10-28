@IsTest
private class VisitActorAccessTest {
    @IsTest
    static void systemAdminCanEditScheduleAndViewServiceRequests() {
        System.assertEquals(true, VisitActorAccess.canEditVisitSchedule());
        System.assertEquals(true, VisitActorAccess.canViewServiceRequests());
        System.assertEquals(true, VisitActorAccess.canEditVisitSchedule());
    }

    @IsTest
    static void testOverridesShortCircuitRoleChecks() {
        VisitActorAccess.testCanEditSchedule = false;
        VisitActorAccess.testCanViewServiceRequests = false;

        System.assertEquals(false, VisitActorAccess.canEditVisitSchedule());
        System.assertEquals(false, VisitActorAccess.canViewServiceRequests());

        VisitActorAccess.testCanEditSchedule = true;
        VisitActorAccess.testCanViewServiceRequests = true;

        System.assertEquals(true, VisitActorAccess.canEditVisitSchedule());
        System.assertEquals(true, VisitActorAccess.canViewServiceRequests());
    }

    @IsTest
    static void editVisitDatePermissionHonorsTestOverride() {
        VisitActorAccess.testCanEditVisitDate = true;
        System.assertEquals(true, VisitActorAccess.canEditVisitDate());
        VisitActorAccess.testCanEditVisitDate = false;
        System.assertEquals(false, VisitActorAccess.canEditVisitDate());
    }

    @IsTest
    static void editVisitDateIsOffWithoutCustomPermission() {
        User rep = userWithTitle('Medical Rep');
        insert rep;
        System.runAs(rep) {
            System.assertEquals(false, VisitActorAccess.canEditVisitDate());
        }
    }

    @IsTest
    static void sfeCanEditScheduleButCannotViewServiceRequests() {
        User sfe = userWithTitle('SFE');
        insert sfe;

        System.runAs(sfe) {
            System.assertEquals(true, VisitActorAccess.canEditVisitSchedule());
            System.assertEquals(false, VisitActorAccess.canViewServiceRequests());
        }
    }

    @IsTest
    static void managerCanEditScheduleAndViewServiceRequests() {
        User manager = userWithTitle('District Manager');
        insert manager;

        System.runAs(manager) {
            System.assertEquals(true, VisitActorAccess.canEditVisitSchedule());
            System.assertEquals(true, VisitActorAccess.canViewServiceRequests());
        }
    }

    @IsTest
    static void medicalRepCannotEditScheduleOrViewServiceRequests() {
        User rep = userWithTitle('Medical Rep');
        insert rep;

        System.runAs(rep) {
            System.assertEquals(false, VisitActorAccess.canEditVisitSchedule());
            System.assertEquals(false, VisitActorAccess.canViewServiceRequests());
            System.assertEquals(false, VisitActorAccess.canEditVisitSchedule());
        }
    }

    @IsTest
    static void territoryManagerRoleGrantsAccessWhenTitleDoesNot() {
        User rep = userWithTitle('Medical Rep');
        insert rep;
        if (!assignTerritoryRole(rep.Id, 'District Manager')) {
            return;
        }

        System.runAs(rep) {
            System.assertEquals(true, VisitActorAccess.canEditVisitSchedule());
            System.assertEquals(true, VisitActorAccess.canViewServiceRequests());
            System.assertEquals(true, VisitActorAccess.canViewServiceRequests());
        }
    }

    private static User userWithTitle(String title) {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
            Alias = suffix.left(8),
            Email = 'actor' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ActorAccess',
            Title = title,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Africa/Cairo',
            UserName = 'actor' + suffix + '@example.com.test',
            ProfileId = standardProfile.Id
        );
    }

    private static Boolean assignTerritoryRole(Id userId, String role) {
        List<Territory2> territories = [SELECT Id FROM Territory2 LIMIT 1];
        if (territories.isEmpty()) {
            return false;
        }
        insert new UserTerritory2Association(
            UserId = userId,
            Territory2Id = territories[0].Id,
            RoleInTerritory2 = role
        );
        return true;
    }
}