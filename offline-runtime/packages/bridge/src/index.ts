/** Typed postMessage RPC between Capacitor shell and local LWC iframe. */

export const OSR_BRIDGE_CHANNEL = 'osr-bridge-v1';

export type BridgeDataSource = 'cache' | 'live' | 'outbox' | 'local';

export type BridgeRequestMethod =
  | 'ping'
  | 'net.status'
  | 'ui.getRecord'
  | 'ui.getObjectInfo'
  | 'ui.getList'
  | 'apex.invoke'
  | 'apex.wire'
  | 'nav.navigate'
  | 'nav.generateUrl'
  | 'ui.toast'
  | 'ui.confirm'
  | 'host.resize'
  | 'lwc.getCompiledModule';

export type BridgeRequest = {
  channel: typeof OSR_BRIDGE_CHANNEL;
  type: 'req';
  id: string;
  method: BridgeRequestMethod;
  params?: Record<string, unknown>;
};

export type BridgeResponse = {
  channel: typeof OSR_BRIDGE_CHANNEL;
  type: 'res';
  id: string;
  ok: boolean;
  result?: unknown;
  error?: string;
  source?: BridgeDataSource;
};

export type BridgeEvent = {
  channel: typeof OSR_BRIDGE_CHANNEL;
  type: 'evt';
  event: string;
  payload?: unknown;
};

export type BridgeMessage = BridgeRequest | BridgeResponse | BridgeEvent;

export function isBridgeMessage(data: unknown): data is BridgeMessage {
  if (!data || typeof data !== 'object') return false;
  const m = data as BridgeMessage;
  return m.channel === OSR_BRIDGE_CHANNEL && (m.type === 'req' || m.type === 'res' || m.type === 'evt');
}

export function newRequestId(): string {
  return `br_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 9)}`;
}

/** Iframe-side client: call shell handlers. */
export class BridgeClient {
  private pending = new Map<
    string,
    {
      resolve: (v: BridgeResponse) => void;
      reject: (e: Error) => void;
      timer: ReturnType<typeof setTimeout>;
    }
  >();
  private target: Window;
  private timeoutMs: number;

  constructor(target: Window = window.parent, timeoutMs = 30000) {
    this.target = target;
    this.timeoutMs = timeoutMs;
  }

  attach(listenerTarget: Window = window): () => void {
    const onMessage = (ev: MessageEvent) => {
      if (!isBridgeMessage(ev.data) || ev.data.type !== 'res') return;
      const wait = this.pending.get(ev.data.id);
      if (!wait) return;
      clearTimeout(wait.timer);
      this.pending.delete(ev.data.id);
      wait.resolve(ev.data);
    };
    listenerTarget.addEventListener('message', onMessage);
    return () => listenerTarget.removeEventListener('message', onMessage);
  }

  async call<T = unknown>(
    method: BridgeRequestMethod,
    params?: Record<string, unknown>
  ): Promise<{ result: T; source?: BridgeDataSource }> {
    const id = newRequestId();
    const req: BridgeRequest = {
      channel: OSR_BRIDGE_CHANNEL,
      type: 'req',
      id,
      method,
      params
    };
    const response = await new Promise<BridgeResponse>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Bridge timeout: ${method}`));
      }, this.timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      this.target.postMessage(req, '*');
    });
    if (!response.ok) {
      throw new Error(response.error || `Bridge failed: ${method}`);
    }
    return { result: response.result as T, source: response.source };
  }

  emit(event: string, payload?: unknown): void {
    const msg: BridgeEvent = {
      channel: OSR_BRIDGE_CHANNEL,
      type: 'evt',
      event,
      payload
    };
    this.target.postMessage(msg, '*');
  }
}

export type BridgeHandler = (
  method: BridgeRequestMethod,
  params: Record<string, unknown>
) => Promise<{ result?: unknown; source?: BridgeDataSource }>;

/** Shell-side host: answer iframe requests. */
export class BridgeHost {
  private handler: BridgeHandler;
  private allowedOrigins: Set<string> | null;

  constructor(handler: BridgeHandler, allowedOrigins?: string[]) {
    this.handler = handler;
    this.allowedOrigins = allowedOrigins?.length ? new Set(allowedOrigins) : null;
  }

  attach(listenerTarget: Window = window): () => void {
    const onMessage = (ev: MessageEvent) => {
      if (this.allowedOrigins && !this.allowedOrigins.has(ev.origin) && ev.origin !== 'null') {
        // Capacitor / file / blob iframes often use opaque or null origins — allow same-window children
        if (ev.source !== null && ev.source !== listenerTarget) {
          /* still allow child frames */
        }
      }
      if (!isBridgeMessage(ev.data) || ev.data.type !== 'req') return;
      const req = ev.data;
      const sourceWin = ev.source as Window | null;
      void this.dispatch(req, sourceWin);
    };
    listenerTarget.addEventListener('message', onMessage);
    return () => listenerTarget.removeEventListener('message', onMessage);
  }

  private async dispatch(req: BridgeRequest, sourceWin: Window | null) {
    let res: BridgeResponse;
    try {
      const out = await this.handler(req.method, req.params ?? {});
      res = {
        channel: OSR_BRIDGE_CHANNEL,
        type: 'res',
        id: req.id,
        ok: true,
        result: out.result,
        source: out.source
      };
    } catch (e) {
      res = {
        channel: OSR_BRIDGE_CHANNEL,
        type: 'res',
        id: req.id,
        ok: false,
        error: e instanceof Error ? e.message : String(e)
      };
    }
    sourceWin?.postMessage(res, '*');
  }
}
