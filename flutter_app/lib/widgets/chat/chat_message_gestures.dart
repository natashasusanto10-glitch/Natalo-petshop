import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/natalo_colors.dart';

/// Gestur pesan chat customer Natalo — PORT dari chat internal NLCATTER
/// (`swipe_to_reply.dart` + `message_actions.dart`) supaya perilaku "sama
/// persis" di kedua app, hanya token warna disesuaikan ke [NataloColors].
///
/// Berisi:
/// - [ChatSwipeToReply] — geser bubble ke kanan sedikit untuk membalas (ala WA).
/// - [showChatMessageActions] — long-press → menu Salin/Balas ala WA.

/// Geser bubble ke kanan sedikit untuk membalas — ala WhatsApp. Gerakan
/// diredam (rubber-band, maks [_maxDrag] px) lalu snap balik; memicu balas
/// begitu geseran melewati [_trigger] px.
class ChatSwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;
  const ChatSwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  @override
  State<ChatSwipeToReply> createState() => _ChatSwipeToReplyState();
}

class _ChatSwipeToReplyState extends State<ChatSwipeToReply>
    with SingleTickerProviderStateMixin {
  static const double _softCap = 48;
  static const double _maxDrag = 72;
  static const double _trigger = 40;
  static const double _slop = 6;
  static const double _edgeZone = 28;

  double _raw = 0;
  double _offset = 0;
  bool _fired = false;

  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onStart(DragStartDetails d) {
    _ctl.stop();
    _raw = 0;
    _offset = 0;
    _fired = false;
  }

  void _onUpdate(DragUpdateDetails d) {
    _raw = (_raw + d.delta.dx).clamp(0, double.infinity);
    final eff = _raw - _slop;
    final double o = eff <= 0
        ? 0
        : eff <= _softCap
            ? eff
            : _softCap + (eff - _softCap) * 0.3;
    setState(() => _offset = o.clamp(0, _maxDrag));
    if (!_fired && _offset >= _trigger) {
      _fired = true;
      HapticFeedback.selectionClick();
    }
  }

  void _onEnd(DragEndDetails d) {
    if (_fired) widget.onReply();
    _animateBack();
  }

  void _onCancel() => _animateBack();

  void _animateBack() {
    final from = _offset;
    if (from <= 0) {
      _raw = 0;
      _fired = false;
      return;
    }
    _ctl.reset();
    final anim = Tween<double>(begin: from, end: 0)
        .animate(CurvedAnimation(parent: _ctl, curve: Curves.easeOut));
    void listener() => setState(() => _offset = anim.value);
    anim.addListener(listener);
    _ctl.forward().whenComplete(() {
      anim.removeListener(listener);
      _raw = 0;
      _fired = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final progress = (_offset / _trigger).clamp(0.0, 1.0);
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _EdgeAwareHDrag: GestureRecognizerFactoryWithHandlers<_EdgeAwareHDrag>(
          () => _EdgeAwareHDrag(edgeZone: _edgeZone),
          (r) => r
            ..onStart = _onStart
            ..onUpdate = _onUpdate
            ..onEnd = _onEnd
            ..onCancel = _onCancel,
        ),
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (_offset > 1)
            Positioned(
              left: 16,
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * progress,
                  child: const Icon(Icons.reply_rounded,
                      color: NataloColors.primary, size: 24),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_offset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// HorizontalDrag yang tidak ikut arena bila sentuhan dimulai dalam [edgeZone]
/// px dari tepi kiri — supaya gesture "kembali" (swipe-back iOS) menang.
class _EdgeAwareHDrag extends HorizontalDragGestureRecognizer {
  _EdgeAwareHDrag({required this.edgeZone});
  final double edgeZone;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (event.position.dx <= edgeZone) return;
    super.addAllowedPointer(event);
  }
}

/// Satu aksi pada menu konteks pesan.
class ChatMsgAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const ChatMsgAction(this.icon, this.label, this.onTap,
      {this.danger = false});
}

/// Menu aksi pesan ala WhatsApp: latar di-dim dengan "lubang" di posisi bubble
/// (bubble asli tetap terang), kartu menu di bawah/atas bubble. [anchorKey] =
/// GlobalKey bubble. [mine] menentukan sisi (kanan untuk pesan sendiri).
Future<void> showChatMessageActions({
  required BuildContext context,
  required GlobalKey anchorKey,
  required bool mine,
  required List<ChatMsgAction> actions,
}) async {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.attached) return;
  final topLeft = box.localToGlobal(Offset.zero);
  final rect = topLeft & box.size;
  HapticFeedback.mediumImpact();

  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, anim, _) => _ChatActionsLayer(
        anim: anim,
        rect: rect,
        mine: mine,
        actions: actions,
      ),
      transitionsBuilder: (_, anim, __, child) => child,
    ),
  );
}

class _ChatActionsLayer extends StatelessWidget {
  final Animation<double> anim;
  final Rect rect;
  final bool mine;
  final List<ChatMsgAction> actions;
  const _ChatActionsLayer({
    required this.anim,
    required this.rect,
    required this.mine,
    required this.actions,
  });

  static const double _gap = 8;
  static const double _itemH = 48;
  static const double _menuW = 220;
  static const double _edge = 10;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final safeTop = media.padding.top + _edge;
    final safeBottom = screen.height - media.padding.bottom - _edge;

    final aboveSpace = (rect.top - safeTop).clamp(0.0, screen.height);
    final belowSpace = (safeBottom - rect.bottom).clamp(0.0, screen.height);
    final fullMenuH = actions.length * _itemH + 12;

    final menuAbove = aboveSpace > belowSpace;
    final menuSide = ((menuAbove ? aboveSpace : belowSpace) - _gap)
        .clamp(0.0, double.infinity);
    final menuMaxH = menuSide.clamp(80.0, fullMenuH);

    double clampLeft(double w) {
      final raw = mine ? rect.right - w : rect.left;
      final maxLeft = (screen.width - _edge - w).clamp(_edge, double.infinity);
      return raw.clamp(_edge, maxLeft);
    }

    final card = _ScaleFade(
      anim: anim,
      alignEnd: mine,
      child: _MenuCard(actions: actions, maxHeight: menuMaxH, width: _menuW),
    );

    final Widget menuPositioned = menuAbove
        ? Positioned(
            bottom: (screen.height - (rect.top - _gap))
                .clamp(_edge, double.infinity),
            left: clampLeft(_menuW),
            child: card,
          )
        : Positioned(
            top: (rect.bottom + _gap).clamp(safeTop, safeBottom - 1),
            left: clampLeft(_menuW),
            child: card,
          );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: FadeTransition(
              opacity: anim,
              child: CustomPaint(
                painter: _SpotlightPainter(rect: rect),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        menuPositioned,
      ],
    );
  }
}

/// Dim seluruh layar kecuali area [rect] (rounded) — bubble asli tampil terang.
class _SpotlightPainter extends CustomPainter {
  final Rect rect;
  _SpotlightPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(
          rect.inflate(2), const Radius.circular(12)));
    final dimmed = Path.combine(PathOperation.difference, bg, hole);
    canvas.drawPath(
        dimmed, Paint()..color = Colors.black.withValues(alpha: 0.45));
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.rect != rect;
}

class _ScaleFade extends StatelessWidget {
  final Animation<double> anim;
  final bool alignEnd;
  final Widget child;
  const _ScaleFade(
      {required this.anim, required this.alignEnd, required this.child});

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
    return FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
        alignment: alignEnd ? Alignment.topRight : Alignment.topLeft,
        child: child,
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<ChatMsgAction> actions;
  final double maxHeight;
  final double width;
  const _MenuCard(
      {required this.actions, required this.maxHeight, required this.width});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NataloColors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: width),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: actions.map((a) {
              final c = a.danger ? NataloColors.danger : NataloColors.textPrimary;
              return InkWell(
                onTap: () {
                  Navigator.of(context).maybePop();
                  a.onTap();
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      Icon(a.icon,
                          size: 20,
                          color: a.danger
                              ? NataloColors.danger
                              : NataloColors.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(a.label,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: c)),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
