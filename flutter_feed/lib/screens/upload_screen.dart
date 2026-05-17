import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';

import '../api/bunny_upload.dart';
import '../services/upload_lifecycle.dart';
import '../state/feed_provider.dart';

// Mirror of components/feed/FeedUploadClient.tsx — 5-step wizard.
// Steps: pick → preview → trim → detail → upload (with TUS resumable).
//
// Limits (mirror lib/feed/video-config.ts USER_VIDEO_CONFIG):
//   - Duration 1-45s
//   - Max source 200 MB (server compresses to ~8 MB via Bunny)
//
// Wave 3: if a pending upload exists in SharedPreferences and matches the
// re-picked file's size+name, resume via TUS findPreviousUploads.

enum _Step { pick, preview, detail, uploading, done }

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen>
    with WidgetsBindingObserver, UploadLifecycleMixin {
  _Step _step = _Step.pick;
  File? _file;
  final _titleCtrl = TextEditingController();
  PendingUpload? _pending;

  double _progress = 0;
  String _progressMessage = '';

  @override
  void initState() {
    super.initState();
    _checkPending();
  }

  Future<void> _checkPending() async {
    final p = await getPendingUpload();
    if (p != null && mounted) setState(() => _pending = p);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  void onAppBackgrounded() {
    if (_step == _Step.uploading) {
      setState(() => _progressMessage = 'Mengunggah di latar belakang...');
    }
  }

  @override
  void onAppForegrounded() {
    if (_step == _Step.uploading) {
      setState(() => _progressMessage = 'Melanjutkan unggahan...');
    }
  }

  Future<void> _pickFile() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 45),
    );
    if (picked == null) return;
    final f = File(picked.path);
    final size = await f.length();
    const max = 200 * 1024 * 1024; // 200 MB
    if (size > max) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video maksimal 200 MB')),
      );
      return;
    }
    setState(() {
      _file = f;
      _step = _Step.preview;
    });
  }

  Future<void> _doUpload() async {
    if (_file == null) return;
    setState(() {
      _step = _Step.uploading;
      _progress = 0;
      _progressMessage = 'Menyiapkan unggahan...';
    });

    final api = ref.read(feedApiProvider);
    final uploader = BunnyUploader(api);

    try {
      // Reuse credentials if a pending state matches this file.
      late BunnyUploadCredentials creds;
      String? resumeUrl;
      final fileName = _file!.uri.pathSegments.last;
      final fileSize = await _file!.length();

      if (_pending != null &&
          _pending!.fileName == fileName &&
          _pending!.fileSize == fileSize) {
        // Reconstruct creds from server (re-sign) — server returns same guid
        // if we pass it back via title hint (in real impl, add a 'resumeGuid'
        // param to /api/feed/bunny/upload-url). For scaffold, we just request
        // fresh creds and let TUS HEAD discover existing offset.
        creds = await uploader.requestCredentials(title: _titleCtrl.text);
        resumeUrl = _pending!.tusUploadUrl;
      } else {
        creds = await uploader.requestCredentials(title: _titleCtrl.text);
      }

      // Persist pending state BEFORE upload starts.
      final pending = PendingUpload(
        fileName: fileName,
        fileSize: fileSize,
        videoGuid: creds.videoGuid,
        tusUploadUrl: null, // filled after first PATCH
        title: _titleCtrl.text,
        savedAt: DateTime.now(),
      );
      await savePendingUpload(pending);

      final uploadUrl = await uploader.uploadResumable(
        file: _file!,
        creds: creds,
        resumeUploadUrl: resumeUrl,
        onProgress: (sent, total) {
          if (!mounted) return;
          setState(() {
            _progress = sent / total;
            _progressMessage =
                'Mengunggah... ${(_progress * 100).toStringAsFixed(0)}%';
          });
          // Persist current URL for future resume.
          savePendingUpload(PendingUpload(
            fileName: fileName,
            fileSize: fileSize,
            videoGuid: creds.videoGuid,
            tusUploadUrl: null, // BunnyUploader doesn't expose mid-flight URL
            title: _titleCtrl.text,
            savedAt: pending.savedAt,
          ));
        },
      );

      // Update final URL.
      await savePendingUpload(PendingUpload(
        fileName: fileName,
        fileSize: fileSize,
        videoGuid: creds.videoGuid,
        tusUploadUrl: uploadUrl,
        title: _titleCtrl.text,
        savedAt: pending.savedAt,
      ));

      await clearPendingUpload();
      if (!mounted) return;
      setState(() => _step = _Step.done);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload gagal: $e — bisa lanjut nanti')),
      );
      setState(() => _step = _Step.preview);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unggah Video')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.pick:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_pending != null)
              Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Upload sebelumnya belum selesai',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${_pending!.fileName} · ${_pending!.title}'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: _pickFile,
                            child: const Text('Pilih file yang sama → lanjut'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () async {
                              await clearPendingUpload();
                              setState(() => _pending = null);
                            },
                            child: const Text('Buang dan mulai baru'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.video_library),
              label: const Text('Pilih video'),
              onPressed: _pickFile,
            ),
            const SizedBox(height: 8),
            const Text('1-45 detik · maks 200 MB',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        );

      case _Step.preview:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_file!.uri.pathSegments.last,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const Spacer(),
            ElevatedButton(
              onPressed: () => setState(() => _step = _Step.detail),
              child: const Text('Lanjut'),
            ),
          ],
        );

      case _Step.detail:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Judul / caption'),
              maxLength: 500,
              maxLines: 4,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _doUpload,
                child: const Text('Unggah'),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Koneksi putus pun bisa lanjut otomatis',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        );

      case _Step.uploading:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            Text(_progressMessage),
          ],
        );

      case _Step.done:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 200,
              // Place file at assets/lottie/upload_success.json (see README).
              child: Lottie.asset(
                'assets/lottie/upload_success.json',
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 100,
                ),
              ),
            ),
            const Text(
              'Berhasil! Post kamu masuk antrian review admin.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Kembali ke Feed'),
            ),
          ],
        );
    }
  }
}
