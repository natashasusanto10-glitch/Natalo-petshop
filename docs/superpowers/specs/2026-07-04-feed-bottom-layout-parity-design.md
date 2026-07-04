# Feed bottom layout — parity IG Reels

**Tanggal:** 2026-07-04
**File terdampak:** `flutter_app/lib/screens/feed_screen.dart`

## Masalah

Membandingkan Reels IG dengan feed kita, bagian bawah "amburadul" karena dua hal
yang berakar sama — elemen bawah tidak di-stack rapat di atas floating nav:

1. **Rail durasi tenggelam.** `FeedVideoScrubber` di-`Positioned(bottom: 0)`, nempel
   tepi bawah layar sehingga ketutup floating nav (`kFloatingNavClearance = 76`).
   User melihatnya "ada tapi di paling bawah layar".
2. **Void besar di bawah caption.** Caption/nama di `feedInfoInset = 24 + navClearance`,
   sedangkan rail di `bottom: 0`. Zona `navClearance` di antara keduanya kosong →
   "jarak nama & caption ke bottom terlalu jauh".

## Rancangan

Susun ulang overlay bawah agar rapat, meniru IG (bawah → atas):
`nav → rail durasi → caption → nama`.

Perubahan murni layout `Positioned` — tidak menyentuh logika playback/scrub.
Berlaku untuk **video** (`_FeedPostView`) dan, untuk konsistensi, **photo carousel**
(`_PhotoCarouselPostView`, kecuali rail durasi yang memang tidak ada di foto).

| Elemen | Sekarang | Usulan |
|---|---|---|
| Rail durasi (`FeedVideoScrubber`) | `bottom: 0` | `bottom: navClearance` — tepat di atas nav, terlihat |
| Caption/nama (`feedInfoInset`) | `24 + navClearance` | `navClearance + railBand + gap` (≈ `navClearance + 34`) — rapat di atas rail |
| Action rail (`actionRailInset`) | `_feedActionBottomInset + navClearance` | diturunkan agar dasar sejajar caption |

`navClearance = MediaQuery.paddingOf(context).bottom + kFloatingNavClearance` (safe-area aware) tetap dasar semua inset → aman di semua device.

## Non-goals

- Tidak mengubah `FeedVideoScrubber` / `FeedVideoProgressBar` internal (hit-area 28px, ekstrapolasi ticker tetap).
- Tidak mengubah gradient, action glyph, atau rotation produk.

## Verifikasi

Jalankan preview + screenshot, bandingkan dengan mockup: rail terlihat di atas nav,
caption rapat, tanpa void. Tuning angka gap jika perlu berdasarkan hasil visual.
