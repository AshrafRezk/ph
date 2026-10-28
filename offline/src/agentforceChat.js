import askPlannerQuestion from './apex/askPlannerQuestion.js';
import { loadProfile, planBrickVisits, plannerDayChoices, profileKeyFor, toApexDate, weekRange } from './agentforceProfiles.js';
import { careCoachViewKey } from './careCoachCopilot.js';
import { navigateNavItem } from './stubs/navigation.js';
import { onAnalyticsSnapshot, readAnalyticsSnapshot, snapshotForPanel } from './analyticsContext.js';
import { escapeHtml, errorMessage } from './views/viewUtils.js';

const POS_KEY = 'zeta.pwa.agentforceFab';
const ROOT_ID = 'osr-agentforce-root';
const DRAG_THRESHOLD = 10;

let openPlanner = () => {};
let open = false;
let asking = false;
let planning = false;
let loading = false;
let loadError = '';
let profile = null;
let loadSeq = 0;
let pageContext = { tabKey: '', tabLabel: '', panel: '', tabObjectApiName: '', visitId: null, record: null, analytics: null };
let analyticsWired = false;
let contextSignature = '';
let messages = [];
let renderedChatKey = '';
let question = '';
let fabX = null;
let fabY = null;
let drag = null;
let moved = false;

function analyticsIdentity(ctx) {
    const snap = ctx.analytics;
    if (!snap) return 'list';
    if (snap.kind === 'report' || snap.kind === 'dashboard') return snap.id || 'open';
    return 'list';
}

function signatureOf(ctx) {
    const key = profileKeyFor(ctx);
    if (key === 'account') return `account:${ctx.record.recordId}`;
    if (key === 'visit') return `visit:${ctx.visitId || ''}`;
    if (key === 'report' || key === 'dashboard') return `${key}:${analyticsIdentity(ctx)}`;
    if (String(key).startsWith('cc')) return `${key}:${careCoachViewKey()}`;
    if (key === 'generic') return `generic:${ctx.tabKey}`;
    return key;
}

function wireAnalytics() {
    if (analyticsWired) return;
    analyticsWired = true;
    onAnalyticsSnapshot((snapshot) => adoptSnapshot(snapshot));
}

function adoptSnapshot(snapshot) {
    const panel = pageContext.panel;
    if (panel !== 'view-reports' && panel !== 'view-dashboards') return;
    const matched = snapshotForPanel(panel, snapshot);
    if (!matched && snapshot) return;
    const prev = contextSignature;
    pageContext = { ...pageContext, analytics: matched };
    const next = signatureOf(pageContext);
    if (next !== prev) {
        contextSignature = next;
        messages = [];
        question = '';
        profile = null;
        loadError = '';
        if (open) void loadPanelData();
        else render();
        return;
    }
    if (open) void loadPanelData();
}

function clampFabPosition(x, y) {
    const fabWidth = 118;
    const fabHeight = 56;
    const maxX = Math.max(8, window.innerWidth - fabWidth - 8);
    const maxY = Math.max(8, window.innerHeight - fabHeight - 8);
    return {
        x: Math.min(maxX, Math.max(8, x)),
        y: Math.min(maxY, Math.max(8, y))
    };
}

function loadPosition() {
    try {
        const raw = JSON.parse(localStorage.getItem(POS_KEY) || 'null');
        if (raw && Number.isFinite(raw.x) && Number.isFinite(raw.y)) {
            const clamped = clampFabPosition(raw.x, raw.y);
            fabX = clamped.x;
            fabY = clamped.y;
        }
    } catch (_err) {
        fabX = null;
        fabY = null;
    }
}

function savePosition() {
    if (fabX == null || fabY == null) return;
    try {
        localStorage.setItem(POS_KEY, JSON.stringify({ x: fabX, y: fabY }));
    } catch (_err) {
        /* ignore */
    }
}

function rootEl() {
    return document.getElementById(ROOT_ID);
}

function shouldOpenBelow() {
    const approxTop = fabY != null ? fabY : window.innerHeight - 72;
    return approxTop < Math.min(window.innerHeight * 0.38, 300);
}

function fabStyle() {
    if (fabX == null || fabY == null) return '';
    const clamped = clampFabPosition(fabX, fabY);
    fabX = clamped.x;
    fabY = clamped.y;
    return `left:${fabX}px;top:${fabY}px;right:auto;bottom:auto;`;
}

const ROBOT_PATH =
    'M12 2a2 2 0 0 1 2 2v1h2a3 3 0 0 1 3 3v2h1a1 1 0 1 1 0 2h-1v2a3 3 0 0 1-3 3h-2v1a2 2 0 1 1-4 0v-1H8a3 3 0 0 1-3-3v-2H4a1 1 0 1 1 0-2h1V8a3 3 0 0 1 3-3h2V4a2 2 0 0 1 2-2zm-3 8a1.25 1.25 0 1 0 0 2.5A1.25 1.25 0 0 0 9 10zm6 0a1.25 1.25 0 1 0 0 2.5A1.25 1.25 0 0 0 15 10zm-6.5 4.25h7a.75.75 0 0 1 0 1.5h-7a.75.75 0 0 1 0-1.5z';
const SEND_PATH = 'M3.4 20.4 21 12 3.4 3.6 3.4 10.2 15 12 3.4 13.8z';

function sectionHtml(section) {
    const meta = section.meta ? `<span class="osr-agentforce-card-meta">${escapeHtml(section.meta)}</span>` : '';
    const items = section.items || [];
    const body = items.length
        ? `<ul class="osr-agentforce-recs">${items
              .map((item) => {
                  const lines = (item.lines || [])
                      .filter(Boolean)
                      .map((line) => `<div class="osr-agentforce-rec-line">${escapeHtml(line)}</div>`)
                      .join('');
                  const actions = item.actions || [];
                  const btn = actions.length
                      ? `<div class="osr-agentforce-row-actions">${actions
                            .map(
                                (action) =>
                                    `<button type="button" class="osr-agentforce-row-btn" data-agentforce-plan="${escapeHtml(action.command)}" ${
                                        asking ? 'disabled' : ''
                                    }>${escapeHtml(action.label)}</button>`
                            )
                            .join('')}</div>`
                      : item.accountId
                        ? `<button type="button" class="osr-agentforce-row-btn" data-agentforce-add="${escapeHtml(item.accountId)}">${escapeHtml(item.action || 'Plan')}</button>`
                        : '';
                  return `<li>
                <div>
                    <div class="osr-agentforce-rec-title">${escapeHtml(item.title || '')}</div>
                    ${lines}
                </div>
                ${btn}
            </li>`;
              })
              .join('')}</ul>`
        : `<p class="osr-agentforce-muted">${escapeHtml(section.empty || 'Nothing to show.')}</p>`;
    return `<div class="osr-agentforce-card">
            <div class="osr-agentforce-card-title">${escapeHtml(section.title)}${meta}</div>
            ${body}
        </div>`;
}

function statsHtml() {
    const stats = (profile && profile.stats) || [];
    if (!stats.length) return '';
    return `<div class="osr-agentforce-stats">${stats
        .map(
            (stat) => `<div class="osr-agentforce-stat${stat.tone ? ` osr-agentforce-stat--${stat.tone}` : ''}">
                <div class="osr-agentforce-stat-value">${escapeHtml(String(stat.value))}</div>
                <div class="osr-agentforce-stat-label">${escapeHtml(stat.label)}</div>
            </div>`
        )
        .join('')}</div>`;
}

function skeletonHtml() {
    const bar = (w) => `<div class="osr-agentforce-skeleton" style="width:${w}%"></div>`;
    return `<div class="osr-agentforce-card">
            <div class="osr-agentforce-card-title">Reading ${escapeHtml(pageContext.tabLabel || 'this tab')}\u2026</div>
            ${bar(90)}${bar(70)}${bar(80)}
        </div>
        <div class="osr-agentforce-card">${bar(60)}${bar(85)}${bar(50)}</div>`;
}

function bodyHtml() {
    if (loading && !profile) return skeletonHtml();
    if (loadError && !profile) {
        return `<div class="osr-agentforce-card"><p class="osr-agentforce-muted">${escapeHtml(loadError)}</p></div>`;
    }
    if (!profile) return '';
    const insights = (profile.insights || []).map((line) => `<li>${escapeHtml(line)}</li>`).join('');
    const insightsBlock = insights
        ? `<div class="osr-agentforce-card">
            <div class="osr-agentforce-card-title">Key insights</div>
            <ul class="osr-agentforce-insights">${insights}</ul>
        </div>`
        : '';
    const sections = (profile.sections || []).map(sectionHtml).join('');
    return statsHtml() + insightsBlock + sections;
}

function chipsHtml() {
    const chips = (profile && profile.chips) || [];
    if (!chips.length) return '';
    return `<div class="osr-agentforce-chips">${chips
        .map(
            (chip) =>
                `<button type="button" class="osr-agentforce-chip" data-agentforce-chip="${escapeHtml(chip)}" ${
                    asking ? 'disabled' : ''
                }>${escapeHtml(chip)}</button>`
        )
        .join('')}</div>`;
}

function popupHtml() {
    if (!open) return '';
    const chat = messages
        .map((msg) => {
            const actions = (msg.actions || [])
                .map(
                    (action) =>
                        `<button type="button" class="osr-agentforce-chip" data-agentforce-plan="${escapeHtml(action.command)}" ${
                            asking ? 'disabled' : ''
                        }>${escapeHtml(action.label)}</button>`
                )
                .join('');
            const actionRow = actions ? `<div class="osr-agentforce-msg-actions">${actions}</div>` : '';
            const role = msg.role === 'user' ? 'osr-agentforce-msg osr-agentforce-msg--user' : 'osr-agentforce-msg osr-agentforce-msg--bot';
            return `<div class="${role}">${escapeHtml(msg.text)}${actionRow}</div>`;
        })
        .join('');
    const typing = asking
        ? `<div class="osr-agentforce-msg osr-agentforce-msg--bot osr-agentforce-msg--typing">${planning ? 'Planning visits\u2026' : 'Thinking\u2026'}</div>`
        : '';
    const onCareCoach = String(pageContext.panel || '').startsWith('view-care-coach');
    const title = (profile && profile.title) || (onCareCoach ? 'Care Coach' : 'Agentforce');
    const subtitle = (profile && profile.subtitle) || pageContext.tabLabel || 'Recommendations & Q&A';
    const placeholder = (profile && profile.placeholder) || 'Ask about this tab';
    return `<section class="osr-agentforce-popup" role="dialog" aria-label="Agentforce">
        <header class="osr-agentforce-popup-header">
            <div class="osr-agentforce-popup-head">
                <span class="osr-agentforce-popup-avatar" aria-hidden="true">
                    <svg viewBox="0 0 24 24"><path fill="currentColor" d="${ROBOT_PATH}"></path></svg>
                </span>
                <div style="min-width:0">
                    <div class="osr-agentforce-popup-title">${escapeHtml(title)}</div>
                    <div class="osr-agentforce-popup-sub">${escapeHtml(subtitle)}</div>
                </div>
            </div>
            <button type="button" class="osr-agentforce-close" data-agentforce-close aria-label="Close">\u00d7</button>
        </header>
        <div class="osr-agentforce-body" data-agentforce-body>
            ${bodyHtml()}
            <div class="osr-agentforce-chat">${chat}${typing}</div>
        </div>
        <footer class="osr-agentforce-footer">
            ${chipsHtml()}
            <div class="osr-agentforce-compose">
                <label class="visually-hidden" for="osr-agentforce-input">Ask Agentforce</label>
                <textarea id="osr-agentforce-input" rows="1" maxlength="500" placeholder="${escapeHtml(placeholder)}">${escapeHtml(question)}</textarea>
                <button type="button" class="osr-agentforce-send" data-agentforce-ask aria-label="Ask" title="Ask" ${asking ? 'disabled' : ''}>
                    <svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="${SEND_PATH}"></path></svg>
                </button>
            </div>
        </footer>
    </section>`;
}

function render() {
    const root = rootEl();
    if (!root) return;
    root.style.cssText = fabStyle();
    root.classList.toggle('is-open', open);
    root.classList.toggle('osr-agentforce--below', shouldOpenBelow());
    const popup = root.querySelector('[data-agentforce-popup]');
    const inputWasFocused = document.activeElement && document.activeElement.id === 'osr-agentforce-input';
    const inputValue = inputWasFocused ? document.activeElement.value : question;
    const oldBody = root.querySelector('[data-agentforce-body]');
    const oldScroll = oldBody ? oldBody.scrollTop : 0;
    const chatKey = messages.length ? `${messages.length}:${asking}` : '';
    const chatChanged = chatKey !== renderedChatKey;
    renderedChatKey = chatKey;
    if (popup) popup.innerHTML = popupHtml();
    const body = root.querySelector('[data-agentforce-body]');
    if (body) body.scrollTop = chatChanged && chatKey ? body.scrollHeight : oldScroll;
    const onCareCoach = String(pageContext.panel || '').startsWith('view-care-coach');
    root.querySelectorAll('[data-agentforce-toggle]').forEach((btn) => {
        btn.setAttribute('aria-expanded', open ? 'true' : 'false');
        if (!btn.classList.contains('osr-agentforce-robot')) return;
        const label = onCareCoach ? 'Ask Care Coach' : 'Ask Agentforce';
        btn.title = label;
        btn.setAttribute('aria-label', label);
    });
    const input = root.querySelector('#osr-agentforce-input');
    if (input) {
        input.value = inputValue;
        question = inputValue;
        if (inputWasFocused) {
            input.focus();
            const len = input.value.length;
            input.setSelectionRange(len, len);
        }
    }
}

function ensureShell() {
    if (rootEl()) return;
    loadPosition();
    const root = document.createElement('div');
    root.id = ROOT_ID;
    root.className = 'osr-agentforce';
    root.hidden = true;
    root.innerHTML = `
        <div class="osr-agentforce-cluster" data-agentforce-drag>
            <div data-agentforce-popup></div>
            <button type="button" class="osr-agentforce-robot" data-agentforce-toggle title="Ask Agentforce" aria-label="Ask Agentforce" aria-expanded="false">
                <svg class="osr-agentforce-icon" viewBox="0 0 24 24" aria-hidden="true">
                    <path fill="currentColor" d="M12 2a2 2 0 0 1 2 2v1h2a3 3 0 0 1 3 3v2h1a1 1 0 1 1 0 2h-1v2a3 3 0 0 1-3 3h-2v1a2 2 0 1 1-4 0v-1H8a3 3 0 0 1-3-3v-2H4a1 1 0 1 1 0-2h1V8a3 3 0 0 1 3-3h2V4a2 2 0 0 1 2-2zm-3 8a1.25 1.25 0 1 0 0 2.5A1.25 1.25 0 0 0 9 10zm6 0a1.25 1.25 0 1 0 0 2.5A1.25 1.25 0 0 0 15 10zm-6.5 4.25h7a.75.75 0 0 1 0 1.5h-7a.75.75 0 0 1 0-1.5z"></path>
                </svg>
            </button>
            <button type="button" class="osr-agentforce-menu" data-agentforce-toggle title="Agentforce menu" aria-label="Agentforce menu" aria-expanded="false">\u00b7\u00b7\u00b7</button>
        </div>
    `;
    document.body.appendChild(root);
    bind(root);
    window.addEventListener('resize', () => {
        if (fabX == null || fabY == null) return;
        const clamped = clampFabPosition(fabX, fabY);
        fabX = clamped.x;
        fabY = clamped.y;
        const el = rootEl();
        if (el) el.style.cssText = fabStyle();
        if (open) render();
    });
    render();
}

function bind(root) {
    root.addEventListener('click', onClick);
    root.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && open) {
            event.preventDefault();
            closePopup();
            return;
        }
        if (event.key === 'Enter' && !event.shiftKey && event.target && event.target.id === 'osr-agentforce-input') {
            event.preventDefault();
            void sendQuestion();
        }
    });
    root.addEventListener('input', (event) => {
        if (event.target && event.target.id === 'osr-agentforce-input') {
            question = event.target.value;
        }
    });
    const dragHandle = root.querySelector('[data-agentforce-drag]');
    if (dragHandle) {
        dragHandle.addEventListener('pointerdown', onPointerDown);
    }
    document.addEventListener('pointerdown', onDocumentPointerDown, true);
}

function closePopup() {
    open = false;
    render();
}

function togglePopup() {
    open = !open;
    if (open && signatureOf(pageContext) !== contextSignature) {
        setAgentforcePageContext({});
        return;
    }
    render();
    if (open) void loadPanelData();
}

function onDocumentPointerDown(event) {
    if (!open) return;
    const root = rootEl();
    if (!root || root.contains(event.target)) return;
    closePopup();
}

function eventFromToggle(event) {
    if (event.target.closest('[data-agentforce-popup]')) return false;
    const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
    return Boolean(
        event.target.closest('[data-agentforce-toggle]') ||
            path.some((node) => node && node.hasAttribute && node.hasAttribute('data-agentforce-toggle'))
    );
}

function onClick(event) {
    const close = event.target.closest('[data-agentforce-close]');
    if (close) {
        event.preventDefault();
        closePopup();
        return;
    }
    if (eventFromToggle(event)) {
        if (moved) {
            moved = false;
            event.preventDefault();
            return;
        }
        event.preventDefault();
        togglePopup();
        return;
    }
    const plan = event.target.closest('[data-agentforce-plan]');
    if (plan && plan.dataset.agentforcePlan) {
        event.preventDefault();
        if (!asking) beginPlan(plan.dataset.agentforcePlan);
        return;
    }
    const add = event.target.closest('[data-agentforce-add]');
    if (add && add.dataset.agentforceAdd) {
        try {
            sessionStorage.setItem('zeta.pwa.planAccountId', add.dataset.agentforceAdd);
        } catch (_err) {
            /* ignore */
        }
        window.dispatchEvent(new CustomEvent('zeta-plan-account'));
        closePopup();
        openPlanner();
        return;
    }
    const chip = event.target.closest('[data-agentforce-chip]');
    if (chip && chip.dataset.agentforceChip) {
        void sendQuestion(chip.dataset.agentforceChip);
        return;
    }
    const ask = event.target.closest('[data-agentforce-ask]');
    if (ask) {
        void sendQuestion();
    }
}

function onPointerDown(event) {
    if (event.button != null && event.button !== 0) return;
    if (
        event.target.closest(
            '[data-agentforce-popup], textarea, [data-agentforce-ask], [data-agentforce-add], [data-agentforce-plan], [data-agentforce-close], [data-agentforce-chip]'
        )
    ) {
        return;
    }
    const root = rootEl();
    if (!root) return;
    const rect = root.getBoundingClientRect();
    moved = false;
    drag = {
        startX: event.clientX,
        startY: event.clientY,
        originLeft: rect.left,
        originTop: rect.top
    };
    window.addEventListener('pointermove', onPointerMove);
    window.addEventListener('pointerup', onPointerUp);
    window.addEventListener('pointercancel', onPointerUp);
}

function onPointerMove(event) {
    if (!drag) return;
    const dx = event.clientX - drag.startX;
    const dy = event.clientY - drag.startY;
    if (Math.abs(dx) > DRAG_THRESHOLD || Math.abs(dy) > DRAG_THRESHOLD) moved = true;
    if (!moved) return;
    event.preventDefault();
    const next = clampFabPosition(drag.originLeft + dx, drag.originTop + dy);
    fabX = next.x;
    fabY = next.y;
    const root = rootEl();
    if (root) root.style.cssText = fabStyle();
}

function onPointerUp() {
    window.removeEventListener('pointermove', onPointerMove);
    window.removeEventListener('pointerup', onPointerUp);
    window.removeEventListener('pointercancel', onPointerUp);
    drag = null;
    savePosition();
    if (moved) {
        window.setTimeout(() => {
            moved = false;
        }, 0);
    }
}

async function loadPanelData() {
    const seq = ++loadSeq;
    const ctx = { ...pageContext };
    const previous = profile;
    loading = !previous;
    loadError = '';
    render();
    try {
        const next = await loadProfile(ctx);
        if (seq !== loadSeq) return;
        profile = next;
    } catch (error) {
        if (seq !== loadSeq) return;
        if (!previous) {
            profile = null;
            loadError = errorMessage(error) || `Could not load ${ctx.tabLabel || 'tab'} insights.`;
        }
    } finally {
        if (seq === loadSeq) {
            loading = false;
            render();
        }
    }
}

function fallbackAnswer() {
    const lines = (profile && profile.insights) || [];
    const chips = (profile && profile.chips) || [];
    const brief = lines.length ? `Here is what I see on ${pageContext.tabLabel || 'this tab'}:\n${lines.join('\n')}` : '';
    const hint = chips.length ? `Try: ${chips.map((chip) => `"${chip}"`).join(', ')}.` : '';
    return [brief, hint].filter(Boolean).join('\n\n') || 'I have no insights for this tab yet.';
}

function parsePlanCommand(command) {
    const [kind, brickKey, date] = String(command || '').split(':');
    if (!brickKey) return null;
    if (kind === 'week') return { brickKey, span: 'week' };
    if (kind === 'day') return { brickKey, span: 'ask-day' };
    if (kind === 'date' && date) return { brickKey, span: 'day', date };
    return null;
}

function askWhichDay(brickKey) {
    const choice = plannerDayChoices(brickKey);
    if (!choice) {
        messages = [...messages, { role: 'bot', text: 'Open the assistant on the planner so I can read your bricks.' }];
        render();
        return;
    }
    if (!choice.days.length) {
        messages = [
            ...messages,
            { role: 'bot', text: `${choice.brick.name} has no working days left this week (Saturday through Wednesday).` }
        ];
        render();
        return;
    }
    messages = [
        ...messages,
        {
            role: 'bot',
            text: `Which day should I plan in ${choice.brick.name}?`,
            actions: choice.days.map((day) => ({ label: day.label, command: `date:${choice.brick.key}:${day.iso}` }))
        }
    ];
    render();
}

function openFromAgent(command) {
    const parts = String(command || '').split(':');
    const objectApiName = parts[1];
    const recordId = parts.slice(2).join(':');
    if (!objectApiName || !recordId) return;
    if (objectApiName === 'Tab') {
        window.dispatchEvent(new CustomEvent('zeta-navigate-tab', { detail: { apiName: recordId } }));
    } else {
        window.dispatchEvent(new CustomEvent('zeta-navigate-record', { detail: { recordId, objectApiName } }));
    }
    closePopup();
}

function handleCareCoachAction(command) {
    const parts = String(command || '').split(':');
    const kind = parts[1];
    const rest = parts.slice(2).join(':');
    if (kind === 'tab' && rest) {
        navigateNavItem(rest, {});
    } else if (kind === 'patient' && rest) {
        navigateNavItem('Care_Coach_Patients', { c__patientId: rest });
    } else if (kind === 'status' && rest) {
        navigateNavItem('Care_Coach_Patients', { c__status: rest });
    } else if (kind === 'group' && rest) {
        navigateNavItem('Care_Coach_Patients', { c__group: rest });
    } else if (kind === 'product' && rest) {
        navigateNavItem('Care_Coach_Patients', { c__productId: rest });
    } else if (kind === 'scripts' && rest) {
        navigateNavItem('Care_Coach_Knowledge', { c__productId: rest });
    } else if (kind === 'script' && rest) {
        navigateNavItem('Care_Coach_Knowledge', { c__scriptId: rest });
    } else {
        return;
    }
    closePopup();
}

function beginPlan(command) {
    if (String(command || '').startsWith('cc:')) {
        handleCareCoachAction(command);
        return;
    }
    if (String(command || '').startsWith('open:')) {
        openFromAgent(command);
        return;
    }
    const intent = parsePlanCommand(command);
    if (!intent) return;
    if (intent.span === 'ask-day') {
        askWhichDay(intent.brickKey);
        return;
    }
    const choice = plannerDayChoices(intent.brickKey);
    const name = (choice && choice.brick.name) || 'this brick';
    const day = choice && choice.days.find((row) => row.iso === intent.date);
    const userText = intent.span === 'day' ? `Plan ${name} on ${day ? day.label : intent.date}` : `Plan ${name} this week`;
    void runPlan(intent, userText);
}

async function runPlan(intent, userText) {
    if (asking) return;
    asking = true;
    planning = true;
    if (userText) messages = [...messages, { role: 'user', text: userText }];
    const signature = contextSignature;
    render();
    try {
        const reply = await planBrickVisits(intent);
        if (signature !== contextSignature) return;
        messages = [...messages, { role: 'bot', text: reply }];
    } catch (error) {
        if (signature !== contextSignature) return;
        messages = [...messages, { role: 'bot', text: errorMessage(error) }];
    } finally {
        asking = false;
        planning = false;
        if (signature === contextSignature) {
            render();
            void loadPanelData();
        }
    }
}

async function sendQuestion(preset) {
    const input = rootEl() && rootEl().querySelector('#osr-agentforce-input');
    const text = (preset || (input && input.value) || question || '').trim();
    if (!text || asking) return;
    asking = true;
    planning = false;
    if (!preset) question = '';
    messages = [...messages, { role: 'user', text }];
    const signature = contextSignature;
    render();
    try {
        if (loading) {
            await new Promise((resolve) => {
                const wait = () => (loading ? window.setTimeout(wait, 120) : resolve());
                wait();
            });
        }
        const intent = profile && typeof profile.planRequest === 'function' ? profile.planRequest(text) : null;
        if (intent) {
            if (signature !== contextSignature) return;
            if (intent.brickKey) {
                planning = true;
                render();
                const reply = await planBrickVisits(intent);
                if (signature !== contextSignature) return;
                messages = [...messages, { role: 'bot', text: reply }];
                return;
            }
            messages = [...messages, { role: 'bot', text: intent.clarify || 'Which brick should I plan?', actions: intent.actions }];
            return;
        }
        let reply = profile && typeof profile.answer === 'function' ? profile.answer(text.toLowerCase()) : null;
        if (reply && typeof reply.then === 'function') reply = await reply;
        if (reply && typeof reply === 'object' && reply.navigate) {
            messages = [...messages, { role: 'bot', text: 'Opening that tab.' }];
            handleCareCoachAction(reply.navigate);
            return;
        }
        if (!reply && profile && profile.remoteAsk) {
            const { start } = weekRange();
            const result = await askPlannerQuestion({ question: text, weekStart: toApexDate(start) });
            reply = (result && result.answer) || 'No answer returned.';
        }
        if (signature !== contextSignature) return;
        if (reply && typeof reply === 'object') {
            messages = [...messages, { role: 'bot', text: reply.text || fallbackAnswer(), actions: reply.actions || [] }];
        } else {
            messages = [...messages, { role: 'bot', text: reply || fallbackAnswer() }];
        }
    } catch (error) {
        if (signature !== contextSignature) return;
        messages = [...messages, { role: 'bot', text: errorMessage(error) }];
    } finally {
        const planned = planning;
        asking = false;
        planning = false;
        if (signature === contextSignature) {
            render();
            if (planned) void loadPanelData();
        }
    }
}

function refreshCareCoachContext() {
    if (!String(pageContext.panel || '').startsWith('view-care-coach')) return;
    setAgentforcePageContext({});
}

export function mountAgentforceChat(options = {}) {
    if (options.openPlanner) openPlanner = options.openPlanner;
    ensureShell();
    wireAnalytics();
    if (!mountAgentforceChat.careCoachWired) {
        mountAgentforceChat.careCoachWired = true;
        window.addEventListener('carecoachmodechange', refreshCareCoachContext);
        window.addEventListener('carecoachscopechange', refreshCareCoachContext);
    }
}

export function setAgentforcePageContext(patch = {}) {
    pageContext = { ...pageContext, ...patch };
    if ('tabKey' in patch && patch.tabKey !== undefined && !('record' in patch)) {
        const modalOpen = document.body.classList.contains('record-modal-open');
        if (!modalOpen) pageContext.record = null;
    }
    if (('panel' in patch || 'tabKey' in patch) && !('analytics' in patch)) {
        pageContext.analytics = snapshotForPanel(pageContext.panel, readAnalyticsSnapshot());
    }
    const nextSignature = signatureOf(pageContext);
    if (nextSignature === contextSignature) return;
    contextSignature = nextSignature;
    loadSeq++;
    profile = null;
    loading = false;
    loadError = '';
    messages = [];
    question = '';
    if (open) void loadPanelData();
    else render();
}

export function setAgentforceChatVisible(visible) {
    ensureShell();
    const root = rootEl();
    if (!root) return;
    root.hidden = !visible;
    if (visible) {
        root.removeAttribute('hidden');
    } else {
        root.setAttribute('hidden', '');
        open = false;
        render();
    }
}
