"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { ProductSlugPicker } from "@/components/admin/BannerManagerClient";

type Popup = {
  id: string;
  imageUrl: string;
  imageAlt: string;
  linkType: string;
  linkValue: string | null;
  audience: string;
  startsAt: string | null;
  endsAt: string | null;
  isActive: boolean;
};

type LabelOption = { slug: string; name: string };

type Props = {
  initialPopups: Popup[];
  categories: LabelOption[];
  brands: LabelOption[];
};

const MAX_SIZE = 1 * 1024 * 1024;

// Rasio + ukuran ideal — popup fullscreen di app Flutter (gaya Shopee).
// 1080×1350 = 4:5. Gambar ditampilkan UTUH (contain), bukan cover, jadi
// rasio lain tetap tampil penuh — 4:5 hanya rekomendasi paling pas layar.
const IDEAL_W = 1080;
const IDEAL_H = 1350;

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

/** Konversi ISO string ↔ value input datetime-local (waktu lokal admin). */
function isoToLocalInput(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function localInputToIso(value: string): string | null {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

export function LaunchPopupManagerClient({
  initialPopups,
  categories,
  brands,
}: Props) {
  const router = useRouter();
  const [popups, setPopups] = useState<Popup[]>(initialPopups);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const addFileRef = useRef<HTMLInputElement>(null);

  function refresh() {
    router.refresh();
  }

  async function uploadImage(file: File): Promise<string | null> {
    if (file.size > MAX_SIZE) {
      setError("Ukuran gambar maksimal 1 MB");
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

  async function handleAddPopup(file: File) {
    setError("");
    setBusy(true);
    try {
      const url = await uploadImage(file);
      if (!url) return;
      const res = await fetch("/api/admin/launch-popup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          imageUrl: url,
          imageAlt: "",
          linkType: "none",
          audience: "member",
          isActive: true,
        }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error ?? "Gagal menambah popup");
        return;
      }
      setPopups((prev) => [data.popup, ...prev]);
      refresh();
    } finally {
      setBusy(false);
    }
  }

  async function patchPopup(id: string, patch: Record<string, unknown>) {
    setError("");
    const res = await fetch(`/api/admin/launch-popup/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(patch),
    });
    const data = await res.json();
    if (!res.ok) {
      setError(data.error ?? "Gagal menyimpan");
      return false;
    }
    setPopups((prev) => prev.map((p) => (p.id === id ? { ...p, ...data.popup } : p)));
    return true;
  }

  async function deletePopup(id: string) {
    if (!confirm("Hapus popup ini?")) return;
    setError("");
    setBusy(true);
    try {
      const res = await fetch(`/api/admin/launch-popup/${id}`, {
        method: "DELETE",
      });
      if (!res.ok) {
        const data = await res.json();
        setError(data.error ?? "Gagal menghapus");
        return;
      }
      setPopups((prev) => prev.filter((p) => p.id !== id));
      refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mt-5 space-y-5">
      {/* Panduan ukuran + perilaku */}
      <div className="rounded-2xl border border-blue-200 bg-blue-50 p-4 text-sm text-blue-900">
        <p className="font-black">📐 Ukuran gambar ideal</p>
        <p className="mt-1 leading-relaxed">
          Rasio <strong>4:5</strong> — ukuran rekomendasi{" "}
          <strong>
            {IDEAL_W}×{IDEAL_H}px
          </strong>
          . Format JPG/PNG/WEBP, maks 1 MB. Gambar tampil <strong>utuh</strong>{" "}
          (tidak ke-crop) di tengah layar + tombol ✕. Popup muncul{" "}
          <strong>setiap kali user buka app</strong> (cold start). Hanya{" "}
          <strong>1 popup aktif terbaru</strong> yang ditampilkan — nonaktifkan
          popup lama saat menambah yang baru.
        </p>
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-2.5 text-sm font-semibold text-red-700">
          {error}
        </div>
      )}

      {/* Tambah popup */}
      <div>
        <input
          ref={addFileRef}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          className="hidden"
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) void handleAddPopup(file);
            e.target.value = "";
          }}
        />
        <button
          type="button"
          disabled={busy}
          onClick={() => addFileRef.current?.click()}
          className="inline-flex items-center gap-2 rounded-full bg-natalo-600 px-5 py-2.5 text-sm font-black text-white shadow-sm transition hover:bg-natalo-700 disabled:opacity-50"
        >
          + Tambah Popup
        </button>
      </div>

      {popups.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-zinc-300 bg-zinc-50 p-8 text-center text-sm font-semibold text-zinc-500">
          Belum ada popup. App tidak menampilkan popup apa pun saat dibuka.
        </div>
      ) : (
        <div className="space-y-4">
          {popups.map((popup) => (
            <PopupCard
              key={popup.id}
              popup={popup}
              categories={categories}
              brands={brands}
              busy={busy}
              onPatch={patchPopup}
              onDelete={deletePopup}
              uploadImage={uploadImage}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function PopupCard({
  popup,
  categories,
  brands,
  busy,
  onPatch,
  onDelete,
  uploadImage,
}: {
  popup: Popup;
  categories: LabelOption[];
  brands: LabelOption[];
  busy: boolean;
  onPatch: (id: string, patch: Record<string, unknown>) => Promise<boolean>;
  onDelete: (id: string) => void;
  uploadImage: (file: File) => Promise<string | null>;
}) {
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);
  const [linkType, setLinkType] = useState(popup.linkType);
  const [linkValue, setLinkValue] = useState(popup.linkValue ?? "");
  const [alt, setAlt] = useState(popup.imageAlt);
  const [audience, setAudience] = useState(popup.audience);
  const [startsAt, setStartsAt] = useState(isoToLocalInput(popup.startsAt));
  const [endsAt, setEndsAt] = useState(isoToLocalInput(popup.endsAt));
  const [saving, setSaving] = useState(false);
  const [replacing, setReplacing] = useState(false);

  const needsValue =
    linkType === "category" ||
    linkType === "brand" ||
    linkType === "product" ||
    linkType === "url";

  async function saveSettings() {
    setSaving(true);
    await onPatch(popup.id, {
      linkType,
      linkValue: needsValue ? linkValue : null,
      imageAlt: alt,
      audience,
      startsAt: localInputToIso(startsAt),
      endsAt: localInputToIso(endsAt),
    });
    setSaving(false);
  }

  async function replaceImage(file: File) {
    setReplacing(true);
    try {
      const url = await uploadImage(file);
      if (!url) return;
      await onPatch(popup.id, { imageUrl: url });
      router.refresh();
    } finally {
      setReplacing(false);
    }
  }

  return (
    <div className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
      <div className="flex items-center justify-between gap-2">
        <span className="rounded-full bg-zinc-100 px-2.5 py-1 text-xs font-black text-zinc-600">
          {popup.audience === "all" ? "Semua user" : "Member saja"}
        </span>
        <div className="flex items-center gap-1.5">
          <label className="flex cursor-pointer items-center gap-1.5 rounded-lg border border-zinc-200 px-2.5 py-1 text-xs font-bold text-zinc-600 hover:bg-zinc-50">
            <input
              type="checkbox"
              checked={popup.isActive}
              onChange={(e) => onPatch(popup.id, { isActive: e.target.checked })}
              className="accent-natalo-600"
            />
            Aktif
          </label>
          <button
            type="button"
            disabled={busy}
            onClick={() => onDelete(popup.id)}
            className="rounded-lg border border-red-200 px-2.5 py-1 text-xs font-bold text-red-600 hover:bg-red-50 disabled:opacity-50"
          >
            Hapus
          </button>
        </div>
      </div>

      {/* Preview 4:5 latar gelap — mensimulasikan overlay app. Gambar contain
          (tampil utuh), sama dengan render Flutter. */}
      <div
        className="relative mx-auto mt-3 w-full max-w-xs overflow-hidden rounded-xl bg-zinc-800 ring-1 ring-black/5"
        style={{ aspectRatio: "4 / 5" }}
      >
        <img
          src={popup.imageUrl}
          alt={popup.imageAlt || "Popup promo"}
          className="h-full w-full object-contain"
        />
        {!popup.isActive && (
          <div className="absolute inset-0 flex items-center justify-center bg-black/60 text-sm font-black text-white">
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

      {/* Pengaturan: link tujuan + audience + jadwal */}
      <div className="mt-4 space-y-3 rounded-xl bg-zinc-50 p-3">
        <p className="text-xs font-black text-zinc-500">LINK TUJUAN (saat gambar di-tap)</p>
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

        <div className="grid gap-2 sm:grid-cols-2">
          <label className="block text-xs font-semibold text-zinc-600">
            Ditampilkan ke
            <select
              value={audience}
              onChange={(e) => setAudience(e.target.value)}
              className="mt-1 w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm font-semibold outline-none focus:border-zinc-950"
            >
              <option value="member">Member saja (login)</option>
              <option value="all">Semua user</option>
            </select>
          </label>
          <div className="grid grid-cols-2 gap-2">
            <label className="block text-xs font-semibold text-zinc-600">
              Mulai (opsional)
              <input
                type="datetime-local"
                value={startsAt}
                onChange={(e) => setStartsAt(e.target.value)}
                className="mt-1 w-full rounded-lg border border-zinc-300 bg-white px-2 py-2 text-xs outline-none focus:border-zinc-950"
              />
            </label>
            <label className="block text-xs font-semibold text-zinc-600">
              Berakhir (opsional)
              <input
                type="datetime-local"
                value={endsAt}
                onChange={(e) => setEndsAt(e.target.value)}
                className="mt-1 w-full rounded-lg border border-zinc-300 bg-white px-2 py-2 text-xs outline-none focus:border-zinc-950"
              />
            </label>
          </div>
        </div>

        <input
          type="text"
          value={alt}
          onChange={(e) => setAlt(e.target.value)}
          placeholder="Deskripsi popup (opsional, untuk aksesibilitas)"
          className="w-full rounded-lg border border-zinc-200 bg-white px-3 py-2 text-xs outline-none focus:border-zinc-400"
        />

        <button
          type="button"
          disabled={saving}
          onClick={saveSettings}
          className="rounded-full bg-zinc-950 px-4 py-1.5 text-xs font-bold text-white hover:bg-zinc-800 disabled:opacity-50"
        >
          {saving ? "Menyimpan…" : "Simpan Pengaturan"}
        </button>
      </div>
    </div>
  );
}
