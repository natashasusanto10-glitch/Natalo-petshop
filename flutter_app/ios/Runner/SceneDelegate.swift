import Flutter
import UIKit
import app_links

class SceneDelegate: FlutterSceneDelegate {
  // COLD START universal link — LAPISAN KETIGA, dan yang sebenarnya.
  //
  // App ini berbasis UIScene (UIApplicationSceneManifest di Info.plist,
  // bawaan Flutter 3.47). Di mode scene, iOS mengantar tautan yang membuka
  // app dari keadaan tertutup lewat `connectionOptions.userActivities` di
  // scene(_:willConnectTo:options:) — BUKAN lewat launchOptions
  // didFinishLaunching, BUKAN lewat application(_:continue:). Dua jalur yang
  // ditangani AppDelegate (#355) tidak pernah dipanggil di mode scene.
  //
  // Warm start bekerja karena Flutter meneruskan scene(_:continue:) ke plugin
  // lama lewat lapisan kompatibilitas. Tapi tautan yang dibawa saat scene
  // PERTAMA KALI tersambung tidak diteruskan ke siapa pun — app_links 6.4.1
  // lahir sebelum era scene dan tidak membaca connectionOptions. Itulah
  // "warm OK, cold nyangkut di Beranda" yang bertahan melewati dua perbaikan.
  //
  // AppLinks.shared = singleton yang sama dengan yang didaftarkan
  // GeneratedPluginRegistrant, jadi tautan yang dititip di sini terbaca oleh
  // getInitialLink() Dart (kalau Dart belum jalan) atau terkirim lewat stream
  // (kalau Dart sudah mendengar). Keduanya sudah ada dedupe di DeepLinkService.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Universal link (https://www.natalopetshop.com/...)
    for activity in connectionOptions.userActivities {
      if let url = activity.webpageURL {
        AppLinks.shared.handleLink(url: url)
      }
    }
    // Skema kustom (kalau suatu hari dipakai) datang lewat urlContexts.
    for context in connectionOptions.urlContexts {
      AppLinks.shared.handleLink(url: context.url)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  // Jaring kedua untuk warm start di mode scene. Super tetap dipanggil supaya
  // plugin lain (dan lapisan kompatibilitas) tetap menerima event-nya;
  // pemanggilan ganda ke handleLink aman — dedupe di sisi Dart.
  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if let url = userActivity.webpageURL {
      AppLinks.shared.handleLink(url: url)
    }
    super.scene(scene, continue: userActivity)
  }
}
