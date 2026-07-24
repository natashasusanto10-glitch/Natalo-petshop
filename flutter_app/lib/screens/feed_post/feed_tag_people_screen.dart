import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/new_post_user_tag.dart';
import '../../services/api_client.dart';
import '../../theme/natalo_colors.dart';
import '../../utils/haptics.dart';
import '../../utils/motion_prefs.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/feed_user_tag_pill.dart';
import '../../widgets/profile_avatar.dart';

const _kMaxTags = 20;

/// Hasil pencarian akun untuk picker — subset field /api/users/search.
class TagSearchUser {
  final String id;
  final String username;
  final String name;
  final String? profilePhotoUrl;
  const TagSearchUser({
    required this.id,
    required this.username,
    this.name = '',
    this.profilePhotoUrl,
  });
}

typedef TagUserSearchFn = Future<List<TagSearchUser>> Function(
  String query, {
  bool suggested,
});

/// Default: GET /api/users/search?q=..&limit=8 / ?suggested=1 (pra-ketik).
Future<List<TagSearchUser>> defaultTagUserSearch(
  String query, {
  bool suggested = false,
}) async {
  final data = await apiClient.getJson(
    '/api/users/search',
    query: suggested && query.isEmpty
        ? {'suggested': '1', 'limit': '8'}
        : {'q': query, 'limit': '8'},
  );
  return parseTagSearchUsers(data);
}

/// Parse body /api/users/search → daftar akun untuk picker tag.
///
/// Backend membalikkan `{ items: [...] }` (sama seperti mention_picker &
/// follow_service). Sebelumnya kode di sini baca `data['users']` yang tidak
/// pernah ada → hasil SELALU kosong saat menandai orang. Diekstrak jadi
/// fungsi murni supaya kontrak key-nya bisa diuji regresi tanpa jaringan.
@visibleForTesting
List<TagSearchUser> parseTagSearchUsers(dynamic data) {
  final users = (data is Map ? data['items'] as List? : null) ?? const [];
  return users
      .whereType<Map>()
      .map((raw) {
        final u = Map<String, dynamic>.from(raw);
        return TagSearchUser(
          id: (u['id'] as String?) ?? '',
          username: (u['username'] as String?) ?? '',
          name: (u['name'] as String?) ?? '',
          profilePhotoUrl: u['profilePhotoUrl'] as String?,
        );
      })
      .where((u) => u.id.isNotEmpty)
      .toList();
}

/// Layar penempatan tag orang di FOTO (Spec B). Ketuk foto → pilih akun via
/// panel pencarian → pill ditancapkan di titik ketuk (koordinat pecahan
/// 0-1, per-foto lewat `mediaIndex`). Pill bisa digeser; tap pill membuka
/// tombol X untuk menghapus. Maksimal `_kMaxTags` tag per postingan.
class FeedTagPeopleScreen extends StatefulWidget {
  final List<File> photoFiles;
  final List<NewPostUserTag> initialTags;
  final TagUserSearchFn searchUsers;

  const FeedTagPeopleScreen({
    super.key,
    required this.photoFiles,
    this.initialTags = const [],
    this.searchUsers = defaultTagUserSearch,
  });

  @override
  State<FeedTagPeopleScreen> createState() => _FeedTagPeopleScreenState();
}

class _FeedTagPeopleScreenState extends State<FeedTagPeopleScreen> {
  late List<NewPostUserTag> _tags = [...widget.initialTags];
  int _pageIndex = 0;
  String? _revealRemoveUserId;
  late final PageController _pageController =
      PageController(initialPage: _pageIndex);

  // Aspect ratio ASLI tiap foto (width/height), keyed by index di
  // widget.photoFiles (final review Spec B fix — koordinat tag drift).
  // Dipakai fittedPhotoRect supaya fraksi tag dihitung relatif area FOTO
  // yang benar-benar ter-render (BoxFit.contain bisa letterbox kalau
  // aspect ratio foto != container), bukan container mentah. Di-load async
  // per file via ui.instantiateImageCodec (native, ~50ms — pola sama
  // dengan feed_media_picker_screen.dart _loadPreviewImageSize). Entry
  // absen (masih loading / gagal decode) → fallback ke aspect container
  // sendiri di build() (rect = container penuh, setara perilaku lama).
  final Map<int, double> _photoAspectRatios = {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadPhotoAspectRatios());
  }

  Future<void> _loadPhotoAspectRatios() async {
    for (var i = 0; i < widget.photoFiles.length; i++) {
      try {
        final bytes = await widget.photoFiles[i].readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final ratio = frame.image.width / frame.image.height;
        frame.image.dispose();
        if (!mounted) return;
        setState(() => _photoAspectRatios[i] = ratio);
      } catch (_) {
        // Biarkan tanpa entry — fallback ke aspect container di build().
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onPhotoTapUp(TapUpDetails details, Rect photoRect) async {
    if (_tags.length >= _kMaxTags) {
      AppToast.show(
        context,
        'Maksimal 20 orang per postingan.',
        kind: ToastKind.info,
      );
      return;
    }
    if (photoRect.width <= 0 || photoRect.height <= 0) return;
    final local = details.localPosition;
    // Fraksi relatif FOTO (photoRect), bukan container mentah — supaya tap
    // di area letterbox tetap clamp ke tepi foto terdekat, bukan salah
    // posisi relatif ke seluruh container.
    final fx = ((local.dx - photoRect.left) / photoRect.width).clamp(0.0, 1.0);
    final fy = ((local.dy - photoRect.top) / photoRect.height).clamp(0.0, 1.0);
    setState(() => _revealRemoveUserId = null);
    final picked = await Navigator.of(context).push<TagSearchUser>(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) =>
            TagUserSearchPanel(searchUsers: widget.searchUsers),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final existingIndex =
          _tags.indexWhere((t) => t.userId == picked.id);
      if (existingIndex != -1) {
        _tags[existingIndex] = _tags[existingIndex].copyWith(
          mediaIndex: _pageIndex,
          x: fx,
          y: fy,
        );
      } else {
        _tags = [
          ..._tags,
          NewPostUserTag(
            userId: picked.id,
            username: picked.username,
            name: picked.name,
            profilePhotoUrl: picked.profilePhotoUrl,
            mediaIndex: _pageIndex,
            x: fx,
            y: fy,
          ),
        ];
      }
    });
    AppHaptics.tap();
  }

  void _onPillDragUpdate(
    NewPostUserTag tag,
    DragUpdateDetails details,
    Rect photoRect,
  ) {
    if (photoRect.width <= 0 || photoRect.height <= 0) return;
    final index = _tags.indexWhere((t) => t.userId == tag.userId);
    if (index == -1) return;
    final current = _tags[index];
    // Pixel delta (details.delta) berlaku sama di koordinat container ATAU
    // photoRect (translasi murni tak mengubah delta) — konversi ke fraksi
    // tetap harus relatif photoRect, bukan container mentah.
    final currentPx = Offset(
      photoRect.left + (current.x ?? 0.5) * photoRect.width,
      photoRect.top + (current.y ?? 0.5) * photoRect.height,
    );
    final nextPx = currentPx + details.delta;
    final nx = (nextPx.dx - photoRect.left) / photoRect.width;
    final ny = (nextPx.dy - photoRect.top) / photoRect.height;
    setState(() {
      _tags[index] = current.copyWith(
        x: nx.clamp(0.0, 1.0),
        y: ny.clamp(0.0, 1.0),
      );
    });
  }

  void _onPillTap(NewPostUserTag tag) {
    setState(() {
      _revealRemoveUserId =
          _revealRemoveUserId == tag.userId ? null : tag.userId;
    });
  }

  void _onPillRemove(NewPostUserTag tag) {
    AppHaptics.tap();
    setState(() {
      _tags = _tags.where((t) => t.userId != tag.userId).toList();
      if (_revealRemoveUserId == tag.userId) _revealRemoveUserId = null;
    });
  }

  void _onDone() {
    Navigator.of(context).pop(List<NewPostUserTag>.of(_tags));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // elevation + surfaceTint 0/transparan: hilangkan garis putih tipis
        // (Material 3 menggambar tint/divider di bawah app bar di atas body
        // hitam) — lihat screenshot device.
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        // appBarTheme global set `shape` (hairline border) untuk header
        // putih di seluruh app — TIDAK ikut ke-null-kan oleh elevation/
        // surfaceTint di atas. Wajib override eksplisit di sini, atau
        // hairline itu tetap tampil sebagai garis terang di layar hitam ini.
        shape: const Border(),
        centerTitle: true,
        // Back bawaan tenggelam di app bar hitam (feedback device: "tombol
        // back tidak terlihat"). Ganti bubble kaca putih tipis — konsisten
        // dgn bubble centang di kanan.
        leadingWidth: 56,
        leading: Center(
          child: Semantics(
            button: true,
            label: 'Kembali',
            child: GestureDetector(
              onTap: () => Navigator.maybePop(context),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ),
        ),
        // appBarTheme global set titleTextStyle dengan warna eksplisit
        // (untuk header putih) — warna itu MENANG atas `foregroundColor`
        // di atas untuk Text judul, jadi harus di-override di sini juga
        // supaya judul putih benar-benar terbaca di latar hitam.
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        title: const Text('Tandai Orang'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Semantics(
                button: true,
                label: 'Selesai menandai',
                child: GestureDetector(
                  onTap: _onDone,
                  behavior: HitTestBehavior.opaque,
                  // Hit target 44dp (checklist tap-target) — lingkaran
                  // visual tetap 36px, ter-pusat (audit polish lanjutan).
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: NataloColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.photoFiles.length,
                  onPageChanged: (i) => setState(() => _pageIndex = i),
                  itemBuilder: (context, index) {
                    return _TaggablePhotoPage(
                      file: widget.photoFiles[index],
                      tags: _tags.where((t) => t.mediaIndex == index).toList(),
                      revealRemoveUserId: _revealRemoveUserId,
                      photoAspectRatio: _photoAspectRatios[index],
                      onTapUp: _onPhotoTapUp,
                      onPillDragUpdate: _onPillDragUpdate,
                      onPillTap: _onPillTap,
                      onPillRemove: _onPillRemove,
                    );
                  },
                ),
              ),
              // Ruang bawah untuk dots + hint pill mengambang.
              SizedBox(height: widget.photoFiles.length > 1 ? 60 : 48),
            ],
          ),
          // Dots carousel (multi-foto) — mengambang di atas hint pill.
          if (widget.photoFiles.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 58,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.photoFiles.length, (i) {
                  final active = i == _pageIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 7 : 5.5,
                    height: active ? 7 : 5.5,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
          // Hint pill mengambang di tengah-bawah foto (bukan teks abu redup di
          // paling bawah). Sembunyi kalau slide aktif sudah punya tag —
          // guidance tak perlu lagi. IgnorePointer: tap tetap tembus ke foto.
          if (!_tags.any((t) => t.mediaIndex == _pageIndex))
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app_outlined,
                            color: Colors.white, size: 15),
                        SizedBox(width: 6),
                        Text(
                          'Ketuk foto untuk menandai',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TaggablePhotoPage extends StatelessWidget {
  final File file;
  final List<NewPostUserTag> tags;
  final String? revealRemoveUserId;
  // Aspect ratio ASLI foto (width/height) — null selama masih loading /
  // gagal decode, fallback ke aspect container sendiri (final review
  // Spec B fix, lihat _photoAspectRatios di parent state).
  final double? photoAspectRatio;
  final Future<void> Function(TapUpDetails details, Rect photoRect) onTapUp;
  final void Function(
      NewPostUserTag tag, DragUpdateDetails details, Rect photoRect)
      onPillDragUpdate;
  final void Function(NewPostUserTag tag) onPillTap;
  final void Function(NewPostUserTag tag) onPillRemove;

  const _TaggablePhotoPage({
    required this.file,
    required this.tags,
    required this.revealRemoveUserId,
    required this.photoAspectRatio,
    required this.onTapUp,
    required this.onPillDragUpdate,
    required this.onPillTap,
    required this.onPillRemove,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final renderSize =
            Size(constraints.maxWidth, constraints.maxHeight);
        // Rect area yang BENAR-BENAR ditempati foto di dalam renderSize
        // (Image.file di bawah pakai BoxFit.contain juga) — kalau aspect
        // ratio foto belum diketahui (masih loading/gagal), fallback ke
        // aspect container sendiri (fittedPhotoRect jadi no-op, setara
        // perilaku lama).
        final containerAspect = renderSize.height > 0
            ? renderSize.width / renderSize.height
            : 1.0;
        final effectiveAspect =
            (photoAspectRatio != null && photoAspectRatio!.isFinite && photoAspectRatio! > 0)
                ? photoAspectRatio!
                : containerAspect;
        final photoRect =
            fittedPhotoRect(renderSize, effectiveAspect, BoxFit.contain);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => onTapUp(details, photoRect),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // RepaintBoundary — isolasi layer foto supaya setState per-frame
              // saat pill di-drag tidak ikut me-repaint bitmap foto (audit
              // polish Spec B: sumber jank saat geser tag).
              RepaintBoundary(
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => Container(
                    color: Colors.grey.shade900,
                    alignment: Alignment.center,
                    child: const Icon(Icons.image_not_supported_outlined,
                        color: Colors.white38, size: 40),
                  ),
                ),
              ),
              // Layer pill dibungkus Positioned sesuai photoRect — anchor
              // tag & clamp placeTagPill (via _TagPillOverlay) jadi relatif
              // FOTO, bukan container (letterbox bar tidak dianggap "dalam
              // foto").
              Positioned(
                left: photoRect.left,
                top: photoRect.top,
                width: photoRect.width,
                height: photoRect.height,
                child: Stack(
                  children: [
                    for (final tag in tags)
                      _TagPillOverlay(
                        key: ValueKey(tag.userId),
                        tag: tag,
                        renderSize: photoRect.size,
                        showRemove: revealRemoveUserId == tag.userId,
                        onDragUpdate: (details) =>
                            onPillDragUpdate(tag, details, photoRect),
                        onTap: () => onPillTap(tag),
                        onRemove: () => onPillRemove(tag),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TagPillOverlay extends StatelessWidget {
  final NewPostUserTag tag;
  final Size renderSize;
  final bool showRemove;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _TagPillOverlay({
    super.key,
    required this.tag,
    required this.renderSize,
    required this.showRemove,
    required this.onDragUpdate,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (renderSize.width <= 0 || renderSize.height <= 0) {
      return const SizedBox.shrink();
    }
    final anchor = Offset(
      (tag.x ?? 0.5) * renderSize.width,
      (tag.y ?? 0.5) * renderSize.height,
    );
    final textPainter = TextPainter(
      text: TextSpan(
        text: tag.username,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final pillWidth =
        textPainter.width + 20 + (showRemove ? 28 : 0); // padding + close(24+gap)
    const pillHeight = 28.0;
    final pillSize = Size(pillWidth, pillHeight);
    final placement = placeTagPill(
      anchor: anchor,
      pillSize: pillSize,
      photoSize: renderSize,
    );
    final pill = FeedUserTagPill(
      username: tag.username,
      arrowBelow: placement.arrowBelow,
      showRemove: showRemove,
      onTap: onTap,
      onRemove: onRemove,
    );
    return Positioned(
      left: placement.topLeft.dx,
      top: placement.topLeft.dy,
      child: GestureDetector(
        onPanStart: (_) => AppHaptics.tap(),
        onPanUpdate: onDragUpdate,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          // Reduced-motion (OS atau toggle Settings) → animasi pop di-skip,
          // pill langsung tampil final (audit polish Spec B lanjutan).
          duration:
              MotionPrefs.effective(context, const Duration(milliseconds: 220)),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => Opacity(
            opacity: v.clamp(0, 1),
            child: Transform.scale(scale: v, child: child),
          ),
          child: pill,
        ),
      ),
    );
  }
}

/// Panel pencarian akun fullscreen ala `feed_user_search_screen.dart` —
/// saran akun tampil SEBELUM user mengetik (`suggested=1`), debounce 300ms
/// saat mengetik.
///
/// Dipakai bersama oleh varian foto ([FeedTagPeopleScreen]) dan video
/// ([FeedTagPeopleVideoScreen]) — jangan buat salinan lain.
class TagUserSearchPanel extends StatefulWidget {
  final TagUserSearchFn searchUsers;
  const TagUserSearchPanel({super.key, required this.searchUsers});

  @override
  State<TagUserSearchPanel> createState() => _TagUserSearchPanelState();
}

class _TagUserSearchPanelState extends State<TagUserSearchPanel> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<TagSearchUser> _results = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSuggested();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSuggested() async {
    setState(() => _loading = true);
    try {
      final users = await widget.searchUsers('', suggested: true);
      if (!mounted) return;
      setState(() => _results = users);
    } catch (_) {
      if (!mounted) return;
      setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged() {
    _debounce?.cancel();
    final query = _controller.text.trim();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(query);
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() => _loading = true);
    try {
      final users = query.isEmpty
          ? await widget.searchUsers('', suggested: true)
          : await widget.searchUsers(query);
      if (!mounted) return;
      setState(() => _results = users);
    } catch (_) {
      if (!mounted) return;
      setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: NataloColors.surfaceVariantDark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        // filled:false + fillColor transparan WAJIB: tema global
                        // (inputDecorationTheme) set `filled:true` + fillColor
                        // PUTIH di light mode → tanpa override ini, TextField
                        // mengecat putih di atas Container navy = teks putih di
                        // atas putih (tak terbaca). Container gelap di belakang
                        // yang jadi latar field.
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          hintText: 'Cari akun',
                          hintStyle:
                              TextStyle(color: NataloColors.feedTextMuted),
                          prefixIcon: Icon(Icons.search,
                              color: NataloColors.feedTextMuted),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Batal',
                          style: TextStyle(color: Colors.white, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading && _results.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final u = _results[index];
                        return ListTile(
                          leading: ProfileAvatar(
                            initial: u.username.isNotEmpty
                                ? u.username[0].toUpperCase()
                                : '?',
                            imageUrl: u.profilePhotoUrl,
                            size: 40,
                            fontSize: 14,
                            plain: true,
                          ),
                          title: Text(u.username,
                              style: const TextStyle(color: Colors.white)),
                          subtitle: u.name.isNotEmpty
                              ? Text(u.name,
                                  style: const TextStyle(
                                      color: NataloColors.feedTextMuted))
                              : null,
                          onTap: () => Navigator.of(context).pop(u),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
