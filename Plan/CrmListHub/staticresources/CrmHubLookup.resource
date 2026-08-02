/* global Visualforce, CrmHubListController */
(function (global) {
    'use strict';

    var STYLE_ID = 'crm-hub-lookup-css';
    var instances = [];

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

    function injectStyles() {
        if (document.getElementById(STYLE_ID)) {
            return;
        }
        var style = document.createElement('style');
        style.id = STYLE_ID;
        style.textContent =
            '.crm-lk{position:relative;width:100%}' +
            '.crm-lk-pill{display:flex;align-items:center;gap:.45rem;min-height:2.1rem;padding:.25rem .45rem;border:1px solid #c9c9c9;border-radius:6px;background:#fff;box-sizing:border-box}' +
            '.crm-lk-pill.is-focus{border-color:#0176d3;box-shadow:0 0 0 1px #0176d3}' +
            '.crm-lk-ico{width:1.25rem;height:1.25rem;border-radius:50%;background:#2e844a;color:#fff;display:inline-flex;align-items:center;justify-content:center;font-size:.55rem;font-weight:700;flex:0 0 auto}' +
            '.crm-lk-selected{flex:1 1 auto;min-width:0;font-size:.875rem;color:#181818;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
            '.crm-lk-clear{border:0;background:transparent;color:#706e6b;cursor:pointer;font-size:1rem;line-height:1;padding:.1rem .25rem;border-radius:4px}' +
            '.crm-lk-clear:hover{background:#f3f3f3;color:#181818}' +
            '.crm-lk-input{width:100%;border:1px solid #c9c9c9;border-radius:6px;padding:.4rem .55rem;font-size:.875rem;font-family:inherit;box-sizing:border-box;background:#fff;color:#181818}' +
            '.crm-lk-input:focus{outline:none;border-color:#0176d3;box-shadow:0 0 0 1px #0176d3}' +
            '.crm-lk-menu{position:absolute;left:0;right:0;top:calc(100% + 2px);z-index:20;background:#fff;border:1px solid #c9c9c9;border-radius:6px;box-shadow:0 8px 20px rgba(15,23,42,.12);max-height:220px;overflow:auto}' +
            '.crm-lk-opt{display:block;width:100%;text-align:left;border:0;background:#fff;padding:.5rem .65rem;font-size:.8125rem;font-family:inherit;cursor:pointer;color:#181818}' +
            '.crm-lk-opt:hover,.crm-lk-opt.is-active{background:#f3f9ff}' +
            '.crm-lk-opt-name{font-weight:600}' +
            '.crm-lk-opt-sub{display:block;font-size:.6875rem;color:#706e6b;margin-top:.1rem}' +
            '.crm-lk-empty,.crm-lk-loading{padding:.55rem .65rem;font-size:.75rem;color:#706e6b}' +
            '.crm-lk-hint{font-size:.6875rem;color:#706e6b;margin-top:.3rem;line-height:1.35}' +
            '.crm-lk-hint-ico{display:inline-block;margin-right:.2rem;opacity:.85}';
        document.head.appendChild(style);
    }

    function defaultSearch(objectApi, term, limit) {
        return new Promise(function (resolve, reject) {
            if (
                typeof CrmHubListController === 'undefined' ||
                typeof CrmHubListController.searchLookupRecords !== 'function' ||
                typeof Visualforce === 'undefined'
            ) {
                reject(new Error('Lookup remoting is unavailable'));
                return;
            }
            Visualforce.remoting.timeout = 60000;
            CrmHubListController.searchLookupRecords(
                objectApi,
                term,
                limit || 20,
                function (res, ev) {
                    if (!ev.status) {
                        reject(new Error(ev.message || 'Lookup search failed'));
                        return;
                    }
                    resolve(res || {});
                }
            );
        });
    }

    function normalizeSelection(sel) {
        if (!sel) {
            return null;
        }
        var id = sel.id || sel.Id || null;
        var name = sel.name || sel.Name || '';
        if (!id) {
            return null;
        }
        return { id: String(id), name: String(name || id) };
    }

    /**
     * Mount a reusable lookup control.
     * @param {HTMLElement} container
     * @param {Object} options
     * @param {string} options.objectApi
     * @param {{id:string,name?:string}|null} [options.value]
     * @param {string} [options.placeholder]
     * @param {string} [options.iconLetters]
     * @param {number} [options.minChars]
     * @param {number} [options.limit]
     * @param {function(string,string,number):Promise} [options.searchFn]
     * @param {function({id:string,name:string}|null):void} [options.onChange]
     * @returns {{getValue:Function,setValue:Function,destroy:Function,focus:Function}}
     */
    function mount(container, options) {
        injectStyles();
        if (!container) {
            throw new Error('CrmHubLookup.mount requires a container');
        }
        var opts = options || {};
        var objectApi = opts.objectApi;
        if (!objectApi) {
            throw new Error('CrmHubLookup.mount requires objectApi');
        }

        var state = {
            value: normalizeSelection(opts.value),
            query: '',
            open: false,
            loading: false,
            results: [],
            activeIndex: -1,
            timer: null,
            destroyed: false
        };

        container.innerHTML = '';
        container.classList.add('crm-lk-root');
        var root = document.createElement('div');
        root.className = 'crm-lk';
        container.appendChild(root);

        var minChars = opts.minChars == null ? 1 : opts.minChars;
        var limit = opts.limit || 20;
        var placeholder = opts.placeholder || 'Search...';
        var iconLetters = opts.iconLetters || String(objectApi).replace(/__c$/, '').substring(0, 1).toUpperCase();
        var searchFn = typeof opts.searchFn === 'function' ? opts.searchFn : defaultSearch;
        var onChange = typeof opts.onChange === 'function' ? opts.onChange : function () {};

        function emit() {
            onChange(state.value ? { id: state.value.id, name: state.value.name } : null);
        }

        function closeMenu() {
            state.open = false;
            state.activeIndex = -1;
            var menu = root.querySelector('.crm-lk-menu');
            if (menu) {
                menu.remove();
            }
        }

        function render() {
            root.innerHTML = '';
            if (state.value) {
                var pill = document.createElement('div');
                pill.className = 'crm-lk-pill';
                pill.innerHTML =
                    '<span class="crm-lk-ico" aria-hidden="true">' +
                    esc(iconLetters) +
                    '</span>' +
                    '<span class="crm-lk-selected">' +
                    esc(state.value.name) +
                    '</span>' +
                    '<button type="button" class="crm-lk-clear" aria-label="Clear selection">&times;</button>';
                root.appendChild(pill);
                pill.querySelector('.crm-lk-clear').onclick = function (ev) {
                    ev.preventDefault();
                    state.value = null;
                    emit();
                    render();
                    focus();
                };
                var hint = document.createElement('div');
                hint.className = 'crm-lk-hint';
                hint.innerHTML =
                    '<span class="crm-lk-hint-ico">ⓘ</span>To remove the selected record, press Backspace or Del.';
                root.appendChild(hint);
                return;
            }

            var input = document.createElement('input');
            input.type = 'text';
            input.className = 'crm-lk-input';
            input.placeholder = placeholder;
            input.setAttribute('autocomplete', 'off');
            input.value = state.query;
            root.appendChild(input);

            input.oninput = function () {
                state.query = input.value;
                scheduleSearch();
            };
            input.onkeydown = function (ev) {
                if (ev.key === 'ArrowDown') {
                    ev.preventDefault();
                    moveActive(1);
                } else if (ev.key === 'ArrowUp') {
                    ev.preventDefault();
                    moveActive(-1);
                } else if (ev.key === 'Enter') {
                    if (state.open && state.activeIndex >= 0 && state.results[state.activeIndex]) {
                        ev.preventDefault();
                        selectResult(state.results[state.activeIndex]);
                    }
                } else if (ev.key === 'Escape') {
                    closeMenu();
                } else if (
                    (ev.key === 'Backspace' || ev.key === 'Delete') &&
                    !state.query &&
                    state.value
                ) {
                    state.value = null;
                    emit();
                    render();
                }
            };
            input.onfocus = function () {
                if (state.query.trim().length >= minChars || state.results.length) {
                    openMenu();
                }
            };
            if (state.open) {
                openMenu();
            }
            input.focus();
        }

        function moveActive(delta) {
            if (!state.results.length) {
                return;
            }
            state.activeIndex = (state.activeIndex + delta + state.results.length) % state.results.length;
            var optsEl = root.querySelectorAll('.crm-lk-opt');
            for (var i = 0; i < optsEl.length; i++) {
                optsEl[i].classList.toggle('is-active', i === state.activeIndex);
            }
        }

        function openMenu() {
            state.open = true;
            var existing = root.querySelector('.crm-lk-menu');
            if (existing) {
                existing.remove();
            }
            var menu = document.createElement('div');
            menu.className = 'crm-lk-menu';
            menu.setAttribute('role', 'listbox');
            if (state.loading) {
                menu.innerHTML = '<div class="crm-lk-loading">Searching…</div>';
            } else if (!state.results.length) {
                menu.innerHTML =
                    '<div class="crm-lk-empty">' +
                    (state.query.trim().length < minChars
                        ? 'Type to search'
                        : 'No matches') +
                    '</div>';
            } else {
                for (var i = 0; i < state.results.length; i++) {
                    var row = state.results[i];
                    var btn = document.createElement('button');
                    btn.type = 'button';
                    btn.className = 'crm-lk-opt' + (i === state.activeIndex ? ' is-active' : '');
                    btn.setAttribute('role', 'option');
                    btn.innerHTML =
                        '<span class="crm-lk-opt-name">' +
                        esc(row.name) +
                        '</span>' +
                        (row.subtitle
                            ? '<span class="crm-lk-opt-sub">' + esc(row.subtitle) + '</span>'
                            : '');
                    (function (r) {
                        btn.onclick = function (ev) {
                            ev.preventDefault();
                            selectResult(r);
                        };
                    })(row);
                    menu.appendChild(btn);
                }
            }
            root.appendChild(menu);
        }

        function selectResult(row) {
            state.value = { id: String(row.id), name: String(row.name || row.id) };
            state.query = '';
            state.results = [];
            closeMenu();
            emit();
            render();
        }

        function scheduleSearch() {
            if (state.timer) {
                clearTimeout(state.timer);
            }
            var term = state.query.trim();
            if (term.length < minChars) {
                state.results = [];
                state.loading = false;
                openMenu();
                return;
            }
            state.loading = true;
            openMenu();
            state.timer = setTimeout(function () {
                runSearch(term);
            }, 220);
        }

        function runSearch(term) {
            if (state.destroyed) {
                return;
            }
            state.loading = true;
            openMenu();
            Promise.resolve(searchFn(objectApi, term, limit))
                .then(function (res) {
                    if (state.destroyed) {
                        return;
                    }
                    state.loading = false;
                    if (!res || res.error) {
                        state.results = [];
                        openMenu();
                        return;
                    }
                    var rows = res.records || [];
                    state.results = rows.map(function (r) {
                        return {
                            id: r.id || r.Id,
                            name: r.name || r.Name || '',
                            subtitle: r.subtitle || r.Subtitle || ''
                        };
                    });
                    state.activeIndex = state.results.length ? 0 : -1;
                    openMenu();
                })
                .catch(function () {
                    if (state.destroyed) {
                        return;
                    }
                    state.loading = false;
                    state.results = [];
                    openMenu();
                });
        }

        function focus() {
            var input = root.querySelector('.crm-lk-input');
            if (input) {
                input.focus();
            }
        }

        function getValue() {
            return state.value ? { id: state.value.id, name: state.value.name } : null;
        }

        function setValue(sel) {
            state.value = normalizeSelection(sel);
            state.query = '';
            closeMenu();
            render();
        }

        function destroy() {
            state.destroyed = true;
            if (state.timer) {
                clearTimeout(state.timer);
            }
            closeMenu();
            container.innerHTML = '';
            var idx = instances.indexOf(api);
            if (idx >= 0) {
                instances.splice(idx, 1);
            }
        }

        function onDocClick(ev) {
            if (!root.contains(ev.target)) {
                closeMenu();
            }
        }
        document.addEventListener('mousedown', onDocClick);

        var api = {
            getValue: getValue,
            setValue: setValue,
            destroy: function () {
                document.removeEventListener('mousedown', onDocClick);
                destroy();
            },
            focus: focus
        };
        instances.push(api);
        render();
        return api;
    }

    global.CrmHubLookup = {
        mount: mount
    };
})(typeof window !== 'undefined' ? window : this);
