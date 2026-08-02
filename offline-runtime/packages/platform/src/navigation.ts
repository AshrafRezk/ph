import { getPlatformBridge } from './bridge-context.js';

export type PageReference = {
  type: string;
  attributes?: Record<string, unknown>;
  state?: Record<string, unknown>;
};

export async function navigate(pageRef: PageReference, replace = false): Promise<void> {
  const bridge = getPlatformBridge();
  await bridge.call('nav.navigate', { pageRef, replace });
}

export async function generateUrl(pageRef: PageReference): Promise<string> {
  const bridge = getPlatformBridge();
  const { result } = await bridge.call<string>('nav.generateUrl', { pageRef });
  return result ?? '#';
}

/** Mixin-style helper for compiled LWCs (attach methods onto class prototype). */
export function NavigationMixin<T extends new (...args: any[]) => object>(Base: T) {
  return class extends Base {
    [NavigationMixin.Navigate](pageRef: PageReference, replace?: boolean) {
      return navigate(pageRef, replace);
    }
    [NavigationMixin.GenerateUrl](pageRef: PageReference) {
      return generateUrl(pageRef);
    }
  };
}

export namespace NavigationMixin {
  export const Navigate = Symbol('Navigate');
  export const GenerateUrl = Symbol('GenerateUrl');
}
