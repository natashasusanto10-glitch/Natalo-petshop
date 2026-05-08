# Vercel Deployment

## Project Settings

- Framework Preset: Next.js
- Install Command: `npm ci`
- Build Command: `npm run build`
- Output Directory: Next.js default

The build script runs:

```bash
prisma generate && prisma migrate deploy && next build
```

That means Vercel must have database access during build, and `DATABASE_URL` / `DIRECT_URL` must point to the production database.

## Required Environment Variables

Set these in Vercel Project Settings -> Environment Variables for Production:

```env
SESSION_SECRET=
ADMIN_EMAIL=
ADMIN_PASSWORD=

DATABASE_URL=
DIRECT_URL=

NEXT_PUBLIC_SITE_URL=https://natalopetshop.com
NEXT_PUBLIC_BRAND_NAME=Natalo Petshop & Aquarium Official Store
NEXT_PUBLIC_WHATSAPP_NUMBER=+6281289997113
NEXT_PUBLIC_WA_NUMBER=6281289997113
NEXT_PUBLIC_STORE_ADDRESS=Jl. MT Haryono No. 103 D Medan

MIDTRANS_SERVER_KEY=
MIDTRANS_CLIENT_KEY=
MIDTRANS_IS_PRODUCTION=true
NEXT_PUBLIC_MIDTRANS_CLIENT_KEY=
NEXT_PUBLIC_MIDTRANS_IS_PRODUCTION=true

BITESHIP_API_KEY=
SHOP_ORIGIN_CONTACT_NAME=Natalo Petshop
SHOP_ORIGIN_CONTACT_PHONE=6281289997113
SHOP_ORIGIN_ADDRESS=Jl. MT Haryono No. 103 D Medan
SHOP_ORIGIN_NOTE=Pickup di titik Google Maps Sinar Aquarium
SHOP_ORIGIN_LATITUDE=3.5884775
SHOP_ORIGIN_LONGITUDE=98.6890277
SHOP_ORIGIN_POSTAL_CODE=20212
SHOP_ORIGIN_AREA_ID=

NEXT_PUBLIC_GOOGLE_MAPS_KEY=
UPLOADTHING_TOKEN=

RESEND_API_KEY=
RESEND_FROM=

OPENAI_API_KEY=
OPENAI_MODEL=gpt-5.5

MEILISEARCH_HOST=
MEILISEARCH_API_KEY=
MEILISEARCH_INDEX=products
```

Optional payment provider:

```env
XENDIT_SECRET_KEY=
XENDIT_CALLBACK_TOKEN=
```

Optional bank display:

```env
NEXT_PUBLIC_BANK_BCA_NO=
NEXT_PUBLIC_BANK_NAMA=
```

## Webhook URLs

Configure Midtrans notification URL:

```text
https://natalopetshop.com/api/payment/midtrans
```

If using Xendit:

```text
https://natalopetshop.com/api/payment/xendit
```

## Deploy Steps

1. Push this repository to GitHub.
2. Import the repository in Vercel.
3. Add all production environment variables above.
4. Deploy.
5. In Vercel, assign the production domain `natalopetshop.com`.
6. Redeploy after any environment variable changes.

## Production Smoke Tests

After deployment:

```bash
curl https://natalopetshop.com/checkout
curl -X POST https://natalopetshop.com/api/shipping/rates \
  -H "Content-Type: application/json" \
  -d "{\"destinationPostalCode\":\"20212\",\"destinationLatitude\":3.59,\"destinationLongitude\":98.69,\"items\":[{\"name\":\"Test\",\"price\":10000,\"weightGram\":500,\"quantity\":1}]}"
```

Expected shipping result should come from Biteship, not dummy rates.
