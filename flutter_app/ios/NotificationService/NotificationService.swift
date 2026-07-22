import UserNotifications
import FirebaseMessaging

/// Notification Service Extension — WAJIB ada supaya rich image
/// (`imageUrl`, dikirim via `mutable-content: 1` + `fcmOptions.imageUrl`
/// dari lib/fcm.ts) benar-benar diunduh & ditempel ke notifikasi iOS.
/// Tanpa target ini, iOS diam-diam mengabaikan field tsb — notifikasi
/// selalu tampil polos dengan ikon app, video/foto thumbnail tak pernah
/// kelihatan. FirebaseMessaging SDK menyediakan helper-nya, kita tinggal
/// panggil dari sini (extension target terpisah, WAJIB dibuat lewat
/// Xcode — lihat catatan setup di README/PR terkait).
class NotificationService: UNNotificationServiceExtension {

  var contentHandler: ((UNNotificationContent) -> Void)?
  var bestAttemptContent: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

    guard let bestAttemptContent = bestAttemptContent else {
      contentHandler(request.content)
      return
    }

    // Firebase parse fcmOptions.imageUrl dari payload, unduh gambarnya,
    // lalu attach sebagai UNNotificationAttachment sebelum contentHandler
    // dipanggil. Kalau unduh gagal (URL kedaluwarsa/403/timeout), fallback
    // otomatis ke notifikasi teks biasa — tidak pernah crash/hang.
    FIRMessagingExtensionHelper().populateNotificationContent(
      bestAttemptContent,
      withContentHandler: contentHandler
    )
  }

  override func serviceExtensionTimeWillExpire() {
    // OS kasih waktu terbatas (~30s) untuk unduh gambar. Kalau lewat,
    // WAJIB tetap panggil contentHandler dgn best-effort content supaya
    // notifikasi tidak macet tanpa muncul sama sekali.
    if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
      contentHandler(bestAttemptContent)
    }
  }
}
