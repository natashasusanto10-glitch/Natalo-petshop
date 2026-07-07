import '../models/launch_popup_campaign.dart';

/// Sumber konten popup pembuka — V1 HARDCODED.
///
/// Untuk upgrade ke admin-managed: ganti isi fungsi ini agar membaca hasil
/// fetch API (lihat spec §11). UI, gate, dan logika skip tidak berubah.
/// Set `_campaign` ke null untuk mematikan popup tanpa hapus kode.
LaunchPopupCampaign? activeLaunchPopup() => _campaign;

const LaunchPopupCampaign? _campaign = LaunchPopupCampaign(
  id: 'promo-juli-2026',
  tone: LaunchPopupTone.promo,
  imageUrl: null, // isi 'assets/...' atau URL saat aset poster siap
  title: 'Diskon 30% khusus member',
  body: 'Hemat 30% untuk vitamin dan makanan. Berlaku sampai 13 Juli.',
  categoryLabel: 'Promo',
  ctaLabel: 'Lihat produk',
  // Pastikan slug ini cocok dengan produk nyata sebelum rilis.
  ctaHref: '/produk/royal-canin-kitten',
  dismissLabel: 'Nanti saja',
);
