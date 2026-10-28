import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.zetapharma.fieldpwa',
  appName: 'Zeta Co-Pilot',
  webDir: 'dist',
  server: {
    androidScheme: 'https'
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 2000,
      backgroundColor: '#ffffff',
      showSpinner: false,
      androidSpinnerStyle: 'small',
      spinnerColor: '#0072bc'
    },
    StatusBar: {
      style: 'DARK',
      backgroundColor: '#0176d3'
    },
    App: {
      // Handle deep links for OAuth callbacks
      deepLinks: [
        {
          scheme: 'com.zetapharma.fieldpwa',
          path: '/oauth/callback'
        }
      ]
    },
    PushNotifications: {
      presentationOptions: ['badge', 'sound', 'alert']
    }
  }
};

export default config;