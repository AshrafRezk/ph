import { registerPlugin } from '@capacitor/core';

export interface OsrOAuthPlugin {
  openOAuthSession(options: {
    url: string;
    callbackScheme: string;
  }): Promise<{ url: string }>;
}

export const OsrOAuth = registerPlugin<OsrOAuthPlugin>('OsrOAuth');
