/**
 * Browser-safe LWC scan / rewrite / fallback module helpers (no @lwc/compiler).
 */
export type CompatFinding = {
  bundleName: string;
  imports: string[];
  unresolved: string[];
  apexBindings: string[];
  usesNavigation: boolean;
  usesToast: boolean;
  usesUiRecordApi: boolean;
  usesLightningBase: string[];
  unsupportedLightningBase: string[];
};

export type CompileResult = {
  ok: boolean;
  bundleName: string;
  code?: string;
  error?: string;
  unresolvedImports?: string[];
};

const SUPPORTED_SHIMS = new Set([
  'lwc',
  '@salesforce/apex',
  'lightning/uiRecordApi',
  'lightning/navigation',
  'lightning/platformShowToastEvent',
  'lightning/confirm',
  'lightning/alert',
  '@osr/platform'
]);

/** Curated lightning-* tags stubbed in @osr/platform (keep in sync with stubs). */
export const STUBBED_LIGHTNING_TAGS = new Set([
  'lightning-button',
  'lightning-input',
  'lightning-textarea',
  'lightning-combobox',
  'lightning-spinner',
  'lightning-card',
  'lightning-badge',
  'lightning-icon',
  'lightning-button-group',
  'lightning-radio-group',
  'lightning-formatted-text',
  'lightning-formatted-number',
  'lightning-layout',
  'lightning-layout-item',
  'lightning-tabset',
  'lightning-tab'
]);

const LIGHTNING_BASE_RE = /<(lightning-[\w-]+)/g;
const IMPORT_RE = /from\s+['"]([^'"]+)['"]/g;
const APEX_IMPORT_RE = /@salesforce\/apex\/([\w.]+)/g;

export function scanLwcSource(
  bundleName: string,
  sourceJs: string,
  sourceHtml = ''
): CompatFinding {
  const imports: string[] = [];
  let m: RegExpExecArray | null;
  const importRe = new RegExp(IMPORT_RE);
  while ((m = importRe.exec(sourceJs))) {
    imports.push(m[1]);
  }

  const apexBindings: string[] = [];
  const apexRe = new RegExp(APEX_IMPORT_RE);
  while ((m = apexRe.exec(sourceJs))) {
    apexBindings.push(m[1]);
  }

  const lightningBase = new Set<string>();
  const baseRe = new RegExp(LIGHTNING_BASE_RE);
  while ((m = baseRe.exec(sourceHtml))) {
    lightningBase.add(m[1]);
  }

  const unresolved = imports.filter((spec) => {
    if (spec === 'lwc' || spec.startsWith('lwc/')) return false;
    if (spec.startsWith('@salesforce/apex/')) return false;
    if (spec.startsWith('c/')) return false;
    if (SUPPORTED_SHIMS.has(spec)) return false;
    if (spec.startsWith('@salesforce/')) return true;
    if (spec.startsWith('lightning/')) return !SUPPORTED_SHIMS.has(spec);
    return true;
  });

  const unsupportedBase = [...lightningBase].filter((t) => !STUBBED_LIGHTNING_TAGS.has(t));

  return {
    bundleName,
    imports,
    unresolved,
    apexBindings,
    usesNavigation: imports.some((i) => i.includes('lightning/navigation')),
    usesToast: imports.some((i) => i.includes('ShowToast') || i.includes('platformShowToast')),
    usesUiRecordApi: imports.some((i) => i.includes('uiRecordApi')),
    usesLightningBase: [...lightningBase],
    unsupportedLightningBase: unsupportedBase
  };
}

/** Replace Apex default imports with createApexInvoker calls. */
export function rewriteApexImportsToInvoker(js: string): string {
  let needsInvoker = false;
  let body = js.replace(
    /import\s+(\w+)\s+from\s+['"]@salesforce\/apex\/([^'"]+)['"];?/g,
    (_all, ident: string, method: string) => {
      needsInvoker = true;
      return `const ${ident} = createApexInvoker('${method}');`;
    }
  );
  body = body
    .replace(/from\s+['"]lightning\/uiRecordApi['"]/g, `from '@osr/platform'`)
    .replace(/from\s+['"]lightning\/navigation['"]/g, `from '@osr/platform'`)
    .replace(/from\s+['"]lightning\/platformShowToastEvent['"]/g, `from '@osr/platform'`);
  if (needsInvoker) {
    return `import { createApexInvoker } from '@osr/platform';\n${body}`;
  }
  return body;
}

export function buildFallbackModule(
  name: string,
  js: string,
  html?: string,
  css?: string
): string {
  const safeHtml = JSON.stringify(
    html ?? `<div class="osr-lwc-fallback"><strong>${name}</strong><p>Offline engine fallback</p></div>`
  );
  const safeCss = JSON.stringify(css ?? '');
  const consts = js
    .split('\n')
    .filter((l) => l.includes('createApexInvoker') || l.includes('import { createApexInvoker'))
    .join('\n');
  return `
${consts.includes('createApexInvoker') && !consts.includes('import') ? `import { createApexInvoker } from '@osr/platform';` : ''}
${consts}
export default class ${pascal(name)} extends HTMLElement {
  connectedCallback() {
    const root = this.attachShadow({ mode: 'open' });
    root.innerHTML = (${safeCss} ? '<style>' + ${safeCss} + '</style>' : '') + ${safeHtml};
  }
}
`;
}

export function pascal(name: string): string {
  return name
    .replace(/[-_]+/g, ' ')
    .replace(/(?:^|\s)(.)/g, (_, c) => c.toUpperCase())
    .replace(/\s/g, '');
}

/**
 * Capacitor / browser compile path: emit a CE fallback module (no Node @lwc/compiler).
 * Full @lwc/compiler transform is available via `@osr/lwc-compile/compile` in Node/CLI.
 */
export async function compileToolingBundle(input: {
  bundleName: string;
  sourceJsRaw?: string;
  sourceHtml?: string;
  sourceCss?: string;
}): Promise<CompileResult> {
  const bundleName = input.bundleName.startsWith('c/')
    ? input.bundleName
    : `c/${input.bundleName}`;
  const name = bundleName.replace(/^c\//, '');
  if (!input.sourceJsRaw && !input.sourceHtml) {
    return { ok: false, bundleName, error: 'No Tooling source' };
  }
  const js = rewriteApexImportsToInvoker(
    input.sourceJsRaw ||
      `import { LightningElement } from 'lwc'; export default class ${pascal(name)} extends LightningElement {}`
  );
  const finding = scanLwcSource(bundleName, input.sourceJsRaw ?? '', input.sourceHtml ?? '');
  return {
    ok: true,
    bundleName,
    code: buildFallbackModule(name, js, input.sourceHtml, input.sourceCss),
    unresolvedImports: finding.unresolved,
    error: 'browser-fallback'
  };
}

export const COMPILE_ALLOWLIST = [
  'homeOfficeMessages',
  'helloOsr',
  'helloRecord'
] as const;

export type AllowlistName = (typeof COMPILE_ALLOWLIST)[number];
