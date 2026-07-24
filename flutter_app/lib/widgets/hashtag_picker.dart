import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/feed_service.dart';
import '../utils/haptics.dart';
import '../utils/mention_text.dart';

/// Detection result dari current cursor position di text. Berisi partial
/// hashtag yang lagi diketik (kalau ada `#partial`), plus range index
/// supaya replace handle smooth saat user pick.
///
/// Near-mirror `_MentionQuery` (lihat mention_picker.dart) — struktur SAMA,
/// isi field sama, cuma nama class beda supaya jelas ini punya hashtag.
class _HashtagQuery {
  /// Partial hashtag (lowercased, tanpa `#`), e.g. "ku" untuk text
  /// "halo #ku|" (cursor di posisi |).
  final String query;

  /// Index awal `#` di full text — buat replace range.
  final int start;

  /// Index akhir query (= cursor position).
  final int end;

  const _HashtagQuery({
    required this.query,
    required this.start,
    required this.end,
  });
}

/// Controller untuk hashtag detection + suggestion fetch. Near-mirror
/// `MentionPickerController` (arsitektur SAMA: listener textController,
/// debounce Timer, `insertHashtag` replace-range) dengan DUA beda sengaja:
///
///  1. Debounce **300ms** (mention 200ms) — Global Constraints spec C.
///  2. Trigger char `#` (bukan `@`) dengan boundary LEBIH KETAT: mirip anti-
///     email mention (baris 136-141 mention_picker.dart), TAPI hashtag
///     HANYA valid di awal-teks atau setelah whitespace persis (bukan
///     whitespace-ATAU-tanda-baca seperti mention) — sama persis dengan
///     [kHashtagPattern] yang sudah dipakai render span (Task 9) & server
///     (`lib/feed/hashtags.ts`). Boundary check REUSE `kHashtagPattern`
///     langsung (`matchAsPrefix`) — bukan regex baru — supaya kalau
///     definisi boundary berubah di satu tempat, di sini otomatis ikut.
///
/// Tidak punya UI sendiri — paired dengan `HashtagSuggestionsPanel` buat
/// render. `searchFn` INJECTABLE (beda dari mention yang hardcode
/// `apiClient.getJson`) supaya unit test bisa fake network — pola dari
/// brief Task 12 (lihat test/widgets/hashtag_picker_test.dart).
class HashtagPickerController extends ChangeNotifier {
  final TextEditingController textController;

  /// Fetch suggestion dari nama partial (tanpa `#`). Produksi: pakai
  /// `feedService.searchHashtags`. Test: fake function no-network.
  final Future<List<HashtagSuggestion>> Function(String query) searchFn;

  Timer? _debounce;
  String _lastQuery = '';
  List<HashtagSuggestion> _suggestions = const [];
  bool _loading = false;
  _HashtagQuery? _activeQuery;

  HashtagPickerController({
    required this.textController,
    required this.searchFn,
  }) {
    textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    textController.removeListener(_onTextChanged);
    super.dispose();
  }

  List<HashtagSuggestion> get suggestions => _suggestions;
  bool get isActive => _activeQuery != null;
  bool get isLoading => _loading;

  /// Parse current cursor position untuk detect `#partial` di word yang
  /// sedang diketik. Return null kalau:
  ///   - Cursor tidak punya selection / di -1
  ///   - Char antara `#` dan cursor bukan char valid hashtag (a-z 0-9 _)
  ///   - Partial KOSONG (beda dari mention: mention tetap `isActive` saat
  ///     query kosong, cuma suggestions disembunyikan. Hashtag TIDAK ada
  ///     konsep "recent" jadi kosong = langsung inactive — lihat brief
  ///     Task 12 Step 3: "kosong → inactive").
  ///   - Partial > 50 char (mirror `kHashtagMaxLength` — analog cap 30 char
  ///     mention yang mirror max username length)
  ///   - Char sebelum `#` bukan boundary valid (start-of-text / whitespace)
  ///     — dicek via `kHashtagPattern.matchAsPrefix`, REUSE pattern yang
  ///     sama dgn server, bukan regex baru.
  _HashtagQuery? _detectHashtag() {
    final selection = textController.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final cursorPos = selection.start;
    if (cursorPos <= 0) return null;
    final text = textController.text;
    if (cursorPos > text.length) return null;

    // Walk back dari cursor untuk cari `#` start. Stop (return null) kalau
    // ketemu char di luar charset hashtag ([a-zA-Z0-9_] — sama dengan grup
    // 2 `kHashtagPattern`, TANPA `.` — beda dari mention yang izinkan `.`
    // untuk handle bergaya subdomain).
    int hashPos = -1;
    for (int i = cursorPos - 1; i >= 0; i--) {
      final c = text[i];
      if (c == '#') {
        hashPos = i;
        break;
      }
      if (!RegExp(r'[a-zA-Z0-9_]').hasMatch(c)) {
        return null;
      }
    }
    if (hashPos < 0) return null;

    final partial = text.substring(hashPos + 1, cursorPos).toLowerCase();
    // Kosong → inactive (beda sengaja dari mention, lihat dokumentasi di
    // atas method).
    if (partial.isEmpty) return null;
    if (partial.length > kHashtagMaxLength) return null;

    // Boundary: REUSE kHashtagPattern (bukan regex baru) — '#' valid hanya
    // di awal teks atau tepat setelah satu whitespace, mirror server persis
    // (Task 9 `mention_text.dart` / `lib/feed/hashtags.ts`).
    final anchor = hashPos == 0 ? 0 : hashPos - 1;
    if (kHashtagPattern.matchAsPrefix(text, anchor) == null) return null;

    return _HashtagQuery(query: partial, start: hashPos, end: cursorPos);
  }

  void _onTextChanged() {
    final detected = _detectHashtag();
    if (detected == null) {
      // Exit hashtag mode.
      if (_activeQuery != null || _suggestions.isNotEmpty || _loading) {
        _activeQuery = null;
        _suggestions = const [];
        _loading = false;
        _lastQuery = '';
        _debounce?.cancel();
        notifyListeners();
      }
      return;
    }
    _activeQuery = detected;
    if (detected.query == _lastQuery) {
      notifyListeners();
      return;
    }
    _debounce?.cancel();
    // 300ms — beda sengaja dari mention (200ms), lihat dokumentasi kelas.
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(detected.query);
    });
  }

  Future<void> _runSearch(String q) async {
    if (q.isEmpty) return;
    _lastQuery = q;
    _loading = true;
    notifyListeners();
    try {
      final result = await searchFn(q);
      // Race guard — kalau query udah ganti antara, abaikan hasil.
      if (_lastQuery != q) return;
      _suggestions = result;
    } catch (e) {
      if (kDebugMode) debugPrint('[hashtag] search error: $e');
      _suggestions = const [];
    } finally {
      _loading = false;
      if (_lastQuery == q) notifyListeners();
    }
  }

  /// Insert pilihan hashtag ke TextField. Replace range [#partial] dengan
  /// `#nama ` (trailing space supaya user langsung lanjut ketik). Move
  /// cursor ke setelah space. Haptic parity persis `insertMention`.
  void insertHashtag(HashtagSuggestion suggestion) {
    final active = _activeQuery;
    if (active == null) return;
    AppHaptics.tap();
    HapticFeedback.selectionClick();
    final text = textController.text;
    final before = text.substring(0, active.start);
    final after = text.substring(active.end);
    final inserted = '#${suggestion.name} ';
    final newText = '$before$inserted$after';
    final newOffset = before.length + inserted.length;
    textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
    // _onTextChanged akan fire dari setValue → hashtag exit naturally
    // (cursor di space, bukan di handle char) → panel auto-hide.
  }
}

/// Render panel suggestions di atas TextField. Listen ke controller.
/// Auto-hide kalau controller.suggestions kosong + tidak loading. Near-
/// mirror `MentionSuggestionsPanel` — layout Container+border+shadow SAMA,
/// isi baris beda (ListTile polos, tanpa avatar — hashtag tidak punya
/// foto profil).
class HashtagSuggestionsPanel extends StatelessWidget {
  final HashtagPickerController controller;

  /// Dark theme prop — konsisten dengan `MentionSuggestionsPanel` (comment
  /// sheet dark, caption editor light).
  final bool darkTheme;

  /// Max height panel. Default 220 — kira-kira 4-5 entry visible sebelum
  /// scroll.
  final double maxHeight;

  const HashtagSuggestionsPanel({
    super.key,
    required this.controller,
    this.darkTheme = false,
    this.maxHeight = 220,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final shouldShow = controller.isActive &&
            (controller.suggestions.isNotEmpty || controller.isLoading);
        if (!shouldShow) return const SizedBox.shrink();

        final bg = darkTheme ? const Color(0xFF1F2937) : Colors.white;
        final border = darkTheme
            ? Colors.white.withValues(alpha: 0.14)
            : const Color(0xFFE2E8F0);
        final shadowColor = darkTheme
            ? Colors.black.withValues(alpha: 0.5)
            : Colors.black.withValues(alpha: 0.08);

        return Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: controller.isLoading && controller.suggestions.isEmpty
              ? _HashtagLoadingRow(darkTheme: darkTheme)
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: controller.suggestions.length,
                  itemBuilder: (context, idx) {
                    final tag = controller.suggestions[idx];
                    return _HashtagSuggestionTile(
                      tag: tag,
                      darkTheme: darkTheme,
                      onTap: () => controller.insertHashtag(tag),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _HashtagSuggestionTile extends StatelessWidget {
  final HashtagSuggestion tag;
  final bool darkTheme;
  final VoidCallback onTap;

  const _HashtagSuggestionTile({
    required this.tag,
    required this.darkTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = darkTheme ? Colors.white : const Color(0xFF0F172A);
    final textMuted = darkTheme
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF64748B);

    // ListTile default height (title+subtitle two-line) jauh di atas 48dp
    // minimum tap target — lolos §3b tanpa penyesuaian tambahan. Ripple
    // bawaan ListTile = tap feedback (§3b hanya wajibkan pressed-state
    // custom utk elemen NON-ListTile).
    return Semantics(
      label: 'Tag ${tag.name}, ${tag.postCount} postingan',
      button: true,
      child: ListTile(
        onTap: onTap,
        title: Text(
          '#${tag.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          '${tag.postCount} postingan',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _HashtagLoadingRow extends StatelessWidget {
  final bool darkTheme;

  const _HashtagLoadingRow({required this.darkTheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: darkTheme ? Colors.white70 : const Color(0xFF0B7FEA),
          ),
        ),
      ),
    );
  }
}
