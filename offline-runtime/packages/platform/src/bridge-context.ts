import type { BridgeClient } from '@osr/bridge';

let client: BridgeClient | null = null;

export function setPlatformBridge(c: BridgeClient): void {
  client = c;
}

export function getPlatformBridge(): BridgeClient {
  if (!client) {
    throw new Error('@osr/platform: bridge not initialized (call setPlatformBridge in LWC host)');
  }
  return client;
}
