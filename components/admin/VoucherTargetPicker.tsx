"use client";
import { useEffect, useId, useState } from "react";

type Option = { id: string; name: string; key?: string };
export function VoucherTargetPicker({ kind, name, label, defaultIds = [], hint }: {
  kind: "user" | "product" | "category"; name: string; label: string; defaultIds?: string[]; hint: string;
}) {
  const id = useId();
  const [selected, setSelected] = useState(defaultIds);
  const [labels, setLabels] = useState<Record<string, string>>({});
  const [query, setQuery] = useState("");
  const [options, setOptions] = useState<Option[]>([]);
  const [loading, setLoading] = useState(false);
  const [resolveError, setResolveError] = useState("");
  const [error, setError] = useState("");
  const [total, setTotal] = useState(0);
  const [retry, setRetry] = useState(0);
  const initialIds = defaultIds.join(",");
  useEffect(() => {
    if (!initialIds) return;

    const controller = new AbortController();
    fetch(`/api/admin/voucher-targets?${new URLSearchParams({ kind, ids: initialIds })}`, { signal: controller.signal })
      .then(async r => { if (!r.ok) throw new Error(); return r.json(); })
      .then(data => { setResolveError(""); setLabels(prev => ({ ...prev, ...Object.fromEntries(data.options.flatMap((o: Option) => [[o.id, o.name], ...(o.key ? [[o.key, o.name]] : [])])) })); })
      .catch(() => { if (!controller.signal.aborted) setResolveError("Nama pilihan tersimpan belum berhasil dimuat. Pilihan tetap dipertahankan."); });
    return () => controller.abort();
  }, [initialIds, kind, retry]);
  useEffect(() => {
    const controller = new AbortController();
    const timer = setTimeout(async () => {
      setLoading(true); setError("");
      try {
        const r = await fetch(`/api/admin/voucher-targets?${new URLSearchParams({ kind, q: query })}`, { signal: controller.signal });
        if (!r.ok) throw new Error();
        const data = await r.json(); setOptions(data.options); setTotal(data.total);
        setLabels(prev => ({ ...prev, ...Object.fromEntries(data.options.map((o: Option) => [o.id, o.name])) }));
      } catch { if (!controller.signal.aborted) { setOptions([]); setError("Pilihan gagal dimuat. Coba lagi."); } }
      finally { if (!controller.signal.aborted) setLoading(false); }
    }, 250);
    return () => { clearTimeout(timer); controller.abort(); };
  }, [query, kind, retry]);
  return <section className="rounded-xl border border-slate-200 bg-white p-4 space-y-3">
    <label htmlFor={id} className="block text-sm font-semibold text-slate-800">{label}</label>
    <p className="text-xs text-slate-500">{hint}</p>
    {resolveError && <p role="alert" className="text-xs text-amber-700">{resolveError}<button type="button" onClick={() => setRetry(v => v + 1)} className="ml-2 underline">Coba lagi</button></p>}
    <input type="hidden" name={name} value={selected.join(",")} />
    <div className="flex flex-wrap gap-2">{selected.map(key => <button type="button" key={key} onClick={() => setSelected(prev => prev.filter(v => v !== key))} aria-label={`Hapus pilihan ${labels[key] ?? key}`} className="min-h-10 rounded-lg bg-blue-50 px-3 text-xs text-blue-800">{labels[key] ?? "Pilihan tersimpan"} ×</button>)}</div>
    <input id={id} type="search" value={query} onChange={e => setQuery(e.target.value)} placeholder={kind === "user" ? "Cari nama, email, atau nomor pelanggan" : "Cari nama"} className="w-full rounded-xl border border-slate-300 px-3 py-2.5 text-sm" />
    {error ? <div role="alert" className="text-sm text-red-700">{error} <button type="button" onClick={() => setRetry(v => v + 1)} className="underline">Coba lagi</button></div> : loading ? <p role="status" className="text-xs text-slate-500">Memuat pilihan…</p> : <>
      <div className="max-h-52 overflow-y-auto divide-y divide-slate-100">{options.map(o => <label key={o.id} className="flex min-h-11 items-center gap-3 py-2 text-sm"><input type="checkbox" checked={selected.includes(o.id) || Boolean(o.key && selected.includes(o.key))} onChange={e => setSelected(prev => e.target.checked ? [...prev, o.id] : prev.filter(v => v !== o.id && v !== o.key))} />{o.name}</label>)}</div>
      <p className="text-xs text-slate-500">{kind === "user" && query.trim().length < 2 ? "Ketik minimal 2 karakter untuk mencari pelanggan." : total === 0 ? "Tidak ada hasil." : `${options.length} dari ${total} hasil${total > options.length ? "; persempit pencarian untuk hasil lainnya" : ""}.`} · {selected.length} dipilih</p>
    </>}
  </section>;
}
