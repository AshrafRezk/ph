/**
 * Backs the public "m" page, the home page of the meet site: /meet/?c={code}. It is the Zeta app for HCPs:
 * Home, Products, News, Events and Requests tabs, plus the invitation with its per-minute door QR that staff
 * scan to check the guest in. Runs without sharing because the site guest user has no access to these records.
 * Site guests here can only reach the home page itself (no /resource, form post or remoting paths), so
 * everything is served from that one URL: assets are inlined, confirming is ?a=confirm, the status poll
 * is ?s=1, requests are a POST to ?a=request (JSON reply), signing in without a personal link is a POST
 * to ?a=pin, and the PWA files are ?f=manifest (web app manifest), ?f=sw (service worker) and ?f=ics
 * (calendar event with reminders).
 */
public without sharing class MeetingCheckInController {
    static final Pattern BOT = Pattern.compile(
        '(?i).*(bot|crawl|spider|slurp|preview|facebookexternalhit|whatsapp|telegram|skype|discord|'
        + 'embedly|vkshare|pinterest|google-|bingpreview|headless|curl|wget|python|java/|okhttp|go-http|axios|node-fetch).*'
    );

    public Boolean invalid { get; private set; }
    public Boolean cancelled { get; private set; }
    public String guestName { get; private set; }
    public String meetingTitle { get; private set; }
    public String whenText { get; private set; }
    public String venue { get; private set; }
    public String status { get; private set; }
    public Boolean canConfirm { get; private set; }
    public Boolean showQr { get; private set; }
    public Boolean doorOpen { get; private set; }
    public Boolean checkedIn { get; private set; }
    public String checkedInText { get; private set; }
    public String message { get; private set; }
    public String code { get; private set; }
    public String qrSecret { get; private set; }
    public Boolean statusOnly { get; private set; }
    /** True when the link carried a personal code, even an invalid one. */
    public Boolean hasCode { get; private set; }
    /** True when a PIN session cookie identifies the HCP. */
    public Boolean signedIn { get; private set; }
    /** Events and meetings stay hidden until a personal link or a PIN session is present, and HCP Portal allows Events. */
    public Boolean showEvents {
        get {
            return hcpTabEnabled('hcp.events') && (invalid != true || signedIn == true);
        }
    }
    public Boolean showHcpProducts {
        get {
            return hcpTabEnabled('hcp.products');
        }
    }
    public Boolean showHcpNews {
        get {
            return hcpTabEnabled('hcp.news');
        }
    }
    public Boolean showHcpHome {
        get {
            return hcpTabEnabled('hcp.home');
        }
    }
    public Boolean showHcpRequests {
        get {
            return hcpTabEnabled('hcp.requests');
        }
    }
    /** page, status, api, manifest, sw or ics. */
    public String view { get; private set; }
    public String apiJson { get; private set; }
    public String contentType {
        get {
            switch on view {
                when 'api' { return 'application/json'; }
                when 'manifest' { return 'application/manifest+json'; }
                when 'sw' { return 'text/javascript'; }
                when 'ics' { return 'text/calendar'; }
                when 'status' { return 'text/plain'; }
                when else { return 'text/html'; }
            }
        }
    }
    public String manifestJson {
        get {
            String start = invalid ? './' : './?c=' + EncodingUtil.urlEncode(code, 'UTF-8');
            return JSON.serialize(new Map<String, Object>{
                'id' => './',
                'name' => 'Zeta Pharma',
                'short_name' => 'Zeta',
                'description' => 'Zeta Pharma for healthcare professionals: events and your live entry pass, products, news and requests.',
                'start_url' => start,
                'scope' => './',
                'display' => 'standalone',
                'orientation' => 'portrait',
                'background_color' => '#f6f8fb',
                'theme_color' => '#032d60',
                'icons' => new List<Object>{
                    icon('MeetingPassIcon192', '192x192', 'any'),
                    icon('MeetingPassIcon512', '512x512', 'any'),
                    icon('MeetingPassIcon512', '512x512', 'maskable')
                }
            });
        }
    }
    /** Network first; falls back to the last copy of each pass so the live QR still works with no signal at the venue. */
    public String swScript {
        get {
            return String.join(new List<String>{
                'const CACHE = "zeta-pass-v1";',
                'self.addEventListener("install", () => self.skipWaiting());',
                'self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));',
                'self.addEventListener("fetch", (e) => {',
                '  const url = new URL(e.request.url);',
                '  if (e.request.method !== "GET" || url.origin !== self.location.origin) return;',
                '  const p = url.searchParams;',
                '  if (p.get("s") === "1" || p.get("f") || p.get("a") || e.request.mode !== "navigate") return;',
                '  const key = url.origin + url.pathname + (p.get("c") ? "?c=" + p.get("c") : "");',
                '  e.respondWith(fetch(e.request).then((res) => {',
                '    if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(key, copy)); }',
                '    return res;',
                '  }).catch(() => caches.match(key).then((hit) => hit || Response.error())));',
                '});'
            }, '\n');
        }
    }
    public String icsText {
        get {
            if (invalid || meeting.Start_Date_Time__c == null) {
                return '';
            }
            DateTime starts = meeting.Start_Date_Time__c;
            DateTime ends = meeting.End_Date_Time__c != null ? meeting.End_Date_Time__c : starts.addHours(2);
            String link = Site.getBaseSecureUrl();
            link = (String.isBlank(link) ? '' : link.removeEnd('/')) + '/?c=' + code;
            List<String> lines = new List<String>{
                'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Zeta Pharma//Zeta Pass//EN', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
                'BEGIN:VEVENT',
                'UID:' + code + '@zetapass',
                'DTSTAMP:' + icsTime(System.now()),
                'DTSTART:' + icsTime(starts),
                'DTEND:' + icsTime(ends),
                'SUMMARY:' + icsEscape(meetingTitle),
                'DESCRIPTION:' + icsEscape('Your Zeta entry pass: ' + link + '\nOpen it at the entrance and show the live QR code.'),
                'URL:' + link
            };
            if (String.isNotBlank(venue)) {
                lines.add('LOCATION:' + icsEscape(venue));
            }
            lines.addAll(alarm('-P1D', 'Tomorrow: ' + meetingTitle));
            lines.addAll(alarm('-PT2H', 'In 2 hours: ' + meetingTitle));
            lines.addAll(new List<String>{ 'END:VEVENT', 'END:VCALENDAR' });
            List<String> folded = new List<String>();
            for (String line : lines) {
                folded.add(icsFold(line));
            }
            return String.join(folded, '\r\n') + '\r\n';
        }
    }
    public String googleCalendarUrl {
        get {
            if (invalid || meeting.Start_Date_Time__c == null) {
                return null;
            }
            DateTime starts = meeting.Start_Date_Time__c;
            DateTime ends = meeting.End_Date_Time__c != null ? meeting.End_Date_Time__c : starts.addHours(2);
            String url = 'https://calendar.google.com/calendar/render?action=TEMPLATE'
                + '&text=' + EncodingUtil.urlEncode(meetingTitle, 'UTF-8')
                + '&dates=' + icsTime(starts) + '/' + icsTime(ends)
                + '&details=' + EncodingUtil.urlEncode('Open your Zeta entry pass at the entrance and show the live QR code.', 'UTF-8');
            if (String.isNotBlank(venue)) {
                url += '&location=' + EncodingUtil.urlEncode(venue, 'UTF-8');
            }
            return url;
        }
    }
    public Boolean hasCalendar {
        get {
            return !invalid && !cancelled && !checkedIn && meeting.Start_Date_Time__c != null;
        }
    }
    public String qrLibScript {
        get {
            if (qrLibScript == null) {
                qrLibScript = resourceText('MeetingQrJs');
            }
            return qrLibScript;
        }
        private set;
    }
    public String logoDataUri {
        get {
            if (logoDataUri == null) {
                List<StaticResource> rows = [SELECT Body FROM StaticResource WHERE Name = 'MeetingPassLogo' LIMIT 1];
                logoDataUri = rows.isEmpty() ? '' : 'data:image/png;base64,' + EncodingUtil.base64Encode(rows[0].Body);
            }
            return logoDataUri;
        }
        private set;
    }
    /** The page cannot use docType="html-5.0" because the same page also serves JSON, JavaScript and calendar files. */
    public String html5Doctype {
        get {
            return '<!DOCTYPE html>';
        }
    }
    public String manifestUrl {
        get {
            return invalid ? './?f=manifest' : './?f=manifest&c=' + EncodingUtil.urlEncode(code, 'UTF-8');
        }
    }
    public String confirmUrl {
        get {
            return invalid ? null : './?c=' + EncodingUtil.urlEncode(code, 'UTF-8') + '&a=confirm';
        }
    }
    public String icsUrl {
        get {
            return invalid ? null : './?c=' + EncodingUtil.urlEncode(code, 'UTF-8') + '&f=ics';
        }
    }
    public String appleIconDataUri {
        get {
            return (String) icon('MeetingPassIcon192', '192x192', 'any').get('src');
        }
    }
    public Long serverMillis {
        get {
            return System.now().getTime();
        }
    }
    public String tokenPrefix {
        get {
            return MeetingInvitationService.TOKEN_PREFIX;
        }
    }
    /** "Not Sent" and "Sent" are organizer-side states; the guest only cares whether they have replied. */
    public String statusLabel {
        get {
            if (status == 'Confirmed') return 'Attending';
            if (status == 'Checked In') return 'Checked in';
            return 'Awaiting your reply';
        }
    }
    public Integer tokenStepSeconds {
        get {
            return MeetingInvitationService.TOKEN_STEP_SECONDS;
        }
    }
    /** Everything the tabs render, embedded in the page so the installed app works without signal. */
    public String appJson {
        get {
            if (appJson == null) {
                ZetaHcpContentService.Hcp hcp = contextHcp();
                Boolean known = showEvents;
                List<Map<String, Object>> mine = known
                    ? ZetaHcpContentService.myEvents(hcp, invalid ? null : invitation.Id)
                    : new List<Map<String, Object>>();
                appJson = JSON.serialize(new Map<String, Object>{
                    'me' => new Map<String, Object>{
                        'name' => hcp.name,
                        'phone' => hcp.phone,
                        'email' => hcp.email,
                        'code' => invalid ? null : code,
                        'known' => known
                    },
                    'products' => ZetaHcpContentService.products(hcp.accountId),
                    'news' => ZetaHcpContentService.news(),
                    'events' => mine,
                    'openEvents' => known ? ZetaHcpContentService.openEvents(mine) : new List<Map<String, Object>>(),
                    'requests' => known ? ZetaHcpContentService.myRequests(hcp) : new List<Map<String, Object>>()
                }).replace('</', '<\\/');
            }
            return appJson;
        }
        private set;
    }

    private Meeting_Invitation__c invitation;
    private Meeting__c meeting;
    private ZetaHcpContentService.Hcp sessionHcp;

    public MeetingCheckInController() {
        invalid = true;
        cancelled = false;
        canConfirm = false;
        showQr = false;
        doorOpen = false;
        checkedIn = false;
        Map<String, String> params = ApexPages.currentPage().getParameters();
        statusOnly = params.get('s') == '1';
        String f = params.get('f');
        String action = params.get('a');
        view = f == 'manifest' || f == 'sw' || f == 'ics' ? f : statusOnly ? 'status' : (action == 'request' || action == 'pin') ? 'api' : 'page';
        hasCode = String.isNotBlank(params.get('c'));
        load(params.get('c'));
        signedIn = false;
        if (invalid == true) {
            sessionHcp = ZetaHcpSignInService.resume(cookieValue(ZetaHcpSignInService.COOKIE));
            signedIn = sessionHcp != null;
        }
    }

    public PageReference logScan() {
        if (view == 'ics') {
            ApexPages.currentPage().getHeaders().put('Content-Disposition', 'inline; filename="zeta-meeting.ics"');
        }
        if (view == 'api' && ApexPages.currentPage().getParameters().get('a') == 'pin') {
            try {
                apiJson = ZetaHcpSignInService.handle(ApexPages.currentPage());
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'HCP sign-in failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
                apiJson = '{"ok":false,"message":"Please try again."}';
            }
            return null;
        }
        if (view == 'api') {
            ZetaHcpRequestService.Result result;
            try {
                result = ZetaHcpRequestService.submit(ApexPages.currentPage().getParameters(), contextHcp());
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'HCP request failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
                result = new ZetaHcpRequestService.Result();
                result.message = 'We could not send your request. Please try again.';
            }
            apiJson = JSON.serialize(result);
            return null;
        }
        if (invitation == null || view != 'page') {
            return null;
        }
        if (ApexPages.currentPage().getParameters().get('a') == 'confirm') {
            confirmAttendance();
        }
        Map<String, String> headers = lowerKeys(ApexPages.currentPage().getHeaders());
        try {
            insert buildScan(invitation.Id, headers.get('user-agent'));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Meeting scan not logged: ' + e.getMessage());
        }
        if (showQr && String.isBlank(qrSecret)) {
            qrSecret = MeetingInvitationService.ensureSecret(invitation);
        }
        return null;
    }

    public PageReference confirmAttendance() {
        if (invitation != null && canConfirm) {
            MeetingInvitationService.confirm(invitation);
            message = 'Thank you. Your attendance is confirmed.';
            refresh();
        }
        return null;
    }

    public static String currentStatus(String code) {
        Meeting_Invitation__c row = MeetingInvitationService.findByCode(code);
        return row == null || row.Active__c != true ? 'Invalid' : row.Status__c;
    }

    private void refresh() {
        load(invitation.Code__c);
    }

    /** The invitation HCP when the link is valid, otherwise the PIN session, otherwise a blank visitor. */
    ZetaHcpContentService.Hcp contextHcp() {
        if (invalid != true && invitation != null) {
            return ZetaHcpContentService.hcpFor(invitation);
        }
        return sessionHcp == null ? new ZetaHcpContentService.Hcp() : sessionHcp;
    }

    static String cookieValue(String name) {
        Map<String, Cookie> cookies = ApexPages.currentPage().getCookies();
        if (cookies == null) {
            return null;
        }
        Cookie cookie = cookies.get(name);
        return cookie == null ? null : cookie.getValue();
    }

    private void load(String code) {
        invitation = find(code);
        if (invitation == null || invitation.Active__c != true) {
            invalid = true;
            return;
        }
        meeting = [
            SELECT Id, Name, Objectives__c, Start_Date_Time__c, End_Date_Time__c, Venue__c, Status__c
            FROM Meeting__c
            WHERE Id = :invitation.Meeting__c
            LIMIT 1
        ];
        invalid = false;
        cancelled = meeting.Status__c == 'Cancelled';
        guestName = invitation.Guest_Name__c;
        meetingTitle = String.isNotBlank(meeting.Objectives__c) ? meeting.Objectives__c.left(160) : meeting.Name;
        whenText = meeting.Start_Date_Time__c == null
            ? null
            : meeting.Start_Date_Time__c.format('EEEE d MMMM yyyy, h:mm a', 'Africa/Cairo');
        venue = meeting.Venue__c;
        status = invitation.Status__c;
        checkedIn = invitation.Status__c == 'Checked In';
        checkedInText = invitation.Checked_In_At__c == null
            ? null
            : invitation.Checked_In_At__c.format('h:mm a', 'Africa/Cairo');
        Boolean open = !cancelled && !checkedIn;
        doorOpen = open && MeetingInvitationService.isCheckInWindow(meeting, System.now());
        canConfirm = open && invitation.Status__c != 'Confirmed';
        // Keep the live pass after check-in so Entry pass still opens the QR.
        showQr = !cancelled;
        this.code = invitation.Code__c;
        qrSecret = invitation.Qr_Secret__c;
    }

    static Map<String, Object> icon(String resource, String sizes, String purpose) {
        List<StaticResource> rows = [SELECT Body FROM StaticResource WHERE Name = :resource LIMIT 1];
        String src = rows.isEmpty() ? '' : 'data:image/png;base64,' + EncodingUtil.base64Encode(rows[0].Body);
        return new Map<String, Object>{ 'src' => src, 'sizes' => sizes, 'type' => 'image/png', 'purpose' => purpose };
    }

    static List<String> alarm(String offset, String text) {
        return new List<String>{ 'BEGIN:VALARM', 'TRIGGER:' + offset, 'ACTION:DISPLAY', 'DESCRIPTION:' + icsEscape(text), 'END:VALARM' };
    }

    @TestVisible
    static String icsTime(DateTime value) {
        return value.formatGmt('yyyyMMdd\'T\'HHmmss\'Z\'');
    }

    @TestVisible
    static String icsEscape(String value) {
        return String.isBlank(value) ? '' : value.replace('\\', '\\\\').replace(';', '\\;').replace(',', '\\,').replace('\r\n', '\\n').replace('\n', '\\n');
    }

    static String icsFold(String line) {
        if (line.length() <= 74) {
            return line;
        }
        List<String> parts = new List<String>();
        for (Integer i = 0; i < line.length(); i += 73) {
            parts.add((i == 0 ? '' : ' ') + line.substring(i, Math.min(i + 73, line.length())));
        }
        return String.join(parts, '\r\n');
    }

    static String resourceText(String name) {
        List<StaticResource> rows = [SELECT Body FROM StaticResource WHERE Name = :name LIMIT 1];
        return rows.isEmpty() ? '' : rows[0].Body.toString().replace('</script', '<\\/script');
    }

    @TestVisible
    static Meeting_Invitation__c find(String code) {
        return MeetingInvitationService.findByCode(code);
    }

    @TestVisible
    static Meeting_QR_Scan__c buildScan(Id invitationId, String ua) {
        return new Meeting_QR_Scan__c(
            Meeting_Invitation__c = invitationId,
            Scanned_At__c = System.now(),
            Is_Bot__c = String.isBlank(ua) || BOT.matcher(ua).matches(),
            User_Agent__c = ua == null ? null : ua.left(255),
            Device__c = device(ua),
            Operating_System__c = os(ua)
        );
    }

    @TestVisible
    static String device(String ua) {
        if (String.isBlank(ua)) return null;
        if (Pattern.matches('(?i).*(ipad|tablet|kindle|silk|(android(?!.*mobile))).*', ua)) return 'Tablet';
        if (Pattern.matches('(?i).*(mobi|iphone|ipod|android|windows phone).*', ua)) return 'Mobile';
        return 'Desktop';
    }

    @TestVisible
    static String os(String ua) {
        if (String.isBlank(ua)) return null;
        if (Pattern.matches('(?i).*(iphone|ipad|ipod).*', ua)) return 'iOS';
        if (Pattern.matches('(?i).*android.*', ua)) return 'Android';
        if (Pattern.matches('(?i).*windows.*', ua)) return 'Windows';
        if (Pattern.matches('(?i).*(mac os x|macintosh).*', ua)) return 'macOS';
        if (Pattern.matches('(?i).*(cros|linux).*', ua)) return 'Linux';
        return 'Other';
    }

    static Map<String, String> lowerKeys(Map<String, String> headers) {
        Map<String, String> out = new Map<String, String>();
        for (String key : headers.keySet()) {
            out.put(key.toLowerCase(), headers.get(key));
        }
        return out;
    }

    static Boolean hcpTabEnabled(String featureKey) {
        if (String.isBlank(featureKey)) {
            return true;
        }
        try {
            List<Field_App_Feature__c> rows = [
                SELECT Is_Enabled__c
                FROM Field_App_Feature__c
                WHERE Feature_Key__c = :featureKey
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                return true;
            }
            return rows[0].Is_Enabled__c == true;
        } catch (Exception ex) {
            return true;
        }
    }
}
