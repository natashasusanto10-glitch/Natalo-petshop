# Public Profile Premium Redesign Design

## Status dan sumber keputusan

Dokumen ini menggantikan keputusan visual public profile pada:

- `2026-07-15-profile-grid-public-header-design.md`; dan
- `2026-07-16-public-profile-tab-merge-design.md`.

Sumber visual utama adalah dua mockup final yang sudah disetujui: public
profile Natalo Petshop Official dan public profile biasa, masing-masing pada
keadaan expanded dan collapsed. Implementasi harus mengikuti mockup tersebut
serta koreksi eksplisit berikut: tidak ada warna biru pada state tab, tidak ada
shared capsule, tidak ada underline ketika collapsed, dan chrome collapsed
harus berupa glass/blur yang memperlihatkan grid di belakangnya.

## Tujuan

Membuat public profile terasa ringkas, premium, dan dekat dengan pola interaksi
Instagram tanpa kehilangan identitas Natalo. Header official tetap memiliki
hero navy Natalo saat expanded. Profil biasa menggunakan surface netral sesuai
tema. Keduanya berubah secara halus menjadi chrome kaca di atas grid ketika
pengguna scroll.

## Cakupan

### Termasuk

- `PublicProfileScreen` untuk profil official maupun profil user biasa.
- Header expanded, toolbar, action row, statistik, bio, mutual followers
  official, dan tab Postingan/Video/Belanja.
- Transisi right-to-left dari tab ikon menjadi tiga pill berlabel.
- Kontrak mutual followers pada endpoint public profile yang sudah ada.
- Tombol `Pesan` official yang membuka chat customer-staff/NLCATTER yang sudah
  tersedia.
- Responsiveness, semantics, reduced motion, dan pengujian visual.

### Tidak termasuk

- Redesign profil sendiri di `MemberScreen`; bottom navigation dan hero profil
  sendiri tetap seperti sekarang.
- Perubahan isi grid, rasio tile, playback, prewarm video, origin handoff,
  pagination, follow mutation, atau detail postingan.
- Sistem notifikasi per akun. Ikon lonceng pada referensi Instagram tidak
  dirender karena Natalo belum memiliki kontrak notifikasi per-profile; tidak
  boleh ada tombol mati.
- Endpoint chat baru, room baru, atau perubahan NLCATTER.
- Migrasi Prisma.

## Prinsip visual bersama

- Grid tetap tiga kolom, rasio 4:5, edge-to-edge, dan gap 1 logical pixel.
- Font tetap Plus Jakarta Sans dan semua ukuran mengikuti text scaling.
- Spacing memakai grid `AppSpacing`; radius memakai `AppRadius`.
- Tidak menambah atau mengubah warna global `NataloColors` hanya untuk tab.
  Neutral pill disimpan sebagai token presentation lokal yang theme-aware.
- Area yang tidak dirender tidak menyisakan margin pengganti. Bio kosong,
  mutual followers kosong, dan action yang tidak tersedia membuat header
  merapat secara alami.
- Public profile tetap tidak memiliki bottom navigation. Native back dan iOS
  swipe-back tetap berfungsi.

## Header expanded: Natalo Petshop Official

- Background memakai `NataloColors.heroGradientV` dan warna foreground putih.
- Toolbar expanded hanya menampilkan tombol kembali dan overflow. Nama tidak
  diduplikasi di toolbar karena identitas official langsung terlihat di bawah.
- Avatar official berukuran 76-80 logical pixel dengan ring putih tipis.
- Nama selalu `Natalo Petshop Official`, diikuti badge official emas dan chip
  kecil `AKUN RESMI`.
- Bio maksimal satu baris pada ukuran normal dan dua baris pada text scale
  besar; overflow menggunakan ellipsis.
- Baris `Diikuti oleh` hanya muncul untuk viewer login, target official,
  bukan owner, dan mutual follower nyata tersedia. Maksimal tiga avatar saling
  overlap; teks menampilkan maksimal dua nama dan sisa jumlah sebagai
  `dan N lainnya`.
- Statistik Postingan/Pengikut/Mengikuti menjadi satu baris tipis tanpa kartu
  besar, outline besar, atau ruang vertikal kosong.
- Action row untuk official non-owner adalah `Ikuti/Mengikuti`, `Pesan`, dan
  tombol compact Bagikan. Untuk official owner, action row menjadi
  `Edit Profil` dan Bagikan; tidak ada Follow, Pesan, atau mutual followers.
- CTA besar `Lihat Etalase Produk` dihapus. Tab `Belanja` tetap menjadi akses
  resmi ke konten shoppable.
- Tab expanded berupa tiga ikon transparan. Tab aktif memakai foreground putih
  lebih kuat dan underline putih pendek. Tab nonaktif memakai putih dengan
  opacity lebih rendah. Tidak ada biru.

## Header expanded: public profile biasa

- Background menggunakan `colorScheme.surface`, dengan teks dan ikon neutral
  dari `colorScheme.onSurface`.
- Toolbar menampilkan kembali, handle, dan overflow. Share/moderation tetap
  memakai flow yang sekarang; tidak ada ikon lonceng tanpa fungsi.
- Avatar, nama, statistik, dan bio disusun compact seperti mockup. Avatar
  sekitar 78 logical pixel; statistik berada sejajar di samping avatar.
- Bio maksimal tiga baris dan hilang sepenuhnya jika kosong.
- Regular non-owner menampilkan `Ikuti/Mengikuti` dan Bagikan. Regular owner
  menampilkan `Edit Profil` dan Bagikan.
- Regular profile tidak pernah menampilkan `Pesan` atau `Diikuti oleh` pada
  fase ini.
- Tab expanded berupa ikon transparan; aktif menggunakan hitam/onSurface dan
  underline neutral pendek. Tidak ada biru.

## Header collapsed dan tab pills

Ketika identity header selesai terscroll, grid harus berada di belakang chrome
yang pinned. Chrome tidak boleh berubah menjadi strip navy atau putih solid.

- Satu `BackdropFilter` memburamkan seluruh area toolbar + tab dengan sigma
  maksimum 12. Jangan membuat blur terpisah pada setiap tombol atau pill.
- Official memakai tint `heroTop` transparan yang cukup untuk menjaga status
  bar dan foreground putih terbaca. Regular light memakai tint surface putih
  transparan dengan foreground gelap. Dark mode membalik neutral treatment
  secara theme-aware.
- Tombol kembali dan overflow berubah menjadi lingkaran frosted dengan target
  sentuh minimal 44 logical pixel.
- Toolbar official menampilkan mini avatar, `Natalo Petshop Official`, dan
  badge official setelah identity utama memudar. Regular mempertahankan handle.
- Tab berubah menjadi tiga pill individual, bukan satu container bersama:
  `Postingan`, `Video`, dan `Belanja`.
- Grup collapsed memiliki padding horizontal 16 logical pixel dan selalu
  muat dalam lebar viewport. Tiga pill menggunakan flex responsif; teks satu
  baris tidak boleh memaksa overflow atau menggeser tombol toolbar.
- Pada light/official treatment, pill aktif memakai charcoal hampir hitam
  dengan ikon/teks putih. Pill nonaktif memakai off-white frosted dengan
  ikon/teks charcoal. Dark mode memakai pasangan neutral terbalik agar kontras
  tetap terjaga.
- Tidak ada blue active state. Tidak ada underline ketika pills terbentuk.
- Active state dibedakan lewat surface, foreground, weight, dan semantics;
  bukan warna saja.

## Arsitektur glass yang benar

`SliverPersistentHeader` solid yang sekarang tidak dapat menghasilkan efek
glass nyata karena grid berhenti di bawah `minExtent`. Mengganti warnanya
menjadi transparan hanya akan memperlihatkan surface kosong, bukan media.

Arsitektur baru memakai `Stack`:

1. `NestedScrollView` tetap menjadi pemilik konten, tab controller, dan scroll
   state. Outer header mereservasi safe-area/toolbar spacer, identity header,
   dan posisi tab expanded, lalu dapat collapse sampai grid naik ke belakang
   overlay.
2. `PublicProfileChromeOverlay` berada di atas scroll view dan hanya menggambar
   toolbar serta tab presentation. Pointer hanya diterima pada kontrol nyata.
3. Overlay mendengarkan scroll controller melalui `AnimatedBuilder` atau
   `ListenableBuilder`, sehingga hanya chrome yang rebuild. Grid, media, dan
   `TabBarView` tidak ikut rebuild per frame.
4. Satu `RepaintBoundary` memisahkan grid dari chrome. Satu blur layer dipakai
   bersama untuk menjaga raster cost.
5. `TabController`, selected tab, swipe antar-tab, per-tab pagination, video
   prewarm, dan origin handoff tidak berubah.

Public-profile header composition diekstrak dari file screen menjadi widget
terfokus. Profil sendiri tetap memakai presentation tab default yang sekarang;
perubahan public pill wajib diaktifkan melalui presentation/config eksplisit
agar tidak mengubah `MemberScreen` secara tidak sengaja.

## Motion choreography

Semua nilai berasal dari satu progress scroll deterministik:

```text
raw = clamp(scrollOffset / collapseDistance, 0, 1)
progress = smoothstep(raw)
```

Tidak ada timer, spring, bounce, atau `AnimationController` kedua. Reverse
scroll pada offset yang sama harus menghasilkan frame yang identik.

- `0.00-0.20`: identity tetap dominan; tab masih full-width dan icon-only.
- `0.20-0.52`: underline aktif memudar sampai nol; tab mulai bergerak dari
  kanan ke kiri dan lebar grup mulai menyusut.
- `0.38-0.78`: neutral surface tiap pill dan glass chrome muncul bertahap.
- `0.45-0.78`: label Postingan/Video/Belanja fade dan reveal tanpa mengubah
  tinggi bar.
- `0.50-0.88`: background expanded memudar; grid mulai terlihat di bawah satu
  blur layer. Toolbar controls berubah menjadi frosted circles.
- `0.78-1.00`: geometri mengunci ke tiga pill individual; identity utama tidak
  lagi menerima pointer; official compact identity muncul di toolbar. Posisi
  akhir grup berada 16 logical pixel dari sisi kiri dan tidak menutup overflow.

Interpolation untuk posisi, lebar, gap, radius, opacity, tint, dan blur memakai
progress yang sama dengan interval terpisah. Tidak boleh ada pergantian boolean
di tengah scroll yang mengubah tinggi layout atau membuat grid meloncat.

Jika `MediaQuery.disableAnimations` aktif, progress tetap terikat langsung ke
scroll tetapi memakai interpolasi linear tanpa decorative easing; blur tidak
dianimasikan dan diganti tint translucent tetap. Tidak ada gerak otomatis
setelah jari berhenti.

## Kontrak mutual followers

Endpoint `GET /api/u/[username]` menambahkan blok backward-compatible:

```json
{
  "mutualFollowers": {
    "items": [
      {
        "id": "user-id",
        "name": "Nama User",
        "username": "handle",
        "profilePhotoUrl": "https://...",
        "isOfficial": false
      }
    ],
    "totalCount": 7
  }
}
```

- Query hanya dijalankan untuk viewer terautentikasi, target official, dan
  bukan owner.
- Items maksimal tiga dan diurutkan berdasarkan waktu akun tersebut mengikuti
  target (terbaru dahulu), lalu `id` ascending sebagai tie-breaker.
  `totalCount` adalah seluruh akun yang viewer ikuti dan juga mengikuti target
  official.
- Data admin yang muncul pada preview harus melalui helper branding existing
  agar nama/foto pribadi admin tidak bocor.
- Guest, owner, regular target, respons client lama, atau query optional yang
  gagal menghasilkan items kosong dan count nol; profil utama tetap dapat
  dimuat.
- Tidak diperlukan migrasi karena relasi `UserFollow` dan indeks yang relevan
  sudah tersedia.
- Flutter menambahkan model preview immutable dan parsing defensif. Saat viewer
  generation berubah, mutual data lama dikosongkan sebelum refetch agar data
  viewer sebelumnya tidak sempat tampil.

## Pesan dan matriks aksi

Tombol `Pesan` hanya diberikan ketika `profile.isOfficial &&
!profile.isOwner` dan chat customer aktif. Callback membuka named route
`/chat` tanpa membuat context palsu. `ChatRoomScreen` yang ada menangani login
gate, room customer `cust_<userId>`, kill switch, polling/push, dan koneksi
NLCATTER.

| Konteks | Aksi |
|---|---|
| Official non-owner | Ikuti/Mengikuti, Pesan, Bagikan |
| Official owner | Edit Profil, Bagikan |
| Regular non-owner | Ikuti/Mengikuti, Bagikan |
| Regular owner | Edit Profil, Bagikan |

Overflow mempertahankan share dan moderation yang sudah didukung. Official
tidak menawarkan report/block terhadap akun brand. Tombol yang tidak memiliki
backend nyata tidak dirender.

## Responsive layout dan aksesibilitas

- Tinggi expanded header dihitung dari jenis profil, text scale, bio yang
  benar-benar dirender, mutual row, dan action matrix. Nilai official `390`
  dan regular `280` yang sekarang tidak dipertahankan sebagai ruang kosong
  tetap.
- Layout wajib bebas overflow pada lebar 320, 360, 393, dan 430 logical pixel,
  serta text scale 1.0, 1.3, dan 2.0.
- Visual control compact boleh 36-40 logical pixel, tetapi semantic/hit target
  minimum 44 logical pixel.
- Label visual di chrome compact boleh membatasi text scale maksimum 1.3 agar
  tiga pill tetap muat pada lebar 320; label semantics tetap lengkap dan tidak
  dibatasi.
- Label semantic tab tetap tersedia ketika label visual tersembunyi. `selected`
  state, tooltip, traversal order, dan tombol back/share/message/follow tetap
  terbaca screen reader.
- Safe area memakai `MediaQuery.paddingOf`; tidak ada offset status bar atau
  Dynamic Island yang di-hardcode.

## Error dan loading behavior

- Kegagalan optional mutual followers tidak menggagalkan profil.
- Follow optimistic behavior, rollback, loading spinner, dan jumlah follower
  tetap menggunakan service/store yang ada.
- Tombol Pesan mengikuti login gate serta chat availability yang ada; tidak
  membuka layar kosong.
- Refresh, loading, empty/error tab, dan selected tab tidak reset karena
  perubahan presentasi header.
- Reverse scroll, pull-to-refresh, dan overscroll tidak boleh menimbulkan flash
  putih/navy atau seam satu pixel.

## Performance budget

- Satu blur layer aktif untuk seluruh collapsed chrome.
- Tidak ada blur per pill, `setState` screen-wide per frame, intrinsic layout
  berat di dalam frame scroll, atau controller animasi tambahan.
- Grid dan video tetap berada di luar repaint area chrome.
- Target visual adalah frame stabil 60 fps pada Android umum dan mengikuti
  refresh rate 120 Hz pada iPhone 15 Pro ketika perangkat mendukungnya.

## Verification

### Backend dan parsing

- Mutual query mengembalikan intersection yang benar, maksimal tiga preview,
  total count benar, dan tidak bocor identitas admin.
- Guest, regular target, owner, serta kegagalan optional mengembalikan blok
  kosong tanpa merusak response profil.
- Flutter parsing menerima response baru dan response lama tanpa field mutual.

### Widget dan motion

- Snapshot state 0%, 25%, 50%, 75%, dan 100% serta reverse pada offset sama.
- Tiga individual pills, tidak ada shared capsule, tidak ada biru, dan
  underline hanya pada expanded state.
- Selected tab dan scroll/grid position tidak berubah selama collapse,
  reverse, tap, atau horizontal swipe.
- Official/regular/owner/non-owner action matrix, mutual conditional, Pesan
  route `/chat`, CTA katalog hilang, dan tab Belanja tetap ada.
- Public profile tetap tanpa bottom nav; profil sendiri tetap dengan bottom
  nav dan presentation tab lamanya.
- Stabilkan `VisibilityDetector` dalam screen tests dengan update interval nol
  agar tidak ada pending timer palsu.

### Visual QA

- Empat golden iPhone 15 Pro (`393x852`, top safe area 59, bottom 34): official
  expanded/collapsed dan regular expanded/collapsed.
- Layout assertions Android compact `360x800` dan standard `412x915`.
- Light/dark, text scale 1.0/1.3/2.0, dan reduced motion.
- Manual: scroll lambat, flick cepat, balik arah pada fase tengah, pull to
  refresh, tab tap/swipe, glass tanpa flash, target sentuh, dan iOS TestFlight
  pada iPhone 15 Pro.

## Kriteria selesai

- Kedua public profile sama dengan mockup final secara hierarchy, density,
  neutral tab color, dan state expanded/collapsed.
- Official tetap Natalo navy saat expanded, tetapi collapsed memperlihatkan
  grid lewat glass, bukan strip biru solid.
- Regular tetap neutral putih/tema saat expanded dan glass ketika collapsed.
- Transisi right-to-left reversible, tidak jump, dan tidak memicu jank.
- Tidak ada ruang kosong buatan, tombol mati, data mutual palsu, blue active
  tab, shared capsule, atau underline collapsed.
- Seluruh kontrak data, semantics, focused tests, analyzer, dan visual QA lulus.
