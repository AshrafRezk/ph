import { createElement } from 'lwc';
import type { LightningElement } from 'lwc';
import {
  registerLwcModule,
  getRegisteredLwc,
  listRegisteredLwcs,
  normalizeBundle,
  bundleToTag
} from './registry.js';

export type MountedLwc = {
  element: HTMLElement;
  unmount: () => void;
};

export {
  registerLwcModule,
  getRegisteredLwc,
  listRegisteredLwcs,
  normalizeBundle,
  bundleToTag
};

/**
 * Mount a registered LWC constructor into `host` using @lwc/engine-dom createElement.
 */
export function mountLwcElement(
  host: HTMLElement,
  bundleName: string,
  props: Record<string, unknown> = {}
): MountedLwc {
  const name = normalizeBundle(bundleName);
  const Ctor = getRegisteredLwc(name);
  if (!Ctor) {
    throw new Error(`LWC module not registered: ${name}`);
  }
  host.innerHTML = '';
  const tag = bundleToTag(name);
  const element = createElement(tag, { is: Ctor }) as HTMLElement & LightningElement;
  for (const [k, v] of Object.entries(props)) {
    try {
      (element as any)[k] = v;
    } catch {
      element.setAttribute(k, String(v));
    }
  }
  host.appendChild(element);
  return {
    element,
    unmount: () => {
      element.remove();
    }
  };
}

/**
 * Mount a plain Custom Element (spike / non-LWC modules) into host.
 */
export function mountCustomElement(
  host: HTMLElement,
  tagName: string,
  props: Record<string, unknown> = {}
): MountedLwc {
  host.innerHTML = '';
  const element = document.createElement(tagName);
  for (const [k, v] of Object.entries(props)) {
    (element as any)[k] = v;
    element.setAttribute(k, String(v));
  }
  host.appendChild(element);
  return {
    element,
    unmount: () => element.remove()
  };
}

export { createElement };
export { LightningElement, api, track, wire } from 'lwc';
