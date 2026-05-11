import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.natalopetshop.app',
  appName: 'Natalo Petshop',
  webDir: 'www',

  // === HYBRID MODE: load live website inside native app ===
  server: {
    url: 'https://www.natalopetshop.com',
    androidScheme: 'https',
    cleartext: false,
    // Domain ini akan di-treat sebagai "internal" — tidak buka di browser eksternal
    allowNavigation: [
      'www.natalopetshop.com',
      'natalopetshop.com',
      '*.natalopetshop.com',
    ],
  },

  android: {
    // Splash screen pakai theme color dari website Anda
    backgroundColor: '#1E5FBF',
    allowMixedContent: false,
    captureInput: true,
    webContentsDebuggingEnabled: false, // true saat development, false untuk release
  },

  plugins: {
    SplashScreen: {
      // 2500ms = aman untuk cover cold-start di jaringan 3G/4G Indonesia.
      // Setelah hide, WebView muncul dengan AppSplashOverlay (komponen React di
      // app/layout.tsx) yang lanjut animasi Netflix-style: N → atalo → PETSHOP.
      // Initial state "show-n" sudah ada di SSR HTML, jadi handoff mulus.
      launchShowDuration: 2500,
      launchAutoHide: true,
      backgroundColor: '#1E5FBF',
      androidSplashResourceName: 'splash',
      androidScaleType: 'CENTER_CROP',
      // Spinner OFF — NL+paw sudah jadi focal point, spinner cuma noise.
      // Animasi gerak diambil alih oleh AppSplashOverlay setelah WebView visible.
      showSpinner: false,
      // Fade 500ms supaya native splash (NL+paw) cross-fade halus ke
      // AppSplashOverlay (yang punya "N" sudah pre-rendered di SSR).
      fadeOutDuration: 500,
      splashFullScreen: true,
      splashImmersive: true,
    },
    StatusBar: {
      // LIGHT supaya ikon putih di atas brand blue saat splash & header app.
      // (Sebelumnya DARK — tidak konsisten dengan iOS dan kurang terbaca.)
      style: 'LIGHT',
      backgroundColor: '#1E5FBF',
      overlaysWebView: false,
    },
  },
};

export default config;
