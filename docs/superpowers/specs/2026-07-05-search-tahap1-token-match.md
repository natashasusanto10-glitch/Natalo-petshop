# Search Engine — Tahap 1: Token-Based Matching di `/api/products`

Status: Approved
Bagian dari: Deep Search Audit (lihat percakapan sesi 2026-07-05). Tahap 1 dari 3 (Tahap 2: toleransi typo, Tahap 3: normalisasi berat).

## Latar belakang

Audit menyeluruh terhadap search engine (Flutter client, API routes, Prisma query, ranking) menemukan tiga implementasi search yang berbeda:

| Path | Endpoint | Logika | Dipakai oleh |
|---|---|---|---|
| Autocomplete | `/api/search/suggest` | Token + trigram di `searchText` | Dropdown saran saat mengetik |
| Hasil pencarian (grid) | `/api/products` | `name: { contains: query }` — substring utuh, hanya kolom `name` | Halaman Produk |
| (Tidak dipakai UI) | `/api/search` | Token-AND + trigram + facet | — |

**Root cause bug**: query multi-kata seperti "whiskas tuna" bukan substring bersambung dari "Whiskas **Adult** Tuna", sehingga `/api/products` mengembalikan 0 hasil walau autocomplete berhasil menemukannya. Dibuktikan langsung ke API produksi:

```
GET /api/products?search=whiskas%20tuna   → total: 0
GET /api/search?q=whiskas%20tuna          → menemukan semua varian Whiskas Adult Tuna
```

Rencana awal (mengarahkan halaman hasil ke `/api/search`) dibatalkan setelah verifikasi: bentuk respons `/api/search` (snake_case, tanpa `voucherPreview`/`gallery`, field harga `price_min`/`price_max`) sama sekali berbeda dari `/api/products` (camelCase, kaya data UI voucher/gallery yang dipakai `Product.fromJson` di Flutter). Mengganti endpoint akan meregresi tampilan badge voucher & gambar di grid produk.

## Keputusan desain

Perbaiki **logika matching** di `/api/products`, bukan ganti endpoint. Bentuk respons tidak berubah sama sekali → nol risiko ke Flutter `Product.fromJson`, badge voucher, gallery.

Reuse fungsi `productSearchWhere()` yang sudah ada dan terbukti benar di `lib/search.ts:257` (dipakai `/api/search`) — token per kata, tiap token harus match (AND) di `name` ATAU `brand.name` ATAU SKU varian ATAU nilai opsi varian (OR per token).

## Perubahan

1. **`lib/search.ts`** — export `productSearchWhere` (saat ini private/tidak diekspor) supaya bisa dipakai ulang dari `lib/products.ts`. Satu sumber logika, hindari duplikasi/divergensi di masa depan.

2. **`lib/products.ts`**, fungsi `buildProductWhere()` (~baris 895-1010):
   - Hapus baris `...(search ? { name: { contains: search, mode: "insensitive" } } : {})`.
   - Sebagai gantinya, **push** hasil `productSearchWhere(search)` ke array `and: Prisma.ProductWhereInput[]` yang sudah ada di fungsi ini — **bukan** di-spread sebagai key `AND` terpisah di object literal return. Alasan: return statement sudah punya `...(and.length ? { AND: and } : {})` di baris akhir; kalau `productSearchWhere()` (yang bentuknya `{ AND: [...] }`) di-spread sebagai key terpisah SEBELUM baris itu, key `AND`-nya akan tertimpa/hilang oleh spread `and[]` berikutnya (object spread: key belakangan menang). Push ke `and[]` menghindari collision ini dan otomatis ter-gabung dengan filter lain (inStock, discount, dst) via `AND` gabungan yang sama.

## Non-goals (ditunda ke tahap berikut)

- Ranking relevansi (skor berdasarkan exact match / posisi kata / dst) — Tahap lanjutan.
- Toleransi typo ("hapy dog" → 0 hasil saat ini) — Tahap 2.
- Normalisasi format berat ("15 kg" vs "15kg") — Tahap 3.
- Filter sinonim client-side (`SearchSynonyms.matches` di `products_screen.dart`) — dibiarkan apa adanya untuk saat ini, jadi lapisan tambahan yang makin jarang berdampak karena server sudah lebih pintar.

## Testing

Verifikasi via `next build` lokal (type-check harus lulus — pelajaran dari insiden deploy sebelumnya) lalu curl matriks kasus yang sama persis ke `/api/products` (bukan `/api/search`) setelah deploy:

`whiskas tuna`, `happy sensible`, `happy dog 15kg`, `happy 15kg`, `15kg happy`, `proplan`, `pro plan`, `rc`, `royal`, `royal canin`, `whiskas kitten`, `kitten whiskas`, `cat food royal`, `makanan kucing rc`.

Target: semua mengembalikan `total > 0` dengan produk yang relevan tampil, dan bentuk field respons (`imageUrl`, `voucherPreview`, dll) tidak berubah dibanding sebelum perubahan.

## Risiko & rollback

Risiko rendah: satu fungsi diekspor, satu blok logika diganti di satu file, bentuk data API tidak disentuh. Rollback = revert satu commit.
