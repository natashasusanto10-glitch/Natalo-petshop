import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'dart:async';

import '../models/member_profile.dart';
import '../services/member_service.dart';
import '../services/places_service.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/wilayah_picker.dart';
import '../state/member_store.dart';
import '../widgets/app_ui.dart';
import '../widgets/glass_surface.dart';

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

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Alamat'),
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
    return Scaffold(
      backgroundColor: Colors.transparent,
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
                  color: const Color(0xFFEAF5FF),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: _brandBlue,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Login member diperlukan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF17202A),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Masuk untuk menyimpan dan mengedit alamat pengiriman.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B7280),
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
    return GlassSurface(
      radius: 26,
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          const AppLottieAsset(
            asset: 'assets/lottie/empty_box.json',
            size: 112,
          ),
          const SizedBox(height: 8),
          const Text(
            'Belum ada alamat tersimpan',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF17202A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tambahkan alamat member agar checkout pengiriman bisa lebih cepat.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Tambah Alamat'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
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
    return const GlassSurface(
      radius: 24,
      padding: EdgeInsets.all(18),
      child: Row(
        children: [
          SoftIconTile(
            icon: Icons.location_on_outlined,
            color: _brandBlue,
            size: 44,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tambah, edit, atau jadikan alamat utama untuk checkout lebih cepat.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w800,
                height: 1.35,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB)),
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
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              address.address,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              address.recipient,
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (address.areaLabel != null && address.areaLabel!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                address.areaLabel!,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
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
                  color: const Color(0xFFEAF5FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Pinpoint: ${address.pinpointAddress}',
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Divider(color: Color(0xFFE5E7EB), height: 1),
            const SizedBox(height: 12),
            // ── Action buttons: Edit (outline gray) + Hapus (outline red) — right aligned ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _AddressActionButton(
                  label: 'Edit',
                  color: const Color(0xFF334155),
                  borderColor: const Color(0xFFE5E7EB),
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
    late final Color bg;
    late final Color border;
    late final Color text;
    switch (variant) {
      case _TagVariant.neutral:
        bg = Colors.white;
        border = const Color(0xFFE5E7EB);
        text = const Color(0xFF334155);
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
            color: Colors.white,
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

  /// Open Google Places search sheet — user search alamat, pick suggestion,
  /// auto-fill semua field (address/postal/lat/lng/province/city/district).
  Future<void> _openPlacesSearch() async {
    final result = await showModalBottomSheet<PlaceDetails>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PlacesSearchSheet(),
    );
    if (result == null || !mounted) return;
    setState(() {
      _addressController.text = result.formattedAddress;
      if (result.postalCode != null && result.postalCode!.isNotEmpty) {
        _postalController.text = result.postalCode!;
      }
      if (result.city != null && result.city!.isNotEmpty) {
        _cityController.text = result.city!;
      }
      if (result.province != null && result.province!.isNotEmpty) {
        _provinceController.text = result.province!;
      }
      if (result.district != null && result.district!.isNotEmpty) {
        _districtController.text = result.district!;
      }
    });
  }

  /// "Pakai Lokasi Saya" — request GPS permission, get coordinates, lalu
  /// reverse-geocode via Google Places (server proxy) → auto-fill alamat.
  ///
  /// Flow:
  /// 1. Cek permission location → request kalau belum granted
  /// 2. Cek service GPS aktif → kalau tidak, kasih hint user untuk on-kan
  /// 3. Get lat/lng via geolocator (LocationAccuracy.high)
  /// 4. Server proxy ke Google Places reverse-geocode (key di server)
  /// 5. Auto-fill controllers + show success snackbar
  bool _fetchingGps = false;
  Future<void> _useMyLocation() async {
    setState(() => _fetchingGps = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 1. Check service
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content:
                Text('GPS tidak aktif. Aktifkan lokasi di pengaturan HP dulu.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      // 2. Check / request permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Izin lokasi ditolak. Buka pengaturan app untuk izinkan akses lokasi.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      // 3. Get coordinates
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      // 4. Server reverse-geocode
      final details = await placesService.reverseGeocode(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      if (details == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Tidak bisa convert koordinat ke alamat. Coba cari manual.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
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
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Alamat diisi dari lokasi saat ini.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal ambil lokasi: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _fetchingGps = false);
    }
  }

  /// Open wilayah cascade picker (Provinsi → Kota → Kec → Desa).
  /// Auto-fill province/city/district controllers dari selection.
  Future<void> _openWilayahPicker() async {
    final selection = await showWilayahPicker(context);
    if (selection == null || !mounted) return;
    setState(() {
      _provinceController.text = selection.province.name;
      _cityController.text = selection.regency.name;
      _districtController.text = selection.district.name;
    });
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
        latitude: previous?.latitude,
        longitude: previous?.longitude,
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
                style: const TextStyle(
                  color: Color(0xFF17202A),
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
              // Quick actions — 3 cara isi alamat:
              // (1) GPS — auto-detect lokasi current → reverse-geocode
              // (2) Cari di Google Maps → autocomplete suggestion
              // (3) Pilih wilayah cascade (Provinsi → Desa) — manual
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          (_saving || _fetchingGps) ? null : _useMyLocation,
                      icon: _fetchingGps
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded, size: 16),
                      label: const Text('GPS'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF16A34A),
                        side: const BorderSide(color: Color(0xFF86EFAC)),
                        minimumSize: const Size.fromHeight(44),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _openPlacesSearch,
                      icon: const Icon(Icons.search_rounded, size: 16),
                      label: const Text('Cari'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0B7FEA),
                        side: const BorderSide(color: Color(0xFFBFDBFE)),
                        minimumSize: const Size.fromHeight(44),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _openWilayahPicker,
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: const Text('Wilayah'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0B7FEA),
                        side: const BorderSide(color: Color(0xFFBFDBFE)),
                        minimumSize: const Size.fromHeight(44),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _TextField(
                controller: _addressController,
                label: 'Nama jalan / alamat',
                maxLines: 2,
                validator: (value) => (value?.trim().length ?? 0) < 5
                    ? 'Alamat minimal 5 karakter'
                    : null,
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
  final int maxLines;
  final String? Function(String?)? validator;

  const _TextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        // Match Capacitor + auth screens: input radius 14.
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// Bottom sheet untuk search alamat via Google Places API.
/// User ketik query → server proxy ke Google → return suggestions.
/// Tap suggestion → fetch details (lat/lng/postal) → pop dengan PlaceDetails.
class _PlacesSearchSheet extends StatefulWidget {
  const _PlacesSearchSheet();

  @override
  State<_PlacesSearchSheet> createState() => _PlacesSearchSheetState();
}

class _PlacesSearchSheetState extends State<_PlacesSearchSheet> {
  final _queryCtrl = TextEditingController();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  bool _fetchingDetails = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    setState(() => _searching = true);
    final results = await placesService.autocomplete(query: query);
    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _searching = false;
    });
  }

  Future<void> _pickSuggestion(PlaceSuggestion suggestion) async {
    setState(() => _fetchingDetails = true);
    final details = await placesService.details(placeId: suggestion.placeId);
    if (!mounted) return;
    setState(() => _fetchingDetails = false);
    if (details == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal ambil detail alamat. Coba lagi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.pop(context, details);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Cari Alamat',
                      style: TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _queryCtrl,
                autofocus: true,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Mis. Jl. MT. Haryono No. 103',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_fetchingDetails) const LinearProgressIndicator(),
              Expanded(
                child: _suggestions.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.place_outlined,
                                color: Color(0xFF9CA3AF),
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _queryCtrl.text.trim().length < 3
                                    ? 'Ketik minimal 3 huruf untuk cari alamat'
                                    : 'Tidak ada hasil. Coba kata kunci lain.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w700,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final s = _suggestions[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.place_outlined,
                              color: Color(0xFF0B7FEA),
                            ),
                            title: Text(
                              s.mainText ?? s.description,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: s.secondaryText != null
                                ? Text(
                                    s.secondaryText!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7280),
                                    ),
                                  )
                                : null,
                            onTap: () => _pickSuggestion(s),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
