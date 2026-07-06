# Bottom Sheet "Lengkapi belanjaanmu" — Add-to-Cart di Halaman Detail Produk

Tanggal: 2026-07-06
Status: Disetujui untuk implementasi (menunggu review spec)
Surface: Flutter app (`flutter_app/`) — **bukan** web Next.js.

## Ringkasan

Setelah user tap tombol **+ Keranjang** di halaman detail produk, muncul
bottom sheet ala Tokopedia ("Lengkapi belanjaanmu") berisi konfirmasi item
masuk keranjang + carousel rekomendasi produk + tombol **Cek Keranjang**.
Sheet ini menggantikan toast lama sebagai konfirmasi utama.

Semua warna/font/ukuran mengikuti tema terang standar app (`NataloColors`,
`colorScheme`). Halaman **Feed dikecualikan** (tetap style immersive-nya
sendiri, tidak tersentuh).

## Scope

**Termasuk:**
- Trigger **hanya** dari tombol utama **+ Keranjang** di halaman detail
  produk ([`product_detail_screen.dart`](../../../flutter_app/lib/screens/product_detail_screen.dart)),
  termasuk jalur setelah pemilihan varian (variant sheet → add).
- Widget sheet baru + helper pemanggil.
- Perlambat animasi fly-to-cart.
- Ganti teks judul carousel rekomendasi di dalam sheet.

**Tidak termasuk (YAGNI / out of scope):**
- Tombol keranjang di grid katalog, home carousel, product peek — tetap
  seperti sekarang (toast biasa, tanpa sheet).
- Perubahan endpoint / backend. Data rekomendasi pakai yang sudah ada.
- Perubahan halaman Feed.

## Keputusan desain (hasil brainstorming)

1. **Trigger:** halaman detail produk saja.
2. **Animasi:** fly-to-cart tetap ada, jalan **dulu**, baru sheet naik.
   Durasi animasi diperlambat (terasa terlalu cepat sekarang).
3. **Tombol di kartu rekomendasi:** pill biru "+ Keranjang" full-width
   (mirip layout screenshot, warna biru Natalo `#1E5FBF`).
4. **Toast lama:** tidak dipakai lagi untuk add dari detail (sheet jadi
   konfirmasinya). Toast tetap dipakai untuk add dari dalam sheet.
5. **Judul carousel:** "Cek keperluan anabulmu yang lain yuk".
6. **Sumber data carousel:** berbasis **isi keranjang**. Saat sheet dibuka,
   fetch ulang `fetchRecommendations(cartIds: <semua product.id di cart>,
   excludeIds: <semua product.id di cart>, limit: 10)`. Untuk menghindari
   carousel kosong sesaat, tampilkan `_related` yang sudah ter-load sebagai
   isi awal (instan), lalu ganti dengan hasil cart-based begitu tiba.
7. **Bentuk & jumlah:** carousel **horizontal** (1 baris, scroll ke samping,
   sesuai screenshot), **10 produk**.

### Catatan: keranjang tidak pernah kosong di titik ini
Sheet hanya muncul setelah `_addToCart` sukses, dan `cartStore.addProduct`
dipanggil **sebelum** sheet naik — jadi produk yang barusan ditambahkan
sudah ada di keranjang. `cartIds` minimal berisi 1 item. Pengaman: kalau
`cartIds` ternyata kosong, fallback ke `viewedIds: [product.id]`.

## Arsitektur & file

### File baru
`flutter_app/lib/widgets/added_to_cart_sheet.dart`
- Helper publik: `Future<void> showAddedToCartSheet(BuildContext context, {required Product product, List<Product> initialRelated = const []})`.
- Private widget `_AddedToCartSheet` **stateful**:
  - `initState`: state carousel diisi `initialRelated` (dari `_related` yang
    sudah ter-load → tampil instan), lalu panggil
    `fetchRecommendations(cartIds: <cart product ids>, excludeIds: <cart product ids>, limit: 10)`;
    `setState` ganti list saat hasil tiba. `cartIds` diambil dari
    `cartStore.items.map((i) => i.product.id)`. Kalau `cartIds` kosong
    (harusnya tidak terjadi), fallback ke `viewedIds: [product.id]`.
  - `_loadRelated()` di halaman detail tetap `limit: 6` (section
    "Rekomendasi Untukmu" tidak diubah); `initialRelated` = `_related`
    hanya placeholder instan sebelum hasil 10 cart-based tiba.
  - Kalau hasil fetch kosong (offline/gagal), pertahankan `initialRelated`
    sebagai fallback; kalau keduanya kosong → section carousel disembunyikan.
- Pakai `showModalBottomSheet` dengan `isScrollControlled: true`,
  `useSafeArea: true`, rounded top corners (radius 22–28 sesuai konvensi app),
  drag handle via [`SheetDragHandle`](../../../flutter_app/lib/widgets/sheet_drag_handle.dart)
  (atau handle inline sesuai `update_profile_photo_sheet.dart`).
- Tinggi: content-sized dengan `mainAxisSize: MainAxisSize.min`, dibungkus
  agar carousel + tombol muat; kalau konten tinggi, batasi ~85% tinggi layar
  dan scroll di bagian tengah. Tombol **Cek Keranjang** sticky di bawah.

### File diubah
1. `flutter_app/lib/screens/product_detail_screen.dart`
   - Di `_addToCart(...)`: hapus `AppToast.showCartAdded(...)` untuk kasus
     sukses normal; setelah animasi fly selesai, panggil
     `showAddedToCartSheet(context, product: product, initialRelated: _related)`.
   - Toast info untuk kasus stok clamp / stok habis tetap dipertahankan.
   - Pastikan sheet dipanggil setelah `flyImageToCart` menandakan selesai
     (lihat perubahan `fly_to_cart.dart`).

2. `flutter_app/lib/utils/fly_to_cart.dart`
   - Tambah mekanisme "selesai": `flyImageToCart` mengembalikan `Future`
     yang complete saat animasi **benar-benar tuntas** (bukan saat overlay
     di-insert). Implementasi: `_FlyToCartOverlay.onComplete` juga
     menuntaskan sebuah `Completer` yang di-await helper. Sheet dipicu dari
     `.then(...)`/`await` supaya tidak pakai timer magic-number.
   - Perlambat durasi total dari `600ms` → **`900ms`** (nilai awal, tunable).
     Kurva `Curves.easeInOutCubic` dipertahankan. Ambang haptic (`>= 0.85`)
     dan arc ratio tetap relatif terhadap progress, jadi ikut menyesuaikan.

## Struktur konten sheet (atas → bawah)

1. **Drag handle** (pill abu, 40×4).
2. **Header row:** judul "Lengkapi belanjaanmu" (16px, weight bold app
   `w900`/sesuai konvensi header sheet lain) + tombol ✕ (ikon dalam bulatan
   abu) di kanan → pop sheet.
3. **Baris konfirmasi:** thumbnail produk 46×46 (rounded) + nama produk
   (1–2 baris) + baris hijau `Icons.check_circle` + "Masuk ke keranjang!"
   (warna `NataloColors.successDark` `#16A34A`).
4. **Divider** tipis.
5. **Judul carousel:** "Cek keperluan anabulmu yang lain yuk".
6. **Carousel horizontal** rekomendasi (berbasis isi keranjang, **10 produk**,
   1 baris di-scroll ke samping):
   - Isi awal `initialRelated` (instan), lalu di-refresh dengan hasil
     cart-based dari `fetchRecommendations(cartIds: ..., excludeIds: ...)`.
   - Tiap kartu: gaya kartu app (surface + border + shadow halus), gambar
     square object-contain, nama 2 baris, harga biru, badge hemat/voucher
     soft, rating + terjual.
   - **Pill biru "+ Keranjang"** full-width di bawah kartu.
   - Kalau list kosong (awal & hasil fetch keduanya kosong) → seluruh
     section carousel disembunyikan (`SizedBox.shrink`), sheet tetap tampil
     (konfirmasi + Cek Keranjang).
7. **Tombol sticky "Cek Keranjang"** (ElevatedButton, `#1E5FBF`, teks putih,
   full-width, radius 12–14, height ~46–50) → pop sheet lalu
   `Navigator.pushNamed(context, '/cart')`.

## Perilaku / interaksi

| Aksi | Hasil |
|------|-------|
| Tap **+ Keranjang** (bottom bar detail) | Add ke cart → fly-to-cart (~900ms) → sheet naik. |
| Tap **+ Keranjang** di kartu rekomendasi (tanpa varian) | `cartStore.addProduct` + haptic sukses + toast mini + badge naik. Sheet tetap terbuka. |
| Tap **+ Keranjang** di kartu rekomendasi (produk **punya varian**) | Tutup sheet + buka halaman detail produk tsb (konsisten `_GridCartButton`). |
| Tap **body kartu** rekomendasi | Tutup sheet + `Navigator.pushNamed('/product-detail', arguments: product)`. |
| Tap **Cek Keranjang** | Tutup sheet + `pushNamed('/cart')`. |
| Tap **✕** / geser bawah / tap luar | Tutup sheet, tanpa efek samping. |

## Edge cases

- **Produk utama punya varian:** alur existing `_openVariantSheet()` jalan
  dulu; setelah user pilih varian & tap add, `_addToCart` berjalan → sheet
  muncul seperti biasa. Tidak ada perubahan urutan varian.
- **Stok habis / clamp:** tetap pakai toast info existing; sheet tetap boleh
  muncul untuk item yang berhasil masuk (mengikuti perilaku add sukses).
- **`_related` belum ter-load / kosong saat buka:** carousel kosong sesaat,
  lalu terisi begitu fetch cart-based selesai. Kalau fetch juga kosong →
  section carousel disembunyikan.
- **Keranjang cuma berisi produk ini saja:** `excludeIds` = isi cart membuat
  produk yang sama tidak muncul; backend tetap balikin produk lain yang
  relevan. Kalau kosong → carousel hilang.
- **Cart icon tidak ada di layar:** `flyImageToCart` sudah no-op aman; sheet
  tetap harus muncul (jangan gantungkan pemunculan sheet pada keberadaan
  cart icon — trigger sheet independen dari sukses animasi).
- **Dark mode:** semua warna via `colorScheme`/`NataloColors` supaya ikut
  adaptif; centang hijau & CTA biru tetap konsisten.
- **Double-tap + Keranjang cepat:** sheet pakai `showModalBottomSheet`;
  guard agar tidak menumpuk dua sheet (mis. cek `ModalRoute.isCurrent` atau
  flag `_sheetOpen`).

## Reuse komponen existing

- Data rekomendasi:
  [`productService.fetchRecommendations`](../../../flutter_app/lib/services/product_service.dart)
  (endpoint `/api/cart/recommendations`) dipanggil dengan `cartIds` = isi
  keranjang. `initialRelated` memakai `_related` yang sudah ter-load via
  `_loadRelated()` sebagai placeholder instan.
- Isi keranjang: `cartStore.items` (tiap `CartItem` punya `.product.id`).
- Warna: [`NataloColors`](../../../flutter_app/lib/theme/natalo_colors.dart)
  (`primary #1E5FBF`, `successDark #16A34A`, `dangerSoft`, dst).
- Toast mini: `AppToast.showCartAdded`.
- Haptic: `AppHaptics`.
- Format harga/terjual: `formatRupiah`, `formatSoldCount`.

## Testing

- **Widget test** `added_to_cart_sheet_test.dart`:
  - Sheet menampilkan nama produk + "Masuk ke keranjang!".
  - Judul carousel = "Cek keperluan anabulmu yang lain yuk".
  - Carousel hilang saat `related` kosong.
  - Tap "Cek Keranjang" memicu navigasi ke `/cart`.
  - Tap "+ Keranjang" kartu non-varian menambah item ke `cartStore`.
- **Integration** (opsional, extend `cart_flow_test.dart`): dari detail →
  tap + Keranjang → sheet muncul → Cek Keranjang → sampai cart screen.
- Manual: cek durasi fly-to-cart baru terasa pas di device fisik.

## Risiko & catatan

- Durasi animasi `900ms` adalah tebakan awal; wajib dilihat di HP dan
  di-tune (jangan sampai terasa lambat/menghambat).
- Jangan meng-couple pemunculan sheet dengan `flyImageToCart` menemukan
  cart icon — kalau icon tidak ada, animasi no-op tapi sheet tetap muncul.
