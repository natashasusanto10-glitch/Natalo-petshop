# Natalo Petshop — Web Desktop Redesign, Fase 1

**Tanggal:** 2026-07-04
**Status:** Disetujui (design), menunggu review spec sebelum implementasi
**Cakupan:** Fondasi design-system + Homepage + Header/Footer desktop

---

## 0. Konteks penting

- Website `www.natalopetshop.com` dilayani oleh **aplikasi Next.js** (App Router + React + Tailwind v4 + Prisma) di Vercel — **bukan Flutter Web**.
- Aplikasi Flutter (`flutter_app/`) adalah **native iOS/Android saja** dan **tidak tersentuh** dalam pekerjaan ini.
- Seluruh pekerjaan Fase 1 berada di codebase Next.js (root repo): `app/`, `components/`, `app/globals.css`.

## 1. Masalah awal (hasil audit)

1. **Homepage tanpa container max-width** — semua section full-bleed (`px-4` saja) → di desktop kartu produk mobile-size mengambang, kesan "mobile diperlebar". (`app/page.tsx`)
2. **Grid produk tidak konsisten / sebagian tidak responsif** — "Rekomendasi" fix `grid-cols-2`, "Flash Sale" fix `grid-cols-3` di semua breakpoint.
3. **Tidak ada desktop navigation e-commerce** — header desktop hanya 4 link (Beranda/Produk/Feed/Tentang), tanpa announcement bar, tanpa nav kategori/brand. (`components/Header.tsx:349`)
4. **Design system belum lengkap** — token warna `natalo-*` ada, tapi tidak ada skala spacing/radius/shadow; ~239 `text-[Npx]` + 50+ hex hardcode; tidak ada primitive Button/Input/Card/Heading.
5. **Duplikasi ProductCard** — `components/ProductCard.tsx` vs `components/home/HomeProductCard.tsx` ~95% identik.

Basis bagus yang sudah ada: Search page punya sidebar filter desktop; Footer responsif 4-kolom; `next/image` + blur placeholder; bottom nav sudah `md:hidden`.

## 2. Keputusan yang sudah disepakati

| Topik | Keputusan |
|---|---|
| Cakupan Fase 1 | Fondasi design-system + Homepage + Header/Footer desktop |
| Pendekatan | **Opsi A** — layer responsif tipis di atas kode existing (primitive baru + token, refactor bertahap). Bukan rewrite. |
| Header nav | Nav kategori **data-driven** (dari API kategori existing) + dropdown ringkas; link tetap Brand/Promo/Terlaris/Produk Baru |
| Max-width konten | **1280px** (`xl`) |
| Mobile web | **Boleh dipoles** (spacing/tipografi/kartu), selain peningkatan desktop |
| Flutter native app | Tidak tersentuh |

## 3. Prinsip & batasan

- Tidak mengubah endpoint API, schema DB, payment flow, autentikasi, atau logic transaksi (voucher, poin, ongkir, checkout).
- Tidak menghapus fitur existing.
- Tidak hardcode data produk/kategori/harga/promo/kontak — pakai sumber existing.
- Refactor bertahap & reversible; primitive lama tetap jalan, diganti per-area yang disentuh.
- Null safety, lint bersih, hindari duplikasi.

## 4. Desain per bagian

### Bagian 1 — Design tokens & responsive primitives

**`app/globals.css` `@theme`:**
- Breakpoints eksplisit: `xs 380`, `sm 640`, `md 768`, `lg 1024`, `xl 1280`, `2xl 1440`.
- Spacing scale section: mis. `--space-gutter`, `--space-section` (dipakai konsisten antar section).
- Radius scale: `--radius-sm/md/lg/xl` (menggantikan `rounded-[18px]` acak).
- Shadow/elevation scale: `--shadow-card`, `--shadow-card-hover`, `--shadow-pop` (menyatukan shadow inline).

**`components/ui/` (baru):**
- `PageContainer` — `mx-auto w-full` + **max-width 1280px** + padding responsif. Satu sumber lebar konten.
- `ResponsiveGrid` — grid produk terpadu: **mobile 2 / sm 3 / lg 4 / xl 5** kolom (prop override), gutter dari token.
- `SectionHeader` — judul + subjudul opsional + link "Lihat Semua" konsisten.
- `Button` — varian `primary/secondary/ghost` + size.

Primitive dipakai di area Fase 1; sisanya menyusul fase berikutnya.

### Bagian 2 — Header desktop 3-tingkat

Refactor `components/Header.tsx`: di `md+` merender struktur e-commerce web; render mobile existing dipertahankan lalu dipoles ringan. Conditional per-route existing **tidak diubah** — hanya menambah lapisan desktop pada cabang yang sudah merender header.

1. **Announcement bar** (`md+`, tipis ±34px): "Gratis ongkir area Medan" · "100% Produk Original" · "Chat admin WhatsApp". WA link dari `NEXT_PUBLIC_WHATSAPP_NUMBER` (pola sama Footer). Warna `natalo-500`. Tidak sticky.
2. **Main header**: logo · **search bar besar di tengah (selalu tampil di desktop, semua halaman)** reuse `HomeSearchBar`/`SearchBar` · kanan: Wishlist, NotificationBell (member), CartCount+badge, tombol Masuk/avatar. CTA download app tidak ditonjolkan.
3. **Navigation bar** (`md+`, data-driven): kategori utama dari API kategori existing (cache/prefetch) + hover dropdown ringkas; diikuti link tetap Brand · Promo · Terlaris · Produk Baru (mengarah ke `/products` + query/filter existing, tanpa endpoint baru). Main header + nav sticky saat scroll.

### Bagian 3 — Homepage (`app/page.tsx`)

Semua section dibungkus `PageContainer` (kecuali hero full-width terkontrol). Urutan:
1. Hero — `HeroBanner` existing, rasio desktop profesional, tinggi dibatasi, skeleton.
2. Shortcut kategori populer — rail ikon rapi (bukan lompat 3→6).
3. Promo / voucher.
4. Produk terlaris — horizontal rail dengan panah navigasi hover (desktop).
5. Brand favorit — grid logo (`mapDbBrandsToCatalogItems`).
6. Kategori populer — grid.
7. Produk rekomendasi — `ResponsiveGrid` (ganti `grid-cols-2` fix).
8. Trust section — reuse `TrustMarquee`/`trustItems`.
9. Footer.

Tiap section pakai `SectionHeader`; spacing dari token; rail vs grid berselang-seling agar tidak monoton. Data dari sumber existing.

### Bagian 4 — Unify ProductCard

Gabung `HomeProductCard` ke `ProductCard.tsx` (prop `variant`). Kartu final: rasio gambar konsisten + skeleton, badge diskon, nama 2 baris ellipsis, harga utama menonjol + coret + %, rating/terjual bila ada, badge stok, **hover elegan desktop** (elevasi + quick "＋ Keranjang"), radius/shadow dari token. Konsumen existing tetap kompatibel.

### Bagian 5 — Footer & mobile polish

- Footer: rapikan spacing/tipografi via token; pastikan lengkap (Tentang · CS/WA · Kebijakan · Sosial · trust). Tanpa rombak besar.
- Mobile web: poles spacing, tipografi, kartu produk agar konsisten dengan token baru.

## 5. Verifikasi (wajib sebelum klaim selesai)

1. `npm run lint` bersih.
2. `npm run build` sukses.
3. Preview visual pada 375 / 768 / 1024 / 1280 / 1440 / 1920 px — homepage & header, tanpa overflow/layout shift.
4. Screenshot before/after desktop + mobile.
5. Konfirmasi tidak ada endpoint/logic transaksi tersentuh.

## 6. Risiko & kompatibilitas

- Header lintas-route dengan banyak conditional — mitigasi: hanya menambah cabang desktop, tidak mengubah logika hide/show existing.
- Cart/checkout/voucher/poin logic tidak disentuh.
- Flutter native app tidak tersentuh.
- Primitive baru bersifat aditif; refactor per-area agar reversible.

## 7. Di luar cakupan Fase 1 (fase berikutnya)

Listing/kategori/search desktop mendalam; product detail (galeri kiri + sticky purchase panel); cart/checkout desktop; SEO lanjutan; performance optimization; analytics/A-B testing.
