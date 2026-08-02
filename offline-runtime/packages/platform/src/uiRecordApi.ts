import { getPlatformBridge } from './bridge-context.js';

export async function getRecord(config: {
  recordId: string;
  objectApiName?: string;
  fields?: string[];
  optionalFields?: string[];
}) {
  const bridge = getPlatformBridge();
  const { result } = await bridge.call('ui.getRecord', {
    recordId: config.recordId,
    objectApi: config.objectApiName,
    fields: config.fields,
    optionalFields: config.optionalFields
  });
  return result;
}

export async function getObjectInfo(config: { objectApiName: string }) {
  const bridge = getPlatformBridge();
  const { result } = await bridge.call('ui.getObjectInfo', {
    objectApi: config.objectApiName
  });
  return result;
}

export async function getListUi(config: {
  objectApiName: string;
  listViewApiName?: string;
  pageSize?: number;
}) {
  const bridge = getPlatformBridge();
  const { result } = await bridge.call('ui.getList', {
    objectApi: config.objectApiName,
    listViewApiName: config.listViewApiName,
    pageSize: config.pageSize ?? 50
  });
  return result;
}

/** Minimal @wire adapter for getRecord. */
export class getRecordWireAdapter {
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
    if (!this.callback || !this.config?.recordId) return;
    try {
      const data = await getRecord({
        recordId: String(this.config.recordId),
        objectApiName: this.config.objectApiName
          ? String(this.config.objectApiName)
          : undefined,
        fields: this.config.fields as string[] | undefined
      });
      this.callback({ data, error: undefined });
    } catch (e) {
      this.callback?.({
        data: undefined,
        error: { body: { message: e instanceof Error ? e.message : String(e) } }
      });
    }
  }
}
