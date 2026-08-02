/* global Visualforce, CrmHubListController */
(function (global) {
    'use strict';

    var config = null;
    var activeSection = null;
    var booted = false;

    var SECTION_FALLBACK = {
        id: 'overview',
        label: 'Overview',
        embedType: 'lightningPage',
        path: '/lightning/n/Command_Center'
    };

    function ccEl(id) {
        return document.getElementById(id);
    }

    function ccAbsUrl(path) {
        if (!config || !config.lightningHost || !path) {
            return '';
        }
        var host = String(config.lightningHost).replace(/\/$/, '');
        var p = path.charAt(0) === '/' ? path : '/' + path;
        return host + p;
    }

    function ccSetLoading(on) {
        var el = ccEl('cc-loading');
        if (el) {
            el.style.display = on ? 'flex' : 'none';
        }
    }

    function ccSetError(msg) {
        var el = ccEl('cc-error');
        if (el) {
            el.textContent = msg || '';
            el.style.display = msg ? 'block' : 'none';
        }
    }

    function ccRenderSubnav() {
        var wrap = ccEl('cc-subnav');
        if (!wrap || !config) {
            return;
        }
        wrap.innerHTML = '';
        var sections = config.sections || [];
        for (var i = 0; i < sections.length; i++) {
            var sec = sections[i];
            var btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'cc-subnav-btn' + (sec.id === activeSection ? ' is-active' : '');
            btn.setAttribute('data-cc-section', sec.id);
            btn.textContent = sec.label;
            btn.addEventListener('click', function (evt) {
                var id = evt.currentTarget.getAttribute('data-cc-section');
                ccActivateSection(id);
            });
            wrap.appendChild(btn);
        }
    }

    function ccRenderFlowLinks(section) {
        var links = ccEl('cc-flow-links');
        if (!links) {
            return;
        }
        links.innerHTML = '';
        if (!section || !section.flows || !section.flows.length) {
            links.style.display = 'none';
            return;
        }
        links.style.display = 'flex';
        for (var i = 0; i < section.flows.length; i++) {
            var flow = section.flows[i];
            var a = document.createElement('a');
            a.className = 'cc-flow-link';
            a.href = ccAbsUrl('/flow/' + encodeURIComponent(flow.apiName));
            a.target = '_blank';
            a.rel = 'noopener';
            a.textContent = flow.label;
            links.appendChild(a);
        }
    }

    function ccDefaultSectionId() {
        return (config && config.defaultSectionId) || 'businesscard';
    }

    function ccFindSection(id) {
        var sections = (config && config.sections) || [];
        for (var i = 0; i < sections.length; i++) {
            if (sections[i].id === id) {
                return sections[i];
            }
        }
        return null;
    }

    function ccSectionPath(section) {
        if (!section) {
            return SECTION_FALLBACK.path;
        }
        if (section.path) {
            return section.path;
        }
        if (section.embedType === 'flow' && section.flowApiName) {
            return '/flow/' + section.flowApiName;
        }
        if (section.embedType === 'report' && section.reportId) {
            return '/lightning/r/Report/' + section.reportId + '/view';
        }
        return SECTION_FALLBACK.path;
    }

    function ccUpdateChrome(section) {
        var title = ccEl('cc-section-title');
        var note = ccEl('cc-section-note');
        var open = ccEl('cc-open-external');
        if (title) {
            title.textContent = section ? section.label : 'Command Center';
        }
        if (note) {
            note.textContent = section && section.note ? section.note : '';
            note.style.display = section && section.note ? 'block' : 'none';
        }
        if (open) {
            var url = '';
            if (section && !ccIsVfSection(section)) {
                url = ccAbsUrl(ccSectionPath(section || SECTION_FALLBACK));
            } else if (section && ccIsVfSection(section)) {
                url = ccAbsUrl('/lightning/n/Command_Center');
            } else {
                url = ccAbsUrl(ccSectionPath(section || SECTION_FALLBACK));
            }
            open.href = url || '#';
            open.classList.toggle('is-disabled', !url);
        }
        ccRenderFlowLinks(section);
    }

    function ccIsVfSection(section) {
        return section && section.embedType === 'vfComponent';
    }

    function ccHideAllVfPanels() {
        var panels = document.querySelectorAll('[data-cc-vf-panel]');
        for (var i = 0; i < panels.length; i++) {
            panels[i].style.display = 'none';
        }
    }

    function ccShowVfPanel(section) {
        ccHideAllVfPanels();
        var frameWrap = ccEl('cc-frame-wrap');
        var panel = section ? ccEl('cc-vf-' + section.id) : null;
        if (frameWrap) {
            frameWrap.style.display = 'none';
        }
        if (panel) {
            panel.style.display = 'block';
        }
        ccSetLoading(false);
        ccSetError('');
        if (section && section.id === 'sonic' && global.CrmHubSonic && typeof global.CrmHubSonic.activate === 'function') {
            global.CrmHubSonic.activate();
        }
    }

    function ccShowIframePanel() {
        ccHideAllVfPanels();
        var frameWrap = ccEl('cc-frame-wrap');
        if (frameWrap) {
            frameWrap.style.display = 'block';
        }
    }

    function ccLoadIframe(section) {
        var frame = ccEl('cc-iframe');
        if (!frame) {
            return;
        }
        var url = ccAbsUrl(ccSectionPath(section));
        if (!url) {
            ccSetError('Command Center URL is not configured.');
            return;
        }
        ccSetError('');
        ccSetLoading(true);
        frame.onload = function () {
            ccSetLoading(false);
        };
        frame.onerror = function () {
            ccSetLoading(false);
            ccSetError('Unable to load Command Center content. Open in Salesforce instead.');
        };
        if (frame.getAttribute('data-src') !== url) {
            frame.setAttribute('data-src', url);
            frame.src = url;
        }
    }

    function ccActivateSection(id) {
        if (!config) {
            return;
        }
        var section = ccFindSection(id);
        if (!section) {
            section = ccFindSection(ccDefaultSectionId()) || SECTION_FALLBACK;
            id = section.id;
        }
        activeSection = id;
        ccRenderSubnav();
        ccUpdateChrome(section);
        if (ccIsVfSection(section)) {
            ccShowVfPanel(section);
            return;
        }
        ccShowIframePanel();
        ccLoadIframe(section);
    }

    function ccRefresh() {
        var section = ccFindSection(activeSection);
        if (ccIsVfSection(section)) {
            ccSetError('');
            if (section && section.id === 'sonic' && global.CrmHubSonic && typeof global.CrmHubSonic.refresh === 'function') {
                global.CrmHubSonic.refresh();
            }
            return;
        }
        var frame = ccEl('cc-iframe');
        if (!frame) {
            return;
        }
        var url = ccAbsUrl(ccSectionPath(section));
        if (!url) {
            return;
        }
        ccSetLoading(true);
        frame.src = url;
    }

    function ccFetchConfig(done) {
        if (typeof Visualforce === 'undefined' || !Visualforce.remoting) {
            done(new Error('Visualforce remoting unavailable'));
            return;
        }
        Visualforce.remoting.Manager.invokeAction(
            'CrmHubListController.getCommandCenterConfig',
            function (result, event) {
                if (event && event.status) {
                    done(null, result || {});
                } else {
                    done(new Error((event && event.message) || 'Failed to load Command Center config'));
                }
            },
            { escape: false, timeout: 120000 }
        );
    }

    function ccBoot() {
        if (booted) {
            return;
        }
        ccSetLoading(true);
        ccFetchConfig(function (err, result) {
            if (err) {
                ccSetLoading(false);
                ccSetError(err.message || String(err));
                return;
            }
            config = result;
            activeSection = ccDefaultSectionId();
            ccRenderSubnav();
            ccActivateSection(activeSection);
            booted = true;
        });

        var refreshBtn = ccEl('cc-refresh-btn');
        if (refreshBtn) {
            refreshBtn.addEventListener('click', ccRefresh);
        }
    }

    function ccOnTabShown() {
        if (!booted) {
            ccBoot();
            return;
        }
        ccActivateSection(ccDefaultSectionId());
    }

    global.CrmHubCommandCenter = {
        activate: ccOnTabShown,
        refresh: ccRefresh
    };
})(typeof window !== 'undefined' ? window : this);
