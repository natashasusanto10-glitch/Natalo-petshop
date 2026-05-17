import 'package:flutter/material.dart';

import '../services/wilayah_service.dart';

/// Hasil dari WilayahPicker — semua 4 level admin yang dipilih user.
class WilayahSelection {
  final WilayahRegion province;
  final WilayahRegion regency;
  final WilayahRegion district;
  final WilayahRegion? village;

  const WilayahSelection({
    required this.province,
    required this.regency,
    required this.district,
    this.village,
  });

  String get fullName {
    final parts = [
      village?.name,
      district.name,
      regency.name,
      province.name,
    ].whereType<String>().where((s) => s.isNotEmpty).toList();
    return parts.join(', ');
  }
}

/// Cascading picker untuk wilayah Indonesia (provinsi → kab/kota →
/// kecamatan → desa/kelurahan). Match endpoint PWA /api/wilayah/*.
///
/// Show as bottom sheet — 4-step wizard. User pilih per level, next level
/// auto-fetch. Tap "Selesai" di step 3 (desa optional) atau step 4 (desa
/// dipilih) → return WilayahSelection ke caller.
///
/// Usage:
/// ```dart
/// final selection = await showWilayahPicker(context);
/// if (selection != null) {
///   _provinceController.text = selection.province.name;
///   _cityController.text = selection.regency.name;
///   _districtController.text = selection.district.name;
/// }
/// ```
Future<WilayahSelection?> showWilayahPicker(BuildContext context) {
  return showModalBottomSheet<WilayahSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _WilayahPickerSheet(),
  );
}

class _WilayahPickerSheet extends StatefulWidget {
  const _WilayahPickerSheet();

  @override
  State<_WilayahPickerSheet> createState() => _WilayahPickerSheetState();
}

enum _Step { province, regency, district, village }

class _WilayahPickerSheetState extends State<_WilayahPickerSheet> {
  _Step _step = _Step.province;
  WilayahRegion? _selectedProvince;
  WilayahRegion? _selectedRegency;
  WilayahRegion? _selectedDistrict;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  late Future<List<WilayahRegion>> _currentList;

  @override
  void initState() {
    super.initState();
    _currentList = wilayahService.provinces();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSelect(WilayahRegion region) {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      switch (_step) {
        case _Step.province:
          _selectedProvince = region;
          _step = _Step.regency;
          _currentList = wilayahService.regencies(region.id);
          break;
        case _Step.regency:
          _selectedRegency = region;
          _step = _Step.district;
          _currentList = wilayahService.districts(region.id);
          break;
        case _Step.district:
          _selectedDistrict = region;
          _step = _Step.village;
          _currentList = wilayahService.villages(region.id);
          break;
        case _Step.village:
          Navigator.pop(
            context,
            WilayahSelection(
              province: _selectedProvince!,
              regency: _selectedRegency!,
              district: _selectedDistrict!,
              village: region,
            ),
          );
          break;
      }
    });
  }

  void _back() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      switch (_step) {
        case _Step.province:
          Navigator.pop(context);
          return;
        case _Step.regency:
          _step = _Step.province;
          _selectedProvince = null;
          _currentList = wilayahService.provinces();
          break;
        case _Step.district:
          _step = _Step.regency;
          _selectedRegency = null;
          _currentList =
              wilayahService.regencies(_selectedProvince!.id);
          break;
        case _Step.village:
          _step = _Step.district;
          _selectedDistrict = null;
          _currentList =
              wilayahService.districts(_selectedRegency!.id);
          break;
      }
    });
  }

  /// Step desa boleh di-skip kalau user tidak perlu spesifik level village.
  void _skipVillage() {
    Navigator.pop(
      context,
      WilayahSelection(
        province: _selectedProvince!,
        regency: _selectedRegency!,
        district: _selectedDistrict!,
      ),
    );
  }

  String get _title {
    switch (_step) {
      case _Step.province:
        return 'Pilih Provinsi';
      case _Step.regency:
        return 'Pilih Kota / Kabupaten';
      case _Step.district:
        return 'Pilih Kecamatan';
      case _Step.village:
        return 'Pilih Desa / Kelurahan';
    }
  }

  int get _stepNumber {
    switch (_step) {
      case _Step.province:
        return 1;
      case _Step.regency:
        return 2;
      case _Step.district:
        return 3;
      case _Step.village:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
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
            bottom: MediaQuery.of(context).viewInsets.bottom + 8,
          ),
          child: Column(
            children: [
              // Drag handle
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
              // Header: back + title + step indicator
              Row(
                children: [
                  IconButton(
                    onPressed: _back,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _title,
                          style: const TextStyle(
                            color: Color(0xFF111111),
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Langkah $_stepNumber dari 4',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_step == _Step.village)
                    TextButton(
                      onPressed: _skipVillage,
                      child: const Text(
                        'Lewati',
                        style: TextStyle(
                          color: Color(0xFF0B7FEA),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              // Breadcrumb selected so far
              if (_selectedProvince != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          _selectedProvince?.name,
                          _selectedRegency?.name,
                          _selectedDistrict?.name,
                        ].whereType<String>().join(' › '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              // Search field
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Cari...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // List
              Expanded(
                child: FutureBuilder<List<WilayahRegion>>(
                  future: _currentList,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final all = snapshot.data ?? const [];
                    if (all.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off_rounded,
                                  color: Color(0xFF9CA3AF), size: 48),
                              SizedBox(height: 12),
                              Text(
                                'Data wilayah tidak tersedia',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final filtered = _searchQuery.isEmpty
                        ? all
                        : all
                            .where((r) => r.name
                                .toLowerCase()
                                .contains(_searchQuery.toLowerCase()))
                            .toList();
                    if (filtered.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Tidak ditemukan: "$_searchQuery"',
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      itemBuilder: (context, index) {
                        final region = filtered[index];
                        return ListTile(
                          onTap: () => _onSelect(region),
                          title: Text(
                            region.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF9CA3AF),
                          ),
                          dense: true,
                        );
                      },
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
