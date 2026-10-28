@IsTest
private class PatientOnboardingTests {
    @IsTest
    static void publicFormAndCoachSend() {
        CareCoachAccess.fullAccessOverride = true;
        Product2 product = new Product2(Name = 'Erbitux', ProductCode = 'PSP-ERBITUX', IsActive = true, Therapy_Area__c = 'Oncology');
        insert product;
        Patient__c patient = new Patient__c(
            First_Name__c = 'Mona',
            Last_Name__c = 'Hassan',
            Email__c = 'mona.onboard@example.com',
            Mobile__c = '+20 111 555 0099',
            Status__c = 'Ongoing',
            Primary_Product__c = product.Id,
            Care_Coach__c = UserInfo.getUserId()
        );
        insert patient;

        PatientOnboardingService.Dispatch mail = PatientOnboardingService.sendEmail(patient.Id);
        System.assert(mail.url.contains('PatientOnboarding?t='));
        PatientOnboardingService.Dispatch wa = PatientOnboardingService.logWhatsApp(patient.Id);
        System.assert(wa.whatsappUrl.startsWith('https://wa.me/20111'));

        String token = [SELECT Onboarding_Token__c FROM Patient__c WHERE Id = :patient.Id].Onboarding_Token__c;
        System.assertEquals(null, PatientOnboardingService.loadForm('not-a-real-token'));
        PatientOnboardingService.Form form = PatientOnboardingService.loadForm(token);
        System.assertEquals('Mona', form.firstName);
        form.consent = false;
        form.allergies = 'Penicillin';
        System.assertNotEquals(null, PatientOnboardingService.saveForm(token, form));
        form.consent = true;
        System.assertEquals(null, PatientOnboardingService.saveForm(token, form));

        Patient__c saved = [
            SELECT Allergies__c, Consent_Given__c, Onboarding_Completed_On__c, Last_Call_Status__c
            FROM Patient__c
            WHERE Id = :patient.Id
        ];
        System.assertEquals('Penicillin', saved.Allergies__c);
        System.assertEquals(true, saved.Consent_Given__c);
        System.assertNotEquals(null, saved.Onboarding_Completed_On__c);
        System.assertEquals(null, saved.Last_Call_Status__c);

        PageReference pageRef = Page.PatientOnboarding;
        pageRef.getParameters().put('t', token);
        Test.setCurrentPage(pageRef);
        PatientOnboardingController page = new PatientOnboardingController();
        System.assertEquals(false, page.invalid);
        page.save();
        System.assertEquals(true, page.submitted);

        PatientOnboardingService.Snapshot snap = PatientOnboardingService.history(patient.Id);
        System.assertEquals('Penicillin', snap.allergies);
        System.assertEquals('201115550099', PatientOnboardingService.digits('01115550099'));
    }
}