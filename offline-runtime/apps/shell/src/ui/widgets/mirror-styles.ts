import { css, unsafeCSS } from 'lit';
import { sldsTokensCss } from '../slds/tokens';
import leafletCss from 'leaflet/dist/leaflet.css?inline';
import todayPlanCss from './styles/today-plan.css?inline';
import metricsCss from './styles/metrics.css?inline';
import nextBestCss from './styles/next-best.css?inline';
import messagesCss from './styles/messages.css?inline';
import clmCss from './styles/clm-prefetch.css?inline';
import plannerCss from './styles/planner.css?inline';
import accountsTabCss from './styles/accounts-tab.css?inline';
import visitCallShellCss from './styles/visit-call-shell.css?inline';
import affiliationNetworkCss from './styles/affiliation-network.css?inline';

/** Org LWC CSS + SLDS token bridge + Leaflet (shadow-DOM safe). */
export const mirrorStyles = css`
  ${unsafeCSS(sldsTokensCss)}
  ${unsafeCSS(leafletCss)}
  ${unsafeCSS(todayPlanCss)}
  ${unsafeCSS(metricsCss)}
  ${unsafeCSS(nextBestCss)}
  ${unsafeCSS(messagesCss)}
  ${unsafeCSS(clmCss)}
  ${unsafeCSS(plannerCss)}
  ${unsafeCSS(accountsTabCss)}
  ${unsafeCSS(visitCallShellCss)}
  ${unsafeCSS(affiliationNetworkCss)}

  /* Shell supplements for interactive chrome shared across overlays */
  .osr-lwc-mirror .scope-chip {
    border: 1px solid #dddbda;
    background: #fff;
    color: #0176d3;
    border-radius: 999px;
    padding: 4px 10px;
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
  }
  .osr-lwc-mirror .scope-chip.active {
    background: #eef4ff;
    border-color: #0176d3;
  }
  .osr-lwc-mirror .account-search {
    width: 100%;
    margin: 6px 0 8px;
    padding: 8px 10px;
    border: 1px solid #dddbda;
    border-radius: 6px;
    font: inherit;
  }
  .osr-lwc-mirror .pager {
    display: flex;
    gap: 8px;
    align-items: center;
    justify-content: center;
    margin-top: 8px;
  }
  .osr-lwc-mirror .account-row {
    display: flex;
    flex-direction: column;
    gap: 2px;
    width: 100%;
    text-align: left;
    border: 1px solid #e5e5e5;
    border-radius: 6px;
    padding: 8px 10px;
    margin-bottom: 6px;
    background: #fff;
    cursor: pointer;
  }
  .osr-lwc-mirror .leaderboard-toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 8px;
    margin-top: 10px;
  }
  .osr-lwc-mirror .scope-chips {
    display: flex;
    gap: 6px;
  }
  .osr-lwc-mirror .planner-toolbar {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    align-items: center;
    justify-content: space-between;
    padding: 10px 12px;
    border-bottom: 1px solid #e5e5e5;
  }
  .osr-lwc-mirror .week-label {
    font-weight: 700;
    color: #032d60;
    min-width: 140px;
    text-align: center;
  }
  .osr-lwc-mirror .cal-event.scheduled {
    background: #eef4ff;
    border: 1px solid #0176d3;
  }
  .osr-lwc-mirror .cal-event.cancelled {
    background: #f3f3f3;
    border: 1px solid #c9c9c9;
    opacity: 0.7;
  }
  .osr-lwc-mirror .cal-event.tot {
    background: #fce4ec;
    border: 1px solid #c2185b;
  }
  .osr-lwc-mirror .cal-col.weekend {
    background: rgba(0, 0, 0, 0.02);
  }
  .osr-lwc-mirror .acct-card.selected {
    border-color: #0176d3;
    box-shadow: 0 0 0 1px #0176d3 inset;
  }
  .osr-lwc-mirror .leaflet-container {
    width: 100%;
    height: 100%;
    min-height: 280px;
    border-radius: 8px;
    z-index: 0;
    background: #e8eef5;
  }
  .osr-lwc-mirror .planner-shell {
    height: calc(100vh - 7rem);
    min-height: 32rem;
  }
  .osr-lwc-mirror .account-chip {
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
    width: calc(100% - 0.75rem);
    margin: 0 0.375rem 0.375rem;
    padding: 0.5rem 0.625rem;
    text-align: left;
    border: 1px solid #dddbda;
    border-radius: 0.375rem;
    background: #fff;
    cursor: pointer;
    font: inherit;
  }
  .osr-lwc-mirror .account-chip.is-selected {
    border-color: #0176d3;
    box-shadow: 0 0 0 1px #0176d3 inset;
  }
  .osr-lwc-mirror .account-chip-name {
    font-weight: 700;
    color: #032d60;
    font-size: 0.8125rem;
  }
  .osr-lwc-mirror .account-chip-meta {
    font-size: 0.6875rem;
    color: #706e6b;
  }
  .osr-lwc-mirror .account-list {
    flex: 1;
    overflow: auto;
    min-height: 0;
    padding-bottom: 0.5rem;
  }
  .osr-lwc-mirror .account-count-label {
    font-size: 0.6875rem;
    color: #706e6b;
    margin-top: 0.35rem;
  }
  .osr-lwc-mirror .collection-chip {
    border: 1px solid #dddbda;
    background: #fff;
    border-radius: 999px;
    padding: 0.25rem 0.625rem;
    font-size: 0.75rem;
    cursor: pointer;
  }
  .osr-lwc-mirror .collection-chip.is-active {
    border-color: #0176d3;
    background: #eef4ff;
    color: #0176d3;
  }
  .osr-lwc-mirror .collection-chips-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.35rem;
    padding: 0 0.75rem 0.5rem;
  }
  .osr-lwc-mirror .slds-col_bump-left {
    margin-left: auto;
  }
  .osr-lwc-mirror .slds-button_success {
    background: #2e844a;
    border-color: #2e844a;
    color: #fff;
  }
  .osr-lwc-mirror .slds-button_success:disabled {
    opacity: 0.45;
  }
  .osr-lwc-mirror .map-view .map-container {
    min-height: 24rem;
    height: 100%;
  }

  /* ── Shared Field Home empty states ── */
  .osr-lwc-mirror .home-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 0.5rem;
    text-align: center;
    padding: 1.75rem 1.25rem;
    border-radius: 0.75rem;
    background:
      radial-gradient(ellipse at 50% 0%, rgba(1, 118, 211, 0.08) 0%, transparent 55%),
      linear-gradient(180deg, #f7fbff 0%, #ffffff 100%);
    border: 1px solid rgba(1, 118, 211, 0.12);
    animation: homeEmptyIn 0.45s ease;
  }
  .osr-lwc-mirror .home-empty-compact {
    padding: 1.25rem 1rem;
  }
  .osr-lwc-mirror .home-empty-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    margin-bottom: 0.15rem;
  }
  .osr-lwc-mirror .home-empty-title {
    font-size: 0.9375rem;
    font-weight: 700;
    color: #032d60;
    line-height: 1.35;
  }
  .osr-lwc-mirror .home-empty-copy {
    margin: 0;
    max-width: 22rem;
    font-size: 0.8125rem;
    color: #706e6b;
    line-height: 1.45;
  }
  .osr-lwc-mirror .home-empty-cta {
    margin-top: 0.5rem;
  }
  @keyframes homeEmptyIn {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  /* Today's Plan empty — illustrated route */
  .osr-lwc-mirror .today-plan-empty .home-empty-visual {
    margin-bottom: 0.35rem;
  }
  .osr-lwc-mirror .today-empty-map {
    position: relative;
    width: 9.5rem;
    height: 5.5rem;
    border-radius: 0.75rem;
    background:
      linear-gradient(135deg, rgba(1, 118, 211, 0.06) 0%, rgba(1, 118, 211, 0.02) 100%),
      repeating-linear-gradient(
        90deg,
        transparent,
        transparent 11px,
        rgba(1, 118, 211, 0.06) 11px,
        rgba(1, 118, 211, 0.06) 12px
      ),
      repeating-linear-gradient(
        0deg,
        transparent,
        transparent 11px,
        rgba(1, 118, 211, 0.06) 11px,
        rgba(1, 118, 211, 0.06) 12px
      );
    border: 1px solid rgba(1, 118, 211, 0.14);
    overflow: hidden;
  }
  .osr-lwc-mirror .today-empty-route {
    position: absolute;
    left: 18%;
    top: 58%;
    width: 64%;
    height: 2px;
    background: linear-gradient(90deg, #0176d3, #91c8f7);
    border-radius: 2px;
    transform: rotate(-8deg);
    opacity: 0.85;
  }
  .osr-lwc-mirror .today-empty-pin {
    position: absolute;
    width: 0.7rem;
    height: 0.7rem;
    border-radius: 50% 50% 50% 0;
    background: #0176d3;
    transform: rotate(-45deg);
    box-shadow: 0 2px 6px rgba(1, 118, 211, 0.35);
    animation: todayPinPulse 2.2s ease-in-out infinite;
  }
  .osr-lwc-mirror .today-empty-pin-a {
    left: 16%;
    top: 42%;
  }
  .osr-lwc-mirror .today-empty-pin-b {
    left: 48%;
    top: 22%;
    background: #6a1b9a;
    animation-delay: 0.35s;
  }
  .osr-lwc-mirror .today-empty-pin-c {
    left: 74%;
    top: 48%;
    animation-delay: 0.7s;
  }
  @keyframes todayPinPulse {
    0%,
    100% {
      transform: rotate(-45deg) scale(1);
    }
    50% {
      transform: rotate(-45deg) scale(1.12);
    }
  }

  /* NBC sidebar polish */
  .osr-lwc-mirror .nbc-card .rank-numeral {
    font-size: 0.875rem;
    font-weight: 800;
    color: inherit;
    line-height: 1;
  }
  .osr-lwc-mirror .nbc-card .rank-icon--first {
    color: #5c4a00;
  }
  .osr-lwc-mirror .nbc-card .rank-icon--second {
    color: #3e3e3c;
  }
  .osr-lwc-mirror .nbc-card .rank-icon--third {
    color: #4a2c0a;
  }
  .osr-lwc-mirror .nbc-card .rank-icon--fourth {
    color: #014486;
  }
  .osr-lwc-mirror .nbc-card .rank-icon--fifth {
    color: #3b1f6e;
  }
  .osr-lwc-mirror .nbc-mini-track {
    margin-top: 0.25rem;
    height: 3px;
    border-radius: 2px;
    background: rgba(0, 0, 0, 0.08);
    overflow: hidden;
  }
  .osr-lwc-mirror .nbc-mini-fill {
    height: 100%;
    border-radius: 2px;
    background: #0176d3;
  }
  .osr-lwc-mirror .nbc-planned-pill {
    display: inline-flex;
    padding: 0.1rem 0.45rem;
    border-radius: 999px;
    font-size: 0.6875rem;
    font-weight: 700;
  }
  .osr-lwc-mirror .nbc-planned-pill.is-yes {
    background: #e8f5e9;
    color: #1b5e20;
  }
  .osr-lwc-mirror .nbc-planned-pill.is-no {
    background: #f3f3f3;
    color: #706e6b;
  }
  .osr-lwc-mirror .ho-header-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 2rem;
    height: 2rem;
    border-radius: 0.5rem;
    background: linear-gradient(135deg, #eef4ff 0%, #f7fbff 100%);
    border: 1px solid rgba(1, 118, 211, 0.16);
    flex-shrink: 0;
  }
  /* Narrow sidebar: stack NBC as compact cards — handled in next-best.css */
  .osr-lwc-mirror .ho-empty-panel,
  .osr-lwc-mirror .nbc-empty {
    margin: 0 0.25rem 0.75rem;
  }
`;
