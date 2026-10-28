public without sharing class PatientOnboardingController {
    public String token { get; set; }
    public PatientOnboardingService.Form form { get; set; }
    public Boolean invalid { get; set; }
    public Boolean submitted { get; set; }
    public String message { get; set; }

    public PatientOnboardingController() {
        token = ApexPages.currentPage().getParameters().get('t');
        form = PatientOnboardingService.loadForm(token);
        invalid = form == null;
        submitted = false;
    }

    public void save() {
        message = PatientOnboardingService.saveForm(token, form);
        submitted = message == null;
    }
}