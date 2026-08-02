/**
 * SLDS token bridge + thin subset for OSR mirror hosts.
 * Maps --sf-* shell tokens onto Lightning-like --slds-g-* names.
 * Includes iOS-quality form controls shared by all fidelity widgets.
 */

export const sldsTokensCss = `
.osr-lwc-mirror {
  --slds-g-color-brand-base-60: var(--sf-blue, #0176d3);
  --slds-g-color-brand-base-70: var(--sf-blue-dark, #032d60);
  --slds-g-color-neutral-base-10: #181818;
  --slds-g-color-neutral-base-50: #706e6b;
  --slds-g-color-neutral-base-95: #f3f3f3;
  --slds-g-color-neutral-base-100: #fff;
  --slds-g-color-border-base-1: #c9c9c9;
  --slds-g-color-border-base-4: #e5e5e5;
  --slds-g-radius-border-2: 0.25rem;
  --slds-g-radius-border-3: 0.5rem;
  --slds-g-radius-border-4: 0.75rem;

  /* iOS-inspired control tokens */
  --osr-control-bg: #f2f4f7;
  --osr-control-bg-hover: #ebeff5;
  --osr-control-bg-focus: #ffffff;
  --osr-control-border: rgba(15, 23, 42, 0.08);
  --osr-control-border-focus: #0176d3;
  --osr-control-radius: 12px;
  --osr-control-height: 44px;
  --osr-control-pad-x: 14px;
  --osr-control-shadow-focus: 0 0 0 4px rgba(1, 118, 211, 0.16);
  --osr-label-color: #5b6573;
  --osr-placeholder: #98a2b3;

  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display",
    "Segoe UI", "Helvetica Neue", Helvetica, Arial, sans-serif;
  font-size: 15px;
  line-height: 1.45;
  color: var(--slds-g-color-neutral-base-10);
  box-sizing: border-box;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}
.osr-lwc-mirror *,
.osr-lwc-mirror *::before,
.osr-lwc-mirror *::after {
  box-sizing: border-box;
}

/* ── Buttons ── */
.osr-lwc-mirror .slds-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.4rem;
  padding: 0 1.1rem;
  min-height: 40px;
  border-radius: 980px;
  border: 1px solid transparent;
  background: #eef2f7;
  color: var(--slds-g-color-brand-base-60);
  font: inherit;
  font-size: 0.9375rem;
  font-weight: 600;
  letter-spacing: -0.01em;
  cursor: pointer;
  text-decoration: none;
  transition: background 0.18s ease, color 0.18s ease, box-shadow 0.18s ease,
    transform 0.12s ease, border-color 0.18s ease;
  -webkit-tap-highlight-color: transparent;
  touch-action: manipulation;
}
.osr-lwc-mirror .slds-button:hover:not(:disabled) {
  background: #e4ebf5;
}
.osr-lwc-mirror .slds-button:active:not(:disabled) {
  transform: scale(0.98);
}
.osr-lwc-mirror .slds-button:focus-visible {
  outline: none;
  box-shadow: var(--osr-control-shadow-focus);
}
.osr-lwc-mirror .slds-button:disabled {
  opacity: 0.4;
  cursor: not-allowed;
  transform: none;
}
.osr-lwc-mirror .slds-button_brand,
.osr-lwc-mirror .slds-button--brand {
  background: linear-gradient(180deg, #1b8aef 0%, #0176d3 100%);
  border-color: transparent;
  color: #fff;
  box-shadow: 0 1px 2px rgba(1, 118, 211, 0.28);
}
.osr-lwc-mirror .slds-button_brand:hover:not(:disabled),
.osr-lwc-mirror .slds-button--brand:hover:not(:disabled) {
  background: linear-gradient(180deg, #1590f8 0%, #0169bd 100%);
}
.osr-lwc-mirror .slds-button_neutral,
.osr-lwc-mirror .slds-button--neutral {
  background: #fff;
  border-color: rgba(15, 23, 42, 0.1);
  color: var(--slds-g-color-brand-base-60);
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);
}
.osr-lwc-mirror .slds-button_neutral:hover:not(:disabled),
.osr-lwc-mirror .slds-button--neutral:hover:not(:disabled) {
  background: #f8fafc;
  border-color: rgba(1, 118, 211, 0.28);
}
.osr-lwc-mirror .slds-button_destructive-text {
  border-color: transparent;
  background: transparent;
  color: #ba0517;
  box-shadow: none;
}
.osr-lwc-mirror .slds-button_base {
  border-color: transparent;
  background: transparent;
  color: var(--slds-g-color-brand-base-60);
  padding-left: 0.5rem;
  padding-right: 0.5rem;
  min-height: 2rem;
  box-shadow: none;
}
.osr-lwc-mirror .slds-badge {
  display: inline-flex;
  align-items: center;
  padding: 0.2rem 0.55rem;
  border-radius: 999px;
  font-size: 0.7rem;
  font-weight: 700;
  background: #eef4ff;
  color: var(--slds-g-color-brand-base-60);
}
.osr-lwc-mirror .slds-card {
  background: #fff;
  border: 1px solid rgba(0, 0, 0, 0.06);
  border-radius: 16px;
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04), 0 8px 24px rgba(15, 23, 42, 0.04);
  overflow: hidden;
}
.osr-lwc-mirror .slds-text-color_weak {
  color: var(--slds-g-color-neutral-base-50);
}
.osr-lwc-mirror .slds-text-align_center {
  text-align: center;
}
.osr-lwc-mirror .slds-p-around_small {
  padding: 0.75rem;
}
.osr-lwc-mirror .slds-p-around_medium {
  padding: 1rem;
}
.osr-lwc-mirror .slds-p-vertical_medium {
  padding-top: 1rem;
  padding-bottom: 1rem;
}
.osr-lwc-mirror .slds-m-top_small {
  margin-top: 0.75rem;
}
.osr-lwc-mirror .slds-m-top_medium {
  margin-top: 1rem;
}
.osr-lwc-mirror .osr-cache-pill {
  font-size: 10px;
  font-weight: 600;
  color: #0176d3;
  background: #eef4ff;
  border-radius: 6px;
  padding: 2px 6px;
  vertical-align: middle;
}

/* ══════════════════════════════════════════
   Generic form controls — iOS-quality
   Applies to ALL inputs in fidelity widgets
   ══════════════════════════════════════════ */

.osr-lwc-mirror .slds-form-element {
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
  width: 100%;
  margin: 0 0 1rem;
}
.osr-lwc-mirror .slds-form-element:last-child {
  margin-bottom: 0;
}
.osr-lwc-mirror .osr-form-grid > .slds-form-element,
.osr-lwc-mirror .form-grid > .slds-form-element,
.osr-lwc-mirror .osr-form-grid .osr-form-grid > .slds-form-element {
  margin-bottom: 0;
}

.osr-lwc-mirror .slds-form-element__label,
.osr-lwc-mirror label.slds-form-element__label,
.osr-lwc-mirror .field-label,
.osr-lwc-mirror .account-filter-label {
  display: block;
  width: 100%;
  margin: 0 0 0.4rem;
  padding: 0;
  font-size: 0.8125rem;
  font-weight: 600;
  letter-spacing: -0.01em;
  color: var(--osr-label-color);
  line-height: 1.3;
}

.osr-lwc-mirror .slds-form-element__label.slds-m-top_small,
.osr-lwc-mirror label.slds-form-element__label.slds-m-top_small {
  margin-top: 1rem;
}

.osr-lwc-mirror input:not([type="checkbox"]):not([type="radio"]):not([type="range"]):not([type="file"]):not([type="hidden"]):not([type="button"]):not([type="submit"]):not([type="reset"]):not(.scope-chip):not(.filter-chip):not(.collection-chip):not(.ho-dot),
.osr-lwc-mirror select,
.osr-lwc-mirror textarea,
.osr-lwc-mirror .slds-input,
.osr-lwc-mirror .slds-select,
.osr-lwc-mirror .slds-textarea,
.osr-lwc-mirror .account-search-input,
.osr-lwc-mirror .account-search {
  appearance: none;
  -webkit-appearance: none;
  display: inline-block;
  margin: 0;
  min-height: var(--osr-control-height);
  padding: 0.7rem var(--osr-control-pad-x);
  border: 1px solid var(--osr-control-border);
  border-radius: var(--osr-control-radius);
  background-color: var(--osr-control-bg);
  color: #0f172a;
  font: inherit;
  font-size: 1rem;
  font-family: inherit;
  font-weight: 500;
  letter-spacing: -0.01em;
  line-height: 1.35;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.6);
  transition: background-color 0.18s ease, border-color 0.18s ease,
    box-shadow 0.18s ease, color 0.18s ease;
  outline: none;
  touch-action: manipulation;
  vertical-align: middle;
}

/* Full-bleed controls in forms / search bars */
.osr-lwc-mirror .slds-input,
.osr-lwc-mirror .slds-select,
.osr-lwc-mirror .slds-textarea,
.osr-lwc-mirror .account-search-input,
.osr-lwc-mirror .account-search,
.osr-lwc-mirror .slds-form-element > input,
.osr-lwc-mirror .slds-form-element > select,
.osr-lwc-mirror .slds-form-element > textarea,
.osr-lwc-mirror .osr-form-grid input,
.osr-lwc-mirror .osr-form-grid select,
.osr-lwc-mirror .osr-form-grid textarea,
.osr-lwc-mirror .form-grid input,
.osr-lwc-mirror .form-grid select,
.osr-lwc-mirror .form-grid textarea {
  display: block;
  width: 100%;
  max-width: 100%;
}

/* Compact controls in toolbars / headers stay auto-width */
.osr-lwc-mirror .planner-toolbar select,
.osr-lwc-mirror .planner-toolbar .slds-select,
.osr-lwc-mirror .map-toolbar select,
.osr-lwc-mirror .map-toolbar .slds-select,
.osr-lwc-mirror .today-plan-header select,
.osr-lwc-mirror .today-plan-header .slds-select,
.osr-lwc-mirror .accounts-toolbar select,
.osr-lwc-mirror .accounts-toolbar .slds-select,
.osr-lwc-mirror .planner-viewer-combobox,
.osr-lwc-mirror .map-toolbar-day,
.osr-lwc-mirror select.today-plan-rep-picker {
  display: inline-block;
  width: auto;
  min-width: 11rem;
  max-width: 100%;
}

.osr-lwc-mirror textarea,
.osr-lwc-mirror .slds-textarea {
  min-height: 6.5rem;
  resize: vertical;
  line-height: 1.45;
  padding-top: 0.85rem;
  padding-bottom: 0.85rem;
}

.osr-lwc-mirror select,
.osr-lwc-mirror .slds-select {
  padding-right: 2.5rem;
  background-image:
    linear-gradient(45deg, transparent 50%, #64748b 50%),
    linear-gradient(135deg, #64748b 50%, transparent 50%);
  background-position:
    calc(100% - 18px) calc(50% - 3px),
    calc(100% - 12px) calc(50% - 3px);
  background-size: 6px 6px, 6px 6px;
  background-repeat: no-repeat;
  cursor: pointer;
}

.osr-lwc-mirror input[type="date"],
.osr-lwc-mirror input[type="time"],
.osr-lwc-mirror input[type="datetime-local"],
.osr-lwc-mirror input[type="month"],
.osr-lwc-mirror input[type="week"] {
  min-height: var(--osr-control-height);
  padding-right: 0.85rem;
  color-scheme: light;
}
.osr-lwc-mirror input[type="date"]::-webkit-calendar-picker-indicator,
.osr-lwc-mirror input[type="time"]::-webkit-calendar-picker-indicator,
.osr-lwc-mirror input[type="datetime-local"]::-webkit-calendar-picker-indicator {
  opacity: 0.55;
  cursor: pointer;
  padding: 0.15rem;
  border-radius: 6px;
}
.osr-lwc-mirror input[type="date"]::-webkit-calendar-picker-indicator:hover,
.osr-lwc-mirror input[type="time"]::-webkit-calendar-picker-indicator:hover,
.osr-lwc-mirror input[type="datetime-local"]::-webkit-calendar-picker-indicator:hover {
  opacity: 1;
  background: rgba(1, 118, 211, 0.1);
}

.osr-lwc-mirror input::placeholder,
.osr-lwc-mirror textarea::placeholder,
.osr-lwc-mirror .slds-input::placeholder,
.osr-lwc-mirror .slds-textarea::placeholder {
  color: var(--osr-placeholder);
  font-weight: 450;
  opacity: 1;
}

.osr-lwc-mirror input:hover:not(:disabled):not(:focus),
.osr-lwc-mirror select:hover:not(:disabled):not(:focus),
.osr-lwc-mirror textarea:hover:not(:disabled):not(:focus),
.osr-lwc-mirror .slds-input:hover:not(:disabled):not(:focus),
.osr-lwc-mirror .slds-select:hover:not(:disabled):not(:focus),
.osr-lwc-mirror .slds-textarea:hover:not(:disabled):not(:focus) {
  background-color: var(--osr-control-bg-hover);
  border-color: rgba(15, 23, 42, 0.14);
}

.osr-lwc-mirror input:focus,
.osr-lwc-mirror select:focus,
.osr-lwc-mirror textarea:focus,
.osr-lwc-mirror .slds-input:focus,
.osr-lwc-mirror .slds-select:focus,
.osr-lwc-mirror .slds-textarea:focus,
.osr-lwc-mirror input:focus-visible,
.osr-lwc-mirror select:focus-visible,
.osr-lwc-mirror textarea:focus-visible {
  background-color: var(--osr-control-bg-focus);
  border-color: var(--osr-control-border-focus);
  box-shadow: var(--osr-control-shadow-focus);
}

.osr-lwc-mirror input:disabled,
.osr-lwc-mirror select:disabled,
.osr-lwc-mirror textarea:disabled,
.osr-lwc-mirror .slds-input:disabled,
.osr-lwc-mirror .slds-select:disabled,
.osr-lwc-mirror .slds-textarea:disabled {
  opacity: 0.55;
  cursor: not-allowed;
  background-color: #eef0f3;
  color: #64748b;
}

.osr-lwc-mirror input[type="checkbox"],
.osr-lwc-mirror input[type="radio"] {
  appearance: none;
  -webkit-appearance: none;
  width: 1.25rem;
  height: 1.25rem;
  min-height: 0;
  margin: 0;
  padding: 0;
  display: inline-grid;
  place-content: center;
  vertical-align: middle;
  border: 1.5px solid rgba(15, 23, 42, 0.22);
  background: #fff;
  box-shadow: none;
  cursor: pointer;
  flex-shrink: 0;
}
.osr-lwc-mirror input[type="checkbox"] {
  border-radius: 6px;
}
.osr-lwc-mirror input[type="radio"] {
  border-radius: 50%;
}
.osr-lwc-mirror input[type="checkbox"]:checked,
.osr-lwc-mirror input[type="radio"]:checked {
  background: var(--slds-g-color-brand-base-60);
  border-color: var(--slds-g-color-brand-base-60);
}
.osr-lwc-mirror input[type="checkbox"]:checked::before {
  content: "";
  width: 0.35rem;
  height: 0.65rem;
  border: solid #fff;
  border-width: 0 2px 2px 0;
  transform: rotate(45deg) translate(-1px, -1px);
}
.osr-lwc-mirror input[type="radio"]:checked::before {
  content: "";
  width: 0.45rem;
  height: 0.45rem;
  border-radius: 50%;
  background: #fff;
}
.osr-lwc-mirror input[type="checkbox"]:focus-visible,
.osr-lwc-mirror input[type="radio"]:focus-visible {
  box-shadow: var(--osr-control-shadow-focus);
}

/* Number spinners — quieter */
.osr-lwc-mirror input[type="number"] {
  -moz-appearance: textfield;
}
.osr-lwc-mirror input[type="number"]::-webkit-outer-spin-button,
.osr-lwc-mirror input[type="number"]::-webkit-inner-spin-button {
  -webkit-appearance: none;
  margin: 0;
}

/* Search clear / cancel */
.osr-lwc-mirror input[type="search"] {
  padding-right: 2rem;
}
.osr-lwc-mirror input[type="search"]::-webkit-search-decoration,
.osr-lwc-mirror input[type="search"]::-webkit-search-cancel-button {
  -webkit-appearance: none;
}

/* Form grids used across widgets */
.osr-lwc-mirror .osr-form-grid,
.osr-lwc-mirror .form-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 1rem;
}
@media (min-width: 720px) {
  .osr-lwc-mirror .osr-form-grid-2,
  .osr-lwc-mirror .form-grid-2 {
    grid-template-columns: 1fr 1fr;
  }
}
`;
