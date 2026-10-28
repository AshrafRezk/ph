/**
 * Sign-in for the public Zeta app when the visitor has no personal ?c= link.
 * They enter an HCP code (Account External ID) or a mobile number, and a 6-digit PIN
 * goes to the email and, when an SMS endpoint is configured, the mobile on file.
 * The PIN is stored only as a hash. A correct PIN sets a cookie that brings back
 * that HCP's events, requests and rated products.
 */
public without sharing class ZetaHcpSignInService {
    public static final String COOKIE = 'zeta_sid';
    static final Integer PIN_MINUTES = 10;
    static final Integer SESSION_DAYS = 30;
    static final Integer MAX_ATTEMPTS = 5;
    static final Integer MAX_PER_IDENTITY = 5;
    static final Integer MAX_PER_HOUR = 80;
    static final String SENT = 'If we recognise that code or number, a PIN is on its way to the email or mobile we have for you. It expires in 10 minutes.';
    static final String WAIT = 'Please wait a few minutes before asking for another PIN.';
    static final String BAD_PIN = 'That PIN is not right, or it has expired.';
    static final Set<String> HCP_TYPES = new Set<String>{
        'SDO_PersonAccounts', 'Medical_Professional_HCP', 'PersonAccount', 'Business_Contact'
    };

    @TestVisible static String testPin;
    @TestVisible static String testSession;
    /** When set in a test, the direct email send is skipped so the queued path can be covered. */
    @TestVisible static Boolean failDirectEmail = false;

    public class Result {
        public Boolean ok = false;
        public String message;
    }

    public static String handle(PageReference page) {
        Map<String, String> params = page.getParameters();
        Result result = params.get('step') == 'check'
            ? check(params.get('who'), params.get('pin'), page)
            : send(params.get('who'));
        return JSON.serialize(result);
    }

    /** The HCP behind a session cookie, or null when the cookie is missing or expired. */
    public static ZetaHcpContentService.Hcp resume(String token) {
        if (String.isBlank(token) || token.length() > 80) {
            return null;
        }
        List<Hcp_App_Sign_In__c> rows = [
            SELECT Account__c, Guest_Name__c, Phone__c, Email__c, App_Code__c
            FROM Hcp_App_Sign_In__c
            WHERE Kind__c = 'Session' AND Secret_Hash__c = :sha(token) AND Expires_At__c > :System.now()
            LIMIT 1
        ];
        return rows.isEmpty() ? null : toHcp(rows[0]);
    }

    /** Sends PIN emails that the site guest could not send itself. Runs as the automated process. */
    public static void deliver(List<Hcp_Pin_Send__e> events) {
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        for (Hcp_Pin_Send__e event : events) {
            if (isEmail(event.Email__c) && String.isNotBlank(event.Pin__c)) {
                mails.add(pinMail(event.Email__c, event.Pin__c, event.Guest_Name__c));
            }
        }
        if (!mails.isEmpty()) {
            Messaging.sendEmail(mails, false);
        }
    }

    static Result send(String who) {
        if (Test.isRunningTest()) {
            testPin = null;
        }
        Result result = new Result();
        String raw = who == null ? '' : who.trim();
        if (String.isBlank(raw) || raw.length() > 80) {
            result.message = 'Enter your HCP code or mobile number.';
            return result;
        }
        String lookup = sha(lookupKey(raw));
        if (tooMany(lookup)) {
            result.ok = true;
            result.message = WAIT;
            return result;
        }
        Identity identity = findIdentity(raw);
        if (identity == null || (!isEmail(identity.email) && String.isBlank(identity.phone))) {
            result.ok = true;
            result.message = SENT;
            return result;
        }
        String pin = newPin();
        Boolean texted = sms(identity.phone, pin);
        Boolean emailed = emailDirect(identity, pin);
        if (!emailed && isEmail(identity.email)) {
            emailed = queueEmail(identity, pin);
        }
        if (!emailed && !texted) {
            result.ok = true;
            result.message = SENT;
            return result;
        }
        expireOpen(lookup);
        insert pinRow(identity, lookup, pin);
        if (Test.isRunningTest()) {
            testPin = pin;
        }
        result.ok = true;
        result.message = SENT;
        return result;
    }

    static Result check(String who, String pin, PageReference page) {
        if (Test.isRunningTest()) {
            testSession = null;
        }
        Result result = new Result();
        String raw = who == null ? '' : who.trim();
        String code = pin == null ? '' : pin.trim();
        if (String.isBlank(raw) || !Pattern.matches('\\d{6}', code)) {
            result.message = BAD_PIN;
            return result;
        }
        String lookup = sha(lookupKey(raw));
        List<Hcp_App_Sign_In__c> rows = [
            SELECT Id, Salt__c, Secret_Hash__c, Attempts__c, Account__c, Guest_Name__c, Phone__c, Email__c, App_Code__c, CreatedDate
            FROM Hcp_App_Sign_In__c
            WHERE Kind__c = 'Pin' AND Lookup_Hash__c = :lookup AND Expires_At__c > :System.now()
            LIMIT 5
            FOR UPDATE
        ];
        Hcp_App_Sign_In__c row = latest(rows);
        if (row == null || sha(row.Salt__c + ':' + code) != row.Secret_Hash__c) {
            if (row != null) {
                noteAttempt(row);
            }
            result.message = BAD_PIN;
            return result;
        }
        String token = EncodingUtil.convertToHex(Crypto.generateAesKey(256));
        insert sessionRow(row, lookup, token);
        row.Expires_At__c = System.now();
        update row;
        page.setCookies(new List<Cookie>{
            new Cookie(COOKIE, token, '/', 60 * 60 * 24 * SESSION_DAYS, true, 'Lax')
        });
        if (Test.isRunningTest()) {
            testSession = token;
        }
        result.ok = true;
        result.message = 'Welcome.';
        return result;
    }

    static Hcp_App_Sign_In__c latest(List<Hcp_App_Sign_In__c> rows) {
        Hcp_App_Sign_In__c best;
        for (Hcp_App_Sign_In__c row : rows) {
            if (best == null || row.CreatedDate > best.CreatedDate) {
                best = row;
            }
        }
        return best;
    }

    static void noteAttempt(Hcp_App_Sign_In__c row) {
        Integer attempts = row.Attempts__c == null ? 1 : row.Attempts__c.intValue() + 1;
        row.Attempts__c = attempts;
        if (attempts >= MAX_ATTEMPTS) {
            row.Expires_At__c = System.now();
        }
        update row;
    }

    static Boolean tooMany(String lookup) {
        DateTime hourAgo = System.now().addHours(-1);
        Integer mine = [
            SELECT COUNT()
            FROM Hcp_App_Sign_In__c
            WHERE Kind__c = 'Pin' AND Lookup_Hash__c = :lookup AND CreatedDate >= :hourAgo
        ];
        if (mine >= MAX_PER_IDENTITY) {
            return true;
        }
        Integer all = [
            SELECT COUNT()
            FROM Hcp_App_Sign_In__c
            WHERE Kind__c = 'Pin' AND CreatedDate >= :hourAgo
        ];
        return all >= MAX_PER_HOUR;
    }

    static void expireOpen(String lookup) {
        List<Hcp_App_Sign_In__c> openPins = [
            SELECT Id
            FROM Hcp_App_Sign_In__c
            WHERE Kind__c = 'Pin' AND Lookup_Hash__c = :lookup AND Expires_At__c > :System.now()
        ];
        for (Hcp_App_Sign_In__c row : openPins) {
            row.Expires_At__c = System.now();
        }
        if (!openPins.isEmpty()) {
            update openPins;
        }
    }

    static Boolean emailDirect(Identity identity, String pin) {
        if (failDirectEmail || !isEmail(identity.email)) {
            return false;
        }
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ pinMail(identity.email.trim(), pin, identity.name) });
            return true;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'HCP PIN email failed: ' + e.getMessage());
            return false;
        }
    }

    static Boolean queueEmail(Identity identity, String pin) {
        try {
            EventBus.publish(new Hcp_Pin_Send__e(
                Email__c = identity.email.trim(),
                Phone__c = clip(identity.phone, 40),
                Pin__c = pin,
                Guest_Name__c = clip(identity.name, 120)
            ));
            return true;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'HCP PIN queue failed: ' + e.getMessage());
            return false;
        }
    }

    static Boolean sms(String phone, String pin) {
        String endpoint = System.Label.Hcp_Sms_Endpoint == null ? '' : System.Label.Hcp_Sms_Endpoint.trim();
        if (String.isBlank(phone) || !endpoint.startsWith('https://')) {
            return false;
        }
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setTimeout(10000);
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(new Map<String, String>{ 'to' => phone, 'text' => pinText(pin) }));
            HttpResponse res = new Http().send(req);
            return res.getStatusCode() >= 200 && res.getStatusCode() < 300;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'HCP PIN text failed: ' + e.getMessage());
            return false;
        }
    }

    static Messaging.SingleEmailMessage pinMail(String email, String pin, String name) {
        String hello = String.isBlank(name) ? 'Hello' : 'Hello ' + name.trim();
        String text = hello + ',\n\nYour Zeta Pharma PIN is ' + pin + '. It expires in 10 minutes.\n\n'
            + 'رمز الدخول: ' + pin + '\nينتهي خلال ١٠ دقائق.\n\n'
            + 'If you did not ask for this, you can ignore this message.';
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ email });
        mail.setSubject('Your Zeta Pharma PIN');
        mail.setSaveAsActivity(false);
        mail.setSenderDisplayName('Zeta Pharma');
        mail.setPlainTextBody(text);
        mail.setHtmlBody(
            '<div style="font-family:-apple-system,Segoe UI,Arial,sans-serif;background:#f4f6f9;padding:24px 12px">'
            + '<div style="max-width:480px;margin:0 auto;background:#fff;border-radius:16px;padding:24px">'
            + '<div style="font-size:12px;font-weight:800;color:#0b5cab;letter-spacing:.06em;text-transform:uppercase">Zeta Pharma</div>'
            + '<p style="color:#181818">' + hello.escapeHtml4() + ',</p>'
            + '<p style="color:#181818">Your PIN is</p>'
            + '<p style="font-size:32px;letter-spacing:.3em;font-weight:800;color:#032d60;margin:8px 0">' + pin + '</p>'
            + '<p style="color:#706e6b">It expires in 10 minutes. If you did not ask for this, you can ignore this message.</p>'
            + '<p dir="rtl" style="color:#444">رمز الدخول: ' + pin + ' — ينتهي خلال ١٠ دقائق.</p>'
            + '</div></div>'
        );
        return mail;
    }

    static String pinText(String pin) {
        return 'Your Zeta Pharma PIN is ' + pin + '. It expires in 10 minutes.';
    }

    class Identity {
        Id accountId;
        String name;
        String phone;
        String email;
        String appCode;
    }

    static Identity findIdentity(String raw) {
        Identity byCode = findByExternalId(raw);
        Identity byPhone = isPhone(raw) ? findByPhone(raw) : null;
        if (byCode != null && byPhone != null && byCode.accountId != byPhone.accountId) {
            return null;
        }
        if (byPhone != null) {
            return byPhone;
        }
        if (byCode != null) {
            return byCode;
        }
        return findByInvitationCode(raw);
    }

    static Identity findByExternalId(String code) {
        List<Account> rows = [
            SELECT Id, Name, Phone, PersonMobilePhone, PersonEmail, Email__c, WhatsApp_Number__c, Clinic_Phone__c,
                Account_Stage__c, Account_Status__c, Duplicate_Of__c, RecordType.DeveloperName
            FROM Account
            WHERE External_ID__c = :code
            LIMIT 2
        ];
        List<Account> matched = new List<Account>();
        for (Account row : rows) {
            if (activeHcp(row)) {
                matched.add(row);
            }
        }
        return matched.size() == 1 ? fromAccount(matched[0], null) : null;
    }

    static Identity findByPhone(String raw) {
        Set<String> variants = phoneVariants(raw);
        List<Account> rows = [
            SELECT Id, Name, Phone, PersonMobilePhone, PersonEmail, Email__c, WhatsApp_Number__c, Clinic_Phone__c,
                Account_Stage__c, Account_Status__c, Duplicate_Of__c, RecordType.DeveloperName
            FROM Account
            WHERE RecordType.DeveloperName IN :HCP_TYPES
                AND (
                    Phone IN :variants
                    OR PersonMobilePhone IN :variants
                    OR WhatsApp_Number__c IN :variants
                    OR Clinic_Phone__c IN :variants
                )
            LIMIT 20
        ];
        List<Account> matched = new List<Account>();
        for (Account row : rows) {
            if (activeHcp(row) && phoneHits(row, raw)) {
                matched.add(row);
            }
        }
        if (matched.size() > 1) {
            return null;
        }
        if (matched.size() == 1) {
            return fromAccount(matched[0], raw);
        }
        List<Meeting_Invitation__c> invites = [
            SELECT Code__c, Guest_Name__c, Phone__c, Email__c, Meeting_Member__r.Customer__c
            FROM Meeting_Invitation__c
            WHERE Active__c = true AND Phone__c IN :variants
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];
        List<Meeting_Invitation__c> hit = new List<Meeting_Invitation__c>();
        for (Meeting_Invitation__c invite : invites) {
            if (phonesMatch(invite.Phone__c, raw)) {
                hit.add(invite);
            }
        }
        if (hit.isEmpty()) {
            return null;
        }
        Set<Id> accountIds = new Set<Id>();
        for (Meeting_Invitation__c invite : hit) {
            if (invite.Meeting_Member__r != null && invite.Meeting_Member__r.Customer__c != null) {
                accountIds.add(invite.Meeting_Member__r.Customer__c);
            }
        }
        if (accountIds.size() > 1) {
            return null;
        }
        if (accountIds.size() == 1) {
            Identity account = findAccountById(new List<Id>(accountIds)[0]);
            if (account != null) {
                if (String.isBlank(account.phone)) {
                    account.phone = hit[0].Phone__c;
                }
                if (String.isBlank(account.email)) {
                    account.email = cleanEmail(hit[0].Email__c);
                }
                return account;
            }
        }
        return fromInvitation(hit[0]);
    }

    static Identity findByInvitationCode(String code) {
        if (String.isBlank(code) || code.length() > 16) {
            return null;
        }
        for (Meeting_Invitation__c invite : [
            SELECT Code__c, Guest_Name__c, Phone__c, Email__c, Meeting_Member__r.Customer__c
            FROM Meeting_Invitation__c
            WHERE Active__c = true AND Code__c = :code
            LIMIT 5
        ]) {
            if (invite.Code__c == null || !invite.Code__c.equals(code)) {
                continue;
            }
            if (invite.Meeting_Member__r != null && invite.Meeting_Member__r.Customer__c != null) {
                Identity account = findAccountById(invite.Meeting_Member__r.Customer__c);
                if (account != null) {
                    if (String.isBlank(account.phone)) {
                        account.phone = invite.Phone__c;
                    }
                    if (String.isBlank(account.email)) {
                        account.email = cleanEmail(invite.Email__c);
                    }
                    return account;
                }
            }
            return fromInvitation(invite);
        }
        return null;
    }

    static Identity findAccountById(Id accountId) {
        List<Account> rows = [
            SELECT Id, Name, Phone, PersonMobilePhone, PersonEmail, Email__c, WhatsApp_Number__c, Clinic_Phone__c,
                Account_Stage__c, Account_Status__c, Duplicate_Of__c, RecordType.DeveloperName
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        return rows.isEmpty() || !activeHcp(rows[0]) ? null : fromAccount(rows[0], null);
    }

    static Identity fromAccount(Account row, String preferPhone) {
        Identity identity = new Identity();
        identity.accountId = row.Id;
        identity.name = row.Name;
        identity.phone = bestPhone(row, preferPhone);
        identity.email = bestEmail(row);
        return identity;
    }

    static Identity fromInvitation(Meeting_Invitation__c invite) {
        Identity identity = new Identity();
        identity.name = invite.Guest_Name__c;
        identity.phone = invite.Phone__c;
        identity.email = cleanEmail(invite.Email__c);
        identity.appCode = invite.Code__c;
        return identity;
    }

    static ZetaHcpContentService.Hcp toHcp(Hcp_App_Sign_In__c row) {
        if (row.Account__c != null) {
            Identity account = findAccountById(row.Account__c);
            return account == null ? null : asHcp(account);
        }
        if (String.isBlank(row.Guest_Name__c) && String.isBlank(row.Phone__c) && String.isBlank(row.App_Code__c)) {
            return null;
        }
        ZetaHcpContentService.Hcp hcp = new ZetaHcpContentService.Hcp();
        hcp.name = row.Guest_Name__c;
        hcp.phone = row.Phone__c;
        hcp.email = row.Email__c;
        hcp.code = row.App_Code__c;
        return hcp;
    }

    static ZetaHcpContentService.Hcp asHcp(Identity identity) {
        ZetaHcpContentService.Hcp hcp = new ZetaHcpContentService.Hcp();
        hcp.accountId = identity.accountId;
        hcp.name = identity.name;
        hcp.phone = identity.phone;
        hcp.email = identity.email;
        hcp.code = identity.appCode;
        return hcp;
    }

    static Hcp_App_Sign_In__c pinRow(Identity identity, String lookup, String pin) {
        String salt = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        return new Hcp_App_Sign_In__c(
            Kind__c = 'Pin',
            Account__c = identity.accountId,
            Guest_Name__c = clip(identity.name, 120),
            Phone__c = clip(identity.phone, 40),
            Email__c = isEmail(identity.email) ? identity.email.trim() : null,
            App_Code__c = clip(identity.appCode, 16),
            Lookup_Hash__c = lookup,
            Salt__c = salt,
            Secret_Hash__c = sha(salt + ':' + pin),
            Expires_At__c = System.now().addMinutes(PIN_MINUTES),
            Attempts__c = 0
        );
    }

    static Hcp_App_Sign_In__c sessionRow(Hcp_App_Sign_In__c pin, String lookup, String token) {
        return new Hcp_App_Sign_In__c(
            Kind__c = 'Session',
            Account__c = pin.Account__c,
            Guest_Name__c = pin.Guest_Name__c,
            Phone__c = pin.Phone__c,
            Email__c = pin.Email__c,
            App_Code__c = pin.App_Code__c,
            Lookup_Hash__c = lookup,
            Secret_Hash__c = sha(token),
            Expires_At__c = System.now().addDays(SESSION_DAYS),
            Attempts__c = 0
        );
    }

    static Boolean activeHcp(Account row) {
        if (row == null || row.RecordType == null || !HCP_TYPES.contains(row.RecordType.DeveloperName)) {
            return false;
        }
        if (row.Duplicate_Of__c != null) {
            return false;
        }
        if (row.Account_Stage__c == 'Inactive' || row.Account_Stage__c == 'Duplicate') {
            return false;
        }
        return row.Account_Status__c != 'Inactive';
    }

    static String bestPhone(Account row, String prefer) {
        List<String> phones = new List<String>{ row.WhatsApp_Number__c, row.PersonMobilePhone, row.Phone, row.Clinic_Phone__c };
        if (String.isNotBlank(prefer)) {
            for (String phone : phones) {
                if (phonesMatch(phone, prefer)) {
                    return phone;
                }
            }
        }
        for (String phone : phones) {
            if (String.isNotBlank(phone)) {
                return phone;
            }
        }
        return null;
    }

    static String bestEmail(Account row) {
        if (isEmail(row.PersonEmail)) {
            return row.PersonEmail.trim();
        }
        return isEmail(row.Email__c) ? row.Email__c.trim() : null;
    }

    static Boolean phoneHits(Account row, String raw) {
        return phonesMatch(row.Phone, raw)
            || phonesMatch(row.PersonMobilePhone, raw)
            || phonesMatch(row.WhatsApp_Number__c, raw)
            || phonesMatch(row.Clinic_Phone__c, raw);
    }

    static Boolean phonesMatch(String left, String right) {
        String a = phoneKey(left);
        String b = phoneKey(right);
        if (String.isBlank(a) || String.isBlank(b) || a.length() < 8 || b.length() < 8) {
            return false;
        }
        return a == b || a.right(8) == b.right(8);
    }

    static Set<String> phoneVariants(String raw) {
        Set<String> out = new Set<String>();
        if (String.isBlank(raw)) {
            return out;
        }
        out.add(raw.trim());
        String digits = raw.replaceAll('[^0-9]', '');
        if (String.isNotBlank(digits)) {
            out.add(digits);
            if (digits.startsWith('00') && digits.length() > 2) {
                digits = digits.substring(2);
            }
            out.add(digits);
            String local = digits;
            if (local.startsWith('20') && local.length() > 10) {
                local = local.substring(2);
            }
            if (local.startsWith('0') && local.length() > 1) {
                local = local.substring(1);
            }
            out.add(local);
            out.add('0' + local);
            out.add('20' + local);
            out.add('+20' + local);
        }
        out.remove(null);
        out.remove('');
        return out;
    }

    static String phoneKey(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String digits = raw.replaceAll('[^0-9]', '');
        if (digits.startsWith('00') && digits.length() > 2) {
            digits = digits.substring(2);
        }
        if (digits.startsWith('20') && digits.length() > 10) {
            digits = digits.substring(2);
        }
        if (digits.startsWith('0') && digits.length() > 1) {
            digits = digits.substring(1);
        }
        return String.isBlank(digits) ? null : digits;
    }

    static Boolean isPhone(String raw) {
        if (String.isBlank(raw)) {
            return false;
        }
        String digits = raw.replaceAll('[^0-9]', '');
        if (digits.length() < 8) {
            return false;
        }
        return Pattern.matches('^[0-9]+$', raw.replaceAll('[\\s().+\\-]', ''));
    }

    static String lookupKey(String raw) {
        String trimmed = raw.trim();
        if (isPhone(trimmed)) {
            String digits = phoneKey(trimmed);
            return 'p:' + (String.isBlank(digits) ? trimmed : digits);
        }
        return 'c:' + trimmed.toLowerCase();
    }

    static String newPin() {
        String digits = '';
        while (digits.length() < 6) {
            String hex = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
            for (Integer i = 0; i < hex.length() && digits.length() < 6; i++) {
                String ch = hex.substring(i, i + 1);
                if (ch >= '0' && ch <= '9') {
                    digits += ch;
                }
            }
        }
        return digits.substring(0, 6);
    }

    static String sha(String value) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(value == null ? '' : value)));
    }

    static Boolean isEmail(String value) {
        return String.isNotBlank(value) && Pattern.matches('(?i)^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', value.trim());
    }

    static String cleanEmail(String value) {
        return isEmail(value) ? value.trim() : null;
    }

    static String clip(String value, Integer max) {
        return String.isBlank(value) ? null : value.trim().left(max);
    }
}
