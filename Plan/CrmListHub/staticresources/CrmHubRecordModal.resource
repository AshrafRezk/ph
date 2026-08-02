/* global Visualforce, CrmHubListController, CrmHubListEngine */
(function (global) {
    'use strict';

    var modalEl = null;
    var bodyEl = null;
    var titleEl = null;
    var subEl = null;
    var tabBarEl = null;
    var pathEl = null;
    var wired = false;
    var openIconUrl = '';
    var currentModalData = null;
    var activeTabId = null;
    var currentRecordId = null;
    var loadedRelatedTabIds = {};
    var relatedListFetchInFlight = {};
    var loadedActivityTabIds = {};
    var activityFetchInFlight = {};
    var activityCacheByRecord = {};
    var viewAllModalEl = null;
    var viewAllBodyEl = null;
    var viewAllTitleEl = null;
    var footerEl = null;
    var headerActionsEl = null;
    var originalValues = {};
    var draftValues = {};
    var ownerLookupInstances = [];
    var refLookupInstances = [];
    var editMode = false;
    var canEditRecord = false;
    var createJobAppInFlight = false;
    var createJaFormEl = null;
    var createJaLookup = null;
    var createJaFormState = null;
    var recordActions = [];
    var actionFormEl = null;
    var actionFormState = null;
    var duplicatesCache = {};
    var duplicatesFetchInFlight = {};
    var openMenuEl = null;
    var hubDialogEl = null;
    var hubDialogKeyHandler = null;

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

    function closeHubDialog(result) {
        if (hubDialogKeyHandler) {
            document.removeEventListener('keydown', hubDialogKeyHandler, true);
            hubDialogKeyHandler = null;
        }
        if (!hubDialogEl) {
            return;
        }
        var onDone = hubDialogEl._onDone;
        hubDialogEl._onDone = null;
        hubDialogEl.style.display = 'none';
        hubDialogEl.setAttribute('aria-hidden', 'true');
        if (typeof onDone === 'function') {
            onDone(!!result);
        }
    }

    function ensureHubDialog() {
        injectStyles();
        if (hubDialogEl) {
            return hubDialogEl;
        }
        hubDialogEl = document.createElement('div');
        hubDialogEl.id = 'crm-hub-dialog';
        hubDialogEl.className = 'crm-hub-dialog-overlay';
        hubDialogEl.style.display = 'none';
        hubDialogEl.setAttribute('role', 'alertdialog');
        hubDialogEl.setAttribute('aria-modal', 'true');
        hubDialogEl.setAttribute('aria-hidden', 'true');
        hubDialogEl.innerHTML =
            '<div class="crm-hub-dialog" role="document">' +
            '<div class="crm-hub-dialog-icon" aria-hidden="true"></div>' +
            '<div class="crm-hub-dialog-copy">' +
            '<h2 class="crm-hub-dialog-title" id="crm-hub-dialog-title"></h2>' +
            '<p class="crm-hub-dialog-msg" id="crm-hub-dialog-msg"></p>' +
            '</div>' +
            '<div class="crm-hub-dialog-actions">' +
            '<button type="button" class="crm-hub-dialog-btn crm-hub-dialog-cancel">Cancel</button>' +
            '<button type="button" class="crm-hub-dialog-btn crm-hub-dialog-ok">OK</button>' +
            '</div>' +
            '</div>';
        document.body.appendChild(hubDialogEl);
        hubDialogEl.addEventListener('click', function (ev) {
            if (ev.target === hubDialogEl) {
                var isConfirm = hubDialogEl.classList.contains('is-confirm');
                closeHubDialog(isConfirm ? false : true);
            }
        });
        hubDialogEl.querySelector('.crm-hub-dialog-cancel').onclick = function () {
            closeHubDialog(false);
        };
        hubDialogEl.querySelector('.crm-hub-dialog-ok').onclick = function () {
            closeHubDialog(true);
        };
        return hubDialogEl;
    }

    /**
     * In-app dialog (replaces browser alert/confirm).
     * opts: { title, message, variant: 'error'|'confirm'|'info'|'success',
     *         okLabel, cancelLabel, onConfirm, onCancel }
     */
    function showHubDialog(opts) {
        opts = opts || {};
        var overlay = ensureHubDialog();
        var variant = opts.variant || 'error';
        var isConfirm = variant === 'confirm';
        var title =
            opts.title ||
            (variant === 'confirm'
                ? 'Please confirm'
                : variant === 'success'
                  ? 'Done'
                  : variant === 'info'
                    ? 'Notice'
                    : 'Something went wrong');
        var msg = opts.message != null ? String(opts.message) : '';
        var okLabel = opts.okLabel || (isConfirm ? 'Confirm' : 'Got it');
        var cancelLabel = opts.cancelLabel || 'Cancel';
        var icon =
            variant === 'confirm'
                ? '?'
                : variant === 'success'
                  ? '✓'
                  : variant === 'info'
                    ? 'i'
                    : '!';

        overlay.className =
            'crm-hub-dialog-overlay is-' +
            variant +
            (isConfirm ? ' is-confirm' : '') +
            (opts.danger ? ' is-danger' : '');
        overlay.querySelector('.crm-hub-dialog-icon').textContent = icon;
        overlay.querySelector('.crm-hub-dialog-title').textContent = title;
        overlay.querySelector('.crm-hub-dialog-msg').textContent = msg;
        overlay.querySelector('.crm-hub-dialog-ok').textContent = okLabel;
        var cancelBtn = overlay.querySelector('.crm-hub-dialog-cancel');
        cancelBtn.textContent = cancelLabel;
        cancelBtn.style.display = isConfirm ? '' : 'none';
        overlay.setAttribute('aria-labelledby', 'crm-hub-dialog-title');
        overlay.setAttribute('aria-describedby', 'crm-hub-dialog-msg');

        overlay._onDone = function (ok) {
            if (ok && typeof opts.onConfirm === 'function') {
                opts.onConfirm();
            } else if (!ok && typeof opts.onCancel === 'function') {
                opts.onCancel();
            }
        };

        if (hubDialogKeyHandler) {
            document.removeEventListener('keydown', hubDialogKeyHandler, true);
        }
        hubDialogKeyHandler = function (ev) {
            if (!overlay || overlay.style.display === 'none') {
                return;
            }
            if (ev.key === 'Escape') {
                ev.preventDefault();
                ev.stopPropagation();
                closeHubDialog(isConfirm ? false : true);
            } else if (ev.key === 'Enter' && !isConfirm) {
                ev.preventDefault();
                closeHubDialog(true);
            }
        };
        document.addEventListener('keydown', hubDialogKeyHandler, true);

        overlay.style.display = 'flex';
        overlay.setAttribute('aria-hidden', 'false');
        setTimeout(function () {
            var focusBtn = isConfirm ? cancelBtn : overlay.querySelector('.crm-hub-dialog-ok');
            if (focusBtn) {
                focusBtn.focus();
            }
        }, 0);
    }

    function hubAlert(message, opts) {
        opts = opts || {};
        showHubDialog({
            variant: opts.variant || 'error',
            title: opts.title,
            message: message,
            okLabel: opts.okLabel || 'Got it',
            onConfirm: opts.onConfirm
        });
    }

    function hubConfirm(message, onConfirm, opts) {
        opts = opts || {};
        showHubDialog({
            variant: 'confirm',
            title: opts.title || 'Please confirm',
            message: message,
            okLabel: opts.okLabel || 'Confirm',
            cancelLabel: opts.cancelLabel || 'Cancel',
            danger: !!opts.danger,
            onConfirm: onConfirm,
            onCancel: opts.onCancel
        });
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

    function isRenderableHtml(v) {
        if (v == null || v === '') {
            return false;
        }
        var s = String(v).trim();
        if (s.charAt(0) === '<' && s.indexOf('>') > 0) {
            return true;
        }
        if (s.indexOf('&lt;') >= 0 && /&lt;[a-zA-Z!/]/.test(s)) {
            return true;
        }
        if (s.indexOf('&amp;lt;') >= 0 && /&amp;lt;[a-zA-Z!/]/.test(s)) {
            return true;
        }
        if (/&#(x3c|60);/i.test(s) && /&#(x3c|60);[a-zA-Z!/]/i.test(s)) {
            return true;
        }
        if (/&lt;(a|img|div|span|p|br)\b/i.test(s)) {
            return true;
        }
        if (/href\s*=\s*(&quot;|&#39;|"|')/i.test(s) && /(&lt;|&#60;|<)a\b/i.test(s)) {
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

    function fieldWantsHtml(details, fieldApi, rawVal) {
        if (!details) {
            return isRenderableHtml(rawVal);
        }
        var type = details.type ? String(details.type).toLowerCase() : '';
        if (details.htmlFormatted === true || details.htmlFormatted === 'true') {
            return true;
        }
        if (type === 'textarea' && details.extraTypeInfo === 'richtext') {
            return true;
        }
        if (details.htmlCapable === true || details.calculated === true) {
            return isRenderableHtml(rawVal) || String(rawVal || '').indexOf('&lt;') >= 0;
        }
        if (isRenderableHtml(rawVal)) {
            return true;
        }
        var f = (fieldApi || '').toLowerCase();
        if (f.indexOf('summary') >= 0 || f.indexOf('contactdetail') >= 0 || f.indexOf('html') >= 0) {
            return isRenderableHtml(rawVal) || String(rawVal || '').indexOf('&lt;') >= 0;
        }
        return false;
    }

    function isEpochMs(v) {
        if (typeof v === 'number' && v > 86400000 && v < 4102444800000) {
            return true;
        }
        if (typeof v === 'string' && /^\d{12,13}$/.test(v)) {
            return true;
        }
        return false;
    }

    function formatDateValue(type, v) {
        if (v === null || v === undefined || v === '') {
            return '—';
        }
        if (typeof v === 'string' && !isEpochMs(v) && type === 'date') {
            return v;
        }
        if (typeof v === 'string' && !isEpochMs(v) && type === 'datetime') {
            return v;
        }
        var n = typeof v === 'number' ? v : Number(v);
        if (!isNaN(n) && isEpochMs(n)) {
            var d = new Date(n);
            if (type === 'datetime') {
                return d.toLocaleString(undefined, {
                    year: 'numeric',
                    month: 'short',
                    day: 'numeric',
                    hour: 'numeric',
                    minute: '2-digit'
                });
            }
            return d.toLocaleDateString(undefined, {
                year: 'numeric',
                month: 'short',
                day: 'numeric'
            });
        }
        return String(v);
    }

    function isPlainObject(v) {
        return v !== null && typeof v === 'object' && !Array.isArray(v);
    }

    function formatCompoundFromObject(val) {
        if (!isPlainObject(val)) {
            return null;
        }
        var street = val.street || val.Street || '';
        var city = val.city || val.City || '';
        var state = val.state || val.State || '';
        var postal = val.postalCode || val.PostalCode || val.zip || val.Zip || '';
        var country = val.country || val.Country || '';
        var parts = [];
        if (street) {
            parts.push(String(street));
        }
        var cityLine = [];
        if (city) {
            cityLine.push(String(city));
        }
        if (state) {
            cityLine.push(String(state));
        }
        if (postal) {
            cityLine.push(String(postal));
        }
        if (cityLine.length) {
            parts.push(cityLine.join(', '));
        }
        if (country) {
            parts.push(String(country));
        }
        if (parts.length) {
            return parts.join('\n');
        }
        var lat = val.latitude != null ? val.latitude : val.Latitude;
        var lng = val.longitude != null ? val.longitude : val.Longitude;
        if (lat != null && lng != null) {
            return String(lat) + ', ' + String(lng);
        }
        var generic = [];
        var keys = ['street', 'city', 'state', 'postalCode', 'country', 'latitude', 'longitude'];
        for (var i = 0; i < keys.length; i++) {
            if (val[keys[i]] != null && String(val[keys[i]]).trim() !== '') {
                generic.push(String(val[keys[i]]).trim());
            }
        }
        return generic.length ? generic.join(', ') : null;
    }

    function formatDisplayLabel(s) {
        return esc(decodeHtmlEntities(s || ''));
    }

    /** Plain-text safe for innerHTML: decode entities then escape (avoids showing &gt;&gt;). */
    function escPlain(s) {
        return esc(decodeHtmlEntities(s == null ? '' : String(s)));
    }

    function formatScalarValue(type, v, details) {
        if (v === null || v === undefined || v === '') {
            return '—';
        }
        if (type === 'boolean') {
            return v === true || v === 'true' ? 'Yes' : 'No';
        }
        if (type === 'date' || type === 'datetime') {
            return formatDateValue(type, v);
        }
        if (type === 'currency') {
            var c = Number(v);
            if (!isNaN(c)) {
                return c.toLocaleString(undefined, { style: 'currency', currency: 'USD', maximumFractionDigits: 2 });
            }
        }
        if (type === 'percent') {
            var p = Number(v);
            if (!isNaN(p)) {
                return p.toLocaleString(undefined, { maximumFractionDigits: 2 }) + '%';
            }
        }
        if (
            (type === 'picklist' || type === 'multipicklist') &&
            typeof v === 'string' &&
            v.indexOf(';') >= 0
        ) {
            return v
                .split(';')
                .map(function (part) {
                    return part.trim();
                })
                .filter(Boolean)
                .join(', ');
        }
        if (type === 'phone' && typeof v === 'string') {
            return '<a href="tel:' + escPlain(v) + '">' + escPlain(v) + '</a>';
        }
        if (type === 'double') {
            var dbl = Number(v);
            if (!isNaN(dbl)) {
                var scale = details && details.scale != null ? Number(details.scale) : 2;
                return dbl.toLocaleString(undefined, {
                    minimumFractionDigits: 0,
                    maximumFractionDigits: scale
                });
            }
        }
        if (type === 'email' && typeof v === 'string') {
            return '<a href="mailto:' + escPlain(v) + '">' + escPlain(v) + '</a>';
        }
        if (type === 'url' && typeof v === 'string') {
            var decodedUrl = decodeHtmlEntities(v);
            var href = decodedUrl.indexOf('://') > 0 ? decodedUrl : 'https://' + decodedUrl;
            return (
                '<a href="' +
                esc(href) +
                '" target="_blank" rel="noopener noreferrer">' +
                escPlain(v) +
                '</a>'
            );
        }
        if ((type === 'address' || type === 'location') && isPlainObject(v)) {
            var compoundText = formatCompoundFromObject(v);
            if (compoundText) {
                return escPlain(compoundText).replace(/\n/g, '<br>');
            }
        }
        if (isPlainObject(v)) {
            var objectText = formatCompoundFromObject(v);
            if (objectText) {
                return escPlain(objectText).replace(/\n/g, '<br>');
            }
            return '—';
        }
        return decodeHtmlEntities(String(v));
    }

    function resolveOpenIconUrl() {
        if (openIconUrl) {
            return openIconUrl;
        }
        var el = document.getElementById('crm-hub-open-icon');
        if (el && el.value) {
            openIconUrl = el.value;
            return openIconUrl;
        }
        return 'https://cdn-icons-png.flaticon.com/512/7794/7794669.png';
    }

    function openRecordIconImg() {
        return (
            '<img class="ch-open-img" src="' +
            esc(resolveOpenIconUrl()) +
            '" alt="" aria-hidden="true" width="18" height="18" />'
        );
    }

    function openRecordIconBtn(rid, title) {
        if (!rid) {
            return '';
        }
        var tip = title ? esc(title) : 'record';
        return (
            '<button type="button" class="ch-open ch-open-ico crm-rm-open" data-id="' +
            esc(String(rid)) +
            '" title="Open record" aria-label="Open record — ' +
            tip +
            '">' +
            openRecordIconImg() +
            '<span class="slds-assistive-text">Open record</span></button>'
        );
    }

    function remotingEnabled() {
        return (
            typeof Visualforce !== 'undefined' &&
            Visualforce.remoting &&
            typeof CrmHubListController !== 'undefined' &&
            typeof CrmHubListController.fetchRecordModalShell === 'function'
        );
    }

    function remotingCall(methodName, args) {
        return new Promise(function (resolve, reject) {
            if (!remotingEnabled() || typeof CrmHubListController[methodName] !== 'function') {
                reject(new Error('CRM Hub record modal remoting is unavailable'));
                return;
            }
            Visualforce.remoting.timeout = 120000;
            var fn = CrmHubListController[methodName];
            fn.apply(
                CrmHubListController,
                args.concat(function (res, ev) {
                    if (!ev.status) {
                        reject(new Error(ev.message || 'Remoting failed'));
                        return;
                    }
                    resolve(res || {});
                })
            );
        });
    }

    function remotingFetch(recordId) {
        return remotingCall('fetchRecordModalData', [recordId]);
    }

    function remotingShell(recordId) {
        return remotingCall('fetchRecordModalShell', [recordId]);
    }

    function remotingDetails(recordId) {
        return remotingCall('fetchRecordModalDetails', [recordId]);
    }

    function remotingTabs(recordId) {
        return remotingCall('fetchRecordModalTabs', [recordId]);
    }

    function remotingPath(recordId) {
        return remotingCall('fetchRecordModalPath', [recordId]);
    }

    function remotingRelatedList(recordId, relatedListApi, tabId, rowLimit) {
        return remotingCall('fetchRecordModalRelatedList', [recordId, relatedListApi, tabId, rowLimit || 5]);
    }

    function remotingActivities(recordId) {
        return remotingCall('fetchRecordModalActivities', [recordId]);
    }

    function remotingCreateActivity(recordId, activityType, fields) {
        return remotingCall('createRecordModalActivity', [recordId, activityType, fields || {}]);
    }

    function remotingCompleteActivity(recordId, activityId) {
        return remotingCall('completeRecordModalActivity', [recordId, activityId]);
    }

    function remotingUpdateRecordFields(recordId, fieldValues) {
        return remotingCall('updateRecordFields', [recordId, fieldValues]);
    }

    function remotingGetCreateJobApplicationForm(recordId) {
        return remotingCall('getCreateJobApplicationForm', [recordId]);
    }

    function remotingCreateJobApplicationFromForm(recordId, fieldValues) {
        return remotingCall('createJobApplicationFromForm', [recordId, fieldValues || {}]);
    }

    function remotingDeleteHubRecord(recordId) {
        return remotingCall('deleteHubRecord', [recordId]);
    }

    function remotingCloneHubRecord(recordId) {
        return remotingCall('cloneHubRecord', [recordId]);
    }

    function remotingCreateClonedRecord(objectApi, fieldValues) {
        return remotingCall('createClonedRecord', [objectApi, fieldValues || {}]);
    }

    function remotingGetQuickActionForm(parentRecordId, objectApi, actionApi, contextType) {
        return remotingCall('getQuickActionForm', [parentRecordId, objectApi, actionApi, contextType || '']);
    }

    function remotingExecuteQuickAction(parentRecordId, objectApi, actionApi, recordValues) {
        return remotingCall('executeQuickAction', [parentRecordId, objectApi, actionApi, recordValues || {}]);
    }

    function remotingFetchPotentialDuplicates(recordId) {
        return remotingCall('fetchPotentialDuplicates', [recordId]);
    }

    function actionByApiName(apiName) {
        var acts = recordActions || [];
        for (var i = 0; i < acts.length; i++) {
            if (acts[i] && String(acts[i].apiName) === String(apiName)) {
                return acts[i];
            }
        }
        return null;
    }

    function hasRecordAction(apiName) {
        return !!actionByApiName(apiName);
    }

    function closeActionMenu() {
        if (openMenuEl && openMenuEl.parentNode) {
            openMenuEl.parentNode.removeChild(openMenuEl);
        }
        openMenuEl = null;
    }

    function confirmHubAction(message, onConfirm, opts) {
        hubConfirm(message, onConfirm, opts || {});
    }

    function handleHubAction(action, context) {
        context = context || {};
        if (!action || !action.apiName) {
            return;
        }
        var apiName = String(action.apiName);
        if (apiName === 'Edit') {
            if (context.recordId && context.recordId !== currentRecordId) {
                openRecordModal(context.recordId, { editOnLoad: true });
            } else {
                enterEditMode();
            }
            return;
        }
        if (apiName === 'Delete') {
            var delId = context.recordId || currentRecordId;
            confirmHubAction(
                'Delete this record? This cannot be undone.',
                function () {
                    remotingDeleteHubRecord(delId)
                        .then(function (res) {
                            if (res.error) {
                                hubAlert(res.error);
                                return;
                            }
                            if (delId === currentRecordId) {
                                closeModalNow();
                            } else if (context.refreshRelatedList) {
                                context.refreshRelatedList();
                            }
                        })
                        .catch(function (err) {
                            hubAlert(err && err.message ? err.message : String(err));
                        });
                },
                { title: 'Delete record?', okLabel: 'Delete', danger: true }
            );
            return;
        }
        if (apiName === 'Clone') {
            var cloneId = context.recordId || currentRecordId;
            openCloneForm(cloneId);
            return;
        }
        if (action.type === 'QuickAction' || apiName.indexOf('__') >= 0 || apiName === 'Create_Job_Application') {
            openQuickActionForm(
                context.parentRecordId || currentRecordId,
                context.objectApi || (currentModalData && currentModalData.objectApi),
                apiName,
                context
            );
            return;
        }
        if (action.targetUrl) {
            openActionIframe(action.targetUrl, action.label || apiName);
        }
    }

    function openActionIframe(url, title) {
        injectStyles();
        var overlay = document.getElementById('crm-rm-iframe-overlay');
        if (!overlay) {
            overlay = document.createElement('div');
            overlay.id = 'crm-rm-iframe-overlay';
            overlay.className = 'crm-rm-iframe-overlay';
            overlay.innerHTML =
                '<div class="crm-rm-iframe-inner">' +
                '<div class="crm-rm-iframe-head"><span class="crm-rm-iframe-title"></span>' +
                '<button type="button" class="crm-rm-close" aria-label="Close">&times;</button></div>' +
                '<iframe class="crm-rm-iframe" title="Action"></iframe></div>';
            document.body.appendChild(overlay);
            overlay.querySelector('.crm-rm-close').onclick = function () {
                overlay.style.display = 'none';
                overlay.querySelector('iframe').src = 'about:blank';
            };
            overlay.addEventListener('click', function (ev) {
                if (ev.target === overlay) {
                    overlay.style.display = 'none';
                    overlay.querySelector('iframe').src = 'about:blank';
                }
            });
        }
        overlay.querySelector('.crm-rm-iframe-title').textContent = title || 'Action';
        overlay.querySelector('iframe').src = url;
        overlay.style.display = 'flex';
    }

    function openQuickActionForm(parentRecordId, objectApi, actionApi, context) {
        if (actionApi === 'Create_Job_Application' || actionApi === 'createJobApplication') {
            openCreateJobApplicationForm(parentRecordId);
            return;
        }
        remotingGetQuickActionForm(parentRecordId, objectApi, actionApi, (context && context.contextType) || '')
            .then(function (res) {
                if (res.error) {
                    hubAlert(res.error);
                    return;
                }
                openGenericActionForm(res, context);
            })
            .catch(function (err) {
                hubAlert(err && err.message ? err.message : String(err));
            });
    }

    function openCloneForm(recordId) {
        remotingCloneHubRecord(recordId)
            .then(function (res) {
                if (res.error) {
                    hubAlert(res.error);
                    return;
                }
                res.isClone = true;
                openGenericActionForm(res, { sourceRecordId: recordId });
            })
            .catch(function (err) {
                hubAlert(err && err.message ? err.message : String(err));
            });
    }

    function ensureGenericActionForm() {
        injectStyles();
        if (actionFormEl) {
            return actionFormEl;
        }
        actionFormEl = document.createElement('div');
        actionFormEl.className = 'crm-rm-createja-overlay crm-rm-actionform-overlay';
        actionFormEl.style.display = 'none';
        actionFormEl.innerHTML =
            '<div class="crm-rm-createja-inner">' +
            '<div class="crm-rm-createja-header">' +
            '<h2 class="crm-rm-createja-title"></h2>' +
            '<button type="button" class="crm-rm-createja-close" aria-label="Close">&times;</button></div>' +
            '<div class="crm-rm-createja-req"></div>' +
            '<div class="crm-rm-createja-body"></div>' +
            '<div class="crm-rm-createja-footer">' +
            '<button type="button" class="crm-rm-createja-cancel">Cancel</button>' +
            '<button type="button" class="crm-rm-createja-save">Save</button></div></div>';
        document.body.appendChild(actionFormEl);
        actionFormEl.querySelector('.crm-rm-createja-close').onclick = closeGenericActionForm;
        actionFormEl.querySelector('.crm-rm-createja-cancel').onclick = closeGenericActionForm;
        actionFormEl.querySelector('.crm-rm-createja-save').onclick = saveGenericActionForm;
        return actionFormEl;
    }

    function closeGenericActionForm() {
        actionFormState = null;
        if (actionFormEl) {
            actionFormEl.style.display = 'none';
        }
    }

    function openGenericActionForm(form, context) {
        var overlay = ensureGenericActionForm();
        overlay.querySelector('.crm-rm-createja-title').textContent = form.title || 'Form';
        overlay.querySelector('.crm-rm-createja-req').textContent = form.requiredHint || '';
        actionFormState = { form: form, context: context || {} };
        var body = overlay.querySelector('.crm-rm-createja-body');
        if (form.isClone || form.values) {
            body.innerHTML = renderCloneFormFields(form);
        } else if (form.parentObjectApi === 'Lead' || form.parentObjectApi === 'Contact') {
            renderCreateJobApplicationForm(form);
            overlay.style.display = 'flex';
            return;
        } else {
            body.innerHTML = '<div class="crm-rm-muted">Quick action form not fully supported in Hub yet.</div>';
        }
        overlay.style.display = 'flex';
    }

    function renderCloneFormFields(form) {
        var values = form.values || {};
        var meta = form.fieldMeta || {};
        var html = ['<div class="crm-rm-grid">'];
        for (var fieldApi in values) {
            if (!Object.prototype.hasOwnProperty.call(values, fieldApi)) {
                continue;
            }
            var m = meta[fieldApi] || {};
            var label = m.label || fieldApi;
            var val = values[fieldApi];
            html.push(
                '<label class="crm-rm-field"><span class="crm-rm-lbl">' +
                    esc(label) +
                    '</span><input class="crm-rm-input" data-field="' +
                    esc(fieldApi) +
                    '" value="' +
                    esc(val == null ? '' : String(val)) +
                    '" /></label>'
            );
        }
        html.push('</div>');
        return html.join('');
    }

    function saveGenericActionForm() {
        if (!actionFormState || !actionFormEl) {
            return;
        }
        var form = actionFormState.form;
        var ctx = actionFormState.context;
        var saveBtn = actionFormEl.querySelector('.crm-rm-createja-save');
        if (saveBtn) {
            saveBtn.disabled = true;
        }
        if (form.isClone) {
            var fieldValues = {};
            var inputs = actionFormEl.querySelectorAll('[data-field]');
            for (var i = 0; i < inputs.length; i++) {
                fieldValues[inputs[i].getAttribute('data-field')] = inputs[i].value;
            }
            remotingCreateClonedRecord(form.objectApi, fieldValues)
                .then(function (res) {
                    closeGenericActionForm();
                    if (res.error) {
                        hubAlert(res.error);
                        return;
                    }
                    if (res.recordId) {
                        openRecordModal(res.recordId);
                    }
                })
                .catch(function (err) {
                    hubAlert(err && err.message ? err.message : String(err));
                })
                .finally(function () {
                    if (saveBtn) {
                        saveBtn.disabled = false;
                    }
                });
            return;
        }
        if (form.parentObjectApi === 'Lead' || form.parentObjectApi === 'Contact') {
            saveCreateJobApplicationForm();
            return;
        }
        if (saveBtn) {
            saveBtn.disabled = false;
        }
    }

    function renderActionButton(action, extraCls) {
        var cls = 'crm-rm-action-btn' + (extraCls ? ' ' + extraCls : '');
        if (action.type === 'QuickAction' && String(action.apiName).indexOf('Create') >= 0) {
            cls += ' is-primary';
        }
        return (
            '<button type="button" class="' +
            cls +
            '" data-hub-action="' +
            esc(action.apiName) +
            '" data-action-type="' +
            esc(action.type || 'StandardButton') +
            '">' +
            esc(action.label || action.apiName) +
            '</button>'
        );
    }

    function showRowActionMenu(ev, actions, context) {
        ev.preventDefault();
        ev.stopPropagation();
        closeActionMenu();
        if (!actions || !actions.length) {
            return;
        }
        var menu = document.createElement('div');
        menu.className = 'crm-rm-action-menu';
        var html = [];
        for (var i = 0; i < actions.length; i++) {
            html.push(
                '<button type="button" class="crm-rm-action-menu-item" data-hub-action="' +
                    esc(actions[i].apiName) +
                    '" data-action-type="' +
                    esc(actions[i].type || 'StandardButton') +
                    '">' +
                    esc(actions[i].label || actions[i].apiName) +
                    '</button>'
            );
        }
        menu.innerHTML = html.join('');
        menu._hubContext = context;
        document.body.appendChild(menu);
        var rect = ev.target.getBoundingClientRect();
        menu.style.top = rect.bottom + 4 + 'px';
        menu.style.left = Math.max(8, rect.left - 80) + 'px';
        openMenuEl = menu;
    }

    function loadDuplicatesTab(tab) {
        if (!tab || !currentRecordId) {
            return;
        }
        var fetchKey = currentRecordId;
        if (duplicatesCache[fetchKey]) {
            renderDuplicatesPanel(duplicatesCache[fetchKey]);
            return;
        }
        if (duplicatesFetchInFlight[fetchKey]) {
            return;
        }
        duplicatesFetchInFlight[fetchKey] = true;
        var panel = bodyEl.querySelector('.crm-rm-panel[data-tab-id="' + tab.id + '"]');
        if (panel) {
            panel.innerHTML = '<div class="crm-rm-tab-loading">Loading potential duplicates…</div>';
        }
        remotingFetchPotentialDuplicates(currentRecordId)
            .then(function (res) {
                delete duplicatesFetchInFlight[fetchKey];
                if (res.error) {
                    if (panel) {
                        panel.innerHTML = '<div class="crm-rm-muted">' + esc(res.error) + '</div>';
                    }
                    return;
                }
                duplicatesCache[fetchKey] = res;
                renderDuplicatesPanel(res);
            })
            .catch(function (err) {
                delete duplicatesFetchInFlight[fetchKey];
                if (panel) {
                    panel.innerHTML =
                        '<div class="crm-rm-muted">' + esc(err && err.message ? err.message : String(err)) + '</div>';
                }
            });
    }

    function renderDuplicatesPanel(res) {
        var panel = bodyEl.querySelector('.crm-rm-panel[data-tab-id="potential_duplicates"]');
        if (!panel) {
            panel = bodyEl.querySelector('.crm-rm-panel[data-tab-id="' + activeTabId + '"]');
        }
        if (!panel) {
            return;
        }
        var groups = (res && res.groups) || [];
        if (!groups.length) {
            panel.innerHTML = '<div class="crm-rm-muted">No potential duplicates found.</div>';
            return;
        }
        var html = [];
        for (var gi = 0; gi < groups.length; gi++) {
            var group = groups[gi];
            html.push('<div class="crm-rm-dup-group">');
            html.push(
                '<h3 class="crm-rm-sec">' +
                    esc(group.duplicateRule || 'Potential Duplicates') +
                    '</h3>'
            );
            if (group.recommendedWinnerId) {
                html.push(
                    '<p class="crm-rm-dup-banner">Recommended master record is highlighted below.</p>'
                );
            }
            html.push('<div class="crm-rm-dup-cards">');
            var records = group.records || [];
            for (var ri = 0; ri < records.length; ri++) {
                var rec = records[ri];
                html.push(
                    '<div class="crm-rm-dup-card' +
                        (rec.isRecommendedWinner ? ' is-winner' : '') +
                        (rec.isCurrent ? ' is-current' : '') +
                        '">'
                );
                html.push('<div class="crm-rm-dup-card-head">');
                html.push(
                    '<button type="button" class="crm-rm-dup-name ch-open" data-id="' +
                        esc(rec.id) +
                        '">' +
                        esc(rec.name || rec.id) +
                        '</button>'
                );
                if (rec.isRecommendedWinner) {
                    html.push('<span class="crm-rm-dup-winner">Recommended master</span>');
                }
                if (rec.isCurrent) {
                    html.push('<span class="crm-rm-dup-current">Current</span>');
                }
                html.push('</div>');
                html.push(
                    '<div class="crm-rm-dup-score"><span class="ch-score-badge ch-score--' +
                        esc(String(rec.completenessBand || 'Watch').toLowerCase().replace(/[^a-z]/g, '')) +
                        '"><span class="ch-score-num">' +
                        esc(String(rec.completenessScore != null ? rec.completenessScore : '—')) +
                        '</span><span class="ch-score-band">' +
                        esc(rec.completenessBand || '') +
                        '</span></span>' +
                        '<span class="crm-rm-dup-meta">' +
                        esc(String(rec.filledFieldCount || 0)) +
                        ' / ' +
                        esc(String(rec.totalScorableFields || 0)) +
                        ' fields</span></div>'
                );
                html.push('</div>');
            }
            html.push('</div></div>');
        }
        panel.innerHTML = html.join('');
    }

    function cloneValuesMap(values) {
        var out = {};
        if (!values) {
            return out;
        }
        for (var k in values) {
            if (Object.prototype.hasOwnProperty.call(values, k)) {
                out[k] = values[k];
            }
        }
        return out;
    }

    function initDraftState(values) {
        originalValues = cloneValuesMap(values || {});
        draftValues = cloneValuesMap(values || {});
    }

    function normalizeCompareValue(val, type) {
        if (val === null || val === undefined || val === '' || val === '—') {
            return '';
        }
        var t = (type || '').toLowerCase();
        if (t === 'boolean') {
            return val === true || val === 'true' || val === 'Yes' || val === '1' ? 'true' : 'false';
        }
        if (t === 'double' || t === 'currency' || t === 'percent') {
            var n = Number(val);
            return isNaN(n) ? String(val).trim() : String(n);
        }
        if (t === 'multipicklist') {
            return String(val)
                .split(';')
                .map(function (p) {
                    return p.trim();
                })
                .filter(Boolean)
                .sort()
                .join(';');
        }
        return String(val).trim();
    }

    function fieldHasChanged(fieldApi, type) {
        return (
            normalizeCompareValue(draftValues[fieldApi], type) !==
            normalizeCompareValue(originalValues[fieldApi], type)
        );
    }

    function countChangedFields() {
        var n = 0;
        var meta = (currentModalData && currentModalData.fieldMeta) || {};
        for (var k in draftValues) {
            if (!Object.prototype.hasOwnProperty.call(draftValues, k)) {
                continue;
            }
            var t = meta[k] ? meta[k].type : '';
            if (fieldHasChanged(k, t)) {
                n++;
            }
        }
        return n;
    }

    function getChangedFieldsOnly() {
        var out = {};
        var meta = (currentModalData && currentModalData.fieldMeta) || {};
        for (var k in draftValues) {
            if (!Object.prototype.hasOwnProperty.call(draftValues, k)) {
                continue;
            }
            var t = meta[k] ? meta[k].type : '';
            if (fieldHasChanged(k, t)) {
                out[k] = draftValues[k];
            }
        }
        return out;
    }

    function hasEditableLayoutFields(layout, fieldMeta) {
        var meta = fieldMeta || {};
        var sections = (layout && layout.detailLayoutSections) || [];
        for (var si = 0; si < sections.length; si++) {
            var rows = sections[si].layoutRows || [];
            for (var ri = 0; ri < rows.length; ri++) {
                var items = rows[ri].layoutItems || [];
                for (var ii = 0; ii < items.length; ii++) {
                    var comps = items[ii].layoutComponents || [];
                    for (var ci = 0; ci < comps.length; ci++) {
                        if (comps[ci].type !== 'Field') {
                            continue;
                        }
                        var fieldApi = comps[ci].value;
                        var details = comps[ci].details || {};
                        if (fieldEditableInModal(fieldApi, details, meta)) {
                            return true;
                        }
                    }
                }
            }
        }
        return false;
    }

    function confirmDiscardIfNeeded(next) {
        if (countChangedFields() === 0) {
            next();
            return;
        }
        var n = countChangedFields();
        hubConfirm(
            'Discard ' + n + ' unsaved change' + (n === 1 ? '' : 's') + '?',
            function () {
                discardDraft();
                next();
            },
            { title: 'Discard changes?', okLabel: 'Discard' }
        );
    }

    function enterEditMode() {
        if (!canEditRecord) {
            return;
        }
        editMode = true;
        refreshDetailsPanelOnly();
        updateFooter();
    }

    function exitEditMode() {
        editMode = false;
        draftValues = cloneValuesMap(originalValues);
        refreshDetailsPanelOnly();
        updateFooter();
    }

    function discardDraft() {
        exitEditMode();
    }

    function supportsCreateJobApplication(objectApi) {
        return objectApi === 'Lead' || objectApi === 'Contact';
    }

    function updateHeaderActions() {
        if (!headerActionsEl) {
            return;
        }
        if (editMode) {
            headerActionsEl.innerHTML = '';
            headerActionsEl.style.display = 'none';
            return;
        }
        var html = [];
        var acts = (recordActions || []).slice();
        var api = (currentModalData && currentModalData.objectApi) || '';
        // Preserve existing Hub Create JA affordance when UI API does not return it.
        if (supportsCreateJobApplication(api) && !hasRecordAction('Create_Job_Application')) {
            acts.push({
                apiName: 'Create_Job_Application',
                label: 'Create Job Application',
                type: 'QuickAction'
            });
        }
        var primary = [];
        var overflow = [];
        for (var i = 0; i < acts.length; i++) {
            var act = acts[i];
            if (!act || !act.apiName) {
                continue;
            }
            if (act.apiName === 'Edit' || act.apiName === 'Delete' || act.apiName === 'Clone') {
                continue;
            }
            if (act.type === 'QuickAction' || String(act.apiName).indexOf('Create') >= 0) {
                primary.push(act);
            } else {
                overflow.push(act);
            }
        }
        for (var p = 0; p < primary.length && p < 2; p++) {
            html.push(renderActionButton(primary[p], 'is-primary'));
        }
        if (overflow.length) {
            html.push(
                '<button type="button" class="crm-rm-action-btn crm-rm-action-more" data-hub-action-menu="header">⋮</button>'
            );
            headerActionsEl._overflowActions = overflow;
        } else {
            headerActionsEl._overflowActions = [];
        }
        headerActionsEl.innerHTML = html.join('');
        headerActionsEl.style.display = html.length ? 'flex' : 'none';
    }

    function handleHeaderActionClick(ev) {
        var menuBtn = ev.target.closest('[data-hub-action-menu="header"]');
        if (menuBtn && headerActionsEl) {
            ev.preventDefault();
            showRowActionMenu(ev, headerActionsEl._overflowActions || [], {});
            return;
        }
        var btn = ev.target.closest('[data-hub-action]');
        if (!btn || !headerActionsEl.contains(btn)) {
            return;
        }
        ev.preventDefault();
        handleHubAction(
            { apiName: btn.getAttribute('data-hub-action'), type: btn.getAttribute('data-action-type') },
            {}
        );
    }

    function createJobApplicationFromCurrentRecord() {
        if (!currentRecordId || createJobAppInFlight) {
            return;
        }
        var api = (currentModalData && currentModalData.objectApi) || '';
        if (!supportsCreateJobApplication(api)) {
            return;
        }
        openCreateJobApplicationForm(currentRecordId);
    }

    function destroyCreateJaLookup() {
        if (createJaLookup && typeof createJaLookup.destroy === 'function') {
            createJaLookup.destroy();
        }
        createJaLookup = null;
    }

    function closeCreateJobApplicationForm() {
        destroyCreateJaLookup();
        createJaFormState = null;
        createJobAppInFlight = false;
        if (createJaFormEl) {
            createJaFormEl.style.display = 'none';
        }
        updateHeaderActions();
        updateFooter();
    }

    function ensureCreateJobApplicationForm() {
        injectStyles();
        if (createJaFormEl) {
            return createJaFormEl;
        }
        createJaFormEl = document.createElement('div');
        createJaFormEl.className = 'crm-rm-createja-overlay';
        createJaFormEl.style.display = 'none';
        createJaFormEl.setAttribute('role', 'dialog');
        createJaFormEl.setAttribute('aria-modal', 'true');
        createJaFormEl.innerHTML =
            '<div class="crm-rm-createja-inner">' +
            '<div class="crm-rm-createja-header">' +
            '<h2 class="crm-rm-createja-title">Create Job Application</h2>' +
            '<button type="button" class="crm-rm-createja-close" aria-label="Close">&times;</button>' +
            '</div>' +
            '<div class="crm-rm-createja-req">* = Required Information</div>' +
            '<div class="crm-rm-createja-body"></div>' +
            '<div class="crm-rm-createja-footer">' +
            '<button type="button" class="crm-rm-createja-cancel">Cancel</button>' +
            '<button type="button" class="crm-rm-createja-save">Save</button>' +
            '</div>' +
            '</div>';
        document.body.appendChild(createJaFormEl);
        createJaFormEl.querySelector('.crm-rm-createja-close').onclick = closeCreateJobApplicationForm;
        createJaFormEl.querySelector('.crm-rm-createja-cancel').onclick = closeCreateJobApplicationForm;
        createJaFormEl.querySelector('.crm-rm-createja-save').onclick = saveCreateJobApplicationForm;
        createJaFormEl.addEventListener('click', function (ev) {
            if (ev.target === createJaFormEl) {
                closeCreateJobApplicationForm();
            }
        });
        return createJaFormEl;
    }

    function openCreateJobApplicationForm(recordId) {
        var overlay = ensureCreateJobApplicationForm();
        var body = overlay.querySelector('.crm-rm-createja-body');
        var saveBtn = overlay.querySelector('.crm-rm-createja-save');
        body.innerHTML = '<div class="crm-rm-loading">Loading…</div>';
        overlay.style.display = 'flex';
        createJobAppInFlight = true;
        updateHeaderActions();
        updateFooter();
        if (saveBtn) {
            saveBtn.disabled = true;
        }

        remotingGetCreateJobApplicationForm(recordId)
            .then(function (res) {
                createJobAppInFlight = false;
                updateHeaderActions();
                updateFooter();
                if (!res || res.error) {
                    closeCreateJobApplicationForm();
                    hubAlert((res && res.error) || 'Unable to open Create Job Application');
                    return;
                }
                renderCreateJobApplicationForm(res);
                if (saveBtn) {
                    saveBtn.disabled = false;
                }
            })
            .catch(function (err) {
                createJobAppInFlight = false;
                closeCreateJobApplicationForm();
                updateHeaderActions();
                updateFooter();
                hubAlert(err && err.message ? err.message : String(err));
            });
    }

    function renderCreateJobApplicationForm(form) {
        var overlay = ensureCreateJobApplicationForm();
        var title = overlay.querySelector('.crm-rm-createja-title');
        var req = overlay.querySelector('.crm-rm-createja-req');
        var body = overlay.querySelector('.crm-rm-createja-body');
        if (title) {
            title.textContent = form.title || 'Create Job Application';
        }
        if (req) {
            req.textContent = form.requiredHint || '* = Required Information';
        }

        destroyCreateJaLookup();
        createJaFormState = {
            parentRecordId: currentRecordId,
            parentObjectApi: form.parentObjectApi,
            parentField: form.parentField,
            parentId: form.parentId,
            parentName: form.parentName || '',
            nextStep: form.nextStep || '',
            status: form.status || 'New',
            statusOptions: form.statusOptions || [],
            positionObject: form.positionLookupObject || 'Position__c'
        };

        var parentLabel = form.parentObjectApi === 'Contact' ? 'Contact' : 'Lead';
        var statusOpts = createJaFormState.statusOptions;
        var statusHtml = ['<select class="crm-rm-input crm-rm-createja-status">'];
        statusHtml.push('<option value=""></option>');
        for (var i = 0; i < statusOpts.length; i++) {
            var sv = String(statusOpts[i]);
            statusHtml.push(
                '<option value="' +
                    esc(sv) +
                    '"' +
                    (String(createJaFormState.status) === sv ? ' selected' : '') +
                    '>' +
                    esc(sv) +
                    '</option>'
            );
        }
        statusHtml.push('</select>');

        var parentFieldHtml =
            '<div class="crm-rm-createja-field">' +
            '<div class="crm-rm-createja-lbl">' +
            esc(parentLabel) +
            '</div>' +
            '<div class="crm-rm-createja-readonly">' +
            esc(createJaFormState.parentName) +
            '</div>' +
            '</div>';
        var nextStepHtml =
            '<div class="crm-rm-createja-field">' +
            '<div class="crm-rm-createja-lbl">Next Step</div>' +
            '<input type="text" class="crm-rm-input crm-rm-createja-nextstep" value="' +
            esc(createJaFormState.nextStep) +
            '" />' +
            '</div>';
        var positionHtml =
            '<div class="crm-rm-createja-field">' +
            '<div class="crm-rm-createja-lbl">Position</div>' +
            '<div class="crm-rm-createja-lookup"></div>' +
            '</div>';
        var statusFieldHtml =
            '<div class="crm-rm-createja-field">' +
            '<div class="crm-rm-createja-lbl">Status</div>' +
            statusHtml.join('') +
            '</div>';

        // Match Lightning quick-action layouts:
        // Lead: Lead/Next Step | Position/Status
        // Contact: Position/Next Step | Contact/Status
        var leftCol;
        var rightCol;
        if (form.parentObjectApi === 'Contact') {
            leftCol = positionHtml + nextStepHtml;
            rightCol = parentFieldHtml + statusFieldHtml;
        } else {
            leftCol = parentFieldHtml + nextStepHtml;
            rightCol = positionHtml + statusFieldHtml;
        }

        body.innerHTML =
            '<div class="crm-rm-createja-grid">' +
            '<div class="crm-rm-createja-col">' +
            leftCol +
            '</div>' +
            '<div class="crm-rm-createja-col">' +
            rightCol +
            '</div>' +
            '</div>';

        var lookupHost = body.querySelector('.crm-rm-createja-lookup');
        var initialPos =
            form.positionId
                ? { id: form.positionId, name: form.positionName || form.positionId }
                : null;
        if (lookupHost && global.CrmHubLookup && typeof global.CrmHubLookup.mount === 'function') {
            createJaLookup = global.CrmHubLookup.mount(lookupHost, {
                objectApi: createJaFormState.positionObject,
                value: initialPos,
                placeholder: 'Search Positions...',
                iconLetters: 'P',
                minChars: 1
            });
        } else if (lookupHost) {
            lookupHost.innerHTML =
                '<input type="text" class="crm-rm-input crm-rm-createja-position-fallback" placeholder="Position Id" value="' +
                esc(form.positionId || '') +
                '" />';
        }
    }

    function saveCreateJobApplicationForm() {
        if (!createJaFormState || !createJaFormState.parentRecordId || createJobAppInFlight) {
            return;
        }
        var overlay = ensureCreateJobApplicationForm();
        var nextInp = overlay.querySelector('.crm-rm-createja-nextstep');
        var statusInp = overlay.querySelector('.crm-rm-createja-status');
        var saveBtn = overlay.querySelector('.crm-rm-createja-save');
        var positionId = null;
        if (createJaLookup && typeof createJaLookup.getValue === 'function') {
            var sel = createJaLookup.getValue();
            positionId = sel && sel.id ? sel.id : null;
        } else {
            var fallback = overlay.querySelector('.crm-rm-createja-position-fallback');
            positionId = fallback && fallback.value ? String(fallback.value).trim() : null;
            if (positionId === '') {
                positionId = null;
            }
        }

        var fields = {
            NextStep__c: nextInp ? nextInp.value : '',
            Status__c: statusInp ? statusInp.value : 'New',
            Position__c: positionId
        };

        createJobAppInFlight = true;
        if (saveBtn) {
            saveBtn.disabled = true;
        }
        updateHeaderActions();
        updateFooter();

        remotingCreateJobApplicationFromForm(createJaFormState.parentRecordId, fields)
            .then(function (res) {
                createJobAppInFlight = false;
                if (saveBtn) {
                    saveBtn.disabled = false;
                }
                updateHeaderActions();
                updateFooter();
                if (!res || res.error) {
                    hubAlert((res && res.error) || 'Unable to create Job Application');
                    return;
                }
                closeCreateJobApplicationForm();
                var jaId = res.jobApplicationId;
                if (jaId) {
                    openRecordModal(jaId, {
                        recordName: res.recordName || 'Job Application',
                        objectApi: 'Job_Application__c',
                        objectLabel: 'Job Application'
                    });
                }
            })
            .catch(function (err) {
                createJobAppInFlight = false;
                if (saveBtn) {
                    saveBtn.disabled = false;
                }
                updateHeaderActions();
                updateFooter();
                hubAlert(err && err.message ? err.message : String(err));
            });
    }

    function updateFooter() {
        if (!footerEl) {
            return;
        }
        var n = countChangedFields();
        var status = footerEl.querySelector('.crm-rm-footer-status');
        var editBtn = footerEl.querySelector('.crm-rm-edit');
        var cancelBtn = footerEl.querySelector('.crm-rm-cancel');
        var saveBtn = footerEl.querySelector('.crm-rm-save');
        var createJaBtn = footerEl.querySelector('.crm-rm-create-ja');
        var showCreateJa =
            supportsCreateJobApplication((currentModalData && currentModalData.objectApi) || '') &&
            !editMode;
        if (status) {
            if (!canEditRecord && !showCreateJa) {
                status.textContent = '';
            } else if (!editMode) {
                status.textContent = 'Viewing record';
            } else if (n > 0) {
                status.textContent = n + ' unsaved change' + (n === 1 ? '' : 's');
            } else {
                status.textContent = 'Editing — no unsaved changes';
            }
        }
        if (createJaBtn) {
            createJaBtn.style.display = 'none';
        }
        var deleteBtn = footerEl.querySelector('.crm-rm-delete');
        var cloneBtn = footerEl.querySelector('.crm-rm-clone');
        var showDelete = hasRecordAction('Delete') && !editMode;
        var showClone = hasRecordAction('Clone') && !editMode;
        if (deleteBtn) {
            deleteBtn.style.display = showDelete ? 'inline-block' : 'none';
        }
        if (cloneBtn) {
            cloneBtn.style.display = showClone ? 'inline-block' : 'none';
        }
        if (editBtn) {
            editBtn.style.display = (canEditRecord || hasRecordAction('Edit')) && !editMode ? 'inline-block' : 'none';
        }
        if (cancelBtn) {
            cancelBtn.style.display = editMode ? 'inline-block' : 'none';
        }
        if (saveBtn) {
            saveBtn.style.display = editMode ? 'inline-block' : 'none';
            saveBtn.disabled = n === 0;
        }
        footerEl.style.display = canEditRecord || showDelete || showClone || (recordActions && recordActions.length) ? 'flex' : 'none';
        footerEl.classList.toggle('is-editing', editMode);
        updateHeaderActions();
    }

    function refreshDetailsPanelOnly() {
        if (!currentModalData || !bodyEl) {
            return;
        }
        var panel = bodyEl.querySelector('.crm-rm-panel[data-tab-id="' + activeTabId + '"]');
        var detailsTab = tabById(activeTabId);
        if (!panel || !detailsTab || detailsTab.type !== 'details') {
            var detailsPanel = bodyEl.querySelector('.crm-rm-panel[data-tab-id]');
            for (var i = 0; i < (currentModalData.tabs || []).length; i++) {
                if (currentModalData.tabs[i].type === 'details') {
                    panel = bodyEl.querySelector(
                        '.crm-rm-panel[data-tab-id="' + currentModalData.tabs[i].id + '"]'
                    );
                    break;
                }
            }
        }
        if (!panel) {
            return;
        }
        destroyOwnerLookups();
        panel.innerHTML = renderDetailsPanel(
            currentModalData.layout,
            draftValues,
            currentModalData.fieldMeta || {}
        );
        wireDetailsPanelInputs(panel);
        wireOwnerLookups(panel);
    }

    function destroyOwnerLookups() {
        destroyRefLookups();
    }

    function destroyRefLookups() {
        var all = ownerLookupInstances.concat(refLookupInstances);
        for (var i = 0; i < all.length; i++) {
            if (all[i] && typeof all[i].destroy === 'function') {
                all[i].destroy();
            }
        }
        ownerLookupInstances = [];
        refLookupInstances = [];
    }

    function resolveLookupObjectApi(fieldApi, meta) {
        if (String(fieldApi || '') === 'OwnerId') {
            return 'User';
        }
        var refs = (meta && meta.referenceTo) || [];
        if (!refs || !refs.length) {
            return null;
        }
        var prefer = ['Contact', 'Account', 'Lead', 'User', 'Opportunity', 'Position__c'];
        for (var i = 0; i < prefer.length; i++) {
            for (var j = 0; j < refs.length; j++) {
                if (String(refs[j]) === prefer[i]) {
                    return prefer[i];
                }
            }
        }
        return String(refs[0]);
    }

    function lookupDisplayName(fieldApi, values, meta) {
        var rel = meta && meta.relationshipName ? String(meta.relationshipName) : '';
        if (rel && values[rel + '.Name'] != null && values[rel + '.Name'] !== '') {
            return String(values[rel + '.Name']);
        }
        if (rel) {
            var want = String(rel + '.Name').toLowerCase();
            for (var vk in values) {
                if (
                    Object.prototype.hasOwnProperty.call(values, vk) &&
                    String(vk).toLowerCase() === want &&
                    values[vk] != null &&
                    values[vk] !== ''
                ) {
                    return String(values[vk]);
                }
            }
        }
        if (fieldApi === 'OwnerId' && values['Owner.Name']) {
            return String(values['Owner.Name']);
        }
        return values[fieldApi] != null ? String(values[fieldApi]) : '';
    }

    function wireOwnerLookups(panel) {
        wireRefLookups(panel);
    }

    function wireRefLookups(panel) {
        if (!panel || !global.CrmHubLookup || typeof global.CrmHubLookup.mount !== 'function') {
            return;
        }
        var hosts = panel.querySelectorAll('.crm-rm-ref-lookup, .crm-rm-owner-lookup');
        for (var i = 0; i < hosts.length; i++) {
            (function (host) {
                var fieldApi = host.getAttribute('data-field-api') || '';
                var objectApi = host.getAttribute('data-ref-object') || '';
                if (!fieldApi || !objectApi) {
                    return;
                }
                var refId =
                    host.getAttribute('data-ref-id') ||
                    host.getAttribute('data-owner-id') ||
                    '';
                var refName =
                    host.getAttribute('data-ref-name') ||
                    host.getAttribute('data-owner-name') ||
                    refId;
                var relName = host.getAttribute('data-relationship') || '';
                var initial =
                    refId
                        ? { id: refId, name: decodeHtmlEntities(refName || refId) }
                        : null;
                var placeholder =
                    objectApi === 'User'
                        ? 'Search users…'
                        : 'Search ' + objectApi.replace(/__c$/, '').replace(/_/g, ' ') + '…';
                var iconLetters =
                    objectApi === 'User'
                        ? 'U'
                        : objectApi === 'Contact'
                          ? 'C'
                          : objectApi === 'Account'
                            ? 'A'
                            : objectApi.substring(0, 2).toUpperCase();
                var api = global.CrmHubLookup.mount(host, {
                    objectApi: objectApi,
                    value: initial,
                    placeholder: placeholder,
                    iconLetters: iconLetters,
                    minChars: 1,
                    onChange: function (sel) {
                        draftValues[fieldApi] = sel && sel.id ? sel.id : null;
                        if (relName) {
                            draftValues[relName + '.Name'] =
                                sel && sel.name ? sel.name : sel && sel.id ? sel.id : null;
                        }
                        if (fieldApi === 'OwnerId') {
                            draftValues['Owner.Name'] =
                                sel && sel.name ? sel.name : sel && sel.id ? sel.id : null;
                        }
                        host.setAttribute('data-ref-id', sel && sel.id ? sel.id : '');
                        host.setAttribute(
                            'data-ref-name',
                            sel && sel.name ? sel.name : sel && sel.id ? sel.id : ''
                        );
                        host.setAttribute('data-owner-id', sel && sel.id ? sel.id : '');
                        host.setAttribute(
                            'data-owner-name',
                            sel && sel.name ? sel.name : sel && sel.id ? sel.id : ''
                        );
                        var fieldEl = host.closest('.crm-rm-field');
                        if (fieldEl) {
                            fieldEl.classList.toggle(
                                'is-changed',
                                fieldHasChanged(fieldApi, 'reference')
                            );
                            var hint = fieldEl.querySelector('.crm-rm-change-hint');
                            if (hint) {
                                var oldDisp = formatScalarValue(
                                    'reference',
                                    originalValues[fieldApi],
                                    {
                                        relationshipName:
                                            relName || (fieldApi === 'OwnerId' ? 'Owner' : '')
                                    }
                                );
                                hint.textContent = fieldHasChanged(fieldApi, 'reference')
                                    ? 'Was: ' + String(oldDisp)
                                    : '';
                            }
                        }
                        updateFooter();
                    }
                });
                refLookupInstances.push(api);
            })(hosts[i]);
        }
    }

    function wireDetailsPanelInputs(panel) {
        if (!panel) {
            return;
        }
        var inputs = panel.querySelectorAll('[data-field-api]');
        for (var i = 0; i < inputs.length; i++) {
            (function (inp) {
                if (
                    inp.classList &&
                    (inp.classList.contains('crm-rm-owner-lookup') ||
                        inp.classList.contains('crm-rm-ref-lookup'))
                ) {
                    return;
                }
                var handler = function () {
                    handleDraftInput(inp);
                };
                inp.addEventListener('input', handler);
                inp.addEventListener('change', handler);
            })(inputs[i]);
        }
    }

    function handleDraftInput(inp) {
        var fieldApi = inp.getAttribute('data-field-api');
        if (!fieldApi) {
            return;
        }
        var type = inp.getAttribute('data-field-type') || '';
        if (type === 'boolean') {
            draftValues[fieldApi] = inp.checked;
            var boolSpan = inp.parentNode && inp.parentNode.querySelector('span');
            if (boolSpan) {
                boolSpan.textContent = inp.checked ? 'Yes' : 'No';
            }
        } else if (type === 'multipicklist' && inp.tagName === 'SELECT' && inp.multiple) {
            var selected = [];
            for (var oi = 0; oi < inp.options.length; oi++) {
                if (inp.options[oi].selected && inp.options[oi].value) {
                    selected.push(inp.options[oi].value);
                }
            }
            draftValues[fieldApi] = selected.join(';');
        } else {
            draftValues[fieldApi] = inp.value;
        }
        var fieldEl = inp.closest('.crm-rm-field');
        if (fieldEl) {
            fieldEl.classList.toggle('is-changed', fieldHasChanged(fieldApi, type));
            var hint = fieldEl.querySelector('.crm-rm-change-hint');
            if (hint) {
                var oldDisp = formatScalarValue(type, originalValues[fieldApi], {});
                hint.textContent = fieldHasChanged(fieldApi, type) ? 'Was: ' + oldDisp : '';
            }
        }
        updateFooter();
    }

    function saveDraft() {
        var changed = getChangedFieldsOnly();
        if (!currentRecordId || !Object.keys(changed).length) {
            return;
        }
        var saveBtn = footerEl ? footerEl.querySelector('.crm-rm-save') : null;
        if (saveBtn) {
            saveBtn.disabled = true;
            saveBtn.textContent = 'Saving…';
        }
        remotingUpdateRecordFields(currentRecordId, changed)
            .then(function (res) {
                if (res.error) {
                    hubAlert(res.error);
                    return;
                }
                var data = ensureModalData();
                var refreshed = res.values || {};
                for (var k in refreshed) {
                    if (Object.prototype.hasOwnProperty.call(refreshed, k)) {
                        data.values[k] = refreshed[k];
                    }
                }
                for (var c in changed) {
                    if (Object.prototype.hasOwnProperty.call(changed, c) && refreshed[c] === undefined) {
                        data.values[c] = changed[c];
                    }
                }
                initDraftState(data.values);
                editMode = false;
                refreshDetailsPanelOnly();
                updateFooter();
            })
            .catch(function (err) {
                hubAlert(err && err.message ? err.message : String(err));
            })
            .then(function () {
                if (saveBtn) {
                    saveBtn.disabled = countChangedFields() === 0;
                    saveBtn.textContent = 'Save';
                }
            });
    }

    function inputValueForField(fieldApi, type, raw, meta) {
        if (raw === null || raw === undefined || raw === '') {
            return '';
        }
        var t = (type || '').toLowerCase();
        if (t === 'boolean') {
            return raw === true || raw === 'true' || raw === 'Yes' || raw === '1';
        }
        if (t === 'date') {
            if (typeof raw === 'string' && /^\d{4}-\d{2}-\d{2}/.test(raw)) {
                return raw.substring(0, 10);
            }
            var d = new Date(raw);
            if (!isNaN(d.getTime())) {
                return d.toISOString().substring(0, 10);
            }
            return String(raw);
        }
        if (t === 'datetime') {
            if (typeof raw === 'string' && raw.indexOf('T') >= 0) {
                return raw.length >= 16 ? raw.substring(0, 16) : raw;
            }
            var dt = new Date(raw);
            if (!isNaN(dt.getTime())) {
                var pad = function (n) {
                    return n < 10 ? '0' + n : String(n);
                };
                return (
                    dt.getFullYear() +
                    '-' +
                    pad(dt.getMonth() + 1) +
                    '-' +
                    pad(dt.getDate()) +
                    'T' +
                    pad(dt.getHours()) +
                    ':' +
                    pad(dt.getMinutes())
                );
            }
            return String(raw);
        }
        return String(raw);
    }

    function resolveFieldMeta(fieldApi, meta) {
        if (!meta || !fieldApi) {
            return {};
        }
        if (meta[fieldApi]) {
            return meta[fieldApi];
        }
        var lower = String(fieldApi).toLowerCase();
        for (var k in meta) {
            if (Object.prototype.hasOwnProperty.call(meta, k) && String(k).toLowerCase() === lower) {
                return meta[k];
            }
        }
        return {};
    }

    function isOwnerLookupField(fieldApi) {
        return String(fieldApi || '') === 'OwnerId';
    }

    function fieldEditableInModal(fieldApi, details, meta) {
        var m = resolveFieldMeta(fieldApi, meta);
        var merged = Object.assign({}, details || {}, m);
        if (merged.calculated === true || merged.readOnly === true) {
            return false;
        }
        var type = (merged.type || '').toLowerCase();
        if (type === 'reference') {
            if (merged.updateable === false) {
                return false;
            }
            return !!resolveLookupObjectApi(fieldApi, merged);
        }
        if (
            type === 'address' ||
            type === 'location' ||
            type === 'id' ||
            fieldApi === 'Id'
        ) {
            return false;
        }
        // Prefer Apex updateable flag; if missing (old payload / case mismatch), allow simple types.
        if (merged.updateable === false) {
            return false;
        }
        if (merged.updateable !== true) {
            var simple =
                !type ||
                type === 'string' ||
                type === 'phone' ||
                type === 'email' ||
                type === 'url' ||
                type === 'double' ||
                type === 'currency' ||
                type === 'percent' ||
                type === 'int' ||
                type === 'boolean' ||
                type === 'picklist' ||
                type === 'multipicklist' ||
                type === 'date' ||
                type === 'datetime' ||
                type === 'textarea';
            if (!simple) {
                return false;
            }
        }
        return true;
    }

    function renderFieldInput(fieldApi, details, values, meta) {
        var m = meta[fieldApi] || {};
        var merged = Object.assign({}, details || {}, m);
        var type = (merged.type || 'string').toLowerCase();
        var raw = values[fieldApi];
        var val = inputValueForField(fieldApi, type, raw, merged);
        var common =
            ' class="crm-rm-input slds-input" data-field-api="' +
            esc(fieldApi) +
            '" data-field-type="' +
            esc(type) +
            '"';

        if (type === 'boolean') {
            var checked = val ? ' checked' : '';
            return (
                '<label class="crm-rm-bool-lbl"><input type="checkbox" class="crm-rm-check" data-field-api="' +
                esc(fieldApi) +
                '" data-field-type="boolean"' +
                checked +
                ' /><span>' +
                (val ? 'Yes' : 'No') +
                '</span></label>'
            );
        }
        if (type === 'picklist') {
            var opts = merged.picklistValues || [];
            var sb = ['<select' + common + '>'];
            sb.push('<option value=""></option>');
            for (var i = 0; i < opts.length; i++) {
                var pv = String(opts[i]);
                sb.push(
                    '<option value="' +
                        esc(pv) +
                        '"' +
                        (String(val) === pv ? ' selected' : '') +
                        '>' +
                        esc(pv) +
                        '</option>'
                );
            }
            sb.push('</select>');
            return sb.join('');
        }
        if (type === 'multipicklist') {
            var multiOpts = merged.picklistValues || [];
            var selectedSet = {};
            String(val || '')
                .split(';')
                .forEach(function (part) {
                    var trimmed = part.trim();
                    if (trimmed) {
                        selectedSet[trimmed] = true;
                    }
                });
            var size = Math.min(Math.max(multiOpts.length, 3), 8);
            var msb = [
                '<select' + common + ' multiple size="' + size + '" title="Hold Ctrl/Cmd to select multiple">'
            ];
            for (var mi = 0; mi < multiOpts.length; mi++) {
                var mpv = String(multiOpts[mi]);
                msb.push(
                    '<option value="' +
                        esc(mpv) +
                        '"' +
                        (selectedSet[mpv] ? ' selected' : '') +
                        '>' +
                        esc(mpv) +
                        '</option>'
                );
            }
            msb.push('</select>');
            return msb.join('');
        }
        if (type === 'textarea') {
            var isRich =
                merged.htmlFormatted === true ||
                merged.extraTypeInfo === 'richtext' ||
                merged.extraTypeInfo === 'richtextarea' ||
                String(merged.extraTypeInfo || '').toLowerCase().indexOf('rich') >= 0;
            var rows = isRich || (merged.length && Number(merged.length) > 255) ? 6 : 3;
            var richHint = isRich
                ? '<div class="crm-rm-rich-hint">Rich text — HTML markup is preserved on save</div>'
                : '';
            var textareaVal = String(val == null ? '' : val);
            if (!isRich) {
                textareaVal = decodeHtmlEntities(textareaVal);
            }
            return (
                '<textarea' +
                common +
                ' rows="' +
                rows +
                '">' +
                esc(textareaVal) +
                '</textarea>' +
                richHint
            );
        }
        if (type === 'date') {
            return '<input type="date"' + common + ' value="' + esc(String(val)) + '" />';
        }
        if (type === 'datetime') {
            return '<input type="datetime-local"' + common + ' value="' + esc(String(val)) + '" />';
        }
        if (type === 'double' || type === 'currency' || type === 'percent') {
            return '<input type="number" step="any"' + common + ' value="' + esc(String(val)) + '" />';
        }
        if (type === 'reference') {
            var objectApi = resolveLookupObjectApi(fieldApi, merged);
            if (!objectApi) {
                return '<span class="crm-rm-muted">—</span>';
            }
            var refId = raw == null ? '' : String(raw);
            var refName = lookupDisplayName(fieldApi, values, merged) || refId;
            var rel = merged.relationshipName ? String(merged.relationshipName) : '';
            return (
                '<div class="crm-rm-ref-lookup' +
                (isOwnerLookupField(fieldApi) ? ' crm-rm-owner-lookup' : '') +
                '" data-field-api="' +
                esc(fieldApi) +
                '" data-field-type="reference" data-ref-object="' +
                esc(objectApi) +
                '" data-ref-id="' +
                esc(refId) +
                '" data-ref-name="' +
                esc(refName) +
                '" data-relationship="' +
                esc(rel) +
                '" data-owner-id="' +
                esc(refId) +
                '" data-owner-name="' +
                esc(refName) +
                '"></div>'
            );
        }
        var inputType = type === 'email' ? 'email' : type === 'url' ? 'url' : type === 'phone' ? 'tel' : 'text';
        return (
            '<input type="' +
            inputType +
            '"' +
            common +
            ' value="' +
            escPlain(val == null ? '' : val) +
            '" />'
        );
    }

    function injectStyles() {
        if (document.getElementById('crm-hub-record-modal-css')) {
            return;
        }
        var style = document.createElement('style');
        style.id = 'crm-hub-record-modal-css';
        style.textContent =
            '.crm-rm-overlay{position:fixed;inset:0;z-index:10000;background:rgba(15,23,42,.45);display:flex;align-items:stretch;justify-content:center;padding:env(safe-area-inset-top,0) max(.5rem,env(safe-area-inset-right)) max(.5rem,env(safe-area-inset-bottom)) max(.5rem,env(safe-area-inset-left))}' +
            '.crm-rm-inner{width:100%;max-width:1040px;background:#fff;border-radius:14px;margin:.5rem 0;display:flex;flex-direction:column;overflow:hidden;box-shadow:0 20px 56px rgba(15,23,42,.2);font-family:"Salesforce Sans",-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}' +
            '@media (prefers-color-scheme:dark){.crm-rm-inner{background:#1c1c1e;color:#f2f2f7}}' +
            '.crm-rm-header{flex:0 0 auto;display:flex;align-items:flex-start;justify-content:space-between;gap:.75rem;padding:1rem 1.25rem .75rem;border-bottom:1px solid #ecebea;background:#fff}' +
            '.crm-rm-header-main{display:flex;align-items:flex-start;gap:.7rem;min-width:0;flex:1 1 auto}' +
            '.crm-rm-header-right{display:flex;align-items:flex-start;gap:.5rem;flex:0 0 auto}' +
            '.crm-rm-header-actions{display:flex;flex-wrap:wrap;align-items:center;justify-content:flex-end;gap:.4rem;max-width:min(28rem,52vw)}' +
            '.crm-rm-action-btn{border:1px solid #c9c9c9;background:#fff;color:#0176d3;border-radius:6px;padding:.35rem .75rem;font-size:.75rem;font-weight:600;cursor:pointer;font-family:inherit;white-space:nowrap}' +
            '.crm-rm-action-btn:hover:not(:disabled){background:#f3f9ff;border-color:#0176d3}' +
            '.crm-rm-action-btn:disabled{opacity:.55;cursor:not-allowed}' +
            '.crm-rm-action-btn.is-primary{border-color:#0176d3;background:#0176d3;color:#fff}' +
            '.crm-rm-action-btn.is-primary:hover:not(:disabled){background:#014486;border-color:#014486}' +
            '.crm-rm-icon{width:2.25rem;height:2.25rem;border-radius:8px;background:linear-gradient(135deg,#0176d3,#1b96ff);display:flex;align-items:center;justify-content:center;color:#fff;font-size:.72rem;font-weight:700;flex:0 0 auto;letter-spacing:.02em}' +
            '.crm-rm-title-wrap{min-width:0}' +
            '.crm-rm-title{font-size:1.125rem;font-weight:700;margin:0;letter-spacing:-.01em;line-height:1.3;color:#181818}' +
            '.crm-rm-sub{font-size:.75rem;color:#706e6b;margin-top:.15rem;text-transform:uppercase;letter-spacing:.04em;font-weight:600}' +
            '.crm-rm-close{border:0;background:transparent;font-size:1.35rem;line-height:1;cursor:pointer;padding:.15rem .35rem;border-radius:6px;color:#706e6b}' +
            '.crm-rm-close:hover{background:#f3f3f3;color:#181818}' +
            '.crm-rm-path-wrap{flex:0 0 auto;background:#f8f9fb;border-bottom:1px solid #ecebea;padding:.65rem 1.25rem .75rem}' +
            '.crm-rm-path-label{font-size:.6875rem;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#706e6b;margin:0 0 .45rem}' +
            '.crm-rm-path-track{overflow-x:auto;-webkit-overflow-scrolling:touch;scrollbar-width:thin}' +
            '.crm-rm-path-nav{display:flex;list-style:none;margin:0;padding:0;width:max-content;min-width:100%}' +
            '.crm-rm-path-item{position:relative;flex:1 1 auto;min-width:5.75rem}' +
            '.crm-rm-path-link{display:flex;align-items:center;justify-content:center;min-height:2rem;padding:.35rem .95rem .35rem 1.1rem;background:#e8e8e8;color:#3e3e3c;font-size:.6875rem;font-weight:600;text-align:center;line-height:1.2;clip-path:polygon(0 0,calc(100% - 8px) 0,100% 50%,calc(100% - 8px) 100%,0 100%,8px 50%)}' +
            '.crm-rm-path-item:first-child .crm-rm-path-link{clip-path:polygon(0 0,calc(100% - 8px) 0,100% 50%,calc(100% - 8px) 100%,0 100%);padding-left:.75rem;border-radius:4px 0 0 4px}' +
            '.crm-rm-path-item:last-child .crm-rm-path-link{border-radius:0 4px 4px 0}' +
            '.crm-rm-path-stage{display:inline-flex;align-items:center;justify-content:center;gap:.25rem;max-width:100%}' +
            '.crm-rm-path-title{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;word-break:normal;hyphens:none}' +
            '.crm-rm-path-check{width:.65rem;height:.65rem;flex:0 0 auto;color:#fff}' +
            '.crm-rm-path-item.is-complete .crm-rm-path-link{background:#04844b;color:#fff}' +
            '.crm-rm-path-item.is-current .crm-rm-path-link{background:#0176d3;color:#fff;box-shadow:inset 0 0 0 1px rgba(255,255,255,.25)}' +
            '.crm-rm-path-item.is-upcoming .crm-rm-path-link{background:#e8e8e8;color:#706e6b}' +
            '.crm-rm-path-guidance{margin-top:.55rem;padding:.55rem .7rem;background:#fff;border:1px solid #e5e5e5;border-left:3px solid #0176d3;border-radius:4px;font-size:.8125rem;color:#3e3e3c;line-height:1.45}' +
            '.crm-rm-path-guidance-title{font-size:.6875rem;font-weight:700;text-transform:uppercase;letter-spacing:.04em;color:#0176d3;margin-bottom:.2rem}' +
            '.crm-rm-path-guidance-body.crm-rm-html img{max-width:100%;height:auto;vertical-align:middle}' +
            '.crm-rm-path-guidance-body.crm-rm-html a{color:#0176d3;text-decoration:none}' +
            '.crm-rm-path-guidance-body.crm-rm-html a:hover{text-decoration:underline}' +
            '.crm-rm-tabs-wrap{flex:0 0 auto;border-bottom:1px solid #ecebea;background:#fff;position:sticky;top:0;z-index:2}' +
            '.crm-rm-tabs{display:flex;gap:0;overflow-x:auto;padding:0 1.25rem;-webkit-overflow-scrolling:touch;scrollbar-width:none}' +
            '.crm-rm-tabs::-webkit-scrollbar{display:none}' +
            '.crm-rm-tab{flex:0 0 auto;border:0;background:transparent;padding:.75rem .9rem;font-size:.8125rem;font-weight:600;color:#706e6b;cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-1px;white-space:nowrap;font-family:inherit}' +
            '.crm-rm-tab:hover{color:#0176d3}' +
            '.crm-rm-tab.is-active{color:#0176d3;border-bottom-color:#0176d3}' +
            '.crm-rm-body{flex:1 1 auto;overflow:auto;padding:1.1rem 1.25rem 1.4rem;-webkit-overflow-scrolling:touch;background:#f4f6f9}' +
            '.crm-rm-panel{display:none}' +
            '.crm-rm-panel.is-active{display:block}' +
            '.crm-rm-sec{font-size:.6875rem;font-weight:700;text-transform:uppercase;letter-spacing:.06em;margin:1.35rem 0 .65rem;color:#0176d3}' +
            '.crm-rm-sec:first-child{margin-top:0}' +
            '.crm-rm-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:0;background:#fff;border:1px solid #e5e5e5;border-radius:10px;overflow:hidden;box-shadow:0 1px 2px rgba(15,23,42,.04)}' +
            '.crm-rm-field{min-width:0;padding:.85rem 1rem;background:transparent;border:0;border-bottom:1px solid #f0f0f0;border-right:1px solid #f0f0f0}' +
            '.crm-rm-field:hover{background:#fafbfd}' +
            '.crm-rm-lbl{font-size:.6875rem;text-transform:uppercase;letter-spacing:.04em;color:#706e6b;margin-bottom:.35rem;font-weight:600;line-height:1.3}' +
            '.crm-rm-val{font-size:.875rem;overflow-wrap:anywhere;word-break:normal;line-height:1.45;color:#181818;min-height:1.35rem}' +
            '.crm-rm-val.crm-rm-html img{max-width:100%;height:auto;vertical-align:middle}' +
            '.crm-rm-val.crm-rm-html a{color:#0176d3;text-decoration:none}' +
            '.crm-rm-val.crm-rm-html a:hover{text-decoration:underline}' +
            '.crm-rm-rl-wrap{margin-top:.25rem}' +
            '.crm-rm-rl-table{width:100%;border-collapse:collapse;font-size:.8125rem;background:#fff;border:1px solid #e5e5e5;border-radius:6px;overflow:hidden}' +
            '.crm-rm-rl-table thead{background:#f3f3f3}' +
            '.crm-rm-rl-table th{text-align:left;font-size:.6875rem;text-transform:uppercase;letter-spacing:.04em;color:#706e6b;padding:.5rem .65rem;border-bottom:1px solid #e5e5e5;font-weight:700}' +
            '.crm-rm-rl-table td{padding:.5rem .65rem;border-bottom:1px solid #ecebea;vertical-align:middle;color:#181818}' +
            '.crm-rm-rl-table tbody tr:nth-child(even){background:#fafaf9}' +
            '.crm-rm-rl-table tbody tr:hover{background:#f3f9ff}' +
            '.crm-rm-rl-table tr:last-child td{border-bottom:0}' +
            '.crm-rm-rl-open{width:2.5rem;text-align:center;padding:.25rem!important}' +
            '.crm-rm-rl-menu{width:2rem;text-align:center;padding:.25rem!important}' +
            '.crm-rm-rl-toolbar{display:flex;flex-wrap:wrap;gap:.4rem;margin:.35rem 0 .65rem}' +
            '.crm-rm-rl-row-menu{border:0;background:transparent;color:#706e6b;font-size:1rem;cursor:pointer;padding:.15rem .35rem;border-radius:4px}' +
            '.crm-rm-rl-row-menu:hover{background:#f3f3f3;color:#0176d3}' +
            '.crm-rm-action-menu{position:fixed;z-index:10002;min-width:9rem;background:#fff;border:1px solid #e5e5e5;border-radius:8px;box-shadow:0 8px 24px rgba(15,23,42,.18);padding:.25rem 0}' +
            '.crm-rm-action-menu-item{display:block;width:100%;text-align:left;border:0;background:transparent;padding:.45rem .75rem;font-size:.8125rem;cursor:pointer;font-family:inherit;color:#181818}' +
            '.crm-rm-action-menu-item:hover{background:#f3f9ff;color:#0176d3}' +
            '.crm-rm-delete{border:0;background:#ba0517;color:#fff;border-radius:6px;padding:.4rem .95rem;font-size:.8125rem;font-weight:600;cursor:pointer;font-family:inherit;margin-right:.35rem}' +
            '.crm-rm-clone{border:1px solid #c9c9c9;background:#fff;color:#0176d3;border-radius:6px;padding:.4rem .95rem;font-size:.8125rem;font-weight:600;cursor:pointer;font-family:inherit;margin-right:.35rem}' +
            '.crm-rm-dup-group{margin-bottom:1rem}' +
            '.crm-rm-dup-banner{font-size:.8125rem;color:#0176d3;margin:0 0 .65rem}' +
            '.crm-rm-dup-cards{display:flex;flex-direction:column;gap:.5rem}' +
            '.crm-rm-dup-card{border:1px solid #e5e5e5;border-radius:10px;padding:.75rem;background:#fff}' +
            '.crm-rm-dup-card.is-winner{border-color:#04844b;box-shadow:0 0 0 1px rgba(4,132,75,.15)}' +
            '.crm-rm-dup-card-head{display:flex;flex-wrap:wrap;align-items:center;gap:.4rem;margin-bottom:.45rem}' +
            '.crm-rm-dup-name{border:0;background:transparent;color:#0176d3;font-weight:700;font-size:.9rem;cursor:pointer;padding:0;font-family:inherit}' +
            '.crm-rm-dup-winner{font-size:.68rem;font-weight:700;text-transform:uppercase;letter-spacing:.04em;color:#04844b;background:rgba(4,132,75,.1);padding:.15rem .45rem;border-radius:999px}' +
            '.crm-rm-dup-current{font-size:.68rem;font-weight:700;color:#706e6b;background:#f3f3f3;padding:.15rem .45rem;border-radius:999px}' +
            '.crm-rm-dup-score{display:flex;align-items:center;gap:.65rem}' +
            '.crm-rm-dup-meta{font-size:.75rem;color:#706e6b}' +
            '.crm-rm-iframe-overlay{position:fixed;inset:0;z-index:10003;background:rgba(15,23,42,.5);display:flex;align-items:center;justify-content:center;padding:1rem}' +
            '.crm-rm-iframe-inner{width:min(920px,100%);height:min(80vh,720px);background:#fff;border-radius:12px;display:flex;flex-direction:column;overflow:hidden}' +
            '.crm-rm-iframe-head{display:flex;align-items:center;justify-content:space-between;padding:.65rem 1rem;border-bottom:1px solid #ecebea}' +
            '.crm-rm-iframe{flex:1;border:0;width:100%}' +
            '.crm-rm-open.ch-open-ico{width:1.85rem;height:1.85rem;min-width:1.85rem;min-height:1.85rem;padding:.15rem;border-radius:6px;border:1px solid #c9c9c9;background:#fff;display:inline-flex;align-items:center;justify-content:center;cursor:pointer}' +
            '.crm-rm-open.ch-open-ico:hover{background:#f3f9ff;border-color:#0176d3}' +
            '.crm-rm-muted{font-size:.8125rem;color:#706e6b;margin:.35rem 0 0;padding:1.5rem;text-align:center}' +
            '.crm-rm-custom{padding:2rem 1rem;text-align:center;color:#706e6b;font-size:.875rem}' +
            '.crm-rm-custom-title{font-size:1rem;font-weight:700;color:#181818;margin-bottom:.5rem}' +
            '.crm-rm-custom-msg{line-height:1.5;max-width:28rem;margin:0 auto}' +
            '.crm-rm-power{margin:-.25rem;border-radius:10px;overflow:hidden;background:#111827;min-height:42rem}' +
            '.crm-rm-power-iframe{width:100%;height:52rem;border:0;display:block;background:#f9fafb}' +
            '.crm-rm-loading,.crm-rm-error{padding:2rem 1.5rem;text-align:center}' +
            '.crm-rm-tab-loading{padding:2rem 1rem;text-align:center;color:#706e6b;font-size:.8125rem}' +
            '.crm-rm-error{color:#ba0517}' +
            '.crm-rm-ref-btn{border:0;background:none;padding:0;color:inherit;cursor:pointer;font:inherit;text-align:left;text-decoration:underline;text-underline-offset:0.12em}' +
            '.crm-rm-ref-btn:hover{color:#0176d3}' +
            '.crm-rm-ref-btn:focus{outline:none;box-shadow:0 0 0 2px rgba(1,118,211,.28);border-radius:2px}' +
            '.crm-rm-rl-actions{display:flex;align-items:center;justify-content:space-between;gap:.75rem;margin:.35rem 0 .5rem}' +
            '.crm-rm-rl-viewall{border:1px solid #c9c9c9;background:#fff;color:#0176d3;border-radius:6px;padding:.35rem .7rem;font-size:.75rem;font-weight:600;cursor:pointer;font-family:inherit}' +
            '.crm-rm-rl-viewall:hover{background:#f3f9ff;border-color:#0176d3}' +
            '.crm-rm-viewall-overlay{position:fixed;inset:0;z-index:10001;background:rgba(15,23,42,.5);display:flex;align-items:center;justify-content:center;padding:1rem}' +
            '.crm-rm-viewall-inner{width:100%;max-width:920px;max-height:85vh;background:#fff;border-radius:12px;display:flex;flex-direction:column;overflow:hidden;box-shadow:0 16px 48px rgba(15,23,42,.22)}' +
            '.crm-rm-viewall-header{display:flex;align-items:center;justify-content:space-between;gap:.75rem;padding:.85rem 1rem;border-bottom:1px solid #e5e5e5}' +
            '.crm-rm-viewall-title{font-size:1rem;font-weight:700;margin:0;color:#181818}' +
            '.crm-rm-viewall-body{flex:1 1 auto;overflow:auto;padding:1rem}' +
            '.crm-rm-footer{flex:0 0 auto;display:none;align-items:center;justify-content:space-between;gap:.75rem;padding:.75rem 1.25rem;border-top:1px solid #ecebea;background:#fff}' +
            '.crm-rm-footer.is-editing{background:#f3f9ff;border-top-color:#cce4f6}' +
            '.crm-rm-footer-status{font-size:.8125rem;color:#706e6b;font-weight:600}' +
            '.crm-rm-footer-actions{display:flex;flex-wrap:wrap;gap:.5rem;align-items:center;justify-content:flex-end}' +
            '.crm-rm-footer-primary{display:flex;flex-wrap:wrap;gap:.45rem;align-items:center}' +
            '.crm-rm-edit{border:0;background:#0176d3;color:#fff;border-radius:6px;padding:.4rem .95rem;font-size:.8125rem;font-weight:600;cursor:pointer;font-family:inherit}' +
            '.crm-rm-edit:hover{background:#014486}' +
            '.crm-rm-create-ja{border:1px solid #0176d3;background:#fff;color:#0176d3;border-radius:6px;padding:.4rem .85rem;font-size:.8125rem;font-weight:600;cursor:pointer;font-family:inherit}' +
            '.crm-rm-create-ja:hover:not(:disabled){background:#f3f9ff}' +
            '.crm-rm-create-ja:disabled{opacity:.55;cursor:not-allowed}' +
            '.crm-rm-cancel{border:1px solid #c9c9c9;background:#fff;color:#3e3e3c;border-radius:6px;padding:.4rem .85rem;font-size:.8125rem;font-weight:600;cursor:pointer;font-family:inherit}' +
            '.crm-rm-cancel:hover{background:#f3f3f3}' +
            '.crm-rm-save{border:0;background:#0176d3;color:#fff;border-radius:6px;padding:.4rem .95rem;font-size:.8125rem;font-weight:600;cursor:pointer;font-family:inherit}' +
            '.crm-rm-save:disabled{opacity:.45;cursor:not-allowed}' +
            '.crm-rm-save:not(:disabled):hover{background:#014486}' +
            '.crm-rm-field.is-changed{background:#fffbeb;box-shadow:inset 3px 0 0 #f59e0b}' +
            '.crm-rm-change-hint{font-size:.6875rem;color:#b45309;margin-top:.25rem;font-style:italic}' +
            '.crm-rm-input{width:100%;max-width:100%;font-size:.875rem;font-family:inherit;border:1px solid #c9c9c9;border-radius:6px;padding:.4rem .55rem;box-sizing:border-box;background:#fff;color:#181818;line-height:1.35}' +
            'select.crm-rm-input{appearance:auto;cursor:pointer}' +
            'select.crm-rm-input[multiple]{min-height:6.5rem;padding:.35rem}' +
            'textarea.crm-rm-input{resize:vertical;min-height:4.5rem}' +
            '.crm-rm-rich-hint{font-size:.6875rem;color:#706e6b;margin-top:.25rem}' +
            '.crm-rm-input:focus{outline:none;border-color:#0176d3;box-shadow:0 0 0 1px #0176d3}' +
            '.crm-rm-bool-lbl{display:inline-flex;align-items:center;gap:.45rem;font-size:.875rem;cursor:pointer;white-space:nowrap;max-width:100%}' +
            '.crm-rm-check,.crm-rm-bool-lbl input[type=checkbox]{width:1rem;height:1rem;min-width:1rem;max-width:1rem;margin:0;padding:0;flex:0 0 auto;accent-color:#0176d3;cursor:pointer;border-radius:3px;box-sizing:border-box}' +
            '.crm-rm-bool-lbl span{flex:0 1 auto;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
            '.crm-rm-act{display:flex;flex-direction:column;gap:.85rem}' +
            '.crm-rm-act-composer{background:#fff;border:1px solid #e5e5e5;border-radius:8px;padding:.75rem .85rem}' +
            '.crm-rm-act-composer-tabs{display:flex;gap:.35rem;flex-wrap:wrap;margin-bottom:.65rem}' +
            '.crm-rm-act-type{border:1px solid #c9c9c9;background:#fff;color:#3e3e3c;border-radius:6px;padding:.3rem .65rem;font-size:.75rem;font-weight:600;cursor:pointer;font-family:inherit}' +
            '.crm-rm-act-type.is-active{background:#0176d3;border-color:#0176d3;color:#fff}' +
            '.crm-rm-act-fields{display:grid;grid-template-columns:1fr 1fr;gap:.55rem}' +
            '.crm-rm-act-fields .crm-rm-act-full{grid-column:1/-1}' +
            '.crm-rm-act-lbl{display:block;font-size:.6875rem;font-weight:600;text-transform:uppercase;letter-spacing:.04em;color:#706e6b;margin-bottom:.2rem}' +
            '.crm-rm-act-actions{display:flex;align-items:center;justify-content:space-between;gap:.75rem;margin-top:.65rem}' +
            '.crm-rm-act-msg{font-size:.75rem;color:#706e6b;min-height:1rem}' +
            '.crm-rm-act-msg.is-error{color:#ba0517}' +
            '.crm-rm-act-msg.is-ok{color:#04844b}' +
            '.crm-rm-act-save{border:0;background:#0176d3;color:#fff;border-radius:6px;padding:.4rem .9rem;font-size:.8125rem;font-weight:600;cursor:pointer;font-family:inherit}' +
            '.crm-rm-act-save:disabled{opacity:.45;cursor:not-allowed}' +
            '.crm-rm-act-section{font-size:.6875rem;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#0176d3;margin:.35rem 0}' +
            '.crm-rm-act-list{display:flex;flex-direction:column;gap:.55rem}' +
            '.crm-rm-act-item{display:flex;gap:.7rem;align-items:flex-start;background:#fff;border:1px solid #e5e5e5;border-radius:8px;padding:.7rem .8rem}' +
            '.crm-rm-act-ico{width:2rem;height:2rem;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:.65rem;font-weight:700;color:#fff;flex:0 0 auto;letter-spacing:.02em}' +
            '.crm-rm-act-ico.is-task{background:#0176d3}' +
            '.crm-rm-act-ico.is-call{background:#2e844a}' +
            '.crm-rm-act-ico.is-event{background:#8b5cf6}' +
            '.crm-rm-act-main{min-width:0;flex:1 1 auto}' +
            '.crm-rm-act-subject{font-size:.875rem;font-weight:700;color:#181818;line-height:1.35}' +
            '.crm-rm-act-meta{font-size:.75rem;color:#706e6b;margin-top:.15rem;line-height:1.4}' +
            '.crm-rm-act-desc{font-size:.8125rem;color:#3e3e3c;margin-top:.35rem;white-space:pre-wrap;word-break:break-word}' +
            '.crm-rm-act-complete{border:1px solid #c9c9c9;background:#fff;color:#0176d3;border-radius:6px;padding:.25rem .55rem;font-size:.6875rem;font-weight:600;cursor:pointer;font-family:inherit;flex:0 0 auto}' +
            '.crm-rm-act-complete:hover{background:#f3f9ff;border-color:#0176d3}' +
            '.crm-rm-act-empty{padding:1.25rem;text-align:center;color:#706e6b;font-size:.8125rem;background:#fff;border:1px dashed #d8d8d8;border-radius:8px}' +
            '@media (max-width:640px){.crm-rm-act-fields{grid-template-columns:1fr}}' +
            '.crm-rm-createja-overlay{position:fixed;inset:0;z-index:10050;background:rgba(15,23,42,.5);display:flex;align-items:center;justify-content:center;padding:1rem}' +
            '.crm-rm-createja-inner{width:100%;max-width:560px;background:#fff;border-radius:12px;box-shadow:0 16px 48px rgba(15,23,42,.24);font-family:"Salesforce Sans",-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;overflow:hidden}' +
            '.crm-rm-createja-header{display:flex;align-items:center;justify-content:center;position:relative;padding:1rem 2.5rem .35rem;border-bottom:0}' +
            '.crm-rm-createja-title{margin:0;font-size:1.125rem;font-weight:700;color:#181818;text-align:center}' +
            '.crm-rm-createja-close{position:absolute;right:.65rem;top:.55rem;border:0;background:#0176d3;color:#fff;width:1.75rem;height:1.75rem;border-radius:50%;font-size:1.15rem;line-height:1;cursor:pointer;display:inline-flex;align-items:center;justify-content:center}' +
            '.crm-rm-createja-close:hover{background:#014486}' +
            '.crm-rm-createja-req{text-align:right;color:#ba0517;font-size:.75rem;padding:0 1.15rem .35rem}' +
            '.crm-rm-createja-body{padding:.35rem 1.15rem 1rem}' +
            '.crm-rm-createja-grid{display:grid;grid-template-columns:1fr 1fr;gap:.85rem 1.15rem}' +
            '.crm-rm-createja-col{display:flex;flex-direction:column;gap:.85rem;min-width:0}' +
            '.crm-rm-createja-field{min-width:0}' +
            '.crm-rm-createja-lbl{font-size:.75rem;font-weight:600;color:#3e3e3c;margin-bottom:.3rem}' +
            '.crm-rm-createja-readonly{font-size:.875rem;color:#181818;min-height:1.35rem;padding:.15rem 0}' +
            '.crm-rm-createja-footer{display:flex;justify-content:flex-end;gap:.5rem;padding:.75rem 1.15rem 1rem;border-top:1px solid #ecebea;background:#fafaf9}' +
            '.crm-rm-createja-cancel{border:1px solid #0176d3;background:#fff;color:#0176d3;border-radius:6px;padding:.4rem .9rem;font-size:.8125rem;font-weight:600;cursor:pointer;font-family:inherit}' +
            '.crm-rm-createja-cancel:hover{background:#f3f9ff}' +
            '.crm-rm-createja-save{border:0;background:#0176d3;color:#fff;border-radius:6px;padding:.4rem .95rem;font-size:.8125rem;font-weight:600;cursor:pointer;font-family:inherit}' +
            '.crm-rm-createja-save:hover:not(:disabled){background:#014486}' +
            '.crm-rm-createja-save:disabled{opacity:.45;cursor:not-allowed}' +
            '@media (max-width:640px){.crm-rm-createja-grid{grid-template-columns:1fr}}' +
            '.crm-hub-dialog-overlay{position:fixed;inset:0;z-index:10090;background:rgba(15,23,42,.55);display:flex;align-items:center;justify-content:center;padding:1rem;animation:crmHubDlgFade .16s ease-out}' +
            '@keyframes crmHubDlgFade{from{opacity:0}to{opacity:1}}' +
            '@keyframes crmHubDlgPop{from{opacity:0;transform:translateY(8px) scale(.97)}to{opacity:1;transform:none}}' +
            '.crm-hub-dialog{width:100%;max-width:22.5rem;background:#fff;border-radius:14px;box-shadow:0 20px 56px rgba(15,23,42,.28);padding:1.25rem 1.25rem 1.1rem;font-family:"Salesforce Sans",-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;animation:crmHubDlgPop .18s ease-out;display:flex;flex-direction:column;align-items:center;text-align:center;gap:.85rem}' +
            '.crm-hub-dialog-icon{width:2.75rem;height:2.75rem;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;font-size:1.25rem;font-weight:700;flex:0 0 auto;line-height:1}' +
            '.crm-hub-dialog-overlay.is-error .crm-hub-dialog-icon{background:#fef1ee;color:#ba0517}' +
            '.crm-hub-dialog-overlay.is-confirm .crm-hub-dialog-icon{background:#fff4e5;color:#a86403}' +
            '.crm-hub-dialog-overlay.is-info .crm-hub-dialog-icon{background:#eef4ff;color:#0176d3}' +
            '.crm-hub-dialog-overlay.is-success .crm-hub-dialog-icon{background:#eaf5ee;color:#2e844a}' +
            '.crm-hub-dialog-copy{min-width:0;width:100%}' +
            '.crm-hub-dialog-title{margin:0;font-size:1.0625rem;font-weight:700;color:#181818;letter-spacing:-.01em;line-height:1.3}' +
            '.crm-hub-dialog-msg{margin:.4rem 0 0;font-size:.875rem;color:#3e3e3c;line-height:1.45;overflow-wrap:anywhere;white-space:pre-wrap}' +
            '.crm-hub-dialog-actions{display:flex;flex-wrap:wrap;justify-content:center;gap:.5rem;width:100%;margin-top:.15rem}' +
            '.crm-hub-dialog-btn{border-radius:6px;padding:.45rem 1.05rem;font-size:.8125rem;font-weight:600;cursor:pointer;font-family:inherit;min-width:5.5rem}' +
            '.crm-hub-dialog-cancel{border:1px solid #c9c9c9;background:#fff;color:#181818}' +
            '.crm-hub-dialog-cancel:hover{background:#f3f3f3;border-color:#aeaeae}' +
            '.crm-hub-dialog-ok{border:0;background:#0176d3;color:#fff}' +
            '.crm-hub-dialog-ok:hover{background:#014486}' +
            '.crm-hub-dialog-overlay.is-error .crm-hub-dialog-ok{background:#ba0517}' +
            '.crm-hub-dialog-overlay.is-error .crm-hub-dialog-ok:hover{background:#8e030f}' +
            '.crm-hub-dialog-overlay.is-confirm .crm-hub-dialog-ok{background:#0176d3}' +
            '.crm-hub-dialog-overlay.is-danger .crm-hub-dialog-ok{background:#ba0517}' +
            '.crm-hub-dialog-overlay.is-danger .crm-hub-dialog-ok:hover{background:#8e030f}' +
            '.crm-hub-dialog-btn:focus{outline:none;box-shadow:0 0 0 2px #fff,0 0 0 4px rgba(1,118,211,.45)}' +
            '[data-record-id],.ch-row,.ch-card,.ch-kan-card,.ch-cal-event,.ch-open,.ch-open-ico,.crm-hub-record{cursor:pointer}';
        document.head.appendChild(style);
    }

    function ensureModal() {
        injectStyles();
        if (modalEl) {
            return;
        }
        modalEl = document.createElement('div');
        modalEl.className = 'crm-rm-overlay';
        modalEl.style.display = 'none';
        modalEl.setAttribute('role', 'dialog');
        modalEl.setAttribute('aria-modal', 'true');
        modalEl.innerHTML =
            '<div class="crm-rm-inner">' +
            '<div class="crm-rm-header">' +
            '<div class="crm-rm-header-main">' +
            '<div class="crm-rm-icon" aria-hidden="true">SF</div>' +
            '<div class="crm-rm-title-wrap"><h2 class="crm-rm-title"></h2><div class="crm-rm-sub"></div></div>' +
            '</div>' +
            '<div class="crm-rm-header-right">' +
            '<div class="crm-rm-header-actions" style="display:none"></div>' +
            '<button type="button" class="crm-rm-close" aria-label="Close">&times;</button>' +
            '</div>' +
            '</div>' +
            '<div class="crm-rm-path-wrap" style="display:none"><div class="crm-rm-path-inner"></div></div>' +
            '<div class="crm-rm-tabs-wrap"><div class="crm-rm-tabs" role="tablist"></div></div>' +
            '<div class="crm-rm-body"></div>' +
            '<div class="crm-rm-footer">' +
            '<span class="crm-rm-footer-status">Viewing record</span>' +
            '<div class="crm-rm-footer-actions">' +
            '<div class="crm-rm-footer-primary">' +
            '<button type="button" class="crm-rm-clone" style="display:none">Clone</button>' +
            '<button type="button" class="crm-rm-edit">Edit</button>' +
            '<button type="button" class="crm-rm-delete" style="display:none">Delete</button>' +
            '</div>' +
            '<button type="button" class="crm-rm-cancel" style="display:none">Cancel</button>' +
            '<button type="button" class="crm-rm-save" style="display:none" disabled>Save</button>' +
            '</div></div>' +
            '</div>';
        document.body.appendChild(modalEl);
        titleEl = modalEl.querySelector('.crm-rm-title');
        subEl = modalEl.querySelector('.crm-rm-sub');
        pathEl = modalEl.querySelector('.crm-rm-path-wrap');
        tabBarEl = modalEl.querySelector('.crm-rm-tabs');
        bodyEl = modalEl.querySelector('.crm-rm-body');
        footerEl = modalEl.querySelector('.crm-rm-footer');
        headerActionsEl = modalEl.querySelector('.crm-rm-header-actions');
        modalEl.querySelector('.crm-rm-close').onclick = function () {
            confirmDiscardIfNeeded(closeModalNow);
        };
        modalEl.addEventListener('click', function (ev) {
            if (ev.target === modalEl) {
                confirmDiscardIfNeeded(closeModalNow);
            }
        });
        bodyEl.addEventListener('click', handleModalBodyClick);
        tabBarEl.addEventListener('click', handleTabBarClick);
        if (headerActionsEl) {
            headerActionsEl.addEventListener('click', handleHeaderActionClick);
        }
        if (footerEl) {
            footerEl.querySelector('.crm-rm-edit').onclick = enterEditMode;
            footerEl.querySelector('.crm-rm-cancel').onclick = discardDraft;
            footerEl.querySelector('.crm-rm-save').onclick = saveDraft;
            var deleteBtn = footerEl.querySelector('.crm-rm-delete');
            if (deleteBtn) {
                deleteBtn.onclick = function () {
                    handleHubAction({ apiName: 'Delete', type: 'StandardButton' }, {});
                };
            }
            var cloneBtn = footerEl.querySelector('.crm-rm-clone');
            if (cloneBtn) {
                cloneBtn.onclick = function () {
                    handleHubAction({ apiName: 'Clone', type: 'StandardButton' }, {});
                };
            }
        }
        document.addEventListener('keydown', function (ev) {
            if (ev.key === 'Escape' && createJaFormEl && createJaFormEl.style.display !== 'none') {
                closeCreateJobApplicationForm();
                return;
            }
            if (ev.key === 'Escape' && viewAllModalEl && viewAllModalEl.style.display !== 'none') {
                closeViewAllModal();
                return;
            }
            if (ev.key === 'Escape' && modalEl && modalEl.style.display !== 'none') {
                confirmDiscardIfNeeded(closeModalNow);
            }
        });
    }

    function handleTabBarClick(ev) {
        var btn = ev.target.closest('.crm-rm-tab');
        if (!btn) {
            return;
        }
        var tabId = btn.getAttribute('data-tab-id');
        if (!tabId || tabId === activeTabId) {
            return;
        }
        confirmDiscardIfNeeded(function () {
            switchTab(tabId);
        });
    }

    function switchTab(tabId) {
        activeTabId = tabId;
        var tabs = tabBarEl.querySelectorAll('.crm-rm-tab');
        for (var i = 0; i < tabs.length; i++) {
            tabs[i].classList.toggle('is-active', tabs[i].getAttribute('data-tab-id') === tabId);
        }
        var panels = bodyEl.querySelectorAll('.crm-rm-panel');
        for (var j = 0; j < panels.length; j++) {
            panels[j].classList.toggle('is-active', panels[j].getAttribute('data-tab-id') === tabId);
        }
        var tab = tabById(tabId);
        if (tab && (tab.type === 'related' || tab.type === 'relatedMulti')) {
            var existing = relatedBlocksForTab(tabId, (currentModalData && currentModalData.relatedListData) || []);
            if (!existing.length) {
                loadRelatedListForTab(tab);
            }
        } else if (tab && tab.type === 'activity') {
            loadActivityForTab(tab);
        } else if (tab && tab.type === 'duplicates') {
            loadDuplicatesTab(tab);
        }
    }

    function handleModalBodyClick(ev) {
        if (openMenuEl && !ev.target.closest('.crm-rm-action-menu')) {
            closeActionMenu();
        }
        var menuItem = ev.target.closest('.crm-rm-action-menu-item');
        if (menuItem && openMenuEl) {
            ev.preventDefault();
            ev.stopPropagation();
            var ctx = openMenuEl._hubContext || {};
            handleHubAction(
                {
                    apiName: menuItem.getAttribute('data-hub-action'),
                    type: menuItem.getAttribute('data-action-type')
                },
                ctx
            );
            closeActionMenu();
            return;
        }
        var rowMenuBtn = ev.target.closest('.crm-rm-rl-row-menu');
        if (rowMenuBtn) {
            var rowActs = [];
            try {
                rowActs = JSON.parse(rowMenuBtn.getAttribute('data-actions') || '[]');
            } catch (eRow) {
                rowActs = [];
            }
            showRowActionMenu(ev, rowActs, {
                recordId: rowMenuBtn.getAttribute('data-record-id'),
                parentRecordId: currentRecordId,
                refreshRelatedList: function () {
                    var tab = tabById(activeTabId);
                    if (tab) {
                        loadRelatedListForTab(tab);
                    }
                }
            });
            return;
        }
        var listActBtn = ev.target.closest('[data-list-action]');
        if (listActBtn) {
            ev.preventDefault();
            ev.stopPropagation();
            handleHubAction(
                {
                    apiName: listActBtn.getAttribute('data-list-action'),
                    type: listActBtn.getAttribute('data-action-type') || 'StandardButton'
                },
                {
                    parentRecordId: currentRecordId,
                    objectApi: listActBtn.getAttribute('data-object-api'),
                    contextType: 'relatedListNew',
                    refreshRelatedList: function () {
                        var tab = tabById(activeTabId);
                        if (tab) {
                            loadRelatedListForTab(tab);
                        }
                    }
                }
            );
            return;
        }
        var actTypeBtn = ev.target.closest('.crm-rm-act-type');
        if (actTypeBtn) {
            ev.preventDefault();
            ev.stopPropagation();
            setActivityComposerType(actTypeBtn.closest('.crm-rm-act'), actTypeBtn.getAttribute('data-act-type'));
            return;
        }
        var actSaveBtn = ev.target.closest('.crm-rm-act-save');
        if (actSaveBtn) {
            ev.preventDefault();
            ev.stopPropagation();
            submitActivityComposer(actSaveBtn.closest('.crm-rm-act'));
            return;
        }
        var actCompleteBtn = ev.target.closest('.crm-rm-act-complete');
        if (actCompleteBtn) {
            ev.preventDefault();
            ev.stopPropagation();
            completeActivityItem(actCompleteBtn.getAttribute('data-activity-id'), actCompleteBtn.closest('.crm-rm-act'));
            return;
        }
        var viewAllBtn = ev.target.closest('.crm-rm-rl-viewall');
        if (viewAllBtn) {
            ev.preventDefault();
            ev.stopPropagation();
            openViewAllModal({
                relatedListName: viewAllBtn.getAttribute('data-related-list'),
                tabId: viewAllBtn.getAttribute('data-tab-id'),
                label: viewAllBtn.getAttribute('data-related-label') || 'Related records'
            });
            return;
        }
        var openBtn = ev.target.closest('.ch-open, .crm-rm-open, .crm-rm-ref-btn[data-id]');
        if (openBtn) {
            var rid = openBtn.getAttribute('data-id');
            if (rid && rid.length >= 15) {
                ev.preventDefault();
                ev.stopPropagation();
                openRecordModalFromClick(rid, ev);
                return;
            }
        }
        var anchor = ev.target.closest('a[href]');
        if (anchor && !anchor.getAttribute('href').startsWith('mailto:')) {
            var hrefId = sfIdFromHref(anchor.getAttribute('href'));
            if (hrefId) {
                ev.preventDefault();
                ev.stopPropagation();
                openRecordModalFromClick(hrefId, ev);
            }
        }
    }

    function closeModalNow() {
        closeCreateJobApplicationForm();
        if (modalEl) {
            modalEl.style.display = 'none';
            bodyEl.innerHTML = '';
            tabBarEl.innerHTML = '';
            if (pathEl) {
                pathEl.style.display = 'none';
                pathEl.querySelector('.crm-rm-path-inner').innerHTML = '';
            }
            if (footerEl) {
                footerEl.style.display = 'none';
            }
            if (headerActionsEl) {
                headerActionsEl.innerHTML = '';
                headerActionsEl.style.display = 'none';
            }
            currentModalData = null;
            activeTabId = null;
            currentRecordId = null;
            loadedRelatedTabIds = {};
            relatedListFetchInFlight = {};
            loadedActivityTabIds = {};
            activityFetchInFlight = {};
            activityCacheByRecord = {};
            originalValues = {};
            draftValues = {};
            editMode = false;
            canEditRecord = false;
            createJobAppInFlight = false;
            recordActions = [];
            duplicatesCache = {};
            closeActionMenu();
            closeGenericActionForm();
        }
    }

    function closeModal() {
        confirmDiscardIfNeeded(closeModalNow);
    }

    function objectLabelFromApi(objectApi) {
        if (!objectApi) {
            return '';
        }
        var known = {
            Account: 'Account',
            Contact: 'Contact',
            Lead: 'Lead',
            Opportunity: 'Opportunity',
            Job_Application__c: 'Job Application',
            Position__c: 'Position',
            Employment_Contract__c: 'Employment Contract'
        };
        if (known[objectApi]) {
            return known[objectApi];
        }
        return String(objectApi).replace(/__c$/, '').replace(/_/g, ' ');
    }

    function defaultDetailsTab() {
        return { id: 'details', label: 'Details', type: 'details', active: true };
    }

    function ensureDetailsTab(tabs) {
        var list = (tabs && tabs.length ? tabs.slice() : []).concat();
        if (!list.length) {
            return [defaultDetailsTab()];
        }
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].type === 'details') {
                return list;
            }
            if (list[i] && String(list[i].label || '').toLowerCase() === 'details') {
                list[i] = Object.assign({}, list[i], { type: 'details' });
                return list;
            }
        }
        return [defaultDetailsTab()].concat(list);
    }

    function isSalesforcePowerTab(tab) {
        if (!tab) {
            return false;
        }
        if (tab.type === 'salesforcePower') {
            return true;
        }
        var label = String(tab.label || '').toLowerCase();
        if (
            label === 'salesforce power' ||
            label === 'agentforce opportunity consultant' ||
            label === 'agentforce consultant' ||
            (label.indexOf('agentforce') >= 0 && label.indexOf('consultant') >= 0)
        ) {
            return true;
        }
        var componentName = String(tab.componentName || '').toLowerCase();
        return (
            componentName.indexOf('opportunitysalesforcepower') >= 0 ||
            componentName.indexOf('salesforce_power') >= 0 ||
            componentName.indexOf('opportunity_salesforce_power') >= 0
        );
    }

    function isActivityTab(tab) {
        if (!tab) {
            return false;
        }
        if (tab.type === 'activity') {
            return true;
        }
        var label = String(tab.label || '').toLowerCase();
        if (
            label === 'activity' ||
            label === 'activities' ||
            label === 'communications' ||
            label === 'communication'
        ) {
            return true;
        }
        var componentName = String(tab.componentName || '').toLowerCase();
        return (
            componentName.indexOf('activitypanel') >= 0 ||
            componentName.indexOf('runtime_sales_activities') >= 0
        );
    }

    function isIntentInsightsTab(tab) {
        if (!tab) {
            return false;
        }
        if (tab.type === 'intentInsights') {
            return true;
        }
        var label = String(tab.label || '').toLowerCase();
        if (label.indexOf('intent insight') >= 0) {
            return true;
        }
        var componentName = String(tab.componentName || '').toLowerCase();
        return (
            componentName.indexOf('powerintentviewer') >= 0 ||
            componentName.indexOf('intentinsight') >= 0
        );
    }

    function hasContactRelatedTab(tabs) {
        var list = tabs || [];
        for (var i = 0; i < list.length; i++) {
            var tab = list[i];
            if (!tab) {
                continue;
            }
            var label = String(tab.label || '').toLowerCase();
            if (
                label.indexOf('contact role') >= 0 ||
                label === 'contacts' ||
                label.indexOf('contacts for parent') >= 0
            ) {
                return true;
            }
            var rlName = String(tab.relatedListName || '').toLowerCase();
            if (
                rlName.indexOf('contactrole') >= 0 ||
                rlName === 'opportunitycontactroles' ||
                rlName === 'parentaccountcontacts'
            ) {
                return true;
            }
            var blocks = tab.relatedBlocks || [];
            for (var bi = 0; bi < blocks.length; bi++) {
                var blockName = String((blocks[bi] && blocks[bi].relatedListName) || '').toLowerCase();
                var blockLabel = String((blocks[bi] && blocks[bi].relatedListLabel) || '').toLowerCase();
                if (
                    blockName.indexOf('contactrole') >= 0 ||
                    blockName === 'opportunitycontactroles' ||
                    blockName === 'parentaccountcontacts' ||
                    blockLabel.indexOf('contact role') >= 0 ||
                    blockLabel.indexOf('contacts for parent') >= 0
                ) {
                    return true;
                }
            }
        }
        return false;
    }

    function ensureSalesforcePowerTab(tabs, objectApi) {
        var api = objectApi || (currentModalData && currentModalData.objectApi) || '';
        var list = (tabs && tabs.length ? tabs.slice() : []).concat();
        if (String(api) !== 'Opportunity') {
            return list;
        }
        for (var i = 0; i < list.length; i++) {
            if (isSalesforcePowerTab(list[i])) {
                list[i] = Object.assign({}, list[i], {
                    type: 'salesforcePower',
                    componentName: 'c:opportunitySalesforcePower',
                    label: list[i].label || 'Salesforce Power'
                });
                return list;
            }
        }
        var insertAt = list.length ? 1 : 0;
        list.splice(insertAt, 0, {
            id: 'salesforce_power',
            label: 'Salesforce Power',
            type: 'salesforcePower',
            componentName: 'c:opportunitySalesforcePower',
            active: false
        });
        return list;
    }

    function ensureActivityTab(tabs, objectApi) {
        var api = objectApi || (currentModalData && currentModalData.objectApi) || '';
        var list = (tabs && tabs.length ? tabs.slice() : []).concat();
        if (String(api) !== 'Opportunity') {
            return list;
        }
        for (var i = 0; i < list.length; i++) {
            if (isActivityTab(list[i])) {
                list[i] = Object.assign({}, list[i], {
                    type: 'activity',
                    label: list[i].label || 'Communications'
                });
                return list;
            }
        }
        var insertAt = list.length ? 1 : 0;
        list.splice(insertAt, 0, {
            id: 'communications',
            label: 'Communications',
            type: 'activity',
            active: false
        });
        return list;
    }

    function ensureContactRelatedTab(tabs, objectApi) {
        var api = objectApi || (currentModalData && currentModalData.objectApi) || '';
        var list = (tabs && tabs.length ? tabs.slice() : []).concat();
        if (String(api) !== 'Opportunity') {
            return list;
        }
        if (hasContactRelatedTab(list)) {
            return list;
        }
        var insertAt = Math.min(2, list.length);
        list.splice(insertAt, 0, {
            id: 'contact_roles',
            label: 'Contacts',
            type: 'relatedMulti',
            relatedBlocks: [
                {
                    relatedListName: 'OpportunityContactRoles',
                    relatedListLabel: 'Contact Roles'
                },
                {
                    relatedListName: 'ParentAccountContacts',
                    relatedListLabel: 'Contacts for Parent Account'
                }
            ],
            active: false
        });
        return list;
    }

    function isVisualforceTab(tab) {
        if (!tab) {
            return false;
        }
        if (tab.type === 'visualforce') {
            return true;
        }
        var label = String(tab.label || '').toLowerCase();
        if (label.indexOf('team builder') >= 0) {
            return true;
        }
        var componentName = String(tab.componentName || '').toLowerCase();
        return componentName.indexOf('visualforcepage') >= 0;
    }

    function isRssFeedTab(tab) {
        if (!tab) {
            return false;
        }
        if (tab.type === 'rssFeed') {
            return true;
        }
        var label = String(tab.label || '').toLowerCase();
        if (label.indexOf('agentforce news') >= 0 || label === 'news' || label.indexOf('rss') >= 0) {
            return true;
        }
        var componentName = String(tab.componentName || '').toLowerCase();
        return (
            componentName.indexOf('cloudastickrssfeedviewer') >= 0 ||
            componentName.indexOf('rssfeedviewer') >= 0
        );
    }

    function normalizeEmbedTabTypes(tabs) {
        var list = (tabs && tabs.length ? tabs.slice() : []).concat();
        for (var i = 0; i < list.length; i++) {
            var tab = list[i];
            if (!tab) {
                continue;
            }
            if (isVisualforceTab(tab)) {
                list[i] = Object.assign({}, tab, {
                    type: 'visualforce',
                    pageName: tab.pageName || (String(tab.label || '').toLowerCase().indexOf('team builder') >= 0
                        ? 'OpportunityTeam'
                        : tab.pageName),
                    label: tab.label || 'Team Builder'
                });
            } else if (isRssFeedTab(tab)) {
                list[i] = Object.assign({}, tab, {
                    type: 'rssFeed',
                    componentName: 'c:cloudastickRssFeedViewer',
                    rssUrlFieldName: tab.rssUrlFieldName || 'Google_Alert_URL__c',
                    label: tab.label || 'Agentforce News'
                });
            }
        }
        return list;
    }

    function ensureIntentInsightsTab(tabs, objectApi) {
        var api = objectApi || (currentModalData && currentModalData.objectApi) || '';
        var list = (tabs && tabs.length ? tabs.slice() : []).concat();
        if (String(api) !== 'Opportunity') {
            return list;
        }
        for (var i = 0; i < list.length; i++) {
            if (isIntentInsightsTab(list[i])) {
                list[i] = Object.assign({}, list[i], {
                    type: 'intentInsights',
                    componentName: 'c:powerIntentViewer',
                    label: list[i].label || 'Agentforce Intent Insights'
                });
                return list;
            }
        }
        var insertAt = Math.min(3, list.length);
        list.splice(insertAt, 0, {
            id: 'intent_insights',
            label: 'Agentforce Intent Insights',
            type: 'intentInsights',
            componentName: 'c:powerIntentViewer',
            active: false
        });
        return list;
    }

    function ensureDuplicatesTab(tabs, objectApi) {
        var dupObjects = {
            Lead: true,
            Contact: true,
            Account: true,
            Job_Application__c: true
        };
        if (!dupObjects[objectApi]) {
            return tabs || [];
        }
        var list = (tabs && tabs.length ? tabs.slice() : []).concat();
        for (var i = 0; i < list.length; i++) {
            if (list[i] && (list[i].type === 'duplicates' || list[i].id === 'potential_duplicates')) {
                list[i] = Object.assign({}, list[i], {
                    type: 'duplicates',
                    label: list[i].label || 'Potential Duplicates'
                });
                return list;
            }
        }
        list.push({
            id: 'potential_duplicates',
            label: 'Potential Duplicates',
            type: 'duplicates',
            active: false
        });
        return list;
    }

    function normalizeModalTabs(tabs, objectApi) {
        var list = ensureDetailsTab(tabs);
        list = normalizeEmbedTabTypes(list);
        list = ensureSalesforcePowerTab(list, objectApi);
        list = ensureActivityTab(list, objectApi);
        list = ensureContactRelatedTab(list, objectApi);
        list = ensureIntentInsightsTab(list, objectApi);
        list = ensureDuplicatesTab(list, objectApi);
        return list;
    }

    function showModalShell(hints) {
        ensureModal();
        hints = hints || {};
        titleEl.textContent = decodeHtmlEntities(hints.recordName || 'Loading…');
        subEl.textContent = hints.objectLabel || objectLabelFromApi(hints.objectApi) || '';
        if (hints.objectApi) {
            modalEl.querySelector('.crm-rm-icon').textContent = objectIconLetters(hints.objectApi);
        }
        tabBarEl.innerHTML = renderTabBar([defaultDetailsTab()], []);
        activeTabId = 'details';
        if (pathEl) {
            pathEl.style.display = 'none';
            pathEl.querySelector('.crm-rm-path-inner').innerHTML = '';
        }
        bodyEl.innerHTML =
            '<div class="crm-rm-panel is-active" data-tab-id="details" role="tabpanel">' +
            '<div class="crm-rm-loading">Loading record details…</div></div>';
        modalEl.style.display = 'flex';
    }

    function updateModalHeader(data) {
        if (!data) {
            return;
        }
        if (data.recordName) {
            titleEl.textContent = decodeHtmlEntities(data.recordName);
        }
        if (data.objectLabel || data.objectApi) {
            subEl.textContent = data.objectLabel || objectLabelFromApi(data.objectApi);
        }
        if (data.objectApi) {
            modalEl.querySelector('.crm-rm-icon').textContent = objectIconLetters(data.objectApi);
        }
    }

    function ensureModalData() {
        if (!currentModalData) {
            currentModalData = {
                tabs: [defaultDetailsTab()],
                relatedListData: [],
                values: {},
                fieldMeta: {}
            };
        }
        return currentModalData;
    }

    function mergeModalData(partial) {
        var data = ensureModalData();
        if (!partial) {
            return data;
        }
        for (var key in partial) {
            if (Object.prototype.hasOwnProperty.call(partial, key)) {
                data[key] = partial[key];
            }
        }
        return data;
    }

    function renderDetailsContent(details) {
        mergeModalData(details);
        var data = currentModalData;
        initDraftState(data.values || {});
        canEditRecord = hasEditableLayoutFields(data.layout, data.fieldMeta || {});
        recordActions = details.recordActions || [];
        editMode = false;
        var tabs = normalizeModalTabs(data.tabs || [defaultDetailsTab()], data.objectApi);
        data.tabs = tabs;
        activeTabId = defaultActiveTabId(tabs);
        tabBarEl.innerHTML = renderTabBar(tabs, data.relatedListData || []);
        bodyEl.innerHTML = renderTabPanels(
            tabs,
            data.layout,
            draftValues,
            data.relatedListData || [],
            data.fieldMeta || {}
        );
        wireAllDetailsInputs();
        updateFooter();
    }

    function wireAllDetailsInputs() {
        if (!bodyEl) {
            return;
        }
        destroyOwnerLookups();
        var panels = bodyEl.querySelectorAll('.crm-rm-panel');
        for (var i = 0; i < panels.length; i++) {
            wireDetailsPanelInputs(panels[i]);
            wireOwnerLookups(panels[i]);
        }
    }

    function updateTabsAndPanels(tabsRes) {
        if (!tabsRes || !tabsRes.tabs || !tabsRes.tabs.length) {
            return;
        }
        var data = mergeModalData({ tabs: normalizeModalTabs(tabsRes.tabs, (currentModalData && currentModalData.objectApi) || tabsRes.objectApi) });
        if (!Object.keys(originalValues).length && data.values) {
            initDraftState(data.values);
        }
        canEditRecord = hasEditableLayoutFields(data.layout, data.fieldMeta || {});
        // Keep current editMode if already editing; otherwise stay in view mode
        if (!editMode) {
            editMode = false;
        }
        activeTabId = defaultActiveTabId(data.tabs);
        tabBarEl.innerHTML = renderTabBar(data.tabs, data.relatedListData || []);
        bodyEl.innerHTML = renderTabPanels(
            data.tabs,
            data.layout,
            draftValues,
            data.relatedListData || [],
            data.fieldMeta || {}
        );
        wireAllDetailsInputs();
        updateFooter();
        prefetchRelatedListTabs(data.tabs);
    }

    function relatedListBlocksForTab(tab) {
        var blocks = [];
        if (tab.type === 'related') {
            blocks.push({
                tabId: tab.id,
                relatedListName: tab.relatedListName,
                relatedListLabel: tab.relatedListLabel,
                relatedListMeta: tab.relatedListMeta
            });
        } else if (tab.type === 'relatedMulti' && tab.relatedBlocks) {
            for (var i = 0; i < tab.relatedBlocks.length; i++) {
                var blockDef = tab.relatedBlocks[i];
                blocks.push({
                    tabId: tab.id,
                    relatedListName: blockDef.relatedListName,
                    relatedListLabel: blockDef.relatedListLabel,
                    relatedListMeta: blockDef.relatedListMeta
                });
            }
        }
        return blocks;
    }

    function mergeRelatedListBlock(block) {
        if (!block || !block.tabId) {
            return;
        }
        var data = ensureModalData();
        var list = data.relatedListData || [];
        var replaced = false;
        for (var i = 0; i < list.length; i++) {
            if (list[i].tabId === block.tabId && list[i].name === block.name) {
                list[i] = block;
                replaced = true;
                break;
            }
        }
        if (!replaced) {
            list.push(block);
        }
        data.relatedListData = list;
        loadedRelatedTabIds[block.tabId + ':' + block.name] = true;
        refreshRelatedTabPanel(block.tabId);
        tabBarEl.innerHTML = renderTabBar(data.tabs || [defaultDetailsTab()], data.relatedListData);
    }

    function refreshRelatedTabPanel(tabId) {
        if (!tabId || tabId !== activeTabId) {
            return;
        }
        var data = currentModalData;
        if (!data || !data.tabs) {
            return;
        }
        var panel = bodyEl.querySelector('.crm-rm-panel[data-tab-id="' + tabId + '"]');
        if (!panel) {
            return;
        }
        var tab = null;
        for (var i = 0; i < data.tabs.length; i++) {
            if (data.tabs[i].id === tabId) {
                tab = data.tabs[i];
                break;
            }
        }
        if (!tab) {
            return;
        }
        var parts = [];
        var relatedBlocks = relatedBlocksForTab(tabId, data.relatedListData || []);
        for (var bi = 0; bi < relatedBlocks.length; bi++) {
            var block = relatedBlocks[bi];
            if (relatedBlocks.length > 1) {
                block = Object.assign({}, block, { sectionLabel: true });
            }
            parts.push(renderRelatedListTable(block));
        }
        panel.innerHTML = parts.length
            ? parts.join('')
            : '<div class="crm-rm-tab-loading">Loading related records…</div>';
    }

    function loadRelatedListForTab(tab, options) {
        options = options || {};
        var blocks = relatedListBlocksForTab(tab);
        if (!blocks.length || !currentRecordId) {
            return Promise.resolve();
        }
        var promises = [];
        for (var i = 0; i < blocks.length; i++) {
            (function (blockDef) {
                var fetchKey = tab.id + ':' + blockDef.relatedListName;
                if (loadedRelatedTabIds[fetchKey] || relatedListFetchInFlight[fetchKey]) {
                    return;
                }
                relatedListFetchInFlight[fetchKey] = true;
                if (!options.silent && tab.id === activeTabId) {
                    var panel = bodyEl.querySelector('.crm-rm-panel[data-tab-id="' + tab.id + '"]');
                    if (panel && !panel.querySelector('.crm-rm-rl-table')) {
                        panel.innerHTML = '<div class="crm-rm-tab-loading">Loading related records…</div>';
                    }
                }
                promises.push(
                    remotingRelatedList(currentRecordId, blockDef.relatedListName, tab.id)
                        .then(function (res) {
                            delete relatedListFetchInFlight[fetchKey];
                            if (res.error) {
                                return;
                            }
                            if (res.relatedList) {
                                mergeRelatedListBlock(res.relatedList);
                            }
                        })
                        .catch(function () {
                            delete relatedListFetchInFlight[fetchKey];
                        })
                );
            })(blocks[i]);
        }
        return Promise.all(promises);
    }

    function prefetchRelatedListTabs(tabs) {
        var list = tabs || [];
        for (var i = 0; i < list.length; i++) {
            var tab = list[i];
            if (tab.type === 'related' || tab.type === 'relatedMulti') {
                loadRelatedListForTab(tab, { silent: true });
            } else if (tab.type === 'activity') {
                loadActivityForTab(tab, { silent: true });
            }
        }
    }

    function activityPanelEl(root) {
        if (!root) {
            return null;
        }
        return root.classList && root.classList.contains('crm-rm-act')
            ? root
            : root.querySelector
              ? root.querySelector('.crm-rm-act')
              : null;
    }

    function setActivityComposerType(root, type) {
        var wrap = activityPanelEl(root);
        if (!wrap || !type) {
            return;
        }
        wrap.setAttribute('data-act-type', type);
        var buttons = wrap.querySelectorAll('.crm-rm-act-type');
        for (var i = 0; i < buttons.length; i++) {
            buttons[i].classList.toggle('is-active', buttons[i].getAttribute('data-act-type') === type);
        }
        var taskFields = wrap.querySelectorAll('[data-act-for="Task"]');
        var eventFields = wrap.querySelectorAll('[data-act-for="Event"]');
        var showTask = type === 'Task';
        var showEvent = type === 'Event';
        for (var t = 0; t < taskFields.length; t++) {
            taskFields[t].style.display = showTask ? '' : 'none';
        }
        for (var e = 0; e < eventFields.length; e++) {
            eventFields[e].style.display = showEvent ? '' : 'none';
        }
        var saveBtn = wrap.querySelector('.crm-rm-act-save');
        if (saveBtn) {
            if (type === 'Call') {
                saveBtn.textContent = 'Log Call';
            } else if (type === 'Event') {
                saveBtn.textContent = 'Save Event';
            } else {
                saveBtn.textContent = 'Save Task';
            }
        }
    }

    function setActivityMessage(wrap, msg, kind) {
        var el = wrap ? wrap.querySelector('.crm-rm-act-msg') : null;
        if (!el) {
            return;
        }
        el.textContent = msg || '';
        el.className = 'crm-rm-act-msg' + (kind ? ' is-' + kind : '');
    }

    function formatActivityDate(val) {
        if (!val) {
            return '';
        }
        try {
            if (/^\d{4}-\d{2}-\d{2}$/.test(String(val))) {
                return String(val);
            }
            var d = new Date(val);
            if (isNaN(d.getTime())) {
                return String(val);
            }
            return d.toLocaleString(undefined, {
                year: 'numeric',
                month: 'short',
                day: 'numeric',
                hour: 'numeric',
                minute: '2-digit'
            });
        } catch (e) {
            return String(val);
        }
    }

    function activityIconClass(item) {
        var t = ((item && (item.type || item.subtype)) || 'Task').toLowerCase();
        if (t === 'call') {
            return 'is-call';
        }
        if (t === 'event') {
            return 'is-event';
        }
        return 'is-task';
    }

    function activityIconLabel(item) {
        var t = ((item && (item.type || item.subtype)) || 'Task').toLowerCase();
        if (t === 'call') {
            return 'CL';
        }
        if (t === 'event') {
            return 'EV';
        }
        return 'TK';
    }

    function renderActivityItems(activities) {
        var openItems = [];
        var pastItems = [];
        var list = activities || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].isOpen) {
                openItems.push(list[i]);
            } else {
                pastItems.push(list[i]);
            }
        }
        var html = [];
        function pushSection(title, items) {
            html.push('<div class="crm-rm-act-section">' + esc(title) + '</div>');
            if (!items.length) {
                html.push('<div class="crm-rm-act-empty">No ' + esc(title.toLowerCase()) + '.</div>');
                return;
            }
            html.push('<div class="crm-rm-act-list">');
            for (var j = 0; j < items.length; j++) {
                var item = items[j];
                var metaParts = [];
                if (item.type) {
                    metaParts.push(item.type);
                }
                if (item.status) {
                    metaParts.push(item.status);
                }
                if (item.activityDate) {
                    metaParts.push(formatActivityDate(item.activityDate));
                }
                if (item.ownerName) {
                    metaParts.push(item.ownerName);
                }
                html.push('<div class="crm-rm-act-item">');
                html.push(
                    '<div class="crm-rm-act-ico ' +
                        activityIconClass(item) +
                        '" aria-hidden="true">' +
                        activityIconLabel(item) +
                        '</div>'
                );
                html.push('<div class="crm-rm-act-main">');
                html.push('<div class="crm-rm-act-subject">' + esc(item.subject || '(No subject)') + '</div>');
                html.push('<div class="crm-rm-act-meta">' + esc(metaParts.join(' · ')) + '</div>');
                if (item.description) {
                    html.push('<div class="crm-rm-act-desc">' + esc(item.description) + '</div>');
                }
                html.push('</div>');
                if (item.isOpen && item.type !== 'Event' && String(item.id || '').indexOf('00T') === 0) {
                    html.push(
                        '<button type="button" class="crm-rm-act-complete" data-activity-id="' +
                            esc(item.id) +
                            '">Complete</button>'
                    );
                }
                html.push('</div>');
            }
            html.push('</div>');
        }
        pushSection('Open Activities', openItems);
        pushSection('Past Activity', pastItems);
        return html.join('');
    }

    function salesforcePowerPageUrl(recordId) {
        if (!recordId) {
            return '';
        }
        return '/apex/Opportunity_Salesforce_Power?id=' + encodeURIComponent(recordId);
    }

    function intentInsightsPageUrl(recordId) {
        if (!recordId) {
            return '';
        }
        return '/apex/Opportunity_Intent_Insights?id=' + encodeURIComponent(recordId);
    }

    function visualforcePageUrl(pageName, recordId) {
        if (!pageName || !recordId) {
            return '';
        }
        var clean = String(pageName).replace(/^\/+/, '').replace(/^apex\//i, '');
        return '/apex/' + encodeURIComponent(clean) + '?id=' + encodeURIComponent(recordId);
    }

    function rssFeedPageUrl(recordId, rssUrlFieldName) {
        if (!recordId) {
            return '';
        }
        var url = '/apex/Opportunity_Agentforce_News?id=' + encodeURIComponent(recordId);
        if (rssUrlFieldName) {
            url += '&rssField=' + encodeURIComponent(rssUrlFieldName);
        }
        return url;
    }

    function renderSalesforcePowerPanel(recordId) {
        var url = salesforcePowerPageUrl(recordId);
        if (!url) {
            return (
                '<div class="crm-rm-custom">' +
                '<div class="crm-rm-custom-title">Salesforce Power</div>' +
                '<div class="crm-rm-custom-msg">Open an Opportunity to load Salesforce Power.</div>' +
                '</div>'
            );
        }
        return (
            '<div class="crm-rm-power">' +
            '<iframe class="crm-rm-power-iframe" src="' +
            esc(url) +
            '" title="Salesforce Power" loading="lazy"></iframe>' +
            '</div>'
        );
    }

    function renderIntentInsightsPanel(recordId) {
        var url = intentInsightsPageUrl(recordId);
        if (!url) {
            return (
                '<div class="crm-rm-custom">' +
                '<div class="crm-rm-custom-title">Agentforce Intent Insights</div>' +
                '<div class="crm-rm-custom-msg">Open an Opportunity to load Intent Insights.</div>' +
                '</div>'
            );
        }
        return (
            '<div class="crm-rm-power">' +
            '<iframe class="crm-rm-power-iframe" src="' +
            esc(url) +
            '" title="Agentforce Intent Insights" loading="lazy"></iframe>' +
            '</div>'
        );
    }

    function renderVisualforcePanel(tab, recordId) {
        var pageName = (tab && tab.pageName) || 'OpportunityTeam';
        var url = visualforcePageUrl(pageName, recordId);
        var title = (tab && tab.label) || 'Visualforce';
        if (!url) {
            return (
                '<div class="crm-rm-custom">' +
                '<div class="crm-rm-custom-title">' +
                formatDisplayLabel(title) +
                '</div>' +
                '<div class="crm-rm-custom-msg">Open a record to load this page.</div>' +
                '</div>'
            );
        }
        return (
            '<div class="crm-rm-power">' +
            '<iframe class="crm-rm-power-iframe" src="' +
            esc(url) +
            '" title="' +
            esc(title) +
            '" loading="lazy"></iframe>' +
            '</div>'
        );
    }

    function renderRssFeedPanel(tab, recordId) {
        var fieldName = (tab && tab.rssUrlFieldName) || 'Google_Alert_URL__c';
        var url = rssFeedPageUrl(recordId, fieldName);
        var title = (tab && tab.label) || 'Agentforce News';
        if (!url) {
            return (
                '<div class="crm-rm-custom">' +
                '<div class="crm-rm-custom-title">' +
                formatDisplayLabel(title) +
                '</div>' +
                '<div class="crm-rm-custom-msg">Open an Opportunity to load Agentforce News.</div>' +
                '</div>'
            );
        }
        return (
            '<div class="crm-rm-power">' +
            '<iframe class="crm-rm-power-iframe" src="' +
            esc(url) +
            '" title="' +
            esc(title) +
            '" loading="lazy"></iframe>' +
            '</div>'
        );
    }

    function renderActivityPanel(activities) {
        return (
            '<div class="crm-rm-act" data-act-type="Task">' +
            '<div class="crm-rm-act-composer">' +
            '<div class="crm-rm-act-composer-tabs">' +
            '<button type="button" class="crm-rm-act-type is-active" data-act-type="Task">New Task</button>' +
            '<button type="button" class="crm-rm-act-type" data-act-type="Call">Log a Call</button>' +
            '<button type="button" class="crm-rm-act-type" data-act-type="Event">New Event</button>' +
            '</div>' +
            '<div class="crm-rm-act-fields">' +
            '<div class="crm-rm-act-full">' +
            '<label class="crm-rm-act-lbl" for="crm-rm-act-subject">Subject</label>' +
            '<input id="crm-rm-act-subject" class="crm-rm-input crm-rm-act-subject" type="text" maxlength="255" placeholder="Subject" />' +
            '</div>' +
            '<div data-act-for="Task">' +
            '<label class="crm-rm-act-lbl" for="crm-rm-act-due">Due Date</label>' +
            '<input id="crm-rm-act-due" class="crm-rm-input crm-rm-act-due" type="date" />' +
            '</div>' +
            '<div data-act-for="Task">' +
            '<label class="crm-rm-act-lbl" for="crm-rm-act-priority">Priority</label>' +
            '<select id="crm-rm-act-priority" class="crm-rm-input crm-rm-act-priority">' +
            '<option value="Normal">Normal</option>' +
            '<option value="High">High</option>' +
            '<option value="Low">Low</option>' +
            '</select>' +
            '</div>' +
            '<div data-act-for="Event" style="display:none">' +
            '<label class="crm-rm-act-lbl" for="crm-rm-act-start">Start</label>' +
            '<input id="crm-rm-act-start" class="crm-rm-input crm-rm-act-start" type="datetime-local" />' +
            '</div>' +
            '<div data-act-for="Event" style="display:none">' +
            '<label class="crm-rm-act-lbl" for="crm-rm-act-end">End</label>' +
            '<input id="crm-rm-act-end" class="crm-rm-input crm-rm-act-end" type="datetime-local" />' +
            '</div>' +
            '<div class="crm-rm-act-full">' +
            '<label class="crm-rm-act-lbl" for="crm-rm-act-desc">Comments</label>' +
            '<textarea id="crm-rm-act-desc" class="crm-rm-input crm-rm-act-desc" rows="3" placeholder="Comments"></textarea>' +
            '</div>' +
            '</div>' +
            '<div class="crm-rm-act-actions">' +
            '<div class="crm-rm-act-msg"></div>' +
            '<button type="button" class="crm-rm-act-save">Save Task</button>' +
            '</div>' +
            '</div>' +
            '<div class="crm-rm-act-timeline">' +
            renderActivityItems(activities) +
            '</div>' +
            '</div>'
        );
    }

    function refreshActivityPanels(activities) {
        if (!bodyEl) {
            return;
        }
        var timelines = bodyEl.querySelectorAll('.crm-rm-act-timeline');
        var html = renderActivityItems(activities);
        for (var i = 0; i < timelines.length; i++) {
            timelines[i].innerHTML = html;
        }
        if (currentModalData) {
            currentModalData.activities = activities || [];
        }
        if (currentRecordId) {
            activityCacheByRecord[currentRecordId] = activities || [];
        }
    }

    function loadActivityForTab(tab, options) {
        options = options || {};
        if (!tab || !currentRecordId) {
            return Promise.resolve();
        }
        var fetchKey = tab.id || 'activity';
        if (loadedActivityTabIds[fetchKey] || activityFetchInFlight[fetchKey]) {
            if (loadedActivityTabIds[fetchKey] && tab.id === activeTabId) {
                var cached = activityCacheByRecord[currentRecordId] || [];
                var panelCached = bodyEl.querySelector('.crm-rm-panel[data-tab-id="' + tab.id + '"]');
                if (panelCached && !panelCached.querySelector('.crm-rm-act')) {
                    panelCached.innerHTML = renderActivityPanel(cached);
                }
            }
            return Promise.resolve();
        }
        activityFetchInFlight[fetchKey] = true;
        if (!options.silent && tab.id === activeTabId) {
            var panel = bodyEl.querySelector('.crm-rm-panel[data-tab-id="' + tab.id + '"]');
            if (panel && !panel.querySelector('.crm-rm-act')) {
                panel.innerHTML = '<div class="crm-rm-tab-loading">Loading activities…</div>';
            }
        }
        return remotingActivities(currentRecordId)
            .then(function (res) {
                delete activityFetchInFlight[fetchKey];
                if (res.error) {
                    var errPanel = bodyEl.querySelector('.crm-rm-panel[data-tab-id="' + tab.id + '"]');
                    if (errPanel) {
                        errPanel.innerHTML =
                            '<div class="crm-rm-error">' + esc(res.error) + '</div>';
                    }
                    return;
                }
                loadedActivityTabIds[fetchKey] = true;
                var activities = res.activities || [];
                activityCacheByRecord[currentRecordId] = activities;
                if (currentModalData) {
                    currentModalData.activities = activities;
                }
                var readyPanel = bodyEl.querySelector('.crm-rm-panel[data-tab-id="' + tab.id + '"]');
                if (readyPanel) {
                    readyPanel.innerHTML = renderActivityPanel(activities);
                }
            })
            .catch(function (err) {
                delete activityFetchInFlight[fetchKey];
                var failPanel = bodyEl.querySelector('.crm-rm-panel[data-tab-id="' + tab.id + '"]');
                if (failPanel) {
                    failPanel.innerHTML =
                        '<div class="crm-rm-error">' +
                        esc(err && err.message ? err.message : 'Unable to load activities') +
                        '</div>';
                }
            });
    }

    function submitActivityComposer(root) {
        var wrap = activityPanelEl(root);
        if (!wrap || !currentRecordId) {
            return;
        }
        var type = wrap.getAttribute('data-act-type') || 'Task';
        var subjectEl = wrap.querySelector('.crm-rm-act-subject');
        var descEl = wrap.querySelector('.crm-rm-act-desc');
        var subject = subjectEl ? subjectEl.value.trim() : '';
        if (!subject) {
            setActivityMessage(wrap, 'Subject is required.', 'error');
            if (subjectEl) {
                subjectEl.focus();
            }
            return;
        }
        var fields = {
            Subject: subject,
            Description: descEl ? descEl.value : ''
        };
        if (type === 'Task') {
            var dueEl = wrap.querySelector('.crm-rm-act-due');
            var priEl = wrap.querySelector('.crm-rm-act-priority');
            if (dueEl && dueEl.value) {
                fields.ActivityDate = dueEl.value;
            }
            if (priEl && priEl.value) {
                fields.Priority = priEl.value;
            }
        } else if (type === 'Event') {
            var startEl = wrap.querySelector('.crm-rm-act-start');
            var endEl = wrap.querySelector('.crm-rm-act-end');
            if (startEl && startEl.value) {
                fields.StartDateTime = startEl.value;
            }
            if (endEl && endEl.value) {
                fields.EndDateTime = endEl.value;
            }
        }
        var saveBtn = wrap.querySelector('.crm-rm-act-save');
        if (saveBtn) {
            saveBtn.disabled = true;
        }
        setActivityMessage(wrap, 'Saving…', '');
        remotingCreateActivity(currentRecordId, type, fields)
            .then(function (res) {
                if (saveBtn) {
                    saveBtn.disabled = false;
                }
                if (res.error) {
                    setActivityMessage(wrap, res.error, 'error');
                    return;
                }
                if (subjectEl) {
                    subjectEl.value = '';
                }
                if (descEl) {
                    descEl.value = '';
                }
                setActivityMessage(wrap, 'Saved.', 'ok');
                refreshActivityPanels(res.activities || []);
                loadedActivityTabIds = {};
            })
            .catch(function (err) {
                if (saveBtn) {
                    saveBtn.disabled = false;
                }
                setActivityMessage(wrap, err && err.message ? err.message : 'Save failed', 'error');
            });
    }

    function completeActivityItem(activityId, root) {
        if (!activityId || !currentRecordId) {
            return;
        }
        var wrap = activityPanelEl(root) || bodyEl.querySelector('.crm-rm-act');
        remotingCompleteActivity(currentRecordId, activityId)
            .then(function (res) {
                if (res.error) {
                    setActivityMessage(wrap, res.error, 'error');
                    return;
                }
                refreshActivityPanels(res.activities || []);
                setActivityMessage(wrap, 'Marked complete.', 'ok');
            })
            .catch(function (err) {
                setActivityMessage(wrap, err && err.message ? err.message : 'Update failed', 'error');
            });
    }

    function tabById(tabId) {
        var tabs = (currentModalData && currentModalData.tabs) || [];
        for (var i = 0; i < tabs.length; i++) {
            if (tabs[i].id === tabId) {
                return tabs[i];
            }
        }
        return null;
    }

    function showLoading() {
        showModalShell({});
    }

    function showError(msg) {
        ensureModal();
        titleEl.textContent = 'Record';
        subEl.textContent = '';
        tabBarEl.innerHTML = '';
        if (pathEl) {
            pathEl.style.display = 'none';
            pathEl.querySelector('.crm-rm-path-inner').innerHTML = '';
        }
        bodyEl.innerHTML = '<div class="crm-rm-error">' + esc(msg || 'Unable to open record') + '</div>';
        modalEl.style.display = 'flex';
    }

    function sfIdFromHref(href) {
        if (!href) {
            return null;
        }
        var m = String(href).match(/\/([a-zA-Z0-9]{15,18})(?:[/?#]|$)/);
        return m ? m[1] : null;
    }

    function objectIconLetters(objectApi) {
        if (!objectApi) {
            return 'SF';
        }
        var parts = String(objectApi).replace(/__c$/, '').split('_');
        if (parts.length >= 2) {
            return (parts[0].charAt(0) + parts[1].charAt(0)).toUpperCase();
        }
        return String(objectApi).substring(0, 2).toUpperCase();
    }

    function renderFieldValue(fieldApi, details, values) {
        var type = details && details.type ? String(details.type).toLowerCase() : '';
        if (type === 'reference') {
            var rel = details.relationshipName;
            var display = null;
            if (rel && values[rel + '.Name'] != null && values[rel + '.Name'] !== '') {
                display = values[rel + '.Name'];
            }
            if (display == null && rel) {
                // Case-insensitive key fallback (Remoting / JSON quirks)
                var want = String(rel + '.Name').toLowerCase();
                for (var vk in values) {
                    if (
                        Object.prototype.hasOwnProperty.call(values, vk) &&
                        String(vk).toLowerCase() === want &&
                        values[vk] != null &&
                        values[vk] !== ''
                    ) {
                        display = values[vk];
                        break;
                    }
                }
            }
            var refId = values[fieldApi];
            if (refId) {
                var label = display != null ? String(display) : String(refId);
                return {
                    html:
                        '<button type="button" class="crm-rm-ref-btn" data-id="' +
                        esc(String(refId)) +
                        '" title="Open related record">' +
                        esc(label) +
                        '</button>',
                    isHtml: false
                };
            }
            return { html: '—', isHtml: false };
        }

        var raw = values[fieldApi];
        if (raw === null || raw === undefined || raw === '') {
            return { html: '—', isHtml: false };
        }

        if (isPlainObject(raw)) {
            var compoundFormatted = formatScalarValue(type || 'address', raw, details);
            return {
                html: compoundFormatted,
                isHtml: compoundFormatted.indexOf('<') >= 0
            };
        }

        if (fieldWantsHtml(details, fieldApi, raw)) {
            var normalized = normalizeRenderableHtml(raw);
            if (isRenderableHtml(normalized) || isRenderableHtml(raw)) {
                return { html: normalized, isHtml: true };
            }
            /* htmlCapable / textarea with entity-only text (e.g. &gt;&gt;) */
            return { html: esc(normalized), isHtml: false };
        }

        var formatted = formatScalarValue(type, raw, details);
        if (type === 'email' || type === 'url' || type === 'phone') {
            return { html: formatted, isHtml: true };
        }
        if (type === 'address' || type === 'location') {
            return { html: formatted, isHtml: formatted.indexOf('<br>') >= 0 };
        }
        /* formatScalarValue already decodes plain strings; esc for safe HTML */
        return { html: esc(String(formatted)), isHtml: false };
    }

    function renderRelatedCellValue(val) {
        if (val == null || val === '') {
            return '—';
        }
        var s = String(val);
        if (isRenderableHtml(s)) {
            return normalizeRenderableHtml(s);
        }
        if (isEpochMs(s) || isEpochMs(Number(s))) {
            return esc(formatDateValue('datetime', s));
        }
        return escPlain(s);
    }

    function tabCountLabel(blocks, tab) {
        var total = 0;
        var blocksForTab = blocks || [];
        for (var i = 0; i < blocksForTab.length; i++) {
            if (blocksForTab[i].tabId === tab.id) {
                total += Number(blocksForTab[i].totalSize || blocksForTab[i].rows.length || 0);
            }
        }
        if (tab.type === 'related' || tab.type === 'relatedMulti') {
            if (total > 20) {
                return ' (' + total + '+)';
            }
            if (total > 0) {
                return ' (' + total + ')';
            }
        }
        return '';
    }

    function ensureViewAllModal() {
        if (viewAllModalEl) {
            return;
        }
        viewAllModalEl = document.createElement('div');
        viewAllModalEl.className = 'crm-rm-viewall-overlay';
        viewAllModalEl.style.display = 'none';
        viewAllModalEl.setAttribute('role', 'dialog');
        viewAllModalEl.setAttribute('aria-modal', 'true');
        viewAllModalEl.innerHTML =
            '<div class="crm-rm-viewall-inner">' +
            '<div class="crm-rm-viewall-header">' +
            '<h3 class="crm-rm-viewall-title"></h3>' +
            '<button type="button" class="crm-rm-close" aria-label="Close">&times;</button>' +
            '</div>' +
            '<div class="crm-rm-viewall-body"></div>' +
            '</div>';
        document.body.appendChild(viewAllModalEl);
        viewAllTitleEl = viewAllModalEl.querySelector('.crm-rm-viewall-title');
        viewAllBodyEl = viewAllModalEl.querySelector('.crm-rm-viewall-body');
        viewAllModalEl.querySelector('.crm-rm-close').onclick = closeViewAllModal;
        viewAllModalEl.addEventListener('click', function (ev) {
            if (ev.target === viewAllModalEl) {
                closeViewAllModal();
            }
        });
        viewAllBodyEl.addEventListener('click', handleModalBodyClick);
    }

    function closeViewAllModal() {
        if (viewAllModalEl) {
            viewAllModalEl.style.display = 'none';
            viewAllBodyEl.innerHTML = '';
        }
    }

    function openViewAllModal(opts) {
        if (!opts || !opts.relatedListName || !currentRecordId) {
            return;
        }
        ensureViewAllModal();
        viewAllTitleEl.textContent = opts.label || 'Related records';
        viewAllBodyEl.innerHTML = '<div class="crm-rm-tab-loading">Loading related records…</div>';
        viewAllModalEl.style.display = 'flex';
        remotingRelatedList(currentRecordId, opts.relatedListName, opts.tabId || '', 200)
            .then(function (res) {
                if (res.error) {
                    viewAllBodyEl.innerHTML =
                        '<div class="crm-rm-error">' + esc(res.error) + '</div>';
                    return;
                }
                var block = res.relatedList;
                if (!block) {
                    viewAllBodyEl.innerHTML = '<div class="crm-rm-muted">No records to display.</div>';
                    return;
                }
                viewAllBodyEl.innerHTML = renderRelatedListTable(block, { fullList: true });
            })
            .catch(function (err) {
                viewAllBodyEl.innerHTML =
                    '<div class="crm-rm-error">' + esc(err && err.message ? err.message : String(err)) + '</div>';
            });
    }

    function relatedListColumnField(col) {
        if (!col) {
            return '';
        }
        if (col.fieldApiName) {
            return String(col.fieldApiName);
        }
        if (col.field) {
            return String(col.field);
        }
        return '';
    }

    function relatedListColumnLabel(col) {
        if (!col) {
            return '';
        }
        if (col.label) {
            return formatDisplayLabel(col.label);
        }
        return formatDisplayLabel(relatedListColumnField(col));
    }

    function getRelatedCellValue(row, fieldApi) {
        if (!row || !fieldApi) {
            return '';
        }
        var cells = row.cells;
        if (cells && typeof cells === 'object' && !Array.isArray(cells)) {
            if (cells[fieldApi] != null && cells[fieldApi] !== '') {
                return cells[fieldApi];
            }
            for (var key in cells) {
                if (Object.prototype.hasOwnProperty.call(cells, key) && key.toLowerCase() === fieldApi.toLowerCase()) {
                    return cells[key];
                }
            }
        }
        if (Array.isArray(cells)) {
            for (var i = 0; i < cells.length; i++) {
                var cell = cells[i];
                if (cell && (cell.field === fieldApi || cell.fieldApiName === fieldApi)) {
                    return cell.value;
                }
            }
        }
        return '';
    }

    function renderRelatedListTable(block, options) {
        options = options || {};
        var rows = block.rows || [];
        var cols = block.columns || [];
        var listActions = block.listActions || [];
        var html = [];
        html.push('<div class="crm-rm-rl-wrap">');
        if (block.label && block.sectionLabel) {
            html.push('<h3 class="crm-rm-sec">' + formatDisplayLabel(block.label) + '</h3>');
        }
        if (listActions.length) {
            html.push('<div class="crm-rm-rl-toolbar">');
            for (var la = 0; la < listActions.length; la++) {
                var lact = listActions[la];
                html.push(
                    '<button type="button" class="crm-rm-action-btn is-primary" data-list-action="' +
                        esc(lact.apiName) +
                        '" data-action-type="' +
                        esc(lact.type || 'StandardButton') +
                        '" data-object-api="' +
                        esc(block.childObjectApi || '') +
                        '">' +
                        esc(lact.label || lact.apiName) +
                        '</button>'
                );
            }
            html.push('</div>');
        }
        if (!rows.length) {
            html.push('<div class="crm-rm-muted">No records to display.</div>');
            html.push('</div>');
            return html.join('');
        }
        if (!options.fullList && block.totalSize > rows.length) {
            html.push('<div class="crm-rm-rl-actions">');
            html.push(
                '<button type="button" class="crm-rm-rl-viewall" data-related-list="' +
                    esc(block.name || '') +
                    '" data-tab-id="' +
                    esc(block.tabId || '') +
                    '" data-related-label="' +
                    esc(block.label || block.name || 'Related records') +
                    '">View All (' +
                    esc(String(block.totalSize)) +
                    ')</button>'
            );
            html.push('</div>');
        }
        html.push('<table class="crm-rm-rl-table"><thead><tr>');
        html.push('<th class="crm-rm-rl-menu" scope="col"><span class="slds-assistive-text">Actions</span></th>');
        html.push('<th class="crm-rm-rl-open" scope="col"><span class="slds-assistive-text">Open</span></th>');
        for (var ci = 0; ci < cols.length; ci++) {
            html.push('<th scope="col">' + relatedListColumnLabel(cols[ci]) + '</th>');
        }
        html.push('</tr></thead><tbody>');
        for (var ri = 0; ri < rows.length; ri++) {
            var row = rows[ri];
            var rowActs = row.actions || [];
            html.push('<tr>');
            html.push(
                '<td class="crm-rm-rl-menu">' +
                    (rowActs.length
                        ? '<button type="button" class="crm-rm-rl-row-menu" data-record-id="' +
                          esc(row.id) +
                          '" data-actions="' +
                          esc(JSON.stringify(rowActs)) +
                          '" title="Actions">⋮</button>'
                        : '') +
                    '</td>'
            );
            html.push('<td class="crm-rm-rl-open">' + openRecordIconBtn(row.id, row.name || row.id) + '</td>');
            for (var cj = 0; cj < cols.length; cj++) {
                var fieldApi = relatedListColumnField(cols[cj]);
                var cellVal = getRelatedCellValue(row, fieldApi);
                var cellHtml = renderRelatedCellValue(cellVal);
                var cellCls = isRenderableHtml(cellVal) ? ' crm-rm-html' : '';
                html.push('<td class="crm-rm-val' + cellCls + '">' + cellHtml + '</td>');
            }
            html.push('</tr>');
        }
        html.push('</tbody></table>');
        if (!options.fullList && block.totalSize > rows.length) {
            html.push(
                '<div class="crm-rm-muted">Showing ' +
                    rows.length +
                    ' of ' +
                    block.totalSize +
                    ' records.</div>'
            );
        }
        html.push('</div>');
        return html.join('');
    }

    function relatedBlocksForTab(tabId, relatedListData) {
        var out = [];
        var blocks = relatedListData || [];
        for (var i = 0; i < blocks.length; i++) {
            if (blocks[i].tabId === tabId) {
                out.push(blocks[i]);
            }
        }
        return out;
    }

    function renderDetailsPanel(layout, values, fieldMeta) {
        var html = [];
        var meta = fieldMeta || {};
        var sections = (layout && layout.detailLayoutSections) || [];
        for (var si = 0; si < sections.length; si++) {
            var sec = sections[si];
            if (sec.useHeading && sec.heading) {
                html.push('<h3 class="crm-rm-sec">' + formatDisplayLabel(sec.heading) + '</h3>');
            }
            html.push('<div class="crm-rm-grid">');
            var rows = sec.layoutRows || [];
            for (var ri = 0; ri < rows.length; ri++) {
                var items = rows[ri].layoutItems || [];
                for (var ii = 0; ii < items.length; ii++) {
                    var item = items[ii];
                    if (item.placeholder) {
                        continue;
                    }
                    var comps = item.layoutComponents || [];
                    for (var ci = 0; ci < comps.length; ci++) {
                        var comp = comps[ci];
                        if (comp.type !== 'Field') {
                            continue;
                        }
                        var fieldApi = comp.value;
                        var details = comp.details || {};
                        var resolvedMeta = resolveFieldMeta(fieldApi, meta);
                        if (resolvedMeta && Object.keys(resolvedMeta).length) {
                            details = Object.assign({}, details, resolvedMeta);
                        }
                        var label = decodeHtmlEntities(item.label || details.label || fieldApi);
                        var type = (details.type || '').toLowerCase();
                        var canEdit = editMode && fieldEditableInModal(fieldApi, details, meta);
                        var changedCls = fieldHasChanged(fieldApi, type) ? ' is-changed' : '';
                        var hintHtml = '';
                        if (fieldHasChanged(fieldApi, type)) {
                            var oldDisp = formatScalarValue(type, originalValues[fieldApi], details);
                            hintHtml =
                                '<div class="crm-rm-change-hint">Was: ' +
                                (String(oldDisp).indexOf('<a ') === 0 || String(oldDisp).indexOf('<br>') >= 0
                                    ? oldDisp
                                    : esc(String(oldDisp))) +
                                '</div>';
                        }
                        var valHtml;
                        if (canEdit) {
                            valHtml =
                                '<div class="crm-rm-val">' +
                                renderFieldInput(fieldApi, details, values, meta) +
                                hintHtml +
                                '</div>';
                        } else {
                            var rendered = renderFieldValue(fieldApi, details, values);
                            var valCls = rendered.isHtml ? ' crm-rm-html' : '';
                            valHtml =
                                '<div class="crm-rm-val' +
                                valCls +
                                '">' +
                                rendered.html +
                                '</div>' +
                                hintHtml;
                        }
                        html.push(
                            '<div class="crm-rm-field' +
                                changedCls +
                                '" data-field="' +
                                esc(fieldApi) +
                                '"><div class="crm-rm-lbl">' +
                                formatDisplayLabel(label) +
                                '</div>' +
                                valHtml +
                                '</div>'
                        );
                    }
                }
            }
            html.push('</div>');
        }
        if (!html.length) {
            return '<div class="crm-rm-muted">No layout sections to display.</div>';
        }
        return html.join('');
    }

    function renderTabPanels(tabs, layout, values, relatedListData, fieldMeta) {
        var html = [];
        for (var ti = 0; ti < tabs.length; ti++) {
            var tab = tabs[ti];
            var panelHtml = '';
            if (tab.type === 'details') {
                panelHtml = renderDetailsPanel(layout, values, fieldMeta);
            } else if (tab.type === 'related' || tab.type === 'relatedMulti') {
                var blocks = relatedBlocksForTab(tab.id, relatedListData);
                if (!blocks.length) {
                    panelHtml = '<div class="crm-rm-tab-loading">Loading related records…</div>';
                } else {
                    var parts = [];
                    for (var bi = 0; bi < blocks.length; bi++) {
                        var block = blocks[bi];
                        if (blocks.length > 1) {
                            block = Object.assign({}, block, { sectionLabel: true });
                        }
                        parts.push(renderRelatedListTable(block));
                    }
                    panelHtml = parts.join('');
                }
            } else if (tab.type === 'activity') {
                var cachedActs =
                    (currentModalData && currentModalData.activities) ||
                    (currentRecordId && activityCacheByRecord[currentRecordId]) ||
                    null;
                panelHtml = cachedActs
                    ? renderActivityPanel(cachedActs)
                    : '<div class="crm-rm-tab-loading">Loading activities…</div>';
            } else if (tab.type === 'salesforcePower') {
                panelHtml = renderSalesforcePowerPanel(currentRecordId || (currentModalData && currentModalData.recordId));
            } else if (tab.type === 'intentInsights') {
                panelHtml = renderIntentInsightsPanel(currentRecordId || (currentModalData && currentModalData.recordId));
            } else if (tab.type === 'duplicates') {
                panelHtml = '<div class="crm-rm-tab-loading">Loading potential duplicates…</div>';
            } else if (tab.type === 'visualforce') {
                panelHtml = renderVisualforcePanel(
                    tab,
                    currentRecordId || (currentModalData && currentModalData.recordId)
                );
            } else if (tab.type === 'rssFeed') {
                panelHtml = renderRssFeedPanel(
                    tab,
                    currentRecordId || (currentModalData && currentModalData.recordId)
                );
            } else {
                var customMsg =
                    tab.message ||
                    'This tab is available in Salesforce Lightning. Open the record in Salesforce for the full experience.';
                var customTitle = tab.componentName
                    ? 'Lightning component: ' + tab.componentName
                    : 'Available in Salesforce Lightning';
                panelHtml =
                    '<div class="crm-rm-custom">' +
                    '<div class="crm-rm-custom-title">' +
                    formatDisplayLabel(tab.label || 'Tab') +
                    '</div>' +
                    '<div class="crm-rm-custom-msg">' +
                    esc(customMsg) +
                    '</div>' +
                    '<div class="crm-rm-muted" style="padding-top:.75rem">' +
                    esc(customTitle) +
                    '</div>' +
                    '</div>';
            }
            html.push(
                '<div class="crm-rm-panel' +
                    (tab.id === activeTabId ? ' is-active' : '') +
                    '" data-tab-id="' +
                    esc(tab.id) +
                    '" role="tabpanel">' +
                    panelHtml +
                    '</div>'
            );
        }
        return html.join('');
    }

    function pathCheckIcon() {
        return (
            '<svg class="crm-rm-path-check" viewBox="0 0 24 24" aria-hidden="true" focusable="false">' +
            '<path fill="currentColor" d="M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4z"/>' +
            '</svg>'
        );
    }

    function renderPath(pathData) {
        if (!pathEl || !pathData || !pathData.steps || !pathData.steps.length) {
            if (pathEl) {
                pathEl.style.display = 'none';
                pathEl.querySelector('.crm-rm-path-inner').innerHTML = '';
            }
            return;
        }
        var steps = pathData.steps;
        var html = [];
        var pathLabel = pathData.pathLabel || pathData.fieldLabel || 'Path';
        html.push('<div class="crm-rm-path-label">' + esc(pathLabel) + '</div>');
        html.push('<div class="crm-rm-path-track"><ul class="crm-rm-path-nav" role="list">');
        for (var i = 0; i < steps.length; i++) {
            var step = steps[i];
            var status = step.status || 'upcoming';
            var cls = 'crm-rm-path-item';
            if (status === 'complete') {
                cls += ' is-complete';
            } else if (status === 'current') {
                cls += ' is-current';
            } else {
                cls += ' is-upcoming';
            }
            html.push('<li class="' + cls + '" role="presentation">');
            html.push('<div class="crm-rm-path-link" aria-current="' + (status === 'current' ? 'step' : 'false') + '">');
            html.push('<span class="crm-rm-path-stage">');
            if (status === 'complete') {
                html.push(pathCheckIcon());
            }
            html.push('<span class="crm-rm-path-title">' + esc(step.label || step.value || '') + '</span>');
            html.push('</span></div></li>');
        }
        html.push('</ul></div>');
        if (pathData.guidanceText) {
            var guidanceBodyCls = 'crm-rm-path-guidance-body';
            if (isRenderableHtml(pathData.guidanceText)) {
                guidanceBodyCls += ' crm-rm-html';
            }
            html.push('<div class="crm-rm-path-guidance">');
            html.push('<div class="crm-rm-path-guidance-title">Guidance for Success</div>');
            html.push('<div class="' + guidanceBodyCls + '">' + renderRelatedCellValue(pathData.guidanceText) + '</div>');
            html.push('</div>');
        }
        pathEl.querySelector('.crm-rm-path-inner').innerHTML = html.join('');
        pathEl.style.display = 'block';
    }

    function renderTabBar(tabs, relatedListData) {
        var html = [];
        for (var i = 0; i < tabs.length; i++) {
            var tab = tabs[i];
            var label = decodeHtmlEntities(tab.label || 'Tab');
            var countSuffix = tabCountLabel(relatedListData, tab);
            var isActive = tab.id === activeTabId;
            html.push(
                '<button type="button" class="crm-rm-tab' +
                    (isActive ? ' is-active' : '') +
                    '" data-tab-id="' +
                    esc(tab.id) +
                    '" role="tab" aria-selected="' +
                    (isActive ? 'true' : 'false') +
                    '">' +
                    formatDisplayLabel(label) +
                    esc(countSuffix) +
                    '</button>'
            );
        }
        return html.join('');
    }

    function defaultActiveTabId(tabs) {
        for (var d = 0; d < tabs.length; d++) {
            if (tabs[d].type === 'details') {
                return tabs[d].id;
            }
        }
        for (var i = 0; i < tabs.length; i++) {
            if (tabs[i].active) {
                return tabs[i].id;
            }
        }
        return tabs.length ? tabs[0].id : 'details';
    }

    function renderModal(data) {
        ensureModal();
        currentModalData = data;
        initDraftState(data.values || {});
        canEditRecord = hasEditableLayoutFields(data.layout, data.fieldMeta || {});
        editMode = false;
        var tabs = ensureDetailsTab(
            data.tabs || [{ id: 'details', label: 'Details', type: 'details', active: true }]
        );
        data.tabs = tabs;
        activeTabId = defaultActiveTabId(tabs);

        titleEl.textContent = decodeHtmlEntities(data.recordName || 'Record');
        subEl.textContent = data.objectLabel || data.objectApi || '';
        modalEl.querySelector('.crm-rm-icon').textContent = objectIconLetters(data.objectApi);

        renderPath(data.path);
        tabBarEl.innerHTML = renderTabBar(tabs, data.relatedListData || []);
        bodyEl.innerHTML = renderTabPanels(
            tabs,
            data.layout,
            draftValues,
            data.relatedListData || [],
            data.fieldMeta || {}
        );
        wireAllDetailsInputs();
        updateFooter();
        modalEl.style.display = 'flex';
    }

    function openRecordModal(recordId, hints) {
        if (!recordId) {
            return;
        }
        hints = hints || {};
        currentRecordId = recordId;
        loadedRelatedTabIds = {};
        relatedListFetchInFlight = {};
        loadedActivityTabIds = {};
        activityFetchInFlight = {};
        activityCacheByRecord = {};
        duplicatesCache = {};
        duplicatesFetchInFlight = {};
        currentModalData = null;
        recordActions = [];
        originalValues = {};
        draftValues = {};
        editMode = false;
        canEditRecord = false;
        showModalShell(hints);

        remotingShell(recordId)
            .then(function (shell) {
                if (shell.error) {
                    showError(shell.error);
                    return Promise.reject(new Error(shell.error));
                }
                updateModalHeader(shell);
                return remotingDetails(recordId);
            })
            .then(function (details) {
                if (!details) {
                    return;
                }
                if (details.error) {
                    showError(details.error);
                    return;
                }
                renderDetailsContent(details);
                if (hints.editOnLoad) {
                    enterEditMode();
                }
                Promise.all([
                    remotingTabs(recordId).catch(function () {
                        return null;
                    }),
                    remotingPath(recordId).catch(function () {
                        return null;
                    })
                ]).then(function (results) {
                    var tabsRes = results[0];
                    var pathRes = results[1];
                    if (tabsRes && !tabsRes.error && tabsRes.tabs) {
                        updateTabsAndPanels(tabsRes);
                    }
                    if (pathRes && !pathRes.error && pathRes.path) {
                        mergeModalData({ path: pathRes.path });
                        renderPath(pathRes.path);
                    }
                });
            })
            .catch(function (err) {
                if (err && err.message && err.message.indexOf('Record Id') >= 0) {
                    return;
                }
                if (bodyEl.querySelector('.crm-rm-error')) {
                    return;
                }
                showError(err && err.message ? err.message : String(err));
            });
    }

    function hintsFromElement(el) {
        if (!el) {
            return {};
        }
        var hints = {};
        var name = el.getAttribute('data-record-name');
        var objectApi = el.getAttribute('data-object-api');
        if (name) {
            hints.recordName = name;
        }
        if (objectApi) {
            hints.objectApi = objectApi;
            hints.objectLabel = objectLabelFromApi(objectApi);
        }
        return hints;
    }

    function openRecordModalFromClick(recordId, ev) {
        var hints = {};
        if (ev && ev.target) {
            var row = ev.target.closest(
                'tr.ch-row, .ch-card, .ch-kan-card, .ch-cal-event, [data-record-id], .ch-open, .ch-open-ico'
            );
            hints = hintsFromElement(row);
            if (!hints.recordName) {
                var btn = ev.target.closest('.ch-open, .ch-open-ico, .ch-kan-card-link, .ch-card-link');
                if (btn && btn.textContent) {
                    hints.recordName = btn.textContent.trim();
                }
            }
        }
        openRecordModal(recordId, hints);
    }

    function recordIdFromClick(ev) {
        if (
            ev.target.closest(
                '.ch-edit-ico, .ch-ed, .ch-col-filter, .ch-sort-btn, .ch-global-search, .ch-cal-prev, .ch-cal-next, .ch-cal-today, .ch-cal-date-field, .ch-score-badge, .ch-score-wrap, .ch-score-modal-overlay, input, textarea, select, button.crm-rm-close, .crm-rm-tab, .crm-rm-footer, .crm-rm-save, .crm-rm-cancel, .crm-rm-edit, .crm-rm-input'
            )
        ) {
            return null;
        }
        var openBtn = ev.target.closest('.ch-open-ico, .ch-open, [data-crm-record-id], [data-cog-id], .ch-cal-event');
        if (openBtn) {
            var openId =
                openBtn.getAttribute('data-id') ||
                openBtn.getAttribute('data-crm-record-id') ||
                openBtn.getAttribute('data-cog-id') ||
                openBtn.getAttribute('data-record-id');
            if (openId && openId.length >= 15) {
                return openId;
            }
        }
        var row = ev.target.closest('tr.ch-row, .ch-card, .ch-kan-card, .ch-cal-event, [data-record-id]');
        if (row) {
            var rid = row.getAttribute('data-record-id');
            if (!rid) {
                var btn = row.querySelector('.ch-open');
                rid = btn ? btn.getAttribute('data-id') : '';
            }
            if (rid && rid.length >= 15) {
                return rid;
            }
        }
        return null;
    }

    function wireGlobalClicks() {
        if (wired) {
            return;
        }
        wired = true;
        document.addEventListener('click', function (ev) {
            if (modalEl && modalEl.style.display !== 'none' && modalEl.contains(ev.target)) {
                return;
            }
            var anchor = ev.target.closest('a[href]');
            if (anchor && !anchor.classList.contains('ch-open')) {
                var hrefId = sfIdFromHref(anchor.getAttribute('href'));
                if (hrefId) {
                    ev.preventDefault();
                    ev.stopPropagation();
                    openRecordModalFromClick(hrefId, ev);
                    return;
                }
            }
            var rid = recordIdFromClick(ev);
            if (!rid) {
                return;
            }
            ev.preventDefault();
            ev.stopPropagation();
            openRecordModalFromClick(rid, ev);
        });
    }

    global.crmHubOpenRecordModal = openRecordModal;
    global.crmHubAlert = hubAlert;
    global.crmHubConfirm = hubConfirm;
    global.CrmHubRecordModal = {
        open: openRecordModal,
        close: closeModal,
        wire: wireGlobalClicks,
        alert: hubAlert,
        confirm: hubConfirm
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', wireGlobalClicks);
    } else {
        wireGlobalClicks();
    }
})(this);
