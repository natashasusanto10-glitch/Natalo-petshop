import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/member_profile.dart';
import '../services/member_service.dart';
import '../state/member_store.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import '../widgets/glass_surface.dart';
import '../widgets/profile_avatar.dart';

const _brandBlue = Color(0xFF0B7FEA);

class MemberProfileScreen extends StatefulWidget {
  const MemberProfileScreen({super.key});

  @override
  State<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

class _MemberProfileScreenState extends State<MemberProfileScreen> {
  late Future<MemberProfile?> _profileFuture;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<MemberProfile?> _loadProfile() async {
    if (!memberStore.isLoggedIn) return memberStore.profile;
    try {
      final profile = await memberService.fetchProfile();
      memberStore.setProfile(profile);
      return profile;
    } catch (_) {
      return memberStore.profile;
    }
  }

  Future<void> _refresh() async {
    setState(() => _profileFuture = _loadProfile());
    await _profileFuture;
  }

  Future<void> _openEditProfile(MemberProfile profile) async {
    final updated = await showModalBottomSheet<MemberProfile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _EditProfileSheet(profile: profile),
    );
    if (updated == null) return;
    memberStore.setProfile(updated);
    setState(() => _profileFuture = Future.value(updated));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profil member diperbarui.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openPhotoSheet(MemberProfile profile) async {
    final hasPhoto = (profile.profilePhotoUrl ?? '').trim().isNotEmpty;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Foto Profil',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                _PhotoAction(
                  icon: Icons.photo_camera_rounded,
                  title: 'Ambil Foto',
                  onTap: () {
                    Navigator.pop(context);
                    _pickProfilePhoto(profile, ImageSource.camera);
                  },
                ),
                _PhotoAction(
                  icon: Icons.photo_library_rounded,
                  title: 'Pilih dari Galeri',
                  onTap: () {
                    Navigator.pop(context);
                    _pickProfilePhoto(profile, ImageSource.gallery);
                  },
                ),
                if (hasPhoto)
                  _PhotoAction(
                    icon: Icons.delete_outline_rounded,
                    title: 'Hapus Foto',
                    danger: true,
                    onTap: () {
                      Navigator.pop(context);
                      _confirmDeletePhoto(profile);
                    },
                  ),
                _PhotoAction(
                  icon: Icons.close_rounded,
                  title: 'Batal',
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickProfilePhoto(
    MemberProfile profile,
    ImageSource source,
  ) async {
    if (_photoBusy) return;
    setState(() => _photoBusy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked == null) return;
      final updated = await memberService.updateProfilePhoto(
        current: memberStore.profile ?? profile,
        sourcePath: picked.path,
      );
      memberStore.setProfile(updated);
      setState(() => _profileFuture = Future.value(updated));
      if (!mounted) return;
      AppToast.show(
        context,
        'Foto profil berhasil diperbarui',
        kind: ToastKind.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        source == ImageSource.camera
            ? 'Natalo perlu akses kamera untuk mengambil foto profil. Kamu bisa mengaktifkannya dari pengaturan HP.'
            : 'Foto profil belum berhasil diperbarui. Coba lagi ya.',
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _confirmDeletePhoto(MemberProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Hapus foto profil?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Foto profil kamu akan dihapus dan avatar akan kembali memakai inisial nama.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _photoBusy = true);
    try {
      final updated = await memberService.deleteProfilePhoto(
        memberStore.profile ?? profile,
      );
      memberStore.setProfile(updated);
      setState(() => _profileFuture = Future.value(updated));
      if (!mounted) return;
      AppToast.show(
        context,
        'Foto profil berhasil dihapus',
        kind: ToastKind.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        'Foto profil belum berhasil dihapus. Coba lagi ya.',
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Profil')),
      body: FutureBuilder<MemberProfile?>(
        future: _profileFuture,
        initialData: memberStore.profile,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          if (profile == null) return const _ProfileGuestState();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
                children: [
                  _ProfileHero(
                    initial: profile.initial,
                    name: profile.name,
                    email: profile.email,
                    points: profile.points,
                    photoUrl: profile.profilePhotoUrl,
                    photoBusy: _photoBusy,
                    onPhotoTap: () => _openPhotoSheet(profile),
                  ),
                  const SizedBox(height: 14),
                  _InfoTile(
                    index: 0,
                    icon: Icons.badge_outlined,
                    label: 'Nama',
                    value: profile.name,
                  ),
                  _InfoTile(
                    index: 1,
                    icon: Icons.alternate_email_rounded,
                    label: 'Email',
                    value: profile.email.isEmpty ? '-' : profile.email,
                  ),
                  _InfoTile(
                    index: 2,
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Nomor WhatsApp',
                    value: profile.phone.isEmpty ? '-' : profile.phone,
                  ),
                  _InfoTile(
                    index: 3,
                    icon: Icons.calendar_month_outlined,
                    label: 'Member Sejak',
                    value: _formatDate(profile.memberSince),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openEditProfile(profile),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Profil'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                  ),
                ]),
          );
        },
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  final MemberProfile profile;

  const _EditProfileSheet({required this.profile});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _phoneController = TextEditingController(text: widget.profile.phone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final updated = await memberService.updateProfile(
        current: widget.profile,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profil gagal disimpan: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'Edit Profil',
                style: TextStyle(
                  color: Color(0xFF17202A),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Nama',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  // Match Capacitor + auth screens: input radius 14
                  // (rounded rectangle), bukan 18.
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? 'Nama terlalu pendek'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Nomor WhatsApp',
                  prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
                  // Match Capacitor + auth screens: input radius 14
                  // (rounded rectangle), bukan 18.
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                validator: (value) {
                  final cleaned = (value ?? '').replaceAll(' ', '');
                  if (cleaned.isEmpty) return null;
                  final valid =
                      RegExp(r'^(\+?62|0)8[1-9][0-9]{6,12}$').hasMatch(cleaned);
                  return valid ? null : 'Format nomor belum valid';
                },
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text('Simpan Profil'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  final String initial;
  final String name;
  final String email;
  final int points;
  final String? photoUrl;
  final bool photoBusy;
  final VoidCallback onPhotoTap;

  const _ProfileHero({
    required this.initial,
    required this.name,
    required this.email,
    required this.points,
    this.photoUrl,
    required this.photoBusy,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 30,
      tint: const Color(0xFFF8FCFF),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              ProfileAvatar(
                initial: initial,
                imageUrl: photoUrl,
                size: 92,
                fontSize: 32,
                showCameraBadge: true,
                onTap: photoBusy ? null : onPhotoTap,
              ),
              if (photoBusy)
                Container(
                  height: 92,
                  width: 92,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.4,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF17202A),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: photoBusy ? null : onPhotoTap,
                  icon: const Icon(Icons.photo_camera_outlined, size: 16),
                  label: Text(
                    (photoUrl ?? '').isEmpty
                        ? 'Tambah Foto Profil'
                        : 'Ubah Foto',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: _brandBlue,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                AppStatusPill(
                  label: '$points poin aktif',
                  color: const Color(0xFF16A34A),
                  icon: Icons.stars_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  const _PhotoAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFEF4444) : _brandBlue;
    return ListTile(
      onTap: onTap,
      leading: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          color: danger ? const Color(0xFFFEE2E2) : const Color(0xFFEAF5FF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: danger ? color : const Color(0xFF17202A),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.index,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + index * 55),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: child,
          ),
        );
      },
      child: GlassSurface(
        radius: 24,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SoftIconTile(icon: icon, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF17202A),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileGuestState extends StatelessWidget {
  const _ProfileGuestState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SoftIconTile(
              icon: Icons.person_outline_rounded,
              color: _brandBlue,
              size: 76,
            ),
            const SizedBox(height: 16),
            const Text(
              'Masuk dulu untuk melihat profil member.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF17202A),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/member/login'),
              child: const Text('Login Member'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
