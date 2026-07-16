# Feed Video Reels Framing

## Tujuan

Menyelaraskan framing video feed Natalo dengan perilaku Instagram Reels pada perangkat tinggi seperti iPhone 15 Pro. Video 9:16 harus tetap menampilkan frame asli tanpa pembesaran dan crop horizontal yang membuat wajah atau produk terlihat terlalu besar.

## Batasan

- Perubahan hanya menyentuh layout/framing media video.
- Warna, tipografi, spacing, action rail, kartu produk, caption, dan bottom navigation Natalo tetap dipertahankan.
- Branch `claude/feed-video-fit` tidak di-merge karena tertinggal jauh dari `main`.
- Tidak ada perubahan pada model, API, upload, atau playback lifecycle.

## Pendekatan yang dipilih

Media menggunakan viewport Reels 9:16 yang stabil dan dipusatkan pada layar. Video 9:16 dirender penuh tanpa crop horizontal. Area layar yang lebih tinggi dari viewport media diisi latar gelap. Overlay UI tetap berada di atas media dan tidak mengubah framing sumber.

Video dengan rasio selain 9:16 menggunakan framing adaptif `contain`, sehingga video square, 4:5, dan landscape tidak dipaksa memenuhi layar dengan zoom. Thumbnail menggunakan aturan yang sama dengan player agar tidak terjadi lompatan framing saat video siap.

## Komponen dan alur data

`_MediaBackground` tetap menjadi satu-satunya pemilik keputusan fit media. Komponen menerima rasio aktual dari controller ketika tersedia, atau rasio post untuk thumbnail. Ia menghasilkan canvas hitam dengan media yang diposisikan di tengah berdasarkan viewport 9:16.

Layer overlay yang sudah ada tetap menjadi sibling di atas background. Tidak ada perubahan pada callback playback, visibility, preloading, gesture, atau action rail.

## Aturan framing

1. Rasio mendekati 9:16: gunakan viewport 9:16 dan tampilkan seluruh frame.
2. Portrait yang lebih pendek dari 9:16, square, dan landscape: gunakan `contain` dengan letterbox.
3. Thumbnail dan video aktif harus menghasilkan keputusan fit yang sama berdasarkan rasio sumber.
4. Fallback ketika metadata belum tersedia tetap menggunakan rasio 9:16.
5. Clip terhadap batas viewport agar media tidak meluber ke area system UI.

## Error handling

Jika dimensi video tidak valid atau controller belum siap, gunakan rasio post bila tersedia dan fallback 9:16. Jika thumbnail gagal, pertahankan latar gelap yang sudah digunakan saat ini.

## Pengujian

- Widget test untuk thumbnail rasio 9:16, 4:5, square, dan 16:9.
- Test memastikan 9:16 tidak memilih crop yang memperbesar media pada viewport tinggi.
- Test memastikan rasio non-9:16 tetap letterbox.
- Regression test untuk widget feed tanpa controller.
- Verifikasi visual manual pada emulator/device berukuran iPhone 15 Pro.

## Kriteria selesai

- Video 9:16 pada iPhone 15 Pro menampilkan framing penuh seperti Reels Instagram.
- Tidak ada crop horizontal yang membuat subjek atau produk membesar.
- Tidak ada perubahan visual yang tidak terkait pada overlay Natalo.
- Semua test terkait feed video lulus.
