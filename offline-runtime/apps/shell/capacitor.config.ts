import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.osr.offline',
  appName: 'Offline Salesforce Runtime',
  webDir: 'dist',
  server: {
    androidScheme: 'https'
  },
  plugins: {
    Preferences: {},
    // Bypass WebView CORS for Salesforce OAuth + REST (native HTTP stack)
    CapacitorHttp: {
      enabled: true
    }
  }
};

export default config;
