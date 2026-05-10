import type { CapacitorConfig } from "@capacitor/cli";

/**
 * Capacitor config — Natalo Petshop iOS wrapper.
 *
 * Strategi: WebView remote-load ke domain produksi (bukan static export),
 * karena project ini punya Prisma + API routes yang harus jalan di server.
 * Yang diinstall ke iPhone adalah shell native tipis yang membuka URL prod.
 *
 * Sebelum build, isi `server.url` dengan domain produksi yang benar
 * (contoh: https://natalo-petshop.vercel.app).
 */
const config: CapacitorConfig = {
  appId: "com.natalo.petshop",
  appName: "Natalo Petshop",
  // webDir tetap di-set walau pakai server.url — Capacitor butuh ini ada,
  // dan jadi fallback offline kalau server.url tidak bisa dijangkau.
  webDir: "out",

  server: {
    // GANTI dengan domain produksi sebelum `npx cap sync ios`.
    url: "https://natalo-petshop.vercel.app",
    cleartext: false,
    // iOS allowed navigation — pastikan deep-link & redirect ke domain ini
    // tidak keluar dari WebView ke Safari.
    allowNavigation: [
      "natalo-petshop.vercel.app",
      "*.natalo-petshop.vercel.app",
    ],
  },

  ios: {
    // Tampilan status bar default — light content di atas brand blue.
    contentInset: "automatic",
    // Kalau pakai cookie auth (jose JWT lewat httpOnly cookie),
    // biarkan WebView pakai shared cookie store iOS.
    limitsNavigationsToAppBoundDomains: false,
    backgroundColor: "#1E5FBF",
  },

  plugins: {
    SplashScreen: {
      // Plugin show storyboard view (solid brand blue, NO logo — sudah edited
      // di LaunchScreen.storyboard) selama 1s untuk cover cold-start network
      // blank period: WebView creation + HTML fetch + JS bundle download.
      // Setelah plugin hide, WebView visible dengan AppSplashOverlay yang
      // langsung punya "N" visible (initial state show-n di komponen) →
      // animation continues seamlessly, no jarring transition.
      launchShowDuration: 1000,
      launchAutoHide: true,
      backgroundColor: "#1E5FBF",
      showSpinner: false, // Tetap clean, no spinner — full solid blue saja
      fadeOutDuration: 250, // Smooth handoff ke web overlay
      androidScaleType: "CENTER_CROP",
    },
    StatusBar: {
      style: "LIGHT",
      backgroundColor: "#1E5FBF",
      overlaysWebView: false,
    },
    Keyboard: {
      // resize "body" → WebView resize saat keyboard muncul, body shrink supaya
      // input area gak ke-cover. iOS pakai ResizePolicy.Body.
      resize: "body",
      // Style "default" follows app theme (light/dark). Set "light" force.
      style: "default",
      resizeOnFullScreen: true,
    },
  },
};

export default config;
