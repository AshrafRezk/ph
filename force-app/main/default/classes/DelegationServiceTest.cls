@IsTest
private class DelegationServiceTest {
    private static Id fakeTerritoryId() {
        String keyPrefix = Territory2.SObjectType.getDescribe().getKeyPrefix();
        return (Id) (keyPrefix + '000000000001');
    }

    private static User delegate() {
        return [SELECT Id FROM User WHERE Email = 'deleg.rep@example.com.invalid' LIMIT 1];
    }

    @TestSetup
    static void setup() {
        Profile p = [SELECT Id FROM Profile LIMIT 1];
        String uniq = 'deleg' + String.valueOf(Datetime.now().getTime());
        insert new User(
            FirstName = 'Deleg',
            LastName = 'Rep',
            Email = 'deleg.rep@example.com.invalid',
            Username = uniq + '@example.com.invalid',
            Alias = 'delg',
            CommunityNickname = uniq.left(40),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
    }

    @IsTest
    static void activeDelegation_grantsTerritoryReach() {
        Id rep = delegate().Id;
        Id terr = fakeTerritoryId();

        Test.startTest();
        DelegationService.createDelegation(rep, terr, Date.today().addDays(-1), Date.today().addDays(30), 'cover leave');
        Test.stopTest();

        System.assert(DelegationService.isActiveDelegate(rep), 'Delegation within window is active');
        Set<Id> territoryIds = DelegationService.getActiveDelegatedTerritoryIds(rep);
        System.assert(territoryIds.contains(terr), 'Delegated territory resolved');
        // No UserTerritory2Association seeded, so no rep is managed yet.
        System.assertEquals(false, DelegationService.canActAsManagerFor(rep, UserInfo.getUserId()));
    }

    @IsTest
    static void futureDelegation_isNotActive() {
        Id rep = delegate().Id;
        DelegationService.createDelegation(rep, fakeTerritoryId(), Date.today().addDays(5), Date.today().addDays(30), null);

        Test.startTest();
        Boolean active = DelegationService.isActiveDelegate(rep);
        Test.stopTest();

        System.assertEquals(false, active, 'Delegation starting in the future is not yet active');
        System.assert(DelegationService.getActiveDelegatedTerritoryIds(rep).isEmpty());
    }

    @IsTest
    static void revoke_deactivatesDelegation() {
        Id rep = delegate().Id;
        Delegation__c d = DelegationService.createDelegation(rep, fakeTerritoryId(), Date.today(), Date.today().addDays(10), null);

        Test.startTest();
        DelegationService.revoke(d.Id);
        Test.stopTest();

        System.assertEquals(false, DelegationService.isActiveDelegate(rep), 'Revoked delegation is inactive');
    }

    @IsTest
    static void validations_rejectBadInput() {
        Id rep = delegate().Id;
        try {
            DelegationService.createDelegation(UserInfo.getUserId(), null, null, null, null);
            System.assert(false, 'Self-delegation should fail');
        } catch (DelegationService.DelegationException ex) {
            System.assert(ex.getMessage().contains('yourself'));
        }
        try {
            DelegationService.createDelegation(rep, null, Date.today(), Date.today().addDays(-1), null);
            System.assert(false, 'End before start should fail');
        } catch (DelegationService.DelegationException ex) {
            System.assert(ex.getMessage().contains('End date'));
        }
        try {
            DelegationService.createDelegation(null, null, null, null, null);
            System.assert(false, 'Null delegate should fail');
        } catch (DelegationService.DelegationException ex) {
            System.assert(ex.getMessage().contains('delegate'));
        }
    }

    @IsTest
    static void listers_returnScopedRows() {
        Id rep = delegate().Id;
        DelegationService.createDelegation(rep, fakeTerritoryId(), Date.today(), Date.today().addDays(10), 'n');

        Test.startTest();
        List<Delegation__c> granted = DelegationService.getDelegationsAsDelegator();
        List<Delegation__c> received = DelegationService.getDelegationsAsDelegate();
        Test.stopTest();

        System.assertEquals(1, granted.size(), 'Running user granted one delegation');
        System.assertEquals(0, received.size(), 'Running user received none');
    }

    @IsTest
    static void controller_delegatesAndSurfacesErrors() {
        Id rep = delegate().Id;

        Test.startTest();
        Id id = DelegationController.inviteDelegate(rep, fakeTerritoryId(), Date.today(), Date.today().addDays(10), 'ctrl');
        List<Delegation__c> granted = DelegationController.getDelegationsGranted();
        List<Delegation__c> received = DelegationController.getDelegationsReceived();
        DelegationController.revokeDelegation(id);
        Test.stopTest();

        System.assertNotEquals(null, id);
        System.assert(!granted.isEmpty());
        System.assertNotEquals(null, received);

        try {
            DelegationController.inviteDelegate(null, null, null, null, null);
            System.assert(false, 'Expected controller to surface an error');
        } catch (Exception ex) {
            System.assert(true);
        }
    }
}