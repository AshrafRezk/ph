@IsTest
private class FieldAccountSearchTest {
    @IsTest
    static void searchFindsLiteralAndCompoundNames() {
        Account latin = new Account(Name = 'Abdelhamid Lookup QA');
        Account arabic = new Account(Name = '\u0639\u0628\u062F \u0627\u0644\u062D\u0645\u064A\u062F Lookup QA');
        insert new List<Account>{ latin, arabic };

        Test.startTest();
        List<FieldAccountSearch.Hit> literal = FieldAccountSearch.search('Lookup QA');
        List<FieldAccountSearch.Hit> compound = FieldAccountSearch.search('abd elham');
        List<FieldAccountSearch.Hit> empty = FieldAccountSearch.search('a');
        Test.stopTest();

        System.assert(containsId(literal, latin.Id), 'Literal search should find the Latin account.');
        System.assert(containsId(compound, latin.Id), 'abd elham should find Abdelhamid.');
        System.assert(containsId(compound, arabic.Id), 'abd elham should find the Arabic spelling.');
        System.assertEquals(0, empty.size());
        System.assertEquals('standard:person_account', FieldAccountSearch.iconFor('PersonAccount'));
        System.assertEquals('standard:household', FieldAccountSearch.iconFor('Pharmacy'));
        System.assertEquals('standard:account', FieldAccountSearch.iconFor('Institution_HCO'));
        System.assertEquals('standard:contact', FieldAccountSearch.iconFor('Business_Contact'));
        System.assert(!AccountNameRomanizer.prefixVariants('abdelham', 4).isEmpty());
    }

    private static Boolean containsId(List<FieldAccountSearch.Hit> hits, Id accountId) {
        if (hits == null) {
            return false;
        }
        for (FieldAccountSearch.Hit hit : hits) {
            if (hit.accountId == accountId) {
                return true;
            }
        }
        return false;
    }
}
