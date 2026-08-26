import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { canRemoveImage, removeImageAt } from "../lib/product/product-media";
import { uploadProductImageFiles } from "../components/MultiImageUpload";
import { compressImage, uploadAdminImage } from "../lib/admin-image-upload";

describe("compact product media rail helpers", () => {
  it("removes the cover and promotes the next image", () => {
    assert.deepStrictEqual(removeImageAt(["cover", "second", "third"], 0), ["second", "third"]);
  });

  it("blocks deleting the last remaining photo", () => {
    assert.strictEqual(canRemoveImage(["only"]), false);
  });

  it("rejects oversized files before upload", async () => {
    const oversized = new File([new Uint8Array(2 * 1024 * 1024 + 1)], "large.jpg", { type: "image/jpeg" });
    const result = await uploadProductImageFiles([oversized], 9);
    assert.deepStrictEqual(result.uploaded, []);
    assert.deepStrictEqual(result.failed, ["large.jpg"]);
  });
});

describe("upload gambar admin tunggal (foto varian, logo brand, dll.)", () => {
  it("memakai penjaga ukuran yang sama dengan upload foto produk", async () => {
    const oversized = new File([new Uint8Array(2 * 1024 * 1024 + 1)], "varian.jpg", {
      type: "image/jpeg",
    });
    await assert.rejects(
      () => uploadAdminImage(oversized),
      /melebihi batas 2 MB/,
      "slot upload tunggal wajib lewat uploadOne, bukan fetch mentah sendiri",
    );
  });

  it("melewatkan file kecil tanpa menyentuh canvas", async () => {
    // < 300 KB: kompresi dilewati, jadi objek File yang sama dikembalikan
    // apa adanya. Ini juga yang membuat test bisa jalan di node tanpa canvas.
    const small = new File([new Uint8Array(1024)], "kecil.png", { type: "image/png" });
    assert.strictEqual(await compressImage(small), small);
  });

  it("menghormati batas yang lebih ketat dari server (popup 1 MB)", async () => {
    // Popup peluncuran sengaja dibatasi 1 MB walau server menerima 2 MB,
    // karena tampil saat app dibuka. Kalau opsi maxBytes diabaikan, file
    // 1,5 MB akan lolos ke server dan popup jadi berat.
    const file = new File([new Uint8Array(1_500_000)], "popup.jpg", { type: "image/jpeg" });
    await assert.rejects(
      () => uploadAdminImage(file, { maxBytes: 1024 * 1024 }),
      /melebihi batas 1 MB/,
    );
  });

  it("meneruskan kind=brand-logo ke server", async () => {
    // Kalau field ini hilang, server melewatkan normalizeBrandLogo: logo
    // tersimpan tanpa di-trim & dipusatkan. TIDAK ada error, TIDAK ada
    // gejala — cuma berat visualnya beda sendiri di grid Brand Favorit.
    const realFetch = globalThis.fetch;
    let sentKind: FormDataEntryValue | null = "BELUM DIPANGGIL";
    globalThis.fetch = (async (_url: string, init: { body: FormData }) => {
      sentKind = init.body.get("kind");
      return { ok: true, json: async () => ({ url: "https://cdn/logo.png" }) };
    }) as unknown as typeof fetch;

    try {
      const logo = new File([new Uint8Array(1024)], "logo.png", { type: "image/png" });
      const url = await uploadAdminImage(logo, { fields: { kind: "brand-logo" } });
      assert.strictEqual(url, "https://cdn/logo.png");
      assert.strictEqual(sentKind, "brand-logo");
    } finally {
      globalThis.fetch = realFetch;
    }
  });

  it("mengembalikan file asli kalau kompresi tidak bisa jalan", async () => {
    // Di node tidak ada createImageBitmap → compressImage harus jatuh ke
    // file asli, BUKAN melempar. Kalau ini pecah, upload gagal total di
    // browser lama alih-alih sekadar mengirim file yang belum dikompresi.
    const big = new File([new Uint8Array(400 * 1024)], "besar.png", { type: "image/png" });
    assert.strictEqual(await compressImage(big), big);
  });
});
