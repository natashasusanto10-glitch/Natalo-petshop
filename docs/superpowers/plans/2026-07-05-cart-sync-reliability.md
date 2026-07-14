# Cart Sync Reliability (Bagian B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Membuat sync cart Flutter→server andal (retry persisten, tidak lagi fire-and-forget) dan menghidupkan `loadFromServer()` sebagai merge union saat login, sehingga cart server tidak lagi menyimpan row "hantu" dan barang guest tidak hilang saat login.

**Architecture:** Semua perubahan di sisi Flutter. `CartStore` (`flutter_app/lib/state/cart_store.dart`) dapat dependency injectable (constructor test-only `CartStore.forTest`) untuk `CartService` dan seam `isLoggedIn`, sehingga logika sync + merge dapat diuji tanpa jaringan. Sebuah flag `_pendingSync` yang dipersist ke SharedPreferences (key terpisah, tidak mengubah format cart yang sudah ada) menandai perubahan lokal yang belum terkonfirmasi sampai ke server; gagal sync menjadwalkan retry backoff, dan tiga pemicu (cold-start via `loadFromDisk`, resume via `WidgetsBindingObserver`, timer retry) memastikan sync akhirnya berhasil. `loadFromServer()` diubah dari clear+replace menjadi merge union (jumlah qty, clamp stok, metadata server) dengan guard idempotensi, dipanggil dari `MemberStore.setSession()`.

**Tech Stack:** Flutter/Dart, `ChangeNotifier`, `SharedPreferences`, `Timer` (dart:async), `WidgetsBindingObserver`, test dengan `flutter_test` (`node:test`-style tidak berlaku — ini Dart).

## Global Constraints

- JANGAN ubah arsitektur `PUT /api/cart` (tetap replace-total) atau backend apa pun — semua perubahan di Flutter.
- Format penyimpanan cart di SharedPreferences (`prefs.setString('cart_items_v2', ...)`) TIDAK berubah. Flag baru disimpan di key TERPISAH `cart_pending_sync_v1`.
- TIDAK ada indikator UI baru — retry berjalan diam-diam; tidak ada exception yang bocor ke UI (semua `try/catch` silent seperti sekarang).
- Merge saat login = UNION + jumlah qty. Item yang sama (`CartItem.key`): qty = qtyLokal + qtyServer, di-clamp ke `effectiveStock` bila `effectiveStock > 0` (kalau `<= 0`, jangan clamp). Metadata (harga/nama/gambar) ambil dari item SERVER.
- Guard idempotensi `_mergedThisSession` di-reset ke `false` HANYA di `MemberStore.logout()`, bukan di `setSession()` (karena `setSession` juga dipanggil saat update profil).
- `ReadOnlyModeException` diperlakukan sebagai "jangan retry" (bukan kegagalan sementara): flag tetap `true`, tapi TIDAK menjadwalkan retry timer.
- `CartService` (`cart_service.dart`) TIDAK diubah — mock di test dibuat via subclass (`extends CartService`, override `fetchCart`/`replaceCart`).
- Spec: `docs/superpowers/specs/2026-07-05-cart-sync-reliability-design.md`.

---

## Task 1: B1 sync engine — dirty-flag persisten + retry backoff + seam injeksi

**Files:**
- Modify: `flutter_app/lib/state/cart_store.dart`
- Test: `flutter_app/test/cart_store_test.dart` (create)

**Interfaces:**
- Consumes: `CartService.replaceCart(List<CartItem>)` (sudah ada), `CartItem` (sudah ada), `ReadOnlyModeException` dari `../utils/read_only_mode.dart` (sudah ada), `memberStore.isLoggedIn` (sudah ada).
- Produces (dipakai Task 2 & 3):
  - `CartStore.forTest({CartService? service, bool Function()? isLoggedIn})` — factory test-only.
  - `Future<void> syncToServer()` — sekarang mengelola `_pendingSync` + retry.
  - `void _markDirtyAndSync()` — dipakai semua mutation (menggantikan `_scheduleRemoteSync()`).
  - Getter `@visibleForTesting`: `bool get pendingSync`, `bool get hasPendingRetry`.
  - Konstanta `static const _pendingKey = 'cart_pending_sync_v1'`.

- [ ] **Step 1: Tulis test yang gagal**

Buat `flutter_app/test/cart_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/cart_item.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/services/cart_service.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';
import 'package:natalo_petshop_flutter/utils/read_only_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake CartService via subclass — override HANYA fetchCart/replaceCart.
/// validate/validatePrivateVoucher diwarisi (tak dipakai CartStore).
class _FakeCartService extends CartService {
  _FakeCartService();

  List<CartItem> remote = [];
  int replaceCallCount = 0;
  Object? throwOnReplace;
  bool throwOnce = false;

  @override
  Future<List<CartItem>> fetchCart() async => remote;

  @override
  Future<void> replaceCart(List<CartItem> items) async {
    replaceCallCount++;
    final err = throwOnReplace;
    if (err != null) {
      if (throwOnce) throwOnReplace = null;
      throw err;
    }
  }
}

Product _product(String id, {int stock = 10}) => Product(
      id: id,
      slug: id,
      title: 'Produk $id',
      category: 'Produk',
      brand: 'Natalo',
      imageUrl: '',
      price: 10000,
      rating: 0,
      reviewCount: 0,
      stock: stock,
      description: '',
    );

CartItem _item(String id, {int quantity = 1, int stock = 10}) => CartItem(
      product: _product(id, stock: stock),
      quantity: quantity,
      unitPrice: 10000,
      effectiveStock: stock,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('mutation menandai pendingSync true; sync sukses menjadikannya false', () async {
    final fake = _FakeCartService();
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.addItem(_item('A', quantity: 2));
    expect(store.pendingSync, true);

    await store.syncToServer();
    expect(fake.replaceCallCount, 1);
    expect(store.pendingSync, false);
  });

  test('sync gagal: flag tetap true + retry terjadwal; sukses di percobaan ke-2 membersihkan flag', () async {
    final fake = _FakeCartService()
      ..throwOnReplace = Exception('network down')
      ..throwOnce = true;
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.addItem(_item('A', quantity: 1));

    await store.syncToServer(); // gagal sekali
    expect(store.pendingSync, true);
    expect(store.hasPendingRetry, true);
    expect(fake.replaceCallCount, 1);

    await store.syncToServer(); // simulasi retry firing — sukses
    expect(store.pendingSync, false);
    expect(store.hasPendingRetry, false);
    expect(fake.replaceCallCount, 2);
  });

  test('ReadOnlyModeException: flag tetap true, TIDAK ada retry terjadwal', () async {
    final fake = _FakeCartService()
      ..throwOnReplace = const ReadOnlyModeException('cart_sync');
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.addItem(_item('A', quantity: 1));
    await store.syncToServer();

    expect(store.pendingSync, true);
    expect(store.hasPendingRetry, false);
    expect(fake.replaceCallCount, 1);
  });
}
```

- [ ] **Step 2: Jalankan test untuk memastikan gagal**

Run: `cd flutter_app && flutter test test/cart_store_test.dart`
Expected: FAIL kompilasi — `CartStore.forTest` / `store.pendingSync` / `store.hasPendingRetry` belum ada.

- [ ] **Step 3: Implementasi di `cart_store.dart`**

3a. Ganti baris import `import 'package:flutter/foundation.dart';` (baris 4) menjadi:

```dart
import 'package:flutter/widgets.dart';
```

(widgets.dart re-export foundation — memberi `ChangeNotifier`, `kDebugMode`, `debugPrint`, `visibleForTesting`, PLUS `WidgetsBindingObserver`/`AppLifecycleState`/`WidgetsBinding` yang dipakai Task 2.)

3b. Tambah dua import baru setelah baris import cart_service:

```dart
import 'dart:math' as math;
import '../utils/read_only_mode.dart';
```

3c. Ganti deklarasi class + constructor (baris 51-52, `class CartStore extends ChangeNotifier {` dan `CartStore._();`) menjadi:

```dart
class CartStore extends ChangeNotifier {
  CartStore._({CartService? service, bool Function()? isLoggedIn})
      : _service = service ?? cartService,
        _isLoggedIn = isLoggedIn ?? _defaultIsLoggedIn;

  /// Constructor test-only — inject fake CartService + seam isLoggedIn
  /// supaya logika sync/merge dapat diuji tanpa jaringan / global state.
  @visibleForTesting
  factory CartStore.forTest({
    CartService? service,
    bool Function()? isLoggedIn,
  }) =>
      CartStore._(service: service, isLoggedIn: isLoggedIn);

  static bool _defaultIsLoggedIn() => memberStore.isLoggedIn;

  final CartService _service;
  final bool Function() _isLoggedIn;
```

3d. Tambah field baru tepat setelah `static const Duration _remoteSyncDebounce = ...` (baris 55):

```dart
  static const _pendingKey = 'cart_pending_sync_v1';
```

dan tepat setelah `Timer? _remoteSyncTimer;` (baris 59):

```dart
  Timer? _retryTimer;
  int _retryAttempt = 0;

  /// Ada perubahan lokal yang belum dikonfirmasi sampai ke server.
  bool _pendingSync = false;

  @visibleForTesting
  bool get pendingSync => _pendingSync;

  @visibleForTesting
  bool get hasPendingRetry => _retryTimer?.isActive ?? false;
```

3e. Di setiap mutation, ganti pemanggilan `_scheduleRemoteSync();` menjadi `_markDirtyAndSync();`. Ada 6 lokasi: `addItem` (baris 192), `updateQuantity` (baris 204 dan 213), `remove` (baris 221), `restore` (baris 243), `clear` (baris 251). Gunakan replace-all pada string `_scheduleRemoteSync();` di dalam method-method itu.

3f. Ganti seluruh method `syncToServer()` (baris 262-280) menjadi:

```dart
  Future<void> syncToServer() async {
    if (!_isLoggedIn()) {
      if (kDebugMode) {
        debugPrint('[CartStore.syncToServer] skip — not logged in');
      }
      return;
    }
    try {
      await _service.replaceCart(_items.values.toList(growable: false));
      _pendingSync = false;
      _retryAttempt = 0;
      _retryTimer?.cancel();
      await _persistPendingFlag();
      if (kDebugMode) {
        debugPrint('[CartStore.syncToServer] OK — ${_items.length} items');
      }
    } on ReadOnlyModeException catch (e) {
      // Read-only bukan kegagalan sementara — jangan retry loop. Flag tetap
      // true supaya pemicu lifecycle/mutation berikutnya coba lagi.
      if (kDebugMode) {
        debugPrint('[CartStore.syncToServer] read-only, skip retry: $e');
      }
    } catch (e) {
      // Network / 5xx — flag tetap true, jadwalkan retry backoff.
      if (kDebugMode) {
        debugPrint('[CartStore.syncToServer] failed, will retry: $e');
      }
      _scheduleRetry();
    }
  }

  Future<void> _persistPendingFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pendingKey, _pendingSync);
    } catch (_) {}
  }

  /// Set flag dirty + persist, lalu debounce sync (menggantikan panggilan
  /// langsung ke [_scheduleRemoteSync] dari mutation).
  void _markDirtyAndSync() {
    _pendingSync = true;
    _persistPendingFlag();
    _scheduleRemoteSync();
  }

  /// Retry backoff: 5s → 10s → 20s → 40s → 60s (cap 60s), reset saat sukses.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delaySeconds = math.min(60, 5 * math.pow(2, _retryAttempt)).toInt();
    _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: delaySeconds), syncToServer);
  }
```

3g. Ganti method `dispose()` (baris 290-294) menjadi:

```dart
  @override
  void dispose() {
    _remoteSyncTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
```

- [ ] **Step 4: Jalankan test — harus lulus**

Run: `cd flutter_app && flutter test test/cart_store_test.dart`
Expected: 3 test lulus (`+3`).

- [ ] **Step 5: Analisis statis**

Run: `cd flutter_app && flutter analyze lib/state/cart_store.dart test/cart_store_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd flutter_app
git add lib/state/cart_store.dart test/cart_store_test.dart
git commit -m "$(cat <<'EOF'
feat(cart): dirty-flag persisten + retry backoff untuk sync keluar

Sync cart Flutter→server tidak lagi fire-and-forget: flag _pendingSync
dipersist di key terpisah, gagal network menjadwalkan retry backoff,
ReadOnlyModeException tidak memicu retry. Tambah seam injeksi
(CartStore.forTest) supaya dapat diuji tanpa jaringan.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: B1 pemicu cold-start + lifecycle (loadFromDisk + WidgetsBindingObserver)

**Files:**
- Modify: `flutter_app/lib/state/cart_store.dart`
- Modify: `flutter_app/lib/main.dart:150`
- Test: `flutter_app/test/cart_store_test.dart` (tambah test)

**Interfaces:**
- Consumes: `_pendingSync`, `syncToServer()`, `_pendingKey`, `_persistPendingFlag()` (Task 1).
- Produces: `void init()` — dipanggil sekali di `main.dart`; `didChangeAppLifecycleState` override.

- [ ] **Step 1: Tulis test yang gagal (tambahkan ke `test/cart_store_test.dart`)**

Tambahkan dua test ini di dalam `main()`, setelah test terakhir Task 1:

```dart
  test('loadFromDisk dengan flag pending tersimpan → memicu sync', () async {
    // Seed: store pertama menambah item (persist item + flag true), lalu
    // dispose sebelum debounce sync sempat jalan — meniru app di-kill.
    final seeder = CartStore.forTest(
      service: _FakeCartService(),
      isLoggedIn: () => true,
    );
    await seeder.addItem(_item('A', quantity: 1));
    expect(seeder.pendingSync, true);
    seeder.dispose();

    // Store kedua load dari disk yang sama (mock prefs persist in-memory).
    final fake = _FakeCartService();
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.loadFromDisk();
    expect(store.pendingSync, true); // flag ter-restore dari disk
    await pumpEventQueue();
    expect(fake.replaceCallCount, 1); // sync ter-trigger otomatis
    expect(store.pendingSync, false);
  });

  test('resume dari background dengan flag pending → sync', () async {
    final fake = _FakeCartService();
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.addItem(_item('A', quantity: 1));
    expect(store.pendingSync, true);

    store.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(fake.replaceCallCount, greaterThanOrEqualTo(1));
    expect(store.pendingSync, false);
  });
```

Tambahkan import berikut di atas file test (setelah import yang sudah ada) supaya `AppLifecycleState` dikenal:

```dart
import 'package:flutter/widgets.dart';
```

- [ ] **Step 2: Jalankan test — harus gagal**

Run: `cd flutter_app && flutter test test/cart_store_test.dart`
Expected: FAIL — `didChangeAppLifecycleState` belum di-override / `init` belum ada; loadFromDisk belum membaca flag.

- [ ] **Step 3: Implementasi di `cart_store.dart`**

3a. Tambahkan mixin `WidgetsBindingObserver` ke deklarasi class (hasil Task 1 step 3c):

```dart
class CartStore extends ChangeNotifier with WidgetsBindingObserver {
```

3b. Tambah field observer-registered tepat setelah field `int _retryAttempt = 0;` (dari Task 1):

```dart
  bool _observerRegistered = false;
```

3c. Ganti seluruh method `loadFromDisk()` (baris 74-89) menjadi:

```dart
  Future<void> loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getBool(_pendingKey) ?? false;
      final raw = prefs.getString(_key);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _items.clear();
        for (final json in list) {
          final item = CartItem.fromJson(json);
          _items[item.key] = item;
        }
        notifyListeners();
      }
      if (pending) {
        // Sesi sebelumnya mati sebelum sync terkonfirmasi. syncToServer
        // self-guard kalau belum login (flag tetap tersimpan untuk nanti).
        _pendingSync = true;
        unawaited(syncToServer());
      }
    } catch (_) {
      // Disk corrupt / format lama — silent reset.
    }
  }
```

3d. Tambahkan method `init()` dan override `didChangeAppLifecycleState` tepat sebelum method `dispose()`:

```dart
  /// Daftarkan observer lifecycle — dipanggil sekali di main(). CartStore
  /// singleton global (bukan widget), jadi ia mengurus observer-nya sendiri.
  void init() {
    if (_observerRegistered) return;
    WidgetsBinding.instance.addObserver(this);
    _observerRegistered = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingSync) {
      unawaited(syncToServer());
    }
  }
```

3e. Tambahkan `removeObserver` ke `dispose()` (hasil Task 1 step 3g) menjadi:

```dart
  @override
  void dispose() {
    _remoteSyncTimer?.cancel();
    _retryTimer?.cancel();
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }
    super.dispose();
  }
```

- [ ] **Step 4: Wire `init()` di main.dart**

Di `flutter_app/lib/main.dart`, tepat setelah baris 150 (`cartStore.loadFromDisk();`), tambahkan:

```dart
  // Daftarkan observer lifecycle cart supaya sync tertunda dicoba ulang
  // saat app kembali ke foreground.
  cartStore.init();
```

- [ ] **Step 5: Jalankan test — harus lulus**

Run: `cd flutter_app && flutter test test/cart_store_test.dart`
Expected: 5 test lulus (`+5`).

- [ ] **Step 6: Analisis statis**

Run: `cd flutter_app && flutter analyze lib/state/cart_store.dart lib/main.dart test/cart_store_test.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
cd flutter_app
git add lib/state/cart_store.dart lib/main.dart test/cart_store_test.dart
git commit -m "$(cat <<'EOF'
feat(cart): pemicu retry cold-start + resume lifecycle

loadFromDisk membaca flag pending tersimpan lalu memicu sync (menutup
kasus app di-kill sebelum debounce sempat kirim). CartStore mendaftarkan
dirinya sebagai WidgetsBindingObserver dan menyinkron ulang saat app
resume kalau masih ada perubahan tertunda.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: B2 merge-on-login (union + jumlah qty) + wiring member_store

**Files:**
- Modify: `flutter_app/lib/state/cart_store.dart`
- Modify: `flutter_app/lib/state/member_store.dart` (`setSession` ~baris 166, `logout` ~baris 169-180)
- Test: `flutter_app/test/cart_store_test.dart` (tambah test)

**Interfaces:**
- Consumes: `_service.fetchCart()`, `_isLoggedIn()`, `_markDirtyAndSync()`, `_persist()`, `_items`, `CartItem.key`, `CartItem.copyWith`, `CartItem.effectiveStock` (Task 1 + yang sudah ada).
- Produces: `Future<void> loadFromServer()` (merge, bukan clear+replace), `void resetLoginMergeGuard()` — dipanggil dari `MemberStore.logout()`.

- [ ] **Step 1: Tulis test yang gagal (tambahkan ke `test/cart_store_test.dart`)**

Tambahkan dua test ini di dalam `main()`:

```dart
  test('loadFromServer merge union: qty dijumlahkan, item server-only masuk', () async {
    final fake = _FakeCartService()
      ..remote = [
        _item('A', quantity: 3, stock: 10),
        _item('B', quantity: 1, stock: 10),
      ];
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.addItem(_item('A', quantity: 2, stock: 10)); // lokal A=2

    await store.loadFromServer();

    expect(store.quantityFor('A'), 5); // 2 lokal + 3 server
    expect(store.quantityFor('B'), 1); // server-only ikut masuk
  });

  test('loadFromServer idempoten dalam satu sesi: panggil 2x tidak menggandakan', () async {
    final fake = _FakeCartService()
      ..remote = [_item('A', quantity: 3, stock: 10)];
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.addItem(_item('A', quantity: 2, stock: 10));

    await store.loadFromServer();
    await store.loadFromServer(); // panggilan ke-2 harus di-skip

    expect(store.quantityFor('A'), 5); // bukan 8
    expect(store.mergedThisSession, true);
  });
```

Tambahkan getter test di daftar import/asumsi — getter `mergedThisSession` dibuat di Step 3.

- [ ] **Step 2: Jalankan test — harus gagal**

Run: `cd flutter_app && flutter test test/cart_store_test.dart`
Expected: FAIL — `store.mergedThisSession` belum ada; `loadFromServer` masih clear+replace (assertion qty gagal).

- [ ] **Step 3: Implementasi merge di `cart_store.dart`**

3a. Tambah field guard tepat setelah field `bool _observerRegistered = false;` (Task 2):

```dart
  bool _mergedThisSession = false;

  @visibleForTesting
  bool get mergedThisSession => _mergedThisSession;
```

3b. Ganti seluruh method `loadFromServer()` (baris 95-115) menjadi:

```dart
  /// Merge cart server ke local state saat login (union + jumlah qty).
  /// Barang yang ditambahkan sebagai guest TIDAK hilang; item server dari
  /// device lain ikut masuk. Hanya merge SEKALI per sesi login (guard
  /// [_mergedThisSession]) karena setSession juga dipanggil saat update
  /// profil. Hasil union di-push balik ke server supaya konsisten.
  Future<void> loadFromServer() async {
    if (!_isLoggedIn()) return;
    if (_mergedThisSession) return;
    try {
      final remoteItems = await _service.fetchCart();
      _mergeServerCart(remoteItems);
      _mergedThisSession = true;
      notifyListeners();
      await _persist();
      _markDirtyAndSync();
      if (kDebugMode) {
        debugPrint(
            '[CartStore.loadFromServer] merged ${remoteItems.length} server items');
      }
    } catch (e) {
      // Server unreachable / auth fail → tetap pakai local state.
      if (kDebugMode) {
        debugPrint('[CartStore.loadFromServer] failed: $e');
      }
    }
  }

  void _mergeServerCart(List<CartItem> remoteItems) {
    for (final remote in remoteItems) {
      final existing = _items[remote.key];
      if (existing == null) {
        _items[remote.key] = remote;
      } else {
        final combined = existing.quantity + remote.quantity;
        final stock = remote.effectiveStock;
        final qty = stock > 0 ? combined.clamp(1, stock) : combined;
        // Metadata dari server (lebih fresh), qty gabungan.
        _items[remote.key] = remote.copyWith(quantity: qty);
      }
    }
  }

  /// Reset guard merge — dipanggil dari MemberStore.logout() supaya login
  /// berikutnya (bisa akun berbeda) melakukan merge lagi.
  void resetLoginMergeGuard() {
    _mergedThisSession = false;
  }
```

- [ ] **Step 4: Jalankan test — harus lulus**

Run: `cd flutter_app && flutter test test/cart_store_test.dart`
Expected: 7 test lulus (`+7`).

- [ ] **Step 5: Wire pemanggilan di `member_store.dart`**

5a. Tambah import cart_store di bagian atas `flutter_app/lib/state/member_store.dart` (setelah import yang sudah ada — cek daftar import di baris awal file, sisipkan sesuai urutan):

```dart
import 'cart_store.dart';
```

5b. Di method `setSession(...)`, tepat setelah baris `hydrateFromApi();` (baris 166), tambahkan:

```dart
    // Merge cart server (device lain) ke local + push balik hasil union.
    // Guard idempotensi di dalam loadFromServer (aman dipanggil tiap
    // setSession, termasuk update profil).
    cartStore.loadFromServer();
```

5c. Di method `logout()`, tepat setelah baris `_orders = const [];` (baris 173, sebelum `notifyListeners();`), tambahkan:

```dart
    cartStore.resetLoginMergeGuard();
```

- [ ] **Step 6: Analisis statis + seluruh suite cart**

Run: `cd flutter_app && flutter analyze lib/state/cart_store.dart lib/state/member_store.dart test/cart_store_test.dart`
Expected: `No issues found!`

Run: `cd flutter_app && flutter test test/cart_store_test.dart`
Expected: 7 test lulus (`+7`).

- [ ] **Step 7: Commit**

```bash
cd flutter_app
git add lib/state/cart_store.dart lib/state/member_store.dart test/cart_store_test.dart
git commit -m "$(cat <<'EOF'
feat(cart): loadFromServer jadi merge union + dipanggil saat login

loadFromServer sekarang menggabungkan cart server dengan local (jumlah
qty, clamp stok, metadata server) alih-alih menimpa — barang guest tidak
hilang saat login. Dipanggil dari MemberStore.setSession dengan guard
idempotensi (_mergedThisSession) yang di-reset saat logout. Hasil union
di-push balik ke server via mesin retry Task 1.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** B1 dirty-flag persisten + persist di key terpisah → Task 1 (3d, 3f). Retry backoff + ReadOnlyModeException tanpa retry → Task 1 (3f). Guard `!isLoggedIn` → Task 1 (3f). Pemicu cold-start (`loadFromDisk`) → Task 2 (3c). Observer di `CartStore` sendiri + `init()` di main + `didChangeAppLifecycleState` resumed → Task 2 (3a,3d,4). B2 merge union (jumlah qty, clamp `effectiveStock>0`, metadata server) → Task 3 (3b). Dipanggil di `setSession`, guard `_mergedThisSession` reset HANYA di `logout` → Task 3 (5b,5c). Push-back hasil union → Task 3 (3b, `_markDirtyAndSync`). `CartService` tidak diubah (mock via subclass) → Task 1 test. Semua enam kasus uji spec tercakup (test 1,2,4 Task 1; test 3 + resume Task 2; test 5,6 Task 3).
- **Placeholder scan:** tidak ada TBD/TODO; semua step berisi kode lengkap atau perintah dengan expected output.
- **Type consistency:** `CartStore.forTest({CartService? service, bool Function()? isLoggedIn})` dipakai identik di semua test. `_markDirtyAndSync()` (Task 1) dipakai oleh mutation (Task 1 step 3e) dan push-back merge (Task 3 3b). `_pendingKey`, `_persistPendingFlag()`, `_pendingSync` konsisten antar Task 1-2-3. `resetLoginMergeGuard()` (Task 3 3b) dipanggil dari `member_store.dart` (Task 3 5c) dengan nama sama. `_mergeServerCart(List<CartItem>)` dan `CartItem.key`/`copyWith`/`effectiveStock` sesuai model yang sudah ada. Getter `pendingSync`/`hasPendingRetry`/`mergedThisSession` semua `@visibleForTesting` dan dipakai di test dengan nama sama.
- **Catatan circular import:** `member_store.dart` meng-import `cart_store.dart` sementara `cart_store.dart` meng-import `member_store.dart`. Dart mengizinkan import siklik antar library file — tidak error. Sudah disengaja (seam `_defaultIsLoggedIn` membaca `memberStore`, dan `setSession` memanggil `cartStore`).
