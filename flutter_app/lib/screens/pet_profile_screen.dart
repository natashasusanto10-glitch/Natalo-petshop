import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../models/pet_care_record.dart';
import '../services/pet_service.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/haptics.dart';
import 'pet_care_screen.dart';
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
  // True kalau pet di-edit in-place — dikembalikan ke AnabulkuScreen saat
  // back supaya list-nya refresh (nama/foto terbaru).
  bool _dirty = false;
  List<PetCareRecord> _careRecords = const [];
  List<PetSchedule> _careUpcoming = const [];

  @override
  void initState() {
    super.initState();
    _pet = widget.pet;
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _loadCare();
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

  Future<void> _loadCare() async {
    try {
      final res = await petService.fetchCare(_pet.id);
      if (!mounted) return;
      setState(() {
        _careRecords = res.records;
        _careUpcoming = res.upcoming;
        _pet = _pet.copyWith(careCount: res.records.length);
      });
    } catch (_) {
      // Diamkan — section perawatan sekadar tak terisi kalau gagal muat.
    }
  }

  Future<void> _openCare() async {
    AppHaptics.tap();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PetCareScreen(petId: _pet.id, petName: _pet.name),
      ),
    );
    _dirty = true;
    await _loadCare();
  }

  Future<void> _openEdit() async {
    AppHaptics.tap();
    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(builder: (_) => PetFormScreen(pet: _pet)),
    );
    if (result == null || !mounted) return;
    if (result is PetDeleted) {
      // Data pet sudah tidak ada — tutup profil, AnabulkuScreen refresh list.
      Navigator.of(context).pop(true);
    } else if (result is Pet) {
      // Simpan sukses — tetap di halaman profil, tampilkan data terbaru,
      // dan tandai dirty supaya list ikut refresh saat back.
      setState(() {
        _pet = result;
        _dirty = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pet = _pet;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_dirty);
      },
      child: Scaffold(
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
            child: _StatsRow(pet: pet, onCareTap: _openCare),
          ),
          _Entrance(
            controller: _entrance,
            start: 0.42,
            child: _CareSection(
              records: _careRecords,
              upcoming: _careUpcoming,
              petName: _pet.name,
              onSeeAll: _openCare,
              onAddFirst: _openCare,
            ),
          ),
          _Entrance(
            controller: _entrance,
            start: 0.5,
            child: _ComingSoonCard(petName: pet.name),
          ),
          const SizedBox(height: 24),
        ],
      ),
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
                          fontWeight: NataloWeight.strong,
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
              if (_hasHealthInfo(pet)) ...[
                const SizedBox(height: 8),
                _Entrance(
                  controller: entrance,
                  start: 0.32,
                  child: _HealthInfoRows(pet: pet),
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

bool _hasHealthInfo(Pet pet) =>
    pet.sterilized != null ||
    (pet.allergy != null && pet.allergy!.trim().isNotEmpty) ||
    (pet.healthNote != null && pet.healthNote!.trim().isNotEmpty);

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
              fontWeight: NataloWeight.strong,
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
  final VoidCallback onCareTap;
  const _StatsRow({required this.pet, required this.onCareTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          const Expanded(child: _StatCard(value: '0', label: 'Momen')),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onCareTap,
              child: _StatCard(value: '${pet.careCount}', label: 'Perawatan'),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: _StatCard(value: '0', label: 'Belanja')),
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
            style:
                const TextStyle(fontSize: 15, fontWeight: NataloWeight.strong),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: NataloWeight.body,
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
              style: TextStyle(fontSize: 13, fontWeight: NataloWeight.strong),
            ),
            const SizedBox(height: 4),
            Text(
              'Journey dan Belanja untuk $petName akan muncul di sini.',
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

class _CareSection extends StatelessWidget {
  final List<PetCareRecord> records;
  final List<PetSchedule> upcoming;
  final String petName;
  final VoidCallback onSeeAll;
  final VoidCallback onAddFirst;
  const _CareSection({
    required this.records,
    required this.upcoming,
    required this.petName,
    required this.onSeeAll,
    required this.onAddFirst,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (records.isEmpty && upcoming.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onAddFirst,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medical_services_outlined,
                      color: _brandBlue, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Catat perawatan pertama $petName',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: NataloWeight.strong)),
                  ),
                  Icon(Icons.chevron_right_rounded, color: cs.outline),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final nearest = upcoming.isNotEmpty ? upcoming.first : null;
    final lastTwo = records.take(2).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Perawatan',
                  style: TextStyle(
                      fontSize: 13, fontWeight: NataloWeight.strong)),
              const Spacer(),
              GestureDetector(
                onTap: onSeeAll,
                child: const Text('Lihat semua',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: NataloWeight.strong,
                        color: _brandBlue)),
              ),
            ],
          ),
          if (nearest != null) ...[
            const SizedBox(height: 8),
            _NearestCard(schedule: nearest),
          ],
          if (lastTwo.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('TERAKHIR DICATAT',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: NataloWeight.strong,
                    letterSpacing: 0.3,
                    color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            for (final r in lastTwo)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(r.category.icon, size: 15, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text('${r.category.label} — ${_fmtDate(r.doneAt)}',
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: NataloWeight.body)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _NearestCard extends StatelessWidget {
  final PetSchedule schedule;
  const _NearestCard({required this.schedule});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overdue =
        scheduleStatusOf(schedule.nextDueAt) == ScheduleStatus.overdue;
    final soon = scheduleStatusOf(schedule.nextDueAt) == ScheduleStatus.soon;
    final bg = overdue
        ? (isDark ? NataloColors.dangerDark.withValues(alpha: 0.18) : NataloColors.dangerSoft)
        : cs.surfaceContainerHighest;
    final border = overdue
        ? NataloColors.danger.withValues(alpha: 0.5)
        : Colors.transparent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(schedule.category.icon,
              size: 17,
              color: overdue ? NataloColors.dangerDark : _brandBlue),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(schedule.category.label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: NataloWeight.strong,
                        color: overdue ? NataloColors.dangerDark : null)),
                const SizedBox(height: 2),
                Text(
                    '${_fmtDate(schedule.nextDueAt)} • ${scheduleCountdownLabel(schedule.nextDueAt)}',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: NataloWeight.body,
                        color: overdue
                            ? NataloColors.danger
                            : cs.onSurfaceVariant)),
              ],
            ),
          ),
          _StatusBadge(overdue: overdue, soon: soon),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool overdue;
  final bool soon;
  const _StatusBadge({required this.overdue, required this.soon});
  @override
  Widget build(BuildContext context) {
    if (!overdue && !soon) return const SizedBox.shrink();
    final bg = overdue ? NataloColors.danger : _brandBlue;
    final label = overdue ? 'Terlambat' : 'Segera';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 9.5,
              fontWeight: NataloWeight.strong,
              color: Colors.white)),
    );
  }
}

class _HealthInfoRows extends StatelessWidget {
  final Pet pet;
  const _HealthInfoRows({required this.pet});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <(String, String)>[
      if (pet.sterilized != null)
        ('Steril', pet.sterilized! ? 'Ya' : 'Belum'),
      if (pet.allergy != null && pet.allergy!.trim().isNotEmpty)
        ('Alergi', pet.allergy!.trim()),
      if (pet.healthNote != null && pet.healthNote!.trim().isNotEmpty)
        ('Kondisi', pet.healthNote!.trim()),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: NataloWeight.strong)),
              TextSpan(
                  text: value,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: NataloWeight.body,
                      color: cs.onSurfaceVariant)),
            ])),
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
