import { html, nothing, svg, type TemplateResult } from 'lit';
import type { AccountSummaryDto, ApexCacheSnapshot } from '../apex-cache';
import {
  accountKindLabel,
  accountKindSvgIcon,
  renderAccountKindBadge,
  resolveAccountKind,
  type AccountKind
} from './account-type';

export type AffLinkKind = 'brick' | 'specialty' | 'city' | 'link';

type AffNodeKind = AccountKind | 'root';

export type AffGraphNode = {
  id: string;
  label: string;
  kind: AffNodeKind;
  specialty?: string;
  city?: string;
  brickName?: string;
  classification?: string;
  recordTypeName?: string;
  depth: number;
  x: number;
  y: number;
};

export type AffGraphEdge = {
  id: string;
  from: string;
  to: string;
  kinds: AffLinkKind[];
  strength: number;
  path: string;
  midX: number;
  midY: number;
  label: string;
};

type AffNetworkUi = {
  layout: 'radial' | 'tree';
  depth: 1 | 2 | 3;
  enabledKinds: Set<AffLinkKind>;
  query: string;
  selectedId: string | null;
  collapsed: Set<string>;
  levelLimits: Map<number, number>;
  view: { x: number; y: number; k: number };
  pointerId: number | null;
  lastX: number;
  lastY: number;
};

const LEVEL_PAGE = 8;
const VIEW_W = 920;
const VIEW_H = 560;
const TREE_COL = 260;
const TREE_ROW = 78;
const NODE_R = 28;

const KIND_META: Record<AffLinkKind, { label: string; color: string }> = {
  brick: { label: 'Brick', color: '#0176d3' },
  specialty: { label: 'Specialty', color: '#2e844a' },
  city: { label: 'City', color: '#ba0517' },
  link: { label: 'HCP↔HCO', color: '#6b53c5' }
};

const uiByRoot = new Map<string, AffNetworkUi>();

function uiFor(rootId: string): AffNetworkUi {
  let state = uiByRoot.get(rootId);
  if (!state) {
    state = {
      layout: 'radial',
      depth: 2,
      enabledKinds: new Set<AffLinkKind>(['brick', 'specialty', 'city', 'link']),
      query: '',
      selectedId: rootId,
      collapsed: new Set(),
      levelLimits: new Map([[1, LEVEL_PAGE], [2, LEVEL_PAGE], [3, LEVEL_PAGE]]),
      view: { x: 0, y: 0, k: 1 },
      pointerId: null,
      lastX: 0,
      lastY: 0
    };
    uiByRoot.set(rootId, state);
  }
  return state;
}

function isHcoLike(a: AccountSummaryDto | null | undefined): boolean {
  const kind = resolveAccountKind(a);
  return kind === 'hco' || kind === 'pharmacy';
}

function nodeKind(a: AccountSummaryDto, isRoot: boolean): AffNodeKind {
  if (isRoot) return 'root';
  return resolveAccountKind(a);
}

function linkKindsBetween(a: AccountSummaryDto, b: AccountSummaryDto): AffLinkKind[] {
  const kinds: AffLinkKind[] = [];
  if (a.brickId && b.brickId && a.brickId === b.brickId) kinds.push('brick');
  if (a.specialty && b.specialty && a.specialty === b.specialty) kinds.push('specialty');
  if (a.city && b.city && a.city === b.city) kinds.push('city');
  if (isHcoLike(a) !== isHcoLike(b)) kinds.push('link');
  return kinds;
}

function strengthOf(kinds: AffLinkKind[]): number {
  let s = 0;
  for (const k of kinds) {
    if (k === 'brick') s += 3;
    else if (k === 'specialty' || k === 'city') s += 2;
    else s += 1;
  }
  return s;
}

function findAccount(snap: ApexCacheSnapshot | null, id: string): AccountSummaryDto | null {
  return snap?.plannerAccounts?.accounts?.find((a) => String(a.id) === id) ?? null;
}

function truncate(label: string, max = 18): string {
  const t = (label || 'Account').trim();
  return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}

function curvePath(x1: number, y1: number, x2: number, y2: number): string {
  const mx = (x1 + x2) / 2;
  const my = (y1 + y2) / 2;
  const dx = x2 - x1;
  const dy = y2 - y1;
  const len = Math.hypot(dx, dy) || 1;
  const ox = (-dy / len) * Math.min(48, len * 0.18);
  const oy = (dx / len) * Math.min(48, len * 0.18);
  const cx = mx + ox;
  const cy = my + oy;
  return `M ${x1} ${y1} Q ${cx} ${cy} ${x2} ${y2}`;
}

function buildGraph(
  rootId: string,
  rootAccount: AccountSummaryDto,
  accounts: AccountSummaryDto[],
  state: AffNetworkUi
): { nodes: AffGraphNode[]; edges: AffGraphEdge[]; hiddenByLevel: Map<number, number> } {
  const byId = new Map<string, AccountSummaryDto>();
  for (const a of accounts) {
    if (a.id) byId.set(String(a.id), a);
  }
  byId.set(rootId, rootAccount);

  const pool = [...byId.values()].filter((a) => a.id);
  const neighborsOf = (acct: AccountSummaryDto): { id: string; kinds: AffLinkKind[] }[] => {
    const out: { id: string; kinds: AffLinkKind[] }[] = [];
    for (const other of pool) {
      const oid = String(other.id);
      if (oid === String(acct.id)) continue;
      const kinds = linkKindsBetween(acct, other).filter((k) => state.enabledKinds.has(k));
      if (!kinds.length) continue;
      out.push({ id: oid, kinds });
    }
    out.sort((a, b) => strengthOf(b.kinds) - strengthOf(a.kinds));
    return out;
  };

  const parent = new Map<string, string>();
  const depthOf = new Map<string, number>([[rootId, 0]]);
  const edgeKinds = new Map<string, AffLinkKind[]>();
  const queue = [rootId];
  const visited = new Set([rootId]);

  while (queue.length) {
    const cur = queue.shift()!;
    const d = depthOf.get(cur) ?? 0;
    if (d >= state.depth) continue;
    if (state.collapsed.has(cur) && cur !== rootId) continue;
    const curAcct = byId.get(cur);
    if (!curAcct) continue;
    for (const { id: nid, kinds } of neighborsOf(curAcct)) {
      if (visited.has(nid)) continue;
      visited.add(nid);
      parent.set(nid, cur);
      depthOf.set(nid, d + 1);
      edgeKinds.set(`${cur}->${nid}`, kinds);
      queue.push(nid);
    }
  }

  const byDepth = new Map<number, string[]>();
  for (const id of visited) {
    const d = depthOf.get(id) ?? 0;
    if (!byDepth.has(d)) byDepth.set(d, []);
    byDepth.get(d)!.push(id);
  }

  const visible = new Set<string>([rootId]);
  const hiddenByLevel = new Map<number, number>();
  for (let d = 1; d <= state.depth; d++) {
    const list = (byDepth.get(d) || []).sort((a, b) => {
      const pa = parent.get(a)!;
      const pb = parent.get(b)!;
      return strengthOf(edgeKinds.get(`${pb}->${b}`) || []) - strengthOf(edgeKinds.get(`${pa}->${a}`) || []);
    });
    // Prefer stronger links first
    list.sort((a, b) => {
      const sa = strengthOf(edgeKinds.get(`${parent.get(a)}->${a}`) || []);
      const sb = strengthOf(edgeKinds.get(`${parent.get(b)}->${b}`) || []);
      return sb - sa;
    });
    const limit = state.levelLimits.get(d) ?? LEVEL_PAGE;
    const shown = list.slice(0, limit);
    const hidden = list.length - shown.length;
    if (hidden > 0) hiddenByLevel.set(d, hidden);
    for (const id of shown) visible.add(id);
  }

  // Drop orphans whose parent isn't visible
  for (const id of [...visible]) {
    if (id === rootId) continue;
    let p = parent.get(id);
    while (p && p !== rootId) {
      if (!visible.has(p)) {
        visible.delete(id);
        break;
      }
      p = parent.get(p);
    }
  }

  const positions = new Map<string, { x: number; y: number }>();
  if (state.layout === 'radial') {
    const cx = VIEW_W / 2;
    const cy = VIEW_H / 2;
    positions.set(rootId, { x: cx, y: cy });
    for (let d = 1; d <= state.depth; d++) {
      const ring = [...visible].filter((id) => depthOf.get(id) === d);
      const radius = 110 + (d - 1) * 130;
      ring.forEach((id, i) => {
        const angle = -Math.PI / 2 + (i / Math.max(ring.length, 1)) * Math.PI * 2;
        positions.set(id, {
          x: cx + Math.cos(angle) * radius,
          y: cy + Math.sin(angle) * radius
        });
      });
    }
  } else {
    const padX = 70;
    const padY = 48;
    positions.set(rootId, { x: padX, y: VIEW_H / 2 - NODE_R });
    for (let d = 1; d <= state.depth; d++) {
      const col = [...visible].filter((id) => depthOf.get(id) === d);
      const totalH = Math.max(col.length - 1, 0) * TREE_ROW;
      const startY = VIEW_H / 2 - totalH / 2;
      col.forEach((id, i) => {
        positions.set(id, {
          x: padX + d * TREE_COL,
          y: startY + i * TREE_ROW
        });
      });
    }
  }

  const nodes: AffGraphNode[] = [];
  for (const id of visible) {
    const acct = byId.get(id);
    if (!acct) continue;
    const pos = positions.get(id) || { x: 0, y: 0 };
    nodes.push({
      id,
      label: acct.name || 'Account',
      kind: nodeKind(acct, id === rootId),
      specialty: acct.specialty,
      city: acct.city,
      brickName: acct.brickName,
      classification: acct.classification,
      recordTypeName: acct.recordTypeName,
      depth: depthOf.get(id) ?? 0,
      x: pos.x,
      y: pos.y
    });
  }

  const edges: AffGraphEdge[] = [];
  for (const id of visible) {
    if (id === rootId) continue;
    const p = parent.get(id);
    if (!p || !visible.has(p)) continue;
    const from = positions.get(p)!;
    const to = positions.get(id)!;
    const kinds = edgeKinds.get(`${p}->${id}`) || [];
    const path = curvePath(from.x, from.y, to.x, to.y);
    const mx = (from.x + to.x) / 2;
    const my = (from.y + to.y) / 2;
    edges.push({
      id: `${p}-${id}`,
      from: p,
      to: id,
      kinds,
      strength: strengthOf(kinds),
      path,
      midX: mx,
      midY: my,
      label: kinds.map((k) => KIND_META[k].label).join(' · ')
    });
  }

  return { nodes, edges, hiddenByLevel };
}

function fillFor(kind: AffNodeKind, selected: boolean, onPath: boolean): string {
  if (selected || onPath) return kind === 'root' ? '#014486' : '#0176d3';
  switch (kind) {
    case 'root':
      return '#014486';
    case 'hcp':
      return '#e8f4fd';
    case 'pharmacy':
      return '#e8f5e9';
    case 'hco':
    default:
      return '#f3e8fd';
  }
}

function strokeFor(kind: AffNodeKind, selected: boolean, onPath: boolean): string {
  if (selected || onPath) return '#032d60';
  switch (kind) {
    case 'root':
      return '#032d60';
    case 'hcp':
      return '#0176d3';
    case 'pharmacy':
      return '#2e844a';
    case 'hco':
    default:
      return '#6b53c5';
  }
}

function textFill(selected: boolean, onPath: boolean, kind: AffNodeKind): string {
  if (selected || onPath || kind === 'root') return '#ffffff';
  return '#181818';
}

function pathIds(selectedId: string | null, edges: AffGraphEdge[], rootId: string): Set<string> {
  const ids = new Set<string>();
  if (!selectedId) return ids;
  ids.add(selectedId);
  const parentOf = new Map(edges.map((e) => [e.to, e.from]));
  let cur: string | undefined = selectedId;
  while (cur && cur !== rootId) {
    const p = parentOf.get(cur);
    if (!p) break;
    ids.add(p);
    cur = p;
  }
  ids.add(rootId);
  return ids;
}

function fitView(state: AffNetworkUi, nodes: AffGraphNode[]) {
  if (!nodes.length) {
    state.view = { x: 0, y: 0, k: 1 };
    return;
  }
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const n of nodes) {
    minX = Math.min(minX, n.x - 60);
    minY = Math.min(minY, n.y - 40);
    maxX = Math.max(maxX, n.x + 60);
    maxY = Math.max(maxY, n.y + 40);
  }
  const w = Math.max(maxX - minX, 1);
  const h = Math.max(maxY - minY, 1);
  const k = Math.min(1.35, Math.max(0.45, Math.min((VIEW_W - 40) / w, (VIEW_H - 40) / h)));
  const cx = (minX + maxX) / 2;
  const cy = (minY + maxY) / 2;
  state.view = {
    k,
    x: VIEW_W / 2 - cx * k,
    y: VIEW_H / 2 - cy * k
  };
}

/** Interactive offline affiliation network — radial/tree, pan/zoom, filters (mobile OK). */
export function renderAffiliationNetwork(opts: {
  rootId: string;
  rootAccount?: AccountSummaryDto | null;
  snap?: ApexCacheSnapshot | null;
  title?: string;
  subtitle?: string;
  onOpenAccount?: (id: string) => void;
  requestUpdate?: () => void;
}): TemplateResult {
  const rootId = String(opts.rootId || '');
  const bump = () => opts.requestUpdate?.();
  const accounts = opts.snap?.plannerAccounts?.accounts ?? [];
  const rootAccount =
    opts.rootAccount ||
    findAccount(opts.snap ?? null, rootId) ||
    ({
      id: rootId,
      name: 'Account'
    } as AccountSummaryDto);

  if (!rootId) {
    return html`<p class="empty-hint">No account selected for affiliations.</p>`;
  }

  const state = uiFor(rootId);
  const { nodes, edges, hiddenByLevel } = buildGraph(rootId, rootAccount, accounts, state);
  const selectedPath = pathIds(state.selectedId, edges, rootId);
  const q = state.query.trim().toLowerCase();
  const selected = nodes.find((n) => n.id === state.selectedId) || nodes.find((n) => n.id === rootId);
  const transform = `translate(${state.view.x} ${state.view.y}) scale(${state.view.k})`;

  const onWheel = (e: WheelEvent) => {
    e.preventDefault();
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    const factor = e.deltaY < 0 ? 1.12 : 0.9;
    const nextK = Math.min(2.4, Math.max(0.35, state.view.k * factor));
    const wx = (mx - state.view.x) / state.view.k;
    const wy = (my - state.view.y) / state.view.k;
    state.view.k = nextK;
    state.view.x = mx - wx * nextK;
    state.view.y = my - wy * nextK;
    bump();
  };

  const onPointerDown = (e: PointerEvent) => {
    const target = e.target as Element;
    if (target.closest?.('[data-node-id]')) return;
    state.pointerId = e.pointerId;
    state.lastX = e.clientX;
    state.lastY = e.clientY;
    (e.currentTarget as HTMLElement).setPointerCapture?.(e.pointerId);
  };

  const onPointerMove = (e: PointerEvent) => {
    if (state.pointerId !== e.pointerId) return;
    const dx = e.clientX - state.lastX;
    const dy = e.clientY - state.lastY;
    state.lastX = e.clientX;
    state.lastY = e.clientY;
    state.view.x += dx;
    state.view.y += dy;
    bump();
  };

  const onPointerUp = (e: PointerEvent) => {
    if (state.pointerId === e.pointerId) state.pointerId = null;
  };

  const selectNode = (id: string) => {
    if (state.selectedId === id) {
      opts.onOpenAccount?.(id);
      return;
    }
    state.selectedId = id;
    bump();
  };

  const toggleKind = (kind: AffLinkKind) => {
    if (state.enabledKinds.has(kind)) {
      if (state.enabledKinds.size === 1) return;
      state.enabledKinds.delete(kind);
    } else {
      state.enabledKinds.add(kind);
    }
    bump();
  };

  return html`
    <div class="aff-net">
      <div class="aff-net-head">
        <div>
          <h2 class="visit-panel-title" style="margin:0">${opts.title || 'Affiliations Network'}</h2>
          <p class="visit-panel-sub" style="margin:4px 0 0">
            ${opts.subtitle ||
            'Interactive territory network — pan, zoom, filter. Stronger than org list/tree (works offline + on phone).'}
          </p>
        </div>
        <div class="aff-net-layout-toggle">
          <button
            type="button"
            class="aff-chip ${state.layout === 'radial' ? 'is-active' : ''}"
            @click=${() => {
              state.layout = 'radial';
              fitView(state, nodes);
              bump();
            }}
          >
            Radial
          </button>
          <button
            type="button"
            class="aff-chip ${state.layout === 'tree' ? 'is-active' : ''}"
            @click=${() => {
              state.layout = 'tree';
              fitView(state, nodes);
              bump();
            }}
          >
            Tree
          </button>
        </div>
      </div>

      <div class="aff-net-toolbar">
        <div class="aff-net-filters">
          ${(Object.keys(KIND_META) as AffLinkKind[]).map(
            (kind) => html`
              <button
                type="button"
                class="aff-chip ${state.enabledKinds.has(kind) ? 'is-active' : ''}"
                style="--aff-chip:${KIND_META[kind].color}"
                @click=${() => toggleKind(kind)}
              >
                ${KIND_META[kind].label}
              </button>
            `
          )}
        </div>
        <div class="aff-net-depth">
          <span>Depth</span>
          ${([1, 2, 3] as const).map(
            (d) => html`
              <button
                type="button"
                class="aff-chip ${state.depth === d ? 'is-active' : ''}"
                @click=${() => {
                  state.depth = d;
                  bump();
                }}
              >
                ${d}
              </button>
            `
          )}
        </div>
        <input
          class="aff-net-search"
          type="search"
          placeholder="Search accounts…"
          .value=${state.query}
          @input=${(e: Event) => {
            state.query = (e.target as HTMLInputElement).value;
            bump();
          }}
        />
        <button
          type="button"
          class="slds-button slds-button_neutral"
          @click=${() => {
            fitView(state, nodes);
            bump();
          }}
        >
          Fit
        </button>
      </div>

      <div class="aff-net-stage-wrap">
        <div
          class="aff-net-stage"
          @wheel=${onWheel}
          @pointerdown=${onPointerDown}
          @pointermove=${onPointerMove}
          @pointerup=${onPointerUp}
          @pointercancel=${onPointerUp}
        >
          ${nodes.length
            ? svg`
                <svg class="aff-net-svg" viewBox="0 0 ${VIEW_W} ${VIEW_H}" role="img" aria-label="Affiliation network">
                  <defs>
                    <filter id=${`affGlow-${rootId}`} x="-40%" y="-40%" width="180%" height="180%">
                      <feDropShadow dx="0" dy="1" stdDeviation="2.2" flood-color="#0176d3" flood-opacity="0.35"/>
                    </filter>
                  </defs>
                  <g transform=${transform}>
                    ${edges.map((edge) => {
                      const onPath =
                        selectedPath.has(edge.from) && selectedPath.has(edge.to) && selectedPath.size > 1;
                      const primary = edge.kinds[0] || 'brick';
                      const showLabel = onPath || edge.kinds.length === 1;
                      const shortLabel =
                        edge.kinds.length > 1
                          ? `${KIND_META[primary].label}+${edge.kinds.length - 1}`
                          : KIND_META[primary].label;
                      return svg`
                        <g class="aff-edge ${onPath ? 'is-path' : ''}">
                          <path
                            d=${edge.path}
                            fill="none"
                            stroke=${onPath ? '#0176d3' : KIND_META[primary].color}
                            stroke-width=${onPath ? 3.2 : Math.min(2.6, 1 + edge.strength * 0.35)}
                            stroke-opacity=${onPath ? 0.95 : 0.45}
                            stroke-linecap="round"
                          ></path>
                          ${showLabel
                            ? svg`
                          <rect
                            x=${edge.midX - 28}
                            y=${edge.midY - 8}
                            width="56"
                            height="16"
                            rx="8"
                            fill=${onPath ? '#eef4ff' : '#ffffff'}
                            stroke=${KIND_META[primary].color}
                            stroke-opacity=${onPath ? 0.85 : 0.35}
                          ></rect>
                          <text
                            x=${edge.midX}
                            y=${edge.midY + 3.5}
                            text-anchor="middle"
                            font-size="8"
                            font-weight=${onPath ? '700' : '600'}
                            fill=${onPath ? '#014486' : '#3e3e3c'}
                          >${truncate(shortLabel, 12)}</text>`
                            : svg`
                          <circle
                            cx=${edge.midX}
                            cy=${edge.midY}
                            r="3.5"
                            fill=${KIND_META[primary].color}
                            opacity="0.7"
                          ></circle>`}
                        </g>
                      `;
                    })}
                    ${nodes.map((node) => {
                      const selected = node.id === state.selectedId;
                      const onPath = selectedPath.has(node.id);
                      const match = q ? node.label.toLowerCase().includes(q) : false;
                      const dim = q && !match && !selected;
                      const iconFill = textFill(selected, onPath, node.kind);
                      return svg`
                        <g
                          class="aff-node ${selected ? 'is-selected' : ''} ${match ? 'is-match' : ''}"
                          data-node-id=${node.id}
                          opacity=${dim ? 0.28 : 1}
                          style="cursor:pointer"
                          @click=${(e: Event) => {
                            e.stopPropagation();
                            selectNode(node.id);
                          }}
                          @dblclick=${(e: Event) => {
                            e.stopPropagation();
                            opts.onOpenAccount?.(node.id);
                          }}
                        >
                          <circle
                            cx=${node.x}
                            cy=${node.y}
                            r=${NODE_R + (node.kind === 'root' ? 6 : 0)}
                            fill=${fillFor(node.kind, selected, onPath)}
                            stroke=${strokeFor(node.kind, selected, onPath)}
                            stroke-width=${selected ? 3 : 2}
                            filter=${selected || onPath ? `url(#affGlow-${rootId})` : nothing}
                          ></circle>
                          ${accountKindSvgIcon(
                            node.kind,
                            node.x,
                            node.y,
                            iconFill,
                            node.kind === 'root' ? 24 : 20
                          )}
                          <text
                            x=${node.x}
                            y=${node.y + NODE_R + 16}
                            text-anchor="middle"
                            font-size="11"
                            font-weight=${selected ? '700' : '600'}
                            fill="#181818"
                          >${truncate(node.label, state.layout === 'radial' ? 16 : 20)}</text>
                          ${node.specialty || node.city
                            ? svg`<text
                                x=${node.x}
                                y=${node.y + NODE_R + 30}
                                text-anchor="middle"
                                font-size="9"
                                fill="#706e6b"
                              >${truncate([node.specialty, node.city].filter(Boolean).join(' · '), 22)}</text>`
                            : nothing}
                        </g>
                      `;
                    })}
                  </g>
                </svg>
              `
            : html`<div class="aff-net-empty">No affiliation links for the current filters in the offline territory cache.</div>`}
        </div>

        <aside class="aff-net-inspector">
          ${selected
            ? html`
                <div class="aff-inspector-card">
                  <div class="aff-inspector-kicker">
                    ${renderAccountKindBadge(
                      {
                        recordTypeName: selected.recordTypeName,
                        name: selected.label
                      },
                      {
                        label:
                          selected.kind === 'root'
                            ? 'Focus'
                            : accountKindLabel(selected.kind as AccountKind),
                        compact: true
                      }
                    )}
                  </div>
                  <h3>${selected.label}</h3>
                  <p>${selected.recordTypeName || 'Account'} · ${selected.classification || '—'}</p>
                  <p class="meta-line">${selected.specialty || '—'} · ${selected.city || '—'}</p>
                  <p class="meta-line">${selected.brickName || 'No brick'}</p>
                  <div class="aff-inspector-actions">
                    <button
                      type="button"
                      class="slds-button slds-button_brand"
                      @click=${() => opts.onOpenAccount?.(selected.id)}
                    >
                      Open account
                    </button>
                    ${selected.id !== rootId
                      ? html`<button
                          type="button"
                          class="slds-button slds-button_neutral"
                          @click=${() => {
                            if (state.collapsed.has(selected.id)) state.collapsed.delete(selected.id);
                            else state.collapsed.add(selected.id);
                            bump();
                          }}
                        >
                          ${state.collapsed.has(selected.id) ? 'Expand branch' : 'Collapse branch'}
                        </button>`
                      : nothing}
                  </div>
                  <p class="aff-hint">Tap once to select · tap again / double-tap to open · drag canvas to pan · scroll to zoom</p>
                </div>
              `
            : html`<p class="empty-hint">Select a node.</p>`}

          ${[...hiddenByLevel.entries()].map(
            ([level, count]) => html`
              <button
                type="button"
                class="aff-more-btn"
                @click=${() => {
                  const cur = state.levelLimits.get(level) ?? LEVEL_PAGE;
                  state.levelLimits.set(level, cur + LEVEL_PAGE);
                  bump();
                }}
              >
                Show +${count} more at depth ${level}
              </button>
            `
          )}

          <div class="aff-legend">
            <div><span class="dot root"></span> Focus account</div>
            <div class="aff-legend-kind">
              ${renderAccountKindBadge({ recordTypeName: 'HCP' }, { compact: true, label: 'HCP' })}
            </div>
            <div class="aff-legend-kind">
              ${renderAccountKindBadge({ recordTypeName: 'HCO' }, { compact: true, label: 'HCO' })}
            </div>
            <div class="aff-legend-kind">
              ${renderAccountKindBadge({ recordTypeName: 'Pharmacy' }, { compact: true, label: 'Pharmacy' })}
            </div>
          </div>
        </aside>
      </div>

      <div class="aff-net-list">
        <h3 class="slds-text-heading_small">Linked accounts (${Math.max(nodes.length - 1, 0)})</h3>
        ${nodes
          .filter((n) => n.id !== rootId)
          .filter((n) => !q || n.label.toLowerCase().includes(q))
          .map((n) => {
            const edge = edges.find((e) => e.to === n.id);
            return html`
              <button
                type="button"
                class="affil-row aff-list-row ${state.selectedId === n.id ? 'is-selected' : ''}"
                @click=${() => selectNode(n.id)}
              >
                <strong>${n.label}</strong>
                <div class="meta-line affil-meta-row">
                  ${renderAccountKindBadge(
                    { recordTypeName: n.recordTypeName, name: n.label },
                    {
                      label: n.recordTypeName || accountKindLabel(n.kind as AccountKind),
                      compact: true
                    }
                  )}
                  <span>${[n.specialty, n.city].filter(Boolean).join(' · ') || '—'}${edge ? ` · ${edge.label}` : ''}</span>
                </div>
              </button>
            `;
          })}
        ${nodes.length <= 1
          ? html`<p class="empty-hint">No related accounts found in the offline territory cache yet.</p>`
          : nothing}
      </div>
    </div>
  `;
}
