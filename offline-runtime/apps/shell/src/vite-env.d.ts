/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SF_CLIENT_ID?: string;
  readonly VITE_SF_REDIRECT_URI?: string;
  readonly VITE_SF_WEB_REDIRECT_URI?: string;
  readonly VITE_SF_LOGIN_URL?: string;
  readonly VITE_SF_API_VERSION?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
