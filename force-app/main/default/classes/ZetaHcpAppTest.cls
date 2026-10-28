@IsTest
private class ZetaHcpAppTest {
    @TestSetup
    static void setup() {
        Id invitedMeeting = meeting('Cardio round table', System.now().addDays(3));
        Id openMeeting = meeting('Diabetes webinar', System.now().addDays(10));
        update new List<Meeting__c>{
            new Meeting__c(Id = invitedMeeting, Show_In_HCP_App__c = true),
            new Meeting__c(Id = openMeeting, Show_In_HCP_App__c = true)
        };
        MeetingInvitationService.addGuest(invitedMeeting, 'Dr. Mona', '01000000001', 'mona@example.com');

        insert new List<Product2>{
            new Product2(Name = 'Cardizet', IsActive = true, Show_In_HCP_App__c = true, Sales_Line__c = 'CVM-I', Product_Image_URL__c = 'https://example.com/c.png'),
            new Product2(Name = 'Hidden', IsActive = true, Show_In_HCP_App__c = false)
        };
        insert new List<Zeta_News__c>{
            new Zeta_News__c(Name = 'Live', Summary__c = 'Now', Body__c = 'Body', Published__c = true, Publish_Date__c = Date.today()),
            new Zeta_News__c(Name = 'Draft', Published__c = false, Publish_Date__c = Date.today()),
            new Zeta_News__c(Name = 'Old', Published__c = true, Publish_Date__c = Date.today().addDays(-30), Expiry_Date__c = Date.today().addDays(-1))
        };
    }

    static Id meeting(String title, DateTime startAt) {
        return MeetingLifecycleController.saveMeeting(JSON.serialize(new Map<String, Object>{
            'title' => title,
            'department' => 'Medical',
            'activityType' => 'Webinar',
            'startDateTime' => startAt,
            'endDateTime' => startAt.addHours(2),
            'venue' => 'Cairo',
            'agenda' => 'Talks',
            'estimatedParticipants' => 20
        }));
    }

    static Meeting_Invitation__c invitation() {
        return [SELECT Id, Code__c, Meeting__c FROM Meeting_Invitation__c WHERE Guest_Name__c = 'Dr. Mona' LIMIT 1];
    }

    static MeetingCheckInController open(Map<String, String> params) {
        Test.setCurrentPage(Page.m);
        ApexPages.currentPage().getParameters().putAll(params);
        MeetingCheckInController page = new MeetingCheckInController();
        page.logScan();
        return page;
    }

    static Map<String, Object> request(Map<String, String> params) {
        Map<String, String> all = new Map<String, String>{ 'a' => 'request' };
        all.putAll(params);
        MeetingCheckInController page = open(all);
        Assert.areEqual('api', page.view);
        Assert.areEqual('application/json', page.contentType);
        return (Map<String, Object>) JSON.deserializeUntyped(page.apiJson);
    }

    @IsTest
    static void appShowsOnlyApprovedContentForThisHcp() {
        Meeting_Invitation__c inv = invitation();
        MeetingCheckInController page = open(new Map<String, String>{ 'c' => inv.Code__c });
        Assert.isTrue(page.hasCode);
        Assert.isTrue(page.showEvents);
        Assert.isFalse(page.signedIn);
        Map<String, Object> app = (Map<String, Object>) JSON.deserializeUntyped(page.appJson);

        Map<String, Object> me = (Map<String, Object>) app.get('me');
        Assert.areEqual(true, me.get('known'));
        Assert.areEqual('Dr. Mona', me.get('name'));
        Assert.areEqual(inv.Code__c, me.get('code'));

        List<Object> products = (List<Object>) app.get('products');
        Assert.areEqual(1, products.size(), 'Only products flagged for the app');
        Assert.areEqual('Cardiology', ((Map<String, Object>) products[0]).get('area'));
        Assert.areEqual(false, ((Map<String, Object>) products[0]).get('rated'), 'A guest with no account has no rated products');

        List<Object> news = (List<Object>) app.get('news');
        Assert.areEqual(1, news.size(), 'Drafts and expired articles are hidden');
        Assert.areEqual('Live', ((Map<String, Object>) news[0]).get('title'));

        List<Object> events = (List<Object>) app.get('events');
        Assert.areEqual(1, events.size());
        Assert.areEqual(true, ((Map<String, Object>) events[0]).get('current'));
        List<Object> openEvents = (List<Object>) app.get('openEvents');
        Assert.areEqual(1, openEvents.size(), 'The meeting the HCP is already invited to is not offered again');
        Assert.areEqual('Diabetes webinar', ((Map<String, Object>) openEvents[0]).get('title'));
        Assert.isFalse(page.appJson.contains('</'), 'Embedded JSON cannot close the script tag');

        Map<String, Object> manifest = (Map<String, Object>) JSON.deserializeUntyped(page.manifestJson);
        Assert.areEqual('Zeta', manifest.get('short_name'));
    }

    @IsTest
    static void appOpensWithoutAPersonalLink() {
        MeetingCheckInController page = open(new Map<String, String>());
        Assert.isFalse(page.hasCode);
        Assert.isTrue(page.invalid);
        Assert.isFalse(page.showEvents);
        Map<String, Object> app = (Map<String, Object>) JSON.deserializeUntyped(page.appJson);
        Assert.areEqual(false, ((Map<String, Object>) app.get('me')).get('known'));
        Assert.areEqual(0, ((List<Object>) app.get('events')).size());
        Assert.areEqual(0, ((List<Object>) app.get('openEvents')).size(), 'Meetings stay hidden without a link or PIN');
        Assert.isFalse(page.appJson.contains('Diabetes webinar'));
        Assert.areEqual(1, ((List<Object>) app.get('news')).size());
        Assert.isTrue(((List<Object>) app.get('products')).size() > 0);
        Assert.areEqual(0, ((List<Object>) app.get('requests')).size());
    }

    @IsTest
    static void eachRequestTypeBecomesARoutedCase() {
        Meeting_Invitation__c inv = invitation();
        Product2 product = [SELECT Id FROM Product2 WHERE Name = 'Cardizet'];
        Meeting__c openMeeting = [SELECT Id FROM Meeting__c WHERE Id != :inv.Meeting__c AND Show_In_HCP_App__c = true LIMIT 1];
        Map<String, Map<String, String>> sends = new Map<String, Map<String, String>>{
            'samples' => new Map<String, String>{ 'productId' => product.Id, 'quantity' => '10' },
            'medical' => new Map<String, String>{ 'category' => 'Dosing', 'message' => 'Max daily dose?', 'productId' => product.Id },
            'visit' => new Map<String, String>{ 'contact' => 'WhatsApp', 'message' => 'New study' },
            'material' => new Map<String, String>{ 'message' => 'Product monograph' },
            'event' => new Map<String, String>{ 'eventId' => openMeeting.Id },
            'side_effect' => new Map<String, String>{ 'productName' => 'Other brand', 'reaction' => 'Rash', 'age' => '40', 'sex' => 'Female', 'serious' => 'yes' }
        };
        Test.startTest();
        for (String type : sends.keySet()) {
            Map<String, String> params = new Map<String, String>{ 'c' => inv.Code__c, 'type' => type };
            params.putAll(sends.get(type));
            Map<String, Object> res = request(params);
            Assert.areEqual(true, res.get('ok'), type + ': ' + res.get('message'));
            Assert.isNotNull(res.get('caseNumber'));
        }
        Test.stopTest();

        Map<String, Case> byType = new Map<String, Case>();
        for (Case c : [
            SELECT Request_Type__c, RecordType.DeveloperName, Service_Category__c, Question_Category__c, Priority, Product__c,
                SuppliedName, SuppliedPhone, SuppliedEmail, HCP_App_Code__c, Origin, Owner.Type, Subject, Description
            FROM Case WHERE HCP_App_Code__c = :inv.Code__c
        ]) {
            byType.put(c.Request_Type__c, c);
            Assert.areEqual('HCP App', c.Origin);
            Assert.areEqual('Dr. Mona', c.SuppliedName);
            Assert.areEqual('01000000001', c.SuppliedPhone);
            Assert.areEqual('mona@example.com', c.SuppliedEmail);
        }
        Assert.areEqual(6, byType.size());
        Assert.areEqual('Sample Request', byType.get('Samples').Service_Category__c);
        Assert.areEqual(product.Id, byType.get('Samples').Product__c);
        Assert.isTrue(byType.get('Samples').Description.contains('Quantity: 10'));
        Assert.areEqual('Medical_Inquiry', byType.get('Medical Question').RecordType.DeveloperName);
        Assert.areEqual('Dosing', byType.get('Medical Question').Question_Category__c);
        Assert.areEqual('General Support', byType.get('Rep Visit').Service_Category__c);
        Assert.isTrue(byType.get('Rep Visit').Description.contains('Preferred contact: WhatsApp'));
        Assert.areEqual('Product Information', byType.get('Scientific Material').Service_Category__c);
        Assert.isTrue(byType.get('Join Event').Subject.contains('Diabetes webinar'));
        Case ae = byType.get('Side Effect');
        Assert.areEqual('Adverse Event', ae.Service_Category__c);
        Assert.areEqual('High', ae.Priority);
        Assert.isTrue(ae.Description.contains('Product: Other brand'));
        Assert.isTrue(ae.Description.contains('Serious (hospitalisation, life-threatening, disability or death): Yes'));

        MeetingCheckInController page = open(new Map<String, String>{ 'c' => inv.Code__c });
        List<Object> mine = (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(page.appJson)).get('requests');
        Assert.areEqual(6, mine.size());
        Assert.areEqual('Submitted', ((Map<String, Object>) mine[0]).get('state'));
    }

    @IsTest
    static void badRequestsAreRejectedWithAClearMessage() {
        Meeting_Invitation__c inv = invitation();
        Assert.areEqual(false, request(new Map<String, String>{ 'c' => inv.Code__c, 'type' => 'nope' }).get('ok'));
        Assert.areEqual(false, request(new Map<String, String>{ 'c' => inv.Code__c, 'type' => 'samples' }).get('ok'));
        Assert.areEqual(false, request(new Map<String, String>{ 'c' => inv.Code__c, 'type' => 'medical', 'message' => ' ' }).get('ok'));
        Assert.areEqual(false, request(new Map<String, String>{ 'c' => inv.Code__c, 'type' => 'event', 'eventId' => inv.Id }).get('ok'));
        Assert.areEqual(false, request(new Map<String, String>{ 'c' => inv.Code__c, 'type' => 'side_effect', 'productName' => 'X' }).get('ok'));
        Assert.areEqual(false, request(new Map<String, String>{ 'c' => inv.Code__c, 'type' => 'side_effect', 'reaction' => 'Rash' }).get('ok'));
        Assert.areEqual(false, request(new Map<String, String>{ 'c' => inv.Code__c, 'type' => 'visit' }).get('ok'));
        Map<String, Object> anonymous = request(new Map<String, String>{ 'type' => 'visit', 'message' => 'Hi' });
        Assert.areEqual(false, anonymous.get('ok'));
        Assert.isTrue(String.valueOf(anonymous.get('message')).contains('mobile'));
        Assert.areEqual(0, [SELECT COUNT() FROM Case]);

        Map<String, Object> walkIn = request(new Map<String, String>{ 'type' => 'visit', 'message' => 'Hi', 'name' => 'Dr. Walk', 'phone' => '0123', 'email' => 'not-an-email' });
        Assert.areEqual(true, walkIn.get('ok'));
        Case c = [SELECT SuppliedEmail, HCP_App_Code__c FROM Case LIMIT 1];
        Assert.isNull(c.SuppliedEmail);
        Assert.isNull(c.HCP_App_Code__c);
    }

    @IsTest
    static void requestsAreRateLimitedPerHcp() {
        Meeting_Invitation__c inv = invitation();
        List<Case> earlier = new List<Case>();
        for (Integer i = 0; i < ZetaHcpRequestService.DAILY_LIMIT; i++) {
            earlier.add(new Case(Origin = 'HCP App', HCP_App_Code__c = inv.Code__c, Subject = 'Earlier ' + i));
        }
        insert earlier;
        Map<String, Object> res = request(new Map<String, String>{ 'c' => inv.Code__c, 'type' => 'visit', 'message' => 'One more' });
        Assert.areEqual(false, res.get('ok'));
        Assert.isTrue(String.valueOf(res.get('message')).contains('many requests'));
    }

    @IsTest
    static void helpersMapStatesAndAreas() {
        Assert.areEqual('Diabetes', ZetaHcpContentService.therapyArea(null, 'DIAB-IV'));
        Assert.areEqual('Neurology', ZetaHcpContentService.therapyArea('Neurology', 'CVM-I'));
        Assert.areEqual('Other', ZetaHcpContentService.therapyArea(null, null));
        Assert.areEqual('Mystery', ZetaHcpContentService.therapyArea(null, 'Mystery'));
        Assert.areEqual('Submitted', ZetaHcpContentService.requestState(new Case(Status = 'New')));
        Assert.isFalse(ZetaHcpContentService.hasProductRating(null));
        Assert.isFalse(ZetaHcpContentService.hasProductRating(new Account_Territory_Product_Fields__c()));
        Assert.isFalse(ZetaHcpContentService.hasProductRating(new Account_Territory_Product_Fields__c(Product_Matrix_Rating__c = ' ')));
        Assert.isTrue(ZetaHcpContentService.hasProductRating(new Account_Territory_Product_Fields__c(Product_Matrix_Rating__c = 'HH')));
        Assert.isTrue(ZetaHcpContentService.hasProductRating(new Account_Territory_Product_Fields__c(Adoption__c = 'M')));
        Assert.isTrue(ZetaHcpContentService.hasProductRating(new Account_Territory_Product_Fields__c(Loyalty__c = 'L')));
        Assert.isTrue(ZetaHcpContentService.hasProductRating(new Account_Territory_Product_Fields__c(Rx_Per_Week__c = 1)));
        Assert.isTrue(ZetaHcpContentService.hasProductRating(new Account_Territory_Product_Fields__c(Potential__c = 0)));
        Assert.isTrue(ZetaHcpContentService.hasProductRating(new Account_Territory_Product_Fields__c(Penetration__c = 4)));
        Assert.areEqual('In progress', ZetaHcpContentService.requestState(new Case(Status = 'In Progress')));
        Assert.areEqual('Answered', ZetaHcpContentService.requestState(new Case(Status = 'In Progress', Response_Text__c = 'Done')));
        Assert.isNull(ZetaHcpRequestService.clean('   ', 5));
        Assert.areEqual('abc', ZetaHcpRequestService.clean(' abcdef ', 3));
    }

    @IsTest
    static void ratedProductsFollowTheHcpOnAnyTerritory() {
        Account doctor = new Account(Name = 'Dr. Rated');
        Account other = new Account(Name = 'Dr. Other');
        insert new List<Account>{ doctor, other };

        Meeting_Invitation__c inv = invitation();
        Id attendeeRt = Schema.SObjectType.Meeting_Member__c.getRecordTypeInfosByDeveloperName().get('Attendee').getRecordTypeId();
        Meeting_Member__c member = new Meeting_Member__c(
            Meeting__c = inv.Meeting__c,
            Customer__c = doctor.Id,
            RecordTypeId = attendeeRt,
            Type__c = 'Participant',
            Status__c = 'Invited'
        );
        insert member;
        update new Meeting_Invitation__c(Id = inv.Id, Meeting_Member__c = member.Id);

        Product2 rated = new Product2(Name = 'Rated Brand', IsActive = true, Show_In_HCP_App__c = true, Therapy_Area__c = 'Neurology');
        Product2 plain = new Product2(Name = 'Unrated Brand', IsActive = true, Show_In_HCP_App__c = true, Therapy_Area__c = 'Dermatology');
        insert new List<Product2>{ rated, plain };
        Product2 cardizet = [SELECT Id FROM Product2 WHERE Name = 'Cardizet' LIMIT 1];
        Product2 hidden = [SELECT Id FROM Product2 WHERE Name = 'Hidden' LIMIT 1];

        insert new List<Account_Territory_Product_Fields__c>{
            new Account_Territory_Product_Fields__c(
                Account__c = doctor.Id,
                Product2_Id__c = String.valueOf(rated.Id).left(15),
                Territory2_Id__c = '0MNterritory000001',
                Adoption__c = 'H'
            ),
            new Account_Territory_Product_Fields__c(
                Account__c = doctor.Id,
                Product2_Id__c = String.valueOf(plain.Id),
                Territory2_Id__c = '0MNterritory000002'
            ),
            new Account_Territory_Product_Fields__c(
                Account__c = doctor.Id,
                Product2_Id__c = String.valueOf(cardizet.Id),
                Territory2_Id__c = '0MNterritory000003',
                Penetration__c = 2
            ),
            new Account_Territory_Product_Fields__c(
                Account__c = doctor.Id,
                Product2_Id__c = String.valueOf(hidden.Id),
                Territory2_Id__c = '0MNterritory000004',
                Loyalty__c = 'H'
            ),
            new Account_Territory_Product_Fields__c(
                Account__c = other.Id,
                Product2_Id__c = String.valueOf(plain.Id),
                Territory2_Id__c = '0MNterritory000005',
                Adoption__c = 'M'
            )
        };

        MeetingCheckInController page = open(new Map<String, String>{ 'c' => inv.Code__c });
        Map<String, Object> app = (Map<String, Object>) JSON.deserializeUntyped(page.appJson);
        Map<String, Boolean> ratedByName = new Map<String, Boolean>();
        for (Object row : (List<Object>) app.get('products')) {
            Map<String, Object> product = (Map<String, Object>) row;
            ratedByName.put((String) product.get('name'), (Boolean) product.get('rated'));
        }
        Assert.areEqual(true, ratedByName.get('Rated Brand'), 'A 15-character id on another territory still counts');
        Assert.areEqual(true, ratedByName.get('Cardizet'), 'Penetration alone is a rating');
        Assert.areEqual(false, ratedByName.get('Unrated Brand'), 'An empty row, or another doctor\'s rating, does not count');
        Assert.isFalse(ratedByName.containsKey('Hidden'), 'Products kept out of the app stay out');
    }

    @IsTest
    static void ratedDetailRollsUpToItsBrand() {
        Account doctor = new Account(Name = 'Dr. Helix');
        insert doctor;
        Meeting_Invitation__c inv = invitation();
        Id attendeeRt = Schema.SObjectType.Meeting_Member__c.getRecordTypeInfosByDeveloperName().get('Attendee').getRecordTypeId();
        Meeting_Member__c member = new Meeting_Member__c(
            Meeting__c = inv.Meeting__c,
            Customer__c = doctor.Id,
            RecordTypeId = attendeeRt,
            Type__c = 'Participant',
            Status__c = 'Invited'
        );
        insert member;
        update new Meeting_Invitation__c(Id = inv.Id, Meeting_Member__c = member.Id);

        Product2 brand = new Product2(
            Name = 'Helix Brand',
            IsActive = true,
            Show_In_HCP_App__c = true,
            Product_Type__c = 'Brand',
            Therapy_Area__c = 'Cardiology'
        );
        Product2 quiet = new Product2(
            Name = 'Quiet Brand',
            IsActive = true,
            Show_In_HCP_App__c = true,
            Product_Type__c = 'Brand',
            Therapy_Area__c = 'Dermatology'
        );
        insert new List<Product2>{ brand, quiet };
        Product2 detail = new Product2(
            Name = 'Helix Brand 10 mg',
            IsActive = true,
            Product_Type__c = 'Detail',
            Parent_Product__c = brand.Id,
            Strength__c = '10 MG',
            Form__c = 'Tablet'
        );
        Product2 quietDetail = new Product2(
            Name = 'Quiet Brand 5 mg',
            IsActive = true,
            Product_Type__c = 'Detail',
            Parent_Product__c = quiet.Id,
            Strength__c = '5 MG',
            Form__c = 'Capsule'
        );
        insert new List<Product2>{ detail, quietDetail };
        insert new Product2(
            Name = 'Helix Brand Sample',
            IsActive = true,
            Product_Type__c = 'Sample',
            Parent_Product__c = detail.Id
        );
        insert new Account_Territory_Product_Fields__c(
            Account__c = doctor.Id,
            Product2_Id__c = String.valueOf(detail.Id).left(15),
            Territory2_Id__c = '0MNterritory000009',
            Adoption__c = 'H'
        );

        MeetingCheckInController page = open(new Map<String, String>{ 'c' => inv.Code__c });
        Map<String, Object> app = (Map<String, Object>) JSON.deserializeUntyped(page.appJson);
        Map<String, Map<String, Object>> byName = new Map<String, Map<String, Object>>();
        for (Object row : (List<Object>) app.get('products')) {
            Map<String, Object> product = (Map<String, Object>) row;
            byName.put((String) product.get('name'), product);
        }
        Assert.areEqual(true, byName.get('Helix Brand').get('rated'), 'A rated detail makes the brand rated');
        Assert.areEqual('brand', byName.get('Helix Brand').get('kind'));
        Assert.areEqual(false, byName.get('Quiet Brand').get('rated'), 'An unrated detail leaves the brand unrated');
        Assert.areEqual('detail', byName.get('Helix Brand 10 mg').get('kind'));
        Assert.areEqual(String.valueOf(brand.Id), byName.get('Helix Brand 10 mg').get('brandId'));
        Assert.areEqual(true, byName.get('Helix Brand 10 mg').get('rated'));
        Assert.areEqual('Cardiology', byName.get('Helix Brand 10 mg').get('area'), 'A detail inherits its brand therapy area');
        Assert.isFalse(byName.containsKey('Helix Brand Sample'), 'Samples stay out of the catalogue');
        Assert.isFalse(byName.containsKey('Hidden'), 'Products kept out of the app stay out');
    }

    @IsTest
    static void pinFromHcpCodeSignsInAndShowsEvents() {
        String phone = localMobile('010');
        String externalId = 'PIN' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(10);
        Account doctor = pinDoctor(externalId, phone, 'farid.pin@example.com');
        Meeting_Invitation__c existing = invitation();
        Id attendeeRt = Schema.SObjectType.Meeting_Member__c.getRecordTypeInfosByDeveloperName().get('Attendee').getRecordTypeId();
        insert new Meeting_Member__c(
            Meeting__c = existing.Meeting__c,
            Customer__c = doctor.Id,
            RecordTypeId = attendeeRt,
            Type__c = 'Participant',
            Status__c = 'Invited'
        );
        Meeting_Member__c member = [SELECT Id FROM Meeting_Member__c WHERE Customer__c = :doctor.Id LIMIT 1];
        insert new Meeting_Invitation__c(
            Meeting__c = existing.Meeting__c,
            Meeting_Member__c = member.Id,
            Guest_Name__c = 'Dr. Farid',
            Phone__c = phone,
            Email__c = 'farid.pin@example.com'
        );

        Test.startTest();
        Map<String, Object> sent = pinCall(new Map<String, String>{ 'step' => 'send', 'who' => externalId.toLowerCase() });
        Assert.areEqual(1, Limits.getEmailInvocations());
        Test.stopTest();
        Assert.areEqual(true, sent.get('ok'));
        Assert.isNotNull(ZetaHcpSignInService.testPin);

        Map<String, Object> bad = pinCall(new Map<String, String>{
            'step' => 'check', 'who' => externalId, 'pin' => ZetaHcpSignInService.testPin == '000000' ? '111111' : '000000'
        });
        Assert.areEqual(false, bad.get('ok'));

        Map<String, Object> good = pinCall(new Map<String, String>{
            'step' => 'check', 'who' => externalId, 'pin' => ZetaHcpSignInService.testPin
        });
        Assert.areEqual(true, good.get('ok'), String.valueOf(good.get('message')));
        Assert.isNotNull(ZetaHcpSignInService.testSession);

        Test.setCurrentPage(Page.m);
        ApexPages.currentPage().setCookies(new List<Cookie>{
            new Cookie(ZetaHcpSignInService.COOKIE, ZetaHcpSignInService.testSession, '/', 3600, true, 'Lax')
        });
        MeetingCheckInController home = new MeetingCheckInController();
        Assert.isTrue(home.signedIn);
        Assert.isTrue(home.showEvents);
        Assert.isFalse(home.hasCode);
        Map<String, Object> app = (Map<String, Object>) JSON.deserializeUntyped(home.appJson);
        Map<String, Object> me = (Map<String, Object>) app.get('me');
        Assert.areEqual(true, me.get('known'));
        Assert.areEqual([SELECT Name FROM Account WHERE Id = :doctor.Id].Name, me.get('name'));
        Assert.isNull(me.get('code'), 'A PIN session must not pretend to be an invitation link');
        Assert.isTrue(((List<Object>) app.get('events')).size() > 0);
        Assert.isTrue(((List<Object>) app.get('news')).size() > 0);
        Assert.isTrue(((List<Object>) app.get('products')).size() > 0);
    }

    @IsTest
    static void pinFromMobileAndUnknownCode() {
        String phone = localMobile('011');
        Account doctor = pinDoctor('MOB' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(8), phone, 'mobile.pin@example.com');
        Test.startTest();
        Map<String, Object> sent = pinCall(new Map<String, String>{ 'step' => 'send', 'who' => '+20' + phone.substring(1) });
        Assert.isNotNull(ZetaHcpSignInService.testPin);
        Assert.areEqual(1, Limits.getEmailInvocations(), 'An unknown code does not send a PIN');
        Map<String, Object> unknown = pinCall(new Map<String, String>{ 'step' => 'send', 'who' => 'NO-SUCH-HCP' });
        Map<String, Object> blank = pinCall(new Map<String, String>{ 'step' => 'send', 'who' => '  ' });
        Test.stopTest();
        Assert.areEqual(true, sent.get('ok'));
        Assert.areEqual(doctor.Id, [SELECT Account__c FROM Hcp_App_Sign_In__c WHERE Kind__c = 'Pin' ORDER BY CreatedDate DESC LIMIT 1].Account__c);
        Assert.areEqual(true, unknown.get('ok'));
        Assert.isTrue(String.valueOf(unknown.get('message')).contains('If we recognise'));
        Assert.areEqual(false, blank.get('ok'));
    }

    @IsTest
    static void wrongPinLocksAfterFiveTries() {
        String externalId = 'LOCK' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(8);
        pinDoctor(externalId, '01255556677', 'lock.pin@example.com');
        pinCall(new Map<String, String>{ 'step' => 'send', 'who' => externalId });
        String pin = ZetaHcpSignInService.testPin;
        String wrong = pin.substring(0, 5) + (pin.substring(5, 6) == '0' ? '1' : '0');
        for (Integer i = 0; i < 5; i++) {
            Map<String, Object> bad = pinCall(new Map<String, String>{ 'step' => 'check', 'who' => externalId, 'pin' => wrong });
            Assert.areEqual(false, bad.get('ok'));
        }
        Map<String, Object> locked = pinCall(new Map<String, String>{ 'step' => 'check', 'who' => externalId, 'pin' => pin });
        Assert.areEqual(false, locked.get('ok'));
    }

    @IsTest
    static void queuedPinEmailStillSends() {
        String externalId = 'QUEUE' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(8);
        pinDoctor(externalId, '01544443333', 'queue.pin@example.com');
        ZetaHcpSignInService.failDirectEmail = true;
        Test.startTest();
        Map<String, Object> sent = pinCall(new Map<String, String>{ 'step' => 'send', 'who' => externalId });
        Test.stopTest();
        Assert.areEqual(true, sent.get('ok'));
        Assert.isNotNull(ZetaHcpSignInService.testPin);
        Integer before = Limits.getEmailInvocations();
        ZetaHcpSignInService.deliver(new List<Hcp_Pin_Send__e>{
            new Hcp_Pin_Send__e(Email__c = 'direct.pin@example.com', Pin__c = '123456', Guest_Name__c = 'Dr Farid')
        });
        Assert.areEqual(before + 1, Limits.getEmailInvocations());
    }

    static Map<String, Object> pinCall(Map<String, String> params) {
        Map<String, String> all = new Map<String, String>{ 'a' => 'pin' };
        all.putAll(params);
        MeetingCheckInController page = open(all);
        Assert.areEqual('api', page.view);
        return (Map<String, Object>) JSON.deserializeUntyped(page.apiJson);
    }

    static String localMobile(String prefix) {
        String digits = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).replaceAll('[^0-9]', '');
        while (digits.length() < 8) {
            digits += '48275913';
        }
        return prefix + digits.left(8);
    }

    static Account pinDoctor(String externalId, String phone, String email) {
        Account row = new Account(External_ID__c = externalId, WhatsApp_Number__c = phone);
        Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Medical_Professional_HCP');
        Boolean person = false;
        if (info != null) {
            row.RecordTypeId = info.getRecordTypeId();
            person = [SELECT IsPersonType FROM RecordType WHERE Id = :info.getRecordTypeId()].IsPersonType;
        }
        if (person) {
            row.LastName = 'Farid';
            row.PersonEmail = email;
            row.PersonMobilePhone = phone;
        } else {
            row.Name = 'Dr. Farid';
            row.Phone = phone;
            row.Email__c = email;
        }
        insert row;
        return row;
    }
}
