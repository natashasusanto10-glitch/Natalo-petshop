/// Rotasi harian deterministik untuk daftar rekomendasi.
///
/// Diekstrak dari home_screen supaya bisa diuji — bug seed `| 1` (rotasi
/// hanya berganti tiap 2 hari karena tanggal genap dipaksa jadi ganjil)
/// bertahan lama justru karena logika ini privat dan tak tersentuh tes.
library;

/// Angka tanggal lokal (YYYYMMDD) — sama sepanjang hari, ganti tengah malam.
int dailyRotationSeed({DateTime? now}) {
  final t = now ?? DateTime.now();
  return t.year * 10000 + t.month * 100 + t.day;
}

/// Dari daftar [ranked] (terurut, index kecil = paling kuat), ambil [count]
/// item dengan rotasi ber-[seed]: [pinned] teratas SELALU tampil, sisanya
/// dipilih bergilir dari kandidat berikutnya. Hasil di-sort ulang mengikuti
/// urutan [ranked] supaya yang tampil teratas tetap yang skornya terkuat.
List<T> dailyRotatingPick<T>(
  List<T> ranked, {
  required int seed,
  required int pinned,
  required int count,
  required Object Function(T) idOf,
}) {
  if (ranked.length <= count) return ranked.take(count).toList();
  final safePinned = pinned.clamp(0, count);
  final pinnedItems = ranked.take(safePinned).toList();
  final pool = ranked.sublist(safePinned);
  final need = count - pinnedItems.length;

  // Fisher-Yates ber-seed (LCG) — deterministik per hari, tanpa Random.
  final order = List<int>.generate(pool.length, (i) => i);
  // Seed DICAMPUR dulu (perkalian Knuth) sebelum dipakai. Versi lama
  // `seed | 1` memaksa bit terakhir jadi 1, sehingga tanggal GENAP
  // menghasilkan state yang sama dengan tanggal ganjil sesudahnya —
  // rotasi efektif hanya berganti tiap 2 hari (28 Agu == 29 Agu).
  var state = (seed * 2654435761) & 0x7fffffff;
  if (state == 0) state = 1;
  for (var i = order.length - 1; i > 0; i -= 1) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    final j = state % (i + 1);
    final tmp = order[i];
    order[i] = order[j];
    order[j] = tmp;
  }
  final picked = order.take(need).map((i) => pool[i]).toList();

  final chosen = <T>[...pinnedItems, ...picked];
  final rankIndex = <Object, int>{
    for (var i = 0; i < ranked.length; i += 1) idOf(ranked[i]): i,
  };
  chosen.sort((a, b) =>
      (rankIndex[idOf(a)] ?? 1 << 30).compareTo(rankIndex[idOf(b)] ?? 1 << 30));
  return chosen;
}
