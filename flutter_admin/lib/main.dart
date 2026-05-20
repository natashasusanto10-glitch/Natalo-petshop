import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'theme/admin_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Hydrate session dari SharedPreferences — adminApi internal _ensureHydrated
  // dipanggil saat request pertama, tapi kita "warm" dulu di sini lewat
  // ping /api/auth/me. Kalau response 401, cookie auto-dihapus.
  try {
    await adminApi.getJson('/api/auth/me');
  } catch (_) {
    // Silent — gate via isAuthenticated di build.
  }
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
      home: adminApi.isAuthenticated ? const HomeShell() : const LoginScreen(),
    );
  }
}
