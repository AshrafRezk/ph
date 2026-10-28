/**
 * Turns requests HCPs send from the Zeta app (/meet site) into Cases on the existing Medical Inquiry and
 * Service Request record types. Medical questions and side effect reports go to the Medical Affairs queue,
 * everything else to the Service Team queue. Runs without sharing because the site guest user creates them.
 */
public without sharing class ZetaHcpRequestService {
    public static final String ORIGIN = 'HCP App';
    @TestVisible static final Integer DAILY_LIMIT = 10;
    static final Set<String> QUESTION_CATEGORIES = new Set<String>{
        'Efficacy', 'Safety', 'Dosing', 'Administration', 'Contraindications', 'Drug Interactions', 'Pregnancy/Lactation', 'Off-label', 'Other'
    };

    /** App request key => Request_Type__c, record type, service category, queue and subject prefix. */
    static final Map<String, List<String>> TYPES = new Map<String, List<String>>{
        'visit' => new List<String>{ 'Rep Visit', 'Service_Request', 'General Support', 'Service_Team', 'Visit request' },
        'samples' => new List<String>{ 'Samples', 'Service_Request', 'Sample Request', 'Service_Team', 'Sample request' },
        'medical' => new List<String>{ 'Medical Question', 'Medical_Inquiry', null, 'Medical_Affairs', 'Medical question' },
        'material' => new List<String>{ 'Scientific Material', 'Service_Request', 'Product Information', 'Service_Team', 'Scientific material' },
        'event' => new List<String>{ 'Join Event', 'Service_Request', 'General Support', 'Service_Team', 'Event request' },
        'side_effect' => new List<String>{ 'Side Effect', 'Service_Request', 'Adverse Event', 'Medical_Affairs', 'Side effect report' }
    };

    public class Result {
        public Boolean ok = false;
        public String message;
        public String caseNumber;
    }

    public static Result submit(Map<String, String> params, Meeting_Invitation__c invitation) {
        return submit(params, ZetaHcpContentService.hcpFor(invitation));
    }

    public static Result submit(Map<String, String> params, ZetaHcpContentService.Hcp hcp) {
        Result result = new Result();
        if (hcp == null) {
            hcp = new ZetaHcpContentService.Hcp();
        }
        String type = clean(params.get('type'), 20);
        if (type == null || !TYPES.containsKey(type)) {
            return fail(result, 'Choose what you need.');
        }
        String name = firstNonBlank(clean(params.get('name'), 80), hcp.name);
        String phone = firstNonBlank(clean(params.get('phone'), 40), hcp.phone);
        String email = firstNonBlank(clean(params.get('email'), 80), hcp.email);
        if (String.isBlank(name) || String.isBlank(phone)) {
            return fail(result, 'Add your name and mobile number so we can reply.');
        }
        if (sentToday(hcp.code, phone) >= DAILY_LIMIT) {
            return fail(result, 'You have sent many requests today. Please try again tomorrow or contact your Zeta representative.');
        }

        String message = clean(params.get('message'), 4000);
        Product2 product = product(params.get('productId'));
        List<String> spec = TYPES.get(type);
        List<String> details = new List<String>();
        String subject = spec[4];
        Case c = new Case(
            Origin = ORIGIN,
            Status = 'New',
            Priority = 'Medium',
            Request_Type__c = spec[0],
            RecordTypeId = recordTypeId(spec[1]),
            Service_Category__c = spec[2],
            SuppliedName = name,
            SuppliedPhone = phone,
            SuppliedEmail = isEmail(email) ? email : null,
            HCP_App_Code__c = hcp.code,
            Inquirer_Account__c = hcp.accountId,
            AccountId = hcp.accountId,
            Product__c = product == null ? null : product.Id
        );

        switch on type {
            when 'samples' {
                if (product == null) {
                    return fail(result, 'Choose the product you need samples of.');
                }
                String quantity = clean(params.get('quantity'), 6);
                details.add('Quantity: ' + (quantity == null ? 'not specified' : quantity));
            }
            when 'medical' {
                if (String.isBlank(message)) {
                    return fail(result, 'Write your question.');
                }
                String category = params.get('category');
                c.Question_Category__c = QUESTION_CATEGORIES.contains(category) ? category : 'Other';
            }
            when 'event' {
                String eventId = params.get('eventId');
                Meeting__c meeting = eventMeeting(eventId);
                if (meeting == null) {
                    return fail(result, 'This event is no longer open.');
                }
                details.add('Event: ' + ZetaHcpContentService.title(meeting) + ' (' + meeting.Name + ')');
                if (meeting.Start_Date_Time__c != null) {
                    details.add('Date: ' + meeting.Start_Date_Time__c.format('EEE d MMM yyyy, h:mm a', 'Africa/Cairo'));
                }
                subject += ': ' + ZetaHcpContentService.title(meeting).left(120);
            }
            when 'side_effect' {
                String reaction = clean(params.get('reaction'), 4000);
                if (product == null && String.isBlank(clean(params.get('productName'), 120))) {
                    return fail(result, 'Tell us which product was taken.');
                }
                if (String.isBlank(reaction)) {
                    return fail(result, 'Describe what happened.');
                }
                c.Priority = 'High';
                if (product == null) {
                    details.add('Product: ' + clean(params.get('productName'), 120));
                }
                details.add('What happened: ' + reaction);
                details.add('Started on: ' + valueOr(clean(params.get('onset'), 20), 'not given'));
                details.add('Patient initials: ' + valueOr(clean(params.get('initials'), 10), 'not given'));
                details.add('Patient age: ' + valueOr(clean(params.get('age'), 10), 'not given'));
                details.add('Patient sex: ' + valueOr(clean(params.get('sex'), 10), 'not given'));
                details.add('Serious (hospitalisation, life-threatening, disability or death): ' + (params.get('serious') == 'yes' ? 'Yes' : 'No'));
            }
            when else {
                if (String.isBlank(message) && product == null) {
                    return fail(result, 'Tell us a little about what you need.');
                }
            }
        }
        if (product != null) {
            subject += (subject.contains(':') ? ' · ' : ': ') + product.Name;
            if (details.isEmpty()) {
                details.add('Product: ' + product.Name);
            } else {
                details.add(0, 'Product: ' + product.Name);
            }
        }
        String preferred = clean(params.get('contact'), 20);
        if (preferred != null) {
            details.add('Preferred contact: ' + preferred);
        }
        if (String.isNotBlank(message)) {
            details.add('');
            details.add(message);
        }
        details.add('');
        details.add('Sent from the Zeta HCP app by ' + name + ' · ' + phone + (String.isBlank(email) ? '' : ' · ' + email));
        c.Subject = subject.left(255);
        c.Description = String.join(details, '\n').left(32000);
        c.OwnerId = queueId(spec[3]);
        if (c.OwnerId == null) {
            c.setOptions(defaultRule());
        }
        insert c;

        result.ok = true;
        result.caseNumber = [SELECT CaseNumber FROM Case WHERE Id = :c.Id].CaseNumber;
        result.message = type == 'side_effect'
            ? 'Thank you. Our safety team received your report and may contact you for details.'
            : type == 'medical'
                ? 'Thank you. Our Medical Affairs team will answer you.'
                : 'Thank you. Your Zeta team will get back to you soon.';
        return result;
    }

    @TestVisible
    static Integer sentToday(String code, String phone) {
        DateTime since = System.now().addHours(-24);
        if (String.isNotBlank(code)) {
            return [SELECT COUNT() FROM Case WHERE Origin = :ORIGIN AND HCP_App_Code__c = :code AND CreatedDate >= :since];
        }
        return [SELECT COUNT() FROM Case WHERE Origin = :ORIGIN AND SuppliedPhone = :phone AND CreatedDate >= :since];
    }

    static Product2 product(String productId) {
        if (String.isBlank(productId)) {
            return null;
        }
        Id pid;
        try {
            pid = Id.valueOf(productId);
        } catch (Exception e) {
            return null;
        }
        List<Product2> rows = [SELECT Id, Name FROM Product2 WHERE Id = :pid AND IsActive = true AND Show_In_HCP_App__c = true LIMIT 1];
        return rows.isEmpty() ? null : rows[0];
    }

    static Meeting__c eventMeeting(String eventId) {
        if (String.isBlank(eventId)) {
            return null;
        }
        Id mid;
        try {
            mid = Id.valueOf(eventId);
        } catch (Exception e) {
            return null;
        }
        if (mid.getSobjectType() != Meeting__c.SObjectType || !ZetaHcpContentService.isOpenEvent(mid)) {
            return null;
        }
        return [SELECT Id, Name, Objectives__c, Start_Date_Time__c FROM Meeting__c WHERE Id = :mid];
    }

    static Id recordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get(developerName);
        return info == null ? null : info.getRecordTypeId();
    }

    static Id queueId(String developerName) {
        List<Group> rows = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :developerName LIMIT 1];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    static Database.DMLOptions defaultRule() {
        Database.DMLOptions options = new Database.DMLOptions();
        options.assignmentRuleHeader.useDefaultRule = true;
        return options;
    }

    static Result fail(Result result, String message) {
        result.ok = false;
        result.message = message;
        return result;
    }

    @TestVisible
    static String clean(String value, Integer max) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.length() == 0 ? null : trimmed.left(max);
    }

    static String firstNonBlank(String a, String b) {
        return String.isNotBlank(a) ? a : b;
    }

    static String valueOr(String value, String fallback) {
        return String.isBlank(value) ? fallback : value;
    }

    static Boolean isEmail(String value) {
        return String.isNotBlank(value) && Pattern.matches('[^@\\s]+@[^@\\s]+\\.[^@\\s]+', value);
    }
}
