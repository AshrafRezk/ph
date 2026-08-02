/**
 * Node/CLI LWC compile using @lwc/compiler (not for Capacitor WebView bundles).
 */
import { transformSync } from '@lwc/compiler';
import {
  scanLwcSource,
  rewriteApexImportsToInvoker,
  buildFallbackModule,
  pascal,
  type CompileResult
} from './scan.js';

export type CompileInput = {
  bundleName: string;
  name: string;
  namespace?: string;
  js: string;
  html?: string;
  css?: string;
};

/**
 * Compile LWC JS (+ optional HTML) with @lwc/compiler transformSync.
 * Produces a single ESM string suitable for blob import in the iframe.
 */
export async function compileLwcModule(input: CompileInput): Promise<CompileResult> {
  const ns = input.namespace ?? 'c';
  const name = input.name;
  const bundleName = input.bundleName.startsWith('c/')
    ? input.bundleName
    : `c/${input.bundleName}`;
  const finding = scanLwcSource(bundleName, input.js, input.html ?? '');
  const jsRewritten = rewriteApexImportsToInvoker(input.js);

  try {
    let templateCode = 'export default function tmpl() { return []; } tmpl.stylesheets = [];';
    if (input.html) {
      const htmlResult = transformSync(input.html, `${name}.html`, {
        namespace: ns,
        name
      });
      templateCode = htmlResult.code;
    }

    const jsResult = transformSync(jsRewritten, `${name}.js`, {
      namespace: ns,
      name
    });

    const code = `
${templateCode.replace(/export\s+default/, 'const __osrTmpl =')}
${jsResult.code
  .replace(/import\s+_tmpl\s+from\s+['"]\.\/[^'"]+['"];?/, '')
  .replace(/import\s+{\s*default as _tmpl\s*}\s+from\s+['"][^'"]+['"];?/, '')
  .replace(/\b_tmpl\b/g, '__osrTmpl')}
`;

    return {
      ok: true,
      bundleName,
      code,
      unresolvedImports: finding.unresolved
    };
  } catch (e) {
    return {
      ok: true,
      bundleName,
      code: buildFallbackModule(name, jsRewritten, input.html, input.css),
      unresolvedImports: finding.unresolved,
      error: e instanceof Error ? e.message : String(e)
    };
  }
}

/** Full compiler path for Node tooling (not browser). */
export async function compileToolingBundleNative(input: {
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
  return compileLwcModule({
    bundleName,
    name,
    js:
      input.sourceJsRaw ||
      `import { LightningElement } from 'lwc'; export default class ${pascal(name)} extends LightningElement {}`,
    html: input.sourceHtml,
    css: input.sourceCss
  });
}
