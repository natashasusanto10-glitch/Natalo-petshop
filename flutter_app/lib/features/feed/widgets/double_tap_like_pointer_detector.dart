import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Deteksi double-tap dari RAW pointer event, untuk kasus "double-tap like
/// saat PageView masih ballistic-settle sesudah swipe" (bug: user harus
/// mengetuk berkali-kali sebelum like masuk).
///
/// KENAPA tracker ini dipasang MEMBUNGKUS PageView (bukan di dalam tiap
/// halaman): selama settle, [ScrollableState] mengaktifkan
/// `IgnorePointer(ignoring: true)` atas SELURUH viewport
/// (`BallisticScrollActivity.shouldIgnorePointer == true`), sehingga
/// hit-test tidak pernah mencapai widget apa pun di dalam halaman —
/// termasuk [Listener] raw sekalipun. Ini bukan soal siapa menang arena,
/// tapi soal hit-test tidak pernah sampai ke sana sama sekali. Level di
/// ATAS Scrollable (ancestor) tetap menerima semua event pointer, jadi
/// tracker HARUS dipasang di situ, bukan di dalam tiap halaman.
///
/// Kriteria satu KETUKAN bersih: gerakan < [tapSlop] px sejak down, durasi
/// tekan < [maxTapDuration], dan hanya satu pointer aktif (pointer kedua yang
/// turun bersamaan = pinch-zoom → sequence batal). DOUBLE-tap: dua ketukan
/// bersih, down kedua ≤ [window] sejak UP pertama, dan jarak down kedua dari
/// down pertama ≤ [secondTapSlop].
///
/// Kelas ini murni logika (tanpa widget) supaya bisa diuji unit tanpa pump.
class RawDoubleTapTracker {
  RawDoubleTapTracker({
    this.window = const Duration(milliseconds: 300),
    this.tapSlop = 24,
    this.secondTapSlop = kDoubleTapSlop, // 100 — selaras arena Flutter
    this.maxTapDuration = const Duration(milliseconds: 250),
  });

  final Duration window;
  final double tapSlop;
  final double secondTapSlop;
  final Duration maxTapDuration;

  // Ketukan yang sedang berlangsung (down, belum up).
  int? _activePointer;
  Offset? _downPosition;
  Duration? _downTime;
  bool _movedPastSlop = false;
  bool _multiTouch = false;
  bool _downSettling = false;

  // Ketukan pertama yang sudah selesai (menunggu pasangan).
  Offset? _firstTapDown;
  Duration? _firstTapUpTime;
  bool _firstTapSettling = false;

  void onPointerDown(int pointer, Offset position, Duration timeStamp,
      {bool settling = false}) {
    if (_activePointer != null) {
      // Pointer kedua turun saat pertama masih ditekan → pinch/multi-touch.
      // Batalkan seluruh sequence; JANGAN jadikan salah satunya ketukan.
      _multiTouch = true;
      _firstTapDown = null;
      _firstTapUpTime = null;
      return;
    }
    _activePointer = pointer;
    _downPosition = position;
    _downTime = timeStamp;
    _movedPastSlop = false;
    _downSettling = settling;
    // Ketukan pertama basi (lewat jendela) → buang sebelum menilai yang baru.
    final firstUp = _firstTapUpTime;
    if (firstUp != null && timeStamp - firstUp > window) {
      _firstTapDown = null;
      _firstTapUpTime = null;
    }
  }

  void onPointerMove(int pointer, Offset position) {
    if (pointer != _activePointer || _movedPastSlop) return;
    final down = _downPosition;
    if (down != null && (position - down).distance > tapSlop) {
      _movedPastSlop = true;
    }
  }

  /// Return posisi (global) ketukan kedua + flag "ketukan pertama terjadi
  /// saat scroll settle" bila up ini MELENGKAPI double-tap; selain itu null.
  ({Offset position, bool firstTapSettling})? onPointerUp(
      int pointer, Offset position, Duration timeStamp) {
    if (pointer != _activePointer) {
      // Up milik pointer non-aktif (sisa multi-touch). Saat semua terangkat,
      // bersihkan flag supaya tap berikutnya mulai bersih.
      _multiTouch = false;
      return null;
    }
    final down = _downPosition;
    final downTime = _downTime;
    final downSettling = _downSettling;
    _activePointer = null;
    _downPosition = null;
    _downTime = null;

    final cleanTap = !_multiTouch &&
        !_movedPastSlop &&
        down != null &&
        downTime != null &&
        timeStamp - downTime <= maxTapDuration;
    _multiTouch = false;
    if (!cleanTap) {
      // Ketukan kotor membatalkan pasangan yang menunggu — mencegah
      // "swipe + tap" terbaca sebagai double-tap.
      _firstTapDown = null;
      _firstTapUpTime = null;
      return null;
    }

    final firstDown = _firstTapDown;
    final firstUp = _firstTapUpTime;
    final pairs = firstDown != null &&
        firstUp != null &&
        downTime - firstUp <= window &&
        (down - firstDown).distance <= secondTapSlop;
    if (pairs) {
      final settledFlag = _firstTapSettling;
      _firstTapDown = null;
      _firstTapUpTime = null;
      return (position: down, firstTapSettling: settledFlag);
    }
    // Bukan pasangan → ketukan ini jadi "pertama" yang baru.
    _firstTapDown = down;
    _firstTapUpTime = timeStamp;
    _firstTapSettling = downSettling;
    return null;
  }

  void onPointerCancel(int pointer) {
    if (pointer == _activePointer) {
      _activePointer = null;
      _downPosition = null;
      _downTime = null;
      _movedPastSlop = false;
    }
    _multiTouch = false;
    _firstTapDown = null;
    _firstTapUpTime = null;
  }
}

/// Pembungkus PageView yang menembakkan [onSettleDoubleTapLike] HANYA bila
/// ketukan PERTAMA dari pasangan double-tap terjadi saat scroll sedang
/// ballistic-settle.
///
/// KENAPA di luar PageView: selama settle, [ScrollableState] mengaktifkan
/// IgnorePointer atas seluruh viewport (BallisticScrollActivity
/// .shouldIgnorePointer == true) sehingga hit-test tidak pernah mencapai
/// widget APA PUN di dalam halaman — termasuk GestureDetector media dan raw
/// Listener. Level ini (ancestor Scrollable) tetap menerima semua event.
///
/// KENAPA gating "ketukan pertama saat settle": saat diam, jalur double-tap
/// lama di dalam FeedVideoPostView yang menangani (tahu area media, tombol
/// aman). Ketukan pertama saat settle mustahil dilihat jalur dalam → wajib
/// ditangani di sini; saat itu semua tombol di dalam halaman juga mati,
/// jadi ketukan bukan pencetan tombol. Dua jalur mutually-exclusive.
class DoubleTapLikePointerDetector extends StatefulWidget {
  const DoubleTapLikePointerDetector({
    super.key,
    required this.onSettleDoubleTapLike,
    required this.child,
  });

  /// Dipanggil saat double-tap "settle-case" lengkap; argumen = posisi
  /// GLOBAL ketukan kedua (dikonversi lokal oleh penerima utk heart burst).
  final ValueChanged<Offset> onSettleDoubleTapLike;
  final Widget child;

  @override
  State<DoubleTapLikePointerDetector> createState() =>
      _DoubleTapLikePointerDetectorState();
}

class _DoubleTapLikePointerDetectorState
    extends State<DoubleTapLikePointerDetector> {
  final RawDoubleTapTracker _tracker = RawDoubleTapTracker();

  /// True selama scroll depth-0 (PageView yang kami bungkus) bergerak tanpa
  /// jari (ballistic). Diperbarui live oleh notifikasi scroll.
  bool _settling = false;

  /// Snapshot [_settling] "per akhir frame", DIPAKAI oleh [onPointerDown]
  /// — BUKAN [_settling] langsung.
  ///
  /// KENAPA perlu snapshot terpisah (bukan baca `_settling` live): tap YANG
  /// SAMA yang ingin kita deteksi "terjadi saat settling" juga men-trigger
  /// [ScrollableState] descendant memanggil `hold()` untuk menghentikan
  /// ballistic — dan hit-test Flutter mem-dispatch pointer event ke target
  /// TERDALAM (descendant Scrollable) LEBIH DULU sebelum ke [Listener]
  /// ancestor kita di frame yang sama. Akibatnya `_settling` sudah keburu
  /// direset ke false oleh notifikasi ScrollEnd SEBELUM `onPointerDown` kita
  /// sempat membacanya — race, bukan bug logika. Snapshot "akhir frame
  /// sebelumnya" kebal terhadap race ini: nilainya dikunci SEBELUM tap yang
  /// sedang diproses punya kesempatan mengubah `_settling`.
  bool _settlingSnapshot = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_captureSettlingSnapshot);
  }

  void _captureSettlingSnapshot(Duration _) {
    _settlingSnapshot = _settling;
    // Terus rekam tiap frame (ballistic PageView memicu frame terus-menerus
    // selama settle) selama widget masih hidup.
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback(_captureSettlingSnapshot);
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    // depth 0 = scrollable langsung di bawah kami (PageView vertikal);
    // scroll lain (mis. carousel foto horizontal di dalam item) diabaikan.
    if (notification.depth != 0) return false;
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails == null) {
      _settling = true;
    } else if (notification is ScrollEndNotification) {
      _settling = false;
    } else if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      // Drag jari asli — bukan settle; tap saat drag bukan kasus kami.
      _settling = false;
    }
    return false; // jangan telan notifikasi milik listener lain.
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => _tracker.onPointerDown(
            event.pointer, event.position, event.timeStamp,
            settling: _settlingSnapshot),
        onPointerMove: (event) =>
            _tracker.onPointerMove(event.pointer, event.position),
        onPointerUp: (event) {
          final hit = _tracker.onPointerUp(
              event.pointer, event.position, event.timeStamp);
          if (hit != null && hit.firstTapSettling) {
            widget.onSettleDoubleTapLike(hit.position);
          }
        },
        onPointerCancel: (event) => _tracker.onPointerCancel(event.pointer),
        child: widget.child,
      ),
    );
  }
}

/// Jembatan perintah like eksternal: layar (pemilik detector luar) →
/// [FeedVideoPostView] yang sedang aktif. Handler tunggal — hanya view
/// aktif yang attach; view lama wajib detach dengan referensi handler-nya
/// sendiri supaya tidak meng-clobber attach view baru (urutan attach/detach
/// saat pindah halaman tidak dijamin).
class ExternalDoubleTapLike {
  void Function(Offset globalPosition)? _handler;

  void attach(void Function(Offset globalPosition) handler) {
    _handler = handler;
  }

  void detach(void Function(Offset globalPosition) handler) {
    // KENAPA `==` bukan `identical()`: instance-method tear-off di Dart
    // TIDAK dijamin `identical` antar evaluasi (`obj.method` bisa
    // menghasilkan closure object baru tiap dipanggil), meski merujuk
    // metode+instance yang SAMA — closure semacam ini tetap `==` (Dart
    // menjamin operator== untuk tear-off metode instance yang sama).
    // Pakai `identical()` di sini akan membuat view GAGAL detach dirinya
    // sendiri (isActive→false) karena `widget.externalDoubleTapLike
    // ?.detach(_onExternalDoubleTapLike)` mengevaluasi tear-off baru yang
    // tak `identical` dengan yang di-attach — bridge tetap nyangkut
    // attached ke view yang sudah tak aktif.
    if (_handler == handler) _handler = null;
  }

  /// True bila ada view aktif yang menangani.
  bool fire(Offset globalPosition) {
    final handler = _handler;
    if (handler == null) return false;
    handler(globalPosition);
    return true;
  }
}
