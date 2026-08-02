/* global Visualforce */
/* global Visualforce, CrmHubListController */
(function (global) {
    'use strict';
    var API_VER = 'v60.0';

    function remotingEnabled() {
        return (
            typeof Visualforce !== 'undefined' &&
            Visualforce.remoting &&
            typeof CrmHubListController !== 'undefined' &&
            typeof CrmHubListController.fetchListViewResults === 'function'
        );
    }

    function remotingCall(method, args) {
        return new Promise(function (resolve, reject) {
            if (!remotingEnabled()) {
                reject(new Error('CRM Hub remoting is unavailable'));
                return;
            }
            Visualforce.remoting.timeout = 120000;
            // VF remoting expects: method(params..., callback, [configuration])
            // Putting config before the callback makes SF treat the config object as a
            // method argument → "Parameter length does not match remote action parameters".
            method.apply(
                CrmHubListController,
                args.concat([
                    function (res, ev) {
                        if (!ev.status) {
                            reject(new Error(ev.message || 'Remoting failed'));
                            return;
                        }
                        if (res && res.error) {
                            reject(new Error(res.error));
                            return;
                        }
                        resolve(res || {});
                    },
                    { escape: false, timeout: 120000 }
                ])
            );
        });
    }

    function remotingListViewResults(objectApi, listViewId, pageSize, offset, listViewDescribeJson, searchTerm) {
        return remotingCall(CrmHubListController.fetchListViewResults, [
            objectApi,
            listViewId,
            pageSize,
            offset,
            listViewDescribeJson || null,
            searchTerm || null
        ]);
    }

    function remotingKanbanBoard(objectApi, listViewId, laneField, perLaneLimit, listViewDescribeJson) {
        return remotingCall(CrmHubListController.fetchKanbanBoard, [
            objectApi,
            listViewId,
            laneField || null,
            perLaneLimit || 10,
            listViewDescribeJson || null
        ]);
    }

    function remotingKanbanLaneMore(
        objectApi,
        listViewId,
        laneField,
        laneValue,
        pageSize,
        offset,
        listViewDescribeJson
    ) {
        return remotingCall(CrmHubListController.fetchKanbanLaneMore, [
            objectApi,
            listViewId,
            laneField,
            laneValue == null || laneValue === '—' ? '' : laneValue,
            pageSize || 10,
            offset || 0,
            listViewDescribeJson || null
        ]);
    }

    function remotingDescribeListView(objectApi, listViewId) {
        return remotingCall(CrmHubListController.describeListView, [objectApi, listViewId]);
    }

    function remotingUpdateRecordFields(recordId, fieldValues) {
        return remotingCall(CrmHubListController.updateRecordFields, [recordId, fieldValues]);
    }

    function apiRoot() {
        return global.location.origin + '/services/data/' + API_VER;
    }

    function headers() {
        var h = { Accept: 'application/json' };
        if (global.CRM_HUB_SESSION) {
            h.Authorization = 'Bearer ' + global.CRM_HUB_SESSION;
        }
        return h;
    }

    function apiGet(url) {
        return fetch(url, { headers: headers(), credentials: 'same-origin' }).then(function (res) {
            if (!res.ok) {
                return res.text().then(function (t) {
                    throw new Error(res.status + ' ' + t);
                });
            }
            return res.json();
        });
    }

    function apiPatch(url, body) {
        return fetch(url, {
            method: 'PATCH',
            headers: Object.assign({}, headers(), { 'Content-Type': 'application/json' }),
            credentials: 'same-origin',
            body: JSON.stringify(body)
        }).then(function (res) {
            if (!res.ok) {
                return res.text().then(function (t) {
                    throw new Error(res.status + ' ' + t);
                });
            }
            return res.text();
        });
    }

    var openIconUrl =
        'https://cdn-icons-png.flaticon.com/512/7794/7794669.png';

    function esc(s) {
        if (s == null || s === undefined) {
            return '';
        }
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function openRecordIconImg() {
        var src = openIconUrl || 'https://cdn-icons-png.flaticon.com/512/7794/7794669.png';
        return (
            '<img class="ch-open-img" src="' +
            esc(src) +
            '" alt="" aria-hidden="true" width="22" height="22" />'
        );
    }

    function openRecordIconBtn(rid, title, compact) {
        if (!rid) {
            return '';
        }
        var tip = title ? esc(title) : 'record';
        var cls = 'slds-button ch-open ch-open-ico' + (compact ? ' ch-open-ico-compact' : '');
        return (
            '<button type="button" class="' +
            cls +
            '" data-id="' +
            esc(rid) +
            '" data-record-id="' +
            esc(rid) +
            '" title="Open record" aria-label="Open record — ' +
            tip +
            '">' +
            openRecordIconImg() +
            '<span class="slds-assistive-text">Open record</span></button>'
        );
    }

    function openRecordIconBtnPlaceholder(compact) {
        var cls = 'ch-open-ico ch-open-ico-missing' + (compact ? ' ch-open-ico-compact' : '');
        return (
            '<span class="' +
            cls +
            '" title="Open record (id unavailable)" aria-hidden="true">' +
            openRecordIconImg() +
            '</span>'
        );
    }

    function stripHtml(s) {
        if (s == null) {
            return '';
        }
        var d = document.createElement('div');
        d.innerHTML = String(s);
        return d.textContent || d.innerText || '';
    }

    function decodeHtmlEntities(s) {
        if (s == null || s === '') {
            return '';
        }
        var cur = String(s);
        var prev = '';
        var guard = 0;
        while (prev !== cur && guard < 6) {
            prev = cur;
            var ta = document.createElement('textarea');
            ta.innerHTML = cur;
            cur = ta.value;
            guard++;
        }
        return cur;
    }

    function fieldApiLooksHtml(fieldApi, label) {
        var f = String(fieldApi || '').toLowerCase();
        var lab = String(label || '').toLowerCase();
        return (
            f.indexOf('quickcontact') >= 0 ||
            f.indexOf('contactdetail') >= 0 ||
            f.indexOf('summaryinfo') >= 0 ||
            f.indexOf('summary_info') >= 0 ||
            lab.indexOf('quick contact') >= 0 ||
            lab.indexOf('contact detail') >= 0 ||
            lab.indexOf('summary info') >= 0 ||
            (lab.indexOf('summary') >= 0 && lab.indexOf('info') >= 0)
        );
    }

    function fieldTypeIsHtml(col) {
        if (!col) {
            return false;
        }
        if (col.htmlCapable === true || col.calculated === true) {
            return true;
        }
        var t = (col.type || '').toLowerCase();
        if (t === 'html' || t === 'richtextarea') {
            return true;
        }
        var extra = (col.extraTypeInfo || '').toLowerCase();
        if (extra === 'richtextarea' || extra === 'html') {
            return true;
        }
        /* Plain textarea is editable long text, not HTML markup */
        if (t === 'textarea') {
            return fieldApiLooksHtml(col.fieldNameOrPath, col.label);
        }
        return fieldApiLooksHtml(col.fieldNameOrPath, col.label);
    }

    /** Long text / wrap-style fields should open a multiline inline editor. */
    function shouldUseMultilineInlineEditor(col, text) {
        var s = String(text == null ? '' : text);
        if (s.indexOf('\n') >= 0 || s.length > 48) {
            return true;
        }
        if (!col) {
            return false;
        }
        var t = (col.type || '').toLowerCase();
        if (t === 'textarea') {
            return true;
        }
        var lab = (col.label || '').toLowerCase();
        var f = (col.fieldNameOrPath || '').toLowerCase();
        if (
            lab.indexOf('next step') >= 0 ||
            lab.indexOf('description') >= 0 ||
            lab.indexOf('comment') >= 0 ||
            lab.indexOf('taken action') >= 0 ||
            f.indexOf('nextstep') >= 0 ||
            f.indexOf('next_step') >= 0 ||
            f.indexOf('description') >= 0 ||
            f.indexOf('comment') >= 0 ||
            f.indexOf('takenaction') >= 0
        ) {
            return true;
        }
        return columnCssClass(col) === 'ch-col-wrap';
    }

    /** Formula IMAGE/HYPERLINK fields must not be used as the record title link. */
    function isHtmlDisplayField(col) {
        if (!col) {
            return false;
        }
        if (fieldApiLooksHtml(col.fieldNameOrPath, col.label)) {
            return true;
        }
        return col.calculated === true && (col.type || '').toLowerCase() === 'string';
    }

    function isRenderableHtml(v) {
        if (v == null || v === '') {
            return false;
        }
        var s = String(v).trim();
        if (s.indexOf('<') >= 0 && /<[a-zA-Z][^>]*>/.test(s)) {
            return true;
        }
        if (/&(?:lt|#0*60|#x0*3c);/i.test(s) && /&(?:lt|#0*60|#x0*3c);[a-zA-Z]/.test(s)) {
            return true;
        }
        if (/&(?:lt|#0*60|#x0*3c);(?:img|br|a|span|div|p)\b/i.test(s)) {
            return true;
        }
        if (/&amp;(?:lt|#0*60|#x0*3c);/i.test(s) && /&amp;(?:lt|#0*60|#x0*3c);[a-zA-Z]/.test(s)) {
            return true;
        }
        if (/&lt;a\b/i.test(s) && /href\s*=/i.test(s)) {
            return true;
        }
        /* Formula IMAGE()/HYPERLINK() often arrives HTML-escaped from remoting */
        if (
            /(?:&lt;|<)\s*img\b/i.test(s) ||
            (/\/resource\//i.test(s) && /(?:&lt;|<)\s*(?:a|img)\b/i.test(s)) ||
            (/linkedin/i.test(s) && /(?:&lt;|<)\s*a\b/i.test(s) && /(?:href|&quot;)/i.test(s))
        ) {
            return true;
        }
        return false;
    }

    function normalizeRenderableHtml(v) {
        var s = String(v).trim();
        if (s.charAt(0) === '<' && s.indexOf('>') > 0) {
            return s;
        }
        return decodeHtmlEntities(s);
    }

    function cellDisplayText(col, rawVal) {
        var v = rawVal == null ? '' : String(rawVal);
        if (fieldTypeIsHtml(col) || isRenderableHtml(v)) {
            return stripHtml(normalizeRenderableHtml(v));
        }
        return decodeHtmlEntities(v);
    }

    function cellInnerHtml(col, rawVal, cellMeta) {
        var v = rawVal == null ? '' : String(rawVal);
        if (v === '') {
            return '';
        }
        if (fieldTypeIsHtml(col) || isRenderableHtml(v)) {
            var html = normalizeRenderableHtml(v);
            if (isRenderableHtml(html) || html.indexOf('<') >= 0 || (fieldTypeIsHtml(col) && v.indexOf('&lt;') >= 0)) {
                return '<div class="ch-cell-html">' + html + '</div>';
            }
            /* Entity-encoded plain text (e.g. Next Step with &gt;&gt;) */
            return esc(html);
        }
        var plain = decodeHtmlEntities(v);
        var t = (col.type || '').toLowerCase();
        if (t === 'url' && plain.indexOf('http') === 0) {
            return (
                '<a class="slds-text-link ch-cell-link" target="_blank" rel="noopener" href="' +
                esc(plain) +
                '">' +
                esc(plain) +
                '</a>'
            );
        }
        if (t === 'email' && plain.indexOf('@') > 0) {
            return (
                '<a class="slds-text-link ch-cell-link" href="mailto:' +
                esc(plain) +
                '">' +
                esc(plain) +
                '</a>'
            );
        }
        var refId =
            (cellMeta && cellMeta.referenceId) ||
            (col && col.referenceId) ||
            '';
        var isRefCol =
            t === 'reference' ||
            (col.fieldNameOrPath &&
                /Id$/i.test(col.fieldNameOrPath) &&
                col.fieldNameOrPath !== 'Id' &&
                String(col.fieldNameOrPath).indexOf('.') < 0);
        if (!refId && isRefCol && looksLikeSalesforceId(plain)) {
            refId = plain;
        }
        if (refId && looksLikeSalesforceId(refId)) {
            var label = plain;
            if (looksLikeSalesforceId(label) && cellMeta && cellMeta.referenceName) {
                label = cellMeta.referenceName;
            }
            return referenceLinkHtml(refId, label);
        }
        if (t === 'reference' && plain.indexOf('http') === 0) {
            return (
                '<a class="slds-text-link ch-cell-link" target="_blank" rel="noopener" href="' +
                esc(plain) +
                '">' +
                esc(plain) +
                '</a>'
            );
        }
        return esc(plain);
    }

    function looksLikeSalesforceId(s) {
        return /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(String(s || '').trim());
    }

    function isHubModalObjectPrefix(id) {
        var p = String(id || '').substring(0, 3);
        return p === '001' || p === '003' || p === '006' || p === '00Q';
    }

    function referenceLinkHtml(refId, label) {
        var id = String(refId || '').trim();
        var text = label == null || String(label).trim() === '' ? id : String(label);
        if (!looksLikeSalesforceId(id)) {
            return esc(text);
        }
        if (isHubModalObjectPrefix(id)) {
            return (
                '<button type="button" class="slds-button slds-button_link ch-open ch-ref-link" data-id="' +
                esc(id) +
                '">' +
                esc(text) +
                '</button>'
            );
        }
        return (
            '<a class="slds-text-link ch-cell-link ch-ref-link" href="/' +
            esc(id) +
            '" target="_top" title="Open record">' +
            esc(text) +
            '</a>'
        );
    }

    function recordIdFromRow(row) {
        if (!row) {
            return '';
        }
        if (row.id) {
            return String(row.id);
        }
        if (row.recordId) {
            return String(row.recordId);
        }
        var cells = row.columns || [];
        for (var i = 0; i < cells.length; i++) {
            if (cells[i].fieldNameOrPath === 'Id') {
                var idVal = cells[i].value || '';
                if (idVal && String(idVal).length >= 15) {
                    return String(idVal);
                }
            }
        }
        for (var j = 0; j < cells.length; j++) {
            var cv = cells[j].value == null ? '' : String(cells[j].value);
            var idMatch = cv.match(/\b([a-zA-Z0-9]{15,18})\b/);
            if (idMatch && idMatch[1].length >= 15) {
                return idMatch[1];
            }
        }
        return '';
    }

    function valueForField(row, fieldApi) {
        var cells = row.columns || [];
        for (var i = 0; i < cells.length; i++) {
            if (cells[i].fieldNameOrPath === fieldApi) {
                return cells[i].value;
            }
        }
        return '';
    }

    function cellForField(row, fieldApi) {
        var cells = row.columns || [];
        for (var i = 0; i < cells.length; i++) {
            if (cells[i].fieldNameOrPath === fieldApi) {
                return cells[i];
            }
        }
        return null;
    }

    function visibleColumns(cols) {
        if (!cols) {
            return [];
        }
        return cols.slice();
    }

    function columnCssClass(col) {
        var f = col.fieldNameOrPath || '';
        var t = (col.type || '').toLowerCase();
        var lab = (col.label || '').toLowerCase();
        if (f === 'Name') {
            return 'ch-col-name';
        }
        if (t === 'date' || t === 'datetime') {
            return 'ch-col-date';
        }
        if (t === 'currency' || t === 'double' || t === 'percent' || t === 'int') {
            return 'ch-col-num';
        }
        if (t === 'boolean') {
            return 'ch-col-bool';
        }
        if (t === 'phone' || t === 'email') {
            return 'ch-col-contact';
        }
        if (t === 'id' || f === 'Id') {
            return 'ch-col-id';
        }
        if (t === 'reference' || f.indexOf('Owner') >= 0 || f.indexOf('User') >= 0) {
            return 'ch-col-ref';
        }
        if (lab.indexOf('next step') >= 0 || lab.indexOf('description') >= 0 || lab.indexOf('comment') >= 0) {
            return 'ch-col-wrap';
        }
        if ((col.type || '').toLowerCase() === 'textarea') {
            return 'ch-col-wrap';
        }
        if (fieldTypeIsHtml(col)) {
            return 'ch-col-html';
        }
        if (
            lab.indexOf('contact detail') >= 0 ||
            lab.indexOf('summary info') >= 0 ||
            f.indexOf('ContactDetails') >= 0 ||
            f.indexOf('QuickContact') >= 0 ||
            f.indexOf('SummaryInfo') >= 0 ||
            f.indexOf('Summary_Info') >= 0
        ) {
            return 'ch-col-html';
        }
        return 'ch-col-text';
    }

    function cellHasIcon(html) {
        return html && (html.indexOf('<img') >= 0 || html.indexOf('slds-avatar') >= 0 || html.indexOf('ch-cell-html') >= 0);
    }

    function wrapCellContent(inner, editable) {
        if (editable) {
            return inner;
        }
        return '<div class="ch-cell-content">' + inner + '</div>';
    }

    /** Formula IMAGE/HYPERLINK / Quick Contact fields must not be used as the record title link. */
    function isHtmlDisplayField(col) {
        if (!col) {
            return false;
        }
        if (fieldApiLooksHtml(col.fieldNameOrPath, col.label)) {
            return true;
        }
        if (col.htmlCapable === true) {
            return true;
        }
        var t = (col.type || '').toLowerCase();
        return t === 'textarea' || t === 'html' || t === 'richtextarea';
    }

    function primaryLinkField(cols) {
        var visible = visibleColumns(cols || []);
        var preferredNames = [
            'ApplicantName__c',
            'Applicant_Name__c',
            'Name',
            'Subject',
            'Title'
        ];
        for (var p = 0; p < preferredNames.length; p++) {
            for (var i = 0; i < visible.length; i++) {
                if (
                    visible[i].fieldNameOrPath === preferredNames[p] &&
                    !isHtmlDisplayField(visible[i])
                ) {
                    return preferredNames[p];
                }
            }
        }
        for (var j = 0; j < visible.length; j++) {
            var col = visible[j];
            var f = col.fieldNameOrPath || '';
            if (f !== 'Id' && f.indexOf('.') < 0 && !isHtmlDisplayField(col)) {
                return f;
            }
        }
        return 'Name';
    }

    /**
     * Plain-text title for a row. Never returns formula IMAGE/HYPERLINK markup —
     * strip it so Kanban/Cards don't show raw <a>/<img> as the card name.
     */
    function resolveRecordDisplayName(row, columns, linkField) {
        var preferred = [
            'ApplicantName__c',
            'Applicant_Name__c',
            'Name',
            linkField,
            'Subject',
            'Title'
        ];
        var seen = {};
        var i;
        for (i = 0; i < preferred.length; i++) {
            var f = preferred[i];
            if (!f || seen[f]) {
                continue;
            }
            seen[f] = true;
            var raw = valueForField(row, f);
            if (raw == null || String(raw).trim() === '') {
                continue;
            }
            if (isRenderableHtml(raw) || fieldApiLooksHtml(f, '')) {
                var stripped = stripHtml(normalizeRenderableHtml(raw)).replace(/\s+/g, ' ').trim();
                if (stripped) {
                    return stripped;
                }
                continue;
            }
            return String(raw).trim();
        }
        var cols = columns || [];
        for (i = 0; i < cols.length; i++) {
            var col = cols[i];
            var api = col.fieldNameOrPath || '';
            if (!api || seen[api] || api === 'Id' || isHtmlDisplayField(col)) {
                continue;
            }
            var v = valueForField(row, api);
            if (v == null || String(v).trim() === '') {
                continue;
            }
            if (isRenderableHtml(v)) {
                continue;
            }
            return String(v).trim();
        }
        if (row && row._chApplicantName) {
            return String(row._chApplicantName).trim();
        }
        return recordIdFromRow(row) || '';
    }

    function fieldSetFromColumns(cols) {
        var m = {};
        for (var i = 0; i < cols.length; i++) {
            m[cols[i].fieldNameOrPath] = true;
        }
        return m;
    }

    var WEAK_KANBAN_LANE_FIELDS = {
        CurrencyIsoCode: true,
        ForecastCategory: true,
        ForecastCategoryName: true,
        RecordTypeId: true,
        OwnerId: true,
        CreatedById: true,
        LastModifiedById: true
    };

    var KANBAN_LANE_DEFAULTS = {
        Opportunity: 'StageName',
        Lead: 'Status',
        Account: 'Type',
        Contact: 'LeadSource',
        Job_Application__c: 'Status__c',
        Position__c: 'Status__c',
        Employment_Contract__c: 'Active__c'
    };

    function isWeakKanbanLaneField(fieldApi) {
        return !!(fieldApi && WEAK_KANBAN_LANE_FIELDS[fieldApi]);
    }

    function isEligibleKanbanLaneColumn(col) {
        if (!col || !col.fieldNameOrPath || String(col.fieldNameOrPath).indexOf('.') >= 0) {
            return false;
        }
        var t = String(col.type || '').toLowerCase();
        return t === 'picklist' || t === 'boolean' || t === 'multipicklist';
    }

    function firstPicklistField(cols) {
        for (var i = 0; i < (cols || []).length; i++) {
            var col = cols[i];
            if (isEligibleKanbanLaneColumn(col) && !isWeakKanbanLaneField(col.fieldNameOrPath)) {
                return col.fieldNameOrPath;
            }
        }
        return '';
    }

    /**
     * Status/stage defaults win even when the list view omits that column.
     * Never auto-pick CurrencyIsoCode (multi-currency orgs put it first as a picklist).
     */
    function kanbanLaneField(objectApi, cols) {
        var persisted = readPersistedKanbanLaneField(objectApi);
        if (persisted) {
            return persisted;
        }
        var def = KANBAN_LANE_DEFAULTS[objectApi];
        if (def) {
            return def;
        }
        if (objectApi === 'Account') {
            var fs = fieldSetFromColumns(cols || []);
            if (fs.Industry) {
                return 'Industry';
            }
        }
        return firstPicklistField(cols);
    }

    function kanbanLaneCandidateColumns(objectApi, cols, activeLane) {
        var out = [];
        var seen = {};
        function pushCol(col) {
            if (!col || !col.fieldNameOrPath || seen[col.fieldNameOrPath]) {
                return;
            }
            if (!isEligibleKanbanLaneColumn(col) && col.fieldNameOrPath !== activeLane) {
                return;
            }
            seen[col.fieldNameOrPath] = true;
            out.push(col);
        }
        var def = KANBAN_LANE_DEFAULTS[objectApi];
        if (def) {
            var defCol = columnByField(cols, def);
            pushCol(
                defCol || {
                    fieldNameOrPath: def,
                    label:
                        def === 'StageName'
                            ? 'Stage'
                            : def === 'Status__c'
                              ? 'Status'
                              : def === 'Active__c'
                                ? 'Active'
                                : def,
                    type: 'picklist'
                }
            );
        }
        for (var i = 0; i < (cols || []).length; i++) {
            pushCol(cols[i]);
        }
        if (activeLane && !seen[activeLane]) {
            pushCol(
                columnByField(cols, activeLane) || {
                    fieldNameOrPath: activeLane,
                    label: activeLane,
                    type: 'picklist'
                }
            );
        }
        return out;
    }

    var KANBAN_SUMMARIZE_DEFAULTS = {
        Opportunity: ['Amount', 'ExpectedRevenue', 'TotalOpportunityQuantity'],
        Account: ['AnnualRevenue', 'NumberOfEmployees'],
        Lead: ['AnnualRevenue', 'NumberOfEmployees'],
        Contact: [],
        Job_Application__c: [
            'Salary_expectations__c',
            'Monthly_Salary__c',
            'Trailhead_Score__c',
            'Average_Rating__c',
            'Total_Rating__c',
            'Years_of_Experience__c'
        ],
        Position__c: ['Max_Pay__c', 'Min_Pay__c', 'Years_Of_Experience__c'],
        Employment_Contract__c: [
            'Total_Work_From_Home_Days_Allowed__c',
            'Total_Vacation_Days_Allowed__c'
        ]
    };

    function isSummarizableColumn(col) {
        if (!col || !col.fieldNameOrPath || col.fieldNameOrPath.indexOf('.') >= 0) {
            return false;
        }
        var t = String(col.type || '').toLowerCase();
        return (
            t === 'currency' ||
            t === 'double' ||
            t === 'int' ||
            t === 'integer' ||
            t === 'long' ||
            t === 'percent' ||
            t === 'number'
        );
    }

    function summarizableColumns(cols) {
        var out = [];
        for (var i = 0; i < (cols || []).length; i++) {
            if (isSummarizableColumn(cols[i])) {
                out.push(cols[i]);
            }
        }
        return out;
    }

    function kanbanSummarizeField(objectApi, cols, preferred) {
        var sumCols = summarizableColumns(cols);
        if (!sumCols.length) {
            return '';
        }
        var fs = fieldSetFromColumns(sumCols);
        if (preferred === '') {
            return '';
        }
        if (preferred && fs[preferred]) {
            return preferred;
        }
        var persisted = readPersistedKanbanSummarizeField(objectApi);
        if (persisted === '') {
            return '';
        }
        if (persisted && fs[persisted]) {
            return persisted;
        }
        var prefs = KANBAN_SUMMARIZE_DEFAULTS[objectApi] || [];
        for (var i = 0; i < prefs.length; i++) {
            if (fs[prefs[i]]) {
                return prefs[i];
            }
        }
        return sumCols[0].fieldNameOrPath;
    }

    function columnByField(cols, fieldApi) {
        for (var i = 0; i < (cols || []).length; i++) {
            if (cols[i].fieldNameOrPath === fieldApi) {
                return cols[i];
            }
        }
        return null;
    }

    function parseNumericCell(rawVal) {
        if (rawVal == null || rawVal === '') {
            return null;
        }
        if (typeof rawVal === 'number' && !isNaN(rawVal)) {
            return rawVal;
        }
        var s = stripHtml(String(rawVal)).trim();
        if (!s || s === '—') {
            return null;
        }
        s = s.replace(/[^0-9.\-]/g, '');
        if (!s || s === '-' || s === '.' || s === '-.') {
            return null;
        }
        var n = Number(s);
        return isNaN(n) ? null : n;
    }

    function formatKanbanSummary(total, col) {
        var t = col && col.type ? String(col.type).toLowerCase() : '';
        if (t === 'currency') {
            try {
                return total.toLocaleString(undefined, {
                    style: 'currency',
                    currency: 'USD',
                    maximumFractionDigits: 0
                });
            } catch (e) {
                return '$' + Math.round(total).toLocaleString();
            }
        }
        if (t === 'percent') {
            return total.toLocaleString(undefined, { maximumFractionDigits: 2 }) + '%';
        }
        return total.toLocaleString(undefined, { maximumFractionDigits: 2 });
    }

    /**
     * Native Kanban shows up to 4 list-view fields on each card (name as title).
     */
    function kanbanCardFields(cols, linkField, laneField) {
        var out = [];
        var htmlFirst = [];
        var rest = [];
        for (var i = 0; i < (cols || []).length; i++) {
            var col = cols[i];
            var f = col.fieldNameOrPath;
            if (!f || f === 'Id' || f === 'Name' || f === 'ApplicantName__c' || f === 'Applicant_Name__c') {
                continue;
            }
            /* Keep Quick Contact / IMAGE formulas even when wrongly selected as linkField */
            if (f === linkField && !isHtmlDisplayField(col) && !fieldTypeIsHtml(col)) {
                continue;
            }
            if (isHtmlDisplayField(col) || fieldTypeIsHtml(col) || fieldApiLooksHtml(f, col.label)) {
                htmlFirst.push(col);
            } else {
                rest.push(col);
            }
        }
        var merged = htmlFirst.concat(rest);
        for (var j = 0; j < merged.length; j++) {
            out.push(merged[j]);
            if (out.length >= 6) {
                break;
            }
        }
        return out;
    }

    function sumLaneField(bucket, fieldApi) {
        var total = 0;
        var any = false;
        for (var i = 0; i < bucket.length; i++) {
            var n = parseNumericCell(valueForField(bucket[i], fieldApi));
            if (n != null) {
                total += n;
                any = true;
            }
        }
        return any ? total : 0;
    }

    /**
     * All picklist/path values in define order, then any orphan values present in the page data.
     */
    function resolveKanbanLaneOrder(laneField, cols, lanes) {
        var col = columnByField(cols, laneField);
        var ordered = [];
        var seen = {};
        var vals = col && col.picklistValues ? col.picklistValues : [];
        var labels = col && col.picklistLabels ? col.picklistLabels : {};
        var labelToValue = {};
        for (var lk in labels) {
            if (Object.prototype.hasOwnProperty.call(labels, lk)) {
                labelToValue[String(labels[lk])] = lk;
            }
        }
        for (var i = 0; i < vals.length; i++) {
            var v = String(vals[i]);
            if (!v || seen[v]) {
                continue;
            }
            ordered.push(v);
            seen[v] = true;
            if (!lanes[v]) {
                lanes[v] = [];
            }
        }
        var orphanKeys = Object.keys(lanes || {});
        for (var oi = 0; oi < orphanKeys.length; oi++) {
            var key = orphanKeys[oi];
            if (seen[key]) {
                continue;
            }
            var mapped = labelToValue[key];
            if (mapped && seen[mapped]) {
                if (key !== mapped) {
                    lanes[mapped] = (lanes[mapped] || []).concat(lanes[key] || []);
                    delete lanes[key];
                }
                continue;
            }
            if (mapped && !seen[mapped]) {
                ordered.push(mapped);
                seen[mapped] = true;
                lanes[mapped] = (lanes[mapped] || []).concat(lanes[key] || []);
                if (key !== mapped) {
                    delete lanes[key];
                }
                continue;
            }
            ordered.push(key);
            seen[key] = true;
        }
        return ordered;
    }

    function kanbanLaneLabel(laneKey, cols, laneField) {
        if (!laneKey || laneKey === '—') {
            return laneKey || '—';
        }
        var col = columnByField(cols, laneField);
        var labels = col && col.picklistLabels ? col.picklistLabels : null;
        if (labels && labels[laneKey]) {
            return String(labels[laneKey]);
        }
        return laneKey;
    }

    var CALENDAR_DATE_DEFAULTS = {
        Lead: ['CreatedDate'],
        Opportunity: ['CloseDate', 'CreatedDate'],
        Account: ['CreatedDate'],
        Contact: ['CreatedDate', 'Birthdate'],
        Job_Application__c: ['InterviewDateTime__c', 'Employment_Date__c', 'Screening_Date__c', 'CreatedDate'],
        Position__c: ['Open_Date__c', 'CreatedDate'],
        Employment_Contract__c: ['Start_Date__c', 'End_Date__c', 'CreatedDate']
    };

    function dateColumns(cols) {
        var out = [];
        for (var i = 0; i < cols.length; i++) {
            var t = (cols[i].type || '').toLowerCase();
            if ((t === 'date' || t === 'datetime') && cols[i].fieldNameOrPath.indexOf('.') < 0) {
                out.push(cols[i]);
            }
        }
        return out;
    }

    function calendarDateField(objectApi, cols, preferred) {
        if (preferred) {
            var fsPref = fieldSetFromColumns(cols);
            if (fsPref[preferred]) {
                return preferred;
            }
        }
        var persisted = readPersistedCalendarDateField(objectApi);
        if (persisted) {
            var fsPersist = fieldSetFromColumns(cols);
            if (fsPersist[persisted]) {
                return persisted;
            }
        }
        var prefs = CALENDAR_DATE_DEFAULTS[objectApi] || ['CreatedDate'];
        var fieldSet = fieldSetFromColumns(cols);
        for (var i = 0; i < prefs.length; i++) {
            if (fieldSet[prefs[i]]) {
                return prefs[i];
            }
        }
        var dates = dateColumns(cols);
        return dates.length ? dates[0].fieldNameOrPath : '';
    }

    function parseRowDate(rawVal) {
        if (rawVal == null || rawVal === '') {
            return null;
        }
        var s = stripHtml(String(rawVal)).trim();
        if (!s) {
            return null;
        }
        var iso = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
        if (iso) {
            return { y: parseInt(iso[1], 10), m: parseInt(iso[2], 10) - 1, d: parseInt(iso[3], 10) };
        }
        var us = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/);
        if (us) {
            return { y: parseInt(us[3], 10), m: parseInt(us[1], 10) - 1, d: parseInt(us[2], 10) };
        }
        var eu = s.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})/);
        if (eu) {
            return { y: parseInt(eu[3], 10), m: parseInt(eu[2], 10) - 1, d: parseInt(eu[1], 10) };
        }
        var dt = new Date(s);
        if (!isNaN(dt.getTime())) {
            return { y: dt.getFullYear(), m: dt.getMonth(), d: dt.getDate() };
        }
        return null;
    }

    function dateKey(y, m, d) {
        return y + '-' + String(m + 1).padStart(2, '0') + '-' + String(d).padStart(2, '0');
    }

    var MONTH_NAMES = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
    ];
    var DAY_HEADERS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    function buildCalendarHtml(objectApi, columns, records, dateField, viewYear, viewMonth) {
        var cols = visibleColumns(columns || []);
        var linkField = primaryLinkField(columns);
        var dateCols = dateColumns(cols);
        if (!dateField || !fieldSetFromColumns(dateCols)[dateField]) {
            dateField = calendarDateField(objectApi, cols, dateField);
        }
        if (dateCols.length === 0) {
            return (
                '<div class="ch-cal-empty slds-box slds-theme_warning">' +
                '<p class="slds-text-body_regular">Calendar needs a date column in this list view. Add a date field to the list view or use List/Cards/Kanban.</p>' +
                '</div>'
            );
        }
        var byDay = {};
        var unscheduled = 0;
        for (var r = 0; r < records.length; r++) {
            var row = records[r];
            var parsed = parseRowDate(valueForField(row, dateField));
            if (!parsed) {
                unscheduled++;
                continue;
            }
            var key = dateKey(parsed.y, parsed.m, parsed.d);
            if (!byDay[key]) {
                byDay[key] = [];
            }
            byDay[key].push(row);
        }
        var first = new Date(viewYear, viewMonth, 1);
        var startDow = first.getDay();
        var daysInMonth = new Date(viewYear, viewMonth + 1, 0).getDate();
        var today = new Date();
        var todayKey = dateKey(today.getFullYear(), today.getMonth(), today.getDate());
        var sb = [];
        sb.push('<div class="ch-cal ch-cal--narrow">');
        sb.push('<div class="ch-cal-toolbar slds-grid slds-wrap slds-grid_vertical-align-center slds-m-bottom_small">');
        sb.push('<div class="slds-col slds-grow ch-cal-nav">');
        sb.push('<button type="button" class="slds-button slds-button_neutral ch-cal-prev" title="Previous month">&#8249;</button> ');
        sb.push('<button type="button" class="slds-button slds-button_neutral ch-cal-today">Today</button> ');
        sb.push('<button type="button" class="slds-button slds-button_neutral ch-cal-next" title="Next month">&#8250;</button> ');
        sb.push(
            '<span class="ch-cal-title slds-text-heading_small slds-m-left_small">' +
                esc(MONTH_NAMES[viewMonth]) +
                ' ' +
                esc(viewYear) +
                '</span>'
        );
        sb.push('</div>');
        sb.push('<div class="slds-col slds-no-flex ch-cal-field-wrap">');
        sb.push('<label class="slds-form-element__label slds-m-right_x-small" for="ch-cal-fld-' + esc(objectApi) + '">Date field</label>');
        sb.push('<select id="ch-cal-fld-' + esc(objectApi) + '" class="slds-select ch-cal-date-field">');
        for (var di = 0; di < dateCols.length; di++) {
            var dc = dateCols[di];
            sb.push(
                '<option value="' +
                    esc(dc.fieldNameOrPath) +
                    '"' +
                    (dc.fieldNameOrPath === dateField ? ' selected="selected"' : '') +
                    '>' +
                    esc(dc.label || dc.fieldNameOrPath) +
                    '</option>'
            );
        }
        sb.push('</select></div></div>');
        sb.push('<div class="ch-cal-scroll">');
        sb.push('<div class="ch-cal-grid">');
        sb.push('<div class="ch-cal-head-row">');
        for (var hi = 0; hi < DAY_HEADERS.length; hi++) {
            sb.push('<div class="ch-cal-head-cell">' + esc(DAY_HEADERS[hi]) + '</div>');
        }
        sb.push('</div><div class="ch-cal-body">');
        var cell = 0;
        var agendaDays = [];
        for (var pad = 0; pad < startDow; pad++) {
            sb.push('<div class="ch-cal-day ch-cal-day-pad" aria-hidden="true"></div>');
            cell++;
        }
        for (var day = 1; day <= daysInMonth; day++) {
            var dk = dateKey(viewYear, viewMonth, day);
            var isToday = dk === todayKey;
            var evts = byDay[dk] || [];
            var hasEvts = evts.length > 0;
            sb.push(
                '<div class="ch-cal-day' +
                    (isToday ? ' ch-cal-day-today' : '') +
                    (hasEvts ? ' ch-cal-day-has-events' : '') +
                    '" data-date="' +
                    esc(dk) +
                    '">'
            );
            sb.push('<div class="ch-cal-day-num">' + esc(day) + '</div>');
            if (hasEvts) {
                sb.push('<span class="ch-cal-day-count" aria-label="' + esc(evts.length) + ' events">' + esc(evts.length) + '</span>');
            }
            sb.push('<div class="ch-cal-events">');
            for (var ei = 0; ei < evts.length; ei++) {
                var erow = evts[ei];
                var rid = recordIdFromRow(erow);
                var nm = valueForField(erow, linkField) || valueForField(erow, 'Name') || rid;
                sb.push(
                    '<div class="ch-cal-event" data-record-id="' +
                        esc(rid) +
                        '" data-record-name="' +
                        esc(nm) +
                        '" data-object-api="' +
                        esc(objectApi) +
                        '" title="' +
                        esc(nm) +
                        '">' +
                        '<button type="button" class="ch-cal-event-txt ch-open slds-button slds-button_reset" data-id="' +
                        esc(rid) +
                        '" data-record-id="' +
                        esc(rid) +
                        '">' +
                        esc(nm) +
                        '</button>' +
                        openRecordIconBtn(rid, nm, true) +
                        '</div>'
                );
            }
            sb.push('</div></div>');
            if (hasEvts) {
                agendaDays.push({ day: day, key: dk, isToday: isToday, events: evts });
            }
            cell++;
        }
        while (cell % 7 !== 0) {
            sb.push('<div class="ch-cal-day ch-cal-day-pad" aria-hidden="true"></div>');
            cell++;
        }
        sb.push('</div></div>');

        sb.push('<div class="ch-cal-agenda" aria-label="Portrait agenda">');
        if (agendaDays.length === 0) {
            sb.push('<div class="ch-cal-agenda-empty">No dated records this month in the current page.</div>');
        } else {
            for (var ai = 0; ai < agendaDays.length; ai++) {
                var ad = agendaDays[ai];
                var adDate = new Date(viewYear, viewMonth, ad.day);
                var dow = DAY_HEADERS[adDate.getDay()];
                sb.push(
                    '<div class="ch-cal-agenda-day' +
                        (ad.isToday ? ' ch-cal-day-today' : '') +
                        '" data-date="' +
                        esc(ad.key) +
                        '">'
                );
                sb.push('<div class="ch-cal-agenda-head">');
                sb.push(
                    '<span class="ch-cal-agenda-date">' +
                        esc(MONTH_NAMES[viewMonth]) +
                        ' ' +
                        esc(ad.day) +
                        '</span>'
                );
                sb.push('<span class="ch-cal-agenda-dow">' + esc(dow) + (ad.isToday ? ' · Today' : '') + '</span>');
                sb.push('</div><div class="ch-cal-agenda-events">');
                for (var aei = 0; aei < ad.events.length; aei++) {
                    var arow = ad.events[aei];
                    var arid = recordIdFromRow(arow);
                    var anm = valueForField(arow, linkField) || valueForField(arow, 'Name') || arid;
                    sb.push(
                        '<div class="ch-cal-event" data-record-id="' +
                            esc(arid) +
                            '" data-record-name="' +
                            esc(anm) +
                            '" data-object-api="' +
                            esc(objectApi) +
                            '" title="' +
                            esc(anm) +
                            '">' +
                            '<button type="button" class="ch-cal-event-txt ch-open slds-button slds-button_reset" data-id="' +
                            esc(arid) +
                            '" data-record-id="' +
                            esc(arid) +
                            '">' +
                            esc(anm) +
                            '</button>' +
                            openRecordIconBtn(arid, anm, true) +
                            '</div>'
                    );
                }
                sb.push('</div></div>');
            }
        }
        sb.push('</div></div>');

        sb.push(
            '<p class="slds-text-body_small slds-m-top_x-small slds-text-color_weak">Date: ' +
                esc(dateField) +
                ' · ' +
                esc(records.length) +
                ' records · ' +
                esc(unscheduled) +
                ' without date · paged data only</p>'
        );
        sb.push('</div>');
        return sb.join('');
    }

    function colFilterPanelOpen(state, fieldApi) {
        if (!state || !fieldApi) {
            return false;
        }
        return !!(state.colFilterOpen && state.colFilterOpen[fieldApi]);
    }

    function colFilterBtnActive(state, fieldApi) {
        if (!state || !fieldApi) {
            return false;
        }
        return !!(state.colFilters && String(state.colFilters[fieldApi] || '').trim());
    }

    function colFilterFunnelBtn(fieldApi, state) {
        var active = colFilterBtnActive(state, fieldApi) ? ' is-active' : '';
        var open = colFilterPanelOpen(state, fieldApi);
        return (
            '<button type="button" class="ch-col-filter-btn' +
            active +
            '" data-field="' +
            esc(fieldApi) +
            '" title="Filter column" aria-label="Filter column" aria-expanded="' +
            (open ? 'true' : 'false') +
            '">' +
            '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M22 3H2l8 9v7l4 2v-9l8-9z"/></svg>' +
            '</button>'
        );
    }

    function colFilterPanelHtml(fieldApi, state) {
        var openCls = colFilterPanelOpen(state, fieldApi) ? ' is-open' : '';
        var val = state && state.colFilters ? state.colFilters[fieldApi] || '' : '';
        return (
            '<div class="ch-col-filter-wrap' +
            openCls +
            '" data-field="' +
            esc(fieldApi) +
            '">' +
            '<input class="slds-input slds-input_height ch-col-filter" type="search" data-field="' +
            esc(fieldApi) +
            '" placeholder="Filter…" value="' +
            esc(val) +
            '" />' +
            '<button type="button" class="ch-col-filter-clear" data-field="' +
            esc(fieldApi) +
            '" title="Clear filter" aria-label="Clear filter">×</button>' +
            '</div>'
        );
    }

    function rowMatchesFilters(row, cols, colFilters, globalQ) {
        var g = (globalQ || '').trim().toLowerCase();
        if (g) {
            var hit = false;
            for (var i = 0; i < cols.length; i++) {
                var fv = cellDisplayText(cols[i], valueForField(row, cols[i].fieldNameOrPath)).toLowerCase();
                if (fv.indexOf(g) >= 0) {
                    hit = true;
                    break;
                }
            }
            if (!hit) {
                return false;
            }
        }
        for (var f in colFilters) {
            if (!Object.prototype.hasOwnProperty.call(colFilters, f)) {
                continue;
            }
            var q = (colFilters[f] || '').trim().toLowerCase();
            if (!q) {
                continue;
            }
            var col = null;
            for (var j = 0; j < cols.length; j++) {
                if (cols[j].fieldNameOrPath === f) {
                    col = cols[j];
                    break;
                }
            }
            if (!col) {
                continue;
            }
            var val = cellDisplayText(col, valueForField(row, f)).toLowerCase();
            if (val.indexOf(q) < 0) {
                return false;
            }
        }
        return true;
    }

    function sortRowsByField(rows, cols, fieldApi, dir) {
        var mult = dir === 'desc' ? -1 : 1;
        if (fieldApi === '_chScore') {
            rows.sort(function (a, b) {
                var na = a && a._chScore != null && a._chScore !== '' ? Number(a._chScore) : -1;
                var nb = b && b._chScore != null && b._chScore !== '' ? Number(b._chScore) : -1;
                if (isNaN(na)) {
                    na = -1;
                }
                if (isNaN(nb)) {
                    nb = -1;
                }
                return mult * (na - nb);
            });
            return;
        }
        var colMeta = null;
        for (var i = 0; i < cols.length; i++) {
            if (cols[i].fieldNameOrPath === fieldApi) {
                colMeta = cols[i];
                break;
            }
        }
        rows.sort(function (a, b) {
            var va = valueForField(a, fieldApi);
            var vb = valueForField(b, fieldApi);
            if (va == null) {
                va = '';
            }
            if (vb == null) {
                vb = '';
            }
            if (colMeta && (colMeta.type === 'double' || colMeta.type === 'currency' || colMeta.type === 'percent' || colMeta.type === 'int')) {
                var na = parseFloat(va);
                var nb = parseFloat(vb);
                if (isNaN(na)) {
                    na = 0;
                }
                if (isNaN(nb)) {
                    nb = 0;
                }
                return mult * (na - nb);
            }
            return mult * String(va).localeCompare(String(vb));
        });
    }

    function sortRowsByOrig(rows) {
        rows.sort(function (a, b) {
            return (a._chOrig || 0) - (b._chOrig || 0);
        });
    }

    /* Material Design icon paths (24x24) — inline SVG so VF CSP cannot break icons */
    var KANBAN_M3_SVG_CACHE = {};
    var KANBAN_M3_PATHS = {
        label: 'M17.63 5.84C17.27 5.33 16.67 5 16 5L5 5.01C3.9 5.01 3 5.9 3 7v10c0 1.1.9 1.99 2 1.99L16 19c.67 0 1.27-.33 1.63-.84L22 12l-4.37-6.16z',
        fiber_new:
            'M20 4H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V6c0-1.11-.89-2-2-2zM8.5 15H7.3l-1.05-3.2H3.7L2.65 15H1.5L3.9 9h1.7l2.4 6zm5.7 0h-1.45V9H14c1.12 0 2.05.38 2.05 1.67 0 .9-.57 1.41-1.17 1.54L16.7 15h-1.55l-1.4-2.6h-.55V15zm-3.35-5.9v1.7h1.05c.45 0 .8-.18.8-.85 0-.52-.35-.85-.85-.85H10.85zm7.85 5.9h-1.3V9h1.3v6zM8.05 12.35l.4-1.25.4 1.25h-.8z',
        inbox:
            'M19 3H4.99c-1.11 0-1.98.89-1.98 2L3 19c0 1.1.88 2 1.99 2H19c1.1 0 2-.9 2-2V5c0-1.11-.9-2-2-2zm0 12h-4c0 1.66-1.35 3-3 3s-3-1.34-3-3H4.99V5H19v10z',
        phone_in_talk:
            'M20 15.5c-1.25 0-2.45-.2-3.57-.57-.35-.11-.74-.03-1.02.24l-2.2 2.2c-2.83-1.44-5.15-3.75-6.59-6.59l2.2-2.21c.28-.27.36-.66.25-1.01C8.7 6.45 8.5 5.25 8.5 4c0-.55-.45-1-1-1H4c-.55 0-1 .45-1 1 0 9.39 7.61 17 17 17 .55 0 1-.45 1-1v-3.5c0-.55-.45-1-1-1zM19 12h2c0-4.97-4.03-9-9-9v2c3.87 0 7 3.13 7 7zm-4 0h2c0-2.76-2.24-5-5-5v2c1.66 0 3 1.34 3 3z',
        verified:
            'M23 12l-2.44-2.79.34-3.69-3.61-.82-1.89-3.2L12 2.96 8.6 1.5 6.71 4.69 3.1 5.5l.34 3.7L1 12l2.44 2.79-.34 3.7 3.61.82L8.6 22.5l3.4-1.47 3.4 1.46 1.89-3.19 3.61-.82-.34-3.69L23 12zm-12.91 4.72l-3.8-3.81 1.48-1.48 2.32 2.33 5.85-5.87 1.48 1.48-7.33 7.35z',
        person_off:
            'M8.65 14.65l-1.48-1.48C6.45 13.93 5.87 14.44 5.28 15 3.87 16.26 3 18.05 3 20.01V21h9.42l-3.77-3.77c-.53-.05-1.03-.2-1.5-.41l1.5-1.5zM17 20l-5.15-5.15C12.55 14.3 13.24 14 14 14c2.21 0 4 1.79 4 4v2h-1zm-1-9c1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3 1.34 3 3 3zM1.39 4.22l2.27 2.27.01-.01L15.73 18.5l2.77 2.77 1.27-1.27L2.66 2.95 1.39 4.22z',
        hourglass_top:
            'M6 2v6h.01L10 12l-3.99 4.01L6 22h12v-6l-4-4 4-3.99V2H6zm10 14.5V20H8v-3.5l4-4 4 4z',
        business_center:
            'M10 16v-1H3.01L3 19c0 1.11.89 2 2 2h14c1.11 0 2-.89 2-2v-4h-7v1h-4zm10-9h-4.01V5l-2-2h-4l-2 2v2H4c-1.1 0-2 .9-2 2v3c0 1.11.89 2 2 2h6v-2h4v2h6c1.1 0 2-.9 2-2V9c0-1.1-.9-2-2-2zm-6 0h-4V5h4v2z',
        event:
            'M17 12h-5v5h5v-5zM16 1v2H8V1H6v2H5c-1.11 0-1.99.9-1.99 2L3 19c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2h-1V1h-2zm3 18H5V8h14v11z',
        check_circle:
            'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z',
        forum:
            'M21 6h-2v9H6v2c0 .55.45 1 1 1h11l4 4V7c0-.55-.45-1-1-1zm-4 6V3c0-.55-.45-1-1-1H3c-.55 0-1 .45-1 1v14l4-4h10c.55 0 1-.45 1-1z',
        redeem:
            'M20 6h-2.18c.11-.31.18-.65.18-1 0-1.66-1.34-3-3-3-1.05 0-1.96.54-2.5 1.35l-.5.67-.5-.68C10.96 2.54 10.05 2 9 2 7.34 2 6 3.34 6 5c0 .35.07.69.18 1H4c-1.11 0-1.99.89-1.99 2L2 19c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-5-2c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zM9 4c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm11 15H4v-2h16v2zm0-5H4V8h5.08L7 10.83 8.62 12 11 8.76l1-1.36 1 1.36L15.38 12 17 10.83 14.92 8H20v6z',
        emoji_events:
            'M19 5h-2V3H7v2H5c-1.1 0-2 .9-2 2v1c0 2.55 1.92 4.63 4.39 4.94.63 1.5 1.98 2.63 3.61 2.96V19H7v2h10v-2h-4v-3.1c1.63-.33 2.98-1.46 3.61-2.96C19.08 12.63 21 10.55 21 8V7c0-1.1-.9-2-2-2zM5 8V7h2v3.82C5.84 10.4 5 9.3 5 8zm14 0c0 1.3-.84 2.4-2 2.82V7h2v1z',
        cancel:
            'M12 2C6.47 2 2 6.47 2 12s4.47 10 10 10 10-4.47 10-10S17.53 2 12 2zm5 13.59L15.59 17 12 13.41 8.41 17 7 15.59 10.59 12 7 8.41 8.41 7 12 10.59 15.59 7 17 8.41 13.41 12 17 15.59z',
        travel_explore:
            'M19.3 16.9c.4-.7.7-1.5.7-2.4 0-2.5-2-4.5-4.5-4.5S11 12 11 14.5s2 4.5 4.5 4.5c.9 0 1.7-.3 2.4-.7l3.2 3.2 1.4-1.4-3.2-3.2zm-3.8.1c-1.4 0-2.5-1.1-2.5-2.5s1.1-2.5 2.5-2.5 2.5 1.1 2.5 2.5-1.1 2.5-2.5 2.5zM12 20v2C6.48 22 2 17.52 2 12S6.48 2 12 2c4.84 0 8.87 3.44 9.8 8h-2.07c-.64-2.46-2.56-4.47-4.93-5.14v2.07c1.44.4 2.67 1.32 3.4 2.57H12.5C11.12 9.5 10 10.62 10 12s1.12 2.5 2.5 2.5h.5v2c-2.66 0-5.06-1.5-6.24-3.75C5.6 15.3 7.2 17.5 9.5 18.5c.7.3 1.45.5 2.25.5H12z',
        description:
            'M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z',
        handshake:
            'M16.24 11.65c.39-.39.39-1.02 0-1.41l-3.54-3.54c-.39-.39-1.02-.39-1.41 0-.39.39-.39 1.02 0 1.41l3.54 3.54c.39.39 1.03.39 1.41 0zM12.7 15.77l-1.06 1.06c-.39.39-.39 1.02 0 1.41.39.39 1.02.39 1.41 0l1.06-1.06c.39-.39.39-1.02 0-1.41-.39-.39-1.02-.39-1.41 0zM20.3 12.35l-1.41-1.41c-.39-.39-1.02-.39-1.41 0l-1.06 1.06 2.83 2.83 1.05-1.07c.39-.39.39-1.02 0-1.41zM4.41 15.06l2.83 2.83 1.06-1.06c.39-.39.39-1.02 0-1.41-.39-.39-1.02-.39-1.41 0L4.41 15.06zM11.65 7.76l-1.41 1.41c-.39.39-.39 1.02 0 1.41l3.54 3.54c.39.39 1.02.39 1.41 0 .39-.39.39-1.02 0-1.41L11.65 7.76zM7.76 11.65L6.35 10.24c-.39-.39-1.02-.39-1.41 0L3.52 11.66c-.39.39-.39 1.02 0 1.41l2.83 2.83 2.83-2.83c.39-.39.39-1.03 0-1.42zM19.07 4.93c-1.17-1.17-3.07-1.17-4.24 0L13.41 6.35l4.24 4.24 1.42-1.41c1.17-1.18 1.17-3.08 0-4.25zM5.64 19.07c1.17 1.17 3.07 1.17 4.24 0l1.41-1.41-4.24-4.24-1.41 1.41c-1.17 1.18-1.17 3.07 0 4.24z',
        lock: 'M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z',
        pending_actions:
            'M17 12c-2.76 0-5 2.24-5 5s2.24 5 5 5 5-2.24 5-5-2.24-5-5-5zm1.65 7.35L16.5 17.2V14h1v2.79l1.85 1.85-.7.71zM18 3h-3.18C14.4 1.84 13.3 1 12 1s-2.4.84-2.82 2H6c-1.1 0-2 .9-2 2v15c0 1.1.9 2 2 2h6.11c-.59-.57-1.07-1.25-1.39-2H6V5h2v3h8V5h2v5.08c.71.1 1.38.31 2 .62V5c0-1.1-.9-2-2-2zm-6 2c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1z',
        bolt: 'M11 21h-1l1-7H7.5c-.58 0-.57-.32-.38-.66.19-.34.05-.08.07-.12C8.48 10.94 10.42 7.54 13 3h1l-1 7h3.5c.49 0 .56.33.47.51l-.07.15C12.96 17.55 11 21 11 21z',
        pause_circle:
            'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9V8h2v8zm4 0h-2V8h2v8z',
        spa: 'M15.49 9.63c-.18-2.79-1.31-5.51-3.43-7.63-2.14 2.14-3.32 4.86-3.55 7.63 1.28.68 2.46 1.56 3.49 2.63 1.03-1.06 2.21-1.94 3.49-2.63zm-6.22 2.78c.1.24.2.47.32.7 1.71 3.02 4.11 5.43 6.41 6.89 2.3-1.46 4.7-3.87 6.41-6.89.12-.23.22-.46.32-.7-2.06-.99-4.28-1.55-6.73-1.55s-4.67.56-6.73 1.55z',
        star: 'M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z'
    };

    function kanbanM3Svg(icon, tone) {
        var cacheKey = String(icon || 'label') + '|' + String(tone || 'neutral');
        if (KANBAN_M3_SVG_CACHE[cacheKey]) {
            return KANBAN_M3_SVG_CACHE[cacheKey];
        }
        var path = KANBAN_M3_PATHS[icon] || KANBAN_M3_PATHS.label;
        var html =
            '<svg class="ch-kan-m3 ch-kan-m3--' +
            tone +
            '" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false">' +
            '<path fill="currentColor" d="' +
            path +
            '"/></svg>';
        KANBAN_M3_SVG_CACHE[cacheKey] = html;
        return html;
    }

    function kanbanLaneIcon(laneKey, laneLabel) {
        var s = String(laneLabel || laneKey || '').toLowerCase().trim();
        var icon = 'label';
        var tone = 'neutral';

        if (s === 'open' || s.indexOf('open -') === 0) {
            icon = 'inbox';
            tone = 'blue';
        } else if (s.indexOf('contacted') >= 0 || s.indexOf('working') >= 0) {
            icon = 'phone_in_talk';
            tone = 'indigo';
        } else if (s.indexOf('unqualif') >= 0 || s.indexOf('disqualif') >= 0) {
            icon = 'person_off';
            tone = 'red';
        } else if (s.indexOf('qualif') >= 0) {
            icon = 'verified';
            tone = 'green';
        } else if (s.indexOf('nurtur') >= 0) {
            icon = 'spa';
            tone = 'teal';
        } else if (s.indexOf('screen') >= 0) {
            icon = 'hourglass_top';
            tone = 'indigo';
        } else if (s.indexOf('case') >= 0 || s.indexOf('study') >= 0) {
            icon = 'business_center';
            tone = 'brown';
        } else if (s.indexOf('interviewed') >= 0) {
            icon = 'check_circle';
            tone = 'green';
        } else if (s.indexOf('interview') >= 0) {
            icon = 'event';
            tone = 'blue';
        } else if (s.indexOf('feedback') >= 0 || s.indexOf('waiting') >= 0) {
            icon = 'forum';
            tone = 'violet';
        } else if (s.indexOf('offer') >= 0) {
            icon = 'redeem';
            tone = 'pink';
        } else if (s.indexOf('accept') >= 0 || s.indexOf('hired') >= 0) {
            icon = 'emoji_events';
            tone = 'gold';
        } else if (s.indexOf('reject') >= 0 || s.indexOf('declin') >= 0) {
            icon = 'cancel';
            tone = 'red';
        } else if (s.indexOf('prospect') >= 0) {
            icon = 'travel_explore';
            tone = 'teal';
        } else if (s.indexOf('propos') >= 0) {
            icon = 'description';
            tone = 'slate';
        } else if (s.indexOf('negotiat') >= 0) {
            icon = 'handshake';
            tone = 'violet';
        } else if (s.indexOf('closed won') >= 0 || s === 'won' || s.indexOf('closed-won') >= 0) {
            icon = 'emoji_events';
            tone = 'gold';
        } else if (s.indexOf('closed lost') >= 0 || s === 'lost' || s.indexOf('closed-lost') >= 0) {
            icon = 'cancel';
            tone = 'red';
        } else if (s.indexOf('closed') >= 0) {
            icon = 'lock';
            tone = 'slate';
        } else if (s.indexOf('analysis') >= 0 || s.indexOf('progress') >= 0) {
            icon = 'pending_actions';
            tone = 'blue';
        } else if (s.indexOf('active') >= 0) {
            icon = 'bolt';
            tone = 'amber';
        } else if (s.indexOf('inactive') >= 0 || s.indexOf('hold') >= 0) {
            icon = 'pause_circle';
            tone = 'slate';
        } else if (s.indexOf('new') >= 0) {
            icon = 'fiber_new';
            tone = 'amber';
        }

        return kanbanM3Svg(icon, tone);
    }

    function stripCellText(htmlOrText) {
        if (htmlOrText == null || htmlOrText === '') {
            return '';
        }
        return stripHtml(String(htmlOrText)).replace(/\s+/g, ' ').trim();
    }

    function looksLikeSalesforceId(val) {
        var s = String(val || '').trim();
        return /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(s);
    }

    function jobAppRedFlags(row, displayName, recordId) {
        var missingName =
            row && row._chMissingName === true
                ? true
                : !displayName ||
                  looksLikeSalesforceId(displayName) ||
                  String(displayName) === String(recordId || '');
        var missingTrailhead = row && row._chMissingTrailhead === true;
        var missingResume = row && row._chMissingResume === true;
        /* If enrichment missing (fallback path), still flag obvious missing name */
        if (row && row._chMissingTrailhead === undefined) {
            missingTrailhead = false;
            missingResume = false;
        }
        return {
            missingName: !!missingName,
            missingTrailhead: !!missingTrailhead,
            missingResume: !!missingResume
        };
    }

    function scoreInfoFromRow(row) {
        if (!row || row._chScore === undefined || row._chScore === null || row._chScore === '') {
            return null;
        }
        var n = Number(row._chScore);
        if (isNaN(n)) {
            return null;
        }
        var factors = row._chScoreFactors;
        if (!factors || !factors.length) {
            factors = [];
        }
        return {
            score: n,
            band: row._chScoreBand || 'Watch',
            factors: factors
        };
    }

    function buildScoreFactorsHtml(factors) {
        if (!factors || !factors.length) {
            return '<p class="ch-score-empty">No score factors yet.</p>';
        }
        var sb = ['<ul class="ch-score-factors">'];
        for (var i = 0; i < factors.length; i++) {
            var f = factors[i] || {};
            var delta = Number(f.delta);
            if (isNaN(delta)) {
                delta = 0;
            }
            var pol = f.polarity || (delta > 0 ? '+' : delta < 0 ? '-' : '0');
            var cls =
                pol === '+'
                    ? 'ch-score-factor--plus'
                    : pol === '-'
                      ? 'ch-score-factor--minus'
                      : 'ch-score-factor--zero';
            var deltaTxt = delta > 0 ? '+' + delta : String(delta);
            sb.push(
                '<li class="ch-score-factor ' +
                    cls +
                    '"><span class="ch-score-pol" aria-hidden="true">' +
                    esc(pol === '0' ? '·' : pol) +
                    '</span><span class="ch-score-label">' +
                    esc(f.label || '') +
                    '</span><span class="ch-score-delta">' +
                    esc(deltaTxt) +
                    '</span></li>'
            );
        }
        sb.push('</ul>');
        return sb.join('');
    }

    function buildScoreBadgeHtml(row, opts) {
        var info = scoreInfoFromRow(row);
        if (!info) {
            return '';
        }
        var compact = opts && opts.compact;
        var bandSlug = String(info.band || 'Watch')
            .toLowerCase()
            .replace(/[^a-z]/g, '');
        var sb = [];
        sb.push('<div class="ch-score-wrap' + (compact ? ' ch-score-wrap--compact' : '') + '">');
        sb.push(
            '<button type="button" class="ch-score-badge ch-score--' +
                esc(bandSlug) +
                '" aria-haspopup="dialog" title="Why this score">'
        );
        sb.push('<span class="ch-score-num">' + esc(String(info.score)) + '</span>');
        if (!compact) {
            sb.push('<span class="ch-score-band">' + esc(info.band) + '</span>');
        }
        sb.push('</button>');
        sb.push('<div class="ch-score-data" hidden>');
        sb.push(
            '<div class="ch-score-modal-sub">Score ' +
                esc(String(info.score)) +
                ' · ' +
                esc(info.band) +
                '</div>'
        );
        sb.push(buildScoreFactorsHtml(info.factors));
        sb.push('</div></div>');
        return sb.join('');
    }

    function closeScoreModal() {
        var overlay = document.getElementById('ch-score-modal');
        if (overlay) {
            overlay.style.display = 'none';
            var body = overlay.querySelector('.ch-score-modal-body');
            if (body) {
                body.innerHTML = '';
            }
        }
        var openBtns = document.querySelectorAll('.ch-score-badge[aria-expanded="true"]');
        for (var i = 0; i < openBtns.length; i++) {
            openBtns[i].setAttribute('aria-expanded', 'false');
        }
    }

    function ensureScoreModal() {
        var overlay = document.getElementById('ch-score-modal');
        if (overlay) {
            return overlay;
        }
        overlay = document.createElement('div');
        overlay.id = 'ch-score-modal';
        overlay.className = 'ch-score-modal-overlay';
        overlay.style.display = 'none';
        overlay.setAttribute('role', 'dialog');
        overlay.setAttribute('aria-modal', 'true');
        overlay.setAttribute('aria-labelledby', 'ch-score-modal-title');
        overlay.innerHTML =
            '<div class="ch-score-modal-inner">' +
            '<div class="ch-score-modal-header">' +
            '<h2 id="ch-score-modal-title" class="ch-score-modal-title">Reason behind the score</h2>' +
            '<button type="button" class="ch-score-modal-close" aria-label="Close">&times;</button>' +
            '</div>' +
            '<div class="ch-score-modal-body"></div>' +
            '</div>';
        document.body.appendChild(overlay);
        overlay.addEventListener('click', function (ev) {
            if (ev.target === overlay || ev.target.closest('.ch-score-modal-close')) {
                ev.preventDefault();
                ev.stopPropagation();
                closeScoreModal();
            }
        });
        document.addEventListener('keydown', function (ev) {
            if (ev.key === 'Escape' && overlay.style.display !== 'none') {
                closeScoreModal();
            }
        });
        return overlay;
    }

    function openScoreModalFromWrap(wrap, badge) {
        var data = wrap.querySelector('.ch-score-data');
        if (!data) {
            return;
        }
        var overlay = ensureScoreModal();
        var body = overlay.querySelector('.ch-score-modal-body');
        body.innerHTML = data.innerHTML;
        if (badge) {
            badge.setAttribute('aria-expanded', 'true');
        }
        overlay.style.display = 'flex';
    }

    function ensureScorePopoverDelegation() {
        if (global.__chScorePopBound) {
            return;
        }
        global.__chScorePopBound = true;
        document.addEventListener(
            'click',
            function (ev) {
                var badge = ev.target.closest ? ev.target.closest('.ch-score-badge') : null;
                if (badge) {
                    ev.preventDefault();
                    ev.stopPropagation();
                    if (ev.stopImmediatePropagation) {
                        ev.stopImmediatePropagation();
                    }
                    var wrap = badge.closest('.ch-score-wrap');
                    if (!wrap) {
                        return;
                    }
                    openScoreModalFromWrap(wrap, badge);
                    return;
                }
            },
            true
        );
    }

    function buildKanbanRedFlagsHtml(flags) {
        if (!flags) {
            return '';
        }
        var chips = [];
        if (flags.missingName) {
            chips.push(
                '<span class="ch-kan-flag ch-kan-flag--name" title="Applicant did not enter a name">No name</span>'
            );
        }
        if (flags.missingTrailhead) {
            chips.push(
                '<span class="ch-kan-flag ch-kan-flag--trail" title="Missing Trailhead profile link">No Trailhead</span>'
            );
        }
        if (flags.missingResume) {
            chips.push(
                '<span class="ch-kan-flag ch-kan-flag--resume" title="Missing resume / CV link">No resume</span>'
            );
        }
        if (!chips.length) {
            return '';
        }
        return '<div class="ch-kan-flags" role="list">' + chips.join('') + '</div>';
    }

    function buildKanbanCardHtml(objectApi, brow, linkField, laneField, cardFields, columns) {
        var rid = recordIdFromRow(brow);
        var nm =
            (brow && brow._chApplicantName) ||
            resolveRecordDisplayName(brow, columns || cardFields, linkField) ||
            rid;
        var flags =
            objectApi === 'Job_Application__c' ? jobAppRedFlags(brow, nm, rid) : null;
        if (flags && flags.missingName && looksLikeSalesforceId(nm)) {
            nm = 'Unnamed applicant';
        }
        var sb = [];
        sb.push(
            '<div class="ch-kan-card' +
                (flags && (flags.missingName || flags.missingTrailhead || flags.missingResume)
                    ? ' ch-kan-card--flagged'
                    : '') +
                '" data-record-id="' +
                esc(rid) +
                '" data-record-name="' +
                esc(nm) +
                '" data-object-api="' +
                esc(objectApi) +
                '">'
        );
        sb.push('<div class="ch-kan-card-top">');
        sb.push('<span class="ch-kan-drag" aria-hidden="true" title="Drag">⋮⋮</span>');
        sb.push(
            '<button type="button" class="slds-button slds-button_link ch-open ch-kan-card-link' +
                (flags && flags.missingName ? ' ch-kan-card-link--missing' : '') +
                '" data-id="' +
                esc(rid) +
                '">' +
                esc(nm) +
                '</button>'
        );
        sb.push(openRecordIconBtn(rid, nm, true));
        sb.push('</div>');
        if (objectApi === 'Job_Application__c' || objectApi === 'Opportunity') {
            var scoreHtml = buildScoreBadgeHtml(brow, { compact: true });
            if (scoreHtml) {
                sb.push('<div class="ch-kan-score">' + scoreHtml + '</div>');
            }
        }
        if (flags) {
            sb.push(buildKanbanRedFlagsHtml(flags));
        }
        if (cardFields.length) {
            sb.push('<div class="ch-kan-card-body">');
            for (var fi = 0; fi < cardFields.length; fi++) {
                var fcol = cardFields[fi];
                var fval = valueForField(brow, fcol.fieldNameOrPath);
                if (fval == null || String(fval).trim() === '') {
                    continue;
                }
                /* Formula IMAGE/HYPERLINK (e.g. LinkedIn/Gender icons) — render HTML */
                if (
                    fieldTypeIsHtml(fcol) ||
                    isHtmlDisplayField(fcol) ||
                    isRenderableHtml(fval)
                ) {
                    var htmlInner = cellInnerHtml(fcol, fval, cellForField(brow, fcol.fieldNameOrPath));
                    if (!htmlInner) {
                        continue;
                    }
                    sb.push(
                        '<div class="ch-kan-card-row ch-kan-card-html">' + htmlInner + '</div>'
                    );
                    continue;
                }
                var text = stripCellText(String(fval));
                if (!text) {
                    continue;
                }
                var isLane = fcol.fieldNameOrPath === laneField;
                if (isLane) {
                    sb.push(
                        '<div class="ch-kan-card-row ch-kan-card-lane">' +
                            '<span class="ch-kan-card-lane-ico" aria-hidden="true">' +
                            kanbanLaneIcon(fval, text) +
                            '</span>' +
                            '<span class="ch-kan-card-val">' +
                            esc(text) +
                            '</span></div>'
                    );
                } else {
                    sb.push(
                        '<div class="ch-kan-card-row">' +
                            '<span class="ch-kan-card-val">' +
                            esc(text) +
                            '</span></div>'
                    );
                }
            }
            sb.push('</div>');
        }
        sb.push('</div>');
        return sb.join('');
    }

    function buildKanbanHtml(objectApi, columns, summarizeField, kanbanState) {
        var cols = visibleColumns(columns || []);
        var linkField = primaryLinkField(columns);
        var laneField =
            (kanbanState && kanbanState.laneField) || kanbanLaneField(objectApi, cols);
        if (!laneField) {
            return (
                '<div class="ch-kanban-empty slds-box slds-theme_warning">' +
                '<p class="slds-text-body_regular">Kanban needs a lane column (e.g. Stage or Status) in this list view. Try another list view or use List/Cards.</p>' +
                '</div>'
            );
        }
        var sumCols = summarizableColumns(cols);
        var sumField = kanbanSummarizeField(objectApi, cols, summarizeField);
        var sumCol = sumField ? columnByField(cols, sumField) : null;
        var cardFields = kanbanCardFields(cols, linkField, laneField);
        var lanes = (kanbanState && kanbanState.laneRecords) || {};
        var laneCounts = (kanbanState && kanbanState.laneCounts) || {};
        var laneOrder =
            (kanbanState && kanbanState.laneOrder && kanbanState.laneOrder.length
                ? kanbanState.laneOrder
                : null) || resolveKanbanLaneOrder(laneField, cols, lanes);
        var loadingLane = (kanbanState && kanbanState.loadingLane) || '';
        var sb = [];
        sb.push('<div class="ch-kanban-wrap ch-kanban-wrap--lex">');

        sb.push('<div class="ch-kan-toolbar">');
        var laneCols = kanbanLaneCandidateColumns(objectApi, cols, laneField);
        if (laneCols.length) {
            sb.push('<div class="ch-kan-sum-wrap">');
            sb.push(
                '<label class="ch-kan-sum-lbl" for="ch-kan-lane-' + esc(objectApi) + '">Columns by</label>'
            );
            sb.push(
                '<select id="ch-kan-lane-' +
                    esc(objectApi) +
                    '" class="slds-select ch-kan-lane-field" title="Kanban column field">'
            );
            for (var liSel = 0; liSel < laneCols.length; liSel++) {
                var lc = laneCols[liSel];
                sb.push(
                    '<option value="' +
                        esc(lc.fieldNameOrPath) +
                        '"' +
                        (lc.fieldNameOrPath === laneField ? ' selected="selected"' : '') +
                        '>' +
                        esc(lc.label || lc.fieldNameOrPath) +
                        '</option>'
                );
            }
            sb.push('</select></div>');
        }
        if (sumCols.length) {
            sb.push('<div class="ch-kan-sum-wrap">');
            sb.push(
                '<label class="ch-kan-sum-lbl" for="ch-kan-sum-' + esc(objectApi) + '">Summarize by</label>'
            );
            sb.push(
                '<select id="ch-kan-sum-' +
                    esc(objectApi) +
                    '" class="slds-select ch-kan-summarize-field" title="Kanban summarize field">'
            );
            sb.push('<option value=""' + (!sumField ? ' selected="selected"' : '') + '>None</option>');
            for (var si = 0; si < sumCols.length; si++) {
                var sc = sumCols[si];
                sb.push(
                    '<option value="' +
                        esc(sc.fieldNameOrPath) +
                        '"' +
                        (sc.fieldNameOrPath === sumField ? ' selected="selected"' : '') +
                        '>' +
                        esc(sc.label || sc.fieldNameOrPath) +
                        '</option>'
                );
            }
            sb.push('</select></div>');
        } else {
            sb.push(
                '<div class="ch-kan-sum-wrap ch-kan-sum-wrap--muted">No number/currency fields on this list view to summarize</div>'
            );
        }
        sb.push('</div>');

        sb.push('<div class="ch-kanban">');
        sb.push('<div class="ch-kanban-row">');
        for (var li = 0; li < laneOrder.length; li++) {
            var ln = laneOrder[li];
            var bucket = lanes[ln] || [];
            var total =
                laneCounts[ln] != null
                    ? Number(laneCounts[ln])
                    : laneCounts[String(ln)] != null
                      ? Number(laneCounts[String(ln)])
                      : bucket.length;
            if (isNaN(total)) {
                total = bucket.length;
            }
            var remaining = Math.max(0, total - bucket.length);
            var laneDisp = kanbanLaneLabel(ln, cols, laneField);
            var laneIco = kanbanLaneIcon(ln, laneDisp);
            sb.push('<div class="ch-kan-col" data-lane="' + esc(ln) + '">');
            sb.push(
                '<div class="ch-kan-col-hdr" title="' +
                    esc(laneDisp) +
                    '">' +
                    '<span class="ch-kan-col-ico" aria-hidden="true">' +
                    laneIco +
                    '</span>' +
                    '<span class="ch-kan-col-title">' +
                    esc(laneDisp) +
                    '</span>' +
                    '<span class="ch-kan-col-count" title="Total in this list view">' +
                    total +
                    '</span></div>'
            );
            if (sumField && sumCol) {
                var laneSum = sumLaneField(bucket, sumField);
                sb.push(
                    '<div class="ch-kan-col-sum" title="' +
                        esc(sumCol.label || sumField) +
                        '">' +
                        esc(formatKanbanSummary(laneSum, sumCol)) +
                        '</div>'
                );
            } else {
                sb.push('<div class="ch-kan-col-sum ch-kan-col-sum--placeholder">&nbsp;</div>');
            }
            sb.push('<div class="ch-kan-col-cards">');
            for (var bi = 0; bi < bucket.length; bi++) {
                sb.push(buildKanbanCardHtml(objectApi, bucket[bi], linkField, laneField, cardFields, cols));
            }
            if (remaining > 0) {
                var isLoading = loadingLane === ln;
                sb.push(
                    '<button type="button" class="ch-kan-more" data-lane="' +
                        esc(ln) +
                        '"' +
                        (isLoading ? ' disabled' : '') +
                        '>' +
                        (isLoading
                            ? 'Loading…'
                            : 'View more (' + remaining + ')') +
                        '</button>'
                );
            }
            sb.push('</div></div>');
        }
        sb.push('</div></div>');
        sb.push(
            '<p class="ch-kan-footnote">On-demand per column · Columns by: ' +
                esc(laneField) +
                (sumField ? ' · Summarize: ' + esc(sumCol && sumCol.label ? sumCol.label : sumField) : '') +
                '</p>'
        );
        sb.push('</div>');
        return sb.join('');
    }

    function buildCardsHtml(objectApi, columns, records) {
        var cols = visibleColumns(columns || []).slice(0, 8);
        var linkField = primaryLinkField(columns);
        var sb = [];
        sb.push('<div class="ch-cards">');
        for (var r = 0; r < records.length; r++) {
            var row = records[r];
            var rid = recordIdFromRow(row);
            var nameVal =
                (row && row._chApplicantName) ||
                resolveRecordDisplayName(row, columns || cols, linkField) ||
                rid;
            var flags =
                objectApi === 'Job_Application__c' ? jobAppRedFlags(row, nameVal, rid) : null;
            if (flags && flags.missingName && looksLikeSalesforceId(nameVal)) {
                nameVal = 'Unnamed applicant';
            }
            sb.push(
                '<div class="ch-card slds-box slds-m-bottom_small' +
                    (flags && (flags.missingName || flags.missingTrailhead || flags.missingResume)
                        ? ' ch-kan-card--flagged'
                        : '') +
                    '" data-record-id="' +
                    esc(rid) +
                    '" data-record-name="' +
                    esc(nameVal) +
                    '" data-object-api="' +
                    esc(objectApi) +
                    '">'
            );
            sb.push(
                '<div class="ch-card-title"><button type="button" class="slds-button slds-button_link ch-open ch-card-link' +
                    (flags && flags.missingName ? ' ch-kan-card-link--missing' : '') +
                    '" data-id="' +
                    esc(rid) +
                    '">' +
                    esc(nameVal) +
                    '</button>' +
                    openRecordIconBtn(rid, nameVal, true) +
                    '</div>'
            );
            if (objectApi === 'Job_Application__c' || objectApi === 'Opportunity') {
                var cardScore = buildScoreBadgeHtml(row, { compact: true });
                if (cardScore) {
                    sb.push('<div class="ch-card-score">' + cardScore + '</div>');
                }
            }
            if (flags) {
                sb.push(buildKanbanRedFlagsHtml(flags));
            }
            for (var j = 0; j < cols.length; j++) {
                var col = cols[j];
                if (
                    col.fieldNameOrPath === 'Name' ||
                    col.fieldNameOrPath === 'ApplicantName__c' ||
                    col.fieldNameOrPath === 'Applicant_Name__c'
                ) {
                    continue;
                }
                /* Skip plain title field; keep Quick Contact / IMAGE formulas as icon rows */
                if (
                    col.fieldNameOrPath === linkField &&
                    !isHtmlDisplayField(col) &&
                    !fieldTypeIsHtml(col)
                ) {
                    continue;
                }
                var val = valueForField(row, col.fieldNameOrPath);
                var cardCell = cellForField(row, col.fieldNameOrPath);
                if (
                    isHtmlDisplayField(col) ||
                    fieldTypeIsHtml(col) ||
                    isRenderableHtml(val)
                ) {
                    sb.push(
                        '<div class="ch-card-row ch-card-html">' +
                            cellInnerHtml(col, val, cardCell) +
                            '</div>'
                    );
                    continue;
                }
                sb.push(
                    '<div class="ch-card-row"><span class="ch-card-lbl">' +
                        esc(col.label || col.fieldNameOrPath) +
                        ':</span> <span class="ch-card-val">' +
                        cellInnerHtml(col, val, cardCell) +
                        '</span></div>'
                );
            }
            sb.push('</div>');
        }
        sb.push('</div>');
        return sb.join('');
    }

    function TabState(cfg) {
        this.objectApi = cfg.objectApi;
        this.lightningSegment = cfg.lightningSegment || cfg.objectApi;
        this.listViewId = cfg.initialListViewId || '';
        var persistedPs = typeof readPersistedPageSize === 'function' ? readPersistedPageSize(cfg.objectApi) : null;
        this.pageSize = persistedPs || cfg.pageSize || 25;
        this.offset = 0;
        this.nextRecordsUrl = null;
        this.columns = [];
        this.allRows = [];
        this.mode = cfg.initialMode || 'list';
        this.listEl = cfg.listEl;
        this.cardsEl = cfg.cardsEl;
        this.kanbanEl = cfg.kanbanEl;
        this.calendarEl = cfg.calendarEl;
        this.pagerEl = cfg.pagerEl;
        this.actionsPrefix = cfg.actionsPrefix || '';
        var now = new Date();
        this.calendarYear = now.getFullYear();
        this.calendarMonth = now.getMonth();
        this.calendarDateField = cfg.calendarDateField || '';
        this.kanbanSummarizeField = cfg.kanbanSummarizeField || null;
        this.kanbanLaneField = null;
        this.kanbanLaneCounts = {};
        this.kanbanLaneRecords = {};
        this.kanbanLaneOrder = [];
        this.kanbanPerLane = 10;
        this.kanbanLoadingLane = '';
        this.colFilters = {};
        this.colFilterOpen = {};
        this.globalSearch = '';
        this.listSearchActive = false;
        this.listSearchTimer = null;
        this.listSearchTruncated = false;
        this.sortField = null;
        this.sortDir = 'none';
        this.describeLabel = '';
        this.describeQuery = '';
        this.describeErr = '';
        this.loading = false;
        this.pendingEdits = {};
    }

    TabState.prototype.describeUrl = function () {
        if (!this.listViewId) {
            return null;
        }
        return (
            apiRoot() +
            '/sobjects/' +
            encodeURIComponent(this.objectApi) +
            '/listviews/' +
            encodeURIComponent(this.listViewId) +
            '/describe'
        );
    };

    TabState.prototype.lightningListUrl = function () {
        if (!this.listViewId) {
            return '#';
        }
        return '/lightning/o/' + encodeURIComponent(this.lightningSegment) + '/list?filterName=' + encodeURIComponent(this.listViewId);
    };

    TabState.prototype.fetchDescribe = function () {
        var self = this;
        if (!self.listViewId) {
            self.describeLabel = '';
            self.describeQuery = '';
            self.describeErr = '';
            self.syncViewActions();
            return Promise.resolve();
        }
        return remotingDescribeListView(self.objectApi, self.listViewId)
            .then(function (d) {
                self.describeLabel = d.label || '';
                self.describeQuery = d.query || '';
                self.describeErr = '';
                self.syncViewActions();
            })
            .catch(function (e) {
                self.describeErr = e.message || String(e);
                self.syncViewActions();
            });
    };

    TabState.prototype.syncViewActions = function () {
        var prefix = this.actionsPrefix;
        if (!prefix) {
            return;
        }
        var soqlBtn = document.getElementById('hub-soql-' + prefix);
        var sfBtn = document.getElementById('hub-sf-' + prefix);
        if (soqlBtn) {
            soqlBtn.disabled = !this.describeQuery && !this.describeErr;
            soqlBtn.title = this.describeErr || (this.describeLabel ? this.describeLabel + ' — SOQL' : 'List view SOQL');
        }
        if (sfBtn) {
            var url = this.lightningListUrl();
            sfBtn.href = url;
            if (this.listViewId) {
                sfBtn.classList.remove('is-disabled');
            } else {
                sfBtn.classList.add('is-disabled');
            }
        }
    };

    TabState.prototype.getDescribeSnapshot = function () {
        return {
            label: this.describeLabel || '',
            query: this.describeQuery || '',
            error: this.describeErr || ''
        };
    };

    TabState.prototype.getWorkingRows = function () {
        var cols = visibleColumns(this.columns || []);
        var out = [];
        var globalQ = this.listSearchActive ? '' : this.globalSearch;
        for (var i = 0; i < this.allRows.length; i++) {
            if (rowMatchesFilters(this.allRows[i], cols, this.colFilters, globalQ)) {
                out.push(this.allRows[i]);
            }
        }
        if (this.sortField && this.sortDir !== 'none') {
            sortRowsByField(out, this.columns, this.sortField, this.sortDir);
        } else {
            sortRowsByOrig(out);
        }
        return out;
    };

    TabState.prototype.pendingEditStats = function () {
        var changes = 0;
        var records = 0;
        var map = this.pendingEdits || {};
        for (var rid in map) {
            if (!Object.prototype.hasOwnProperty.call(map, rid)) {
                continue;
            }
            var fields = map[rid];
            var n = 0;
            for (var f in fields) {
                if (Object.prototype.hasOwnProperty.call(fields, f)) {
                    n++;
                }
            }
            if (n > 0) {
                records++;
                changes += n;
            }
        }
        return { changes: changes, records: records };
    };

    TabState.prototype.getCellValue = function (row, fieldApi) {
        var rid = recordIdFromRow(row);
        if (rid && this.pendingEdits[rid] && this.pendingEdits[rid][fieldApi] !== undefined) {
            return this.pendingEdits[rid][fieldApi];
        }
        return valueForField(row, fieldApi);
    };

    TabState.prototype.isCellChanged = function (row, fieldApi) {
        var rid = recordIdFromRow(row);
        if (!rid || !this.pendingEdits[rid] || this.pendingEdits[rid][fieldApi] === undefined) {
            return false;
        }
        var orig = valueForField(row, fieldApi);
        var pending = this.pendingEdits[rid][fieldApi];
        return String(pending == null ? '' : pending).trim() !== String(orig == null ? '' : orig).trim();
    };

    TabState.prototype.buildPendingBarHtml = function () {
        var stats = this.pendingEditStats();
        if (!stats.changes) {
            return '';
        }
        return (
            '<div class="ch-pending-bar" role="status">' +
            '<span class="ch-pending-msg">' +
            esc(String(stats.changes)) +
            ' unsaved change' +
            (stats.changes === 1 ? '' : 's') +
            ' on ' +
            esc(String(stats.records)) +
            ' record' +
            (stats.records === 1 ? '' : 's') +
            '</span>' +
            '<span class="ch-pending-actions">' +
            '<button type="button" class="slds-button slds-button_neutral ch-pending-discard">Discard all</button>' +
            '<button type="button" class="slds-button slds-button_brand ch-pending-save">Save all</button>' +
            '</span></div>'
        );
    };

    TabState.prototype.discardAllPending = function () {
        this.pendingEdits = {};
        this.render();
    };

    TabState.prototype.saveAllPending = function () {
        var self = this;
        var promises = [];
        var map = self.pendingEdits || {};
        for (var rid in map) {
            if (!Object.prototype.hasOwnProperty.call(map, rid)) {
                continue;
            }
            var fields = map[rid];
            var keys = [];
            for (var k in fields) {
                if (Object.prototype.hasOwnProperty.call(fields, k)) {
                    keys.push(k);
                }
            }
            if (keys.length) {
                promises.push(remotingUpdateRecordFields(rid, fields));
            }
        }
        if (!promises.length) {
            return Promise.resolve();
        }
        var saveBtn = self.listEl.querySelector('.ch-pending-save');
        if (saveBtn) {
            saveBtn.disabled = true;
            saveBtn.textContent = 'Saving…';
        }
        return Promise.all(promises)
            .then(function (results) {
                for (var i = 0; i < results.length; i++) {
                    if (results[i] && results[i].error) {
                        throw new Error(results[i].error);
                    }
                }
                self.pendingEdits = {};
                return self.load();
            })
            .catch(function (e) {
                var msg = e && e.message ? e.message : String(e);
                if (typeof global.crmHubAlert === 'function') {
                    global.crmHubAlert(msg);
                } else {
                    alert(msg);
                }
            })
            .then(function () {
                if (saveBtn) {
                    saveBtn.disabled = false;
                    saveBtn.textContent = 'Save all';
                }
            });
    };

    TabState.prototype.getToolbarHost = function () {
        if (this.toolbarEl && this.toolbarEl.isConnected) {
            return this.toolbarEl;
        }
        if (!this.listEl) {
            return null;
        }
        var panel = this.listEl.closest ? this.listEl.closest('.hub-tab-panel') : null;
        if (!panel) {
            return null;
        }
        this.toolbarEl = panel.querySelector('.hub-toolbar-search');
        return this.toolbarEl;
    };

    TabState.prototype.buildToolbarHtml = function () {
        var self = this;
        return (
            '<div class="hub-list-search-bar">' +
            '<svg class="hub-list-search-ico" viewBox="0 0 24 24" aria-hidden="true">' +
            '<circle cx="11" cy="11" r="7" fill="none" stroke="currentColor" stroke-width="2"/>' +
            '<path d="M20 20l-3.5-3.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>' +
            '</svg>' +
            '<label class="slds-assistive-text" for="ch-glob-' +
            esc(self.objectApi) +
            '">Search this list</label>' +
            '<input id="ch-glob-' +
            esc(self.objectApi) +
            '" class="hub-list-search-input ch-global-search" type="search" placeholder="Search this list…" value="' +
            esc(self.globalSearch) +
            '" autocomplete="off" />' +
            '<div class="hub-list-search-actions">' +
            '<button type="button" class="hub-list-search-clear ch-clear-filters" aria-label="Clear filters" title="Clear">×</button>' +
            '<button type="button" class="hub-list-search-btn" aria-label="Search this list">Search</button>' +
            '</div></div>'
        );
    };

    TabState.prototype.syncToolbarChrome = function () {
        var host = this.getToolbarHost();
        if (!host) {
            return;
        }
        var active = document.activeElement;
        var keepFocus = active && host.contains(active) && active.classList && active.classList.contains('ch-global-search');
        var selStart = keepFocus ? active.selectionStart : null;
        var selEnd = keepFocus ? active.selectionEnd : null;
        host.innerHTML = this.buildToolbarHtml();
        this.attachToolbarHandlers(host);
        if (keepFocus) {
            var glob = host.querySelector('.ch-global-search');
            if (glob) {
                glob.focus();
                try {
                    if (selStart != null && selEnd != null) {
                        glob.setSelectionRange(selStart, selEnd);
                    }
                } catch (e) {
                    /* ignore */
                }
            }
        }
    };

    TabState.prototype.attachToolbarHandlers = function (root) {
        var self = this;
        root = root || this.getToolbarHost();
        if (!root) {
            return;
        }
        function runSearchNow() {
            var globEl = root.querySelector('.ch-global-search');
            var term = globEl ? (globEl.value || '').trim() : (self.globalSearch || '').trim();
            self.globalSearch = globEl ? globEl.value : self.globalSearch;
            if (self.listSearchTimer) {
                clearTimeout(self.listSearchTimer);
                self.listSearchTimer = null;
            }
            if (!term) {
                self.listSearchActive = false;
                self.listSearchTruncated = false;
                self.offset = 0;
                self.load();
                return;
            }
            if (self.mode === 'kanban') {
                self.renderListRowsOnly();
                return;
            }
            self.runListSearch(term);
        }
        var glob = root.querySelector('.ch-global-search');
        if (glob) {
            glob.oninput = function () {
                self.globalSearch = glob.value;
                if (self.listSearchTimer) {
                    clearTimeout(self.listSearchTimer);
                }
                var term = (glob.value || '').trim();
                if (!term) {
                    self.listSearchActive = false;
                    self.listSearchTruncated = false;
                    self.offset = 0;
                    self.load();
                    return;
                }
                if (self.mode === 'kanban') {
                    self.renderListRowsOnly();
                    return;
                }
                self.listSearchTimer = setTimeout(function () {
                    self.runListSearch(term);
                }, 400);
            };
            glob.onkeydown = function (ev) {
                if (ev.key === 'Enter') {
                    ev.preventDefault();
                    runSearchNow();
                }
            };
        }
        var go = root.querySelector('.hub-list-search-btn');
        if (go) {
            go.onclick = function () {
                runSearchNow();
            };
        }
        var clr = root.querySelector('.ch-clear-filters');
        if (clr) {
            clr.onclick = function () {
                self.colFilters = {};
                self.colFilterOpen = {};
                self.globalSearch = '';
                self.listSearchActive = false;
                self.listSearchTruncated = false;
                self.sortField = null;
                self.sortDir = 'none';
                self.offset = 0;
                self.load();
            };
        }
    };

    TabState.prototype.runListSearch = function (term) {
        var self = this;
        if (!term || !self.listViewId || self.mode === 'kanban') {
            return;
        }
        self.loading = true;
        self.listSearchActive = true;
        self.globalSearch = term;
        self.offset = 0;
        self.syncToolbarChrome();
        if (self.mode === 'list') {
            self.listEl.innerHTML = self.buildSkeletonHtml();
        } else if (self.mode === 'calendar' && self.calendarEl) {
            self.calendarEl.innerHTML = self.buildSkeletonHtml();
        }
        var describeJson = null;
        var describePromise = Promise.resolve();
        if (self.describeUrl()) {
            describePromise = apiGet(self.describeUrl())
                .then(function (d) {
                    describeJson = JSON.stringify(d);
                })
                .catch(function () {
                    describeJson = null;
                });
        }
        return describePromise
            .then(function () {
                return remotingListViewResults(
                    self.objectApi,
                    self.listViewId,
                    Math.max(self.pageSize || 25, 500),
                    0,
                    describeJson,
                    term
                );
            })
            .then(function (data) {
                self.columns = data.columns || self.columns;
                self.calendarDateField = calendarDateField(
                    self.objectApi,
                    self.columns,
                    self.calendarDateField
                );
                var recs = data.records || [];
                for (var i = 0; i < recs.length; i++) {
                    recs[i]._chOrig = i;
                }
                self.allRows = recs;
                self.nextRecordsUrl = null;
                self.listSearchTruncated = !!data.searchTruncated;
                self.loading = false;
                self.render();
                self.renderPager();
            })
            .catch(function (e) {
                self.loading = false;
                self.listSearchActive = false;
                if (self.mode === 'list') {
                    self.listEl.innerHTML =
                        '<div class="slds-text-color_error">' + esc(e.message || e) + '</div>';
                }
                self.renderPager();
            });
    };

    TabState.prototype.buildTableHtml = function (records) {
        var objectApi = this.objectApi;
        var cols = visibleColumns(this.columns || []);
        var linkField = primaryLinkField(this.columns);
        var showScore = objectApi === 'Job_Application__c' || objectApi === 'Opportunity';
        var extraCols = (showScore ? 1 : 0) + 1; /* score + open */
        var sb = [];
        sb.push(this.buildPendingBarHtml());
        sb.push('<div class="ch-grid-wrap ch-lv-scroll">');
        sb.push(
            '<table class="slds-table slds-table_cell-buffer slds-table_bordered slds-table_col-bordered ch-data-table" data-object-api="' +
                esc(objectApi) +
                '">'
        );
        sb.push('<thead><tr class="ch-head-row">');
        if (showScore) {
            var scoreDir = this.sortField === '_chScore' ? this.sortDir : 'none';
            var scoreAria = 'none';
            if (scoreDir === 'asc') {
                scoreAria = 'ascending';
            }
            if (scoreDir === 'desc') {
                scoreAria = 'descending';
            }
            sb.push(
                '<th scope="col" class="ch-th ch-score-col" data-field="_chScore" aria-sort="' +
                    scoreAria +
                    '">'
            );
            sb.push('<div class="ch-th-inner">');
            sb.push(
                '<button type="button" class="slds-button slds-button_neutral ch-sort-btn" data-field="_chScore" title="Sort by Hub score">' +
                    '<span class="ch-sort-label">Score</span>'
            );
            if (scoreDir === 'asc') {
                sb.push(' <span class="ch-sort-ico" aria-hidden="true">▲</span>');
            } else if (scoreDir === 'desc') {
                sb.push(' <span class="ch-sort-ico" aria-hidden="true">▼</span>');
            } else {
                sb.push(' <span class="ch-sort-ico ch-sort-muted" aria-hidden="true">⇅</span>');
            }
            sb.push('</button></div></th>');
        }
        for (var h = 0; h < cols.length; h++) {
            var c = cols[h];
            var colCls = columnCssClass(c);
            var dir = this.sortField === c.fieldNameOrPath ? this.sortDir : 'none';
            var aria = 'none';
            if (dir === 'asc') {
                aria = 'ascending';
            }
            if (dir === 'desc') {
                aria = 'descending';
            }
            sb.push(
                '<th scope="col" class="ch-th ' +
                    colCls +
                    '" data-field="' +
                    esc(c.fieldNameOrPath) +
                    '" aria-sort="' +
                    aria +
                    '">'
            );
            sb.push('<div class="ch-th-inner">');
            sb.push(
                '<button type="button" class="slds-button slds-button_neutral ch-sort-btn" data-field="' +
                    esc(c.fieldNameOrPath) +
                    '" title="Sort">' +
                    '<span class="ch-sort-label">' +
                    esc(c.label || c.fieldNameOrPath) +
                    '</span>'
            );
            if (dir === 'asc') {
                sb.push(' <span class="ch-sort-ico" aria-hidden="true">▲</span>');
            } else if (dir === 'desc') {
                sb.push(' <span class="ch-sort-ico" aria-hidden="true">▼</span>');
            } else {
                sb.push(' <span class="ch-sort-ico ch-sort-muted" aria-hidden="true">⇅</span>');
            }
            sb.push('</button>');
            sb.push(colFilterFunnelBtn(c.fieldNameOrPath, this));
            sb.push('</div>');
            sb.push(colFilterPanelHtml(c.fieldNameOrPath, this));
            sb.push('</th>');
        }
        sb.push(
            '<th scope="col" class="ch-th ch-open-col" title="Open record" aria-label="Open record">' +
                '<span class="slds-assistive-text">Open</span></th>'
        );
        sb.push('</tr></thead><tbody>');
        if (records.length === 0) {
            sb.push(
                '<tr><td colspan="' +
                    (cols.length + extraCols) +
                    '" class="slds-text-align_center slds-p-around_medium slds-text-color_weak">No matching rows. Clear filters or change list view.</td></tr>'
            );
        }
        for (var r = 0; r < records.length; r++) {
            var row = records[r];
            var rid = recordIdFromRow(row);
            var rowName = valueForField(row, linkField) || valueForField(row, 'Name');
            sb.push(
                '<tr data-record-id="' +
                    esc(rid) +
                    '" data-record-name="' +
                    esc(rowName) +
                    '" data-object-api="' +
                    esc(objectApi) +
                    '" class="ch-row">'
            );
            if (showScore) {
                sb.push(
                    '<td class="ch-td ch-score-cell">' +
                        (buildScoreBadgeHtml(row) || '<span class="ch-score-na">—</span>') +
                        '</td>'
                );
            }
            for (var j = 0; j < cols.length; j++) {
                var col = cols[j];
                var val = this.getCellValue(row, col.fieldNameOrPath);
                var cellMeta = cellForField(row, col.fieldNameOrPath);
                var inner = cellInnerHtml(col, val, cellMeta);
                var t = (col.type || '').toLowerCase();
                var isLinkCol = col.fieldNameOrPath === linkField || col.fieldNameOrPath === 'Name';
                if (isLinkCol && rid) {
                    inner =
                        '<button type="button" class="slds-button slds-button_link ch-open" data-id="' +
                        esc(rid) +
                        '">' +
                        inner +
                        '</button>';
                }
                var extraInfo = (col.extraTypeInfo || '').toLowerCase();
                var isPlainTextarea =
                    t === 'textarea' &&
                    extraInfo !== 'richtextarea' &&
                    extraInfo !== 'html' &&
                    !fieldApiLooksHtml(col.fieldNameOrPath, col.label);
                var simple =
                    t === 'string' ||
                    t === 'phone' ||
                    t === 'email' ||
                    t === 'url' ||
                    t === 'double' ||
                    t === 'currency' ||
                    t === 'percent' ||
                    t === 'int' ||
                    t === 'boolean' ||
                    t === 'picklist' ||
                    isPlainTextarea;
                var editable =
                    !isLinkCol &&
                    simple &&
                    col.calculated !== true &&
                    col.updateable !== false &&
                    col.fieldNameOrPath !== 'Id' &&
                    col.fieldNameOrPath.indexOf('.') < 0 &&
                    inner.indexOf('<a ') < 0 &&
                    inner.indexOf('<img') < 0 &&
                    inner.indexOf('ch-cell-html') < 0;
                if (editable) {
                    inner =
                        '<span class="ch-cell-wrap"><span class="ch-ed" tabindex="0" role="button" title="Click or press Enter to edit">' +
                        inner +
                        '</span><button type="button" class="slds-button slds-button_icon slds-button_icon-border-filled ch-edit-ico" title="Edit" aria-label="Edit"><span class="slds-assistive-text">Edit</span>✎</button></span>';
                } else {
                    inner = wrapCellContent(inner, false);
                }
                var tdCls = columnCssClass(col);
                if (fieldTypeIsHtml(col) || isRenderableHtml(val)) {
                    tdCls += ' ch-col-html';
                }
                if (cellHasIcon(inner)) {
                    tdCls += ' ch-col-icon';
                }
                if (this.isCellChanged(row, col.fieldNameOrPath)) {
                    tdCls += ' ch-cell-changed';
                }
                sb.push('<td class="ch-td ' + tdCls + '">' + inner + '</td>');
            }
            sb.push('<td class="ch-td ch-open-cell">' + (openRecordIconBtn(rid) || openRecordIconBtnPlaceholder()) + '</td>');
            sb.push('</tr>');
        }
        sb.push('</tbody></table></div>');
        return sb.join('');
    };

    TabState.prototype.buildSkeletonHtml = function () {
        return (
            '<div class="ch-skeleton slds-p-around_medium" aria-busy="true">' +
            '<div class="slds-text-body_small slds-m-bottom_small">Loading list…</div>' +
            '<div class="ch-sk-line"></div><div class="ch-sk-line ch-sk-short"></div><div class="ch-sk-line"></div>' +
            '</div>'
        );
    };

    TabState.prototype.load = function () {
        var self = this;
        if (!self.listViewId) {
            self.listEl.innerHTML = '<div class="slds-text-color_error">Select a list view.</div>';
            self.cardsEl.innerHTML = '';
            if (self.kanbanEl) {
                self.kanbanEl.innerHTML = '';
            }
            if (self.calendarEl) {
                self.calendarEl.innerHTML = '';
            }
            self.allRows = [];
            self.kanbanLaneRecords = {};
            self.kanbanLaneCounts = {};
            self.kanbanLaneOrder = [];
            self.syncViewActions();
            self.syncToolbarChrome();
            return Promise.resolve();
        }
        if (self.mode === 'kanban') {
            return self.loadKanban();
        }
        self.listSearchActive = false;
        self.listSearchTruncated = false;
        self.loading = true;
        self.syncToolbarChrome();
        if (self.mode === 'list') {
            self.listEl.innerHTML = self.buildSkeletonHtml();
        } else if (self.mode === 'calendar' && self.calendarEl) {
            self.calendarEl.innerHTML = self.buildSkeletonHtml();
        }
        var describeJson = null;
        var describePromise = Promise.resolve();
        if (self.listViewId && self.describeUrl()) {
            describePromise = apiGet(self.describeUrl())
                .then(function (d) {
                    describeJson = JSON.stringify(d);
                })
                .catch(function () {
                    describeJson = null;
                });
        }
        var p1 = describePromise.then(function () {
            return remotingListViewResults(
                self.objectApi,
                self.listViewId,
                self.pageSize,
                self.offset,
                describeJson,
                null
            );
        }).then(function (data) {
            self.columns = data.columns || [];
            self.calendarDateField = calendarDateField(self.objectApi, self.columns, self.calendarDateField);
            var recs = data.records || [];
            for (var i = 0; i < recs.length; i++) {
                recs[i]._chOrig = i;
            }
            self.allRows = recs;
            self.nextRecordsUrl = data.nextRecordsUrl || null;
            self.loading = false;
            self.render();
            self.renderPager();
        });
        var p2 = self.fetchDescribe();
        return Promise.all([p1, p2]).then(function () {}).catch(function (e) {
            self.loading = false;
            self.listEl.innerHTML = '<div class="slds-text-color_error">' + esc(e.message || e) + '</div>';
        });
    };

    TabState.prototype.flattenKanbanRows = function () {
        var out = [];
        var order = this.kanbanLaneOrder || [];
        var idx = 0;
        for (var i = 0; i < order.length; i++) {
            var bucket = this.kanbanLaneRecords[order[i]] || [];
            for (var j = 0; j < bucket.length; j++) {
                bucket[j]._chOrig = idx++;
                out.push(bucket[j]);
            }
        }
        return out;
    };

    TabState.prototype.getKanbanState = function () {
        return {
            laneField: this.kanbanLaneField,
            laneCounts: this.kanbanLaneCounts || {},
            laneRecords: this.kanbanLaneRecords || {},
            laneOrder: this.kanbanLaneOrder || [],
            loadingLane: this.kanbanLoadingLane || ''
        };
    };

    TabState.prototype.buildKanbanLanesFromRows = function (rows, laneField) {
        var lanes = {};
        var counts = {};
        var order = [];
        var seen = {};
        var list = rows || [];
        for (var i = 0; i < list.length; i++) {
            var lane = valueForField(list[i], laneField);
            var key = lane == null || lane === '' ? '—' : String(lane);
            if (!lanes[key]) {
                lanes[key] = [];
                counts[key] = 0;
            }
            counts[key]++;
            if (lanes[key].length < (this.kanbanPerLane || 10)) {
                lanes[key].push(list[i]);
            }
            if (!seen[key]) {
                order.push(key);
                seen[key] = true;
            }
        }
        var resolved = resolveKanbanLaneOrder(laneField, this.columns || [], lanes);
        return {
            laneRecords: lanes,
            laneCounts: counts,
            laneOrder: resolved && resolved.length ? resolved : order
        };
    };

    TabState.prototype.loadKanbanFallback = function (describeJson) {
        var self = this;
        return remotingListViewResults(
            self.objectApi,
            self.listViewId,
            Math.max(self.pageSize || 25, 100),
            0,
            describeJson || null,
            null
        ).then(function (data) {
            self.columns = data.columns || [];
            self.kanbanLaneField =
                self.kanbanLaneField ||
                readPersistedKanbanLaneField(self.objectApi) ||
                kanbanLaneField(self.objectApi, self.columns);
            var built = self.buildKanbanLanesFromRows(data.records || [], self.kanbanLaneField);
            self.kanbanLaneCounts = built.laneCounts;
            self.kanbanLaneRecords = built.laneRecords;
            self.kanbanLaneOrder = built.laneOrder;
            self.kanbanLoadingLane = '';
            self.allRows = self.flattenKanbanRows();
            self.nextRecordsUrl = null;
            self.offset = 0;
            self.loading = false;
            self.render();
            self.renderPager();
        });
    };

    TabState.prototype.loadKanban = function () {
        var self = this;
        if (!self.listViewId) {
            return self.load();
        }
        self.loading = true;
        self.syncToolbarChrome();
        if (self.kanbanEl) {
            self.kanbanEl.innerHTML = self.buildSkeletonHtml();
            self.hideAllViews();
            self.kanbanEl.style.display = 'flex';
        }
        var describeJson = null;
        var describePromise = Promise.resolve();
        if (self.listViewId && self.describeUrl()) {
            describePromise = apiGet(self.describeUrl())
                .then(function (d) {
                    describeJson = JSON.stringify(d);
                })
                .catch(function () {
                    describeJson = null;
                });
        }
        var preferredLane =
            self.kanbanLaneField ||
            readPersistedKanbanLaneField(self.objectApi) ||
            kanbanLaneField(self.objectApi, self.columns || []);
        var p1 = describePromise
            .then(function () {
                return remotingKanbanBoard(
                    self.objectApi,
                    self.listViewId,
                    preferredLane || null,
                    self.kanbanPerLane,
                    describeJson
                );
            })
            .then(function (data) {
                self.columns = data.columns || [];
                self.kanbanLaneField =
                    data.laneField ||
                    preferredLane ||
                    kanbanLaneField(self.objectApi, self.columns);
                if (self.kanbanLaneField) {
                    persistKanbanLaneField(self.objectApi, self.kanbanLaneField);
                }
                self.kanbanLaneCounts = data.laneCounts || {};
                self.kanbanLaneRecords = data.laneRecords || {};
                self.kanbanLaneOrder = data.laneOrder || Object.keys(self.kanbanLaneRecords);
                self.kanbanPerLane = data.perLaneLimit || self.kanbanPerLane || 10;
                self.kanbanLoadingLane = '';
                self.allRows = self.flattenKanbanRows();
                self.nextRecordsUrl = null;
                self.offset = 0;
                self.loading = false;
                self.render();
                self.renderPager();
            })
            .catch(function () {
                return self.loadKanbanFallback(describeJson);
            });
        var p2 = self.fetchDescribe();
        return Promise.all([p1, p2])
            .then(function () {})
            .catch(function (e) {
                self.loading = false;
                if (self.kanbanEl) {
                    self.kanbanEl.innerHTML =
                        '<div class="slds-text-color_error">' + esc(e.message || e) + '</div>';
                }
            });
    };

    TabState.prototype.loadKanbanLaneMore = function (laneKey) {
        var self = this;
        if (!self.listViewId || !self.kanbanLaneField || self.kanbanLoadingLane) {
            return Promise.resolve();
        }
        var bucket = self.kanbanLaneRecords[laneKey] || [];
        var total =
            self.kanbanLaneCounts[laneKey] != null
                ? Number(self.kanbanLaneCounts[laneKey])
                : bucket.length;
        if (bucket.length >= total) {
            return Promise.resolve();
        }
        self.kanbanLoadingLane = laneKey;
        self.render();
        var describeJson = null;
        var describePromise = Promise.resolve();
        if (self.describeUrl()) {
            describePromise = apiGet(self.describeUrl())
                .then(function (d) {
                    describeJson = JSON.stringify(d);
                })
                .catch(function () {
                    describeJson = null;
                });
        }
        return describePromise
            .then(function () {
                return remotingKanbanLaneMore(
                    self.objectApi,
                    self.listViewId,
                    self.kanbanLaneField,
                    laneKey,
                    self.kanbanPerLane,
                    bucket.length,
                    describeJson
                );
            })
            .then(function (data) {
                var more = data.records || [];
                if (!self.kanbanLaneRecords[laneKey]) {
                    self.kanbanLaneRecords[laneKey] = [];
                }
                for (var i = 0; i < more.length; i++) {
                    self.kanbanLaneRecords[laneKey].push(more[i]);
                }
                self.allRows = self.flattenKanbanRows();
                self.kanbanLoadingLane = '';
                self.render();
            })
            .catch(function (e) {
                self.kanbanLoadingLane = '';
                self.render();
                /* Soft-fail: keep existing cards; do not blank the board */
                if (window.console && console.warn) {
                    console.warn('Kanban load more failed', e);
                }
            });
    };

    TabState.prototype.hideAllViews = function () {
        this.listEl.style.display = 'none';
        this.cardsEl.style.display = 'none';
        if (this.kanbanEl) {
            this.kanbanEl.style.display = 'none';
        }
        if (this.calendarEl) {
            this.calendarEl.style.display = 'none';
        }
    };

    TabState.prototype.renderListRowsOnly = function () {
        if (this.mode !== 'list') {
            this.render();
            return;
        }
        var wrap = this.listEl.querySelector('.ch-grid-wrap');
        if (!wrap) {
            this.render();
            return;
        }
        var temp = document.createElement('div');
        temp.innerHTML = this.buildTableHtml(this.getWorkingRows());
        var newTbody = temp.querySelector('table.ch-data-table tbody');
        var oldTbody = wrap.querySelector('table.ch-data-table tbody');
        if (newTbody && oldTbody) {
            oldTbody.replaceWith(newTbody);
            return;
        }
        this.render();
    };

    TabState.prototype.render = function () {
        var work = this.getWorkingRows();
        this.syncToolbarChrome();
        if (this.mode === 'list') {
            this.listEl.innerHTML = this.buildTableHtml(work);
                this.hideAllViews();
                this.listEl.style.display = 'flex';
                this.attachListChromeHandlers();
        } else if (this.mode === 'kanban') {
            if (this.kanbanEl) {
                this.kanbanSummarizeField = kanbanSummarizeField(
                    this.objectApi,
                    this.columns,
                    this.kanbanSummarizeField
                );
                this.kanbanEl.innerHTML = buildKanbanHtml(
                    this.objectApi,
                    this.columns,
                    this.kanbanSummarizeField,
                    this.getKanbanState()
                );
                this.hideAllViews();
                this.kanbanEl.style.display = 'flex';
            }
            this.attachKanbanHandlers();
        } else if (this.mode === 'calendar') {
            if (this.calendarEl) {
                this.calendarDateField = calendarDateField(this.objectApi, this.columns, this.calendarDateField);
                this.calendarEl.innerHTML = buildCalendarHtml(
                    this.objectApi,
                    this.columns,
                    work,
                    this.calendarDateField,
                    this.calendarYear,
                    this.calendarMonth
                );
                this.hideAllViews();
                this.calendarEl.style.display = 'flex';
                applyCalendarLayoutMode(this.calendarEl);
            }
            this.attachCalendarHandlers();
            ensureCalendarLayoutResize();
        } else {
            this.cardsEl.innerHTML = buildCardsHtml(this.objectApi, this.columns, work);
            this.hideAllViews();
            this.cardsEl.style.display = 'flex';
            this.attachCardHandlers();
        }
    };

    TabState.prototype.cycleSort = function (field) {
        if (this.sortField !== field) {
            this.sortField = field;
            this.sortDir = 'asc';
        } else if (this.sortDir === 'asc') {
            this.sortDir = 'desc';
        } else if (this.sortDir === 'desc') {
            this.sortDir = 'none';
            this.sortField = null;
        } else {
            this.sortDir = 'asc';
        }
        this.render();
    };

    TabState.prototype.syncColFilterChrome = function (table, fieldApi) {
        if (!table || !fieldApi) {
            return;
        }
        var th = table.querySelector('th.ch-th[data-field="' + fieldApi + '"]');
        if (!th) {
            return;
        }
        var wrap = th.querySelector('.ch-col-filter-wrap');
        var btn = th.querySelector('.ch-col-filter-btn');
        var inp = th.querySelector('.ch-col-filter');
        var open = colFilterPanelOpen(this, fieldApi);
        var active = colFilterBtnActive(this, fieldApi);
        if (wrap) {
            if (open) {
                wrap.classList.add('is-open');
            } else {
                wrap.classList.remove('is-open');
            }
        }
        if (btn) {
            if (active) {
                btn.classList.add('is-active');
            } else {
                btn.classList.remove('is-active');
            }
            btn.setAttribute('aria-expanded', open ? 'true' : 'false');
        }
        if (inp && document.activeElement !== inp) {
            inp.value = this.colFilters[fieldApi] || '';
        }
    };

    TabState.prototype.attachListChromeHandlers = function () {
        var self = this;
        var root = self.listEl;

        var pendingSave = root.querySelector('.ch-pending-save');
        if (pendingSave) {
            pendingSave.onclick = function () {
                self.saveAllPending();
            };
        }
        var pendingDiscard = root.querySelector('.ch-pending-discard');
        if (pendingDiscard) {
            pendingDiscard.onclick = function () {
                self.discardAllPending();
            };
        }
        var table = root.querySelector('table.ch-data-table');
        if (!table) {
            return;
        }
        var filters = root.querySelectorAll('.ch-col-filter');
        for (var fi = 0; fi < filters.length; fi++) {
            (function (inp) {
                inp.oninput = function () {
                    var f = inp.getAttribute('data-field');
                    if (!self.colFilterOpen) {
                        self.colFilterOpen = {};
                    }
                    self.colFilterOpen[f] = true;
                    self.colFilters[f] = inp.value;
                    self.renderListRowsOnly();
                    self.syncColFilterChrome(table, f);
                };
            })(filters[fi]);
        }
        var filterBtns = root.querySelectorAll('.ch-col-filter-btn');
        for (var fb = 0; fb < filterBtns.length; fb++) {
            (function (btn) {
                btn.onclick = function (ev) {
                    ev.stopPropagation();
                    var f = btn.getAttribute('data-field');
                    if (!f) {
                        return;
                    }
                    if (!self.colFilterOpen) {
                        self.colFilterOpen = {};
                    }
                    self.colFilterOpen[f] = !self.colFilterOpen[f];
                    if (!self.colFilterOpen[f]) {
                        delete self.colFilterOpen[f];
                    }
                    self.syncColFilterChrome(table, f);
                    if (self.colFilterOpen[f]) {
                        var wrap = table.querySelector('.ch-col-filter-wrap[data-field="' + f + '"]');
                        var inpEl = wrap ? wrap.querySelector('.ch-col-filter') : null;
                        if (inpEl) {
                            inpEl.focus();
                        }
                    }
                };
            })(filterBtns[fb]);
        }
        var clearBtns = root.querySelectorAll('.ch-col-filter-clear');
        for (var cb = 0; cb < clearBtns.length; cb++) {
            (function (btn) {
                btn.onclick = function (ev) {
                    ev.stopPropagation();
                    var f = btn.getAttribute('data-field');
                    if (!f) {
                        return;
                    }
                    delete self.colFilters[f];
                    if (self.colFilterOpen) {
                        delete self.colFilterOpen[f];
                    }
                    self.renderListRowsOnly();
                    self.syncColFilterChrome(table, f);
                };
            })(clearBtns[cb]);
        }

        table.onclick = function (ev) {
            var sortB = ev.target.closest('.ch-sort-btn');
            if (sortB) {
                self.cycleSort(sortB.getAttribute('data-field'));
                return;
            }
            var ico = ev.target.closest('.ch-edit-ico');
            if (ico) {
                var wrap = ico.closest('.ch-cell-wrap');
                if (wrap) {
                    var sp = wrap.querySelector('.ch-ed');
                    if (sp) {
                        self.startEditCell(table, sp);
                    }
                }
                return;
            }
            var ed = ev.target.closest('.ch-ed');
            if (ed) {
                self.startEditCell(table, ed);
            }
        };
        table.onkeydown = function (ev) {
            if (ev.key === 'Enter' && ev.target.classList && ev.target.classList.contains('ch-ed')) {
                self.startEditCell(table, ev.target);
            }
        };
    };

    TabState.prototype.startEditCell = function (table, span) {
        var self = this;
        var tr = span.closest('tr');
        if (!tr) {
            return;
        }
        var oid = tr.getAttribute('data-record-id');
        var td = span.closest('td');
        var colIdx = Array.prototype.indexOf.call(tr.children, td);
        var ths = table.querySelectorAll('thead th');
        var fieldApi = ths[colIdx] ? ths[colIdx].getAttribute('data-field') : null;
        if (!oid || !fieldApi) {
            return;
        }
        var colMeta = null;
        var cols = (self.describe && self.describe.columns) || self.columns || [];
        for (var ci = 0; ci < cols.length; ci++) {
            if (cols[ci] && cols[ci].fieldNameOrPath === fieldApi) {
                colMeta = cols[ci];
                break;
            }
        }
        if (colMeta && (colMeta.calculated === true || colMeta.updateable === false)) {
            return;
        }
        /* Prefer full value from row data — display span is CSS-truncated */
        var currentText = span.textContent || '';
        var rows = self.allRows || [];
        for (var ri = 0; ri < rows.length; ri++) {
            if (recordIdFromRow(rows[ri]) === oid) {
                currentText = cellDisplayText(
                    colMeta || { type: 'string' },
                    self.getCellValue(rows[ri], fieldApi)
                );
                break;
            }
        }
        var multiline = shouldUseMultilineInlineEditor(colMeta, currentText);
        var editor;
        if (multiline) {
            editor = document.createElement('textarea');
            editor.className = 'slds-textarea ch-inline-editor ch-inline-editor--multiline';
            editor.rows = 3;
            editor.setAttribute('aria-label', 'Edit field');
        } else {
            editor = document.createElement('input');
            editor.type = 'text';
            editor.className = 'slds-input ch-inline-editor';
            editor.setAttribute('aria-label', 'Edit field');
        }
        editor.value = currentText;
        td.setAttribute('data-saving', '1');
        td.classList.add('ch-td-editing');
        td.innerHTML = '';
        td.appendChild(editor);

        function sizeEditor() {
            if (editor.tagName === 'TEXTAREA') {
                editor.style.height = 'auto';
                var maxPx = Math.max(160, Math.floor(window.innerHeight * 0.55));
                editor.style.height =
                    Math.min(Math.max(editor.scrollHeight + 2, 72), maxPx) + 'px';
                return;
            }
            /* Grow single-line input so the full value stays visible while focused */
            var len = String(editor.value || '').length;
            var ch = Math.min(Math.max(len + 2, 16), 72);
            editor.style.width = ch + 'ch';
            editor.style.minWidth = '12rem';
        }
        sizeEditor();
        editor.addEventListener('input', sizeEditor);

        editor.focus();
        if (editor.tagName === 'INPUT') {
            editor.select();
        } else {
            try {
                var L = editor.value.length;
                editor.setSelectionRange(L, L);
            } catch (ignoreSel) {
                /* ignore */
            }
        }
        try {
            editor.scrollIntoView({ block: 'nearest', inline: 'nearest' });
        } catch (ignoreScroll) {
            /* ignore */
        }

        function finish(save) {
            var v = editor.value;
            td.removeAttribute('data-saving');
            td.classList.remove('ch-td-editing');
            if (save) {
                if (!self.pendingEdits[oid]) {
                    self.pendingEdits[oid] = {};
                }
                self.pendingEdits[oid][fieldApi] = v;
                self.render();
            } else {
                self.render();
            }
        }
        editor.onblur = function () {
            if (td.getAttribute('data-saving') === '1') {
                finish(true);
            }
        };
        editor.onkeydown = function (e) {
            if (e.key === 'Escape') {
                e.preventDefault();
                finish(false);
                return;
            }
            if (e.key === 'Enter') {
                if (multiline) {
                    /* Enter = newline; Ctrl/Cmd+Enter commits */
                    if (e.metaKey || e.ctrlKey) {
                        e.preventDefault();
                        finish(true);
                    }
                    return;
                }
                e.preventDefault();
                finish(true);
            }
        };
    };

    TabState.prototype.attachKanbanHandlers = function () {
        var self = this;
        var root = self.kanbanEl;
        if (!root) {
            return;
        }
        var sel = root.querySelector('.ch-kan-summarize-field');
        if (sel) {
            sel.onchange = function () {
                self.kanbanSummarizeField = sel.value;
                persistKanbanSummarizeField(self.objectApi, sel.value);
                self.render();
            };
        }
        var laneSel = root.querySelector('.ch-kan-lane-field');
        if (laneSel) {
            laneSel.onchange = function () {
                var next = laneSel.value;
                if (!next || next === self.kanbanLaneField) {
                    return;
                }
                self.kanbanLaneField = next;
                persistKanbanLaneField(self.objectApi, next);
                self.loadKanban();
            };
        }
        var moreBtns = root.querySelectorAll('.ch-kan-more');
        for (var i = 0; i < moreBtns.length; i++) {
            (function (btn) {
                btn.onclick = function () {
                    var lane = btn.getAttribute('data-lane');
                    if (lane != null) {
                        self.loadKanbanLaneMore(lane);
                    }
                };
            })(moreBtns[i]);
        }
    };

    TabState.prototype.attachCardHandlers = function () {
        // Record open clicks handled by CrmHubRecordModal global delegation.
    };

    TabState.prototype.attachCalendarHandlers = function () {
        var self = this;
        var root = self.calendarEl;
        if (!root) {
            return;
        }
        var prev = root.querySelector('.ch-cal-prev');
        if (prev) {
            prev.onclick = function () {
                self.calendarMonth -= 1;
                if (self.calendarMonth < 0) {
                    self.calendarMonth = 11;
                    self.calendarYear -= 1;
                }
                self.render();
            };
        }
        var next = root.querySelector('.ch-cal-next');
        if (next) {
            next.onclick = function () {
                self.calendarMonth += 1;
                if (self.calendarMonth > 11) {
                    self.calendarMonth = 0;
                    self.calendarYear += 1;
                }
                self.render();
            };
        }
        var todayBtn = root.querySelector('.ch-cal-today');
        if (todayBtn) {
            todayBtn.onclick = function () {
                var t = new Date();
                self.calendarYear = t.getFullYear();
                self.calendarMonth = t.getMonth();
                self.render();
            };
        }
        var sel = root.querySelector('.ch-cal-date-field');
        if (sel) {
            sel.onchange = function () {
                self.calendarDateField = sel.value;
                persistCalendarDateField(self.objectApi, sel.value);
                self.render();
            };
        }
    };

    TabState.prototype.renderPager = function () {
        if (!this.pagerEl) {
            return;
        }
        var self = this;
        var PAGE_SIZES = [10, 25, 50, 100, 200];
        if (self.mode === 'kanban') {
            var total = 0;
            var counts = self.kanbanLaneCounts || {};
            for (var k in counts) {
                if (Object.prototype.hasOwnProperty.call(counts, k)) {
                    total += Number(counts[k]) || 0;
                }
            }
            var loaded = self.allRows ? self.allRows.length : 0;
            self.pagerEl.innerHTML =
                '<div class="ch-pager">' +
                '<div class="ch-pager-meta">' +
                esc(loaded) +
                ' cards loaded · ' +
                esc(total) +
                ' total in list view' +
                '</div></div>';
            return;
        }
        var hasPrev = !self.listSearchActive && self.offset > 0;
        var hasNext =
            !self.listSearchActive && (!!self.nextRecordsUrl || self.allRows.length === self.pageSize);
        var summary = '';
        if (self.listSearchActive) {
            summary =
                esc(self.allRows.length) +
                ' match' +
                (self.allRows.length === 1 ? '' : 'es') +
                ' in list view';
            if (self.listSearchTruncated) {
                summary += ' (showing first 2,000)';
            }
        } else {
            summary =
                esc(self.allRows.length) +
                ' loaded · offset ' +
                esc(self.offset);
        }
        var sizeOpts = '';
        for (var si = 0; si < PAGE_SIZES.length; si++) {
            var sz = PAGE_SIZES[si];
            sizeOpts +=
                '<option value="' +
                esc(String(sz)) +
                '"' +
                (Number(self.pageSize) === sz ? ' selected' : '') +
                '>' +
                esc(String(sz)) +
                '</option>';
        }
        self.pagerEl.innerHTML =
            '<div class="ch-pager">' +
            '<div class="ch-pager-left">' +
            '<span class="ch-pager-meta">' +
            summary +
            '</span>' +
            (self.listSearchActive
                ? ''
                : '<label class="ch-page-size">' +
                  '<span class="ch-page-size-lbl">Per page</span>' +
                  '<select class="ch-page-size-select" aria-label="Records per page">' +
                  sizeOpts +
                  '</select></label>') +
            '</div>' +
            '<div class="ch-pager-nav">' +
            '<button type="button" class="slds-button slds-button_neutral ch-prev"' +
            (hasPrev ? '' : ' disabled') +
            '>Previous</button>' +
            '<button type="button" class="slds-button slds-button_neutral ch-next"' +
            (hasNext ? '' : ' disabled') +
            '>Next</button>' +
            '</div></div>';
        var prevBtn = self.pagerEl.querySelector('.ch-prev');
        var nextBtn = self.pagerEl.querySelector('.ch-next');
        var sizeSel = self.pagerEl.querySelector('.ch-page-size-select');
        if (prevBtn) {
            prevBtn.onclick = function () {
                if (self.offset >= self.pageSize) {
                    self.offset -= self.pageSize;
                    self.nextRecordsUrl = null;
                    self.load();
                }
            };
        }
        if (nextBtn) {
            nextBtn.onclick = function () {
                if (self.allRows.length === self.pageSize) {
                    self.offset += self.pageSize;
                    self.nextRecordsUrl = null;
                    self.load();
                }
            };
        }
        if (sizeSel) {
            sizeSel.onchange = function () {
                var next = parseInt(sizeSel.value, 10);
                if (!next || next === self.pageSize) {
                    return;
                }
                if (PAGE_SIZES.indexOf(next) < 0) {
                    return;
                }
                self.pageSize = next;
                persistPageSize(self.objectApi, next);
                self.offset = 0;
                self.nextRecordsUrl = null;
                self.load();
            };
        }
    };

    var tabs = {};
    var storageUserId = '';
    var listViewPrefs = {};

    function storagePrefsKey() {
        if (storageUserId) {
            return 'crmhub_lvpref_' + storageUserId;
        }
        return 'crmhub_lvpref';
    }

    function normalizePref(raw) {
        var pinnedId = '';
        var favoriteIds = [];
        if (raw && typeof raw === 'object') {
            pinnedId = raw.pinnedId ? String(raw.pinnedId) : '';
            if (raw.favoriteIds && raw.favoriteIds.length) {
                for (var i = 0; i < raw.favoriteIds.length; i++) {
                    if (raw.favoriteIds[i]) {
                        favoriteIds.push(String(raw.favoriteIds[i]));
                    }
                }
            }
        }
        return { pinnedId: pinnedId, favoriteIds: favoriteIds };
    }

    function persistPrefsCache() {
        try {
            sessionStorage.setItem(storagePrefsKey(), JSON.stringify(listViewPrefs));
        } catch (e) {}
    }

    function readPrefsCache() {
        try {
            var raw = sessionStorage.getItem(storagePrefsKey());
            if (!raw) {
                return {};
            }
            var parsed = JSON.parse(raw);
            return parsed && typeof parsed === 'object' ? parsed : {};
        } catch (e) {
            return {};
        }
    }

    function seedListViewPrefs(serverPrefs) {
        var cached = readPrefsCache();
        var src = serverPrefs && typeof serverPrefs === 'object' ? serverPrefs : {};
        var serverKeys = [];
        for (var sk in src) {
            if (Object.prototype.hasOwnProperty.call(src, sk)) {
                serverKeys.push(sk);
            }
        }
        var merged = {};
        if (serverKeys.length) {
            for (var i = 0; i < serverKeys.length; i++) {
                merged[serverKeys[i]] = normalizePref(src[serverKeys[i]]);
            }
        } else {
            for (var ck in cached) {
                if (Object.prototype.hasOwnProperty.call(cached, ck)) {
                    merged[ck] = normalizePref(cached[ck]);
                }
            }
        }
        listViewPrefs = merged;
        persistPrefsCache();
        return listViewPrefs;
    }

    function hydrateListViewPrefsFromCache() {
        var cached = readPrefsCache();
        var merged = {};
        var has = false;
        for (var k in cached) {
            if (Object.prototype.hasOwnProperty.call(cached, k)) {
                merged[k] = normalizePref(cached[k]);
                has = true;
            }
        }
        if (has) {
            listViewPrefs = merged;
        }
        return listViewPrefs;
    }

    function getListViewPref(objectApi) {
        if (!objectApi) {
            return { pinnedId: '', favoriteIds: [] };
        }
        if (listViewPrefs[objectApi]) {
            return normalizePref(listViewPrefs[objectApi]);
        }
        return { pinnedId: '', favoriteIds: [] };
    }

    function setListViewPref(objectApi, pref) {
        if (!objectApi) {
            return;
        }
        listViewPrefs[objectApi] = normalizePref(pref);
        persistPrefsCache();
    }

    function mount(name, cfg) {
        ensureScorePopoverDelegation();
        tabs[name] = new TabState(cfg);
        return tabs[name];
    }

    function syncListView(name, listViewId) {
        var t = tabs[name];
        if (!t) {
            return;
        }
        t.listViewId = listViewId;
        t.offset = 0;
        t.nextRecordsUrl = null;
        t.colFilters = {};
        t.colFilterOpen = {};
        t.globalSearch = '';
        t.listSearchActive = false;
        t.listSearchTruncated = false;
        t.sortField = null;
        t.sortDir = 'none';
        if (listViewId) {
            persistListView(name, listViewId);
        }
        return t.load();
    }

    function syncMode(name, mode) {
        var t = tabs[name];
        if (!t) {
            return;
        }
        var prev = t.mode;
        if (mode === 'cards') {
            t.mode = 'cards';
        } else if (mode === 'kanban') {
            t.mode = 'kanban';
        } else if (mode === 'calendar') {
            t.mode = 'calendar';
        } else {
            t.mode = 'list';
        }
        if (t.mode === 'kanban') {
            t.offset = 0;
            return t.loadKanban();
        }
        if (prev === 'kanban') {
            t.offset = 0;
            return t.load();
        }
        t.render();
        t.renderPager();
    }

    function activate(name) {
        var t = tabs[name];
        if (!t) {
            return;
        }
        if (!t.columns || t.columns.length === 0) {
            return t.load();
        }
        t.render();
        t.renderPager();
    }

    function storageModeKey(objectApi) {
        return 'crmhub_mode_' + objectApi;
    }

    function storageListViewKey(objectApi) {
        if (storageUserId) {
            return 'crmhub_lv_' + storageUserId + '_' + objectApi;
        }
        return 'crmhub_lv_' + objectApi;
    }

    function persistListView(objectApi, listViewId) {
        if (!listViewId) {
            return;
        }
        try {
            sessionStorage.setItem(storageListViewKey(objectApi), listViewId);
        } catch (e) {}
    }

    function readPersistedListView(objectApi) {
        try {
            return sessionStorage.getItem(storageListViewKey(objectApi));
        } catch (e) {
            return null;
        }
    }

    function persistMode(objectApi, mode) {
        try {
            sessionStorage.setItem(storageModeKey(objectApi), mode);
        } catch (e) {}
    }

    function storagePageSizeKey(objectApi) {
        if (storageUserId) {
            return 'crmhub_ps_' + storageUserId + '_' + objectApi;
        }
        return 'crmhub_ps_' + objectApi;
    }

    function persistPageSize(objectApi, pageSize) {
        if (!objectApi || !pageSize) {
            return;
        }
        try {
            sessionStorage.setItem(storagePageSizeKey(objectApi), String(pageSize));
        } catch (e) {}
    }

    function readPersistedPageSize(objectApi) {
        try {
            var raw = sessionStorage.getItem(storagePageSizeKey(objectApi));
            var n = parseInt(raw, 10);
            if (n === 10 || n === 25 || n === 50 || n === 100 || n === 200) {
                return n;
            }
            return null;
        } catch (e) {
            return null;
        }
    }

    function applyCalendarLayoutMode(root) {
        if (!root) {
            return;
        }
        var cal = root.classList && root.classList.contains('ch-cal') ? root : root.querySelector('.ch-cal');
        if (!cal) {
            return;
        }
        var w = cal.clientWidth || (root.clientWidth || 0) || window.innerWidth || 0;
        cal.classList.remove('ch-cal--narrow', 'ch-cal--medium', 'ch-cal--wide');
        if (w < 560) {
            cal.classList.add('ch-cal--narrow');
        } else if (w < 900) {
            cal.classList.add('ch-cal--medium');
        } else {
            cal.classList.add('ch-cal--wide');
        }
    }

    var calLayoutResizeBound = false;
    function ensureCalendarLayoutResize() {
        if (calLayoutResizeBound) {
            return;
        }
        calLayoutResizeBound = true;
        var timer = null;
        window.addEventListener('resize', function () {
            if (timer) {
                clearTimeout(timer);
            }
            timer = setTimeout(function () {
                var cals = document.querySelectorAll('.ch-cal');
                for (var i = 0; i < cals.length; i++) {
                    applyCalendarLayoutMode(cals[i]);
                }
            }, 120);
        });
    }

    function storageCalendarDateFieldKey(objectApi) {
        if (storageUserId) {
            return 'crmhub_cal_date_' + storageUserId + '_' + objectApi;
        }
        return 'crmhub_cal_date_' + objectApi;
    }

    function persistCalendarDateField(objectApi, fieldApi) {
        if (!fieldApi) {
            return;
        }
        try {
            sessionStorage.setItem(storageCalendarDateFieldKey(objectApi), fieldApi);
        } catch (e) {}
    }

    function readPersistedCalendarDateField(objectApi) {
        try {
            return sessionStorage.getItem(storageCalendarDateFieldKey(objectApi));
        } catch (e) {
            return null;
        }
    }

    function storageKanbanSummarizeKey(objectApi) {
        if (storageUserId) {
            return 'crmhub_kan_sum_' + storageUserId + '_' + objectApi;
        }
        return 'crmhub_kan_sum_' + objectApi;
    }

    function persistKanbanSummarizeField(objectApi, fieldApi) {
        try {
            if (fieldApi == null) {
                sessionStorage.removeItem(storageKanbanSummarizeKey(objectApi));
                return;
            }
            sessionStorage.setItem(storageKanbanSummarizeKey(objectApi), fieldApi);
        } catch (e) {}
    }

    function readPersistedKanbanSummarizeField(objectApi) {
        try {
            var v = sessionStorage.getItem(storageKanbanSummarizeKey(objectApi));
            return v;
        } catch (e) {
            return null;
        }
    }

    function storageKanbanLaneKey(objectApi) {
        if (storageUserId) {
            return 'crmhub_kan_lane_' + storageUserId + '_' + objectApi;
        }
        return 'crmhub_kan_lane_' + objectApi;
    }

    function persistKanbanLaneField(objectApi, fieldApi) {
        try {
            if (!fieldApi) {
                sessionStorage.removeItem(storageKanbanLaneKey(objectApi));
                return;
            }
            sessionStorage.setItem(storageKanbanLaneKey(objectApi), fieldApi);
        } catch (e) {}
    }

    function readPersistedKanbanLaneField(objectApi) {
        try {
            return sessionStorage.getItem(storageKanbanLaneKey(objectApi));
        } catch (e) {
            return null;
        }
    }

    function readPersistedMode(objectApi) {
        try {
            return sessionStorage.getItem(storageModeKey(objectApi));
        } catch (e) {
            return null;
        }
    }

    function getTab(name) {
        return tabs[name] || null;
    }

    global.CrmHubListEngine = {
        initSession: function (sid) {
            global.CRM_HUB_SESSION = sid;
        },
        initUserId: function (uid) {
            storageUserId = uid || '';
            hydrateListViewPrefsFromCache();
        },
        initOpenIconUrl: function (url) {
            openIconUrl = url || openIconUrl;
        },
        mount: mount,
        getTab: getTab,
        syncListView: syncListView,
        syncMode: syncMode,
        activate: activate,
        persistMode: persistMode,
        readPersistedMode: readPersistedMode,
        persistListView: persistListView,
        readPersistedListView: readPersistedListView,
        persistPageSize: persistPageSize,
        readPersistedPageSize: readPersistedPageSize,
        persistCalendarDateField: persistCalendarDateField,
        readPersistedCalendarDateField: readPersistedCalendarDateField,
        persistKanbanSummarizeField: persistKanbanSummarizeField,
        readPersistedKanbanSummarizeField: readPersistedKanbanSummarizeField,
        persistKanbanLaneField: persistKanbanLaneField,
        readPersistedKanbanLaneField: readPersistedKanbanLaneField,
        seedListViewPrefs: seedListViewPrefs,
        hydrateListViewPrefsFromCache: hydrateListViewPrefsFromCache,
        getListViewPref: getListViewPref,
        setListViewPref: setListViewPref,
        openRecordIconBtn: openRecordIconBtn
    };
})(this);
