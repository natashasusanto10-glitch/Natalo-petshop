import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';

/// Form broadcast push notification ke semua customer.
///
/// Pakai endpoint POST /api/admin/push/broadcast yang sudah ada.
/// Body: {title, body, url?, segment}
///
/// Segment options:
/// - all: semua user dengan push subscription
/// - members: yang pernah complete order
/// - active30d: yang punya order 30 hari terakhir
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _urlController = TextEditingController();
  String _segment = 'all';
  bool _sending = false;

  static const _segments = [
    _Segment('all', 'Semua pengguna', 'Semua user dengan push subscription'),
    _Segment('members', 'Member aktif', 'User yang pernah complete order'),
    _Segment('active30d', '30 hari terakhir', 'Order dalam 30 hari'),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty) return _err('Judul wajib diisi');
    if (body.isEmpty) return _err('Isi pesan wajib diisi');
    if (title.length > 60) return _err('Judul maksimal 60 karakter');
    if (body.length > 180) return _err('Isi pesan maksimal 180 karakter');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kirim broadcast?'),
        content: Text(
          'Notifikasi akan dikirim ke segmen "${_segments.firstWhere((s) => s.key == _segment).label}".\n\nLanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kirim'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _sending = true);
    try {
      final response = await adminApi.postJson(
        '/api/admin/push/broadcast',
        body: {
          'title': title,
          'body': body,
          if (_urlController.text.trim().isNotEmpty)
            'url': _urlController.text.trim(),
          'segment': _segment,
        },
      );
      if (!mounted) return;
      final recipientCount =
          (response is Map && response['recipientCount'] is num)
          ? (response['recipientCount'] as num).toInt()
          : 0;
      final sent = (response is Map && response['sent'] is num)
          ? (response['sent'] as num).toInt()
          : 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terkirim ke $sent dari $recipientCount user'),
          backgroundColor: AdminColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _titleController.clear();
      _bodyController.clear();
      _urlController.clear();
    } on AdminApiException catch (e) {
      _err('Gagal: ${e.message}');
    } catch (_) {
      _err('Gagal kirim. Coba lagi.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final titleLen = _titleController.text.length;
    final bodyLen = _bodyController.text.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Broadcast Notifikasi')),
      body: ListView(
        children: [
          Container(
            color: AdminColors.primaryLight,
            padding: const EdgeInsets.all(14),
            child: const Row(
              children: [
                Icon(
                  Icons.campaign_outlined,
                  color: AdminColors.primary,
                  size: 22,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kirim push notification ke pengguna app Natalo. '
                    'Pastikan judul, isi pesan, dan segmen sudah benar sebelum mengirim.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AdminColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Judul *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                    Text(
                      '$titleLen / 60',
                      style: TextStyle(
                        fontSize: 11,
                        color: titleLen > 60
                            ? AdminColors.danger
                            : AdminColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _titleController,
                  maxLength: 60,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '🎉 Promo Spesial Akhir Pekan!',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Isi Pesan *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                    Text(
                      '$bodyLen / 180',
                      style: TextStyle(
                        fontSize: 11,
                        color: bodyLen > 180
                            ? AdminColors.danger
                            : AdminColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _bodyController,
                  maxLength: 180,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Diskon 30% semua pakan kucing! Klaim sekarang.',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'URL Tujuan (opsional)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: '/products?promo=weekend',
                    prefixIcon: Icon(Icons.link_outlined),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Path relatif (mis. /products) atau full URL. '
                  'User akan diarahkan ke sini saat tap notif.',
                  style: TextStyle(fontSize: 11, color: AdminColors.textMuted),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Kirim ke',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                RadioGroup<String>(
                  groupValue: _segment,
                  onChanged: (v) => setState(() => _segment = v ?? 'all'),
                  child: Column(
                    children: [
                      for (final s in _segments)
                        RadioListTile<String>(
                          value: s.key,
                          activeColor: AdminColors.primary,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            s.label,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            s.description,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AdminColors.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'Mengirim...' : 'Kirim ke User'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _sending ? null : _send,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Segment {
  final String key;
  final String label;
  final String description;
  const _Segment(this.key, this.label, this.description);
}
