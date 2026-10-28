@IsTest
private class ZetaCommercialUserLoaderTest {
    @IsTest
    static void passwordUsesFirstName() {
        System.assertEquals('Mayar@2026!', ZetaCommercialUserLoader.passwordFor('Mayar Ashraf Mohamed'));
        System.assertEquals('User@2026!', ZetaCommercialUserLoader.passwordFor(null));
        System.assertEquals('AbdEl@2026!', ZetaCommercialUserLoader.passwordFor('Abd-El Rahman'));
    }

    @IsTest
    static void chunkCreatesUserWithoutChaining() {
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        ZetaCommercialUserLoader.testEmployeesJson =
            '[{"code":"T' + uniq + '","name":"Mayar Ashraf","title":"Medical Representative","department":"Sales","line":"GIT II","managerCode":"","email":"mayar.loader.' +
            uniq +
            '@zeta-pharma.com","mobile":"01000000000"}]';
        ZetaCommercialUserLoader.skipChain = true;

        Test.startTest();
        new ZetaCommercialUserLoader().execute(null);
        Test.stopTest();

        User created = [
            SELECT FirstName, LastName, EmployeeNumber, IsActive, Profile.Name
            FROM User
            WHERE Username = :('mayar.loader.' + uniq + '@zeta-pharma.com')
        ];
        System.assertEquals('Mayar', created.FirstName);
        System.assertEquals('Ashraf', created.LastName);
        System.assertEquals('T' + uniq, created.EmployeeNumber);
        System.assertEquals(true, created.IsActive);
        System.assertEquals('Standard User', created.Profile.Name);
    }

    @IsTest
    static void loadAssignsManagerAndResetsPassword() {
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String managerEmail = 'nader.loader.' + uniq + '@zeta-pharma.com';
        String repEmail = 'mayar.mgr.' + uniq + '@zeta-pharma.com';
        ZetaCommercialUserLoader.testEmployeesJson =
            '[{"code":"","name":"","title":"","department":"","line":"","managerCode":"","email":"","mobile":""},' +
            '{"code":"M' + uniq + '","name":"Nader","title":"National Sales Manager","department":"Sales","line":"GIT II","managerCode":"","email":"' +
            managerEmail +
            '","mobile":""},' +
            '{"code":"R' + uniq + '","name":"Mayar Ashraf Mohamed Ibrahim Extra Name That Is Quite Long For A Last Name Field In Salesforce User Records Today","title":"Medical Representative","department":"Sales","line":"GIT II","managerCode":"M' +
            uniq +
            '","email":"' +
            repEmail +
            '","mobile":"01011111111"}]';
        ZetaCommercialUserLoader.skipChain = true;

        Test.startTest();
        new ZetaCommercialUserLoader().execute(null);
        new ZetaCommercialUserLoader().execute(null);
        ZetaCommercialUserLoader.executePhase('managers');
        ZetaCommercialUserLoader.executePhase('passwords');
        Test.stopTest();

        User rep = [SELECT Manager.EmployeeNumber FROM User WHERE Username = :repEmail];
        System.assertEquals('M' + uniq, rep.Manager.EmployeeNumber);
        System.assertEquals(
            true,
            ZetaCommercialUserLoader.isIntegration(new User(Username = 'insights@example.ext'))
        );
    }

    @IsTest
    static void deltaUpdatesExistingUserWithoutPasswordPhase() {
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String managerEmail = 'delta.mgr.' + uniq + '@zeta-pharma.com';
        String repEmail = 'delta.rep.' + uniq + '@zeta-pharma.com';
        ZetaCommercialUserLoader.testDeltaJson =
            '[{"code":"DM' + uniq + '","name":"Nader Khaled","title":"Group Brand Lead","department":"Marketing","line":"","managerCode":"","email":"' +
            managerEmail +
            '","mobile":""},{"code":"DR' + uniq + '","name":"Rwan Ashraf","title":"Brand Manager","department":"Marketing","line":"GIT I","managerCode":"DM' +
            uniq +
            '","email":"' +
            repEmail +
            '","mobile":"1020000000"}]';

        ZetaCommercialUserLoader.skipChain = true;
        Test.startTest();
        ZetaCommercialUserLoader.executePhase('delta');
        ZetaCommercialUserLoader.executePhase('deltaManagers');
        Test.stopTest();

        User rep = [
            SELECT Title, Manager.EmployeeNumber, Department
            FROM User
            WHERE Username = :repEmail
        ];
        System.assertEquals('Brand Manager', rep.Title);
        System.assertEquals('DM' + uniq, rep.Manager.EmployeeNumber);
        System.assertEquals('Marketing', rep.Department);

        String renamed = 'delta.rep.renamed.' + uniq + '@zeta-pharma.com';
        ZetaCommercialUserLoader.testDeltaJson =
            '[{"code":"DR' + uniq + '","name":"Rwan Ashraf","title":"Brand Manager","department":"Marketing","line":"","managerCode":"DM' +
            uniq +
            '","email":"' +
            renamed +
            '","mobile":""}]';
        ZetaCommercialUserLoader.executePhase('delta');

        User updated = [
            SELECT Username, Division
            FROM User
            WHERE EmployeeNumber = :('DR' + uniq)
        ];
        System.assertEquals(renamed, updated.Username);
        System.assertEquals(true, String.isBlank(updated.Division));
    }
}
