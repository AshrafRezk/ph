import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getContext from '@salesforce/apex/CareCoachAccess.getContext';
import getPlannerData from '@salesforce/apex/CareCoachPlannerController.getPlannerData';
import scheduleCall from '@salesforce/apex/CareCoachPlannerController.scheduleCall';
import rescheduleCall from '@salesforce/apex/CareCoachPlannerController.rescheduleCall';
import deleteCall from '@salesforce/apex/CareCoachPlannerController.deleteCall';
import completeCall from '@salesforce/apex/CareCoachPlannerController.completeCall';
import createTimeOff from '@salesforce/apex/CareCoachPlannerController.createTimeOff';
import updateTimeOff from '@salesforce/apex/CareCoachPlannerController.updateTimeOff';
import moveTimeOff from '@salesforce/apex/CareCoachPlannerController.moveTimeOff';
import setTimeOffStage from '@salesforce/apex/CareCoachPlannerController.setTimeOffStage';
import deleteTimeOff from '@salesforce/apex/CareCoachPlannerController.deleteTimeOff';
import attachCallRecording from '@salesforce/apex/CareCoachTelephonyController.attachCallRecording';
import {
    STATUS_META,
    CALL_STATUS_COLORS,
    riskClass,
    formatRelative,
    formatTime,
    formatDateTime,
    toIsoDate,
    reduceError,
    getStoredMode,
    storeMode,
    onModeChange,
    initialsAvatar
} from 'c/careCoachUtils';

const DAY_START = 8;
const DAY_END = 20;
const HOUR_PX = 72;
const SLOT_MIN = 15;
const SNAP_MIN = 5;
const CALL_MINUTES = 5;
const LONG_PRESS_MS = 350;
const TOUCH_SLOP = 10;
const DRAG_THRESHOLD = 5;
const AUTO_SCROLL_EDGE = 48;
const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const HOUR_OPTIONS = ['1', '2', '3', '4', '5', '6', '7', '8'];

function startOfWeek(d) {
    const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    x.setDate(x.getDate() - x.getDay());
    return x;
}

function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

function toLocalInput(d) {
    return d.toISOString();
}

export default class CareCoachPlanner extends NavigationMixin(LightningElement) {
    context;
    mode = 'psp';
    view = 'week';
    anchor = new Date();
    data;
    isLoading = true;
    error;
    patientSearch = '';
    patientFilter = 'all';
    drag;
    highlightEl;
    highlightKey;
    suppressClickUntil = 0;
    unsubscribe;

    showCallModal = false;
    showDetailModal = false;
    showTimeOffModal = false;
    saving = false;
    callForm = {};
    completeForm = {};
    timeOffForm = {};
    selectedCall;
    rescheduleValue;
    showDialer = false;
    pendingRecording;

    connectedCallback() {
        this.mode = getStoredMode();
        this.unsubscribe = onModeChange((mode) => {
            if (mode !== this.mode) {
                this.mode = mode;
                this.load();
            }
        });
        getContext()
            .then((ctx) => {
                this.context = ctx;
            })
            .catch(() => {});
        window.addEventListener('touchmove', this.onTouchMove, { passive: false });
        this.load();
    }

    disconnectedCallback() {
        if (this.unsubscribe) this.unsubscribe();
        window.removeEventListener('touchmove', this.onTouchMove);
        this.endDrag();
    }

    // ---------------------------------------------------------------- data

    get rangeStart() {
        return this.view === 'week'
            ? startOfWeek(this.anchor)
            : new Date(this.anchor.getFullYear(), this.anchor.getMonth(), this.anchor.getDate());
    }

    get rangeDays() {
        return this.view === 'week' ? 7 : 1;
    }

    async load() {
        this.isLoading = true;
        this.error = undefined;
        try {
            this.data = await getPlannerData({ startDate: toIsoDate(this.rangeStart), days: this.rangeDays, mode: this.mode });
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    get canEdit() {
        return this.data && this.data.canEdit;
    }

    get readOnly() {
        return !this.canEdit;
    }

    handleModeChange(event) {
        storeMode(event.detail);
    }

    // ---------------------------------------------------------------- toolbar

    get rangeLabel() {
        const start = this.rangeStart;
        if (this.view === 'day') {
            return start.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
        }
        const end = new Date(start);
        end.setDate(end.getDate() + 6);
        const fmt = { day: 'numeric', month: 'short' };
        return `${start.toLocaleDateString(undefined, fmt)} – ${end.toLocaleDateString(undefined, { ...fmt, year: 'numeric' })}`;
    }

    get weekBtnClass() {
        return this.view === 'week' ? 'is-active' : '';
    }

    get dayBtnClass() {
        return this.view === 'day' ? 'is-active' : '';
    }

    handleView(event) {
        this.view = event.currentTarget.dataset.view;
        this.load();
    }

    handlePrev() {
        this.shift(-1);
    }

    handleNext() {
        this.shift(1);
    }

    handleToday() {
        this.anchor = new Date();
        this.load();
    }

    shift(direction) {
        const d = new Date(this.anchor);
        d.setDate(d.getDate() + direction * this.rangeDays);
        this.anchor = d;
        this.load();
    }

    get summaryText() {
        if (!this.data) return '';
        const calls = this.data.calls;
        const planned = calls.filter((c) => c.status === 'Planned').length;
        const reached = calls.filter((c) => c.status === 'Reached').length;
        const unreached = calls.filter((c) => c.status && c.status.startsWith('Unreached')).length;
        return `${planned} planned · ${reached} reached · ${unreached} unreached`;
    }

    get showJumpToday() {
        const today = new Date();
        const start = this.rangeStart;
        const end = new Date(start);
        end.setDate(end.getDate() + this.rangeDays);
        return today < start || today >= end;
    }

    // ---------------------------------------------------------------- patients panel

    get filterChips() {
        const items = [
            { key: 'all', label: 'All' },
            { key: 'due', label: 'Follow-up due' },
            { key: 'risk', label: 'High risk' },
            { key: 'pending', label: 'Pending' }
        ];
        return items.map((i) => ({ ...i, cls: i.key === this.patientFilter ? 'mini-chip is-active' : 'mini-chip' }));
    }

    handlePatientFilter(event) {
        this.patientFilter = event.currentTarget.dataset.key;
    }

    handlePatientSearch(event) {
        this.patientSearch = (event.target.value || '').toLowerCase();
    }

    get patients() {
        if (!this.data) return [];
        const term = this.patientSearch;
        return this.data.patients
            .filter((p) => {
                if (this.patientFilter === 'due' && !p.followUpDue) return false;
                if (this.patientFilter === 'risk' && p.adherence !== 'High risk') return false;
                if (this.patientFilter === 'pending' && p.status !== 'Pending') return false;
                if (term && !`${p.displayName} ${p.patientNumber} ${p.phone || ''}`.toLowerCase().includes(term)) return false;
                return true;
            })
            .slice(0, 150)
            .map((p) => {
                const meta = STATUS_META[p.status] || STATUS_META['Unknown (Failed calls)'];
                return {
                    ...p,
                    avatar: initialsAvatar(p.displayName),
                    avatarClass: this.data.masked ? 'cc-avatar cc-avatar_masked' : 'cc-avatar',
                    riskClass: riskClass(p.adherence),
                    riskLabel: p.adherence ? p.adherence.replace(' risk', '') : '',
                    lastCall: `Last call ${formatRelative(p.lastCallDate).toLowerCase()}`,
                    next: p.nextCallDate ? `Next ${formatDateTime(p.nextCallDate)}` : '',
                    statusDot: `background:${meta.color};`,
                    draggable: this.canEdit ? 'true' : 'false',
                    cardClass: `${p.followUpDue ? 'patient-card patient-card_due' : 'patient-card'}${this.canEdit ? ' can-drag' : ''}`
                };
            });
    }

    get patientCountLabel() {
        const total = this.data ? this.data.patients.length : 0;
        return `${this.patients.length} of ${total} active patients`;
    }

    handlePatientClick(event) {
        if (this.readOnly || this.clickSuppressed()) return;
        const id = event.currentTarget.dataset.id;
        const start = this.nextFreeSlot();
        this.openCallModal(id, start);
    }

    // ---------------------------------------------------------------- calendar

    get hours() {
        const out = [];
        for (let h = DAY_START; h < DAY_END; h++) {
            out.push({ key: `h${h}`, label: `${String(h).padStart(2, '0')}:00` });
        }
        return out;
    }

    get gridStyle() {
        return `height:${(DAY_END - DAY_START) * HOUR_PX}px;`;
    }

    get days() {
        const out = [];
        const today = new Date();
        const calls = this.data ? this.data.calls : [];
        const timeOffs = this.data ? this.data.timeOffs : [];
        for (let i = 0; i < this.rangeDays; i++) {
            const day = new Date(this.rangeStart);
            day.setDate(day.getDate() + i);
            const iso = toIsoDate(day);
            const slots = [];
            for (let m = DAY_START * 60; m < DAY_END * 60; m += SLOT_MIN) {
                slots.push({ key: `${iso}-${m}`, minutes: m, cls: m % 60 === 0 ? 'slot slot_hour' : 'slot' });
            }
            const dayCalls = calls
                .filter((c) => sameDay(new Date(c.startTime), day))
                .map((c) => this.decorateCall(c));
            this.layoutOverlaps(dayCalls);
            const dayTimeOffs = timeOffs
                .filter((t) => {
                    const s = new Date(t.startTime);
                    const e = new Date(t.endTime);
                    const dayStart = new Date(day);
                    const dayEnd = new Date(day);
                    dayEnd.setDate(dayEnd.getDate() + 1);
                    return s < dayEnd && e > dayStart;
                })
                .map((t) => this.decorateTimeOff(t, day));
            let cls = 'day-col';
            if (sameDay(day, today)) cls += ' day-col_today';
            out.push({
                key: iso,
                iso,
                name: DAY_NAMES[day.getDay()],
                num: day.getDate(),
                isToday: sameDay(day, today),
                headCls: sameDay(day, today) ? 'day-head day-head_today' : 'day-head',
                cls,
                slots,
                calls: dayCalls,
                fullDayOff: dayTimeOffs.filter((t) => t.isFullDay),
                blocks: dayTimeOffs.filter((t) => !t.isFullDay),
                count: dayCalls.length
            });
        }
        return out;
    }

    get hasFullDayRow() {
        return this.days.some((d) => d.fullDayOff.length);
    }

    minutesOf(date) {
        return date.getHours() * 60 + date.getMinutes();
    }

    decorateCall(c) {
        const s = new Date(c.startTime);
        const e = new Date(c.endTime);
        const top = Math.max(0, ((this.minutesOf(s) - DAY_START * 60) / 60) * HOUR_PX);
        const height = Math.max(18, ((e - s) / 3600000) * HOUR_PX - 2);
        const color = CALL_STATUS_COLORS[c.status] || '#8a8886';
        const planned = c.status === 'Planned';
        const compact = height < 36;
        return {
            ...c,
            top,
            height,
            timeLabel: formatTime(s),
            cls: `event${planned ? ' event_planned' : ''}${compact ? ' event_compact' : ''}${planned && this.canEdit ? ' can-drag' : ''}`,
            color,
            draggable: planned && this.canEdit ? 'true' : 'false',
            dragLabel: c.patientName,
            title: `${c.patientName} · ${c.reason || ''} · ${c.status}`,
            riskBadge: c.aiRisk === 'High',
            col: 0,
            cols: 1
        };
    }

    layoutOverlaps(events) {
        events.sort((a, b) => a.top - b.top);
        let group = [];
        let groupEnd = -1;
        const flush = () => {
            const cols = [];
            group.forEach((ev) => {
                let placed = false;
                for (let i = 0; i < cols.length; i++) {
                    if (cols[i] <= ev.top) {
                        ev.col = i;
                        cols[i] = ev.top + ev.height;
                        placed = true;
                        break;
                    }
                }
                if (!placed) {
                    ev.col = cols.length;
                    cols.push(ev.top + ev.height);
                }
            });
            group.forEach((ev) => {
                ev.cols = cols.length;
            });
        };
        events.forEach((ev) => {
            if (ev.top >= groupEnd && group.length) {
                flush();
                group = [];
            }
            group.push(ev);
            groupEnd = Math.max(groupEnd, ev.top + ev.height);
        });
        if (group.length) flush();
        events.forEach((ev) => {
            const width = 100 / ev.cols;
            ev.style = `top:${ev.top}px;height:${ev.height}px;left:calc(${ev.col * width}% + 2px);width:calc(${width}% - 4px);--event-color:${ev.color};`;
        });
    }

    decorateTimeOff(t, day) {
        const isFullDay = t.spanType === 'Full_Day' || t.spanType === 'Days';
        const s = new Date(t.startTime);
        const e = new Date(t.endTime);
        const top = Math.max(0, ((this.minutesOf(s) - DAY_START * 60) / 60) * HOUR_PX);
        const height = Math.max(20, ((e - s) / 3600000) * HOUR_PX - 2);
        const movable = this.canEdit && (t.stage === 'Draft' || t.stage === 'Submitted for Approval');
        return {
            ...t,
            key: `${t.id}-${toIsoDate(day)}`,
            isFullDay,
            style: `top:${top}px;height:${height}px;`,
            label: `${t.type}${t.stage ? ' · ' + t.stage : ''}`,
            timeLabel: isFullDay ? 'All day' : `${formatTime(s)}–${formatTime(e)}`,
            cls: `${t.stage === 'Approved' ? 'tot tot_approved' : t.stage === 'Draft' ? 'tot tot_draft' : 'tot'}${movable ? ' tot_movable can-drag' : ''}`,
            draggable: movable ? 'true' : 'false',
            fullDayAttr: isFullDay ? 'true' : 'false'
        };
    }

    nextFreeSlot() {
        const now = new Date();
        const d = new Date(now);
        d.setMinutes(now.getMinutes() < 30 ? 30 : 60, 0, 0);
        if (d.getHours() < DAY_START) d.setHours(DAY_START, 0, 0, 0);
        if (d.getHours() >= DAY_END) {
            d.setDate(d.getDate() + 1);
            d.setHours(DAY_START + 1, 0, 0, 0);
        }
        return d;
    }

    slotDate(iso, minutes) {
        const [y, m, d] = iso.split('-').map(Number);
        return new Date(y, m - 1, d, Math.floor(minutes / 60), minutes % 60, 0, 0);
    }

    handleSlotClick(event) {
        if (this.readOnly || this.clickSuppressed()) return;
        const start = this.slotDate(event.currentTarget.dataset.day, Number(event.currentTarget.dataset.minutes));
        this.openCallModal(null, start);
    }

    // ---------------------------------------------------------------- drag and drop
    // Pointer based so it works with mouse, touch and pen. Touch drags start on long-press
    // so a normal swipe still scrolls the list and calendar.

    handleDragPointerDown(event) {
        const el = event.currentTarget;
        if (this.readOnly || !el.classList.contains('can-drag') || (event.pointerType === 'mouse' && event.button !== 0)) return;
        this.endDrag();
        const rect = el.getBoundingClientRect();
        const kind = el.dataset.drag;
        const touch = event.pointerType !== 'mouse';
        this.drag = {
            kind,
            id: el.dataset.id,
            label: el.dataset.label || '',
            fullDay: el.dataset.fullday === 'true',
            source: el,
            pointerId: event.pointerId,
            touch,
            startX: event.clientX,
            startY: event.clientY,
            offsetY: kind === 'patient' ? 0 : event.clientY - rect.top,
            active: false,
            target: null
        };
        if (!touch) event.preventDefault();
        if (touch) {
            this.drag.timer = setTimeout(() => this.activateDrag(), LONG_PRESS_MS);
        }
        window.addEventListener('pointermove', this.onDragMove);
        window.addEventListener('pointerup', this.onDragUp);
        window.addEventListener('pointercancel', this.onDragCancel);
        window.addEventListener('contextmenu', this.onDragContextMenu);
    }

    onDragMove = (event) => {
        const d = this.drag;
        if (!d || event.pointerId !== d.pointerId) return;
        const moved = Math.hypot(event.clientX - d.startX, event.clientY - d.startY);
        if (!d.active) {
            if (d.touch) {
                if (moved > TOUCH_SLOP) this.endDrag();
                return;
            }
            if (moved < DRAG_THRESHOLD) return;
            this.activateDrag();
        }
        event.preventDefault();
        this.autoScroll(event.clientY);
        this.updateDrag(event.clientX, event.clientY);
    };

    onDragUp = (event) => {
        const d = this.drag;
        if (!d || event.pointerId !== d.pointerId) return;
        if (!d.active) {
            this.endDrag();
            return;
        }
        this.updateDrag(event.clientX, event.clientY);
        const target = d.target;
        this.suppressClickUntil = Date.now() + 400;
        this.endDrag();
        if (target) this.commitDrop(d, target);
    };

    onDragCancel = () => {
        this.endDrag();
    };

    onDragContextMenu = (event) => {
        if (this.drag) event.preventDefault();
    };

    onTouchMove = (event) => {
        if (this.drag && this.drag.active && event.cancelable) event.preventDefault();
    };

    activateDrag() {
        const d = this.drag;
        if (!d) return;
        d.active = true;
        d.source.classList.add('is-dragging');
        const ghost = this.template.querySelector('.drag-ghost');
        if (ghost) {
            ghost.textContent = d.label;
            ghost.classList.add('drag-ghost_visible');
        }
        if (d.touch && navigator.vibrate) navigator.vibrate(15);
        try {
            d.source.setPointerCapture(d.pointerId);
        } catch (e) {
            /* pointer already released */
        }
        this.updateDrag(d.startX, d.startY);
    }

    updateDrag(x, y) {
        const d = this.drag;
        const ghost = this.template.querySelector('.drag-ghost');
        const span = this.dragMinutes(d);
        const target = this.dropTargetAt(x, y - d.offsetY, d.kind === 'tot' && d.fullDay);
        if (ghost) {
            ghost.style.transform = `translate(${x + 12}px, ${y + 12}px)`;
            ghost.textContent = target ? `${d.label} → ${this.dropLabel(target, d)}` : d.label;
        }
        this.highlightSlot(target && !(d.kind === 'tot' && d.fullDay) ? target : null, span);
        d.target = target;
    }

    dropTargetAt(x, y, dayOnly) {
        const cols = this.template.querySelectorAll('.day-col');
        for (const col of cols) {
            const rect = col.getBoundingClientRect();
            if (x < rect.left || x >= rect.right) continue;
            if (dayOnly) return { day: col.dataset.day, minutes: DAY_START * 60 };
            if (y < rect.top - 28 || y > rect.bottom + 16) return null;
            const yClamped = Math.min(rect.bottom - 1, Math.max(rect.top, y));
            const snapPx = (HOUR_PX * SNAP_MIN) / 60;
            const index = Math.floor((yClamped - rect.top) / snapPx);
            const maxIndex = ((DAY_END - DAY_START) * 60) / SNAP_MIN - 1;
            const minutes = DAY_START * 60 + Math.min(maxIndex, Math.max(0, index)) * SNAP_MIN;
            return { day: col.dataset.day, minutes };
        }
        return null;
    }

    dropLabel(target, d) {
        const start = this.slotDate(target.day, target.minutes);
        const day = start.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric' });
        return d.kind === 'tot' && d.fullDay ? day : `${day} ${formatTime(start)}`;
    }

    highlightSlot(target, minutesLong) {
        const span = minutesLong || CALL_MINUTES;
        const key = target ? `${target.day}|${target.minutes}|${span}` : null;
        if (key === this.highlightKey) return;
        if (this.highlightEl) this.highlightEl.classList.remove('drop-mark_on');
        this.highlightEl = null;
        if (target) {
            const mark = this.template.querySelector(`.drop-mark[data-day="${target.day}"]`);
            if (mark) {
                const top = ((target.minutes - DAY_START * 60) / 60) * HOUR_PX;
                const height = Math.max(16, (span / 60) * HOUR_PX);
                mark.style.top = `${top}px`;
                mark.style.height = `${height}px`;
                mark.classList.add('drop-mark_on');
                this.highlightEl = mark;
            }
        }
        this.highlightKey = key;
    }

    dragMinutes(d) {
        if (!d || !this.data) return CALL_MINUTES;
        if (d.kind === 'call') {
            const call = this.data.calls.find((c) => c.id === d.id);
            if (call) return Math.max(CALL_MINUTES, Math.round((new Date(call.endTime) - new Date(call.startTime)) / 60000));
        }
        if (d.kind === 'tot' && !d.fullDay) {
            const t = this.data.timeOffs.find((x) => x.id === d.id);
            if (t) return Math.max(30, Math.round((new Date(t.endTime) - new Date(t.startTime)) / 60000));
        }
        return CALL_MINUTES;
    }

    autoScroll(y) {
        const scroller = this.template.querySelector('.cal-scroll');
        if (!scroller) return;
        const rect = scroller.getBoundingClientRect();
        if (y < rect.top + AUTO_SCROLL_EDGE) scroller.scrollTop -= 14;
        else if (y > rect.bottom - AUTO_SCROLL_EDGE) scroller.scrollTop += 14;
    }

    endDrag() {
        const d = this.drag;
        if (!d) return;
        clearTimeout(d.timer);
        d.source.classList.remove('is-dragging');
        const ghost = this.template.querySelector('.drag-ghost');
        if (ghost) ghost.classList.remove('drag-ghost_visible');
        this.highlightSlot(null);
        window.removeEventListener('pointermove', this.onDragMove);
        window.removeEventListener('pointerup', this.onDragUp);
        window.removeEventListener('pointercancel', this.onDragCancel);
        window.removeEventListener('contextmenu', this.onDragContextMenu);
        this.drag = undefined;
    }

    clickSuppressed() {
        return Date.now() < (this.suppressClickUntil || 0);
    }

    async commitDrop(d, target) {
        const start = this.slotDate(target.day, target.minutes);
        if (d.kind === 'call') {
            const call = this.data.calls.find((c) => c.id === d.id);
            if (call && new Date(call.startTime).getTime() === start.getTime()) return;
            await this.run(() => rescheduleCall({ callId: d.id, startTime: start.toISOString(), durationMinutes: null }), `Call moved to ${formatDateTime(start)}`);
        } else if (d.kind === 'tot') {
            const t = this.data.timeOffs.find((x) => x.id === d.id);
            if (!t) return;
            const original = new Date(t.startTime);
            if (d.fullDay) {
                if (sameDay(original, start)) return;
                start.setHours(original.getHours(), original.getMinutes(), 0, 0);
            } else if (original.getTime() === start.getTime()) {
                return;
            }
            await this.run(() => moveTimeOff({ timeOffId: d.id, startTime: start.toISOString() }), 'Time off moved');
        } else if (d.kind === 'patient') {
            await this.run(
                () =>
                    scheduleCall({
                        patientId: d.id,
                        startTime: start.toISOString(),
                        durationMinutes: CALL_MINUTES,
                        reason: 'Follow up',
                        direction: 'Outbound',
                        notes: null
                    }),
                `Call planned for ${formatDateTime(start)}`
            );
        }
    }

    handleEventClick(event) {
        event.stopPropagation();
        if (this.clickSuppressed()) return;
        const id = event.currentTarget.dataset.id;
        const call = this.data.calls.find((c) => c.id === id);
        if (!call) return;
        this.selectedCall = {
            ...call,
            when: `${formatDateTime(call.startTime)} – ${formatTime(call.endTime)}`,
            isPlanned: call.status === 'Planned',
            canComplete: call.status === 'Planned' && this.canEdit
        };
        this.rescheduleValue = call.startTime;
        this.completeForm = { status: 'Reached', notes: call.notes || '', transcript: '', followUpDate: null, adverseEvent: false, durationMinutes: CALL_MINUTES, recordingConsent: false };
        this.pendingRecording = null;
        this.showDetailModal = true;
    }

    // ---------------------------------------------------------------- call modals

    get patientOptions() {
        return (this.data ? this.data.patients : []).map((p) => ({ label: `${p.displayName} · ${p.productName || ''}`, value: p.id }));
    }

    get reasonOptions() {
        return this.data ? this.data.reasons : [];
    }

    get outcomeOptions() {
        return this.data ? this.data.outcomes : [];
    }

    get directionOptions() {
        return [
            { label: 'Outbound', value: 'Outbound' },
            { label: 'Inbound', value: 'Inbound' }
        ];
    }

    get durationOptions() {
        return ['5', '10', '15', '20', '30'].map((v) => ({ label: `${v} min`, value: v }));
    }

    openCallModal(patientId, start) {
        this.callForm = {
            patientId: patientId || '',
            startTime: toLocalInput(start),
            duration: String(CALL_MINUTES),
            reason: 'Follow up',
            direction: 'Outbound',
            notes: ''
        };
        this.showCallModal = true;
    }

    handleNewCall() {
        this.openCallModal(null, this.nextFreeSlot());
    }

    handleCallField(event) {
        this.callForm = { ...this.callForm, [event.target.dataset.field]: event.detail.value };
    }

    async saveCall() {
        if (!this.callForm.patientId) {
            this.toast('Select a patient', 'Choose which patient to call.', 'warning');
            return;
        }
        this.saving = true;
        const ok = await this.run(
            () =>
                scheduleCall({
                    patientId: this.callForm.patientId,
                    startTime: this.callForm.startTime,
                    durationMinutes: Number(this.callForm.duration),
                    reason: this.callForm.reason,
                    direction: this.callForm.direction,
                    notes: this.callForm.notes
                }),
            'Call planned'
        );
        this.saving = false;
        if (ok) this.showCallModal = false;
    }

    handleCompleteField(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'toggle' || event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
        this.completeForm = { ...this.completeForm, [field]: value };
    }

    handleRescheduleField(event) {
        this.rescheduleValue = event.detail.value;
    }

    get canDialSelected() {
        return this.selectedCall && this.selectedCall.canComplete && !this.data.masked;
    }

    get recordingHint() {
        if (!this.pendingRecording) return '';
        const kb = Math.round((this.pendingRecording.base64.length * 3) / 4 / 1024);
        return `The call recording (${kb} KB) will be attached when you save the outcome.`;
    }

    openDialer() {
        this.showDetailModal = false;
        this.showDialer = true;
    }

    closeDialer() {
        this.showDialer = false;
        this.showDetailModal = true;
    }

    handleCallComplete(event) {
        const d = event.detail || {};
        this.showDialer = false;
        this.pendingRecording = d.recording || null;
        this.completeForm = {
            ...this.completeForm,
            status: d.status || 'Reached',
            transcript: d.transcript || this.completeForm.transcript,
            durationMinutes: d.durationMinutes || this.completeForm.durationMinutes,
            recordingConsent: d.consent === true,
            language: d.language || this.completeForm.language,
            recordingUrl: d.recordingUrl || null
        };
        this.showDetailModal = true;
        if (d.transcriptError) {
            this.toast('Transcription failed', `${d.transcriptError}. You can type notes or paste a transcript instead.`, 'warning');
        }
    }

    async saveComplete() {
        this.saving = true;
        let analysis;
        const recording = this.pendingRecording;
        const ok = await this.run(async () => {
            analysis = await completeCall({
                callId: this.selectedCall.id,
                payloadJson: JSON.stringify({ ...this.completeForm, durationMinutes: Number(this.completeForm.durationMinutes) || null })
            });
            if (recording && this.completeForm.recordingConsent) {
                try {
                    await attachCallRecording({ callId: this.selectedCall.id, fileName: recording.fileName, base64Data: recording.base64 });
                } catch (e) {
                    this.toast('Recording not saved', reduceError(e), 'warning');
                }
            }
            this.pendingRecording = null;
        }, null);
        this.saving = false;
        if (ok) {
            this.showDetailModal = false;
            this.toast(
                'Call completed',
                analysis && analysis.aiRisk
                    ? `AI analysis: ${analysis.aiRisk} adherence risk. ${analysis.aiNextBestAction || ''}`
                    : 'Outcome saved.',
                analysis && analysis.aiRisk === 'High' ? 'warning' : 'success'
            );
        }
    }

    async saveReschedule() {
        this.saving = true;
        const ok = await this.run(
            () => rescheduleCall({ callId: this.selectedCall.id, startTime: this.rescheduleValue, durationMinutes: null }),
            'Call rescheduled'
        );
        this.saving = false;
        if (ok) this.showDetailModal = false;
    }

    async removeCall() {
        this.saving = true;
        const ok = await this.run(() => deleteCall({ callId: this.selectedCall.id }), 'Call removed');
        this.saving = false;
        if (ok) this.showDetailModal = false;
    }

    openPatient() {
        const patientId = this.selectedCall.patientId;
        this.showDetailModal = false;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Care_Coach_Patients' },
            state: { c__patientId: patientId }
        });
    }

    // ---------------------------------------------------------------- time off

    get timeOffTypeOptions() {
        return this.data ? this.data.timeOffTypes : [];
    }

    get spanOptions() {
        return [
            { label: 'Full day', value: 'Full_Day' },
            { label: 'Partial (hours)', value: 'Hours' }
        ];
    }

    get hourOptions() {
        return HOUR_OPTIONS.map((h) => ({ label: `${h} h`, value: h }));
    }

    get isHours() {
        return this.timeOffForm.spanType === 'Hours';
    }

    get timeOffTitle() {
        return this.timeOffForm.id ? `Time off · ${this.timeOffForm.name || ''}` : 'Request time off';
    }

    get isNewTimeOff() {
        return !this.timeOffForm.id;
    }

    get timeOffEditable() {
        return !this.timeOffForm.id || this.timeOffForm.stage === 'Draft';
    }

    get timeOffLocked() {
        return !this.timeOffEditable;
    }

    get canSubmitTimeOff() {
        return this.timeOffForm.id && this.timeOffForm.stage === 'Draft';
    }

    get canRecallTimeOff() {
        return this.timeOffForm.id && this.timeOffForm.stage === 'Submitted for Approval';
    }

    get canDeleteTimeOff() {
        return this.timeOffForm.id && this.timeOffForm.stage !== 'Approved';
    }

    handleNewTimeOff() {
        const start = new Date(this.rangeStart);
        const today = new Date();
        const base = start < today ? today : start;
        base.setHours(9, 0, 0, 0);
        this.timeOffForm = {
            type: this.timeOffTypeOptions.length ? this.timeOffTypeOptions[0].value : '',
            spanType: 'Full_Day',
            hours: '2',
            startTime: base.toISOString(),
            comments: '',
            submit: true
        };
        this.showTimeOffModal = true;
    }

    handleTimeOffClick(event) {
        event.stopPropagation();
        if (this.clickSuppressed()) return;
        const id = event.currentTarget.dataset.id;
        const t = this.data.timeOffs.find((x) => x.id === id);
        if (!t) return;
        const hours = t.spanType === 'Hours' ? String(Math.max(1, Math.round((new Date(t.endTime) - new Date(t.startTime)) / 3600000))) : '2';
        this.timeOffForm = {
            id: t.id,
            name: t.name,
            stage: t.stage,
            type: t.type,
            spanType: t.spanType === 'Hours' ? 'Hours' : 'Full_Day',
            hours,
            startTime: t.startTime,
            comments: t.comments || '',
            submit: false
        };
        this.showTimeOffModal = true;
    }

    handleTimeOffField(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'toggle' || event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
        this.timeOffForm = { ...this.timeOffForm, [field]: value };
    }

    async saveTimeOff() {
        const f = this.timeOffForm;
        this.saving = true;
        const ok = await this.run(
            () =>
                f.id
                    ? updateTimeOff({
                          timeOffId: f.id,
                          typeValue: f.type,
                          spanType: f.spanType,
                          durationHours: f.spanType === 'Hours' ? f.hours : null,
                          startTime: f.startTime,
                          comments: f.comments
                      })
                    : createTimeOff({
                          typeValue: f.type,
                          spanType: f.spanType,
                          durationHours: f.spanType === 'Hours' ? f.hours : null,
                          startTime: f.startTime,
                          comments: f.comments,
                          submit: f.submit
                      }),
            f.id ? 'Time off updated' : 'Time off requested'
        );
        this.saving = false;
        if (ok) this.showTimeOffModal = false;
    }

    async submitTimeOff() {
        await this.changeTimeOffStage('Submitted for Approval', 'Submitted for approval');
    }

    async recallTimeOff() {
        await this.changeTimeOffStage('Draft', 'Recalled to draft');
    }

    async changeTimeOffStage(stage, message) {
        this.saving = true;
        const ok = await this.run(() => setTimeOffStage({ timeOffId: this.timeOffForm.id, stage }), message);
        this.saving = false;
        if (ok) this.showTimeOffModal = false;
    }

    async removeTimeOff() {
        this.saving = true;
        const ok = await this.run(() => deleteTimeOff({ timeOffId: this.timeOffForm.id }), 'Time off deleted');
        this.saving = false;
        if (ok) this.showTimeOffModal = false;
    }

    // ---------------------------------------------------------------- shared

    closeModals() {
        this.showCallModal = false;
        this.showDetailModal = false;
        this.showTimeOffModal = false;
    }

    async run(fn, successMessage) {
        try {
            await fn();
            if (successMessage) this.toast(successMessage, '', 'success');
            await this.load();
            return true;
        } catch (e) {
            this.toast('Something went wrong', reduceError(e), 'error');
            return false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}