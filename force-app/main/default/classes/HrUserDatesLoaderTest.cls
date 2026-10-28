@IsTest
private class HrUserDatesLoaderTest {
    @IsTest
    static void backfillsHireResignationAndLastDayByEmployeeNumber() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
        User u = new User(
            Alias = 'hrdt', Email = 'hrdt' + uniq + '@example.com', Username = 'hrdt' + uniq + '@example.com.zeta',
            LastName = 'Hr', EmployeeNumber = 'HR7001', TimeZoneSidKey = 'Africa/Cairo', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', ProfileId = p.Id,
            Hire_Date__c = Date.newInstance(2020, 1, 1), Resignation_Date__c = Date.newInstance(2026, 1, 1)
        );
        Database.insert(u, AccessLevel.SYSTEM_MODE);

        HrUserDatesLoader.LoadResult first = HrUserDatesLoader.apply(
            new List<HrUserDatesLoader.HrRow>{
                new HrUserDatesLoader.HrRow('HR7001', '2022-02-01', '2026-09-01', '2026-10-01'),
                new HrUserDatesLoader.HrRow('NOBODY', '2022-02-01', '', '')
            },
            false
        );
        System.assertEquals(2, first.rowsRead);
        System.assertEquals(1, first.usersMatched);
        System.assertEquals(1, first.noUser);
        System.assertEquals(1, first.usersUpdated);
        User saved = [SELECT Hire_Date__c, Resignation_Date__c, Last_Work_Day__c FROM User WHERE Id = :u.Id WITH SYSTEM_MODE];
        System.assertEquals(Date.newInstance(2022, 2, 1), saved.Hire_Date__c);
        System.assertEquals(Date.newInstance(2026, 9, 1), saved.Resignation_Date__c);
        System.assertEquals(Date.newInstance(2026, 10, 1), saved.Last_Work_Day__c);

        // Blank HR dates do not wipe what is there unless clearBlanks is set.
        HrUserDatesLoader.LoadResult keep = HrUserDatesLoader.apply(
            new List<HrUserDatesLoader.HrRow>{ new HrUserDatesLoader.HrRow('HR7001', '', '', '') },
            false
        );
        System.assertEquals(0, keep.usersUpdated);
        System.assertEquals(Date.newInstance(2026, 9, 1), [SELECT Resignation_Date__c FROM User WHERE Id = :u.Id WITH SYSTEM_MODE].Resignation_Date__c);
        HrUserDatesLoader.LoadResult cleared = HrUserDatesLoader.apply(
            new List<HrUserDatesLoader.HrRow>{ new HrUserDatesLoader.HrRow('HR7001', '', '', '') },
            true
        );
        System.assertEquals(1, cleared.usersUpdated);
        System.assertEquals(null, [SELECT Resignation_Date__c FROM User WHERE Id = :u.Id WITH SYSTEM_MODE].Resignation_Date__c);
    }

    @IsTest
    static void emptyInputIsHarmless() {
        System.assertEquals(0, HrUserDatesLoader.apply(null, false).rowsRead);
        System.assertEquals(0, HrUserDatesLoader.apply(new List<HrUserDatesLoader.HrRow>(), false).usersMatched);
    }

    @IsTest
    static void staticResourceLoadRunsEndToEnd() {
        // The shipped HR master is read in full; in a test org no user matches its codes except by chance.
        HrUserDatesLoader.LoadResult res = HrUserDatesLoader.loadFromStaticResource();
        System.assertNotEquals(null, res);
        HrUserDatesLoader.LoadResult resClear = HrUserDatesLoader.loadFromStaticResource(false);
        System.assertEquals(res.rowsRead, resClear.rowsRead);
        System.assertEquals(null, HrUserDatesLoader.apply(new List<HrUserDatesLoader.HrRow>{ new HrUserDatesLoader.HrRow(null, 'bad', 'bad', 'bad') }, false).messages.isEmpty() ? null : 'unexpected');
    }
}
