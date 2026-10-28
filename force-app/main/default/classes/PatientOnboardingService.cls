/**
 * Public patient-history form and the coach actions that send its link.
 * The form is opened with an unguessable token. Coaches send it by email or WhatsApp.
 */
public without sharing class PatientOnboardingService {
    public class Dispatch {
        @AuraEnabled public String url;
        @AuraEnabled public String whatsappUrl;
        @AuraEnabled public String email;
        @AuraEnabled public String mobile;
    }

    public class Form {
        public String firstName { get; set; }
        public String mobile { get; set; }
        public String email { get; set; }
        public String city { get; set; }
        public String address { get; set; }
        public Date birthdate { get; set; }
        public String diagnosis { get; set; }
        public Date diagnosisDate { get; set; }
        public String physician { get; set; }
        public String hospital { get; set; }
        public String occupation { get; set; }
        public String allergies { get; set; }
        public String medications { get; set; }
        public String conditions { get; set; }
        public String emergencyName { get; set; }
        public String emergencyPhone { get; set; }
        public Boolean consent { get; set; }
        public Boolean alreadyCompleted { get; set; }
    }

    public class Snapshot {
        @AuraEnabled public String allergies;
        @AuraEnabled public String medications;
        @AuraEnabled public String conditions;
        @AuraEnabled public String emergencyName;
        @AuraEnabled public String emergencyPhone;
        @AuraEnabled public Datetime onboardingSentOn;
        @AuraEnabled public Datetime onboardingCompletedOn;
    }

    @AuraEnabled
    public static Snapshot history(Id patientId) {
        CareCoachAccess.assertCanEdit();
        if (patientId == null) {
            throw CareCoachAccess.fail('Patient Id is required.');
        }
        List<Patient__c> rows = [
            SELECT Allergies__c, Current_Medications__c, Medical_Conditions__c,
                Emergency_Contact_Name__c, Emergency_Contact_Phone__c,
                Onboarding_Sent_On__c, Onboarding_Completed_On__c
            FROM Patient__c
            WHERE Id = :patientId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw CareCoachAccess.fail('Patient not found or you do not have access.');
        }
        Patient__c p = rows[0];
        Snapshot s = new Snapshot();
        s.allergies = p.Allergies__c;
        s.medications = p.Current_Medications__c;
        s.conditions = p.Medical_Conditions__c;
        s.emergencyName = p.Emergency_Contact_Name__c;
        s.emergencyPhone = p.Emergency_Contact_Phone__c;
        s.onboardingSentOn = p.Onboarding_Sent_On__c;
        s.onboardingCompletedOn = p.Onboarding_Completed_On__c;
        return s;
    }

    @AuraEnabled
    public static Dispatch sendEmail(Id patientId) {
        Patient__c p = loadForCoach(patientId);
        if (String.isBlank(p.Email__c)) {
            throw CareCoachAccess.fail('This patient has no email address.');
        }
        Dispatch link = buildLink(p);
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ p.Email__c });
        mail.setSubject('Please complete your patient history');
        mail.setHtmlBody(emailBody(p, link.url));
        mail.setSaveAsActivity(false);
        mail.setReplyTo(UserInfo.getUserEmail());
        mail.setSenderDisplayName(UserInfo.getName());
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        logSent(p, 'Email', link.url);
        return link;
    }

    @AuraEnabled
    public static Dispatch logWhatsApp(Id patientId) {
        Patient__c p = loadForCoach(patientId);
        if (String.isBlank(whatsAppPhone(p))) {
            throw CareCoachAccess.fail('This patient has no mobile number.');
        }
        Dispatch link = buildLink(p);
        logSent(p, 'WhatsApp', link.url);
        return link;
    }

    public static Form loadForm(String token) {
        Patient__c p = findByToken(token);
        if (p == null) {
            return null;
        }
        Form f = new Form();
        f.firstName = p.First_Name__c;
        f.mobile = p.Mobile__c;
        f.email = p.Email__c;
        f.city = p.City__c;
        f.address = p.Address__c;
        f.birthdate = p.Birthdate__c;
        f.diagnosis = p.Diagnosis__c;
        f.diagnosisDate = p.Diagnosis_Date__c;
        f.physician = p.Physician_Name__c;
        f.hospital = p.Hospital__c;
        f.occupation = p.Occupation__c;
        f.allergies = p.Allergies__c;
        f.medications = p.Current_Medications__c;
        f.conditions = p.Medical_Conditions__c;
        f.emergencyName = p.Emergency_Contact_Name__c;
        f.emergencyPhone = p.Emergency_Contact_Phone__c;
        f.consent = p.Consent_Given__c == true;
        f.alreadyCompleted = p.Onboarding_Completed_On__c != null;
        return f;
    }

    public static String saveForm(String token, Form form) {
        Patient__c p = findByToken(token);
        if (p == null || form == null) {
            return 'This link is not valid. Ask your care coach to send a new one.';
        }
        if (form.consent != true) {
            return 'Please confirm that the information is yours and that the programme may keep it.';
        }
        if (String.isBlank(form.allergies) && String.isBlank(form.medications)
            && String.isBlank(form.conditions) && String.isBlank(form.diagnosis)) {
            return 'Add your diagnosis, allergies, medicines, or other conditions.';
        }
        update new Patient__c(
            Id = p.Id,
            Mobile__c = clip(form.mobile, 40),
            Email__c = clip(form.email, 80),
            City__c = clip(form.city, 80),
            Address__c = clip(form.address, 255),
            Birthdate__c = form.birthdate,
            Diagnosis__c = clip(form.diagnosis, 120),
            Diagnosis_Date__c = form.diagnosisDate,
            Physician_Name__c = clip(form.physician, 120),
            Hospital__c = clip(form.hospital, 120),
            Occupation__c = clip(form.occupation, 80),
            Allergies__c = clip(form.allergies, 2000),
            Current_Medications__c = clip(form.medications, 2000),
            Medical_Conditions__c = clip(form.conditions, 2000),
            Emergency_Contact_Name__c = clip(form.emergencyName, 80),
            Emergency_Contact_Phone__c = clip(form.emergencyPhone, 40),
            Consent_Given__c = true,
            Onboarding_Completed_On__c = System.now()
        );
        return null;
    }

    private static Dispatch buildLink(Patient__c p) {
        String token = ensureToken(p);
        String url = formUrl(token);
        Dispatch out = new Dispatch();
        out.url = url;
        out.email = p.Email__c;
        out.mobile = whatsAppPhone(p);
        if (String.isNotBlank(out.mobile)) {
            String text = 'Hello ' + (String.isBlank(p.First_Name__c) ? 'there' : p.First_Name__c)
                + ', please complete your patient history form so we can support your treatment: ' + url;
            out.whatsappUrl = 'https://wa.me/' + digits(out.mobile) + '?text=' + EncodingUtil.urlEncode(text, 'UTF-8');
        }
        return out;
    }

    private static void logSent(Patient__c p, String channel, String url) {
        insert new Patient_Interaction__c(
            Patient__c = p.Id,
            Care_Coach__c = UserInfo.getUserId(),
            Product__c = p.Primary_Product__c,
            Type__c = channel,
            Direction__c = 'Outbound',
            Status__c = 'New',
            Subject__c = 'Onboarding form',
            Interaction_Reason__c = 'Welcome call',
            Start__c = System.now(),
            Notes__c = 'Onboarding form link sent by ' + channel + '.\n' + url
        );
        update new Patient__c(Id = p.Id, Onboarding_Sent_On__c = System.now());
    }

    private static Patient__c loadForCoach(Id patientId) {
        CareCoachAccess.assertCanEdit();
        if (patientId == null) {
            throw CareCoachAccess.fail('Patient Id is required.');
        }
        List<Patient__c> rows = [
            SELECT Id, First_Name__c, Email__c, Mobile__c, Phone__c, Primary_Product__c, Onboarding_Token__c
            FROM Patient__c
            WHERE Id = :patientId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw CareCoachAccess.fail('Patient not found or you do not have access.');
        }
        return rows[0];
    }

    private static String ensureToken(Patient__c p) {
        if (String.isNotBlank(p.Onboarding_Token__c)) {
            return p.Onboarding_Token__c;
        }
        String token = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        update new Patient__c(Id = p.Id, Onboarding_Token__c = token);
        p.Onboarding_Token__c = token;
        return token;
    }

    private static Patient__c findByToken(String token) {
        if (String.isBlank(token) || token.length() < 16) {
            return null;
        }
        List<Patient__c> rows = [
            SELECT Id, First_Name__c, Mobile__c, Email__c, City__c, Address__c, Birthdate__c,
                Diagnosis__c, Diagnosis_Date__c, Physician_Name__c, Hospital__c, Occupation__c,
                Allergies__c, Current_Medications__c, Medical_Conditions__c,
                Emergency_Contact_Name__c, Emergency_Contact_Phone__c, Consent_Given__c, Onboarding_Completed_On__c
            FROM Patient__c
            WHERE Onboarding_Token__c = :token
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    @TestVisible
    private static String formUrl(String token) {
        String base = Test.isRunningTest() ? 'https://example.com/onboard' : siteBase();
        if (String.isBlank(base)) {
            throw CareCoachAccess.fail('The public onboarding site is not available yet.');
        }
        base = base.removeEnd('/');
        if (!base.endsWith('/PatientOnboarding')) {
            base += '/PatientOnboarding';
        }
        return base + '?t=' + token;
    }

    private static String siteBase() {
        List<Site> sites = [SELECT Id FROM Site WHERE UrlPathPrefix = 'onboard' AND Status = 'Active' LIMIT 1];
        if (sites.isEmpty()) {
            return null;
        }
        List<SiteDetail> details = [SELECT SecureUrl FROM SiteDetail WHERE DurableId = :sites[0].Id LIMIT 1];
        return details.isEmpty() ? null : details[0].SecureUrl;
    }

    private static String whatsAppPhone(Patient__c p) {
        return String.isBlank(p.Mobile__c) ? p.Phone__c : p.Mobile__c;
    }

    @TestVisible
    private static String digits(String phone) {
        if (String.isBlank(phone)) {
            return '';
        }
        String d = phone.replaceAll('[^0-9]', '');
        if (d.startsWith('00')) {
            d = d.substring(2);
        }
        if (d.startsWith('0') && d.length() == 11) {
            d = '20' + d.substring(1);
        } else if (d.length() == 10 && d.startsWith('1')) {
            d = '20' + d;
        }
        return d;
    }

    private static String clip(String value, Integer max) {
        if (String.isBlank(value)) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.length() > max ? trimmed.substring(0, max) : trimmed;
    }

    private static String emailBody(Patient__c p, String url) {
        String name = String.isBlank(p.First_Name__c) ? 'there' : p.First_Name__c.escapeHtml4();
        return '<div style="font-family:Arial,sans-serif;color:#181818;max-width:32rem">'
            + '<p>Hello ' + name + ',</p>'
            + '<p>Your care coach asked you to complete a short patient history form. It takes a few minutes and helps the support programme look after your treatment.</p>'
            + '<p><a href="' + url + '" style="display:inline-block;background:#0f7c8c;color:#fff;text-decoration:none;padding:0.6rem 1rem;border-radius:999px;font-weight:700">Open the form</a></p>'
            + '<p style="font-size:0.85rem;color:#706e6b">Or copy this link:<br/>' + url + '</p>'
            + '<p style="font-size:0.85rem;color:#706e6b">This link is only for you. Please do not forward it.</p>'
            + '</div>';
    }
}