import { html, nothing, type TemplateResult } from 'lit';
import {
  type HomeMetricsDto,
  type GamificationDto,
  type RankingsDto,
  type AccountCoverageRowDto,
  pct
} from '../apex-cache';

const BADGE_DEFINITIONS = [
  {
    id: 'coverage_champion',
    label: 'Coverage Champion',
    icon: '🏆',
    hint: 'Reach 80% visit coverage this cycle'
  },
  {
    id: 'on_target',
    label: 'On Target',
    icon: '🎯',
    hint: 'Achieve 100% of your call plan'
  },
  {
    id: 'class_a_ace',
    label: 'Class A Ace',
    icon: '⭐',
    hint: 'Reach 90% Class A visit coverage'
  },
  {
    id: 'streak_starter',
    label: 'Streak Starter',
    icon: '🔥',
    hint: 'Log visits on 3 consecutive working days'
  },
  {
    id: 'perfect_week',
    label: 'Perfect Week',
    icon: '📅',
    hint: 'Visit accounts every weekday this week'
  },
  {
    id: 'early_bird',
    label: 'Early Bird',
    icon: '🌅',
    hint: 'Check in before 9 AM on any field day'
  }
];

const CLASS_COLORS: Record<string, { accent: string; bg: string }> = {
  A: { accent: '#0176d3', bg: 'rgba(1, 118, 211, 0.07)' },
  B: { accent: '#2e844a', bg: 'rgba(46, 132, 74, 0.08)' },
  C: { accent: '#fe9339', bg: 'rgba(254, 147, 57, 0.1)' }
};

const TIER_CONFIG: Record<
  string,
  { label: string; icon: string; accent: string; bg: string }
> = {
  starter: {
    label: 'Starter',
    icon: '🌱',
    accent: '#8b9196',
    bg: 'rgba(139, 145, 150, 0.07)'
  },
  builder: {
    label: 'Builder',
    icon: '🔨',
    accent: '#cd7f32',
    bg: 'rgba(205, 127, 50, 0.09)'
  },
  achiever: {
    label: 'Achiever',
    icon: '⚡',
    accent: '#0176d3',
    bg: 'rgba(1, 118, 211, 0.08)'
  },
  champion: {
    label: 'Champion',
    icon: '🏆',
    accent: '#f4b400',
    bg: 'rgba(244, 180, 0, 0.1)'
  },
  legend: {
    label: 'Legend',
    icon: '⭐',
    accent: '#7c4dff',
    bg: 'rgba(124, 77, 255, 0.1)'
  }
};

const NEXT_TIER: Record<string, { threshold: number; label: string }> = {
  starter: { threshold: 25, label: 'Builder' },
  builder: { threshold: 50, label: 'Achiever' },
  achiever: { threshold: 80, label: 'Champion' },
  champion: { threshold: 100, label: 'Legend' }
};

const TIER_TAGLINES: Record<string, string[]> = {
  starter: ['Keep pushing!', 'Every visit counts', 'Build your foundation'],
  builder: ['Almost there!', 'Building momentum', 'Keep climbing'],
  achiever: ['On fire!', 'Strong progress', "You're crushing it"],
  champion: ['Champion level!', 'So close to Legend', 'Elite performance'],
  legend: ['Legend status!', 'Maximum impact!', 'At the top!']
};

const RING_R = 28;
const RING_C = 2 * Math.PI * RING_R;
const PAGE_SIZE = 5;
const MILESTONES = [25, 50, 80, 100];

function resolveTierId(percent: number): string {
  const p = Math.round(percent || 0);
  if (p >= 100) return 'legend';
  if (p >= 80) return 'champion';
  if (p >= 50) return 'achiever';
  if (p >= 25) return 'builder';
  return 'starter';
}

function taglineFor(tierId: string, percent: number): string {
  const lines = TIER_TAGLINES[tierId] || TIER_TAGLINES.starter;
  return lines[Math.floor((percent || 0) / 10) % lines.length];
}

function buildKpi(id: string, label: string, hint: string, value: number) {
  const percent = Math.round(value || 0);
  const tierId = resolveTierId(percent);
  const tier = TIER_CONFIG[tierId];
  const next = NEXT_TIER[tierId];
  const gap = next ? Math.max(0, next.threshold - percent) : 0;
  const offset = RING_C - (Math.min(100, Math.max(0, percent)) / 100) * RING_C;
  return {
    id,
    label,
    hint,
    percent,
    tierId,
    tier,
    tagline: taglineFor(tierId, percent),
    offset,
    showNext: Boolean(next && gap > 0),
    nextLabel: next ? `${gap}% to ${next.label}` : '',
    sparkle: MILESTONES.some((m) => percent === m || (m === 100 && percent > 100)),
    cardClass: `kpi-card kpi-card-tier-${tierId}${tierId === 'legend' ? ' kpi-card-legend' : ''}`,
    cardStyle: `border-left-color:${tier.accent};background:linear-gradient(135deg,${tier.bg} 0%,#fff 100%)`,
    ringFillClass: `kpi-ring-fill kpi-ring-fill-tier-${tierId}${tierId === 'legend' ? ' kpi-ring-legend-pulse' : ''}`,
    tierPillClass: `kpi-tier-pill kpi-tier-pill-${tierId}`
  };
}

function statusClass(status: string | null | undefined): string {
  const s = String(status ?? '').toUpperCase();
  if (s === 'LCF') return 'status-lcf';
  if (s === 'RCF') return 'status-rcf';
  if (s === 'MCF') return 'status-mcf';
  return 'status-neutral';
}

export function renderFidelityMetrics(opts: {
  label: string;
  metrics: HomeMetricsDto | null;
  gamification: GamificationDto | null;
  rankings: RankingsDto | null;
  accountCoverage?: AccountCoverageRowDto[] | null;
  cached?: boolean;
  leaderboardScope?: 'bu' | 'company';
  filter?: string;
  search?: string;
  page?: number;
  onScope?: (s: 'bu' | 'company') => void;
  onFilter?: (f: string) => void;
  onSearch?: (q: string) => void;
  onPage?: (p: number) => void;
  onOpenAccount?: (id: string) => void;
}): TemplateResult {
  const m = opts.metrics;
  const g = opts.gamification;
  const r = opts.rankings;
  const activity = g?.streaks?.activityStreak ?? 0;
  const coverage = g?.streaks?.coverageStreak ?? 0;
  const gauges = [
    buildKpi('visit', 'Visit Coverage', 'Actual vs target visits', pct(m?.visitCoveragePercent)),
    buildKpi(
      'customer',
      'Customer Coverage',
      'Accounts visited this cycle',
      pct(m?.customerCoveragePercent)
    ),
    buildKpi('rf', 'Right Frequency', 'RCF across all accounts', pct(m?.rfPercentTotal))
  ];
  const scope = opts.leaderboardScope ?? 'bu';
  const top = scope === 'bu' ? (r?.top5InBu ?? []) : (r?.top5Company ?? []);
  const showRankings = (r?.buTotal || 0) > 0 || (r?.companyTotal || 0) > 0;
  const badges = BADGE_DEFINITIONS.map((def) => {
    const raw = (g?.badges ?? []).find((b) => b.badgeId === def.id);
    return {
      ...def,
      earned: !!raw?.earned,
      progress: pct(raw?.progressPercent)
    };
  });
  const earned = badges.filter((b) => b.earned).length;
  const byClass = m?.byClassification ?? [];
  const filter = opts.filter ?? 'All';
  const search = (opts.search ?? '').toLowerCase();
  const page = opts.page ?? 0;
  let accounts = (opts.accountCoverage ?? []) as AccountCoverageRowDto[];
  if (filter !== 'All') {
    accounts = accounts.filter(
      (a) => String(a.calculatedClassification ?? '').toUpperCase() === filter
    );
  }
  if (search) {
    accounts = accounts.filter((a) =>
      `${a.accountName ?? ''} ${a.specialty ?? ''} ${a.city ?? ''}`.toLowerCase().includes(search)
    );
  }
  const pageCount = Math.max(1, Math.ceil(accounts.length / PAGE_SIZE));
  const pageRows = accounts.slice(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE);
  const rangeStart = accounts.length ? page * PAGE_SIZE + 1 : 0;
  const rangeEnd = Math.min(accounts.length, (page + 1) * PAGE_SIZE);
  const title =
    !opts.label || opts.label === 'Metrics' || /field.?rep.?home.?metrics/i.test(opts.label)
      ? 'Your Performance'
      : opts.label;

  return html`
    <article class="osr-lwc-mirror perf-card">
      <header class="perf-header">
        <div class="perf-header-top">
          <div>
            <h2 class="perf-title">
              ${title}
              ${opts.cached ? html`<span class="osr-cache-pill">Cached</span>` : nothing}
            </h2>
            <p class="perf-subtitle">Month-to-date coverage and call frequency</p>
          </div>
          ${activity > 0 || coverage > 0
            ? html`
                <div class="streak-banner" aria-live="polite">
                  ${activity > 0
                    ? html`<span class="streak-pill streak-pill-activity"
                        >🔥 ${activity}-day activity streak</span
                      >`
                    : nothing}
                  ${coverage > 0
                    ? html`<span class="streak-pill streak-pill-coverage"
                        >💪 ${coverage}-day coverage streak</span
                      >`
                    : nothing}
                </div>
              `
            : nothing}
        </div>
      </header>

      <div class="perf-body">
        <div class="kpi-row" role="list" aria-label="Performance KPI rings">
          ${gauges.map(
            (kpi) => html`
              <div
                class=${kpi.cardClass}
                style=${kpi.cardStyle}
                role="listitem"
                aria-label="${kpi.label}: ${kpi.percent} percent, ${kpi.tier.label} tier. ${kpi.tagline}"
              >
                <div class="kpi-card-inner">
                  <div class="kpi-card-meta">
                    <span class=${kpi.tierPillClass}>
                      <span class="kpi-tier-icon" aria-hidden="true">${kpi.tier.icon}</span>
                      <span class="kpi-tier-text">${kpi.tier.label}</span>
                    </span>
                    <span class="kpi-label">${kpi.label}</span>
                    <span class="kpi-tagline">${kpi.tagline}</span>
                    ${kpi.showNext
                      ? html`<span class="kpi-next-tier">${kpi.nextLabel}</span>`
                      : nothing}
                    <span class="kpi-hint">${kpi.hint}</span>
                  </div>
                  <div class="kpi-ring-wrap">
                    <svg class="kpi-ring-svg" viewBox="0 0 64 64" aria-hidden="true">
                      <circle class="kpi-ring-bg" cx="32" cy="32" r=${RING_R}></circle>
                      <circle
                        class=${kpi.ringFillClass}
                        cx="32"
                        cy="32"
                        r=${RING_R}
                        style="stroke-dasharray:${RING_C};stroke-dashoffset:${kpi.offset}"
                      ></circle>
                    </svg>
                    <span class="kpi-ring-value" aria-hidden="true">${kpi.percent}%</span>
                    ${kpi.sparkle
                      ? html`<span class="kpi-sparkle" aria-hidden="true" title="Milestone reached"
                          >✨</span
                        >`
                      : nothing}
                  </div>
                </div>
              </div>
            `
          )}
        </div>

        ${showRankings && r
          ? html`
              <section class="competition-section" aria-label="Performance rankings">
                <div class="competition-header">
                  <h3 class="section-label">Competition</h3>
                  <span class="competition-hint">Ranked by visit coverage</span>
                </div>

                <div class="rank-summary-row">
                  <div class="rank-summary-card">
                    <span class="rank-summary-label">My rank in BU</span>
                    <span class="rank-summary-value"
                      >${r.buRank && r.buTotal
                        ? `#${r.buRank} of ${r.buTotal} in ${r.buName || 'your team'}`
                        : '—'}</span
                    >
                  </div>
                  <div class="rank-summary-card">
                    <span class="rank-summary-label">Company-wide</span>
                    <span class="rank-summary-value"
                      >${r.companyRank && r.companyTotal
                        ? `#${r.companyRank} of ${r.companyTotal} reps`
                        : '—'}</span
                    >
                  </div>
                </div>

                ${r.isFirstInBu
                  ? html`<div class="first-place-card" aria-live="polite">
                      <span class="first-place-icon" aria-hidden="true">🏆</span>
                      <p class="first-place-message">
                        You're #1 in ${r.buName || 'your BU'}! Keep it up.
                      </p>
                    </div>`
                  : r.personAbove
                    ? html`<div class="catch-up-card" aria-live="polite">
                        <span class="catch-up-icon" aria-hidden="true">🏃</span>
                        <p class="catch-up-message">
                          ${r.personAbove.gapPercent ?? '?'}% behind ${r.personAbove.name} (#${r
                            .personAbove.rank})
                        </p>
                      </div>`
                    : nothing}

                <div class="leaderboard-panel">
                  <div class="leaderboard-toolbar">
                    <span class="leaderboard-title"
                      >Top 5 — ${scope === 'bu' ? r.buName || 'BU' : 'Company'}</span
                    >
                    <div class="scope-chips" role="tablist" aria-label="Leaderboard scope">
                      <button
                        type="button"
                        class="scope-chip ${scope === 'bu' ? 'scope-chip-active' : ''}"
                        role="tab"
                        aria-selected=${scope === 'bu'}
                        @click=${() => opts.onScope?.('bu')}
                      >
                        BU
                      </button>
                      <button
                        type="button"
                        class="scope-chip ${scope === 'company' ? 'scope-chip-active' : ''}"
                        role="tab"
                        aria-selected=${scope === 'company'}
                        @click=${() => opts.onScope?.('company')}
                      >
                        Company
                      </button>
                    </div>
                  </div>
                  <div class="leaderboard-list" role="list">
                    ${top.map(
                      (e) => html`
                        <div
                          class="leaderboard-row ${e.isCurrentUser ? 'leaderboard-row-you' : ''}"
                          role="listitem"
                        >
                          <span class="leaderboard-rank">#${e.rank}</span>
                          <span class="leaderboard-medal" aria-hidden="true"
                            >${e.badgeIcon || ''}</span
                          >
                          <span class="leaderboard-name"
                            >${e.name}${e.isCurrentUser ? ' (you)' : ''}</span
                          >
                          <span class="leaderboard-coverage">${pct(e.coveragePercent)}%</span>
                        </div>
                      `
                    )}
                  </div>
                </div>
              </section>
            `
          : nothing}

        <section class="achievements-section">
          <div class="achievements-header">
            <h3 class="section-label">Achievements</h3>
            <span class="achievements-summary">${earned} of ${badges.length} earned</span>
          </div>
          <div class="achievements-row" role="list" aria-label="Performance badges">
            ${badges.map(
              (b) => html`
                <button
                  type="button"
                  class="achievement-badge ${b.earned
                    ? 'achievement-badge-earned'
                    : 'achievement-badge-locked'}"
                  role="listitem"
                  title=${b.hint}
                  aria-label=${b.earned
                    ? `${b.label} earned`
                    : `${b.label}: ${b.progress}% — ${b.hint}`}
                >
                  <span class="achievement-icon" aria-hidden="true">${b.icon}</span>
                  <span class="achievement-label">${b.label}</span>
                  ${b.earned
                    ? nothing
                    : html`<span class="achievement-progress">${b.progress}%</span>`}
                </button>
              `
            )}
          </div>
        </section>

        ${byClass.length
          ? html`
              <section class="class-section">
                <h3 class="section-label">By classification</h3>
                <div class="class-row">
                  ${byClass.map((c) => {
                    const name = String(c.classification ?? '').toUpperCase() || '?';
                    const colors = CLASS_COLORS[name] || {
                      accent: '#706e6b',
                      bg: '#f3f3f3'
                    };
                    const visitPct = pct(c.visitCoveragePercent);
                    return html`
                      <div
                        class="class-card"
                        style="background:${colors.bg};border-left:4px solid ${colors.accent}"
                      >
                        <div class="class-card-header">
                          <span class="class-badge">Class ${name}</span>
                          <span class="class-primary">${visitPct}%</span>
                        </div>
                        <div class="class-bar-track">
                          <div
                            class="class-bar-fill"
                            style="width:${visitPct}%;background:${colors.accent}"
                          ></div>
                        </div>
                        <div class="class-stats">
                          <span class="class-stat">
                            <span class="class-stat-label">Customers</span>
                            <span class="class-stat-value">${pct(c.customerCoveragePercent)}%</span>
                          </span>
                          <span class="class-stat">
                            <span class="class-stat-label">RF</span>
                            <span class="class-stat-value">${pct(c.rfPercent)}%</span>
                          </span>
                          <span class="class-stat">
                            <span class="class-stat-label">LF</span>
                            <span class="class-stat-value">${pct(c.lfPercent)}%</span>
                          </span>
                        </div>
                      </div>
                    `;
                  })}
                </div>
              </section>
            `
          : !m
            ? html`<div class="home-empty">
                <div class="home-empty-icon" aria-hidden="true">${emptyChartSvg()}</div>
                <strong class="home-empty-title">Metrics not synced yet</strong>
                <p class="home-empty-copy">Pull to sync when online to load your coverage KPIs.</p>
              </div>`
            : nothing}

        <section class="accounts-section">
          <div class="accounts-header">
            <div>
              <h3 class="section-label">Account drill-down</h3>
              <span class="account-count">${accounts.length} accounts</span>
            </div>
            <div class="filter-chips" role="tablist" aria-label="Filter by class">
              ${['All', 'A', 'B', 'C'].map(
                (f) => html`
                  <button
                    type="button"
                    class="filter-chip ${filter === f ? 'filter-chip-active' : ''}"
                    role="tab"
                    aria-selected=${filter === f}
                    @click=${() => {
                      opts.onFilter?.(f);
                      opts.onPage?.(0);
                    }}
                  >
                    ${f}
                  </button>
                `
              )}
            </div>
          </div>

          <div class="accounts-toolbar">
            <div class="search-field">
              <input
                type="search"
                class="account-search-input"
                placeholder="Search name, specialty, city…"
                aria-label="Search accounts"
                .value=${opts.search ?? ''}
                @input=${(e: Event) => {
                  opts.onSearch?.((e.target as HTMLInputElement).value);
                  opts.onPage?.(0);
                }}
              />
            </div>
          </div>

          ${pageRows.length === 0
            ? html`<div class="home-empty home-empty-compact">
                <strong class="home-empty-title"
                  >${search || filter !== 'All'
                    ? 'No accounts match'
                    : 'No account coverage yet'}</strong
                >
                <p class="home-empty-copy">
                  ${search || filter !== 'All'
                    ? 'Try another filter or clear your search.'
                    : 'Coverage rows appear after your first sync of the cycle.'}
                </p>
              </div>`
            : html`
                <div class="account-table">
                  <div class="account-table-head">
                    <span class="account-th">Account</span>
                    <span class="account-th">Class</span>
                    <span class="account-th">Call plan</span>
                    <span class="account-th">Reach %</span>
                    <span class="account-th">Frequency</span>
                    <span class="account-th">Visited</span>
                  </div>
                  ${pageRows.map((a) => {
                    const actual = Number(a.actualVisits ?? 0);
                    const target = Number(a.targetVisits ?? 0);
                    const reach = pct(
                      a.reachPercent ?? (target > 0 ? (actual / target) * 100 : 0)
                    );
                    const barPct = Math.max(
                      0,
                      Math.min(100, target > 0 ? (actual / target) * 100 : 0)
                    );
                    return html`
                      <div class="account-table-row">
                        <div class="account-cell account-name-cell">
                          <button
                            type="button"
                            class="account-link"
                            @click=${() => a.accountId && opts.onOpenAccount?.(String(a.accountId))}
                          >
                            ${a.accountName || 'Account'}
                          </button>
                          ${a.specialty
                            ? html`<span class="account-sub">${a.specialty}</span>`
                            : nothing}
                          ${a.city ? html`<span class="account-sub">${a.city}</span>` : nothing}
                        </div>
                        <div class="account-cell">
                          <span class="class-pill">${a.calculatedClassification || '—'}</span>
                        </div>
                        <div class="account-cell">
                          <span class="cell-value">${actual}/${target}</span>
                          <div class="mini-bar-track">
                            <div class="mini-bar-fill" style="width:${barPct}%"></div>
                          </div>
                        </div>
                        <div class="account-cell">
                          <span class="cell-value">${reach}%</span>
                        </div>
                        <div class="account-cell">
                          <span class=${statusClass(a.frequencyStatus)}
                            >${a.frequencyStatus || '—'}</span
                          >
                        </div>
                        <div class="account-cell">
                          <span class=${a.isVisited ? 'visited-yes' : 'visited-no'}
                            >${a.isVisited ? 'Yes' : 'No'}</span
                          >
                        </div>
                      </div>
                    `;
                  })}
                </div>
                <div class="pagination-bar">
                  <span class="pagination-range"
                    >${rangeStart}–${rangeEnd} of ${accounts.length}</span
                  >
                  <div class="pagination-controls">
                    <button
                      type="button"
                      class="page-btn"
                      ?disabled=${page <= 0}
                      @click=${() => opts.onPage?.(page - 1)}
                    >
                      Previous
                    </button>
                    <span class="page-label">${page + 1} / ${pageCount}</span>
                    <button
                      type="button"
                      class="page-btn"
                      ?disabled=${page + 1 >= pageCount}
                      @click=${() => opts.onPage?.(page + 1)}
                    >
                      Next
                    </button>
                  </div>
                </div>
              `}
        </section>
      </div>
    </article>
  `;
}

function emptyChartSvg(): TemplateResult {
  return html`<svg width="48" height="48" viewBox="0 0 48 48" fill="none" aria-hidden="true">
    <circle cx="24" cy="24" r="20" stroke="#c9d7e8" stroke-width="3" />
    <path
      d="M24 8a16 16 0 0 1 16 16"
      stroke="#0176d3"
      stroke-width="3"
      stroke-linecap="round"
    />
    <circle cx="24" cy="24" r="6" fill="#eef4ff" stroke="#0176d3" stroke-width="2" />
  </svg>`;
}
