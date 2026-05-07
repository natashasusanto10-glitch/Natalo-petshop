"use client";

import { useState, useRef, useEffect } from "react";
import { formatRupiah } from "@/lib/format";

type Field = "price" | "stock";

interface Props {
  productId: string;
  field: Field;
  initialValue: number;
  /** Jika true, cell ditampilkan read-only (mis. produk dengan varian) */
  readOnly?: boolean;
  /** Hint tooltip saat readOnly */
  readOnlyHint?: string;
}

function formatPrice(n: number) {
  if (!n && n !== 0) return "";
  return Math.round(n).toLocaleString("id-ID");
}

function parsePrice(s: string) {
  const clean = s.replace(/\./g, "").replace(/[^\d]/g, "");
  return clean === "" ? 0 : parseInt(clean, 10);
}

export function InlineEditCell({
  productId,
  field,
  initialValue,
  readOnly,
  readOnlyHint,
}: Props) {
  const [value, setValue] = useState(initialValue);
  const [draft, setDraft] = useState(
    field === "price" ? formatPrice(initialValue) : String(initialValue)
  );
  const [saving, setSaving] = useState(false);
  const [savedAt, setSavedAt] = useState<number>(0);
  const [error, setError] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Sync ketika initialValue berubah (mis. setelah revalidate)
  useEffect(() => {
    setValue(initialValue);
    setDraft(field === "price" ? formatPrice(initialValue) : String(initialValue));
  }, [initialValue, field]);

  // Hilangkan flash "tersimpan" setelah 2 detik
  useEffect(() => {
    if (savedAt === 0) return;
    const t = setTimeout(() => setSavedAt(0), 2000);
    return () => clearTimeout(t);
  }, [savedAt]);

  if (readOnly) {
    return (
      <div title={readOnlyHint} className="cursor-help text-sm">
        {field === "price" ? (
          <span className="text-zinc-500">{formatRupiah(value)}</span>
        ) : (
          <span className="inline-flex items-center rounded-full bg-zinc-100 px-2 py-0.5 text-xs font-bold text-zinc-500">
            {value}
          </span>
        )}
        <p className="mt-0.5 text-[10px] italic text-zinc-400">via varian</p>
      </div>
    );
  }

  async function save(newVal: number) {
    if (newVal === value) return;
    setSaving(true);
    setError(null);
    try {
      const res = await fetch("/api/admin/products/bulk", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          updates: [{ id: productId, [field]: newVal }],
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data?.error || "Gagal simpan");
      setValue(newVal);
      setSavedAt(Date.now());
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal");
      // Revert ke nilai terakhir yang valid
      setDraft(field === "price" ? formatPrice(value) : String(value));
    } finally {
      setSaving(false);
    }
  }

  function handleBlur() {
    const num = field === "price" ? parsePrice(draft) : Number(draft);
    if (!Number.isFinite(num) || num < 0) {
      setDraft(field === "price" ? formatPrice(value) : String(value));
      return;
    }
    save(num);
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Enter") {
      e.preventDefault();
      inputRef.current?.blur();
    } else if (e.key === "Escape") {
      e.preventDefault();
      setDraft(field === "price" ? formatPrice(value) : String(value));
      inputRef.current?.blur();
    }
  }

  const isStockEmpty = field === "stock" && value === 0;
  const isStockLow = field === "stock" && value > 0 && value < 5;

  return (
    <div className="relative">
      <div
        className={`flex items-center gap-1 rounded-lg border px-2 py-1 transition focus-within:border-zinc-950 ${
          error
            ? "border-red-300 bg-red-50"
            : savedAt > 0
            ? "border-green-300 bg-green-50"
            : isStockEmpty
            ? "border-red-200 bg-red-50/50"
            : isStockLow
            ? "border-amber-200 bg-amber-50/50"
            : "border-transparent hover:border-zinc-200 bg-transparent"
        }`}
      >
        {field === "price" && <span className="text-xs text-zinc-400">Rp</span>}
        <input
          ref={inputRef}
          type={field === "stock" ? "number" : "text"}
          inputMode="numeric"
          min={field === "stock" ? 0 : undefined}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={handleBlur}
          onKeyDown={handleKeyDown}
          onFocus={(e) => e.target.select()}
          disabled={saving}
          className={`w-full bg-transparent text-sm font-medium text-zinc-950 outline-none disabled:opacity-50 ${
            field === "price" ? "text-right" : ""
          }`}
        />
        {saving && <span className="text-xs text-zinc-400">…</span>}
        {!saving && savedAt > 0 && <span className="text-xs text-green-600">✓</span>}
      </div>
      {error && (
        <p className="mt-1 text-[10px] font-semibold text-red-600">{error}</p>
      )}
    </div>
  );
}
