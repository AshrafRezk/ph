import { getPlatformBridge } from './bridge-context.js';

/** Normalize `@salesforce/apex/Foo.bar` or `Foo.bar` to cache key form. */
export function apexMethodKey(specifier: string): string {
  return specifier
    .replace(/^@salesforce\/apex\//, '')
    .replace(/\.js$/, '')
    .replace(/\//g, '.');
}

/**
 * Create an imperative Apex function shim used by compiled LWC imports.
 * Example: `export default createApexInvoker('HomeOfficeMessageController.getActiveMessages')`
 */
export function createApexInvoker(methodSpec: string) {
  const method = apexMethodKey(methodSpec);
  return async function invokeApex(params: Record<string, unknown> = {}) {
    const bridge = getPlatformBridge();
    const { result } = await bridge.call('apex.invoke', { method, params });
    return result;
  };
}

/** Wire-style adapter factory for @wire(apexMethod). */
export function createApexWireAdapter(methodSpec: string) {
  const method = apexMethodKey(methodSpec);
  class ApexWireAdapter {
    callback: ((value: unknown) => void) | null = null;
    config: Record<string, unknown> | undefined;

    constructor(callback: (value: unknown) => void) {
      this.callback = callback;
    }

    connect() {
      void this.refresh();
    }

    disconnect() {
      this.callback = null;
    }

    update(config?: Record<string, unknown>) {
      this.config = config;
      void this.refresh();
    }

    async refresh() {
      if (!this.callback) return;
      try {
        const bridge = getPlatformBridge();
        const { result } = await bridge.call('apex.wire', {
          method,
          params: this.config ?? {}
        });
        this.callback({ data: result, error: undefined });
      } catch (e) {
        this.callback?.({
          data: undefined,
          error: { body: { message: e instanceof Error ? e.message : String(e) } }
        });
      }
    }
  }
  return ApexWireAdapter;
}
