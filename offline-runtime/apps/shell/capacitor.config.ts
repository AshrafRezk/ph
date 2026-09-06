import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.osr.offline',
  appName: 'Offline Salesforce Runtime',
  webDir: 'dist',
  // Identify the WebView to map tile CDNs (OSM blocks generic Android WebView UAs).
  appendUserAgent: ' OSR-Offline/0.1 (+https://github.com/osr; com.osr.offline)',
  server: {
    androidScheme: 'https'
  },
  android: {
    appendUserAgent: ' OSR-Offline/0.1 (+https://github.com/osr; com.osr.offline)'
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
