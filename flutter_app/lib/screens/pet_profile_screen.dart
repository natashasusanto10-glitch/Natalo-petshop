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

class _PetProfileScreenState extends State<PetProfileScreen> {
  late Pet _pet;

  @override
  void initState() {
    super.initState();
    _pet = widget.pet;
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
          _ProfileHeader(pet: pet),
          _StatsRow(pet: pet),
          _ComingSoonCard(petName: pet.name),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final Pet pet;
  const _ProfileHeader({required this.pet});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = [
      pet.type,
      if (pet.breed != null && pet.breed!.trim().isNotEmpty) pet.breed!.trim(),
      if (pet.ageLabel != null) pet.ageLabel!,
    ].join(' • ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 40, color: NataloColors.primarySoft),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PetAvatarLarge(pet: pet),
              const SizedBox(height: 10),
              Row(
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
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              if (pet.bio != null && pet.bio!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  pet.bio!.trim(),
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
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

class _PetAvatarLarge extends StatelessWidget {
  final Pet pet;
  const _PetAvatarLarge({required this.pet});

  @override
  Widget build(BuildContext context) {
    const size = 88.0;
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: NataloColors.primarySoft,
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
        color: NataloColors.grey100,
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
          color: NataloColors.grey100,
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
