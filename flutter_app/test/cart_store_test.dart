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
}
