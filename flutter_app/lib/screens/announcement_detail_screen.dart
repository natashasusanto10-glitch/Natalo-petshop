import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../services/notification_service.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';

const _brandBlue = Color(0xFF1677FF);
const _announcementGreen = Color(0xFF20B26B);
const _pageBg = Color(0xFFF7F9FC);
const _textPrimary = Color(0xFF101828);
const _textSecondary = Color(0xFF667085);
const _border = Color(0xFFE5EAF2);

class AnnouncementDetailScreen extends StatefulWidget {
  final AppNotification notification;

  const AnnouncementDetailScreen({
    super.key,
    required this.notification,
  });

  @override
  State<AnnouncementDetailScreen> createState() =>
      _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState extends State<AnnouncementDetailScreen> {
  bool _markingRead = false;

  AppNotification get _notification => widget.notification;

  @override
  void initState() {
    super.initState();
    _markAsRead();
  }

  Future<void> _markAsRead() async {
    if (_notification.read || _markingRead) return;
    _markingRead = true;
    try {
      await notificationService.markRead(_notification.id);
    } catch (_) {
      // Best-effort. Notification Center reload akan sinkron saat kembali.
    } finally {
      _markingRead = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final notification = _notification;

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Column(
          children: [
            _AnnouncementHeader(onBack: () => Navigator.maybePop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: _AnnouncementCard(notification: notification),
              ),
            ),
            _AnnouncementBottomActions(
              onPrimary: () async {
                AppHaptics.tap();
                await _markAsRead();
                if (context.mounted) Navigator.maybePop(context);
              },
              onSecondary: () {
                AppHaptics.tap();
                Navigator.maybePop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _AnnouncementHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: _textPrimary,
              size: 27,
            ),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Detail Pengumuman',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _textPrimary,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final AppNotification notification;

  const _AnnouncementCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    final body = notification.body.trim().isEmpty
        ? (notification.shortDescription ?? '').trim()
        : notification.body.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AnnouncementTitleSection(notification: notification),
          const SizedBox(height: 20),
          const Divider(color: _border),
          const SizedBox(height: 20),
          Text(
            body.isEmpty
                ? 'Pengumuman dari Natalo Petshop belum memiliki isi lengkap.'
                : body,
            style: const TextStyle(
              color: Color(0xFF1D2939),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.58,
            ),
          ),
          _ImportantInfo(notification: notification),
          const SizedBox(height: 22),
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Salam hangat,\n'),
                TextSpan(
                  text: 'Natalo Petshop',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            style: TextStyle(
              color: Color(0xFF1D2939),
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          _InfoNote(notification: notification),
        ],
      ),
    );
  }
}

class _AnnouncementTitleSection extends StatelessWidget {
  final AppNotification notification;

  const _AnnouncementTitleSection({required this.notification});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F8F0),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.campaign_rounded,
            color: _announcementGreen,
            size: 34,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _categoryLabel(notification),
                  style: const TextStyle(
                    color: _announcementGreen,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                notification.title,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  height: 1.18,
                  letterSpacing: -0.35,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 9,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MetaChip(
                    icon: Icons.calendar_today_rounded,
                    text: formatTanggal(notification.createdAt),
                  ),
                  const Text(
                    '•',
                    style: TextStyle(
                      color: Color(0xFF98A2B3),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  _MetaChip(
                    icon: Icons.access_time_rounded,
                    text: _formatClock(notification.createdAt),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: _textSecondary),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ImportantInfo extends StatelessWidget {
  final AppNotification notification;

  const _ImportantInfo({required this.notification});

  @override
  Widget build(BuildContext context) {
    final title = notification.importantTitle?.trim();
    final value = notification.importantValue?.trim();
    final description = notification.importantDescription?.trim();

    if ((title == null || title.isEmpty) &&
        (value == null || value.isEmpty) &&
        (description == null || description.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FAF5),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFDDF7EA)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Color(0xFFDDF7EA),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.info_rounded,
                color: _announcementGreen,
                size: 25,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null && title.isNotEmpty)
                    Text(
                      title,
                      style: const TextStyle(
                        color: _announcementGreen,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  if (value != null && value.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      value,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(
                        color: _textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  final AppNotification notification;

  const _InfoNote({required this.notification});

  @override
  Widget build(BuildContext context) {
    final note = notification.infoNote?.trim();
    if (note == null || note.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDCEBFF)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFFDCEBFF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.info_outline_rounded,
                color: _brandBlue,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                note,
                style: const TextStyle(
                  color: Color(0xFF0B4DBA),
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementBottomActions extends StatelessWidget {
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  const _AnnouncementBottomActions({
    required this.onPrimary,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      decoration: BoxDecoration(
        color: _pageBg,
        border: const Border(top: BorderSide(color: _border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: onPrimary,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text(
                'Mengerti',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: onSecondary,
              style: OutlinedButton.styleFrom(
                foregroundColor: _brandBlue,
                side: const BorderSide(color: _brandBlue, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text(
                'Cek Info Lainnya',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _categoryLabel(AppNotification notification) {
  final category = notification.category?.trim();
  if (category != null && category.isNotEmpty) return category;
  return 'Pengumuman';
}

String _formatClock(DateTime date) {
  final hh = date.hour.toString().padLeft(2, '0');
  final mm = date.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}
