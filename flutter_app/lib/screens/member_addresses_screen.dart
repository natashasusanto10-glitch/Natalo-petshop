import 'package:flutter/material.dart';

import '../models/member_profile.dart';
import '../services/member_service.dart';
import '../widgets/address_autocomplete_field.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../state/member_store.dart';
import '../widgets/app_ui.dart';

const _brandBlue = Color(0xFF0B7FEA);

class MemberAddressesScreen extends StatefulWidget {
  const MemberAddressesScreen({super.key});

  @override
  State<MemberAddressesScreen> createState() => _MemberAddressesScreenState();
}

class _MemberAddressesScreenState extends State<MemberAddressesScreen> {
  late Future<List<MemberAddress>> _addressesFuture;
  List<MemberAddress> _addresses = const [];

  @override
  void initState() {
    super.initState();
    _addressesFuture = _loadAddresses();
  }

  Future<List<MemberAddress>> _loadAddresses() async {
    if (!memberStore.isLoggedIn) return [];
    try {
      final addresses = await memberService.fetchAddresses();
      _addresses = addresses;
      return _addresses;
    } catch (_) {
      return [];
    }
  }

  Future<void> _refresh() async {
    setState(() => _addressesFuture = _loadAddresses());
    await _addressesFuture;
  }

  Future<void> _openAddressForm([MemberAddress? address]) async {
    final saved = await showModalBottomSheet<MemberAddress>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AddressFormSheet(address: address),
    );
    if (saved == null) return;
    setState(() => _addressesFuture = _loadAddresses());
  }

  Future<void> _setPrimary(MemberAddress address) async {
    try {
      await memberService.setPrimaryAddress(address.id);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alamat utama diperbarui.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal set utama: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteAddress(MemberAddress address) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Hapus alamat?'),
        content: Text(
          'Alamat ${address.label} untuk ${address.recipient} akan dihapus dari akun member.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await memberService.deleteAddress(address.id);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alamat berhasil dihapus.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alamat gagal dihapus: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!memberStore.isLoggedIn) {
      return const _LoginRequiredScaffold(title: 'Alamat');
    }

    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      // Solid white bg (was transparent → kalau parent transparent ke
      // device bg, content GlassSurface BackdropFilter bisa render
      // weird di iOS — text invisible, blank screen reports dari user).
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 1),
        ),
        title: Text(
          'Alamat',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
        actions: [
          AppHeaderIconButton(
            onPressed: _openAddressForm,
            tooltip: 'Tambah alamat',
            child: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<MemberAddress>>(
        future: _addressesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const AppSkeletonList(itemCount: 5);
          }
          final addresses = snapshot.data ?? _addresses;
          return NataloPawRefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
              itemCount: addresses.isEmpty ? 2 : addresses.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) return const _AddressHeader();
                if (addresses.isEmpty) {
                  return _EmptyAddressesCard(
                    onAdd: _openAddressForm,
                  );
                }
                final address = addresses[index - 1];
                return _AddressCard(
                  address: address,
                  index: index - 1,
                  onEdit: () => _openAddressForm(address),
                  onSetPrimary: () => _setPrimary(address),
                  onDelete: () => _deleteAddress(address),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _LoginRequiredScaffold extends StatelessWidget {
  final String title;

  const _LoginRequiredScaffold({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 76,
                width: 76,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                      : const Color(0xFFEAF5FF),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: _brandBlue,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Login member diperlukan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Masuk untuk menyimpan dan mengedit alamat pengiriman.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/member/login'),
                child: const Text('Masuk Member'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAddressesCard extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyAddressesCard({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          // Icon location pin di lingkaran biru lembut — replace Lottie
          // stub yang cuma render pets icon fallback (visual misleading).
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                  : const Color(0xFFEAF5FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: _brandBlue,
              size: 44,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Belum ada alamat tersimpan',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tambahkan alamat member agar checkout pengiriman bisa lebih cepat.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              height: 1.45,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Tambah Alamat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressHeader extends StatelessWidget {
  const _AddressHeader();

  @override
  Widget build(BuildContext context) {
    // Plain Container, bukan GlassSurface — BackdropFilter di iOS bisa
    // render weird saat scaffold transparent dan tidak ada content
    // di belakang untuk di-blur (root cause user report "alamat error
    // blank page").
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                  : const Color(0xFFEAF5FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.location_on_outlined,
              color: _brandBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tambah, edit, atau jadikan alamat utama untuk checkout lebih cepat.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final MemberAddress address;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onSetPrimary;
  final VoidCallback onDelete;

  const _AddressCard({
    required this.address,
    required this.index,
    required this.onEdit,
    required this.onSetPrimary,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + index * 70),
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
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF111111).withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Tags row: Label / Utama / Pinpoint OK / Area Biteship OK ──
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _AddressTag(
                  label: address.label ?? 'Alamat',
                  variant: _TagVariant.neutral,
                ),
                if (address.isPrimary)
                  const _AddressTag(
                    label: 'Utama',
                    variant: _TagVariant.primary,
                  ),
                if (address.latitude != null && address.longitude != null)
                  const _AddressTag(
                    label: 'Pinpoint OK',
                    variant: _TagVariant.success,
                  ),
                if (address.areaId != null && address.areaId!.isNotEmpty)
                  const _AddressTag(
                    label: 'Area Biteship OK',
                    variant: _TagVariant.success,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Nama - No HP bold ──
            Text(
              '${address.recipient} - ${address.phone}',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              address.address,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            // BUG FIX: sebelumnya ada Text(address.recipient) standalone di
            // bawah alamat — duplicate dari baris "Nama - HP" di atas.
            // Hasilnya nama recipient tampil dua kali di card. Removed.
            if (address.areaLabel != null && address.areaLabel!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                address.areaLabel!,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
            if (address.pinpointAddress != null &&
                address.pinpointAddress!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                      : const Color(0xFFEAF5FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Pinpoint: ${address.pinpointAddress}',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Divider(color: cs.outlineVariant, height: 1),
            const SizedBox(height: 12),
            // ── Action buttons: Edit (outline gray) + Hapus (outline red) — right aligned ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _AddressActionButton(
                  label: 'Edit',
                  color: cs.onSurfaceVariant,
                  borderColor: cs.outlineVariant,
                  onTap: onEdit,
                ),
                const SizedBox(width: 10),
                _AddressActionButton(
                  label: 'Hapus',
                  color: const Color(0xFFEF4444),
                  borderColor: const Color(0xFFFECACA),
                  onTap: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _TagVariant { neutral, primary, success }

class _AddressTag extends StatelessWidget {
  final String label;
  final _TagVariant variant;

  const _AddressTag({required this.label, required this.variant});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    late final Color bg;
    late final Color border;
    late final Color text;
    switch (variant) {
      case _TagVariant.neutral:
        bg = cs.surface;
        border = cs.outlineVariant;
        text = cs.onSurfaceVariant;
        break;
      case _TagVariant.primary:
        bg = _brandBlue;
        border = _brandBlue;
        text = Colors.white;
        break;
      case _TagVariant.success:
        bg = const Color(0xFFF0FDF4);
        border = const Color(0xFFBBF7D0);
        text = const Color(0xFF16A34A);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AddressActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color borderColor;
  final VoidCallback onTap;

  const _AddressActionButton({
    required this.label,
    required this.color,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressFormSheet extends StatefulWidget {
  final MemberAddress? address;

  const _AddressFormSheet({this.address});

  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _recipientController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _postalController;
  late final TextEditingController _provinceController;
  late final TextEditingController _districtController;
  late String _label;
  late bool _isPrimary;
  bool _saving = false;
  // Koordinat dari autocomplete pick (atau dari record existing).
  // Critical untuk eligibility kurir instant (Gojek/Grab) — backend
  // /api/shipping/rates butuh destination_latitude + destination_longitude.
  // Tanpa ini, response selalu "Lengkapi titik lokasi alamat agar
  // Gojek Instant dan Grab Instant tersedia."
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    final address = widget.address;
    _label = address?.label == 'Kantor' ? 'Kantor' : 'Rumah';
    _isPrimary = address?.isPrimary ?? false;
    _recipientController =
        TextEditingController(text: address?.recipient ?? '');
    _phoneController = TextEditingController(text: address?.phone ?? '');
    _addressController = TextEditingController(text: address?.address ?? '');
    _cityController = TextEditingController(text: address?.city ?? 'Medan');
    _postalController =
        TextEditingController(text: address?.postalCode ?? '20212');
    _provinceController =
        TextEditingController(text: address?.provinceName ?? 'Sumatera Utara');
    _districtController =
        TextEditingController(text: address?.districtName ?? 'Medan Kota');
    _latitude = address?.latitude;
    _longitude = address?.longitude;
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _postalController.dispose();
    _provinceController.dispose();
    _districtController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final previous = widget.address;
      final payload = MemberAddress(
        id: previous?.id ?? '',
        label: _label,
        recipient: _recipientController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        isPrimary: _isPrimary,
        city: _cityController.text.trim(),
        postalCode: _postalController.text.trim(),
        provinceName: _provinceController.text.trim(),
        districtName: _districtController.text.trim(),
        areaId: previous?.areaId,
        areaLabel: previous?.areaLabel,
        // Pakai state yang di-update dari autocomplete pick. Fallback ke
        // previous record's lat/lng kalau user buka edit tapi tidak ulang
        // pilih dari autocomplete.
        latitude: _latitude ?? previous?.latitude,
        longitude: _longitude ?? previous?.longitude,
        pinpointAddress: previous?.pinpointAddress,
      );
      final saved = previous == null
          ? await memberService.createAddress(payload)
          : await memberService.updateAddress(payload);
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alamat gagal disimpan: $error'),
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
              Text(
                widget.address == null ? 'Tambah Alamat' : 'Edit Alamat',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _label,
                decoration: const InputDecoration(labelText: 'Label'),
                items: const [
                  DropdownMenuItem(value: 'Rumah', child: Text('Rumah')),
                  DropdownMenuItem(value: 'Kantor', child: Text('Kantor')),
                ],
                onChanged: (value) => setState(() => _label = value ?? 'Rumah'),
              ),
              const SizedBox(height: 12),
              _TextField(
                controller: _recipientController,
                label: 'Nama penerima',
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? 'Minimal 2 karakter'
                    : null,
              ),
              const SizedBox(height: 12),
              _TextField(
                controller: _phoneController,
                label: 'Nomor telepon',
                keyboardType: TextInputType.phone,
                validator: (value) => (value?.trim().length ?? 0) < 8
                    ? 'Nomor belum valid'
                    : null,
              ),
              const SizedBox(height: 12),
              // Single search field — autocomplete address Google Places.
              // Tombol GPS + Cari + Wilayah dihapus per revisi spec, cukup
              // satu kolom search dengan dropdown rekomendasi real-time.
              // Tap salah satu suggestion → field address/kota/kode pos/
              // provinsi/kecamatan otomatis terisi (lihat onSelected).
              AddressAutocompleteField(
                controller: _addressController,
                hint: 'Cari Nama Jalan, Gedung, Alamat',
                validator: (value) => (value?.trim().length ?? 0) < 5
                    ? 'Alamat minimal 5 karakter'
                    : null,
                onSelected: (details) {
                  setState(() {
                    _addressController.text = details.formattedAddress;
                    if (details.postalCode?.isNotEmpty == true) {
                      _postalController.text = details.postalCode!;
                    }
                    if (details.city?.isNotEmpty == true) {
                      _cityController.text = details.city!;
                    }
                    if (details.province?.isNotEmpty == true) {
                      _provinceController.text = details.province!;
                    }
                    if (details.district?.isNotEmpty == true) {
                      _districtController.text = details.district!;
                    }
                    // Simpan lat/lng dari Google Places → wajib untuk
                    // eligibility kurir instant Gojek/Grab. Tanpa ini
                    // alamat selalu di-tag "belum tersedia untuk instant".
                    if (details.latitude != null && details.longitude != null) {
                      _latitude = details.latitude;
                      _longitude = details.longitude;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TextField(
                      controller: _cityController,
                      label: 'Kota',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TextField(
                      controller: _postalController,
                      label: 'Kode pos',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TextField(
                      controller: _provinceController,
                      label: 'Provinsi',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TextField(
                      controller: _districtController,
                      label: 'Kecamatan',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _isPrimary,
                onChanged: (value) => setState(() => _isPrimary = value),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Jadikan alamat utama',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 12),
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
                    : const Text('Simpan Alamat'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _TextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        // Match Capacitor + auth screens: input radius 14.
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
