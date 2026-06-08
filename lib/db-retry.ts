import { Prisma } from "@prisma/client";

/**
 * Jalankan operasi DB (umumnya `prisma.$transaction` dengan isolation
 * Serializable) dengan retry otomatis saat Postgres melempar serialization
 * failure (kode 40001) atau deadlock (40P01) — Prisma surface keduanya
 * sebagai `P2034` ("Transaction failed due to a write conflict or a
 * deadlock. Please retry your transaction.").
 *
 * Kenapa perlu: Serializable isolation = Postgres ABORT salah satu dari
 * dua transaksi yang konflik (write-skew / concurrent stock deduct di
 * produk sama saat flash sale). Tanpa retry, user dapat error 500 padahal
 * percobaan ulang biasanya langsung sukses (transaksi lawannya sudah commit
 * + stok ke-update). Retry = UX mulus di momen high-traffic.
 *
 * PENTING: error bisnis (mis. StockConflictError, InsufficientPointsError)
 * BUKAN P2034 → langsung propagate tanpa retry. Itu memang kondisi gagal
 * yang sah (stok benar-benar habis) — retry tidak akan menolong.
 *
 * Operasi `fn` HARUS idempotent saat di-retry: seluruh isi $transaction
 * otomatis rollback pada P2034, jadi state DB bersih sebelum attempt
 * berikutnya. Pastikan tidak ada side-effect non-DB (kirim email, panggil
 * payment gateway) di dalam `fn` — taruh itu SETELAH operasi sukses.
 *
 * @param fn Operasi yang dijalankan (return Promise hasil transaksi).
 * @param opts.maxAttempts Total percobaan (default 3). Attempt terakhir
 *        yang gagal P2034 akan throw error-nya (caller handle jadi 409).
 * @param opts.baseDelayMs Backoff dasar — delay = baseDelayMs × attempt
 *        (linear). Default 25ms → 25, 50, 75... Kontensi checkout biasanya
 *        resolve cepat, jadi delay kecil cukup.
 */
export async function withSerializationRetry<T>(
  fn: () => Promise<T>,
  opts?: { maxAttempts?: number; baseDelayMs?: number }
): Promise<T> {
  const maxAttempts = opts?.maxAttempts ?? 3;
  const baseDelayMs = opts?.baseDelayMs ?? 25;

  let lastError: unknown;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastError = err;
      const isSerialization =
        err instanceof Prisma.PrismaClientKnownRequestError &&
        err.code === "P2034";
      // Bukan serialization failure → error bisnis / lainnya, propagate.
      // Atau ini attempt terakhir → propagate juga (caller handle).
      if (!isSerialization || attempt === maxAttempts - 1) {
        throw err;
      }
      // Linear backoff sebelum retry. Beri jeda supaya transaksi konflik
      // sempat commit & lepas lock.
      await new Promise((resolve) =>
        setTimeout(resolve, baseDelayMs * (attempt + 1))
      );
    }
  }
  // Secara normal unreachable (loop selalu return atau throw). Guard TS.
  throw lastError;
}

/**
 * True kalau error adalah Postgres serialization failure / deadlock
 * (Prisma P2034) yang sudah exhaust retry. Caller pakai untuk return
 * 409 "Sistem sibuk, coba lagi" alih-alih 500 generic.
 */
export function isSerializationFailure(error: unknown): boolean {
  return (
    error instanceof Prisma.PrismaClientKnownRequestError &&
    error.code === "P2034"
  );
}
