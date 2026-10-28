@IsTest
private class AccountMasterImportUtilTest {
    @IsTest
    static void workplaceAndHelpers_coverCoreMapping() {
        System.assertEquals(true, AccountMasterImportUtil.isWorkplaceDoctorName('Dusit'));
        System.assertEquals(true, AccountMasterImportUtil.isWorkplaceDoctorName('Tharwa'));
        System.assertEquals(true, AccountMasterImportUtil.isWorkplaceDoctorName('UCP Site'));
        System.assertEquals(true, AccountMasterImportUtil.isWorkplaceDoctorName('ABB'));
        System.assertEquals(true, AccountMasterImportUtil.isWorkplaceDoctorName('P.M.S'));
        System.assertEquals(true, AccountMasterImportUtil.isWorkplaceDoctorName('E GAS'));
        System.assertEquals(true, AccountMasterImportUtil.isWorkplaceDoctorName('Mohamed Ahmed'));
        System.assertEquals(true, AccountMasterImportUtil.isWorkplaceDoctorName('ABB New Cairo'));
        // ??? (workplace prefix) built from code points to keep source ASCII-safe
        String qism = String.fromCharArray(new List<Integer>{ 1602, 1587, 1605 });
        System.assertEquals(true, AccountMasterImportUtil.isWorkplaceDoctorName(qism + ' ER'));
        System.assertEquals(false, AccountMasterImportUtil.isWorkplaceDoctorName(null));
        System.assertEquals(false, AccountMasterImportUtil.isWorkplaceDoctorName('   '));

        System.assertEquals('DOC-921', AccountMasterImportUtil.doctorExternalId('921'));
        System.assertEquals('CLINIC-12', AccountMasterImportUtil.clinicExternalId('12'));
        System.assertEquals(
            'AFF-DOC-921-CLINIC-12',
            AccountMasterImportUtil.affiliationExternalId('921', 'CLINIC-12')
        );
        System.assertEquals('Andrology', AccountMasterImportUtil.mapSpecialty('Andro'));
        System.assertEquals(null, AccountMasterImportUtil.mapSpecialty('UnknownSpec'));
        System.assertEquals('A', AccountMasterImportUtil.mapTierFromClass('A1'));
        System.assertEquals('B', AccountMasterImportUtil.mapTierFromClass('B2'));
        System.assertEquals('C', AccountMasterImportUtil.mapTierFromClass('C3'));
        System.assertEquals(null, AccountMasterImportUtil.mapTierFromClass(null));
        System.assertEquals(null, AccountMasterImportUtil.mapTierFromClass('XYZ'));

        Account person = new Account();
        AccountMasterImportUtil.splitPersonName('Mohamed Ahmed Ali', person);
        System.assertEquals('Mohamed', person.FirstName);
        System.assertEquals('Ahmed Ali', person.LastName);
        AccountMasterImportUtil.splitPersonName('Solo', person);
        System.assertEquals('Solo', person.LastName);
        AccountMasterImportUtil.splitPersonName('  ', person);
        System.assertEquals('Unknown', person.LastName);
        AccountMasterImportUtil.splitPersonName(null, person);
        System.assertEquals('Unknown', person.LastName);

        System.assertNotEquals(null, AccountMasterImportUtil.normalizePhone('01001234567'));
        System.assertEquals(null, AccountMasterImportUtil.normalizePhone(null));
        System.assertEquals(null, AccountMasterImportUtil.normalizePhone('abc'));
        System.assertEquals('Clean Name', AccountMasterImportUtil.cleanPrefixedAccountName('1000027554_Clean Name'));
        System.assertEquals('NoPrefix', AccountMasterImportUtil.cleanPrefixedAccountName('NoPrefix'));
        System.assertEquals('x_y', AccountMasterImportUtil.cleanPrefixedAccountName('x_y'));
        System.assertEquals(null, AccountMasterImportUtil.cleanPrefixedAccountName(null));
        System.assertEquals('1000027554', AccountMasterImportUtil.pharmacyCodeFromName('1000027554_Clean Name'));
        System.assertEquals(null, AccountMasterImportUtil.pharmacyCodeFromName('x_y'));
        System.assertEquals(null, AccountMasterImportUtil.pharmacyCodeFromName(null));
        System.assertEquals('7_Name', AccountMasterImportUtil.pharmacyMasterName('7', 'Name'));
        System.assertEquals('Name', AccountMasterImportUtil.pharmacyMasterName(null, 'Name'));
        System.assertEquals('IM', AccountMasterImportUtil.excelSpecialty('Internal_Medicine'));
        System.assertEquals(null, AccountMasterImportUtil.excelSpecialty('Unknown_Value'));
        System.assertEquals(null, AccountMasterImportUtil.excelSpecialty(null));

        String clinicName = AccountMasterImportUtil.clinicDisplayName('Doctor', 'Maadi', '99', null);
        System.assert(clinicName.contains('Maadi'));
        System.assert(AccountMasterImportUtil.clinicDisplayName(null, null, '99', null).contains('99'));

        System.assertEquals(true, AccountMasterImportUtil.toBoolean('true', false));
        System.assertEquals(true, AccountMasterImportUtil.toBoolean(true, false));
        System.assertEquals(true, AccountMasterImportUtil.toBoolean('1', false));
        System.assertEquals(true, AccountMasterImportUtil.toBoolean('yes', false));
        System.assertEquals(false, AccountMasterImportUtil.toBoolean('false', true));
        System.assertEquals(false, AccountMasterImportUtil.toBoolean('0', true));
        System.assertEquals(false, AccountMasterImportUtil.toBoolean('no', true));
        System.assertEquals(true, AccountMasterImportUtil.toBoolean(null, true));
        System.assertEquals(false, AccountMasterImportUtil.toBoolean('maybe', false));

        Id clinicRt = AccountMasterImportUtil.clinicHcpRecordTypeId();
        System.assertNotEquals(null, clinicRt);
        System.assertEquals(false, AccountMasterImportUtil.isPersonRecordType(clinicRt));
        System.assertEquals(false, AccountMasterImportUtil.isPersonRecordType(null));
    }
}