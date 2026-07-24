import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../models/pet.dart';
import '../models/pet_care_record.dart';
import '../services/pet_service.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/haptics.dart';
import '../widgets/app_ui.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import 'pet_care_screen.dart';
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
    final created = await Navigator.of(context).push<Object>(
      MaterialPageRoute(builder: (_) => const PetFormScreen()),
    );
    if (created != null) await _load();
  }

  Future<void> _openProfile(Pet pet) async {
    AppHaptics.tap();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PetProfileScreen(pet: pet)),
    );
    if (changed == true) await _load();
  }

  Future<void> _openCareFor(Pet pet) async {
    AppHaptics.tap();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PetCareScreen(pet: pet),
      ),
    );
    await _load();
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
                          onTapSchedule: _openCareFor,
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
  final ValueChanged<Pet> onTapSchedule;

  const _PetList({
    required this.pets,
    required this.onTapPet,
    required this.onAdd,
    required this.onTapSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        const Text(
          'Pet Saya',
          style: TextStyle(
            fontSize: 17,
            fontWeight: NataloWeight.strong,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${pets.length} anabul terdaftar',
          style: TextStyle(
            fontSize: 12,
            fontWeight: NataloWeight.body,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        for (final pet in pets) ...[
          _PetTile(pet: pet, onTap: () => onTapPet(pet)),
          const SizedBox(height: 10),
        ],
        _AddPetCard(onTap: onAdd),
        _JadwalTerdekatSection(pets: pets, onTap: onTapSchedule),
      ],
    );
  }
}

/// Kartu "Tambah anabul" bergaris putus — mengisi ruang & ajak aksi jelas.
class _AddPetCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddPetCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: DottedBorderBox(
          color: isDark
              ? _brandBlue.withValues(alpha: 0.55)
              : const Color(0xFFC6D4EA),
          radius: 16,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(
              color: isDark
                  ? _brandBlue.withValues(alpha: 0.10)
                  : NataloColors.primarySoft.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DecoratedBox(
                  decoration:
                      BoxDecoration(color: _brandBlue, shape: BoxShape.circle),
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.add_rounded,
                        size: 16, color: Colors.white),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Tambah anabul',
                  style: TextStyle(
                    color: _brandBlue,
                    fontSize: 13,
                    fontWeight: NataloWeight.strong,
                  ),
                ),
              ],
            ),
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
    ].join(' • ');
    final hasChips =
        pet.gender != null || pet.ageLabel != null || pet.nearestDue != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              // Shared-element ke PetProfileScreen — avatar morph mulus.
              Hero(
                tag: 'pet-photo-${pet.id}',
                child: _PetAvatar(pet: pet, size: 56),
              ),
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
                        fontSize: 15,
                        fontWeight: NataloWeight.strong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                        fontWeight: NataloWeight.body,
                      ),
                    ),
                    if (hasChips) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (pet.gender != null)
                            _GenderChipMini(gender: pet.gender!),
                          if (pet.gender != null && pet.ageLabel != null)
                            const SizedBox(width: 5),
                          if (pet.ageLabel != null)
                            _NeutralChip(label: pet.ageLabel!),
                          if (pet.nearestDue != null) ...[
                            if (pet.gender != null || pet.ageLabel != null)
                              const SizedBox(width: 5),
                            _ScheduleChip(schedule: pet.nearestDue!),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: cs.outline, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip gender mungil (♂/♀) — theme-aware, dipakai di kartu daftar.
class _GenderChipMini extends StatelessWidget {
  final PetGender gender;
  const _GenderChipMini({required this.gender});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
            size: 11,
            color: _brandBlue,
          ),
          const SizedBox(width: 2),
          Text(
            gender.label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: NataloWeight.strong,
              color: _brandBlue,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip netral (mis. umur) — theme-aware surface muted.
class _NeutralChip extends StatelessWidget {
  final String label;
  const _NeutralChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: NataloWeight.strong,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PetAvatar extends StatelessWidget {
  final Pet pet;
  final double size;
  const _PetAvatar({required this.pet, this.size = 48});

  @override
  Widget build(BuildContext context) {
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

/// Kotak dengan border putus-putus (rounded). Flutter tak punya dashed
/// border bawaan, jadi digambar via CustomPaint di atas [child].
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;

  const DottedBorderBox({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final len = (dist + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, len), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
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
              style: TextStyle(fontSize: 15, fontWeight: NataloWeight.strong),
            ),
            const SizedBox(height: 6),
            Text(
              'Tambahkan hewan peliharaan pertama untuk mulai mengatur profilnya.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                fontWeight: NataloWeight.body,
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
                  style:
                      TextStyle(fontWeight: NataloWeight.strong, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip jadwal terdekat di kartu pet — merah bila terlambat, biru bila segera,
/// netral bila normal.
class _ScheduleChip extends StatelessWidget {
  final PetSchedule schedule;
  const _ScheduleChip({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = scheduleStatusOf(schedule.nextDueAt);
    final overdue = status == ScheduleStatus.overdue;
    final soon = status == ScheduleStatus.soon;
    final Color bg;
    final Color fg;
    if (overdue) {
      bg = isDark
          ? NataloColors.danger.withValues(alpha: 0.22)
          : NataloColors.dangerSoft;
      fg = NataloColors.dangerDark;
    } else if (soon) {
      bg = isDark ? _brandBlue.withValues(alpha: 0.22) : NataloColors.primarySoft;
      fg = _brandBlue;
    } else {
      bg = cs.surfaceContainerHighest;
      fg = cs.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        '${schedule.category.label} • ${scheduleCountdownLabel(schedule.nextDueAt)}',
        style: TextStyle(
            fontSize: 10, fontWeight: NataloWeight.strong, color: fg),
      ),
    );
  }
}

/// Gabungan jadwal terdekat semua pet (maks 3), diurutkan paling dekat dulu.
class _JadwalTerdekatSection extends StatelessWidget {
  final List<Pet> pets;
  final ValueChanged<Pet> onTap;
  const _JadwalTerdekatSection({required this.pets, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = <({Pet pet, PetSchedule schedule})>[];
    for (final p in pets) {
      final due = p.nearestDue;
      if (due != null) entries.add((pet: p, schedule: due));
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    entries.sort(
        (a, b) => a.schedule.nextDueAt.compareTo(b.schedule.nextDueAt));
    final top = entries.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const Text('Jadwal Terdekat',
            style: TextStyle(fontSize: 13, fontWeight: NataloWeight.strong)),
        const SizedBox(height: 8),
        for (final e in top)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(e.pet),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(e.schedule.category.icon,
                          size: 15, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${e.pet.name} — ${e.schedule.category.label}',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: NataloWeight.strong)),
                          const SizedBox(height: 2),
                          Text(_fmtDate(e.schedule.nextDueAt),
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: NataloWeight.body,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    _ScheduleChip(schedule: e.schedule),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
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
                fontWeight: NataloWeight.body,
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
