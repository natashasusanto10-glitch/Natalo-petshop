import 'dart:io';

import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../models/pet_care_record.dart';
import '../services/api_client.dart';
import '../services/pet_care_photo_store.dart';
import '../services/pet_service.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/haptics.dart';
import '../utils/read_only_mode.dart';
import '../widgets/app_toast.dart';
import '../widgets/care_product_picker.dart';
import 'profile_photo_picker_screen.dart';

const _brandBlue = NataloColors.primary;

/// Form "Catat Perawatan" — pop `PetCareRecord` saat sukses, `null` saat batal.
class PetCareFormScreen extends StatefulWidget {
  final Pet pet;
  const PetCareFormScreen({super.key, required this.pet});

  @override
  State<PetCareFormScreen> createState() => _PetCareFormScreenState();
}

class _PetCareFormScreenState extends State<PetCareFormScreen> {
  PetCareCategory _category = PetCareCategory.grooming;
  DateTime _doneAt = DateTime.now();
  DateTime? _nextDueAt;
  final _noteController = TextEditingController();
  final _placeController = TextEditingController();
  final _vaccineNameController = TextEditingController();
  final _complaintController = TextEditingController();
  late final _weightController = TextEditingController(
      text: widget.pet.weightKg != null
          ? _fmtWeight(widget.pet.weightKg!)
          : '');
  File? _pickedPhoto;
  bool _saving = false;

  double? _weightKg;
  String? _place;
  String? _vaccineName;
  String? _complaint;
  CareSelection? _selection;

  @override
  void initState() {
    super.initState();
    _weightKg = widget.pet.weightKg;
  }

  @override
  void dispose() {
    _noteController.dispose();
    _placeController.dispose();
    _vaccineNameController.dispose();
    _complaintController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _pickDoneDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _doneAt,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
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
    if (picked != null) setState(() => _doneAt = picked);
  }

  Future<void> _pickNextDate() async {
    final base = _doneAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDueAt ?? base.add(const Duration(days: 30)),
      firstDate: base.add(const Duration(days: 1)),
      lastDate: DateTime(base.year + 5),
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
    if (picked != null) setState(() => _nextDueAt = picked);
  }

  Future<void> _pickPhoto() async {
    AppHaptics.tap();
    final cropped =
        await ProfilePhotoPickerScreen.open(context, title: 'Foto perawatan');
    if (cropped != null) setState(() => _pickedPhoto = cropped);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final note = _noteController.text.trim();
      final isDewormOrFlea =
          _category == PetCareCategory.deworm || _category == PetCareCategory.flea;
      final record = await petService.createCare(
        widget.pet.id,
        category: _category,
        doneAt: _doneAt,
        note: note.isEmpty ? null : note,
        nextDueAt: _nextDueAt,
        weightKg: isDewormOrFlea ? _weightKg : null,
        productId: isDewormOrFlea ? _selection?.productId : null,
        brandText: isDewormOrFlea ? _selection?.brandText : null,
        dosageNote: isDewormOrFlea ? _selection?.dosageNote : null,
        place: (_category == PetCareCategory.grooming ||
                _category == PetCareCategory.vaccine ||
                _category == PetCareCategory.vet)
            ? _place
            : null,
        vaccineName: _category == PetCareCategory.vaccine ? _vaccineName : null,
        complaint: _category == PetCareCategory.vet ? _complaint : null,
      );
      if (_pickedPhoto != null) {
        try {
          await petCarePhotoStore.save(record.id, _pickedPhoto!.path);
        } catch (_) {
          // Foto lokal gagal disimpan — record tetap sukses, jangan blokir.
        }
      }
      AppHaptics.success();
      if (!mounted) return;
      Navigator.of(context).pop(record);
      AppToast.show(context, 'Perawatan dicatat', kind: ToastKind.success);
    } on ReadOnlyModeException {
      if (!mounted) return;
      AppToast.show(context, 'Mode aman aktif, coba lagi nanti.',
          kind: ToastKind.warning);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message, kind: ToastKind.error);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal menyimpan. Coba lagi.',
          kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFmt = _fmtDate(_doneAt);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Tutup',
        ),
        title: const Text('Catat Perawatan'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Simpan',
                    style: TextStyle(
                        fontWeight: NataloWeight.strong, color: _brandBlue)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          const _Label('Jenis perawatan'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in PetCareCategory.ordered)
                _CategoryChip(
                  category: c,
                  selected: _category == c,
                  onTap: () => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 18),
          ..._buildCategoryFields(),
          const _Label('Tanggal dilakukan'),
          const SizedBox(height: 6),
          _PickerField(
            icon: Icons.calendar_today_rounded,
            text: dateFmt,
            onTap: _pickDoneDate,
          ),
          const SizedBox(height: 18),
          const _Label('Foto (opsional)'),
          const SizedBox(height: 6),
          _PhotoField(picked: _pickedPhoto, onTap: _pickPhoto),
          const SizedBox(height: 18),
          const _Label('Catatan (opsional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _noteController,
            maxLength: 200,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              filled: true,
              fillColor: cs.surface,
              hintText: _category.noteHint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const _Label('Jadwal berikutnya (opsional)'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _NextChip(
                label: '+1 bulan',
                selected: _isNext(const Duration(days: 30)),
                onTap: () => setState(() =>
                    _nextDueAt = _doneAt.add(const Duration(days: 30))),
              ),
              _NextChip(
                label: '+3 bulan',
                selected: _isNext(const Duration(days: 90)),
                onTap: () => setState(() =>
                    _nextDueAt = _doneAt.add(const Duration(days: 90))),
              ),
              _NextChip(
                label: _nextDueAt != null && !_isPreset()
                    ? _fmtDate(_nextDueAt!)
                    : 'Pilih tanggal',
                selected: _nextDueAt != null && !_isPreset(),
                onTap: _pickNextDate,
              ),
              if (_nextDueAt != null)
                _NextChip(
                  label: 'Hapus jadwal',
                  selected: false,
                  onTap: () => setState(() => _nextDueAt = null),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCategoryFields() {
    switch (_category) {
      case PetCareCategory.deworm:
      case PetCareCategory.flea:
        return [
          const _Label('Berat saat ini (kg)'),
          const SizedBox(height: 6),
          TextField(
            controller: _weightController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              hintText: widget.pet.weightKg != null
                  ? 'Terakhir: ${_fmtWeight(widget.pet.weightKg!)} kg'
                  : 'Mis. 4.2',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            onChanged: (v) => setState(() => _weightKg = double.tryParse(v.trim())),
          ),
          const SizedBox(height: 12),
          CareProductPicker(
            category: _category,
            species: widget.pet.type,
            weightKg: _weightKg,
            onChanged: (s) => setState(() => _selection = s),
          ),
          const SizedBox(height: 18),
        ];
      case PetCareCategory.grooming:
        return [
          const _Label('Tempat grooming (opsional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _placeController,
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              hintText: 'Mis. Natalo Petshop',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            onChanged: (v) => setState(() => _place = v.trim().isEmpty ? null : v.trim()),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final suggestion in const ['Natalo Petshop', 'Di rumah'])
                _NextChip(
                  label: suggestion,
                  selected: _place == suggestion,
                  onTap: () => setState(() {
                    _place = suggestion;
                    _placeController.text = suggestion;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ];
      case PetCareCategory.vaccine:
        return [
          const _Label('Nama vaksin (opsional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _vaccineNameController,
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              hintText: 'Mis. Rabies',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            onChanged: (v) =>
                setState(() => _vaccineName = v.trim().isEmpty ? null : v.trim()),
          ),
          const SizedBox(height: 8),
          const _Label('Dokter hewan/tempat (opsional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _placeController,
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              hintText: 'Mis. Klinik Sehat',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            onChanged: (v) => setState(() => _place = v.trim().isEmpty ? null : v.trim()),
          ),
          const SizedBox(height: 18),
        ];
      case PetCareCategory.vet:
        return [
          const _Label('Keluhan/tujuan kunjungan (opsional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _complaintController,
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              hintText: 'Mis. Cek rutin',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            onChanged: (v) =>
                setState(() => _complaint = v.trim().isEmpty ? null : v.trim()),
          ),
          const SizedBox(height: 8),
          const _Label('Dokter hewan/tempat (opsional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _placeController,
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              hintText: 'Mis. Klinik Sehat',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            onChanged: (v) => setState(() => _place = v.trim().isEmpty ? null : v.trim()),
          ),
          const SizedBox(height: 18),
        ];
      case PetCareCategory.other:
        return const [];
    }
  }

  bool _isPreset() =>
      _isNext(const Duration(days: 30)) || _isNext(const Duration(days: 90));

  bool _isNext(Duration d) {
    final n = _nextDueAt;
    if (n == null) return false;
    final expected = _doneAt.add(d);
    return n.year == expected.year &&
        n.month == expected.month &&
        n.day == expected.day;
  }
}

String _fmtWeight(double w) {
  final s = w.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(text,
        style: TextStyle(
            fontSize: 12,
            fontWeight: NataloWeight.body,
            color: cs.onSurfaceVariant));
  }
}

class _CategoryChip extends StatelessWidget {
  final PetCareCategory category;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip(
      {required this.category, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                    ? _brandBlue.withValues(alpha: 0.20)
                    : NataloColors.primarySoft)
                : Colors.transparent,
            border: Border.all(
                color: selected ? _brandBlue : cs.outlineVariant),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(category.icon,
                  size: 15,
                  color: selected ? _brandBlue : cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(category.label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: NataloWeight.strong,
                      color: selected ? _brandBlue : cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  const _PickerField(
      {required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(text, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoField extends StatelessWidget {
  final File? picked;
  final VoidCallback onTap;
  const _PhotoField({required this.picked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (picked != null) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(picked!,
                width: 56, height: 56, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: onTap, child: const Text('Ganti foto')),
        ],
      );
    }
    // WAJIB Align: sebagai anak ListView, constraint cross-axis-nya TIGHT
    // (minWidth == maxWidth == lebar layar) sehingga `width: 56` di Container
    // diabaikan dan kotaknya melebar full-width — persis blok "foto besar"
    // yang spec form dinamis justru minta dihapus. Align meneruskan
    // constraint loose, jadi thumbnail 56px benar-benar 56px.
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.add_a_photo_outlined,
                size: 18, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _NextChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NextChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                    ? _brandBlue.withValues(alpha: 0.20)
                    : NataloColors.primarySoft)
                : Colors.transparent,
            border: Border.all(
                color: selected ? _brandBlue : cs.outlineVariant),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: NataloWeight.strong,
                  color: selected ? _brandBlue : cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}
