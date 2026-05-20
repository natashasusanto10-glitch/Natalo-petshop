/**
 * /admin/diskon/promo-toko/new — Create Promo Toko
 *
 * Server wrapper minimal — render PromoTokoForm client component
 * tanpa initial data (mode create).
 */
import { PromoTokoForm } from "@/components/admin/PromoTokoForm";

export default function PromoTokoNewPage() {
  return <PromoTokoForm />;
}
