import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import app_links

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // WAJIB boot Firebase iOS SDK SEBELUM Flutter engine + plugin registrant
    // jalan. Tanpa ini, FlutterImplicitEngineDelegate pattern bikin plugin
    // registration delayed ke didInitializeImplicitFlutterEngine() callback,
    // yang fires SETELAH Flutter Dart code mulai eksekusi. Dart panggil
    // Firebase.initializeApp() → race condition → silent fail → getToken()
    // return null → registerWithServer() early-return tanpa hit backend.
    //
    // Symptom yang muncul tanpa baris ini:
    //   - Popup iOS notification permission tidak pernah muncul
    //   - FCM token null di Flutter
    //   - /api/push/subscribe-fcm tidak pernah di-call (zero di Vercel logs)
    //   - Firebase Cloud Messaging Reports: Sends X, Received 0
    //
    // Reference: firebase_messaging Flutter plugin docs explicit
    // mention `FirebaseApp.configure()` di AppDelegate untuk iOS.
    FirebaseApp.configure()
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()

    // COLD START universal link — WAJIB ditangkap manual di sini.
    //
    // app_links di iOS hanya menangkap tautan lewat callback
    // `application(_:continue:)`, yang diteruskan FlutterAppDelegate HANYA ke
    // plugin yang SUDAH terdaftar. Pola engine implisit di file ini
    // (FlutterImplicitEngineDelegate) mendaftarkan plugin belakangan — di
    // didInitializeImplicitFlutterEngine, bukan di dalam didFinishLaunching
    // seperti template lama — sedangkan iOS mengantarkan tautan cold start
    // tepat setelah peluncuran. Tautannya lewat sebelum ada yang mendengar:
    // getInitialLink() balas nil, stream diam, user nyangkut di Beranda.
    // Warm start tak terpengaruh (plugin sudah lama terdaftar) — persis
    // gejala "warm OK, cold gagal" yang bertahan walau
    // FlutterDeepLinkingEnabled sudah false.
    //
    // AppLinks.shared adalah singleton yang SAMA dengan yang nanti didaftarkan
    // registrant, jadi tautan yang dititip di sini terbaca oleh
    // getInitialLink() Dart begitu channel-nya siap.
    if let url = AppLinks.shared.getLink(launchOptions: launchOptions) {
      AppLinks.shared.handleLink(url: url)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Jaring kedua untuk race yang sama: iOS memanggil ini setelah peluncuran.
  // Kalau plugin belum terdaftar saat itu, forwarding super tak sampai ke
  // app_links — titipkan langsung. handleLink aman dipanggil ganda: sisi Dart
  // punya dedupe window per-target, jadi saat KEDUA jalur sampai (delegate
  // sudah terdaftar), tautan tidak dieksekusi dua kali.
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if let url = userActivity.webpageURL {
      AppLinks.shared.handleLink(url: url)
    }
    return super.application(
      application, continue: userActivity, restorationHandler: restorationHandler)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Ensure Firebase Messaging receives the APNs token even when app
    // delegate proxy/swizzling timing changes under TestFlight builds.
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[push] iOS failed to register for remote notifications: %@", error.localizedDescription)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
