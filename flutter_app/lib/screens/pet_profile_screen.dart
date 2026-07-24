import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import 'pet_form_screen.dart';

const _brandBlue = NataloColors.primary;

/// Halaman "Profil Anabulku" ("Anabulku" Tahap 2) — profil satu pet.
/// Privat: hanya pemilik yang bisa membuka (dibuka dari tap kartu di
/// [AnabulkuScreen], bukan route publik). Stats (Momen/Perawatan/Belanja)
/// masih placeholder 0 sampai Tahap 3-5 (Journey/Perawatan/Belanja) dibangun.
class PetProfileScreen extends StatefulWidget {
  final Pet pet;

  const PetProfileScreen({super.key, required this.pet});

  @override
  State<PetProfileScreen> createState() => _PetProfileScreenState();
}

class _PetProfileScreenState extends State<PetProfileScreen>
    with SingleTickerProviderStateMixin {
  late Pet _pet;
  late final AnimationController _entrance;
  bool _entranceStarted = false;

  @override
  void initState() {
    super.initState();
    _pet = widget.pet;
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceStarted) return;
    _entranceStarted = true;
    // Reduced-motion: langsung tampil penuh tanpa animasi masuk.
    if (MediaQuery.of(context).disableAnimations) {
      _entrance.value = 1;
    } else {
      // Tunggu transisi halaman selesai supaya entrance tidak balapan
      // dengan slide route (kesan lebih tenang & premium).
      Future<void>.delayed(const Duration(milliseconds: 90), () {
        if (mounted) _entrance.forward();
      });
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _openEdit() async {
    AppHaptics.tap();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PetFormScreen(pet: _pet)),
    );
    if (changed == true) {
      // Pet form pop(true) berarti sukses simpan/hapus; kalau dihapus,
      // caller (AnabulkuScreen) yang refresh listnya — di sini cukup
      // tutup profil karena datanya sudah tidak valid untuk ditampilkan.
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pet = _pet;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Kembali',
        ),
        title: const Text('Profil Anabulku'),
        actions: [
          IconButton(
            onPressed: _openEdit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit pet',
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _ProfileHeader(pet: pet, entrance: _entrance),
          _Entrance(
            controller: _entrance,
            start: 0.28,
            child: _StatsRow(pet: pet),
          ),
          _Entrance(
            controller: _entrance,
            start: 0.42,
            child: _ComingSoonCard(petName: pet.name),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final Pet pet;
  final Animation<double> entrance;
  const _ProfileHeader({required this.pet, required this.entrance});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitle = [
      pet.type,
      if (pet.breed != null && pet.breed!.trim().isNotEmpty) pet.breed!.trim(),
      if (pet.ageLabel != null) pet.ageLabel!,
    ].join(' • ');
    // Avatar overlap ala IG: cover 64px + avatar 88px menumpuk setengah ke
    // bawah cover (Stack+Positioned, BUKAN Transform.translate — translate
    // tidak mengurangi ruang layout, jadi hanya boleh dipakai bareng SizedBox
    // kompensasi di bawah). Menghindari strip cover polos yang terasa kosong.
    const coverHeight = 64.0;
    const avatarSize = 88.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: coverHeight,
              color: isDark
                  ? _brandBlue.withValues(alpha: 0.18)
                  : NataloColors.primarySoft,
            ),
            Positioned(
              left: 20,
              top: coverHeight - avatarSize / 2,
              child: Hero(
                tag: 'pet-photo-${pet.id}',
                child: _PetAvatarLarge(pet: pet, size: avatarSize),
              ),
            ),
          ],
        ),
        const SizedBox(height: avatarSize / 2 + 10),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Entrance(
                controller: entrance,
                start: 0.14,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        pet.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (pet.gender != null) ...[
                      const SizedBox(width: 8),
                      _GenderPill(gender: pet.gender!),
                    ],
                  ],
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                _Entrance(
                  controller: entrance,
                  start: 0.21,
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (pet.bio != null && pet.bio!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                _Entrance(
                  controller: entrance,
                  start: 0.28,
                  child: Text(
                    pet.bio!.trim(),
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fade + slide-up halus, di-stagger via [start] (0..1) di sepanjang
/// [controller]. Otomatis "no-op" saat reduced-motion (controller sudah
/// di-set ke 1 oleh parent) — tetap render child penuh.
class _Entrance extends StatelessWidget {
  final Animation<double> controller;
  final double start;
  final Widget child;

  const _Entrance({
    required this.controller,
    required this.start,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final t = anim.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _PetAvatarLarge extends StatelessWidget {
  final Pet pet;
  final double size;
  const _PetAvatarLarge({required this.pet, this.size = 88.0});

  @override
  Widget build(BuildContext context) {
    final url = pet.photoUrl;
    final fallback = Container(
      color: NataloColors.grey400.withValues(alpha: 0.25),
      alignment: Alignment.center,
      child: const Icon(Icons.pets_rounded, color: _brandBlue, size: 34),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: ClipOval(
        child: url == null || url.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: size,
                height: size,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (_, __) => Container(
                  color: NataloColors.grey400.withValues(alpha: 0.25),
                ),
                errorWidget: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

class _GenderPill extends StatelessWidget {
  final PetGender gender;
  const _GenderPill({required this.gender});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? _brandBlue.withValues(alpha: 0.22)
            : NataloColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            gender == PetGender.male
                ? Icons.male_rounded
                : Icons.female_rounded,
            size: 13,
            color: _brandBlue,
          ),
          const SizedBox(width: 3),
          Text(
            gender.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _brandBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final Pet pet;
  const _StatsRow({required this.pet});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          Expanded(child: _StatCard(value: '0', label: 'Momen')),
          SizedBox(width: 8),
          Expanded(child: _StatCard(value: '0', label: 'Perawatan')),
          SizedBox(width: 8),
          Expanded(child: _StatCard(value: '0', label: 'Belanja')),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingSoonCard extends StatelessWidget {
  final String petName;
  const _ComingSoonCard({required this.petName});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                color: _brandBlue, size: 22),
            const SizedBox(height: 8),
            const Text(
              'Segera hadir',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Journey, Perawatan, dan Belanja untuk $petName akan muncul di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
