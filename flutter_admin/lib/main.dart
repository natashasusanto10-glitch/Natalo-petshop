import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/fcm_service.dart';
import 'theme/admin_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait-only — admin tools rarely benefit from landscape; mengunci
  // orientation sederhana-kan layout (terutama bottom sheet & form).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // System UI styling: status bar transparan dengan icon gelap supaya
  // terbaca di atas AppBar putih. Nav bar (Android gesture / button)
  // transparan menyatu dengan content — Material 3 default edge-to-edge.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light, // iOS
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Color(0xFFEEEEEE),
    ),
  );

  // Init DateFormat locale 'id_ID' — wajib SEBELUM panggil DateFormat
  // dengan locale custom (sebelumnya crash diam-diam karena baru di-trigger
  // saat user buka voucher list / audit log).
  await initializeDateFormatting('id_ID');

  // Hydrate session dari SharedPreferences — adminApi internal _ensureHydrated
  // dipanggil saat request pertama, tapi kita "warm" dulu di sini lewat
  // ping /api/auth/me. Kalau response 401, cookie auto-dihapus.
  try {
    await adminApi.getJson('/api/auth/me');
  } catch (_) {
    // Silent — gate via isAuthenticated di build.
  }

  // FCM init — try/catch internal, no-op kalau google-services.json belum
  // di-drop. Awaited supaya getInitialMessage (cold start dari tap notif)
  // tertangani sebelum first frame.
  await FcmService.instance.init();

  runApp(const NataloAdminApp());
}

class NataloAdminApp extends StatelessWidget {
  const NataloAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Natalo Admin',
      debugShowCheckedModeBanner: false,
      theme: adminThemeLight(),
      // Localizations supaya date picker, time picker, dll. tampil dalam
      // Bahasa Indonesia. Default Inggris kalau locale device bukan id.
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
