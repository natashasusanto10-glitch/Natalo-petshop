# Feed–Profile Race Recovery Equivalence Audit

## Tujuan

Memastikan seluruh perilaku perbaikan pada `claude/feed-profile-race-recover`
telah tercakup oleh `main` terbaru tanpa memasukkan kembali implementasi
playback lama. Commit lama tidak dianggap wajib masuk ke riwayat `main`; yang
wajib adalah kesetaraan perilaku dan perlindungan regresinya.

## Sumber kebenaran

`origin/main` terbaru menjadi fondasi implementasi. Arsitektur playback yang
sudah ada di `main`, termasuk `VideoAudioClaim`, `_playLegacy()`,
`_dependenciesReady`, coordinator playback, serta pengamanan frame/audio,
harus dipertahankan.

Branch `claude/feed-profile-race-recover` digunakan sebagai sumber persyaratan
perilaku dan skenario tes, bukan sebagai sumber kode yang harus diambil secara
utuh.

## Metode audit

Setiap perubahan produksi dan setiap skenario tes pada commit `ee1c48ca`
dipetakan ke salah satu status berikut:

1. **Setara langsung** — perilaku dan tes yang sama sudah ada di `main`.
2. **Setara melalui arsitektur baru** — hasilnya sama, tetapi dijaga oleh
   mekanisme playback/audio yang lebih baru.
3. **Belum tercakup** — perilaku atau regresi test belum ada dan perlu dipindah.
4. **Tidak lagi relevan** — detail implementasi lama telah digantikan dan tidak
   boleh dihidupkan kembali.

Matriks audit harus mencakup setidaknya:

- navigasi Feed ke Profile ketika controller belum selesai inisialisasi;
- route opaque dan nested route;
- bottom sheet transparan;
- app background/foreground ketika Feed tertutup;
- mute dan pemulihan volume setelah kembali;
- resume setelah controller belum tersedia ketika cover dimulai;
- seluruh jalur autoplay/play legacy;
- perilaku managed/coordinator agar tidak mengalami regresi;
- lifecycle, listener, dan pembersihan resource.

## Aturan integrasi

Tidak dilakukan rebase penuh atau cherry-pick langsung terhadap `ee1c48ca`.
Jika audit menemukan gap, hanya perubahan minimum yang dipindahkan ke branch
audit di atas `origin/main`, menggunakan API playback terbaru.

Pemanggilan `VideoPlayerController.play()` langsung tidak boleh ditambahkan
pada jalur legacy jika seharusnya melewati `_playLegacy()` dan audio claim.
Perubahan nomor versi dari branch lama juga tidak dipindahkan karena versi
`main` telah bergerak independen.

Jika tidak ditemukan gap, audit boleh selesai tanpa perubahan source code.
Tidak boleh membuat perubahan semu hanya agar commit lama tampak ter-merge.

## Verifikasi

Verifikasi dilakukan berlapis:

1. Bandingkan diff produksi dan tes commit lama terhadap `main`.
2. Jalankan seluruh tes `feed_video_post_view_test.dart` pada `main` terbaru.
3. Jalankan analyzer Flutter untuk file/scope relevan.
4. Jika ada kode yang dipindahkan, tambahkan atau sesuaikan tes yang gagal
   sebelum implementasi, lalu ulangi tes Feed dan suite yang proporsional.
5. Review akhir memastikan tidak ada jalur play langsung, debug code,
   perubahan versi tak sengaja, atau regresi terhadap bottom sheet transparan.

## Kriteria selesai

Audit selesai apabila setiap perilaku branch lama memiliki status dan bukti,
semua gap yang valid telah dipindahkan dengan arsitektur terbaru, serta tes
relevan lulus. Setelah itu `claude/feed-profile-race-recover` dapat dihapus dari
lokal dan remote karena tidak lagi menyimpan perilaku unik.

Penghapusan branch hanya dilakukan setelah hasil audit ditinjau dan pengguna
secara eksplisit menyetujuinya.
