import { html, type TemplateResult } from 'lit';
import type { AdminModuleContext } from './types';
import { renderIntegrationsManagement } from './integrations-management';
import { renderClmAdminConsole } from './clm-admin-console';
import { renderCoachingTemplateManager } from './coaching-template-manager';
import { renderTerritoryManagementConsole } from './territory-management-console';
import { renderBricksManagementConsole } from './bricks-management-console';
import { renderProductTerritoryManager } from './product-territory-manager';
import { renderPlanCycleManager } from './plan-cycle-manager';
import { renderPharmacySalesDataAdmin } from './pharmacy-sales-data-admin';
import { renderClmRatingLayoutEditor } from './clm-rating-layout-editor';

/** Map Salesforce adminConsole child componentName → Lit render function. */
const RENDERERS: Record<string, (ctx: AdminModuleContext) => TemplateResult> = {
  integrationsManagementConsole: renderIntegrationsManagement,
  clmAdminConsole: (ctx) => renderClmAdminConsole({ ...ctx, embedded: true }),
  clmRatingLayoutEditor: renderClmRatingLayoutEditor,
  coachingTemplateManager: renderCoachingTemplateManager,
  territoryManagementConsole: renderTerritoryManagementConsole,
  bricksManagementConsole: renderBricksManagementConsole,
  productTerritoryManager: renderProductTerritoryManager,
  planCycleManager: renderPlanCycleManager,
  pharmacySalesDataAdmin: renderPharmacySalesDataAdmin
};

export function hasAdminModulePort(componentName: string): boolean {
  return componentName in RENDERERS;
}

export function renderAdminModule(componentName: string, ctx: AdminModuleContext): TemplateResult {
  const fn = RENDERERS[componentName];
  if (!fn) {
    return html`<div class="admin-module-placeholder">
      <strong>Module unavailable</strong>
      <p>No offline port for ${componentName}.</p>
    </div>`;
  }
  return fn(ctx);
}

export function listAdminModulePorts(): string[] {
  return Object.keys(RENDERERS);
}

export type { AdminModuleContext } from './types';
export { renderIntegrationsManagement } from './integrations-management';
export { renderClmAdminConsole } from './clm-admin-console';
export { renderCoachingTemplateManager } from './coaching-template-manager';
export { renderTerritoryManagementConsole } from './territory-management-console';
export { renderBricksManagementConsole } from './bricks-management-console';
export { renderProductTerritoryManager } from './product-territory-manager';
export { renderPlanCycleManager } from './plan-cycle-manager';
export { renderPharmacySalesDataAdmin } from './pharmacy-sales-data-admin';
export { renderClmRatingLayoutEditor } from './clm-rating-layout-editor';
