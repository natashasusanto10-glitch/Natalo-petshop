import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../services/api_client.dart';
import '../services/pet_service.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/haptics.dart';
import '../utils/read_only_mode.dart';
import '../widgets/app_toast.dart';
import 'profile_photo_picker_screen.dart';

const _brandBlue = NataloColors.primary;

/// Sentinel yang di-pop [PetFormScreen] saat pet DIHAPUS — beda dgn `null`
/// (dibatalkan) atau [Pet] (berhasil disimpan/ditambah), supaya caller bisa
/// membedakan "refresh data di tempat" vs "data sudah tidak valid, tutup".
class PetDeleted {
  const PetDeleted();
}

const petDeleted = PetDeleted();

/// Form tambah/edit pet ("Anabulku" Tahap 1). Foto di-pick+crop lewat
/// engine bersama [ProfilePhotoPickerScreen] (sama dengan foto profil
/// user) — kompresi JPEG otomatis, jadi TIDAK upload file mentah.
///
/// Upload foto ditunda sampai Simpan ditekan (bukan langsung saat pick):
/// pet baru belum punya id sebelum create sukses, dan menunda juga
/// membuat perilaku "Batal" konsisten — tidak ada foto ter-upload kalau
/// form dibatalkan.
class PetFormScreen extends StatefulWidget {
  final Pet? pet;

  const PetFormScreen({super.key, this.pet});

  @override
  State<PetFormScreen> createState() => _PetFormScreenState();
}

class _PetFormScreenState extends State<PetFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _breedController;
  late final TextEditingController _bioController;
  String _type = kPetTypes.first;
  DateTime? _birthDate;
  PetGender? _gender;
  File? _pickedPhoto;
  bool _saving = false;
  bool _deleting = false;
  bool? _sterilized;
  final _allergyController = TextEditingController();
  final _healthNoteController = TextEditingController();

  bool get _isEdit => widget.pet != null;

  @override
  void initState() {
    super.initState();
    final pet = widget.pet;
    _nameController = TextEditingController(text: pet?.name ?? '');
    _breedController = TextEditingController(text: pet?.breed ?? '');
    _bioController = TextEditingController(text: pet?.bio ?? '');
    _type = pet != null && kPetTypes.contains(pet.type)
        ? pet.type
        : kPetTypes.first;
    _birthDate = pet?.birthDate;
    _gender = pet?.gender;
    _sterilized = widget.pet?.sterilized;
    _allergyController.text = widget.pet?.allergy ?? '';
    _healthNoteController.text = widget.pet?.healthNote ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _breedController.dispose();
    _bioController.dispose();
    _allergyController.dispose();
    _healthNoteController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_saving || _deleting) return;
    AppHaptics.tap();
    final cropped = await ProfilePhotoPickerScreen.open(
      context,
      title: 'Foto pet baru',
    );
    if (cropped == null || !mounted) return;
    setState(() => _pickedPhoto = cropped);
  }

  Future<void> _pickBirthDate() async {
    if (_saving || _deleting) return;
    AppHaptics.tap();
    final now = DateTime.now();
    final initial = _birthDate ?? DateTime(now.year - 1, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 40),
      lastDate: now,
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _brandBlue,
              onPrimary: Colors.white,
              onSurface: Color(0xFF101828),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _brandBlue),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    if (_saving || _deleting) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppToast.show(context, 'Nama pet wajib diisi.', kind: ToastKind.warning);
      return;
    }
    AppHaptics.tap();
    setState(() => _saving = true);
    try {
      final breed = _breedController.text.trim();
      final bio = _bioController.text.trim();
      Pet pet = _isEdit
          ? await petService.updatePet(
              widget.pet!.id,
              name: name,
              type: _type,
              breed: breed.isEmpty ? null : breed,
              birthDate: _birthDate,
              gender: _gender,
              bio: bio.isEmpty ? null : bio,
              sterilized: _sterilized,
              allergy: _allergyController.text.trim().isEmpty
                  ? null
                  : _allergyController.text.trim(),
              healthNote: _healthNoteController.text.trim().isEmpty
                  ? null
                  : _healthNoteController.text.trim(),
            )
          : await petService.createPet(
              name: name,
              type: _type,
              breed: breed.isEmpty ? null : breed,
              birthDate: _birthDate,
              gender: _gender,
              bio: bio.isEmpty ? null : bio,
              sterilized: _sterilized,
              allergy: _allergyController.text.trim().isEmpty
                  ? null
                  : _allergyController.text.trim(),
              healthNote: _healthNoteController.text.trim().isEmpty
                  ? null
                  : _healthNoteController.text.trim(),
            );
      final photo = _pickedPhoto;
      if (photo != null) {
        pet = await petService.uploadPetPhoto(pet.id, photo.path);
      }
      if (!mounted) return;
      AppHaptics.success();
      Navigator.of(context).pop(pet);
      AppToast.show(
        context,
        _isEdit ? 'Profil pet diperbarui.' : 'Pet berhasil ditambahkan.',
        kind: ToastKind.success,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(context, error.message, kind: ToastKind.error);
    } on ReadOnlyModeException {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(
        context,
        'Mode aman aktif. Simpan pet belum bisa dilakukan.',
        kind: ToastKind.warning,
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(context, 'Gagal menyimpan: $error', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    if (_saving || _deleting) return;
    AppHaptics.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus pet?'),
        content: Text(
          '${widget.pet!.name} akan dihapus dari Anabulku. Tindakan ini tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await petService.deletePet(widget.pet!.id);
      if (!mounted) return;
      AppHaptics.success();
      Navigator.of(context).pop(petDeleted);
      AppToast.show(context, 'Pet dihapus.', kind: ToastKind.success);
    } on ApiException catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(context, error.message, kind: ToastKind.error);
    } on ReadOnlyModeException {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(
        context,
        'Mode aman aktif. Hapus pet belum bisa dilakukan.',
        kind: ToastKind.warning,
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(context, 'Gagal menghapus: $error', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final busy = _saving || _deleting;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        // Header ikut standar global (appBarTheme): title 18/w700, flat +
        // hairline border. Konsisten dgn halaman lain.
        leading: IconButton(
          onPressed: busy ? null : () => Navigator.maybePop(context),
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Tutup',
        ),
        title: Text(_isEdit ? 'Edit Pet' : 'Tambah Pet'),
        actions: [
          TextButton(
            onPressed: busy ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _brandBlue,
                    ),
                  )
                : const Text(
                    'Simpan',
                    style: TextStyle(
                      color: _brandBlue,
                      fontWeight: NataloWeight.strong,
                    ),
                  ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Center(child: _PhotoPicker(pet: widget.pet, file: _pickedPhoto, onTap: _pickPhoto)),
          const SizedBox(height: 24),
          const _FieldLabel('Nama'),
          TextField(
            controller: _nameController,
            enabled: !busy,
            maxLength: 40,
            decoration: const InputDecoration(
              hintText: 'Nama pet',
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Jenis'),
          DropdownButtonFormField<String>(
            initialValue: _type,
            onChanged: busy ? null : (v) => setState(() => _type = v!),
            items: [
              for (final type in kPetTypes)
                DropdownMenuItem(value: type, child: Text(type)),
            ],
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Breed (opsional)'),
          TextField(
            controller: _breedController,
            enabled: !busy,
            maxLength: 60,
            decoration: const InputDecoration(
              hintText: 'Contoh: British Shorthair',
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Tanggal lahir (opsional)'),
          InkWell(
            onTap: busy ? null : _pickBirthDate,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: const InputDecoration(),
              child: Text(
                _birthDate == null
                    ? 'Pilih tanggal'
                    : '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}',
                style: TextStyle(
                  color: _birthDate == null ? cs.onSurfaceVariant : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Gender (opsional)'),
          _GenderSelector(
            value: _gender,
            enabled: !busy,
            onChanged: (v) => setState(() => _gender = v),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Bio (opsional)'),
          TextField(
            controller: _bioController,
            enabled: !busy,
            maxLength: 150,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Ceritakan sedikit tentang pet ini',
            ),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Steril'),
          Row(
            children: [
              Expanded(
                child: _SterilChip(
                  label: 'Ya',
                  selected: _sterilized == true,
                  onTap: () => setState(() =>
                      _sterilized = _sterilized == true ? null : true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SterilChip(
                  label: 'Belum',
                  selected: _sterilized == false,
                  onTap: () => setState(() =>
                      _sterilized = _sterilized == false ? null : false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Alergi (opsional)'),
          TextField(
            controller: _allergyController,
            maxLength: 100,
            decoration: _healthFieldDecoration(context, 'Mis. Ayam'),
          ),
          const SizedBox(height: 8),
          const _FieldLabel('Kondisi khusus (opsional)'),
          TextField(
            controller: _healthNoteController,
            maxLength: 150,
            maxLines: 2,
            minLines: 1,
            decoration: _healthFieldDecoration(context, 'Mis. Sensitif dingin'),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: busy ? null : _confirmDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFEF4444),
                        ),
                      )
                    : const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text(
                  'Hapus Pet',
                  style: TextStyle(fontWeight: NataloWeight.strong),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: NataloWeight.body,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _GenderSelector extends StatelessWidget {
  final PetGender? value;
  final bool enabled;
  final ValueChanged<PetGender?> onChanged;

  const _GenderSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _GenderChip(
            label: 'Jantan',
            icon: Icons.male_rounded,
            selected: value == PetGender.male,
            enabled: enabled,
            onTap: () =>
                onChanged(value == PetGender.male ? null : PetGender.male),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _GenderChip(
            label: 'Betina',
            icon: Icons.female_rounded,
            selected: value == PetGender.female,
            enabled: enabled,
            onTap: () => onChanged(
                value == PetGender.female ? null : PetGender.female),
          ),
        ),
      ],
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _GenderChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                    ? _brandBlue.withValues(alpha: 0.20)
                    : NataloColors.primarySoft)
                : null,
            border: Border.all(
              color: selected ? _brandBlue : cs.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18, color: selected ? _brandBlue : cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: NataloWeight.strong,
                  color: selected ? _brandBlue : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SterilChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SterilChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                    ? _brandBlue.withValues(alpha: 0.20)
                    : NataloColors.primarySoft)
                : Colors.transparent,
            border: Border.all(
                color: selected ? _brandBlue : cs.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: NataloWeight.strong,
                  color: selected ? _brandBlue : cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}

InputDecoration _healthFieldDecoration(BuildContext context, String hint) {
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    filled: true,
    fillColor: cs.surface,
    hintText: hint,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant),
    ),
  );
}

class _PhotoPicker extends StatelessWidget {
  final Pet? pet;
  final File? file;
  final VoidCallback onTap;

  const _PhotoPicker({required this.pet, required this.file, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const size = 88.0;
    final url = pet?.photoUrl;
    final fallback = Container(
      color: NataloColors.grey400.withValues(alpha: 0.25),
      alignment: Alignment.center,
      child: const Icon(Icons.pets_rounded, color: _brandBlue, size: 34),
    );
    Widget content;
    if (file != null) {
      content = Image.file(file!, fit: BoxFit.cover, width: size, height: size);
    } else if (url != null && url.isNotEmpty) {
      content = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: size,
        height: size,
        fadeInDuration: const Duration(milliseconds: 180),
        placeholder: (_, __) => Container(
          color: NataloColors.grey400.withValues(alpha: 0.25),
        ),
        errorWidget: (_, __, ___) => fallback,
      );
    } else {
      content = fallback;
    }
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ClipOval(
            child: SizedBox(width: size, height: size, child: content),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: _brandBlue,
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.white, width: 2),
                ),
              ),
              child: const Icon(Icons.camera_alt_rounded,
                  color: Colors.white, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}
