# Share Preview dan Deep Link Natalo Petshop

Tanggal: 22 Juli 2026  
Status: Ditinjau setelah audit implementasi
Platform: Flutter Android, Flutter iOS, Next.js web, WhatsApp dan system share sheet

## 1. Ringkasan

Natalo harus membagikan URL publik yang sama pada Android dan iOS, lalu membiarkan sistem operasi dan aplikasi tujuan seperti WhatsApp mengambil preview dari metadata web. Setiap URL harus mewakili objek yang spesifik:

- Feed: `https://www.natalopetshop.com/feed/<postId>`
- Produk: `https://www.natalopetshop.com/products/<slug>`
- Profil: `https://www.natalopetshop.com/u/<username>`

Jika aplikasi Natalo terpasang, URL membuka layar native yang tepat. Jika aplikasi tidak terpasang, URL membuka halaman web publik yang tetap berguna. Preview WhatsApp memakai metadata Open Graph dinamis dan gambar share yang dibuat khusus untuk objek tersebut, bukan metadata homepage Natalo.

WhatsApp tetap memiliki kendali atas ukuran akhir, susunan kartu, cache, dan apakah preview ditampilkan. Natalo hanya menjamin metadata, gambar, URL, dan fallback web yang benar. Versi pertama tidak menjanjikan video dapat diputar langsung di dalam preview WhatsApp. Video diwakili poster yang memiliki indikator play dan durasi.

## 2. Tujuan

1. Share produk menampilkan foto produk, nama, harga, dan domain Natalo seperti kartu commerce.
2. Share Feed menampilkan foto atau poster video dari postingan yang dibagikan, identitas author, dan caption ringkas.
3. Share profil menampilkan avatar atau logo resmi, nama, username, dan ringkasan profil.
4. Satu URL bekerja untuk Android, iOS, browser, dan WhatsApp.
5. Link membuka app secara langsung jika terpasang, termasuk cold start dan warm start.
6. Jika app tidak tersedia, pengguna melihat halaman web yang relevan dan dapat melanjutkan ke App Store atau Play Store.
7. Konten privat, dihapus, belum dipublikasikan, atau dimoderasi tidak boleh bocor melalui metadata preview.
8. Share count Feed tetap konsisten dan tidak bertambah hanya karena pengguna membuka share sheet lalu membatalkannya.

## 3. Non-Tujuan

1. Menjamin layout preview WhatsApp identik pada seluruh versi WhatsApp.
2. Menjamin video dapat diputar langsung di kartu WhatsApp.
3. Mengirim file foto atau video sebagai attachment. Yang dibagikan tetap URL publik.
4. Mengganti navigation stack atau arsitektur Feed yang tidak terkait deep link.
5. Membuat short-link service baru pada versi pertama.
6. Menyimpan identitas penerima share atau aplikasi tujuan.
7. Membuka order, cart, wishlist, dan chat sebagai bagian dari paket ini. Jalur tersebut tetap menggunakan deep link yang sudah ada.

## 4. Kondisi Sistem Saat Ini

### 4.1 Flutter

- Paket `app_links` sudah digunakan.
- `DeepLinkService` sudah mengenali:
  - `/feed/<postId>`
  - `/products/<slug>` dan `/produk/<slug>`
  - `/u/<username>`
- Produk sudah dibagikan sebagai URL `/products/<slug>`.
- Profil sudah dibagikan sebagai URL `/u/<username>`.
- Feed sudah membagikan URL `/feed/<postId>` dari beberapa permukaan.
- Implementasi pembentukan teks dan URL share masih tersebar pada beberapa screen/widget.

### 4.2 Android

- `AndroidManifest.xml` sudah memiliki HTTPS App Link dengan `android:autoVerify="true"` untuk:
  - `natalopetshop.com`
  - `www.natalopetshop.com`
- Endpoint `/.well-known/assetlinks.json` sudah ada dan mengarah ke package `com.natalo.petshop` dengan Play App Signing fingerprint.
- Intent filter saat ini menangkap seluruh path HTTPS pada kedua host.

### 4.3 iOS

- Associated Domains sudah berisi:
  - `applinks:natalopetshop.com`
  - `applinks:www.natalopetshop.com`
- Endpoint AASA sudah ada.
- AASA sudah mengizinkan produk dan profil, tetapi belum mengizinkan `/feed/*`.
- `/feed/*` wajib ditambahkan agar share Feed membuka aplikasi pada iOS.

### 4.4 Web

- Produk memiliki `generateMetadata()` dinamis dengan judul, deskripsi, URL canonical, dan foto produk.
- Produk juga sudah memiliki `app/products/[slug]/opengraph-image.tsx`. Implementasi ini harus dimigrasikan atau diperkeras, bukan dibuat ulang. Saat ini ia masih memakai remote image langsung, fallback host lama, dan belum berbagi policy keamanan dengan Feed/profil.
- Profil memiliki `generateMetadata()` dinamis dengan identitas dan avatar.
- `/feed` hanya memiliki metadata umum.
- Belum ada halaman publik `/feed/[id]` dengan metadata per postingan.
- Belum ada kontrak data, policy keamanan remote image, cache, dan endpoint Open Graph yang konsisten untuk Feed, produk, dan profil.

## 5. Alternatif Desain

### 5.1 Menggunakan gambar asli langsung sebagai `og:image`

Kelebihan:

- Implementasi paling kecil.
- Tidak memerlukan render gambar server.
- Foto tetap tajam.

Kekurangan:

- Video tidak memiliki indikator play atau durasi.
- Profil hanya terlihat sebagai foto tanpa konteks.
- Gambar produk dengan latar transparan dapat terlihat kecil atau kosong.
- Hasil antar tipe konten tidak konsisten.

### 5.2 Generator Open Graph dinamis per tipe objek - dipilih

Server menghasilkan gambar preview khusus menggunakan `ImageResponse` atau renderer server yang setara.

Kelebihan:

- Feed video dapat menampilkan poster, play, dan durasi.
- Produk dapat menampilkan foto, nama ringkas, harga, dan identitas toko.
- Profil dapat menampilkan avatar, nama, username, dan statistik publik.
- Fallback visual dapat dikontrol ketika media rusak.
- Hasil konsisten di WhatsApp, Telegram, iMessage, dan crawler sosial lain yang membaca Open Graph.

Kekurangan:

- Lebih banyak kode server dan pengujian.
- Remote image harus diambil dengan aman.
- Perlu cache agar tidak membebani server.

### 5.3 Membuat file share image permanen saat konten dibuat

Kelebihan:

- Sangat cepat saat crawler mengakses link.
- Tidak ada render real-time.

Kekurangan:

- Gambar menjadi basi saat harga, caption, avatar, atau username berubah.
- Membutuhkan storage, lifecycle cleanup, dan worker tambahan.
- Upload Feed menjadi lebih kompleks.

### 5.4 Keputusan

Gunakan alternatif 5.2. Generator dinamis diberi cache CDN. Data objek tetap menjadi sumber kebenaran, sedangkan URL preview dapat diberi versi untuk mengatasi cache WhatsApp setelah objek diperbarui.

## 6. Arsitektur

```text
Flutter Share Action
  -> ShareLinkBuilder membentuk canonical URL + teks
  -> Android/iOS system share sheet
  -> WhatsApp menerima URL
  -> WhatsApp crawler GET halaman publik
  -> generateMetadata membaca objek publik
  -> og:image menunjuk dynamic OG image endpoint
  -> WhatsApp menyimpan dan menampilkan preview

Pengguna mengetuk URL
  -> App terpasang
     -> Android App Links / iOS Universal Links
     -> app_links
     -> DeepLinkService
     -> layar Feed / produk / profil yang tepat
  -> App tidak terpasang
     -> halaman web publik
     -> CTA buka/download aplikasi
```

Komponen baru atau yang disesuaikan:

1. `ShareLinkBuilder` di Flutter.
2. Model `ShareContent` di Flutter.
3. Halaman web publik `/feed/[id]`.
4. Helper query server-only untuk objek share publik.
5. Generator gambar OG untuk Feed, produk, dan profil.
6. Metadata dinamis yang konsisten.
7. Penambahan `/feed/*` pada AASA.
8. Penguatan lifecycle dan deduplikasi `DeepLinkService`.

## 7. Kontrak URL

### 7.1 Host canonical

Gunakan satu sumber konfigurasi untuk host share production:

```text
https://www.natalopetshop.com
```

Host apex `https://natalopetshop.com` tetap didukung oleh App Links dan Universal Links, tetapi URL baru yang dibagikan selalu memakai host canonical. Redirect apex ke `www` tidak boleh memutus akses AASA atau Asset Links.

### 7.2 Feed

```text
GET /feed/<postId>
```

Aturan:

- `postId` adalah ID database yang valid.
- Query `v` opsional menggunakan token versi share yang stabil:

```text
/feed/<postId>?v=<shareVersion>
```

- Query `v` tidak mengubah identitas objek.
- Canonical metadata selalu tanpa query `v`.
- Deep-link router mengabaikan `v`.

### 7.3 Produk

```text
GET /products/<slug>?v=<shareVersion>
```

- Slug dinormalisasi server.
- Alias `/produk/<slug>` tetap diterima oleh app, tetapi URL share baru memakai `/products/<slug>`.

### 7.4 Profil

```text
GET /u/<username>?v=<shareVersion>
```

- Username diubah ke lowercase sebelum membentuk URL.
- Display name tidak digunakan sebagai path.

## 8. Kontrak Share Flutter

### 8.1 Model

```dart
sealed class ShareContent {
  const ShareContent();
}

final class FeedShareContent extends ShareContent {
  final String postId;
  final String authorName;
  final String caption;
  final String? shareVersion;
}

final class ProductShareContent extends ShareContent {
  final String slug;
  final String name;
  final int effectivePrice;
  final String? shareVersion;
}

final class ProfileShareContent extends ShareContent {
  final String username;
  final String displayName;
  final String? shareVersion;
}
```

Nama akhir boleh mengikuti pola lokal repo, tetapi tanggung jawabnya harus tetap sama.

### 8.2 Builder

`ShareLinkBuilder` harus menghasilkan:

- URL HTTPS absolut.
- Subject opsional untuk platform yang mendukungnya.
- Teks pendek yang dilanjutkan URL pada baris terakhir.
- Versi cache dari `shareVersion` jika tersedia.

`shareVersion` adalah token opaque dan deterministik dari server, bukan waktu yang dibuat ketika tombol share ditekan. Server membentuknya dari field publik yang memengaruhi preview, misalnya caption, media utama, identitas author, harga efektif, stok, atau avatar. Implementasi awal boleh memakai hash SHA-256 yang dipotong menjadi 12-16 karakter URL-safe. Flutter hanya menyimpan, meng-encode, dan meneruskannya; Flutter tidak menghitung versi sendiri. Seluruh parser harus tetap kompatibel jika server lama belum mengirim field ini.

Builder tidak boleh:

- Mengakses `BuildContext`.
- Melakukan network request.
- Mengubah share count.
- Menyisipkan data anggota privat.
- Membentuk URL dari string interpolasi yang tidak di-encode.

### 8.3 Teks Feed

```text
Lihat postingan <authorName> di Natalo.
<canonicalShareUrl>
```

Caption tidak perlu disalin seluruhnya ke pesan WhatsApp. Caption digunakan pada metadata preview dan dibatasi panjangnya. Ini mencegah pesan terlalu panjang seperti iklan.

### 8.4 Teks produk

```text
Temukan <productName> seharga <formattedPrice> di Natalo Petshop.
<canonicalShareUrl>
```

Harga memakai harga efektif saat share. Harga di preview tetap berasal dari server saat crawler membuka URL, sehingga server adalah sumber kebenaran.

### 8.5 Teks profil

```text
Lihat profil <displayName> (@<username>) di Natalo.
<canonicalShareUrl>
```

### 8.6 Share result dan analytics

- Feed share count hanya bertambah setelah `ShareResultStatus.success`.
- Status `dismissed` dan `unavailable` tidak menambah count.
- Request increment harus idempotent untuk satu operasi share lokal jika platform mengirim callback ganda.
- Analytics hanya mencatat:
  - content type
  - content ID
  - result status
  - platform OS
- Analytics tidak mencatat kontak penerima atau aplikasi tujuan.

### 8.7 iPad

Pemanggilan share harus menyediakan `sharePositionOrigin` dari render box tombol untuk mencegah crash/popover error pada iPad. Android dan iPhone mengabaikan kebutuhan anchor ini.

## 9. Metadata Open Graph

### 9.1 Field wajib

Setiap halaman share publik harus menghasilkan:

- `title`
- `description`
- `alternates.canonical`
- `openGraph.title`
- `openGraph.description`
- `openGraph.url`
- `openGraph.siteName = "Natalo Petshop"`
- `openGraph.images`
- `twitter.card = "summary_large_image"`
- `twitter.title`
- `twitter.description`
- `twitter.images`
- `robots.index` sesuai visibilitas objek

Gambar harus mempunyai URL absolut HTTPS, content type gambar valid, dan dapat diakses tanpa cookie atau header autentikasi.

### 9.2 Feed

Judul:

```text
<authorName> di Natalo
```

Deskripsi:

- Caption yang dinormalisasi whitespace.
- Maksimal 140 karakter.
- Jika caption kosong: `Lihat postingan terbaru dari <authorName> di Natalo.`

Tipe:

- `article` untuk foto/carousel dan video pada versi pertama.
- Jangan mengiklankan `og:video` sampai kompatibilitas, keamanan URL media, dan cache WhatsApp lulus device test.

### 9.3 Produk

Judul:

```text
<productName> | Natalo Petshop
```

Deskripsi:

```text
<formattedEffectivePrice> - <stockLabel>. Produk original Natalo Petshop.
```

Jika harga atau stok berubah, crawler menerima data terbaru ketika cache URL versi berubah.

### 9.4 Profil

Judul:

```text
<displayName> (@<username>) di Natalo
```

Deskripsi:

- Bio publik maksimal 120 karakter.
- Fallback: `Lihat profil dan postingan <displayName> di Natalo.`

`openGraph.type` memakai `profile` jika tipe Metadata Next.js yang digunakan mendukung field tersebut dengan benar. Jika tidak, gunakan `website` tanpa custom tag yang tidak tervalidasi.

## 10. Desain Gambar Open Graph

### 10.1 Format umum

- Render server-side dengan `ImageResponse` atau renderer setara.
- Format PNG atau JPEG yang diterima crawler.
- Ukuran dasar: 1200 x 630 px untuk kompatibilitas Open Graph.
- Semua teks berada dalam safe area minimal 48 px.
- Maksimal dua baris untuk judul.
- Tidak ada data yang membutuhkan login.
- Gunakan warna solid dan token Natalo; media tetap menjadi fokus.

WhatsApp dapat memotong atau menyusun gambar secara berbeda. Karena itu, informasi penting tidak boleh ditempatkan terlalu dekat tepi.

### 10.2 Feed video

Komposisi:

- Poster video sebagai media utama.
- Media menggunakan `object-fit: cover` hanya di dalam frame preview, bukan mengubah playback di app.
- Overlay play di tengah.
- Durasi di kanan bawah jika tersedia.
- Nama author dan logo Natalo berada pada band informasi yang tidak menutupi subject utama.
- Caption tidak dirender penuh pada gambar.

Jika poster tidak ada:

- Gunakan thumbnail media pertama.
- Jika tetap tidak ada, gunakan fallback Feed Natalo yang netral.

### 10.3 Feed foto dan carousel

- Foto pertama menjadi media utama.
- Carousel menampilkan badge `1/<mediaCount>`.
- Jangan membuat kolase semua foto karena objek akan terlalu kecil di WhatsApp.
- Jika foto berorientasi portrait, gunakan contain/crop yang menjaga titik tengah dan menghindari distorsi.

### 10.4 Produk

- Foto utama produk berada pada latar putih atau abu sangat muda.
- Produk memakai `object-fit: contain`.
- Nama produk maksimal dua baris.
- Harga efektif ditampilkan jelas.
- Diskon hanya tampil jika benar-benar aktif.
- Logo Natalo kecil sebagai identitas, bukan hero.
- Tidak menampilkan banner homepage.

### 10.5 Profil

- Avatar atau logo official berada di kiri.
- Nama dan username berada di kanan.
- Badge official hanya muncul jika role/flag server menyatakan official.
- Statistik publik maksimal tiga item:
  - postingan
  - pengikut
  - mengikuti
- Akun official selalu memakai `OfficialBrandAvatar`, tidak boleh kembali ke inisial `N` jika logo resmi tersedia.

## 11. Query Data Publik

### 11.1 Feed

Buat helper server-only, misalnya `getPublicShareFeedPost(postId)`, yang hanya mengembalikan:

- ID
- status
- deleted state
- publishedAt
- updatedAt
- kind/media type
- caption/title/description yang diperlukan
- thumbnail/poster publik
- durasi video
- jumlah media
- author display name
- author username
- author public avatar
- author official flag

Query wajib menolak:

- draft
- pending moderation
- rejected
- soft-deleted
- account yang diblokir atau dihapus sesuai kebijakan produk
- konten yang memerlukan autentikasi

### 11.2 Produk

Gunakan sumber data produk yang sudah dipakai halaman detail. Tambahkan hanya field yang dibutuhkan gambar OG:

- effective price
- original price opsional
- stock
- image URL
- updatedAt

### 11.3 Profil

Gunakan sanitasi identitas official yang sama dengan halaman profil publik. Jangan mengambil:

- email
- nomor telepon
- alamat
- tanggal lahir
- statistik privat
- data membership

### 11.4 Kontrak `shareVersion`

Server membentuk token melalui satu helper, misalnya `buildShareVersion(parts)`, lalu menyertakannya pada payload publik yang sudah dipakai Flutter:

- setiap item Feed list dan single post
- detail produk
- profil publik dan item Feed pada profil

Token adalah hash pendek URL-safe dari nilai publik yang sudah dinormalisasi. Field bersifat additive dan nullable agar build Flutter lama tetap kompatibel. Flutter model menyimpan token sebagai `String?` tanpa menginterpretasikan isinya.

Field input minimal:

- Feed: post ID, caption/deskripsi, thumbnail/media pertama, durasi, author display name/avatar/official flag.
- Produk: slug, nama, image utama, harga efektif, harga asli, status diskon, dan label stok.
- Profil: username, display name, avatar/logo, bio publik, official flag, dan statistik publik yang tampil di kartu.

Dengan kontrak ini, perubahan harga promo dari tabel turunan tetap menghasilkan URL versi baru walaupun `Product.updatedAt` tidak berubah. Jangan memasukkan waktu request, token autentikasi, signed media query yang cepat kedaluwarsa, atau data privat ke hash.

## 12. Halaman Publik Feed Per Post

Buat route:

```text
app/feed/[id]/page.tsx
```

Tanggung jawab:

1. `generateMetadata()` membaca post publik.
2. Jika post tidak valid, hasil metadata aman dan halaman 404/noindex.
3. Halaman menampilkan media/poster, author, caption ringkas, dan CTA buka aplikasi.
4. Video web boleh menggunakan poster dengan tombol play, tetapi playback web bukan syarat preview WhatsApp.
5. Halaman tidak mengandalkan session cookie.
6. Halaman tetap usable jika JavaScript gagal.
7. Tombol App Store dan Play Store menggunakan URL production yang benar.

Halaman ini tidak menggantikan `/feed` utama.

## 13. Generator OG Image

Struktur yang dipilih setelah audit:

```text
app/api/share/og/feed/[id]/route.ts
app/api/share/og/product/[slug]/route.ts
app/api/share/og/profile/[username]/route.ts
lib/share/feed-share-data.ts
lib/share/product-share-data.ts
lib/share/profile-share-data.ts
lib/share/share-version.ts
lib/share/og-image-security.ts
lib/share/og/feed-card.tsx
lib/share/og/product-card.tsx
lib/share/og/profile-card.tsx
```

Endpoint eksplisit dipilih karena metadata dapat menunjuk URL gambar yang versioned secara deterministik dan route dapat menetapkan `Cache-Control`, content type, serta fallback secara eksplisit. Template tetap berbeda per tipe objek. Primitive visual boleh dibagi jika benar-benar sama, tetapi satu template universal tidak diwajibkan.

`app/products/[slug]/opengraph-image.tsx` yang sudah ada dimigrasikan ke endpoint produk di atas setelah metadata produk menunjuk endpoint baru dan regression test lulus. Jangan menjalankan dua template produk sebagai sumber kebenaran permanen.

### 13.1 Cache

- Metadata page: revalidate 60 detik atau mengikuti strategi halaman yang sudah ada.
- OG image: CDN cache dengan `s-maxage` dan `stale-while-revalidate`.
- Share URL dan URL gambar OG boleh memakai `?v=<shareVersion>` agar crawler melihat URL baru setelah perubahan penting.
- Canonical URL tetap tanpa `v`.
- Versi tidak boleh memakai timestamp saat tombol ditekan karena akan membuat URL unik setiap share dan menghancurkan cache.
- Nilai `v` tidak pernah dipakai untuk memilih data database; ia hanya menjadi cache key. Endpoint selalu membaca objek terbaru yang masih publik.

### 13.2 Fallback

- Image fetch gagal: render template tanpa foto, bukan 500.
- Font gagal: gunakan bundled font/fallback system yang didukung renderer.
- Caption null: gunakan fallback copy.
- Produk tidak ditemukan: jangan menghasilkan preview seolah produk masih tersedia.

## 14. Keamanan

### 14.1 SSRF dan remote image

Generator OG tidak boleh mengambil URL arbitrary dari database tanpa validasi.

Allowlist minimal:

- domain Natalo production
- domain upload/CDN resmi yang digunakan Feed
- Bunny CDN/Stream host yang digunakan thumbnail
- host storage profil resmi

Aturan:

- hanya HTTPS
- hanya host exact atau suffix CDN resmi yang dikonfigurasi; pencocokan substring dilarang
- blok localhost, loopback, private IP, link-local, dan metadata service
- URL dengan credential, port non-HTTPS, IP literal, atau scheme selain HTTPS ditolak

Versi pertama tidak membuat generic image proxy. `ImageResponse` hanya menerima URL HTTPS dari host CDN resmi yang lolos validator; URL lain diganti fallback lokal. Karena tidak ada endpoint proxy arbitrary, user tidak dapat meminta server mengambil host bebas. Jika kemudian dibutuhkan fetch byte server-side, perubahan itu wajib menambah timeout, batas ukuran response, validasi `image/*`, dan pemeriksaan redirect terpisah sebelum dirilis.

### 14.2 Sanitasi teks

- Hilangkan control character.
- Normalisasi whitespace.
- Batasi panjang sebelum render.
- Jangan merender HTML dari caption/bio/description.
- Emoji boleh dipertahankan jika font renderer mendukungnya; jika tidak, fallback tidak boleh membuat render gagal.

### 14.3 Otorisasi dan privasi

- Metadata dan OG image hanya memakai data yang boleh dilihat publik.
- Objek privat mengembalikan 404 atau metadata noindex tanpa media privat.
- Preview yang sudah tersimpan di chat WhatsApp tidak dapat ditarik kembali oleh Natalo setelah konten dihapus. Ini harus dianggap sebagai batas platform.

## 15. Deep Link Android dan iOS

### 15.1 Android

Pertahankan intent filter HTTPS dan `autoVerify=true`.

Verifikasi production:

```text
https://www.natalopetshop.com/.well-known/assetlinks.json
https://natalopetshop.com/.well-known/assetlinks.json
```

Kedua URL harus:

- HTTP 200
- `Content-Type: application/json`
- tidak redirect
- package `com.natalo.petshop`
- fingerprint Play App Signing production

### 15.2 iOS

Tambahkan komponen AASA:

```json
{ "/": "/feed/*", "comment": "Public Feed post deep links" }
```

Verifikasi kedua domain associated:

```text
https://www.natalopetshop.com/.well-known/apple-app-site-association
https://natalopetshop.com/.well-known/apple-app-site-association
```

Keduanya harus:

- HTTP 200
- tanpa ekstensi file
- `Content-Type: application/json`
- tidak redirect
- memakai Team ID dan bundle ID production yang benar

### 15.3 Cold start, warm start, dan deduplikasi

`DeepLinkService` harus memenuhi kontrak berikut:

1. Initial URI tidak hilang ketika `NavigatorState` belum siap.
2. URI disimpan sebagai pending sampai navigator tersedia.
3. URI dari `getInitialLink()` dan `uriLinkStream` yang sama tidak diproses dua kali.
4. Deduplikasi memakai normalized URI dan jendela waktu pendek.
5. Satu deep link hanya menghasilkan satu navigation push.
6. Query `v`, UTM, atau analytics tidak mengubah route target.
7. Host harus `natalopetshop.com` atau `www.natalopetshop.com` sebelum diproses sebagai internal deep link.
8. Scheme selain HTTPS ditolak kecuali custom scheme resmi ditambahkan melalui desain terpisah.

### 15.4 Route behavior

Feed:

- Video membuka scoped fullscreen langsung sesuai perilaku `openFeedPostSmart` yang ada.
- Foto/carousel membuka `MemberPostDetailScreen`.
- Post tidak tersedia: fallback ke `/feed` dengan pesan ringan, bukan blank screen.

Produk:

- Fetch by slug.
- Jika tidak ditemukan, buka pencarian produk dengan keyword hasil slug.

Profil:

- Username lowercase.
- Jika tidak ditemukan, buka Feed atau layar not-found yang jelas.

## 16. UX Fallback Web

Setiap halaman publik memiliki CTA yang tidak mengganggu crawler:

1. `Buka di aplikasi Natalo` jika browser dapat menjalankan Universal/App Link.
2. `Download di App Store`.
3. `Download di Play Store`.
4. Konten publik tetap terlihat tanpa memaksa instalasi.

Tidak boleh ada redirect otomatis agresif ke store karena:

- crawler WhatsApp harus dapat membaca metadata dan halaman.
- pengguna desktop tetap membutuhkan fallback web.
- redirect loop dapat merusak link preview.

## 17. Observabilitas

Event minimum:

- `share_sheet_opened`
- `share_completed`
- `share_dismissed`
- `deep_link_received`
- `deep_link_opened`
- `deep_link_fallback`
- `deep_link_failed`
- `og_image_render_failed`

Property aman:

- content type
- content ID atau hashed ID sesuai kebijakan analytics
- OS
- app lifecycle state
- target route
- failure reason enum

Jangan log:

- isi chat
- nama penerima
- nomor WhatsApp
- token autentikasi
- order tracking token

## 18. Error Handling

| Kondisi | Preview web | Native deep link |
| --- | --- | --- |
| Feed post tidak ditemukan | 404/noindex | buka Feed + toast ringan |
| Feed post belum published | 404/noindex | buka Feed + toast ringan |
| Poster video gagal | OG fallback Feed | video mencoba sumber valid, jika gagal tampil retry |
| Produk tidak ditemukan | 404/noindex | buka pencarian dari slug |
| Profil tidak ditemukan | 404/noindex | buka Feed/not-found |
| App tidak terpasang | halaman web | tidak berlaku |
| Navigator belum siap | tidak berlaku | antrekan pending URI |
| URI ganda dari plugin | tidak berlaku | deduplikasi, satu push |
| OG renderer gagal | metadata tanpa image/fallback statis | tidak memengaruhi routing |

## 19. Pengujian

### 19.1 Unit test Flutter

- Builder Feed menghasilkan path, teks, dan version query yang benar.
- Builder produk memformat harga dan encode slug.
- Builder profil lowercase dan encode username.
- Builder tidak menambahkan `v` bila `shareVersion` null atau kosong.
- Tidak ada data null yang menghasilkan string `null`.
- Share count hanya dipanggil pada success.
- Dismissed tidak mengubah count.
- Deep-link parser menerima kedua host resmi.
- Deep-link parser menolak host mirip seperti `natalopetshop.com.evil.com`.
- Initial URI diproses setelah navigator siap.
- URI duplikat hanya membuka satu route.

### 19.2 Unit/integration test web

- Metadata Feed published berisi author, caption, canonical, dan OG image.
- Draft/deleted/rejected Feed tidak membocorkan metadata.
- Metadata produk berisi harga efektif dan foto valid.
- Metadata profil official memakai brand-safe identity.
- OG endpoints mengembalikan HTTP 200 dan `image/png` atau `image/jpeg`.
- OG fallback tetap 200 saat image origin gagal.
- Remote image allowlist menolak private/unknown host.
- AASA berisi `/feed/*`, `/products/*`, dan `/u/*`.
- Asset Links tetap memiliki package dan fingerprint production.

### 19.3 Android device test

Dengan app terpasang:

```text
adb shell am start -a android.intent.action.VIEW \
  -d "https://www.natalopetshop.com/feed/<id>"
```

Uji Feed video, Feed foto/carousel, produk, dan profil pada:

- app terminated
- app background
- app foreground
- user sudah login
- user belum login untuk konten publik

Dengan app tidak terpasang:

- link membuka halaman web yang benar.

### 19.4 iOS device/simulator test

```text
xcrun simctl openurl booted \
  "https://www.natalopetshop.com/feed/<id>"
```

Uji lifecycle yang sama dengan Android. Universal Link final wajib diverifikasi pada device iOS/TestFlight karena simulator tidak mewakili seluruh cache AASA production.

### 19.5 WhatsApp test matrix

| Platform | Feed video | Feed foto | Carousel | Produk | Profil |
| --- | --- | --- | --- | --- | --- |
| WhatsApp Android | wajib | wajib | wajib | wajib | wajib |
| WhatsApp Business Android | smoke | smoke | smoke | smoke | smoke |
| WhatsApp iOS | wajib | wajib | wajib | wajib | wajib |

Untuk setiap sel:

- preview muncul tanpa login
- gambar sesuai objek
- judul dan deskripsi tidak generik
- tap membuka app jika terpasang
- tap membuka web jika app tidak terpasang
- back navigation masuk akal
- tidak ada duplicate route

Gunakan URL versi baru ketika perlu menghindari cache preview WhatsApp selama QA. Jangan menilai perubahan metadata dengan URL lama yang sudah di-cache.

## 20. Urutan Implementasi

### Tahap 1: Fondasi URL dan Share Builder

1. Tambahkan `shareVersion` pada serializer publik Feed, produk, dan profil serta parser model Flutter secara backward-compatible.
2. Tambahkan `ShareContent` dan `ShareLinkBuilder`.
3. Migrasikan tombol share Feed, detail Postingan, produk, dan profil ke builder.
4. Pertahankan behavior share count.
5. Tambahkan unit test Android/iOS-independent.

### Tahap 2: Feed Public Page dan Metadata

1. Tambahkan helper query Feed publik.
2. Tambahkan `/feed/[id]`.
3. Tambahkan metadata per post.
4. Tambahkan noindex/404 untuk konten tidak publik.
5. Tambahkan integration test.

### Tahap 3: OG Image

1. Implementasikan endpoint dan template Feed.
2. Migrasikan generator produk lama ke endpoint/template produk yang diperkeras.
3. Implementasikan endpoint dan template profil.
4. Tambahkan fallback dan image host allowlist.
5. Tambahkan cache headers dan test.

### Tahap 4: Universal/App Link Hardening

1. Tambahkan `/feed/*` pada AASA.
2. Tambahkan pending URI dan deduplikasi pada `DeepLinkService`. Ini wajib menjadi bagian implementasi agar cold start tidak bergantung pada waktu kesiapan navigator.
3. Verifikasi domain apex dan `www` production.
4. Jalankan device tests.

### Tahap 5: Production Verification

1. Deploy web terlebih dahulu.
2. Verifikasi crawler dapat membaca metadata tanpa cookie.
3. Build Android dan iOS baru untuk perubahan native/deep-link handler.
4. Test WhatsApp dengan URL baru.
5. Monitor error OG dan deep-link fallback.

## 21. Rollout dan Rollback

### 21.1 Rollout

- Web metadata dan OG image dapat dirilis lebih dulu tanpa build mobile.
- AASA diterapkan melalui deploy web, tetapi iOS dapat menyimpan cache association.
- Perubahan Flutter memerlukan build Android dan iOS baru.
- Migrasi tombol share dilakukan berurutan agar regresi mudah diisolasi:
  - produk
  - profil
  - Feed/detail Postingan/fullscreen

### 21.2 Rollback

- OG image error: metadata kembali memakai gambar asli atau fallback statis.
- Feed public page error: route dapat kembali ke halaman minimal tetapi tetap mempertahankan metadata aman.
- Share builder error: rollback Flutter ke URL stable lama.
- Deep-link regression: rollback build mobile; web fallback tetap berjalan.
- Jangan menghapus AASA/Asset Links saat rollback visual karena dapat memutus seluruh link native yang sudah stabil.

## 22. Acceptance Criteria

Fitur selesai jika seluruh kondisi berikut terpenuhi:

1. Share Feed video di Android dan iOS mengirim URL `/feed/<postId>` yang sama.
2. Share Feed foto/carousel memakai URL objek yang sama, bukan URL Feed umum.
3. WhatsApp menampilkan poster/foto Feed, author, dan caption ringkas.
4. Video preview memiliki sinyal play dan durasi jika data tersedia.
5. Carousel memiliki badge jumlah media pada OG image.
6. Produk menampilkan foto produk, nama, harga efektif, dan domain Natalo.
7. Profil menampilkan avatar/logo, nama, username, dan ringkasan publik.
8. Akun official tidak pernah kembali menjadi avatar inisial jika logo resmi tersedia.
9. Tap link Feed membuka konten yang benar pada Android saat app terpasang.
10. Tap link Feed membuka konten yang benar pada iOS saat app terpasang.
11. Tap link produk membuka detail produk pada kedua platform.
12. Tap link profil membuka profil publik pada kedua platform.
13. Cold start, warm start, dan foreground menghasilkan satu navigation push.
14. App yang tidak terpasang membuka halaman web publik yang relevan.
15. Draft, rejected, deleted, dan private content tidak muncul di metadata.
16. Share yang dibatalkan tidak menambah share count.
17. WhatsApp Android dan iOS lulus test matrix dengan URL yang belum di-cache.
18. Halaman dan OG endpoint tidak membutuhkan login.
19. OG renderer tidak dapat dipakai untuk SSRF ke host arbitrary/private.
20. Analyzer Flutter, test Flutter terkait, typecheck, lint, dan test web terkait lulus.

## 23. File yang Diperkirakan Terdampak

Daftar final ditentukan setelah implementation plan, tetapi batas perubahan diperkirakan meliputi:

```text
flutter_app/lib/services/deep_link_service.dart
flutter_app/lib/services/share_link_builder.dart
flutter_app/lib/models/share_content.dart
flutter_app/lib/models/feed_post.dart
flutter_app/lib/models/product.dart
flutter_app/lib/models/public_profile.dart
flutter_app/lib/features/feed/widgets/feed_video_post_view.dart
flutter_app/lib/screens/feed_screen.dart
flutter_app/lib/screens/member_post_detail_screen.dart
flutter_app/lib/screens/member_posts_screen.dart
flutter_app/lib/screens/product_detail_screen.dart
flutter_app/lib/screens/public_profile_screen.dart
flutter_app/android/app/src/main/AndroidManifest.xml
flutter_app/ios/Runner/Runner.entitlements

app/feed/[id]/page.tsx
app/products/[slug]/page.tsx
app/products/[slug]/opengraph-image.tsx
app/u/[username]/page.tsx
app/api/share/og/feed/[id]/route.ts
app/api/share/og/product/[slug]/route.ts
app/api/share/og/profile/[username]/route.ts
app/api/feed/posts/[id]/route.ts
app/api/feed/posts/route.ts
lib/feed/queries.ts
app/api/products/[slug]/route.ts
app/api/u/[username]/route.ts
app/.well-known/apple-app-site-association/route.ts
app/.well-known/assetlinks.json/route.ts
lib/share/*
```

`AndroidManifest.xml` dan `Runner.entitlements` tidak memerlukan perubahan isi untuk scope ini karena kedua host production sudah dideklarasikan. Keduanya tetap masuk checklist verifikasi. Perubahan iOS dilakukan pada endpoint AASA server untuk menambahkan `/feed/*`, bukan dengan menambah associated domain baru.

## 24. Keputusan yang Dikunci

1. Share mengirim URL publik, bukan attachment media.
2. URL yang sama dipakai Android dan iOS.
3. Preview dibangun melalui metadata Open Graph dinamis.
4. Video memakai poster, bukan janji playable preview WhatsApp.
5. Feed, produk, dan profil memiliki template preview berbeda.
6. WhatsApp menentukan layout akhir preview.
7. `/feed/*` ditambahkan ke AASA iOS.
8. Konten publik tetap dapat dibuka di web tanpa app.
9. Cache preview dibusting berdasarkan `shareVersion` server yang stabil, bukan waktu share.
10. Keamanan remote image dan visibilitas konten adalah release gate.
11. Endpoint OG eksplisit menjadi satu-satunya sumber gambar preview dinamis; generator produk lama dipensiunkan setelah parity test lulus.
