import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/state/home_snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> productJson(String id, {String? name}) => {
      'id': id,
      'slug': id,
      'name': name ?? 'Produk $id',
      'price': 10000,
      'image_url': '',
    };

Map<String, dynamic> snapshotJson({
  required List<Map<String, dynamic>> products,
}) =>
    {
      'savedAt': '2026-07-01T00:00:00.000',
      'products': products,
      'brands': [
        {'name': 'BrandUji', 'slug': 'branduji', 'logoUrl': 'https://x/l.png'},
      ],
      'categories': [
        {'id': 'c1', 'name': 'Makanan', 'slug': 'makanan'},
      ],
      'banners': [
        {'id': 'b1', 'image': 'https://x/b.jpg'},
      ],
    };

/// Set semua fetcher non-produk ke sukses-kosong supaya tiap test cukup
/// mengatur fetcher produk (kriteria gagal = produk).
void stubOthersEmpty() {
  homeSnapshotStore.debugBestSellersFetcher = () async => [];
  homeSnapshotStore.debugBrandsFetcher = () async => [];
  homeSnapshotStore.debugCategoriesFetcher = () async => [];
  homeSnapshotStore.debugBannersFetcher = () async => [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    homeSnapshotStore.resetForTest();
  });

  test('loadFromDisk snapshot valid → state terisi + notify sekali', () async {
    SharedPreferences.setMockInitialValues({
      'home_snapshot_v1':
          jsonEncode(snapshotJson(products: [productJson('p1')])),
    });
    var notified = 0;
    homeSnapshotStore.addListener(() => notified++);
    await homeSnapshotStore.loadFromDisk();
    expect(homeSnapshotStore.products, hasLength(1));
    expect(homeSnapshotStore.products.first.id, 'p1');
    expect(homeSnapshotStore.brands, hasLength(1));
    expect(homeSnapshotStore.categories, hasLength(1));
    expect(homeSnapshotStore.banners, hasLength(1));
    expect(homeSnapshotStore.hasContent, isTrue);
    expect(notified, 1);
  });

  test('loadFromDisk JSON korup → tetap kosong + key dihapus, tidak throw',
      () async {
    SharedPreferences.setMockInitialValues({'home_snapshot_v1': '{rusak'});
    await homeSnapshotStore.loadFromDisk();
    expect(homeSnapshotStore.hasContent, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('home_snapshot_v1'), isNull);
  });

  test('guard race: refresh sukses duluan → loadFromDisk TIDAK menimpa',
      () async {
    SharedPreferences.setMockInitialValues({
      'home_snapshot_v1':
          jsonEncode(snapshotJson(products: [productJson('lama')])),
    });
    homeSnapshotStore.debugProductsFetcher =
        () async => [productJson('segar')];
    stubOthersEmpty();
    await homeSnapshotStore.refresh();
    await homeSnapshotStore.loadFromDisk();
    expect(homeSnapshotStore.products.single.id, 'segar');
  });

  test('refresh sukses → state ditimpa + snapshot disk tertulis (raw)',
      () async {
    homeSnapshotStore.debugProductsFetcher = () async => [productJson('p1')];
    homeSnapshotStore.debugBestSellersFetcher = () async => [];
    homeSnapshotStore.debugBrandsFetcher = () async => [
          {'name': 'BrandBaru', 'slug': 'brandbaru'},
        ];
    homeSnapshotStore.debugCategoriesFetcher = () async => [];
    homeSnapshotStore.debugBannersFetcher = () async => [];
    await homeSnapshotStore.refresh();
    // _persist fire-and-forget — kasih kesempatan microtask selesai.
    await Future<void>.delayed(Duration.zero);
    expect(homeSnapshotStore.products.single.id, 'p1');
    expect(homeSnapshotStore.brands.single.name, 'BrandBaru');
    final prefs = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(prefs.getString('home_snapshot_v1')!) as Map<String, dynamic>;
    expect((saved['products'] as List).single['id'], 'p1');
    expect((saved['brands'] as List).single['name'], 'BrandBaru');
    expect(saved['savedAt'], isNotNull);
  });

  test('refresh gagal saat konten ada → state tetap + flag set (UI diam)',
      () async {
    homeSnapshotStore.debugProductsFetcher = () async => [productJson('p1')];
    stubOthersEmpty();
    await homeSnapshotStore.refresh();
    homeSnapshotStore.debugProductsFetcher = () async => null; // gagal
    await homeSnapshotStore.refresh(force: true);
    expect(homeSnapshotStore.products.single.id, 'p1'); // dipertahankan
    expect(homeSnapshotStore.lastRefreshFailed, isTrue);
    expect(homeSnapshotStore.hasContent, isTrue); // banner tetap tak tampil
  });

  test('refresh gagal tanpa konten → lastRefreshFailed + hasContent false',
      () async {
    homeSnapshotStore.debugProductsFetcher = () async => null;
    stubOthersEmpty();
    await homeSnapshotStore.refresh();
    expect(homeSnapshotStore.lastRefreshFailed, isTrue);
    expect(homeSnapshotStore.hasContent, isFalse);
  });

  test('gagal lalu sukses → lastRefreshFailed kembali false', () async {
    homeSnapshotStore.debugProductsFetcher = () async => null;
    stubOthersEmpty();
    await homeSnapshotStore.refresh();
    expect(homeSnapshotStore.lastRefreshFailed, isTrue);
    homeSnapshotStore.debugProductsFetcher = () async => [productJson('p1')];
    await homeSnapshotStore.refresh(force: true);
    expect(homeSnapshotStore.lastRefreshFailed, isFalse);
    expect(homeSnapshotStore.hasContent, isTrue);
  });

  test('guard anti-dobel: panggilan kedua saat in-flight = no-op', () async {
    var calls = 0;
    final gate = Completer<List<Map<String, dynamic>>?>();
    homeSnapshotStore.debugProductsFetcher = () {
      calls++;
      return gate.future;
    };
    stubOthersEmpty();
    final first = homeSnapshotStore.refresh();
    await homeSnapshotStore.refresh(force: true); // langsung return (skip)
    expect(calls, 1);
    gate.complete([productJson('p1')]);
    await first;
    expect(homeSnapshotStore.products, hasLength(1));
  });

  test('soft-throttle: non-force <30s setelah sukses skip; force jalan',
      () async {
    var calls = 0;
    homeSnapshotStore.debugProductsFetcher = () async {
      calls++;
      return [productJson('p1')];
    };
    stubOthersEmpty();
    await homeSnapshotStore.refresh();
    expect(calls, 1);
    await homeSnapshotStore.refresh(); // throttled
    expect(calls, 1);
    await homeSnapshotStore.refresh(force: true); // bypass
    expect(calls, 2);
  });

  test('gagal parsial: produk sukses + banner gagal → banner lama bertahan',
      () async {
    homeSnapshotStore.debugProductsFetcher = () async => [productJson('p1')];
    homeSnapshotStore.debugBestSellersFetcher = () async => [];
    homeSnapshotStore.debugBrandsFetcher = () async => [];
    homeSnapshotStore.debugCategoriesFetcher = () async => [];
    homeSnapshotStore.debugBannersFetcher = () async => [
          {'id': 'b1', 'image': 'https://x/b.jpg'},
        ];
    await homeSnapshotStore.refresh();
    expect(homeSnapshotStore.banners, hasLength(1));
    homeSnapshotStore.debugProductsFetcher = () async => [productJson('p2')];
    homeSnapshotStore.debugBannersFetcher = () async => null; // gagal
    await homeSnapshotStore.refresh(force: true);
    expect(homeSnapshotStore.products.single.id, 'p2'); // ditimpa
    expect(homeSnapshotStore.banners, hasLength(1)); // dipertahankan
    // Produk sukses = refresh sukses walau banner gagal.
    expect(homeSnapshotStore.lastRefreshFailed, isFalse);
  });

  test('terlaris: diambil dari fetcher sendiri, BUKAN urutan ulang products',
      () async {
    // products = 48 produk terbaru (soldCount kecil); bestSellers = daftar
    // terpisah dari seluruh katalog. Kalau suatu saat kode kembali
    // mengurutkan `products` by soldCount, test ini gagal.
    homeSnapshotStore.debugProductsFetcher = () async => [
          productJson('baru-1'),
          productJson('baru-2'),
        ];
    homeSnapshotStore.debugBestSellersFetcher = () async => [
          productJson('juara-27-terjual'),
          productJson('juara-20-terjual'),
        ];
    homeSnapshotStore.debugBrandsFetcher = () async => [];
    homeSnapshotStore.debugCategoriesFetcher = () async => [];
    homeSnapshotStore.debugBannersFetcher = () async => [];

    await homeSnapshotStore.refresh();

    expect(
      homeSnapshotStore.bestSellers.map((p) => p.id).toList(),
      ['juara-27-terjual', 'juara-20-terjual'],
      reason: 'urutan dari server dipakai apa adanya, tanpa di-sort ulang',
    );
    expect(
      homeSnapshotStore.products.map((p) => p.id).toList(),
      ['baru-1', 'baru-2'],
      reason: 'daftar produk utama tidak ikut tercampur',
    );
  });

  test('terlaris gagal sendirian → daftar lama dipertahankan, refresh TIDAK gagal',
      () async {
    homeSnapshotStore.debugProductsFetcher = () async => [productJson('p1')];
    stubOthersEmpty();
    homeSnapshotStore.debugBestSellersFetcher =
        () async => [productJson('juara')];
    await homeSnapshotStore.refresh();
    expect(homeSnapshotStore.bestSellers.single.id, 'juara');

    // Putaran kedua: terlaris gagal (null), produk tetap sukses.
    homeSnapshotStore.debugProductsFetcher = () async => [productJson('p2')];
    homeSnapshotStore.debugBestSellersFetcher = () async => null;
    await homeSnapshotStore.refresh(force: true);

    expect(homeSnapshotStore.lastRefreshFailed, isFalse);
    expect(homeSnapshotStore.products.single.id, 'p2');
    expect(homeSnapshotStore.bestSellers.single.id, 'juara',
        reason: 'daftar terlaris lama dipertahankan, bukan dikosongkan');
  });

  test('snapshot disk LAMA tanpa key bestSellers tetap terbaca (tidak korup)',
      () async {
    // Snapshot yang ditulis versi app sebelum bagian ini ada.
    SharedPreferences.setMockInitialValues({
      'home_snapshot_v1': jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'products': [productJson('lama')],
        'brands': <Map<String, dynamic>>[],
        'categories': <Map<String, dynamic>>[],
        'banners': <Map<String, dynamic>>[],
      }),
    });
    await homeSnapshotStore.loadFromDisk();
    expect(homeSnapshotStore.products.single.id, 'lama',
        reason: 'snapshot lama harus tetap dipakai, bukan dibuang');
    expect(homeSnapshotStore.bestSellers, isEmpty,
        reason: 'terisi nanti saat refresh pertama');
  });
}
