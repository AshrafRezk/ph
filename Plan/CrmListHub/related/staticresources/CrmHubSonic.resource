/* global Visualforce, crmHubOpenRecordModal */
(function (global) {
  'use strict';

  var STORAGE_KEY = 'cloudastickSonic_lastListViewId';
  var ICON_FALLBACK = '/resource/email';

  var TAKEN_ACTION_SHORTCUTS = [
    { code: 'C', desc: 'Call Done', icon: 'call' },
    { code: 'W', desc: 'Log WhatsApp', icon: 'chat' },
    { code: 'E', desc: 'Email body', icon: 'mail' },
    { code: 'L', desc: 'Log LinkedIn', icon: 'work' },
    { code: 'NA', desc: 'No answer log', icon: 'phone_disabled' },
    { code: 'NE', desc: 'No answer — send email', icon: 'forward_to_inbox' },
    { code: 'ES', desc: 'Email Sent (Externally)', icon: 'mark_email_read' },
    { code: 'R', desc: 'Create Requirement', icon: 'assignment' },
    { code: 'CLS', desc: 'Close Opportunity', icon: 'flag', confirm: true },
    { code: 'DEL', desc: 'Delete the Opportunity', icon: 'delete', confirm: true }
  ];

  var MANAGE_ACTIONS = [
    { id: 'setAe', label: 'Set AE', icon: 'person' },
    { id: 'setEmail', label: 'Set Email', icon: 'alternate_email' },
    { id: 'setLinkedIn', label: 'Set LinkedIn', icon: 'link' },
    { id: 'setMobile', label: 'Set Mobile', icon: 'smartphone' },
    { id: 'changeOwner', label: 'Change Owner', icon: 'key' },
    { id: 'teamMember', label: 'Add/Remove Member', icon: 'group' }
  ];

  var state = {
    listViews: [],
    listViewSearch: '',
    selectedListViewId: '',
    selectedListViewLabel: '',
    pickerExpanded: true,
    opportunities: [],
    currentIndex: 0,
    totalInListView: 0,
    queueTruncated: false,
    takenAction: '',
    daysToPush: '',
    nextStep: '',
    selectedStage: '',
    encouragementIdea: '',
    baselineTakenAction: '',
    baselineDaysToPush: '',
    baselineNextStep: '',
    baselineStage: '',
    stageOptions: [],
    isLoadingListViews: false,
    isLoadingQueue: false,
    loadError: '',
    saveStatus: '',
    pendingSaves: 0,
    failedSaveMessage: '',
    actionModalOpen: false,
    pendingActionCode: '',
    actionModalText: '',
    pendingWhatsAppUrl: '',
    pendingWhatsAppPrefix: '',
    manageModalOpen: false,
    manageActionId: '',
    manageSearch: '',
    manageSearchResults: [],
    manageFieldValue: '',
    manageBusy: false,
    manageError: '',
    emailDraftOpen: false,
    emailDraftSubject: '',
    emailDraftBody: '',
    emailDraftBusy: false,
    emailDraftError: '',
    apolloBusy: false,
    apolloMessage: '',
    contactRoleOptions: [],
    selectedContactId: '',
    opportunityPrimaryContactId: '',
    activeContact: null,
    contactRoleBusy: false,
    swipeStartX: 0,
    swipeStartY: 0,
    swipeDeltaX: 0,
    isSwiping: false,
    cardAnimating: false,
    audioContext: null,
    viewportMode: 'desktop',
    mobileTab: 'overview',
    summaryExpanded: false,
    sectionContextOpen: true,
    sectionPeopleOpen: true,
    sectionUpdateOpen: true,
    activated: false,
    boundResize: null,
    eventsBound: false,
    resizeObserver: null
  };

  /* ── Quick contact link helpers (from quickContactLinks.js) ── */

  function decodeHtmlEntities(value) {
    if (!value) return '';
    var cur = String(value);
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

  function esc(s) {
    if (s == null) return '';
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function escPlain(s) {
    return esc(decodeHtmlEntities(s == null ? '' : String(s)));
  }

  function decodeQueryParam(value) {
    if (!value) return '';
    try {
      return decodeURIComponent(String(value).replace(/\+/g, '%20'));
    } catch (e) {
      return String(value).replace(/\+/g, ' ');
    }
  }

  function resolveLinkType(url) {
    if (!url) return 'web';
    if (url.indexOf('tel:') === 0) return 'tel';
    if (/wa\.me|whatsapp:\/\//i.test(url)) return 'whatsapp';
    if (url.indexOf('mailto:') === 0) return 'email';
    if (/^\/[a-zA-Z0-9]{15,18}/.test(url)) return 'record';
    return 'web';
  }

  function normalizeQuickContactUrl(url, html) {
    if (!url) return url;
    if (url.indexOf('Vlog_whatsapp') !== -1) {
      var phoneMatch = html.match(/whatsapp:\/\/send\/\?phone=([0-9]+)/i);
      var msgMatch = url.match(/c__defaultMsg=([^&]+)/i);
      var phone = phoneMatch ? phoneMatch[1] : null;
      var msg = msgMatch ? decodeQueryParam(msgMatch[1]) : '';
      if (phone) {
        return msg
          ? 'https://wa.me/' + phone + '?text=' + encodeURIComponent(msg)
          : 'https://wa.me/' + phone;
      }
    }
    if (url.indexOf('whatsapp://') === 0) {
      var p = url.match(/phone=([0-9]+)/i);
      var tMatch = url.match(/text=([^&]+)/i);
      var ph = p ? p[1] : null;
      var text = tMatch ? decodeQueryParam(tMatch[1]) : '';
      if (ph) {
        return text
          ? 'https://wa.me/' + ph + '?text=' + encodeURIComponent(text)
          : 'https://wa.me/' + ph;
      }
    }
    return url;
  }

  function parseQuickContactHtml(html) {
    var links = [];
    if (!html) return links;
    var anchorRegex = /<a\b[^>]*\bhref=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
    var anchorMatch = anchorRegex.exec(html);
    while (anchorMatch) {
      var rawUrl = decodeHtmlEntities(anchorMatch[1]);
      var inner = anchorMatch[2];
      var imgTagMatch = inner.match(/<img\b[^>]*>/i);
      if (!imgTagMatch) {
        anchorMatch = anchorRegex.exec(html);
        continue;
      }
      var imgTag = imgTagMatch[0];
      var srcMatch = imgTag.match(/\bsrc=["']([^"']+)["']/i);
      if (!srcMatch) {
        anchorMatch = anchorRegex.exec(html);
        continue;
      }
      var altMatch = imgTag.match(/\balt=["']([^"']*)["']/i);
      var url = normalizeQuickContactUrl(rawUrl, html);
      links.push({
        key: url + '-' + links.length,
        url: url,
        icon: srcMatch[1] || ICON_FALLBACK,
        title: altMatch ? altMatch[1] : 'Open',
        type: resolveLinkType(url)
      });
      anchorMatch = anchorRegex.exec(html);
    }
    return links;
  }

  function mapApexQuickLinks(links) {
    if (!links || !links.length) return [];
    return links.map(function (row) {
      return {
        key: row.key,
        url: row.url,
        icon: row.iconPath,
        title: row.title,
        type: row.type
      };
    });
  }

  function linkDedupeKey(link) {
    return String((link && (link.url || link.key || link.title)) || '')
      .trim()
      .toLowerCase();
  }

  function linkFamily(link) {
    var type = String((link && link.type) || '').toLowerCase();
    var key = String((link && link.key) || '').toLowerCase();
    var title = String((link && link.title) || '').toLowerCase();
    var url = String((link && link.url) || '').toLowerCase();
    if (type === 'tel' || key.indexOf('call') === 0 || url.indexOf('tel:') === 0) return 'call';
    if (type === 'whatsapp' || key.indexOf('wa') !== -1 || /wa\.me|whatsapp/i.test(url) || title.indexOf('whatsapp') !== -1) return 'whatsapp';
    if (type === 'email' || key.indexOf('gmail') !== -1 || key.indexOf('email') !== -1 || url.indexOf('mailto:') === 0 || /mail\.google|mailto:/i.test(url) || title.indexOf('email') !== -1) return 'email';
    if (key.indexOf('li-') !== -1 || key.indexOf('linkedin') !== -1 || /linkedin/i.test(url)) return 'linkedin';
    if (key === 'cv' || title.indexOf('cv') !== -1) return 'cv';
    if (key === 'fb' || title.indexOf('fb') !== -1 || /facebook/i.test(url)) return 'fb';
    return linkDedupeKey(link) || 'other';
  }

  var FAMILY_PRIORITY = {
    call: ['call-mobile', 'call-phone'],
    whatsapp: ['wa-direct', 'wa-agent'],
    email: ['gmail-compose', 'gmail-find'],
    linkedin: ['li-profile', 'li-search'],
    cv: ['cv'],
    fb: ['fb']
  };

  function familyRank(family, link) {
    var prefs = FAMILY_PRIORITY[family] || [];
    var key = String((link && link.key) || '').toLowerCase();
    var idx = prefs.indexOf(key);
    if (idx >= 0) return idx;
    if (family === 'email' && /find|search/i.test((link && link.title) || '')) return 50;
    return 10;
  }

  function collapseQuickLinksByFamily(links) {
    var bestByFamily = {};
    (links || []).forEach(function (link) {
      if (!link || !link.url) return;
      var family = linkFamily(link);
      var existing = bestByFamily[family];
      if (!existing || familyRank(family, link) < familyRank(family, existing)) {
        var copy = {};
        for (var k in link) if (Object.prototype.hasOwnProperty.call(link, k)) copy[k] = link[k];
        copy.key = link.key || family;
        bestByFamily[family] = copy;
      }
    });
    var order = ['call', 'whatsapp', 'email', 'linkedin', 'cv', 'fb'];
    var ordered = [];
    order.forEach(function (family) {
      if (bestByFamily[family]) {
        ordered.push(bestByFamily[family]);
        delete bestByFamily[family];
      }
    });
    Object.keys(bestByFamily).forEach(function (f) {
      ordered.push(bestByFamily[f]);
    });
    return ordered;
  }

  function mergeQuickLinks() {
    var lists = Array.prototype.slice.call(arguments);
    var merged = [];
    var seen = {};
    lists.forEach(function (list) {
      (list || []).forEach(function (link) {
        if (!link || !link.url) return;
        var dedupeKey = linkDedupeKey(link);
        if (seen[dedupeKey]) return;
        seen[dedupeKey] = true;
        merged.push(link);
      });
    });
    return collapseQuickLinksByFamily(merged);
  }

  function extractWaMeParts(url) {
    var m = String(url).match(/wa\.me\/([0-9]+)/i);
    var phone = m ? m[1] : null;
    var textMatch = String(url).match(/[?&]text=([^&]*)/i);
    var text = textMatch ? decodeQueryParam(textMatch[1]) : '';
    return { phone: phone, text: text };
  }

  function extractWhatsAppProtocolParts(url) {
    var m = String(url).match(/phone=([0-9]+)/i);
    var phone = m ? m[1] : null;
    var textMatch = String(url).match(/[?&]text=([^&]*)/i);
    var text = textMatch ? decodeQueryParam(textMatch[1]) : '';
    return { phone: phone, text: text };
  }

  /* ── Utilities ── */

  function remoting(method) {
    var args = Array.prototype.slice.call(arguments, 1);
    return new Promise(function (resolve, reject) {
      if (typeof Visualforce === 'undefined' || !Visualforce.remoting) {
        reject(new Error('Visualforce remoting unavailable'));
        return;
      }
      var cb = function (result, event) {
        if (event && event.status) {
          resolve(result);
        } else {
          reject(new Error((event && event.message) || 'Remoting failed'));
        }
      };
      args.push(cb);
      args.push({ escape: false, timeout: 120000 });
      try {
        Visualforce.remoting.Manager.invokeAction.apply(
          Visualforce.remoting.Manager,
          ['CrmHubListController.' + method].concat(args)
        );
      } catch (err) {
        reject(err);
      }
    });
  }

  function haptic(kind) {
    if (!navigator.vibrate) return;
    try {
      if (kind === 'tap') navigator.vibrate(12);
      else if (kind === 'success') navigator.vibrate([14, 42, 14]);
      else if (kind === 'milestone') navigator.vibrate([18, 32, 18, 32, 22]);
    } catch (e) { /* ignore */ }
  }

  function ms(name) {
    return '<span class="material-symbols-outlined" aria-hidden="true">' + name + '</span>';
  }

  function root() {
    return document.getElementById('sonic-root');
  }

  function reduceError(error) {
    if (!error) return 'Unexpected error';
    if (Array.isArray(error.body)) {
      return error.body.map(function (row) { return row.message; }).join(', ');
    }
    return (error.body && error.body.message) || error.message || 'Unexpected error';
  }

  function normalizeNumber(value) {
    if (value === null || value === undefined || value === '') return '';
    return String(value);
  }

  function isDirty() {
    return (
      state.takenAction !== state.baselineTakenAction ||
      normalizeNumber(state.daysToPush) !== normalizeNumber(state.baselineDaysToPush) ||
      (state.nextStep || '') !== (state.baselineNextStep || '') ||
      (state.selectedStage || '') !== (state.baselineStage || '')
    );
  }

  function currentOpportunity() {
    return state.opportunities[state.currentIndex] || null;
  }

  function isMobileUa() {
    return /iPhone|iPad|iPod|Android|Mobile/i.test(navigator.userAgent || '');
  }

  function openRecord(recordId) {
    if (!recordId) return;
    if (typeof global.crmHubOpenRecordModal === 'function') {
      global.crmHubOpenRecordModal(recordId);
      return;
    }
    window.open('/' + recordId, '_blank');
  }

  function openNativeUrl(url) {
    var anchor = document.createElement('a');
    anchor.href = url;
    anchor.style.display = 'none';
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
  }

  function openWebPage(url) {
    window.open(url, '_blank', 'noopener,noreferrer');
  }

  function readStoredListViewId() {
    try {
      return window.localStorage.getItem(STORAGE_KEY) || '';
    } catch (e) {
      return '';
    }
  }

  function storeListViewId(listViewId) {
    try {
      if (listViewId) window.localStorage.setItem(STORAGE_KEY, listViewId);
    } catch (e) { /* ignore */ }
  }

  function updateViewportMode() {
    var el = root();
    var width = (el && el.clientWidth) || window.innerWidth;
    var nextMode = width < 640 ? 'phone' : width < 1024 ? 'tablet' : 'desktop';
    if (nextMode !== state.viewportMode) {
      state.viewportMode = nextMode;
      if (nextMode !== 'phone') state.mobileTab = 'overview';
      render();
    }
  }

  function filteredListViews() {
    var term = (state.listViewSearch || '').trim().toLowerCase();
    if (!term) return state.listViews;
    return state.listViews.filter(function (row) {
      return (row.label || '').toLowerCase().indexOf(term) !== -1;
    });
  }

  function progressLabel() {
    if (!state.opportunities.length) return '0 / 0';
    return Math.min(state.currentIndex + 1, state.opportunities.length) + ' / ' + state.opportunities.length;
  }

  function progressPercent() {
    if (!state.opportunities.length) return 0;
    return Math.round(
      (Math.min(state.currentIndex + 1, state.opportunities.length) / state.opportunities.length) * 100
    );
  }

  function isShortcutActive(code) {
    var value = state.takenAction || '';
    if (code === 'DEL' || code === 'CLS') return value === code || value.indexOf(code) === 0;
    return value.indexOf(code + ':') === 0;
  }

  function extractActionBody(code) {
    if (!state.takenAction) return '';
    var prefix = code + ':';
    if (state.takenAction.indexOf(prefix) !== 0) return '';
    return state.takenAction.substring(prefix.length);
  }

  function parseActionDate(value) {
    if (value === null || value === undefined || value === '') return null;
    if (value instanceof Date && !isNaN(value.getTime())) {
      return new Date(value.getFullYear(), value.getMonth(), value.getDate());
    }
    if (typeof value === 'number' && isFinite(value)) {
      var fromNum = new Date(value);
      if (!isNaN(fromNum.getTime())) {
        return new Date(fromNum.getFullYear(), fromNum.getMonth(), fromNum.getDate());
      }
    }
    var raw = String(value).trim();
    if (/^\d{10,13}$/.test(raw)) {
      var ms = Number(raw.length === 10 ? raw + '000' : raw);
      var fromEpoch = new Date(ms);
      if (!isNaN(fromEpoch.getTime())) {
        return new Date(fromEpoch.getFullYear(), fromEpoch.getMonth(), fromEpoch.getDate());
      }
    }
    var parts = raw.split('-');
    if (parts.length === 3) {
      var y = Number(parts[0]);
      var m = Number(parts[1]);
      var d = Number(parts[2]);
      if (y && m && d) return new Date(y, m - 1, d);
    }
    var parsed = new Date(raw);
    if (!isNaN(parsed.getTime())) {
      return new Date(parsed.getFullYear(), parsed.getMonth(), parsed.getDate());
    }
    return null;
  }

  function formatDate(value) {
    var date = parseActionDate(value);
    if (!date) return value ? String(value) : '—';
    return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  }

  function formatRelativeActionDate(value) {
    var target = parseActionDate(value);
    if (!target) return '—';
    var today = new Date();
    today.setHours(0, 0, 0, 0);
    var diffDays = Math.round((target - today) / 86400000);
    if (diffDays === 0) return 'today';
    if (diffDays === 1) return 'tomorrow';
    if (diffDays === -1) return 'yesterday';
    if (diffDays < -1) return Math.abs(diffDays) + ' days ago';
    return 'in ' + diffDays + ' days';
  }

  function fixQuickContactHtml(html) {
    if (!html) return '';
    var fixed = String(html);
    var phoneMatch = fixed.match(/whatsapp:\/\/send\/\?phone=([0-9]+)/i);
    var waPhone = phoneMatch ? phoneMatch[1] : null;
    if (waPhone) {
      var waUrl = 'https://wa.me/' + waPhone;
      fixed = fixed.replace(/href="[^"]*Vlog_whatsapp[^"]*"/gi, 'href="' + waUrl + '" target="_blank" rel="noopener noreferrer"');
      fixed = fixed.replace(/href='[^']*Vlog_whatsapp[^']*'/gi, "href='" + waUrl + "' target='_blank' rel='noopener noreferrer'");
      fixed = fixed.replace(/href="whatsapp:\/\/[^"]*"/gi, 'href="' + waUrl + '" target="_blank" rel="noopener noreferrer"');
      fixed = fixed.replace(/href='whatsapp:\/\/[^']*'/gi, "href='" + waUrl + "' target='_blank' rel='noopener noreferrer'");
    }
    return fixed;
  }

  function buildPersonRow(person) {
    if (!person || !person.recordId) return null;
    return { recordId: person.recordId, name: person.name, firstName: person.firstName };
  }

  function activeContactPerson() {
    return state.activeContact || (currentOpportunity() && currentOpportunity().primaryContact) || null;
  }

  function contactHtmlFixed() {
    var person = activeContactPerson();
    var opp = currentOpportunity();
    var isOppPrimary = person && person.recordId && person.recordId === state.opportunityPrimaryContactId;
    var html = isOppPrimary
      ? (opp && (opp.primaryContactDetails || (person && person.quickContactDetailsHtml)))
      : (person && person.quickContactDetailsHtml);
    return fixQuickContactHtml(html);
  }

  function aeHtmlFixed() {
    var opp = currentOpportunity();
    if (!opp) return '';
    var html = opp.primaryAeDetails || (opp.primaryAe && opp.primaryAe.quickContactDetailsHtml);
    return fixQuickContactHtml(html);
  }

  function resolveQuickLinks(person, html) {
    var apexLinks = mapApexQuickLinks(person && person.quickLinks);
    var htmlLinks = parseQuickContactHtml(fixQuickContactHtml(html));
    return mergeQuickLinks(apexLinks, htmlLinks);
  }

  function contactQuickLinks() {
    return resolveQuickLinks(activeContactPerson(), contactHtmlFixed());
  }

  function aeQuickLinks() {
    var opp = currentOpportunity();
    return resolveQuickLinks(opp && opp.primaryAe, aeHtmlFixed());
  }

  function parseDaysToPush() {
    var value = normalizeNumber(state.daysToPush);
    if (value === '') return null;
    var parsed = Number(value);
    return isNaN(parsed) ? null : parsed;
  }

  function getWhatsAppPrefix(url) {
    if (String(url).indexOf('whatsapp://') === 0) {
      return extractWhatsAppProtocolParts(url).text || '';
    }
    return extractWaMeParts(url).text || '';
  }

  /* ── Data loading ── */

  function loadStageOptions() {
    return remoting('sonicGetOpportunityStageOptions')
      .then(function (rows) {
        state.stageOptions = (rows || []).map(function (row) {
          return { label: row.label, value: row.value };
        });
      })
      .catch(function () {
        state.stageOptions = [];
      });
  }

  function loadListViews() {
    state.isLoadingListViews = true;
    state.loadError = '';
    render();
    return remoting('sonicGetOpportunityListViews')
      .then(function (rows) {
        state.listViews = rows || [];
        var remembered = readStoredListViewId();
        if (
          remembered &&
          state.listViews.some(function (row) {
            return row.id === remembered;
          })
        ) {
          state.selectedListViewId = remembered;
          state.pickerExpanded = false;
          return loadQueue(remembered);
        }
        return null;
      })
      .catch(function (error) {
        state.loadError = reduceError(error);
      })
      .then(function () {
        state.isLoadingListViews = false;
        render();
      });
  }

  function loadQueue(listViewId) {
    state.isLoadingQueue = true;
    state.loadError = '';
    state.opportunities = [];
    state.currentIndex = 0;
    render();
    return remoting('sonicGetOpportunityQueue', listViewId)
      .then(function (result) {
        state.opportunities = (result && result.opportunities) || [];
        state.totalInListView = (result && result.totalInListView) || 0;
        state.queueTruncated = !!(result && result.truncated);
        state.selectedListViewLabel = (result && result.listViewLabel) || 'List view';
        syncFormFromCurrent();
      })
      .catch(function (error) {
        state.loadError = reduceError(error);
      })
      .then(function () {
        state.isLoadingQueue = false;
        render();
      });
  }

  function reloadCurrentCardQuietly() {
    if (!state.selectedListViewId) return Promise.resolve();
    var index = state.currentIndex;
    return remoting('sonicGetOpportunityQueue', state.selectedListViewId)
      .then(function (result) {
        state.opportunities = (result && result.opportunities) || [];
        state.totalInListView = (result && result.totalInListView) || 0;
        state.queueTruncated = !!(result && result.truncated);
        state.currentIndex = Math.min(index, Math.max(state.opportunities.length - 1, 0));
        syncFormFromCurrent();
        render();
      })
      .catch(function (error) {
        state.failedSaveMessage = reduceError(error);
        render();
      });
  }

  function syncFormFromCurrent() {
    var opp = currentOpportunity();
    state.takenAction = (opp && opp.takenAction) || '';
    state.daysToPush =
      !opp || opp.numberOfDaysToPush === null || opp.numberOfDaysToPush === undefined
        ? ''
        : String(opp.numberOfDaysToPush);
    state.nextStep = (opp && opp.nextStep) || '';
    state.selectedStage = (opp && opp.stageName) || '';
    state.encouragementIdea = '';
    state.apolloMessage = '';
    state.apolloBusy = false;
    state.contactRoleBusy = false;
    state.opportunityPrimaryContactId = (opp && opp.primaryContact && opp.primaryContact.recordId) || '';
    state.selectedContactId = state.opportunityPrimaryContactId;
    state.activeContact = (opp && opp.primaryContact) || null;
    state.baselineTakenAction = state.takenAction;
    state.baselineDaysToPush = state.daysToPush;
    state.baselineNextStep = state.nextStep;
    state.baselineStage = state.selectedStage;
    state.summaryExpanded = false;
    state.sectionContextOpen = true;
    state.sectionPeopleOpen = true;
    state.sectionUpdateOpen = true;
    if (state.viewportMode === 'phone') state.mobileTab = 'overview';
    closeActionModal(false);
    closeManageModal(false);
    closeEmailDraft(false);
    loadContactRoles();
  }

  function loadContactRoles() {
    var opp = currentOpportunity();
    if (!opp || !opp.id) {
      state.contactRoleOptions = [];
      return Promise.resolve();
    }
    return remoting('sonicGetOpportunityContactRoles', opp.id)
      .then(function (rows) {
        rows = rows || [];
        state.contactRoleOptions = rows.map(function (row) {
          return {
            label: row.isPrimary ? row.label + ' (primary)' : row.label,
            value: row.contactId,
            isPrimary: !!row.isPrimary
          };
        });
        var primary = null;
        for (var i = 0; i < rows.length; i++) {
          if (rows[i].isPrimary) { primary = rows[i]; break; }
        }
        if (primary && primary.contactId) {
          state.opportunityPrimaryContactId = primary.contactId;
        }
        if (!state.selectedContactId) {
          state.selectedContactId =
            state.opportunityPrimaryContactId || (rows[0] && rows[0].contactId) || '';
        }
        if (state.selectedContactId && (!state.activeContact || state.selectedContactId !== state.activeContact.recordId)) {
          return loadActiveContact(state.selectedContactId);
        }
      })
      .catch(function (error) {
        state.contactRoleOptions = [];
        state.failedSaveMessage = reduceError(error);
      })
      .then(function () {
        render();
      });
  }

  function loadActiveContact(contactId) {
    if (!contactId) {
      state.activeContact = null;
      return Promise.resolve();
    }
    var opp = currentOpportunity();
    var oppPrimary = opp && opp.primaryContact;
    if (oppPrimary && oppPrimary.recordId === contactId) {
      state.activeContact = oppPrimary;
      return Promise.resolve();
    }
    return remoting('sonicGetContactPersonActions', contactId)
      .then(function (person) {
        state.activeContact = person || null;
      })
      .catch(function (error) {
        state.activeContact = null;
        state.failedSaveMessage = reduceError(error);
      });
  }

  /* ── Save / advance ── */

  function enqueueBackgroundSave() {
    var opp = currentOpportunity();
    if (!opp || !isDirty()) return;
    var takenActionChanged = state.takenAction !== state.baselineTakenAction;
    var daysToPushChanged = normalizeNumber(state.daysToPush) !== normalizeNumber(state.baselineDaysToPush);
    var nextStepChanged = (state.nextStep || '') !== (state.baselineNextStep || '');
    var stageNameChanged = (state.selectedStage || '') !== (state.baselineStage || '');
    state.pendingSaves += 1;
    state.saveStatus = 'Saving…';
    render();
    remoting(
      'sonicSaveOpportunityUpdate',
      opp.id,
      state.takenAction,
      parseDaysToPush(),
      state.nextStep,
      takenActionChanged,
      daysToPushChanged,
      nextStepChanged,
      state.selectedStage,
      stageNameChanged
    )
      .then(function () {
        state.failedSaveMessage = '';
        state.saveStatus = state.pendingSaves > 1 ? 'Saving…' : 'Saved';
        playSaveSound();
        haptic('success');
        window.setTimeout(function () {
          if (state.saveStatus === 'Saved') {
            state.saveStatus = '';
            render();
          }
        }, 1800);
      })
      .catch(function (error) {
        state.failedSaveMessage = reduceError(error);
        state.saveStatus = 'Save failed';
      })
      .then(function () {
        state.pendingSaves = Math.max(0, state.pendingSaves - 1);
        render();
      });
  }

  function playSaveSound() {
    try {
      var AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) return;
      if (!state.audioContext) state.audioContext = new AudioCtx();
      var ctx = state.audioContext;
      if (ctx.state === 'suspended') ctx.resume();
      var now = ctx.currentTime;
      var tones = [
        { frequency: 880, start: 0, duration: 0.09, volume: 0.18 },
        { frequency: 1174.66, start: 0.06, duration: 0.11, volume: 0.16 },
        { frequency: 1567.98, start: 0.12, duration: 0.16, volume: 0.14 }
      ];
      tones.forEach(function (tone) {
        var osc = ctx.createOscillator();
        var gain = ctx.createGain();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(tone.frequency, now + tone.start);
        gain.gain.setValueAtTime(0.0001, now + tone.start);
        gain.gain.exponentialRampToValueAtTime(tone.volume, now + tone.start + 0.015);
        gain.gain.exponentialRampToValueAtTime(0.0001, now + tone.start + tone.duration);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now + tone.start);
        osc.stop(now + tone.start + tone.duration + 0.02);
      });
    } catch (e) { /* optional */ }
  }

  function advanceQueue() {
    enqueueBackgroundSave();
    state.currentIndex += 1;
    syncFormFromCurrent();
    if (state.currentIndex >= state.opportunities.length) haptic('milestone');
    else haptic('tap');
  }

  function animateAdvance(card) {
    state.cardAnimating = true;
    if (card) {
      card.style.transition = 'transform 280ms cubic-bezier(.2,.8,.2,1), opacity 280ms ease';
      card.style.transform = 'translateX(-130%) rotate(-18deg)';
      card.style.opacity = '0';
      setStampOpacity(card, 1, 0);
    }
    window.setTimeout(function () {
      advanceQueue();
      resetCardMotion(card);
      state.cardAnimating = false;
      render();
    }, 290);
  }

  function animateRetreat(card) {
    state.cardAnimating = true;
    if (card) {
      card.style.transition = 'transform 280ms cubic-bezier(.2,.8,.2,1), opacity 280ms ease';
      card.style.transform = 'translateX(130%) rotate(18deg)';
      card.style.opacity = '0';
      setStampOpacity(card, 0, 1);
    }
    window.setTimeout(function () {
      state.currentIndex -= 1;
      syncFormFromCurrent();
      haptic('tap');
      state.cardAnimating = false;
      render();
      window.requestAnimationFrame(function () {
        var c = root() && root().querySelector('.sonic-card.is-top');
        if (c) {
          c.style.transition = 'none';
          c.style.transform = 'translateX(120%) rotate(12deg)';
          c.style.opacity = '0';
          window.requestAnimationFrame(function () {
            c.style.transition = 'transform 280ms cubic-bezier(.2,.8,.2,1), opacity 280ms ease';
            c.style.transform = '';
            c.style.opacity = '';
          });
        }
      });
    }, 290);
  }

  function setStampOpacity(card, nextOpacity, backOpacity) {
    if (!card) return;
    var nextStamp = card.querySelector('.stamp-next');
    var backStamp = card.querySelector('.stamp-back');
    if (nextStamp) nextStamp.style.opacity = String(nextOpacity);
    if (backStamp) backStamp.style.opacity = String(backOpacity);
  }

  function applySwipeTransform(card, visualDelta) {
    if (!card) return;
    var rot = visualDelta / 22;
    var abs = Math.abs(visualDelta);
    card.style.transition = 'none';
    card.style.transform = 'translateX(' + visualDelta + 'px) rotate(' + rot + 'deg)';
    card.style.opacity = String(Math.max(0.55, 1 - abs / 520));
    var nextOpacity = visualDelta < 0 ? Math.min(1, abs / 100) : 0;
    var backOpacity = visualDelta > 0 ? Math.min(1, abs / 100) : 0;
    setStampOpacity(card, nextOpacity, backOpacity);
  }

  function resetCardMotion(card) {
    if (!card) return;
    card.style.transition = '';
    card.style.transform = '';
    card.style.opacity = '';
    setStampOpacity(card, 0, 0);
  }

  /* ── Modals / actions ── */

  function closeActionModal(doRender) {
    state.actionModalOpen = false;
    state.pendingActionCode = '';
    state.actionModalText = '';
    state.pendingWhatsAppUrl = '';
    state.pendingWhatsAppPrefix = '';
    if (doRender !== false) render();
  }

  function closeManageModal(doRender) {
    state.manageModalOpen = false;
    state.manageActionId = '';
    state.manageError = '';
    state.manageBusy = false;
    if (doRender !== false) render();
  }

  function closeEmailDraft(doRender) {
    state.emailDraftOpen = false;
    state.emailDraftError = '';
    state.emailDraftBusy = false;
    if (doRender !== false) render();
  }

  function openWhatsAppWithUserMessage(url, userBody) {
    var phone = null;
    var prefix = state.pendingWhatsAppPrefix || getWhatsAppPrefix(url);
    if (String(url).indexOf('whatsapp://') === 0) {
      phone = extractWhatsAppProtocolParts(url).phone;
    } else {
      phone = extractWaMeParts(url).phone;
    }
    if (!phone) return;
    var message = userBody ? prefix + userBody : (prefix || '').trim();
    var directUrl = 'whatsapp://send?phone=' + phone + '&text=' + encodeURIComponent(message);
    if (isMobileUa()) {
      openNativeUrl(directUrl);
      return;
    }
    openWebPage('https://wa.me/' + phone + '?text=' + encodeURIComponent(message));
  }

  function openWhatsApp(url) {
    var phone = null;
    var text = '';
    if (String(url).indexOf('whatsapp://') === 0) {
      var parts = extractWhatsAppProtocolParts(url);
      phone = parts.phone;
      text = parts.text;
    } else {
      var parts2 = extractWaMeParts(url);
      phone = parts2.phone;
      text = parts2.text;
    }
    if (!phone) {
      openWebPage(url);
      return;
    }
    var directUrl = 'whatsapp://send?phone=' + phone;
    if (text) directUrl += '&text=' + encodeURIComponent(text);
    if (isMobileUa()) {
      openNativeUrl(directUrl);
      return;
    }
    var webUrl = text
      ? 'https://wa.me/' + phone + '?text=' + encodeURIComponent(text)
      : 'https://wa.me/' + phone;
    openWebPage(webUrl);
  }

  function openQuickLink(url, linkType) {
    if (!url) return;
    if (linkType === 'record') {
      var recordId = url.replace(/^\//, '').split('?')[0];
      if (recordId) openRecord(recordId);
      return;
    }
    if (linkType === 'tel') {
      openNativeUrl(url);
      return;
    }
    if (linkType === 'email') {
      if (String(url).indexOf('mailto:') === 0) openNativeUrl(url);
      else openWebPage(url);
      return;
    }
    if (linkType === 'whatsapp') {
      openWhatsApp(url);
      return;
    }
    openWebPage(url);
  }

  /* ── Render ── */

  function sectionClass(base, openFlag, phoneTab) {
    var parts = ['panel-section', base];
    if (state.viewportMode === 'tablet') {
      parts.push('is-accordion');
      if (openFlag) parts.push('is-open');
    }
    if (state.viewportMode === 'phone' && state.mobileTab !== phoneTab) {
      parts.push('is-hidden');
    }
    return parts.join(' ');
  }

  function stageClass(stageName) {
    var stage = (stageName || '').toLowerCase();
    if (stage.indexOf('closed won') !== -1) return 'stage-badge stage-won';
    if (stage.indexOf('closed') !== -1) return 'stage-badge stage-lost';
    return 'stage-badge';
  }

  function interactionMeta(opp) {
    var days = opp && opp.lastInteractionDaysAgo;
    var cls = 'meta-chip';
    var label = 'No interaction data';
    if (days !== null && days !== undefined) {
      if (days >= 14) cls = 'meta-chip meta-hot';
      else if (days >= 7) cls = 'meta-chip meta-warm';
      else cls = 'meta-chip meta-cool';
      if (days === 0) label = 'Last interaction today';
      else if (days === 1) label = '1 day since last interaction';
      else label = days + ' days since last interaction';
    }
    return { cls: cls, label: label };
  }

  function createdDaysAgoLabel(opp) {
    var days = opp && opp.createdDaysAgo;
    if (days === null || days === undefined) return '—';
    if (days === 0) return 'today';
    if (days === 1) return '1 day ago';
    return days + ' days ago';
  }

  function activityCountLabel(opp) {
    var count = opp && opp.activityCount;
    if (count === null || count === undefined) return '—';
    if (count === 1) return '1 done';
    return count + ' done';
  }

  function renderShortcuts() {
    return TAKEN_ACTION_SHORTCUTS.map(function (row) {
      var cls = isShortcutActive(row.code) ? 'shortcut-chip is-selected' : 'shortcut-chip';
      return (
        '<button type="button" class="' + cls + '" data-code="' + esc(row.code) + '" title="' + esc(row.desc) + '">' +
          ms(row.icon) +
          '<span class="chip-code">' + esc(row.code) + '</span>' +
        '</button>'
      );
    }).join('');
  }

  function renderManageChips() {
    return MANAGE_ACTIONS.map(function (action) {
      return (
        '<button type="button" class="manage-chip" data-id="' + esc(action.id) + '" title="' + esc(action.label) + '">' +
          ms(action.icon) +
          '<span class="manage-label">' + esc(action.label) + '</span>' +
        '</button>'
      );
    }).join('');
  }

  function renderQuickLinkButtons(links) {
    return (links || []).map(function (link) {
      return (
        '<button type="button" class="icon-only-btn" title="' + esc(link.title) + '" data-url="' + esc(link.url) + '" data-link-type="' + esc(link.type) + '">' +
          '<img src="' + esc(link.icon) + '" alt="' + esc(link.title) + '" class="action-icon" />' +
        '</button>'
      );
    }).join('');
  }

  function renderModals() {
    var html = '';
    if (state.actionModalOpen) {
      var title = state.pendingWhatsAppUrl
        ? 'WhatsApp message'
        : ((TAKEN_ACTION_SHORTCUTS.filter(function (r) { return r.code === state.pendingActionCode; })[0] || {}).desc || 'Action details');
      var confirmLabel = state.pendingWhatsAppUrl ? 'Send & log' : 'Set action';
      html +=
        '<section class="action-modal-backdrop" data-modal="action" role="dialog" aria-modal="true">' +
          '<div class="action-modal" data-stop="1">' +
            '<h3 class="action-modal-title">' + esc(title) + '</h3>' +
            '<p class="action-modal-code">' + esc(state.pendingActionCode) + ':</p>' +
            '<label class="field-label" for="sonic-action-text">Description</label>' +
            '<textarea id="sonic-action-text" class="sonic-input" rows="4" placeholder="Enter details for this action…">' + esc(state.actionModalText) + '</textarea>' +
            '<div class="action-modal-buttons">' +
              '<button type="button" class="modal-cancel" data-action="action-cancel">Cancel</button>' +
              '<button type="button" class="modal-confirm" data-action="action-confirm">' + esc(confirmLabel) + '</button>' +
            '</div>' +
          '</div>' +
        '</section>';
    }
    if (state.manageModalOpen) {
      var manageRow = MANAGE_ACTIONS.filter(function (a) { return a.id === state.manageActionId; })[0];
      var manageTitle = manageRow ? manageRow.label : 'Manage';
      var isSearch = state.manageActionId === 'setAe' || state.manageActionId === 'changeOwner';
      var isField = state.manageActionId === 'setEmail' || state.manageActionId === 'setMobile' || state.manageActionId === 'setLinkedIn';
      var fieldLabel = 'Value';
      if (state.manageActionId === 'setEmail') fieldLabel = 'Primary contact email';
      if (state.manageActionId === 'setMobile') fieldLabel = 'Primary contact mobile';
      if (state.manageActionId === 'setLinkedIn') fieldLabel = 'Primary contact LinkedIn URL';
      html +=
        '<section class="action-modal-backdrop" data-modal="manage" role="dialog" aria-modal="true">' +
          '<div class="action-modal" data-stop="1">' +
            '<h3 class="action-modal-title">' + esc(manageTitle) + '</h3>' +
            (state.manageError ? '<div class="save-error">' + esc(state.manageError) + '</div>' : '') +
            (isSearch
              ? '<label class="field-label" for="sonic-manage-search">Search</label>' +
                '<input id="sonic-manage-search" class="sonic-input" type="search" value="' + esc(state.manageSearch) + '" />' +
                '<div class="action-modal-buttons">' +
                  '<button type="button" class="modal-cancel" data-action="manage-cancel">Cancel</button>' +
                  '<button type="button" class="modal-confirm" data-action="manage-search"' + (state.manageBusy ? ' disabled' : '') + '>Search</button>' +
                '</div>' +
                '<ul class="manage-results">' +
                  state.manageSearchResults.map(function (row) {
                    return '<li><button type="button" class="manage-result-btn" data-id="' + esc(row.id) + '">' + esc(row.name) + '</button></li>';
                  }).join('') +
                '</ul>'
              : '') +
            (isField
              ? '<label class="field-label" for="sonic-manage-field">' + esc(fieldLabel) + '</label>' +
                '<input id="sonic-manage-field" class="sonic-input" type="text" value="' + esc(state.manageFieldValue) + '" />' +
                '<div class="action-modal-buttons">' +
                  '<button type="button" class="modal-cancel" data-action="manage-cancel">Cancel</button>' +
                  '<button type="button" class="modal-confirm" data-action="manage-save"' + (state.manageBusy ? ' disabled' : '') + '>Save</button>' +
                '</div>'
              : '') +
          '</div>' +
        '</section>';
    }
    if (state.emailDraftOpen) {
      html +=
        '<section class="action-modal-backdrop" data-modal="email" role="dialog" aria-modal="true">' +
          '<div class="action-modal action-modal-wide" data-stop="1">' +
            '<h3 class="action-modal-title">Encouragement email</h3>' +
            (state.emailDraftError ? '<div class="save-error">' + esc(state.emailDraftError) + '</div>' : '') +
            (state.emailDraftBusy
              ? '<div class="panel-loading"><span class="sonic-spinner"></span></div>'
              : '<label class="field-label" for="sonic-email-subject">Subject</label>' +
                '<input id="sonic-email-subject" class="sonic-input" type="text" value="' + esc(state.emailDraftSubject) + '" />' +
                '<label class="field-label" for="sonic-email-body">Body</label>' +
                '<textarea id="sonic-email-body" class="sonic-input" rows="8">' + esc(state.emailDraftBody) + '</textarea>') +
            '<div class="action-modal-buttons">' +
              '<button type="button" class="modal-cancel" data-action="email-cancel">Cancel</button>' +
              '<button type="button" class="modal-confirm" data-action="email-send"' + (state.emailDraftBusy ? ' disabled' : '') + '>Send &amp; log</button>' +
            '</div>' +
          '</div>' +
        '</section>';
    }
    return html;
  }

  function renderCard(opp) {
    var isPhone = state.viewportMode === 'phone';
    var isTablet = state.viewportMode === 'tablet';
    var isDesktop = state.viewportMode === 'desktop';
    var meta = interactionMeta(opp);
    var person = activeContactPerson();
    var contactLinks = contactQuickLinks();
    var aeLinks = aeQuickLinks();
    var primaryContactRow = buildPersonRow(person);
    var primaryAeRow = buildPersonRow(opp.primaryAe);
    var hasContact = !!contactHtmlFixed() || !!primaryContactRow;
    var hasAe = !!aeHtmlFixed() || !!primaryAeRow;
    var showPeople = hasContact || hasAe;
    var contactName = (person && (person.name || person.firstName)) || (primaryContactRow && primaryContactRow.name) || '';
    var aeName = (primaryAeRow && primaryAeRow.name) || (opp.primaryAe && opp.primaryAe.firstName) || '';
    var needsApollo = !!(person && person.recordId && person.recordId === state.opportunityPrimaryContactId && !person.mobilePhone);
    var showSetPrimary = !!(state.selectedContactId && state.selectedContactId !== state.opportunityPrimaryContactId);
    var summaryHtml = opp.summaryInfo || '';
    var dirty = isDirty();

    var tabsHtml = '';
    if (isPhone) {
      var tabs = [
        { id: 'overview', label: 'Opp', icon: 'description' },
        { id: 'people', label: 'People', icon: 'group' },
        { id: 'update', label: 'Update', icon: 'edit' }
      ];
      tabsHtml =
        '<div class="mobile-tab-bar" role="tablist" aria-label="Card sections">' +
        tabs.map(function (tab) {
          var active = state.mobileTab === tab.id;
          return (
            '<button type="button" role="tab" class="mobile-tab' + (active ? ' is-active' : '') + '" data-tab="' + tab.id + '" aria-selected="' + active + '">' +
              ms(tab.icon) +
              '<span class="tab-label">' + tab.label + '</span>' +
              (tab.id === 'update' && dirty ? '<span class="dirty-dot" aria-label="Unsaved changes"></span>' : '') +
            '</button>'
          );
        }).join('') +
        '</div>';
    }

    var contextBody =
      (summaryHtml
        ? '<div class="rich-block summary-block' + (state.summaryExpanded ? ' is-expanded' : '') + '">' +
            '<div class="summary-header">' +
              '<p class="field-label">What they\'re talking about</p>' +
              (!state.summaryExpanded
                ? '<button type="button" class="text-button compact" data-action="toggle-summary">Show full summary</button>'
                : '') +
            '</div>' +
            '<div class="summary-content">' + summaryHtml + '</div>' +
            (state.summaryExpanded
              ? '<button type="button" class="text-button compact" data-action="toggle-summary">Show less</button>'
              : '') +
          '</div>'
        : '') +
      '<div class="meta-grid">' +
        '<div class="meta-item meta-highlight"><span class="meta-key">Next action</span><span class="meta-value">' + esc(formatRelativeActionDate(opp.nextActionDate)) + '</span></div>' +
        '<div class="meta-item meta-highlight"><span class="meta-key">Current next step</span><span class="meta-value">' + escPlain(opp.nextStep || '—') + '</span></div>' +
      '</div>';

    var contactPicker = '';
    if (state.contactRoleOptions && state.contactRoleOptions.length) {
      contactPicker =
        '<div class="primary-contact-picker"><div class="contact-picker-row">' +
          '<select class="sonic-input sonic-select" data-action="contact-select"' + (state.contactRoleBusy ? ' disabled' : '') + '>' +
            state.contactRoleOptions.map(function (opt) {
              return '<option value="' + esc(opt.value) + '"' + (opt.value === state.selectedContactId ? ' selected' : '') + '>' + esc(opt.label) + '</option>';
            }).join('') +
          '</select>' +
          (showSetPrimary
            ? '<button type="button" class="set-primary-btn" title="Set as opportunity primary contact" data-action="set-primary"' + (state.contactRoleBusy ? ' disabled' : '') + '>' + ms('check_circle') + '</button>'
            : '') +
        '</div></div>';
    } else if (contactName) {
      contactPicker =
        '<button class="person-name compact" type="button" data-person-id="' + esc(primaryContactRow && primaryContactRow.recordId) + '">' + esc(contactName) + '</button>';
    }

    var peopleBody = showPeople
      ? '<div class="people-grid ' + (hasContact && hasAe ? 'two-cols' : 'one-col') + '">' +
          (hasContact
            ? '<div class="people-cell people-cell-contact">' +
                '<p class="cell-label">Main contact</p>' +
                contactPicker +
                (contactLinks.length
                  ? '<div class="icon-row">' + renderQuickLinkButtons(contactLinks) + '</div>'
                  : '') +
                (needsApollo
                  ? '<button type="button" class="apollo-mobile-btn" data-action="apollo"' + (state.apolloBusy ? ' disabled' : '') + '>' +
                      (state.apolloBusy ? 'Requesting…' : 'Get mobile (Apollo)') +
                    '</button>'
                  : '') +
                (state.apolloMessage ? '<p class="apollo-message">' + esc(state.apolloMessage) + '</p>' : '') +
              '</div>'
            : '') +
          (hasAe
            ? '<div class="people-cell people-cell-ae">' +
                '<p class="cell-label">Account executive</p>' +
                (aeName
                  ? '<button class="person-name compact" type="button" data-person-id="' + esc(primaryAeRow && primaryAeRow.recordId) + '">' + esc(aeName) + '</button>'
                  : '') +
                (aeLinks.length ? '<div class="icon-row">' + renderQuickLinkButtons(aeLinks) + '</div>' : '') +
              '</div>'
            : '') +
        '</div>' +
        '<div class="opp-stats-row" aria-label="Opportunity summary">' +
          '<div class="opp-stat-chip"><span class="opp-stat-label">Created</span><span class="opp-stat-value">' + esc(createdDaysAgoLabel(opp)) + '</span></div>' +
          '<div class="opp-stat-chip"><span class="opp-stat-label">Activity</span><span class="opp-stat-value">' + esc(activityCountLabel(opp)) + '</span></div>' +
        '</div>'
      : '<p class="empty-panel-copy">No contact or AE linked to this opportunity.</p>' +
        '<div class="opp-stats-row" aria-label="Opportunity summary">' +
          '<div class="opp-stat-chip"><span class="opp-stat-label">Created</span><span class="opp-stat-value">' + esc(createdDaysAgoLabel(opp)) + '</span></div>' +
          '<div class="opp-stat-chip"><span class="opp-stat-label">Activity</span><span class="opp-stat-value">' + esc(activityCountLabel(opp)) + '</span></div>' +
        '</div>';

    var stageOptionsHtml = state.stageOptions
      .map(function (opt) {
        var selected = (opt.value || '') === (state.selectedStage || '') ? ' selected' : '';
        return '<option value="' + esc(opt.value) + '"' + selected + '>' + esc(opt.label) + '</option>';
      })
      .join('');
    var updateBody =
      '<p class="actions-title">Quick update</p>' +
      '<label class="field-label" for="sonic-stage">Stage</label>' +
      '<select id="sonic-stage" class="sonic-select stage-picker" data-action="stage">' +
        '<option value="">Select stage</option>' +
        stageOptionsHtml +
      '</select>' +
      '<div class="shortcut-bar" role="toolbar" aria-label="Taken action shortcuts">' + renderShortcuts() + '</div>' +
      '<div class="manage-bar" role="toolbar" aria-label="Opportunity manage actions">' + renderManageChips() + '</div>' +
      '<label class="field-label" for="sonic-taken-action">Action log</label>' +
      '<textarea id="sonic-taken-action" class="sonic-input" rows="2" readonly>' + esc(state.takenAction) + '</textarea>' +
      '<div class="days-stepper">' +
        '<span class="stepper-label">Days to push</span>' +
        '<div class="stepper-controls">' +
          '<button type="button" class="stepper-btn" data-action="days-dec" aria-label="Decrease days">−</button>' +
          '<input class="sonic-input stepper-input" type="number" data-action="days-input" value="' + esc(state.daysToPush) + '" step="1" />' +
          '<button type="button" class="stepper-btn" data-action="days-inc" aria-label="Increase days">+</button>' +
        '</div>' +
      '</div>' +
      '<label class="field-label" for="sonic-next-step">Next step</label>' +
      '<textarea id="sonic-next-step" class="sonic-input" rows="3" data-action="next-step">' + esc(state.nextStep) + '</textarea>' +
      '<div class="encouragement-block">' +
        '<label class="field-label" for="sonic-encourage">Encouragement Email Main Idea</label>' +
        '<textarea id="sonic-encourage" class="sonic-input" rows="3" data-action="encourage" placeholder="Rough note — Sonic will turn this into a full email to the main contact">' + esc(state.encouragementIdea) + '</textarea>' +
        '<button type="button" class="primary-button encouragement-btn" data-action="draft-email">Draft &amp; preview email</button>' +
      '</div>';

    return (
      '<div class="sonic-deck mode-' + state.viewportMode + '">' +
        (isPhone
          ? (state.opportunities[state.currentIndex + 2]
              ? '<div class="deck-peek peek-2" aria-hidden="true"></div>'
              : '') +
            (state.opportunities[state.currentIndex + 1]
              ? '<div class="deck-peek peek-1" aria-hidden="true"></div>'
              : '')
          : '') +
        '<section class="sonic-card is-top mode-' + state.viewportMode + '" data-card="1">' +
          '<div class="swipe-stamp stamp-next" aria-hidden="true">NEXT</div>' +
          '<div class="swipe-stamp stamp-back" aria-hidden="true">BACK</div>' +
          '<div class="card-hero">' +
            '<div class="hero-top">' +
              '<button class="opp-name" type="button" data-action="open-opp">' + esc(opp.name) + '</button>' +
              '<span class="' + stageClass(opp.stageName) + '">' + esc(opp.stageName) + '</span>' +
            '</div>' +
            (opp.accountName ? '<p class="account-line">' + esc(opp.accountName) + '</p>' : '') +
            '<div class="hero-meta">' +
              '<div class="' + meta.cls + '">' + esc(meta.label) + '</div>' +
              '<span class="hero-progress">' + esc(progressLabel()) + '</span>' +
            '</div>' +
            '<div class="progress-track" role="progressbar" aria-valuenow="' + progressPercent() + '" aria-valuemin="0" aria-valuemax="100">' +
              '<div class="progress-fill" style="width:' + progressPercent() + '%"></div>' +
            '</div>' +
          '</div>' +
          tabsHtml +
          '<div class="card-body ' + (isDesktop ? 'is-split' : 'is-stacked') + '">' +
            '<div class="' + sectionClass('section-context', state.sectionContextOpen, 'overview') + '">' +
              (isTablet
                ? '<button type="button" class="accordion-trigger" data-action="toggle-context"><span class="accordion-title">Opportunity context</span>' + ms('expand_more') + '</button>'
                : '') +
              '<div class="section-body sonic-context">' + contextBody + '</div>' +
            '</div>' +
            '<div class="' + sectionClass('section-people', state.sectionPeopleOpen, 'people') + '">' +
              (isTablet
                ? '<button type="button" class="accordion-trigger" data-action="toggle-people"><span class="accordion-title">People</span>' + ms('expand_more') + '</button>'
                : '') +
              '<div class="section-body">' + peopleBody + '</div>' +
            '</div>' +
            '<div class="' + sectionClass('section-update sonic-actions', state.sectionUpdateOpen, 'update') + '">' +
              (isTablet
                ? '<button type="button" class="accordion-trigger" data-action="toggle-update"><span class="accordion-title">Quick update</span>' + ms('expand_more') + '</button>'
                : '') +
              '<div class="section-body">' + updateBody + '</div>' +
            '</div>' +
          '</div>' +
          (isPhone
            ? '<footer class="card-footer tinder-footer is-sticky">' +
                '<button class="tinder-btn tinder-back" type="button" data-action="prev"' + (state.currentIndex <= 0 ? ' disabled' : '') + ' aria-label="Previous opportunity">' +
                  ms('undo') +
                '</button>' +
                '<div class="tinder-hint">' +
                  '<p class="swipe-hint">Swipe or tap Next</p>' +
                  (dirty ? '<span class="dirty-pill">Unsaved — advances save</span>' : '') +
                '</div>' +
                '<button class="tinder-btn tinder-next" type="button" data-action="next" aria-label="' + (dirty ? 'Save and next' : 'Next opportunity') + '">' +
                  (dirty ? '<span class="dirty-indicator" aria-hidden="true"></span>' : '') +
                  ms('arrow_forward') +
                '</button>' +
              '</footer>'
            : '<footer class="card-footer' + (!isDesktop ? ' is-sticky' : '') + '">' +
                '<button class="prev-button" type="button" data-action="prev"' + (state.currentIndex <= 0 ? ' disabled' : '') + ' aria-label="Previous opportunity">' +
                  ms('chevron_left') + ' Prev' +
                '</button>' +
                '<p class="swipe-hint">Swipe or use buttons to move through the queue</p>' +
                '<button class="next-button" type="button" data-action="next">' +
                  (dirty ? '<span class="dirty-indicator" aria-hidden="true"></span>' : '') +
                  (dirty ? 'Save &amp; next' : 'Next') + ' ' + ms('chevron_right') +
                '</button>' +
              '</footer>') +
          renderModals() +
        '</section>' +
      '</div>'
    );
  }

  function render() {
    var el = root();
    if (!el) return;
    var showCollapsed = !!state.selectedListViewId && !state.pickerExpanded;
    var showPicker = state.pickerExpanded || !state.selectedListViewId;
    var opp = currentOpportunity();
    var showCard = !!state.selectedListViewId && !state.isLoadingQueue && !!opp;
    var showDone = !!state.selectedListViewId && !state.isLoadingQueue && state.opportunities.length > 0 && state.currentIndex >= state.opportunities.length;
    var showEmpty = !!state.selectedListViewId && !state.isLoadingQueue && state.opportunities.length === 0 && !state.loadError;
    var views = filteredListViews();

    var html =
      '<div class="sonic-shell mode-' + state.viewportMode + '">' +
        '<header class="sonic-header">' +
          '<div class="sonic-brand">' +
            ms('bolt') +
            '<span class="sonic-title">Sonic</span>' +
          '</div>' +
          (showCollapsed
            ? '<button class="collapsed-bar" type="button" data-action="toggle-picker" title="' + esc(state.selectedListViewLabel) + '">' +
                '<span class="collapsed-label">' + esc(state.selectedListViewLabel) + '</span>' +
                ms('expand_more') +
              '</button>'
            : '') +
          (state.saveStatus ? '<span class="save-pill">' + esc(state.saveStatus) + '</span>' : '') +
        '</header>' +
        (state.failedSaveMessage ? '<div class="save-error">' + esc(state.failedSaveMessage) + '</div>' : '') +
        (showPicker
          ? '<section class="picker-panel">' +
              (state.isLoadingListViews
                ? '<div class="panel-loading"><span class="sonic-spinner"></span></div>'
                : '<p class="picker-prompt">Pick a list view to start swiping opportunities.</p>' +
                  '<label class="field-label" for="sonic-lv-search">Opportunity list view</label>' +
                  '<input id="sonic-lv-search" class="sonic-input" type="search" placeholder="Search list views…" value="' + esc(state.listViewSearch) + '" data-action="lv-search" />' +
                  '<div class="list-view-scroll">' +
                    (views.length
                      ? '<ul class="list-view-list">' +
                          views.map(function (view) {
                            return (
                              '<li><button class="list-view-item" type="button" data-id="' + esc(view.id) + '" data-label="' + esc(view.label) + '">' +
                                esc(view.label) +
                              '</button></li>'
                            );
                          }).join('') +
                        '</ul>'
                      : '<p class="empty-copy">No list views match your search.</p>') +
                  '</div>') +
            '</section>'
          : '') +
        (state.loadError ? '<div class="panel-error">' + esc(state.loadError) + '</div>' : '') +
        (state.isLoadingQueue
          ? '<div class="queue-loading"><span class="sonic-spinner"></span><p>Loading queue…</p></div>'
          : '') +
        (showEmpty
          ? '<div class="empty-queue"><p>This list view has no opportunities.</p>' +
              '<button class="text-button" type="button" data-action="toggle-picker">Choose another list view</button></div>'
          : '') +
        (showDone
          ? '<section class="done-screen">' +
              '<div class="celebration">' + ms('celebration') + '</div>' +
              '<h2 class="done-title">Thanks — queue cleared!</h2>' +
              '<p class="done-copy">You processed every opportunity in ' + esc(state.selectedListViewLabel) + '.</p>' +
              '<button class="primary-button" type="button" data-action="toggle-picker">Pick another list view</button>' +
            '</section>'
          : '') +
        (showCard ? renderCard(opp) : '') +
      '</div>';

    el.innerHTML = html;
    bindEvents(el);
  }

  function onRootClick(evt) {
    var el = root();
    if (!el) return;
    var t = evt.target;
    var btn = t.closest
      ? t.closest(
          'button, [data-action], .list-view-item, .manage-result-btn, .icon-only-btn, .shortcut-chip, .manage-chip, .person-name'
        )
      : null;
    if (!btn) {
      if (t.classList && t.classList.contains('action-modal-backdrop')) {
        if (t.getAttribute('data-modal') === 'action') closeActionModal();
      }
      return;
    }

    var action = btn.getAttribute('data-action');
    var code = btn.getAttribute('data-code');

    if (btn.classList.contains('list-view-item')) {
      haptic('tap');
      state.selectedListViewId = btn.getAttribute('data-id');
      state.selectedListViewLabel = btn.getAttribute('data-label');
      storeListViewId(state.selectedListViewId);
      state.pickerExpanded = false;
      loadQueue(state.selectedListViewId);
      return;
    }

    if (btn.classList.contains('shortcut-chip') && code) {
      haptic('tap');
      handleShortcut(code);
      return;
    }

    if (btn.classList.contains('manage-chip')) {
      haptic('tap');
      handleManageOpen(btn.getAttribute('data-id'));
      return;
    }

    if (btn.classList.contains('icon-only-btn')) {
      evt.preventDefault();
      haptic('tap');
      var url = btn.getAttribute('data-url');
      var linkType = btn.getAttribute('data-link-type');
      if (linkType === 'whatsapp') {
        state.pendingWhatsAppUrl = url;
        state.pendingWhatsAppPrefix = getWhatsAppPrefix(url);
        state.pendingActionCode = 'W';
        state.actionModalText = extractActionBody('W');
        state.actionModalOpen = true;
        render();
        return;
      }
      openQuickLink(url, linkType);
      return;
    }

    if (btn.classList.contains('manage-result-btn')) {
      handleManagePick(btn.getAttribute('data-id'));
      return;
    }

    if (btn.classList.contains('person-name') || btn.getAttribute('data-person-id')) {
      openRecord(btn.getAttribute('data-person-id') || btn.getAttribute('data-id'));
      return;
    }

    if (btn.classList.contains('opp-name') || action === 'open-opp') {
      var opp = currentOpportunity();
      if (opp) openRecord(opp.id);
      return;
    }

    switch (action) {
      case 'toggle-picker':
        state.pickerExpanded = !state.pickerExpanded;
        haptic('tap');
        render();
        break;
      case 'toggle-summary':
        state.summaryExpanded = !state.summaryExpanded;
        render();
        break;
      case 'toggle-context':
        if (state.viewportMode === 'tablet') {
          state.sectionContextOpen = !state.sectionContextOpen;
          render();
        }
        break;
      case 'toggle-people':
        if (state.viewportMode === 'tablet') {
          state.sectionPeopleOpen = !state.sectionPeopleOpen;
          render();
        }
        break;
      case 'toggle-update':
        if (state.viewportMode === 'tablet') {
          state.sectionUpdateOpen = !state.sectionUpdateOpen;
          render();
        }
        break;
      case 'prev':
        if (!state.cardAnimating && state.currentIndex > 0) {
          animateRetreat(el.querySelector('.sonic-card.is-top'));
        }
        break;
      case 'next':
        if (!state.cardAnimating && showCardSafe()) {
          animateAdvance(el.querySelector('.sonic-card.is-top'));
        }
        break;
      case 'days-dec':
        decrementDays();
        break;
      case 'days-inc':
        incrementDays();
        break;
      case 'draft-email':
        draftEncouragement();
        break;
      case 'apollo':
        requestApollo();
        break;
      case 'set-primary':
        setPrimaryContact();
        break;
      case 'action-cancel':
        closeActionModal();
        break;
      case 'action-confirm':
        confirmActionModal();
        break;
      case 'manage-cancel':
        closeManageModal();
        break;
      case 'manage-search':
        runManageSearch();
        break;
      case 'manage-save':
        saveManageField();
        break;
      case 'email-cancel':
        closeEmailDraft();
        break;
      case 'email-send':
        sendEncouragement();
        break;
      default:
        if (btn.getAttribute('data-tab')) {
          state.mobileTab = btn.getAttribute('data-tab');
          haptic('tap');
          render();
        }
        break;
    }
  }

  function onRootInput(evt) {
    var t = evt.target;
    var action = t.getAttribute('data-action');
    if (action === 'lv-search' || t.id === 'sonic-lv-search') {
      state.listViewSearch = t.value || '';
      render();
      var input = root() && root().querySelector('#sonic-lv-search');
      if (input) {
        input.focus();
        var len = input.value.length;
        input.setSelectionRange(len, len);
      }
      return;
    }
    if (action === 'days-input') {
      state.daysToPush = t.value;
      return;
    }
    if (action === 'stage' || t.id === 'sonic-stage') {
      state.selectedStage = t.value || '';
      return;
    }
    if (action === 'next-step' || t.id === 'sonic-next-step') {
      state.nextStep = t.value || '';
      return;
    }
    if (action === 'encourage' || t.id === 'sonic-encourage') {
      state.encouragementIdea = t.value || '';
      return;
    }
    if (t.id === 'sonic-action-text') {
      state.actionModalText = t.value || '';
      return;
    }
    if (t.id === 'sonic-manage-search') {
      state.manageSearch = t.value || '';
      return;
    }
    if (t.id === 'sonic-manage-field') {
      state.manageFieldValue = t.value || '';
      return;
    }
    if (t.id === 'sonic-email-subject') {
      state.emailDraftSubject = t.value || '';
      return;
    }
    if (t.id === 'sonic-email-body') {
      state.emailDraftBody = t.value || '';
    }
  }

  function onRootChange(evt) {
    var t = evt.target;
    if (t.getAttribute('data-action') === 'contact-select') {
      var contactId = t.value;
      if (!contactId || contactId === state.selectedContactId) return;
      state.selectedContactId = contactId;
      state.apolloMessage = '';
      state.contactRoleBusy = true;
      render();
      loadActiveContact(contactId).then(function () {
        state.contactRoleBusy = false;
        render();
      });
    }
  }

  function bindEvents(el) {
    var card = el.querySelector('[data-card="1"]');
    if (card) {
      card.addEventListener('touchstart', onTouchStart, { passive: true });
      card.addEventListener('touchmove', onTouchMove, { passive: false });
      card.addEventListener('touchend', onTouchEnd);
    }

    // Root listeners must bind once — re-binding on every render stacked handlers
    // and made toggle-picker (and other clicks) cancel themselves out.
    if (!state.eventsBound) {
      state.eventsBound = true;
      el.addEventListener('click', onRootClick);
      el.addEventListener('input', onRootInput);
      el.addEventListener('change', onRootChange);
    }
  }

  function showCardSafe() {
    return !!state.selectedListViewId && !state.isLoadingQueue && !!currentOpportunity();
  }

  function handleShortcut(code) {
    var row = null;
    for (var i = 0; i < TAKEN_ACTION_SHORTCUTS.length; i++) {
      if (TAKEN_ACTION_SHORTCUTS[i].code === code) { row = TAKEN_ACTION_SHORTCUTS[i]; break; }
    }
    if (row && row.confirm) {
      if (!window.confirm('Confirm: ' + row.desc + '?')) return;
      if (code === 'DEL' || code === 'CLS') {
        state.takenAction = code;
        closeActionModal();
        return;
      }
    }
    state.pendingActionCode = code;
    state.pendingWhatsAppUrl = '';
    state.pendingWhatsAppPrefix = '';
    state.actionModalText = extractActionBody(code);
    state.actionModalOpen = true;
    render();
  }

  function confirmActionModal() {
    var code = state.pendingActionCode;
    if (!code) {
      closeActionModal();
      return;
    }
    var body = (state.actionModalText || '').trim();
    state.takenAction = body ? code + ':' + body : code + ':';
    if (state.pendingWhatsAppUrl) {
      openWhatsAppWithUserMessage(state.pendingWhatsAppUrl, body);
    }
    haptic('success');
    closeActionModal();
  }

  function handleManageOpen(actionId) {
    if (!actionId) return;
    if (actionId === 'teamMember') {
      var opp = currentOpportunity();
      if (opp && opp.id) {
        openWebPage('/lightning/r/Opportunity/' + opp.id + '/related/OpportunityTeamMembers/view');
      }
      return;
    }
    state.manageActionId = actionId;
    state.manageSearch = '';
    state.manageSearchResults = [];
    state.manageFieldValue = '';
    state.manageError = '';
    state.manageModalOpen = true;
    var cur = currentOpportunity();
    if (actionId === 'setEmail') {
      state.manageFieldValue = (cur && cur.primaryContact && cur.primaryContact.email) || '';
    } else if (actionId === 'setMobile') {
      state.manageFieldValue = (cur && cur.primaryContact && cur.primaryContact.mobilePhone) || '';
    } else if (actionId === 'setLinkedIn') {
      state.manageFieldValue = (cur && cur.primaryContact && cur.primaryContact.linkedInUrl) || '';
    }
    render();
  }

  function runManageSearch() {
    state.manageBusy = true;
    state.manageError = '';
    render();
    var p;
    if (state.manageActionId === 'changeOwner') {
      p = remoting('sonicSearchUsers', state.manageSearch);
    } else if (state.manageActionId === 'setAe') {
      p = remoting('sonicSearchContacts', state.manageSearch);
    } else {
      state.manageBusy = false;
      render();
      return;
    }
    p.then(function (rows) {
      state.manageSearchResults = rows || [];
    }).catch(function (error) {
      state.manageError = reduceError(error);
    }).then(function () {
      state.manageBusy = false;
      render();
    });
  }

  function handleManagePick(recordId) {
    var opp = currentOpportunity();
    if (!recordId || !opp || !opp.id) return;
    state.manageBusy = true;
    state.manageError = '';
    render();
    var p;
    if (state.manageActionId === 'setAe') {
      p = remoting('sonicSetPrimaryAe', opp.id, recordId);
    } else if (state.manageActionId === 'changeOwner') {
      p = remoting('sonicChangeOpportunityOwner', opp.id, recordId);
    } else {
      state.manageBusy = false;
      render();
      return;
    }
    p.then(function () {
      state.manageModalOpen = false;
      state.saveStatus = 'Updated';
      haptic('success');
      return reloadCurrentCardQuietly();
    }).catch(function (error) {
      state.manageError = reduceError(error);
    }).then(function () {
      state.manageBusy = false;
      render();
    });
  }

  function saveManageField() {
    var opp = currentOpportunity();
    if (!opp || !opp.id) return;
    var fieldName = '';
    if (state.manageActionId === 'setEmail') fieldName = 'Email';
    else if (state.manageActionId === 'setMobile') fieldName = 'MobilePhone';
    else if (state.manageActionId === 'setLinkedIn') fieldName = 'LinkedInURL__c';
    else return;
    state.manageBusy = true;
    state.manageError = '';
    render();
    remoting('sonicUpdatePrimaryContactField', opp.id, fieldName, state.manageFieldValue)
      .then(function () {
        state.manageModalOpen = false;
        state.saveStatus = 'Updated';
        haptic('success');
        return reloadCurrentCardQuietly();
      })
      .catch(function (error) {
        state.manageError = reduceError(error);
      })
      .then(function () {
        state.manageBusy = false;
        render();
      });
  }

  function incrementDays() {
    var current = parseInt(state.daysToPush, 10);
    state.daysToPush = String(isNaN(current) ? 1 : current + 1);
    haptic('tap');
    render();
  }

  function decrementDays() {
    var current = parseInt(state.daysToPush, 10);
    state.daysToPush = String(isNaN(current) ? -1 : current - 1);
    haptic('tap');
    render();
  }

  function draftEncouragement() {
    var opp = currentOpportunity();
    if (!opp || !opp.id) return;
    if (!(state.encouragementIdea || '').trim()) {
      state.emailDraftError = 'Add a main idea first.';
      state.emailDraftOpen = true;
      render();
      return;
    }
    state.emailDraftBusy = true;
    state.emailDraftError = '';
    state.emailDraftOpen = true;
    render();
    remoting('sonicDraftEncouragementEmail', opp.id, state.encouragementIdea)
      .then(function (draft) {
        state.emailDraftSubject = (draft && draft.subject) || '';
        state.emailDraftBody = (draft && draft.body) || '';
      })
      .catch(function (error) {
        state.emailDraftError = reduceError(error);
      })
      .then(function () {
        state.emailDraftBusy = false;
        render();
      });
  }

  function sendEncouragement() {
    var opp = currentOpportunity();
    if (!opp || !opp.id) return;
    state.emailDraftBusy = true;
    state.emailDraftError = '';
    render();
    remoting('sonicSendEncouragementEmail', opp.id, state.emailDraftSubject, state.emailDraftBody)
      .then(function () {
        state.takenAction = 'E:' + (state.emailDraftSubject || '').trim();
        state.encouragementIdea = '';
        state.emailDraftOpen = false;
        state.saveStatus = 'Email sent';
        playSaveSound();
        haptic('success');
        window.setTimeout(function () {
          if (state.saveStatus === 'Email sent') {
            state.saveStatus = '';
            render();
          }
        }, 1800);
      })
      .catch(function (error) {
        state.emailDraftError = reduceError(error);
      })
      .then(function () {
        state.emailDraftBusy = false;
        render();
      });
  }

  function requestApollo() {
    var opp = currentOpportunity();
    if (!opp || !opp.id || state.apolloBusy) return;
    state.apolloBusy = true;
    state.apolloMessage = '';
    render();
    remoting('sonicRequestApolloMobile', opp.id)
      .then(function (result) {
        state.apolloMessage = (result && result.message) || 'Apollo request sent.';
        if (result && result.success) {
          state.saveStatus = 'Apollo…';
          haptic('success');
          window.setTimeout(function () {
            if (state.saveStatus === 'Apollo…') {
              state.saveStatus = '';
              render();
            }
          }, 2500);
        }
      })
      .catch(function (error) {
        state.apolloMessage = reduceError(error);
      })
      .then(function () {
        state.apolloBusy = false;
        render();
      });
  }

  function setPrimaryContact() {
    var opp = currentOpportunity();
    var contactId = state.selectedContactId;
    if (!opp || !opp.id || !contactId || contactId === state.opportunityPrimaryContactId) return;
    state.contactRoleBusy = true;
    render();
    remoting('sonicSetOpportunityPrimaryContact', opp.id, contactId)
      .then(function () {
        state.saveStatus = 'Primary updated';
        haptic('success');
        return reloadCurrentCardQuietly();
      })
      .catch(function (error) {
        state.failedSaveMessage = reduceError(error);
      })
      .then(function () {
        state.contactRoleBusy = false;
        window.setTimeout(function () {
          if (state.saveStatus === 'Primary updated') {
            state.saveStatus = '';
            render();
          }
        }, 1800);
        render();
      });
  }

  function onTouchStart(event) {
    if (state.cardAnimating || !showCardSafe()) return;
    if (event.target && event.target.closest && event.target.closest('textarea, input, select, button, a')) {
      state.isSwiping = false;
      return;
    }
    var touch = event.changedTouches[0];
    state.swipeStartX = touch.clientX;
    state.swipeStartY = touch.clientY;
    state.swipeDeltaX = 0;
    state.isSwiping = true;
  }

  function onTouchMove(event) {
    if (!state.isSwiping) return;
    var touch = event.changedTouches[0];
    var deltaX = touch.clientX - state.swipeStartX;
    var deltaY = touch.clientY - state.swipeStartY;
    if (Math.abs(deltaY) > Math.abs(deltaX) && Math.abs(deltaY) > 12) {
      state.isSwiping = false;
      var cancelCard = root() && root().querySelector('.sonic-card.is-top');
      if (cancelCard) {
        cancelCard.style.transition = 'transform 180ms ease, opacity 180ms ease';
        resetCardMotion(cancelCard);
      }
      return;
    }
    if (Math.abs(deltaX) < 8) return;
    event.preventDefault();
    var visualDelta = deltaX;
    if (state.currentIndex <= 0 && visualDelta > 0) visualDelta = Math.min(visualDelta, 56);
    state.swipeDeltaX = deltaX;
    applySwipeTransform(root() && root().querySelector('.sonic-card.is-top'), visualDelta);
  }

  function onTouchEnd() {
    if (!state.isSwiping) return;
    state.isSwiping = false;
    var card = root() && root().querySelector('.sonic-card.is-top');
    if (state.swipeDeltaX < -96) {
      animateAdvance(card);
    } else if (state.swipeDeltaX > 96 && state.currentIndex > 0) {
      animateRetreat(card);
    } else if (card) {
      card.style.transition = 'transform 220ms cubic-bezier(.2,.8,.2,1), opacity 220ms ease';
      resetCardMotion(card);
    }
    state.swipeDeltaX = 0;
  }

    function activate() {
    if (!root()) return;
    if (!state.boundResize) {
      state.boundResize = function () { updateViewportMode(); };
      window.addEventListener('resize', state.boundResize);
      if (typeof ResizeObserver !== 'undefined') {
        state.resizeObserver = new ResizeObserver(function () { updateViewportMode(); });
        state.resizeObserver.observe(root());
      }
    }
    updateViewportMode();
    if (!state.activated) {
      state.activated = true;
      loadStageOptions();
      loadListViews();
      return;
    }
    // Retry if a prior load left us empty without an in-flight request.
    if (!state.listViews.length && !state.isLoadingListViews && !state.selectedListViewId) {
      loadListViews();
      return;
    }
    render();
  }

  function refresh() {
    if (!root()) return;
    if (state.selectedListViewId) {
      loadQueue(state.selectedListViewId);
    } else {
      loadListViews();
    }
  }

  global.CrmHubSonic = {
    activate: activate,
    refresh: refresh
  };
})(window);
