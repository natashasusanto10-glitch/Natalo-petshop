import 'package:flutter/material.dart';

import '../models/pet_care_record.dart';
import '../services/pet_service.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';

const _brandBlue = NataloColors.primary;

/// Hasil pilihan pengguna di [CareProductPicker]: baik produk katalog
/// (`productId`) maupun input manual (`brandText`/`dosageNote`).
class CareSelection {
  final String? productId;
  final String? brandText;
  final String? dosageNote;
  final String? instructionShown;

  const CareSelection({
    this.productId,
    this.brandText,
    this.dosageNote,
    this.instructionShown,
  });
}

/// Widget pemilih produk obat cacing/kutu + kartu dosis, dengan fallback
/// mode manual bila produk dibeli di luar Natalo.
typedef CareRecommendationFetcher = Future<List<CareProduct>> Function({
  required PetCareCategory category,
  required String species,
  double? weightKg,
});

class CareProductPicker extends StatefulWidget {
  final PetCareCategory? category;
  final String? species;
  final double? weightKg;
  final void Function(CareSelection selection) onChanged;
  final CareRecommendationFetcher? recommendationFetcher;
  final List<CareProduct>? _debugProducts;

  const CareProductPicker({
    super.key,
    required this.category,
    required this.species,
    required this.weightKg,
    required this.onChanged,
    this.recommendationFetcher,
  }) : _debugProducts = null;

  /// Konstruktor khusus test: menyuntik daftar produk langsung tanpa
  /// memanggil `fetchCareRecommendation`.
  const CareProductPicker.debugWithProducts({
    super.key,
    required List<CareProduct> products,
    required this.onChanged,
  })  : category = null,
        species = null,
        weightKg = null,
        recommendationFetcher = null,
        _debugProducts = products;

  bool get _isDebug => _debugProducts != null;

  @override
  State<CareProductPicker> createState() => _CareProductPickerState();
}

class _CareProductPickerState extends State<CareProductPicker> {
  List<CareProduct> _products = [];
  bool _loading = false;
  String? _selectedId;
  bool _manual = false;
  final _brandCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget._isDebug) {
      _products = widget._debugProducts!;
    } else {
      _fetch();
    }
  }

  @override
  void didUpdateWidget(covariant CareProductPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._isDebug) return;
    if (oldWidget.category != widget.category ||
        oldWidget.species != widget.species ||
        oldWidget.weightKg != widget.weightKg) {
      _fetch();
    }
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _dosageCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final category = widget.category;
    final species = widget.species;
    if (category == null || species == null) return;
    setState(() => _loading = true);
    try {
      final fetch = widget.recommendationFetcher ??
          petService.fetchCareRecommendation;
      final products = await fetch(
        category: category,
        species: species,
        weightKg: widget.weightKg,
      );
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _products = [];
        _loading = false;
      });
    }
  }

  void _selectProduct(CareProduct product) {
    setState(() {
      _selectedId = product.id;
      _manual = false;
    });
    widget.onChanged(CareSelection(
      productId: product.id,
      instructionShown: product.instruction,
    ));
  }

  void _toggleManual() {
    setState(() {
      _manual = true;
      _selectedId = null;
    });
    _emitManual();
  }

  void _emitManual() {
    widget.onChanged(CareSelection(
      brandText: _brandCtrl.text.trim(),
      dosageNote: _dosageCtrl.text.trim(),
    ));
  }

  CareProduct? get _selectedProduct {
    final id = _selectedId;
    if (id == null) return null;
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedProduct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (!_manual && _products.isNotEmpty)
          Column(
            children: [
              for (var i = 0; i < _products.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _ProductTile(
                  product: _products[i],
                  selected: _selectedId == _products[i].id,
                  showBadge:
                      i == 0 && (widget._isDebug || widget.weightKg != null),
                  onTap: () => _selectProduct(_products[i]),
                ),
              ],
            ],
          ),
        if (!_manual) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: _toggleManual,
            child: const Text(
              'Beli di luar Natalo? Ketik manual',
              style: TextStyle(
                fontSize: 12,
                fontWeight: NataloWeight.strong,
                color: _brandBlue,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ] else ...[
          _ManualEntry(
            brandCtrl: _brandCtrl,
            dosageCtrl: _dosageCtrl,
            onChanged: _emitManual,
          ),
        ],
        const SizedBox(height: 12),
        _DosageCard(
          instruction: !_manual ? selected?.instruction : null,
          manual: _manual,
          dosageNote: _manual ? _dosageCtrl.text.trim() : null,
        ),
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  final CareProduct product;
  final bool selected;
  final bool showBadge;
  final VoidCallback onTap;

  const _ProductTile({
    required this.product,
    required this.selected,
    required this.showBadge,
    required this.onTap,
  });

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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            product.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: NataloWeight.strong,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        if (showBadge) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? _brandBlue.withValues(alpha: 0.20)
                                  : NataloColors.primarySoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Paling sesuai',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: NataloWeight.strong,
                                color: _brandBlue,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Rp${product.effectivePrice}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: NataloWeight.body,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 18,
                color: selected ? _brandBlue : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualEntry extends StatelessWidget {
  final TextEditingController brandCtrl;
  final TextEditingController dosageCtrl;
  final VoidCallback onChanged;

  const _ManualEntry({
    required this.brandCtrl,
    required this.dosageCtrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: brandCtrl,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            filled: true,
            fillColor: cs.surface,
            hintText: 'Nama brand',
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
        TextField(
          controller: dosageCtrl,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            filled: true,
            fillColor: cs.surface,
            hintText: 'Aturan pakai (opsional)',
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
      ],
    );
  }
}

class _DosageCard extends StatelessWidget {
  final String? instruction;
  final bool manual;
  final String? dosageNote;

  const _DosageCard({
    required this.instruction,
    required this.manual,
    required this.dosageNote,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String text;
    if (!manual && instruction != null && instruction!.isNotEmpty) {
      text =
          'Anjuran pakai: $instruction. Ikuti aturan kemasan atau tanya dokter hewan.';
    } else if (manual && dosageNote != null && dosageNote!.isNotEmpty) {
      text = 'Dicatat sendiri: $dosageNote';
    } else {
      text =
          'Dosis obat cacing/kutu umumnya dihitung per kg berat badan — cek kemasan atau tanya dokter hewan.';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? _brandBlue.withValues(alpha: 0.12)
            : NataloColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: NataloWeight.body,
          color: isDark ? cs.onSurface : _brandBlue,
        ),
      ),
    );
  }
}
