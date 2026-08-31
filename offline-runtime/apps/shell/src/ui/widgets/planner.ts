import { html, nothing, type TemplateResult } from 'lit';
import { ref } from 'lit/directives/ref.js';
import {
  type VisitSummaryDto,
  type AccountSummaryDto,
  type PlannerPayloadDto,
  formatVisitTimeRange,
  estimateRouteKm,
  haversineKm
} from '../apex-cache';
import { createOsrMap, pinKindFromRecordType, type OsrMapHandle } from '../map/osr-leaflet';
import { renderAccountKindBadge } from './account-type';
import {
  fetchDrivingRoute,
  getCurrentPosition,
  type RoutePoint,
  type RouteResult
} from '../map/osr-route';
import { repLocationTracker } from '../../location/rep-location-tracker';
import {
  FILTER_ALL,
  countActiveFilters,
  deriveFilterOptions,
  filterPlannerAccounts,
  type PlannerAccountFilters,
  type PlannerCollection
} from '../planner-accounts';

const DAY_START = 6;
const DAY_END = 24;
/** Match Salesforce fieldRepPlanner: half-hour slots. */
const SLOT_MINUTES = 30;
const PX_PER_MINUTE = 1.25;
const HEADER_H = 48;
const GUTTER_W = 56;
const DEFAULT_VISIT_MS = 60 * 60 * 1000;
const HOURS = Array.from({ length: DAY_END - DAY_START }, (_, i) => DAY_START + i);
const TOUCH_DRAG_THRESHOLD_PX = 12;
const MOUSE_DRAG_THRESHOLD_PX = 4;

const TOT_TYPES = [
  { label: 'Holiday', value: 'Holiday' },
  { label: 'Sick Leave', value: 'Sick Leave' },
  { label: 'Training', value: 'Training' },
  { label: 'Event', value: 'Event' },
  { label: 'Travelling', value: 'Travelling' }
];

const plannerMaps = new WeakMap<Element, OsrMapHandle>();
/** Last mounted planner map (shadow-DOM safe — avoid document.querySelector). */
let activePlannerMap: OsrMapHandle | null = null;
let dragAccountId: string | null = null;
let dragVisitId: string | null = null;
/** True while HTML5 or touch DnD is active — used to let drops hit day columns under events. */
let calendarDndActive = false;
type DragPayload =
  | {
      kind: 'visit';
      id: string;
      durationMs: number;
      nextLat?: number | null;
      nextLon?: number | null;
    }
  | { kind: 'account'; id: string; nextLat?: number | null; nextLon?: number | null };
let dragPayload: DragPayload | null = null;
type TouchDragState = {
  kind: 'account' | 'visit';
  id: string;
  label: string;
  active: boolean;
  startX: number;
  startY: number;
  durationMs?: number;
  nextLat?: number | null;
  nextLon?: number | null;
};
let touchDrag: TouchDragState | null = null;
let touchGhostEl: HTMLElement | null = null;
let touchHighlightEl: HTMLElement | null = null;
let touchListenersBound = false;
let pointerListenersBound = false;
let pointerDragEl: HTMLElement | null = null;
/** Skip visit open click after a drag gesture. */
let suppressVisitClick = false;
let touchLongPressTimer: ReturnType<typeof setTimeout> | null = null;
const TOUCH_LONG_PRESS_MS = 280;
/** Local optimized order for map day (visit ids). */
let routeOrderIds: string[] | null = null;
let routeOrderDayKey: string | null = null;
let routeStatusMessage: string | null = null;
let cachedCurrentLocation: RoutePoint | null = null;
let locationLookupInFlight = false;
let lastRouteGeometry: [number, number][] | null = null;
let lastRouteResult: RouteResult | null = null;

function isoDateLocal(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function startOfSunday(d: Date): Date {
  const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  x.setDate(x.getDate() - x.getDay());
  return x;
}

function parseIso(s: string): Date {
  const [y, m, d] = s.slice(0, 10).split('-').map(Number);
  return new Date(y, m - 1, d);
}

function addDays(d: Date, n: number): Date {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
}

function dateKeyOf(iso?: string): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return String(iso).slice(0, 10);
  return isoDateLocal(d);
}

function minutesFromDayStart(iso?: string): number {
  if (!iso) return 0;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return 0;
  return d.getHours() * 60 + d.getMinutes() - DAY_START * 60;
}

function formatHour(h: number): string {
  const ampm = h >= 12 ? 'PM' : 'AM';
  const hr = h % 12 || 12;
  return `${hr}:00 ${ampm}`;
}

function weekLabel(start: Date): string {
  const end = addDays(start, 6);
  const a = start.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  const b = end.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  return `${a} – ${b}`;
}

/**
 * Map a pointer Y inside an hour cell to a slot start.
 * Uses the cell's real height (not a fixed px/min) and floors to SLOT_MINUTES
 * so a drop near the top of the hour lands on :00 — not :30 from cursor/chip offset.
 */
function slotIsoFromCell(day: Date, hour: number, clientY: number, el: HTMLElement): string {
  const rect = el.getBoundingClientRect();
  const height = Math.max(1, rect.height);
  const y = Math.max(0, Math.min(height, clientY - rect.top));
  const minsInHour = Math.min(
    60 - SLOT_MINUTES,
    Math.floor((y / height) * 60 / SLOT_MINUTES) * SLOT_MINUTES
  );
  const startDt = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, minsInHour, 0, 0);
  return startDt.toISOString();
}

function setDragHotspot(e: DragEvent, el: HTMLElement): void {
  try {
    const rect = el.getBoundingClientRect();
    // Pin cursor to the top of the chip/event so drop Y matches the intended slot.
    e.dataTransfer?.setDragImage(el, Math.min(48, Math.max(12, rect.width / 2)), 6);
  } catch {
    /* setDragImage unsupported in some WebViews — slot floor still helps */
  }
}

function syncCalendarDndClass(root?: ParentNode | null): void {
  const nodes: ParentNode[] = [];
  if (root) nodes.push(root);
  if (typeof document !== 'undefined') nodes.push(document);
  for (const scope of nodes) {
    const canvases = scope.querySelectorAll?.('.calendar-canvas');
    canvases?.forEach((el) => {
      el.classList.toggle('is-dnd-active', calendarDndActive);
    });
  }
}

function clearCalendarDropHighlights(root?: ParentNode | null): void {
  const nodes: ParentNode[] = [];
  if (root) nodes.push(root);
  if (typeof document !== 'undefined') nodes.push(document);
  for (const scope of nodes) {
    scope.querySelectorAll?.('.day-column.calendar-drop-target').forEach((el) => {
      el.classList.remove('calendar-drop-target');
    });
  }
}

function resolveCalendarDropTarget(
  clientX: number,
  clientY: number,
  root?: ParentNode | null
): { day: Date; hour: number; cell: HTMLElement } | null {
  const col = findDayColumnAtPoint(clientX, clientY, root);
  if (!col) return null;
  const dayKey = col.getAttribute('data-day-key') || '';
  const hour = Number(col.getAttribute('data-hour'));
  const [y, m, d] = dayKey.split('-').map(Number);
  if (!dayKey || !Number.isFinite(hour) || !y || !m || !d) return null;
  return { day: new Date(y, m - 1, d), hour, cell: col };
}

function beginHtmlCalendarDrag(
  root: ParentNode,
  payload: DragPayload,
  e: DragEvent,
  el: HTMLElement
): void {
  dragPayload = payload;
  calendarDndActive = true;
  if (payload.kind === 'visit') {
    dragVisitId = payload.id;
    dragAccountId = null;
    if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move';
  } else {
    dragAccountId = payload.id;
    dragVisitId = null;
    if (e.dataTransfer) e.dataTransfer.effectAllowed = 'copy';
  }
  syncCalendarDndClass(root);
  setDragHotspot(e, el);
  el.classList.add('is-dragging');
}

function endHtmlCalendarDrag(root: ParentNode, el: HTMLElement | null, bump?: () => void): void {
  el?.classList.remove('is-dragging');
  calendarDndActive = false;
  dragPayload = null;
  syncCalendarDndClass(root);
  clearCalendarDropHighlights(root);
  setTimeout(() => {
    dragVisitId = null;
    dragAccountId = null;
    bump?.();
  }, 50);
}

function visitDragLocked(v: VisitSummaryDto): boolean {
  const status = String(v.status ?? '').toLowerCase();
  return status === 'completed' || status === 'cancelled';
}

function findDayColumnAtPoint(clientX: number, clientY: number, root?: ParentNode | null): HTMLElement | null {
  const ghostHidden = touchGhostEl?.style.display;
  if (touchGhostEl) touchGhostEl.style.display = 'none';
  let el: Element | null = null;
  const sr = root as ShadowRoot | null | undefined;
  if (sr && typeof sr.elementFromPoint === 'function') {
    el = sr.elementFromPoint(clientX, clientY);
  }
  if (!el && typeof document !== 'undefined') {
    el = document.elementFromPoint(clientX, clientY);
  }
  if (touchGhostEl) touchGhostEl.style.display = ghostHidden ?? '';
  return (el?.closest?.('.day-column') as HTMLElement | null) || null;
}

/** Prefer GPS fix, else last trail point from location sharing. */
function resolveCurrentLocation(): RoutePoint | null {
  if (cachedCurrentLocation) return cachedCurrentLocation;
  const trail = repLocationTracker.getState().lastPoint;
  if (trail && Number.isFinite(trail.latitude) && Number.isFinite(trail.longitude)) {
    return { lat: trail.latitude, lon: trail.longitude };
  }
  return null;
}

function ensureCurrentLocation(bump?: () => void): void {
  if (cachedCurrentLocation || locationLookupInFlight) return;
  locationLookupInFlight = true;
  void getCurrentPosition()
    .then((pos) => {
      if (pos) {
        cachedCurrentLocation = pos;
        bump?.();
      }
    })
    .finally(() => {
      locationLookupInFlight = false;
    });
}

function visitDurationMs(v: VisitSummaryDto): number {
  const start = v.startDateTime ? new Date(v.startDateTime) : null;
  const end = v.endDateTime ? new Date(v.endDateTime) : null;
  if (start && end && !Number.isNaN(start.getTime()) && !Number.isNaN(end.getTime())) {
    return Math.max(SLOT_MINUTES * 60 * 1000, end.getTime() - start.getTime());
  }
  return DEFAULT_VISIT_MS;
}

/**
 * If the drop lands inside an existing visit, push to previous end + drive.
 * Does not rewrite intentional gaps — use "Update route & calendar" to pack a day.
 */
function packDropStartIso(
  dayKey: string,
  rawStartIso: string,
  dayVisits: VisitSummaryDto[],
  opts?: {
    movingVisitId?: string | null;
    nextLat?: number | null;
    nextLon?: number | null;
  }
): string {
  const raw = new Date(rawStartIso);
  if (Number.isNaN(raw.getTime())) return rawStartIso;
  const others = dayVisits
    .filter((v) => v.id && String(v.id) !== String(opts?.movingVisitId || ''))
    .filter((v) => dateKeyOf(v.startDateTime) === dayKey)
    .sort((a, b) => String(a.startDateTime ?? '').localeCompare(String(b.startDateTime ?? '')));

  let cursor = new Date(raw.getTime());
  for (const prev of others) {
    const prevStart = prev.startDateTime ? new Date(prev.startDateTime) : null;
    const prevEnd = prev.endDateTime
      ? new Date(prev.endDateTime)
      : prevStart
        ? new Date(prevStart.getTime() + visitDurationMs(prev))
        : null;
    if (!prevStart || !prevEnd || Number.isNaN(prevEnd.getTime())) continue;

    const insidePrior =
      cursor.getTime() >= prevStart.getTime() && cursor.getTime() < prevEnd.getTime();
    if (!insidePrior) continue;

    let driveMin = 5;
    const plat = Number(prev.accountLatitude);
    const plon = Number(prev.accountLongitude);
    const nlat = Number(opts?.nextLat);
    const nlon = Number(opts?.nextLon);
    if (
      Number.isFinite(plat) &&
      Number.isFinite(plon) &&
      Number.isFinite(nlat) &&
      Number.isFinite(nlon)
    ) {
      driveMin = Math.max(1, Math.round(haversineKm(plat, plon, nlat, nlon) * 1.4));
    }
    cursor = new Date(prevEnd.getTime() + driveMin * 60 * 1000);
  }
  // Keep packed time as prevEnd+drive (minute precision). Raw drops are already slotted.
  cursor.setSeconds(0, 0);
  return cursor.toISOString();
}

function clearTouchHighlight(): void {
  if (touchHighlightEl) {
    touchHighlightEl.classList.remove('calendar-drop-target');
    touchHighlightEl = null;
  }
}

function removeTouchGhost(): void {
  touchGhostEl?.remove();
  touchGhostEl = null;
}

function showTouchGhost(label: string, x: number, y: number): void {
  if (!touchGhostEl) {
    touchGhostEl = document.createElement('div');
    touchGhostEl.className = 'touch-drag-ghost';
    // Inline styles — ghost lives on document.body; planner CSS is shadow-scoped.
    Object.assign(touchGhostEl.style, {
      position: 'fixed',
      zIndex: '10001',
      pointerEvents: 'none',
      transform: 'translate(-50%, -120%)',
      maxWidth: '14rem',
      padding: '0.5rem 0.625rem',
      borderRadius: '0.375rem',
      background: '#fff',
      border: '1px solid #0176d3',
      boxShadow: '0 4px 12px rgba(1, 118, 211, 0.25)',
      fontSize: '0.75rem',
      fontWeight: '600',
      color: '#181818'
    });
    document.body.appendChild(touchGhostEl);
  }
  touchGhostEl.textContent = label;
  touchGhostEl.style.left = `${x}px`;
  touchGhostEl.style.top = `${y}px`;
}

function teardownTouchDrag(bump?: () => void): void {
  if (touchLongPressTimer != null) {
    clearTimeout(touchLongPressTimer);
    touchLongPressTimer = null;
  }
  if (touchListenersBound) {
    document.removeEventListener('touchmove', onDocumentTouchMove);
    document.removeEventListener('touchend', onDocumentTouchEnd);
    document.removeEventListener('touchcancel', onDocumentTouchEnd);
    touchListenersBound = false;
  }
  if (pointerListenersBound) {
    document.removeEventListener('pointermove', onDocumentPointerMove);
    document.removeEventListener('pointerup', onDocumentPointerUp);
    document.removeEventListener('pointercancel', onDocumentPointerUp);
    pointerListenersBound = false;
  }
  pointerDragEl?.classList.remove('is-dragging');
  pointerDragEl = null;
  removeTouchGhost();
  clearTouchHighlight();
  touchDrag = null;
  calendarDndActive = false;
  dragPayload = null;
  dragAccountId = null;
  dragVisitId = null;
  syncCalendarDndClass(touchDropContext?.root);
  clearCalendarDropHighlights(touchDropContext?.root);
  bump?.();
}

function finishCalendarDragAt(clientX: number, clientY: number): void {
  const ctx = touchDropContext;
  const state = touchDrag;
  if (!state?.active || !ctx || ctx.isReadOnly) return;
  const col = findDayColumnAtPoint(clientX, clientY, ctx.root);
  if (!col) return;
  const dayKey = col.getAttribute('data-day-key') || '';
  const hour = Number(col.getAttribute('data-hour'));
  const [y, m, d] = dayKey.split('-').map(Number);
  if (!dayKey || !Number.isFinite(hour) || !y || !m || !d) return;
  const dropped = applyPlannerCalendarDrop({
    day: new Date(y, m - 1, d),
    hour,
    clientY,
    cell: col,
    visits: ctx.visits,
    allAccounts: ctx.allAccounts,
    isReadOnly: ctx.isReadOnly,
    selectedAccountId: ctx.selectedAccountId,
    accountIdHint: state.kind === 'account' ? state.id : null,
    visitIdHint: state.kind === 'visit' ? state.id : null,
    onRescheduleVisit: ctx.onRescheduleVisit,
    onCreateDraft: ctx.onCreateDraft,
    onOpenPlanChoice: ctx.onOpenPlanChoice,
    onSelectAccount: ctx.onSelectAccount
  });
  if (dropped) suppressVisitClick = true;
}

type CalendarDropOpts = {
  day: Date;
  hour: number;
  clientY: number;
  cell: HTMLElement;
  visits: VisitSummaryDto[];
  allAccounts: AccountSummaryDto[];
  isReadOnly: boolean;
  selectedAccountId?: string | null;
  accountIdHint?: string | null;
  visitIdHint?: string | null;
  onRescheduleVisit?: (visitId: string, startIso: string, endIso: string) => void;
  onCreateDraft?: (accountId: string, startIso: string) => void;
  onOpenPlanChoice?: (startIso: string) => void;
  onSelectAccount?: (id: string | null) => void;
};

function applyPlannerCalendarDrop(args: CalendarDropOpts): boolean {
  if (args.isReadOnly) return false;
  const rawStartIso = slotIsoFromCell(args.day, args.hour, args.clientY, args.cell);
  const dayKey = isoDateLocal(args.day);
  const dayVisitsForPack = args.visits.filter((v) => dateKeyOf(v.startDateTime) === dayKey);
  const visitId =
    args.visitIdHint ||
    dragVisitId ||
    (dragPayload?.kind === 'visit' ? dragPayload.id : '') ||
    '';
  if (visitId && args.onRescheduleVisit) {
    const existing = args.visits.find((v) => String(v.id) === visitId);
    const oldStart = existing?.startDateTime ? new Date(existing.startDateTime) : null;
    const oldEnd = existing?.endDateTime ? new Date(existing.endDateTime) : null;
    const payloadDur = dragPayload?.kind === 'visit' ? dragPayload.durationMs : undefined;
    const durMs =
      payloadDur ??
      (oldStart && oldEnd && !Number.isNaN(oldStart.getTime())
        ? Math.max(SLOT_MINUTES * 60 * 1000, oldEnd.getTime() - oldStart.getTime())
        : DEFAULT_VISIT_MS);
    const startIso = packDropStartIso(dayKey, rawStartIso, dayVisitsForPack, {
      movingVisitId: visitId,
      nextLat: existing?.accountLatitude,
      nextLon: existing?.accountLongitude
    });
    const newStart = new Date(startIso);
    const newEnd = new Date(newStart.getTime() + durMs);
    args.onRescheduleVisit(visitId, newStart.toISOString(), newEnd.toISOString());
    dragVisitId = null;
    dragAccountId = null;
    return true;
  }
  const accountId =
    args.accountIdHint ||
    dragAccountId ||
    args.selectedAccountId ||
    '';
  if (accountId && args.onCreateDraft) {
    const account = args.allAccounts.find((a) => String(a.id) === String(accountId));
    const startIso = packDropStartIso(dayKey, rawStartIso, dayVisitsForPack, {
      nextLat: account?.latitude,
      nextLon: account?.longitude
    });
    args.onSelectAccount?.(String(accountId));
    args.onCreateDraft(String(accountId), startIso);
    dragAccountId = null;
    dragVisitId = null;
    return true;
  }
  if (args.onOpenPlanChoice) {
    args.onOpenPlanChoice(rawStartIso);
    return true;
  }
  return false;
}

/** Bound once while a touch-drag is active; closed over latest drop context via module vars. */
let touchDropContext: {
  visits: VisitSummaryDto[];
  allAccounts: AccountSummaryDto[];
  isReadOnly: boolean;
  selectedAccountId?: string | null;
  onRescheduleVisit?: CalendarDropOpts['onRescheduleVisit'];
  onCreateDraft?: CalendarDropOpts['onCreateDraft'];
  onOpenPlanChoice?: CalendarDropOpts['onOpenPlanChoice'];
  onSelectAccount?: CalendarDropOpts['onSelectAccount'];
  bump?: () => void;
  root?: ParentNode | null;
} | null = null;

function onDocumentTouchMove(event: TouchEvent): void {
  if (!touchDrag) return;
  const touch = event.touches?.[0];
  if (!touch) return;
  const dx = touch.clientX - touchDrag.startX;
  const dy = touch.clientY - touchDrag.startY;
  const dist = Math.hypot(dx, dy);

  // Still waiting for long-press: any real movement means the user is scrolling — cancel.
  if (!touchDrag.active) {
    if (dist >= TOUCH_DRAG_THRESHOLD_PX) {
      teardownTouchDrag(touchDropContext?.bump);
    }
    return;
  }

  event.preventDefault();
  showTouchGhost(touchDrag.label, touch.clientX, touch.clientY);
  clearTouchHighlight();
  const col = findDayColumnAtPoint(touch.clientX, touch.clientY, touchDropContext?.root);
  if (col) {
    col.classList.add('calendar-drop-target');
    touchHighlightEl = col;
  }
}

function onDocumentTouchEnd(event: TouchEvent): void {
  if (!touchDrag) {
    teardownTouchDrag(touchDropContext?.bump);
    return;
  }
  const wasActive = touchDrag.active;
  const touch = event.changedTouches?.[0];
  const ctx = touchDropContext;
  if (wasActive && touch && ctx && !ctx.isReadOnly) {
    finishCalendarDragAt(touch.clientX, touch.clientY);
  }
  teardownTouchDrag(ctx?.bump);
}

function onDocumentPointerMove(event: PointerEvent): void {
  if (!touchDrag) return;
  const dx = event.clientX - touchDrag.startX;
  const dy = event.clientY - touchDrag.startY;
  const dist = Math.hypot(dx, dy);

  if (!touchDrag.active) {
    if (event.pointerType === 'mouse') {
      if (dist >= MOUSE_DRAG_THRESHOLD_PX) activateTouchDrag();
    } else if (dist >= TOUCH_DRAG_THRESHOLD_PX) {
      teardownTouchDrag(touchDropContext?.bump);
    }
    return;
  }

  event.preventDefault();
  showTouchGhost(touchDrag.label, event.clientX, event.clientY);
  clearTouchHighlight();
  const col = findDayColumnAtPoint(event.clientX, event.clientY, touchDropContext?.root);
  if (col) {
    col.classList.add('calendar-drop-target');
    touchHighlightEl = col;
  }
}

function onDocumentPointerUp(event: PointerEvent): void {
  if (!touchDrag) {
    teardownTouchDrag(touchDropContext?.bump);
    return;
  }
  const wasActive = touchDrag.active;
  const ctx = touchDropContext;
  if (wasActive && ctx && !ctx.isReadOnly) {
    finishCalendarDragAt(event.clientX, event.clientY);
  }
  teardownTouchDrag(ctx?.bump);
}

function beginVisitPointerDrag(
  e: PointerEvent,
  state: TouchDragState,
  ctx: NonNullable<typeof touchDropContext>,
  el: HTMLElement
): void {
  if (e.button !== 0) return;
  teardownTouchDrag();
  touchDrag = state;
  touchDropContext = ctx;
  pointerDragEl = el;
  try {
    el.setPointerCapture(e.pointerId);
  } catch {
    /* ignore */
  }
  if (!pointerListenersBound) {
    document.addEventListener('pointermove', onDocumentPointerMove, { passive: false });
    document.addEventListener('pointerup', onDocumentPointerUp);
    document.addEventListener('pointercancel', onDocumentPointerUp);
    pointerListenersBound = true;
  }
  // Touch: long-press then drag. Mouse: drag after a small move threshold.
  if (e.pointerType !== 'mouse') {
    touchLongPressTimer = setTimeout(() => activateTouchDrag(), TOUCH_LONG_PRESS_MS);
  }
}

function activateTouchDrag(): void {
  if (!touchDrag || touchDrag.active) return;
  touchLongPressTimer = null;
  touchDrag = { ...touchDrag, active: true };
  calendarDndActive = true;
  if (touchDrag.kind === 'account') {
    dragAccountId = touchDrag.id;
    dragPayload = {
      kind: 'account',
      id: touchDrag.id,
      nextLat: touchDrag.nextLat,
      nextLon: touchDrag.nextLon
    };
  } else {
    dragVisitId = touchDrag.id;
    dragPayload = {
      kind: 'visit',
      id: touchDrag.id,
      durationMs: touchDrag.durationMs ?? DEFAULT_VISIT_MS,
      nextLat: touchDrag.nextLat,
      nextLon: touchDrag.nextLon
    };
  }
  pointerDragEl?.classList.add('is-dragging');
  showTouchGhost(touchDrag.label, touchDrag.startX, touchDrag.startY);
  syncCalendarDndClass(touchDropContext?.root);
  // Re-render only for account sidebar touch state — visit drag must not re-render mid-gesture.
  if (touchDrag.kind === 'account') touchDropContext?.bump?.();
}

function beginTouchDrag(
  state: TouchDragState,
  ctx: NonNullable<typeof touchDropContext>
): void {
  teardownTouchDrag();
  touchDrag = state;
  touchDropContext = ctx;
  if (!touchListenersBound) {
    document.addEventListener('touchmove', onDocumentTouchMove, { passive: false });
    document.addEventListener('touchend', onDocumentTouchEnd);
    document.addEventListener('touchcancel', onDocumentTouchEnd);
    touchListenersBound = true;
  }
  touchLongPressTimer = setTimeout(() => activateTouchDrag(), TOUCH_LONG_PRESS_MS);
}

async function drawRouteForVisits(
  handle: OsrMapHandle,
  ordered: VisitSummaryDto[],
  bump: () => void,
  labelPrefix: string
): Promise<void> {
  const stops = ordered.filter(
    (v) => Number.isFinite(Number(v.accountLatitude)) && Number.isFinite(Number(v.accountLongitude))
  );
  const me = resolveCurrentLocation();
  const points: RoutePoint[] = [
    ...(me ? [me] : []),
    ...stops.map((v) => ({ lat: Number(v.accountLatitude), lon: Number(v.accountLongitude) }))
  ];
  if (points.length < 2) {
    handle.setRoute(null);
    lastRouteGeometry = null;
    lastRouteResult = null;
    routeStatusMessage = `${labelPrefix} · need location + stops to draw route`;
    bump();
    return;
  }
  const result = await fetchDrivingRoute(points);
  if (!result) {
    handle.setRoute(null);
    routeStatusMessage = `${labelPrefix} · could not compute route`;
    bump();
    return;
  }
  lastRouteGeometry = result.latLngs;
  lastRouteResult = result;
  handle.setRoute(result.latLngs, { fit: true });
  const via = result.source === 'osrm' ? 'road' : 'estimate';
  routeStatusMessage = `${labelPrefix} · ${result.distanceKm} km · ~${result.durationMin} min (${via})`;
  bump();
}

export function renderFidelityPlanner(opts: {
  label: string;
  week: PlannerPayloadDto | null;
  accounts: AccountSummaryDto[] | null;
  totalAccounts?: number;
  weekStart?: string;
  mode?: 'calendar' | 'map';
  search?: string;
  selectedAccountId?: string | null;
  mapDay?: string;
  cached?: boolean;
  planChoiceSlot?: string | null;
  visitDetailId?: string | null;
  totModalStart?: string | null;
  promoModalStart?: string | null;
  promotionalProjects?: { id: string; name: string }[];
  viewer?: Record<string, unknown> | null;
  selectedContextUserId?: string | null;
  accountFilters?: PlannerAccountFilters;
  filterPanelOpen?: boolean;
  collections?: PlannerCollection[];
  selectedCollectionId?: string | null;
  saveCollectionOpen?: boolean;
  onOpenAccount?: (id: string) => void;
  onOpenVisit?: (id: string) => void;
  onWeekChange?: (weekStart: string) => void;
  onMode?: (m: 'calendar' | 'map') => void;
  onSearch?: (q: string) => void;
  onSelectAccount?: (id: string | null) => void;
  onCreateDraft?: (accountId: string, startIso: string) => void;
  onOpenPlanChoice?: (startIso: string) => void;
  onClosePlanChoice?: () => void;
  onOpenTotModal?: (startIso: string) => void;
  onCloseTotModal?: () => void;
  onOpenPromoModal?: (startIso: string) => void;
  onClosePromoModal?: () => void;
  onCloseVisitDetail?: () => void;
  onSaveVisitDetail?: (visitId: string, status: string, cancellationReason: string) => void;
  onPostponeVisit?: (visitId: string) => void;
  onRemoveVisit?: (visitId: string) => void;
  onViewVisit?: (visitId: string) => void;
  onCreateTimeOff?: (input: {
    startIso: string;
    typeValue: string;
    spanType: string;
    durationHours?: string;
    comments?: string;
  }) => void;
  onCreatePromo?: (projectId: string, startIso: string) => void;
  onToggleFilterPanel?: () => void;
  onCloseFilterPanel?: () => void;
  onSetAccountFilters?: (filters: PlannerAccountFilters) => void;
  onClearAccountFilters?: () => void;
  onSelectCollection?: (id: string | null) => void;
  onOpenSaveCollection?: () => void;
  onCloseSaveCollection?: () => void;
  onSaveCollection?: (name: string, accountIds: string[], filters: PlannerAccountFilters) => void;
  onDeleteCollection?: (id: string) => void;
  onAddAccountToCollection?: (collectionId: string, accountId: string) => void;
  onMapDayChange?: (dayKey: string) => void;
  onReorderDayVisits?: (
    orderedVisitIds: string[],
    dayKey: string,
    legs?: { distanceKm: number; durationMin: number }[]
  ) => void;
  onRescheduleVisit?: (visitId: string, startIso: string, endIso: string) => void;
  onContextUserChange?: (userId: string | null) => void;
  requestUpdate?: () => void;
}): TemplateResult {
  const bump = () => opts.requestUpdate?.();
  const start = opts.weekStart ? parseIso(opts.weekStart) : startOfSunday(new Date());
  const days = Array.from({ length: 7 }, (_, i) => addDays(start, i));
  const visits = opts.week?.visits ?? [];
  const tots = (opts.week?.timeOffBlocks as { startDateTime?: string; endDateTime?: string; name?: string }[]) ?? [];
  const mode = opts.mode ?? 'calendar';
  const todayKey = isoDateLocal(new Date());
  const viewer = opts.viewer ?? {};
  const canSwitchView = viewer.canSwitchView === true;
  const defaultUserId = String(viewer.defaultUserId ?? '');
  const selectedUserId = opts.selectedContextUserId || defaultUserId;
  const isViewingSelf = !selectedUserId || selectedUserId === defaultUserId;
  const isReadOnly = canSwitchView && !isViewingSelf;
  const viewerOptions = Array.isArray(viewer.options)
    ? (viewer.options as { userId?: string; label?: string; userName?: string }[])
    : [];
  const selectedViewerLabel =
    viewerOptions.find((o) => o.userId === selectedUserId)?.label ||
    viewerOptions.find((o) => o.userId === selectedUserId)?.userName ||
    '';
  const territoryBadge =
    viewer.viewerMode === 'admin' && viewer.topTerritoryName
      ? String(viewer.topTerritoryName)
      : '';
  const filters: PlannerAccountFilters = {
    searchTerm: opts.search ?? '',
    recordType: opts.accountFilters?.recordType ?? FILTER_ALL,
    specialty: opts.accountFilters?.specialty ?? FILTER_ALL,
    classification: opts.accountFilters?.classification ?? FILTER_ALL,
    brickId: opts.accountFilters?.brickId ?? FILTER_ALL
  };
  const allAccounts = opts.accounts ?? [];
  const collections = opts.collections ?? [];
  // Keep touch-drop callbacks current across re-renders while a gesture is in flight.
  touchDropContext = {
    visits,
    allAccounts,
    isReadOnly,
    selectedAccountId: opts.selectedAccountId,
    onRescheduleVisit: opts.onRescheduleVisit,
    onCreateDraft: opts.onCreateDraft,
    onOpenPlanChoice: opts.onOpenPlanChoice,
    onSelectAccount: opts.onSelectAccount,
    bump,
    root: touchDropContext?.root ?? null
  };
  const selectedCollection =
    opts.selectedCollectionId
      ? collections.find((c) => c.id === opts.selectedCollectionId) ?? null
      : null;
  const filterOptions = deriveFilterOptions(allAccounts);
  const activeFilterCount = countActiveFilters(filters);
  const accounts = filterPlannerAccounts(allAccounts, filters, selectedCollection);
  const mapDayKey = opts.mapDay ?? todayKey;
  if (routeOrderDayKey !== mapDayKey) {
    routeOrderIds = null;
    routeOrderDayKey = mapDayKey;
    routeStatusMessage = null;
    lastRouteGeometry = null;
    lastRouteResult = null;
  }
  let dayVisits = visits.filter((v) => dateKeyOf(v.startDateTime) === mapDayKey);
  if (routeOrderIds?.length) {
    const byId = new Map(dayVisits.map((v) => [String(v.id), v]));
    const ordered = routeOrderIds.map((id) => byId.get(id)).filter(Boolean) as VisitSummaryDto[];
    const rest = dayVisits.filter((v) => !routeOrderIds!.includes(String(v.id)));
    dayVisits = [...ordered, ...rest];
  }
  const dayRoute = estimateRouteKm(dayVisits);
  const currentLocation = resolveCurrentLocation();
  if (mode === 'map') ensureCurrentLocation(bump);
  const mapDayOptions = days.map((d) => {
    const key = isoDateLocal(d);
    const count = visits.filter((v) => dateKeyOf(v.startDateTime) === key).length;
    const label = d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
    return { value: key, label: `${label} (${count})` };
  });
  const dayHeight = (DAY_END - DAY_START) * 60 * PX_PER_MINUTE;
  const canvasHeight = HEADER_H + dayHeight;
  const detailVisit = opts.visitDetailId
    ? visits.find((v) => String(v.id) === opts.visitDetailId)
    : undefined;

  const mountMap = (el: Element | undefined) => {
    if (mode !== 'map') {
      if (activePlannerMap) {
        activePlannerMap.destroy();
        activePlannerMap = null;
      }
      return;
    }
    // Lit calls ref(undefined) before every re-render; do not destroy the map there.
    if (!(el instanceof HTMLElement)) return;
    const markers = [
      ...(currentLocation
        ? [
            {
              id: 'current-location',
              lat: currentLocation.lat,
              lon: currentLocation.lon,
              label: 'Current location',
              kind: 'you' as const
            }
          ]
        : []),
      ...dayVisits
        .filter((v) => Number.isFinite(Number(v.accountLatitude)) && Number.isFinite(Number(v.accountLongitude)))
        .map((v) => ({
          id: String(v.id),
          lat: Number(v.accountLatitude),
          lon: Number(v.accountLongitude),
          label: v.accountName || v.name,
          kind: pinKindFromRecordType(v.accountRecordTypeName, v.accountRecordTypeDeveloperName)
        }))
    ];
    let handle = plannerMaps.get(el);
    if (handle && !handle.isAlive()) {
      plannerMaps.delete(el);
      handle = undefined;
    }
    if (!handle) {
      handle = createOsrMap(el, { fitBounds: true });
      plannerMaps.set(el, handle);
    }
    activePlannerMap = handle;
    handle.setMarkers(markers);
    if (lastRouteGeometry?.length) {
      handle.setRoute(lastRouteGeometry, { fit: false });
    } else {
      handle.setRoute(null);
    }
    handle.invalidateSize();
  };

  return html`
    <section class="osr-lwc-mirror planner-shell slds-card">
      <header class="planner-card-title">
        <h2>${opts.label || 'Field Rep Planner'}</h2>
        ${opts.cached ? html`<span class="osr-cache-pill">Cached</span>` : nothing}
      </header>
      ${opts.cached
        ? html`<div class="slds-notify slds-notify_alert slds-theme_alert-texture slds-theme_info slds-m-around_x-small">
            Showing cached planner from device
          </div>`
        : nothing}
      <div class="planner-toolbar">
        ${canSwitchView
          ? html`
              <select
                class="planner-viewer-combobox slds-select"
                aria-label="View planner for"
                style="width:auto;min-width:12rem"
                .value=${selectedUserId}
                @change=${(e: Event) => {
                  opts.onContextUserChange?.((e.target as HTMLSelectElement).value || null);
                }}
              >
                <option value=${defaultUserId}>My planner</option>
                ${viewerOptions.map(
                  (o) =>
                    html`<option value=${o.userId || ''}>
                      ${o.label || o.userName || o.userId}
                    </option>`
                )}
              </select>
              ${territoryBadge
                ? html`<span class="planner-territory-badge">${territoryBadge}</span>`
                : nothing}
            `
          : nothing}
        <div class="week-nav">
          <button
            type="button"
            class="slds-button slds-button_neutral"
            @click=${() => opts.onWeekChange?.(isoDateLocal(addDays(start, -7)))}
          >
            ‹
          </button>
          <button
            type="button"
            class="slds-button slds-button_neutral"
            @click=${() => opts.onWeekChange?.(isoDateLocal(startOfSunday(new Date())))}
          >
            Today
          </button>
          <button
            type="button"
            class="slds-button slds-button_neutral"
            @click=${() => opts.onWeekChange?.(isoDateLocal(addDays(start, 7)))}
          >
            ›
          </button>
        </div>
        <div class="slds-text-heading_small slds-m-left_small week-label">${weekLabel(start)}</div>
        <div class="slds-col_bump-left toolbar-view-actions">
          <button
            type="button"
            class="planning-plus-btn"
            title="Add TOT or promotional event"
            ?disabled=${isReadOnly}
            @click=${() => {
              if (isReadOnly) return;
              const d = parseIso(mapDayKey);
              d.setHours(9, 0, 0, 0);
              opts.onOpenPlanChoice?.(d.toISOString());
            }}
          >
            +
          </button>
          <div class="view-mode-switch" role="group" aria-label="Planner view">
            <button
              type="button"
              class="view-mode-switch__btn ${mode === 'calendar' ? 'is-active' : ''}"
              title="Calendar"
              aria-pressed=${mode === 'calendar'}
              aria-label="Calendar view"
              @click=${() => opts.onMode?.('calendar')}
            >
              <svg class="view-mode-switch__icon" viewBox="0 0 52 52" aria-hidden="true">
                <path
                  fill="currentColor"
                  d="M46.5 9H41V5.5A1.5 1.5 0 0 0 39.5 4h-3A1.5 1.5 0 0 0 35 5.5V9H17V5.5A1.5 1.5 0 0 0 15.5 4h-3A1.5 1.5 0 0 0 11 5.5V9H5.5A3.5 3.5 0 0 0 2 12.5v32A3.5 3.5 0 0 0 5.5 48h41a3.5 3.5 0 0 0 3.5-3.5v-32A3.5 3.5 0 0 0 46.5 9zM44 43H8V21h36z"
                />
              </svg>
              <span class="view-mode-switch__label">Calendar</span>
            </button>
            <button
              type="button"
              class="view-mode-switch__btn ${mode === 'map' ? 'is-active' : ''}"
              title="Map & Route"
              aria-pressed=${mode === 'map'}
              aria-label="Map and route view"
              @click=${() => opts.onMode?.('map')}
            >
              <svg class="view-mode-switch__icon" viewBox="0 0 52 52" aria-hidden="true">
                <path
                  fill="currentColor"
                  d="M38 4a14 14 0 0 0-14 14c0 10.5 14 30 14 30s14-19.5 14-30A14 14 0 0 0 38 4zm0 19a5 5 0 1 1 0-10 5 5 0 0 1 0 10zM8 20l12 4v24L8 44zm16 5.2 12-4.2v23.4l-12 4.2z"
                />
              </svg>
              <span class="view-mode-switch__label">Map</span>
            </button>
          </div>
        </div>
      </div>
      <div
        class="planner-map-toolbar ${mode === 'map' ? 'is-open' : ''}"
        aria-hidden=${mode !== 'map'}
      >
        <select
          class="slds-select map-toolbar-day"
          aria-label="Map day"
          ?disabled=${mode !== 'map'}
          .value=${mapDayKey}
          @change=${(e: Event) => {
            const key = (e.target as HTMLSelectElement).value;
            routeOrderIds = null;
            routeStatusMessage = null;
            lastRouteGeometry = null;
            lastRouteResult = null;
            opts.onMapDayChange?.(key);
            bump();
          }}
        >
          ${mapDayOptions.map((o) => html`<option value=${o.value}>${o.label}</option>`)}
        </select>
        <button
          type="button"
          class="slds-button slds-button_brand"
          ?disabled=${isReadOnly ||
          mode !== 'map' ||
          dayVisits.filter(
            (v) =>
              Number.isFinite(Number(v.accountLatitude)) &&
              Number.isFinite(Number(v.accountLongitude))
          ).length < 1}
          @click=${() => {
            if (isReadOnly || mode !== 'map') return;
            const ordered = nearestNeighborOrder(dayVisits);
            routeOrderIds = ordered.map((v) => String(v.id));
            routeOrderDayKey = mapDayKey;
            if (activePlannerMap) {
              void drawRouteForVisits(activePlannerMap, ordered, bump, 'Built route');
            } else {
              const next = estimateRouteKm(ordered);
              routeStatusMessage = `Built route · ${next.km} km · ~${next.minutes} min`;
              bump();
            }
          }}
        >
          Build Route
        </button>
        <button
          type="button"
          class="slds-button slds-button_neutral"
          ?disabled=${isReadOnly ||
          mode !== 'map' ||
          dayVisits.filter(
            (v) =>
              Number.isFinite(Number(v.accountLatitude)) &&
              Number.isFinite(Number(v.accountLongitude))
          ).length < 2}
          @click=${() => {
            if (isReadOnly || mode !== 'map') return;
            const ordered = bestNearestNeighbor(dayVisits);
            routeOrderIds = ordered.map((v) => String(v.id));
            routeOrderDayKey = mapDayKey;
            const before = dayRoute;
            const savedHint = Math.max(0, before.minutes - estimateRouteKm(ordered).minutes);
            if (activePlannerMap) {
              void drawRouteForVisits(
                activePlannerMap,
                ordered,
                bump,
                `Optimized · saved ~${savedHint} min`
              );
            } else {
              const next = estimateRouteKm(ordered);
              routeStatusMessage = `Optimized · ${next.km} km · saved ~${savedHint} min`;
              bump();
            }
          }}
        >
          Optimize Route
        </button>
        <button
          type="button"
          class="slds-button slds-button_success"
          ?disabled=${isReadOnly || mode !== 'map' || !routeOrderIds?.length}
          @click=${() => {
            if (isReadOnly || mode !== 'map' || !routeOrderIds?.length) return;
            opts.onReorderDayVisits?.(routeOrderIds, mapDayKey, lastRouteResult?.legs);
            routeStatusMessage = 'Route applied to calendar times';
            bump();
          }}
        >
          Update route &amp; calendar
        </button>
      </div>
      ${isReadOnly
        ? html`<div class="planner-readonly-banner">
            Viewing ${selectedViewerLabel || 'another rep'}'s planner (read-only)
          </div>`
        : nothing}
      ${routeStatusMessage && mode === 'map'
        ? html`<div class="slds-notify slds-notify_alert slds-theme_info slds-m-around_x-small">
            ${routeStatusMessage} · current estimate ${dayRoute.km} km / ${dayRoute.minutes} min
          </div>`
        : nothing}

      <div class="planner-body">
        <aside class="planner-sidebar">
          <div class="sidebar-section-title">Accounts — drag to calendar</div>
          <div class="slds-p-horizontal_small slds-p-bottom_x-small account-filters">
            <div class="account-filters-toolbar" style="display:flex;gap:0.5rem;align-items:flex-start">
              <input
                class="account-search account-search-input"
                type="search"
                placeholder="Search accounts…"
                .value=${opts.search ?? ''}
                @input=${(e: Event) => opts.onSearch?.((e.target as HTMLInputElement).value)}
              />
              <button
                type="button"
                class="filter-funnel-btn ${opts.filterPanelOpen ? 'is-open' : ''} ${
                  activeFilterCount > 0 ? 'has-active-filters' : ''
                }"
                title="Filter accounts"
                @click=${() => opts.onToggleFilterPanel?.()}
              >
                ☰
                ${activeFilterCount > 0
                  ? html`<span class="filter-funnel-badge">${activeFilterCount}</span>`
                  : nothing}
              </button>
            </div>
            <div class="account-count-label">
              Showing ${Math.min(accounts.length, 50)} of ${opts.totalAccounts ?? allAccounts.length}
            </div>
            ${activeFilterCount > 0
              ? html`
                  <div class="active-filter-row" style="display:flex;flex-wrap:wrap;gap:0.35rem;margin-top:0.35rem">
                    ${filters.recordType && filters.recordType !== FILTER_ALL
                      ? html`<span class="active-filter-chip">${filters.recordType}</span>`
                      : nothing}
                    ${filters.specialty && filters.specialty !== FILTER_ALL
                      ? html`<span class="active-filter-chip">${filters.specialty}</span>`
                      : nothing}
                    ${filters.classification && filters.classification !== FILTER_ALL
                      ? html`<span class="active-filter-chip">Class ${filters.classification}</span>`
                      : nothing}
                    ${filters.brickId && filters.brickId !== FILTER_ALL
                      ? html`<span class="active-filter-chip">${
                          filterOptions.bricks.find((b) => b.value === filters.brickId)?.label ||
                          'Brick'
                        }</span>`
                      : nothing}
                    <button
                      type="button"
                      class="clear-filters-link"
                      @click=${() => opts.onClearAccountFilters?.()}
                    >
                      Clear
                    </button>
                  </div>
                `
              : nothing}
            ${accounts.length > 0
              ? html`
                  <button
                    type="button"
                    class="save-collection-link"
                    @click=${() => opts.onOpenSaveCollection?.()}
                  >
                    Save filter as list
                  </button>
                `
              : nothing}
          </div>
          <div class="account-collections">
            <div class="sidebar-section-title collections-section-title">My lists</div>
            <div class="collection-chips-row">
              <button
                type="button"
                class="collection-chip ${!selectedCollection ? 'is-active collection-chip-active' : ''}"
                @click=${() => opts.onSelectCollection?.(null)}
              >
                All accounts
              </button>
              ${collections.map(
                (col) => html`
                  <button
                    type="button"
                    class="collection-chip ${selectedCollection?.id === col.id
                      ? 'is-active collection-chip-active'
                      : ''}"
                    @dragover=${(e: DragEvent) => {
                      e.preventDefault();
                      (e.currentTarget as HTMLElement).classList.add('collection-chip-drop-target');
                    }}
                    @dragleave=${(e: DragEvent) => {
                      (e.currentTarget as HTMLElement).classList.remove('collection-chip-drop-target');
                    }}
                    @drop=${(e: DragEvent) => {
                      e.preventDefault();
                      (e.currentTarget as HTMLElement).classList.remove('collection-chip-drop-target');
                      const accountId =
                        dragAccountId || e.dataTransfer?.getData('text/plain') || '';
                      if (accountId) opts.onAddAccountToCollection?.(col.id, accountId);
                      dragAccountId = null;
                    }}
                    @click=${() => opts.onSelectCollection?.(col.id)}
                  >
                    ${col.name}
                  </button>
                `
              )}
            </div>
            ${selectedCollection
              ? html`
                  <div class="collection-actions">
                    <button
                      type="button"
                      class="delete-collection-link"
                      @click=${() => opts.onDeleteCollection?.(selectedCollection.id)}
                    >
                      Delete list
                    </button>
                  </div>
                `
              : nothing}
          </div>
          <div class="account-list">
            ${accounts.length === 0
              ? html`<div class="slds-p-around_small slds-text-color_weak">
                  ${allAccounts.length
                    ? 'No accounts match these filters.'
                    : 'No accounts in cache yet. Sync while online, then reopen Planner.'}
                </div>`
              : accounts.slice(0, 50).map(
                  (a) => html`
                    <div
                      class="account-chip ${opts.selectedAccountId === a.id ? 'is-selected' : ''} ${
                        touchDrag?.active && touchDrag.kind === 'account' && touchDrag.id === String(a.id)
                          ? 'is-touch-dragging'
                          : ''
                      }"
                      draggable=${isReadOnly ? 'false' : 'true'}
                      role="button"
                      tabindex="0"
                      data-account-id=${a.id || ''}
                      title="Drag onto calendar to schedule a visit"
                      @dragstart=${(e: DragEvent) => {
                        if (isReadOnly) {
                          e.preventDefault();
                          return;
                        }
                        const id = a.id ? String(a.id) : '';
                        if (!id) return;
                        const root = (e.currentTarget as HTMLElement).getRootNode() as ParentNode;
                        beginHtmlCalendarDrag(
                          root,
                          {
                            kind: 'account',
                            id,
                            nextLat: a.latitude,
                            nextLon: a.longitude
                          },
                          e,
                          e.currentTarget as HTMLElement
                        );
                        opts.onSelectAccount?.(id);
                        e.dataTransfer?.setData('text/plain', id);
                        e.dataTransfer?.setData('application/x-osr-account-id', id);
                      }}
                      @dragend=${(e: DragEvent) => {
                        const root = (e.currentTarget as HTMLElement).getRootNode() as ParentNode;
                        endHtmlCalendarDrag(root, e.currentTarget as HTMLElement, bump);
                      }}
                      @touchstart=${(e: TouchEvent) => {
                        if (isReadOnly) return;
                        const touch = e.touches?.[0];
                        const id = a.id ? String(a.id) : '';
                        if (!touch || !id) return;
                        const root = (e.currentTarget as HTMLElement).getRootNode() as ParentNode;
                        beginTouchDrag(
                          {
                            kind: 'account',
                            id,
                            label: a.name || 'Account',
                            active: false,
                            startX: touch.clientX,
                            startY: touch.clientY,
                            nextLat: a.latitude,
                            nextLon: a.longitude
                          },
                          {
                            visits,
                            allAccounts,
                            isReadOnly,
                            selectedAccountId: opts.selectedAccountId,
                            onRescheduleVisit: opts.onRescheduleVisit,
                            onCreateDraft: opts.onCreateDraft,
                            onOpenPlanChoice: opts.onOpenPlanChoice,
                            onSelectAccount: opts.onSelectAccount,
                            bump,
                            root
                          }
                        );
                      }}
                      @click=${() => {
                        if (touchDrag?.active) return;
                        opts.onSelectAccount?.(a.id ? String(a.id) : null);
                      }}
                      @keydown=${(e: KeyboardEvent) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault();
                          opts.onSelectAccount?.(a.id ? String(a.id) : null);
                        }
                      }}
                    >
                      <span class="account-chip-name">${a.name || 'Account'}</span>
                      <span class="account-chip-meta affil-meta-row">
                        ${renderAccountKindBadge(a, {
                          label: a.recordTypeName || undefined,
                          compact: true
                        })}
                        <span
                          >${[a.specialty, a.classification ? `Class ${a.classification}` : '', a.city]
                            .filter(Boolean)
                            .join(' · ')}</span
                        >
                      </span>
                      ${a.targetVisits != null
                        ? html`<span class="account-chip-meta"
                            >Actual ${Number(a.actualVisits ?? 0)} / Target ${Number(a.targetVisits)}</span
                          >`
                        : nothing}
                    </div>
                  `
                )}
          </div>
        </aside>

        <section class="planner-main" style="position:relative">
          ${opts.filterPanelOpen
            ? html`
                <div class="main-overlay-backdrop" @click=${() => opts.onCloseFilterPanel?.()}></div>
                <div class="main-overlay-panel account-filter-panel" @click=${(e: Event) => e.stopPropagation()}>
                  <div class="account-filter-panel-header">
                    <span class="account-filter-panel-title">Filter accounts</span>
                    <button
                      type="button"
                      class="account-filter-panel-close"
                      @click=${() => opts.onCloseFilterPanel?.()}
                    >
                      ×
                    </button>
                  </div>
                  <div class="account-filter-panel-body">
                    ${renderFilterSelect(
                      'Record type',
                      filters.recordType ?? FILTER_ALL,
                      [{ label: 'All types', value: FILTER_ALL }, ...filterOptions.recordTypes],
                      (value) => opts.onSetAccountFilters?.({ ...filters, recordType: value })
                    )}
                    ${renderFilterSelect(
                      'Specialty',
                      filters.specialty ?? FILTER_ALL,
                      [{ label: 'All specialties', value: FILTER_ALL }, ...filterOptions.specialties],
                      (value) => opts.onSetAccountFilters?.({ ...filters, specialty: value })
                    )}
                    ${renderFilterSelect(
                      'Classification',
                      filters.classification ?? FILTER_ALL,
                      [
                        { label: 'All classifications', value: FILTER_ALL },
                        ...filterOptions.classifications
                      ],
                      (value) => opts.onSetAccountFilters?.({ ...filters, classification: value })
                    )}
                    ${renderFilterSelect(
                      'Brick',
                      filters.brickId ?? FILTER_ALL,
                      [{ label: 'All bricks', value: FILTER_ALL }, ...filterOptions.bricks],
                      (value) => opts.onSetAccountFilters?.({ ...filters, brickId: value })
                    )}
                  </div>
                  <div class="account-filter-panel-footer">
                    <button
                      type="button"
                      class="clear-filters-link"
                      @click=${() => opts.onClearAccountFilters?.()}
                    >
                      Clear filters
                    </button>
                  </div>
                </div>
              `
            : nothing}
          ${mode === 'map'
            ? html`
                <div class="map-view">
                  <div class="map-layout">
                    <div class="map-container" ${ref(mountMap)}></div>
                    <div class="map-sidebar">
                      <div class="sidebar-section-title">Route stops</div>
                      <div class="map-account-count">
                        ${dayVisits.length} stop(s) · ${mapDayKey} ·
                        ${lastRouteResult?.distanceKm ?? dayRoute.km} km
                      </div>
                      ${currentLocation
                        ? html`
                            <div class="route-stop is-current-location">
                              <span class="route-stop-order is-current-location">You</span>
                              <div>
                                <strong>Current location</strong>
                                <div class="route-stop-type">Route starting point</div>
                              </div>
                            </div>
                          `
                        : html`<div class="slds-text-color_weak slds-p-around_x-small slds-text-body_small">
                            Locating you… allow location to start the route from your position.
                          </div>`}
                      ${dayVisits.length === 0
                        ? html`<div class="slds-text-color_weak slds-p-around_small">No visits this day</div>`
                        : dayVisits.map(
                            (v, i) => html`
                              <button
                                type="button"
                                class="route-stop"
                                style="width:100%;text-align:left;cursor:pointer"
                                @click=${() => v.id && opts.onOpenVisit?.(String(v.id))}
                              >
                                <span
                                  class="route-stop-order ${pinKindFromRecordType(
                                    v.accountRecordTypeName,
                                    v.accountRecordTypeDeveloperName
                                  ) === 'hco'
                                    ? 'route-stop-order-hco'
                                    : 'route-stop-order-hcp'}"
                                  >${i + 1}</span
                                >
                                <div>
                                  <strong>${v.accountName || v.name}</strong>
                                  <div class="route-stop-type">
                                    ${formatVisitTimeRange(v.startDateTime, v.endDateTime)}
                                  </div>
                                </div>
                              </button>
                            `
                          )}
                    </div>
                  </div>
                </div>
              `
            : html`
                <div class="calendar-view">
                  <div
                    class="calendar-scroll"
                    @dragover=${(e: DragEvent) => {
                      if (isReadOnly) return;
                      e.preventDefault();
                      if (e.dataTransfer) {
                        e.dataTransfer.dropEffect =
                          dragVisitId || dragPayload?.kind === 'visit' ? 'move' : 'copy';
                      }
                      const root = (e.currentTarget as HTMLElement).getRootNode() as ParentNode;
                      clearCalendarDropHighlights(root);
                      const target = resolveCalendarDropTarget(e.clientX, e.clientY, root);
                      target?.cell.classList.add('calendar-drop-target');
                    }}
                    @dragleave=${(e: DragEvent) => {
                      const root = (e.currentTarget as HTMLElement).getRootNode() as ParentNode;
                      if (!(e.currentTarget as HTMLElement).contains(e.relatedTarget as Node)) {
                        clearCalendarDropHighlights(root);
                      }
                    }}
                    @drop=${(e: DragEvent) => {
                      if (isReadOnly) return;
                      e.preventDefault();
                      e.stopPropagation();
                      const root = (e.currentTarget as HTMLElement).getRootNode() as ParentNode;
                      clearCalendarDropHighlights(root);
                      calendarDndActive = false;
                      syncCalendarDndClass(root);
                      const target = resolveCalendarDropTarget(e.clientX, e.clientY, root);
                      if (target) {
                        const mimeVisit =
                          e.dataTransfer?.getData('application/x-osr-visit-id') || '';
                        const mimeAccount =
                          e.dataTransfer?.getData('application/x-osr-account-id') ||
                          e.dataTransfer?.getData('text/plain') ||
                          '';
                        applyPlannerCalendarDrop({
                          day: target.day,
                          hour: target.hour,
                          clientY: e.clientY,
                          cell: target.cell,
                          visits,
                          allAccounts,
                          isReadOnly,
                          selectedAccountId: opts.selectedAccountId,
                          visitIdHint: dragVisitId || mimeVisit || null,
                          accountIdHint: dragAccountId || (!mimeVisit ? mimeAccount : null),
                          onRescheduleVisit: opts.onRescheduleVisit,
                          onCreateDraft: opts.onCreateDraft,
                          onOpenPlanChoice: opts.onOpenPlanChoice,
                          onSelectAccount: opts.onSelectAccount
                        });
                      }
                      dragPayload = null;
                      setTimeout(() => {
                        dragVisitId = null;
                        dragAccountId = null;
                        bump();
                      }, 50);
                    }}
                  >
                    <div
                      class="calendar-canvas ${calendarDndActive || touchDrag?.active ? 'is-dnd-active' : ''}"
                      style="min-width:56rem;height:${canvasHeight}px;position:relative"
                    >
                      <div
                        class="calendar-grid"
                        style="grid-template-rows: ${HEADER_H}px repeat(${HOURS.length}, ${60 *
                        PX_PER_MINUTE}px)"
                      >
                        <div class="calendar-header-cell"></div>
                        ${days.map((d) => {
                          const key = isoDateLocal(d);
                          const dow = d.getDay();
                          const weekend = dow === 5 || dow === 6;
                          return html`
                            <div
                              class="calendar-header-cell ${key === todayKey
                                ? 'is-today'
                                : ''} ${weekend ? 'is-weekend' : ''}"
                            >
                              <div>${d.toLocaleDateString(undefined, { weekday: 'short' })}</div>
                              <div class="slds-text-body_small">
                                ${d.toLocaleDateString(undefined, {
                                  month: 'short',
                                  day: 'numeric'
                                })}
                              </div>
                            </div>
                          `;
                        })}
                        ${HOURS.map(
                          (h) => html`
                            <div class="time-gutter">${formatHour(h)}</div>
                            ${days.map((d) => {
                              const key = isoDateLocal(d);
                              const dow = d.getDay();
                              const weekend = dow === 5 || dow === 6;
                              return html`
                                <div
                                  class="day-column ${key === todayKey
                                    ? 'is-today'
                                    : ''} ${weekend ? 'is-weekend' : ''}"
                                  data-day-key=${key}
                                  data-hour=${h}
                                  @click=${(e: MouseEvent) => {
                                    if (isReadOnly) return;
                                    const startIso = slotIsoFromCell(
                                      d,
                                      h,
                                      e.clientY,
                                      e.currentTarget as HTMLElement
                                    );
                                    opts.onOpenPlanChoice?.(startIso);
                                  }}
                                ></div>
                              `;
                            })}
                          `
                        )}
                      </div>
                      <div
                        class="calendar-events-layer"
                        style="top:${HEADER_H}px;left:${GUTTER_W}px;right:0;bottom:0"
                      >
                        ${visits.map((v) =>
                          renderEventBlock(v, days, 'visit', opts.onOpenVisit, {
                            readOnly: isReadOnly,
                            bump,
                            visits,
                            allAccounts,
                            selectedAccountId: opts.selectedAccountId,
                            onRescheduleVisit: opts.onRescheduleVisit,
                            onCreateDraft: opts.onCreateDraft,
                            onOpenPlanChoice: opts.onOpenPlanChoice,
                            onSelectAccount: opts.onSelectAccount
                          })
                        )}
                        ${tots.map((t) => renderTotEvent(t, days))}
                      </div>
                    </div>
                  </div>
                </div>
              `}
        </section>
      </div>

      ${opts.planChoiceSlot
        ? renderPlanChoiceModal(opts.planChoiceSlot, opts)
        : nothing}
      ${detailVisit
        ? renderVisitDetailModal(detailVisit, opts)
        : nothing}
      ${opts.totModalStart
        ? renderTotModal(opts.totModalStart, opts)
        : nothing}
      ${opts.promoModalStart
        ? renderPromoModal(opts.promoModalStart, opts.promotionalProjects ?? [], opts)
        : nothing}
      ${opts.saveCollectionOpen
        ? renderSaveCollectionModal(accounts, filters, opts)
        : nothing}
    </section>
  `;
}

function renderFilterSelect(
  label: string,
  value: string,
  options: { label: string; value: string }[],
  onChange: (value: string) => void
): TemplateResult {
  return html`
    <div class="account-filter-field">
      <label class="account-filter-label">${label}</label>
      <select
        class="slds-select"
        .value=${value}
        @change=${(e: Event) => onChange((e.target as HTMLSelectElement).value)}
      >
        ${options.map((o) => html`<option value=${o.value} ?selected=${o.value === value}>${o.label}</option>`)}
      </select>
    </div>
  `;
}

function renderSaveCollectionModal(
  accounts: AccountSummaryDto[],
  filters: PlannerAccountFilters,
  opts: {
    onCloseSaveCollection?: () => void;
    onSaveCollection?: (name: string, accountIds: string[], filters: PlannerAccountFilters) => void;
  }
): TemplateResult {
  const formId = 'save-collection-modal';
  const ids = accounts.map((a) => String(a.id)).filter(Boolean);
  return html`
    <section role="dialog" class="slds-modal slds-fade-in-open osr-planner-modal">
      <div class="slds-modal__container" id=${formId}>
        <header class="slds-modal__header">
          <h2 class="slds-text-heading_medium">Save filter as list</h2>
        </header>
        <div class="slds-modal__content slds-p-around_medium">
          <p class="slds-m-bottom_small">${ids.length} account(s) match the current filters.</p>
          <label class="slds-form-element__label">List name</label>
          <input class="slds-input" data-field="collection-name" placeholder="e.g. Class A Helwan" />
        </div>
        <footer class="slds-modal__footer">
          <button type="button" class="slds-button slds-button_neutral" @click=${() => opts.onCloseSaveCollection?.()}>
            Cancel
          </button>
          <button
            type="button"
            class="slds-button slds-button_brand"
            @click=${() => {
              const root = document.getElementById(formId);
              const name =
                (root?.querySelector('[data-field="collection-name"]') as HTMLInputElement | null)
                  ?.value || '';
              if (!name.trim() || !ids.length) return;
              opts.onSaveCollection?.(name.trim(), ids, filters);
            }}
          >
            Save list
          </button>
        </footer>
      </div>
    </section>
    <div class="slds-backdrop slds-backdrop_open"></div>
  `;
}

function renderPlanChoiceModal(
  startIso: string,
  opts: {
    selectedAccountId?: string | null;
    onClosePlanChoice?: () => void;
    onCreateDraft?: (accountId: string, startIso: string) => void;
    onOpenTotModal?: (startIso: string) => void;
    onOpenPromoModal?: (startIso: string) => void;
  }
): TemplateResult {
  const when = new Date(startIso).toLocaleString();
  const hasAccount = !!opts.selectedAccountId;
  return html`
    <section role="dialog" class="slds-modal slds-fade-in-open osr-planner-modal">
      <div class="slds-modal__container plan-choice-modal">
        <header class="slds-modal__header">
          <h2 class="slds-text-heading_medium">Plan this time slot</h2>
        </header>
        <div class="slds-modal__content slds-p-around_medium">
          <p class="slds-m-bottom_medium">${when}</p>
          <p class="slds-text-body_regular slds-m-bottom_medium">What would you like to schedule?</p>
          ${!hasAccount
            ? html`<p class="slds-text-color_error slds-m-bottom_small">
                Select an account in the sidebar first (or drag one onto the calendar).
              </p>`
            : nothing}
          <div class="plan-choice-actions" style="display:flex;flex-direction:column;gap:0.5rem">
            <button
              type="button"
              class="slds-button slds-button_brand"
              ?disabled=${!hasAccount}
              @click=${() => {
                if (!opts.selectedAccountId || !opts.onCreateDraft) return;
                opts.onCreateDraft(opts.selectedAccountId, startIso);
                opts.onClosePlanChoice?.();
              }}
            >
              Plan a Visit
            </button>
            <button
              type="button"
              class="slds-button slds-button_neutral"
              @click=${() => opts.onOpenTotModal?.(startIso)}
            >
              Time Off (TOT)
            </button>
            <button
              type="button"
              class="slds-button slds-button_neutral"
              @click=${() => opts.onOpenPromoModal?.(startIso)}
            >
              Promotional Event
            </button>
          </div>
        </div>
        <footer class="slds-modal__footer">
          <button type="button" class="slds-button slds-button_neutral" @click=${() => opts.onClosePlanChoice?.()}>
            Cancel
          </button>
        </footer>
      </div>
    </section>
    <div class="slds-backdrop slds-backdrop_open" @click=${() => opts.onClosePlanChoice?.()}></div>
  `;
}

function renderVisitDetailModal(
  visit: VisitSummaryDto,
  opts: {
    onCloseVisitDetail?: () => void;
    onSaveVisitDetail?: (visitId: string, status: string, cancellationReason: string) => void;
    onPostponeVisit?: (visitId: string) => void;
    onRemoveVisit?: (visitId: string) => void;
    onViewVisit?: (visitId: string) => void;
  }
): TemplateResult {
  const start = visit.startDateTime ? new Date(visit.startDateTime) : null;
  const end = visit.endDateTime ? new Date(visit.endDateTime) : null;
  const formId = `visit-detail-${visit.id}`;
  return html`
    <section role="dialog" class="slds-modal slds-fade-in-open osr-planner-modal">
      <div class="slds-modal__container" id=${formId}>
        <header class="slds-modal__header">
          <h2 class="slds-text-heading_medium">Plan Visit</h2>
        </header>
        <div class="slds-modal__content slds-p-around_medium">
          <p class="slds-text-title_caps slds-m-bottom_x-small">${visit.accountName || visit.name}</p>
          <p class="slds-m-bottom_medium">
            <strong>When:</strong>
            ${start ? start.toLocaleString() : '—'} – ${end ? end.toLocaleTimeString() : '—'}
          </p>
          <label class="slds-form-element__label">Status</label>
          <select class="slds-select" data-field="status">
            ${['Draft', 'Scheduled', 'Completed', 'Cancelled'].map(
              (s) => html`<option value=${s} ?selected=${String(visit.status || 'Draft') === s}>${s}</option>`
            )}
          </select>
          <label class="slds-form-element__label slds-m-top_small">Cancellation Reason</label>
          <textarea class="slds-textarea" data-field="cancellation"></textarea>
        </div>
        <footer class="slds-modal__footer" style="display:flex;flex-wrap:wrap;gap:0.5rem;justify-content:flex-end">
          <button
            type="button"
            class="slds-button slds-button_destructive"
            @click=${() => {
              if (visit.id) opts.onRemoveVisit?.(String(visit.id));
              opts.onCloseVisitDetail?.();
            }}
          >
            Remove visit
          </button>
          <button
            type="button"
            class="slds-button slds-button_neutral"
            @click=${() => {
              if (visit.id) opts.onPostponeVisit?.(String(visit.id));
              opts.onCloseVisitDetail?.();
            }}
          >
            Postpone to tomorrow
          </button>
          <button type="button" class="slds-button slds-button_neutral" @click=${() => opts.onCloseVisitDetail?.()}>
            Close
          </button>
          <button
            type="button"
            class="slds-button slds-button_brand"
            @click=${() => visit.id && opts.onViewVisit?.(String(visit.id))}
          >
            View Visit
          </button>
          <button
            type="button"
            class="slds-button slds-button_brand"
            @click=${() => {
              const root = document.getElementById(formId);
              const status =
                (root?.querySelector('[data-field="status"]') as HTMLSelectElement | null)?.value ||
                String(visit.status || 'Draft');
              const cancellation =
                (root?.querySelector('[data-field="cancellation"]') as HTMLTextAreaElement | null)?.value ||
                '';
              if (visit.id) opts.onSaveVisitDetail?.(String(visit.id), status, cancellation);
            }}
          >
            Save
          </button>
        </footer>
      </div>
    </section>
    <div class="slds-backdrop slds-backdrop_open"></div>
  `;
}

function renderTotModal(
  startIso: string,
  opts: {
    onCloseTotModal?: () => void;
    onCreateTimeOff?: (input: {
      startIso: string;
      typeValue: string;
      spanType: string;
      durationHours?: string;
      comments?: string;
    }) => void;
  }
): TemplateResult {
  const formId = `tot-modal-${startIso}`;
  return html`
    <section role="dialog" class="slds-modal slds-fade-in-open osr-planner-modal">
      <div class="slds-modal__container" id=${formId}>
        <header class="slds-modal__header">
          <h2 class="slds-text-heading_medium">Create Time Off (TOT)</h2>
        </header>
        <div class="slds-modal__content slds-p-around_medium">
          <p class="slds-m-bottom_small">${new Date(startIso).toLocaleString()}</p>
          <label class="slds-form-element__label">Type</label>
          <select class="slds-select" data-field="type">
            ${TOT_TYPES.map(
              (t) => html`<option value=${t.value} ?selected=${t.value === 'Training'}>${t.label}</option>`
            )}
          </select>
          <label class="slds-form-element__label slds-m-top_small">Span</label>
          <select class="slds-select" data-field="span">
            <option value="Hours" selected>Hours</option>
            <option value="Full_Day">Full Day</option>
          </select>
          <label class="slds-form-element__label slds-m-top_small">Duration (hours)</label>
          <input class="slds-input" type="number" min="1" max="12" value="2" data-field="hours" />
          <label class="slds-form-element__label slds-m-top_small">Comments</label>
          <textarea class="slds-textarea" data-field="comments"></textarea>
        </div>
        <footer class="slds-modal__footer">
          <button type="button" class="slds-button slds-button_neutral" @click=${() => opts.onCloseTotModal?.()}>
            Cancel
          </button>
          <button
            type="button"
            class="slds-button slds-button_brand"
            @click=${() => {
              const root = document.getElementById(formId);
              opts.onCreateTimeOff?.({
                startIso,
                typeValue:
                  (root?.querySelector('[data-field="type"]') as HTMLSelectElement | null)?.value || 'Training',
                spanType:
                  (root?.querySelector('[data-field="span"]') as HTMLSelectElement | null)?.value || 'Hours',
                durationHours:
                  (root?.querySelector('[data-field="hours"]') as HTMLInputElement | null)?.value || '2',
                comments:
                  (root?.querySelector('[data-field="comments"]') as HTMLTextAreaElement | null)?.value || ''
              });
            }}
          >
            Save Draft
          </button>
        </footer>
      </div>
    </section>
    <div class="slds-backdrop slds-backdrop_open"></div>
  `;
}

function renderPromoModal(
  startIso: string,
  projects: { id: string; name: string }[],
  opts: {
    onClosePromoModal?: () => void;
    onCreatePromo?: (projectId: string, startIso: string) => void;
  }
): TemplateResult {
  const formId = `promo-modal-${startIso}`;
  return html`
    <section role="dialog" class="slds-modal slds-fade-in-open osr-planner-modal">
      <div class="slds-modal__container" id=${formId}>
        <header class="slds-modal__header">
          <h2 class="slds-text-heading_medium">Plan Promotional Event</h2>
        </header>
        <div class="slds-modal__content slds-p-around_medium">
          <p class="slds-m-bottom_small">${new Date(startIso).toLocaleString()}</p>
          ${projects.length === 0
            ? html`<p class="slds-text-color_weak">
                No promotional projects synced. Sync online to load projects.
              </p>`
            : html`
                <label class="slds-form-element__label">Promotional project</label>
                <select class="slds-select" data-field="project">
                  ${projects.map((p) => html`<option value=${p.id}>${p.name}</option>`)}
                </select>
              `}
        </div>
        <footer class="slds-modal__footer">
          <button type="button" class="slds-button slds-button_neutral" @click=${() => opts.onClosePromoModal?.()}>
            Cancel
          </button>
          <button
            type="button"
            class="slds-button slds-button_brand"
            ?disabled=${projects.length === 0}
            @click=${() => {
              const root = document.getElementById(formId);
              const projectId =
                (root?.querySelector('[data-field="project"]') as HTMLSelectElement | null)?.value ||
                projects[0]?.id;
              if (projectId) opts.onCreatePromo?.(projectId, startIso);
            }}
          >
            Save
          </button>
        </footer>
      </div>
    </section>
    <div class="slds-backdrop slds-backdrop_open"></div>
  `;
}

function renderEventBlock(
  v: VisitSummaryDto,
  days: Date[],
  kind: 'visit',
  onOpen?: (id: string) => void,
  dragCtx?: {
    readOnly?: boolean;
    bump?: () => void;
    visits: VisitSummaryDto[];
    allAccounts: AccountSummaryDto[];
    selectedAccountId?: string | null;
    onRescheduleVisit?: (visitId: string, startIso: string, endIso: string) => void;
    onCreateDraft?: (accountId: string, startIso: string) => void;
    onOpenPlanChoice?: (startIso: string) => void;
    onSelectAccount?: (id: string | null) => void;
  }
): TemplateResult | typeof nothing {
  const key = dateKeyOf(v.startDateTime);
  const dayIndex = days.findIndex((d) => isoDateLocal(d) === key);
  if (dayIndex < 0) return nothing;
  const top = Math.max(0, minutesFromDayStart(v.startDateTime)) * PX_PER_MINUTE;
  const dur = Math.max(
    SLOT_MINUTES,
    minutesFromDayStart(v.endDateTime) - minutesFromDayStart(v.startDateTime) || 60
  );
  const height = dur * PX_PER_MINUTE;
  const status = String(v.status ?? '').toLowerCase();
  const cls = [
    'event-block',
    kind,
    status === 'draft' ? 'draft' : '',
    status === 'cancelled' ? 'cancelled' : '',
    status === 'scheduled' || status === 'rescheduled' ? 'scheduled' : '',
    touchDrag?.active && touchDrag.kind === 'visit' && touchDrag.id === String(v.id)
      ? 'is-touch-dragging'
      : ''
  ]
    .filter(Boolean)
    .join(' ');
  const leftPct = (dayIndex / 7) * 100;
  const widthPct = 100 / 7;
  const locked = visitDragLocked(v);
  const canDrag = !dragCtx?.readOnly && !!v.id && !locked;
  const oldStart = v.startDateTime ? new Date(v.startDateTime) : null;
  const oldEnd = v.endDateTime ? new Date(v.endDateTime) : null;
  const durationMs =
    oldStart && oldEnd && !Number.isNaN(oldStart.getTime())
      ? Math.max(SLOT_MINUTES * 60 * 1000, oldEnd.getTime() - oldStart.getTime())
      : DEFAULT_VISIT_MS;
  const grabbableClass = canDrag ? 'is-grabbable' : '';
  return html`
    <div
      class="${cls} ${grabbableClass}"
      role="button"
      tabindex="0"
      title=${canDrag ? 'Drag to reschedule' : locked ? 'Completed or cancelled visits cannot be moved' : ''}
      style="top:${top}px;height:${height}px;left:calc(${leftPct}% + 2px);width:calc(${widthPct}% - 6px);position:absolute;text-align:left"
      @pointerdown=${(e: PointerEvent) => {
        if (!canDrag || !v.id || !dragCtx) return;
        e.stopPropagation();
        const el = e.currentTarget as HTMLElement;
        const root = el.getRootNode() as ParentNode;
        beginVisitPointerDrag(
          e,
          {
            kind: 'visit',
            id: String(v.id),
            label: v.accountName || v.name || 'Visit',
            active: false,
            startX: e.clientX,
            startY: e.clientY,
            durationMs,
            nextLat: v.accountLatitude,
            nextLon: v.accountLongitude
          },
          {
            visits: dragCtx.visits,
            allAccounts: dragCtx.allAccounts,
            isReadOnly: !!dragCtx.readOnly,
            selectedAccountId: dragCtx.selectedAccountId,
            onRescheduleVisit: dragCtx.onRescheduleVisit,
            onCreateDraft: dragCtx.onCreateDraft,
            onOpenPlanChoice: dragCtx.onOpenPlanChoice,
            onSelectAccount: dragCtx.onSelectAccount,
            bump: dragCtx.bump,
            root
          },
          el
        );
      }}
      @click=${(e: Event) => {
        e.stopPropagation();
        if (touchDrag?.active || suppressVisitClick) {
          suppressVisitClick = false;
          return;
        }
        if (v.id) onOpen?.(String(v.id));
      }}
      @keydown=${(e: KeyboardEvent) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          e.stopPropagation();
          if (v.id) onOpen?.(String(v.id));
        }
      }}
    >
      <div class="event-title">
        ${status === 'draft' ? 'Draft' : v.status || 'Visit'} · ${v.accountName || v.name || ''}
      </div>
      <div class="event-time">${formatVisitTimeRange(v.startDateTime, v.endDateTime)}</div>
    </div>
  `;
}

function renderTotEvent(
  t: { startDateTime?: string; endDateTime?: string; name?: string },
  days: Date[]
): TemplateResult | typeof nothing {
  const key = dateKeyOf(t.startDateTime);
  const dayIndex = days.findIndex((d) => isoDateLocal(d) === key);
  if (dayIndex < 0) return nothing;
  const top = Math.max(0, minutesFromDayStart(t.startDateTime)) * PX_PER_MINUTE;
  const dur = Math.max(
    SLOT_MINUTES,
    minutesFromDayStart(t.endDateTime) - minutesFromDayStart(t.startDateTime) || 60
  );
  const leftPct = (dayIndex / 7) * 100;
  const widthPct = 100 / 7;
  return html`
    <div
      class="event-block tot"
      style="top:${top}px;height:${dur * PX_PER_MINUTE}px;left:calc(${leftPct}% + 2px);width:calc(${widthPct}% - 6px);position:absolute"
    >
      <div class="event-title">TOT · ${t.name || 'Time off'}</div>
    </div>
  `;
}

function nearestNeighborOrder(visits: VisitSummaryDto[]): VisitSummaryDto[] {
  const pts = visits.filter(
    (v) => Number.isFinite(Number(v.accountLatitude)) && Number.isFinite(Number(v.accountLongitude))
  );
  const ungeocoded = visits.filter(
    (v) => !Number.isFinite(Number(v.accountLatitude)) || !Number.isFinite(Number(v.accountLongitude))
  );
  if (pts.length < 2) return [...pts, ...ungeocoded];
  const remaining = [...pts];
  const ordered: VisitSummaryDto[] = [remaining.shift()!];
  while (remaining.length) {
    const last = ordered[ordered.length - 1];
    let bestIdx = 0;
    let bestD = Infinity;
    for (let i = 0; i < remaining.length; i++) {
      const d = haversineKm(
        Number(last.accountLatitude),
        Number(last.accountLongitude),
        Number(remaining[i].accountLatitude),
        Number(remaining[i].accountLongitude)
      );
      if (d < bestD) {
        bestD = d;
        bestIdx = i;
      }
    }
    ordered.push(remaining.splice(bestIdx, 1)[0]);
  }
  return [...ordered, ...ungeocoded];
}

/** Try each geocoded start point; keep the shortest nearest-neighbor tour. */
function bestNearestNeighbor(visits: VisitSummaryDto[]): VisitSummaryDto[] {
  const pts = visits.filter(
    (v) => Number.isFinite(Number(v.accountLatitude)) && Number.isFinite(Number(v.accountLongitude))
  );
  if (pts.length < 2) return nearestNeighborOrder(visits);
  let best = nearestNeighborOrder(visits);
  let bestKm = estimateRouteKm(best).km;
  for (let i = 1; i < pts.length; i++) {
    const rotated = [...pts.slice(i), ...pts.slice(0, i)];
    const ungeocoded = visits.filter(
      (v) => !Number.isFinite(Number(v.accountLatitude)) || !Number.isFinite(Number(v.accountLongitude))
    );
    const candidate = nearestNeighborOrder([...rotated, ...ungeocoded]);
    const km = estimateRouteKm(candidate).km;
    if (km < bestKm) {
      best = candidate;
      bestKm = km;
    }
  }
  return best;
}
