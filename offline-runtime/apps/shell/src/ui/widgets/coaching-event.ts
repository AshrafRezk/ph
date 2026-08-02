import { html, type TemplateResult } from 'lit';

export function renderCoachingEventEvaluation(opts: {
  recordId?: string | null;
  label?: string;
  online?: boolean;
}): TemplateResult {
  return html`
    <div class="osr-lwc-mirror slds-card slds-p-around_medium">
      <h3 class="slds-text-heading_small">${opts.label || 'Coaching Evaluation'}</h3>
      <p class="slds-text-body_small slds-text-color_weak">
        Coaching event ${opts.recordId || ''} — evaluation form fields sync with Coaching_Event__c.
        ${opts.online
          ? 'Online: edits save through the record form / outbox.'
          : 'Offline: use the record Details section below; changes queue to the outbox.'}
      </p>
    </div>
  `;
}

export function renderCoachingEventInsights(opts: {
  recordId?: string | null;
  label?: string;
}): TemplateResult {
  return html`
    <div class="osr-lwc-mirror slds-card slds-p-around_medium">
      <h3 class="slds-text-heading_small">${opts.label || 'Coaching Insights'}</h3>
      <p class="slds-text-body_small slds-text-color_weak">
        Score trends and coaching insights for ${opts.recordId || 'this event'} appear when related metrics are
        synced. Open related lists for visit and template context.
      </p>
    </div>
  `;
}
