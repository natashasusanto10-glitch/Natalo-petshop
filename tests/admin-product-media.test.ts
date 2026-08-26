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

  it("mengembalikan file asli kalau kompresi tidak bisa jalan", async () => {
    // Di node tidak ada createImageBitmap → compressImage harus jatuh ke
    // file asli, BUKAN melempar. Kalau ini pecah, upload gagal total di
    // browser lama alih-alih sekadar mengirim file yang belum dikompresi.
    const big = new File([new Uint8Array(400 * 1024)], "besar.png", { type: "image/png" });
    assert.strictEqual(await compressImage(big), big);
  });
});
