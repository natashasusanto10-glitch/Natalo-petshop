import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../models/pet.dart';
import '../services/pet_service.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/app_ui.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import 'pet_form_screen.dart';
import 'pet_profile_screen.dart';

const _brandBlue = NataloColors.primary;

/// "Anabulku" — daftar pet milik user (Tahap 1: CRUD dasar). Dibuka dari
/// tombol "Pets Profile" di header profil sendiri (menggantikan "Edit
/// Profil" — edit profil member tetap ada lewat ikon gear/Pengaturan Akun).
class AnabulkuScreen extends StatefulWidget {
  const AnabulkuScreen({super.key});

  @override
  State<AnabulkuScreen> createState() => _AnabulkuScreenState();
}

class _AnabulkuScreenState extends State<AnabulkuScreen> {
  List<Pet> _pets = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pets = await petService.fetchPets();
      if (!mounted) return;
      setState(() {
        _pets = pets;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat daftar pet. Tarik untuk coba lagi.';
        _loading = false;
      });
    }
  }

  Future<void> _openAddForm() async {
    AppHaptics.tap();
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PetFormScreen()),
    );
    if (created == true) await _load();
  }

  Future<void> _openProfile(Pet pet) async {
    AppHaptics.tap();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PetProfileScreen(pet: pet)),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        // Header ikut standar global (appBarTheme): title 18/w700, flat +
        // hairline border, tanpa shadow-on-scroll. Konsisten dgn halaman lain.
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Kembali',
        ),
        title: const Text('Anabulku'),
      ),
      body: NataloPawRefreshIndicator(
        onRefresh: _load,
        child: AppFadeSwitcher(
          stateKey: _loading
              ? 'loading'
              : _error != null
                  ? 'error'
                  : _pets.isEmpty
                      ? 'empty'
                      : 'content',
          child: _loading
              ? const _PetListSkeleton()
              : _error != null
                  ? _ErrorState(text: _error!, onRetry: _load)
                  : _pets.isEmpty
                      ? _EmptyState(onAdd: _openAddForm)
                      : _PetList(
                          pets: _pets,
                          onTapPet: _openProfile,
                          onAdd: _openAddForm,
                        ),
        ),
      ),
    );
  }
}

class _PetList extends StatelessWidget {
  final List<Pet> pets;
  final ValueChanged<Pet> onTapPet;
  final VoidCallback onAdd;

  const _PetList({
    required this.pets,
    required this.onTapPet,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Pet Saya',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            _AddButton(onTap: onAdd),
          ],
        ),
        const SizedBox(height: 12),
        for (final pet in pets) ...[
          _PetTile(pet: pet, onTap: () => onTapPet(pet)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: _brandBlue),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: _brandBlue),
              SizedBox(width: 4),
              Text(
                'Tambah',
                style: TextStyle(
                  color: _brandBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PetTile extends StatelessWidget {
  final Pet pet;
  final VoidCallback onTap;

  const _PetTile({required this.pet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = [
      pet.type,
      if (pet.breed != null && pet.breed!.trim().isNotEmpty) pet.breed!.trim(),
      if (pet.ageLabel != null) pet.ageLabel!,
    ].join(' • ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: NataloColors.primarySoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _PetAvatar(pet: pet),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _PetAvatar extends StatelessWidget {
  final Pet pet;
  const _PetAvatar({required this.pet});

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    final url = pet.photoUrl;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url.isEmpty
            ? const _PetAvatarFallback(iconSize: 22)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: size,
                height: size,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (_, __) => Container(
                  color: NataloColors.grey400.withValues(alpha: 0.25),
                ),
                errorWidget: (_, __, ___) =>
                    const _PetAvatarFallback(iconSize: 22),
              ),
      ),
    );
  }
}

/// Fallback bulat abu + ikon paws — dipakai saat pet belum punya foto atau
/// gambar gagal dimuat.
class _PetAvatarFallback extends StatelessWidget {
  final double iconSize;
  const _PetAvatarFallback({required this.iconSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NataloColors.grey400.withValues(alpha: 0.25),
      alignment: Alignment.center,
      child: Icon(Icons.pets_rounded, color: _brandBlue, size: iconSize),
    );
  }
}

class _PetListSkeleton extends StatelessWidget {
  const _PetListSkeleton();

  static const int _tileCount = 3;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white12 : const Color(0xFFE9ECEF);
    final highlightColor = isDark ? Colors.white24 : const Color(0xFFF6F7F9);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Shimmer.fromColors(
          baseColor: baseColor,
          highlightColor: highlightColor,
          child: Column(
            children: [
              for (var i = 0; i < _tileCount; i++) ...[
                Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 90, 32, 100),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark
                    ? _brandBlue.withValues(alpha: 0.20)
                    : NataloColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.pets_rounded,
                  color: _brandBlue, size: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'Belum ada pet',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Tambahkan hewan peliharaan pertama untuk mulai mengatur profilnya.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: onAdd,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'Tambah Pet Pertama',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;

  const _ErrorState({required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 90, 32, 100),
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded, color: cs.onSurfaceVariant, size: 40),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
