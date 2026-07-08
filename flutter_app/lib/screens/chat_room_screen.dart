import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';
import '../services/api_client.dart';
import '../services/app_analytics.dart';
import '../services/chat_message_merge.dart';
import '../services/chat_service.dart';
import '../services/push_notification_service.dart';
import '../state/chat_store.dart';
import '../state/member_store.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/natalo_colors.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import '../widgets/chat/chat_bubble.dart';
import '../widgets/chat/chat_composer.dart';
import '../widgets/chat/chat_image_message.dart';
import '../widgets/chat/chat_product_card.dart';
import '../widgets/chat/chat_system_note.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';

/// Layar chat customer <-> staff (satu room per customer, 1:1 dgn NLCATTER).
///
/// Full UI (Task 4): header status jam operasional, daftar pesan (bubble
/// teks, kartu produk, foto, catatan sistem/otomatis), composer teks dgn
/// kirim optimistic dasar.
///
/// Mesin runtime (Task 5): retry sungguhan (`_onRetry`), kirim foto
/// (`_onAttachPhoto`), polling `Timer.periodic` 4 detik + lifecycle
/// (`WidgetsBindingObserver`) + wake FCM (`notificationRefreshTick`),
/// pull-to-refresh (`NataloPawRefreshIndicator`), dan mark-read
/// (`chatStore.setUnread(0)` setiap `fetchMessages` sukses — GET
/// `[chatId]` sudah reset `unreadForCustomer` di server, Plan 2 fix C2).
///
/// **Load-more riwayat LAMA (scroll ke atas) SENGAJA TIDAK diimplementasikan**
/// — backend `GET /api/chat/[chatId]` cuma paginate MAJU
/// (`orderBy(createdAt ASC).startAfter(after)`; `after` = cursor → pesan
/// LEBIH BARU, bukan lebih lama). Tidak ada endpoint/param untuk fetch
/// pesan yang lebih lama dari halaman pertama, jadi "prepend saat scroll
/// atas" mustahil dibangun di atas kontrak ini. Sebagai gantinya, initial
/// load & pull-to-refresh men-drain SEMUA halaman MAJU (`_drainForward`)
/// sampai `nextCursor == null` — untuk thread support 1:1 yang realistis
/// kecil, ini efektif memuat seluruh riwayat sekali buka, jadi fitur
/// load-more tidak dibutuhkan juga secara praktis.
class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, this.chatId, this.productContext});

  /// null = resolve room milik user yang sedang login di server (backend
  /// cari/buatkan room berdasarkan auth token, bukan dari client).
  final String? chatId;

  /// Konteks produk saat entry dari tombol chat di halaman detail produk,
  /// mis. `{'type': 'product', 'productId': ..., 'slug': ...}`. Dikirim
  /// sebagai `context` pesan pertama yang benar-benar terkirim sesi ini.
  final Map<String, dynamic>? productContext;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen>
    with WidgetsBindingObserver {
  final List<ChatMessage> _messages = [];
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  /// `viewInsets.bottom` terakhir yang teramati (`didChangeMetrics`) — dipakai
  /// mendeteksi transisi keyboard TERTUTUP->TERBUKA (0 -> positif) supaya
  /// auto-scroll (F10) hanya fire sekali saat keyboard baru muncul, bukan
  /// tiap kali `didChangeMetrics` fire (bisa >1x selama animasi keyboard di
  /// sebagian device/OS).
  double _lastViewInsetBottom = 0;

  /// Guard defensif forward-drain (`_drainForward`) — cap total halaman per
  /// panggilan supaya tak pernah hang tak berujung kalau proxy suatu saat
  /// mengirim cursor yang tidak pernah habis. Thread support 1:1 realistis
  /// jauh di bawah ini (PAGE_SIZE proxy = 50/halaman).
  static const int _kMaxDrainPages = 40;

  /// Polling near-realtime — hidup HANYA saat layar tampak: `Timer` sendiri
  /// start di `_loadMessages` sukses & `resumed`, stop di `paused`/
  /// `inactive`/`detached`/`dispose`, DAN tiap tick individual di-skip
  /// (no fetch/mark-read/setUnread) selama route layar ini TERTUTUP route
  /// lain yang di-push di atasnya (`ModalRoute.isCurrent == false`, F1) —
  /// lihat `_pollTick`.
  Timer? _pollTimer;

  /// Guard 1 poll in-flight dalam satu waktu — cegah tick baru numpuk kalau
  /// tick sebelumnya (mis. forward-drain multi-halaman) belum selesai saat
  /// timer 4 detik berikutnya sudah fire, ATAU 2 sumber sekaligus
  /// (`Timer.periodic` + `notificationRefreshTick`) trigger bersamaan.
  bool _pollInFlight = false;

  /// Hitungan tick poll yang BENAR-BENAR diproses (lolos guard visibilitas
  /// route & `_authError`) — dipakai me-refresh `chatStore.fetchConfig()`
  /// (kill-switch + status online, F7) tiap [_kConfigRefreshEveryNTicks]
  /// tick (~20 detik) supaya keduanya tak membeku selama room terbuka lama.
  int _pollTickCount = 0;
  static const int _kConfigRefreshEveryNTicks = 5;

  /// `clientMsgId` foto yang sedang/baru dikirim -> path file lokal.
  /// `ChatMessage` (Task 1, frozen) tidak punya field path lokal, cuma
  /// `imageUrl` network — map transient ini yang menjembatani supaya
  /// [ChatImageMessage] bisa render thumbnail SEBELUM upload selesai.
  /// Entry dibersihkan begitu versi server pesan itu direkonsiliasi
  /// (lihat `_mergeIncoming`) — tidak pernah leak tak terbatas.
  final Map<String, String> _pendingImagePaths = {};

  /// `clientMsgId` pesan pembawa `product_context` -> payload context-nya,
  /// ditahan supaya `_onRetry` bisa MELAMPIRKAN ulang context saat mengirim
  /// ulang pesan pertama yang gagal (tanpa ini, retry pesan konteks kehilangan
  /// `product_context`-nya). Diisi HANYA untuk pesan yang benar-benar membawa
  /// context, dibersihkan begitu kirim sukses ATAU versi server-nya
  /// direkonsiliasi (`_mergeIncoming`).
  final Map<String, Map<String, dynamic>> _pendingContext = {};

  /// Teks PERSIS pesan sistem auto-reopen — HARUS sama persis dgn
  /// `REOPEN_TEXT` di `lib/chat/auto-effects.ts` (repo proxy Natalo). Dipakai
  /// [_logReopenEvents] (analitik `chat_reopened`, spec §11).
  static const String _reopenSystemText = 'Percakapan dibuka kembali.';

  /// Id server pesan reopen yang analitiknya SUDAH dicatat sesi ini — cegah
  /// dobel-hitung (lihat docstring [_logReopenEvents]).
  final Set<String> _loggedReopenMessageIds = {};

  /// True setelah riwayat AWAL berhasil di-seed ke [_loggedReopenMessageIds]
  /// TEPAT SEKALI — baik lewat `_loadMessages` sukses NORMAL, MAUPUN lewat
  /// [_mergeIncoming] di jalur RECOVERY (F6, lihat docstring situ). Selama
  /// masih `false`, [_mergeIncoming] memperlakukan batch pesan yang masuk
  /// sebagai HISTORY (seed dedupe TANPA fire event), bukan pesan baru —
  /// mencegah replay burst `chat_reopened` kalau initial load GAGAL (mis.
  /// offline saat buka) lalu baru pulih lewat poll/wake/pull-to-refresh
  /// berikutnya (jalur itu full-drain SELURUH riwayat krn `_afterCursor`
  /// masih null selama `_messages` kosong).
  bool _historySeeded = false;

  String? _chatId;
  bool _loading = true;
  Object? _loadError;

  /// True kalau fetch chat (initial load/poll/pull-to-refresh) balas 401/403
  /// — chatId asing (bukan milik akun ini) atau sesi sudah habis (F8).
  /// BEDA dari `_loadError` biasa: kondisi ini PERMANEN sampai user
  /// login ulang/keluar layar, jadi begitu true, polling DIHENTIKAN
  /// permanen (lihat `_pollTick`/`didChangeAppLifecycleState`) — retry
  /// otomatis tak akan pernah berhasil, cuma menghajar endpoint terus.
  bool _authError = false;

  /// Guard "konteks hanya nempel di pesan pertama sesi ini" — sekali
  /// terkirim (sukses ATAU gagal, karena keduanya sudah "mencoba" memakai
  /// kontekstnya), jangan kirim ulang `widget.productContext` di pesan
  /// berikutnya.
  bool _contextSent = false;

  /// Status room ('open'/'resolved' dst). **Belum ada sumber data**: respons
  /// `GET /api/chat/{chatId}` yang di-ship (Plan 2) hanya balas
  /// `{chatId, messages, nextCursor}` — TIDAK ada field `status` room sama
  /// sekali (lihat `app/api/chat/[chatId]/route.ts`), dan `ChatService`
  /// (Task 2, frozen di task ini) tidak expose field itu meski suatu saat
  /// proxy menambahkannya. Default 'open' (kontrak sama dgn `ChatRoomState`
  /// di `chat_message.dart`) sehingga catatan "resolved" di bawah TIDAK
  /// PERNAH tampil hari ini — plumbing UI-nya tetap dibangun (bukan
  /// skip) supaya begitu proxy/`ChatService` expose status asli, tinggal
  /// disambungkan di sini tanpa ubah widget tree. `final` (bukan var) krn
  /// tak pernah di-reassign dgn sumber data saat ini.
  final String _roomStatus = 'open';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Wake FCM (brief §9): push masuk foreground -> tick berubah -> fetch
    // sekali tanpa nunggu polling 4 detik berikutnya. Listener dipasang
    // terlepas dari status login/chatId — `_onFcmWakeTick` sendiri yang
    // guard `_chatId == null`, konsisten dgn `dispose` yang selalu
    // melepasnya lagi (simetris, tak perlu cabang kondisional di initState).
    pushNotificationService.notificationRefreshTick.addListener(
      _onFcmWakeTick,
    );

    // Populate chatStore.online + chatEnabled — header & composer area
    // bereaksi lewat AnimatedBuilder(animation: chatStore) di build().
    chatStore.fetchConfig();

    final explicit = widget.chatId;
    _chatId =
        (explicit != null && explicit.isNotEmpty) ? explicit : _myChatId();
    if (_chatId == null) {
      // Belum login (tidak ada chatId eksplisit dari argumen rute, dan
      // memberStore.profile kosong) — build() akan render prompt login,
      // bukan mencoba fetch tanpa identitas.
      _loading = false;
    } else {
      _loadMessages();
    }
  }

  /// `chatId = cust_<User.id>` — deterministik sama dgn `chatIdForUser`
  /// proxy (`lib/chat/core.ts`, repo Natalo). `GET /api/chat/[chatId]`
  /// menegakkan anti-IDOR dgn membandingkan param URL ke
  /// `chatIdForUser(session.sub)` (403 kalau beda) — jadi klien WAJIB
  /// mengirim string yang persis sama, bukan sekadar id opak apa pun.
  /// `session.sub` proxy = Prisma `User.id` (cuid), field yang SAMA dgn
  /// `memberStore.profile.id` (diisi dari `/api/auth/me` → `{id: session.sub}`,
  /// lihat `app/api/auth/me/route.ts`) — dipakai sinkron di banyak tempat
  /// lain di app ini sbg "id user sendiri" (mis. `feed_screen.dart`
  /// `selfId = memberStore.profile?.id`), jadi aman dibaca langsung di
  /// `initState` tanpa fetch tambahan.
  String? _myChatId() {
    final id = memberStore.profile?.id;
    return (id != null && id.isNotEmpty) ? 'cust_$id' : null;
  }

  /// Initial load (dipanggil dari `initState`) — drain forward PENUH dari
  /// awal thread, tampilkan spinner selama proses, lalu mulai polling.
  Future<void> _loadMessages() async {
    final chatId = _chatId;
    if (chatId == null) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final fetched = await _drainForward();
      if (!mounted) return;
      setState(() {
        // Merge (bukan clear+replace mentah) — kalau user sempat kirim
        // pesan SEBELUM initial load ini selesai (composer tidak
        // digembok saat `_loading`), bubble optimistic itu tidak boleh
        // hilang begitu saja.
        final merged =
            fetched.isEmpty ? _messages : mergeChatMessages(_messages, fetched);
        _messages
          ..clear()
          ..addAll(merged);
        _loading = false;
      });
      // Seed dedupe reopen: tandai SEMUA pesan reopen yang sudah ada di
      // riwayat awal sebagai "sudah dicatat" TANPA fire `chat_reopened`.
      // Initial load memang tak lewat `_logReopenEvents`, tapi
      // `_onPullToRefresh` melakukan full-redrain (`after: null`) yang
      // MELEWATI `_mergeIncoming` → `_logReopenEvents`; tanpa seed ini,
      // pull-to-refresh PERTAMA di sesi ini akan mem-fire ulang tiap reopen
      // historis (set masih kosong). Seed = guard replay itu.
      _seedLoggedReopenIds(_messages);
      // Tandai riwayat sudah di-seed (F6) — jalur RECOVERY di
      // [_mergeIncoming] (initial load ini GAGAL lalu poll/wake pulih
      // duluan) tidak perlu seed ulang lagi begitu jalur normal ini
      // akhirnya sukses juga (mis. user tap Retry setelah sempat pulih via
      // poll) — `_seedLoggedReopenIds` sendiri idempoten (Set), tapi flag
      // ini yang menentukan apakah [_mergeIncoming] berikutnya masih
      // menganggap batch sbg history atau pesan baru.
      _historySeeded = true;
      // GET yang barusan sukses sudah reset `unreadForCustomer` di server
      // (fix C2 Plan 2) — sinkronkan badge lokal.
      chatStore.setUnread(0);
      _scrollToBottom(animate: false);
      _startPolling();
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatRoomScreen] fetchMessages gagal: $e');
      if (!mounted) return;
      if (_isAuthError(e)) {
        // chatId asing/sesi habis (F8) — hentikan polling permanen & pakai
        // state khusus (BUKAN AppErrorState generic+retry, retry-nya tak
        // akan pernah berhasil).
        _stopPolling();
        setState(() {
          _authError = true;
          _loading = false;
        });
        return;
      }
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  /// True kalau [e] adalah `ApiException` 401/403 — dipakai `_loadMessages`/
  /// `_pollTick`/`_onPullToRefresh` (F8) membedakan error auth PERMANEN
  /// (chatId asing/sesi habis, tak akan pernah sukses lewat retry biasa)
  /// dari error transient lain (network/5xx) yang tetap boleh di-retry.
  bool _isAuthError(Object e) =>
      e is ApiException && (e.isUnauthorized || e.isForbidden);

  /// Fetch SEMUA pesan mulai dari [after] (null = dari awal thread) dengan
  /// men-drain `nextCursor` MAJU terus-menerus. Backend `GET
  /// /api/chat/[chatId]` HANYA paginate ke pesan yang LEBIH BARU dari
  /// `after` (`orderBy(createdAt ASC).startAfter(after)`) — tidak ada
  /// jalur untuk fetch pesan yang lebih LAMA dari halaman pertama, jadi
  /// fungsi ini (dipakai initial load, pull-to-refresh, & tiap poll tick)
  /// SELALU bergerak maju, tak pernah prepend riwayat lama (lihat
  /// docstring kelas `ChatRoomScreen` di atas).
  ///
  /// Berhenti kalau: halaman kosong (0 pesan baru — tanda sudah mentok),
  /// `nextCursor == null`, ATAU sudah [_kMaxDrainPages] halaman (guard
  /// defensif terhadap loop tak berujung; harusnya tak pernah kena di
  /// produksi untuk thread support 1:1 yang realistis kecil).
  Future<List<ChatMessage>> _drainForward({Object? after}) async {
    final chatId = _chatId;
    if (chatId == null) return const [];
    final collected = <ChatMessage>[];
    Object? cursor = after;
    var pageCount = 0;
    while (true) {
      final page = await chatService.fetchMessages(chatId, after: cursor);
      if (page.messages.isEmpty) break;
      collected.addAll(page.messages);
      pageCount++;
      if (page.nextCursor == null) break;
      if (pageCount >= _kMaxDrainPages) {
        if (kDebugMode) {
          debugPrint(
            '[ChatRoomScreen] forward-drain stop paksa @ '
            '$_kMaxDrainPages halaman (cursor=${page.nextCursor}) — cek '
            'proxy kalau ini kejadian nyata, harusnya tak pernah kena.',
          );
        }
        break;
      }
      cursor = page.nextCursor;
    }
    return collected;
  }

  /// Terapkan [mergeChatMessages] ke `_messages` + bersihkan
  /// `_pendingImagePaths`/`_pendingContext` untuk `clientMsgId` yang barusan
  /// direkonsiliasi (versi server sudah datang → thumbnail lokal &
  /// context-tahan tak perlu lagi; [ChatImageMessage] otomatis pindah ke
  /// `imageUrl` network). No-op kalau [incoming] kosong — hindari `setState`
  /// sia-sia tiap poll tick tanpa pesan baru.
  ///
  /// **Guard HISTORY-vs-BARU (F6):** kalau `_historySeeded` masih `false`
  /// saat dipanggil, berarti `_loadMessages` (initial load) BELUM PERNAH
  /// sukses — jalur ini dipanggil dari poll/wake/pull-to-refresh yang
  /// PERTAMA kali berhasil pulih (mis. initial load gagal krn offline saat
  /// buka, lalu resume/FCM/pull-to-refresh sukses full-drain SELURUH
  /// riwayat karena `_afterCursor` masih null selagi `_messages` kosong).
  /// Batch itu diperlakukan sbg HISTORY — di-seed ke [_loggedReopenMessageIds]
  /// TANPA fire `chat_reopened` (persis seperti `_loadMessages` sukses
  /// normal), bukan lewat [_logReopenEvents] — kalau tidak, tiap pesan
  /// sistem reopen di SELURUH riwayat lama akan dihitung sbg reopen BARU
  /// sekaligus (replay burst, overcount metrik spec §11). Batch BERIKUTNYA
  /// (pesan yang benar-benar baru datang live) tetap lewat [_logReopenEvents]
  /// seperti biasa begitu flag ini `true`.
  void _mergeIncoming(List<ChatMessage> incoming) {
    if (incoming.isEmpty) return;
    if (_historySeeded) {
      _logReopenEvents(incoming);
    } else {
      _seedLoggedReopenIds(incoming);
      _historySeeded = true;
    }
    final merged = mergeChatMessages(_messages, incoming);
    setState(() {
      _messages
        ..clear()
        ..addAll(merged);
    });
    for (final s in incoming) {
      final id = s.clientMsgId;
      if (id != null) {
        _pendingImagePaths.remove(id);
        // (F2) `_contextSent` tak perlu di-set di sini — kalau `id` ini
        // punya entry di `_pendingContext`, ia HANYA bisa dari message yang
        // sudah meng-klaim context SINKRON di titik pembuatannya
        // (`_onSendText`/`_onRetry`), yang berarti `_contextSent` SUDAH
        // true sejak saat itu. Baris server yang datang telat (mis. bekas
        // timeout client yang ternyata sukses di server) cuma perlu
        // membersihkan pending-nya di sini, bukan meng-klaim context lagi.
        _pendingContext.remove(id);
      }
    }
  }

  /// Analitik `chat_reopened` (spec §11) — fire saat customer MENERIMA pesan
  /// sistem auto-reopen. Marker = teks PERSIS `REOPEN_TEXT` di
  /// `lib/chat/auto-effects.ts` (repo Natalo proxy, `autoReopenIfResolved`):
  /// `senderRole: 'system', type: 'system', text: 'Percakapan dibuka
  /// kembali.', auto: true`. Cocokkan `type == system` + teks persis (bukan
  /// `startsWith`/`contains` — teks itu konstanta stabil, exact match lebih
  /// aman dari false-positive dgn catatan sistem lain kelak).
  ///
  /// Dipanggil HANYA dari [_mergeIncoming], DAN HANYA setelah `_historySeeded
  /// == true` (F6) — SENGAJA TIDAK dari `_loadMessages` (initial history
  /// load pas buka room) maupun dari batch RECOVERY pertama [_mergeIncoming]
  /// (lihat docstring situ), supaya reopen LAMA yang sudah "diterima"
  /// sebelum sesi ini dibuka tak menghasilkan event analitik palsu tiap
  /// kali user buka/pulihkan room. Guard [_loggedReopenMessageIds] per `id`
  /// server — cegah dobel-hitung kalau pesan yang sama terlihat lagi (mis.
  /// pull-to-refresh drain ulang dari awal thread, atau poll tick overlap)
  /// — "sekali per reopen".
  void _logReopenEvents(List<ChatMessage> incoming) {
    for (final m in incoming) {
      if (m.type != ChatMsgType.system) continue;
      if (m.text != _reopenSystemText) continue;
      if (!_loggedReopenMessageIds.add(m.id)) continue;
      AppAnalytics.logEvent('chat_reopened');
    }
  }

  /// Tandai pesan reopen di riwayat AWAL sebagai "sudah dicatat" TANPA
  /// fire event (bedanya dgn [_logReopenEvents]: tak ada `logEvent`) —
  /// dipanggil dari DUA jalur history: `_loadMessages` sukses NORMAL, atau
  /// [_mergeIncoming] jalur RECOVERY (F6, initial load sempat gagal) — baik
  /// `_onPullToRefresh` (full-redrain) maupun batch recovery poll/wake
  /// tak mem-fire ulang reopen historis. Reopen BARU yang datang live
  /// SETELAH riwayat ter-seed tetap tak masuk set ini → tetap fire tepat
  /// sekali lewat [_logReopenEvents].
  void _seedLoggedReopenIds(List<ChatMessage> history) {
    for (final m in history) {
      if (m.type != ChatMsgType.system) continue;
      if (m.text != _reopenSystemText) continue;
      _loggedReopenMessageIds.add(m.id);
    }
  }

  /// Cursor untuk polling: `createdAt` TERBESAR di antara pesan SERVER
  /// (`!m.isOptimistic`) — delegasi ke [maxServerCreatedAt]
  /// (`chat_message_merge.dart`, F3), helper murni yang SAMA dipakai
  /// [_nextOptimisticCreatedAtNow] untuk clock-skew guard bubble baru,
  /// supaya loop "cari createdAt server terbesar" cuma ada SATU tempat.
  /// Null kalau belum ada satupun pesan server (poll pertama efektif
  /// `after: null`).
  ///
  /// **Kenapa `isOptimistic` BUKAN `status == null`:** proxy MENGIRIM
  /// `status: "sent"` untuk pesan customer (`lib/chat/rooms.ts:204` →
  /// `lib/chat/core.ts:69`), jadi pesan customer dari `fetchMessages` pun
  /// `status` non-null. Kalau cursor memakai `status == null`, ia akan
  /// MELEWATKAN pesan customer terkonfirmasi (yang sering jadi pesan
  /// terbaru tepat setelah user kirim) → cursor tak maju → tiap tick 4s
  /// men-drain ulang ekor thread (idempoten tapi boros jaringan/baterai +
  /// jank). Flag `isOptimistic` (hanya `true` utk bubble lokal, `fromJson`
  /// selalu `false`) menandai provenance dengan benar.
  Object? get _afterCursor => maxServerCreatedAt(_messages);

  /// `createdAt` untuk BUBBLE OPTIMISTIC BARU (F3, guard clock skew) —
  /// tipis di atas [nextOptimisticCreatedAt] murni (`chat_message_merge.dart`)
  /// supaya titik panggil (`_onSendText`/`_onAttachPhoto`) tidak perlu
  /// mengoper `_messages` manual tiap kali. Lihat docstring
  /// [nextOptimisticCreatedAt] untuk penjelasan lengkap skenario skew.
  int _nextOptimisticCreatedAtNow() => nextOptimisticCreatedAt(_messages);

  /// True kalau posisi scroll user sudah dekat bawah (atau belum ada
  /// scrollable sama sekali, mis. list pendek yang tak butuh scroll) —
  /// dipakai polling supaya TIDAK menarik paksa pandangan user yang sedang
  /// scroll ke atas baca riwayat lama saat pesan baru masuk.
  ///
  /// **Threshold include `viewInsets.bottom` (F10):** keyboard terbuka
  /// menyusutkan viewport ~300px (`resizeToAvoidBottomInset`) tanpa
  /// menggeser `pixels` — `maxScrollExtent - pixels` jadi membesar sebesar
  /// tinggi keyboard walau posisi user relatif TAK berubah. Threshold dasar
  /// 96px jauh di bawah itu, jadi tanpa kompensasi ini, poll berhenti
  /// auto-scroll pesan masuk begitu keyboard dibuka meski user sebenarnya
  /// masih persis di bawah. Menambah `viewInsets.bottom` ke threshold
  /// menetralkan pergeseran itu (matematis setara dgn cek "dekat bawah"
  /// versi SEBELUM keyboard terbuka, karena `pixels` tak berubah).
  bool _isNearBottom({double threshold = 96}) {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return (position.maxScrollExtent - position.pixels) <=
        threshold + keyboardInset;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pollTick();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Satu siklus poll/wake: fetch pesan baru sejak [_afterCursor], gabung
  /// ke `_messages`, tandai room "sudah dibaca" (server-side, via GET yang
  /// sama), auto-scroll HANYA kalau user sudah dekat bawah SEBELUM merge.
  /// Dipanggil dari 3 tempat: `Timer.periodic` 4 detik, lifecycle
  /// `resumed` (sekali, langsung), dan `notificationRefreshTick` (wake
  /// FCM, sekali).
  ///
  /// **Silent-fail pada GAGAL** (swallow error, TIDAK set `_loadError`) —
  /// poll background gagal sesekali (network flaky) tak boleh mengganti body
  /// chat yang sudah terisi jadi error state; beda dgn `_loadMessages`
  /// (initial load) yang memang perlu tampilkan error karena belum ada
  /// apa-apa untuk ditampilkan kalau gagal. **Pada SUKSES**, sebaliknya,
  /// error stale DIBERSIHKAN (`_clearLoadErrorIfSet`) — kalau initial load
  /// tadi gagal (offline saat buka) lalu poll/wake ini berhasil, user tak
  /// boleh tetap terjebak di layar error padahal thread-nya sudah termuat.
  /// **Pengecualian 401/403** — lihat `_isAuthError`, bukan silent-fail.
  ///
  /// **Guard visibilitas route (F1):** kalau layar ini TERTUTUP route lain
  /// yang di-push di atasnya (mis. tap chip produk -> ProductDetailScreen),
  /// `ModalRoute.of(context)!.isCurrent` jadi false — tick SKIP TOTAL (tak
  /// fetch, tak mark-read, tak `setUnread`). Bukan RouteAware/stop timer;
  /// timer tetap jalan tiap 4 detik tapi no-op selama tertutup, dan begitu
  /// route penutup di-pop, tick berikutnya (<=4 detik) otomatis resume.
  Future<void> _pollTick() async {
    if (_chatId == null || !mounted || _pollInFlight || _authError) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    // Refresh kill-switch + status online (F7) tiap N tick (~20 detik) —
    // TERPISAH dari fetch pesan di bawah supaya gagalnya salah satu tak
    // menghalangi yang lain (`chatStore.fetchConfig()` fail-open sendiri).
    _pollTickCount++;
    if (_pollTickCount % _kConfigRefreshEveryNTicks == 0) {
      chatStore.fetchConfig();
    }

    _pollInFlight = true;
    try {
      final wasNearBottom = _isNearBottom();
      final fetched = await _drainForward(after: _afterCursor);
      if (!mounted) return;
      _mergeIncoming(fetched);
      _clearLoadErrorIfSet();
      chatStore.setUnread(0);
      if (fetched.isNotEmpty && wasNearBottom) _scrollToBottom();
    } catch (e) {
      if (_isAuthError(e)) {
        // chatId asing/sesi habis (F8) — hentikan polling permanen, JANGAN
        // silent-fail seperti error lain (bakal menghajar endpoint 401/403
        // tiap 4 detik selamanya kalau dibiarkan).
        if (kDebugMode) {
          debugPrint('[ChatRoomScreen] poll 401/403 — stop polling: $e');
        }
        _stopPolling();
        if (mounted) setState(() => _authError = true);
      } else if (kDebugMode) {
        debugPrint('[ChatRoomScreen] poll gagal (diabaikan): $e');
      }
    } finally {
      _pollInFlight = false;
    }
  }

  /// Bersihkan error load stale setelah SUATU fetch sukses (poll/wake/
  /// pull-to-refresh) — guarded `setState` yang HANYA rebuild kalau memang
  /// sedang ada error (jalur pemulihan langka), jadi tak menambah rebuild di
  /// steady-state normal. Dipanggil TERPISAH dari `_mergeIncoming` (yang
  /// no-op kalau tak ada pesan baru) supaya error tetap kebersihan walau
  /// fetch sukses mengembalikan 0 pesan baru.
  void _clearLoadErrorIfSet() {
    if (_loadError == null) return;
    setState(() => _loadError = null);
  }

  void _onFcmWakeTick() {
    if (_chatId != null) _pollTick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _stopPolling();
        break;
      case AppLifecycleState.resumed:
        if (_chatId != null) {
          // Refresh kill-switch + status online (F7) tiap kali app kembali
          // ke foreground — jangan sampai user balik dari background lalu
          // masih lihat status stale berjam-jam.
          chatStore.fetchConfig();
          // JANGAN restart polling kalau sudah kena 401/403 permanen (F8) —
          // begitu `_authError` true, endpoint ini tak akan pernah sukses
          // lagi sampai user login ulang/keluar layar.
          if (!_authError) {
            _pollTick();
            _startPolling();
          }
        }
        break;
    }
  }

  /// Deteksi keyboard buka/tutup (F10) — `WidgetsBindingObserver` sudah
  /// dipasang untuk lifecycle app, jadi tinggal override hook ini juga.
  /// Defer ke post-frame callback: pas `didChangeMetrics` fire, layout baru
  /// MULAI menyesuaikan inset baru — `MediaQuery`/`ScrollPosition` belum
  /// pasti reflect nilai final sampai frame berikutnya selesai.
  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _onMetricsSettled());
  }

  void _onMetricsSettled() {
    if (!mounted) return;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardJustOpened = bottomInset > 0 && _lastViewInsetBottom <= 0;
    _lastViewInsetBottom = bottomInset;
    // Keyboard baru saja terbuka DAN user sudah dekat bawah (dihitung pakai
    // `_isNearBottom` yang sudah include inset baru, lihat docstring-nya) —
    // auto-scroll supaya bubble terbaru tidak tersembunyi di balik keyboard.
    if (keyboardJustOpened && _isNearBottom()) {
      _scrollToBottom();
    }
  }

  /// Pull-to-refresh (`NataloPawRefreshIndicator`) → forward-drain PENUH
  /// dari awal thread (`after: null`), bukan cuma dari [_afterCursor] —
  /// resync total untuk cover kasus polling/wake sempat miss sesuatu.
  /// Pakai [_mergeIncoming] (BUKAN clear+replace mentah) supaya bubble
  /// optimistic yang mungkin lagi `sending` (user kirim pesan PAS menarik
  /// refresh) tidak hilang — untuk kasus normal (tak ada pesan optimistic
  /// in-flight) hasilnya identik dgn full-replace karena semua baris
  /// server yang sudah dimiliki di-skip via dedupe by id.
  ///
  /// Menghormati `_pollInFlight` (sama seperti `_pollTick`) — kalau sebuah
  /// drain (poll tick) sudah jalan, skip: datanya sedang di-fetch toh, jadi
  /// fetch kedua konkuren cuma mubazir (aman krn merge idempoten, tapi tak
  /// perlu). Set flag selama drain-nya sendiri supaya poll tick tidak
  /// menyelinap bersamaan.
  Future<void> _onPullToRefresh() async {
    if (_chatId == null || _pollInFlight || _authError) return;
    _pollInFlight = true;
    try {
      final fetched = await _drainForward();
      if (!mounted) return;
      _mergeIncoming(fetched);
      _clearLoadErrorIfSet();
      chatStore.setUnread(0);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatRoomScreen] pull-to-refresh gagal: $e');
      }
      if (!mounted) return;
      if (_isAuthError(e)) {
        // Sesi habis/chatId asing (F8) baru ketahuan pas pull-to-refresh —
        // sama seperti `_loadMessages`/`_pollTick`: hentikan polling &
        // pindah ke state khusus, bukan toast generic yang bisa diulang.
        _stopPolling();
        setState(() => _authError = true);
        return;
      }
      AppToast.show(
        context,
        'Gagal memuat ulang percakapan',
        kind: ToastKind.error,
      );
    } finally {
      _pollInFlight = false;
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  /// Guard kill-switch di titik kirim (F7) — `_buildFooter` sudah
  /// menggantikan composer dgn `_ChatMaintenanceBanner` saat
  /// `!chatStore.chatEnabled`, tapi `chatStore` bisa berubah status DI
  /// ANTARA render terakhir dan tap kirim (composer sempat kefokus, config
  /// refresh 20-detikan mematikan kill-switch tepat sebelum tap). Tanpa
  /// guard ini, request tetap terkirim ke server (yang JUGA menolak, urutan
  /// guard proxy: CSRF -> session -> kill-switch) lalu bubble jadi `failed`
  /// tanpa penjelasan & retry yang selamanya gagal. Return false = jangan
  /// lanjut kirim.
  bool _guardChatEnabled() {
    if (chatStore.chatEnabled) return true;
    AppToast.show(
      context,
      'Chat sedang dalam pemeliharaan',
      kind: ToastKind.warning,
    );
    return false;
  }

  /// Kirim teks optimistic dasar — tampilkan bubble `sending` segera, lalu
  /// update jadi `sent`/`failed` sesuai hasil `chatService.sendText`.
  /// Rekonsiliasi penuh dgn versi server (via poll + `clientMsgId` dedupe)
  /// serta retry yang benar-benar mengirim ulang = Task 5.
  Future<void> _onSendText(String text) async {
    if (!_guardChatEnabled()) return;
    final clientMsgId = newClientMsgId();
    final optimistic = ChatMessage(
      id: clientMsgId,
      sender: ChatSender.customer,
      type: ChatMsgType.text,
      text: text,
      createdAt: _nextOptimisticCreatedAtNow(),
      clientMsgId: clientMsgId,
      status: ChatSendStatus.sending,
      isOptimistic: true,
    );

    _composerController.clear();
    setState(() => _messages.add(optimistic));
    _scrollToBottom();

    // Konteks produk/pesanan (entry dari Detail Produk) HANYA nempel di
    // pesan PERTAMA yang DIBUAT membawa context sesi ini — aturan CLAIM
    // deterministik satu-kali (F2/F11). `_contextSent` di-set true DI SINI,
    // SINKRON, SEBELUM await apa pun (bukan setelah sukses kirim seperti
    // sebelumnya) — semua kode di atas titik ini (`newClientMsgId`,
    // `setState` bubble, `_scrollToBottom`) juga sinkron, jadi klaim ini
    // efektif terjadi di titik pembuatan bubble optimistic, sebelum Dart
    // event loop sempat menjalankan `_onSendText` lain manapun. Ini
    // menutup DUA celah dari perilaku lama (claim setelah await sukses):
    //  (a) F11 — kirim kedua yang di-dispatch SEBELUM request pertama
    //      selesai round-trip juga membaca `_contextSent == false` (belum
    //      sempat di-set true) & ikut melampirkan context;
    //  (b) F2 — kirim pertama TIMEOUT di client tapi sebenarnya SUKSES di
    //      server; `_mergeIncoming` merekonsiliasi baris server itu &
    //      membersihkan `_pendingContext`-nya TANPA pernah men-set
    //      `_contextSent` (tak ada await sukses utk trigger-nya) — pesan
    //      kedua yang user ketik sesudahnya masih membaca `_contextSent ==
    //      false` & context terkirim DOBEL.
    //
    // `_pendingContext[clientMsgId]` tetap diisi HANYA untuk pesan
    // pengklaim INI — dipakai `_onRetry` pesan ini sendiri (nothing else,
    // lihat docstring situ) untuk melampirkan ulang context yang sama
    // kalau percobaan pertamanya gagal. Edge case yang DISENGAJA: kalau
    // pesan pengklaim ini gagal PERMANEN dan user tak pernah retry, context
    // itu tetap "terpakai" (tak pernah bocor ke pesan lain) — deterministik
    // & tetap bisa dipulihkan kapan pun via retry pesan ini, bukan pindah
    // ke pesan berikutnya.
    final sendContext = _contextSent ? null : widget.productContext;
    if (sendContext != null) {
      _contextSent = true;
      _pendingContext[clientMsgId] = sendContext;
    }

    try {
      // Oper `clientMsgId` yang SAMA dgn bubble optimistic — supaya baris
      // server yang datang di poll berikutnya (proyeksi proxy MEMBAWA
      // `clientMsgId`) bisa direkonsiliasi dgn bubble ini, dan retry
      // mengirim ulang id yang sama → proxy dedupe idempoten (tanpa ini,
      // ChatService akan generate id berbeda → optimistic & server row tak
      // pernah bisa di-match).
      await chatService.sendText(
        text,
        context: sendContext,
        clientMsgId: clientMsgId,
      );
      if (!mounted) return;
      setState(() => _replaceStatus(clientMsgId, ChatSendStatus.sent));
      // `_contextSent` SUDAH true sejak klaim sinkron di atas (bukan di
      // sini lagi) — sukses kirim cuma perlu membersihkan `_pendingContext`
      // (tak butuh lagi ditahan utk retry, pesan ini sudah confirmed).
      _pendingContext.remove(clientMsgId);
      // Analitik — funnel MVP chat (spec §11): SUKSES kirim saja (bukan
      // optimistic add, bukan gagal) — fire-and-forget, tak pernah
      // menyentuh alur kirim/retry.
      AppAnalytics.logEvent('customer_message_sent', {'type': 'text'});
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[ChatRoomScreen] sendText gagal: $e');
      if (!mounted) return;
      setState(() => _replaceStatus(clientMsgId, ChatSendStatus.failed));
    } catch (e) {
      // Non-ApiException (mis. error tak terduga di layer bawah) juga harus
      // memindahkan bubble ke `failed`, bukan membiarkannya macet selamanya
      // di `sending` / naik sbg unhandled async error.
      if (kDebugMode) {
        debugPrint('[ChatRoomScreen] sendText gagal (non-Api): $e');
      }
      if (!mounted) return;
      setState(() => _replaceStatus(clientMsgId, ChatSendStatus.failed));
    }
  }

  void _replaceStatus(String clientMsgId, ChatSendStatus status) {
    final idx = _messages.indexWhere((m) => m.clientMsgId == clientMsgId);
    if (idx == -1) return;
    final m = _messages[idx];
    _messages[idx] = ChatMessage(
      id: m.id,
      sender: m.sender,
      type: m.type,
      text: m.text,
      product: m.product,
      image: m.image,
      order: m.order,
      createdAt: m.createdAt,
      clientMsgId: m.clientMsgId,
      status: status,
      // PRESERVE `isOptimistic` — ini masih bubble lokal (cuma ganti status
      // sending↔sent/failed) sampai poll berikutnya menggantinya dgn baris
      // server. Kalau di-drop jadi false, `_afterCursor` akan salah
      // memakainya sbg cursor (timestamp lokalnya tak sinkron jam server).
      isOptimistic: m.isOptimistic,
      auto: m.auto,
    );
  }

  /// Kirim ulang pesan `failed` — pakai `clientMsgId` YANG SAMA dgn bubble
  /// ini → proxy dedupe idempoten (`writeCustomerMessage` di
  /// `lib/chat/rooms.ts`) supaya retry tidak menggandakan pesan kalau
  /// percobaan pertama sebenarnya sudah sukses di server tapi client cuma
  /// gagal baca response. Foto: pakai path lokal yang masih tersimpan di
  /// `_pendingImagePaths` (foto tidak pernah dikompres ulang saat retry —
  /// file terkompresi hasil percobaan pertama dipakai apa adanya). Teks:
  /// LAMPIRKAN ULANG `product_context` yang tertahan di `_pendingContext`
  /// (kalau pesan ini pembawa context yg percobaan pertamanya gagal) —
  /// kirim ulang context aman krn proxy dedupe seluruh pesan by clientMsgId.
  ///
  /// **F2/F11 — hanya baca entry MILIK [message] SENDIRI:**
  /// `_pendingContext[clientMsgId]` di sini SELALU `clientMsgId` = milik
  /// [message] yang di-retry, tak pernah entry pesan lain — konsisten dgn
  /// aturan CLAIM satu-kali di `_onSendText`: hanya pesan yang MENGKLAIM
  /// context saat dibuat yang pernah punya entry di `_pendingContext` sama
  /// sekali, jadi retry pesan LAIN (yang tak pernah mengklaim context)
  /// otomatis membaca `null` di sini — tak ada jalur utk "mencuri" context
  /// yang sudah terpakai pesan lain.
  Future<void> _onRetry(ChatMessage message) async {
    if (!_guardChatEnabled()) return;
    final clientMsgId = message.clientMsgId;
    if (clientMsgId == null) return;
    setState(() => _replaceStatus(clientMsgId, ChatSendStatus.sending));
    try {
      if (message.type == ChatMsgType.image) {
        final path = _pendingImagePaths[clientMsgId];
        if (path == null) {
          // Tak ada file lokal tersisa (mis. proses di-kill lalu dibuka
          // lagi — `_pendingImagePaths` in-memory, tak persist) — tak ada
          // apa pun untuk dikirim ulang, kembalikan ke `failed`.
          if (!mounted) return;
          setState(() => _replaceStatus(clientMsgId, ChatSendStatus.failed));
          return;
        }
        await chatService.sendImage(path, clientMsgId: clientMsgId);
      } else {
        await chatService.sendText(
          message.text ?? '',
          clientMsgId: clientMsgId,
          context: _pendingContext[clientMsgId],
        );
      }
      if (!mounted) return;
      setState(() => _replaceStatus(clientMsgId, ChatSendStatus.sent));
      // `_contextSent` SUDAH true kalau pesan ini pembawa context (di-set
      // sinkron sejak pesan ini DIBUAT via `_onSendText`, aturan CLAIM
      // F2/F11) — baris ini re-affirm (no-op logically kalau sudah true)
      // + bersihkan `_pendingContext` (retry sukses, tak perlu ditahan lagi).
      if (_pendingContext.remove(clientMsgId) != null) _contextSent = true;
      // Analitik — retry yang berhasil TETAP dihitung "kirim sukses" (pesan
      // memang benar-benar terkirim, percobaan pertama cuma gagal secara
      // network) — simetris dgn `_onSendText`/`_onAttachPhoto`.
      AppAnalytics.logEvent('customer_message_sent', {
        'type': message.type == ChatMsgType.image ? 'image' : 'text',
      });
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[ChatRoomScreen] retry gagal: $e');
      if (!mounted) return;
      setState(() => _replaceStatus(clientMsgId, ChatSendStatus.failed));
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatRoomScreen] retry gagal (non-Api): $e');
      if (!mounted) return;
      setState(() => _replaceStatus(clientMsgId, ChatSendStatus.failed));
    }
  }

  /// Tap ikon kamera composer — bottom sheet kamera/galeri, kompresi (pola
  /// `feed_photo_service._compressForUpload`), lalu bubble optimistic
  /// (thumbnail dari file LOKAL — lihat `_pendingImagePaths`) sebelum
  /// upload selesai. Sukses/gagal update status sama seperti kirim teks;
  /// versi server (`imageUrl` network) datang lewat poll berikutnya dan
  /// direkonsiliasi via `clientMsgId` (`_mergeIncoming`).
  Future<void> _onAttachPhoto() async {
    if (!_guardChatEnabled()) return;
    final source = await _pickImageSource();
    if (source == null || !mounted) return;

    XFile? picked;
    try {
      picked = await _imagePicker.pickImage(source: source, imageQuality: 90);
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatRoomScreen] pickImage gagal: $e');
      if (mounted) {
        AppToast.show(context, 'Gagal membuka kamera/galeri',
            kind: ToastKind.error);
      }
      return;
    }
    if (picked == null) return;

    final clientMsgId = newClientMsgId();
    final compressedPath = await _compressForChatUpload(File(picked.path));
    _pendingImagePaths[clientMsgId] = compressedPath;

    final optimistic = ChatMessage(
      id: clientMsgId,
      sender: ChatSender.customer,
      type: ChatMsgType.image,
      // F3 — clock-skew guard sama seperti `_onSendText`, lihat docstring
      // `_nextOptimisticCreatedAtNow`/`nextOptimisticCreatedAt`.
      createdAt: _nextOptimisticCreatedAtNow(),
      clientMsgId: clientMsgId,
      status: ChatSendStatus.sending,
      isOptimistic: true,
    );
    if (!mounted) return;
    setState(() => _messages.add(optimistic));
    _scrollToBottom();

    try {
      await chatService.sendImage(compressedPath, clientMsgId: clientMsgId);
      if (!mounted) return;
      setState(() => _replaceStatus(clientMsgId, ChatSendStatus.sent));
      // Analitik — funnel MVP chat (spec §11): SUKSES kirim saja.
      AppAnalytics.logEvent('customer_message_sent', {'type': 'image'});
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[ChatRoomScreen] sendImage gagal: $e');
      if (!mounted) return;
      setState(() => _replaceStatus(clientMsgId, ChatSendStatus.failed));
      // Path lokal SENGAJA dipertahankan di `_pendingImagePaths` (bukan
      // dihapus) — retry (`_onRetry`) butuh file itu lagi utk kirim ulang.
    } catch (e) {
      // Non-ApiException juga harus memindahkan bubble ke `failed` (path
      // lokal tetap dipertahankan utk retry).
      if (kDebugMode) {
        debugPrint('[ChatRoomScreen] sendImage gagal (non-Api): $e');
      }
      if (!mounted) return;
      setState(() => _replaceStatus(clientMsgId, ChatSendStatus.failed));
    }
  }

  /// Bottom sheet 2 opsi (kamera/galeri) — pola sama dgn
  /// `update_profile_photo_sheet.dart`, disederhanakan (tanpa opsi hapus,
  /// tak relevan utk kirim foto chat) & pakai token warna chat
  /// (`NataloColors`) konsisten dgn sisa layar ini.
  Future<ImageSource?> _pickImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: NataloColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: NataloColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined,
                    color: NataloColors.primary),
                title: const Text('Ambil Foto'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: NataloColors.primary),
                title: const Text('Pilih dari Galeri'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }

  /// Kompres foto sebelum upload — mirror
  /// `FeedPhotoService._compressForUpload`: skip kalau file sudah ≤1.5MB
  /// (sudah aman di bawah limit body request Vercel), selain itu resize ke
  /// max 1920×1920 quality 75 JPEG. Return path original kalau compress
  /// gagal (graceful fallback, bukan throw — foto kecil tetap harus bisa
  /// terkirim meski compressor error).
  Future<String> _compressForChatUpload(File source) async {
    try {
      final originalBytes = await source.length();
      if (originalBytes <= 1.5 * 1024 * 1024) return source.path;

      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}/chat_compressed_'
          '${DateTime.now().millisecondsSinceEpoch}.jpg';

      final compressed = await FlutterImageCompress.compressAndGetFile(
        source.path,
        outputPath,
        minWidth: 1920,
        minHeight: 1920,
        quality: 75,
        format: CompressFormat.jpeg,
      );
      return compressed?.path ?? source.path;
    } catch (_) {
      return source.path;
    }
  }

  @override
  void dispose() {
    _stopPolling();
    WidgetsBinding.instance.removeObserver(this);
    pushNotificationService.notificationRefreshTick.removeListener(
      _onFcmWakeTick,
    );
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _chatId == null) {
      // Teruskan `productContext` (F9) — supaya prompt login bisa redirect
      // balik ke `/chat` DENGAN context produk utuh setelah login sukses,
      // bukan cuma ke `/member` generic (lihat `_ChatLoginRequiredScaffold`).
      return _ChatLoginRequiredScaffold(productContext: widget.productContext);
    }

    return Scaffold(
      backgroundColor: NataloColors.surface,
      appBar: const _ChatHeader(),
      // Tanpa SafeArea di sini SENGAJA — `_ChatHeader` (appBar) sudah
      // menangani inset atas (status bar) via `SafeArea(bottom: false)`
      // sendiri, dan footer (`ChatComposer`/`_ChatMaintenanceBanner`) sudah
      // menangani inset bawah (home indicator/gesture bar) via
      // `SafeArea(top: false)` masing-masing. Bungkus SafeArea lagi di sini
      // akan DOBEL reservasi inset bawah (composer ketarik naik 2x lipat).
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          AnimatedBuilder(
            animation: chatStore,
            builder: (context, _) => _buildFooter(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    // Room 401/403 (F8) — sembunyikan composer/banner sepenuhnya. Tanpa ini,
    // user bisa mengetik & "kirim" ke room yang tak akan pernah menampilkan
    // hasilnya (`_buildBody` sudah berhenti merender `_messages` begitu
    // `_authError` true) — kirim yang seolah menghilang ke ruang hampa.
    if (_authError) return const SizedBox.shrink();
    if (!chatStore.chatEnabled) {
      return const _ChatMaintenanceBanner();
    }
    return ChatComposer(
      controller: _composerController,
      onAttachPhoto: _onAttachPhoto,
      onSend: _onSendText,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: NataloColors.primary),
      );
    }
    if (_authError) {
      return _buildAuthErrorState();
    }
    if (_loadError != null) {
      return AppErrorState(
        variant: appErrorVariantFromError(_loadError),
        onRetry: _loadMessages,
      );
    }
    if (_messages.isEmpty) {
      return const AppEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Mulai percakapan dengan Natalo Petshop',
        subtitle: 'Tim kami siap bantu pertanyaan produk & pesananmu.',
      );
    }

    final showResolvedNote = _roomStatus == 'resolved';
    final itemCount = _messages.length + (showResolvedNote ? 1 : 0);

    // NataloPawRefreshIndicator butuh child scrollable dgn
    // AlwaysScrollableScrollPhysics supaya overscroll notification tetap
    // fire (dan pull-to-refresh tetap bisa dipicu) walau konten pendek —
    // pola sama dgn layar lain yang pakai widget ini (mis. wishlist_screen).
    return NataloPawRefreshIndicator(
      onRefresh: _onPullToRefresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (showResolvedNote && index == _messages.length) {
            return const _ResolvedNote();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _buildMessageItem(_messages[index]),
          );
        },
      ),
    );
  }

  /// State dead-end KHUSUS untuk chatId asing/sesi habis (F8) — beda dari
  /// `AppErrorState` generic bawaan `_loadError` (yang default nawarin
  /// "Coba lagi" ke fetch yang PASTI gagal lagi selama sesi belum diganti).
  /// Dua jalan keluar: "Login ulang" (redirect ke `/member/login`, biar
  /// user sadar sesinya sudah tak valid) atau "Kembali" (pop layar ini).
  Widget _buildAuthErrorState() {
    return AppErrorState(
      variant: AppErrorVariant.generic,
      title: 'Percakapan tidak tersedia',
      description:
          'Percakapan ini tidak tersedia untuk akun ini. Coba login ulang '
          'atau kembali.',
      retryLabel: 'Login ulang',
      onRetry: () => Navigator.pushNamed(context, '/member/login'),
      secondaryAction: TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Kembali'),
      ),
    );
  }

  /// Dispatch render KEY OFF `type`, BUKAN `sender` — proyeksi proxy
  /// customer (`projectMessageForCustomer`) SELALU menormalisasi
  /// `senderRole` mentah 'system' jadi 'customer' sebelum sampai client,
  /// jadi kalau dispatch pakai sender, pesan sistem/auto akan salah
  /// dirender sebagai bubble customer biasa alih-alih catatan sistem.
  Widget _buildMessageItem(ChatMessage message) {
    if (message.type == ChatMsgType.system) {
      return ChatSystemNote(message: message);
    }

    final isCustomer = message.sender == ChatSender.customer;
    final Widget content;

    switch (message.type) {
      case ChatMsgType.product:
        final product = message.product;
        content = product != null
            ? ChatProductCard(product: product)
            : ChatBubble(message: message, onRetry: () => _onRetry(message));
        break;
      case ChatMsgType.image:
        // Thumbnail lokal (`_pendingImagePaths`) diprioritaskan otomatis
        // oleh `ChatImageMessage` selama masih ada — begitu versi server
        // direkonsiliasi (`_mergeIncoming` hapus entry-nya), fallback ke
        // `imageUrl` network di render berikutnya.
        final localPath = message.clientMsgId != null
            ? _pendingImagePaths[message.clientMsgId]
            : null;
        content = ChatImageMessage(
          imageUrl: message.imageUrl,
          localFile: localPath != null ? File(localPath) : null,
        );
        break;
      case ChatMsgType.productContext:
      case ChatMsgType.orderContext:
        // Belum ada jalur proxy yang benar-benar menerbitkan tipe ini
        // terpisah hari ini (context produk/pesanan datang menempel di
        // pesan `type: text`, ditangani `ChatBubble` sendiri via
        // `ChatContextChip`) — cabang ini menjaga UI tetap benar kalau
        // proxy suatu saat mengirim tipe ini secara eksplisit.
        content = (message.product != null || message.order != null)
            ? ChatContextChip(
                product: message.product,
                order: message.order,
                isCustomer: isCustomer,
              )
            : ChatBubble(message: message, onRetry: () => _onRetry(message));
        break;
      case ChatMsgType.text:
      case ChatMsgType.system:
        content =
            ChatBubble(message: message, onRetry: () => _onRetry(message));
        break;
    }

    return Row(
      mainAxisAlignment:
          isCustomer ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [content],
    );
  }
}

/// Header custom (bukan `AppBar` default) — avatar inisial "N", judul, dan
/// status jam operasional yang bereaksi ke `chatStore.online` (dihitung
/// SERVER dari `GET /api/chat/config`, klien tidak menebak dari timestamp
/// lokal — fix B3 Plan 2/4).
class _ChatHeader extends StatelessWidget implements PreferredSizeWidget {
  const _ChatHeader();

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: NataloColors.white,
        border: Border(bottom: BorderSide(color: NataloColors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: NataloColors.textPrimary,
                ),
              ),
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: NataloColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  'N',
                  style: TextStyle(
                    color: NataloColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Natalo Petshop',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: NataloColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedBuilder(
                      animation: chatStore,
                      builder: (context, _) =>
                          _StatusRow(online: chatStore.online),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final bool online;

  const _StatusRow({required this.online});

  @override
  Widget build(BuildContext context) {
    if (online) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: NataloColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'Online',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: NataloColors.success,
            ),
          ),
        ],
      );
    }
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.access_time_rounded,
            size: 11, color: NataloColors.textTertiary),
        SizedBox(width: 4),
        Text(
          'Di luar jam operasional',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: NataloColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// Banner pengganti composer saat kill-switch OFF (`!chatStore.chatEnabled`)
/// — riwayat tetap scrollable, cuma jalur kirim yang ditutup.
class _ChatMaintenanceBanner extends StatelessWidget {
  const _ChatMaintenanceBanner();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: NataloColors.white,
        border: Border(top: BorderSide(color: NataloColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: AppInfoBanner(
            message:
                'Chat sedang dalam pemeliharaan. Riwayat tetap bisa dibaca.',
            icon: Icons.build_rounded,
            color: NataloColors.warning,
          ),
        ),
      ),
    );
  }
}

/// Catatan ramah saat room `resolved` — lihat docstring `_roomStatus` pada
/// state (belum ada sumber data hari ini, plumbing disiapkan untuk proxy
/// masa depan).
class _ResolvedNote extends StatelessWidget {
  const _ResolvedNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: NataloColors.surfaceVariant,
            borderRadius: AppRadius.medium,
            border: Border.all(color: NataloColors.border),
          ),
          child: const Text(
            'Percakapan ditandai selesai. Kirim pesan lagi untuk melanjutkan.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: NataloColors.textSecondary,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

/// Prompt login — dipakai kalau `chatId` tak bisa di-resolve (tak ada
/// argumen rute eksplisit DAN `memberStore.profile` kosong). `AppChatButton`
/// dipasang di beberapa layar publik (mis. Beranda) yang tak mensyaratkan
/// login, jadi entry point ini harus tetap aman diakses guest.
///
/// **Redirect-back setelah login (F9):** pakai konvensi `arguments:
/// {'redirect': ..., 'arguments': ...}` yang sudah dipakai `cart_screen.dart`
/// ({'redirect': '/checkout'}) — `LoginScreen._login` (login_screen.dart)
/// sukses login SELALU memanggil `Navigator.pushNamedAndRemoveUntil(
/// redirectRoute ?? '/member', (route) => false, arguments:
/// redirectArguments)`. Predicate `(route) => false` membuang SELURUH
/// route di bawahnya (termasuk `ChatRoomScreen`/layar ini sendiri) —
/// route itu DIHAPUS, bukan di-pop, jadi `Future` dari
/// `Navigator.pushNamed('/member/login')` TIDAK PERNAH complete (tak ada
/// `didComplete` yang dipanggil untuk route yang dihapus, bukan di-pop).
/// Pola "await push lalu re-init screen yang sama" karena itu TIDAK
/// applicable di sini — solusi yang robust & minimal justru memakai
/// redirect argument yang sudah ada: `/member/login` diberi
/// `{'redirect': '/chat', 'arguments': productContext}`, sehingga
/// `LoginScreen` sendiri yang mem-push `/chat` (route baru, main.dart sudah
/// tolerant `arguments is Map<String, dynamic>` -> `ChatRoomScreen(
/// productContext: ...)`) begitu login sukses — chat TERBUKA LANGSUNG
/// dengan context produk utuh, tanpa perlu listener/`AnimatedBuilder`
/// tambahan ke `memberStore`.
class _ChatLoginRequiredScaffold extends StatelessWidget {
  const _ChatLoginRequiredScaffold({this.productContext});

  /// Diteruskan dari `ChatRoomScreen.widget.productContext` — ikut dibawa
  /// sebagai redirect argument supaya tak hilang kalau guest masuk dari
  /// "Tanya Produk Ini" (product_detail_screen.dart).
  final Map<String, dynamic>? productContext;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NataloColors.surface,
      appBar: AppBar(title: const Text('Natalo Petshop')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 76,
                width: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: NataloColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: NataloColors.primary,
                  size: 36,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Login member diperlukan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: NataloColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Masuk untuk mulai chat dengan tim Natalo Petshop.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NataloColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(
                  context,
                  '/member/login',
                  arguments: {
                    'redirect': '/chat',
                    if (productContext != null) 'arguments': productContext,
                  },
                ),
                child: const Text('Masuk Member'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
