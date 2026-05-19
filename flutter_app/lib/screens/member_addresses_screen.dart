import 'package:flutter/material.dart';

import '../models/member_address.dart';
import '../services/member_service.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';

/// Member Addresses — list saved addresses, kalau ada empty state CTA add.
/// Edit/delete operations stub via toast (sementara pakai PWA web).
class MemberAddressesScreen extends StatefulWidget {
  const MemberAddressesScreen({super.key});

  @override
  State<MemberAddressesScreen> createState() => _MemberAddressesScreenState();
}

class _MemberAddressesScreenState extends State<MemberAddressesScreen> {
  late Future<List<MemberAddress>> _addressesFuture;

  @override
  void initState() {
    super.initState();
    _addressesFuture = _load();
  }

  Future<List<MemberAddress>> _load() async {
    if (!memberStore.isLoggedIn) return const [];
    try {
      final addrs = await memberService.fetchAddresses();
      memberStore.setAddresses(addrs);
      return addrs;
    } catch (_) {
      return memberStore.addresses;
    }
  }

  Future<void> _refresh() async {
    AppHaptics.tap();
    setState(() {
      _addressesFuture = _load();
    });
    await _addressesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text('Alamat Pengiriman'),
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
      ),
      body: NataloPawRefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<MemberAddress>>(
          future: _addressesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final addresses = snapshot.data ?? const <MemberAddress>[];
            if (addresses.isEmpty) {
              return _EmptyState(onAdd: () => _showAddPlaceholder(context));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: addresses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _AddressCard(
                address: addresses[index],
                onEdit: () => _showEditPlaceholder(context),
                onDelete: () => _showDeletePlaceholder(context),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddPlaceholder(context),
        backgroundColor: NataloColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Tambah Alamat'),
      ),
    );
  }

  void _showAddPlaceholder(BuildContext context) {
    AppHaptics.tap();
    AppToast.show(
      context,
      'Tambah alamat sementara via PWA web. Flutter coming soon.',
      kind: ToastKind.info,
    );
  }

  void _showEditPlaceholder(BuildContext context) {
    AppHaptics.tap();
    AppToast.show(
      context,
      'Edit alamat sementara via PWA web.',
      kind: ToastKind.info,
    );
  }

  void _showDeletePlaceholder(BuildContext context) {
    AppHaptics.tap();
    AppToast.show(
      context,
      'Hapus alamat sementara via PWA web.',
      kind: ToastKind.info,
    );
  }
}

class _AddressCard extends StatelessWidget {
  final MemberAddress address;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AddressCard({
    required this.address,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isPrimary = address.isMain;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPrimary
              ? NataloColors.primary
              : const Color(0xFFDDE8F8),
          width: isPrimary ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  address.label ?? 'Alamat',
                  style: const TextStyle(
                    color: NataloColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isPrimary) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Utama',
                    style: TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: NataloColors.textTertiary,
                ),
                onPressed: () => _showMenu(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            address.recipient,
            style: const TextStyle(
              color: NataloColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (address.phone.isNotEmpty)
            Text(
              address.phone,
              style: const TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            address.address,
            style: const TextStyle(
              color: NataloColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          if ((address.cityName ?? address.city) != null ||
              address.postalCode != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (address.districtName?.isNotEmpty == true) address.districtName,
                if ((address.cityName ?? address.city)?.isNotEmpty == true)
                  (address.cityName ?? address.city),
                if (address.provinceName?.isNotEmpty == true) address.provinceName,
                if (address.postalCode?.isNotEmpty == true) address.postalCode,
              ].whereType<String>().join(', '),
              style: const TextStyle(
                color: NataloColors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit alamat'),
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: NataloColors.danger,
              ),
              title: const Text(
                'Hapus alamat',
                style: TextStyle(color: NataloColors.danger),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.location_off_outlined,
                size: 44,
                color: NataloColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Belum ada alamat',
              style: TextStyle(
                color: NataloColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tambahkan alamat pengiriman supaya checkout lebih cepat.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Tambah Alamat'),
            ),
          ],
        ),
      ),
    );
  }
}
