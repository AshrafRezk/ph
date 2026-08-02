import { getPlatformBridge } from './bridge-context.js';

export type ToastVariant = 'info' | 'success' | 'warning' | 'error';

export class ShowToastEvent extends CustomEvent<{
  title?: string;
  message?: string;
  variant?: ToastVariant;
  mode?: string;
}> {
  static eventName = 'showtoast';

  constructor(detail: {
    title?: string;
    message?: string;
    variant?: ToastVariant;
    mode?: string;
  }) {
    super(ShowToastEvent.eventName, { detail, bubbles: true, composed: true });
  }
}

export async function showToast(detail: {
  title?: string;
  message?: string;
  variant?: ToastVariant;
  mode?: string;
}): Promise<void> {
  const bridge = getPlatformBridge();
  await bridge.call('ui.toast', detail as Record<string, unknown>);
}
