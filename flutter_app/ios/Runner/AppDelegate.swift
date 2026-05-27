import Flutter
import UIKit
import FirebaseCore

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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
