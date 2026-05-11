"use client";

import { useEffect, useState } from "react";

type Segment = "all" | "members" | "active30d" | "test";

type Result = {
  ok: boolean;
  segment?: Segment;
  recipientCount?: number;
  sent?: number;
  failed?: number;
  elapsed_ms?: number;
  dryRun?: boolean;
  error?: string;
};

type ChannelStats = { total: number; withUser: number; anonymous: number };
type PushStats = {
  totalRows: number;
  distinctUsersWithSub: number;
  anonymousRows: number;
  byChannel: { web: ChannelStats; apns: ChannelStats; fcm: ChannelStats; unknown: ChannelStats };
  env?: {
    vapid: { publicKey: boolean; privateKey: boolean; publicNext: boolean };
    apns: { keyId: boolean; teamId: boolean; keyContent: boolean; bundleId: string | null; production: string | null };
    fcm: { projectId: boolean; clientEmail: boolean; privateKey: boolean };
  };
};

type TestSelfResult = {
  ok: boolean;
  adminUserId?: string;
  subscriptionCount?: { web: number; apns: number; fcm: number; total: number };
  anonymousCount?: { web: number; apns: number; fcm: number };
  results?: {
    web: Array<{ endpointHint: string; status: "ok" | "error"; error?: string; statusCode?: number }>;
    apns: Array<{ tokenHint: string; status: "ok" | "error"; reason?: string; statusCode?: number }>;
    fcm: Array<{ tokenHint: string; status: "ok" | "error"; errorCode?: string; errorMsg?: string }>;
  };
  hint?: string;
  error?: string;
};

const SEGMENT_OPTIONS: Array<{ id: Segment; label: string; desc: string }> = [
  { id: "all", label: "Semua user", desc: "Semua yg subscribe push (PWA + iOS native)" },
  { id: "members", label: "Member (pernah belanja)", desc: "User dgn min. 1 order paymentStatus=PAID" },
  { id: "active30d", label: "Aktif 30 hari", desc: "User yg order dalam 30 hari terakhir" },
  { id: "test", label: "Test ke saya", desc: "Cuma admin yang trigger — preview test" },
];

export function BroadcastForm() {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [url, setUrl] = useState("");
  const [segment, setSegment] = useState<Segment>("test");
  const [recipientCount, setRecipientCount] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [result, setResult] = useState<Result | null>(null);
  const [error, setError] = useState("");
  const [stats, setStats] = useState<PushStats | null>(null);
  const [testRunning, setTestRunning] = useState(false);
  const [testResult, setTestResult] = useState<TestSelfResult | null>(null);

  const canSubmit = title.trim().length > 0 && body.trim().length > 0 && !loading;

  async function runTestPush() {
    setTestRunning(true);
    setTestResult(null);
    try {
      const res = await fetch("/api/admin/push/test-self", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });
      const text = await res.text();
      let data: TestSelfResult;
      try {
        data = JSON.parse(text) as TestSelfResult;
      } catch {
        data = { ok: false, error: `HTTP ${res.status} non-JSON: ${text.slice(0, 200)}` };
      }
      setTestResult(data);
    } catch (err) {
      setTestResult({ ok: false, error: err instanceof Error ? err.message : "Network error" });
    } finally {
      setTestRunning(false);
    }
  }

  // Auto-fetch breakdown subscriber pada mount — supaya admin langsung tahu
  // berapa device subscribed (per channel + with/without userId), tanpa
  // perlu klik "Cek jumlah" dulu. Bantu diagnose kalau "Semua user" return 0.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch("/api/admin/push/stats");
        if (!res.ok) return;
        const data = (await res.json()) as PushStats & { ok: boolean };
        if (!cancelled && data.ok) setStats(data);
      } catch {
        // silent — stats panel cuma diagnostic, gak boleh block form
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Helper: parse response defensively. Kalau server return HTML (timeout
  // page / crash) bukan JSON, surface info status code supaya errornya useful.
  async function readResponseSafely(res: Response): Promise<Result> {
    const text = await res.text().catch(() => "");
    try {
      return JSON.parse(text) as Result;
    } catch {
      const snippet = text.slice(0, 120).replace(/\s+/g, " ").trim();
      return {
        ok: false,
        error: `HTTP ${res.status} non-JSON response${snippet ? ` — ${snippet}` : ""}`,
      };
    }
  }

  async function checkRecipientCount() {
    setError("");
    setLoading(true);
    try {
      const res = await fetch("/api/admin/push/broadcast", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title: title || "preview", body: body || "preview", url, segment, dryRun: true }),
      });
      const data = await readResponseSafely(res);
      if (!res.ok) {
        setError(data.error ?? `Gagal cek recipient (HTTP ${res.status})`);
        return;
      }
      setRecipientCount(data.recipientCount ?? 0);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "network";
      setError(`Gagal cek recipient (${msg})`);
    } finally {
      setLoading(false);
    }
  }

  async function sendBroadcast() {
    setError("");
    setResult(null);
    setLoading(true);
    try {
      const res = await fetch("/api/admin/push/broadcast", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title, body, url, segment }),
      });
      const data = await readResponseSafely(res);
      if (!res.ok) {
        setError(data.error ?? `Gagal kirim broadcast (HTTP ${res.status})`);
        return;
      }
      setResult(data);
      setConfirming(false);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "network";
      setError(`Gagal kirim broadcast (${msg})`);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-5">
      {stats && (
        <div className="rounded-xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-900">
          <p className="font-bold">📊 Subscriber di DB</p>
          <div className="mt-1.5 grid grid-cols-2 gap-x-4 gap-y-0.5 text-xs sm:grid-cols-4">
            <span>Total: <strong>{stats.totalRows}</strong></span>
            <span>Web: <strong>{stats.byChannel.web.total}</strong></span>
            <span>APNs (iOS): <strong>{stats.byChannel.apns.total}</strong></span>
            <span>FCM (Android): <strong>{stats.byChannel.fcm.total}</strong></span>
            <span className="col-span-2">User unique (login): <strong>{stats.distinctUsersWithSub}</strong></span>
            <span className="col-span-2">Anonymous (belum login): <strong>{stats.anonymousRows}</strong></span>
          </div>
          {stats.totalRows > 0 && stats.distinctUsersWithSub === 0 && (
            <p className="mt-2 text-xs font-semibold text-amber-700">
              ⚠️ Semua subscription anonymous (userId null). Segment &quot;Semua user&quot; akan return 0
              karena query filter <code>userId IS NOT NULL</code>. Subscriber subscribe push sebelum
              login, jadi gak ke-link ke akun mereka.
            </p>
          )}

          {stats.env && (
            <div className="mt-3 border-t border-blue-200 pt-2">
              <p className="text-xs font-bold uppercase tracking-wide text-blue-800">Env config (Vercel)</p>
              <div className="mt-1 grid grid-cols-1 gap-x-4 gap-y-0.5 text-xs sm:grid-cols-3">
                <span>
                  VAPID:{" "}
                  <strong>
                    {stats.env.vapid.publicKey && stats.env.vapid.privateKey && stats.env.vapid.publicNext
                      ? "✓ lengkap"
                      : "⚠ kurang"}
                  </strong>
                </span>
                <span>
                  APNs:{" "}
                  <strong>
                    {stats.env.apns.keyId && stats.env.apns.teamId && stats.env.apns.keyContent
                      ? "✓ lengkap"
                      : "⚠ kurang"}
                  </strong>
                </span>
                <span>
                  FCM:{" "}
                  <strong>
                    {stats.env.fcm.projectId && stats.env.fcm.clientEmail && stats.env.fcm.privateKey
                      ? "✓ lengkap"
                      : "⚠ kurang"}
                  </strong>
                </span>
                <span className="col-span-1 sm:col-span-3">
                  APNS_PRODUCTION: <strong>{stats.env.apns.production ?? "(unset)"}</strong>
                  {stats.env.apns.production !== "true" && (
                    <span className="ml-1 font-semibold text-amber-700">
                      — TestFlight pakai PRODUCTION! Set ke &quot;true&quot;.
                    </span>
                  )}
                </span>
                <span className="col-span-1 sm:col-span-3">
                  APNS_BUNDLE_ID: <strong>{stats.env.apns.bundleId ?? "(default com.natalo.petshop)"}</strong>
                </span>
              </div>
            </div>
          )}

          <div className="mt-3 border-t border-blue-200 pt-2">
            <button
              type="button"
              onClick={runTestPush}
              disabled={testRunning}
              className="rounded-full border border-blue-300 bg-white px-4 py-1.5 text-xs font-bold text-blue-700 transition hover:bg-blue-100 disabled:opacity-50"
            >
              {testRunning ? "Mengirim test..." : "🧪 Test push ke device admin (debug)"}
            </button>
          </div>
        </div>
      )}

      {testResult && (
        <div
          className={`rounded-xl border px-4 py-3 text-sm ${
            testResult.ok ? "border-emerald-200 bg-emerald-50 text-emerald-900" : "border-red-200 bg-red-50 text-red-900"
          }`}
        >
          <p className="font-bold">{testResult.ok ? "🧪 Test push hasil" : "❌ Test push gagal"}</p>
          {testResult.error && <p className="mt-1 text-xs">{testResult.error}</p>}
          {testResult.hint && <p className="mt-1 text-xs italic">{testResult.hint}</p>}
          {testResult.subscriptionCount && (
            <p className="mt-2 text-xs">
              Subscription admin: <strong>{testResult.subscriptionCount.total}</strong>{" "}
              (web {testResult.subscriptionCount.web} · apns {testResult.subscriptionCount.apns} · fcm{" "}
              {testResult.subscriptionCount.fcm})
            </p>
          )}
          {testResult.anonymousCount && (
            <p className="mt-1 text-xs">
              Anonymous di DB: web {testResult.anonymousCount.web} · apns {testResult.anonymousCount.apns} · fcm{" "}
              {testResult.anonymousCount.fcm}
            </p>
          )}
          {testResult.results && (
            <div className="mt-2 space-y-1.5 text-xs">
              {testResult.results.apns.length > 0 && (
                <div>
                  <p className="font-bold">APNs:</p>
                  {testResult.results.apns.map((r, i) => (
                    <p key={i} className="font-mono">
                      {r.status === "ok" ? "✓" : "✗"} {r.tokenHint}
                      {r.reason && <> — {r.reason}</>}
                      {typeof r.statusCode === "number" && <> (HTTP {r.statusCode})</>}
                    </p>
                  ))}
                </div>
              )}
              {testResult.results.web.length > 0 && (
                <div>
                  <p className="font-bold">Web Push:</p>
                  {testResult.results.web.map((r, i) => (
                    <p key={i} className="font-mono">
                      {r.status === "ok" ? "✓" : "✗"} {r.endpointHint}
                      {r.error && <> — {r.error}</>}
                      {typeof r.statusCode === "number" && <> (HTTP {r.statusCode})</>}
                    </p>
                  ))}
                </div>
              )}
              {testResult.results.fcm.length > 0 && (
                <div>
                  <p className="font-bold">FCM:</p>
                  {testResult.results.fcm.map((r, i) => (
                    <p key={i} className="font-mono">
                      {r.status === "ok" ? "✓" : "✗"} {r.tokenHint}
                      {r.errorCode && <> — {r.errorCode}</>}
                      {r.errorMsg && <>: {r.errorMsg}</>}
                    </p>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      )}

      <div>
        <label className="block text-sm font-bold text-zinc-700">Title</label>
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          maxLength={60}
          placeholder="Promo Akhir Pekan 🔥"
          className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-400"
        />
        <p className="mt-1 text-xs text-zinc-400">{title.length}/60 karakter</p>
      </div>

      <div>
        <label className="block text-sm font-bold text-zinc-700">Pesan (body)</label>
        <textarea
          value={body}
          onChange={(e) => setBody(e.target.value)}
          maxLength={180}
          rows={3}
          placeholder="Diskon 20% semua pakan kucing s/d besok. Klik untuk lihat produk."
          className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-400"
        />
        <p className="mt-1 text-xs text-zinc-400">{body.length}/180 karakter</p>
      </div>

      <div>
        <label className="block text-sm font-bold text-zinc-700">URL tujuan saat di-klik (opsional)</label>
        <input
          type="text"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          placeholder="/products?kategori=kucing  (default: /)"
          className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-400"
        />
      </div>

      <div>
        <label className="block text-sm font-bold text-zinc-700">Target audience</label>
        <div className="mt-2 space-y-2">
          {SEGMENT_OPTIONS.map((opt) => (
            <label
              key={opt.id}
              className={`flex cursor-pointer items-start gap-3 rounded-xl border px-4 py-3 transition ${
                segment === opt.id ? "border-natalo-400 bg-natalo-50" : "border-zinc-200 bg-white"
              }`}
            >
              <input
                type="radio"
                name="segment"
                value={opt.id}
                checked={segment === opt.id}
                onChange={() => {
                  setSegment(opt.id);
                  setRecipientCount(null);
                }}
                className="mt-1 h-4 w-4 accent-natalo-600"
              />
              <span className="min-w-0 flex-1">
                <span className="block text-sm font-bold text-zinc-950">{opt.label}</span>
                <span className="mt-0.5 block text-xs text-zinc-500">{opt.desc}</span>
              </span>
            </label>
          ))}
        </div>
      </div>

      <div className="rounded-xl border border-zinc-200 bg-zinc-50 px-4 py-3">
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="text-xs font-bold text-zinc-500 uppercase tracking-wide">Estimasi penerima</p>
            <p className="mt-1 text-2xl font-black text-zinc-900">
              {recipientCount !== null ? recipientCount.toLocaleString("id-ID") : "—"} user
            </p>
          </div>
          <button
            type="button"
            onClick={checkRecipientCount}
            disabled={loading}
            className="rounded-full border border-zinc-300 bg-white px-4 py-2 text-xs font-bold text-zinc-700 disabled:opacity-50"
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
          <p className="font-bold">✅ Broadcast selesai</p>
          <ul className="mt-1.5 space-y-0.5 text-xs">
            <li>Segment: <strong>{result.segment}</strong></li>
            <li>Total recipient: <strong>{result.recipientCount}</strong></li>
            <li>Sukses: <strong>{result.sent}</strong></li>
            <li>Gagal: <strong>{result.failed}</strong></li>
            <li>Durasi: <strong>{result.elapsed_ms}ms</strong></li>
          </ul>
        </div>
      )}

      <div className="flex gap-3 pt-2">
        {!confirming ? (
          <button
            type="button"
            onClick={() => {
              if (!canSubmit) return;
              if (segment === "test") {
                // Test mode → langsung kirim ke admin saja, tidak perlu konfirmasi
                void sendBroadcast();
              } else {
                setConfirming(true);
              }
            }}
            disabled={!canSubmit}
            className="flex-1 rounded-full bg-natalo-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:bg-zinc-300"
          >
            {segment === "test" ? "Test ke saya" : "Kirim broadcast"}
          </button>
        ) : (
          <>
            <button
              type="button"
              onClick={() => setConfirming(false)}
              disabled={loading}
              className="flex-1 rounded-full border border-zinc-300 bg-white px-6 py-3 text-sm font-bold text-zinc-700 disabled:opacity-50"
            >
              Batal
            </button>
            <button
              type="button"
              onClick={sendBroadcast}
              disabled={loading}
              className="flex-1 rounded-full bg-red-600 px-6 py-3 text-sm font-bold text-white transition active:bg-red-700 disabled:bg-zinc-300"
            >
              {loading ? "Mengirim..." : `Konfirmasi kirim${recipientCount !== null ? ` ke ${recipientCount} user` : ""}`}
            </button>
          </>
        )}
      </div>
    </div>
  );
}
