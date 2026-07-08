# Cart Sync Reliability (Bagian B) — Design

## Problem

Ini adalah "Bagian B" yang tercatat sebagai Out-of-Scope di
`docs/superpowers/specs/2026-07-05-abandoned-cart-cron-guardrail-design.md`:
perbaikan akar penyebab, bukan gejala. Guardrail cron (Bagian A) hanya
menyaring notifikasi salah sasaran; ia tidak memperbaiki mengapa cart
server bisa menyimpang dari cart yang user lihat di app.

Dua bug asli di `flutter_app/lib/state/cart_store.dart`:

- **B1 — Sync keluar (Flutter → server) rapuh.** `_scheduleRemoteSync()`
  men-debounce mutation cart 800ms lalu memanggil `syncToServer()` sekali,
  fire-and-forget. Kalau gagal (offline, app ditutup/di-background sebelum
  debounce selesai, 500 dari server), kegagalan itu diam-diam dan **tidak
  ada retry**. Row cart "hantu" tertinggal di server (item yang sudah user
  hapus di app tapi penghapusannya tak pernah sampai ke server). Ini
  penyebab langsung insiden "Woo Nature's Touch Pet Wet Wipes" — notifikasi
  abandoned-cart untuk produk yang tak lagi ada di cart user.
- **B2 — `loadFromServer()` mati total.** Menurut doc comment-nya, fungsi
  ini "dipanggil saat user login" untuk menyatukan cart dari device lain.
  Faktanya **tidak pernah dipanggil di mana pun**. Continuity multi-device
  yang dijanjikan tidak pernah jalan.

## Scope

Spec ini mencakup B1 **dan** B2. Tidak mengubah arsitektur `PUT /api/cart`
(tetap replace-total) maupun backend cron. Semua perubahan di sisi Flutter:
`cart_store.dart`, `cart_service.dart` (agar dapat di-mock untuk test), dan
satu pemanggilan di `member_store.dart`.

## Design

### B1 — Dirty-flag persisten + retry backoff + hook lifecycle

**State baru di `CartStore`:**

- `bool _pendingSync` — menandai "ada perubahan lokal yang belum
  dikonfirmasi sampai ke server". In-memory, tapi juga dipersist ke disk.
- `Timer? _retryTimer` — terpisah dari `_remoteSyncTimer` (debounce yang
  sudah ada). Menjadwalkan percobaan ulang sync.
- `int _retryAttempt` — untuk hitung backoff.

**Persistensi flag:** format penyimpanan cart yang sudah ada
(`prefs.setString('cart_items_v2', jsonEncode(list))`) TIDAK diubah — biar
tidak ada masalah baca data lama. Flag disimpan di key terpisah
`cart_pending_sync_v1` (bool). `loadFromDisk()` membaca key itu; kalau
`true`, berarti sesi sebelumnya mati sebelum sync terkonfirmasi → jadwalkan
sync segera (ini yang menutup kasus "app di-kill dalam 800ms sebelum
debounce sempat kirim").

**Alur mutation → sync:**

- Tiap mutation (`addItem`, `updateQuantity`, `remove`, `restore`,
  `clear`) memanggil helper baru `_markDirtyAndSync()` menggantikan
  `_scheduleRemoteSync()`. Helper: set `_pendingSync = true`, persist flag,
  lalu debounce 800ms (perilaku existing) sebelum memanggil `syncToServer()`.
- `syncToServer()` diubah:
  - Sukses → `_pendingSync = false`, persist flag `false`, batalkan
    `_retryTimer`, reset `_retryAttempt = 0`.
  - Gagal (network / 5xx) → JANGAN reset flag; jadwalkan retry via backoff.
  - Gagal karena `ReadOnlyModeException` → JANGAN reset flag, tapi JUGA
    jangan jadwalkan retry (read-only bukan kegagalan sementara; menunggu
    pemicu lifecycle/mutation berikutnya saja). Ditangani sebagai catch
    terpisah dari network error.
  - Guard `!memberStore.isLoggedIn` → skip (tidak retry; flag tetap
    tersimpan untuk disinkron setelah login).

**Backoff:** urutan 5s → 10s → 20s → 40s → 60s, di-cap 60s, reset ke 5s
setelah sukses. Formula: `delayDetik = min(60, 5 * pow(2, _retryAttempt))`,
`_retryAttempt` naik tiap kegagalan.

### B1 — Pemicu retry tambahan (lifecycle)

`CartStore` adalah singleton global (`final cartStore = CartStore._()`),
bukan widget, jadi ia meng-`implements WidgetsBindingObserver` dan
mendaftarkan dirinya sendiri:

- Tambah method `init()` yang memanggil
  `WidgetsBinding.instance.addObserver(this)`. Dipanggil sekali di
  `main.dart`, di dekat pemanggilan `cartStore.loadFromDisk()` yang sudah
  ada.
- `dispose()` (sudah ada) memanggil `WidgetsBinding.instance.removeObserver(this)`.
- `didChangeAppLifecycleState(state)`: pada `AppLifecycleState.resumed`,
  kalau `_pendingSync == true` → panggil `syncToServer()`. Pola ini identik
  dengan `chat_room_screen.dart` dan `app_notification_button.dart`.

Kombinasi: cold-start dirty (via `loadFromDisk`), resume dirty (via
observer), dan retry berjalan (via `_retryTimer`) menutup ketiga celah.

### B2 — `loadFromServer()` menjadi merge-on-login (union + jumlah qty)

`loadFromServer()` sekarang melakukan `_items.clear()` lalu isi dari server
(server-menang) — diganti menjadi **merge union** agar barang yang
ditambahkan sebagai guest tidak hilang saat login.

**`_mergeServerCart(remoteItems)`:**

- Untuk tiap item server, cari padanan lokal berdasar `item.key`
  (`productId:variantId`, key yang sudah dipakai `_items`).
- Ada di **kedua sisi**: qty final = `qtyLokal + qtyServer`, di-clamp ke
  stok bila stok diketahui (`effectiveStock > 0`) memakai logika clamp yang
  sudah ada; kalau `effectiveStock <= 0` (stok belum diketahui) jangan
  clamp — konsisten dengan aturan `addItem`. Metadata (harga/nama/gambar)
  ambil dari **server** (lebih fresh; server sudah re-price via
  `applyCurrentCartPricing`).
- Hanya di **server**: masuk apa adanya.
- Hanya di **lokal** (barang guest): dipertahankan.

**Kapan dipanggil:** satu pemanggilan `cartStore.loadFromServer()` di
`MemberStore.setSession()`, setelah sesi tersimpan. Tidak bergantung pada
`hydrateFromApi()` (boleh setelah atau paralel).

**Push balik setelah merge:** hasil union berbeda dari cart server (qty
bertambah), jadi tepat setelah merge sukses, tandai `_pendingSync = true`
dan panggil `syncToServer()` agar server ikut ter-update. Ini otomatis
lewat mesin B1.

**Guard idempotensi:** karena merge menjumlahkan qty, `loadFromServer()`
hanya boleh melakukan merge **sekali per transisi login**. Ini kritis
karena `setSession()` TIDAK hanya dipanggil saat login — ia juga dipanggil
pada update profil (mis. ganti foto lewat bottom sheet; lihat komentar di
`member_store.dart` sekitar baris 135). Tanpa guard, tiap update profil
akan men-trigger merge lagi dan menggandakan qty. Dijaga flag
`_mergedThisSession` yang di-set `true` setelah merge sukses dan di-reset
`false` HANYA di `MemberStore.logout()` (bukan di `setSession`).

## Edge Cases

- **Guest murni:** `_markDirtyAndSync()` set flag, `syncToServer()` guard
  `!isLoggedIn` → skip; flag tetap tersimpan. Login → merge → push. Cart
  guest tidak hilang.
- **Read-only mode:** `replaceCart()` throw `ReadOnlyModeException` →
  catch terpisah; flag tetap `true`, TIDAK ada retry terjadwal.
- **Logout dengan flag dirty:** `logout()` reset `_mergedThisSession = false`.
  `_pendingSync` dibiarkan; login berikutnya menyelaraskan. Cart lokal
  tidak di-clear saat logout (perilaku existing dipertahankan).
- **Merge saat stok tak diketahui** (`effectiveStock <= 0`): qty
  dijumlahkan tanpa clamp.

## Error Handling

Semua tetap `try/catch` diam-diam seperti sekarang; yang menentukan retry
hanyalah `_pendingSync`. Tidak ada exception yang bocor ke UI. Filosofi
"gagal silent, local-first" dipertahankan penuh (keputusan user: retry
berjalan tak terlihat, tanpa indikator UI baru).

## Testing Plan

File Flutter/Dart — pakai `flutter test`. `cartService` yang saat ini
singleton global di-import langsung dibuat dapat di-override untuk test
(field opsional injektable, refactor minimal). Kasus uji `CartStore`:

1. Mutation → `_pendingSync` = `true`; sync sukses → `false`.
2. Sync gagal (mock throw) → flag tetap `true`, retry terjadwal; sukses di
   percobaan ke-2 → flag `false`.
3. `loadFromDisk()` dengan flag `true` tersimpan → memicu sync.
4. `ReadOnlyModeException` → flag tetap `true`, TIDAK ada retry terjadwal.
5. Merge union: lokal `{A:2}` + server `{A:3, B:1}` → `{A:5, B:1}`, clamp
   ke stok bila ada.
6. Merge idempoten: `loadFromServer()` 2x dalam satu sesi →
   `_mergedThisSession` mencegah qty dobel.

Catatan (dari memori proyek): `flutter test` di Windows punya 2 golden
failure pre-existing yang TIDAK terkait (natalo_colors, status_pill) dan
widget test yang me-render gambar bisa hang — test di spec ini murni logika
`CartStore` tanpa render widget, jadi tidak terkena masalah itu.

## Out of Scope

- Arsitektur `PUT /api/cart` tetap replace-total (tidak pindah ke
  diff/incremental sync).
- Tidak ada indikator UI "belum tersinkron" (keputusan user: retry diam-diam).
- Backend cron tidak disentuh (sudah ditangani Bagian A).
