"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";

type Banner = {
  id: string;
  imageUrl: string;
  imageAlt: string;
  linkType: string;
  linkValue: string | null;
  isActive: boolean;
  position: number;
};

type LabelOption = { slug: string; name: string };

type Props = {
  initialBanners: Banner[];
  categories: LabelOption[];
  brands: LabelOption[];
};

const MAX_SIZE = 2 * 1024 * 1024;

// Rasio + ukuran ideal — HARUS match Flutter _HeroBanner (AspectRatio 16:7,
// BoxFit.cover). 1280×560 = 16:7 @2x untuk layar HD. Gambar di luar rasio
// ini akan ter-crop di tepi.
const IDEAL_W = 1280;
const IDEAL_H = 560;

const LINK_TYPE_LABELS: Record<string, string> = {
  none: "Tidak bisa di-tap",
  category: "Kategori",
  product: "Produk spesifik",
  brand: "Brand",
  promo: "Promo / Diskon",
  voucher: "Voucher",
  loyalty: "Tukar Poin",
  url: "URL eksternal",
};

export function BannerManagerClient({ initialBanners, categories, brands }: Props) {
  const router = useRouter();
  const [banners, setBanners] = useState<Banner[]>(initialBanners);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const addFileRef = useRef<HTMLInputElement>(null);

  function refresh() {
    router.refresh();
  }

  async function uploadImage(file: File): Promise<string | null> {
    if (file.size > MAX_SIZE) {
      setError("Ukuran gambar maksimal 2 MB");
      return null;
    }
    const formData = new FormData();
    formData.append("file", file);
    const res = await fetch("/api/admin/upload", { method: "POST", body: formData });
    const data = (await res.json()) as { url?: string; error?: string };
    if (!res.ok || !data.url) {
      setError(data.error ?? "Upload gagal");
      return null;
    }
    return data.url;
  }

  async function handleAddBanner(file: File) {
    setError("");
    setBusy(true);
    try {
      const url = await uploadImage(file);
      if (!url) return;
      const res = await fetch("/api/admin/banners", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          imageUrl: url,
          imageAlt: "",
          linkType: "none",
          isActive: true,
        }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error ?? "Gagal menambah banner");
        return;
      }
      setBanners((prev) => [...prev, data.banner]);
      refresh();
    } finally {
      setBusy(false);
    }
  }

  async function patchBanner(id: string, patch: Partial<Banner>) {
    setError("");
    const res = await fetch(`/api/admin/banners/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(patch),
    });
    const data = await res.json();
    if (!res.ok) {
      setError(data.error ?? "Gagal menyimpan");
      return false;
    }
    setBanners((prev) => prev.map((b) => (b.id === id ? { ...b, ...data.banner } : b)));
    return true;
  }

  async function deleteBanner(id: string) {
    if (!confirm("Hapus banner ini?")) return;
    setError("");
    setBusy(true);
    try {
      const res = await fetch(`/api/admin/banners/${id}`, { method: "DELETE" });
      if (!res.ok) {
        const data = await res.json();
        setError(data.error ?? "Gagal menghapus");
        return;
      }
      setBanners((prev) => prev.filter((b) => b.id !== id));
      refresh();
    } finally {
      setBusy(false);
    }
  }

  async function move(id: string, dir: -1 | 1) {
    const idx = banners.findIndex((b) => b.id === id);
    const target = idx + dir;
    if (idx < 0 || target < 0 || target >= banners.length) return;
    const next = [...banners];
    [next[idx], next[target]] = [next[target], next[idx]];
    setBanners(next);
    setBusy(true);
    try {
      await fetch("/api/admin/banners/reorder", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ids: next.map((b) => b.id) }),
      });
      refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mt-5 space-y-5">
      {/* Panduan ukuran — biar admin upload gambar yang tidak ke-crop */}
      <div className="rounded-2xl border border-blue-200 bg-blue-50 p-4 text-sm text-blue-900">
        <p className="font-black">📐 Ukuran gambar ideal</p>
        <p className="mt-1 leading-relaxed">
          Rasio <strong>16:7</strong> — ukuran rekomendasi{" "}
          <strong>
            {IDEAL_W}×{IDEAL_H}px
          </strong>
          . Gambar di luar rasio ini akan <strong>terpotong di tepi</strong>{" "}
          (atas-bawah / kiri-kanan). Format JPG/PNG/WEBP, maks 2 MB. Preview di
          bawah menampilkan area yang benar-benar tampil di app.
        </p>
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-2.5 text-sm font-semibold text-red-700">
          {error}
        </div>
      )}

      {/* Tambah banner */}
      <div>
        <input
          ref={addFileRef}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          className="hidden"
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) void handleAddBanner(file);
            e.target.value = "";
          }}
        />
        <button
          type="button"
          disabled={busy}
          onClick={() => addFileRef.current?.click()}
          className="inline-flex items-center gap-2 rounded-full bg-natalo-600 px-5 py-2.5 text-sm font-black text-white shadow-sm transition hover:bg-natalo-700 disabled:opacity-50"
        >
          + Tambah Banner
        </button>
      </div>

      {banners.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-zinc-300 bg-zinc-50 p-8 text-center text-sm font-semibold text-zinc-500">
          Belum ada banner. App menampilkan banner bawaan sampai kamu tambah di
          sini.
        </div>
      ) : (
        <div className="space-y-4">
          {banners.map((banner, idx) => (
            <BannerCard
              key={banner.id}
              banner={banner}
              index={idx}
              total={banners.length}
              categories={categories}
              brands={brands}
              busy={busy}
              onPatch={patchBanner}
              onDelete={deleteBanner}
              onMove={move}
              uploadImage={uploadImage}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function BannerCard({
  banner,
  index,
  total,
  categories,
  brands,
  busy,
  onPatch,
  onDelete,
  onMove,
  uploadImage,
}: {
  banner: Banner;
  index: number;
  total: number;
  categories: LabelOption[];
  brands: LabelOption[];
  busy: boolean;
  onPatch: (id: string, patch: Partial<Banner>) => Promise<boolean>;
  onDelete: (id: string) => void;
  onMove: (id: string, dir: -1 | 1) => void;
  uploadImage: (file: File) => Promise<string | null>;
}) {
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);
  const [linkType, setLinkType] = useState(banner.linkType);
  const [linkValue, setLinkValue] = useState(banner.linkValue ?? "");
  const [alt, setAlt] = useState(banner.imageAlt);
  const [saving, setSaving] = useState(false);
  const [replacing, setReplacing] = useState(false);

  const needsValue =
    linkType === "category" ||
    linkType === "brand" ||
    linkType === "product" ||
    linkType === "url";

  async function saveLink() {
    setSaving(true);
    await onPatch(banner.id, {
      linkType,
      linkValue: needsValue ? linkValue : null,
      imageAlt: alt,
    });
    setSaving(false);
  }

  async function replaceImage(file: File) {
    setReplacing(true);
    try {
      const url = await uploadImage(file);
      if (!url) return;
      await onPatch(banner.id, { imageUrl: url });
      router.refresh();
    } finally {
      setReplacing(false);
    }
  }

  return (
    <div className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
      <div className="flex items-center justify-between gap-2">
        <span className="rounded-full bg-zinc-100 px-2.5 py-1 text-xs font-black text-zinc-600">
          Slide {index + 1}
        </span>
        <div className="flex items-center gap-1.5">
          <button
            type="button"
            disabled={busy || index === 0}
            onClick={() => onMove(banner.id, -1)}
            className="rounded-lg border border-zinc-200 px-2.5 py-1 text-xs font-bold text-zinc-600 hover:bg-zinc-50 disabled:opacity-30"
            title="Naikkan"
          >
            ↑
          </button>
          <button
            type="button"
            disabled={busy || index === total - 1}
            onClick={() => onMove(banner.id, 1)}
            className="rounded-lg border border-zinc-200 px-2.5 py-1 text-xs font-bold text-zinc-600 hover:bg-zinc-50 disabled:opacity-30"
            title="Turunkan"
          >
            ↓
          </button>
          <label className="flex cursor-pointer items-center gap-1.5 rounded-lg border border-zinc-200 px-2.5 py-1 text-xs font-bold text-zinc-600 hover:bg-zinc-50">
            <input
              type="checkbox"
              checked={banner.isActive}
              onChange={(e) => onPatch(banner.id, { isActive: e.target.checked })}
              className="accent-natalo-600"
            />
            Aktif
          </label>
          <button
            type="button"
            disabled={busy}
            onClick={() => onDelete(banner.id)}
            className="rounded-lg border border-red-200 px-2.5 py-1 text-xs font-bold text-red-600 hover:bg-red-50 disabled:opacity-50"
          >
            Hapus
          </button>
        </div>
      </div>

      {/* Preview 16:7 — area yang BENAR-BENAR tampil di app (cover crop) */}
      <div className="relative mt-3 w-full overflow-hidden rounded-xl bg-zinc-100 ring-1 ring-black/5" style={{ aspectRatio: "16 / 7" }}>
        <img
          src={banner.imageUrl}
          alt={banner.imageAlt || "Banner"}
          className="h-full w-full object-cover"
        />
        {!banner.isActive && (
          <div className="absolute inset-0 flex items-center justify-center bg-black/50 text-sm font-black text-white">
            NONAKTIF
          </div>
        )}
      </div>

      <input
        ref={fileRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) void replaceImage(file);
          e.target.value = "";
        }}
      />
      <button
        type="button"
        disabled={replacing}
        onClick={() => fileRef.current?.click()}
        className="mt-2 rounded-full border border-zinc-300 bg-white px-4 py-1.5 text-xs font-bold text-zinc-700 hover:bg-zinc-50 disabled:opacity-50"
      >
        {replacing ? "Mengupload…" : "Ganti Gambar"}
      </button>

      {/* Link tujuan */}
      <div className="mt-4 space-y-2 rounded-xl bg-zinc-50 p-3">
        <p className="text-xs font-black text-zinc-500">LINK TUJUAN (saat di-tap)</p>
        <div className="flex flex-col gap-2 sm:flex-row">
          <select
            value={linkType}
            onChange={(e) => {
              setLinkType(e.target.value);
              setLinkValue("");
            }}
            className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm font-semibold outline-none focus:border-zinc-950"
          >
            {Object.entries(LINK_TYPE_LABELS).map(([val, label]) => (
              <option key={val} value={val}>
                {label}
              </option>
            ))}
          </select>

          {linkType === "category" && (
            <select
              value={linkValue}
              onChange={(e) => setLinkValue(e.target.value)}
              className="flex-1 rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-zinc-950"
            >
              <option value="">— pilih kategori —</option>
              {categories.map((c) => (
                <option key={c.slug} value={c.slug}>
                  {c.name}
                </option>
              ))}
            </select>
          )}
          {linkType === "brand" && (
            <select
              value={linkValue}
              onChange={(e) => setLinkValue(e.target.value)}
              className="flex-1 rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-zinc-950"
            >
              <option value="">— pilih brand —</option>
              {brands.map((b) => (
                <option key={b.slug} value={b.slug}>
                  {b.name}
                </option>
              ))}
            </select>
          )}
          {linkType === "product" && (
            <ProductSlugPicker value={linkValue} onChange={setLinkValue} />
          )}
          {linkType === "url" && (
            <input
              type="url"
              value={linkValue}
              onChange={(e) => setLinkValue(e.target.value)}
              placeholder="https://..."
              className="flex-1 rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-zinc-950"
            />
          )}
          {(linkType === "promo" ||
            linkType === "voucher" ||
            linkType === "loyalty") && (
            <p className="flex-1 self-center text-xs text-zinc-500">
              Otomatis ke halaman{" "}
              {linkType === "promo"
                ? "Promo/Diskon"
                : linkType === "voucher"
                  ? "Voucher"
                  : "Tukar Poin"}
              .
            </p>
          )}
        </div>

        <input
          type="text"
          value={alt}
          onChange={(e) => setAlt(e.target.value)}
          placeholder="Deskripsi banner (opsional, untuk aksesibilitas)"
          className="w-full rounded-lg border border-zinc-200 bg-white px-3 py-2 text-xs outline-none focus:border-zinc-400"
        />

        <button
          type="button"
          disabled={saving}
          onClick={saveLink}
          className="rounded-full bg-zinc-950 px-4 py-1.5 text-xs font-bold text-white hover:bg-zinc-800 disabled:opacity-50"
        >
          {saving ? "Menyimpan…" : "Simpan Link"}
        </button>
      </div>
    </div>
  );
}

/** Cari produk by nama → set slug. Pakai /api/search/suggest (sudah ada). */
function ProductSlugPicker({
  value,
  onChange,
}: {
  value: string;
  onChange: (slug: string) => void;
}) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Array<{ slug: string; name: string }>>([]);
  const [open, setOpen] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  function search(q: string) {
    setQuery(q);
    if (timer.current) clearTimeout(timer.current);
    if (q.trim().length < 2) {
      setResults([]);
      return;
    }
    timer.current = setTimeout(async () => {
      try {
        const res = await fetch(
          `/api/search/suggest?q=${encodeURIComponent(q.trim())}&limit=8`,
        );
        const data = await res.json();
        const products = (data.products ?? []) as Array<{
          slug: string;
          name: string;
        }>;
        setResults(products);
        setOpen(true);
      } catch {
        setResults([]);
      }
    }, 300);
  }

  return (
    <div className="relative flex-1">
      <input
        type="text"
        value={query || value}
        onChange={(e) => search(e.target.value)}
        onFocus={() => results.length > 0 && setOpen(true)}
        placeholder={value ? `Terpilih: ${value}` : "Cari nama produk…"}
        className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-zinc-950"
      />
      {open && results.length > 0 && (
        <div className="absolute z-10 mt-1 max-h-56 w-full overflow-y-auto rounded-xl border border-zinc-200 bg-white shadow-lg">
          {results.map((p) => (
            <button
              key={p.slug}
              type="button"
              onClick={() => {
                onChange(p.slug);
                setQuery(p.name);
                setOpen(false);
              }}
              className="block w-full px-3 py-2 text-left text-sm hover:bg-zinc-50"
            >
              <span className="font-semibold text-zinc-900">{p.name}</span>
              <span className="ml-1 text-xs text-zinc-400">{p.slug}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
