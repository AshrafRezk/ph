@IsTest
private class FieldBookAccessTest {
    @IsTest
    static void systemAdminCanOpenTheFullBook() {
        FieldBookAccess.BookMode mode = FieldBookAccess.getBookMode();
        System.assertEquals(false, FieldBookAccess.restrictsToOwnBook());
        System.assertEquals(true, FieldBookAccess.canAdministerSales());
        System.assertEquals(false, mode.ownBookOnly);
        System.assertEquals(true, mode.canOpenFullBook);
    }

    @IsTest
    static void medicalRepIsLimitedToOwnBook() {
        User rep = userWithTitle('Medical Rep');
        insert rep;
        System.runAs(rep) {
            System.assertEquals(true, FieldBookAccess.restrictsToOwnBook());
            System.assertEquals(false, FieldBookAccess.canAdministerSales());
            FieldBookAccess.BookMode mode = FieldBookAccess.getBookMode();
            System.assertEquals(true, mode.ownBookOnly);
            System.assertEquals(false, mode.canOpenFullBook);
        }
    }

    @IsTest
    static void salesAdminTitlesCanChangeSetup() {
        User sfe = userWithTitle('SFE');
        insert sfe;
        System.runAs(sfe) {
            System.assertEquals(true, FieldBookAccess.canAdministerSales());
            FieldBookAccess.assertCanAdministerSales();
        }
        User rep = userWithTitle('Medical Rep');
        insert rep;
        System.runAs(rep) {
            Boolean blocked = false;
            try {
                FieldBookAccess.assertCanAdministerSales();
            } catch (AuraHandledException ex) {
                blocked = true;
            }
            System.assertEquals(true, blocked);
        }
    }

    @IsTest
    static void sfeTitleGetsTheWholeBookWithoutHeadOffice() {
        User sfe = userWithTitle('CRM & SFE Specialist');
        insert sfe;
        System.runAs(sfe) {
            System.assertEquals(true, FieldBookAccess.isSfeUser());
            System.assertEquals(false, FieldBookAccess.restrictsToOwnBook());
            FieldBookAccess.BookMode mode = FieldBookAccess.getBookMode();
            System.assertEquals(true, mode.fullBookByDefault);
            System.assertEquals(true, mode.canOpenFullBook);
        }
    }

    @IsTest
    static void wordsContainingSfeAreNotSfe() {
        User clerk = userWithTitle('Transfer Coordinator');
        insert clerk;
        System.runAs(clerk) {
            System.assertEquals(false, FieldBookAccess.isSfeUser());
            System.assertEquals(false, FieldBookAccess.getBookMode().fullBookByDefault);
        }
    }

    @IsTest
    static void demoMedicalRepUsernameIsLimitedToOwnBook() {
        User rep = userWithTitle('Coordinator');
        rep.Username = 'book' + String.valueOf(Math.abs(Crypto.getRandomInteger())) + '.mr@pharma.demo';
        insert rep;
        System.runAs(rep) {
            System.assertEquals(true, FieldBookAccess.restrictsToOwnBook());
            FieldBookAccess.BookMode mode = FieldBookAccess.getBookMode();
            System.assertEquals(true, mode.ownBookOnly);
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
            Email = 'book' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'BookAccess',
            Title = title,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Africa/Cairo',
            UserName = 'book' + suffix + '@example.com.test',
            ProfileId = standardProfile.Id
        );
    }
}
