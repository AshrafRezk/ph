import { html, nothing, type TemplateResult } from 'lit';
import type { LocationTrackerState } from '../../location/rep-location-tracker';

export function renderRepLocationPublisher(opts: {
  label?: string;
  state: LocationTrackerState;
  onToggleSharing?: (enabled: boolean) => void;
}): TemplateResult {
  const { state } = opts;
  const point = state.lastPoint;
  const coords =
    point != null
      ? `${point.latitude.toFixed(5)}, ${point.longitude.toFixed(5)}`
      : 'Waiting for GPS fix…';
  const accuracy =
    point?.accuracyMeters != null ? `±${Math.round(Number(point.accuracyMeters))} m` : '';
  const deviceBits = [
    point?.deviceModel,
    point?.deviceOs,
    point?.appVersion ? `app ${point.appVersion}` : null
  ].filter(Boolean);

  return html`
    <div class="osr-lwc-mirror slds-card slds-p-around_medium rep-location-card">
      <div class="slds-grid slds-grid_align-spread slds-m-bottom_small">
        <strong>${opts.label || 'My Location'}</strong>
        <label class="slds-checkbox_toggle slds-grid">
          <span class="slds-form-element__label slds-m-bottom_none">Share</span>
          <input
            type="checkbox"
            .checked=${state.sharing}
            ?disabled=${state.permissionDenied}
            @change=${(e: Event) =>
              opts.onToggleSharing?.((e.target as HTMLInputElement).checked)}
          />
          <span class="slds-checkbox_faux_container" aria-live="assertive">
            <span class="slds-checkbox_faux"></span>
          </span>
        </label>
      </div>
      ${state.permissionDenied
        ? html`<p class="slds-text-color_error">Location permission denied</p>`
        : nothing}
      ${state.error && !state.permissionDenied
        ? html`<p class="slds-text-color_error">${state.error}</p>`
        : nothing}
      ${state.sharing && !state.permissionDenied
        ? html`
            <p class="slds-text-body_regular">${coords} ${accuracy}</p>
            <p class="slds-text-body_small slds-text-color_weak">
              ${state.watching ? 'Tracking (GPS)' : 'Starting GPS…'}
              ${point?.recordedAt
                ? html` · ${new Date(point.recordedAt).toLocaleTimeString()}`
                : nothing}
            </p>
            ${deviceBits.length
              ? html`<p class="slds-text-body_small slds-text-color_weak">
                  ${deviceBits.join(' · ')}
                </p>`
              : nothing}
          `
        : html`<p class="slds-text-color_weak">Location sharing is off</p>`}
    </div>
  `;
}
