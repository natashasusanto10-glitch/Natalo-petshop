import { z } from "zod";

// Schema: Buat brand baru inline dari BrandCombobox (Tambah/Edit Produk).
export const createBrandSchema = z.object({
  name: z.string().trim().min(1, "Nama brand wajib diisi").max(100),
});

// Slugify — identik dengan slugify() di app/admin/(protected)/brands/page.tsx
// (duplikasi disengaja, ikuti konvensi kodebase: tidak ada shared util).
export function slugifyBrandName(name: string): string {
  return name
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}
