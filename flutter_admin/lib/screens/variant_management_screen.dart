import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';

/// Manage varian satu produk: aktivasi, atribut, options, harga & stok
/// per kombinasi.
///
/// Pattern:
///   1. Load current state via GET /api/admin/products/:id/variants
///   2. Toggle "Punya Varian?" — kalau OFF, simpan kosongkan attribut+variant
///   3. Add up to 3 attribute (Ukuran, Warna, Berat — common di petshop)
///   4. Auto-generate kombinasi (cartesian product) saat options berubah
///   5. Per-kombinasi: edit harga, stok, SKU opsional, aktif/non
///   6. Save → PUT /api/admin/products/:id/variants (full-replace atomik)
///
/// Backend constraint:
///   - Max 3 attribute, 30 options per attribute, 200 variant total
///   - Variant yang punya order existing → backend auto-soft-delete
///     (kita tidak perlu khawatirkan dari sisi UI, full-replace aman)
class VariantManagementScreen extends StatefulWidget {
  final String productId;
  final String productName;

  const VariantManagementScreen({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  State<VariantManagementScreen> createState() =>
      _VariantManagementScreenState();
}

class _VariantManagementScreenState extends State<VariantManagementScreen> {
  static const int _maxAttributes = 3;
  static const int _maxOptionsPerAttribute = 30;
  static const int _maxVariants = 200;

  bool _loading = true;
  String? _error;
  bool _hasVariants = false;
  bool _saving = false;

  final List<_AttributeEdit> _attributes = [];
  // Map dari combinationKey ("attr0Opt:attr1Opt") → variant data.
  // Pakai map (bukan list) supaya saat options dirubah, variant yang
  // masih relevan tetap preserve data, yang sudah tidak ada di-discard.
  final Map<String, _VariantEdit> _variantsByKey = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await adminApi.getJson(
        '/api/admin/products/${Uri.encodeComponent(widget.productId)}/variants',
      );
      if (data is Map<String, dynamic>) {
        _hasVariants = data['hasVariants'] == true;
        _attributes.clear();
        _variantsByKey.clear();
        final attrs = data['attributes'] as List?;
        final variants = data['variants'] as List?;

        if (attrs != null) {
          for (final attr in attrs.whereType<Map<String, dynamic>>()) {
            final options = ((attr['options'] as List?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map((o) => _OptionEdit(
                      id: o['id']?.toString(),
                      value: (o['value'] ?? '').toString(),
                      position:
                          (o['position'] is num) ? (o['position'] as num).toInt() : 0,
                    ))
                .toList();
            _attributes.add(_AttributeEdit(
              name: (attr['name'] ?? '').toString(),
              position:
                  (attr['position'] is num) ? (attr['position'] as num).toInt() : 0,
              options: options,
            ));
          }
        }

        // Map optionId → "attrPosition:value" untuk derive combinationKey
        // dari variant.options[].optionId.
        final optionIdToRef = <String, String>{};
        for (final attr in _attributes) {
          for (final opt in attr.options) {
            if (opt.id != null) {
              optionIdToRef[opt.id!] = '${attr.position}:${opt.value}';
            }
          }
        }

        if (variants != null) {
          for (final v in variants.whereType<Map<String, dynamic>>()) {
            final optionRefs = ((v['options'] as List?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map((o) => optionIdToRef[o['optionId']?.toString()])
                .whereType<String>()
                .toList();
            if (optionRefs.isEmpty) continue;
            optionRefs.sort();
            final key = optionRefs.join('|');
            _variantsByKey[key] = _VariantEdit(
              optionRefs: optionRefs,
              price: (v['price'] is num) ? (v['price'] as num).toInt() : 0,
              stock: (v['stock'] is num) ? (v['stock'] as num).toInt() : 0,
              weightGram: (v['weightGram'] is num)
                  ? (v['weightGram'] as num).toInt()
                  : 0,
              sku: v['sku']?.toString() ?? '',
              isActive: v['isActive'] != false,
            );
          }
        }
        _regenerateCombinations();
      }
    } on AdminApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Tidak bisa load varian. Cek koneksi.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Setiap kali options diubah, regenerate cartesian product variants.
  /// Variant yang masih relevan (combinationKey sama) tetap pakai data
  /// existing — supaya harga/stok yang admin udah set tidak hilang.
  void _regenerateCombinations() {
    if (!_hasVariants || _attributes.isEmpty) {
      _variantsByKey.removeWhere((_, _) => true);
      return;
    }
    // Build cartesian product dari options aktif (yang punya value non-empty).
    final lists = _attributes
        .where((a) => a.name.trim().isNotEmpty)
        .map((a) =>
            a.options.where((o) => o.value.trim().isNotEmpty).toList())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lists.isEmpty) {
      _variantsByKey.removeWhere((_, _) => true);
      return;
    }

    final newKeys = <String>{};
    void recurse(int depth, List<String> acc) {
      if (depth == lists.length) {
        final sorted = [...acc]..sort();
        newKeys.add(sorted.join('|'));
        return;
      }
      final attrPos = _attributes
          .where((a) => a.name.trim().isNotEmpty)
          .where((a) => a.options.any((o) => o.value.trim().isNotEmpty))
          .toList()[depth]
          .position;
      for (final opt in lists[depth]) {
        recurse(depth + 1, [...acc, '$attrPos:${opt.value.trim()}']);
      }
    }

    recurse(0, []);
    // Drop variants yang sudah tidak relevan (option combination tidak ada).
    _variantsByKey.removeWhere((k, _) => !newKeys.contains(k));
    // Add variants baru dgn default value.
    for (final k in newKeys) {
      _variantsByKey.putIfAbsent(
        k,
        () => _VariantEdit(
          optionRefs: k.split('|'),
          price: 0,
          stock: 0,
          weightGram: 0,
          sku: '',
          isActive: true,
        ),
      );
    }
  }

  void _addAttribute() {
    if (_attributes.length >= _maxAttributes) return;
    setState(() {
      _attributes.add(_AttributeEdit(
        name: '',
        position: _attributes.length,
        options: [
          _OptionEdit(value: '', position: 0),
        ],
      ));
    });
  }

  void _removeAttribute(int index) {
    setState(() {
      _attributes.removeAt(index);
      // Reposition.
      for (var i = 0; i < _attributes.length; i++) {
        _attributes[i] = _attributes[i].copyWith(position: i);
      }
      _regenerateCombinations();
    });
  }

  void _addOption(int attrIndex) {
    final attr = _attributes[attrIndex];
    if (attr.options.length >= _maxOptionsPerAttribute) return;
    setState(() {
      attr.options.add(_OptionEdit(value: '', position: attr.options.length));
    });
  }

  void _removeOption(int attrIndex, int optionIndex) {
    setState(() {
      _attributes[attrIndex].options.removeAt(optionIndex);
      for (var i = 0; i < _attributes[attrIndex].options.length; i++) {
        _attributes[attrIndex].options[i] =
            _attributes[attrIndex].options[i].copyWith(position: i);
      }
      _regenerateCombinations();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    // Validasi sederhana sebelum kirim — backend juga validate, tapi
    // error early UX lebih nyaman.
    if (_hasVariants) {
      if (_attributes.isEmpty) {
        _showError('Tambah minimal 1 atribut atau matikan varian.');
        return;
      }
      for (final attr in _attributes) {
        if (attr.name.trim().isEmpty) {
          _showError('Nama atribut tidak boleh kosong.');
          return;
        }
        if (attr.options.where((o) => o.value.trim().isNotEmpty).isEmpty) {
          _showError('Atribut "${attr.name}" perlu minimal 1 opsi.');
          return;
        }
      }
      if (_variantsByKey.isEmpty) {
        _showError('Tidak ada kombinasi varian.');
        return;
      }
      if (_variantsByKey.length > _maxVariants) {
        _showError(
            'Maksimal $_maxVariants varian. Sekarang ${_variantsByKey.length}.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'hasVariants': _hasVariants,
        'attributes': _hasVariants
            ? _attributes
                .where((a) => a.name.trim().isNotEmpty)
                .map((a) => {
                      'name': a.name.trim(),
                      'position': a.position,
                      'options': a.options
                          .where((o) => o.value.trim().isNotEmpty)
                          .map((o) => {
                                'value': o.value.trim(),
                                'position': o.position,
                              })
                          .toList(),
                    })
                .toList()
            : [],
        'variants': _hasVariants
            ? _variantsByKey.values
                .map((v) => {
                      'optionRefs': v.optionRefs,
                      'price': v.price,
                      'stock': v.stock,
                      'weightGram': v.weightGram,
                      if (v.sku.trim().isNotEmpty) 'sku': v.sku.trim(),
                      'isActive': v.isActive,
                    })
                .toList()
            : [],
      };

      await adminApi.putJson(
        '/api/admin/products/${Uri.encodeComponent(widget.productId)}/variants',
        body: payload,
        timeout: const Duration(seconds: 20),
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Varian tersimpan ✓'),
          backgroundColor: AdminColors.success,
        ),
      );
      Navigator.of(context).pop(true);
    } on AdminApiException catch (e) {
      _showError('Gagal: ${e.message}');
    } catch (_) {
      _showError('Gagal simpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Varian'),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: Text(
              'Simpan',
              style: TextStyle(
                color: _saving || _loading
                    ? AdminColors.textMuted
                    : AdminColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AdminColors.primary))
          : _error != null
              ? _ErrorBody(message: _error!, onRetry: _load)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AdminColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _hasVariants,
                activeThumbColor: AdminColors.primary,
                title: const Text(
                  'Produk punya varian',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  _hasVariants
                      ? 'Harga & stok di-set per kombinasi'
                      : 'Pakai harga & stok di form produk',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textSecondary,
                  ),
                ),
                onChanged: (v) {
                  setState(() {
                    _hasVariants = v;
                    if (v && _attributes.isEmpty) {
                      _addAttribute();
                    }
                    _regenerateCombinations();
                  });
                },
              ),
            ],
          ),
        ),
        if (_hasVariants) ...[
          const SizedBox(height: 12),
          _sectionTitle('Atribut'),
          for (var i = 0; i < _attributes.length; i++)
            _AttributeCard(
              key: ValueKey('attr-$i'),
              attribute: _attributes[i],
              onNameChanged: (val) {
                setState(() => _attributes[i] = _attributes[i].copyWith(name: val));
              },
              onAddOption: () => _addOption(i),
              onRemoveOption: (oi) => _removeOption(i, oi),
              onOptionChanged: (oi, val) {
                setState(() {
                  _attributes[i].options[oi] =
                      _attributes[i].options[oi].copyWith(value: val);
                  _regenerateCombinations();
                });
              },
              onRemoveAttribute: _attributes.length > 1
                  ? () => _removeAttribute(i)
                  : null,
            ),
          if (_attributes.length < _maxAttributes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Tambah atribut'),
                onPressed: _addAttribute,
              ),
            ),
          const SizedBox(height: 16),
          _sectionTitle(
            'Kombinasi (${_variantsByKey.length})',
            hint: _variantsByKey.isEmpty
                ? null
                : 'Tap kombinasi untuk edit harga/stok',
          ),
          for (final entry in _variantsByKey.entries)
            _VariantRow(
              key: ValueKey('variant-${entry.key}'),
              variantKey: entry.key,
              variant: entry.value,
              onUpdated: (updated) {
                setState(() => _variantsByKey[entry.key] = updated);
              },
            ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _sectionTitle(String text, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AdminColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint,
              style: const TextStyle(
                fontSize: 11,
                color: AdminColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttributeEdit {
  final String name;
  final int position;
  final List<_OptionEdit> options;

  _AttributeEdit({
    required this.name,
    required this.position,
    required this.options,
  });

  _AttributeEdit copyWith({String? name, int? position}) {
    return _AttributeEdit(
      name: name ?? this.name,
      position: position ?? this.position,
      options: options,
    );
  }
}

class _OptionEdit {
  final String? id;
  final String value;
  final int position;

  _OptionEdit({this.id, required this.value, required this.position});

  _OptionEdit copyWith({String? value, int? position}) {
    return _OptionEdit(
      id: id,
      value: value ?? this.value,
      position: position ?? this.position,
    );
  }
}

class _VariantEdit {
  final List<String> optionRefs;
  final int price;
  final int stock;
  final int weightGram;
  final String sku;
  final bool isActive;

  _VariantEdit({
    required this.optionRefs,
    required this.price,
    required this.stock,
    required this.weightGram,
    required this.sku,
    required this.isActive,
  });

  _VariantEdit copyWith({
    int? price,
    int? stock,
    int? weightGram,
    String? sku,
    bool? isActive,
  }) {
    return _VariantEdit(
      optionRefs: optionRefs,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      weightGram: weightGram ?? this.weightGram,
      sku: sku ?? this.sku,
      isActive: isActive ?? this.isActive,
    );
  }

  String get displayLabel =>
      optionRefs.map((r) => r.split(':').last).join(' • ');
}

class _AttributeCard extends StatefulWidget {
  final _AttributeEdit attribute;
  final ValueChanged<String> onNameChanged;
  final void Function() onAddOption;
  final ValueChanged<int> onRemoveOption;
  final void Function(int index, String value) onOptionChanged;
  final VoidCallback? onRemoveAttribute;

  const _AttributeCard({
    super.key,
    required this.attribute,
    required this.onNameChanged,
    required this.onAddOption,
    required this.onRemoveOption,
    required this.onOptionChanged,
    required this.onRemoveAttribute,
  });

  @override
  State<_AttributeCard> createState() => _AttributeCardState();
}

class _AttributeCardState extends State<_AttributeCard> {
  late TextEditingController _nameController;
  final List<TextEditingController> _optionControllers = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.attribute.name);
    for (final opt in widget.attribute.options) {
      _optionControllers.add(TextEditingController(text: opt.value));
    }
  }

  @override
  void didUpdateWidget(covariant _AttributeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controllers kalau options bertambah/berkurang dari luar.
    while (_optionControllers.length < widget.attribute.options.length) {
      _optionControllers.add(TextEditingController(
        text: widget.attribute.options[_optionControllers.length].value,
      ));
    }
    while (_optionControllers.length > widget.attribute.options.length) {
      _optionControllers.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  onChanged: widget.onNameChanged,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama atribut',
                    hintText: 'Misal: Ukuran, Warna, Berat',
                    isDense: true,
                  ),
                ),
              ),
              if (widget.onRemoveAttribute != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AdminColors.danger),
                  tooltip: 'Hapus atribut',
                  onPressed: widget.onRemoveAttribute,
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Opsi',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AdminColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < widget.attribute.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _optionControllers[i],
                      onChanged: (val) => widget.onOptionChanged(i, val),
                      decoration: InputDecoration(
                        hintText: 'Opsi ${i + 1}',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  if (widget.attribute.options.length > 1)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => widget.onRemoveOption(i),
                    ),
                ],
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Tambah opsi'),
            onPressed: widget.onAddOption,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantRow extends StatefulWidget {
  final String variantKey;
  final _VariantEdit variant;
  final ValueChanged<_VariantEdit> onUpdated;

  const _VariantRow({
    super.key,
    required this.variantKey,
    required this.variant,
    required this.onUpdated,
  });

  @override
  State<_VariantRow> createState() => _VariantRowState();
}

class _VariantRowState extends State<_VariantRow> {
  late TextEditingController _priceController;
  late TextEditingController _stockController;
  late TextEditingController _skuController;

  @override
  void initState() {
    super.initState();
    _priceController =
        TextEditingController(text: widget.variant.price.toString());
    _stockController =
        TextEditingController(text: widget.variant.stock.toString());
    _skuController = TextEditingController(text: widget.variant.sku);
  }

  @override
  void dispose() {
    _priceController.dispose();
    _stockController.dispose();
    _skuController.dispose();
    super.dispose();
  }

  void _commit({int? price, int? stock, String? sku, bool? isActive}) {
    widget.onUpdated(widget.variant.copyWith(
      price: price,
      stock: stock,
      sku: sku,
      isActive: isActive,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.variant.isActive
              ? AdminColors.divider
              : AdminColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.variant.displayLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: widget.variant.isActive
                        ? AdminColors.textPrimary
                        : AdminColors.textMuted,
                  ),
                ),
              ),
              Switch(
                value: widget.variant.isActive,
                activeThumbColor: AdminColors.primary,
                onChanged: (v) => _commit(isActive: v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) =>
                      _commit(price: int.tryParse(v.trim()) ?? 0),
                  decoration: const InputDecoration(
                    labelText: 'Harga',
                    prefixText: 'Rp ',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _stockController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) =>
                      _commit(stock: int.tryParse(v.trim()) ?? 0),
                  decoration: const InputDecoration(
                    labelText: 'Stok',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _skuController,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_\-]')),
            ],
            onChanged: (v) => _commit(sku: v),
            decoration: const InputDecoration(
              labelText: 'SKU (opsional)',
              hintText: 'PRD-001-M',
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AdminColors.textMuted),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AdminColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}
