/* global Visualforce, CrmHubListEngine, CrmHubListController, crmHubOpenRecordModal */
(function (global) {
    'use strict';

    var CRM_HUB_SYNC = {
        lead: 'Lead',
        opp: 'Opportunity',
        acc: 'Account',
        con: 'Contact',
        jobapp: 'Job_Application__c',
        pos: 'Position__c',
        empcon: 'Employment_Contract__c'
    };

    var hubAllowedTabs = null;
    var hubAccessMode = 'Partial Hub Access';
    var hubElevenLabsConfigured = false;
    var hubSmartCreditsRemaining = 0;
    var hubSmartUsedToday = false;
    var cogLastSearchRes = null;
    var cogLastQuery = '';
    var cogVoiceFromMic = false;
    var cogPreferredVoice = null;
    var cogTtsAudio = null;
    var hubBrowserSpeakGen = 0;
    var hubBriefingSpeaking = false;
    var hubBriefingPreset = 'everything';
    var hubBriefingAudience = 'sales';
    var hubBriefingSelectedTabs = [];
    var hubHomeStatsCache = null;
    var hubHomeScope = 'me';
    var hubHomeLoading = false;

    var HUB_BRIEFING_TAB_META = [
        { id: 'leads', label: 'Leads' },
        { id: 'opps', label: 'Opportunities' },
        { id: 'accounts', label: 'Accounts' },
        { id: 'contacts', label: 'Contacts' },
        { id: 'jobapps', label: 'Job Applications' },
        { id: 'positions', label: 'Positions' },
        { id: 'contracts', label: 'Contracts' }
    ];

    function hubTabAllowed(tabId) {
        if (tabId === 'home') {
            return true;
        }
        if (!hubAllowedTabs) {
            return true;
        }
        return hubAllowedTabs.indexOf(tabId) >= 0;
    }

    function hubIsPartialAccess() {
        return hubAccessMode === 'Partial Hub Access';
    }

    function crmHubUpdateSearchPlaceholder() {
        var input = document.getElementById('cog-search');
        if (!input) {
            return;
        }
        var greeting = 'Hello, ' + crmHubHomeFirstName() + '; ';
        if (hubIsPartialAccess()) {
            input.placeholder = greeting + 'Search across Leads, Contacts, Accounts, Opps';
        } else {
            input.placeholder =
                greeting +
                'Search across Leads, Contacts, Accounts, Opps, Job Apps, Positions, Contracts';
        }
    }

    function crmHubApplyAccessConfig(cfg) {
        if (!cfg) {
            return;
        }
        hubAccessMode = cfg.mode || 'Partial Hub Access';
        hubAllowedTabs = cfg.allowedTabs || null;
        hubElevenLabsConfigured = !!cfg.elevenLabsConfigured;
        hubSmartCreditsRemaining = Number(cfg.smartCreditsRemaining) || 0;
        hubSmartUsedToday = !!cfg.smartUsedToday;
        crmHubUpdateSearchPlaceholder();
        crmHubRenderBriefingTabs();
        crmHubRenderBriefingAudience();
        crmHubUpdateBriefingCreditUi();
        if (!hubIsPartialAccess()) {
            return;
        }
        var blocked = ['jobapps', 'positions', 'contracts'];
        for (var i = 0; i < blocked.length; i++) {
            var bi = hubBriefingSelectedTabs.indexOf(blocked[i]);
            if (bi >= 0) {
                hubBriefingSelectedTabs.splice(bi, 1);
            }
            var tabId = blocked[i];
            var btn = document.querySelector('.hub-tab-btn[data-tab="' + tabId + '"]');
            if (btn) {
                btn.style.display = 'none';
                btn.setAttribute('aria-hidden', 'true');
            }
            var panel = document.getElementById('hub-panel-' + tabId);
            if (panel) {
                panel.style.display = 'none';
                panel.classList.remove('is-active');
            }
        }
        if (hubBriefingAudience === 'hr') {
            hubBriefingAudience = 'sales';
        }
        crmHubLayoutTabOverflow();
    }

    function crmHubTab(tabId) {
        if (!hubTabAllowed(tabId)) {
            tabId = 'home';
        }
        var panels = document.querySelectorAll('.hub-tab-panel');
        for (var pi = 0; pi < panels.length; pi++) {
            panels[pi].classList.remove('is-active');
        }
        var el = document.getElementById('hub-panel-' + tabId);
        if (el) {
            el.classList.add('is-active');
        }
        var btns = document.querySelectorAll('.hub-tab-btn');
        for (var bi = 0; bi < btns.length; bi++) {
            btns[bi].classList.remove('is-active');
            if (btns[bi].getAttribute('data-tab') === tabId) {
                btns[bi].classList.add('is-active');
            }
        }
        var wrap = document.querySelector('.hub-wrap');
        if (wrap && typeof wrap.scrollIntoView === 'function') {
            wrap.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }
        if (tabId === 'home') {
            crmHubLoadHomeStats(false);
        }
        if (tabId === 'leads' && global.CrmHubListEngine) {
            CrmHubListEngine.activate('Lead');
        }
        if (tabId === 'opps' && global.CrmHubListEngine) {
            CrmHubListEngine.activate('Opportunity');
        }
        if (tabId === 'accounts' && global.CrmHubListEngine) {
            CrmHubListEngine.activate('Account');
        }
        if (tabId === 'contacts' && global.CrmHubListEngine) {
            CrmHubListEngine.activate('Contact');
        }
        if (tabId === 'jobapps' && global.CrmHubListEngine && hubTabAllowed('jobapps')) {
            CrmHubListEngine.activate('Job_Application__c');
        }
        if (tabId === 'positions' && global.CrmHubListEngine && hubTabAllowed('positions')) {
            CrmHubListEngine.activate('Position__c');
        }
        if (tabId === 'contracts' && global.CrmHubListEngine && hubTabAllowed('contracts')) {
            CrmHubListEngine.activate('Employment_Contract__c');
        }
        if (tabId === 'commandcenter' && global.CrmHubCommandCenter) {
            CrmHubCommandCenter.activate();
        }
        var searchBox = document.querySelector('.hub-search-box');
        if (searchBox) {
            searchBox.style.display = tabId === 'commandcenter' ? 'none' : '';
        }
        crmHubLayoutTabOverflow();
    }

    function crmHubParseJson(id) {
        var n = document.getElementById(id);
        if (!n) {
            return [];
        }
        try {
            return JSON.parse(n.textContent || '[]');
        } catch (e) {
            return [];
        }
    }

    function crmHubLvHidden(prefix) {
        return document.getElementById('lv-id-' + prefix);
    }

    function crmHubComboFilterRows(rows, q) {
        var t = (q || '').trim().toLowerCase();
        if (!t) {
            return rows.slice();
        }
        var out = [];
        for (var i = 0; i < rows.length; i++) {
            var lab = (rows[i].label || '').toLowerCase();
            if (lab.indexOf(t) >= 0) {
                out.push(rows[i]);
            }
        }
        return out;
    }

    function crmHubPrefForObject(objectApi) {
        if (global.CrmHubListEngine && typeof CrmHubListEngine.getListViewPref === 'function') {
            return CrmHubListEngine.getListViewPref(objectApi);
        }
        return { pinnedId: '', favoriteIds: [] };
    }

    function crmHubSortLabel(a, b) {
        var la = (a.label || a.id || '').toLowerCase();
        var lb = (b.label || b.id || '').toLowerCase();
        if (la < lb) {
            return -1;
        }
        if (la > lb) {
            return 1;
        }
        return 0;
    }

    function crmHubPartitionRows(prefix, rows) {
        var objectApi = CRM_HUB_SYNC[prefix];
        var pref = crmHubPrefForObject(objectApi);
        var favSet = {};
        var favIds = pref.favoriteIds || [];
        for (var i = 0; i < favIds.length; i++) {
            favSet[favIds[i]] = true;
        }
        var favorites = [];
        var rest = [];
        for (var r = 0; r < rows.length; r++) {
            if (favSet[rows[r].id]) {
                favorites.push(rows[r]);
            } else {
                rest.push(rows[r]);
            }
        }
        favorites.sort(crmHubSortLabel);
        rest.sort(crmHubSortLabel);
        return {
            favorites: favorites,
            rest: rest,
            pinnedId: pref.pinnedId || '',
            favSet: favSet
        };
    }

    function crmHubUpdateComboPinnedState(prefix) {
        var btn = document.getElementById('combo-' + prefix + '-btn');
        var hid = crmHubLvHidden(prefix);
        if (!btn || !hid) {
            return;
        }
        var objectApi = CRM_HUB_SYNC[prefix];
        var pref = crmHubPrefForObject(objectApi);
        var pinned = pref.pinnedId || '';
        if (pinned && hid.value === pinned) {
            btn.classList.add('is-pinned');
            btn.setAttribute('title', 'Pinned list view');
        } else {
            btn.classList.remove('is-pinned');
            btn.removeAttribute('title');
        }
    }

    function crmHubRemotePref(methodName, objectApi, listViewId, onDone) {
        if (
            typeof CrmHubListController === 'undefined' ||
            typeof CrmHubListController[methodName] !== 'function' ||
            typeof Visualforce === 'undefined' ||
            !Visualforce.remoting
        ) {
            if (onDone) {
                onDone(null);
            }
            return;
        }
        try {
            CrmHubListController[methodName](
                objectApi,
                listViewId,
                function (res, ev) {
                    if (ev && ev.status && res && res.success && res.pref && global.CrmHubListEngine) {
                        CrmHubListEngine.setListViewPref(objectApi, res.pref);
                    }
                    if (onDone) {
                        onDone(res);
                    }
                },
                { escape: false }
            );
        } catch (eRemote) {
            if (onDone) {
                onDone(null);
            }
        }
    }

    function crmHubToggleFavorite(prefix, listViewId) {
        var objectApi = CRM_HUB_SYNC[prefix];
        if (!objectApi || !listViewId || !global.CrmHubListEngine) {
            return;
        }
        var pref = crmHubPrefForObject(objectApi);
        var favorites = (pref.favoriteIds || []).slice();
        var idx = favorites.indexOf(listViewId);
        if (idx >= 0) {
            favorites.splice(idx, 1);
        } else {
            favorites.push(listViewId);
        }
        CrmHubListEngine.setListViewPref(objectApi, {
            pinnedId: pref.pinnedId || '',
            favoriteIds: favorites
        });
        var rows = crmHubComboRowsCache[prefix] || [];
        var qEl = document.getElementById('combo-' + prefix + '-q');
        var q = qEl ? qEl.value : '';
        crmHubComboRenderUl(prefix, crmHubComboFilterRows(rows, q));
        crmHubRemotePref('toggleFavoriteListView', objectApi, listViewId);
    }

    function crmHubComboFlashError(prefix, msg) {
        var btn = document.getElementById('combo-' + prefix + '-btn');
        if (!btn || !msg) {
            return;
        }
        var prevTitle = btn.getAttribute('title') || '';
        btn.setAttribute('title', msg);
        btn.setAttribute('data-hub-lv-err', '1');
        setTimeout(function () {
            if (btn.getAttribute('data-hub-lv-err') !== '1') {
                return;
            }
            btn.removeAttribute('data-hub-lv-err');
            if (prevTitle) {
                btn.setAttribute('title', prevTitle);
            } else {
                btn.removeAttribute('title');
            }
            crmHubUpdateComboPinnedState(prefix);
        }, 2800);
    }

    function crmHubApplyListViewSelection(prefix, row, keepPanelOpen) {
        var hid = crmHubLvHidden(prefix);
        if (hid) {
            hid.value = row.id;
        }
        var btn = document.getElementById('combo-' + prefix + '-btn');
        if (btn) {
            var selectedLabel = row.label || row.id;
            btn.textContent = selectedLabel;
            btn.setAttribute('title', selectedLabel);
            btn.removeAttribute('data-hub-lv-err');
        }
        crmHubUpdateComboPinnedState(prefix);
        if (!keepPanelOpen) {
            var pan = document.getElementById('combo-' + prefix + '-panel');
            if (pan) {
                pan.style.display = 'none';
            }
        }
        if (global.CrmHubListEngine) {
            CrmHubListEngine.syncListView(CRM_HUB_SYNC[prefix], row.id);
        }
    }

    function crmHubTogglePin(prefix, listViewId) {
        var objectApi = CRM_HUB_SYNC[prefix];
        if (!objectApi || !listViewId || !global.CrmHubListEngine) {
            return;
        }
        var pref = crmHubPrefForObject(objectApi);
        var prevPinned = pref.pinnedId || '';
        var prevFav = (pref.favoriteIds || []).slice();
        var nextPinned = prevPinned === listViewId ? '' : listViewId;
        CrmHubListEngine.setListViewPref(objectApi, {
            pinnedId: nextPinned,
            favoriteIds: prevFav
        });
        var rows = crmHubComboRowsCache[prefix] || [];
        var qEl = document.getElementById('combo-' + prefix + '-q');
        var q = qEl ? qEl.value : '';
        var filtered = crmHubComboFilterRows(rows, q);
        if (nextPinned) {
            var pinLabel = listViewId;
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].id === listViewId) {
                    pinLabel = rows[i].label || listViewId;
                    break;
                }
            }
            // Select + sync, but keep the dropdown open so pin icons update in place.
            crmHubApplyListViewSelection(
                prefix,
                { id: listViewId, label: pinLabel },
                true
            );
        } else {
            crmHubUpdateComboPinnedState(prefix);
        }
        crmHubComboRenderUl(prefix, filtered);
        crmHubRemotePref('setPinnedListView', objectApi, nextPinned, function (res) {
            if (res && res.success) {
                return;
            }
            CrmHubListEngine.setListViewPref(objectApi, {
                pinnedId: prevPinned,
                favoriteIds: prevFav
            });
            crmHubUpdateComboPinnedState(prefix);
            crmHubComboRenderUl(prefix, crmHubComboFilterRows(rows, q));
            crmHubComboFlashError(
                prefix,
                (res && res.error) || 'Could not update pin. Try again.'
            );
        });
    }

    function crmHubAppendComboRow(ul, prefix, row, pinnedId, favSet, selectedId) {
        var li = document.createElement('li');
        var isSelected = !!(selectedId && selectedId === row.id);
        li.className = 'hub-lv-row' + (isSelected ? ' is-selected' : '');
        li.setAttribute('role', 'option');
        li.setAttribute('aria-selected', isSelected ? 'true' : 'false');

        var favBtn = document.createElement('button');
        favBtn.type = 'button';
        favBtn.className = 'hub-lv-icon-btn hub-lv-fav' + (favSet[row.id] ? ' is-on' : '');
        favBtn.setAttribute('aria-label', favSet[row.id] ? 'Remove favorite' : 'Add favorite');
        favBtn.setAttribute('title', favSet[row.id] ? 'Remove favorite' : 'Favorite');
        favBtn.textContent = favSet[row.id] ? '★' : '☆';
        favBtn.onclick = function (ev) {
            ev.preventDefault();
            ev.stopPropagation();
            crmHubToggleFavorite(prefix, row.id);
        };

        var labelBtn = document.createElement('button');
        labelBtn.type = 'button';
        labelBtn.className = 'hub-lv-row-label';
        labelBtn.textContent = row.label || row.id;
        labelBtn.setAttribute('data-id', row.id);
        labelBtn.setAttribute('data-label', row.label || row.id);
        labelBtn.setAttribute('title', row.label || row.id);
        labelBtn.onclick = function (ev) {
            var btn = ev.currentTarget;
            crmHubComboSelect(prefix, {
                id: btn.getAttribute('data-id'),
                label: btn.getAttribute('data-label')
            });
        };

        var pinBtn = document.createElement('button');
        pinBtn.type = 'button';
        var isPinned = pinnedId && pinnedId === row.id;
        pinBtn.className = 'hub-lv-icon-btn hub-lv-pin' + (isPinned ? ' is-on' : '');
        pinBtn.setAttribute('aria-label', isPinned ? 'Unpin list' : 'Pin as default');
        pinBtn.setAttribute('title', isPinned ? 'Unpin' : 'Pin as default');
        pinBtn.textContent = isPinned ? '📌' : '📍';
        pinBtn.onclick = function (ev) {
            ev.preventDefault();
            ev.stopPropagation();
            crmHubTogglePin(prefix, row.id);
        };

        var actions = document.createElement('span');
        actions.className = 'hub-lv-row-actions';
        actions.appendChild(pinBtn);
        actions.appendChild(favBtn);
        li.appendChild(actions);
        li.appendChild(labelBtn);
        ul.appendChild(li);
    }

    function crmHubComboRenderUl(prefix, rows) {
        var ul = document.getElementById('combo-' + prefix + '-ul');
        if (!ul) {
            return;
        }
        ul.innerHTML = '';
        var hid = crmHubLvHidden(prefix);
        var selectedId = hid ? hid.value : '';
        var parts = crmHubPartitionRows(prefix, rows || []);
        if (parts.favorites.length) {
            var favLabel = document.createElement('li');
            favLabel.className = 'hub-lv-section-label';
            favLabel.textContent = 'Favorites';
            ul.appendChild(favLabel);
            for (var f = 0; f < parts.favorites.length; f++) {
                crmHubAppendComboRow(ul, prefix, parts.favorites[f], parts.pinnedId, parts.favSet, selectedId);
            }
            if (parts.rest.length) {
                var divider = document.createElement('li');
                divider.className = 'hub-lv-divider';
                divider.setAttribute('aria-hidden', 'true');
                ul.appendChild(divider);
            }
        }
        for (var i = 0; i < parts.rest.length; i++) {
            crmHubAppendComboRow(ul, prefix, parts.rest[i], parts.pinnedId, parts.favSet, selectedId);
        }
    }

    function crmHubComboSelect(prefix, row) {
        crmHubApplyListViewSelection(prefix, row, false);
    }

    var crmHubComboRowsCache = {};

    function crmHubInitCombo(prefix, rows) {
        crmHubComboRowsCache[prefix] = rows || [];
        var hid = crmHubLvHidden(prefix);
        var sel = hid ? hid.value : '';
        var label = '';
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].id === sel) {
                label = rows[i].label || rows[i].id;
                break;
            }
        }
        var btn = document.getElementById('combo-' + prefix + '-btn');
        if (btn) {
            btn.textContent = label || 'Select list view';
            if (label) {
                btn.setAttribute('title', label);
            }
        }
        crmHubUpdateComboPinnedState(prefix);
        var q = document.getElementById('combo-' + prefix + '-q');
        if (q) {
            q.value = '';
        }
        crmHubComboRenderUl(prefix, rows);
        if (q) {
            q.oninput = function () {
                crmHubComboRenderUl(prefix, crmHubComboFilterRows(crmHubComboRowsCache[prefix] || [], q.value));
            };
        }
        if (btn) {
            btn.onclick = function (e) {
                e.stopPropagation();
                var pan = document.getElementById('combo-' + prefix + '-panel');
                if (!pan) {
                    return;
                }
                var open = pan.style.display !== 'block';
                document.querySelectorAll('.hub-lv-panel').forEach(function (p) {
                    p.style.display = 'none';
                });
                pan.style.display = open ? 'block' : 'none';
                if (open) {
                    crmHubComboRenderUl(
                        prefix,
                        crmHubComboFilterRows(crmHubComboRowsCache[prefix] || [], q ? q.value : '')
                    );
                    if (q) {
                        q.focus();
                    }
                }
            };
        }
    }

    function crmHubPersistedOrRadio(prefix, engineName) {
        var p = CrmHubListEngine.readPersistedMode(engineName);
        if (p === 'list' || p === 'cards' || p === 'kanban' || p === 'calendar') {
            return p;
        }
        var on = document.querySelector('input[name="' + prefix + '-view"]:checked');
        return on ? on.value : 'list';
    }

    function crmHubSetViewVisual(seg, mode) {
        var btns = seg.querySelectorAll('.hub-vm');
        for (var i = 0; i < btns.length; i++) {
            btns[i].classList.toggle('is-on', btns[i].getAttribute('data-mode') === mode);
        }
        var r = seg.querySelector('input[value="' + mode + '"]');
        if (r) {
            r.checked = true;
        }
    }

    function crmHubWireViewSeg(segEl, engineName) {
        var btns = segEl.querySelectorAll('.hub-vm');
        for (var i = 0; i < btns.length; i++) {
            btns[i].onclick = function () {
                var m = this.getAttribute('data-mode');
                crmHubSetViewVisual(segEl, m);
                CrmHubListEngine.syncMode(engineName, m);
                CrmHubListEngine.persistMode(engineName, m);
            };
        }
    }

    function crmHubSoqlModalEl() {
        return document.getElementById('hub-soql-modal');
    }

    function crmHubCloseSoqlModal() {
        var modal = crmHubSoqlModalEl();
        if (!modal) {
            return;
        }
        modal.classList.remove('is-open');
        modal.setAttribute('aria-hidden', 'true');
    }

    function crmHubOpenSoqlModal(prefix) {
        if (!global.CrmHubListEngine || typeof CrmHubListEngine.getTab !== 'function') {
            return;
        }
        var objectApi = CRM_HUB_SYNC[prefix];
        if (!objectApi) {
            return;
        }
        var tab = CrmHubListEngine.getTab(objectApi);
        if (!tab || typeof tab.getDescribeSnapshot !== 'function') {
            return;
        }
        var snap = tab.getDescribeSnapshot();
        var modal = crmHubSoqlModalEl();
        var titleEl = document.getElementById('hub-soql-title');
        var textEl = document.getElementById('hub-soql-text');
        if (!modal || !textEl) {
            return;
        }
        if (titleEl) {
            titleEl.textContent = snap.label ? snap.label + ' — SOQL' : 'List view SOQL';
        }
        if (snap.error) {
            textEl.textContent = snap.error;
        } else if (snap.query) {
            textEl.textContent = snap.query;
        } else {
            textEl.textContent = 'No SOQL query is available for this list view.';
        }
        modal.classList.add('is-open');
        modal.setAttribute('aria-hidden', 'false');
    }

    function crmHubInitSoqlModal() {
        var modal = crmHubSoqlModalEl();
        if (!modal) {
            return;
        }
        modal.addEventListener('click', function (ev) {
            if (ev.target === modal) {
                crmHubCloseSoqlModal();
            }
        });
        var closeBtns = modal.querySelectorAll('[data-hub-soql-close]');
        for (var ci = 0; ci < closeBtns.length; ci++) {
            closeBtns[ci].onclick = crmHubCloseSoqlModal;
        }
        var copyBtn = document.getElementById('hub-soql-copy');
        if (copyBtn) {
            copyBtn.onclick = function () {
                var textEl = document.getElementById('hub-soql-text');
                var text = textEl ? textEl.textContent || '' : '';
                if (!text) {
                    return;
                }
                if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
                    navigator.clipboard.writeText(text).catch(function () {});
                    return;
                }
                var ta = document.createElement('textarea');
                ta.value = text;
                ta.setAttribute('readonly', 'readonly');
                ta.style.position = 'absolute';
                ta.style.left = '-9999px';
                document.body.appendChild(ta);
                ta.select();
                try {
                    document.execCommand('copy');
                } catch (e) {}
                document.body.removeChild(ta);
            };
        }
        document.addEventListener('keydown', function (ev) {
            if (ev.key === 'Escape' && modal.classList.contains('is-open')) {
                crmHubCloseSoqlModal();
            }
        });
    }

    function crmHubWireSoqlButtons() {
        var btns = document.querySelectorAll('[id^="hub-soql-"]');
        for (var i = 0; i < btns.length; i++) {
            (function (btn) {
                btn.onclick = function () {
                    var prefix = btn.getAttribute('data-prefix');
                    if (prefix) {
                        crmHubOpenSoqlModal(prefix);
                    }
                };
            })(btns[i]);
        }
    }

    function crmHubCogClick(ev) {
        var t = ev.target;
        if (!t || !t.closest) {
            return;
        }
        var btn = t.closest('[data-cog-id]');
        if (btn) {
            var rid = btn.getAttribute('data-cog-id');
            if (rid && typeof global.crmHubOpenRecordModal === 'function') {
                global.crmHubOpenRecordModal(rid);
            }
        }
    }

    function crmHubEsc(s) {
        if (s == null) {
            return '';
        }
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/"/g, '&quot;');
    }

    function crmHubSetVoiceStatus(msg) {
        var el = document.getElementById('cog-voice-status');
        if (el) {
            el.textContent = msg || '';
        }
    }

    function crmHubSetSpeakEnabled(on) {
        var btn = document.getElementById('cog-speak-btn');
        if (btn) {
            btn.disabled = !on;
        }
    }

    function crmHubStopSpeech() {
        hubBrowserSpeakGen += 1;
        if (typeof window !== 'undefined' && window.speechSynthesis) {
            window.speechSynthesis.cancel();
        }
        if (cogTtsAudio) {
            try {
                cogTtsAudio.pause();
                cogTtsAudio.removeAttribute('src');
                cogTtsAudio.load();
            } catch (eAudio) {
                /* ignore */
            }
            cogTtsAudio = null;
        }
        var speakBtn = document.getElementById('cog-speak-btn');
        if (speakBtn) {
            speakBtn.classList.remove('is-speaking');
        }
    }

    function crmHubGetSpokenUserName() {
        var firstEl = document.getElementById('crm-hub-user-first-name');
        var first = firstEl ? String(firstEl.value || '').trim() : '';
        if (first) {
            return first;
        }
        var lastEl = document.getElementById('crm-hub-user-last-name');
        var last = lastEl ? String(lastEl.value || '').trim() : '';
        return last;
    }

    function crmHubBuildTimeGreeting() {
        var hour = new Date().getHours();
        var salutation =
            hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
        var name = crmHubGetSpokenUserName();
        return name ? salutation + ', ' + name + '.' : salutation + '.';
    }

    function crmHubPickTtsVoice() {
        if (!window.speechSynthesis) {
            return null;
        }
        var voices = window.speechSynthesis.getVoices() || [];
        if (!voices.length) {
            return null;
        }
        var preferred = [
            'Google US English',
            'Microsoft Aria Online (Natural) - English (United States)',
            'Microsoft Jenny Online (Natural) - English (United States)',
            'Samantha',
            'Karen',
            'Moira',
            'Google UK English Female',
            'Karen',
            'Daniel'
        ];
        var i;
        var j;
        for (i = 0; i < preferred.length; i++) {
            for (j = 0; j < voices.length; j++) {
                if (voices[j].name === preferred[i]) {
                    return voices[j];
                }
            }
        }
        for (j = 0; j < voices.length; j++) {
            var lang = (voices[j].lang || '').toLowerCase();
            if (lang.indexOf('en') === 0 && /premium|enhanced|natural|neural|online/i.test(voices[j].name || '')) {
                return voices[j];
            }
        }
        for (j = 0; j < voices.length; j++) {
            if ((voices[j].lang || '').toLowerCase().indexOf('en') === 0) {
                return voices[j];
            }
        }
        return voices[0];
    }

    function crmHubEnsureTtsVoice(cb) {
        if (!window.speechSynthesis) {
            cb(null);
            return;
        }
        cogPreferredVoice = crmHubPickTtsVoice();
        if (cogPreferredVoice) {
            cb(cogPreferredVoice);
            return;
        }
        var done = false;
        function finish() {
            if (done) {
                return;
            }
            done = true;
            cogPreferredVoice = crmHubPickTtsVoice();
            cb(cogPreferredVoice);
        }
        window.speechSynthesis.onvoiceschanged = finish;
        setTimeout(finish, 400);
    }

    function crmHubBuildSpeakSummary(query, res) {
        var greeting = crmHubBuildTimeGreeting();
        if (!res) {
            return greeting + ' There are no search results to read right now.';
        }
        var sections = [
            { label: 'leads', singular: 'lead', rows: res.leads },
            { label: 'contacts', singular: 'contact', rows: res.contacts },
            { label: 'accounts', singular: 'account', rows: res.accounts },
            { label: 'opportunities', singular: 'opportunity', rows: res.opportunities },
            { label: 'job applications', singular: 'job application', rows: res.jobApplications },
            { label: 'positions', singular: 'position', rows: res.positions },
            { label: 'contracts', singular: 'contract', rows: res.contracts }
        ];
        var countParts = [];
        var detailParts = [];
        var total = 0;
        var s;
        for (s = 0; s < sections.length; s++) {
            var rows = sections[s].rows || [];
            if (!rows.length) {
                continue;
            }
            total += rows.length;
            var label =
                rows.length === 1 ? sections[s].singular : sections[s].label;
            countParts.push(rows.length + ' ' + label);
            var names = [];
            var n;
            for (n = 0; n < rows.length && names.length < 5; n++) {
                var row = rows[n] || {};
                var bit = row.name || '';
                if (!bit) {
                    continue;
                }
                if (row.subtitle) {
                    bit += ', ' + String(row.subtitle).replace(/\s+/g, ' ').trim();
                }
                names.push(bit);
            }
            if (names.length) {
                detailParts.push(
                    'For ' +
                        sections[s].label +
                        ': ' +
                        names.join('; ') +
                        (rows.length > names.length ? ', and more' : '') +
                        '.'
                );
            }
        }
        if (!total) {
            return (
                greeting +
                ' I did not find any matches for ' +
                (query || 'your search') +
                '.'
            );
        }
        var line =
            greeting +
            ' I found ' +
            total +
            ' result' +
            (total === 1 ? '' : 's') +
            ' for ' +
            (query || 'your search') +
            '. That includes ' +
            countParts.join(', ') +
            '.';
        if (detailParts.length) {
            line += ' ' + detailParts.join(' ');
        }
        return line;
    }

    /**
     * Split spoken text so browser TTS can pause after periods and commas.
     */
    function crmHubSplitSpeakChunks(text) {
        var normalized = String(text || '')
            .replace(/\s+/g, ' ')
            .trim();
        if (!normalized) {
            return [];
        }
        var raw = normalized.split(/([,.]\s+)/);
        var chunks = [];
        var i = 0;
        while (i < raw.length) {
            var piece = raw[i] || '';
            var delim = raw[i + 1] || '';
            i += 2;
            var spoken = (piece + (delim ? delim.charAt(0) : '')).trim();
            if (!spoken) {
                continue;
            }
            var pauseAfter = 0;
            if (delim.charAt(0) === '.') {
                pauseAfter = 420;
            } else if (delim.charAt(0) === ',') {
                pauseAfter = 180;
            }
            chunks.push({ text: spoken, pauseAfter: pauseAfter });
        }
        if (!chunks.length) {
            chunks.push({ text: normalized, pauseAfter: 0 });
        }
        return chunks;
    }

    function crmHubSpeakWithBrowser(text, onEnd) {
        if (!window.speechSynthesis || !text) {
            if (typeof onEnd === 'function') {
                onEnd();
            }
            return;
        }
        var myGen = hubBrowserSpeakGen;
        var chunks = crmHubSplitSpeakChunks(text);
        if (!chunks.length) {
            if (typeof onEnd === 'function') {
                onEnd();
            }
            return;
        }
        crmHubEnsureTtsVoice(function (voice) {
            if (myGen !== hubBrowserSpeakGen) {
                return;
            }
            var speakBtn = document.getElementById('cog-speak-btn');
            if (speakBtn) {
                speakBtn.classList.add('is-speaking');
            }
            var idx = 0;
            function finish() {
                if (speakBtn) {
                    speakBtn.classList.remove('is-speaking');
                }
                if (typeof onEnd === 'function') {
                    onEnd();
                }
            }
            function speakNext() {
                if (myGen !== hubBrowserSpeakGen) {
                    return;
                }
                if (idx >= chunks.length) {
                    finish();
                    return;
                }
                var chunk = chunks[idx++];
                var utter = new SpeechSynthesisUtterance(chunk.text);
                utter.rate = 0.98;
                utter.pitch = 1;
                utter.volume = 1;
                if (voice) {
                    utter.voice = voice;
                    if (voice.lang) {
                        utter.lang = voice.lang;
                    }
                } else {
                    utter.lang = 'en-US';
                }
                utter.onend = function () {
                    if (myGen !== hubBrowserSpeakGen) {
                        return;
                    }
                    if (chunk.pauseAfter > 0 && idx < chunks.length) {
                        setTimeout(speakNext, chunk.pauseAfter);
                    } else {
                        speakNext();
                    }
                };
                utter.onerror = function () {
                    if (myGen !== hubBrowserSpeakGen) {
                        return;
                    }
                    finish();
                };
                window.speechSynthesis.speak(utter);
            }
            speakNext();
        });
    }

    function crmHubPlayBase64Audio(base64, mimeType, onEnd, fallbackText) {
        var speakBtn = document.getElementById('cog-speak-btn');
        try {
            var binary = atob(base64);
            var len = binary.length;
            var bytes = new Uint8Array(len);
            var i;
            for (i = 0; i < len; i++) {
                bytes[i] = binary.charCodeAt(i);
            }
            var blob = new Blob([bytes], { type: mimeType || 'audio/mpeg' });
            var url = URL.createObjectURL(blob);
            if (cogTtsAudio) {
                try {
                    cogTtsAudio.pause();
                } catch (ePause) {
                    /* ignore */
                }
            }
            cogTtsAudio = new Audio(url);
            if (speakBtn) {
                speakBtn.classList.add('is-speaking');
            }
            var finish = function () {
                try {
                    URL.revokeObjectURL(url);
                } catch (eRev) {
                    /* ignore */
                }
                if (speakBtn) {
                    speakBtn.classList.remove('is-speaking');
                }
                cogTtsAudio = null;
                if (typeof onEnd === 'function') {
                    onEnd();
                }
            };
            cogTtsAudio.onended = finish;
            cogTtsAudio.onerror = function () {
                try {
                    URL.revokeObjectURL(url);
                } catch (eRev2) {
                    /* ignore */
                }
                if (speakBtn) {
                    speakBtn.classList.remove('is-speaking');
                }
                cogTtsAudio = null;
                crmHubSpeakWithBrowser(fallbackText || '', onEnd);
            };
            cogTtsAudio.play().catch(function () {
                if (speakBtn) {
                    speakBtn.classList.remove('is-speaking');
                }
                cogTtsAudio = null;
                crmHubSpeakWithBrowser(fallbackText || '', onEnd);
            });
        } catch (ePlay) {
            if (speakBtn) {
                speakBtn.classList.remove('is-speaking');
            }
            crmHubSpeakWithBrowser(fallbackText || '', onEnd);
        }
    }

    function crmHubInvokeRemote(actionPath, args, callback, options) {
        options = options || { escape: false, timeout: 120000 };
        var remote = global.CRM_HUB_REMOTE || {};
        var resolved =
            (actionPath === 'CrmHubListController.fetchHubBriefing' && remote.fetchHubBriefing) ||
            (actionPath === 'CrmHubHomeController.fetchHubHomeStats' && remote.fetchHubHomeStats) ||
            (actionPath === 'CrmHubListController.fetchHubHomeStats' && remote.fetchHubHomeStats) ||
            (actionPath === 'CrmHubListController.synthesizeHubSpeech' && remote.synthesizeHubSpeech) ||
            (actionPath === 'CrmHubVoiceSearchController.transcribeHubSpeech' &&
                remote.transcribeHubSpeech) ||
            (actionPath === 'CrmHubListController.transcribeHubSpeech' && remote.transcribeHubSpeech) ||
            (actionPath === 'CrmHubListController.getHubBriefingVoiceStatus' &&
                remote.getHubBriefingVoiceStatus) ||
            actionPath;
        if (
            typeof Visualforce === 'undefined' ||
            !Visualforce.remoting ||
            !Visualforce.remoting.Manager ||
            typeof Visualforce.remoting.Manager.invokeAction !== 'function'
        ) {
            callback(null, { status: false, message: 'Visualforce remoting unavailable' });
            return;
        }
        var callArgs = [resolved].concat(args || []);
        callArgs.push(callback);
        callArgs.push(options);
        Visualforce.remoting.Manager.invokeAction.apply(Visualforce.remoting.Manager, callArgs);
    }

    /**
     * Briefing may pass { useSmart: true } for ElevenLabs (1 credit/day).
     * Search Speak always uses browser Web Speech.
     * otherwise improved browser Web Speech.
     */
    function crmHubSpeakText(text, onEnd, opts) {
        opts = opts || {};
        if (!text) {
            if (typeof onEnd === 'function') {
                onEnd();
            }
            return;
        }
        crmHubStopSpeech();

        var useSmart = !!opts.useSmart;
        if (!useSmart) {
            crmHubSpeakWithBrowser(text, onEnd);
            return;
        }

        var hasTyped =
            typeof CrmHubListController !== 'undefined' &&
            typeof CrmHubListController.synthesizeHubSpeech === 'function';
        var hasRemoting =
            typeof Visualforce !== 'undefined' &&
            Visualforce.remoting &&
            Visualforce.remoting.Manager;

        function onSynth(res, ev) {
            if (res) {
                if (typeof res.smartCreditsRemaining === 'number') {
                    hubSmartCreditsRemaining = Number(res.smartCreditsRemaining) || 0;
                }
                if (typeof res.smartUsedToday === 'boolean') {
                    hubSmartUsedToday = !!res.smartUsedToday;
                }
                if (typeof res.elevenLabsConfigured === 'boolean') {
                    hubElevenLabsConfigured = !!res.elevenLabsConfigured;
                }
                crmHubUpdateBriefingCreditUi();
            }
            if (ev && ev.status && res && res.success && res.audioBase64) {
                crmHubPlayBase64Audio(res.audioBase64, res.mimeType || 'audio/mpeg', onEnd, text);
                return;
            }
            if (opts.useSmart) {
                var why =
                    (res && res.error) ||
                    (ev && !ev.status && ev.message) ||
                    'Smart voice unavailable';
                crmHubSetVoiceStatus(why + ' — using standard voice.');
            }
            crmHubSpeakWithBrowser(text, onEnd);
        }

        if (!hasTyped && !hasRemoting) {
            crmHubSpeakWithBrowser(text, onEnd);
            return;
        }

        try {
            if (hasTyped) {
                CrmHubListController.synthesizeHubSpeech(
                    text,
                    useSmart,
                    onSynth,
                    { escape: false, timeout: 120000 }
                );
            } else {
                crmHubInvokeRemote(
                    'CrmHubListController.synthesizeHubSpeech',
                    [text, useSmart],
                    onSynth,
                    { escape: false, timeout: 120000 }
                );
            }
        } catch (eSynth) {
            crmHubSpeakWithBrowser(text, onEnd);
        }
    }

    /**
     * CrmHubVoice popup posts { source: 'crmHubVoice', type, … }.
     * Used when Hub is framed (e.g. VF tab inside LEX) because cross-origin
     * parents do not grant microphone to the Visualforce iframe.
     */
    function crmHubBindVoicePopupMessages() {
        if (global.__crmHubVoicePopupBound) {
            return;
        }
        global.__crmHubVoicePopupBound = true;
        window.addEventListener('message', function (ev) {
            var data = ev && ev.data;
            if (!data || data.source !== 'crmHubVoice') {
                return;
            }
            if (data.type === 'ready' || data.type === 'listening') {
                crmHubVoiceOpenModal();
                crmHubSetMicListening(true);
                crmHubVoiceSetRecoveryActions(false);
                crmHubVoiceSetHint('Listening… speak now, then tap I’m done speaking… search.');
                crmHubVoiceSetTranscript('', { emptyMsg: 'Listening for speech…' });
                var titleReady = document.getElementById('hub-voice-title');
                if (titleReady) {
                    titleReady.textContent = 'Listening';
                }
            } else if (data.type === 'interim') {
                var interim = (data.transcript || '').trim();
                if (interim) {
                    crmHubVoiceOpenModal();
                    crmHubSetMicListening(true);
                    crmHubVoiceSetTranscript(interim);
                    crmHubVoiceSetHint('Hearing you… tap I’m done speaking… search when ready.');
                }
            } else if (data.type === 'transcript') {
                hubVoicePopupRef = null;
                var text = (data.transcript || '').trim();
                if (text) {
                    crmHubApplyTranscriptAndSearch(text);
                } else {
                    crmHubVoiceCloseModal();
                    crmHubSetVoiceStatus('Nothing captured. Tap the mic and try again.');
                }
            } else if (data.type === 'error') {
                hubVoicePopupRef = null;
                crmHubVoiceOpenModal();
                crmHubVoiceShowBlocked('not-allowed');
                crmHubVoiceSetHint(
                    (data.message || 'Microphone blocked.') +
                        ' Allow mic for the voice window, then tap Try again.'
                );
                crmHubSetVoiceStatus(data.message || 'Voice search failed.');
            } else if (data.type === 'closed') {
                hubVoicePopupRef = null;
                crmHubSetMicListening(false);
            }
        });
        crmHubVoiceBindModalControls();
    }

    function crmHubSpeakResults() {
        if (!cogLastSearchRes) {
            crmHubSetVoiceStatus('Run a search first, then tap speak.');
            return;
        }
        if (
            (window.speechSynthesis && window.speechSynthesis.speaking) ||
            (cogTtsAudio && !cogTtsAudio.paused)
        ) {
            crmHubStopSpeech();
            crmHubSetVoiceStatus('Stopped reading.');
            return;
        }
        var summary = crmHubBuildSpeakSummary(cogLastQuery, cogLastSearchRes);
        crmHubSetVoiceStatus('Reading results…');
        crmHubSpeakText(summary, function () {
            crmHubSetVoiceStatus('');
        });
    }

    var cogVoiceSession = null;
    var hubVoicePopupRef = null;
    var crmHubAudioCtx = null;
    var HUB_TAB_MIN_WIDTH = 68;
    var HUB_TAB_VISIBLE_SLOTS = 4; /* primary destinations + More */

    function crmHubSpeechCtor() {
        return window.SpeechRecognition || window.webkitSpeechRecognition || null;
    }

    /** True when this VF page is inside a parent frame (mic usually blocked). */
    function crmHubIsFramed() {
        try {
            return window.top !== window.self;
        } catch (eFrame) {
            return true;
        }
    }

    function crmHubVoicePopupUrl() {
        try {
            return new URL('/apex/CrmHubVoice', window.location.href).toString();
        } catch (eUrl) {
            return '/apex/CrmHubVoice';
        }
    }

    function crmHubCloseVoicePopup() {
        if (!hubVoicePopupRef) {
            return;
        }
        try {
            hubVoicePopupRef.postMessage({ source: 'crmHubList', type: 'stop' }, '*');
        } catch (ePost) {
            /* ignore */
        }
        try {
            if (!hubVoicePopupRef.closed) {
                hubVoicePopupRef.close();
            }
        } catch (eClose) {
            /* ignore */
        }
        hubVoicePopupRef = null;
    }

    /**
     * Open top-level /apex/CrmHubVoice under the user gesture so the browser
     * allows mic when this Hub page itself is framed. Orb modal stays the UI.
     */
    function crmHubOpenVoicePopupBridge() {
        crmHubBindVoicePopupMessages();
        crmHubAbortVoiceSessionSoft();
        crmHubCloseVoicePopup();
        crmHubVoiceOpenModal();
        crmHubVoiceSetHint('Opening secure mic window…');
        crmHubVoiceSetTranscript('', { emptyMsg: 'Preparing mic…' });
        crmHubVoiceSetRecoveryActions(false);

        var features =
            'popup=yes,width=360,height=420,left=' +
            Math.max(40, Math.round((window.screen.width || 800) / 2 - 180)) +
            ',top=' +
            Math.max(40, Math.round((window.screen.height || 600) / 2 - 210)) +
            ',resizable=yes,scrollbars=no';
        var popup;
        try {
            popup = window.open(crmHubVoicePopupUrl(), 'crmHubVoiceMic', features);
        } catch (eOpen) {
            popup = null;
        }
        if (!popup) {
            crmHubVoiceShowBlocked('popup-blocked');
            return false;
        }
        hubVoicePopupRef = popup;
        try {
            popup.focus();
        } catch (eFocus) {
            /* ignore */
        }
        return true;
    }

    function crmHubPlayListenCue() {
        try {
            if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
                return;
            }
            var AC = window.AudioContext || window.webkitAudioContext;
            if (!AC) {
                return;
            }
            if (!crmHubAudioCtx) {
                crmHubAudioCtx = new AC();
            }
            var ctx = crmHubAudioCtx;
            if (ctx.state === 'suspended' && ctx.resume) {
                ctx.resume();
            }
            var now = ctx.currentTime;
            function tone(freq, start, dur, peak) {
                var osc = ctx.createOscillator();
                var gain = ctx.createGain();
                osc.type = 'sine';
                osc.frequency.setValueAtTime(freq, start);
                gain.gain.setValueAtTime(0.0001, start);
                gain.gain.exponentialRampToValueAtTime(peak, start + 0.018);
                gain.gain.exponentialRampToValueAtTime(0.0001, start + dur);
                osc.connect(gain);
                gain.connect(ctx.destination);
                osc.start(start);
                osc.stop(start + dur + 0.03);
            }
            /* Soft two-note “ready” chime — subtle, mobile-friendly */
            tone(784, now, 0.11, 0.055);
            tone(1046.5, now + 0.09, 0.14, 0.04);
        } catch (eCue) {
            /* never block voice UI if AudioContext fails */
        }
    }

    function crmHubSetMicListening(on) {
        var mic = document.getElementById('cog-mic-btn');
        var overlay = document.getElementById('hub-voice-overlay');
        if (mic) {
            if (on) {
                mic.classList.add('is-listening');
            } else {
                mic.classList.remove('is-listening');
            }
        }
        if (overlay) {
            if (on) {
                overlay.classList.add('is-listening');
            } else {
                overlay.classList.remove('is-listening');
            }
        }
    }

    function crmHubVoiceSetHint(msg) {
        var hint = document.getElementById('hub-voice-hint');
        if (hint) {
            hint.textContent = msg || '';
        }
        crmHubSetVoiceStatus(msg || '');
    }

    function crmHubVoiceSetTranscript(text, opts) {
        var el = document.getElementById('hub-voice-transcript');
        if (!el) {
            return;
        }
        opts = opts || {};
        var t = (text || '').trim();
        if (t) {
            el.textContent = t;
            el.classList.remove('is-placeholder');
            el.classList.remove('is-suppressed');
            el.removeAttribute('data-empty');
        } else {
            el.textContent = '';
            el.classList.add('is-placeholder');
            var emptyMsg = opts.emptyMsg || 'Listening for speech…';
            el.setAttribute('data-empty', emptyMsg);
            /* Hide the light-blue bar when there is nothing useful to show (blocked / recovery). */
            if (opts.suppress || emptyMsg === ' ' || emptyMsg === '') {
                el.classList.add('is-suppressed');
            } else {
                el.classList.remove('is-suppressed');
            }
        }
    }

    function crmHubVoiceSetRecoveryActions(show) {
        var stopBtn = document.getElementById('hub-voice-stop');
        var retryBtn = document.getElementById('hub-voice-retry');
        var cancelBtn = document.getElementById('hub-voice-cancel');
        if (stopBtn) {
            stopBtn.hidden = !!show;
        }
        if (retryBtn) {
            retryBtn.hidden = !show;
        }
        if (cancelBtn) {
            cancelBtn.textContent = show ? 'Continue typing' : 'Cancel';
        }
    }

    function crmHubVoiceFocusSearch() {
        var input = document.getElementById('cog-search');
        if (!input) {
            return;
        }
        try {
            input.focus();
            if (typeof input.select === 'function' && input.value) {
                input.select();
            }
        } catch (eFocus) {
            /* ignore */
        }
    }

    function crmHubReleaseMediaStream(stream) {
        if (!stream) {
            return;
        }
        try {
            var tracks = stream.getTracks();
            var i;
            for (i = 0; i < tracks.length; i++) {
                tracks[i].stop();
            }
        } catch (eRel) {
            /* ignore */
        }
    }

    /**
     * Request mic under a user gesture. In LEX iframes, getUserMedia first often
     * unlocks SpeechRecognition (service-not-allowed) without opening a new window.
     */
    function crmHubRequestMicPermission(done) {
        if (!navigator.mediaDevices || typeof navigator.mediaDevices.getUserMedia !== 'function') {
            done({ ok: true, stream: null });
            return;
        }
        try {
            navigator.mediaDevices
                .getUserMedia({ audio: true })
                .then(function (stream) {
                    done({ ok: true, stream: stream });
                })
                .catch(function (err) {
                    var name = String((err && (err.name || err.message)) || '');
                    if (/NotAllowed|PermissionDenied|SecurityError/i.test(name)) {
                        done({ ok: false, code: 'not-allowed' });
                    } else if (/NotFound|DevicesNotFound|NotReadable|TrackStart|AbortError/i.test(name)) {
                        done({ ok: false, code: 'audio-capture' });
                    } else {
                        /* Still try SpeechRecognition — gUM failure is not always fatal. */
                        done({ ok: true, stream: null });
                    }
                });
        } catch (eSync) {
            done({ ok: true, stream: null });
        }
    }

    function crmHubVoiceOpenModal() {
        var overlay = document.getElementById('hub-voice-overlay');
        if (!overlay) {
            return;
        }
        overlay.classList.remove('is-speaking');
        overlay.classList.add('is-open');
        overlay.setAttribute('aria-hidden', 'false');
        var title = document.getElementById('hub-voice-title');
        if (title) {
            title.textContent = 'Listening';
        }
        var stopBtn = document.getElementById('hub-voice-stop');
        if (stopBtn) {
            stopBtn.hidden = false;
            stopBtn.textContent = 'I’m done speaking… search';
        }
        hubBriefingSpeaking = false;
        crmHubVoiceSetRecoveryActions(false);
        crmHubVoiceSetTranscript('', { emptyMsg: 'Listening for speech…' });
        crmHubVoiceSetHint('Speak your search, then tap I’m done speaking… search.');
    }

    function crmHubVoiceCloseModal() {
        var overlay = document.getElementById('hub-voice-overlay');
        if (!overlay) {
            return;
        }
        overlay.classList.remove('is-open');
        overlay.classList.remove('is-listening');
        overlay.classList.remove('is-speaking');
        overlay.setAttribute('aria-hidden', 'true');
        crmHubSetMicListening(false);
        crmHubSetVoiceOverlaySpeaking(false);
        crmHubVoiceSetRecoveryActions(false);
        hubBriefingSpeaking = false;
        var stopBtn = document.getElementById('hub-voice-stop');
        if (stopBtn) {
            stopBtn.textContent = 'I’m done speaking… search';
        }
        var cancelBtn = document.getElementById('hub-voice-cancel');
        if (cancelBtn) {
            cancelBtn.textContent = 'Cancel';
        }
    }

    function crmHubApplyTranscriptAndSearch(transcript) {
        transcript = (transcript || '').trim();
        crmHubVoiceCloseModal();
        if (!transcript) {
            crmHubSetVoiceStatus('Could not understand that. Please try again.');
            return;
        }
        var input = document.getElementById('cog-search');
        if (input) {
            input.value = transcript;
        }
        crmHubSetVoiceStatus('Searching for “' + transcript + '”…');
        cogVoiceFromMic = true;
        crmHubRunSearch();
    }

    function crmHubVoiceStopSession(submit) {
        if (hubVoicePopupRef && !hubVoicePopupRef.closed) {
            if (submit) {
                try {
                    hubVoicePopupRef.postMessage({ source: 'crmHubList', type: 'stop' }, '*');
                } catch (eStopPost) {
                    crmHubCloseVoicePopup();
                    crmHubVoiceCloseModal();
                }
                crmHubVoiceSetHint('Finishing…');
                return;
            }
            try {
                hubVoicePopupRef.postMessage({ source: 'crmHubList', type: 'cancel' }, '*');
            } catch (eCancelPost) {
                /* ignore */
            }
            crmHubCloseVoicePopup();
            crmHubVoiceCloseModal();
            crmHubSetVoiceStatus('');
            return;
        }
        var session = cogVoiceSession;
        if (!session) {
            crmHubVoiceCloseModal();
            return;
        }
        session.wantListen = false;
        if (session.restartTimer) {
            clearTimeout(session.restartTimer);
            session.restartTimer = null;
        }

        if (session.mode === 'media' && session.recorder) {
            var mediaRec = session.recorder;
            if (mediaRec.state === 'inactive') {
                crmHubFinishMediaSession(session, submit);
                return;
            }
            mediaRec.onstop = function () {
                try {
                    session.blob = new Blob(session.chunks || [], {
                        type: session.mimeType || 'audio/webm'
                    });
                } catch (eBlob) {
                    session.blob = null;
                }
                crmHubFinishMediaSession(session, submit);
            };
            try {
                mediaRec.stop();
            } catch (eStopRec) {
                crmHubFinishMediaSession(session, submit);
            }
            return;
        }

        var finalText = (session.finalText || '').trim();
        if (!finalText && session.interimText) {
            finalText = String(session.interimText || '').trim();
        }
        crmHubReleaseMediaStream(session.micStream);
        session.micStream = null;
        try {
            if (session.rec) {
                session.rec.stop();
            }
        } catch (eStop) {
            /* ignore */
        }
        cogVoiceSession = null;
        crmHubSetMicListening(false);
        if (submit) {
            crmHubVoiceSetHint('Finishing…');
            if (finalText) {
                crmHubApplyTranscriptAndSearch(finalText);
            } else {
                crmHubVoiceCloseModal();
                crmHubSetVoiceStatus('Nothing captured. Tap the mic and try again.');
            }
        } else {
            crmHubVoiceCloseModal();
            crmHubSetVoiceStatus('');
        }
    }

    function crmHubVoiceShowBlocked(code) {
        var titleEl = document.getElementById('hub-voice-title');
        var statusMsg;
        var titleText = 'Unavailable';
        var host = '';
        try {
            host = window.location.hostname || '';
        } catch (eHost) {
            host = '';
        }
        if (code === 'not-allowed' || code === 'audio-capture') {
            titleText = 'Mic blocked';
            statusMsg =
                'Microphone was denied for this Visualforce site' +
                (host ? ' (' + host + ')' : '') +
                '. In the browser address bar / site settings, allow Microphone, then tap Try again.';
        } else if (code === 'popup-blocked') {
            titleText = 'Popup blocked';
            statusMsg =
                'Browser blocked the mic helper window. Allow popups for this Salesforce domain, then tap Try again.';
        } else if (code === 'service-not-allowed' || code === 'iframe') {
            titleText = 'Mic blocked';
            statusMsg =
                'This Hub tab is framed, so the browser blocks the mic here. Tap Try again to use the mic helper window, or allow Microphone for ' +
                (host || 'this Visualforce domain') +
                '.';
        } else if (code === 'network') {
            titleText = 'Voice offline';
            statusMsg =
                'Browser speech service failed. Tap Try again to record with the mic (server transcription), or Continue typing.';
        } else if (code === 'stt') {
            titleText = 'Couldn’t transcribe';
            statusMsg = 'Transcription failed. Tap Try again, or Continue typing.';
        } else if (code === 'unsupported') {
            titleText = 'Unsupported';
            statusMsg =
                'Voice recording needs a modern Chrome or Edge. Or Continue typing to search below.';
        } else {
            statusMsg =
                'Voice failed' + (code ? ' (' + code + ')' : '') + '. Tap Try again, or Continue typing.';
        }
        if (titleEl) {
            titleEl.textContent = titleText;
        }
        /* Hint carries the tip; hide empty transcript bar so it does not look like a blank chip. */
        crmHubVoiceSetHint(statusMsg);
        crmHubVoiceSetTranscript('', { emptyMsg: ' ', suppress: true });
        crmHubVoiceSetRecoveryActions(true);
        crmHubSetMicListening(false);
    }

    function crmHubAbortVoiceSessionSoft() {
        var session = cogVoiceSession;
        if (!session) {
            return;
        }
        session.wantListen = false;
        if (session.restartTimer) {
            clearTimeout(session.restartTimer);
            session.restartTimer = null;
        }
        try {
            if (session.recorder && session.recorder.state !== 'inactive') {
                session.recorder.onstop = null;
                session.recorder.stop();
            }
        } catch (eRecStop) {
            /* ignore */
        }
        try {
            if (session.rec) {
                session.rec.abort();
            }
        } catch (eAbort) {
            try {
                if (session.rec) {
                    session.rec.stop();
                }
            } catch (eStop) {
                /* ignore */
            }
        }
        crmHubReleaseMediaStream(session.micStream);
        session.micStream = null;
        cogVoiceSession = null;
        crmHubSetMicListening(false);
    }

    function crmHubPickRecorderMime() {
        if (typeof MediaRecorder === 'undefined') {
            return '';
        }
        var candidates = [
            'audio/webm;codecs=opus',
            'audio/webm',
            'audio/mp4',
            'audio/ogg;codecs=opus'
        ];
        var i;
        for (i = 0; i < candidates.length; i++) {
            try {
                if (MediaRecorder.isTypeSupported(candidates[i])) {
                    return candidates[i];
                }
            } catch (eSup) {
                /* ignore */
            }
        }
        return '';
    }

    function crmHubBlobToBase64(blob, done) {
        if (!blob) {
            done(null);
            return;
        }
        var reader = new FileReader();
        reader.onloadend = function () {
            var result = reader.result || '';
            var comma = String(result).indexOf(',');
            done(comma >= 0 ? String(result).substring(comma + 1) : String(result));
        };
        reader.onerror = function () {
            done(null);
        };
        reader.readAsDataURL(blob);
    }

    function crmHubTranscribeRecording(blob, mimeType, onDone) {
        crmHubBlobToBase64(blob, function (b64) {
            if (!b64) {
                onDone({ success: false, error: 'Could not read recording.' });
                return;
            }
            function onRes(res, ev) {
                if (!ev || !ev.status) {
                    onDone({
                        success: false,
                        error: (ev && ev.message) || 'Transcription remoting failed.'
                    });
                    return;
                }
                onDone(res || { success: false, error: 'Empty transcription response.' });
            }
            var hasTyped =
                typeof CrmHubVoiceSearchController !== 'undefined' &&
                typeof CrmHubVoiceSearchController.transcribeHubSpeech === 'function';
            var hasLegacyTyped =
                typeof CrmHubListController !== 'undefined' &&
                typeof CrmHubListController.transcribeHubSpeech === 'function';
            try {
                if (hasTyped) {
                    CrmHubVoiceSearchController.transcribeHubSpeech(
                        b64,
                        mimeType || 'audio/webm',
                        onRes,
                        { escape: false, timeout: 120000, buffer: true }
                    );
                } else if (hasLegacyTyped) {
                    CrmHubListController.transcribeHubSpeech(
                        b64,
                        mimeType || 'audio/webm',
                        onRes,
                        { escape: false, timeout: 120000, buffer: true }
                    );
                } else {
                    crmHubInvokeRemote(
                        'CrmHubVoiceSearchController.transcribeHubSpeech',
                        [b64, mimeType || 'audio/webm'],
                        onRes,
                        { escape: false, timeout: 120000, buffer: true }
                    );
                }
            } catch (eCall) {
                onDone({ success: false, error: (eCall && eCall.message) || 'Transcription call failed.' });
            }
        });
    }

    function crmHubFinishMediaSession(session, submit) {
        if (!session) {
            crmHubVoiceCloseModal();
            return;
        }
        crmHubReleaseMediaStream(session.micStream);
        session.micStream = null;
        cogVoiceSession = null;
        crmHubSetMicListening(false);

        if (!submit) {
            crmHubVoiceCloseModal();
            crmHubSetVoiceStatus('');
            return;
        }

        var blob = session.blob;
        if (!blob || !blob.size) {
            crmHubVoiceCloseModal();
            crmHubSetVoiceStatus('Nothing captured. Tap the mic and try again.');
            return;
        }

        crmHubVoiceSetHint('Transcribing…');
        crmHubVoiceSetTranscript('', { emptyMsg: 'Transcribing your search…' });
        crmHubTranscribeRecording(blob, session.mimeType || blob.type || 'audio/webm', function (res) {
            if (!res || res.success === false) {
                crmHubVoiceOpenModal();
                crmHubVoiceShowBlocked('stt');
                crmHubVoiceSetHint(
                    ((res && res.error) || 'Could not transcribe.') + ' Tap Try again, or Continue typing.'
                );
                return;
            }
            var text = (res.transcript || '').trim();
            if (!text) {
                crmHubVoiceCloseModal();
                crmHubSetVoiceStatus('Nothing captured. Tap the mic and try again.');
                return;
            }
            crmHubApplyTranscriptAndSearch(text);
        });
    }

    /**
     * Record with MediaRecorder (mic works), then ElevenLabs Scribe via Apex.
     * Avoids Chrome Web Speech "network" failures inside Salesforce.
     */
    function crmHubBeginMediaRecorderListen(micStream) {
        var mime = crmHubPickRecorderMime();
        if (!mime || typeof MediaRecorder === 'undefined') {
            crmHubReleaseMediaStream(micStream);
            crmHubVoiceShowBlocked('unsupported');
            return false;
        }

        var recorder;
        try {
            recorder = new MediaRecorder(micStream, { mimeType: mime });
        } catch (eRec) {
            try {
                recorder = new MediaRecorder(micStream);
                mime = recorder.mimeType || mime;
            } catch (eRec2) {
                crmHubReleaseMediaStream(micStream);
                crmHubVoiceShowBlocked('audio-capture');
                return false;
            }
        }

        var session = {
            mode: 'media',
            recorder: recorder,
            micStream: micStream,
            chunks: [],
            mimeType: mime,
            wantListen: true,
            blob: null,
            restartTimer: null,
            rec: null
        };
        cogVoiceSession = session;

        recorder.ondataavailable = function (ev) {
            if (ev && ev.data && ev.data.size > 0) {
                session.chunks.push(ev.data);
            }
        };
        recorder.onerror = function () {
            session.wantListen = false;
            crmHubReleaseMediaStream(session.micStream);
            session.micStream = null;
            cogVoiceSession = null;
            crmHubVoiceShowBlocked('audio-capture');
        };

        crmHubSetMicListening(true);
        crmHubVoiceSetRecoveryActions(false);
        crmHubVoiceSetHint('Speak your search, then tap I’m done speaking… search.');
        crmHubVoiceSetTranscript('', { emptyMsg: 'Listening for speech…' });
        var titleEl = document.getElementById('hub-voice-title');
        if (titleEl) {
            titleEl.textContent = 'Listening';
        }
        var stopBtn = document.getElementById('hub-voice-stop');
        if (stopBtn) {
            stopBtn.hidden = false;
            stopBtn.textContent = 'I’m done speaking… search';
        }
        crmHubPlayListenCue();

        try {
            recorder.start(250);
            return true;
        } catch (eStart) {
            crmHubReleaseMediaStream(session.micStream);
            session.micStream = null;
            cogVoiceSession = null;
            crmHubVoiceShowBlocked('audio-capture');
            return false;
        }
    }

    function crmHubStartVoiceModalListen() {
        if (typeof MediaRecorder === 'undefined' || !crmHubPickRecorderMime()) {
            crmHubVoiceOpenModal();
            crmHubVoiceShowBlocked('unsupported');
            return false;
        }

        crmHubAbortVoiceSessionSoft();
        crmHubVoiceOpenModal();
        crmHubVoiceSetHint('Requesting microphone…');
        crmHubVoiceSetTranscript('', { emptyMsg: 'Preparing mic…' });

        crmHubRequestMicPermission(function (perm) {
            if (!perm.ok) {
                crmHubReleaseMediaStream(perm.stream);
                if (crmHubIsFramed()) {
                    if (crmHubOpenVoicePopupBridge()) {
                        return;
                    }
                }
                crmHubVoiceShowBlocked(perm.code || 'not-allowed');
                return;
            }
            crmHubBeginMediaRecorderListen(perm.stream || null);
        });
        return true;
    }

    function crmHubVoiceBindModalControls() {
        var stopBtn = document.getElementById('hub-voice-stop');
        var cancelBtn = document.getElementById('hub-voice-cancel');
        var retryBtn = document.getElementById('hub-voice-retry');
        var overlay = document.getElementById('hub-voice-overlay');
        if (stopBtn && !stopBtn.getAttribute('data-bound')) {
            stopBtn.setAttribute('data-bound', '1');
            stopBtn.addEventListener('click', function (ev) {
                if (ev && ev.preventDefault) {
                    ev.preventDefault();
                }
                if (hubBriefingSpeaking) {
                    crmHubStopBriefingSpeaking(true);
                    return;
                }
                crmHubVoiceStopSession(true);
            });
        }
        if (cancelBtn && !cancelBtn.getAttribute('data-bound')) {
            cancelBtn.setAttribute('data-bound', '1');
            cancelBtn.addEventListener('click', function (ev) {
                if (ev && ev.preventDefault) {
                    ev.preventDefault();
                }
                if (hubBriefingSpeaking) {
                    crmHubStopBriefingSpeaking(true);
                    return;
                }
                crmHubVoiceStopSession(false);
                crmHubVoiceFocusSearch();
            });
        }
        if (retryBtn && !retryBtn.getAttribute('data-bound')) {
            retryBtn.setAttribute('data-bound', '1');
            retryBtn.addEventListener('click', function (ev) {
                if (ev && ev.preventDefault) {
                    ev.preventDefault();
                }
                /* Re-run MediaRecorder capture under this click gesture. */
                crmHubStartVoiceModalListen();
            });
        }
        if (overlay && !overlay.getAttribute('data-bound')) {
            overlay.setAttribute('data-bound', '1');
            overlay.addEventListener('click', function (ev) {
                if (ev.target === overlay) {
                    if (hubBriefingSpeaking) {
                        crmHubStopBriefingSpeaking(true);
                        return;
                    }
                    crmHubVoiceStopSession(false);
                }
            });
        }
    }

    function crmHubVoiceSearch() {
        crmHubStopSpeech();
        crmHubVoiceBindModalControls();
        crmHubBindVoicePopupMessages();
        if (
            (cogVoiceSession && cogVoiceSession.wantListen) ||
            (hubVoicePopupRef && !hubVoicePopupRef.closed)
        ) {
            crmHubVoiceStopSession(true);
            return;
        }
        /* MediaRecorder + server STT works on top-level VF; popup only if mic denied while framed. */
        crmHubStartVoiceModalListen();
    }

    /* ---- Hub Briefing ---- */

    function crmHubPad2(n) {
        return (n < 10 ? '0' : '') + n;
    }

    function crmHubDateToIso(d) {
        return d.getFullYear() + '-' + crmHubPad2(d.getMonth() + 1) + '-' + crmHubPad2(d.getDate());
    }

    function crmHubParseIsoDate(iso) {
        if (!iso) {
            return null;
        }
        var parts = String(iso).split('-');
        if (parts.length !== 3) {
            return null;
        }
        return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    }

    function crmHubFormatSpeakDate(iso) {
        var d = crmHubParseIsoDate(iso);
        if (!d || isNaN(d.getTime())) {
            return iso || '';
        }
        try {
            return d.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
        } catch (eFmt) {
            return iso;
        }
    }

    function crmHubGreetingForNow() {
        var h = new Date().getHours();
        if (h < 12) {
            return 'Good morning';
        }
        if (h < 17) {
            return 'Good afternoon';
        }
        return 'Good evening';
    }

    function crmHubBriefingAllowedObjectTabs() {
        var out = [];
        var i;
        for (i = 0; i < HUB_BRIEFING_TAB_META.length; i++) {
            var tab = HUB_BRIEFING_TAB_META[i];
            if (hubTabAllowed(tab.id)) {
                out.push(tab);
            }
        }
        return out;
    }

    function crmHubSetBriefingStatus(msg, isError) {
        var el = document.getElementById('hub-briefing-status');
        if (!el) {
            return;
        }
        el.textContent = msg || '';
        if (isError) {
            el.classList.add('is-error');
        } else {
            el.classList.remove('is-error');
        }
    }

    function crmHubSetVoiceOverlaySpeaking(on) {
        var overlay = document.getElementById('hub-voice-overlay');
        if (!overlay) {
            return;
        }
        if (on) {
            overlay.classList.add('is-speaking');
        } else {
            overlay.classList.remove('is-speaking');
        }
    }

    function crmHubApplyBriefingDateRange(kind) {
        var today = new Date();
        today.setHours(0, 0, 0, 0);
        var from = new Date(today.getTime());
        var to = new Date(today.getTime());
        if (kind === 'today') {
            /* same day */
        } else if (kind === 'month') {
            from = new Date(today.getFullYear(), today.getMonth(), 1);
        } else {
            from = new Date(today.getTime());
            from.setDate(from.getDate() - 6);
        }
        var fromEl = document.getElementById('hub-briefing-from');
        var toEl = document.getElementById('hub-briefing-to');
        if (fromEl) {
            fromEl.value = crmHubDateToIso(from);
        }
        if (toEl) {
            toEl.value = crmHubDateToIso(to);
        }
        var chips = document.querySelectorAll('#hub-briefing-range-presets .hub-briefing-chip');
        var i;
        for (i = 0; i < chips.length; i++) {
            if (chips[i].getAttribute('data-range') === kind) {
                chips[i].classList.add('is-on');
            } else {
                chips[i].classList.remove('is-on');
            }
        }
    }

    function crmHubSelectAllBriefingTabs() {
        var allowed = crmHubBriefingAllowedObjectTabs();
        hubBriefingSelectedTabs = [];
        var i;
        for (i = 0; i < allowed.length; i++) {
            hubBriefingSelectedTabs.push(allowed[i].id);
        }
        crmHubSyncBriefingTabChips();
    }

    function crmHubSyncBriefingTabChips() {
        var wrap = document.getElementById('hub-briefing-tabs');
        if (!wrap) {
            return;
        }
        var chips = wrap.querySelectorAll('.hub-briefing-chip');
        var i;
        for (i = 0; i < chips.length; i++) {
            var id = chips[i].getAttribute('data-tab');
            if (hubBriefingSelectedTabs.indexOf(id) >= 0) {
                chips[i].classList.add('is-on');
            } else {
                chips[i].classList.remove('is-on');
            }
        }
    }

    function crmHubSyncBriefingPresetChips() {
        var chips = document.querySelectorAll('#hub-briefing-presets .hub-briefing-chip');
        var i;
        for (i = 0; i < chips.length; i++) {
            if (chips[i].getAttribute('data-preset') === hubBriefingPreset) {
                chips[i].classList.add('is-on');
            } else {
                chips[i].classList.remove('is-on');
            }
        }
    }

    function crmHubSyncBriefingAudienceChips() {
        var chips = document.querySelectorAll('#hub-briefing-audience .hub-briefing-chip');
        var i;
        for (i = 0; i < chips.length; i++) {
            if (chips[i].getAttribute('data-audience') === hubBriefingAudience) {
                chips[i].classList.add('is-on');
            } else {
                chips[i].classList.remove('is-on');
            }
        }
    }

    function crmHubRenderBriefingAudience() {
        var wrap = document.getElementById('hub-briefing-audience');
        if (!wrap) {
            return;
        }
        var chips = wrap.querySelectorAll('.hub-briefing-chip');
        var i;
        for (i = 0; i < chips.length; i++) {
            var needsFull = chips[i].getAttribute('data-requires-full') === '1';
            if (needsFull && hubIsPartialAccess()) {
                chips[i].hidden = true;
                chips[i].disabled = true;
                chips[i].classList.remove('is-on');
            } else {
                chips[i].hidden = false;
                chips[i].disabled = false;
            }
        }
        if (hubBriefingAudience === 'hr' && hubIsPartialAccess()) {
            hubBriefingAudience = 'sales';
        }
        crmHubSyncBriefingAudienceChips();
    }

    function crmHubRenderBriefingTabs() {
        var wrap = document.getElementById('hub-briefing-tabs');
        if (!wrap) {
            return;
        }
        var allowed = crmHubBriefingAllowedObjectTabs();
        var html = [];
        var i;
        for (i = 0; i < allowed.length; i++) {
            html.push(
                '<button type="button" class="hub-briefing-chip" data-tab="' +
                    allowed[i].id +
                    '">' +
                    allowed[i].label +
                    '</button>'
            );
        }
        wrap.innerHTML = html.join('');
        if (!hubBriefingSelectedTabs.length) {
            crmHubSelectAllBriefingTabs();
        } else {
            var filtered = [];
            for (i = 0; i < hubBriefingSelectedTabs.length; i++) {
                if (hubTabAllowed(hubBriefingSelectedTabs[i])) {
                    filtered.push(hubBriefingSelectedTabs[i]);
                }
            }
            hubBriefingSelectedTabs = filtered.length ? filtered : [];
            if (!hubBriefingSelectedTabs.length) {
                crmHubSelectAllBriefingTabs();
            } else {
                crmHubSyncBriefingTabChips();
            }
        }
        if (!wrap.getAttribute('data-bound')) {
            wrap.setAttribute('data-bound', '1');
            wrap.addEventListener('click', function (ev) {
                var btn = ev.target && ev.target.closest ? ev.target.closest('.hub-briefing-chip') : null;
                if (!btn || !wrap.contains(btn)) {
                    return;
                }
                var tabId = btn.getAttribute('data-tab');
                if (!tabId) {
                    return;
                }
                var idx = hubBriefingSelectedTabs.indexOf(tabId);
                if (idx >= 0) {
                    if (hubBriefingSelectedTabs.length === 1) {
                        return;
                    }
                    hubBriefingSelectedTabs.splice(idx, 1);
                } else {
                    hubBriefingSelectedTabs.push(tabId);
                }
                if (hubBriefingPreset === 'everything') {
                    hubBriefingPreset = 'headlines';
                    crmHubSyncBriefingPresetChips();
                }
                crmHubSyncBriefingTabChips();
            });
        }
    }

    function crmHubBindBriefingControls() {
        var presets = document.getElementById('hub-briefing-presets');
        if (presets && !presets.getAttribute('data-bound')) {
            presets.setAttribute('data-bound', '1');
            presets.addEventListener('click', function (ev) {
                var btn = ev.target && ev.target.closest ? ev.target.closest('.hub-briefing-chip') : null;
                if (!btn || !presets.contains(btn)) {
                    return;
                }
                var preset = btn.getAttribute('data-preset');
                if (!preset) {
                    return;
                }
                hubBriefingPreset = preset;
                crmHubSyncBriefingPresetChips();
                if (preset === 'everything' || preset === 'actToday') {
                    crmHubSelectAllBriefingTabs();
                }
            });
        }
        var audienceWrap = document.getElementById('hub-briefing-audience');
        if (audienceWrap && !audienceWrap.getAttribute('data-bound')) {
            audienceWrap.setAttribute('data-bound', '1');
            audienceWrap.addEventListener('click', function (ev) {
                var btn = ev.target && ev.target.closest ? ev.target.closest('.hub-briefing-chip') : null;
                if (!btn || !audienceWrap.contains(btn) || btn.disabled || btn.hidden) {
                    return;
                }
                var audience = btn.getAttribute('data-audience');
                if (!audience) {
                    return;
                }
                if (audience === 'hr' && hubIsPartialAccess()) {
                    return;
                }
                hubBriefingAudience = audience;
                crmHubSyncBriefingAudienceChips();
            });
        }
        var ranges = document.getElementById('hub-briefing-range-presets');
        if (ranges && !ranges.getAttribute('data-bound')) {
            ranges.setAttribute('data-bound', '1');
            ranges.addEventListener('click', function (ev) {
                var btn = ev.target && ev.target.closest ? ev.target.closest('.hub-briefing-chip') : null;
                if (!btn || !ranges.contains(btn)) {
                    return;
                }
                crmHubApplyBriefingDateRange(btn.getAttribute('data-range') || '7d');
            });
        }
        var fromEl = document.getElementById('hub-briefing-from');
        var toEl = document.getElementById('hub-briefing-to');
        function clearRangeChips() {
            var chips = document.querySelectorAll('#hub-briefing-range-presets .hub-briefing-chip');
            var i;
            for (i = 0; i < chips.length; i++) {
                chips[i].classList.remove('is-on');
            }
        }
        if (fromEl && !fromEl.getAttribute('data-bound')) {
            fromEl.setAttribute('data-bound', '1');
            fromEl.addEventListener('change', clearRangeChips);
        }
        if (toEl && !toEl.getAttribute('data-bound')) {
            toEl.setAttribute('data-bound', '1');
            toEl.addEventListener('change', clearRangeChips);
        }
    }

    function crmHubUpdateBriefingCreditUi() {
        var el = document.getElementById('hub-briefing-credit');
        var smartBtn = document.getElementById('hub-briefing-start-smart');
        if (!el) {
            return;
        }
        if (!hubElevenLabsConfigured) {
            el.textContent =
                'Smart voice not configured — standard browser voice is unlimited.';
            el.classList.add('is-used');
            if (smartBtn) {
                smartBtn.disabled = true;
                smartBtn.title = 'ElevenLabs is not configured in this org.';
            }
            return;
        }
        if (hubSmartUsedToday || hubSmartCreditsRemaining <= 0) {
            el.textContent =
                'Smart voice used today — 1 credit/day. Standard voice is unlimited.';
            el.classList.add('is-used');
            if (smartBtn) {
                smartBtn.disabled = true;
                smartBtn.title =
                    '1 Smart Briefing per day. Come back tomorrow, or use standard voice anytime.';
            }
            return;
        }
        el.textContent =
            'Smart voice: ' +
            hubSmartCreditsRemaining +
            ' credit left today (realistic ElevenLabs). Standard voice unlimited.';
        el.classList.remove('is-used');
        if (smartBtn) {
            smartBtn.disabled = false;
            smartBtn.title = '';
        }
    }

    function crmHubRefreshBriefingVoiceStatus(done) {
        function apply(res) {
            if (res && res.success !== false) {
                if (typeof res.elevenLabsConfigured === 'boolean') {
                    hubElevenLabsConfigured = !!res.elevenLabsConfigured;
                }
                if (typeof res.smartCreditsRemaining === 'number') {
                    hubSmartCreditsRemaining = Number(res.smartCreditsRemaining) || 0;
                }
                if (typeof res.smartUsedToday === 'boolean') {
                    hubSmartUsedToday = !!res.smartUsedToday;
                }
            }
            crmHubUpdateBriefingCreditUi();
            if (typeof done === 'function') {
                done();
            }
        }
        var hasTyped =
            typeof CrmHubListController !== 'undefined' &&
            typeof CrmHubListController.getHubBriefingVoiceStatus === 'function';
        try {
            if (hasTyped) {
                CrmHubListController.getHubBriefingVoiceStatus(function (res, ev) {
                    apply(ev && ev.status ? res : null);
                }, { escape: false, timeout: 30000 });
            } else {
                crmHubInvokeRemote(
                    'CrmHubListController.getHubBriefingVoiceStatus',
                    [],
                    function (res, ev) {
                        apply(ev && ev.status ? res : null);
                    },
                    { escape: false, timeout: 30000 }
                );
            }
        } catch (eStatus) {
            crmHubUpdateBriefingCreditUi();
            if (typeof done === 'function') {
                done();
            }
        }
    }

    function crmHubOpenBriefing() {
        crmHubStopSpeech();
        if (cogVoiceSession && cogVoiceSession.wantListen) {
            crmHubVoiceStopSession(false);
        }
        crmHubVoiceCloseModal();
        crmHubBindBriefingControls();
        crmHubRenderBriefingTabs();
        crmHubRenderBriefingAudience();
        hubBriefingPreset = 'everything';
        if (!hubBriefingAudience) {
            hubBriefingAudience = 'sales';
        }
        crmHubSyncBriefingPresetChips();
        crmHubSyncBriefingAudienceChips();
        crmHubSelectAllBriefingTabs();
        crmHubApplyBriefingDateRange('7d');
        crmHubSetBriefingStatus('');
        crmHubRefreshBriefingVoiceStatus();
        var overlay = document.getElementById('hub-briefing-overlay');
        if (!overlay) {
            return;
        }
        overlay.classList.add('is-open');
        overlay.setAttribute('aria-hidden', 'false');
    }

    function crmHubCloseBriefingSetup(ev) {
        if (ev && ev.target && ev.currentTarget && ev.target !== ev.currentTarget) {
            return;
        }
        var overlay = document.getElementById('hub-briefing-overlay');
        if (!overlay) {
            return;
        }
        overlay.classList.remove('is-open');
        overlay.setAttribute('aria-hidden', 'true');
        crmHubSetBriefingStatus('');
        var startBtn = document.getElementById('hub-briefing-start');
        var smartBtn = document.getElementById('hub-briefing-start-smart');
        if (startBtn) {
            startBtn.disabled = false;
        }
        if (smartBtn) {
            smartBtn.disabled = false;
        }
        crmHubUpdateBriefingCreditUi();
    }

    function crmHubStopBriefingSpeaking(closeModal) {
        hubBriefingSpeaking = false;
        crmHubStopSpeech();
        crmHubSetVoiceOverlaySpeaking(false);
        if (closeModal) {
            crmHubVoiceCloseModal();
        }
        crmHubSetVoiceStatus('');
    }

    function crmHubOpenBriefingSpeakModal(scriptText) {
        crmHubVoiceBindModalControls();
        var overlay = document.getElementById('hub-voice-overlay');
        if (!overlay) {
            return;
        }
        overlay.classList.remove('is-listening');
        overlay.classList.add('is-open');
        overlay.classList.add('is-speaking');
        overlay.setAttribute('aria-hidden', 'false');
        var title = document.getElementById('hub-voice-title');
        if (title) {
            title.textContent = 'Your briefing';
        }
        crmHubVoiceSetRecoveryActions(false);
        crmHubVoiceSetHint('I’m reading your Hub briefing…');
        crmHubVoiceSetTranscript(scriptText || '', { emptyMsg: 'Preparing briefing…' });
        var stopBtn = document.getElementById('hub-voice-stop');
        if (stopBtn) {
            stopBtn.hidden = false;
            stopBtn.textContent = 'Stop speaking';
        }
        var cancelBtn = document.getElementById('hub-voice-cancel');
        if (cancelBtn) {
            cancelBtn.hidden = false;
        }
    }

    function crmHubJoinPersonCounts(rows, noun) {
        if (!rows || !rows.length) {
            return '';
        }
        var parts = [];
        var i;
        for (i = 0; i < rows.length; i++) {
            var n = Number(rows[i].count) || 0;
            var name = rows[i].name || 'someone';
            parts.push(n + ' ' + (noun || 'by') + ' ' + name);
        }
        if (parts.length === 1) {
            return parts[0];
        }
        if (parts.length === 2) {
            return parts[0] + ', and ' + parts[1];
        }
        return parts.slice(0, -1).join(', ') + ', and ' + parts[parts.length - 1];
    }

    function crmHubJoinNames(items, key) {
        key = key || 'name';
        if (!items || !items.length) {
            return '';
        }
        var names = [];
        var i;
        for (i = 0; i < items.length; i++) {
            if (items[i] && items[i][key]) {
                names.push(items[i][key]);
            }
        }
        if (!names.length) {
            return '';
        }
        if (names.length === 1) {
            return names[0];
        }
        if (names.length === 2) {
            return names[0] + ' and ' + names[1];
        }
        return names.slice(0, -1).join(', ') + ', and ' + names[names.length - 1];
    }

    function crmHubFormatMoney(amount) {
        var n = Number(amount);
        if (!isFinite(n) || n === 0) {
            return '';
        }
        try {
            return new Intl.NumberFormat('en-US', {
                style: 'currency',
                currency: 'USD',
                maximumFractionDigits: 0
            }).format(n);
        } catch (eFmt) {
            return '$' + Math.round(n);
        }
    }

    function crmHubDescribeRecordBrief(item) {
        if (!item || !item.name) {
            return '';
        }
        var bits = [item.name];
        if (item.account) {
            bits.push('at ' + item.account);
        }
        if (item.company) {
            bits.push('at ' + item.company);
        }
        if (item.title) {
            bits.push(item.title);
        }
        var money = crmHubFormatMoney(item.amount);
        if (money) {
            bits.push(money);
        }
        if (item.stage) {
            bits.push('in ' + item.stage);
        }
        if (item.status) {
            bits.push(item.status);
        }
        if (item.primaryAe) {
            bits.push('owned by ' + item.primaryAe);
        }
        if (item.nextStep) {
            bits.push('next step ' + item.nextStep);
        }
        return bits.join(', ');
    }

    function crmHubDescribeDeal(item) {
        return crmHubDescribeRecordBrief(item);
    }

    function crmHubNamedSampleList(items, maxN) {
        if (!items || !items.length) {
            return '';
        }
        var names = [];
        var i;
        for (i = 0; i < items.length && names.length < maxN; i++) {
            var bit = crmHubDescribeRecordBrief(items[i]);
            if (bit) {
                names.push(bit);
            }
        }
        return names.length ? names.join('; ') : '';
    }

    /**
     * Prefer Apex digestText (on-screen / standard) or scriptText (smart).
     * Falls back to local rebuild only when Apex texts are missing.
     */
    function crmHubBuildBriefingScript(payload, preset, opts) {
        opts = opts || {};
        var concise = !!opts.concise;
        if (payload) {
            if (concise && payload.scriptText) {
                return String(payload.scriptText).replace(/\s+/g, ' ').trim();
            }
            if (!concise && payload.digestText) {
                return String(payload.digestText).replace(/\s+/g, ' ').trim();
            }
            if (payload.digestText) {
                return String(payload.digestText).replace(/\s+/g, ' ').trim();
            }
            if (payload.scriptText) {
                return String(payload.scriptText).replace(/\s+/g, ' ').trim();
            }
        }

        var objects = (payload && payload.objects) || [];
        var actions = (payload && payload.actions) || {};
        var insights = (payload && payload.insights) || {};
        var lines = [];
        var hasFacts = false;
        var o;
        var maxNames = concise ? 2 : 4;
        var maxLen = concise ? 500 : 1600;

        function pushFact(line) {
            if (!line) {
                return;
            }
            lines.push(line);
            hasFacts = true;
        }

        if (!concise) {
            lines.push(crmHubBuildTimeGreeting());
            lines.push('Here is your CRM Hub briefing.');
        }

        if (preset !== 'actToday') {
            for (o = 0; o < objects.length; o++) {
                var row = objects[o] || {};
                var label = row.label || row.api || 'records';
                var createdTotal = Number(row.createdTotal) || 0;
                var modifiedTotal = Number(row.modifiedTotal) || 0;
                if (preset !== 'moved' && createdTotal > 0) {
                    pushFact(createdTotal + ' new ' + label + '.');
                    var createdBits = crmHubNamedSampleList(row.highlights, maxNames);
                    if (createdBits) {
                        pushFact('Highlights include ' + createdBits + '.');
                    }
                }
                if (preset !== 'headlines' && modifiedTotal > 0) {
                    pushFact(modifiedTotal + ' updated ' + label + '.');
                    var modSrc = row.recentModified && row.recentModified.length
                        ? row.recentModified
                        : row.highlights;
                    var modBits = crmHubNamedSampleList(modSrc, maxNames);
                    if (modBits) {
                        pushFact('Notable updates: ' + modBits + '.');
                    }
                }
            }
            var pipeMoney = crmHubFormatMoney(insights.pipelineAmount);
            if (pipeMoney) {
                pushFact(
                    concise
                        ? 'Touched pipeline about ' + pipeMoney + '.'
                        : 'Touched pipeline in this window is about ' + pipeMoney + '.'
                );
            }
            if (!concise) {
                var stages = insights.opportunityStages || [];
                if (stages.length) {
                    var stageBits = [];
                    var si;
                    for (si = 0; si < stages.length && stageBits.length < 4; si++) {
                        stageBits.push(
                            (stages[si].count || 0) + ' in ' + (stages[si].name || 'Unknown')
                        );
                    }
                    if (stageBits.length) {
                        pushFact('Stage mix: ' + stageBits.join(', ') + '.');
                    }
                }
                var topDeals = crmHubNamedSampleList(insights.topDeals, 3);
                if (topDeals) {
                    pushFact('Top open deals: ' + topDeals + '.');
                }
                var closingWeek = crmHubNamedSampleList(insights.closingThisWeek, 3);
                if (closingWeek) {
                    pushFact('Closing this week: ' + closingWeek + '.');
                }
            }
        }
        if (preset === 'everything' || preset === 'actToday') {
            var overdueCount = Number(actions.overdueTaskCount) || (actions.overdueTasks || []).length;
            var dueTodayCount = Number(actions.dueTodayTaskCount) || (actions.dueTodayTasks || []).length;
            if (overdueCount) {
                var overdueBits = crmHubNamedSampleList(actions.overdueTasks, maxNames);
                pushFact(
                    overdueCount +
                        ' overdue task' +
                        (overdueCount === 1 ? '' : 's') +
                        (overdueBits ? ': ' + overdueBits : '') +
                        '.'
                );
            }
            if (dueTodayCount) {
                var dueBits = crmHubNamedSampleList(actions.dueTodayTasks, maxNames);
                pushFact(
                    dueTodayCount +
                        ' task' +
                        (dueTodayCount === 1 ? '' : 's') +
                        ' due today' +
                        (dueBits ? ': ' + dueBits : '') +
                        '.'
                );
            }
            var events = actions.eventsToday || [];
            if (events.length) {
                var eventBits = crmHubNamedSampleList(events, maxNames);
                pushFact(
                    events.length +
                        ' meeting' +
                        (events.length === 1 ? '' : 's') +
                        ' today' +
                        (eventBits ? ': ' + eventBits : '') +
                        '.'
                );
            }
            var closing = actions.oppsClosingToday || [];
            if (closing.length) {
                pushFact(
                    'Closing today: ' +
                        closing
                            .slice(0, concise ? 2 : 4)
                            .map(crmHubDescribeDeal)
                            .filter(Boolean)
                            .join('; ') +
                        '.'
                );
            }
            if (!concise) {
                var stale = crmHubNamedSampleList(actions.staleOpps, 3);
                if (stale) {
                    pushFact('Stale deals needing attention: ' + stale + '.');
                }
            }
        }
        if (!hasFacts) {
            var quiet =
                'Quiet window — no material CRM movement on the selected tabs.';
            return concise ? quiet : crmHubBuildTimeGreeting() + ' ' + quiet;
        }
        var joined = lines.join(' ').replace(/\s+/g, ' ').trim();
        if (joined.length > maxLen) {
            joined = joined.slice(0, maxLen);
            var cut = Math.max(joined.lastIndexOf('.'), joined.lastIndexOf(' '));
            if (cut > 120) {
                joined = joined.slice(0, cut + (joined.charAt(cut) === '.' ? 1 : 0)).trim();
            }
        }
        return joined;
    }

    function crmHubStartBriefing(useSmart) {
        var wantSmart = !!useSmart;
        var fromEl = document.getElementById('hub-briefing-from');
        var toEl = document.getElementById('hub-briefing-to');
        var startIso = fromEl ? fromEl.value : '';
        var endIso = toEl ? toEl.value : '';
        if (!startIso || !endIso) {
            crmHubSetBriefingStatus('Pick a from and to date.', true);
            return;
        }
        if (endIso < startIso) {
            crmHubSetBriefingStatus('End date must be on or after the start date.', true);
            return;
        }
        if (!hubBriefingSelectedTabs.length) {
            crmHubSetBriefingStatus('Pick at least one tab to brief on.', true);
            return;
        }
        if (wantSmart && (hubSmartUsedToday || hubSmartCreditsRemaining <= 0)) {
            crmHubSetBriefingStatus(
                '1 Smart Briefing per day. Come back tomorrow, or use standard voice anytime.',
                true
            );
            return;
        }

        var startBtn = document.getElementById('hub-briefing-start');
        var smartBtn = document.getElementById('hub-briefing-start-smart');
        if (startBtn) {
            startBtn.disabled = true;
        }
        if (smartBtn) {
            smartBtn.disabled = true;
        }
        crmHubSetBriefingStatus(
            wantSmart ? 'Gathering Smart Briefing…' : 'Gathering standard briefing…'
        );

        var tabsJson = JSON.stringify(hubBriefingSelectedTabs);
        var preset = hubBriefingPreset || 'everything';
        var audience = hubBriefingAudience || 'sales';

        function onBriefingResult(res, ev) {
            if (startBtn) {
                startBtn.disabled = false;
            }
            crmHubUpdateBriefingCreditUi();
            if (!ev || !ev.status) {
                crmHubSetBriefingStatus(
                    (ev && ev.message) || 'Could not load briefing. Try again.',
                    true
                );
                return;
            }
            if (!res || res.success === false) {
                crmHubSetBriefingStatus((res && res.error) || 'Could not load briefing.', true);
                return;
            }
            if (typeof res.smartCreditsRemaining === 'number') {
                hubSmartCreditsRemaining = Number(res.smartCreditsRemaining) || 0;
            }
            if (typeof res.smartUsedToday === 'boolean') {
                hubSmartUsedToday = !!res.smartUsedToday;
            }
            if (typeof res.elevenLabsConfigured === 'boolean') {
                hubElevenLabsConfigured = !!res.elevenLabsConfigured;
            }
            var scriptText = crmHubBuildBriefingScript(res, preset, {
                concise: wantSmart,
                detailed: !wantSmart
            });
            crmHubCloseBriefingSetup();
            hubBriefingSpeaking = true;
            crmHubOpenBriefingSpeakModal(scriptText);
            crmHubSetVoiceStatus(
                wantSmart ? 'Reading Smart Briefing…' : 'Reading briefing (standard voice)…'
            );
            crmHubSpeakText(
                scriptText,
                function () {
                    hubBriefingSpeaking = false;
                    crmHubSetVoiceOverlaySpeaking(false);
                    crmHubVoiceCloseModal();
                    crmHubSetVoiceStatus('');
                    crmHubRefreshBriefingVoiceStatus();
                },
                { useSmart: wantSmart }
            );
        }

        var remote = global.CRM_HUB_REMOTE || {};
        var hasTyped =
            typeof CrmHubListController !== 'undefined' &&
            typeof CrmHubListController.fetchHubBriefing === 'function';
        var hasStub = !!remote.fetchHubBriefing;
        var hasRemoting =
            typeof Visualforce !== 'undefined' &&
            Visualforce.remoting &&
            Visualforce.remoting.Manager &&
            typeof Visualforce.remoting.Manager.invokeAction === 'function';

        if (!hasTyped && !hasStub && !hasRemoting) {
            if (startBtn) {
                startBtn.disabled = false;
            }
            crmHubUpdateBriefingCreditUi();
            crmHubSetBriefingStatus(
                'Briefing needs a deploy of CrmHubListController. Refresh after deploy.',
                true
            );
            return;
        }

        try {
            if (hasTyped) {
                CrmHubListController.fetchHubBriefing(
                    startIso,
                    endIso,
                    tabsJson,
                    preset,
                    audience,
                    onBriefingResult,
                    { escape: false, timeout: 120000 }
                );
            } else {
                crmHubInvokeRemote(
                    'CrmHubListController.fetchHubBriefing',
                    [startIso, endIso, tabsJson, preset, audience],
                    onBriefingResult,
                    { escape: false, timeout: 120000 }
                );
            }
        } catch (eStart) {
            if (startBtn) {
                startBtn.disabled = false;
            }
            crmHubUpdateBriefingCreditUi();
            crmHubSetBriefingStatus(
                (eStart && eStart.message) || 'Could not start briefing.',
                true
            );
        }
    }

    /* ---- Bottom nav overflow (More) ---- */
    function crmHubGetTabButtons() {
        var inner = document.getElementById('hub-tabbar-inner');
        if (!inner) {
            return [];
        }
        var nodes = inner.querySelectorAll('.hub-tab-btn[data-tab]');
        var out = [];
        var i;
        for (i = 0; i < nodes.length; i++) {
            var btn = nodes[i];
            if (btn.getAttribute('aria-hidden') === 'true') {
                continue;
            }
            if (btn.style.display === 'none') {
                continue;
            }
            out.push(btn);
        }
        return out;
    }

    function crmHubCloseTabOverflow() {
        var menu = document.getElementById('hub-tab-overflow');
        var more = document.getElementById('hub-tab-more');
        if (menu) {
            menu.classList.remove('is-open');
            menu.hidden = true;
        }
        if (more) {
            more.setAttribute('aria-expanded', 'false');
        }
    }

    function crmHubToggleTabOverflow(forceOpen) {
        var menu = document.getElementById('hub-tab-overflow');
        var more = document.getElementById('hub-tab-more');
        if (!menu || !more) {
            return;
        }
        var open = typeof forceOpen === 'boolean' ? forceOpen : !menu.classList.contains('is-open');
        if (open) {
            menu.hidden = false;
            /* force reflow so transition runs */
            void menu.offsetWidth;
            menu.classList.add('is-open');
            more.setAttribute('aria-expanded', 'true');
        } else {
            crmHubCloseTabOverflow();
        }
    }

    function crmHubBuildOverflowMenu(overflowBtns, activeTab) {
        var menu = document.getElementById('hub-tab-overflow');
        if (!menu) {
            return;
        }
        menu.innerHTML = '';
        var i;
        for (i = 0; i < overflowBtns.length; i++) {
            var src = overflowBtns[i];
            var tabId = src.getAttribute('data-tab');
            var labelEl = src.querySelector('.hub-tab-lbl');
            var icoEl = src.querySelector('.hub-tab-ico');
            var item = document.createElement('button');
            item.type = 'button';
            item.className = 'hub-tab-overflow-item' + (tabId === activeTab ? ' is-active' : '');
            item.setAttribute('role', 'menuitem');
            item.setAttribute('data-tab', tabId);
            var lbl = document.createElement('span');
            lbl.className = 'hub-tab-overflow-lbl';
            lbl.textContent = labelEl ? labelEl.textContent : tabId;
            var ico = document.createElement('span');
            ico.className = 'hub-tab-overflow-ico';
            ico.setAttribute('aria-hidden', 'true');
            if (icoEl) {
                ico.innerHTML = icoEl.innerHTML;
            }
            item.appendChild(lbl);
            item.appendChild(ico);
            item.addEventListener('click', function (ev) {
                var id = (ev.currentTarget && ev.currentTarget.getAttribute('data-tab')) || '';
                crmHubCloseTabOverflow();
                if (id) {
                    crmHubTab(id);
                }
            });
            menu.appendChild(item);
        }
    }

    function crmHubLayoutTabOverflow() {
        var inner = document.getElementById('hub-tabbar-inner');
        var moreWrap = document.getElementById('hub-tab-more-wrap');
        var moreBtn = document.getElementById('hub-tab-more');
        if (!inner || !moreWrap || !moreBtn) {
            return;
        }

        /* Reset so we can measure natural fit */
        inner.classList.remove('is-overflow');
        var allBtns = inner.querySelectorAll('.hub-tab-btn[data-tab]');
        var ai;
        for (ai = 0; ai < allBtns.length; ai++) {
            allBtns[ai].classList.remove('hub-tab-in-overflow');
        }
        moreBtn.classList.remove('is-active');
        crmHubCloseTabOverflow();

        var eligible = crmHubGetTabButtons();
        if (eligible.length <= HUB_TAB_VISIBLE_SLOTS - 1) {
            return;
        }

        var gap = 4;
        var width = inner.clientWidth || 0;
        if (!width) {
            return;
        }
        var need = eligible.length * HUB_TAB_MIN_WIDTH + (eligible.length - 1) * gap;
        if (need <= width) {
            return;
        }

        inner.classList.add('is-overflow');
        var primaryCount = HUB_TAB_VISIBLE_SLOTS - 1;
        var activeBtn = null;
        var i;
        for (i = 0; i < eligible.length; i++) {
            if (eligible[i].classList.contains('is-active')) {
                activeBtn = eligible[i];
                break;
            }
        }
        var primarySet = {};
        var primaryList = [];
        if (activeBtn) {
            primarySet[activeBtn.getAttribute('data-tab')] = true;
            primaryList.push(activeBtn);
        }
        for (i = 0; i < eligible.length && primaryList.length < primaryCount; i++) {
            var tab = eligible[i];
            var id = tab.getAttribute('data-tab');
            if (primarySet[id]) {
                continue;
            }
            primarySet[id] = true;
            primaryList.push(tab);
        }

        var overflowBtns = [];
        var activeTab = activeBtn ? activeBtn.getAttribute('data-tab') : '';
        var activeInOverflow = false;
        for (i = 0; i < eligible.length; i++) {
            var b = eligible[i];
            var bid = b.getAttribute('data-tab');
            if (primarySet[bid]) {
                b.classList.remove('hub-tab-in-overflow');
            } else {
                b.classList.add('hub-tab-in-overflow');
                overflowBtns.push(b);
                if (bid === activeTab) {
                    activeInOverflow = true;
                }
            }
        }

        if (activeInOverflow) {
            moreBtn.classList.add('is-active');
        }
        crmHubBuildOverflowMenu(overflowBtns, activeTab);
    }

    function crmHubBindTabOverflow() {
        var moreBtn = document.getElementById('hub-tab-more');
        if (moreBtn && !moreBtn.getAttribute('data-bound')) {
            moreBtn.setAttribute('data-bound', '1');
            moreBtn.addEventListener('click', function (ev) {
                if (ev && ev.preventDefault) {
                    ev.preventDefault();
                }
                if (ev && ev.stopPropagation) {
                    ev.stopPropagation();
                }
                crmHubToggleTabOverflow();
            });
        }
        if (!document.documentElement.getAttribute('data-hub-tab-overflow-bound')) {
            document.documentElement.setAttribute('data-hub-tab-overflow-bound', '1');
            document.addEventListener('click', function (ev) {
                var wrap = document.getElementById('hub-tab-more-wrap');
                if (!wrap) {
                    return;
                }
                if (wrap.contains(ev.target)) {
                    return;
                }
                crmHubCloseTabOverflow();
            });
        document.addEventListener('keydown', function (ev) {
            if (ev.key === 'Escape' || ev.keyCode === 27) {
                crmHubCloseTabOverflow();
                crmHubCloseSearchResults();
            }
        });
            var resizeTimer = null;
            window.addEventListener('resize', function () {
                if (resizeTimer) {
                    clearTimeout(resizeTimer);
                }
                resizeTimer = setTimeout(crmHubLayoutTabOverflow, 120);
            });
        }
    }

    function crmHubOpenSearchResults(query) {
        var overlay = document.getElementById('hub-search-overlay');
        var qEl = document.getElementById('hub-search-query');
        var modalInput = document.getElementById('hub-search-modal-input');
        if (qEl) {
            qEl.textContent = query ? 'Results for “' + query + '”' : '';
        }
        if (modalInput && query) {
            modalInput.value = query;
        }
        if (overlay) {
            overlay.classList.add('is-open');
            overlay.setAttribute('aria-hidden', 'false');
        }
        hubSearchFocusIndex = -1;
    }

    function crmHubCloseSearchResults(ev) {
        if (ev && ev.target && ev.currentTarget !== ev.target) {
            return;
        }
        var overlay = document.getElementById('hub-search-overlay');
        if (overlay) {
            overlay.classList.remove('is-open');
            overlay.setAttribute('aria-hidden', 'true');
        }
        hubSearchFocusIndex = -1;
    }

    var hubSearchFocusIndex = -1;

    function crmHubNormalizeSearchName(name) {
        return String(name || '')
            .toLowerCase()
            .replace(/[^\w\s]/g, ' ')
            .replace(/\s+/g, ' ')
            .trim();
    }

    function crmHubHighlightQuery(text, query) {
        var raw = String(text == null ? '' : text);
        if (!query || query.length < 2) {
            return crmHubEsc(raw);
        }
        var escText = crmHubEsc(raw);
        var q = crmHubEsc(query);
        try {
            var re = new RegExp('(' + q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'ig');
            return escText.replace(re, '<mark>$1</mark>');
        } catch (e) {
            return escText;
        }
    }

    function crmHubDetectCrossObjectDuplicates(res) {
        var buckets = [
            { key: 'leads', label: 'Lead' },
            { key: 'contacts', label: 'Contact' },
            { key: 'accounts', label: 'Account' },
            { key: 'opportunities', label: 'Opportunity' },
            { key: 'jobApplications', label: 'Job App' },
            { key: 'positions', label: 'Position' },
            { key: 'contracts', label: 'Contract' }
        ];
        var byName = {};
        for (var bi = 0; bi < buckets.length; bi++) {
            var rows = res[buckets[bi].key] || [];
            for (var ri = 0; ri < rows.length; ri++) {
                var nm = crmHubNormalizeSearchName(rows[ri].name);
                if (!nm) {
                    continue;
                }
                if (!byName[nm]) {
                    byName[nm] = [];
                }
                byName[nm].push(buckets[bi].label);
            }
        }
        for (var bi2 = 0; bi2 < buckets.length; bi2++) {
            var rows2 = res[buckets[bi2].key] || [];
            for (var ri2 = 0; ri2 < rows2.length; ri2++) {
                var nm2 = crmHubNormalizeSearchName(rows2[ri2].name);
                var objs = byName[nm2] || [];
                var unique = [];
                for (var ui = 0; ui < objs.length; ui++) {
                    if (unique.indexOf(objs[ui]) < 0) {
                        unique.push(objs[ui]);
                    }
                }
                if (unique.length > 1) {
                    rows2[ri2].possibleDuplicate = true;
                    rows2[ri2].duplicateOf = unique;
                }
            }
        }
    }

    function crmHubSearchSkeletonHtml() {
        return (
            '<div class="hub-search-skeleton" aria-hidden="true">' +
            '<div class="hub-search-skel-row"></div>' +
            '<div class="hub-search-skel-row"></div>' +
            '<div class="hub-search-skel-row"></div>' +
            '<div class="hub-search-skel-row"></div>' +
            '</div>'
        );
    }

    function crmHubSearchObjectIconSvg(kind) {
        var icons = {
            lead: '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
            contact:
                '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
            account:
                '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M9 22v-4h6v4"/><path d="M9 6h1M9 10h1M9 14h1M14 6h1M14 10h1M14 14h1"/>',
            opportunity:
                '<polyline points="23 6 13.5 15.5 8.5 10.5 1 18"/><polyline points="17 6 23 6 23 12"/>',
            jobapp:
                '<rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2"/>',
            position:
                '<path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><rect x="8" y="2" width="8" height="4" rx="1"/><line x1="8" y1="12" x2="16" y2="12"/><line x1="8" y1="16" x2="13" y2="16"/>',
            contract:
                '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="8" y1="13" x2="16" y2="13"/><line x1="8" y1="17" x2="13" y2="17"/>'
        };
        return (
            '<svg viewBox="0 0 24 24" aria-hidden="true">' +
            (icons[kind] || icons.lead) +
            '</svg>'
        );
    }

    function crmHubRenderSearchSection(title, objectLabel, kind, rows, query) {
        if (!rows || !rows.length) {
            return '';
        }
        var chev =
            '<span class="hub-search-card-chev" aria-hidden="true"><svg viewBox="0 0 24 24"><polyline points="9 18 15 12 9 6"/></svg></span>';
        var h =
            '<section class="hub-search-section">' +
            '<div class="hub-search-section-head">' +
            '<span class="hub-search-section-ico hub-search-sec-' +
            crmHubEsc(kind) +
            '">' +
            crmHubSearchObjectIconSvg(kind) +
            '</span>' +
            '<h3 class="hub-search-section-title">' +
            crmHubEsc(title) +
            '</h3><span class="hub-search-count">' +
            rows.length +
            '</span></div><div class="hub-search-cards">';
        for (var i = 0; i < rows.length; i++) {
            var rid = rows[i].id || '';
            var nm = rows[i].name || rows[i].id || '';
            var sub = rows[i].subtitle || '';
            h +=
                '<button type="button" class="hub-search-card ch-open" data-cog-id="' +
                crmHubEsc(rid) +
                '" data-id="' +
                crmHubEsc(rid) +
                '" data-record-name="' +
                crmHubEsc(nm) +
                '" data-object-api="' +
                crmHubEsc(objectLabel) +
                '">' +
                '<span class="hub-search-obj-ico hub-search-obj-' +
                crmHubEsc(kind) +
                '">' +
                crmHubSearchObjectIconSvg(kind) +
                '</span><span class="hub-search-card-main">' +
                '<span class="hub-search-card-top">' +
                '<span class="hub-search-card-name">' +
                crmHubHighlightQuery(nm, query) +
                '</span><span class="hub-search-obj-label">' +
                crmHubEsc(objectLabel) +
                '</span></span>';
            if (sub) {
                h +=
                    '<span class="hub-search-card-sub">' +
                    crmHubHighlightQuery(sub, query) +
                    '</span>';
            }
            if (rows[i].possibleDuplicate) {
                h +=
                    '<span class="hub-search-dup-pill">Possible duplicate · ' +
                    crmHubEsc((rows[i].duplicateOf || []).join(' + ')) +
                    '</span>';
            }
            h += '</span>' + chev + '</button>';
        }
        return h + '</div></section>';
    }

    function crmHubRenderSearchResults(res, query) {
        crmHubDetectCrossObjectDuplicates(res);
        var sections = [
            { title: 'Leads', label: 'Lead', kind: 'lead', rows: res.leads },
            { title: 'Contacts', label: 'Contact', kind: 'contact', rows: res.contacts },
            { title: 'Accounts', label: 'Account', kind: 'account', rows: res.accounts },
            { title: 'Opportunities', label: 'Opportunity', kind: 'opportunity', rows: res.opportunities },
            { title: 'Job Apps', label: 'Job App', kind: 'jobapp', rows: res.jobApplications },
            { title: 'Positions', label: 'Position', kind: 'position', rows: res.positions },
            { title: 'Contracts', label: 'Contract', kind: 'contract', rows: res.contracts }
        ];
        var total = 0;
        var parts = [];
        var summaryBits = [];
        for (var i = 0; i < sections.length; i++) {
            var n = (sections[i].rows || []).length;
            total += n;
            if (n) {
                summaryBits.push(sections[i].title + ' ' + n);
                parts.push(
                    crmHubRenderSearchSection(
                        sections[i].title,
                        sections[i].label,
                        sections[i].kind,
                        sections[i].rows,
                        query
                    )
                );
            }
        }
        var summaryEl = document.getElementById('hub-search-summary');
        if (summaryEl) {
            summaryEl.textContent = total
                ? total + ' result' + (total === 1 ? '' : 's') + (summaryBits.length ? ' · ' + summaryBits.join(' · ') : '')
                : '';
        }
        if (res.message) {
            return '<div class="hub-search-empty"><strong>' + crmHubEsc(res.message) + '</strong></div>';
        }
        if (!parts.length) {
            return (
                '<div class="hub-search-empty"><strong>No matches</strong>Try a different name, email, or company.</div>'
            );
        }
        return parts.join('');
    }

    function crmHubBindSearchInput() {
        var input = document.getElementById('cog-search');
        if (input && !input.getAttribute('data-hub-enter-bound')) {
            input.setAttribute('data-hub-enter-bound', '1');
            input.addEventListener('keydown', function (ev) {
                if (ev.key === 'Enter' || ev.keyCode === 13) {
                    if (ev.preventDefault) {
                        ev.preventDefault();
                    }
                    crmHubRunSearch();
                }
            });
        }
        var modalInput = document.getElementById('hub-search-modal-input');
        if (modalInput && !modalInput.getAttribute('data-hub-enter-bound')) {
            modalInput.setAttribute('data-hub-enter-bound', '1');
            modalInput.addEventListener('keydown', function (ev) {
                if (ev.key === 'Enter' || ev.keyCode === 13) {
                    if (ev.preventDefault) {
                        ev.preventDefault();
                    }
                    var main = document.getElementById('cog-search');
                    if (main) {
                        main.value = modalInput.value;
                    }
                    crmHubRunSearch();
                }
            });
        }
        var modalGo = document.getElementById('hub-search-modal-go');
        if (modalGo && !modalGo.getAttribute('data-hub-bound')) {
            modalGo.setAttribute('data-hub-bound', '1');
            modalGo.addEventListener('click', function () {
                var main = document.getElementById('cog-search');
                var mi = document.getElementById('hub-search-modal-input');
                if (main && mi) {
                    main.value = mi.value;
                }
                crmHubRunSearch();
            });
        }
        var results = document.getElementById('cog-results');
        if (results && !results.getAttribute('data-hub-click-bound')) {
            results.setAttribute('data-hub-click-bound', '1');
            results.addEventListener('click', crmHubCogClick);
            results.addEventListener('keydown', function (ev) {
                var cards = results.querySelectorAll('.hub-search-card');
                if (!cards.length) {
                    return;
                }
                if (ev.key === 'ArrowDown' || ev.keyCode === 40) {
                    ev.preventDefault();
                    hubSearchFocusIndex = Math.min(cards.length - 1, hubSearchFocusIndex + 1);
                } else if (ev.key === 'ArrowUp' || ev.keyCode === 38) {
                    ev.preventDefault();
                    hubSearchFocusIndex = Math.max(0, hubSearchFocusIndex - 1);
                } else if ((ev.key === 'Enter' || ev.keyCode === 13) && hubSearchFocusIndex >= 0) {
                    ev.preventDefault();
                    cards[hubSearchFocusIndex].click();
                    return;
                } else {
                    return;
                }
                for (var i = 0; i < cards.length; i++) {
                    cards[i].classList.toggle('is-focused', i === hubSearchFocusIndex);
                }
                if (hubSearchFocusIndex >= 0 && cards[hubSearchFocusIndex]) {
                    cards[hubSearchFocusIndex].focus();
                }
            });
        }
    }

    function crmHubRunSearch() {
        var q = document.getElementById('cog-search').value;
        var out = document.getElementById('cog-results');
        var speakAfter = cogVoiceFromMic;
        cogVoiceFromMic = false;
        crmHubStopSpeech();
        cogLastSearchRes = null;
        cogLastQuery = (q || '').trim();
        crmHubSetSpeakEnabled(false);
        crmHubOpenSearchResults(cogLastQuery);
        if (out) {
            out.innerHTML = crmHubSearchSkeletonHtml();
        }
        var summaryEl = document.getElementById('hub-search-summary');
        if (summaryEl) {
            summaryEl.textContent = 'Searching…';
        }
        Visualforce.remoting.timeout = 120000;
        CrmHubListController.cognitiveSearch(q, function (res, ev) {
            if (!out) {
                return;
            }
            if (!ev.status) {
                out.textContent = ev.message;
                crmHubSetVoiceStatus('');
                return;
            }
            if (res.error) {
                out.textContent = res.error;
                crmHubSetVoiceStatus('');
                return;
            }
            cogLastSearchRes = res;
            crmHubSetSpeakEnabled(true);
            out.innerHTML = crmHubRenderSearchResults(res, cogLastQuery);
            hubSearchFocusIndex = -1;
            if (speakAfter && !res.message) {
                var summary = crmHubBuildSpeakSummary(cogLastQuery, res);
                crmHubSetVoiceStatus('Reading results…');
                crmHubSpeakText(summary, function () {
                    crmHubSetVoiceStatus('');
                });
            } else if (!speakAfter) {
                crmHubSetVoiceStatus('');
            }
        });
    }

    function lvVal(prefix) {
        var h = crmHubLvHidden(prefix);
        return h ? h.value : '';
    }

    function crmHubResolveListViewId(rows, pinnedId, persistedId, fallbackId, preferredDev) {
        if (!rows || !rows.length) {
            return fallbackId || '';
        }
        if (pinnedId) {
            for (var pi = 0; pi < rows.length; pi++) {
                if (rows[pi].id === pinnedId) {
                    return pinnedId;
                }
            }
        }
        if (persistedId) {
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].id === persistedId) {
                    return persistedId;
                }
            }
        }
        if (preferredDev) {
            var pref = preferredDev.toLowerCase();
            for (var pd = 0; pd < rows.length; pd++) {
                var pdev = (rows[pd].developerName || '').toLowerCase();
                if (pdev === pref) {
                    return rows[pd].id;
                }
            }
        }
        if (fallbackId) {
            for (var j = 0; j < rows.length; j++) {
                if (rows[j].id === fallbackId) {
                    return fallbackId;
                }
            }
        }
        for (var k = 0; k < rows.length; k++) {
            var lab = (rows[k].label || '').toLowerCase();
            var dev = (rows[k].developerName || '').toLowerCase();
            if (lab.indexOf('all ') === 0 || dev.indexOf('all') === 0) {
                return rows[k].id;
            }
        }
        return rows[0].id || '';
    }

    function crmHubApplyPersistedListView(prefix, engineName, rows, preferredDev) {
        if (!global.CrmHubListEngine) {
            return;
        }
        var hid = crmHubLvHidden(prefix);
        var serverDefault = hid ? hid.value : '';
        var persisted = CrmHubListEngine.readPersistedListView(engineName);
        var pref = crmHubPrefForObject(engineName);
        var pinnedId = pref.pinnedId || '';
        var resolved = crmHubResolveListViewId(rows, pinnedId, persisted, serverDefault, preferredDev);
        if (hid && resolved) {
            hid.value = resolved;
        }
    }

    function crmHubSeedListViewPrefs() {
        if (!global.CrmHubListEngine) {
            return;
        }
        var embedded = {};
        try {
            var el = document.getElementById('lv-prefs-json');
            if (el && el.textContent) {
                embedded = JSON.parse(el.textContent) || {};
            }
        } catch (ePref) {
            embedded = {};
        }
        if (typeof CrmHubListEngine.seedListViewPrefs === 'function') {
            CrmHubListEngine.seedListViewPrefs(embedded);
        }
    }

    function crmHubRefreshComboUi(prefix, preferredDev) {
        var rows = crmHubComboRowsCache[prefix];
        if (!rows || !rows.length) {
            return;
        }
        var engineName = CRM_HUB_SYNC[prefix];
        if (engineName) {
            crmHubApplyPersistedListView(prefix, engineName, rows, preferredDev);
        }
        var hid = crmHubLvHidden(prefix);
        var sel = hid ? hid.value : '';
        var label = '';
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].id === sel) {
                label = rows[i].label || rows[i].id;
                break;
            }
        }
        var btn = document.getElementById('combo-' + prefix + '-btn');
        if (btn) {
            btn.textContent = label || 'Select list view';
            if (label) {
                btn.setAttribute('title', label);
            }
        }
        crmHubUpdateComboPinnedState(prefix);
        var qEl = document.getElementById('combo-' + prefix + '-q');
        var q = qEl ? qEl.value : '';
        crmHubComboRenderUl(prefix, crmHubComboFilterRows(rows, q));
    }

    function crmHubRefreshAllComboUiFromPrefs() {
        crmHubRefreshComboUi('lead');
        crmHubRefreshComboUi('opp');
        crmHubRefreshComboUi('acc');
        crmHubRefreshComboUi('con');
        if (!hubIsPartialAccess()) {
            crmHubRefreshComboUi('jobapp');
            crmHubRefreshComboUi('pos');
            crmHubRefreshComboUi('empcon', 'HR');
        }
    }

    function crmHubFetchListViewPrefsAsync() {
        function applyPrefs(prefs) {
            if (!prefs || !global.CrmHubListEngine || typeof CrmHubListEngine.seedListViewPrefs !== 'function') {
                return;
            }
            CrmHubListEngine.seedListViewPrefs(prefs);
            crmHubRefreshAllComboUiFromPrefs();
        }
        if (
            typeof CrmHubListController !== 'undefined' &&
            typeof CrmHubListController.getListViewPrefs === 'function' &&
            typeof Visualforce !== 'undefined' &&
            Visualforce.remoting
        ) {
            try {
                CrmHubListController.getListViewPrefs(
                    function (res, ev) {
                        if (ev && ev.status && res && res.success && res.prefs) {
                            applyPrefs(res.prefs);
                        }
                    },
                    { escape: false, buffer: false, timeout: 15000 }
                );
                return;
            } catch (eRemotePrefs) {
                /* fall through */
            }
        }
        if (
            global.CRM_HUB_REMOTE &&
            CRM_HUB_REMOTE.getListViewPrefs &&
            typeof Visualforce !== 'undefined' &&
            Visualforce.remoting &&
            Visualforce.remoting.Manager
        ) {
            try {
                Visualforce.remoting.Manager.invokeAction(
                    CRM_HUB_REMOTE.getListViewPrefs,
                    function (res, ev) {
                        if (ev && ev.status && res && res.success && res.prefs) {
                            applyPrefs(res.prefs);
                        }
                    },
                    { escape: false, buffer: false, timeout: 15000 }
                );
            } catch (eInvokePrefs) {
                /* ignore */
            }
        }
    }

    function crmHubEsc(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function crmHubHomeFirstName() {
        var el = document.getElementById('crm-hub-user-first-name');
        var raw = el && el.value ? String(el.value).trim() : '';
        if (raw) {
            return raw;
        }
        var lastEl = document.getElementById('crm-hub-user-last-name');
        var last = lastEl && lastEl.value ? String(lastEl.value).trim() : '';
        return last || 'there';
    }

    function crmHubHomeNum(n) {
        var v = Number(n);
        return isNaN(v) ? 0 : v;
    }

    function crmHubHomeDeltaHtml(thisVal, lastVal) {
        var t = crmHubHomeNum(thisVal);
        var l = crmHubHomeNum(lastVal);
        var d = t - l;
        if (d === 0) {
            return '<span>vs last week: 0</span>';
        }
        var cls = d > 0 ? 'is-up' : 'is-down';
        var sign = d > 0 ? '+' : '';
        return (
            '<span class="' +
            cls +
            '">' +
            sign +
            d +
            '</span> <span>vs last week (' +
            l +
            ')</span>'
        );
    }

    function crmHubHomeMetricCard(label, thisVal, lastVal, breakdownHtml) {
        return (
            '<div class="hub-home-metric">' +
            '<p class="hub-home-metric-label">' +
            crmHubEsc(label) +
            '</p>' +
            '<p class="hub-home-metric-value">' +
            crmHubHomeNum(thisVal) +
            '</p>' +
            '<p class="hub-home-metric-meta">' +
            crmHubHomeDeltaHtml(thisVal, lastVal) +
            '</p>' +
            (breakdownHtml || '') +
            '</div>'
        );
    }

    function crmHubHomeActivitiesBreakdown(tw) {
        var by = (tw && tw.activitiesByType) || {};
        return (
            '<ul class="hub-home-breakdown">' +
            '<li>Call ' +
            crmHubHomeNum(by.Call) +
            '</li>' +
            '<li>Email ' +
            crmHubHomeNum(by.Email) +
            '</li>' +
            '<li>Meeting ' +
            crmHubHomeNum(by.Meeting) +
            '</li>' +
            '<li>Other ' +
            crmHubHomeNum(by.Other) +
            '</li>' +
            '</ul>'
        );
    }

    function crmHubHomeBandClass(kind, value) {
        var n = crmHubHomeNum(value);
        var low;
        var mid;
        if (kind === 'score') {
            low = 35;
            mid = 55;
        } else if (kind === 'opps') {
            low = 1;
            mid = 10;
        } else if (kind === 'acts') {
            low = 1;
            mid = 8;
        } else if (kind === 'acctcon') {
            low = 1;
            mid = 6;
        } else if (kind === 'apps') {
            low = 1;
            mid = 5;
        } else if (kind === 'screens') {
            low = 1;
            mid = 3;
        } else if (kind === 'interviews') {
            low = 1;
            mid = 3;
        } else {
            low = 1;
            mid = 5;
        }
        if (n < low) {
            return 'hub-home-band-low';
        }
        if (n < mid) {
            return 'hub-home-band-mid';
        }
        return 'hub-home-band-high';
    }

    function crmHubHomeBandCell(kind, value, label) {
        var n = crmHubHomeNum(value);
        var text = label != null ? label : String(n);
        return (
            '<td><span class="hub-home-band ' +
            crmHubHomeBandClass(kind, n) +
            '">' +
            crmHubEsc(text) +
            '</span></td>'
        );
    }

    function crmHubHomeColIcon(name) {
        var paths = {
            score: '<path d="M12 2l2.4 7.2H22l-6 4.4 2.3 7L12 16.8 5.7 20.6 8 13.6 2 9.2h7.6z"/>',
            opps: '<polyline points="23 6 13.5 15.5 8.5 10.5 1 18"/><polyline points="17 6 23 6 23 12"/>',
            acts: '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/>',
            acctcon:
                '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
            apps: '<rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2"/>',
            screens:
                '<path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><rect x="8" y="2" width="8" height="4" rx="1"/><line x1="8" y1="12" x2="16" y2="12"/><line x1="8" y1="16" x2="13" y2="16"/>',
            interviews:
                '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/><circle cx="12" cy="15" r="2"/>'
        };
        var d = paths[name] || '';
        return (
            '<svg class="hub-home-th-ico" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
            d +
            '</svg>'
        );
    }

    function crmHubHomeTh(icon, label) {
        return (
            '<th><span class="hub-home-th">' +
            crmHubHomeColIcon(icon) +
            '<span>' +
            crmHubEsc(label) +
            '</span></span></th>'
        );
    }

    function crmHubRenderHomeStats(data) {
        var loading = document.getElementById('hub-home-loading');
        var content = document.getElementById('hub-home-content');
        var errEl = document.getElementById('hub-home-error');
        if (!content) {
            return;
        }
        if (loading) {
            loading.style.display = 'none';
        }
        if (errEl) {
            errEl.style.display = 'none';
            errEl.textContent = '';
        }
        content.style.display = '';

        var scopeKey = hubHomeScope === 'company' ? 'company' : 'me';
        var block = data[scopeKey] || {};
        var tw = block.thisWeek || {};
        var lw = block.lastWeek || {};
        var me = data.me || {};
        var co = data.company || {};
        var meScore = crmHubHomeNum(me.score);
        var coScore = crmHubHomeNum(co.score);
        var rangeLabel =
            crmHubFormatSpeakDate(data.weekStart) + ' – ' + crmHubFormatSpeakDate(data.weekEnd);

        var salesHtml =
            crmHubHomeMetricCard('New accounts', tw.accountsCreated, lw.accountsCreated) +
            crmHubHomeMetricCard('New contacts', tw.contactsCreated, lw.contactsCreated) +
            crmHubHomeMetricCard('Opportunities acted on', tw.oppsActedOn, lw.oppsActedOn) +
            crmHubHomeMetricCard(
                'Opp activities',
                tw.activitiesTotal,
                lw.activitiesTotal,
                crmHubHomeActivitiesBreakdown(tw)
            ) +
            crmHubHomeMetricCard('Contact info improved', tw.contactImproved, lw.contactImproved);

        var hrHtml = '';
        var isFull = !!data.isFullAccess;
        if (isFull) {
            hrHtml =
                '<div class="hub-home-hr">' +
                '<h3 class="hub-home-section-title">Recruiting</h3>' +
                '<div class="hub-home-grid">' +
                crmHubHomeMetricCard('New applicants', tw.applicantsNew, lw.applicantsNew) +
                crmHubHomeMetricCard('Applicants processed', tw.applicantsProcessed, lw.applicantsProcessed) +
                crmHubHomeMetricCard('Screenings finished', tw.screeningsFinished, lw.screeningsFinished) +
                crmHubHomeMetricCard('Technical interviews', tw.interviewsDone, lw.interviewsDone) +
                '</div></div>';
        }

        var boardRows = '';
        var board = data.leaderboard || [];
        var bi;
        for (bi = 0; bi < board.length; bi++) {
            var row = board[bi] || {};
            var rtw = row.thisWeek || {};
            var acctCon =
                crmHubHomeNum(rtw.accountsCreated) + crmHubHomeNum(rtw.contactsCreated);
            boardRows +=
                '<tr class="' +
                (row.isMe ? 'is-me' : '') +
                '">' +
                '<td>' +
                crmHubEsc(row.name) +
                (row.isMe ? ' (you)' : '') +
                '</td>' +
                crmHubHomeBandCell('score', row.score) +
                crmHubHomeBandCell('opps', rtw.oppsActedOn) +
                crmHubHomeBandCell('acts', rtw.activitiesTotal) +
                crmHubHomeBandCell(
                    'acctcon',
                    acctCon,
                    crmHubHomeNum(rtw.accountsCreated) + '/' + crmHubHomeNum(rtw.contactsCreated)
                ) +
                (isFull
                    ? crmHubHomeBandCell('apps', rtw.applicantsNew) +
                      crmHubHomeBandCell('screens', rtw.screeningsFinished) +
                      crmHubHomeBandCell('interviews', rtw.interviewsDone)
                    : '') +
                '</tr>';
        }

        var histNote = data.historyAvailable
            ? ''
            : '<p class="hub-home-note">Contact info improved needs Field History on Email / Phone / MobilePhone.</p>';

        var boardHead =
            '<th>Name</th>' +
            crmHubHomeTh('score', 'Score') +
            crmHubHomeTh('opps', 'Opps') +
            crmHubHomeTh('acts', 'Acts') +
            crmHubHomeTh('acctcon', 'Acct/Con') +
            (isFull
                ? crmHubHomeTh('apps', 'Apps') +
                  crmHubHomeTh('screens', 'Screens') +
                  crmHubHomeTh('interviews', 'Interviews')
                : '');

        var meScoreBand = crmHubHomeBandClass('score', meScore);
        var coScoreBand = crmHubHomeBandClass('score', coScore);

        content.innerHTML =
            '<div class="hub-home-header">' +
            '<div><h2 class="hub-home-title">Hello, ' +
            crmHubEsc(crmHubHomeFirstName()) +
            '!</h2>' +
            '<p class="hub-home-sub">This week · ' +
            crmHubEsc(rangeLabel) +
            ' · Sun–Sat</p></div>' +
            '<button type="button" class="hub-action-btn" onclick="crmHubRefreshHome();">Refresh</button>' +
            '</div>' +
            '<div class="hub-home-scores">' +
            '<div class="hub-home-score-card"><div class="hub-home-score-label">My score</div>' +
            '<div class="hub-home-score-value ' +
            meScoreBand +
            '">' +
            meScore +
            '</div></div>' +
            '<div class="hub-home-score-card"><div class="hub-home-score-label">Company score</div>' +
            '<div class="hub-home-score-value ' +
            coScoreBand +
            '">' +
            coScore +
            '</div></div>' +
            '</div>' +
            '<div class="hub-home-scope" role="group" aria-label="Metric scope">' +
            '<button type="button" class="hub-home-scope-btn' +
            (hubHomeScope === 'me' ? ' is-on' : '') +
            '" onclick="crmHubHomeSetScope(\'me\');">Me</button>' +
            '<button type="button" class="hub-home-scope-btn' +
            (hubHomeScope === 'company' ? ' is-on' : '') +
            '" onclick="crmHubHomeSetScope(\'company\');">Company</button>' +
            '</div>' +
            hrHtml +
            '<div class="hub-home-grid">' +
            salesHtml +
            '</div>' +
            '<h3 class="hub-home-section-title">Leaderboard</h3>' +
            '<div class="hub-home-board"><table><thead><tr>' +
            boardHead +
            '</tr></thead><tbody>' +
            (boardRows ||
                '<tr><td colspan="' +
                (isFull ? '8' : '5') +
                '">No activity yet this week.</td></tr>') +
            '</tbody></table></div>' +
            histNote;
    }

    function crmHubLoadHomeStats(forceRefresh) {
        if (hubHomeStatsCache && !forceRefresh) {
            crmHubRenderHomeStats(hubHomeStatsCache);
            return;
        }
        if (hubHomeLoading) {
            return;
        }
        hubHomeLoading = true;
        var loading = document.getElementById('hub-home-loading');
        var content = document.getElementById('hub-home-content');
        var errEl = document.getElementById('hub-home-error');
        if (loading) {
            loading.style.display = '';
            loading.textContent = 'Loading your week…';
        }
        if (content && forceRefresh) {
            content.style.display = 'none';
        }
        if (errEl) {
            errEl.style.display = 'none';
        }

        function done(res, ev) {
            hubHomeLoading = false;
            if (loading) {
                loading.style.display = 'none';
            }
            if (ev && ev.status === false) {
                if (errEl) {
                    errEl.style.display = '';
                    errEl.textContent = ev.message || 'Could not load Home stats.';
                }
                return;
            }
            if (!res || res.success === false) {
                if (errEl) {
                    errEl.style.display = '';
                    errEl.textContent = (res && res.error) || 'Could not load Home stats.';
                }
                return;
            }
            hubHomeStatsCache = res;
            crmHubRenderHomeStats(res);
        }

        if (
            typeof CrmHubHomeController !== 'undefined' &&
            typeof CrmHubHomeController.fetchHubHomeStats === 'function'
        ) {
            CrmHubHomeController.fetchHubHomeStats(done, { escape: false, timeout: 120000 });
            return;
        }
        crmHubInvokeRemote('CrmHubHomeController.fetchHubHomeStats', [], done, {
            escape: false,
            timeout: 120000
        });
    }

    function crmHubInitSessionAndPrefs() {
        var sessEl = document.getElementById('crm-hub-session');
        if (global.CrmHubListEngine && sessEl) {
            CrmHubListEngine.initSession(sessEl.value || '');
        }
        var userEl = document.getElementById('crm-hub-user-id');
        if (global.CrmHubListEngine && userEl) {
            CrmHubListEngine.initUserId(userEl.value || '');
        }
        crmHubSeedListViewPrefs();
        crmHubFetchListViewPrefsAsync();
    }

    function crmHubBoot() {
        crmHubInitSessionAndPrefs();
        function continueBoot() {
            crmHubBootCore();
        }
        if (
            typeof CrmHubListController !== 'undefined' &&
            typeof CrmHubListController.getHubAccessConfig === 'function' &&
            typeof Visualforce !== 'undefined' &&
            Visualforce.remoting
        ) {
            try {
                Visualforce.remoting.timeout = 120000;
                CrmHubListController.getHubAccessConfig(function (res, ev) {
                    if (ev && ev.status) {
                        crmHubApplyAccessConfig(res);
                    }
                    continueBoot();
                }, { escape: false });
                return;
            } catch (eBoot) {
                /* fall through to sync boot */
            }
        }
        continueBoot();
    }

    function crmHubBootCore() {
        var openIconEl = document.getElementById('crm-hub-open-icon');
        if (global.CrmHubListEngine && openIconEl && openIconEl.value) {
            CrmHubListEngine.initOpenIconUrl(openIconEl.value);
        }
        var leadRows = crmHubParseJson('lv-json-lead');
        var oppRows = crmHubParseJson('lv-json-opp');
        var accRows = crmHubParseJson('lv-json-acc');
        var conRows = crmHubParseJson('lv-json-con');
        var jobappRows = crmHubParseJson('lv-json-jobapp');
        var posRows = crmHubParseJson('lv-json-pos');
        var empconRows = crmHubParseJson('lv-json-empcon');
        var mountHrTabs = !hubIsPartialAccess();
        crmHubApplyPersistedListView('lead', 'Lead', leadRows);
        crmHubApplyPersistedListView('opp', 'Opportunity', oppRows);
        crmHubApplyPersistedListView('acc', 'Account', accRows);
        crmHubApplyPersistedListView('con', 'Contact', conRows);
        if (mountHrTabs) {
            crmHubApplyPersistedListView('jobapp', 'Job_Application__c', jobappRows);
            crmHubApplyPersistedListView('pos', 'Position__c', posRows);
            crmHubApplyPersistedListView('empcon', 'Employment_Contract__c', empconRows, 'HR');
        }
        crmHubInitCombo('lead', leadRows);
        crmHubInitCombo('opp', oppRows);
        crmHubInitCombo('acc', accRows);
        crmHubInitCombo('con', conRows);
        if (mountHrTabs) {
            crmHubInitCombo('jobapp', jobappRows);
            crmHubInitCombo('pos', posRows);
            crmHubInitCombo('empcon', empconRows);
        }
        CrmHubListEngine.mount('Lead', {
            objectApi: 'Lead',
            lightningSegment: 'Lead',
            initialListViewId: lvVal('lead'),
            pageSize: 25,
            initialMode: crmHubPersistedOrRadio('lead', 'Lead'),
            listEl: document.getElementById('lv-list-lead'),
            cardsEl: document.getElementById('lv-cards-lead'),
            kanbanEl: document.getElementById('lv-kanban-lead'),
            calendarEl: document.getElementById('lv-calendar-lead'),
            pagerEl: document.getElementById('lv-pager-lead'),
            actionsPrefix: 'lead'
        });
        CrmHubListEngine.mount('Opportunity', {
            objectApi: 'Opportunity',
            lightningSegment: 'Opportunity',
            initialListViewId: lvVal('opp'),
            pageSize: 25,
            initialMode: crmHubPersistedOrRadio('opp', 'Opportunity'),
            listEl: document.getElementById('lv-list-opp'),
            cardsEl: document.getElementById('lv-cards-opp'),
            kanbanEl: document.getElementById('lv-kanban-opp'),
            calendarEl: document.getElementById('lv-calendar-opp'),
            pagerEl: document.getElementById('lv-pager-opp'),
            actionsPrefix: 'opp'
        });
        CrmHubListEngine.mount('Account', {
            objectApi: 'Account',
            lightningSegment: 'Account',
            initialListViewId: lvVal('acc'),
            pageSize: 25,
            initialMode: crmHubPersistedOrRadio('acc', 'Account'),
            listEl: document.getElementById('lv-list-acc'),
            cardsEl: document.getElementById('lv-cards-acc'),
            kanbanEl: document.getElementById('lv-kanban-acc'),
            calendarEl: document.getElementById('lv-calendar-acc'),
            pagerEl: document.getElementById('lv-pager-acc'),
            actionsPrefix: 'acc'
        });
        CrmHubListEngine.mount('Contact', {
            objectApi: 'Contact',
            lightningSegment: 'Contact',
            initialListViewId: lvVal('con'),
            pageSize: 25,
            initialMode: crmHubPersistedOrRadio('con', 'Contact'),
            listEl: document.getElementById('lv-list-con'),
            cardsEl: document.getElementById('lv-cards-con'),
            kanbanEl: document.getElementById('lv-kanban-con'),
            calendarEl: document.getElementById('lv-calendar-con'),
            pagerEl: document.getElementById('lv-pager-con'),
            actionsPrefix: 'con'
        });
        if (mountHrTabs) {
            CrmHubListEngine.mount('Job_Application__c', {
                objectApi: 'Job_Application__c',
                lightningSegment: 'Job_Application__c',
                initialListViewId: lvVal('jobapp'),
                pageSize: 25,
                initialMode: crmHubPersistedOrRadio('jobapp', 'Job_Application__c'),
                listEl: document.getElementById('lv-list-jobapp'),
                cardsEl: document.getElementById('lv-cards-jobapp'),
                kanbanEl: document.getElementById('lv-kanban-jobapp'),
                calendarEl: document.getElementById('lv-calendar-jobapp'),
                pagerEl: document.getElementById('lv-pager-jobapp'),
                actionsPrefix: 'jobapp'
            });
            CrmHubListEngine.mount('Position__c', {
                objectApi: 'Position__c',
                lightningSegment: 'Position__c',
                initialListViewId: lvVal('pos'),
                pageSize: 25,
                initialMode: crmHubPersistedOrRadio('pos', 'Position__c'),
                listEl: document.getElementById('lv-list-pos'),
                cardsEl: document.getElementById('lv-cards-pos'),
                kanbanEl: document.getElementById('lv-kanban-pos'),
                calendarEl: document.getElementById('lv-calendar-pos'),
                pagerEl: document.getElementById('lv-pager-pos'),
                actionsPrefix: 'pos'
            });
            CrmHubListEngine.mount('Employment_Contract__c', {
                objectApi: 'Employment_Contract__c',
                lightningSegment: 'Employment_Contract__c',
                initialListViewId: lvVal('empcon'),
                pageSize: 25,
                initialMode: crmHubPersistedOrRadio('empcon', 'Employment_Contract__c'),
                listEl: document.getElementById('lv-list-empcon'),
                cardsEl: document.getElementById('lv-cards-empcon'),
                kanbanEl: document.getElementById('lv-kanban-empcon'),
                calendarEl: document.getElementById('lv-calendar-empcon'),
                pagerEl: document.getElementById('lv-pager-empcon'),
                actionsPrefix: 'empcon'
            });
        }
        crmHubInitSoqlModal();
        crmHubWireSoqlButtons();
        crmHubWireViewSeg(document.getElementById('seg-lead'), 'Lead');
        crmHubWireViewSeg(document.getElementById('seg-opp'), 'Opportunity');
        crmHubWireViewSeg(document.getElementById('seg-acc'), 'Account');
        crmHubWireViewSeg(document.getElementById('seg-con'), 'Contact');
        if (mountHrTabs) {
            crmHubWireViewSeg(document.getElementById('seg-jobapp'), 'Job_Application__c');
            crmHubWireViewSeg(document.getElementById('seg-pos'), 'Position__c');
            crmHubWireViewSeg(document.getElementById('seg-empcon'), 'Employment_Contract__c');
        }
        crmHubSetViewVisual(document.getElementById('seg-lead'), crmHubPersistedOrRadio('lead', 'Lead'));
        crmHubSetViewVisual(document.getElementById('seg-opp'), crmHubPersistedOrRadio('opp', 'Opportunity'));
        crmHubSetViewVisual(document.getElementById('seg-acc'), crmHubPersistedOrRadio('acc', 'Account'));
        crmHubSetViewVisual(document.getElementById('seg-con'), crmHubPersistedOrRadio('con', 'Contact'));
        if (mountHrTabs) {
            crmHubSetViewVisual(document.getElementById('seg-jobapp'), crmHubPersistedOrRadio('jobapp', 'Job_Application__c'));
            crmHubSetViewVisual(document.getElementById('seg-pos'), crmHubPersistedOrRadio('pos', 'Position__c'));
            crmHubSetViewVisual(document.getElementById('seg-empcon'), crmHubPersistedOrRadio('empcon', 'Employment_Contract__c'));
        }
        CrmHubListEngine.syncMode('Lead', crmHubPersistedOrRadio('lead', 'Lead'));
        CrmHubListEngine.syncMode('Opportunity', crmHubPersistedOrRadio('opp', 'Opportunity'));
        CrmHubListEngine.syncMode('Account', crmHubPersistedOrRadio('acc', 'Account'));
        CrmHubListEngine.syncMode('Contact', crmHubPersistedOrRadio('con', 'Contact'));
        if (mountHrTabs) {
            CrmHubListEngine.syncMode('Job_Application__c', crmHubPersistedOrRadio('jobapp', 'Job_Application__c'));
            CrmHubListEngine.syncMode('Position__c', crmHubPersistedOrRadio('pos', 'Position__c'));
            CrmHubListEngine.syncMode('Employment_Contract__c', crmHubPersistedOrRadio('empcon', 'Employment_Contract__c'));
        }
        crmHubTab('home');
        CrmHubListEngine.syncListView('Opportunity', lvVal('opp'));
        crmHubBindTabOverflow();
        crmHubBindVoicePopupMessages();
        crmHubBindBriefingControls();
        crmHubBindSearchInput();
        crmHubRenderBriefingTabs();
        setTimeout(crmHubLayoutTabOverflow, 0);
        setTimeout(crmHubLayoutTabOverflow, 250);
    }

    document.addEventListener('click', function () {
        document.querySelectorAll('.hub-lv-panel').forEach(function (p) {
            p.style.display = 'none';
        });
    });

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', crmHubBoot);
    } else {
        crmHubBoot();
    }

    global.crmHubTab = crmHubTab;
    global.crmHubRunSearch = crmHubRunSearch;
    global.crmHubOpenSearchResults = crmHubOpenSearchResults;
    global.crmHubCloseSearchResults = crmHubCloseSearchResults;
    global.crmHubCogClick = crmHubCogClick;
    global.crmHubVoiceSearch = crmHubVoiceSearch;
    global.crmHubSpeakResults = crmHubSpeakResults;
    global.crmHubOpenBriefing = crmHubOpenBriefing;
    global.crmHubCloseBriefingSetup = crmHubCloseBriefingSetup;
    global.crmHubStartBriefing = crmHubStartBriefing;
    global.crmHubRefreshHome = function () {
        crmHubLoadHomeStats(true);
    };
    global.crmHubHomeSetScope = function (scope) {
        hubHomeScope = scope === 'company' ? 'company' : 'me';
        if (hubHomeStatsCache) {
            crmHubRenderHomeStats(hubHomeStatsCache);
        }
    };
})(typeof window !== 'undefined' ? window : this);
