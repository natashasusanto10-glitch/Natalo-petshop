import 'dart:async';

import 'package:flutter/material.dart';

import '../config/launch_popup_campaigns.dart';
import '../models/launch_popup_campaign.dart';
import '../screens/onboarding_screen.dart';
import '../services/app_analytics.dart';
import '../services/connectivity_service.dart';
import '../services/deep_link_service.dart';
import '../services/push_notification_service.dart';
import '../state/member_store.dart';
import 'launch_promo_decision.dart';
import 'launch_promo_dialog.dart';

/// Gate di rantai MaterialApp.builder: setelah frame pertama, evaluasi
/// kondisi (sekali per mount = sekali per cold start) lalu tampilkan popup
/// pembuka via showGeneralDialog pada root navigator.
///
/// Semua seam (campaignProvider, isLoggedIn, dll) opsional — default null
/// menunjuk implementasi produksi (singleton). Test menyuntik fake supaya
/// hermetik & bebas shimmer/navigator nyata.
class LaunchPromoGate extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  final LaunchPopupCampaign? Function()? campaignProvider;
  final Future<void> Function()? ensureAuthReady;
  final bool Function()? isLoggedIn;
  final Future<bool> Function()? hasSeenOnboarding;
  final bool Function()? isOnline;
  final bool Function()? launchedExternally;
  final bool Function()? routeStackedAboveHome;
  final Future<LaunchPromoOutcome> Function(BuildContext, LaunchPopupCampaign)?
      showDialogFn;
  final Future<void> Function(String href)? openHref;
  final Future<void> Function(String, Map<String, Object>)? logEvent;
  final Duration settleDelay;

  const LaunchPromoGate({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.campaignProvider,
    this.ensureAuthReady,
    this.isLoggedIn,
    this.hasSeenOnboarding,
    this.isOnline,
    this.launchedExternally,
    this.routeStackedAboveHome,
    this.showDialogFn,
    this.openHref,
    this.logEvent,
    this.settleDelay = const Duration(milliseconds: 900),
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
  LaunchPopupCampaign? _campaign() =>
      (widget.campaignProvider ?? activeLaunchPopup)();

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

  Future<void> _openHref(String href) =>
      (widget.openHref ??
          (h) async => deepLinkService.handleExternalUri(h))(href);

  Future<void> _log(String name, Map<String, Object> params) =>
      (widget.logEvent ?? AppAnalytics.logEvent)(name, params);

  Future<LaunchPromoOutcome> _show(LaunchPopupCampaign c) {
    final ctx = widget.navigatorKey.currentContext ?? context;
    final fn = widget.showDialogFn ??
        (context, camp) => showLaunchPromoDialog(context, campaign: camp);
    return fn(ctx, c);
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

    final campaign = _campaign();
    if (campaign == null) return;

    await _ensureAuthReady();
    if (!mounted) return;
    if (widget.settleDelay > Duration.zero) {
      await Future<void>.delayed(widget.settleDelay);
    }
    if (!mounted) return;

    final show = launchPromoShouldShow(
      hasCampaign: true,
      isLoggedIn: _isLoggedIn(),
      hasSeenOnboarding: await _hasSeenOnboarding(),
      isOnline: _isOnline(),
      launchedExternally: _launchedExternally(),
      routeStackedAboveHome: _routeStacked(),
    );
    if (!mounted || !show) return;

    await _log('launch_popup_shown', {'campaign_id': campaign.id});
    if (!mounted) return; // tree torn down selama await log → jangan tampilkan dialog
    final outcome = await _show(campaign);
    // Tidak perlu cek mounted di sini: _log & _openHref pakai singleton
    // global (AppAnalytics, deepLinkService), bukan context widget ini —
    // aksi CTA yang user minta harus tetap jalan walau gate sudah dispose.
    if (outcome == LaunchPromoOutcome.cta && campaign.hasCta) {
      await _log('launch_popup_cta_click', {'campaign_id': campaign.id});
      await _openHref(campaign.ctaHref!);
    } else {
      await _log('launch_popup_dismiss', {'campaign_id': campaign.id});
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
