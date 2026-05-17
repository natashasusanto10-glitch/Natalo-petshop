import 'package:flutter/material.dart';

import '../state/settings_store.dart';

class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettingsStore,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Pengaturan')),
          body: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_6_rounded),
                title: const Text('Tema'),
                subtitle: Text(_themeLabel(appSettingsStore.themeMode)),
                onTap: () => _showThemeDialog(context),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.vibration_rounded),
                title: const Text('Haptic feedback'),
                value: appSettingsStore.hapticsEnabled,
                onChanged: appSettingsStore.setHapticsEnabled,
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('Fitur lain'),
                subtitle: Text('Akan tersedia di update berikutnya.'),
              ),
            ],
          ),
        );
      },
    );
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Terang';
      case ThemeMode.dark:
        return 'Gelap';
      case ThemeMode.system:
        return 'Mengikuti sistem';
    }
  }

  Future<void> _showThemeDialog(BuildContext context) async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Pilih tema'),
        children: [
          for (final mode in ThemeMode.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, mode),
              child: Text(_themeLabel(mode)),
            ),
        ],
      ),
    );
    if (selected != null) appSettingsStore.setThemeMode(selected);
  }
}

