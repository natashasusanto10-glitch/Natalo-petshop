"""Kompres bitmap assets in-place untuk Play Console bitmap optimization.

Aturan per folder (max dimensi disesuaikan ukuran display di app):
- assets/brands   : logo brand, tampil kecil (~100-200px)  -> max 512px
- assets/products : gambar produk fallback                  -> max 1024px
- assets/banners  : banner hero full-width                  -> max 1600px
- assets/images   : ilustrasi umum                          -> max 1024px

Nama file + ekstensi TIDAK diubah (di-refer langsung dari kode Dart).
PNG: resize + optimize (palet dipertahankan kalau sudah palet).
JPEG: resize + quality 82 progressive.
File asli recoverable via git checkout kalau hasil tidak memuaskan.
"""
import sys
from pathlib import Path
from PIL import Image

RULES = {
    "brands": 512,
    "products": 1024,
    "banners": 1600,
    "images": 1024,
}

ASSETS = Path(__file__).resolve().parent.parent / "assets"

total_before = 0
total_after = 0
changed = 0

for folder, max_dim in RULES.items():
    root = ASSETS / folder
    if not root.exists():
        continue
    for path in sorted(root.rglob("*")):
        if path.suffix.lower() not in (".png", ".jpg", ".jpeg"):
            continue
        before = path.stat().st_size
        try:
            img = Image.open(path)
            img.load()
        except Exception as e:  # noqa: BLE001 - skip file korup, jangan gagalkan batch
            print(f"SKIP (unreadable) {path.name}: {e}")
            continue

        w, h = img.size
        scale = min(1.0, max_dim / max(w, h))
        resized = False
        if scale < 1.0:
            img = img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
            resized = True

        tmp = path.with_suffix(path.suffix + ".tmp")
        if path.suffix.lower() == ".png":
            # Pertahankan alpha; optimize zlib. Quantize hanya kalau untung
            # besar dan gambar bukan foto (heuristik: <=100k warna unik tak
            # praktis dicek, jadi cukup optimize saja — aman & lossless).
            img.save(tmp, format="PNG", optimize=True)
        else:
            if img.mode in ("RGBA", "P", "LA"):
                img = img.convert("RGB")
            img.save(tmp, format="JPEG", quality=82, optimize=True, progressive=True)

        after = tmp.stat().st_size
        # Pakai hasil hanya kalau benar-benar lebih kecil (>2% saving);
        # kalau tidak, buang tmp — jangan tulis ulang file tanpa untung.
        if after < before * 0.98:
            tmp.replace(path)
            changed += 1
            note = f"{w}x{h}->{img.size[0]}x{img.size[1]}" if resized else "recompress"
            print(f"OK  {path.relative_to(ASSETS)}  {before//1024}KB -> {after//1024}KB  ({note})")
            total_before += before
            total_after += after
        else:
            tmp.unlink()

print(f"\n{changed} file dikompres: {total_before/1024/1024:.1f}MB -> {total_after/1024/1024:.1f}MB "
      f"(hemat {(total_before-total_after)/1024/1024:.1f}MB)")
