"use client";

import { useMemo, useState } from "react";

type BroadcastType = "promo" | "announcement";
type Segment = "all" | "members" | "active30d" | "test";
type PublishStatus = "PUBLISHED" | "DRAFT";

type Result = {
  ok: boolean;
  segment?: Segment;
  recipientCount?: number;
  sent?: number;
  failed?: number;
  announcementId?: string | null;
  elapsed_ms?: number;
  dryRun?: boolean;
  error?: string;
};

const TYPE_OPTIONS: Array<{ id: BroadcastType; label: string; desc: string }> = [
  {
    id: "promo",
    label: "Promo",
    desc: "Masuk ke Notification Center User - Tab Promo.",
  },
  {
    id: "announcement",
    label: "Pengumuman",
    desc: "Masuk ke Notification Center User - Tab Pengumuman.",
  },
];

const SEGMENT_OPTIONS: Array<{ id: Segment; label: string; desc: string }> = [
  { id: "all", label: "Semua user", desc: "Semua user yang sesuai aturan broadcast in-app dan push." },
  { id: "members", label: "Member pernah belanja", desc: "User dengan minimal 1 order paymentStatus=PAID." },
  { id: "active30d", label: "Aktif 30 hari", desc: "User yang punya order dalam 30 hari terakhir." },
  { id: "test", label: "Test ke saya", desc: "Hanya admin yang sedang login, tidak masuk Notification Center user." },
];

const CTA_OPTIONS: Record<BroadcastType, string[]> = {
  promo: ["Lihat Promo", "Pakai Voucher", "Belanja Sekarang", "Lihat Detail"],
  announcement: ["Lihat Detail", "Cek Info", "Mengerti", "Perbarui Sekarang"],
};

/**
 * Mapping CTA label → URL deep link target.
 *
 * Saat admin pilih CTA dari dropdown, URL field auto-update ke value
 * yang sesuai. Cegah misconfiguration: dulu admin pilih "Pakai Voucher"
 * tapi URL tetap `/products` → user tap tombol Voucher justru masuk
 * halaman produk (atau Flutter pakai fallback CTA-label detection, tapi
 * tidak 100% reliable).
 *
 * Sekarang CTA → URL preset eksplisit, admin tetap bisa override manual
 * kalau perlu (mis. promo voucher spesifik kategori produk tertentu).
 *
 * Routes ini juga match dengan Flutter Navigator routes di main.dart.
 */
const CTA_TO_URL: Record<string, string> = {
  // Promo CTAs
  "Lihat Promo": "/products",
  "Pakai Voucher": "/member/vouchers", // ← Tap tombol = buka halaman voucher
  "Belanja Sekarang": "/products",
  "Lihat Detail": "/notifications",
  // Announcement CTAs
  "Cek Info": "/notifications",
  Mengerti: "/notifications",
  "Perbarui Sekarang": "/notifications",
};

/**
 * Friendly label untuk target URL — preview yang admin lihat saat pilih
 * CTA. "User akan dibawa ke: 🎁 Halaman Voucher" daripada URL teknis.
 */
function urlPreviewLabel(url: string): string {
  if (url.startsWith("/member/vouchers")) return "🎁 Voucher Saya";
  if (url.startsWith("/member/refund-balance")) return "💰 Saldo Refund";
  if (url.startsWith("/member/orders")) return "📦 Pesanan Saya";
  if (url.startsWith("/member/loyalty")) return "⭐ Poin Loyalty";
  if (url.startsWith("/products")) return "🛍️ Katalog Produk";
  if (url.startsWith("/notifications")) return "🔔 Pengumuman Detail";
  if (url.startsWith("/feed")) return "🎬 Feed";
  if (url.startsWith("/cart")) return "🛒 Keranjang";
  if (url.startsWith("http")) return "🔗 Link Eksternal";
  if (!url) return "Tidak diatur";
  return url;
}

function defaultTarget(type: BroadcastType) {
  return type === "promo" ? "/products" : "/notifications";
}

async function readResponseSafely(res: Response): Promise<Result> {
  const text = await res.text().catch(() => "");
  try {
    return JSON.parse(text) as Result;
  } catch {
    const snippet = text.slice(0, 120).replace(/\s+/g, " ").trim();
    return {
      ok: false,
      error: `HTTP ${res.status} non-JSON response${snippet ? ` - ${snippet}` : ""}`,
    };
  }
}

export function BroadcastForm() {
  const [type, setType] = useState<BroadcastType>("promo");
  const [title, setTitle] = useState("Flash Sale Hari Ini");
  const [body, setBody] = useState("Diskon hingga 25% untuk makanan kucing premium.");
  const [startsAt, setStartsAt] = useState("");
  const [endsAt, setEndsAt] = useState("");
  const [publishedAt, setPublishedAt] = useState("");
  const [ctaLabel, setCtaLabel] = useState("Lihat Promo");
  const [url, setUrl] = useState("/products");
  const [status, setStatus] = useState<PublishStatus>("PUBLISHED");
  const [segment, setSegment] = useState<Segment>("all");
  const [recipientCount, setRecipientCount] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [result, setResult] = useState<Result | null>(null);
  const [error, setError] = useState("");

  const canSubmit = title.trim().length > 0 && body.trim().length > 0 && !loading;
  const typeCopy = useMemo(() => {
    if (type === "promo") {
      return {
        titleLabel: "Judul Promo",
        bodyLabel: "Deskripsi Promo",
        startLabel: "Tanggal Mulai",
        endLabel: "Tanggal Berakhir",
        source: "Dashboard Admin -> Broadcast Notifikasi -> Tipe Promo -> Publish -> Tab Promo user.",
      };
    }

    return {
      titleLabel: "Judul Pengumuman",
      bodyLabel: "Isi Pengumuman",
      startLabel: "Tanggal Publish",
      endLabel: "Tanggal Selesai Tampil",
      source: "Dashboard Admin -> Broadcast Notifikasi -> Tipe Pengumuman -> Publish -> Tab Pengumuman user.",
    };
  }, [type]);

  function switchType(nextType: BroadcastType) {
    setType(nextType);
    setRecipientCount(null);
    setResult(null);

    if (nextType === "promo") {
      setTitle((current) => (current === "Perubahan Jam Operasional" ? "Flash Sale Hari Ini" : current));
      setBody((current) =>
        current.includes("Layanan toko") ? "Diskon hingga 25% untuk makanan kucing premium." : current,
      );
      setCtaLabel((current) => (CTA_OPTIONS.announcement.includes(current) ? "Lihat Promo" : current));
    } else {
      setTitle((current) => (current === "Flash Sale Hari Ini" ? "Perubahan Jam Operasional" : current));
      setBody((current) =>
        current.includes("Diskon hingga")
          ? "Layanan toko dan customer service akan beroperasi pukul 09.00 - 20.00 mulai Senin depan."
          : current,
      );
      setCtaLabel((current) => (CTA_OPTIONS.promo.includes(current) ? "Lihat Detail" : current));
    }
    setUrl((current) => (current === defaultTarget(type) ? defaultTarget(nextType) : current));
  }

  function buildPayload(dryRun = false) {
    return {
      title,
      body,
      url,
      type,
      ctaLabel,
      startsAt: type === "promo" ? startsAt || null : publishedAt || startsAt || null,
      endsAt: endsAt || null,
      publishedAt: publishedAt || startsAt || null,
      status,
      segment,
      dryRun,
    };
  }

  async function postBroadcast(dryRun = false) {
    setError("");
    setResult(null);
    setLoading(true);
    try {
      const res = await fetch("/api/admin/push/broadcast", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(buildPayload(dryRun)),
      });
      const data = await readResponseSafely(res);
      if (!res.ok || !data.ok) {
        setError(data.error ?? `Broadcast gagal (HTTP ${res.status})`);
        return null;
      }
      return data;
    } catch (err) {
      setError(err instanceof Error ? err.message : "Network error");
      return null;
    } finally {
      setLoading(false);
    }
  }

  async function checkRecipientCount() {
    const data = await postBroadcast(true);
    if (data) setRecipientCount(data.recipientCount ?? 0);
  }

  async function sendBroadcast() {
    const data = await postBroadcast(false);
    if (data) {
      setResult(data);
      setConfirming(false);
      setRecipientCount(data.recipientCount ?? recipientCount);
    }
  }

  return (
    <div className="space-y-5">
      <div>
        <label className="block text-sm font-bold text-zinc-700">Tipe Broadcast</label>
        <div className="mt-2 grid gap-2 sm:grid-cols-2">
          {TYPE_OPTIONS.map((option) => (
            <label
              key={option.id}
              className={`flex cursor-pointer items-start gap-3 rounded-2xl border px-4 py-3 transition ${
                type === option.id ? "border-natalo-400 bg-natalo-50" : "border-zinc-200 bg-white"
              }`}
            >
              <input
                type="radio"
                name="type"
                value={option.id}
                checked={type === option.id}
                onChange={() => switchType(option.id)}
                className="mt-1 h-4 w-4 accent-natalo-600"
              />
              <span>
                <span className="block text-sm font-black text-zinc-950">{option.label}</span>
                <span className="mt-0.5 block text-xs leading-relaxed text-zinc-500">{option.desc}</span>
              </span>
            </label>
          ))}
        </div>
      </div>

      <div className="rounded-xl border border-blue-200 bg-blue-50 px-4 py-3 text-xs font-semibold text-blue-900">
        {typeCopy.source}
      </div>

      <div>
        <label className="block text-sm font-bold text-zinc-700">{typeCopy.titleLabel}</label>
        <input
          type="text"
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          maxLength={60}
          className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-400"
        />
        <p className="mt-1 text-xs text-zinc-400">{title.length}/60 karakter</p>
      </div>

      <div>
        <label className="block text-sm font-bold text-zinc-700">{typeCopy.bodyLabel}</label>
        <textarea
          value={body}
          onChange={(event) => setBody(event.target.value)}
          maxLength={180}
          rows={4}
          className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-400"
        />
        <p className="mt-1 text-xs text-zinc-400">{body.length}/180 karakter</p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className="block text-sm font-bold text-zinc-700">{typeCopy.startLabel}</label>
          <input
            type="datetime-local"
            value={type === "promo" ? startsAt : publishedAt}
            onChange={(event) => {
              if (type === "promo") setStartsAt(event.target.value);
              else setPublishedAt(event.target.value);
            }}
            className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-400"
          />
        </div>
        <div>
          <label className="block text-sm font-bold text-zinc-700">{typeCopy.endLabel}</label>
          <input
            type="datetime-local"
            value={endsAt}
            onChange={(event) => setEndsAt(event.target.value)}
            className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-400"
          />
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className="block text-sm font-bold text-zinc-700">CTA Label</label>
          <select
            value={ctaLabel}
            onChange={(event) => {
              const next = event.target.value;
              setCtaLabel(next);
              // Auto-update URL berdasarkan CTA. Cegah misconfig
              // "Pakai Voucher" → URL salah. Admin tetep bisa override
              // manual setelah ini dengan ngetik di field URL.
              const presetUrl = CTA_TO_URL[next];
              if (presetUrl !== undefined) {
                setUrl(presetUrl);
              }
            }}
            className="mt-1 block w-full rounded-xl border border-zinc-300 bg-white px-4 py-3 text-sm font-semibold outline-none focus:border-natalo-400"
          >
            {CTA_OPTIONS[type].map((label) => (
              <option key={label} value={label}>
                {label}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-sm font-bold text-zinc-700">CTA Link / Target Page</label>
          <input
            type="text"
            value={url}
            onChange={(event) => setUrl(event.target.value)}
            placeholder={defaultTarget(type)}
            className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-400"
          />
          {/* Preview chip — show admin tujuan akhir user saat tap CTA.
              Useful supaya admin gak salah set URL (mis. typo, atau lupa
              ubah default). */}
          <p className="mt-1 text-xs font-semibold text-zinc-500">
            User akan dibawa ke:{" "}
            <span className="font-bold text-natalo-700">
              {urlPreviewLabel(url)}
            </span>
          </p>
        </div>
      </div>

      <div>
        <label className="block text-sm font-bold text-zinc-700">Status Publish</label>
        <div className="mt-2 grid grid-cols-2 gap-2">
          {(["PUBLISHED", "DRAFT"] as const).map((option) => (
            <label
              key={option}
              className={`flex cursor-pointer items-center gap-3 rounded-xl border px-4 py-3 text-sm font-bold ${
                status === option ? "border-natalo-400 bg-natalo-50 text-natalo-700" : "border-zinc-200 bg-white text-zinc-600"
              }`}
            >
              <input
                type="radio"
                name="status"
                checked={status === option}
                onChange={() => setStatus(option)}
                className="h-4 w-4 accent-natalo-600"
              />
              {option === "PUBLISHED" ? "Publish" : "Draft"}
            </label>
          ))}
        </div>
      </div>

      <div>
        <label className="block text-sm font-bold text-zinc-700">Target Audience</label>
        <div className="mt-2 space-y-2">
          {SEGMENT_OPTIONS.map((option) => (
            <label
              key={option.id}
              className={`flex cursor-pointer items-start gap-3 rounded-xl border px-4 py-3 transition ${
                segment === option.id ? "border-natalo-400 bg-natalo-50" : "border-zinc-200 bg-white"
              }`}
            >
              <input
                type="radio"
                name="segment"
                value={option.id}
                checked={segment === option.id}
                onChange={() => {
                  setSegment(option.id);
                  setRecipientCount(null);
                }}
                className="mt-1 h-4 w-4 accent-natalo-600"
              />
              <span className="min-w-0 flex-1">
                <span className="block text-sm font-bold text-zinc-950">{option.label}</span>
                <span className="mt-0.5 block text-xs text-zinc-500">{option.desc}</span>
              </span>
            </label>
          ))}
        </div>
      </div>

      <div className="rounded-xl border border-zinc-200 bg-zinc-50 px-4 py-3">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="min-w-0">
            <p className="text-xs font-bold uppercase tracking-wide text-zinc-500">Estimasi penerima push</p>
            <p className="mt-1 text-xl font-black text-zinc-900 sm:text-2xl">
              {recipientCount !== null ? recipientCount.toLocaleString("id-ID") : "-"} user
            </p>
          </div>
          <button
            type="button"
            onClick={checkRecipientCount}
            disabled={loading || !canSubmit}
            className="shrink-0 rounded-full border border-zinc-300 bg-white px-4 py-2 text-xs font-bold text-zinc-700 disabled:opacity-50"
          >
            Cek jumlah
          </button>
        </div>
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-semibold text-red-700">
          {error}
        </div>
      )}

      {result?.ok && (
        <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">
          <p className="font-bold">{status === "DRAFT" ? "Draft tersimpan" : "Broadcast selesai"}</p>
          <ul className="mt-1.5 space-y-0.5 text-xs">
            <li>
              Tipe: <strong>{type === "promo" ? "Promo" : "Pengumuman"}</strong>
            </li>
            <li>
              Segment: <strong>{result.segment}</strong>
            </li>
            <li>
              Total recipient push: <strong>{result.recipientCount}</strong>
            </li>
            <li>
              Sukses: <strong>{result.sent}</strong>
            </li>
            <li>
              Gagal: <strong>{result.failed}</strong>
            </li>
            <li>
              Durasi: <strong>{result.elapsed_ms}ms</strong>
            </li>
          </ul>
        </div>
      )}

      <div className="flex flex-col gap-3 pt-2 sm:flex-row">
        {!confirming ? (
          <button
            type="button"
            onClick={() => {
              if (!canSubmit) return;
              if (segment === "test" || status === "DRAFT") {
                void sendBroadcast();
              } else {
                setConfirming(true);
              }
            }}
            disabled={!canSubmit}
            className="flex-1 rounded-full bg-natalo-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:bg-zinc-300"
          >
            {loading
              ? "Memproses..."
              : segment === "test"
                ? "Test ke saya"
                : status === "DRAFT"
                  ? "Simpan draft"
                  : "Publish broadcast"}
          </button>
        ) : (
          <>
            <button
              type="button"
              onClick={() => setConfirming(false)}
              disabled={loading}
              className="rounded-full border border-zinc-300 bg-white px-6 py-3 text-sm font-bold text-zinc-700 disabled:opacity-50 sm:flex-1"
            >
              Batal
            </button>
            <button
              type="button"
              onClick={sendBroadcast}
              disabled={loading}
              className="flex-1 rounded-full bg-red-600 px-6 py-3 text-sm font-bold text-white transition active:bg-red-700 disabled:bg-zinc-300"
            >
              {loading ? "Mengirim..." : `Konfirmasi publish${recipientCount !== null ? ` ke ${recipientCount} user` : ""}`}
            </button>
          </>
        )}
      </div>
    </div>
  );
}
