# Public Profile Tab Merge Design

## Tujuan

Merapikan navigasi Grid, Video, dan Belanja pada seluruh public profile agar mengikuti pola Instagram: bersih ketika profil berada di posisi awal, lalu berubah menjadi kontrol berlabel ketika header menyatu saat pengguna scroll.

## Cakupan

- Berlaku pada profil public biasa dan Natalo Petshop Official.
- Tidak mengubah isi grid, data postingan, tab controller, atau perilaku swipe antar-tab.
- Tidak mengubah warna utama, font, atau spacing global Natalo di luar area navigasi tab profil.

## Mode awal

- Tampilkan hanya ikon Grid, Video, dan Belanja.
- Tidak ada label teks.
- Tidak ada background putih, border, atau container kapsul.
- Background area tab transparan dan menyatu dengan header profil.
- Warna ikon mengikuti foreground header: putih di hero official/navy, `onSurface` pada public profile biasa.
- Tab aktif memakai aksen Natalo tanpa menambahkan bar putih.

## Mode header menyatu

- Saat scroll mencapai fase collapse, grup tab bergerak halus dari kanan ke kiri.
- Grup berubah menjadi kapsul navy/charcoal transparan agar terbaca baik di atas header maupun media grid.
- Ikon dan label `Postingan`, `Video`, dan `Belanja` muncul dalam kapsul.
- Ikon dan teks nonaktif berwarna putih dengan opasitas tereduksi.
- Tab aktif memakai aksen Natalo sebagai penanda seleksi; bukan underline.
- Background kapsul tidak memakai putih polos.

## Transisi

- Gunakan progres scroll yang sudah tersedia pada `PublicProfileHeaderMotion`.
- Label bertransisi dari opacity 0 ke 1 saat kapsul mulai terbentuk.
- Radius, lebar grup, dan gap antar-tab beranimasi secara smoothstep seperti perilaku header saat ini.
- Underline aktif memudar ke opacity 0 sebelum mode kapsul selesai terbentuk dan tetap tidak terlihat ketika collapsed.
- Reverse-scroll harus membalikkan transisi secara mulus tanpa loncatan state.

## Struktur komponen

- `PublicProfileHeaderMotion` menyediakan nilai motion untuk mode awal dan collapsed: lebar grup, posisi horizontal, radius, gap, opacity label, opacity underline, dan status surface merged.
- `PublicProfileCollapsingHeaderDelegate` meneruskan nilai motion tersebut ke tab bar.
- `ProfileContentTabBar` menentukan background transparan atau kapsul gelap-transparan, serta warna ikon/label per mode.
- `_AnimatedProfileTab` tetap memiliki satu sumber state seleksi dari `TabController`.

## Aksesibilitas dan pengujian

- Label semantic dan tooltip tiap tab tetap ada walaupun teks visual disembunyikan pada mode awal.
- Test motion memverifikasi mode awal tidak memiliki label/underline dan mode collapsed memiliki label tanpa underline.
- Test widget memverifikasi tab tetap dapat ditap dan swipe antar-tab tidak berubah.
- Verifikasi visual manual dilakukan untuk public profile biasa dan official profile pada iPhone 15 Pro.

## Kriteria selesai

- Tidak ada bar putih pada tab profil di posisi awal ataupun mode merged.
- Tulisan hanya tampil setelah grup tab menyatu saat scroll.
- Kapsul mode collapsed selalu navy/charcoal transparan dan tidak mengganggu grid.
- Underline tidak terlihat ketika tab sudah merged.
