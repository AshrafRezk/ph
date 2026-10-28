/**
 * Meeting invitations: short check-in codes, the public invitation link, WhatsApp and email delivery,
 * and the rotating door QR. The link opens the public "m" page on the onboard site, where the guest
 * confirms and shows a QR that is re-signed every minute; staff scan it to check the guest in.
 */
public without sharing class MeetingInvitationService {
    static final String ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789';
    @TestVisible static final Integer CODE_LENGTH = 6;
    @TestVisible static final String TEST_SITE_BASE = 'https://example.com/meet';
    /** The meet site serves the "m" page as its home page; other paths on this org's sites are not reachable by guests. */
    static final String SITE_PREFIX = 'meet';
    static final String EMAIL_LOGO_URL = 'https://zetapharma.net/wp-content/uploads/2022/07/zeta-logo.png';
    public static final String TOKEN_PREFIX = 'ZM1';
    public static final Integer TOKEN_STEP_SECONDS = 60;
    /** A code stays valid for its own minute plus one minute either side, so a flip mid-scan still checks in. */
    @TestVisible static final Integer TOKEN_GRACE_STEPS = 1;
    /** Offline door scans older than this when they sync are judged at sync time instead. */
    static final Long OFFLINE_SCAN_MAX_AGE_MS = 7L * 24 * 60 * 60 * 1000;

    public static final String SCAN_CHECKED_IN = 'checked_in';
    public static final String SCAN_ALREADY = 'already';
    public static final String SCAN_EXPIRED = 'expired';
    public static final String SCAN_INVALID = 'invalid';
    public static final String SCAN_OTHER_MEETING = 'other_meeting';
    public static final String SCAN_INACTIVE = 'inactive';
    public static final String SCAN_CLOSED = 'closed';

    public class InvitationException extends Exception {}

    public class ScanResult {
        @AuraEnabled public String outcome;
        @AuraEnabled public Boolean ok;
        @AuraEnabled public String title;
        @AuraEnabled public String message;
        @AuraEnabled public Id invitationId;
        @AuraEnabled public String guestName;
        @AuraEnabled public DateTime checkedInAt;
        @AuraEnabled public Integer checkedInCount;
        @AuraEnabled public Integer invitedCount;
    }

    public class InvitationRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id memberId;
        @AuraEnabled public String code;
        @AuraEnabled public String guestName;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean active;
        @AuraEnabled public DateTime sentAt;
        @AuraEnabled public DateTime checkedInAt;
        @AuraEnabled public Integer scans;
        @AuraEnabled public String link;
        @AuraEnabled public String whatsappUrl;
    }

    // ---------------------------------------------------------------- codes

    public static void assignCodes(List<Meeting_Invitation__c> rows) {
        List<Meeting_Invitation__c> blank = new List<Meeting_Invitation__c>();
        for (Meeting_Invitation__c row : rows) {
            if (String.isBlank(row.Qr_Secret__c)) {
                row.Qr_Secret__c = newSecret();
            }
            if (String.isBlank(row.Code__c)) {
                blank.add(row);
            } else {
                row.Code__c = row.Code__c.trim();
            }
        }
        if (blank.isEmpty()) {
            return;
        }
        Set<String> candidates = new Set<String>();
        while (candidates.size() < blank.size() * 2) {
            candidates.add(randomCode());
        }
        Set<String> taken = new Set<String>();
        for (Meeting_Invitation__c existing : [SELECT Code__c FROM Meeting_Invitation__c WHERE Code__c IN :candidates]) {
            taken.add(existing.Code__c.toLowerCase());
        }
        candidates.removeAll(taken);
        List<String> free = new List<String>(candidates);
        for (Integer i = 0; i < blank.size(); i++) {
            blank[i].Code__c = i < free.size() ? free[i] : randomCode() + randomCode().left(2);
        }
    }

    static String randomCode() {
        String code = '';
        for (Integer i = 0; i < CODE_LENGTH; i++) {
            Integer idx = Math.abs(Math.mod(Crypto.getRandomInteger(), ALPHABET.length()));
            code += ALPHABET.substring(idx, idx + 1);
        }
        return code;
    }

    // ---------------------------------------------------------------- rotating door QR

    public static String newSecret() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(256));
    }

    /** Gives older invitations a signing key the first time their page is opened. */
    public static String ensureSecret(Meeting_Invitation__c invitation) {
        if (String.isBlank(invitation.Qr_Secret__c)) {
            invitation.Qr_Secret__c = newSecret();
            update new Meeting_Invitation__c(Id = invitation.Id, Qr_Secret__c = invitation.Qr_Secret__c);
        }
        return invitation.Qr_Secret__c;
    }

    /** Must match the signature computed by the public "m" page: HMAC-SHA256(secret, code:step), first 16 hex. */
    public static String tokenMac(String secret, String code, Long step) {
        Blob mac = Crypto.generateMac('hmacSHA256', Blob.valueOf(code + ':' + step), Blob.valueOf(secret));
        return EncodingUtil.convertToHex(mac).left(16);
    }

    public static Long tokenStep(Long millis) {
        return millis / (TOKEN_STEP_SECONDS * 1000L);
    }

    @TestVisible
    static String buildToken(String secret, String code, Long step) {
        return TOKEN_PREFIX + ':' + code + ':' + step + ':' + tokenMac(secret, code, step);
    }

    /** Checks a scanned door QR for this meeting and checks the guest in when it is genuine and fresh. */
    public static ScanResult scan(Meeting__c meeting, String payload, Long nowMillis) {
        return scanAt(meeting, payload, nowMillis, nowMillis);
    }

    /**
     * Same checks as scan(), judged at the moment the device scanned the code rather than when it reached
     * the server, so a door scan saved offline keeps its real arrival time when it syncs later.
     */
    public static ScanResult scanAt(Meeting__c meeting, String payload, Long scannedAtMillis, Long receivedMillis) {
        Boolean plausible = scannedAtMillis != null && scannedAtMillis <= receivedMillis
            && scannedAtMillis >= receivedMillis - OFFLINE_SCAN_MAX_AGE_MS;
        Long nowMillis = plausible ? scannedAtMillis : receivedMillis;
        ScanResult result = new ScanResult();
        List<String> parts = String.isBlank(payload) ? new List<String>() : payload.trim().split(':');
        if (parts.size() != 4 || parts[0] != TOKEN_PREFIX || !parts[2].isNumeric() || parts[1].length() > 16) {
            return finish(result, meeting, SCAN_INVALID, 'Not a Zeta invitation',
                'This QR is not a meeting check-in code. Ask the guest to open their invitation link.', null);
        }
        Meeting_Invitation__c invitation = findByCode(parts[1]);
        if (invitation == null || String.isBlank(invitation.Qr_Secret__c)) {
            return finish(result, meeting, SCAN_INVALID, 'Unknown invitation', 'This code does not match any invitation.', null);
        }
        Long step = Long.valueOf(parts[2]);
        if (tokenMac(invitation.Qr_Secret__c, invitation.Code__c, step) != parts[3].toLowerCase()) {
            return finish(result, meeting, SCAN_INVALID, 'Code not genuine', 'This QR was altered or copied. Ask the guest to open their invitation link.', invitation);
        }
        if (invitation.Meeting__c != meeting.Id) {
            return finish(result, meeting, SCAN_OTHER_MEETING, 'Different meeting', invitation.Guest_Name__c + ' is invited to another meeting.', invitation);
        }
        if (invitation.Active__c != true) {
            return finish(result, meeting, SCAN_INACTIVE, 'Invitation turned off', 'The organizer turned this invitation off.', invitation);
        }
        if (invitation.Status__c == 'Checked In') {
            return finish(result, meeting, SCAN_ALREADY, 'Already checked in',
                invitation.Guest_Name__c + ' checked in at ' + invitation.Checked_In_At__c.format('h:mm a', 'Africa/Cairo') + '.', invitation);
        }
        if (Math.abs(tokenStep(nowMillis) - step) > TOKEN_GRACE_STEPS) {
            return finish(result, meeting, SCAN_EXPIRED, 'Code expired',
                'This looks like a screenshot. Ask the guest to show the live code on their phone.', invitation);
        }
        if (meeting.Status__c == 'Cancelled' || !isCheckInWindow(meeting, DateTime.newInstance(nowMillis))) {
            String window = 'Check-in opens 12 hours before the meeting and closes 6 hours after it ends.';
            if (meeting.Status__c != 'Cancelled' && meeting.Start_Date_Time__c != null && DateTime.newInstance(nowMillis) < checkInOpens(meeting)) {
                window = 'Door check-in opens ' + checkInOpens(meeting).format('EEE d MMM, h:mm a', 'Africa/Cairo') + '.';
            }
            return finish(result, meeting, SCAN_CLOSED, 'Check-in is not open', window, invitation);
        }
        checkIn(invitation, DateTime.newInstance(nowMillis));
        return finish(result, meeting, SCAN_CHECKED_IN, 'Welcome, ' + invitation.Guest_Name__c, 'Checked in.', invitation);
    }

    static ScanResult finish(ScanResult result, Meeting__c meeting, String outcome, String title, String message, Meeting_Invitation__c invitation) {
        result.outcome = outcome;
        result.ok = outcome == SCAN_CHECKED_IN;
        result.title = title;
        result.message = message;
        if (invitation != null) {
            result.invitationId = invitation.Id;
            result.guestName = invitation.Guest_Name__c;
            result.checkedInAt = invitation.Checked_In_At__c;
        }
        result.invitedCount = [SELECT COUNT() FROM Meeting_Invitation__c WHERE Meeting__c = :meeting.Id AND Active__c = true];
        result.checkedInCount = [SELECT COUNT() FROM Meeting_Invitation__c WHERE Meeting__c = :meeting.Id AND Status__c = 'Checked In'];
        return result;
    }

    public static Meeting_Invitation__c findByCode(String code) {
        if (String.isBlank(code) || code.length() > 16) {
            return null;
        }
        code = code.trim();
        for (Meeting_Invitation__c row : [
            SELECT Id, Meeting__c, Meeting_Member__c, Code__c, Guest_Name__c, Status__c, Active__c,
                Checked_In_At__c, Qr_Secret__c
            FROM Meeting_Invitation__c
            WHERE Code__c = :code
            LIMIT 20
        ]) {
            if (row.Code__c.equals(code)) {
                return row;
            }
        }
        return null;
    }

    // ---------------------------------------------------------------- links

    public static String siteBase() {
        if (Test.isRunningTest()) {
            return TEST_SITE_BASE;
        }
        List<Site> sites = [SELECT Id FROM Site WHERE UrlPathPrefix = :SITE_PREFIX AND Status = 'Active' LIMIT 1];
        if (sites.isEmpty()) {
            return null;
        }
        List<SiteDetail> details = [SELECT SecureUrl FROM SiteDetail WHERE DurableId = :sites[0].Id LIMIT 1];
        return details.isEmpty() ? null : details[0].SecureUrl;
    }

    public static String checkInLink(String base, String code) {
        if (String.isBlank(base) || String.isBlank(code)) {
            return null;
        }
        return base.removeEnd('/') + '/?c=' + code;
    }

    public static String whatsappUrl(Meeting__c meeting, Meeting_Invitation__c invitation, String link) {
        String text = message(meeting, invitation.Guest_Name__c, link);
        String phone = digits(invitation.Phone__c);
        return 'https://wa.me/' + phone + '?text=' + EncodingUtil.urlEncode(text, 'UTF-8').replace('+', '%20');
    }

    @TestVisible
    static String message(Meeting__c meeting, String guestName, String link) {
        String title = String.isNotBlank(meeting.Objectives__c) ? meeting.Objectives__c.left(120) : meeting.Name;
        String timing = meeting.Start_Date_Time__c == null
            ? ''
            : ' on ' + meeting.Start_Date_Time__c.format('EEE d MMM yyyy, h:mm a', 'Africa/Cairo');
        String place = String.isBlank(meeting.Venue__c) ? '' : ' at ' + meeting.Venue__c;
        String hello = String.isBlank(guestName) ? 'Hello' : 'Hello ' + guestName;
        return hello + ', you are invited to ' + title + timing + place + '.\n'
            + 'Please confirm here. At the entrance, open the same link and show the live QR code:\n' + link + '\n\n'
            + 'نتشرف بدعوتكم. برجاء تأكيد الحضور من الرابط، وعند الوصول افتح الرابط واعرض رمز QR.';
    }

    public static InvitationRow sendEmail(Id invitationId, String email) {
        Meeting_Invitation__c invitation = loadInvitation(invitationId);
        if (String.isNotBlank(email)) {
            invitation.Email__c = email.trim();
        }
        if (String.isBlank(invitation.Email__c)) {
            throw new InvitationException('Enter the guest email address.');
        }
        String base = siteBase();
        String link = checkInLink(base, invitation.Code__c);
        if (link == null) {
            throw new InvitationException('The public check-in site is not active.');
        }
        Meeting__c meeting = MeetingApprovalChainService.loadMeeting(invitation.Meeting__c);
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ invitation.Email__c });
        mail.setSubject('Invitation: ' + title(meeting));
        mail.setPlainTextBody(message(meeting, invitation.Guest_Name__c, link));
        mail.setHtmlBody(emailHtml(meeting, invitation.Guest_Name__c, link, base));
        mail.setSaveAsActivity(false);
        mail.setSenderDisplayName('Zeta Pharma');
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });

        if (invitation.Status__c == 'Not Sent' || String.isBlank(invitation.Status__c)) {
            invitation.Status__c = 'Sent';
        }
        invitation.Sent_At__c = System.now();
        update invitation;
        return toRow(meeting, loadInvitation(invitationId), base);
    }

    static String title(Meeting__c meeting) {
        return String.isNotBlank(meeting.Objectives__c) ? meeting.Objectives__c.left(120) : meeting.Name;
    }

    @TestVisible
    static String emailHtml(Meeting__c meeting, String guestName, String link, String base) {
        String timing = meeting.Start_Date_Time__c == null
            ? ''
            : meeting.Start_Date_Time__c.format('EEEE d MMMM yyyy, h:mm a', 'Africa/Cairo');
        String row = '<tr><td style="padding:6px 0;color:#706e6b;font-size:12px;text-transform:uppercase;letter-spacing:.04em">{0}</td></tr>'
            + '<tr><td style="padding:0 0 12px;font-size:15px;color:#181818">{1}</td></tr>';
        String facts = '';
        if (String.isNotBlank(timing)) {
            facts += String.format(row, new List<String>{ 'When', timing.escapeHtml4() });
        }
        if (String.isNotBlank(meeting.Venue__c)) {
            facts += String.format(row, new List<String>{ 'Where', meeting.Venue__c.escapeHtml4() });
        }
        String hello = String.isBlank(guestName) ? 'Hello' : 'Hello ' + guestName.escapeHtml4();
        return '<div style="background:#f4f6f9;padding:24px 12px;font-family:-apple-system,Segoe UI,Arial,sans-serif">'
            + '<table role="presentation" width="100%" style="max-width:520px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden">'
            + '<tr><td style="padding:20px 24px 16px;border-bottom:4px solid #0b5cab">'
            + '<img src="' + EMAIL_LOGO_URL + '" alt="Zeta Pharma" height="40" style="display:block;height:40px;width:auto" /></td></tr>'
            + '<tr><td style="padding:24px">'
            + '<div style="font-size:12px;font-weight:800;color:#0b5cab;text-transform:uppercase;letter-spacing:.06em">You are invited</div>'
            + '<h1 style="margin:6px 0 4px;font-size:22px;color:#032d60">' + title(meeting).escapeHtml4() + '</h1>'
            + '<p style="margin:0 0 16px;color:#444">' + hello + '</p>'
            + '<table role="presentation" width="100%">' + facts + '</table>'
            + '<a href="' + link + '" style="display:block;text-align:center;background:#0b5cab;color:#fff;text-decoration:none;font-weight:800;padding:14px;border-radius:999px;margin:8px 0 14px">Open my invitation</a>'
            + '<p style="margin:0;color:#706e6b;font-size:13px;text-align:center">Confirm your attendance from the link. At the entrance, open it again and show the live QR code.</p>'
            + '<p dir="rtl" style="margin:10px 0 0;color:#444;font-size:13px;text-align:center">برجاء تأكيد الحضور من الرابط، وعند الوصول افتح الرابط واعرض رمز QR.</p>'
            + '</td></tr></table></div>';
    }

    @TestVisible
    static String digits(String phone) {
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

    // ---------------------------------------------------------------- invitations

    public static List<InvitationRow> listForMeeting(Meeting__c meeting) {
        String base = siteBase();
        List<InvitationRow> rows = new List<InvitationRow>();
        for (Meeting_Invitation__c invitation : [
            SELECT Id, Meeting_Member__c, Code__c, Guest_Name__c, Phone__c, Email__c, Status__c, Active__c,
                Sent_At__c, Checked_In_At__c, Scans__c
            FROM Meeting_Invitation__c
            WHERE Meeting__c = :meeting.Id
            ORDER BY Guest_Name__c ASC
            LIMIT 500
        ]) {
            rows.add(toRow(meeting, invitation, base));
        }
        return rows;
    }

    public static InvitationRow toRow(Meeting__c meeting, Meeting_Invitation__c invitation, String base) {
        InvitationRow row = new InvitationRow();
        row.id = invitation.Id;
        row.memberId = invitation.Meeting_Member__c;
        row.code = invitation.Code__c;
        row.guestName = invitation.Guest_Name__c;
        row.phone = invitation.Phone__c;
        row.email = invitation.Email__c;
        row.status = invitation.Status__c;
        row.active = invitation.Active__c;
        row.sentAt = invitation.Sent_At__c;
        row.checkedInAt = invitation.Checked_In_At__c;
        row.scans = invitation.Scans__c == null ? 0 : invitation.Scans__c.intValue();
        row.link = checkInLink(base, invitation.Code__c);
        row.whatsappUrl = row.link == null ? null : whatsappUrl(meeting, invitation, row.link);
        return row;
    }

    /** Creates one invitation per meeting member that does not have one yet. */
    public static Integer inviteMembers(Id meetingId) {
        Set<Id> invited = new Set<Id>();
        for (Meeting_Invitation__c existing : [
            SELECT Meeting_Member__c FROM Meeting_Invitation__c WHERE Meeting__c = :meetingId AND Meeting_Member__c != NULL
        ]) {
            invited.add(existing.Meeting_Member__c);
        }
        List<Meeting_Invitation__c> created = new List<Meeting_Invitation__c>();
        for (Meeting_Member__c member : [
            SELECT Id, Customer__r.Name, Customer__r.Phone, Customer__r.PersonEmail, Colleague__r.Name,
                Colleague__r.MobilePhone, Colleague__r.Phone, Colleague__r.Email, Write_In_Name__c, Type__c
            FROM Meeting_Member__c
            WHERE Meeting__c = :meetingId
            LIMIT 500
        ]) {
            if (invited.contains(member.Id) || member.Type__c == 'Approver' || member.Type__c == 'Second Approver') {
                continue;
            }
            created.add(new Meeting_Invitation__c(
                Meeting__c = meetingId,
                Meeting_Member__c = member.Id,
                Guest_Name__c = MeetingApprovalChainService.trimTo(memberName(member), 120),
                Phone__c = memberPhone(member),
                Email__c = memberEmail(member)
            ));
        }
        if (!created.isEmpty()) {
            insert created;
        }
        return created.size();
    }

    public static Id addGuest(Id meetingId, String guestName, String phone) {
        return addGuest(meetingId, guestName, phone, null);
    }

    public static Id addGuest(Id meetingId, String guestName, String phone, String email) {
        if (String.isBlank(guestName)) {
            throw new InvitationException('Enter the guest name.');
        }
        Meeting_Invitation__c invitation = new Meeting_Invitation__c(
            Meeting__c = meetingId,
            Guest_Name__c = MeetingApprovalChainService.trimTo(guestName.trim(), 120),
            Phone__c = String.isBlank(phone) ? null : phone.trim(),
            Email__c = String.isBlank(email) ? null : email.trim()
        );
        insert invitation;
        return invitation.Id;
    }

    public static InvitationRow markSent(Id invitationId, String phone) {
        Meeting_Invitation__c invitation = loadInvitation(invitationId);
        if (String.isNotBlank(phone)) {
            invitation.Phone__c = phone.trim();
        }
        if (invitation.Status__c == 'Not Sent' || String.isBlank(invitation.Status__c)) {
            invitation.Status__c = 'Sent';
        }
        invitation.Sent_At__c = System.now();
        update invitation;
        Meeting__c meeting = MeetingApprovalChainService.loadMeeting(invitation.Meeting__c);
        return toRow(meeting, loadInvitation(invitationId), siteBase());
    }

    public static void setActive(Id invitationId, Boolean active) {
        Meeting_Invitation__c invitation = loadInvitation(invitationId);
        invitation.Active__c = active == true;
        update invitation;
    }

    public static Meeting_Invitation__c loadInvitation(Id invitationId) {
        List<Meeting_Invitation__c> rows = [
            SELECT Id, Meeting__c, Meeting_Member__c, Code__c, Guest_Name__c, Phone__c, Email__c, Status__c, Active__c,
                Sent_At__c, Checked_In_At__c, Scans__c
            FROM Meeting_Invitation__c
            WHERE Id = :invitationId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new InvitationException('Invitation not found.');
        }
        return rows[0];
    }

    // ---------------------------------------------------------------- attendance

    public static void confirm(Meeting_Invitation__c invitation) {
        if (invitation.Status__c == 'Checked In' || invitation.Status__c == 'Confirmed') {
            return;
        }
        invitation.Status__c = 'Confirmed';
        update invitation;
        if (invitation.Meeting_Member__c != null) {
            update new Meeting_Member__c(Id = invitation.Meeting_Member__c, Status__c = 'Accepted');
        }
    }

    public static void checkIn(Meeting_Invitation__c invitation) {
        checkIn(invitation, System.now());
    }

    public static void checkIn(Meeting_Invitation__c invitation, DateTime arrivedAt) {
        if (invitation.Status__c == 'Checked In') {
            return;
        }
        invitation.Status__c = 'Checked In';
        invitation.Checked_In_At__c = arrivedAt == null ? System.now() : arrivedAt;
        update invitation;
        if (invitation.Meeting_Member__c != null) {
            update new Meeting_Member__c(
                Id = invitation.Meeting_Member__c,
                Status__c = 'Accepted',
                Attendance_Status__c = 'Attended'
            );
        }
    }

    public static DateTime checkInOpens(Meeting__c meeting) {
        return meeting.Start_Date_Time__c.addHours(-12);
    }

    public static Boolean isCheckInWindow(Meeting__c meeting, DateTime now) {
        if (meeting.Start_Date_Time__c == null) {
            return false;
        }
        DateTime opens = checkInOpens(meeting);
        DateTime closes = (meeting.End_Date_Time__c == null ? meeting.Start_Date_Time__c : meeting.End_Date_Time__c).addHours(6);
        return now >= opens && now <= closes;
    }

    private static String memberName(Meeting_Member__c member) {
        if (member.Customer__r != null) {
            return member.Customer__r.Name;
        }
        if (member.Colleague__r != null) {
            return member.Colleague__r.Name;
        }
        return String.isBlank(member.Write_In_Name__c) ? 'Guest' : member.Write_In_Name__c;
    }

    private static String memberPhone(Meeting_Member__c member) {
        if (member.Customer__r != null) {
            return member.Customer__r.Phone;
        }
        if (member.Colleague__r != null) {
            return String.isBlank(member.Colleague__r.MobilePhone) ? member.Colleague__r.Phone : member.Colleague__r.MobilePhone;
        }
        return null;
    }

    private static String memberEmail(Meeting_Member__c member) {
        if (member.Customer__r != null) {
            return member.Customer__r.PersonEmail;
        }
        if (member.Colleague__r != null) {
            return member.Colleague__r.Email;
        }
        return null;
    }
}
