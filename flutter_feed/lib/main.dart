import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/feed_screen.dart';
import 'screens/upload_screen.dart';
import 'services/push_notifications.dart';

// Entry point — Riverpod ProviderScope + go_router + push init.
//
// To enable push notifications:
//   1. Add firebase_core init: `await Firebase.initializeApp(...)` before
//      `runApp` (requires google-services.json + GoogleService-Info.plist).
//   2. Uncomment `PushNotificationService.instance.init()` call below.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Full-screen feed looks best edge-to-edge.
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  // TODO: uncomment after firebase_core is configured per platform
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // await PushNotificationService.instance.init();

  runApp(const ProviderScope(child: NataloFeedApp()));
}

class NataloFeedApp extends StatelessWidget {
  const NataloFeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/feed',
      routes: [
        GoRoute(
          path: '/feed',
          builder: (_, __) => const FeedScreen(),
        ),
        GoRoute(
          path: '/feed/upload',
          builder: (_, __) => const UploadScreen(),
        ),
      ],
    );

    // Wire push tap → router. Done after router is built so we have the
    // navigator key available.
    PushNotificationService.instance.onNotificationTap = (url, actionId) {
      if (url == null) return;
      // Action button "Lihat" → just open URL.
      // Action button "Buang" (admin reject) → POST reject endpoint then open.
      // For scaffold, both → navigate.
      router.go(url);
    };

    return MaterialApp.router(
      title: 'Natalo Feed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
