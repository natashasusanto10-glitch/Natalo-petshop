/// FCM service stub — push notifications disabled sampai google-services.json
/// di-drop ke android/app/. Lihat PUSH_SETUP.md untuk setup lengkap.
///
/// Semua method no-op supaya kode pemanggil tidak perlu diubah.
/// Badge counting tetap jalan via NotificationCounts polling (60s interval).
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  bool get firebaseReady => false;
  String? get currentToken => null;

  Future<void> init() async {
    // no-op: Firebase belum dikonfigurasi.
  }

  Future<void> registerAfterLogin() async {
    // no-op.
  }

  Future<void> unregister() async {
    // no-op.
  }
}
