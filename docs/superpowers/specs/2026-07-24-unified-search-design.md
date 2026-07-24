# Unified Search (Akun + Hashtag) Implementation Plan — Design

**Status: Approved — siap masuk writing-plans**

## Latar belakang

Di app kita, pencarian akun dan hashtag adalah dua alur terpisah yang tidak
saling terhubung:

- **Cari akun**: `FeedUserSearchScreen` (`flutter_app/lib/screens/feed_user_search_screen.dart`)
  — layar khusus, orang-saja, dibuka dari ikon search di tab Feed/Postingan
  (`feed_screen.dart` `_openFeedSearch()`).
- **Cari hashtag**: TIDAK ADA layar tersendiri. Hanya muncul sebagai
  autocomplete (`HashtagPickerController`/`HashtagSuggestionsPanel`,
  `flutter_app/lib/widgets/hashtag_picker.dart`) saat mengetik `#` di dalam
  editor caption (create/edit post). Tidak bisa dijelajahi di luar itu.
- `HashtagScreen` (`/hashtag/<name>`) sudah ada tapi cuma halaman HASIL untuk
  nama tag yang sudah diketahui — bukan pencarian.

Instagram menyatukan keduanya dalam satu kotak search: ketik teks biasa →
hasil akun, ketik `#...` → hasil hashtag, plus satu rail "Recent" campur
kedua jenis (dikonfirmasi via screenshot Instagram yang dilampirkan user:
baris vertikal, avatar bulat untuk akun / lingkaran `#` untuk tag, tombol
dismiss X per-baris).

Spec ini memperluas `FeedUserSearchScreen` yang sudah ada supaya berperilaku
sama — bukan membuat layar/titik-masuk baru. Search Beranda/Produk (di luar
lingkup, per instruksi proyek) TIDAK disentuh.

## Cakupan

1. **Deteksi mode berdasar prefix `#`** di kotak search yang sudah ada.
2. **Hasil hashtag**: daftar `#nama` + "N postingan", reuse
   `feedService.searchHashtags` (endpoint `GET /api/feed/hashtag-search`,
   sudah ada, tidak berubah). Tap → `Navigator.pushNamed('/hashtag',
   arguments: hashtag.name)` — argumen berupa **String nama tag polos**
   (tanpa `#`, boleh campur kasus, `HashtagScreen` normalize sendiri ke
   lowercase), persis pola yang sudah dipakai `mention_text.dart` untuk
   tap `#hashtag` di caption/komentar (lihat route registration
   `flutter_app/lib/main.dart:426-429`: `'/hashtag' when settings.arguments
   is String => HashtagScreen(name: settings.arguments as String)`). TIDAK
   ADA kelas argumen baru yang perlu dibuat.
3. **Recent (riwayat) campur akun+hashtag**, gaya DAFTAR VERTIKAL (bukan rail
   avatar horizontal yang ada sekarang) — baris: ikon (avatar bundar untuk
   akun / lingkaran `#` untuk tag) + judul (nama/username akun, atau `#tag`)
   + subtitle (nama lengkap akun, atau "N postingan" untuk tag) + tombol
   dismiss (X) di kanan, per-baris. Tanpa link "See all" (dikonfirmasi user).
4. **Suggested users** (saat kotak kosong) tetap seperti sekarang — tidak ada
   "suggested hashtag" (IG juga tidak punya ini).
5. **Titik masuk** tidak berubah — tetap ikon search yang sama di
   `feed_screen.dart`.

## Arsitektur

### Model gabungan untuk Recent

`FeedUserSearchScreen` saat ini menyimpan `List<FollowUserSummary>` sebagai
recent (SharedPreferences, key `feed_user_search_recent_v1` di-scope per
`OwnerScope`, JSON list, maks 12 entry, lihat baris 24-29/138-211). Diganti
jadi satu tipe union sederhana:

```dart
/// Satu entry recent — akun ATAU hashtag, tidak pernah dua-duanya.
class RecentSearchEntry {
  final FollowUserSummary? user;
  final HashtagSuggestion? hashtag;

  const RecentSearchEntry.user(this.user) : hashtag = null;
  const RecentSearchEntry.hashtag(this.hashtag) : user = null;

  bool get isHashtag => hashtag != null;

  Map<String, dynamic> toJson() => isHashtag
      ? {'type': 'hashtag', 'name': hashtag!.name, 'postCount': hashtag!.postCount}
      : {'type': 'user', ...user!.toJson()};

  factory RecentSearchEntry.fromJson(Map<String, dynamic> json) {
    if (json['type'] == 'hashtag') {
      return RecentSearchEntry.hashtag(
        HashtagSuggestion(
          name: (json['name'] as String?) ?? '',
          postCount: (json['postCount'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return RecentSearchEntry.user(FollowUserSummary.fromJson(json));
  }

  /// Identity key untuk dedupe (userId, atau `hashtag:<name>`).
  String get key => isHashtag ? 'hashtag:${hashtag!.name}' : 'user:${user!.id}';
}
```

Storage key TETAP `feed_user_search_recent_v1` (owner-scoped) — entry lama
(murni `FollowUserSummary.toJson()`, tanpa field `type`) di-parse sebagai
`type: 'user'` secara implisit (field `type` absen → default ke cabang user
di `fromJson`, backward compatible, tidak perlu migrasi data).

Maks entry tetap 12 (`_maxRecentUsers` → rename `_maxRecentEntries`),
dedupe by `.key`, item terbaru naik ke atas (perilaku sama seperti sekarang,
cuma tipe elemennya diganti).

### Mode deteksi + hasil

Di `_FeedUserSearchScreenState`, tambah:

```dart
bool get _isHashtagMode => _queryController.text.trim().startsWith('#');
String get _hashtagQuery =>
    _queryController.text.trim().substring(1); // buang '#'
```

Saat `_isHashtagMode`, debounce search (pola 250ms yang sudah ada,
JANGAN diubah) memanggil `feedService.searchHashtags(_hashtagQuery)`
alih-alih `followService.searchUsers(...)`. State hasil pakai union
sederhana (`List<FollowUserSummary> _userResults` DAN
`List<HashtagSuggestion> _hashtagResults`, cuma satu yang non-empty
tergantung mode — tidak perlu tipe union baru untuk ini, cukup dua field
terpisah + `_isHashtagMode` sebagai switch render).

Query kosong (`""`) atau cuma `"#"` tanpa apa pun setelahnya → tampilkan
state kosong hashtag (bukan error, bukan daftar suggested — beda dari mode
akun-kosong yang menampilkan suggested users).

### Rendering hasil hashtag

Baris baru `_HashtagResultTile` (paralel dengan tile hasil akun yang sudah
ada): leading lingkaran ikon `#` (mengikuti style `HashtagSuggestionsPanel`
di `hashtag_picker.dart` supaya konsisten visual dengan autocomplete
composer), title `#${hashtag.name}`, subtitle `'${hashtag.postCount}
postingan'`. `onTap`:

```dart
unawaited(_rememberRecentHashtag(hashtag)); // simpan ke recent
Navigator.of(context).pushNamed('/hashtag', arguments: hashtag.name);
```

### Rendering recent (list vertikal)

Widget `_RecentUserRail` (horizontal, avatar-carousel) DIHAPUS, diganti
`_RecentEntryList` (vertikal, `ListView`/`Column` biasa — TIDAK perlu
scrollable sendiri, sudah ada dalam scroll view existing screen):

- Leading: `ProfileAvatar` (akun) ATAU lingkaran abu dengan ikon `#`
  (hashtag) — ukuran sama (mis. 40px, cocokkan dengan ukuran avatar existing).
- Title: `user.username` (akun) atau `'#${hashtag.name}'`.
- Subtitle: `user.name` (akun, kalau beda dari username — logic existing
  dipertahankan) atau `'${hashtag.postCount} postingan'` (hashtag).
- Trailing: tombol X (`icon: Icons.close`, size mengikuti tap-target 44dp
  existing pattern proyek), `onTap` → hapus SATU entry ini dari recent
  (bukan clear semua) + persist.
- Row `onTap`: akun → `PublicProfileScreen` (perilaku sekarang, tidak
  berubah); hashtag → push `/hashtag` sama seperti tile hasil pencarian.

Header "Recent" tetap ada (judul + tombol "Hapus semua" yang sudah ada di
`_clearRecentUsers()` — rename ke `_clearRecentEntries()`), TANPA "See all"
(dikonfirmasi user — recent dibatasi 12 entry, tidak perlu halaman
terpisah).

### Backend

TIDAK ADA perubahan backend. `feedService.searchHashtags` dan
`followService.searchUsers` sudah ada dan cukup.

## Testing

- Widget test: ketik teks biasa → hasil akun (perilaku existing, regresi
  check). Ketik `#kata` → hasil hashtag muncul, tap → verifikasi push
  `/hashtag` dengan argumen benar.
- Widget test: recent campur — simpan 1 akun + 1 hashtag, reload screen,
  verifikasi urutan + tipe render benar (avatar vs ikon `#`).
- Widget test: dismiss satu entry recent (baik akun maupun hashtag) via
  tombol X → entry hilang, sisanya tetap ada, persist ke SharedPreferences
  terverifikasi (baca ulang setelah rebuild).
- Widget test: backward-compat — entry lama (JSON murni `FollowUserSummary`
  tanpa field `type`) dari storage tetap ter-parse sebagai akun, tidak
  crash.
- Widget test: query `"#"` doang (tanpa nama) → state kosong hashtag, bukan
  daftar suggested users, bukan error.

## Di luar cakupan (tidak dikerjakan di spec ini)

- Search Beranda/Produk — tidak disentuh sama sekali (instruksi proyek).
- Backend/endpoint baru — reuse yang sudah ada.
- "See all" recent / halaman riwayat terpisah — dikonfirmasi tidak perlu.
- Suggested hashtags saat kotak kosong — IG juga tidak punya ini.
- Preview grid thumbnail untuk hasil hashtag (dipilih: daftar nama+count
  saja, bukan grid visual).
- Titik masuk baru / navigasi baru — tetap ikon search yang sama di
  `feed_screen.dart`.
