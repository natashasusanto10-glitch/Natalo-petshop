import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../services/api_client.dart';
import '../services/chat_service.dart';
import '../state/chat_store.dart';
import '../state/member_store.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/natalo_colors.dart';
import '../widgets/app_ui.dart';
import '../widgets/chat/chat_bubble.dart';
import '../widgets/chat/chat_composer.dart';
import '../widgets/chat/chat_image_message.dart';
import '../widgets/chat/chat_product_card.dart';
import '../widgets/chat/chat_system_note.dart';

/// Layar chat customer <-> staff (satu room per customer, 1:1 dgn NLCATTER).
///
/// Full UI (Task 4): header status jam operasional, daftar pesan (bubble
/// teks, kartu produk, foto, catatan sistem/otomatis), composer teks dgn
/// kirim optimistic dasar. Mesin runtime (retry sungguhan, kirim foto,
/// polling, lifecycle, load-more, mark-read) menyusul di Task 5 — lihat
/// TODO di `_loadMessages`.
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

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _chatId;
  bool _loading = true;
  Object? _loadError;

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
      final page = await chatService.fetchMessages(chatId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        _loading = false;
      });
      _scrollToBottom(animate: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatRoomScreen] fetchMessages gagal: $e');
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
    // TODO(Task 5): Timer.periodic(4s) polling saat layar tampak (dedupe by
    // id/clientMsgId) + WidgetsBindingObserver (stop di background, fetch
    // sekali + resume di foreground) + listener
    // pushNotificationService.notificationRefreshTick (wake FCM) +
    // load-more riwayat lewat ChatMessagesPage.nextCursor saat scroll ke
    // atas + reconciliation mark-read (chatStore.setUnread(0) setelah GET,
    // yang di server sudah reset unreadForCustomer — lihat fix C2 Plan 2).
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

  /// Kirim teks optimistic dasar — tampilkan bubble `sending` segera, lalu
  /// update jadi `sent`/`failed` sesuai hasil `chatService.sendText`.
  /// Rekonsiliasi penuh dgn versi server (via poll + `clientMsgId` dedupe)
  /// serta retry yang benar-benar mengirim ulang = Task 5.
  Future<void> _onSendText(String text) async {
    final clientMsgId = newClientMsgId();
    final optimistic = ChatMessage(
      id: clientMsgId,
      sender: ChatSender.customer,
      type: ChatMsgType.text,
      text: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      clientMsgId: clientMsgId,
      status: ChatSendStatus.sending,
    );

    _composerController.clear();
    setState(() => _messages.add(optimistic));
    _scrollToBottom();

    // Konteks produk/pesanan (entry dari Detail Produk) HANYA nempel di
    // pesan pertama yang benar-benar dicoba kirim sesi ini.
    final sendContext = _contextSent ? null : widget.productContext;
    _contextSent = true;

    try {
      // Oper `clientMsgId` yang SAMA dgn bubble optimistic — supaya baris
      // server yang datang di poll berikutnya (proyeksi proxy MEMBAWA
      // `clientMsgId`) bisa direkonsiliasi dgn bubble ini, dan retry (Task
      // 5) mengirim ulang id yang sama → proxy dedupe idempoten (tanpa ini,
      // ChatService akan generate id berbeda → optimistic & server row tak
      // pernah bisa di-match).
      await chatService.sendText(
        text,
        context: sendContext,
        clientMsgId: clientMsgId,
      );
      if (!mounted) return;
      setState(() => _replaceStatus(clientMsgId, ChatSendStatus.sent));
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[ChatRoomScreen] sendText gagal: $e');
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
      auto: m.auto,
    );
  }

  void _onRetry(ChatMessage message) {
    // TODO(Task 5): kirim ulang lewat `chatService.sendText(text,
    // clientMsgId: message.clientMsgId)` — pakai `clientMsgId` YANG SAMA
    // dgn bubble ini (sekarang bisa, karena `sendText` menerima param
    // clientMsgId dan `_onSendText` sudah mengoper id bubble optimistic-nya)
    // → proxy dedupe idempoten (`writeCustomerMessage` di `lib/chat/rooms.ts`)
    // supaya retry tidak menggandakan pesan kalau percobaan pertama
    // sebenarnya sudah sukses di server tapi client cuma gagal baca response.
    // Sengaja no-op di Task 4 — brief eksplisit menaruh retry sungguhan di
    // Task 5.
  }

  void _onAttachPhoto() {
    // TODO(Task 5): image_picker (kamera/galeri) + kompresi (pola
    // feed_photo_service.dart) + thumbnail optimistic lokal +
    // chatService.sendImage.
  }

  @override
  void dispose() {
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _chatId == null) {
      return const _ChatLoginRequiredScaffold();
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

    return ListView.builder(
      controller: _scrollController,
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
        content = ChatImageMessage(imageUrl: message.imageUrl);
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
class _ChatLoginRequiredScaffold extends StatelessWidget {
  const _ChatLoginRequiredScaffold();

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
                onPressed: () => Navigator.pushNamed(context, '/member/login'),
                child: const Text('Masuk Member'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
