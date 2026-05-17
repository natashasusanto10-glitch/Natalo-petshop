import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Mirror of lib/feed/upload-lifecycle.ts (Wave 3).
//
// Capacitor App lifecycle is replaced by Flutter's WidgetsBindingObserver
// (built-in). State persistence via shared_preferences with TTL 24h.
//
// Use case:
//   - User starts upload of 200 MB file
//   - App backgrounded (other call, app switcher)
//   - On resume, banner shows "Upload sebelumnya belum selesai"
//   - User re-picks same file → TUS resume from last byte via stored URL.

const String _kPendingKey = 'feed.upload.pending';
const Duration _kTtl = Duration(hours: 24);

class PendingUpload {
  final String fileName;
  final int fileSize;
  final String videoGuid;
  final String? tusUploadUrl; // URL returned from TUS Location header
  final String title;
  final DateTime savedAt;

  const PendingUpload({
    required this.fileName,
    required this.fileSize,
    required this.videoGuid,
    required this.tusUploadUrl,
    required this.title,
    required this.savedAt,
  });

  bool get isExpired => DateTime.now().difference(savedAt) > _kTtl;

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'fileSize': fileSize,
        'videoGuid': videoGuid,
        'tusUploadUrl': tusUploadUrl,
        'title': title,
        'savedAt': savedAt.toIso8601String(),
      };

  factory PendingUpload.fromJson(Map<String, dynamic> j) => PendingUpload(
        fileName: j['fileName'] as String,
        fileSize: (j['fileSize'] as num).toInt(),
        videoGuid: j['videoGuid'] as String,
        tusUploadUrl: j['tusUploadUrl'] as String?,
        title: j['title'] as String? ?? '',
        savedAt:
            DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

Future<void> savePendingUpload(PendingUpload state) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kPendingKey, jsonEncode(state.toJson()));
}

Future<PendingUpload?> getPendingUpload() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kPendingKey);
  if (raw == null || raw.isEmpty) return null;
  try {
    final state = PendingUpload.fromJson(
        jsonDecode(raw) as Map<String, dynamic>);
    if (state.isExpired) {
      await clearPendingUpload();
      return null;
    }
    return state;
  } catch (_) {
    await clearPendingUpload();
    return null;
  }
}

Future<void> clearPendingUpload() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kPendingKey);
}

// ─────────────────────────────────────────────────────────────────────────────
// Lifecycle hook — equivalent of React useUploadLifecycle() in web.
//
// Usage: `class _MyState extends State<X> with WidgetsBindingObserver,
// UploadLifecycleMixin { ... }`. The `WidgetsBindingObserver` mixin must
// come first so its default empty implementations satisfy Dart's interface
// requirements (it has 20+ methods we don't care about — back gestures,
// view focus, locales, etc.).

mixin UploadLifecycleMixin<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  bool _isBackgrounded = false;
  bool get isBackgrounded => _isBackgrounded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Override to react to backgrounding (e.g. show "uploading in background").
  void onAppBackgrounded() {}

  /// Override to react to resume (e.g. show "resuming...").
  void onAppForegrounded() {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        if (!_isBackgrounded) {
          _isBackgrounded = true;
          onAppBackgrounded();
        }
        break;
      case AppLifecycleState.resumed:
        if (_isBackgrounded) {
          _isBackgrounded = false;
          onAppForegrounded();
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }
}
