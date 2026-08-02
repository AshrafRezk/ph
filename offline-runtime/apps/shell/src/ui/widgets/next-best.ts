import { html, nothing, type TemplateResult } from 'lit';
import { type NbcRowDto } from '../apex-cache';
import { sldsButton } from '../slds/primitives';

const RANK_META = [
  { iconClass: 'rank-icon rank-icon--first', label: '1st', numeral: '1' },
  { iconClass: 'rank-icon rank-icon--second', label: '2nd', numeral: '2' },
  { iconClass: 'rank-icon rank-icon--third', label: '3rd', numeral: '3' },
  { iconClass: 'rank-icon rank-icon--fourth', label: '4th', numeral: '4' },
  { iconClass: 'rank-icon rank-icon--fifth', label: '5th', numeral: '5' }
];

export function renderFidelityNextBest(opts: {
  label: string;
  rows: NbcRowDto[] | null;
  cached?: boolean;
  onOpenAccount?: (id: string) => void;
  onPlanVisit?: (accountId: string) => void;
}): TemplateResult {
  const rows = opts.rows ?? [];
  return html`
    <article class="osr-lwc-mirror slds-card nbc-card">
      <div class="nbc-header slds-p-around_small">
        <h2 class="nbc-title">
          Top 5 NBC
          ${opts.cached ? html`<span class="osr-cache-pill">Cached</span>` : nothing}
        </h2>
        <p class="nbc-subtitle">Next best customers to prioritize today</p>
      </div>
      <div class="nbc-list slds-p-around_small">
        ${rows.length === 0
          ? html`<div class="home-empty home-empty-compact nbc-empty">
              <div class="home-empty-icon" aria-hidden="true">${targetSvg()}</div>
              <strong class="home-empty-title">No next best customers yet</strong>
              <p class="home-empty-copy">
                Recommendations appear once account scores and call plans sync for your territory.
              </p>
            </div>`
          : rows.map((r) => {
              const meta = RANK_META[Math.max(0, (r.rank ?? 1) - 1)] ?? RANK_META[4];
              const score = Math.round(Number(r.score ?? 0));
              const actual = Math.round(Number(r.actualVisits ?? 0));
              const target = Math.round(Number(r.targetVisits ?? 0));
              const barPct = target > 0 ? Math.min(100, (actual / target) * 100) : 0;
              return html`
                <div class="nbc-row">
                  <div class=${meta.iconClass} title=${meta.label}>
                    <span class="rank-numeral">${meta.numeral}</span>
                  </div>
                  <div class="cell account">
                    <button
                      type="button"
                      class="account-link"
                      @click=${() => r.accountId && opts.onOpenAccount?.(String(r.accountId))}
                    >
                      ${r.accountName || 'Account'}
                    </button>
                  </div>
                  <div class="cell action">
                    ${sldsButton('Plan call', {
                      variant: 'neutral',
                      className: 'plan-call-btn',
                      onClick: () => r.accountId && opts.onPlanVisit?.(String(r.accountId))
                    })}
                  </div>
                  <div class="nbc-meta-row">
                    <div class="nbc-stat">
                      <div class="cell-label">Call plan</div>
                      <div class="cell-value">${actual}/${target}</div>
                      <div class="nbc-mini-track" aria-hidden="true">
                        <div class="nbc-mini-fill" style="width:${barPct}%"></div>
                      </div>
                    </div>
                    <div class="nbc-stat">
                      <div class="cell-label">Planned</div>
                      <span class="nbc-planned-pill ${r.planned ? 'is-yes' : 'is-no'}"
                        >${r.planned ? 'Yes' : 'No'}</span
                      >
                    </div>
                    <div class="nbc-stat nbc-stat-score">
                      <div class="cell-label">Score</div>
                      <div class="score-circle">
                        <span class="score-value">${score}</span>
                      </div>
                    </div>
                  </div>
                </div>
              `;
            })}
      </div>
    </article>
  `;
}

function targetSvg(): TemplateResult {
  return html`<svg width="40" height="40" viewBox="0 0 48 48" fill="none" aria-hidden="true">
    <circle cx="24" cy="24" r="18" stroke="#c9d7e8" stroke-width="2.5" />
    <circle cx="24" cy="24" r="11" stroke="#91c8f7" stroke-width="2.5" />
    <circle cx="24" cy="24" r="4" fill="#0176d3" />
  </svg>`;
}
