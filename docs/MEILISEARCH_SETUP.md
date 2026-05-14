# Meilisearch Setup

Production search di Vercel butuh Meilisearch yang **public-reachable**. Vercel serverless tidak bisa akses `localhost` atau jaringan private.

## Pilihan Hosting

### 1. Meilisearch Cloud (paling cepat) — recommended

- URL: https://cloud.meilisearch.com
- Free tier: 100k dokumen, 1 project
- Build tier: $25/bulan, 1M dokumen
- Sudah HTTPS, master key auto-generated, zero ops

Cocok untuk catalog < 100k SKU. Daftar → buat project → copy host + API key.

### 2. Railway / Fly.io (self-hosted murah)

- Railway: ~$5/bulan untuk 512MB RAM
- Fly.io: free tier 256MB cukup untuk < 5k produk
- Deploy image `getmeili/meilisearch:latest`, set `MEILI_MASTER_KEY`, expose port 7700

Cocok kalau mau full control + sudah pakai platform tersebut.

### 3. VPS sendiri (Hetzner, DigitalOcean, dst.)

- Pakai docker-compose yang sudah ada di repo (lihat `docker-compose.yml`)
- Tambah reverse proxy (Caddy/Nginx) untuk HTTPS
- Lebih murah jangka panjang, tapi ada ops cost

## Setup Checklist

Setelah dapat host + key dari salah satu pilihan di atas:

### 1. Set env di Vercel Dashboard

Vercel → Settings → Environment Variables → Production:

```
MEILISEARCH_HOST=https://your-meili-host.example.com
MEILISEARCH_API_KEY=master-key-dari-provider
MEILISEARCH_INDEX=products
```

### 2. Test koneksi dari lokal

Update `.env` sementara untuk test (atau export env shell), lalu:

```bash
npm run search:check:prod
```

Output yang diharapkan:

```
[OK]  env MEILISEARCH_HOST — https://...
[OK]  env MEILISEARCH_API_KEY — 64 chars
[OK]  GET /health — available
[OK]  API key valid (GET /version) — Meilisearch v1.x
[OK]  Index "products" ada — primaryKey=id
[OK]  Index ada dokumen — 1234 docs
[OK]  Search dummy berhasil — 1234 total hits
```

### 3. Initial setup index + settings

```bash
npm run search:setup:prod
```

Ini buat index `products` + apply settings (searchable fields, filterable, synonyms, dst.).

### 4. Initial reindex semua produk

```bash
npm run search:reindex:prod
```

Aman untuk live traffic — pakai temporary index + atomic swap.

### 5. Redeploy Vercel

Setelah env terisi, trigger redeploy supaya runtime baca env baru.

## Maintenance

- **Tambah produk baru**: sudah auto-sync via `syncProduct()` di admin product create/update (`app/api/admin/products/*`).
- **Bulk import**: gunakan reindex setelah import.
- **Update index settings** (synonyms, dst.): edit `lib/search-document.mjs`, jalankan `npm run search:setup:prod`.
- **Recovery dari corruption / mismatch**: `npm run search:reindex:prod`.

## Troubleshooting

| Symptom | Penyebab umum | Fix |
|---|---|---|
| `fetch failed` / `ECONNREFUSED` | Host salah atau tidak public-reachable | Cek URL dari browser/curl, pastikan HTTPS untuk Vercel |
| `Invalid API key` / 403 | Pakai search key (read-only) padahal butuh admin actions | Pakai master key di `MEILISEARCH_API_KEY` |
| `Index not found` | Belum di-setup | Jalankan `npm run search:setup:prod` |
| `0 documents` | Belum di-reindex | Jalankan `npm run search:reindex:prod` |
| Search jalan, tapi typo tidak ditolerir | Settings belum diapply | Cek `lib/search-document.mjs`, re-run setup |
