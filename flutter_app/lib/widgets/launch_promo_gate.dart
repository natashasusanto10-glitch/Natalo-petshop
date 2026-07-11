import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/launch_popup.dart';
import '../screens/onboarding_screen.dart';
import '../services/app_analytics.dart';
import '../services/connectivity_service.dart';
import '../services/deep_link_service.dart';
import '../services/product_service.dart';
import '../services/push_notification_service.dart';
import '../state/member_store.dart';
import 'launch_promo_decision.dart';
import 'launch_promo_dialog.dart';

/// Gate di rantai MaterialApp.builder: setelah frame pertama, evaluasi
/// kondisi (sekali per mount = sekali per cold start) lalu tampilkan popup
/// pembuka via showGeneralDialog pada root navigator.
///
/// Konten popup ADMIN-MANAGED: fetch GET /api/launch-popup (gambar penuh
/// gaya Shopee + tombol X). API kosong / fetch gagal / gambar gagal
/// di-precache → tidak tampil apa-apa (tanpa fallback hardcoded).
///
/// Semua seam (popupProvider, isLoggedIn, dll) opsional — default null
/// menunjuk implementasi produksi (singleton). Test menyuntik fake supaya
/// hermetik & bebas shimmer/navigator nyata.
class LaunchPromoGate extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  final Future<LaunchPopup?> Function()? popupProvider;
  final Future<void> Function()? ensureAuthReady;
  final bool Function()? isLoggedIn;
  final Future<bool> Function()? hasSeenOnboarding;
  final bool Function()? isOnline;
  final bool Function()? launchedExternally;
  final bool Function()? routeStackedAboveHome;

  /// Precache gambar popup — return false = gambar rusak/timeout → skip
  /// popup total (spec: JANGAN tampilkan dialog dengan gambar kosong).
  final Future<bool> Function(String url)? preloadImage;
  final Future<LaunchPromoOutcome> Function(BuildContext, LaunchPopup)?
      showDialogFn;
  final Future<void> Function(String href)? openHref;
  final Future<void> Function(String, Map<String, Object>)? logEvent;
  final Duration settleDelay;

  const LaunchPromoGate({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.popupProvider,
    this.ensureAuthReady,
    this.isLoggedIn,
    this.hasSeenOnboarding,
    this.isOnline,
    this.launchedExternally,
    this.routeStackedAboveHome,
    this.preloadImage,
    this.showDialogFn,
    this.openHref,
    this.logEvent,
    // 2000ms: tunggu AppStartupSplash (opaque ~1400ms + fade ~360ms ≈ 1760ms)
    // selesai dulu supaya popup muncul & beranimasi DI ATAS Beranda, bukan di
    // balik splash; sekaligus memberi margin lebih untuk flag launchedFromColdPush
    // (di-set setelah Firebase getInitialMessage) resolve sebelum keputusan.
    this.settleDelay = const Duration(milliseconds: 2000),
  });

  @override
  State<LaunchPromoGate> createState() => _LaunchPromoGateState();
}

class _LaunchPromoGateState extends State<LaunchPromoGate> {
  bool _ran = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  // ── seam resolvers (fake bila di-inject, else produksi) ──
  Future<LaunchPopup?> _popup() =>
      (widget.popupProvider ?? productService.fetchLaunchPopup)();

  Future<void> _ensureAuthReady() =>
      (widget.ensureAuthReady ?? _realEnsureAuthReady)();

  bool _isLoggedIn() => (widget.isLoggedIn ?? () => memberStore.isLoggedIn)();

  Future<bool> _hasSeenOnboarding() =>
      (widget.hasSeenOnboarding ?? OnboardingScreen.hasSeen)();

  bool _isOnline() => (widget.isOnline ?? () => connectivityService.isOnline)();

  bool _launchedExternally() =>
      (widget.launchedExternally ??
          () =>
              deepLinkService.launchedFromDeepLink ||
              pushNotificationService.launchedFromColdPush)();

  bool _routeStacked() =>
      (widget.routeStackedAboveHome ??
          () => widget.navigatorKey.currentState?.canPop() ?? false)();

  Future<bool> _preload(String url) =>
      (widget.preloadImage ?? _realPreloadImage)(url);

  Future<void> _openHref(String href) =>
      (widget.openHref ??
          (h) async => deepLinkService.handleExternalUri(h))(href);

  Future<void> _log(String name, Map<String, Object> params) =>
      (widget.logEvent ?? AppAnalytics.logEvent)(name, params);

  Future<LaunchPromoOutcome> _show(LaunchPopup p) {
    final ctx = widget.navigatorKey.currentContext ?? context;
    final fn = widget.showDialogFn ??
        (context, popup) => showLaunchPromoDialog(context, popup: popup);
    return fn(ctx, p);
  }

  /// Precache produksi: gambar HARUS sudah di cache sebelum dialog dibuka
  /// supaya popup muncul utuh seketika (tanpa shimmer/blank). Timeout 8s +
  /// error apa pun → false (skip popup, jangan tampilkan kotak kosong).
  /// Context di-resolve DI SINI (sync, tepat setelah cek mounted) supaya
  /// tidak ada BuildContext yang menyeberang async gap di _maybeShow.
  Future<bool> _realPreloadImage(String url) async {
    if (url.isEmpty || !mounted) return false;
    final ctx = widget.navigatorKey.currentContext ?? context;
    try {
      await precacheImage(CachedNetworkImageProvider(url), ctx)
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Tunggu memberStore selesai load profil dari disk (isLoggedIn bisa
  /// berubah false→true async). Timeout 3s sebagai jaring pengaman.
  Future<void> _realEnsureAuthReady() async {
    if (memberStore.initialized) return;
    final completer = Completer<void>();
    void listener() {
      if (memberStore.initialized && !completer.isCompleted) {
        memberStore.removeListener(listener);
        completer.complete();
      }
    }

    memberStore.addListener(listener);
    try {
      await completer.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // biarkan — pakai state login apa adanya.
    } finally {
      memberStore.removeListener(listener);
    }
  }

  Future<void> _maybeShow() async {
    if (_ran) return;
    _ran = true; // evaluasi sekali per mount

    // Fetch popup PARALEL dengan auth-ready + settle delay — API call
    // biasanya selesai jauh sebelum delay 2000ms habis, jadi tidak
    // menambah waktu tunggu.
    final popupFuture = _popup();

    await _ensureAuthReady();
    if (!mounted) return;
    if (widget.settleDelay > Duration.zero) {
      await Future<void>.delayed(widget.settleDelay);
    }
    if (!mounted) return;

    LaunchPopup? popup;
    try {
      popup = await popupFuture;
    } catch (_) {
      return; // fetch gagal → tidak tampil apa-apa
    }
    if (!mounted || popup == null || popup.imageUrl.isEmpty) return;

    final show = launchPromoShouldShow(
      hasCampaign: true,
      memberOnly: popup.memberOnly,
      isLoggedIn: _isLoggedIn(),
      hasSeenOnboarding: await _hasSeenOnboarding(),
      isOnline: _isOnline(),
      launchedExternally: _launchedExternally(),
      routeStackedAboveHome: _routeStacked(),
    );
    if (!mounted || !show) return;

    // Gambar rusak/timeout → skip total (spec: fallback = tidak muncul).
    final imageReady = await _preload(popup.imageUrl);
    if (!mounted || !imageReady) return;

    await _log('launch_popup_shown', {'campaign_id': popup.id});
    if (!mounted) return; // tree torn down selama await log → jangan tampilkan dialog
    final outcome = await _show(popup);
    // Tidak perlu cek mounted di sini: _log & _openHref pakai singleton
    // global (AppAnalytics, deepLinkService), bukan context widget ini —
    // aksi CTA yang user minta harus tetap jalan walau gate sudah dispose.
    if (outcome == LaunchPromoOutcome.cta && popup.href != null) {
      await _log('launch_popup_cta_click', {'campaign_id': popup.id});
      await _openHref(popup.href!);
    } else {
      await _log('launch_popup_dismiss', {'campaign_id': popup.id});
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
