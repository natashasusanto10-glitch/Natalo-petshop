# Toko PWA Starter

Starter project untuk website toko sendiri / PWA dengan stack:

- Next.js App Router
- PostgreSQL
- Prisma ORM
- Tailwind CSS
- Midtrans
- Biteship
- OpenAI API

Target MVP: customer dari marketplace bisa scan QR, masuk website resmi, daftar member, pakai voucher, checkout, dan repeat order langsung.

## 1. Setup lokal

```bash
cp .env.example .env
npm install
```

Isi `DATABASE_URL` di `.env`, lalu jalankan:

```bash
npx prisma generate
npx prisma migrate dev --name init
npm run prisma:seed
npm run dev
```

Buka:

```bash
http://localhost:3000
```

## 2. Fitur yang sudah ada

- Homepage brand
- Katalog produk
- Detail produk
- Keranjang via localStorage
- Checkout form
- Order creation API
- Voucher basic `MEMBER10`
- Admin dashboard awal `/admin`
- AI product assistant placeholder + OpenAI Responses API
- Biteship rates endpoint dengan fallback dummy
- Midtrans Snap redirect payment dari `/api/orders`

## 3. Environment variables

Lihat `.env.example`.

Minimal untuk development:

```env
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/toko_pwa?schema=public"
NEXT_PUBLIC_SITE_URL="http://localhost:3000"
NEXT_PUBLIC_BRAND_NAME="Nama Brand"
NEXT_PUBLIC_WHATSAPP_NUMBER="6281234567890"
```

Untuk payment/shipping/AI:

```env
MIDTRANS_SERVER_KEY=""
MIDTRANS_CLIENT_KEY=""
MIDTRANS_IS_PRODUCTION="false"
BITESHIP_API_KEY=""
SHOP_ORIGIN_POSTAL_CODE=""
OPENAI_API_KEY=""
OPENAI_MODEL="gpt-5.5"
```

## 4. Rekomendasi build order

1. Rapikan branding: nama toko, warna, logo, foto produk.
2. Finalisasi database produk dan seed.
3. Selesaikan checkout manual dulu.
4. Gunakan Midtrans untuk payment gateway v1.
5. Pilih satu shipping aggregator untuk v1: Biteship **atau** RajaOngkir.
6. Tambahkan webhook payment untuk update status order otomatis.
7. Tambahkan admin auth sebelum production.
8. Tambahkan customer login/member area.
9. Tambahkan WhatsApp CRM/reorder reminder.
10. Tambahkan AI assistant berbasis katalog asli.

## 5. Catatan penting sebelum production

Starter ini belum production-ready. Wajib ditambahkan:

- Authentication untuk admin.
- Rate limiting API.
- Validasi stok saat checkout.
- Webhook Midtrans untuk payment status.
- Logging error.
- Backup database.
- Kebijakan privasi dan syarat penggunaan.
- Validasi alamat/pengiriman.
- Security review.

## 6. Struktur folder

```text
app/
  api/
    ai/product-assistant
    orders
    payment/midtrans
    shipping/rates
  admin
  cart
  checkout
  member
  order-status
  products
components/
lib/
prisma/
public/
```
