import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'models/app_notification.dart';
import 'models/cart_item.dart';
import 'models/member_profile.dart';
import 'models/product.dart';
import 'screens/account_security_screen.dart';
import 'screens/account_settings_screen.dart';
import 'screens/all_brands_screen.dart';
import 'screens/announcement_detail_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/help_center_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/login_otp_screen.dart';
import 'screens/member_addresses_screen.dart';
import 'screens/member_loyalty_history_screen.dart';
import 'screens/member_loyalty_screen.dart';
import 'screens/member_order_detail_screen.dart';
import 'screens/member_orders_screen.dart';
import 'screens/member_post_detail_screen.dart';
import 'screens/member_post_edit_screen.dart';
import 'screens/member_posts_screen.dart';
import 'screens/member_profile_screen.dart';
import 'screens/member_reviews_screen.dart';
import 'screens/member_screen.dart';
import 'screens/member_vouchers_screen.dart';
import 'models/my_feed_post.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/notification_preferences_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/register_screen.dart';
import 'screens/static_info_screen.dart';
import 'state/cart_store.dart';
import 'state/feed_local_store.dart';
import 'state/member_store.dart';
import 'state/recently_viewed_store.dart';
import 'state/search_history_store.dart';
import 'state/settings_store.dart';
import 'state/trending_placeholder_controller.dart';
import 'utils/motion_prefs.dart';
import 'utils/read_only_mode.dart';
import 'screens/products_screen.dart';
import 'screens/wishlist_screen.dart';
import 'services/analytics_observer.dart';
import 'services/app_analytics.dart';
import 'services/app_crashlytics.dart';
import 'services/connectivity_service.dart';
import 'services/video_quality_service.dart';
import 'services/deep_link_service.dart';
import 'services/push_notification_service.dart';
import 'services/quick_actions_service.dart';
import 'theme/natalo_colors.dart';
import 'theme/natalo_theme.dart';
import 'widgets/app_error_widget.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/offline_banner.dart';
import 'widgets/read_only_welcome_gate.dart';

/// Global navigator key — dipakai DeepLinkService untuk navigate dari luar
/// widget tree (saat receive incoming URI dari native intent).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Initial route resolved sebelum runApp — onboarding kalau first launch,
/// home kalau sudah pernah lihat. Future di-await di main().
late final String _initialRoute;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase core init — wajib sebelum messaging/crashlytics/analytics dipakai.
  // Pakai DefaultFirebaseOptions yang di-generate FlutterFire CLI dari
  // google-services.json (Android) + GoogleService-Info.plist (iOS). Wrap
  // try/catch supaya kalau platform tidak ada config (mis. forgot to
  // download plist), app tetap boot — Firebase feature jadi no-op.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('[main] Firebase init failed: $e');
  }
  // Custom branded error widget — replace Flutter default red "Bad state"
  // screen. Debug build: show full stacktrace. Release: friendly UI +
  // crashlytics report fire-and-forget.
  ErrorWidget.builder = AppErrorWidget.builder;
  // Edge-to-edge layout — content extend ke balik status bar + nav bar.
  // Status bar icon adaptive: dark icon di light theme, light di dark.
  // Bottom nav bar transparent supaya gesture nav Android 12+ kelihatan.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark, // light theme default
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  // Cek onboarding flag sebelum kasih ke MaterialApp.initialRoute.
  // Pakai await singkat (~5ms baca SharedPreferences) supaya first paint
  // langsung ke screen yang benar tanpa flicker.
  _initialRoute = await OnboardingScreen.hasSeen() ? '/' : '/onboarding';
  // Load read-only mode flag — default ON sampai user explicit toggle off
  // di Settings. Service mutation throws ReadOnlyModeException kalau
  // dipanggil saat ON, supaya database Capacitor tidak ke-mutate dari
  // Flutter testing.
  await readOnlyMode.initialize();
  // Motion preference — respect OS reduce-motion + user manual toggle.
  // Widget animations check via `MotionPrefs.shouldReduce(context)`.
  await motionPrefs.initialize();
  memberStore.initialize();
  // Settings store (theme mode dll) di-initialize sebelum runApp supaya
  // first paint pakai theme yang benar (light vs dark vs system).
  appSettingsStore.initialize();
  // Restore cart dari disk supaya item yang user tambah survive app restart.
  // Match offline-first pattern — cart tetap ada walau tutup app sebelum sync.
  cartStore.loadFromDisk();
  // Recently viewed — load history dari disk supaya Home carousel
  // langsung populated saat user buka app.
  recentlyViewedStore.loadFromDisk();
  // Search history — load query history dari disk supaya Home
  // "Rekomendasi Untukmu" bisa langsung pakai keyword behavior user.
  searchHistoryStore.initialize();
  // Trending placeholder — fetch trending search terms untuk dynamic
  // placeholder di search bar Beranda. Fire-and-forget; loads fallback
  // first kalau API belum respond.
  trendingPlaceholderController.initialize();
  // Feed local store — liked posts cache (#7) + offline feed cache (#11).
  // Fire-and-forget; feed_screen also re-init defensively saat first open.
  feedLocalStore.initialize();
  // Initialize deep link listener — handle URI yang buka app + URI yang
  // datang saat app sudah running. Idempotent kalau dipanggil ulang.
  deepLinkService.initialize(rootNavigatorKey);
  // Register launcher quick actions (long-press app icon → shortcut).
  AppQuickActions.initialize(rootNavigatorKey);
  // Initialize FCM push notification — gracefully no-op kalau Firebase
  // belum di-setup (lihat FIREBASE_SETUP.md).
  pushNotificationService.initialize(rootNavigatorKey);
  // Initialize Crashlytics — auto-report crashes. Aman dipanggil sebelum
  // ada user (setUserId akan di-call nanti saat login). Hook
  // FlutterError.onError + PlatformDispatcher.onError untuk capture
  // semua jenis error.
  AppCrashlytics.initialize();
  // Initialize Analytics — track funnel events di release build, no-op
  // di debug supaya dashboard tidak polluted dengan dev data.
  AppAnalytics.initialize();
  // Subscribe ke native connectivity changes — banner offline auto-show
  // saat WiFi/data hilang.
  connectivityService.initialize();
  // Sprint 2 #7 — Video quality service. Listen network tier supaya
  // feed player auto-switch URL quality (WiFi HLS, mobile MP4 480/720p).
  videoQualityService.initialize();
  runApp(const NataloPetshopApp());
}

class NataloPetshopApp extends StatelessWidget {
  const NataloPetshopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettingsStore,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          // Analytics observer — auto log screen view + crashlytics breadcrumb
          // setiap push/replace. Cover semua route tanpa per-screen edits.
          navigatorObservers: [nataloAnalyticsObserver],
          title: 'Natalo Petshop',
          debugShowCheckedModeBanner: false,
          theme: NataloTheme.lightTheme,
          darkTheme: NataloTheme.darkTheme,
          themeMode: appSettingsStore.themeMode,
          builder: (context, child) {
            // Solid background dari ThemeData.scaffoldBackgroundColor —
            // no gradient overlay. Faster rendering di HP murah, better
            // readability outdoor, familiar pattern untuk user Indonesia
            // (Tokopedia/Shopee style).
            return AppLockGate(
              child: ReadOnlyWelcomeGate(
                // ColoredBox provides bg behind transparent Scaffolds —
                // dipakai theme dark, ganti otomatis via Theme.of context.
                child: ColoredBox(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? NataloColors.feedBlack
                      : NataloColors.background,
                  child: Stack(
                    children: [
                      child ?? const SizedBox.shrink(),
                      // Offline banner di top — auto slide-in/out berdasar
                      // connectivity status. Z-index above semua screen.
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: OfflineBanner(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          initialRoute: _initialRoute,
          onGenerateRoute: (settings) {
            final page = switch (settings.name) {
              '/onboarding' => const OnboardingScreen(),
              '/' => const HomeScreen(),
              '/products' when settings.arguments is ProductCatalogArgs =>
                ProductsScreen(
                  selectedBrand:
                      (settings.arguments as ProductCatalogArgs).selectedBrand,
                  initialQuery:
                      (settings.arguments as ProductCatalogArgs).initialQuery,
                  initialCategory: (settings.arguments as ProductCatalogArgs)
                      .initialCategory,
                ),
              '/products' => ProductsScreen(
                  selectedBrand: settings.arguments is String
                      ? settings.arguments as String
                      : null,
                ),
              '/brands' => const AllBrandsScreen(),
              '/cart' => const CartScreen(),
              '/checkout' when settings.arguments is List<CartItem> =>
                CheckoutScreen(items: settings.arguments as List<CartItem>),
              '/checkout' => const CheckoutScreen(),
              '/notifications' => const NotificationsScreen(),
              '/announcement-detail'
                  when settings.arguments is AppNotification =>
                AnnouncementDetailScreen(
                  notification: settings.arguments as AppNotification,
                ),
              '/settings/notifications' =>
                const NotificationPreferencesScreen(),
              // Alias — beberapa caller pakai path baru, keep both untuk
              // backward compat sambil migrate semua usage.
              '/notifications/preferences' =>
                const NotificationPreferencesScreen(),
              '/account/settings' => const AccountSettingsScreen(),
              '/account/privacy' => const StaticInfoScreen.accountPrivacy(),
              '/account/security' => const AccountSecurityScreen(),
              '/wishlist' => const WishlistScreen(),
              '/bantuan' => const HelpCenterScreen(),
              '/help' => const HelpCenterScreen(),
              '/tentang-kami' => const StaticInfoScreen.about(),
              '/tentang-natalo' => const StaticInfoScreen.about(),
              '/about' => const StaticInfoScreen.about(),
              '/cara-pemesanan' => const StaticInfoScreen.orderGuide(),
              '/order-guide' => const StaticInfoScreen.orderGuide(),
              '/syarat-ketentuan' => const StaticInfoScreen.terms(),
              '/terms' => const StaticInfoScreen.terms(),
              '/kebijakan-privasi' => const StaticInfoScreen.privacyPolicy(),
              '/privacy-policy' => const StaticInfoScreen.privacyPolicy(),
              '/kebijakan-pengembalian' =>
                const StaticInfoScreen.returnPolicy(),
              '/return-policy' => const StaticInfoScreen.returnPolicy(),
              '/feed' => const FeedScreen(),
              '/member' => const MemberScreen(),
              '/member/login' => const LoginScreen(),
              '/member/login-otp' => const LoginOtpScreen(),
              '/member/register' => const RegisterScreen(),
              '/member/forgot-password' => const ForgotPasswordScreen(),
              '/member/profile' => const MemberProfileScreen(),
              '/member/addresses' => const MemberAddressesScreen(),
              '/member/orders' => const MemberOrdersScreen(),
              '/member/reviews' => const MemberReviewsScreen(),
              '/member/loyalty' => const MemberLoyaltyScreen(),
              '/member/loyalty/history' => const MemberLoyaltyHistoryScreen(),
              '/member/postingan' => const MemberPostsScreen(),
              // Alias EN — beberapa caller pakai /member/posts (profile
              // quick actions). Keep both untuk konsistensi.
              '/member/posts' => const MemberPostsScreen(),
              '/member/postingan-detail'
                  when settings.arguments is MyFeedPost =>
                MemberPostDetailScreen(post: settings.arguments as MyFeedPost),
              '/member/postingan-edit' when settings.arguments is MyFeedPost =>
                MemberPostEditScreen(post: settings.arguments as MyFeedPost),
              '/member/order-detail' when settings.arguments is OrderSummary =>
                MemberOrderDetailScreen(
                    order: settings.arguments as OrderSummary),
              '/member/vouchers' => const MemberVouchersScreen(),
              '/product-detail' when settings.arguments is Product =>
                ProductDetailScreen(product: settings.arguments as Product),
              _ => const HomeScreen(),
            };

            return _SmoothPageRoute(settings: settings, child: page);
          },
        );
      },
    );
  }
}

class _SmoothPageRoute extends PageRouteBuilder<void> {
  final Widget child;

  _SmoothPageRoute({required RouteSettings settings, required this.child})
      : super(
          settings: settings,
          transitionDuration: const Duration(milliseconds: 340),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final isRoot = settings.name == '/';
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            final offset = Tween<Offset>(
              begin: isRoot ? const Offset(0.04, 0.02) : const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved);
            final scale = Tween<double>(
              begin: isRoot ? 0.985 : 1,
              end: 1,
            ).animate(curved);

            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: offset,
                child: ScaleTransition(
                  scale: scale,
                  child: _SlideBackGesture(
                    enabled: !isRoot,
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
}

class _SlideBackGesture extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const _SlideBackGesture({
    required this.child,
    required this.enabled,
  });

  @override
  State<_SlideBackGesture> createState() => _SlideBackGestureState();
}

class _SlideBackGestureState extends State<_SlideBackGesture> {
  static const _edgeWidth = 30.0;
  static const _minimumDistance = 72.0;
  static const _minimumVelocity = 420.0;

  double _dragDistance = 0;

  void _reset() {
    _dragDistance = 0;
  }

  bool get _canPop {
    final route = ModalRoute.of(context);
    return widget.enabled &&
        route?.isCurrent == true &&
        Navigator.canPop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _edgeWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _reset(),
            onHorizontalDragUpdate: (details) {
              if (!_canPop) return;
              _dragDistance += details.primaryDelta ?? 0;
            },
            onHorizontalDragEnd: (details) {
              if (!_canPop) {
                _reset();
                return;
              }

              final velocity = details.primaryVelocity ?? 0;
              final shouldPop = _dragDistance > _minimumDistance ||
                  velocity > _minimumVelocity;
              _reset();
              if (shouldPop) Navigator.maybePop(context);
            },
          ),
        ),
      ],
    );
  }
}
