# Notifikasi Promo — Voucher & Diskon Produk

**Date:** 2026-07-19
**Scope:** Backend web (Next.js `lib/`, `app/api/`, `prisma/`) + admin web form + client Flutter
**Status:** Draft for review
**Depends on:** Redesign notifikasi (#189) + P0–P3 routing/thumbnail (#190/#192/#195/#196), preferensi notifikasi server-filter (#188).

## Latar

Saat ini pembuatan Voucher (`app/api/admin/vouchers/route.ts` POST :90-191) dan Diskon Produk "Promo Toko" (`app/api/admin/discounts/promo-toko/route.ts` POST :95-214) **sama sekali tidak memberi tahu user** — tidak ada push, FCM, maupun baris `Announcement`. Padahal ala Shopee/Tokopedia, promo (diskon produk, gratis ongkir) adalah notifikasi bernilai tinggi — dengan gambar yang tepat dan routing presisi.

Keputusan produk (sudah disepakati):

1. **Trigger**: checkbox **"Beri tahu pelanggan"** di form admin (default OFF) — konsisten dengan feed publish (PR #112). Admin memutuskan promo mana yang layak dikirim; bukan otomatis (anti-spam).
2. **Penerima**: semua member (broadcast segment), bukan tertarget wishlist.
3. **Gambar**: diskon produk → foto produk pertama (`thumbnailUrl`); voucher (termasuk gratis ongkir) → **ilustrasi digambar client Flutter** berdasarkan jenis voucher (truk = gratis ongkir, %-tag = potongan), `thumbnailUrl` null.
4. **Routing tap**: voucher → `/member/vouchers` (rute sudah ada `main.dart:429`); diskon 1 produk → `/produk/{slug}`; diskon banyak produk → `/products`.
5. **Promo terjadwal**: notif dikirim **saat promo MULAI** (bukan saat dibuat) via cron; promo yang sudah aktif saat dibuat → kirim langsung.

## Arsitektur

Ikuti pola `lib/feed/publish-push.ts` (bukan `push-marketing.ts` per-user): **satu baris `Announcement` ber-`segment`** (tampil di lonceng, murah — bukan N baris per user) + push batch (`sendPushToUser` + `sendFcmToUser`) ke user hasil `resolveSegmentUserIds` (helper sudah ada, `publish-push.ts:31`, batch 50).

**PENTING — pakai `segment:"all"`, BUKAN `"members"`.** Verifikasi kode: `resolveSegmentUserIds("members")` (`publish-push.ts:44-62`) hanya menghasilkan user yang punya pesanan **PAID** + push subscription; dan lonceng `app/api/notifications/me/route.ts:116-128` hanya menampilkan Announcement `segment:"members"` ke user ber-`hasPaidOrder`. Karena keputusan produk = **semua member**, kedua kanal WAJIB pakai `segment:"all"` (lonceng `route.ts:126` menyemai `["all"]` untuk semua user; push `resolveSegmentUserIds("all")` `:32-38` = semua user dgn push subscription). Setiap baris Announcement baru juga WAJIB set `status:"PUBLISHED"` (API memfilter `status:"PUBLISHED"` + jendela tanggal aktif `route.ts:85-139`; feed helper set ini, jangan andalkan default diam-diam).

### Skema (migration SQL tulis-tangan, `IF NOT EXISTS`)

```sql
ALTER TABLE "Voucher"
ADD COLUMN IF NOT EXISTS "notifyAtStart" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS "promoNotifiedAt" TIMESTAMP(3);

ALTER TABLE "ProductDiscount"
ADD COLUMN IF NOT EXISTS "notifyAtStart" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS "promoNotifiedAt" TIMESTAMP(3);
```

- `notifyAtStart` = admin mencentang checkbox. `promoNotifiedAt` = guard anti-dobel (di-klaim atomik via `updateMany where promoNotifiedAt:null`).
- Field waktu: Voucher `startsAt`(default `now()`)/`expiresAt` (`schema.prisma:801-802`), ProductDiscount `startsAt`/`endsAt` (:726-727), keduanya + `isActive`. **Prisma schema**: tambah dua field ke model `Voucher` (~:789) dan `ProductDiscount` (~:722) selain migration SQL, supaya klien Prisma mengenalinya.

### `lib/push-promo.ts` (modul baru)

- `sendVoucherPromoPush(voucherId)`:
  - **Klaim atomik anti-dobel dulu** (pola feed `publish-push.ts:142-146`): `prisma.voucher.updateMany({ where:{ id, promoNotifiedAt:null }, data:{ promoNotifiedAt: now } })`. Bila `count === 0` → sudah terkirim (route+cron race) → return tanpa mengirim. Ini menggantikan "set flag lalu kirim" biasa supaya route dan cron tidak pernah dobel-kirim.
  - Ambil voucher (`name, code, kind, discountPercent, discountAmount, isActive, startsAt, expiresAt`). Skip (dan boleh reset flag / biarkan) bila tidak aktif/kedaluwarsa.
  - Judul/body via builder murni teruji `buildVoucherPromoContent(voucher)`:
    - `kind === "FREE_SHIPPING"` → title `🚚 Gratis Ongkir dari Natalo!`, body `Voucher gratis ongkir {code} sudah aktif. Klaim sekarang sebelum habis!`
    - selain itu → title `🎟️ Voucher diskon baru buat kamu`, body menyebut nilai (`Diskon {percent}%` / `Potongan Rp{amount}`) + kode.
  - **`eventType` membawa jenis voucher** (bukan `data`): `"voucher_freeship_published"` untuk gratis ongkir, `"voucher_discount_published"` untuk diskon. Alasan: `AppNotification`/API lonceng (`mapAnnouncement` `route.ts:38-77`) hanya membawa field datar — **tidak ada `data` map / `voucherKind`**; ilustrasi client HARUS dibedakan dari `eventType` (bukan `data.voucherKind`, yang cuma ada di toast push OS, bukan baris lonceng).
  - `Announcement` SATU baris: `segment:"all"`, `status:"PUBLISHED"`, `type:"promo"`, `eventType` (dua nilai di atas), `url:"/member/vouchers"`, `thumbnailUrl:null`, `ctaLabel:"Lihat Voucher"`, `publishedAt: now`.
  - Push batch ke `resolveSegmentUserIds("all")` dengan `PushPayload` ber-`prefCategory:"promo"` (**WAJIB** — gate preferensi #188; feed publish-push TIDAK set ini, jadi promo harus set eksplisit), `data.type` = eventType, `data.voucherKind` (untuk toast OS saja), `tag:"voucher-promo-{id}"`.
- `sendProductDiscountPromoPush(discountId)`:
  - Klaim atomik `productDiscount.updateMany({where:{id,promoNotifiedAt:null},data:{promoNotifiedAt:now}})` dulu (sama seperti voucher). `count===0` → return.
  - Ambil discount + `items` — join **`product { name, slug, imageUrl, price }` dan `variant { price }`** (WAJIB: `ProductDiscountItem` hanya simpan `discountedPrice` `schema.prisma:753`, TANPA harga asli; `maxPercent` dihitung dari harga asli produk/varian vs `discountedPrice`, jadi harga asli wajib di-fetch). Skip bila tidak aktif / di luar periode.
  - Builder murni `buildDiscountPromoContent(discount, items)`:
    - 1 item → title `🔥 {productName} lagi diskon!`, url `/produk/{slug}`.
    - >1 item → title `🔥 Promo Toko: {N} produk diskon`, url `/products`. Body menyebut diskon terbesar `s/d {maxPercent}%` (persen tertinggi across item; bila harga asli 0/tak ada → item itu dilewati; bila tak ada satu pun persen valid → body tanpa angka).
  - `Announcement` SATU baris: `segment:"all"`, `status:"PUBLISHED"`, `type:"promo"`, `eventType:"product_discount_published"`, `thumbnailUrl` = `items[0].product.imageUrl`, `url` (slug/katalog), `ctaLabel:"Lihat Promo"`, `publishedAt: now`.
  - Push batch sama seperti voucher, `tag:"discount-promo-{id}"`.
- Kedua fungsi fire-and-forget di call-site route admin (`.catch(console.warn)`) — kegagalan push tidak boleh menggagalkan pembuatan promo. Karena flag di-klaim atomik di AWAL, kegagalan setelah klaim = kehilangan 1 push (bukan dobel) — arah guard yang aman.

### Admin create-path (KOREKSI vs audit: dua jalur berbeda)

Verifikasi ke kode: UI admin buat voucher & buat Promo Toko memakai mekanisme berbeda —

- **Voucher = Server Action** `createVoucher` di `app/admin/(protected)/vouchers/new/page.tsx:10-160` (bukan `app/api/admin/vouchers/route.ts` POST; route itu jalur programatik terpisah, TIDAK dipakai form UI). Server action **membaca `startsAt`** (`:54-55`, default `new Date()`) → voucher terjadwal DIDUKUNG. Tambah: baca checkbox `formData.get("notifyCustomers") === "on"`. Setelah `prisma.voucher.create` (`:131`, tambah `notifyAtStart` ke `data`, dan `select id/isActive/startsAt/expiresAt` — saat ini create tak select, jadi tambahkan `select`), lalu (fire-and-forget, sebelum `redirect`): bila `notifyCustomers && isActive && startsAt <= now && (expiresAt null || expiresAt > now)` → `void sendVoucherPromoPush(voucher.id).catch(...)`; bila `startsAt > now` → tak kirim (cron yang urus). `redirect` dari Next.js melempar — panggil push SEBELUM redirect.
- **Promo Toko = POST route** `app/api/admin/discounts/promo-toko/route.ts:95-214` (dipanggil `components/admin/PromoTokoForm.tsx:250` via `fetch`). Body pakai Zod `createSchema` (`:31-37`) — tambah `notifyCustomers: z.boolean().default(false)` ke schema. Setelah `prisma.productDiscount.create` (`:192`, tambah `notifyAtStart` ke `data`): bila `notifyCustomers && startsAt <= now < endsAt` → `void sendProductDiscountPromoPush(discount.id).catch(...)`; bila `startsAt > now` → cron yang urus. (`isActive` selalu `true` saat create `:197`.)
- Form JSX: voucher → tambah checkbox `name="notifyCustomers"` di `<form>` (`page.tsx` ~:178+); Promo Toko → tambah state + kirim di body `fetch` (`PromoTokoForm.tsx`). Teks: "Beri tahu pelanggan — kirim notifikasi & push ke semua pelanggan saat promo aktif." Default OFF.
- Edit/PATCH promo: di luar scope (checkbox hanya di create; klaim atomik `promoNotifiedAt` tetap melindungi dari kirim-ulang).

### Cron `app/api/cron/promo-notify/route.ts`

- Auth `Bearer ${CRON_SECRET}` (pola `order-confirm-reminder/route.ts:37-42`, soft-skip bila env kosong). Daftarkan di `vercel.json` `"crons"` (array `{path,schedule}`, 13 entri existing) dgn schedule `"0 * * * *"` (tiap jam); `functions` cron `maxDuration:60` sudah ada.
- Query (helper murni teruji `isPromoDue(row, now)`): Voucher `notifyAtStart && promoNotifiedAt: null && isActive && startsAt <= now && (expiresAt null || > now)`; ProductDiscount analog dengan `startsAt <= now && endsAt > now`. Limit batch 20 per run (anti-timeout).
- Panggil fungsi kirim per baris; **klaim atomik di dalam fungsi** (`updateMany where promoNotifiedAt:null`) menjamin idempotensi meski route + cron menyentuh baris yang sama.

### Admin web form

- Form buat voucher + form buat Promo Toko: checkbox **"Beri tahu pelanggan"** dengan teks bantu "Kirim notifikasi & push ke semua pelanggan saat promo aktif." Default tidak dicentang. (Presentasi mengikuti primitive form admin yang ada; tanpa perubahan lain.)

### Client Flutter (butuh rilis app)

- Ilustrasi voucher = **ikon di avatar KIRI** (`_NotificationVisual`, lingkaran ber-tint yang sudah jadi mekanisme visual existing), **dibedakan dari `eventType`**, bukan `data` (baris lonceng tak punya `data` map). Voucher tak punya foto konten → slot thumbnail kanan tetap kosong (tak berubah). Sisipkan cabang di `_NotificationVisual.from` (`notifications_screen.dart:1216`) SEBELUM cabang `_isVoucherNotification` generik:
  - `eventType == 'voucher_freeship_published'` → `icon: Icons.local_shipping_rounded`, warna biru brand, label "Gratis Ongkir".
  - `eventType == 'voucher_discount_published'` → `icon: Icons.sell_rounded` (tag diskon), warna hijau voucher existing `Color(0xFF16A34A)`, label "Voucher".
  - Cabang voucher generik existing (`:1243`) tetap sebagai fallback untuk voucher lama tanpa eventType baru.
- Routing: `url` server presisi (`/member/vouchers`, `/produk/{slug}`, `/products`). `_navigateForNotification`: `/member/vouchers` → `pushNamed('/member/vouchers')` (rute no-arg sudah ada `main.dart:429`). `/produk/{slug}` → **fetch-by-slug dulu** (`fetchProductBySlug` `notifications_screen.dart:420`, pola sama `deep_link_service.dart:253-269`) lalu `pushNamed('/produk'/detail, arguments: Product)` — produk detail butuh objek `Product`, bukan slug mentah (`main.dart:433/439`). Ini kerja BARU, bukan cabang existing. `/products` → rute katalog existing.
- **App lama (tanpa rilis)**: notif tetap tampil (title/body/ikon kategori promo), tap mengikuti fallback url — degradasi anggun; ilustrasi & routing presisi menyusul saat rilis.

## Testing

- Backend unit (`tsx --test`): `buildVoucherPromoContent` (free-shipping → `eventType:voucher_freeship_published`; diskon % vs nominal → `voucher_discount_published`; body menyebut kode), `buildDiscountPromoContent` (1 vs N item; url slug vs katalog; `maxPercent` dihitung dari `product.price`/`variant.price` vs `discountedPrice`, termasuk kasus harga asli 0/absen → item dilewati / body tanpa angka), `isPromoDue(row, now)` (voucher & discount, batas periode).
- Idempotensi: klaim atomik — uji bahwa pemanggilan kedua (setelah `promoNotifiedAt` terisi) menghasilkan `updateMany count 0` → tidak ada push (mock prisma/dispatch, atau uji predicate murni).
- Flutter widget: `voucher_freeship_published` → ikon truk (bukan network image); `voucher_discount_published` → ikon %; `product_discount_published` dgn thumbnailUrl → foto produk; routing tap voucher → pushNamed `/member/vouchers` (fake navigator).
- Regression: pembuatan voucher/promo TANPA checkbox → tidak ada Announcement/push baru.

## Out of Scope

- Notif tertarget wishlist/keranjang ("produk di wishlist-mu turun harga") — fase lanjutan bila diminta.
- Re-notify saat promo diedit/diperpanjang.
- Banner campaign upload admin.
- Notif untuk `eligibleBrandIds` khusus follower brand.

## Urutan Deploy

1. Migration deploy (kolom baru, backward compatible).
2. Backend + admin web deploy → notif lonceng + push langsung jalan (app lama: tampil polos, url fallback).
3. Rilis app Flutter → ilustrasi voucher + routing presisi.

## Acceptance Criteria

1. Admin buat voucher aktif + centang → **semua user** (`segment:"all"`, bukan hanya pembeli) dapat push (kategori promo, ter-filter preferensi) + 1 notif lonceng ber-`status:"PUBLISHED"`; tap → halaman voucher; app baru menampilkan ilustrasi truk (gratis ongkir) / % (diskon) sesuai `eventType`.
2. Admin buat Promo Toko aktif + centang → notif dengan foto produk pertama; tap → detail produk (1 item) / katalog (banyak).
3. Promo Toko terjadwal + centang → notif keluar saat promo mulai (cron), **tepat sekali** (klaim atomik `updateMany where promoNotifiedAt:null`, aman terhadap race route+cron).
4. Tanpa centang → tidak ada notif (perilaku hari ini).
5. Push menghormati preferensi kategori promo user (#188).
