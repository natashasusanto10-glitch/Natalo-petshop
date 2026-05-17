/// Smart search synonyms — expand user query dengan terms yang
/// related supaya hasil search lebih relevan.
///
/// Pattern:
/// - Map kata Indonesia ↔ English ("anjing" ↔ "dog")
/// - Common typo ("kucing" / "kuching")
/// - Brand alias ("rc" / "royal canin")
/// - Singular/plural ("dog" / "dogs")
///
/// Pakai client-side karena:
/// 1. Capacitor backend search basic LIKE — limited synonym handling
/// 2. Latency 0 vs server roundtrip
/// 3. Tidak perlu update backend buat tambah synonym baru
class SearchSynonyms {
  /// Map word → list of equivalents. Bidirectional — kalau "anjing"
  /// di-expand jadi ["anjing", "dog"], maka "dog" juga expand jadi
  /// ["dog", "anjing"] via reverse build di constructor.
  static final Map<String, List<String>> _map = _buildBidirectional({
    // Pet types — Indonesia ↔ English
    'anjing': ['dog', 'doggie'],
    'kucing': ['cat', 'kitty'],
    'burung': ['bird'],
    'ikan': ['fish'],
    'hamster': ['hams'],
    'kelinci': ['rabbit', 'bunny'],
    'reptil': ['reptile'],
    'kura': ['turtle', 'kura-kura'],

    // Categories
    'makanan': ['food', 'pakan', 'kibble'],
    'mainan': ['toy', 'toys', 'mainan'],
    'snack': ['camilan', 'treat', 'treats'],
    'shampoo': ['shampo', 'sampo'],
    'kandang': ['cage', 'crate'],
    'pasir': ['litter', 'sand'],
    'kalung': ['collar', 'kalung'],
    'tali': ['leash', 'tali'],
    'mangkok': ['bowl', 'mangkuk'],
    'sisir': ['brush', 'comb'],
    'obat': ['medicine', 'med'],
    'vitamin': ['vit', 'supplement'],

    // Sizes / age
    'anak': ['puppy', 'kitten', 'junior'],
    'dewasa': ['adult'],
    'senior': ['old'],

    // Common brand abbreviations
    'rc': ['royal canin', 'royalcanin'],
    'rcfm': ['royal canin'],
    'mch': ['me-o', 'meo'],
    'whiskas': ['whiska'],

    // Typo correction
    'kuching': ['kucing'],
    'anjeng': ['anjing'],
    'royal': ['royal canin'],
    'cattie': ['kucing'],
  });

  /// Bidirectional builder — kalau a maps to [b,c], maka b maps to [a,c]
  /// dan c maps to [a,b]. Result: bisa cari pakai term apa pun.
  static Map<String, List<String>> _buildBidirectional(
      Map<String, List<String>> input) {
    final result = <String, Set<String>>{};
    for (final entry in input.entries) {
      final key = entry.key.toLowerCase();
      final values = entry.value.map((v) => v.toLowerCase()).toList();
      // Forward: key → values
      result.putIfAbsent(key, () => <String>{}).addAll(values);
      // Reverse: each value → [key, ...siblings]
      for (final value in values) {
        final siblings = [key, ...values.where((v) => v != value)];
        result.putIfAbsent(value, () => <String>{}).addAll(siblings);
      }
    }
    return result.map((k, v) => MapEntry(k, v.toList()));
  }

  /// Expand query → list of terms yang harus dicocokan. Selalu include
  /// original query. Result lowercased + deduped.
  ///
  /// Contoh:
  /// - `expand("makanan anjing")` → `["makanan anjing", "makanan", "anjing",
  ///    "food", "pakan", "kibble", "dog", "doggie"]`
  /// - `expand("rc")` → `["rc", "royal canin", "royalcanin"]`
  static List<String> expand(String query) {
    final original = query.trim().toLowerCase();
    if (original.isEmpty) return const [];

    final result = <String>{original};
    // Tambah whole-phrase synonym kalau ada.
    if (_map.containsKey(original)) {
      result.addAll(_map[original]!);
    }
    // Split per kata, tambah synonym tiap word.
    final words = original.split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.length < 2) continue;
      result.add(word);
      if (_map.containsKey(word)) {
        result.addAll(_map[word]!);
      }
    }
    return result.toList();
  }

  /// Match: cek apakah `text` mengandung salah satu term dari `expand(query)`.
  /// Pakai di filter list produk client-side.
  static bool matches(String text, String query) {
    final terms = expand(query);
    if (terms.isEmpty) return true;
    final lower = text.toLowerCase();
    return terms.any(lower.contains);
  }
}
