import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/fcm_service.dart';
import 'theme/admin_theme.dart';

// Global error untuk ditampilkan ke layar kalau startup crash.
String? _startupError;

Future<void> main() async {
  // Tangkap semua uncaught Dart error — tampilkan ke layar supaya bisa
  // debug tanpa ADB. Hapus ini setelah isu teridentifikasi.
  FlutterError.onError = (details) {
    _startupError ??= '${details.exception}\n\n${details.stack}';
    FlutterError.presentError(details);
  };

  try {
    WidgetsFlutterBinding.ensureInitialized();

    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Color(0xFFEEEEEE),
      ),
    );

    await initializeDateFormatting('id_ID');

    try {
      await adminApi.getJson('/api/auth/me');
    } catch (_) {
      // Silent — gate via isAuthenticated di build.
    }

    await FcmService.instance.init();
  } catch (e, st) {
    _startupError = '$e\n\n$st';
  }

  runApp(const NataloAdminApp());
}

class NataloAdminApp extends StatelessWidget {
  const NataloAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Kalau ada startup error — tampilkan layar merah dengan pesan error
    // supaya bisa dibaca langsung di HP tanpa perlu ADB/logcat.
    if (_startupError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _ErrorScreen(error: _startupError!),
      );
    }

    return MaterialApp(
      title: 'Natalo Admin',
      debugShowCheckedModeBanner: false,
      theme: adminThemeLight(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('id', 'ID'),
        Locale('en', 'US'),
      ],
      locale: const Locale('id', 'ID'),
      home: adminApi.isAuthenticated ? const HomeShell() : const LoginScreen(),
    );
  }
}

/// Layar debug sementara — tampil saat startup crash sebelum UI normal muncul.
class _ErrorScreen extends StatelessWidget {
  final String error;
  const _ErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFB71C1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
        title: const Text('Startup Error — kirim screenshot ke dev'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          error,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
