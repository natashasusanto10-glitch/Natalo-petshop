import 'package:flutter/material.dart';

import '../models/pet_care_record.dart';
import '../services/pet_service.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/formatters.dart';
import 'app_product_image.dart';

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
  bool _weightMatched = false;
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
      final weightKg = widget.weightKg;
      var products = await fetch(
        category: category,
        species: species,
        weightKg: weightKg,
      );
      var weightMatched = weightKg != null && products.isNotEmpty;
      if (products.isEmpty && weightKg != null) {
        // Fallback: no product matched the entered weight — fall back to
        // the full unfiltered category list so we never show an empty
        // list, only the manual-entry link.
        products = await fetch(
          category: category,
          species: species,
          weightKg: null,
        );
        weightMatched = false;
      }
      if (!mounted) return;
      setState(() {
        _products = products;
        _weightMatched = weightMatched;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _products = [];
        _weightMatched = false;
        _loading = false;
      });
    }
  }

  void _selectProduct(CareProduct product) {
    // Produk habis tidak boleh terpilih — mencatat perawatan dengan produk
    // yang tak bisa dibeli menyesatkan, dan kontrol yang tampak bisa ditekan
    // tapi tak melakukan apa-apa melanggar aturan disabled-state.
    if (!product.inStock) return;
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
    final cs = Theme.of(context).colorScheme;
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
        else if (!_manual)
          // Satu kartu berpembatas, bukan kotak-kotak mengambang: daftar
          // produk + jalur manual dibaca sebagai satu unit pilihan.
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < _products.length; i++) ...[
                  if (i > 0) _hairline(cs),
                  _ProductTile(
                    product: _products[i],
                    selected: _selectedId == _products[i].id,
                    showBadge: i == 0 && (widget._isDebug || _weightMatched),
                    onTap: () => _selectProduct(_products[i]),
                  ),
                ],
                if (_products.isNotEmpty) _hairline(cs),
                _ManualRow(onTap: _toggleManual),
              ],
            ),
          )
        else
          _ManualEntry(
            brandCtrl: _brandCtrl,
            dosageCtrl: _dosageCtrl,
            onChanged: _emitManual,
          ),
        // Kartu dosis hanya untuk info yang BELUM tampil di tile terpilih —
        // anjuran produk katalog sudah menempel di barisnya sendiri, jadi
        // tidak diulang di sini (dulu blok biru selalu tampil & mendominasi).
        if (_manual || selected?.instruction == null) ...[
          const SizedBox(height: 12),
          _DosageCard(
            manual: _manual,
            dosageNote: _manual ? _dosageCtrl.text.trim() : null,
          ),
        ],
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
    final habis = !product.inStock;
    final instruction = product.instruction;
    // Semantics eksplisit: tile ini radio kustom, tanpa ini pembaca layar
    // tak pernah mengumumkan status terpilih/nonaktif.
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      enabled: !habis,
      button: !habis,
      label: habis ? '${product.name}, stok habis' : product.name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: habis ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            // Hanya warna latar yang berubah saat dipilih — padding/ukuran
            // tetap supaya tak ada geseran layout saat ditekan.
            color: selected
                ? (isDark
                    ? _brandBlue.withValues(alpha: 0.18)
                    : NataloColors.primarySoft)
                : Colors.transparent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: habis ? 0.4 : 1,
                  child: AppProductImage(
                    imageUrl: product.imageUrl,
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Text(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: NataloWeight.strong,
                                color: habis ? cs.onSurfaceVariant : cs.onSurface,
                              ),
                            ),
                          ),
                          if (showBadge && !habis) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? _brandBlue.withValues(alpha: 0.24)
                                    : _brandBlue,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Paling sesuai',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: NataloWeight.strong,
                                  color: isDark ? _brandBlue : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        habis
                            ? 'Stok habis'
                            : formatRupiah(product.effectivePrice),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              habis ? NataloWeight.body : NataloWeight.strong,
                          color: habis ? cs.onSurfaceVariant : cs.onSurface,
                        ),
                      ),
                      // Anjuran dosis menempel di produk terpilih — jawaban
                      // yang dicari user ada di tempat keputusannya dibuat.
                      if (selected && instruction != null && instruction.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          instruction,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: NataloWeight.strong,
                            color: isDark ? cs.onSurface : _brandBlue,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 20,
                    color: selected
                        ? _brandBlue
                        : (habis ? cs.outlineVariant : cs.onSurfaceVariant),
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

/// Pembatas tipis antar baris di dalam kartu pilihan.
Widget _hairline(ColorScheme cs) =>
    Divider(height: 0.5, thickness: 0.5, color: cs.outlineVariant);

/// Baris terakhir kartu: jalur ketik-manual. Baris penuh (bukan teks
/// bergaris-bawah gaya web) supaya target sentuhnya lega.
class _ManualRow extends StatelessWidget {
  final VoidCallback onTap;

  const _ManualRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Beli di luar Natalo? Ketik manual',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: NataloWeight.strong,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: cs.onSurfaceVariant),
              ],
            ),
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
        // Label terlihat, bukan placeholder-only: begitu user mulai mengetik
        // placeholder hilang dan konteks kolomnya ikut hilang.
        _FieldLabel('Nama brand', cs: cs),
        const SizedBox(height: 6),
        TextField(
          controller: brandCtrl,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            filled: true,
            fillColor: cs.surface,
            hintText: 'Mis. Drontal',
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
        const SizedBox(height: 12),
        _FieldLabel('Aturan pakai (opsional)', cs: cs),
        const SizedBox(height: 6),
        TextField(
          controller: dosageCtrl,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            filled: true,
            fillColor: cs.surface,
            hintText: 'Mis. 1 tablet per 10 kg',
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

/// Label kolom kecil, seragam dengan `_Label` di form perawatan.
class _FieldLabel extends StatelessWidget {
  final String text;
  final ColorScheme cs;

  const _FieldLabel(this.text, {required this.cs});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: NataloWeight.body,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}

/// Catatan dosis — hanya tampil saat anjuran BELUM terlihat di baris produk
/// terpilih (mode manual, atau produk tanpa data dosis).
class _DosageCard extends StatelessWidget {
  final bool manual;
  final String? dosageNote;

  const _DosageCard({
    required this.manual,
    required this.dosageNote,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final note = dosageNote;
    final text = manual && note != null && note.isNotEmpty
        ? 'Dicatat sendiri: $note'
        : 'Dosis obat cacing/kutu dihitung per kg berat badan — cek kemasan atau tanya dokter hewan.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? _brandBlue.withValues(alpha: 0.12)
            : NataloColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: isDark ? cs.onSurface : _brandBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: NataloWeight.body,
                color: isDark ? cs.onSurface : _brandBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
