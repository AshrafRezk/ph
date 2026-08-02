/**
 * Boot script for osr-lwc-host iframe.
 * Initializes bridge client, platform stubs, and mounts the requested bundle.
 */
import { BridgeClient } from '@osr/bridge';
import { setPlatformBridge, registerLightningStubs } from '@osr/platform';
import { mountLwcElement, mountCustomElement, registerLwcModule, getRegisteredLwc } from './index.js';

export type HostBootOptions = {
  root: HTMLElement;
  bundle: string;
  props?: Record<string, unknown>;
  /** Optional pre-bundled module map: bundleName -> constructor */
  modules?: Record<string, any>;
  /** Custom element tag for spike demos */
  customElementTag?: string;
};

export async function bootLwcHost(opts: HostBootOptions): Promise<() => void> {
  const client = new BridgeClient(window.parent);
  const detachClient = client.attach(window);
  setPlatformBridge(client);
  registerLightningStubs();

  for (const [name, Ctor] of Object.entries(opts.modules ?? {})) {
    registerLwcModule(name, Ctor);
  }

  // Ask parent for a compiled module if not already registered
  if (!getRegisteredLwc(opts.bundle) && !opts.customElementTag) {
    try {
      const { result } = await client.call<{ moduleUrl?: string; sourceJs?: string }>(
        'lwc.getCompiledModule',
        { bundle: opts.bundle }
      );
      if (result?.moduleUrl) {
        const mod = await import(/* @vite-ignore */ result.moduleUrl);
        const Ctor = mod.default ?? mod;
        registerLwcModule(opts.bundle, Ctor);
      } else if (result?.sourceJs) {
        const blob = new Blob([result.sourceJs], { type: 'text/javascript' });
        const url = URL.createObjectURL(blob);
        try {
          const mod = await import(/* @vite-ignore */ url);
          registerLwcModule(opts.bundle, mod.default ?? mod);
        } finally {
          URL.revokeObjectURL(url);
        }
      }
    } catch (e) {
      console.warn('[osr-lwc-host] compiled module unavailable', e);
    }
  }

  let mounted: { unmount: () => void; element: HTMLElement };
  if (opts.customElementTag) {
    mounted = mountCustomElement(opts.root, opts.customElementTag, opts.props ?? {});
  } else {
    mounted = mountLwcElement(opts.root, opts.bundle, opts.props ?? {});
  }

  const reportHeight = () => {
    const h = Math.max(
      document.documentElement.scrollHeight,
      document.body?.scrollHeight ?? 0,
      mounted.element.scrollHeight || 0
    );
    client.emit('host.resize', { height: h, bundle: opts.bundle });
    void client.call('host.resize', { height: h, bundle: opts.bundle });
  };
  reportHeight();
  const ro = new ResizeObserver(() => reportHeight());
  ro.observe(opts.root);
  if (mounted.element) ro.observe(mounted.element);

  void client.call('ping', { bundle: opts.bundle });

  return () => {
    ro.disconnect();
    mounted.unmount();
    detachClient();
  };
}

export function parseHostHash(hash = location.hash): {
  bundle: string;
  recordId?: string;
  objectApi?: string;
  props: Record<string, unknown>;
} {
  const raw = hash.startsWith('#') ? hash.slice(1) : hash;
  const params = new URLSearchParams(raw);
  const bundle = params.get('bundle') || 'c/helloOsr';
  const recordId = params.get('recordId') || undefined;
  const objectApi = params.get('objectApi') || undefined;
  const props: Record<string, unknown> = {};
  if (recordId) props.recordId = recordId;
  if (objectApi) props.objectApi = objectApi;
  for (const [k, v] of params.entries()) {
    if (k === 'bundle' || k === 'recordId' || k === 'objectApi') continue;
    props[k] = v;
  }
  return { bundle, recordId, objectApi, props };
}
