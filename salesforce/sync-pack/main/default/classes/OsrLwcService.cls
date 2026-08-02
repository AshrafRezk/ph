@RestResource(urlMapping='/osr/v1/lwc')
global with sharing class OsrLwcService {
    global class LwcRequest {
        public List<String> bundles;
    }
    global class LwcBundle {
        public String bundleName;
        public String version;
        public String moduleUrl;
        /** Mountable custom-element JS (offline host or runnable HTMLElement). */
        public String sourceJs;
        /** Raw org HTML template (Tooling). */
        public String sourceHtml;
        /** Raw org CSS (Tooling). */
        public String sourceCss;
        /** Raw org JS controller (Tooling) — usually not runnable offline as-is. */
        public String sourceJsRaw;
        /** js-meta.xml when available. */
        public String sourceMetaXml;
        /** Parsed @salesforce/apex bindings from controller JS. */
        public List<String> apexBindings;
        /** staticResource | toolingSource | offlineHost | stub */
        public String sourceKind;
        /** True when Tooling/StaticResource returned real org sources. */
        public Boolean hasOrgSource;
    }
    global class LwcResponse {
        public List<LwcBundle> bundles;
        public String warning;
    }

    private static final Integer MAX_SOURCE_CHARS = 100000;
    private static final Integer MAX_TOOLING_BUNDLES = 20;

    @HttpPost
    global static void exportBundles() {
        writeJson(buildResponse());
    }

    public static LwcResponse buildResponse() {
        LwcRequest req = (LwcRequest) JSON.deserialize(
            RestContext.request.requestBody.toString(),
            LwcRequest.class
        );
        LwcResponse res = new LwcResponse();
        res.bundles = new List<LwcBundle>();
        List<String> names = req == null || req.bundles == null ? new List<String>() : req.bundles;

        Map<String, Map<String, String>> toolingByDev = fetchToolingSources(names);

        for (String rawName : names) {
            String bundleName = normalizeBundleName(rawName);
            String srName = toStaticResourceName(bundleName);
            List<StaticResource> srs = [
                SELECT Id, Name, SystemModstamp, Body
                FROM StaticResource
                WHERE Name = :srName
                LIMIT 1
            ];
            LwcBundle b = new LwcBundle();
            b.bundleName = bundleName;
            b.hasOrgSource = false;
            b.apexBindings = new List<String>();

            if (!srs.isEmpty()) {
                b.version = String.valueOf(srs[0].SystemModstamp.getTime());
                b.sourceJs = srs[0].Body.toString();
                b.moduleUrl = '/resource/' + srs[0].Name;
                b.sourceKind = 'staticResource';
                b.hasOrgSource = true;
                res.bundles.add(b);
                continue;
            }

            String devName = developerNameFromBundle(bundleName);
            Map<String, String> files = toolingByDev.get(devName);
            if (files != null && !files.isEmpty()) {
                b.hasOrgSource = true;
                String js = files.get('js');
                String html = files.get('html');
                String css = files.get('css');
                String metaXml = files.get('meta');
                b.sourceHtml = truncate(html, MAX_SOURCE_CHARS);
                b.sourceCss = truncate(css, MAX_SOURCE_CHARS);
                b.sourceJsRaw = truncate(js, MAX_SOURCE_CHARS);
                b.sourceMetaXml = truncate(metaXml, 20000);
                b.apexBindings = parseApexBindings(js);

                Boolean runnable = isRunnableOfflineJs(js);
                if (runnable && String.isNotBlank(js)) {
                    b.sourceJs = truncate(js, MAX_SOURCE_CHARS);
                    b.sourceKind = 'toolingSource';
                    b.version = String.valueOf(
                        hashVersion(js + nvl(html) + nvl(css))
                    );
                } else {
                    // Package HTML+CSS(+raw JS reference) as a mountable custom element
                    b.sourceJs = buildOfflineHost(bundleName, html, css, js);
                    b.sourceKind = 'offlineHost';
                    b.version = String.valueOf(
                        hashVersion(nvl(html) + nvl(css) + nvl(js) + 'host2')
                    );
                }
                res.bundles.add(b);
                continue;
            }

            b.version = '0';
            b.sourceKind = 'stub';
            b.sourceJs = buildTierAStub(bundleName);
            res.bundles.add(b);
        }
        return res;
    }

    /**
     * One Tooling query for all requested LWC resources (js/html/css/meta).
     */
    private static Map<String, Map<String, String>> fetchToolingSources(List<String> bundleNames) {
        Map<String, Map<String, String>> byDev = new Map<String, Map<String, String>>();
        if (bundleNames == null || bundleNames.isEmpty() || !OsrToolingClient.canCallout()) {
            return byDev;
        }
        List<String> devNames = new List<String>();
        Set<String> seen = new Set<String>();
        for (String b : bundleNames) {
            String dn = developerNameFromBundle(normalizeBundleName(b));
            if (String.isBlank(dn) || seen.contains(dn)) {
                continue;
            }
            seen.add(dn);
            devNames.add(dn);
            if (devNames.size() >= MAX_TOOLING_BUNDLES) {
                break;
            }
        }
        if (devNames.isEmpty()) {
            return byDev;
        }
        try {
            String soql =
                'SELECT FilePath, Format, Source, LightningComponentBundle.DeveloperName ' +
                'FROM LightningComponentResource WHERE LightningComponentBundle.DeveloperName IN ' +
                OsrToolingClient.inClause(devNames);
            for (Map<String, Object> row : OsrToolingClient.query(soql)) {
                Map<String, Object> bundleRef = (Map<String, Object>) row.get(
                    'LightningComponentBundle'
                );
                String dn = bundleRef == null
                    ? null
                    : String.valueOf(bundleRef.get('DeveloperName'));
                if (String.isBlank(dn)) {
                    continue;
                }
                String format = row.get('Format') == null
                    ? ''
                    : String.valueOf(row.get('Format')).toLowerCase();
                String path = row.get('FilePath') == null ? '' : String.valueOf(row.get('FilePath'));
                String source = row.get('Source') == null ? '' : String.valueOf(row.get('Source'));
                if (String.isBlank(source)) {
                    continue;
                }
                String kind = null;
                if (path.endsWith('-meta.xml')) {
                    kind = 'meta';
                } else if (format == 'js' || path.endsWith('.js')) {
                    kind = 'js';
                } else if (format == 'html' || path.endsWith('.html')) {
                    kind = 'html';
                } else if (format == 'css' || path.endsWith('.css')) {
                    kind = 'css';
                }
                if (kind == null) {
                    continue;
                }
                if (!byDev.containsKey(dn)) {
                    byDev.put(dn, new Map<String, String>());
                }
                byDev.get(dn).put(kind, truncate(source, MAX_SOURCE_CHARS));
            }
        } catch (Exception e) {
            // Fall through — stubs / offline hosts
        }
        return byDev;
    }

    /** Extract @salesforce/apex/Class.method imports from controller JS. */
    @TestVisible
    private static List<String> parseApexBindings(String js) {
        List<String> out = new List<String>();
        if (String.isBlank(js)) {
            return out;
        }
        // import x from '@salesforce/apex/MyClass.myMethod'
        Matcher m = Pattern.compile(
                '@salesforce/apex/([A-Za-z0-9_.]+)'
            )
            .matcher(js);
        Set<String> seen = new Set<String>();
        while (m.find()) {
            String binding = m.group(1);
            if (!seen.contains(binding)) {
                seen.add(binding);
                out.add(binding);
            }
        }
        return out;
    }

    private static Boolean isRunnableOfflineJs(String js) {
        if (String.isBlank(js)) {
            return false;
        }
        if (js.contains('from \'lwc\'') || js.contains('from "lwc"')) {
            return false;
        }
        if (js.contains('lightning/') || js.contains('@salesforce/')) {
            return false;
        }
        return js.contains('extends HTMLElement') || js.contains('export default class');
    }

    /**
     * High-fidelity offline host from real HTML+CSS (+ badge when controller exists).
     * Controllers / @wire are not executed — shell may still prefer Lit stand-ins
     * that bind SQLite for interactive Home widgets.
     */
    private static String buildOfflineHost(
        String bundleName,
        String html,
        String css,
        String js
    ) {
        String cls = sanitizeClass(bundleName);
        String title = friendlyLwcTitle(bundleName);
        String bodyHtml = templateToHtml(html);
        if (String.isBlank(bodyHtml)) {
            bodyHtml =
                '<div class="osr-empty"><strong>No items to display</strong>' +
                '<div class="osr-muted">Synced from org · interactive Apex/@wire unavailable offline</div></div>';
        }
        String style = String.isBlank(css) ? defaultHostCss() : css;
        String safeStyle = jsSingleQuoted(style);
        String safeHtml = jsSingleQuoted(bodyHtml);
        String safeTitle = jsSingleQuoted(title);
        Boolean hasController = String.isNotBlank(js) && js.length() > 40;
        List<String> apex = parseApexBindings(js);
        String apexNote = apex.isEmpty()
            ? ''
            : '<div class="osr-apex">Apex: ' +
              String.join(apex, ', ') +
              '</div>';
        return
            'export default class ' +
            cls +
            ' extends HTMLElement {\n' +
            '  connectedCallback(){\n' +
            '    const title = \'' +
            safeTitle +
            '\';\n' +
            '    const style = \'' +
            safeStyle +
            '\';\n' +
            '    const body = \'' +
            safeHtml +
            '\';\n' +
            '    const apexNote = \'' +
            jsSingleQuoted(apexNote) +
            '\';\n' +
            '    this.attachShadow({mode:\'open\'}).innerHTML = `\n' +
            '      <style>${style}\n' +
            '        :host{display:block;font:13px/1.4 Salesforce Sans,Helvetica,Arial,sans-serif;color:#181818}\n' +
            '        .osr-host-wrap{background:#fff;border:1px solid #c9c9c9;border-radius:4px;overflow:hidden}\n' +
            '        .osr-host-hdr{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:10px 12px;border-bottom:1px solid #e5e5e5;font-weight:700;font-size:13px}\n' +
            '        .osr-badge{font-size:10px;font-weight:600;color:#0176d3;background:#eef4ff;border-radius:4px;padding:2px 6px;white-space:nowrap}\n' +
            '        .osr-host-body{padding:0;min-height:48px}\n' +
            '        .osr-empty{padding:20px 12px;text-align:center;color:#706e6b}\n' +
            '        .osr-muted{font-size:11px;margin-top:6px;color:#939393}\n' +
            '        .osr-apex{font-size:10px;color:#706e6b;padding:6px 12px;border-top:1px solid #f3f3f3;background:#fafaf9}\n' +
            '      </style>\n' +
            '      <div class="osr-host-wrap">\n' +
            '        <div class="osr-host-hdr"><span>${title}</span>' +
            (hasController ? '<span class="osr-badge">Offline view</span>' : '') +
            '</div>\n' +
            '        <div class="osr-host-body">${body}</div>\n' +
            '        ${apexNote}\n' +
            '      </div>`;\n' +
            '  }\n' +
            '}';
    }

    private static String buildTierAStub(String bundleName) {
        String cls = sanitizeClass(bundleName);
        String title = friendlyLwcTitle(bundleName);
        return
            'export default class ' +
            cls +
            ' extends HTMLElement {\n' +
            '  connectedCallback(){\n' +
            '    const title = ' +
            JSON.serialize(title) +
            ';\n' +
            '    this.innerHTML = `\n' +
            '      <div style="font:13px/1.4 Salesforce Sans,Helvetica,Arial,sans-serif;color:#181818;background:#fff;border:1px solid #c9c9c9;border-radius:4px;overflow:hidden">\n' +
            '        <div style="padding:10px 12px;border-bottom:1px solid #e5e5e5;font-weight:700;font-size:13px">${title}</div>\n' +
            '        <div style="padding:20px 12px;text-align:center;color:#706e6b;font-size:13px">No items to display</div>\n' +
            '      </div>`;\n' +
            '  }\n' +
            '}';
    }

    private static String templateToHtml(String html) {
        if (String.isBlank(html)) {
            return '';
        }
        String s = html.trim();
        if (s.length() > 40000) {
            s = s.substring(0, 40000);
        }
        String lower = s.toLowerCase();
        if (lower.startsWith('<template')) {
            Integer gt = s.indexOf('>');
            Integer endIdx = lower.lastIndexOf('</template>');
            if (gt > 0 && endIdx > gt) {
                s = s.substring(gt + 1, endIdx).trim();
            }
        }
        Integer guard = 0;
        while (guard < 200) {
            Integer i = s.indexOf('{');
            Integer j = (i < 0) ? -1 : s.indexOf('}', i + 1);
            if (i < 0 || j < 0 || j - i > 200) {
                break;
            }
            s = s.substring(0, i) + '-' + s.substring(j + 1);
            guard++;
        }
        return s.trim();
    }

    private static String defaultHostCss() {
        return '.osr-empty{padding:20px 12px;text-align:center;color:#706e6b}';
    }

    private static String jsSingleQuoted(String s) {
        if (s == null) {
            return '';
        }
        return s.replace('\\', '\\\\')
            .replace('\'', '\\\'')
            .replace('\n', '\\n')
            .replace('\r', '')
            .replace('`', '\\`')
            .replace('${', '\\${');
    }

    private static String nvl(String s) {
        return s == null ? '' : s;
    }

    private static String truncate(String s, Integer maxLen) {
        if (s == null) {
            return null;
        }
        return s.length() <= maxLen ? s : s.substring(0, maxLen);
    }

    private static Integer hashVersion(String s) {
        return s == null ? 0 : Math.abs(s.hashCode());
    }

    global static String normalizeBundleName(String bundleName) {
        if (String.isBlank(bundleName)) {
            return bundleName;
        }
        return OsrToolingClient.toBundleNamePublic(bundleName.trim());
    }

    private static String developerNameFromBundle(String bundleName) {
        if (String.isBlank(bundleName)) {
            return '';
        }
        String s = bundleName.trim();
        if (s.startsWith('c/')) {
            return s.substring(2);
        }
        if (s.startsWith('c:')) {
            return s.substring(2);
        }
        Integer slash = s.lastIndexOf('/');
        if (slash >= 0) {
            return s.substring(slash + 1);
        }
        Integer colon = s.indexOf(':');
        if (colon > 0) {
            return s.substring(colon + 1);
        }
        return s;
    }

    private static void writeJson(Object value) {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(value));
    }

    private static String toStaticResourceName(String bundleName) {
        String s = bundleName.replace('c/', 'c_').replace('/', '_').replace('-', '_');
        s = s.replaceAll('[^A-Za-z0-9_]', '_');
        return ('OSR_LWC_' + s).left(40);
    }

    private static String sanitizeClass(String bundleName) {
        String s = bundleName.replace('c/', '').replace('/', '_');
        s = s.replaceAll('[^A-Za-z0-9_]', '');
        if (s.length() == 0) {
            return 'OsrLwcStub';
        }
        return s;
    }

    private static String friendlyLwcTitle(String bundleName) {
        String raw = bundleName == null ? '' : bundleName.replace('c/', '').replace('c:', '');
        if (raw.equalsIgnoreCase('fieldRepHomeTodayPlan')) {
            return 'Today\'s Plan';
        }
        if (raw.equalsIgnoreCase('fieldRepHomeMetrics')) {
            return 'Metrics';
        }
        if (raw.equalsIgnoreCase('fieldRepHomeNextBestCustomer')) {
            return 'Next Best Customer';
        }
        if (raw.equalsIgnoreCase('fieldRepHomeClmPrefetch')) {
            return 'CLM Content';
        }
        if (raw.equalsIgnoreCase('homeOfficeMessages')) {
            return 'Office Messages';
        }
        if (raw.equalsIgnoreCase('repLocationPublisher')) {
            return 'My Location';
        }
        if (raw.equalsIgnoreCase('reportsHub')) {
            return 'Reports';
        }
        if (raw.equalsIgnoreCase('fieldRepPlanner')) {
            return 'Planner';
        }
        if (raw.equalsIgnoreCase('clmPresentationsHub')) {
            return 'CLM Presentations';
        }
        if (raw.equalsIgnoreCase('accountsTab')) {
            return 'Accounts';
        }
        if (raw.equalsIgnoreCase('timeOffSubmission')) {
            return 'Request Time Off';
        }
        if (raw.equalsIgnoreCase('visitCallShellLite')) {
            return 'Visit Call';
        }
        if (raw.equalsIgnoreCase('clmPlayerLite')) {
            return 'CLM Player';
        }
        String spaced = raw.replaceAll('([a-z0-9])([A-Z])', '$1 $2').replace('_', ' ').trim();
        if (String.isBlank(spaced)) {
            return 'Component';
        }
        List<String> parts = spaced.split('\\s+');
        List<String> titled = new List<String>();
        for (String p : parts) {
            if (p.length() == 0) {
                continue;
            }
            titled.add(p.substring(0, 1).toUpperCase() + p.substring(1));
        }
        return String.join(titled, ' ');
    }
}
