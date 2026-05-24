"use client";

/**
 * AI voucher suggest button + modal.
 *
 * Flow:
 *   1. Admin tap "✨ Buat dengan AI" → modal terbuka
 *   2. Input deskripsi prompt natural language
 *   3. Submit → POST /api/admin/ai/voucher-suggest
 *   4. Tampil preview suggestion (name, code, type, dst)
 *   5. Tap "Pakai" → auto-fill form fields via DOM
 *      (`document.querySelector('[name=X]')`)
 *   6. User review + edit + submit form normal
 *
 * Catatan: pakai DOM manipulation karena form server-side (gak ada
 * React state). Form values persistent setelah set — user bisa tweak
 * sebelum submit.
 */
import { useState } from "react";

type AIVoucherSuggestion = {
  name: string;
  code: string;
  description: string;
  type: string;
  discountType: string;
  discountAmount: number | null;
  discountPercent: number | null;
  maxDiscountAmount: number | null;
  minimumOrder: number;
  maxUsage: number | null;
  usageLimitPerUser: number;
  expiresAt: string;
  targetUser: string;
  reasoning: string;
};

const EXAMPLE_PROMPTS = [
  "Diskon 20% makanan kucing, min belanja 100rb, max potong 50rb, berlaku 7 hari",
  "Voucher gratis ongkir 30rb untuk new member, min belanja 75rb, expire akhir bulan",
  "Promo flash sale Lebaran: cashback 25rb, min 150rb, valid 3 hari",
];

function formatRupiah(n: number | null | undefined): string {
  if (n === null || n === undefined) return "—";
  return `Rp${new Intl.NumberFormat("id-ID").format(n)}`;
}

function formatDate(iso: string): string {
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return iso;
    return new Intl.DateTimeFormat("id-ID", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    }).format(d);
  } catch {
    return iso;
  }
}

export default function AIVoucherSuggestButton() {
  const [open, setOpen] = useState(false);
  const [prompt, setPrompt] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [suggestion, setSuggestion] = useState<AIVoucherSuggestion | null>(null);

  const reset = () => {
    setPrompt("");
    setError(null);
    setSuggestion(null);
    setLoading(false);
  };

  const close = () => {
    setOpen(false);
    reset();
  };

  const submit = async () => {
    if (loading) return;
    setLoading(true);
    setError(null);
    setSuggestion(null);
    try {
      const res = await fetch("/api/admin/ai/voucher-suggest", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ prompt }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error ?? "Gagal generate. Coba lagi.");
        return;
      }
      setSuggestion(data.suggestion);
    } catch (err) {
      setError(
        err instanceof Error
          ? `Network error: ${err.message}`
          : "Network error",
      );
    } finally {
      setLoading(false);
    }
  };

  /**
   * Apply suggestion ke form. Pakai querySelector by name, set value
   * + dispatch input event supaya React/form library refresh display.
   * Form server-side gak punya React state, jadi DOM set langsung
   * persist sampai submit.
   */
  const applyToForm = () => {
    if (!suggestion) return;

    const setField = (name: string, value: string | number | null) => {
      const el = document.querySelector<HTMLInputElement | HTMLSelectElement>(
        `[name="${name}"]`,
      );
      if (!el) return;
      el.value = value === null || value === undefined ? "" : String(value);
      // Fire change event supaya kalau ada controlled component, sync.
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
    };

    setField("name", suggestion.name);
    setField("code", suggestion.code);
    setField("description", suggestion.description);
    setField("type", suggestion.type);
    setField("discountPercent", suggestion.discountPercent);
    setField("discountAmount", suggestion.discountAmount);
    setField("maxDiscountAmount", suggestion.maxDiscountAmount);
    setField("minimumOrder", suggestion.minimumOrder);
    setField("maxUsage", suggestion.maxUsage);
    setField("usageLimitPerUser", suggestion.usageLimitPerUser);

    // Date field expects YYYY-MM-DDTHH:MM format (datetime-local).
    try {
      const expireDate = new Date(suggestion.expiresAt);
      if (!Number.isNaN(expireDate.getTime())) {
        // Format ke local datetime-local format.
        const pad = (n: number) => String(n).padStart(2, "0");
        const formatted = `${expireDate.getFullYear()}-${pad(expireDate.getMonth() + 1)}-${pad(expireDate.getDate())}T${pad(expireDate.getHours())}:${pad(expireDate.getMinutes())}`;
        setField("expiresAt", formatted);
      }
    } catch {
      // Skip kalau parse fail.
    }

    close();
    // Scroll to top form supaya user lihat field ke-isi.
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="mb-5 inline-flex items-center gap-2 rounded-lg border-2 border-purple-300 bg-purple-50 px-4 py-2 text-sm font-bold text-purple-800 hover:bg-purple-100"
      >
        <span>✨</span>
        Buat dengan AI (Claude)
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          onClick={close}
        >
          <div
            className="w-full max-w-lg rounded-2xl bg-white p-5 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-lg font-bold text-zinc-950">
                  ✨ Buat Voucher dengan AI
                </h2>
                <p className="mt-0.5 text-xs text-zinc-600">
                  Ceritakan promo yang mau dibuat, AI akan generate config.
                </p>
              </div>
              <button
                type="button"
                onClick={close}
                className="rounded-lg p-1 text-zinc-400 hover:bg-zinc-100"
              >
                ✕
              </button>
            </div>

            {!suggestion && (
              <>
                <textarea
                  value={prompt}
                  onChange={(e) => setPrompt(e.target.value)}
                  rows={4}
                  maxLength={2000}
                  disabled={loading}
                  placeholder="Contoh: Promo Imlek 5 hari, diskon 20% buat makanan kucing, min belanja 100rb, max potong 50rb"
                  className="mt-3 w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
                />
                <p className="mt-1 text-[11px] text-zinc-500">
                  {prompt.length}/2000 karakter
                </p>

                <div className="mt-3">
                  <p className="text-[11px] font-semibold uppercase text-zinc-500">
                    Contoh prompt:
                  </p>
                  <div className="mt-1 space-y-1">
                    {EXAMPLE_PROMPTS.map((ex, i) => (
                      <button
                        key={i}
                        type="button"
                        onClick={() => setPrompt(ex)}
                        disabled={loading}
                        className="block w-full text-left text-[11px] text-blue-700 hover:underline"
                      >
                        → {ex}
                      </button>
                    ))}
                  </div>
                </div>

                {error && (
                  <div className="mt-3 rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700">
                    ⚠️ {error}
                  </div>
                )}

                <div className="mt-4 flex gap-2">
                  <button
                    type="button"
                    onClick={submit}
                    disabled={loading || prompt.trim().length < 10}
                    className="flex-1 rounded-lg bg-purple-600 px-4 py-2 text-sm font-bold text-white hover:bg-purple-700 disabled:cursor-not-allowed disabled:bg-zinc-300"
                  >
                    {loading ? "Generating…" : "Generate"}
                  </button>
                  <button
                    type="button"
                    onClick={close}
                    className="rounded-lg border border-zinc-300 bg-white px-4 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-50"
                  >
                    Batal
                  </button>
                </div>
              </>
            )}

            {suggestion && (
              <>
                <div className="mt-3 rounded-lg border border-purple-200 bg-purple-50/50 p-3 text-xs">
                  <p className="font-semibold text-purple-900">
                    💡 {suggestion.reasoning}
                  </p>
                </div>

                <dl className="mt-3 space-y-1.5 text-xs">
                  <Row label="Nama">{suggestion.name}</Row>
                  <Row label="Kode" mono>
                    {suggestion.code}
                  </Row>
                  <Row label="Deskripsi">{suggestion.description}</Row>
                  <Row label="Type">{suggestion.type}</Row>
                  {suggestion.discountPercent && (
                    <Row label="Diskon %">{suggestion.discountPercent}%</Row>
                  )}
                  {suggestion.discountAmount && (
                    <Row label="Diskon Rp">
                      {formatRupiah(suggestion.discountAmount)}
                    </Row>
                  )}
                  {suggestion.maxDiscountAmount && (
                    <Row label="Max diskon">
                      {formatRupiah(suggestion.maxDiscountAmount)}
                    </Row>
                  )}
                  <Row label="Min belanja">
                    {formatRupiah(suggestion.minimumOrder)}
                  </Row>
                  <Row label="Max usage total">
                    {suggestion.maxUsage ?? "Unlimited"}
                  </Row>
                  <Row label="Limit per user">
                    {suggestion.usageLimitPerUser}× lifetime
                  </Row>
                  <Row label="Expire">{formatDate(suggestion.expiresAt)}</Row>
                  <Row label="Target">{suggestion.targetUser}</Row>
                </dl>

                <div className="mt-4 flex gap-2">
                  <button
                    type="button"
                    onClick={applyToForm}
                    className="flex-1 rounded-lg bg-purple-600 px-4 py-2 text-sm font-bold text-white hover:bg-purple-700"
                  >
                    ✓ Pakai sebagai draft
                  </button>
                  <button
                    type="button"
                    onClick={() => setSuggestion(null)}
                    className="rounded-lg border border-zinc-300 bg-white px-4 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-50"
                  >
                    Generate ulang
                  </button>
                </div>
                <p className="mt-2 text-[11px] text-zinc-500">
                  Setelah "Pakai", review + edit field di form bawah sebelum
                  Submit. AI bisa salah — pastikan config benar.
                </p>
              </>
            )}
          </div>
        </div>
      )}
    </>
  );
}

function Row({
  label,
  children,
  mono,
}: {
  label: string;
  children: React.ReactNode;
  mono?: boolean;
}) {
  return (
    <div className="flex items-baseline gap-3">
      <dt className="w-28 shrink-0 text-zinc-500">{label}</dt>
      <dd
        className={`flex-1 break-words text-zinc-900 ${mono ? "font-mono font-bold" : ""}`}
      >
        {children}
      </dd>
    </div>
  );
}
