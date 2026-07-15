import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../utils/haptics.dart';
import 'profile_avatar.dart';
import '../constants/official_brand.dart';

/// User suggestion entry untuk @mention picker. Subset dari User model
/// yang dibalikin /api/users/search?q=.
class MentionUser {
  final String id;
  final String name;
  final String username;
  final String? profilePhotoUrl;

  /// Akun admin = brand "Natalo Petshop" + badge official. Saat true,
  /// picker tampil brand (bukan nama/username personal). Konsisten dgn
  /// FeedAuthor.displayName di feed.
  final bool isOfficial;

  const MentionUser({
    required this.id,
    required this.name,
    required this.username,
    this.profilePhotoUrl,
    this.isOfficial = false,
  });

  /// Nama tampil di picker — brand untuk admin, nama personal untuk user.
  String get displayLabel => isOfficial ? kOfficialBrandName : name;

  factory MentionUser.fromJson(Map<String, dynamic> json) {
    return MentionUser(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      profilePhotoUrl:
          (json['profilePhotoUrl'] as String?)?.trim().isNotEmpty == true
              ? json['profilePhotoUrl'] as String
              : null,
      isOfficial: json['isOfficial'] == true,
    );
  }
}

/// Detection result dari current cursor position di text. Berisi info
/// query yang lagi diketik (kalau ada `@partial`), plus range index
/// supaya replace handle smooth saat user pick.
class _MentionQuery {
  /// Query string (lowercased, tanpa `@`), e.g. "as" untuk text
  /// "halo @as|" (cursor di posisi |).
  final String query;

  /// Index awal `@` di full text — buat replace range.
  final int start;

  /// Index akhir query (= cursor position).
  final int end;

  const _MentionQuery({
    required this.query,
    required this.start,
    required this.end,
  });
}

/// Controller untuk mention detection + suggestion fetch. Tidak punya
/// UI sendiri — paired dengan MentionSuggestionsPanel buat render.
///
/// Setup: parent attach controller ke TextEditingController dengan
/// `attach()`. Saat user ketik `@`, controller mulai polling search
/// endpoint (debounced 200ms). Hasil di-expose via `suggestions`
/// notifier. Saat user tap entry, panggil `insertMention(user)`
/// yang replace `@partial` jadi `@username ` di TextEditingController.
class MentionPickerController extends ChangeNotifier {
  final TextEditingController textController;
  Timer? _debounce;
  String _lastQuery = '';
  List<MentionUser> _suggestions = const [];
  bool _loading = false;
  _MentionQuery? _activeQuery;

  MentionPickerController({required this.textController}) {
    textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    textController.removeListener(_onTextChanged);
    super.dispose();
  }

  List<MentionUser> get suggestions => _suggestions;
  bool get isActive => _activeQuery != null;
  bool get isLoading => _loading;

  /// Parse current cursor position untuk detect `@partial` di word
  /// yang sedang diketik. Return null kalau:
  ///   - Cursor tidak punya selection / di -1
  ///   - Char di posisi `@` bukan start-of-string atau didahului
  ///     whitespace/punctuation (anti email `name@domain.com`)
  ///   - Query > 30 char (limit username)
  ///   - Query mengandung whitespace (user udah selesai mention)
  _MentionQuery? _detectMention() {
    final selection = textController.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final cursorPos = selection.start;
    if (cursorPos <= 0) return null;
    final text = textController.text;
    if (cursorPos > text.length) return null;

    // Walk back from cursor untuk cari `@` start. Stop kalau ketemu
    // whitespace/newline → ga di dalam mention.
    int startIdx = -1;
    for (int i = cursorPos - 1; i >= 0; i--) {
      final c = text[i];
      if (c == '@') {
        startIdx = i;
        break;
      }
      // Hanya allowed chars dalam mention: a-z 0-9 _ . dan uppercase
      // (user mungkin ketik kapital, kita lowercase saat search).
      if (!RegExp(r'[a-zA-Z0-9_.]').hasMatch(c)) {
        return null;
      }
    }
    if (startIdx < 0) return null;
    // Cek char SEBELUM `@` — harus boundary (start, whitespace, atau
    // punctuation umum). Anti email: `nama@domain` → @ didahului `a`
    // (huruf) → skip.
    if (startIdx > 0) {
      final prev = text[startIdx - 1];
      if (!RegExp(r'[\s\n.,!?;:()\[\]{}"“”‘’]').hasMatch(prev)) {
        return null;
      }
    }
    final query = text.substring(startIdx + 1, cursorPos).toLowerCase();
    if (query.length > 30) return null;
    if (RegExp(r'\s').hasMatch(query)) return null;
    return _MentionQuery(query: query, start: startIdx, end: cursorPos);
  }

  void _onTextChanged() {
    final detected = _detectMention();
    if (detected == null) {
      // Exit mention mode.
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
    // Empty query — hide panel sampai user mulai ketik karakter.
    // (Beda dari IG: IG show "recent" kalau cuma `@` — defer dulu untuk
    // simplicity. Add later kalau perlu).
    if (detected.query.isEmpty) {
      _suggestions = const [];
      _loading = false;
      notifyListeners();
      return;
    }
    if (detected.query == _lastQuery) {
      notifyListeners();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _runSearch(detected.query);
    });
  }

  Future<void> _runSearch(String q) async {
    if (q.isEmpty) return;
    _lastQuery = q;
    _loading = true;
    notifyListeners();
    try {
      final data = await apiClient.getJson(
        '/api/users/search',
        query: {'q': q, 'limit': '8'},
        timeout: const Duration(seconds: 4),
      );
      // Race guard — kalau query udah ganti antara, abaikan hasil.
      if (_lastQuery != q) return;
      if (data is Map<String, dynamic>) {
        final items = data['items'];
        if (items is List) {
          _suggestions = items
              .whereType<Map<String, dynamic>>()
              .map(MentionUser.fromJson)
              .where((u) => u.username.isNotEmpty)
              .toList();
        } else {
          _suggestions = const [];
        }
      } else {
        _suggestions = const [];
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[mention] search error: $e');
      _suggestions = const [];
    } finally {
      _loading = false;
      if (_lastQuery == q) notifyListeners();
    }
  }

  /// Insert pilihan user ke TextField. Replace range [@partial] dengan
  /// `@username ` (trailing space supaya user langsung lanjut ketik).
  /// Move cursor ke setelah space.
  void insertMention(MentionUser user) {
    final active = _activeQuery;
    if (active == null) return;
    AppHaptics.tap();
    HapticFeedback.selectionClick();
    final text = textController.text;
    final before = text.substring(0, active.start);
    final after = text.substring(active.end);
    final inserted = '@${user.username} ';
    final newText = '$before$inserted$after';
    final newOffset = before.length + inserted.length;
    textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
    // _onTextChanged akan fire dari setValue → mention exit naturally
    // (cursor di space, bukan di handle char) → panel auto-hide.
  }
}

/// Render panel suggestions di atas TextField. Listen ke controller.
/// Auto-hide kalau controller.suggestions kosong + tidak loading.
class MentionSuggestionsPanel extends StatelessWidget {
  final MentionPickerController controller;

  /// Dark theme prop — comment sheet pakai dark, caption editor light.
  final bool darkTheme;

  /// Max height panel. Default 220 — kira-kira 4-5 entry visible
  /// sebelum scroll.
  final double maxHeight;

  const MentionSuggestionsPanel({
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
              ? _LoadingRow(darkTheme: darkTheme)
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: controller.suggestions.length,
                  itemBuilder: (context, idx) {
                    final user = controller.suggestions[idx];
                    return _SuggestionTile(
                      user: user,
                      darkTheme: darkTheme,
                      onTap: () => controller.insertMention(user),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final MentionUser user;
  final bool darkTheme;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.user,
    required this.darkTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = darkTheme ? Colors.white : const Color(0xFF0F172A);
    final textMuted = darkTheme
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ProfileAvatar(
              initial: user.displayLabel.trim().isEmpty
                  ? 'N'
                  : user.displayLabel.trim()[0].toUpperCase(),
              imageUrl: user.profilePhotoUrl,
              size: 32,
              fontSize: 13,
              isOfficial: user.isOfficial,
              plain: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Admin = brand "Natalo Petshop" + badge official (primary),
                  // username sebagai secondary supaya user tahu handle yg
                  // di-insert. User biasa: IG pattern — username primary,
                  // nama secondary.
                  if (user.isOfficial) ...[
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 15,
                          color: Color(0xFF0B7FEA),
                        ),
                      ],
                    ),
                    if (user.username.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        '@${user.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ] else ...[
                    // IG pattern: suggestion row tampil bare `username`.
                    // `@` cuma muncul setelah user tap → insertMention()
                    // yang prepend `@` saat inject ke TextField.
                    Text(
                      user.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (user.name.isNotEmpty && user.name != user.username) ...[
                      const SizedBox(height: 1),
                      Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  final bool darkTheme;

  const _LoadingRow({required this.darkTheme});

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
