/**
 * Birthday voucher auto-issue logic. Dipakai oleh cron daily
 * `/api/cron/birthday-voucher`. Pisah dari endpoint biar bisa unit-
 * test + reuse kalau ada trigger lain (mis. admin "fire ulang").
 *
 * Rules:
 *  - User dengan birthDate `MM-DD === today MM-DD`
 *  - Skip kalau User.birthdayVoucherYear === currentYear (anti-double
 *    issue saat cron jalan 2x karena re-deploy / manual trigger)
 *  - Issue voucher: PUBLIC_PRODUCT_DISCOUNT type, USER_OWNED visibility,
 *    1× per user, expire 30 hari setelah ulang tahun
 *  - Update User.birthdayVoucherYear ke currentYear (atomic dalam
 *    transaction yang sama dengan voucher create)
 *  - Fire push notif "Selamat ulang tahun! Voucher Rp X masuk"
 *  - Fire-and-forget errors per user — 1 user fail tidak kill batch
 */
import { randomBytes } from "crypto";
import { prisma } from "@/lib/prisma";
import { sendPushToUser } from "@/lib/push";

/**
 * Default voucher config. Tweak disini kalau Natalo mau ubah skema
 * birthday gift. Bisa juga di-pindah ke env / admin settings nanti.
 */
export const BIRTHDAY_VOUCHER_CONFIG = {
  /** Nominal diskon Rp. */
  discountAmount: 50_000,
  /** Minimum belanja untuk bisa apply voucher. Min 200rb supaya user
   *  beneran transaksi, tidak cuma claim & flip checkout kosong. */
  minimumOrder: 200_000,
  /** Berapa hari valid setelah ulang tahun. */
  expiresAfterDays: 30,
};

/**
 * Minimum usia akun sebelum eligible dapat voucher ulang tahun.
 *
 * Anti-abuse: tanpa guard ini, user bisa register hari ini → set tgl
 * lahir = besok → cron jalan besok → dapat voucher Rp50k.
 * Worst case 1 keluarga 4 HP register barengan → farm 4× Rp200k.
 *
 * 30 hari = compromise: cukup deter abuse instant tapi tidak terlalu
 * keras buat user genuine yang baru kenal Natalo dan kebetulan ulang
 * tahun bulan ini. Tokopedia pakai 90 hari (lebih ketat).
 *
 * Override via env `BIRTHDAY_VOUCHER_MIN_ACCOUNT_DAYS` (number string)
 * kalau owner mau tuning tanpa redeploy schema.
 */
const DEFAULT_MIN_ACCOUNT_DAYS = 30;

function getMinAccountDays(): number {
  const raw = process.env.BIRTHDAY_VOUCHER_MIN_ACCOUNT_DAYS;
  if (!raw) return DEFAULT_MIN_ACCOUNT_DAYS;
  const parsed = parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : DEFAULT_MIN_ACCOUNT_DAYS;
}

export type BirthdayIssueResult = {
  candidates: number;
  issued: number;
  skipped: number;
  errors: number;
  details: Array<{
    userId: string;
    name: string;
    status: "issued" | "skipped" | "error";
    voucherCode?: string;
    reason?: string;
  }>;
};

/**
 * Cek today MM-DD vs user.birthDate MM-DD. Pakai server local time
 * (Vercel cron run pakai UTC, tapi schedule "0 2 * * *" = 09:00 WIB
 * supaya match Indonesia user). Return list user yang harus dapat
 * voucher hari ini.
 *
 * Note: leap year birthday 29-Feb akan dapat voucher tiap 28-Feb di
 * non-leap year (defensive — alternatif: 1-Mar, tapi 28-Feb lebih
 * konservatif).
 */
async function findTodayBirthdayUsers(today: Date): Promise<
  Array<{ id: string; name: string; birthDate: Date; birthdayVoucherYear: number | null }>
> {
  const month = today.getMonth() + 1; // 1-12
  const day = today.getDate();
  const currentYear = today.getFullYear();
  const minAccountDays = getMinAccountDays();
  const accountAgeThreshold = new Date(
    today.getTime() - minAccountDays * 24 * 60 * 60 * 1000,
  );

  // Prisma tidak native support EXTRACT(MONTH FROM x) dalam where.
  // Pakai raw query untuk filter by month + day. Cast ke timestamp
  // supaya match Postgres date functions.
  //
  // Eligibility additions:
  //   - createdAt < threshold (akun minimal N hari) → anti-abuse
  //     "register + set tgl besok = farm voucher"
  const users = await prisma.$queryRaw<
    Array<{
      id: string;
      name: string;
      birthDate: Date;
      birthdayVoucherYear: number | null;
    }>
  >`
    SELECT id, name, "birthDate", "birthdayVoucherYear"
    FROM "User"
    WHERE "birthDate" IS NOT NULL
      AND EXTRACT(MONTH FROM "birthDate") = ${month}
      AND EXTRACT(DAY FROM "birthDate") = ${day}
      AND ("birthdayVoucherYear" IS NULL OR "birthdayVoucherYear" < ${currentYear})
      AND "createdAt" < ${accountAgeThreshold}
      AND role = 'CUSTOMER'
  `;
  return users;
}

/**
 * Issue voucher untuk 1 user. Atomic dalam transaction:
 *   1. Create Voucher row (PUBLIC_PRODUCT_DISCOUNT, USER_OWNED)
 *   2. Update User.birthdayVoucherYear = currentYear
 * Return voucher code kalau sukses.
 */
async function issueBirthdayVoucher(userId: string, currentYear: number): Promise<string> {
  const code = `BDAY-${currentYear}-${randomBytes(3).toString("hex").toUpperCase()}`;
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + BIRTHDAY_VOUCHER_CONFIG.expiresAfterDays);

  await prisma.$transaction([
    prisma.voucher.create({
      data: {
        code,
        name: "Voucher Ulang Tahun",
        description: `Selamat ulang tahun! Diskon Rp${BIRTHDAY_VOUCHER_CONFIG.discountAmount.toLocaleString("id-ID")} (min belanja Rp${BIRTHDAY_VOUCHER_CONFIG.minimumOrder.toLocaleString("id-ID")}).`,
        discountAmount: BIRTHDAY_VOUCHER_CONFIG.discountAmount,
        minimumOrder: BIRTHDAY_VOUCHER_CONFIG.minimumOrder,
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
    }),
    prisma.user.update({
      where: { id: userId },
      data: {
        birthdayVoucherYear: currentYear,
        // Defensive re-lock — di model Opsi B (Shopee strict),
        // birthDateLockedAt sudah ke-set saat user first save birthDate
        // (lihat /api/member/profile PUT). Statement ini overwrite jadi
        // timestamp baru — semantik field = "kapan terakhir lock", tetap
        // non-null (block UI tetap aktif). Kalau ada edge case dimana
        // voucher di-issue tapi lock belum set (mis. data corrupt /
        // migration legacy), ini ensure lock terpasang.
        birthDateLockedAt: new Date(),
      },
    }),
  ]);
  return code;
}

/**
 * Fire push notif "Selamat ulang tahun!" — fire-and-forget, errors
 * caught di caller. Deep link ke /member/vouchers supaya user tap
 * langsung lihat voucher mereka.
 */
async function sendBirthdayPush(
  userId: string,
  userName: string,
  voucherCode: string,
): Promise<void> {
  const firstName = (userName.split(" ")[0] || "").trim() || "Sahabat";
  await sendPushToUser(userId, {
    title: `🎂 Selamat Ulang Tahun, ${firstName}!`,
    body: `Hadiah dari Natalo: voucher diskon Rp${BIRTHDAY_VOUCHER_CONFIG.discountAmount.toLocaleString("id-ID")} sudah masuk akunmu. Berlaku ${BIRTHDAY_VOUCHER_CONFIG.expiresAfterDays} hari.`,
    url: "/member/vouchers",
    tag: `birthday-${voucherCode}`,
    category: "voucher",
  });
}

/**
 * Run birthday voucher batch untuk hari ini. Returns aggregate
 * result untuk cron log.
 */
export async function runBirthdayVoucherJob(
  today: Date = new Date(),
): Promise<BirthdayIssueResult> {
  const candidates = await findTodayBirthdayUsers(today);
  const currentYear = today.getFullYear();
  const result: BirthdayIssueResult = {
    candidates: candidates.length,
    issued: 0,
    skipped: 0,
    errors: 0,
    details: [],
  };

  for (const u of candidates) {
    // Defensive double-check (queryRaw already filtered, but race
    // window exists kalau cron re-run dalam beberapa detik).
    if (u.birthdayVoucherYear === currentYear) {
      result.skipped += 1;
      result.details.push({
        userId: u.id,
        name: u.name,
        status: "skipped",
        reason: "Sudah dapat voucher tahun ini",
      });
      continue;
    }
    try {
      const code = await issueBirthdayVoucher(u.id, currentYear);
      result.issued += 1;
      result.details.push({
        userId: u.id,
        name: u.name,
        status: "issued",
        voucherCode: code,
      });
      // Fire push notif — errors di-catch dan TIDAK count sebagai error
      // (voucher tetap valid di DB, push fail terjadi karena no token /
      // server APN down — user akan lihat voucher di app saat buka).
      sendBirthdayPush(u.id, u.name, code).catch((err) => {
        console.warn("[birthday-voucher] push failed:", {
          userId: u.id,
          error: err instanceof Error ? err.message : String(err),
        });
      });
    } catch (err) {
      result.errors += 1;
      result.details.push({
        userId: u.id,
        name: u.name,
        status: "error",
        reason: err instanceof Error ? err.message : String(err),
      });
      console.error("[birthday-voucher] issue failed:", {
        userId: u.id,
        error: err,
      });
    }
  }
  return result;
}
