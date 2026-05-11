import type { CapacitorConfig } from "@capacitor/cli";
import { KeyboardResize, KeyboardStyle } from "@capacitor/keyboard";

/**
 * Capacitor config — Natalo Petshop iOS + Android wrapper.
 *
 * Strategi: WebView remote-load ke domain produksi (bukan static export),
 * karena project ini punya Prisma + API routes yang harus jalan di server.
 * Yang diinstall ke iPhone / HP Android adalah shell native tipis yang
 * membuka URL prod.
 *
 * Sebelum build, isi `server.url` dengan domain produksi yang benar
 * (contoh: https://natalo-petshop.vercel.app).
 *
 * ─────────────────────────────────────────────────────────────────────
 *  ANDROID + FCM PUSH SETUP (lakukan sekali sebelum build APK pertama):
 * ─────────────────────────────────────────────────────────────────────
 *  1) Firebase Console → Add project (or pakai project existing).
 *  2) Project → Add app → Android, package name: "com.natalo.petshop".
 *  3) Download `google-services.json` → simpan ke `android/app/google-services.json`.
 *  4) Project Settings → Service accounts → Generate new private key.
 *     Dari JSON yang ter-download, isi env vars di `.env.local` /
 *     Vercel: FCM_PROJECT_ID, FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY.
 *  5) Pastikan `android/app/build.gradle` punya plugin Google Services
 *     (Capacitor PushNotifications plugin v8 auto-inject saat `cap sync`).
 *     Jalankan: `npm run cap:sync:android`.
 *  6) Build via Android Studio: `npm run cap:open:android` → Build → Generate
 *     Signed Bundle/APK. Untuk Play Store kirim AAB.
 *
 *  Push delivery flow (Android):
 *    Order status berubah → backend `sendOrderStatusPush()` → kirim ke 3
 *    channel paralel (web push, APNs, FCM) → device dgn endpoint "fcm:<token>"
 *    nerima dari `firebase-admin/messaging` → ditampilkan native oleh OS
 *    saat app background, atau di-forward ke `pushNotificationReceived`
 *    listener saat app foreground.
 * ─────────────────────────────────────────────────────────────────────
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

  android: {
    // WebView container background — same rationale as iOS (mencegah flash
    // hitam di area system bars sebelum WebView paint).
    backgroundColor: "#ffffff",
    // Allow mixed content tetap false di production (server.url HTTPS).
    allowMixedContent: false,
    // Untuk cookie auth (jose JWT httpOnly) kerja di Android WebView,
    // captureInput dibiarkan default — WebView handle cookies via standard
    // CookieManager yang shared dengan domain server.url.
    captureInput: false,
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
