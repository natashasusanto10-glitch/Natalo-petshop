import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/cart_item.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/services/cart_service.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';
import 'package:natalo_petshop_flutter/utils/read_only_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake CartService via subclass — override HANYA fetchCart/replaceCart.
/// validate/validatePrivateVoucher diwarisi (tak dipakai CartStore).
class _FakeCartService extends CartService {
  _FakeCartService();

  List<CartItem> remote = [];
  int replaceCallCount = 0;
  Object? throwOnReplace;
  bool throwOnce = false;

  @override
  Future<List<CartItem>> fetchCart() async => remote;

  @override
  Future<void> replaceCart(List<CartItem> items) async {
    replaceCallCount++;
    final err = throwOnReplace;
    if (err != null) {
      if (throwOnce) throwOnReplace = null;
      throw err;
    }
  }
}

Product _product(String id, {int stock = 10}) => Product(
      id: id,
      slug: id,
      title: 'Produk $id',
      category: 'Produk',
      brand: 'Natalo',
      imageUrl: '',
      price: 10000,
      rating: 0,
      reviewCount: 0,
      stock: stock,
      description: '',
    );

CartItem _item(String id, {int quantity = 1, int stock = 10}) => CartItem(
      product: _product(id, stock: stock),
      quantity: quantity,
      unitPrice: 10000,
      effectiveStock: stock,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('mutation menandai pendingSync true; sync sukses menjadikannya false', () async {
    final fake = _FakeCartService();
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.addItem(_item('A', quantity: 2));
    expect(store.pendingSync, true);

    await store.syncToServer();
    expect(fake.replaceCallCount, 1);
    expect(store.pendingSync, false);
  });

  test('sync gagal: flag tetap true + retry terjadwal; sukses di percobaan ke-2 membersihkan flag', () async {
    final fake = _FakeCartService()
      ..throwOnReplace = Exception('network down')
      ..throwOnce = true;
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.addItem(_item('A', quantity: 1));

    await store.syncToServer(); // gagal sekali
    expect(store.pendingSync, true);
    expect(store.hasPendingRetry, true);
    expect(fake.replaceCallCount, 1);

    await store.syncToServer(); // simulasi retry firing — sukses
    expect(store.pendingSync, false);
    expect(store.hasPendingRetry, false);
    expect(fake.replaceCallCount, 2);
  });

  test('ReadOnlyModeException: flag tetap true, TIDAK ada retry terjadwal', () async {
    final fake = _FakeCartService()
      ..throwOnReplace = const ReadOnlyModeException('cart_sync');
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.addItem(_item('A', quantity: 1));
    await store.syncToServer();

    expect(store.pendingSync, true);
    expect(store.hasPendingRetry, false);
    expect(fake.replaceCallCount, 1);
  });

  test('loadFromDisk dengan flag pending tersimpan → memicu sync', () async {
    // Seed: store pertama menambah item (persist item + flag true), lalu
    // dispose sebelum debounce sync sempat jalan — meniru app di-kill.
    final seeder = CartStore.forTest(
      service: _FakeCartService(),
      isLoggedIn: () => true,
    );
    await seeder.addItem(_item('A', quantity: 1));
    expect(seeder.pendingSync, true);
    seeder.dispose();

    // Store kedua load dari disk yang sama (mock prefs persist in-memory).
    final fake = _FakeCartService();
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.loadFromDisk();
    expect(store.pendingSync, true); // flag ter-restore dari disk
    await pumpEventQueue();
    expect(fake.replaceCallCount, 1); // sync ter-trigger otomatis
    expect(store.pendingSync, false);
  });

  test('resume dari background dengan flag pending → sync', () async {
    final fake = _FakeCartService();
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.addItem(_item('A', quantity: 1));
    expect(store.pendingSync, true);

    store.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(fake.replaceCallCount, greaterThanOrEqualTo(1));
    expect(store.pendingSync, false);
  });

  test('loadFromServer merge union: qty dijumlahkan, item server-only masuk', () async {
    final fake = _FakeCartService()
      ..remote = [
        _item('A', quantity: 3, stock: 10),
        _item('B', quantity: 1, stock: 10),
      ];
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.addItem(_item('A', quantity: 2, stock: 10)); // lokal A=2

    await store.loadFromServer();

    expect(store.quantityFor('A'), 5); // 2 lokal + 3 server
    expect(store.quantityFor('B'), 1); // server-only ikut masuk
  });

  test('loadFromServer idempoten dalam satu sesi: panggil 2x tidak menggandakan', () async {
    final fake = _FakeCartService()
      ..remote = [_item('A', quantity: 3, stock: 10)];
    final store = CartStore.forTest(service: fake, isLoggedIn: () => true);
    addTearDown(store.dispose);

    await store.addItem(_item('A', quantity: 2, stock: 10));

    await store.loadFromServer();
    await store.loadFromServer(); // panggilan ke-2 harus di-skip

    expect(store.quantityFor('A'), 5); // bukan 8
    expect(store.mergedThisSession, true);
  });

  group('addProduct return = "berhasil ditambah penuh"', () {
    // Regresi: addProduct dulu SELALU return true (flag clamped dari
    // addItem dibuang), jadi guard `if (!added) return;` di
    // order_success_screen adalah kode mati dan keranjang penuh tetap
    // memunculkan toast "masuk keranjang" padahal tidak ada yang masuk.
    test('normal: return true dan qty bertambah', () async {
      final store = CartStore.forTest(
        service: _FakeCartService(), isLoggedIn: () => false);
      addTearDown(store.dispose);

      final added = await store.addProduct(_product('A', stock: 5));
      expect(added, true);
      expect(store.quantityFor('A'), 1);
    });

    test('keranjang sudah di batas stok: return false, qty tidak berubah',
        () async {
      final store = CartStore.forTest(
        service: _FakeCartService(), isLoggedIn: () => false);
      addTearDown(store.dispose);

      await store.addProduct(_product('A', stock: 2), quantity: 2);
      final added = await store.addProduct(_product('A', stock: 2));
      expect(added, false, reason: 'tidak ada yang masuk — jangan bilang sukses');
      expect(store.quantityFor('A'), 2);
    });

    test('sebagian masuk (minta 3, slot sisa 1): return false, qty ke cap',
        () async {
      final store = CartStore.forTest(
        service: _FakeCartService(), isLoggedIn: () => false);
      addTearDown(store.dispose);

      await store.addProduct(_product('A', stock: 3), quantity: 2);
      final added = await store.addProduct(_product('A', stock: 3), quantity: 3);
      expect(added, false, reason: 'permintaan TIDAK terpenuhi penuh');
      expect(store.quantityFor('A'), 3);
    });

    test('stok 0 = tidak diketahui: tidak di-clamp, return true', () async {
      final store = CartStore.forTest(
        service: _FakeCartService(), isLoggedIn: () => false);
      addTearDown(store.dispose);

      final added = await store.addProduct(_product('A', stock: 0));
      expect(added, true, reason: 'server /api/cart/validate yang jadi backstop');
      expect(store.quantityFor('A'), 1);
    });
  });
}
