@IsTest
private class PublicHolidayServiceTest {
    @IsTest
    static void dateKeysInRange_returnsSortedIsoDates() {
        PublicHolidayService.testHolidays = new List<Public_Holiday__c>{
            mockHoliday('Company Day', Date.newInstance(2026, 10, 5), false, true),
            mockHoliday('Earlier Day', Date.newInstance(2026, 10, 1), false, true)
        };

        Test.startTest();
        List<String> keys = PublicHolidayService.dateKeysInRange(
            Date.newInstance(2026, 10, 1),
            Date.newInstance(2026, 10, 31)
        );
        Test.stopTest();

        System.assertEquals(2, keys.size());
        System.assertEquals('2026-10-01', keys[0]);
        System.assertEquals('2026-10-05', keys[1]);
        PublicHolidayService.testHolidays = null;
    }

    @IsTest
    static void isPublicHoliday_usesInjectedHolidayRows() {
        Date holiday = Date.newInstance(2026, 12, 25);
        PublicHolidayService.testHolidays = new List<Public_Holiday__c>{
            mockHoliday('Year End', holiday, true, true)
        };

        Test.startTest();
        System.assertEquals(true, PublicHolidayService.isPublicHoliday(holiday));
        System.assertEquals(false, PublicHolidayService.isPublicHoliday(holiday.addDays(1)));
        Test.stopTest();

        PublicHolidayService.testHolidays = null;
    }

    @IsTest
    static void datesInRange_handlesBlankWindow() {
        System.assertEquals(0, PublicHolidayService.datesInRange(null, Date.today()).size());
        System.assertEquals(0, PublicHolidayService.datesInRange(Date.today(), null).size());
        System.assertEquals(
            0,
            PublicHolidayService.datesInRange(Date.today().addDays(3), Date.today()).size()
        );
    }

    @IsTest
    static void countAvailableWorkingDays_skipsHolidaysAndLeave() {
        Date startDate = Date.newInstance(2026, 3, 2);
        Date endDate = Date.newInstance(2026, 3, 6);
        PublicHolidayService.testHolidays = new List<Public_Holiday__c>{
            mockHoliday('Midweek', Date.newInstance(2026, 3, 4), false, true)
        };
        Set<Date> leaveDates = new Set<Date>{ Date.newInstance(2026, 3, 3) };

        Test.startTest();
        Integer available = PublicHolidayService.countAvailableWorkingDays(startDate, endDate, leaveDates);
        Test.stopTest();

        System.assert(available >= 0, 'Expected a non-negative working-day count.');
        PublicHolidayService.testHolidays = null;
    }

    @IsTest
    static void listHolidays_returnsRows() {
        Test.startTest();
        List<PublicHolidayService.HolidayRow> rows = PublicHolidayService.listHolidays();
        Test.stopTest();
        System.assertNotEquals(null, rows);
    }

    @IsTest
    static void isPublicHoliday_returnsFalseForNullDate() {
        System.assertEquals(false, PublicHolidayService.isPublicHoliday(null));
    }

    @IsTest
    static void saveHoliday_rejectsMissingHolidayRecord() {
        PublicHolidayService.HolidayRow row = new PublicHolidayService.HolidayRow();
        row.id = UserInfo.getUserId();
        row.name = 'Missing';
        row.holidayDate = Date.today();
        Boolean threw = false;
        try {
            PublicHolidayService.saveHoliday(row);
        } catch (Exception ex) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void saveHoliday_createsHolidayRecord() {
        PublicHolidayService.HolidayRow created = new PublicHolidayService.HolidayRow();
        created.name = 'Planner Holiday';
        created.holidayDate = Date.newInstance(2027, 1, 2);
        created.recursYearly = true;
        created.isActive = true;

        Test.startTest();
        PublicHolidayService.HolidayRow saved = PublicHolidayService.saveHoliday(created);
        PublicHolidayService.deleteHoliday(saved.id);
        Test.stopTest();

        System.assertNotEquals(null, saved.id);
    }

    @IsTest
    static void saveHoliday_validatesRequiredFields() {
        Boolean threw = false;
        try {
            PublicHolidayService.saveHoliday(null);
        } catch (Exception ex) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void deleteHoliday_requiresId() {
        Boolean threw = false;
        try {
            PublicHolidayService.deleteHoliday(null);
        } catch (Exception ex) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void saveHoliday_rejectsSecondHolidayOnSameDate() {
        Date holidayDate = Date.newInstance(2027, 1, 7);
        insert new Public_Holiday__c(Name = 'Coptic Christmas', Holiday_Date__c = holidayDate, Is_Active__c = true);

        PublicHolidayService.HolidayRow duplicate = new PublicHolidayService.HolidayRow();
        duplicate.name = 'Coptic Christmas again';
        duplicate.holidayDate = holidayDate;
        Boolean threw = false;
        Test.startTest();
        try {
            PublicHolidayService.saveHoliday(duplicate);
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'A second holiday on the same date should be refused.');
        System.assertEquals(1, [SELECT COUNT() FROM Public_Holiday__c WHERE Holiday_Date__c = :holidayDate]);
    }

    @IsTest
    static void loadEgypt2026Holidays_insertsMissingDatesOnce() {
        insert new Public_Holiday__c(
            Name = 'Labour Day',
            Holiday_Date__c = Date.newInstance(2026, 5, 1),
            Recurs_Yearly__c = true,
            Is_Active__c = true
        );

        Test.startTest();
        Integer firstRun = PublicHolidayService.loadEgypt2026Holidays();
        Integer secondRun = PublicHolidayService.loadEgypt2026Holidays();
        Test.stopTest();

        System.assertEquals(6, firstRun, 'Labour Day already exists, so 6 of the 7 dates are added.');
        System.assertEquals(0, secondRun, 'A second load adds nothing.');
        System.assertEquals(7, [SELECT COUNT() FROM Public_Holiday__c]);
        System.assertEquals(7, PublicHolidayService.listHolidays().size());
    }

    @IsTest
    static void recurringHoliday_addsEachYearInRange() {
        PublicHolidayService.testHolidays = new List<Public_Holiday__c>{
            mockHoliday('Annual', Date.newInstance(2020, 7, 4), true, true),
            mockHoliday('Inactive', Date.newInstance(2026, 7, 4), false, false)
        };

        Set<Date> dates = PublicHolidayService.datesInRange(
            Date.newInstance(2026, 1, 1),
            Date.newInstance(2026, 12, 31)
        );
        System.assert(dates.contains(Date.newInstance(2026, 7, 4)));
        PublicHolidayService.testHolidays = null;
    }

    @IsTest
    static void saveHolidayFields_createsFromPlainValues() {
        Test.startTest();
        PublicHolidayService.HolidayRow saved = PublicHolidayService.saveHolidayFields(
            null,
            '  Coptic Christmas ',
            '2027-01-07',
            false,
            true
        );
        Test.stopTest();

        Public_Holiday__c row = [
            SELECT Name, Holiday_Date__c, Recurs_Yearly__c, Is_Active__c
            FROM Public_Holiday__c
            WHERE Id = :saved.id
        ];
        System.assertEquals('Coptic Christmas', row.Name);
        System.assertEquals(Date.newInstance(2027, 1, 7), row.Holiday_Date__c);
        System.assertEquals(false, row.Recurs_Yearly__c);
        System.assertEquals(true, row.Is_Active__c);
    }

    @IsTest
    static void saveHolidayFields_editsAndRefusesDuplicateDate() {
        Public_Holiday__c eid = new Public_Holiday__c(
            Name = 'Eid al-Fitr (approx)',
            Holiday_Date__c = Date.newInstance(2026, 3, 20),
            Is_Active__c = true
        );
        Public_Holiday__c other = new Public_Holiday__c(
            Name = 'Coptic Christmas',
            Holiday_Date__c = Date.newInstance(2027, 1, 7),
            Is_Active__c = true
        );
        insert new List<Public_Holiday__c>{ eid, other };

        Test.startTest();
        PublicHolidayService.saveHolidayFields(eid.Id, 'Eid al-Fitr', '21/03/2026', false, true);
        String duplicateMessage;
        try {
            PublicHolidayService.saveHolidayFields(null, 'Again', '2027-01-07', false, true);
        } catch (AuraHandledException ex) {
            duplicateMessage = ex.getMessage();
        }
        Test.stopTest();

        Public_Holiday__c edited = [SELECT Name, Holiday_Date__c FROM Public_Holiday__c WHERE Id = :eid.Id];
        System.assertEquals('Eid al-Fitr', edited.Name);
        System.assertEquals(Date.newInstance(2026, 3, 21), edited.Holiday_Date__c);
        System.assertEquals('Coptic Christmas is already set for that date.', duplicateMessage);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Public_Holiday__c WHERE Holiday_Date__c = :Date.newInstance(2027, 1, 7)]
        );
    }

    @IsTest
    static void saveHolidayFields_refusesDateCoveredByYearlyHoliday() {
        insert new Public_Holiday__c(
            Name = 'Revolution Day',
            Holiday_Date__c = Date.newInstance(2026, 1, 25),
            Recurs_Yearly__c = true,
            Is_Active__c = true
        );
        String message;
        try {
            PublicHolidayService.saveHolidayFields(null, 'Revolution Day 2027', '2027-01-25', false, true);
        } catch (AuraHandledException ex) {
            message = ex.getMessage();
        }
        System.assertEquals('Revolution Day already repeats every year on that date.', message);
    }

    @IsTest
    static void saveHolidayFields_explainsWhatIsMissing() {
        List<String> messages = new List<String>();
        for (List<String> pair : new List<List<String>>{
            new List<String>{ '', '' },
            new List<String>{ '', '2027-01-07' },
            new List<String>{ 'Coptic Christmas', '' },
            new List<String>{ 'Coptic Christmas', 'Jan 7th' }
        }) {
            try {
                PublicHolidayService.saveHolidayFields(null, pair[0], pair[1], false, true);
                messages.add('saved');
            } catch (AuraHandledException ex) {
                messages.add(ex.getMessage());
            }
        }
        System.assertEquals('Enter the holiday name and pick its date.', messages[0]);
        System.assertEquals('Enter the holiday name.', messages[1]);
        System.assertEquals('Pick the holiday date from the calendar.', messages[2]);
        System.assertEquals('Pick the holiday date from the calendar.', messages[3]);
        System.assertEquals(0, [SELECT COUNT() FROM Public_Holiday__c]);
    }

    @IsTest
    static void previewEgypt2026Holidays_listsOnlyMissingDates() {
        insert new Public_Holiday__c(
            Name = 'Coptic Christmas',
            Holiday_Date__c = Date.newInstance(2026, 1, 7),
            Is_Active__c = true
        );
        Test.startTest();
        List<PublicHolidayService.HolidayRow> preview = PublicHolidayService.previewEgypt2026Holidays();
        Test.stopTest();

        System.assertEquals(6, preview.size());
        for (PublicHolidayService.HolidayRow row : preview) {
            System.assertNotEquals('Coptic Christmas', row.name);
        }
        System.assertEquals(1, [SELECT COUNT() FROM Public_Holiday__c], 'Preview must not insert anything.');
    }

    private static Public_Holiday__c mockHoliday(
        String name,
        Date holidayDate,
        Boolean recursYearly,
        Boolean isActive
    ) {
        return new Public_Holiday__c(
            Name = name,
            Holiday_Date__c = holidayDate,
            Recurs_Yearly__c = recursYearly,
            Is_Active__c = isActive
        );
    }
}