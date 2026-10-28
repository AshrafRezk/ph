/**
 * Care Coach Co-pilot access model.
 * PSP team (custom permission PSP_Full_Patient_Access) sees identified patients.
 * Everyone else (pharma company) only ever receives de-identified data.
 * A PSP user may request the company view to preview it; the reverse is never allowed.
 */
public with sharing class CareCoachAccess {
    public static final String FULL_ACCESS_PERMISSION = 'PSP_Full_Patient_Access';
    public static final String MODE_PSP = 'psp';
    public static final String MODE_COMPANY = 'company';
    public static final String SCOPE_MINE = 'mine';
    public static final String SCOPE_ALL = 'all';

    @TestVisible
    private static Boolean fullAccessOverride;
    @TestVisible
    private static Boolean supervisorOverride;

    public class Context {
        @AuraEnabled public Boolean hasFullAccess;
        @AuraEnabled public Boolean isSupervisor;
        @AuraEnabled public Boolean isCompanyViewer;
        @AuraEnabled public String defaultScope;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String firstName;
    }

    @AuraEnabled(cacheable=true)
    public static Context getContext() {
        Context ctx = new Context();
        ctx.hasFullAccess = hasFullAccess();
        ctx.isSupervisor = isSupervisor();
        ctx.isCompanyViewer = !ctx.hasFullAccess;
        ctx.defaultScope = (ctx.isSupervisor || ctx.isCompanyViewer) ? SCOPE_ALL : SCOPE_MINE;
        ctx.userId = UserInfo.getUserId();
        ctx.userName = UserInfo.getName();
        ctx.firstName = UserInfo.getFirstName();
        return ctx;
    }

    public static Boolean hasFullAccess() {
        if (fullAccessOverride != null) {
            return fullAccessOverride;
        }
        return FeatureManagement.checkPermission(FULL_ACCESS_PERMISSION);
    }

    public static Boolean isSupervisor() {
        if (supervisorOverride != null) {
            return supervisorOverride;
        }
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSet.Name = 'PSP_Supervisor'
        ] > 0;
    }

    public static String resolveMode(String requested) {
        if (!hasFullAccess()) {
            return MODE_COMPANY;
        }
        return requested == MODE_COMPANY ? MODE_COMPANY : MODE_PSP;
    }

    public static Boolean isMasked(String requestedMode) {
        return resolveMode(requestedMode) == MODE_COMPANY;
    }

    /** Coaches without supervisor rights are always limited to their own patients. */
    public static String resolveScope(String requested) {
        if (!hasFullAccess()) {
            return SCOPE_ALL;
        }
        if (!isSupervisor()) {
            return SCOPE_MINE;
        }
        return requested == SCOPE_MINE ? SCOPE_MINE : SCOPE_ALL;
    }

    public static void assertCanEdit() {
        if (!hasFullAccess()) {
            throw fail('The pharma company view is read-only.');
        }
    }

    public class CareCoachException extends Exception {}

    /**
     * AuraHandledException hides its message outside Lightning, so the Apex REST
     * endpoint used by the offline app gets a plain exception instead.
     */
    public static Exception fail(String message) {
        if (Request.getCurrent().getQuiddity() == Quiddity.REST) {
            return new CareCoachException(message);
        }
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    private static final Pattern PHONE_PATTERN = Pattern.compile('(\\+?\\d[\\d\\s\\-]{7,}\\d)');
    private static final Pattern EMAIL_PATTERN = Pattern.compile('[\\w.+-]+@[\\w-]+\\.[\\w.]+');

    /** Strips phone numbers and emails from free text shown to the pharma company. */
    public static String redact(String text) {
        if (String.isBlank(text)) {
            return text;
        }
        String out = PHONE_PATTERN.matcher(text).replaceAll('[redacted phone]');
        return EMAIL_PATTERN.matcher(out).replaceAll('[redacted email]');
    }
}