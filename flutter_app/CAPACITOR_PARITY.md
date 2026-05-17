# Capacitor PWA ↔ Flutter Parity Roadmap

Audit dari `C:\Users\USER\Desktop\toko-pwa-starter\app\api\**\route.ts` (103 routes).

## ✅ Layer 1: API services (100% wired)

Semua user-facing endpoint Capacitor sudah punya service method di
`lib/services/`. Lihat audit lengkap:

```bash
grep -rE "/api/[a-z]" flutter_app/lib/services/ | grep -oE "/api/[a-zA-Z0-9/_-]+" | sort -u
```

Service files:
- `auth_service.dart` — login, register, forgot, reset-password, me, logout,
  delete-account (`/api/account/delete`), revoke-others
- `member_service.dart` — profile, orders, vouchers, claim-voucher,
  loyalty/history, addresses CRUD, cart-vouchers
- `cart_service.dart` — get, replace, **validate**, **validate-private-voucher**
- `order_service.dart` — create, detail, payment-proof, reorder,
  **cancel**, **bulk-status**, **midtrans**
- `product_service.dart` — list, detail, view, search/suggest, banners,
  brands, categories, **product-vouchers**, **product-feed-posts**
- `feed_service.dart` — posts CRUD, comments, likes, shares, upload-video,
  upload-thumbnail, bunny/upload-url, my-posts, **pinnable-products**
- `notification_service.dart` — list, mark-read, **mark-all-read**,
  **preferences GET/PUT**
- `push_notification_service.dart` — subscribe-fcm, **subscribe-apns**,
  **me/status**, **me/test**
- `review_service.dart` — list, summary, helpful, upload, **update**, **delete**
- `shipping_service.dart` — rates, **areas search**, **origin**
- `favorite_service.dart` — wishlist sync
- `search_service.dart` — **search, facets, popular, trending, log**
- `places_service.dart` — **autocomplete, details, reverse-geocode**
- `wilayah_service.dart` — **provinces → regencies → districts → villages**
- `store_info_service.dart` — **GET /api/store-info** (jam buka, kontak)
- `voucher_service.dart` — **validate** + **checkout/recalculate**

Bold = ditambah di Sprint terakhir.

## ✅ Layer 2: UI wiring (done — 5 items)

1. **Search log + popular/trending chips** — `home_screen.dart` search sheet
2. **Live operational hours card** — `register_screen.dart` `_LiveOperationalHoursCard`
3. **Test push button + subscription status** — `notification_preferences_screen.dart` `_TestPushButton`
4. **Cart validate pre-checkout** — `checkout_screen.dart` `_placeOrder()`
5. **Manual voucher input** — `_VoucherSheet` di checkout

## ⏳ Layer 2: UI wiring TODO (11 items remaining)

Setiap item punya service method siap pakai. Tinggal hook UI ke service call.

### Quick wins (S effort, < 1 jam each)

#### 6. Checkout server-side recalc
**Lokasi**: `checkout_screen.dart` `_placeOrder()` setelah `cartService.validate()`
**Service**: `checkoutService.recalculate(items, voucherCode, shippingRate, useProtection)`
**UI change**: 
```dart
final recalc = await checkoutService.recalculate(...);
if (recalc != null && (recalc.total - _grandTotal).abs() > 100) {
  // Total beda → show dialog "Total berubah jadi Rp X, lanjut?"
}
```

#### 7. Orders bulk status auto-refresh
**Lokasi**: `member_orders_screen.dart`
**Service**: `orderService.bulkStatus(orderNumbers)`
**UI change**: Timer 30-detik poll → update status badge di list cards.

#### 8. Review edit/delete menu
**Lokasi**: `widgets/product_review_section.dart` `_ReviewCard`
**Service**: `reviewService.updateReview()` + `deleteReview()`
**UI change**: Add 3-dot menu di card kalau `review.userId == currentUserId`:
```dart
PopupMenuButton(...) // Edit dialog + Hapus confirmation
```

### Medium UI (M effort, 1-3 jam each)

#### 9. Reset password screen (deep link receiver)
**Service**: `authService.resetPassword(token, newPassword)`
**New screen**: `lib/screens/reset_password_screen.dart`
**Route**: `/auth/reset-password?token=...`
**Deep link**: `deep_link_service.dart` parse `?token=` query param dari
URL `natalopetshop.com/auth/reset-password?token=ABC`, push ke screen baru.
**UI**: Form dengan 2 password field + token (hidden) + submit button.

#### 10. Product detail — voucher section
**Lokasi**: `product_detail_screen.dart` insert section setelah `_ProductHero`
**Service**: `productService.fetchProductVouchers(slug)`
**UI**: Horizontal carousel voucher cards (mirror Tokopedia/Shopee pattern).

#### 11. Product detail — UGC feed videos
**Lokasi**: `product_detail_screen.dart` insert section "Video dari user"
**Service**: `productService.fetchProductFeedPosts(slug)`
**UI**: Horizontal video thumbnail carousel → tap → open feed dengan post terpilih.

#### 12. Feed upload — product tagger
**Lokasi**: `widgets/feed_upload_sheet.dart` add step setelah caption
**Service**: `feedService.fetchPinnableProducts()`
**UI**: Step picker — list produk yang pernah dibeli user → multi-select chips
→ kirim `productIds` ke `feedService.createFeedPost()`.

### Large UI (M-L effort, 3-6 jam each)

#### 13-16. Address form major refactor
**Lokasi**: `widgets/address_form_sheet.dart` (or wherever address create/edit)
**Services**:
- `placesService.autocomplete(query)` — saat user ketik di field alamat
- `placesService.reverseGeocode(lat, lng)` — saat tap "Pakai GPS"
- `wilayahService.*` — cascade dropdown Provinsi → Kota → Kec → Desa
- `shippingService.fetchAreas(query)` — search Biteship area untuk shipping
- `geolocator` package — get GPS coordinates

**Flow design**:
```
[Field "Alamat lengkap"] → autocomplete dropdown (placesService)
                       ↓ tap suggestion
[Auto-fill Provinsi/Kota/Kec/Desa] → cascade picker (wilayahService)
                                  ↓ pick area
[Auto-suggest Biteship areaId] → shipping calc available (shippingService)

[Tombol "Pakai GPS"] → permission → coords → reverseGeocode → fill all fields
```

Need additional package: `geolocator: ^13.0.0` untuk native GPS access.

#### 17. Midtrans payment gateway
**Service**: `orderService.initiateMidtrans(orderNumber)` returns Snap token
**Options**:
- A) Add package `midtrans_sdk: ^1.0.0` — native Snap UI
- B) WebView dengan `redirectUrl` — pakai `flutter_inappwebview` (sudah ada)
- C) Open external browser via `url_launcher`

**Recommended**: Option B (WebView in-app) supaya user tidak keluar app.

## 📊 Endpoint coverage summary

| Domain | Capacitor routes | Flutter service | UI wired |
|--------|------------------|-----------------|----------|
| Auth | 8 | 8/8 ✅ | 6/8 (reset-password screen pending) |
| Account | 2 | 2/2 ✅ | 2/2 ✅ |
| Member | 6 | 6/6 ✅ | 6/6 ✅ |
| Cart | 7 | 7/7 ✅ | 5/7 (private voucher + recalc UI pending) |
| Checkout | 1 | 1/1 ✅ | 0/1 (recalc UI pending) |
| Orders | 5 | 5/5 ✅ | 4/5 (bulk status pending) |
| Payment | 1 | 1/1 ✅ | 0/1 (Midtrans WebView pending) |
| Products | 6 | 6/6 ✅ | 4/6 (vouchers + UGC pending) |
| Feed | 14 | 14/14 ✅ | 13/14 (pinnable products pending) |
| Reviews | 5 | 5/5 ✅ | 3/5 (edit/delete UI pending) |
| Notifications | 4 | 4/4 ✅ | 4/4 ✅ |
| Push | 5 | 5/5 ✅ | 5/5 ✅ |
| Shipping | 3 | 3/3 ✅ | 1/3 (areas + origin UI pending) |
| Places | 3 | 3/3 ✅ | 0/3 (autocomplete UI pending) |
| Wilayah | 1 (catchall) | 4 methods ✅ | 0/4 (cascade picker UI pending) |
| Search | 6 | 6/6 ✅ | 5/6 (facets UI pending) |
| Store info | 1 | 1/1 ✅ | 1/1 ✅ |
| Vouchers | 1 | 1/1 ✅ | 1/1 ✅ |
| **TOTAL** | **79 user-facing** | **79/79 ✅** | **~60/79 wired** |

## 🎯 Recommended next sprint priority

1. **HIGH**: Reset password screen (deep link) — Play Store reviewer akan test
2. **HIGH**: Address form Places autocomplete — UX gap besar di checkout flow
3. **MED**: Review edit/delete — common e-commerce feature
4. **MED**: Product detail voucher section — discovery booster
5. **LOW**: Feed pinnable products — power user feature
6. **LOW**: Midtrans WebView — pakai redirectUrl (already returned from service)

## How to wire incrementally

Pattern untuk wire 1 item:

```dart
// 1. Import service
import '../services/voucher_service.dart';

// 2. Add state (kalau StatefulWidget)
class _MyState extends State<...> {
  bool _loading = false;
  String? _error;
  
  // 3. Add async handler
  Future<void> _doAction() async {
    setState(() => _loading = true);
    final result = await voucherService.validate(code: ..., subtotal: ...);
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.valid) {
      setState(() => _error = result.message);
      return;
    }
    // Apply result ke UI state
  }
  
  // 4. Render button + loading + error
  Widget build(BuildContext context) {
    return Column(children: [
      if (_loading) CircularProgressIndicator(),
      if (_error != null) Text(_error!, style: TextStyle(color: Colors.red)),
      ElevatedButton(onPressed: _doAction, child: Text('Action')),
    ]);
  }
}
```

All service methods sudah punya defensive try/catch — kalau backend endpoint
belum aktif, gracefully return empty/null instead of throwing. UI tidak crash.
