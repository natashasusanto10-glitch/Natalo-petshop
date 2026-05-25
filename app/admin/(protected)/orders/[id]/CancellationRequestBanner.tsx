"use client";

/**
 * Banner "Permintaan Pembatalan dari Customer" — muncul di atas order
 * detail saat customer sudah submit cancel request (paymentStatus=PAID
 * dan user pencet "Batalkan" di app).
 *
 * Admin lihat alasan customer + dua tombol:
 *   - [Setujui & Refund] → konfirmasi → run approveCancellationRequest.
 *     Action ini jalanin markAsCancelled internally, jadi auto-refund
 *     full + restore stock + voucher rollback + push notif customer.
 *   - [Tolak] → expand textarea reject reason → submit
 *     rejectCancellationRequest. Status order tidak berubah.
 *
 * Status guard di server: kalau cancellationRequestStatus !== "PENDING"
 * server return error. Page revalidate → banner hilang setelah action.
 *
 * Banner juga menampilkan history kalau request sudah APPROVED / REJECTED
 * sebelumnya — visible buat audit trail. APPROVED otomatis berarti order
 * sudah CANCELLED (parent page biasanya udah render "Dibatalkan" banner).
 */
import { useState, useTransition } from "react";

type Props = {
  status: "PENDING" | "APPROVED" | "REJECTED";
  reason: string | null;
  requestedAt: string | null;
  respondedAt: string | null;
  rejectReason: string | null;
  approveAction: () => Promise<void>;
  rejectAction: (formData: FormData) => Promise<void>;
};

function formatTime(iso: string | null): string {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString("id-ID", {
      day: "2-digit",
      month: "short",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return iso;
  }
}

export default function CancellationRequestBanner({
  status,
  reason,
  requestedAt,
  respondedAt,
  rejectReason,
  approveAction,
  rejectAction,
}: Props) {
  const [isPending, startTransition] = useTransition();
  const [showRejectForm, setShowRejectForm] = useState(false);
  const [rejectInput, setRejectInput] = useState("");
  const [error, setError] = useState<string | null>(null);

  // History view: APPROVED → cancel sudah dieksekusi (parent show "Dibatalkan"
  // section). REJECTED → tampilkan info "ditolak" supaya admin audit ulang.
  if (status === "APPROVED") {
    return (
      <div className="mt-4 rounded-2xl border border-emerald-200 bg-emerald-50 p-4 text-sm">
        <p className="font-bold text-emerald-800">
          ✓ Permintaan pembatalan telah disetujui
        </p>
        <p className="mt-1 text-xs text-emerald-700">
          Customer minta batal pada {formatTime(requestedAt)}, disetujui pada{" "}
          {formatTime(respondedAt)}.
          {reason && (
            <>
              <br />
              Alasan customer: <em>&quot;{reason}&quot;</em>
            </>
          )}
        </p>
      </div>
    );
  }

  if (status === "REJECTED") {
    return (
      <div className="mt-4 rounded-2xl border border-zinc-200 bg-zinc-50 p-4 text-sm">
        <p className="font-bold text-zinc-700">
          ⊘ Permintaan pembatalan ditolak
        </p>
        <p className="mt-1 text-xs text-zinc-600">
          Customer minta batal pada {formatTime(requestedAt)}, ditolak pada{" "}
          {formatTime(respondedAt)}.
        </p>
        {reason && (
          <p className="mt-2 text-xs text-zinc-600">
            Alasan customer: <em>&quot;{reason}&quot;</em>
          </p>
        )}
        {rejectReason && (
          <p className="mt-1 text-xs text-zinc-600">
            Alasan penolakan: <em>&quot;{rejectReason}&quot;</em>
          </p>
        )}
      </div>
    );
  }

  // PENDING — actionable banner.
  async function handleApprove() {
    setError(null);
    const ok = window.confirm(
      "Setujui permintaan pembatalan?\n\n" +
        "• Order akan otomatis di-CANCEL\n" +
        "• Stock dikembalikan + voucher dibebaskan\n" +
        "• Total order otomatis kredit ke Saldo Refund customer\n\n" +
        "Lanjutkan?",
    );
    if (!ok) return;
    startTransition(async () => {
      try {
        await approveAction();
      } catch (err) {
        setError(err instanceof Error ? err.message : "Gagal menyetujui.");
      }
    });
  }

  async function handleReject(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    if (rejectInput.trim().length === 0) {
      setError("Alasan penolakan wajib diisi supaya customer paham.");
      return;
    }
    const formData = new FormData();
    formData.set("rejectReason", rejectInput.trim());
    startTransition(async () => {
      try {
        await rejectAction(formData);
        setShowRejectForm(false);
        setRejectInput("");
      } catch (err) {
        setError(err instanceof Error ? err.message : "Gagal menolak.");
      }
    });
  }

  return (
    <div className="mt-4 rounded-2xl border-2 border-amber-300 bg-amber-50 p-4 shadow-sm">
      <div className="flex items-start gap-3">
        <div className="text-2xl">⚠️</div>
        <div className="flex-1">
          <p className="font-bold text-amber-900">
            Customer minta batal pesanan
          </p>
          <p className="mt-1 text-xs text-amber-800">
            Diajukan {formatTime(requestedAt)}
          </p>
          {reason ? (
            <div className="mt-3 rounded-xl bg-white/60 p-3 text-sm">
              <p className="text-xs font-semibold text-amber-900">
                Alasan customer:
              </p>
              <p className="mt-1 text-zinc-900">{reason}</p>
            </div>
          ) : (
            <p className="mt-2 text-xs italic text-amber-700">
              Customer tidak menyertakan alasan.
            </p>
          )}

          {error && (
            <div className="mt-3 rounded-lg bg-red-100 p-2 text-xs font-semibold text-red-700">
              {error}
            </div>
          )}

          {!showRejectForm ? (
            <div className="mt-4 flex flex-wrap gap-2">
              <button
                type="button"
                onClick={handleApprove}
                disabled={isPending}
                className="rounded-full bg-amber-600 px-4 py-2 text-xs font-bold text-white hover:bg-amber-700 disabled:opacity-50"
              >
                {isPending ? "Memproses..." : "Setujui & Refund"}
              </button>
              <button
                type="button"
                onClick={() => setShowRejectForm(true)}
                disabled={isPending}
                className="rounded-full border border-amber-300 bg-white px-4 py-2 text-xs font-bold text-amber-800 hover:bg-amber-100 disabled:opacity-50"
              >
                Tolak
              </button>
            </div>
          ) : (
            <form onSubmit={handleReject} className="mt-4 space-y-2">
              <label className="block text-xs font-semibold text-amber-900">
                Alasan penolakan (akan ditampilkan ke customer):
              </label>
              <textarea
                value={rejectInput}
                onChange={(e) => setRejectInput(e.target.value)}
                rows={3}
                maxLength={500}
                placeholder="Contoh: Pesanan sudah dalam proses packing dan tidak bisa dibatalkan. Mohon tunggu paket sampai dan ajukan retur jika ada masalah."
                className="w-full rounded-lg border border-amber-300 bg-white px-3 py-2 text-sm placeholder:text-zinc-400 focus:border-amber-500 focus:outline-none"
                disabled={isPending}
              />
              <div className="flex gap-2">
                <button
                  type="submit"
                  disabled={isPending}
                  className="rounded-full bg-red-600 px-4 py-2 text-xs font-bold text-white hover:bg-red-700 disabled:opacity-50"
                >
                  {isPending ? "Memproses..." : "Kirim Penolakan"}
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setShowRejectForm(false);
                    setError(null);
                  }}
                  disabled={isPending}
                  className="rounded-full border border-zinc-300 bg-white px-4 py-2 text-xs font-bold text-zinc-700 hover:bg-zinc-100 disabled:opacity-50"
                >
                  Batal
                </button>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
