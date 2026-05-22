import '../models/member_profile.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

class AuthService {
  String? _lastSessionToken;

  String? get lastSessionToken => _lastSessionToken;

  Future<MemberProfile> login({
    required String identifier,
    required String password,
  }) async {
    _lastSessionToken = null;
    final data = _expectMap(
      await apiClient.postJson(
        '/api/auth/member-login',
        body: {
          'identifier': identifier.trim(),
          'password': password,
        },
      ),
      fallbackMessage: 'Response login tidak valid.',
    );
    _lastSessionToken = _sessionTokenFrom(data);
    final user =
        _userFrom(data, fallbackMessage: 'Response login tidak valid.');
    return MemberProfile.fromApiJson(user);
  }

  /// Step 1 register: kirim data tanpa OTP → server kirim kode ke email + WA.
  /// Step 2 register: kirim data + OTP → server buat user.
  ///
  /// Match endpoint PWA POST /api/auth/member-register dengan dua mode di
  /// satu endpoint (otp empty = step 1, otp filled = step 2).
  Future<MemberProfile?> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String confirmPassword,
    String? otp,
  }) async {
    // Register bikin user baru di DB production — block di read-only
    // supaya Capacitor admin tidak dapat user test dari Flutter.
    readOnlyMode.assertWritable('register');
    final isVerifyStep = otp != null && otp.trim().isNotEmpty;
    final data = _expectMap(
      await apiClient.postJson(
        '/api/auth/member-register',
        timeout: isVerifyStep
            ? const Duration(seconds: 20)
            : const Duration(seconds: 75),
        body: {
          'name': name.trim(),
          'email': email.trim().toLowerCase(),
          'phone': phone.trim(),
          'password': password,
          'confirmPassword': confirmPassword,
          if (otp != null && otp.trim().isNotEmpty) 'otp': otp.trim(),
        },
      ),
      fallbackMessage: 'Response daftar member tidak valid.',
    );
    // Step 2 (dengan OTP) return user. Step 1 return {message: "OTP terkirim"}.
    final user = data['user'];
    if (user is Map<String, dynamic>) {
      return MemberProfile.fromApiJson(user);
    }
    return null;
  }

  /// Request OTP login via WhatsApp. Match endpoint POST
  /// /api/auth/member-login-otp/request — body `{phone}`.
  ///
  /// Server selalu return success 200 (anti-enumeration): kalau nomor
  /// tidak terdaftar, response sukses tapi WA tidak benar-benar dikirim.
  /// Throw ApiException kalau ada error 429 / 5xx.
  ///
  /// OTP berlaku 5 menit, kirim via Fonnte. Rate limit 5/10menit per IP+phone.
  Future<void> requestLoginOtp({required String phone}) async {
    readOnlyMode.assertWritable('request_login_otp');
    await apiClient.postJson(
      '/api/auth/member-login-otp/request',
      body: {'phone': phone.trim()},
    );
  }

  /// Verify OTP login. Match endpoint POST /api/auth/member-login-otp/verify —
  /// body `{phone, otp}`. Sukses → server set session cookie + return user.
  ///
  /// Returns full MemberProfile setelah login berhasil (re-fetch via /me
  /// supaya field lengkap, sama seperti `login()` password flow).
  /// Throw ApiException(401) kalau OTP salah, 400 kalau expired / belum diminta.
  Future<MemberProfile> verifyLoginOtp({
    required String phone,
    required String otp,
  }) async {
    readOnlyMode.assertWritable('verify_login_otp');
    _lastSessionToken = null;
    final data = _expectMap(
      await apiClient.postJson(
        '/api/auth/member-login-otp/verify',
        body: {
          'phone': phone.trim(),
          'otp': otp.trim(),
        },
      ),
      fallbackMessage: 'Response login OTP tidak valid.',
    );
    _lastSessionToken = _sessionTokenFrom(data);
    final user =
        _userFrom(data, fallbackMessage: 'Response login OTP tidak valid.');
    return MemberProfile.fromApiJson(user);
  }

  /// Request reset password link. Match endpoint PWA POST /api/auth/forgot-password.
  /// Server selalu return success (anti email enumeration) — kalau email tidak
  /// terdaftar, tetap sukses tapi tidak ada email yang dikirim. Rate limit 3/jam.
  Future<void> forgotPassword(String email) async {
    await apiClient.postJson(
      '/api/auth/forgot-password',
      body: {'email': email.trim().toLowerCase()},
    );
  }

  Future<MemberProfile?> me() async {
    final data = _expectMap(
      await apiClient.getJson('/api/auth/me'),
      fallbackMessage: 'Response profil member tidak valid.',
    );
    if (data['id'] == null) return null;
    return MemberProfile.fromApiJson(data);
  }

  Future<void> logout() async {
    try {
      await apiClient.postJson(
        '/api/auth/logout',
        body: {'scope': 'CUSTOMER'},
      );
    } finally {
      await apiClient.clearSession();
    }
  }

  Future<void> logoutLocal() {
    return apiClient.clearSession();
  }

  /// Hapus akun member secara permanen. Match endpoint PWA
  /// POST /api/account/delete dengan body `{confirmation: "HAPUS AKUN SAYA"}`.
  ///
  /// User HARUS ketik phrase "HAPUS AKUN SAYA" di UI untuk konfirmasi —
  /// pattern anti-accident yang sama seperti GitHub repo delete.
  ///
  /// Server akan:
  /// - Delete password reset tokens
  /// - Anonymize order history (keep for tax/audit, strip PII)
  /// - Hapus profile + addresses + favorites + cart + sessions
  Future<void> deleteAccount({String confirmation = 'HAPUS AKUN SAYA'}) async {
    readOnlyMode.assertWritable('delete_account');
    try {
      await apiClient.postJson(
        '/api/account/delete',
        body: {'confirmation': confirmation},
      );
    } finally {
      // Always clear local session.
      await apiClient.clearSession();
    }
  }

  /// Logout dari semua perangkat LAIN (current device tetap login).
  /// Match endpoint PWA POST /api/account/sessions/revoke-others.
  ///
  /// Mekanisme: increment User.tokenVersion → JWT lama (di device lain)
  /// gagal validasi getSession → user perlu login ulang di sana.
  /// Current device dapat JWT baru supaya tetap login.
  Future<void> revokeOtherSessions() async {
    readOnlyMode.assertWritable('revoke_other_sessions');
    await apiClient.postJson(
      '/api/account/sessions/revoke-others',
      body: const {},
    );
  }

  /// Reset password dengan token dari email link. Match endpoint PWA
  /// POST /api/auth/reset-password — body `{token, newPassword}`.
  ///
  /// Token didapat dari email yang dikirim via `forgotPassword()`.
  /// Token expired ~1 jam.
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    readOnlyMode.assertWritable('reset_password');
    await apiClient.postJson(
      '/api/auth/reset-password',
      body: {
        'token': token,
        'newPassword': newPassword,
      },
    );
  }

  Map<String, dynamic> _expectMap(
    dynamic value, {
    required String fallbackMessage,
  }) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      final trimmed = value.trimLeft();
      if (trimmed.startsWith('<!DOCTYPE html') || trimmed.startsWith('<html')) {
        throw const ApiException(
          'Server membalas halaman web, bukan data login. Cek koneksi API.',
        );
      }
    }
    throw ApiException(fallbackMessage);
  }

  Map<String, dynamic> _userFrom(
    Map<String, dynamic> data, {
    required String fallbackMessage,
  }) {
    final user = data['user'] ?? data['data'];
    if (user is Map<String, dynamic>) return user;
    if (user is Map) return Map<String, dynamic>.from(user);
    throw ApiException(fallbackMessage);
  }

  String? _sessionTokenFrom(Map<String, dynamic> data) {
    final token = data['token'] ??
        data['sessionToken'] ??
        data['session_token'] ??
        apiClient.lastSessionToken;
    final normalized = token?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

final authService = AuthService();
