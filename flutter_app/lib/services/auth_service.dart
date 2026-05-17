import '../models/member_profile.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';
import 'member_service.dart';

class AuthService {
  Future<MemberProfile> login({
    required String identifier,
    required String password,
  }) async {
    final data = await apiClient.postJson(
      '/api/auth/member-login',
      body: {
        'identifier': identifier.trim(),
        'password': password,
      },
    );
    final user = data['user'];
    if (user is! Map<String, dynamic>) {
      throw const ApiException('Response login tidak valid.');
    }

    try {
      return await memberService.fetchProfile();
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        throw const ApiException(
          'Sesi login belum tersimpan. Coba login ulang.',
          statusCode: 401,
        );
      }
      return MemberProfile.fromApiJson(user);
    }
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
    final data = await apiClient.postJson(
      '/api/auth/member-register',
      body: {
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'phone': phone.trim(),
        'password': password,
        'confirmPassword': confirmPassword,
        if (otp != null && otp.trim().isNotEmpty) 'otp': otp.trim(),
      },
    );
    // Step 2 (dengan OTP) return user. Step 1 return {message: "OTP terkirim"}.
    final user = data['user'];
    if (user is Map<String, dynamic>) {
      return MemberProfile.fromApiJson(user);
    }
    return null;
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
    final data = await apiClient.getJson('/api/auth/me');
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
}

final authService = AuthService();
