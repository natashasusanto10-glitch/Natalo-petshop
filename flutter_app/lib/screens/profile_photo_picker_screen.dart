// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/collapsing_header_delegate.dart';
import '../widgets/photo_crop/photo_crop_export.dart';
import '../widgets/photo_crop/photo_crop_preview.dart';
import '../widgets/photo_crop/photo_crop_transform.dart';

const _bgBlack = Color(0xFF000000);
const _natoloBlue = NataloColors.primary;
const _textWhite = Color(0xFFFFFFFF);
const _textMuted = Color(0xFF9CA3AF);
const _tileBg = Color(0xFF1F2937);

/// Full-screen photo picker khusus foto profil — Instagram-style.
///
/// Grid galeri (`photo_manager`) single-select foto saja, di atasnya preview
/// crop persegi dengan mask lingkaran yang bisa di-pinch/geser (engine bersama
/// [PhotoCropPreview]). Preview meng-collapse jadi thumbnail bulat kecil saat
/// grid di-scroll (delegate bersama [CollapsingHeaderDelegate], PINNED).
///
/// [open] mengembalikan `File` JPEG persegi hasil crop, atau null kalau user
/// batal. Upload + toast + error handling ditangani caller (sheet), bukan di
/// sini — screen ini murni pilih + crop.
class ProfilePhotoPickerScreen extends StatefulWidget {
  const ProfilePhotoPickerScreen({super.key});

  static Future<File?> open(BuildContext context) {
    return Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => const ProfilePhotoPickerScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<ProfilePhotoPickerScreen> createState() =>
      _ProfilePhotoPickerScreenState();
}

class _ProfilePhotoPickerScreenState extends State<ProfilePhotoPickerScreen> {
  static const int _maxLongSide = 1024; // sama dengan cap camera path.
  static const int _jpegQuality = 88;
  static const int _pageSize = 80;

  PermissionState? _permissionState;
  AssetPathEntity? _album;
  final List<AssetEntity> _assets = [];
  int _assetPage = 0;
  bool _hasMore = true;
  bool _loading = false;

  AssetEntity? _previewAsset;
  String? _previewPath;
  final Map<String, PhotoCropTransform> _transforms = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initPermissionAndLoad();
  }

  @override
  void dispose() {
    for (final t in _transforms.values) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _initPermissionAndLoad() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    setState(() => _permissionState = permission);
    if (!permission.isAuth && !permission.hasAccess) return;

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image, // foto saja (bukan video).
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    if (!mounted) return;
    if (albums.isEmpty) {
      setState(() => _album = null);
      return;
    }
    setState(() => _album = albums.first);
    await _loadMore(initial: true);
  }

  Future<void> _loadMore({bool initial = false}) async {
    if (_loading) return;
    final album = _album;
    if (album == null) return;
    if (!initial && !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await album.getAssetListPaged(
        page: _assetPage,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (initial) _assets.clear();
        _assets.addAll(page);
        _hasMore = page.length >= _pageSize;
        _assetPage += 1;
        _loading = false;
      });
      if (initial && _assets.isNotEmpty) {
        await _setPreview(_assets.first);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _setPreview(AssetEntity asset) async {
    final file = await asset.originFile;
    if (!mounted || file == null) return;
    setState(() {
      _previewAsset = asset;
      _previewPath = file.path;
    });
  }

  PhotoCropTransform _transformFor(String id) =>
      _transforms.putIfAbsent(id, PhotoCropTransform.new);

  Future<void> _onTapAsset(AssetEntity asset) async {
    if (_busy) return;
    AppHaptics.selection();
    await _setPreview(asset);
  }

  Future<void> _confirm() async {
    final asset = _previewAsset;
    final path = _previewPath;
    if (asset == null || path == null || _busy) return;
    AppHaptics.tap();
    setState(() => _busy = true);
    try {
      final tmpDir = await getTemporaryDirectory();
      final transform = _transformFor(asset.id);
      final args = PhotoProcessArgs(
        sourcePath: path,
        tmpDirPath: tmpDir.path,
        targetAspect: 1.0, // square avatar.
        scale: transform.scale,
        offsetFractionX: transform.offsetFraction.dx,
        offsetFractionY: transform.offsetFraction.dy,
        preserveOriginal: false,
        maxLongSide: _maxLongSide,
        jpegQuality: _jpegQuality,
        timestampSuffix: 0,
        pathSeparator: Platform.pathSeparator,
      );
      final outPath = await compute(processPhotoInIsolate, args);
      if (!mounted) return;
      Navigator.of(context).pop(File(outPath));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permission = _permissionState;
    return Scaffold(
      backgroundColor: _bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              canConfirm: _previewAsset != null && !_busy,
              onClose: () => Navigator.of(context).pop(),
              onConfirm: _confirm,
            ),
            if (permission == null)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: _natoloBlue,
                    strokeWidth: 2.4,
                  ),
                ),
              )
            else if (!permission.isAuth && !permission.hasAccess)
              const Expanded(child: _PermissionDeniedView())
            else
              Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    // Near-full-width (margin 12px kiri/kanan) supaya lingkaran crop sebesar
    // Instagram — 0.72 lama bikin foto terasa kecil & jauh (zoom-out) vs IG.
    final previewMax = screenW - 24;
    const vPad = 16.0;
    final maxHeight = previewMax + vPad * 2;
    const minHeight = 56.0 + vPad;

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: CollapsingHeaderDelegate(
            minHeight: minHeight,
            maxHeight: maxHeight,
            builder: (context, t) => _CollapsingPreview(
              t: t,
              previewMax: previewMax,
              file: _previewPath == null ? null : File(_previewPath!),
              transform: _previewAsset == null
                  ? null
                  : _transformFor(_previewAsset!.id),
            ),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
          sliver: SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Terbaru',
                style: TextStyle(
                  color: _textWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= _assets.length) {
                  if (_hasMore) _loadMore();
                  return const ColoredBox(color: _tileBg);
                }
                final asset = _assets[index];
                return _GalleryTile(
                  asset: asset,
                  active: asset.id == _previewAsset?.id,
                  onTap: () => _onTapAsset(asset),
                );
              },
              childCount: _assets.length + (_hasMore ? 8 : 0),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Collapsing preview (square + circular mask → small circle) ────────

class _CollapsingPreview extends StatelessWidget {
  final double t; // 0 expanded → 1 collapsed.
  final double previewMax;
  final File? file;
  final PhotoCropTransform? transform;

  const _CollapsingPreview({
    required this.t,
    required this.previewMax,
    required this.file,
    required this.transform,
  });

  @override
  Widget build(BuildContext context) {
    final dia = previewMax + (56.0 - previewMax) * t;
    // Mask fade + clip-to-circle selesai di t=0.3 supaya collapsed state
    // membaca sebagai avatar bulat polos, bukan kotak crop yang mengecil.
    final tt = (t / 0.3).clamp(0.0, 1.0);
    final content = file == null || transform == null
        ? const ColoredBox(
            color: _tileBg,
            child: Center(
              child: Icon(Icons.person_rounded, color: _textMuted, size: 64),
            ),
          )
        : Stack(
            fit: StackFit.expand,
            children: [
              PhotoCropPreview(
                file: file!,
                fitOriginal: false,
                cropTransform: transform!,
                overlayBuilder: (ctx, frame) => _CircleMask(
                  opacity: 1 - tt,
                ),
              ),
            ],
          );

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular((dia / 2) * tt),
        child: SizedBox(
          width: dia,
          height: dia,
          child: FittedBox(
            fit: BoxFit.fill,
            child: IgnorePointer(
              // Cropping hanya saat expanded penuh; saat collapse, sentuhan
              // preview diabaikan (scroll grid yang menggerakkan collapse).
              ignoring: t > 0.02,
              child: SizedBox(
                width: previewMax,
                height: previewMax,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Overlay: redupkan area di luar lingkaran + ring tipis di tepi lingkaran.
class _CircleMask extends StatelessWidget {
  final double opacity;
  const _CircleMask({required this.opacity});

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: CustomPaint(
          painter: _CircleMaskPainter(),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = Path()
      ..addOval(
        Rect.fromCircle(
          center: rect.center,
          radius: math.min(size.width, size.height) / 2,
        ),
      );
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      circle,
    );
    canvas.drawPath(
      outside,
      Paint()..color = _bgBlack.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _textWhite.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _CircleMaskPainter oldDelegate) => false;
}

// ─── Gallery tile ──────────────────────────────────────────────────────

class _GalleryTile extends StatefulWidget {
  final AssetEntity asset;
  final bool active;
  final VoidCallback onTap;

  const _GalleryTile({
    required this.asset,
    required this.active,
    required this.onTap,
  });

  @override
  State<_GalleryTile> createState() => _GalleryTileState();
}

class _GalleryTileState extends State<_GalleryTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(_GalleryTile old) {
    super.didUpdateWidget(old);
    if (old.asset.id != widget.asset.id) {
      _thumb = null;
      _loadThumb();
    }
  }

  Future<void> _loadThumb() async {
    final data =
        await widget.asset.thumbnailDataWithSize(const ThumbnailSize(220, 220));
    if (!mounted) return;
    setState(() => _thumb = data);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: _tileBg,
            child: _thumb == null
                ? const SizedBox.shrink()
                : Image.memory(
                    _thumb!,
                    fit: BoxFit.cover,
                    cacheWidth: 240,
                    gaplessPlayback: true,
                  ),
          ),
          if (widget.active)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: _natoloBlue, width: 3),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Header ────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool canConfirm;
  final VoidCallback onClose;
  final VoidCallback onConfirm;

  const _Header({
    required this.canConfirm,
    required this.onClose,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: 14),
          _CircleButton(
            icon: Icons.close_rounded,
            filled: false,
            onTap: onClose,
          ),
          const Expanded(
            child: Text(
              'Foto profil baru',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textWhite,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _CircleButton(
            icon: Icons.check_rounded,
            filled: canConfirm,
            onTap: canConfirm ? onConfirm : null,
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  const _CircleButton({
    required this.icon,
    required this.filled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: filled ? _natoloBlue : Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: filled
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Icon(
            icon,
            color: filled ? _textWhite : _textMuted,
            size: 19,
          ),
        ),
      ),
    );
  }
}

// ─── Permission denied ─────────────────────────────────────────────────

class _PermissionDeniedView extends StatelessWidget {
  const _PermissionDeniedView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_library_outlined, color: _textMuted, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Akses galeri ditolak',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textWhite,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Buka Pengaturan untuk izinkan akses foto supaya bisa memilih foto profil.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => PhotoManager.openSetting(),
            style: ElevatedButton.styleFrom(
              backgroundColor: _natoloBlue,
              foregroundColor: _textWhite,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Buka Pengaturan',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
