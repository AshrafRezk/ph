/** Module registry without importing @lwc/engine-dom (Node-test friendly). */

const registry = new Map<string, any>();

export function registerLwcModule(bundleName: string, Ctor: any): void {
  const name = normalizeBundle(bundleName);
  registry.set(name, Ctor);
}

export function getRegisteredLwc(bundleName: string): any | undefined {
  return registry.get(normalizeBundle(bundleName));
}

export function listRegisteredLwcs(): string[] {
  return [...registry.keys()];
}

export function normalizeBundle(bundle: string): string {
  const s = bundle.trim();
  if (s.startsWith('c/')) return s;
  if (s.startsWith('c:')) return `c/${s.slice(2)}`;
  return `c/${s}`;
}

export function bundleToTag(bundle: string): string {
  return (
    'osr-lwc-' +
    normalizeBundle(bundle)
      .replace(/^[\w.-]+\//, '')
      .replace(/([a-z])([A-Z])/g, '$1-$2')
      .replace(/__/g, '-')
      .replace(/\//g, '-')
      .toLowerCase()
  );
}
