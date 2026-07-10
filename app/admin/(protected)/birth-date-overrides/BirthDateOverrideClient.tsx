"use client";

/**
 * UI admin override tgl lahir customer:
 *   1. Search field (email/phone/name)
 *   2. List hasil dengan info utama + lock state
 *   3. Klik user → expand form override (date picker + reason + submit)
 *   4. Success/error banner dari useActionState
 *
 * Workflow CS pattern:
 *   - Customer email/WA: "tgl lahir saya salah, harusnya 1 Jan 1990"
 *   - CS buka page ini, search by email/phone
 *   - Klik user → expand form
 *   - Input tgl baru + alasan (mis. "Customer WA, KTP attached")
 *   - Submit → audit log otomatis
 *   - Inform customer di WA: "Sudah diubah ya, silakan cek di app"
 */
import { useState, useActionState, useTransition } from "react";
import { Button } from "@/components/admin/ui";
import {
  searchUserByQuery,
  unlockAndUpdateBirthDate,
  type UserSearchResult,
  type OverrideResult,
} from "./actions";

function formatDate(iso: string | null): string {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleDateString("id-ID", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    });
  } catch {
    return iso;
  }
}

const initialOverride: OverrideResult = { ok: false, message: "" };

export default function BirthDateOverrideClient() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<UserSearchResult[]>([]);
  const [selectedUser, setSelectedUser] = useState<UserSearchResult | null>(
    null,
  );
  const [searching, startSearching] = useTransition();
  const [searchError, setSearchError] = useState<string | null>(null);

  const [overrideState, overrideAction, overridePending] = useActionState(
    unlockAndUpdateBirthDate,
    initialOverride,
  );

  function handleSearch(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setSearchError(null);
    if (query.trim().length < 2) {
      setSearchError("Min 2 karakter untuk search.");
      return;
    }
    startSearching(async () => {
      try {
        const users = await searchUserByQuery(query);
        setResults(users);
        setSelectedUser(null);
        if (users.length === 0) {
          setSearchError("Tidak ada customer match.");
        }
      } catch (err) {
        setSearchError(err instanceof Error ? err.message : "Search gagal.");
      }
    });
  }

  return (
    <div className="mx-auto max-w-3xl px-4 py-6 md:py-10">
      <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
        Override Tanggal Lahir Customer
      </h1>
      <p className="mt-2 text-sm text-zinc-600">
        Tools untuk CS team unlock + ubah tgl lahir customer yang sudah ke-lock
        otomatis setelah dapat voucher ultah pertama. Semua override tercatat
        di audit log.
      </p>

      <div className="mt-6 rounded-2xl border-2 border-amber-200 bg-amber-50 p-4">
        <p className="text-sm font-bold text-amber-900">
          ⚠ Sebelum override, pastikan:
        </p>
        <ul className="mt-2 ml-4 list-disc text-sm text-amber-900 space-y-1">
          <li>
            Customer beneran request via WA / email (minta screenshot kalau
            ragu)
          </li>
          <li>
            Verifikasi identity — minimal sebutkan nama lengkap, email, atau
            no HP terdaftar
          </li>
          <li>Untuk perubahan tgl lahir krusial (mis. ubah jauh), minta foto KTP</li>
        </ul>
      </div>

      {/* Search form */}
      <form onSubmit={handleSearch} className="mt-6 space-y-3">
        <label className="block text-sm font-bold text-zinc-900">
          Cari customer
        </label>
        <div className="flex gap-2">
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Email, no HP, atau nama (min 2 karakter)"
            className="flex-1 rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
            disabled={searching}
          />
          <Button
            type="submit"
            disabled={searching || query.trim().length < 2}
          >
            {searching ? "Cari…" : "Cari"}
          </Button>
        </div>
        {searchError && (
          <p className="text-xs text-red-600">{searchError}</p>
        )}
      </form>

      {/* Search results */}
      {results.length > 0 && (
        <div className="mt-6">
          <p className="text-xs font-bold text-zinc-500 uppercase tracking-wide">
            {results.length} customer ditemukan
          </p>
          <div className="mt-3 space-y-2">
            {results.map((user) => (
              <button
                key={user.id}
                type="button"
                onClick={() => setSelectedUser(user)}
                className={`w-full text-left rounded-xl border-2 p-4 transition ${
                  selectedUser?.id === user.id
                    ? "border-zinc-900 bg-zinc-50"
                    : "border-zinc-200 bg-white hover:border-zinc-400"
                }`}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <p className="font-bold text-zinc-950 truncate">
                      {user.name}
                    </p>
                    <p className="text-xs text-zinc-600 truncate">
                      {user.email ?? "(no email)"} ·{" "}
                      {user.phone ?? "(no phone)"}
                    </p>
                    <p className="mt-1 text-xs text-zinc-500">
                      Member sejak {formatDate(user.createdAt)} · Tgl lahir:{" "}
                      <span className="font-bold text-zinc-700">
                        {formatDate(user.birthDate)}
                      </span>
                    </p>
                  </div>
                  <div className="flex flex-col items-end gap-1">
                    {user.birthDateLockedAt ? (
                      <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-black text-amber-800">
                        🔒 LOCKED
                      </span>
                    ) : (
                      <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-[10px] font-black text-emerald-700">
                        ✓ UNLOCKED
                      </span>
                    )}
                    {user.birthdayVoucherYear && (
                      <span className="text-[10px] text-zinc-500">
                        Voucher: {user.birthdayVoucherYear}
                      </span>
                    )}
                  </div>
                </div>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Override form (visible when user selected) */}
      {selectedUser && (
        <div className="mt-6 rounded-2xl border-2 border-zinc-900 bg-white p-5">
          <h2 className="text-lg font-black text-zinc-950">
            Override untuk: {selectedUser.name}
          </h2>
          <div className="mt-3 grid gap-2 text-sm sm:grid-cols-2">
            <div className="rounded-lg bg-zinc-50 p-3">
              <p className="text-[10px] font-bold uppercase tracking-wide text-zinc-500">
                Tgl lahir saat ini
              </p>
              <p className="mt-1 font-bold text-zinc-950">
                {formatDate(selectedUser.birthDate)}
              </p>
            </div>
            <div className="rounded-lg bg-zinc-50 p-3">
              <p className="text-[10px] font-bold uppercase tracking-wide text-zinc-500">
                Locked since
              </p>
              <p className="mt-1 font-bold text-zinc-950">
                {selectedUser.birthDateLockedAt
                  ? formatDate(selectedUser.birthDateLockedAt)
                  : "(belum di-lock)"}
              </p>
            </div>
          </div>

          {/* Success/error banner */}
          {overrideState.message && (
            <div
              className={`mt-4 rounded-xl p-3 text-sm font-semibold ${
                overrideState.ok
                  ? "bg-emerald-50 text-emerald-800"
                  : "bg-red-50 text-red-700"
              }`}
            >
              {overrideState.message}
            </div>
          )}

          <form action={overrideAction} className="mt-5 space-y-4">
            <input type="hidden" name="userId" value={selectedUser.id} />

            <div>
              <label className="block text-xs font-bold text-zinc-700 mb-1">
                Tgl lahir baru <span className="text-red-500">*</span>
              </label>
              <input
                type="date"
                name="newBirthDate"
                defaultValue={
                  selectedUser.birthDate
                    ? selectedUser.birthDate.slice(0, 10)
                    : ""
                }
                max={new Date().toISOString().slice(0, 10)}
                min="1900-01-01"
                required
                className="w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-zinc-700 mb-1">
                Alasan override <span className="text-red-500">*</span>{" "}
                <span className="font-normal text-zinc-500">
                  (min 10 karakter, tercatat di audit log)
                </span>
              </label>
              <textarea
                name="reason"
                rows={3}
                maxLength={500}
                required
                placeholder='Contoh: "Customer WA bilang salah input, tgl asli 1 Jan 1990. KTP sudah dilampirkan via email."'
                className="w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
              />
            </div>

            <div className="rounded-lg bg-blue-50 p-3 text-xs text-blue-900">
              <p className="font-bold">Setelah submit:</p>
              <ul className="mt-1 ml-4 list-disc space-y-0.5">
                <li>Tgl lahir customer di-update sesuai input</li>
                <li>
                  Status lock di-clear → customer bisa edit 1× lagi sendiri di
                  app
                </li>
                <li>
                  Tercatat di AdminActionLog dengan kamu sebagai actor + alasan
                </li>
                <li>
                  Kalau dapat voucher lagi → otomatis lock lagi (anti-abuse
                  tetap aktif)
                </li>
              </ul>
            </div>

            <div className="flex gap-2">
              <Button
                type="button"
                variant="secondary"
                onClick={() => setSelectedUser(null)}
                disabled={overridePending}
              >
                Batal
              </Button>
              <Button
                type="submit"
                variant="primary"
                disabled={overridePending}
                className="flex-1"
              >
                {overridePending ? "Memproses…" : "Update & Audit"}
              </Button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
