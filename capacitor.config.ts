import type { CapacitorConfig } from "@capacitor/cli";
import { KeyboardResize, KeyboardStyle } from "@capacitor/keyboard";

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
      "www.natalopetshop.com",
      "natalopetshop.com",
      "*.natalopetshop.com",
    ],
  },

  ios: {
    // Status bar default: dark icons di atas white bg (selaras dgn header
    // putih web). Lihat plugins.StatusBar di bawah untuk runtime config.
    contentInset: "automatic",
    // Kalau pakai cookie auth (jose JWT lewat httpOnly cookie),
    // biarkan WebView pakai shared cookie store iOS.
    limitsNavigationsToAppBoundDomains: false,
    // WebView container background — terlihat di safe area top/bottom
    // sebelum WebView paint penuh. Selaras dgn root/status bar putih.
    backgroundColor: "#ffffff",
  },

  plugins: {
    SplashScreen: {
      // Plugin show storyboard view (sekarang putih, NO logo — sudah edited
      // di LaunchScreen.storyboard) selama 1s untuk cover cold-start network
      // blank period: WebView creation + HTML fetch + JS bundle download.
      // Setelah plugin hide, WebView visible dengan AppSplashOverlay yang
      // langsung punya "N" visible (initial state show-n di komponen) →
      // animation continues seamlessly, no jarring transition.
      launchShowDuration: 1000,
      launchAutoHide: true,
      backgroundColor: "#ffffff",
      showSpinner: false, // Tetap clean, no spinner
      fadeOutDuration: 250, // Smooth handoff ke web overlay
      androidScaleType: "CENTER_CROP",
    },
    StatusBar: {
      // Capacitor Style.LIGHT = darkContent = ikon hitam, untuk bg terang.
      style: "LIGHT",
      backgroundColor: "#ffffff",
      overlaysWebView: false,
    },
    Keyboard: {
      // resize Native → iOS WebView TIDAK resize saat keyboard muncul,
      // keyboard float di atas. Kita handle layout via visualViewport API
      // + @capacitor/keyboard event keyboardWillShow.keyboardHeight di
      // CheckoutVoucherCard. Pakai Body bikin window.innerHeight shrink
      // sehingga kalkulasi keyboard-inset = 0 (visualViewport.height
      // sudah match innerHeight) — sheet tidak pernah naik.
      resize: KeyboardResize.Native,
      // Default follows app theme (light/dark).
      style: KeyboardStyle.Default,
      resizeOnFullScreen: true,
    },
  },
};

export default config;
