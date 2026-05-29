/**
 * Welcome voucher — auto-grant ke user baru saat first register
 * sukses. Engagement nudge supaya user transaksi pertama (kebanyakan
 * abandon antara register & first order).
 *
 * Dipakai di `app/api/auth/member-register/route.ts` step-2 (verify
 * OTP + create user). Fire-and-forget — kalau voucher creation gagal,
 * register tetap sukses (user gak terblock).
 *
 * Config: lihat WELCOME_VOUCHER_CONFIG. Tweak nominal/min order sesuai
 * business strategy. Voucher di-issue 1× per user (enforced via cek
 * existing voucher code-prefix WELCOME- di voucher table).
 *
 * KEPUTUSAN BISNIS (Mei 2026): WELCOME adalah SATU-SATUNYA voucher
 * new-customer. Voucher manual NATA-NEW (Rp50k) sengaja di-nonaktifkan
 * (di dashboard admin, bukan code) untuk konsolidasi ke 1 sistem:
 *   - Auto-grant (semua customer baru pasti kebagian, NATA-NEW butuh
 *     user tau kodenya + pool terbatas 50x yg habis di customer ke-51).
 *   - Per-user, tak terbatas jumlah customer.
 * Nominal SENGAJA ditahan Rp25k (BUKAN Rp50k seperti NATA-NEW): WELCOME
 * auto-dikasih ke siapa saja yg daftar (cukup nomor HP + OTP), jadi
 * nominal besar = umpan farming akun. NATA-NEW boleh Rp50k DULU karena
 * pool-nya dibatasi 50x (kerugian max terkunci). JANGAN naikkan ke Rp50k
 * tanpa proteksi tambahan (mis. min belanja naik / syarat akun verified)
 * + data abuse yg menunjukkan aman.
 */
import { randomBytes } from "crypto";
import { prisma } from "@/lib/prisma";

export const WELCOME_VOUCHER_CONFIG = {
  /** Nominal diskon. Smaller than birthday (Rp50k) karena gratis
   *  untuk register — anti scammer farming akun. */
  discountAmount: 25_000,
  /** Min belanja. Higher than discount nominal supaya margin positif
   *  + filter "sekedar coba" user. */
  minimumOrder: 100_000,
  /** Berapa hari valid setelah register. 30 hari memberi user
   *  ruang explore + first impression sebelum voucher expire. */
  expiresAfterDays: 30,
};

/**
 * Grant welcome voucher untuk user baru. Idempotent — check kalau
 * user sudah pernah dapat (code prefix `WELCOME-` ada di Voucher
 * table for this userId), skip create. Penting kalau register flow
 * di-retry atau ada double-trigger.
 *
 * Return voucher code yang baru di-create, atau null kalau skipped
 * (already granted) atau error (logged + swallowed).
 */
export async function grantWelcomeVoucher(
  userId: string,
): Promise<string | null> {
  try {
    // Idempotency check — skip kalau user sudah punya welcome voucher.
    // Pakai code prefix match karena Voucher table gak punya field
    // dedicated untuk "source"/origin.
    const existing = await prisma.voucher.findFirst({
      where: {
        userId,
        code: { startsWith: "WELCOME-" },
      },
      select: { id: true },
    });
    if (existing) {
      return null;
    }

    const code = `WELCOME-${randomBytes(3).toString("hex").toUpperCase()}`;
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + WELCOME_VOUCHER_CONFIG.expiresAfterDays);

    await prisma.voucher.create({
      data: {
        code,
        name: "Voucher Selamat Datang",
        description: `Voucher pertama untukmu! Diskon Rp${WELCOME_VOUCHER_CONFIG.discountAmount.toLocaleString("id-ID")} (min belanja Rp${WELCOME_VOUCHER_CONFIG.minimumOrder.toLocaleString("id-ID")}).`,
        discountAmount: WELCOME_VOUCHER_CONFIG.discountAmount,
        minimumOrder: WELCOME_VOUCHER_CONFIG.minimumOrder,
        maxUsage: 1,
        usedCount: 0,
        usageLimitPerUser: 1,
        expiresAt,
        isActive: true,
        userId,
        sourceType: "CUSTOMER",
        type: "PUBLIC_PRODUCT_DISCOUNT",
        kind: "PRODUCT_DISCOUNT",
        visibility: "USER_OWNED",
        discountType: "FIXED_AMOUNT",
        discountScope: "PRODUCT",
      },
    });
    return code;
  } catch (err) {
    console.warn("[welcome-voucher] grant failed:", {
      userId,
      error: err instanceof Error ? err.message : String(err),
    });
    return null;
  }
}
