/// <reference types="@capacitor/keyboard" />

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
    // Production canonical domain. WebView load disini supaya cookie domain
    // (member_session, admin_session) konsisten dgn web. Sebelumnya pakai
    // vercel preview domain → kalau user navigasi ke natalopetshop.com via
    // deep link, session cookie tidak follow (different cookie domain).
    url: "https://www.natalopetshop.com",
    cleartext: false,
    // iOS allowed navigation — pastikan deep-link & redirect ke domain ini
    // tidak keluar dari WebView ke Safari. Vercel preview tetap di-allowlist
    // untuk staging/QA builds.
    allowNavigation: [
      "www.natalopetshop.com",
      "natalopetshop.com",
      "*.natalopetshop.com",
      "natalo-petshop.vercel.app",
      "*.natalo-petshop.vercel.app",
      "*.uploadthing.com",
      "*.ufs.sh",
      "utfs.io",
    ],
  },

  ios: {
    // Status bar default: dark icons di atas white bg (selaras dgn header
    // putih web). Lihat plugins.StatusBar di bawah untuk runtime config.
    // Jangan biarkan WKWebView menambah safe-area inset native sendiri.
    // App sudah memakai env(safe-area-inset-*) di CSS; "automatic" bikin
    // iOS menambah top/bottom inset kedua yang terlihat putih di Feed.
    contentInset: "never",
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
      // overlaysWebView: false → WebView NOT extend ke area status bar.
      // Native OS handle status bar dengan solid white bg (backgroundColor
      // di atas). Trade-off vs `true`:
      //   true  = WebView fullscreen, butuh CSS padding-top safe-area di
      //           setiap sticky header. Konten bisa overlap status bar saat
      //           non-sticky header scroll-away (mis. detail pesanan
      //           menampilkan alamat masuk ke bawah status bar).
      //   false = WebView start dari bawah status bar, tidak ada overlap
      //           kemungkinan. Sebelumnya pernah show hairline separator
      //           biru di iOS — sekarang sudah di-fix via backgroundColor
      //           putih + LaunchScreen storyboard white.
      // Pilih false untuk safety: content NEVER tertimpa status bar regardless
      // of header sticky / non-sticky behavior. Apply setelah `npx cap sync`.
      overlaysWebView: false,
    },
    Keyboard: {
      // Instagram/Reels-like comment sheet: jangan biarkan iOS WKWebView
      // resize otomatis saat keyboard muncul. Feed comment sheet mengatur
      // offset sendiri via @capacitor/keyboard + visualViewport fallback.
      resize: KeyboardResize.None,
      style: KeyboardStyle.Dark,
    },
  },
};

export default config;
