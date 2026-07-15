# Comment Drawer Presentation Design

**Date:** 2026-07-15  
**Scope:** Flutter Feed/Reels, halaman Postingan, dan scoped fullscreen dari Profile

## Goal

Menyediakan pengalaman komentar yang konsisten dan tahan race tanpa memaksakan satu presentasi visual pada semua permukaan. Natalo memakai satu mesin data komentar, tetapi dua mode drawer sesuai konteks pengguna:

1. Feed/Reels memakai drawer interaktif yang mengubah ukuran konten secara dua arah.
2. Halaman Postingan memakai modal drawer yang langsung menjeda video.

Scoped fullscreen tanpa drawer tetap memakai kontrol pause yang sama dengan Feed.

## Shared Comment Engine

Semua mode memakai sumber data dan lifecycle komentar yang sama:

- session komentar per viewer dan post;
- draft, reply target, posisi scroll, pagination, polling, dan moderasi;
- optimistic update dan rekonsiliasi server;
- proteksi pergantian akun dan route;
- single-flight admission untuk mencegah drawer ganda;
- cleanup overlay, focus, keyboard, Android back lease, dan controller;
- state machine `closed -> mounting -> opening -> visible -> closing`.

Presentation mode tidak boleh membuat implementasi data komentar kedua.

## Mode A: Feed/Reels

### Surfaces

Mode ini berlaku pada post video, foto tunggal, dan carousel di Feed/Reels.

### Bidirectional Media Resize

Extent drawer menjadi satu-satunya sumber progress visual:

- drawer naik: seluruh permukaan post mengecil;
- drawer turun: seluruh permukaan post membesar kembali;
- perubahan ukuran mengikuti posisi jari setiap frame;
- media, caption, action rail, dan overlay commerce bergerak sebagai satu permukaan;
- tarikan yang dilepas snap ke posisi tertutup, awal, atau maksimum;
- tarikan pendek yang dibatalkan menggunakan spring kembali ke snap terdekat;
- drawer tertutup mengembalikan post ke ukuran penuh tanpa lompatan.

Foto, carousel, dan video harus memakai rumus transformasi dan kurva yang sama. Aspect ratio media tidak boleh berubah atau terdistorsi selama resize.

### Playback Rules

- Posisi awal drawer adalah `0.60` dari tinggi host drawer.
- Posisi maksimum mengikuti safe area perangkat, dibatasi maksimal `0.96`.
- Drawer dianggap maksimum ketika extent berada dalam `0.02` dari posisi maksimum.
- Video tetap bermain pada posisi awal dan intermediate.
- Ketika drawer mencapai posisi maksimum, video dijeda otomatis.
- Saat drawer turun dari maksimum, video hanya dilanjutkan jika pause sebelumnya disebabkan drawer.
- Pause manual pengguna tidak boleh dibatalkan oleh perubahan extent drawer.
- Foto dan carousel hanya mengikuti transformasi visual tanpa state playback.

Nilai extent di atas menjadi konstanta bersama untuk presentation controller dan test; jalur foto, carousel, dan video tidak boleh mendefinisikan angka sendiri.

### Mute Control

- Saat drawer terlihat, tombol mute/unmute berada di kanan tepat di atas drawer.
- Tombol mengikuti posisi drawer agar tidak tertutup sheet.
- Tombol tidak memberikan haptic.
- Mute tetap menjadi preferensi global Feed/Postingan.
- Hanya controller video aktif yang boleh mengeluarkan suara.

### Overlay Visibility

Action rail dan overlay lain tidak boleh disembunyikan hanya karena state berubah menjadi `opening`. Visibilitas berubah setelah drawer benar-benar mencapai extent terlihat. Jika pembukaan gagal, seluruh overlay harus tetap atau kembali interaktif.

## Mode B: Halaman Postingan

### Presentation

- Drawer tampil sebagai modal di atas halaman.
- Background diredupkan.
- Konten Postingan tidak memakai transformasi resize Reels.
- Drawer memakai isi, draft, reply, polling, pagination, dan moderation engine yang sama dengan Mode A.

### Playback

- Video langsung pause ketika drawer mulai dibuka.
- State playback sebelum drawer dibuka disimpan.
- Saat drawer ditutup, video dilanjutkan hanya jika sebelumnya sedang bermain.
- Video yang sebelumnya dijeda harus tetap dijeda.

## Scoped Fullscreen From Profile

Alur: `Profile -> Postingan -> tap video -> scoped fullscreen`.

Tanpa drawer komentar, kontrol harus sama dengan Feed:

- tap sekali menjeda atau melanjutkan video;
- saat pause, tampilkan tombol play besar dan mute/unmute;
- saat resume, kontrol pause menghilang;
- state pause berasal dari coordinator, bukan tebakan state lokal widget;
- swipe ke post lain tidak membawa overlay pause dari post sebelumnya;
- mute tetap global dan hanya sesi aktif yang boleh bersuara.

Coordinator harus mengekspos state pause aktif melalui listenable/revision yang dapat diamati managed view.

## Drawer Reliability Contract

### Opening Watchdog

Setelah perintah membuka drawer:

1. Controller harus terpasang.
2. Extent harus bergerak melewati ambang terlihat dalam batas waktu transisi.
3. Jika controller detach, animasi gagal, atau extent tetap nol, lakukan rollback atomik ke `closed`.

Rollback wajib:

- menghentikan animasi;
- melepas overlay lock;
- menghapus back closer;
- membersihkan phase dan active session reference;
- memulihkan action rail, caption, dan tombol lain;
- menyelesaikan completer penutupan;
- membuat tap komentar berikutnya dapat membuka drawer lagi.

### Closing

Semua jalur penutupan harus melalui satu finalizer idempotent:

- tap backdrop;
- drag ke bawah;
- system back;
- route berpindah;
- widget deactivate/dispose;
- pergantian akun;
- modal lain menutup atau menutupi drawer.

Finalizer boleh dipanggil lebih dari sekali tanpa meninggalkan overlay transparan atau lock aktif.

## State Ownership

- Comment session store memiliki data komentar, draft, reply target, dan posisi scroll.
- Presentation controller memiliki phase, extent, animation, dan overlay lease.
- Playback coordinator memiliki play, pause, audio claim, dan mute application.
- Widget media hanya merender state dan melaporkan gesture.

Tidak boleh ada dua pemilik untuk playback atau drawer phase yang sama.

## Accessibility

- Tombol mute memiliki semantic label yang sesuai state.
- Drag handle dan tombol close/back dapat digunakan pembaca layar.
- Touch target minimal 44x44 logical pixels.
- Reduced motion tetap mengeksekusi perubahan state tanpa animasi panjang.

## Error Handling

- Gagal memuat komentar menampilkan retry di dalam drawer, bukan menutup drawer.
- Gagal membuka presentation tidak boleh memblokir Feed.
- Pergantian akun membatalkan request dan session milik viewer lama.
- Error playback tidak boleh mengubah ownership drawer.

## Acceptance Criteria

1. Foto, carousel, dan video di Feed mengecil saat drawer naik dan membesar saat drawer turun.
2. Resize mengikuti jari tanpa lompatan atau distorsi aspect ratio.
3. Video Feed tetap bermain pada initial/intermediate extent dan pause pada maximum extent.
4. Video hanya auto-resume bila pause disebabkan drawer.
5. Mute button terlihat di kanan tepat di atas drawer dan tidak memicu haptic.
6. Halaman Postingan menjeda video ketika modal komentar dibuka dan memulihkan state sebelumnya saat ditutup.
7. Scoped fullscreen menampilkan kontrol pause dan mute yang sama dengan Feed.
8. Tap komentar berulang tidak membuat drawer ganda atau invisible overlay.
9. Kegagalan attach/animation mengembalikan UI ke state interaktif dalam satu siklus transisi.
10. Back, drag-dismiss, route change, account switch, dan dispose selalu melepas seluruh lock.
11. Foto, carousel, video, dan Postingan memakai data komentar yang sama tanpa state duplikat.
12. Android dan iOS lulus pengujian gesture dan lifecycle yang sama.

## Required Tests

- widget test resize dua arah untuk foto, carousel, dan video;
- widget test playback pada initial, intermediate, dan maximum extent;
- test manual pause versus drawer-induced pause;
- test posisi dan semantics tombol mute;
- test opening watchdog untuk detached controller dan animation failure;
- test repeated rapid comment taps;
- test close melalui backdrop, drag, back, route change, account switch, dan dispose;
- test Postingan pause/resume restoration;
- test managed fullscreen pause notifier dan kontrol visual;
- regression test bahwa media gesture tetap bekerja setelah drawer gagal dibuka;
- device verification pada iOS dan Android.

## Out of Scope

- menambah reaction bar, GIF, gift, atau fitur komentar baru;
- mengubah backend schema komentar selain yang dibutuhkan untuk sinkronisasi yang sudah ada;
- mengubah layout product overlay, bottom navigation, atau action rail di luar transformasi drawer;
- menyalin visual Instagram secara identik; Natalo tetap memakai token warna dan komponen aplikasinya sendiri.
