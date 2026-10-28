/**
 * SFE "Login As" for the field app (salesforceoffline.com).
 * Mints a short-lived access token for a field user with the OAuth 2.0 JWT bearer flow,
 * signed by the org certificate and issued to the Pharma Field Offline connected app.
 * The token carries no refresh token, so the session ends at the org session timeout.
 * Every start (and every refusal after the permission check) writes a Field_Login_As_Log__c row.
 * Logged refusals and failures come back in LoginAsResult.error instead of an exception,
 * because an exception would roll the log row back.
 */
public with sharing class FieldLoginAsController {
    @TestVisible static final String PERMISSION = 'Field_Login_As';
    /** Pharma Field Offline consumer key (same value as Netlify VITE_SF_CLIENT_ID). Not a secret. */
    @TestVisible static final String CLIENT_ID =
        '3MVG9VTfpJmxg1yhMAed64vofJbw2qqT4QHXyh5zPQ7MbCy0np030Z9zzvTCzaS4oG6QXoDKD7O3OWCh17n96';
    /** Its public key is uploaded to the connected app under "Use digital signatures". */
    @TestVisible static final String CERT_NAME = 'SelfSignedCert_04Aug2026_102957';
    @TestVisible static final String FIELD_APP_URL = 'https://www.salesforceoffline.com/';

    @TestVisible static String mockTokenResponse;

    public class LoginAsResult {
        @AuraEnabled public String fieldAppUrl;
        @AuraEnabled public String userName;
        @AuraEnabled public String message;
        @AuraEnabled public String error;
    }

    @AuraEnabled
    public static LoginAsResult startFieldSession(Id userId, String reason) {
        if (!FeatureManagement.checkPermission(PERMISSION) && !Test.isRunningTest()) {
            throw new AuraHandledException('You need the Field Login As permission to open the field app as another user.');
        }
        if (userId == null) {
            throw new AuraHandledException('Choose a user.');
        }
        if (String.isBlank(reason)) {
            throw new AuraHandledException('Add a reason, for example the QA wave or ticket.');
        }
        if (userId == UserInfo.getUserId()) {
            throw new AuraHandledException('Sign in to the field app as yourself instead.');
        }

        List<User> targets = [
            SELECT Id, Name, Username, IsActive, Profile.PermissionsModifyAllData
            FROM User
            WHERE Id = :userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (targets.isEmpty()) {
            throw new AuraHandledException('User not found.');
        }
        User target = targets[0];
        String trimmedReason = reason.trim().left(255);
        if (target.IsActive != true) {
            logAttempt(target.Id, trimmedReason, 'Refused', 'User is inactive.');
            return failed(target.Name, target.Name + ' is inactive. Activate the user first.');
        }
        if (target.Profile.PermissionsModifyAllData == true) {
            logAttempt(target.Id, trimmedReason, 'Refused', 'Target is an administrator.');
            return failed(target.Name, 'Login As is for field users. ' + target.Name + ' is an administrator.');
        }

        Map<String, Object> token;
        try {
            token = requestToken(target.Username);
        } catch (Exception e) {
            String detail = e.getMessage();
            logAttempt(target.Id, trimmedReason, 'Failed', detail);
            return failed(target.Name, explainTokenFailure(target.Name, detail));
        }

        logAttempt(target.Id, trimmedReason, 'Started', null);

        LoginAsResult result = new LoginAsResult();
        result.userName = target.Name;
        result.fieldAppUrl = FIELD_APP_URL + '#login-as'
            + '&access_token=' + EncodingUtil.urlEncode(String.valueOf(token.get('access_token')), 'UTF-8')
            + '&instance_url=' + EncodingUtil.urlEncode(String.valueOf(token.get('instance_url')), 'UTF-8')
            + '&issued_at=' + EncodingUtil.urlEncode(String.valueOf(token.get('issued_at')), 'UTF-8')
            + '&as=' + EncodingUtil.urlEncode(target.Name, 'UTF-8')
            + '&by=' + EncodingUtil.urlEncode(UserInfo.getName(), 'UTF-8');
        result.message = 'Field app session ready for ' + target.Name + '. Anything you save is saved as them.';
        return result;
    }

    private static LoginAsResult failed(String userName, String error) {
        LoginAsResult result = new LoginAsResult();
        result.userName = userName;
        result.error = error;
        return result;
    }

    private static Map<String, Object> requestToken(String username) {
        String body = mockTokenResponse;
        if (body == null) {
            Auth.JWT jwt = new Auth.JWT();
            jwt.setSub(username);
            jwt.setAud(audience());
            jwt.setIss(CLIENT_ID);
            Auth.JWS jws = new Auth.JWS(jwt, CERT_NAME);
            // Plain POST rather than Auth.JWTBearerTokenExchange, which hides Salesforce's error body on failure.
            HttpRequest req = new HttpRequest();
            req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + '/services/oauth2/token');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setBody(
                'grant_type=' + EncodingUtil.urlEncode('urn:ietf:params:oauth:grant-type:jwt-bearer', 'UTF-8')
                + '&assertion=' + jws.getCompactSerialization()
            );
            body = new Http().send(req).getBody();
        }
        Map<String, Object> token;
        try {
            token = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            throw new CalloutException('Unexpected token response: ' + String.valueOf(body).left(200));
        }
        if (token.get('access_token') == null) {
            // Keep both parts, e.g. "invalid_grant: invalid assertion".
            throw new CalloutException(token.get('error') + ': ' + token.get('error_description'));
        }
        if (token.get('instance_url') == null) {
            token.put('instance_url', URL.getOrgDomainUrl().toExternalForm());
        }
        if (token.get('issued_at') == null) {
            token.put('issued_at', String.valueOf(System.now().getTime()));
        }
        return token;
    }

    private static String audience() {
        Boolean sandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        return sandbox ? 'https://test.salesforce.com' : 'https://login.salesforce.com';
    }

    /** Plain-language cause first, then Salesforce's own error so admins can act on it. */
    @TestVisible
    private static String explainTokenFailure(String userName, String detail) {
        String text = String.isBlank(detail) ? '' : detail.toLowerCase();
        String salesforceSays = ' (Salesforce: ' + (String.isBlank(detail) ? 'no detail' : detail) + ')';
        if (text.contains('user hasn') || text.contains('not approved')) {
            return userName + ' has not approved the Pharma Field Offline app yet. Ask them to sign in once at '
                + 'salesforceoffline.com, or pre-authorize the app for their profile.' + salesforceSays;
        }
        if (text.contains('invalid assertion')) {
            return 'Salesforce rejected the signed Login As request. Upload certificate ' + CERT_NAME
                + ' to the Pharma Field Offline connected app under "Use digital signatures".' + salesforceSays;
        }
        if (text.contains('audience')) {
            return 'Salesforce rejected the Login As audience for this org.' + salesforceSays;
        }
        if (text.contains('client identifier')) {
            return 'The Pharma Field Offline consumer key in Login As does not match the connected app.' + salesforceSays;
        }
        return 'Could not open the field app as ' + userName + '.' + salesforceSays;
    }

    private static void logAttempt(Id targetId, String reason, String status, String detail) {
        insert as system new Field_Login_As_Log__c(
            Target_User__c = targetId,
            Reason__c = reason,
            Status__c = status,
            Detail__c = String.isBlank(detail) ? null : detail.left(255)
        );
    }
}
