import 'dart:io';

import 'package:flutter/material.dart';

import '../models/pet_care_record.dart';
import '../services/pet_care_photo_store.dart';
import '../services/pet_service.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/haptics.dart';
import '../widgets/app_ui.dart';
import '../widgets/app_toast.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import 'pet_care_form_screen.dart';

const _brandBlue = NataloColors.primary;

class PetCareScreen extends StatefulWidget {
  final String petId;
  final String petName;
  const PetCareScreen({super.key, required this.petId, required this.petName});

  @override
  State<PetCareScreen> createState() => _PetCareScreenState();
}

class _PetCareScreenState extends State<PetCareScreen> {
  List<PetCareRecord> _records = const [];
  List<PetSchedule> _upcoming = const [];
  bool _loading = true;
  String? _error;
  PetCareCategory? _filter; // null = Semua

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
      final res = await petService.fetchCare(widget.petId);
      if (!mounted) return;
      setState(() {
        _records = res.records;
        _upcoming = res.upcoming;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat perawatan. Tarik untuk coba lagi.';
        _loading = false;
      });
    }
  }

  Future<void> _openForm() async {
    AppHaptics.tap();
    final created = await Navigator.of(context).push<PetCareRecord>(
      MaterialPageRoute(
          builder: (_) => PetCareFormScreen(petId: widget.petId)),
    );
    if (created != null) await _load();
  }

  Future<void> _markDone(PetSchedule schedule) async {
    // "Tandai selesai": tawarkan jadwal berikutnya dulu, lalu catat SATU
    // record baru kategori sama (doneAt = hari ini, nextDueAt opsional).
    AppHaptics.tap();
    final now = DateTime.now();
    final nextDue = await _pickFollowUpSchedule(now);
    if (!mounted) return;
    try {
      await petService.createCare(
        widget.petId,
        category: schedule.category,
        doneAt: now,
        nextDueAt: nextDue,
      );
      await _load();
      if (!mounted) return;
      AppToast.show(context, 'Ditandai selesai', kind: ToastKind.success);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal. Coba lagi.', kind: ToastKind.error);
    }
  }

  /// Bottom-sheet ringan setelah "Tandai selesai": tawarkan jadwal
  /// berikutnya (+1 bulan / +3 bulan / pilih tanggal / lewati).
  Future<DateTime?> _pickFollowUpSchedule(DateTime doneAt) async {
    return showModalBottomSheet<DateTime?>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Atur jadwal berikutnya?',
                    style: TextStyle(
                        fontSize: 15, fontWeight: NataloWeight.strong)),
                const SizedBox(height: 4),
                Text('Opsional — bisa dilewati kapan saja.',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: NataloWeight.body,
                        color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext)
                            .pop(doneAt.add(const Duration(days: 30))),
                        child: const Text('+1 bulan'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext)
                            .pop(doneAt.add(const Duration(days: 90))),
                        child: const Text('+3 bulan'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        initialDate: doneAt.add(const Duration(days: 30)),
                        firstDate: doneAt.add(const Duration(days: 1)),
                        lastDate: DateTime(doneAt.year + 5),
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: ColorScheme.light(
                              primary: _brandBlue,
                              onPrimary: Colors.white,
                              onSurface: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null && sheetContext.mounted) {
                        Navigator.of(sheetContext).pop(picked);
                      }
                    },
                    child: const Text('Pilih tanggal'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(null),
                    child: Text('Lewati',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(PetCareRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus catatan?'),
        content: Text('${record.category.label} akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus',
                  style: TextStyle(color: NataloColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await petService.deleteCare(widget.petId, record.id);
      await petCarePhotoStore.delete(record.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal menghapus.', kind: ToastKind.error);
    }
  }

  List<PetCareRecord> get _filtered => _filter == null
      ? _records
      : _records.where((r) => r.category == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Kembali',
        ),
        title: Text('Perawatan ${widget.petName}'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
      body: NataloPawRefreshIndicator(
        onRefresh: _load,
        child: AppFadeSwitcher(
          stateKey: _loading
              ? 'loading'
              : _error != null
                  ? 'error'
                  : (_records.isEmpty && _upcoming.isEmpty)
                      ? 'empty'
                      : 'content',
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const _CareSkeleton();
    if (_error != null) {
      return _CareMessage(icon: Icons.wifi_off_rounded, text: _error!);
    }
    if (_records.isEmpty && _upcoming.isEmpty) {
      return _CareEmpty(onAdd: () => _openForm());
    }
    final nearest = _upcoming.isNotEmpty ? _upcoming.first : null;
    final others = _upcoming.length > 1 ? _upcoming.sublist(1) : <PetSchedule>[];
    final filtered = _filtered;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 96),
      children: [
        _FilterRow(
          selected: _filter,
          onSelect: (c) => setState(() => _filter = c),
        ),
        if (nearest != null) ...[
          const SizedBox(height: 14),
          PetCareBanner(schedule: nearest, onMarkDone: () => _markDone(nearest)),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < others.length && i < 2; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _MiniSchedule(schedule: others[i])),
              ],
            ],
          ),
        ],
        const SizedBox(height: 14),
        Text('RIWAYAT',
            style: TextStyle(
                fontSize: 10,
                fontWeight: NataloWeight.strong,
                letterSpacing: 0.3,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Belum ada catatan untuk filter ini.',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: NataloWeight.body,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          )
        else
          for (final r in filtered)
            _HistoryTile(record: r, onDelete: () => _confirmDelete(r)),
      ],
    );
  }
}

/// Banner jadwal terdekat. Merah + label "SUDAH LEWAT JADWAL" saat overdue,
/// biru brand + "JADWAL TERDEKAT" selain itu.
class PetCareBanner extends StatelessWidget {
  final PetSchedule schedule;
  final VoidCallback onMarkDone;
  const PetCareBanner(
      {super.key, required this.schedule, required this.onMarkDone});

  @override
  Widget build(BuildContext context) {
    final status = scheduleStatusOf(schedule.nextDueAt);
    final overdue = status == ScheduleStatus.overdue;
    final bg = overdue ? NataloColors.dangerDark : _brandBlue;
    final label = overdue ? 'SUDAH LEWAT JADWAL' : 'JADWAL TERDEKAT';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: NataloWeight.strong,
                  letterSpacing: 0.4,
                  color: Colors.white70)),
          const SizedBox(height: 4),
          Text(schedule.category.label,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: NataloWeight.strong,
                  color: Colors.white)),
          const SizedBox(height: 7),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(scheduleCountdownLabel(schedule.nextDueAt),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: NataloWeight.strong,
                        color: Colors.white)),
              ),
              const Spacer(),
              InkWell(
                onTap: onMarkDone,
                child: const Text('Tandai selesai',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: NataloWeight.strong,
                        color: Colors.white,
                        decoration: TextDecoration.underline)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniSchedule extends StatelessWidget {
  final PetSchedule schedule;
  const _MiniSchedule({required this.schedule});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final overdue = scheduleStatusOf(schedule.nextDueAt) == ScheduleStatus.overdue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(schedule.category.icon, size: 13, color: _brandBlue),
              const SizedBox(width: 5),
              Flexible(
                child: Text(schedule.category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: NataloWeight.body,
                        color: cs.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(scheduleCountdownLabel(schedule.nextDueAt),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: NataloWeight.strong,
                  color: overdue ? NataloColors.dangerDark : null)),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final PetCareRecord record;
  final VoidCallback onDelete;
  const _HistoryTile({required this.record, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = [
      _fmtDate(record.doneAt),
      if (record.note != null && record.note!.trim().isNotEmpty)
        record.note!.trim(),
    ].join(' • ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isDark
                  ? _brandBlue.withValues(alpha: 0.18)
                  : NataloColors.primarySoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(record.category.icon, size: 15, color: _brandBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.category.label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: NataloWeight.strong)),
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: NataloWeight.body,
                        color: cs.onSurfaceVariant)),
                _CarePhotoThumb(recordId: record.id),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: Icon(Icons.more_horiz_rounded, color: cs.outline),
            tooltip: 'Hapus',
          ),
        ],
      ),
    );
  }
}

class _CarePhotoThumb extends StatefulWidget {
  final String recordId;
  const _CarePhotoThumb({required this.recordId});
  @override
  State<_CarePhotoThumb> createState() => _CarePhotoThumbState();
}

class _CarePhotoThumbState extends State<_CarePhotoThumb> {
  File? _file;
  @override
  void initState() {
    super.initState();
    petCarePhotoStore.get(widget.recordId).then((f) {
      if (mounted) setState(() => _file = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    if (f == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog(child: Image.file(f)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(f, width: 56, height: 56, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final PetCareCategory? selected;
  final ValueChanged<PetCareCategory?> onSelect;
  const _FilterRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(context, 'Semua', selected == null, () => onSelect(null)),
          for (final c in PetCareCategory.ordered) ...[
            const SizedBox(width: 6),
            _chip(context, c.label, selected == c, () => onSelect(c)),
          ],
        ],
      ),
    );
  }

  Widget _chip(
      BuildContext context, String label, bool active, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? _brandBlue : Colors.transparent,
            border: Border.all(color: active ? _brandBlue : cs.outlineVariant),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: NataloWeight.strong,
                  color: active ? Colors.white : cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}

class _CareEmpty extends StatelessWidget {
  final VoidCallback onAdd;
  const _CareEmpty({required this.onAdd});
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
              child: const Icon(Icons.medical_services_outlined,
                  color: _brandBlue, size: 30),
            ),
            const SizedBox(height: 16),
            const Text('Belum ada perawatan',
                style: TextStyle(
                    fontSize: 15, fontWeight: NataloWeight.strong)),
            const SizedBox(height: 6),
            Text(
                'Catat vaksin, grooming, atau obat untuk memantau kesehatannya.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: NataloWeight.body,
                    color: cs.onSurfaceVariant)),
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
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Catat Perawatan',
                    style: TextStyle(
                        fontWeight: NataloWeight.strong, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CareMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CareMessage({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 90, 32, 100),
        child: Column(
          children: [
            Icon(icon, color: cs.onSurfaceVariant, size: 40),
            const SizedBox(height: 14),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: NataloWeight.body,
                    color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _CareSkeleton extends StatelessWidget {
  const _CareSkeleton();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Container(
          height: 96,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
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
