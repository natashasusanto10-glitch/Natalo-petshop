# Natalo Social Service

NestJS service untuk fitur sosial V1. Service ini berbagi database Prisma dengan Next.js, tetapi bisa dideploy terpisah.

## Scripts

```bash
npm run social:dev
npm run social:env:check
npm run social:build
npm run social:start
```

## Environment

- `DATABASE_URL` — sama dengan Next.js
- `DIRECT_URL` — sama dengan Next.js
- `SESSION_SECRET` — sama dengan Next.js supaya token login Flutter valid
- `SOCIAL_SERVICE_PORT` atau `PORT`

Saat dijalankan lokal, service otomatis membaca env yang belum ada dari:

1. `.env.local`
2. `.env.production.local`
3. `.env`

Env yang sudah disuntik oleh hosting tidak dioverride.

Kalau file lokal masih kosong, pull env production dulu:

```bash
vercel link
vercel env pull .env.production.local --environment=production
npm run social:env:check
```

Flutter bisa diarahkan ke service ini dengan dart define:

```bash
--dart-define=SOCIAL_API_BASE_URL=https://social-api.example.com
```
