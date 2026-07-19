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

Ikuti pola `lib/feed/publish-push.ts` (bukan `push-marketing.ts` per-user): **satu baris `Announcement` ber-`segment`** (tampil di lonceng semua user, murah — bukan N baris per user) + push batch (`sendPushToUser` + `sendFcmToUser`) ke user hasil `resolveSegmentUserIds` (helper sudah ada, `publish-push.ts:31`, batch 50).

### Skema (migration SQL tulis-tangan, `IF NOT EXISTS`)

```sql
ALTER TABLE "Voucher"
ADD COLUMN IF NOT EXISTS "notifyAtStart" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS "promoNotifiedAt" TIMESTAMP(3);

ALTER TABLE "ProductDiscount"
ADD COLUMN IF NOT EXISTS "notifyAtStart" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS "promoNotifiedAt" TIMESTAMP(3);
```

- `notifyAtStart` = admin mencentang checkbox. `promoNotifiedAt` = guard anti-dobel (cron/route hanya kirim bila null).
- Field waktu yang dipakai: Voucher `startsAt`/`expiresAt` (`schema.prisma:801-802`), ProductDiscount `startsAt`/`endsAt` (:726-727), keduanya + `isActive`.

### `lib/push-promo.ts` (modul baru)

- `sendVoucherPromoPush(voucherId)`:
  - Ambil voucher (`name, code, kind, discountPercent, discountAmount, isActive, startsAt, expiresAt, promoNotifiedAt`). Skip bila `promoNotifiedAt != null` atau tidak aktif/kedaluwarsa.
  - Judul/body via builder murni teruji `buildVoucherPromoContent(voucher)`:
    - `kind === "FREE_SHIPPING"` → title `🚚 Gratis Ongkir dari Natalo!`, body `Voucher gratis ongkir {code} sudah aktif. Klaim sekarang sebelum habis!`
    - selain itu → title `🎟️ Voucher diskon baru buat kamu`, body menyebut nilai (`Diskon {percent}%` / `Potongan Rp{amount}`) + kode.
  - `Announcement` SATU baris: `segment:"members"`, `type:"promo"`, `eventType:"voucher_published"`, `url:"/member/vouchers"`, `thumbnailUrl:null`, `ctaLabel:"Lihat Voucher"`, `publishedAt: now`. (Kolom `eventType` sudah ada di `Announcement`.)
  - Push batch ke `resolveSegmentUserIds("members")` dengan `PushPayload` ber-`prefCategory:"promo"` (**WAJIB** — gate preferensi #188), `data.type:"voucher_published"`, `data.voucherKind`, `tag:"voucher-promo-{id}"`.
  - Set `promoNotifiedAt` SEBELUM dispatch push (kompensasi crash = kehilangan 1 push, bukan dobel — konsisten arah guard yang aman).
- `sendProductDiscountPromoPush(discountId)`:
  - Ambil discount + `items` (join `product { name, slug, imageUrl }`), skip bila `promoNotifiedAt != null` / tidak aktif / di luar periode.
  - Builder murni `buildDiscountPromoContent(discount, items)`:
    - 1 item → title `🔥 {productName} lagi diskon!`, url `/produk/{slug}`.
    - >1 item → title `🔥 Promo Toko: {N} produk diskon`, url `/products`. Body menyebut diskon terbesar (`s/d {maxPercent}%` dihitung dari harga coret vs harga promo per item — bila persen tak bisa dihitung, body tanpa angka).
  - `Announcement` SATU baris: `segment:"members"`, `type:"promo"`, `eventType:"product_discount_published"`, `thumbnailUrl` = `items[0].product.imageUrl`, `ctaLabel:"Lihat Promo"`.
  - Push batch sama seperti voucher, `tag:"discount-promo-{id}"`.
- Kedua fungsi fire-and-forget di call-site route admin (`.catch(console.warn)`) — kegagalan push tidak boleh menggagalkan pembuatan promo.

### Route admin

- `app/api/admin/vouchers/route.ts` POST: terima `notifyCustomers?: boolean`. Simpan `notifyAtStart`. Setelah create: bila `notifyCustomers && isActive && startsAt <= now` → panggil `sendVoucherPromoPush` langsung; bila `startsAt > now` → biarkan cron.
- `app/api/admin/discounts/promo-toko/route.ts` POST: sama (`startsAt <= now <= endsAt` → kirim langsung).
- PATCH/PUT edit promo: di luar scope (checkbox hanya di create; edit tidak memicu ulang — `promoNotifiedAt` guard tetap melindungi).

### Cron `app/api/cron/promo-notify/route.ts`

- Auth `CRON_SECRET` (pola `order-confirm-reminder`). Dijadwalkan tiap jam (vercel.json ikut pola cron lain).
- Query: Voucher `notifyAtStart && promoNotifiedAt: null && isActive && startsAt <= now && (expiresAt null || > now)`; ProductDiscount analog dengan `endsAt > now`. Limit batch 20 per run (anti-timeout).
- Panggil fungsi kirim per baris; fungsi sendiri yang set `promoNotifiedAt` (idempotent, aman dipanggil dobel oleh route + cron).

### Admin web form

- Form buat voucher + form buat Promo Toko: checkbox **"Beri tahu pelanggan"** dengan teks bantu "Kirim notifikasi & push ke semua member saat promo mulai." Default tidak dicentang. (Presentasi mengikuti primitive form admin yang ada; tanpa perubahan lain.)

### Client Flutter (butuh rilis app)

- `NotificationRow`: bila `eventType == 'voucher_published'` → slot thumbnail kanan menampilkan **ilustrasi kartu voucher** yang digambar lokal (widget baru kecil, token `NataloColors`): latar tint biru + ikon `local_shipping_rounded` untuk `data.voucherKind == 'FREE_SHIPPING'` (fallback: deteksi dari title mengandung "Gratis Ongkir"), ikon `percent_rounded` untuk lainnya. Ukuran sama dgn slot thumbnail (radius sama).
- Routing: `url` dari server sudah presisi (`/member/vouchers`, `/produk/{slug}`, `/products`) — pastikan `_navigateForNotification` menangani `/member/vouchers` dan `/produk/{slug}` (cek: rute produk by-slug perlu fetch product dulu ala deep-link; ikuti pola `deep_link_service`).
- **App lama (tanpa rilis)**: notif tetap tampil (title/body/ikon kategori promo), tap mengikuti fallback url — degradasi anggun; ilustrasi & routing presisi menyusul saat rilis.

## Testing

- Backend unit (`tsx --test`): `buildVoucherPromoContent` (free-shipping vs diskon %, vs nominal; body menyebut kode), `buildDiscountPromoContent` (1 vs N item; url slug vs katalog; maxPercent), guard `promoNotifiedAt` (fungsi skip bila sudah terisi — uji via builder/predicate murni `shouldSendPromo(row, now)`).
- Cron: predicate query teruji via helper murni `isPromoDue(row, now)` (voucher & discount).
- Flutter widget: notif `voucher_published` → ilustrasi voucher tampil (bukan network image); `product_discount_published` dgn thumbnailUrl → foto produk; routing tap voucher → pushNamed `/member/vouchers` (fake navigator).
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

1. Admin buat voucher aktif + centang → semua member dapat push (kategori promo, ter-filter preferensi) + 1 notif lonceng; tap → halaman voucher; app baru menampilkan ilustrasi (truk untuk gratis ongkir).
2. Admin buat Promo Toko aktif + centang → notif dengan foto produk pertama; tap → detail produk (1 item) / katalog (banyak).
3. Promo terjadwal + centang → notif keluar saat promo mulai (cron), tepat sekali (`promoNotifiedAt` guard).
4. Tanpa centang → tidak ada notif (perilaku hari ini).
5. Push menghormati preferensi kategori promo user (#188).
