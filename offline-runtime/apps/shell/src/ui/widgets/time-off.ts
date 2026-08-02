import { html, nothing, type TemplateResult } from 'lit';

const TOT_TYPES = [
  { label: 'Holiday', value: 'Holiday' },
  { label: 'Sick Leave', value: 'Sick Leave' },
  { label: 'Training', value: 'Training' },
  { label: 'Event', value: 'Event' },
  { label: 'Travelling', value: 'Travelling' }
];

const form = {
  startIso: new Date().toISOString().slice(0, 10),
  typeValue: 'Holiday',
  spanType: 'Full Day',
  durationHours: '8',
  comments: '',
  submitted: false,
  error: ''
};

/** Vite catalog port for c/timeOffSubmission. */
export function renderTimeOffSubmission(opts: {
  label: string;
  online?: boolean;
  onSubmit?: (input: {
    startIso: string;
    typeValue: string;
    spanType: string;
    durationHours?: string;
    comments?: string;
  }) => void;
  requestUpdate?: () => void;
}): TemplateResult {
  const bump = () => opts.requestUpdate?.();

  return html`
    <div class="osr-lwc-mirror time-off slds-card slds-p-around_medium">
      <h2 class="slds-text-heading_medium">${opts.label || 'Request Time Off'}</h2>
      <p class="slds-text-body_small slds-text-color_weak">
        Submits to the offline outbox${opts.online ? ' and syncs when connected' : ' (you are offline)'}.
      </p>
      ${form.submitted
        ? html`<div class="slds-notify slds-notify_alert slds-theme_success slds-m-vertical_small">
            Time off queued. It will appear on the planner after sync.
          </div>`
        : nothing}
      ${form.error
        ? html`<div class="slds-text-color_error slds-m-vertical_small">${form.error}</div>`
        : nothing}
      <label class="slds-form-element__label">Date</label>
      <input
        class="slds-input"
        type="date"
        .value=${form.startIso}
        @input=${(e: Event) => {
          form.startIso = (e.target as HTMLInputElement).value;
          form.submitted = false;
        }}
      />
      <label class="slds-form-element__label slds-m-top_small">Type</label>
      <select
        class="slds-select"
        .value=${form.typeValue}
        @change=${(e: Event) => {
          form.typeValue = (e.target as HTMLSelectElement).value;
        }}
      >
        ${TOT_TYPES.map((t) => html`<option value=${t.value}>${t.label}</option>`)}
      </select>
      <label class="slds-form-element__label slds-m-top_small">Span</label>
      <select
        class="slds-select"
        .value=${form.spanType}
        @change=${(e: Event) => {
          form.spanType = (e.target as HTMLSelectElement).value;
        }}
      >
        <option value="Full Day">Full Day</option>
        <option value="Half Day">Half Day</option>
        <option value="Hours">Hours</option>
      </select>
      ${form.spanType === 'Hours'
        ? html`
            <label class="slds-form-element__label slds-m-top_small">Duration (hours)</label>
            <input
              class="slds-input"
              type="number"
              min="1"
              max="24"
              .value=${form.durationHours}
              @input=${(e: Event) => {
                form.durationHours = (e.target as HTMLInputElement).value;
              }}
            />
          `
        : nothing}
      <label class="slds-form-element__label slds-m-top_small">Comments</label>
      <textarea
        class="slds-textarea"
        .value=${form.comments}
        @input=${(e: Event) => {
          form.comments = (e.target as HTMLTextAreaElement).value;
        }}
      ></textarea>
      <div class="slds-m-top_medium">
        <button
          type="button"
          class="slds-button slds-button_brand"
          @click=${() => {
            if (!form.startIso) {
              form.error = 'Pick a date';
              bump();
              return;
            }
            form.error = '';
            const startIso = form.startIso.includes('T')
              ? form.startIso
              : `${form.startIso}T09:00:00.000Z`;
            opts.onSubmit?.({
              startIso,
              typeValue: form.typeValue,
              spanType: form.spanType,
              durationHours: form.spanType === 'Hours' ? form.durationHours : undefined,
              comments: form.comments || undefined
            });
            form.submitted = true;
            bump();
          }}
        >
          Submit time off
        </button>
      </div>
    </div>
  `;
}
