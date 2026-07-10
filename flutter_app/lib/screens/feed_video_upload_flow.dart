import 'package:flutter/material.dart';

const _feedUploadBlue = Color(0xFF1E5BFF);
const _feedUploadBg = Color(0xFF05070D);
const _feedUploadCard = Color(0xFF11141B);
const _feedUploadBorder = Color(0xFF252A35);
const _feedUploadText = Color(0xFFFFFFFF);
const _feedUploadMuted = Color(0xFFAEB7C7);

// NOTE(Task 5 — feed-posting fase 2B): file ini dulu berisi seluruh flow
// upload video legacy (FeedVideoStartScreen → FeedVideoPreviewScreen →
// FeedVideoTrimScreen → FeedPostDetailScreen → FeedUploadProgressScreen).
// Semua layar itu sudah tak terjangkau sejak picker (FeedMediaPickerScreen)
// + FeedVideoEditScreen (Fase 2B) mengambil alih flow pick+trim+edit, dan
// upload jaringan sekarang berjalan di background via FeedUploadStore
// (state/feed_upload_store.dart). Kelas-kelas mati (0 call site, verified
// via grep) dihapus supaya file tidak menyesatkan; yang tersisa cuma
// FeedPostSubmittedScreen (masih dipush dari feed_photo_upload_flow.dart)
// + helper dark-scaffold generik yang masih dipakainya.

class FeedPostSubmittedScreen extends StatelessWidget {
  const FeedPostSubmittedScreen({super.key});

  void _backToFeed(BuildContext context) {
    Navigator.of(context).popUntil((route) {
      return route.settings.name == '/feed' || route.isFirst;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _DarkUploadScaffold(
      title: '',
      leading: Icons.arrow_back_rounded,
      onLeading: () => _backToFeed(context),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SubmittedIllustration(),
            const SizedBox(height: 28),
            const Text(
              'Postingan berhasil dikirim!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _feedUploadText,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Feed kamu sedang menunggu review admin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _feedUploadMuted,
                fontSize: 14.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            const _ReviewEstimateCard(),
            const SizedBox(height: 28),
            _PrimaryUploadButton(
              label: 'Lihat Postingan Saya',
              icon: Icons.video_collection_rounded,
              onPressed: () {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/member/postingan',
                  (route) => route.isFirst,
                );
              },
            ),
            const SizedBox(height: 12),
            _SecondaryUploadButton(
              label: 'Kembali ke Feed',
              icon: Icons.play_circle_outline_rounded,
              onPressed: () => _backToFeed(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkUploadScaffold extends StatelessWidget {
  final String title;
  final IconData leading;
  final VoidCallback onLeading;
  final Widget child;

  const _DarkUploadScaffold({
    required this.title,
    required this.leading,
    required this.onLeading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _feedUploadBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    _IconCircleButton(icon: leading, onTap: onLeading),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _feedUploadText,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 44, height: 44),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmittedIllustration extends StatelessWidget {
  const _SubmittedIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      width: 132,
      decoration: BoxDecoration(
        color: _feedUploadBlue.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 82,
            width: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFDCE8FF),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _feedUploadBlue.withValues(alpha: 0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.playlist_add_check_rounded,
              color: _feedUploadBlue,
              size: 46,
            ),
          ),
          const Positioned(
            right: 18,
            bottom: 24,
            child: Icon(Icons.pets_rounded, color: Color(0xFFF7B955), size: 34),
          ),
          const Positioned(
            left: 23,
            top: 24,
            child: Icon(Icons.auto_awesome_rounded,
                color: _feedUploadBlue, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ReviewEstimateCard extends StatelessWidget {
  const _ReviewEstimateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _feedUploadCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _feedUploadBorder),
      ),
      child: const Row(
        children: [
          Icon(Icons.schedule_rounded, color: _feedUploadBlue),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Estimasi review',
                style: TextStyle(
                  color: _feedUploadMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 3),
              Text(
                '1 x 24 jam',
                style: TextStyle(
                  color: _feedUploadText,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimaryUploadButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _PrimaryUploadButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: _feedUploadBlue,
          disabledBackgroundColor: const Color(0xFF293244),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _SecondaryUploadButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _SecondaryUploadButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: _feedUploadText,
          disabledForegroundColor: _feedUploadMuted.withValues(alpha: 0.35),
          side: const BorderSide(
            color: _feedUploadBorder,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}
