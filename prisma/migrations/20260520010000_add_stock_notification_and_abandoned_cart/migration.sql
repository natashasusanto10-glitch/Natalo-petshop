-- Migration: Stock Notification (pre-order out-of-stock) + Abandoned Cart push
-- Date: 2026-05-20
--
-- Adds:
--   1. CartItem.notifiedAbandonedAt — tracks last abandoned-cart push timestamp
--      per cart item. Cron query uses this to skip already-notified items.
--   2. StockNotification table — user subscriptions for "notify when back in
--      stock" on out-of-stock products / variants.
--
-- Idempotent: uses IF NOT EXISTS for ADD COLUMN + CREATE TABLE.

-- 1. CartItem: tambah notifiedAbandonedAt column
ALTER TABLE "CartItem"
  ADD COLUMN IF NOT EXISTS "notifiedAbandonedAt" TIMESTAMP(3);

-- Index untuk cron query (filter by notifiedAt IS NULL + createdAt range).
CREATE INDEX IF NOT EXISTS "CartItem_notifiedAbandonedAt_createdAt_idx"
  ON "CartItem" ("notifiedAbandonedAt", "createdAt");

-- 2. StockNotification table
CREATE TABLE IF NOT EXISTS "StockNotification" (
  "id"         TEXT NOT NULL,
  "userId"     TEXT NOT NULL,
  "productId"  TEXT NOT NULL,
  "variantId"  TEXT,
  "createdAt"  TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "notifiedAt" TIMESTAMP(3),

  CONSTRAINT "StockNotification_pkey" PRIMARY KEY ("id")
);

-- Foreign keys
ALTER TABLE "StockNotification"
  DROP CONSTRAINT IF EXISTS "StockNotification_userId_fkey";
ALTER TABLE "StockNotification"
  ADD CONSTRAINT "StockNotification_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "StockNotification"
  DROP CONSTRAINT IF EXISTS "StockNotification_productId_fkey";
ALTER TABLE "StockNotification"
  ADD CONSTRAINT "StockNotification_productId_fkey"
  FOREIGN KEY ("productId") REFERENCES "Product"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "StockNotification"
  DROP CONSTRAINT IF EXISTS "StockNotification_variantId_fkey";
ALTER TABLE "StockNotification"
  ADD CONSTRAINT "StockNotification_variantId_fkey"
  FOREIGN KEY ("variantId") REFERENCES "ProductVariant"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

-- Unique: (user, product, variant) — re-subscribe = upsert (reset notifiedAt).
-- NULL handling: Postgres treats NULL in unique as distinct, jadi user yang
-- subscribe ke product tanpa variant + product dengan variant tertentu OK.
CREATE UNIQUE INDEX IF NOT EXISTS "StockNotification_userId_productId_variantId_key"
  ON "StockNotification" ("userId", "productId", "variantId");

-- Indexes untuk restock-trigger query (cari subscriber by productId/variantId
-- yang belum di-notify).
CREATE INDEX IF NOT EXISTS "StockNotification_productId_notifiedAt_idx"
  ON "StockNotification" ("productId", "notifiedAt");
CREATE INDEX IF NOT EXISTS "StockNotification_variantId_notifiedAt_idx"
  ON "StockNotification" ("variantId", "notifiedAt");
