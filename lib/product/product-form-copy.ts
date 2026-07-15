export function productFormCopy(mode: "create" | "edit") {
  return mode === "create"
    ? { title: "Tambah Produk", submit: "Simpan Produk", success: "Produk berhasil dibuat" }
    : { title: "Edit Produk", submit: "Simpan Perubahan", success: "Perubahan produk berhasil disimpan" };
}
