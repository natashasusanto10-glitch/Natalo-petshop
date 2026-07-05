-- Target brand untuk voucher (dipilih via picker admin, cocok ke Product.brandId).
-- Sama pola dengan eligibleProductIds/eligibleCategoryIds yang sudah ada.
ALTER TABLE "Voucher"
  ADD COLUMN IF NOT EXISTS "eligibleBrandIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
