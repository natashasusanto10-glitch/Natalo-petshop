# Customer Chat — Plan: Toggle `canHandleCustomer` di UI NLCATTER

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Memberi **owner** kontrol UI untuk menentukan karyawan mana yang boleh membalas chat customer Natalo — lewat sakelar **"Balas chat customer"** di layar Kelola Karyawan NLCATTER, yang menulis flag `canHandleCustomer` di `users/{uid}`. Menutup gap "mekanisme rules ada (Plan 1) tapi UI toggle belum".

**Architecture:** Flag boolean orthogonal `canHandleCustomer` di `users/{uid}` (project `tokochat-a8879`). Owner menyalakan/mematikan per karyawan; rules (Plan 1 Task 4) sudah mengunci karyawan tak bisa self-grant (immutable-by-self di CREATE+UPDATE), dan owner boleh set. UI ini adalah permukaan owner untuk operasi `users.update({canHandleCustomer})` yang sudah diizinkan rules. **Bukan** role baru — role tetap `owner`/`karyawan` agar filter payroll/absensi (`role == 'karyawan'`) tak rusak (lihat memori `nlcatter-role-filter-gotcha`).

**Tech Stack:** Flutter, Provider (`AuthProvider`), `cloud_firestore` (`users` collection), design tokens `AppColors`/`AppRadius` (`lib/utils/theme.dart`), `RolePill` (`lib/widgets/role_pill.dart`), Node test Flutter (`flutter test`, `test/`).

## Global Constraints

- Semua path relatif ke root repo **NLCHAT** (`C:/Users/USER/Desktop/NLCHAT`).
- **Owner-only:** baris toggle HANYA tampil bila current user owner (`context.read<AuthProvider>().userProfile?.isOwner == true`) **dan** target adalah karyawan (`!u.isOwner`) — owner selalu bisa handle customer, tak perlu flag. Enforcement sebenarnya di rules; UI cuma menyembunyikan kontrol yang pasti gagal.
- **Jangan sentuh** `role`, `active`, `ikutAbsensi`, atau alur payroll/absensi. Perubahan write TERBATAS ke field `canHandleCustomer`.
- Ikuti preseden `ikutAbsensi`/`active`: field boolean di `UserProfile` dengan default, di-parse `?? default`, **tidak** dimasukkan ke `toMap()` (write lewat `.update({...})` langsung, sama seperti `_toggleActive`).
- Default `canHandleCustomer` = **false** (user lama tak otomatis jadi CS). Bandingkan `ikutAbsensi` yang default true — di sini justru sebaliknya, sengaja.
- Chip penanda pakai **tint lembut** (hijau `bgGreen`/`successText`), bukan fill saturasi; jangan menabrak warna pil `RolePill` sky (lihat memori `design-subtle-badges`).
- Konfirmasi tak diperlukan untuk toggle (aksi ringan & reversibel), cukup optimistic update + snackbar — beda dari Nonaktifkan/Hapus yang pakai dialog.

---

## File Structure

- `lib/models/user_model.dart` — **modify**: tambah field + getter + parse `canHandleCustomer`.
- `lib/screens/manage_users_screen.dart` — **modify**: (a) chip "Balas chat" di kartu; (b) baris toggle owner-only di `_showUserMenu`; (c) handler `_toggleCanHandleCustomer`.
- `test/user_model_test.dart` — **create/modify**: uji parsing `canHandleCustomer` (murni, tanpa Firebase).

---

### Task 1: Field `canHandleCustomer` di `UserProfile` — TDD

**Files:**
- Test: `test/user_model_test.dart`
- Modify: `lib/models/user_model.dart`

**Interfaces:**
- Produces: `UserProfile.canHandleCustomer: bool` (default false) + parse dari `data['canHandleCustomer']`. Dikonsumsi Task 2.

- [ ] **Step 1: Tulis test yang gagal — `test/user_model_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nlcatter/models/user_model.dart'; // sesuaikan nama package pubspec

void main() {
  test('canHandleCustomer default false saat field absen', () {
    final u = UserProfile.fromMap({'nama': 'Budi', 'role': 'karyawan'}, 'uid1');
    expect(u.canHandleCustomer, false);
  });

  test('canHandleCustomer terbaca true dari data', () {
    final u = UserProfile.fromMap(
        {'nama': 'Sisca', 'role': 'karyawan', 'canHandleCustomer': true}, 'uid2');
    expect(u.canHandleCustomer, true);
  });

  test('role tetap karyawan (flag tak mengubah role)', () {
    final u = UserProfile.fromMap(
        {'nama': 'Sisca', 'role': 'karyawan', 'canHandleCustomer': true}, 'uid2');
    expect(u.role, 'karyawan');
    expect(u.isOwner, false);
  });
}
```

> Catatan: cek nama package di `pubspec.yaml` (`name:`) untuk import `package:<name>/...`. Bila sudah ada `test/user_model_test.dart`, tambahkan 3 test ini alih-alih menimpa.

- [ ] **Step 2: Jalankan — pastikan GAGAL**

Run (dari root NLCHAT): `flutter test test/user_model_test.dart`
Expected: gagal — `canHandleCustomer` belum ada (compile error / getter undefined).

- [ ] **Step 3: Tambah field ke `lib/models/user_model.dart`**

- Tambah field `final bool canHandleCustomer;` (setelah `ikutAbsensi`), dengan doc singkat:
  ```dart
  // true = boleh buka Customer Inbox & balas chat customer Natalo.
  // Default false (beda dari ikutAbsensi) — user lama TIDAK otomatis jadi CS.
  // Rules mengunci hanya owner yang boleh mengubah (immutable-by-self).
  final bool canHandleCustomer;
  ```
- Tambah ke konstruktor: `this.canHandleCustomer = false,`.
- Tambah ke `fromMap`: `canHandleCustomer: data['canHandleCustomer'] ?? false,`.
- **JANGAN** tambah ke `toMap()` (ikuti preseden `active` yang juga tak ada di `toMap`; write via `.update()`).

- [ ] **Step 4: Jalankan — pastikan LULUS**

Run: `flutter test test/user_model_test.dart`
Expected: 3 test PASS. Golden test lain yang pra-existing flaky (`natalo_colors`, `status_pill`) di luar cakupan — jangan jalankan seluruh suite untuk verifikasi task ini.

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add lib/models/user_model.dart test/user_model_test.dart
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(users): field canHandleCustomer (default false) di UserProfile"
```

---

### Task 2: Chip "Balas chat" + toggle owner-only di Kelola Karyawan

**Files:**
- Modify: `lib/screens/manage_users_screen.dart`

**Interfaces:**
- Consumes: `UserProfile.canHandleCustomer` (Task 1), `AuthProvider.userProfile.isOwner`, `AppColors.bgGreen`/`successText`, `db.collection('users')`.

- [ ] **Step 1: Chip penanda "Balas chat" di kartu karyawan**

Di `build`, kolom kanan kartu (dekat `RolePill`/chip "Nonaktif"), tambahkan — HANYA untuk karyawan yang `canHandleCustomer` true:

```dart
if (!u.isOwner && u.canHandleCustomer) ...[
  const SizedBox(height: 4),
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.bgGreen,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AppColors.successText.withValues(alpha: 0.16)),
    ),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.headset_mic_outlined, size: 12, color: AppColors.successText),
      SizedBox(width: 4),
      Text('Balas chat',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: AppColors.successText, letterSpacing: 0.3)),
    ]),
  ),
],
```

- [ ] **Step 2: Baris toggle owner-only di `_showUserMenu`**

Di `_showUserMenu(UserProfile u)`, **paling atas** daftar aksi (sebelum "Edit karyawan"), sisipkan — hanya bila current user owner & target karyawan:

```dart
if (context.read<AuthProvider>().userProfile?.isOwner == true && !u.isOwner)
  SwitchListTile(
    secondary: Icon(Icons.headset_mic_outlined,
        color: u.canHandleCustomer ? AppColors.primary : AppColors.textMeta),
    title: const Text('Balas chat customer'),
    subtitle: const Text('Boleh buka Customer Inbox & balas chat dari Natalo app'),
    activeColor: AppColors.primary,
    value: u.canHandleCustomer,
    onChanged: (v) {
      Navigator.pop(ctx);
      _toggleCanHandleCustomer(u, v);
    },
  ),
```

> Catatan konteks: `_showUserMenu` sudah punya `ctx` dari `builder`. Ambil owner-check via `context.read<AuthProvider>()` (context State, bukan `ctx`) — pastikan `import '../providers/auth_provider.dart'` sudah ada (ya, sudah dipakai di file ini).

- [ ] **Step 3: Handler `_toggleCanHandleCustomer` (optimistic + snackbar)**

Tambahkan method (pola meniru `_toggleActive`, tapi tanpa dialog konfirmasi):

```dart
Future<void> _toggleCanHandleCustomer(UserProfile u, bool value) async {
  try {
    await db.collection('users').doc(u.uid).update({'canHandleCustomer': value});
    if (!mounted) return;
    showSnack(value
        ? '${u.nama} sekarang bisa balas chat customer'
        : '${u.nama} berhenti balas chat customer');
    _loadUsers();
  } catch (e) {
    if (mounted) showSnack('Gagal mengubah akses chat');
  }
}
```

- [ ] **Step 4: Verifikasi kompilasi & analisa statis**

Run (dari root NLCHAT): `flutter analyze lib/screens/manage_users_screen.dart lib/models/user_model.dart`
Expected: `No issues found` (atau hanya lint pra-existing yang tak terkait).

- [ ] **Step 5: Verifikasi UI manual (checklist)**

Jalankan app sebagai **owner** → Kelola Karyawan:
- [ ] Buka ⋮ pada karyawan → baris "Balas chat customer" muncul di atas, switch mencerminkan state.
- [ ] Toggle ON → snackbar muncul, chip hijau "Balas chat" tampil di kartu setelah reload.
- [ ] Toggle OFF → chip hilang.
- [ ] Buka ⋮ pada **owner lain** (jika ada) → baris toggle TIDAK muncul.
- [ ] Login sebagai **karyawan** (jika bisa akses layar) → baris toggle TIDAK muncul; (dan jika dipaksa, rules menolak — di luar cakupan UI).

- [ ] **Step 6: Commit**

```bash
git -C C:/Users/USER/Desktop/NLCHAT add lib/screens/manage_users_screen.dart
git -C C:/Users/USER/Desktop/NLCHAT commit -m "feat(chat): toggle canHandleCustomer owner-only + chip 'Balas chat' di Kelola Karyawan"
```

---

## Definition of Done

- [ ] `flutter test test/user_model_test.dart` hijau (3 test baru).
- [ ] `flutter analyze` bersih untuk 2 file yang diubah.
- [ ] Owner bisa toggle `canHandleCustomer` per karyawan dari ⋮; chip hijau "Balas chat" muncul untuk yang aktif.
- [ ] Baris toggle tak muncul untuk non-owner atau target owner.
- [ ] `role`/`active`/`ikutAbsensi` & alur payroll/absensi tak tersentuh; write terbatas ke `canHandleCustomer`.

## Self-Review (penulis plan)

- **Grounding kode nyata:** `UserProfile` (field `ikutAbsensi`/`active` sebagai preseden flag), `_showUserMenu`/`_toggleActive`/`_loadUsers` di `manage_users_screen.dart`, `RolePill` styling, `AuthProvider.userProfile.isOwner`, token `AppColors.bgGreen/successText` — semua terverifikasi ada. ✓
- **Keamanan:** UI owner-gated hanya kosmetik; enforcement nyata = rules Plan 1 Task 4 (immutable-by-self). Tak ada role baru → payroll/absensi aman (`nlcatter-role-filter-gotcha`). ✓
- **Konsistensi desain:** chip tint lembut hijau, beda dari pil sky Karyawan (`design-subtle-badges`). ✓
- **Batas uji:** parsing model teruji unit; interaksi Firestore diverifikasi manual (widget test butuh mock Firebase — di luar cakupan, konsisten gaya repo). Golden flaky pra-existing tak dijalankan.
- **Ketergantungan:** butuh Plan 1 (rules `canHandleCustomer`) sudah di-deploy agar toggle benar-benar menegakkan akses; UI bisa dibuat lebih dulu tapi efek keamanannya baru aktif setelah rules live.
