-- Tambah promoPrice column ke FeedPostProduct supaya admin bisa set
-- discount per-product di video PROMO (bukan single discount per post).
-- Original price tetap ambil dari Product.price (no denormalize).

ALTER TABLE "FeedPostProduct" ADD COLUMN "promoPrice" INTEGER;
