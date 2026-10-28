@IsTest
private class FieldLoginAsControllerTest {
    private static User fieldUser(Boolean active) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User u = new User(
            Alias = 'fla' + stamp.left(4),
            Email = 'fla' + stamp + '@example.com',
            Username = 'fla' + stamp + '@zeta.test',
            LastName = 'Field Rep',
            FirstName = 'Test',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = active
        );
        insert u;
        return u;
    }

    @IsTest
    static void startsSessionAndLogs() {
        User rep = fieldUser(true);
        FieldLoginAsController.mockTokenResponse =
            '{"access_token":"00Dtoken!abc","instance_url":"https://zetapharma.my.salesforce.com","issued_at":"1761465600000"}';

        Test.startTest();
        FieldLoginAsController.LoginAsResult result = FieldLoginAsController.startFieldSession(rep.Id, 'Wave E retest');
        Test.stopTest();

        Assert.isTrue(result.fieldAppUrl.startsWith('https://www.salesforceoffline.com/#login-as&access_token=00Dtoken'));
        Assert.isTrue(result.fieldAppUrl.contains('&as=Test+Field+Rep'));
        Field_Login_As_Log__c log = [SELECT Target_User__c, Status__c, Reason__c FROM Field_Login_As_Log__c LIMIT 1];
        Assert.areEqual(rep.Id, log.Target_User__c);
        Assert.areEqual('Started', log.Status__c);
        Assert.areEqual('Wave E retest', log.Reason__c);
    }

    @IsTest
    static void refusesInactiveUser() {
        User rep = fieldUser(false);
        FieldLoginAsController.LoginAsResult result = FieldLoginAsController.startFieldSession(rep.Id, 'QA');
        Assert.isTrue(result.error.contains('inactive'));
        Assert.isNull(result.fieldAppUrl);
        Assert.areEqual('Refused', [SELECT Status__c FROM Field_Login_As_Log__c LIMIT 1].Status__c);
    }

    @IsTest
    static void refusesSelfAndBlankReason() {
        User rep = fieldUser(true);
        try {
            FieldLoginAsController.startFieldSession(UserInfo.getUserId(), 'QA');
            Assert.fail('Expected refusal for self');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        try {
            FieldLoginAsController.startFieldSession(rep.Id, '  ');
            Assert.fail('Expected refusal for blank reason');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void refusesAdministratorsAndMissingUsers() {
        User admin = fieldUser(true);
        admin.ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        update admin;
        FieldLoginAsController.LoginAsResult refused = FieldLoginAsController.startFieldSession(admin.Id, 'QA');
        Assert.isTrue(refused.error.contains('administrator'));
        Assert.areEqual('Refused', [SELECT Status__c FROM Field_Login_As_Log__c LIMIT 1].Status__c);
        try {
            FieldLoginAsController.startFieldSession(null, 'QA');
            Assert.fail('Expected refusal for null user');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        try {
            FieldLoginAsController.startFieldSession('005000000000000AAA', 'QA');
            Assert.fail('Expected refusal for unknown user');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void fillsMissingInstanceAndIssuedAt() {
        User rep = fieldUser(true);
        FieldLoginAsController.mockTokenResponse = '{"access_token":"00Dtoken!xyz"}';
        FieldLoginAsController.LoginAsResult result = FieldLoginAsController.startFieldSession(rep.Id, 'QA');
        Assert.isTrue(result.fieldAppUrl.contains('&instance_url=https'));
        Assert.isNull(result.error);
        Assert.isTrue(FieldLoginAsController.explainTokenFailure('Rep', 'timeout').startsWith('Could not open'));
    }

    @IsTest
    static void logsTokenFailure() {
        User rep = fieldUser(true);
        FieldLoginAsController.mockTokenResponse =
            '{"error":"invalid_grant","error_description":"user hasn\'t approved this consumer"}';
        FieldLoginAsController.LoginAsResult result = FieldLoginAsController.startFieldSession(rep.Id, 'QA');
        Assert.isTrue(result.error.contains('has not approved'), result.error);
        Assert.isNull(result.fieldAppUrl);
        Field_Login_As_Log__c log = [SELECT Status__c, Detail__c FROM Field_Login_As_Log__c LIMIT 1];
        Assert.areEqual('Failed', log.Status__c);
        Assert.areEqual('invalid_grant: user hasn\'t approved this consumer', log.Detail__c);
    }

    @IsTest
    static void explainsSignatureAndOtherFailures() {
        User rep = fieldUser(true);
        FieldLoginAsController.mockTokenResponse =
            '{"error":"invalid_grant","error_description":"invalid assertion"}';
        FieldLoginAsController.LoginAsResult result = FieldLoginAsController.startFieldSession(rep.Id, 'QA');
        Assert.isTrue(result.error.contains('Use digital signatures'), result.error);
        Assert.isTrue(result.error.contains('invalid_grant: invalid assertion'), result.error);
        Assert.isTrue(FieldLoginAsController.explainTokenFailure('Rep', 'invalid_grant: audience is invalid').contains('audience'));
        Assert.isTrue(FieldLoginAsController.explainTokenFailure('Rep', 'invalid_client_id: client identifier invalid').contains('consumer key'));

        FieldLoginAsController.mockTokenResponse = '<html>gateway error</html>';
        FieldLoginAsController.LoginAsResult garbled = FieldLoginAsController.startFieldSession(rep.Id, 'QA');
        Assert.isTrue(garbled.error.contains('Unexpected token response'), garbled.error);
    }
}
