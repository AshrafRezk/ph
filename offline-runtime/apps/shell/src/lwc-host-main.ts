/**
 * Iframe entry: boots platform bridge and mounts allowlisted / compiled LWC modules.
 */
import { BridgeClient } from '@osr/bridge';
import { setPlatformBridge, registerLightningStubs } from '@osr/platform';
import {
  defineEngineCustomElements,
  getEngineModule,
  listEngineModules
} from './lwc-modules/registry';

function parseHash(hash = location.hash) {
  const raw = hash.startsWith('#') ? hash.slice(1) : hash;
  const params = new URLSearchParams(raw);
  const bundle = params.get('bundle') || 'c/helloRecord';
  const props: Record<string, string> = {};
  for (const [k, v] of params.entries()) {
    if (k === 'bundle') continue;
    props[k] = v;
  }
  return { bundle, props };
}

async function main() {
  const root = document.getElementById('root');
  if (!root) throw new Error('#root missing');

  const client = new BridgeClient(window.parent);
  client.attach(window);
  setPlatformBridge(client);
  registerLightningStubs();
  defineEngineCustomElements();

  const { bundle, props } = parseHash();
  root.innerHTML = '';

  const entry = getEngineModule(bundle);
  if (entry?.kind === 'ce' && entry.tag) {
    const el = document.createElement(entry.tag);
    for (const [k, v] of Object.entries(props)) {
      el.setAttribute(k.replace(/[A-Z]/g, (m) => '-' + m.toLowerCase()), v);
      (el as any)[k] = v;
    }
    if (props.recordId) el.setAttribute('record-id', props.recordId);
    if (props.objectApi) el.setAttribute('object-api', props.objectApi);
    root.appendChild(el);
  } else {
    // Try parent-provided compiled module
    try {
      const { result } = await client.call<{ sourceJs?: string; moduleUrl?: string }>(
        'lwc.getCompiledModule',
        { bundle }
      );
      if (result?.sourceJs) {
        const blob = new Blob([result.sourceJs], { type: 'text/javascript' });
        const url = URL.createObjectURL(blob);
        const mod = await import(/* @vite-ignore */ url);
        URL.revokeObjectURL(url);
        const Ctor = mod.default;
        if (Ctor && !customElements.get('osr-compiled-' + bundle.replace(/\W/g, '-'))) {
          const tag = 'osr-compiled-' + bundle.replace(/\W/g, '-');
          customElements.define(tag, Ctor);
          root.appendChild(document.createElement(tag));
        } else if (Ctor) {
          const tag = 'osr-compiled-' + bundle.replace(/\W/g, '-');
          root.appendChild(document.createElement(tag));
        }
      } else {
        root.innerHTML = `<div style="padding:1rem;font-family:system-ui;color:#706e6b">
          <strong>No engine module for ${bundle}</strong>
          <p>Known: ${listEngineModules().map((e) => e.bundle).join(', ')}</p>
        </div>`;
      }
    } catch (e) {
      root.innerHTML = `<div style="padding:1rem;color:#ba0517;font-family:system-ui">
        Failed to mount ${bundle}: ${e instanceof Error ? e.message : String(e)}
      </div>`;
    }
  }

  const report = () => {
    const h = Math.max(document.documentElement.scrollHeight, root.scrollHeight, 120);
    void client.call('host.resize', { height: h, bundle });
  };
  report();
  new ResizeObserver(report).observe(root);
  void client.call('ping', { bundle, known: listEngineModules().map((e) => e.bundle) });
}

void main();
