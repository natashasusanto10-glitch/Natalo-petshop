import 'package:flutter/material.dart';

import '../../models/cart_item.dart';
import '../../models/member_profile.dart';
import '../../models/product.dart';
import '../../models/shipping_rate.dart';
import '../../services/member_service.dart';
import '../../services/shipping_service.dart';
import '../../state/member_store.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../utils/formatters.dart';

typedef ProductAddressLoader = Future<List<MemberAddress>> Function();
typedef ProductShippingRateLoader = Future<ShippingRateResult> Function({
  required MemberAddress address,
  required List<CartItem> items,
});

/// Ringkasan ongkir detail produk yang memakai kalkulasi yang sama dengan
/// checkout. Widget ini sengaja tidak membungkus dirinya dengan card agar bisa
/// ditempatkan dalam quick-info section yang compact.
class ProductShippingSection extends StatefulWidget {
  const ProductShippingSection({
    super.key,
    required this.product,
    this.variant,
    this.variantLabel,
    this.onLoginRequested,
    this.onAddressRequested,
    this.onVariantRequested,
    this.addressLoader,
    this.rateLoader,
  });

  final Product product;
  final ProductVariant? variant;
  final String? variantLabel;
  final Future<void> Function()? onLoginRequested;
  final Future<void> Function()? onAddressRequested;
  final Future<void> Function()? onVariantRequested;

  /// Injection points untuk focused widget tests; production memakai service
  /// yang sama dengan checkout.
  final ProductAddressLoader? addressLoader;
  final ProductShippingRateLoader? rateLoader;

  @override
  State<ProductShippingSection> createState() => ProductShippingSectionState();
}

class ProductShippingSectionState extends State<ProductShippingSection> {
  bool _loading = false;
  String? _error;
  MemberAddress? _address;
  List<ShippingRate> _rates = const [];
  int _requestId = 0;

  CartItem get _item => CartItem(
        product: widget.product,
        variant: widget.variant,
        variantLabel: widget.variantLabel,
        quantity: 1,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProductShippingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldItem = _itemFor(oldWidget);
    final currentItem = _itemFor(widget);
    if (oldWidget.product.id != widget.product.id ||
        oldWidget.product.title != widget.product.title ||
        oldWidget.variant?.id != widget.variant?.id ||
        oldItem.weightGram != currentItem.weightGram ||
        oldItem.unitPrice != currentItem.unitPrice) {
      _load();
    }
  }

  CartItem _itemFor(ProductShippingSection source) => CartItem(
        product: source.product,
        variant: source.variant,
        variantLabel: source.variantLabel,
        quantity: 1,
      );

  @override
  void dispose() {
    _requestId++;
    super.dispose();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    final requestId = ++_requestId;
    if (widget.product.hasVariants && widget.variant == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _address = null;
        _rates = const [];
      });
      return;
    }
    if (!memberStore.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _address = null;
        _rates = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final addresses =
          await (widget.addressLoader ?? memberService.fetchAddresses)();
      if (!mounted || requestId != _requestId) return;
      final address = pickPrimaryAddress(addresses);
      if (address == null) {
        setState(() {
          _loading = false;
          _address = null;
          _rates = const [];
        });
        return;
      }
      if ((address.areaId ?? '').trim().isEmpty) {
        setState(() {
          _loading = false;
          _address = address;
          _rates = const [];
          _error = 'Lengkapi alamat untuk cek ongkir';
        });
        return;
      }

      // Simpan alamat valid sebelum request tarif sehingga kegagalan parsing
      // atau loader tetap bisa dibedakan dari kondisi belum memiliki alamat.
      _address = address;

      final result = await (widget.rateLoader ?? shippingService.fetchRates)(
        address: address,
        items: [_item],
      );
      if (!mounted || requestId != _requestId) return;
      final deliveryRates = result.rates
          .where((rate) => rate.available && !rate.isSelfPickup)
          .toList(growable: false);
      setState(() {
        _loading = false;
        _address = address;
        _rates = result.rates.where((rate) => rate.available).toList();
        _error = result.fromApi
            ? (deliveryRates.isEmpty
                ? 'Pengiriman belum tersedia ke alamat ini'
                : null)
            : 'Ongkir gagal dimuat · Coba lagi';
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _rates = const [];
        _error = 'Ongkir gagal dimuat · Coba lagi';
      });
    }
  }

  Future<void> _handleTap() async {
    if (widget.product.hasVariants && widget.variant == null) {
      await widget.onVariantRequested?.call();
      return;
    }
    if (!memberStore.isLoggedIn) {
      await widget.onLoginRequested?.call();
      if (mounted) await _load();
      return;
    }
    if (_error == 'Lengkapi alamat untuk cek ongkir') {
      await widget.onAddressRequested?.call();
      if (mounted) await _load();
      return;
    }
    if (_error != null) {
      await _load();
      return;
    }
    if (_address == null || (_address!.areaId ?? '').trim().isEmpty) {
      await widget.onAddressRequested?.call();
      if (mounted) await _load();
      return;
    }
    if (_rates.isEmpty) {
      await _load();
      return;
    }
    if (!mounted) return;
    await showProductShippingDetailSheet(
      context: context,
      address: _address!,
      item: _item,
      rates: _rates,
      shippingVoucher: widget.product.shippingVoucherPreview,
      onChangeAddress: widget.onAddressRequested,
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cheapest = cheapestDeliveryRate(_rates);
    final label = _summaryLabel(cheapest);

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: _loading ? null : _handleTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  size: 22,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _loading
                      ? const _ShippingSummarySkeleton()
                      : Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _summaryLabel(ShippingRate? cheapest) {
    if (widget.product.hasVariants && widget.variant == null) {
      return 'Pilih varian untuk cek ongkir';
    }
    if (!memberStore.isLoggedIn) return 'Masuk untuk cek ongkir';
    if (_loading) return 'Menghitung ongkir';
    if (_error != null) return _error!;
    if (_address == null) return 'Atur alamat untuk cek ongkir';
    if (cheapest == null) return 'Tersedia ambil sendiri di toko';
    final duration = cheapest.duration.trim();
    return 'Ongkos kirim mulai dari ${formatRupiah(cheapest.price)}'
        '${duration.isEmpty || duration == '-' ? '' : ' · Estimasi ${formatShippingDuration(duration)}'}';
  }
}

/// Normalizes API-provided delivery durations into the Indonesian UI copy.
/// The API may return English units (for example, `1–3 Hours`) while some
/// providers already return localized values such as `Hari ini`.
String formatShippingDuration(String value) {
  var normalized = value.trim();
  if (normalized.isEmpty || normalized == '-') return normalized;

  normalized = normalized
      .replaceAll(RegExp(r'\bhours?\b', caseSensitive: false), 'jam')
      .replaceAll(RegExp(r'\bdays?\b', caseSensitive: false), 'hari')
      .replaceAll(RegExp(r'\bminutes?\b', caseSensitive: false), 'menit')
      .replaceAll(RegExp(r'\bmins?\b', caseSensitive: false), 'menit');

  return normalized;
}

MemberAddress? pickPrimaryAddress(List<MemberAddress> addresses) {
  if (addresses.isEmpty) return null;
  return addresses.firstWhere(
    (address) => address.isPrimary,
    orElse: () => addresses.first,
  );
}

ShippingRate? cheapestDeliveryRate(List<ShippingRate> rates) {
  ShippingRate? cheapest;
  for (final rate in rates) {
    if (!rate.available || rate.isSelfPickup) continue;
    if (cheapest == null || rate.price < cheapest.price) cheapest = rate;
  }
  return cheapest;
}

Future<void> showProductShippingDetailSheet({
  required BuildContext context,
  required MemberAddress address,
  required CartItem item,
  required List<ShippingRate> rates,
  ProductVoucherPreview? shippingVoucher,
  Future<void> Function()? onChangeAddress,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _ProductShippingDetailSheet(
      address: address,
      item: item,
      rates: rates,
      shippingVoucher: shippingVoucher,
      onChangeAddress: onChangeAddress,
    ),
  );
}

class _ProductShippingDetailSheet extends StatelessWidget {
  const _ProductShippingDetailSheet({
    required this.address,
    required this.item,
    required this.rates,
    this.shippingVoucher,
    this.onChangeAddress,
  });

  final MemberAddress address;
  final CartItem item;
  final List<ShippingRate> rates;
  final ProductVoucherPreview? shippingVoucher;
  final Future<void> Function()? onChangeAddress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final orderedRates = [...rates]..sort((a, b) {
        if (a.isSelfPickup != b.isSelfPickup) return a.isSelfPickup ? 1 : -1;
        return a.price.compareTo(b.price);
      });

    return FractionallySizedBox(
      heightFactor: .72,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Detail Pengiriman',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              children: [
                const _LocationLine(
                  icon: Icons.storefront_outlined,
                  title: 'Dikirim dari',
                  value: PickupStoreInfo.name,
                ),
                const SizedBox(height: AppSpacing.lg),
                _LocationLine(
                  icon: Icons.location_on_outlined,
                  title: 'Dikirim ke',
                  value: _addressLabel(address),
                  trailing: onChangeAddress == null
                      ? null
                      : TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await onChangeAddress?.call();
                          },
                          child: const Text('Ubah'),
                        ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '1 item · ${item.weightGram} gram',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Pilihan pengiriman',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...orderedRates.map(
                  (rate) => _ShippingRateTile(rate: rate),
                ),
                if (shippingVoucher != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: AppSpacing.cardPaddingSmall,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: AppRadius.medium,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.local_offer_outlined,
                          size: 20,
                          color: colors.onPrimaryContainer,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shippingVoucher!.badgeLabel,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                shippingVoucher!.sheetSubtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Pilihan dan potongan ongkir final ditentukan saat checkout.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationLine extends StatelessWidget {
  const _LocationLine({
    required this.icon,
    required this.title,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs / 2),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _ShippingRateTile extends StatelessWidget {
  const _ShippingRateTile({required this.rate});

  final ShippingRate rate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rate.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  rate.isSelfPickup
                      ? rate.duration
                      : 'Estimasi ${formatShippingDuration(rate.duration)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Text(
            rate.price == 0 ? 'Gratis' : formatRupiah(rate.price),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShippingSummarySkeleton extends StatelessWidget {
  const _ShippingSummarySkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 210,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          borderRadius: AppRadius.pill,
        ),
      ),
    );
  }
}

String _addressLabel(MemberAddress address) {
  final location = address.areaLabel ??
      address.districtName ??
      address.cityName ??
      address.city ??
      address.address;
  final label = address.label?.trim();
  return label == null || label.isEmpty ? location : '$label · $location';
}
