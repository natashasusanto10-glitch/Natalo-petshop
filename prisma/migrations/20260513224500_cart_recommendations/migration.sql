CREATE TABLE IF NOT EXISTS "user_product_views" (
  "id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "product_id" TEXT NOT NULL,
  "viewed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "user_product_views_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "product_recommendation_rules" (
  "id" TEXT NOT NULL,
  "source_product_id" TEXT NOT NULL,
  "recommended_product_id" TEXT NOT NULL,
  "relation_type" TEXT NOT NULL DEFAULT 'complementary',
  "priority" INTEGER NOT NULL DEFAULT 0,
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "product_recommendation_rules_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "user_product_views_user_id_product_id_key"
  ON "user_product_views"("user_id", "product_id");
CREATE INDEX IF NOT EXISTS "user_product_views_user_id_viewed_at_idx"
  ON "user_product_views"("user_id", "viewed_at");
CREATE INDEX IF NOT EXISTS "user_product_views_product_id_idx"
  ON "user_product_views"("product_id");

CREATE UNIQUE INDEX IF NOT EXISTS "product_recommendation_rules_source_product_id_recommended_product_id_relation_type_key"
  ON "product_recommendation_rules"("source_product_id", "recommended_product_id", "relation_type");
CREATE INDEX IF NOT EXISTS "product_recommendation_rules_source_product_id_is_active_priority_idx"
  ON "product_recommendation_rules"("source_product_id", "is_active", "priority");
CREATE INDEX IF NOT EXISTS "product_recommendation_rules_recommended_product_id_idx"
  ON "product_recommendation_rules"("recommended_product_id");

ALTER TABLE "user_product_views"
  ADD CONSTRAINT "user_product_views_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "user_product_views"
  ADD CONSTRAINT "user_product_views_product_id_fkey"
  FOREIGN KEY ("product_id") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product_recommendation_rules"
  ADD CONSTRAINT "product_recommendation_rules_source_product_id_fkey"
  FOREIGN KEY ("source_product_id") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "product_recommendation_rules"
  ADD CONSTRAINT "product_recommendation_rules_recommended_product_id_fkey"
  FOREIGN KEY ("recommended_product_id") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;
