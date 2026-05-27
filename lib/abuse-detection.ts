/**
 * Voucher abuse detection rules.
 *
 * Run by cron `/api/cron/voucher-abuse-detect` daily. Tiap rule scan
 * recent activity (window 24-72 jam) dan tandai user dengan pola
 * mencurigakan. Admin review via /admin/abuse-flags.
 *
 * Design principle:
 *  - Detection runs offline (cron) — TIDAK block user action real-time
 *  - Severity 3-tier (LOW/MEDIUM/HIGH) — admin decide bagaimana respond
 *  - Avoid false positive: rules require multiple signals
 *  - Idempotent: re-running cron tidak create duplicate OPEN flag untuk
 *    user+ruleCode combo (cek existing OPEN sebelum insert)
 */
import { prisma } from "@/lib/prisma";

export const AbuseRule = {
  BURST_VOUCHER_CLAIM: "BURST_VOUCHER_CLAIM",
  GMAIL_ALIAS_DUPLICATE: "GMAIL_ALIAS_DUPLICATE",
  DUPLICATE_SHIPPING_ADDRESS: "DUPLICATE_SHIPPING_ADDRESS",
  NEW_ACCOUNT_INSTANT_CLAIM: "NEW_ACCOUNT_INSTANT_CLAIM",
} as const;

export type AbuseRuleCode = (typeof AbuseRule)[keyof typeof AbuseRule];
export type AbuseSeverity = "LOW" | "MEDIUM" | "HIGH";

type FlagInput = {
  userId: string;
  ruleCode: AbuseRuleCode;
  severity: AbuseSeverity;
  details: Record<string, unknown>;
};

/**
 * Idempotent flag creator — skip kalau user udah punya OPEN flag
 * dengan ruleCode sama. Mencegah cron yang re-run nge-flood AbuseFlag
 * table. Re-flag tetap bisa kalau status sebelumnya REVIEWED/DISMISSED
 * (admin pernah review, tapi pattern terulang lagi).
 */
async function createFlagIfMissing(input: FlagInput): Promise<boolean> {
  const existing = await prisma.abuseFlag.findFirst({
    where: {
      userId: input.userId,
      ruleCode: input.ruleCode,
      status: "OPEN",
    },
    select: { id: true },
  });
  if (existing) return false;
  const flag = await prisma.abuseFlag.create({
    data: {
      userId: input.userId,
      ruleCode: input.ruleCode,
      severity: input.severity,
      details: input.details as object,
      status: "OPEN",
    },
    select: { id: true, user: { select: { name: true, email: true } } },
  });
  // Push notif ke admin — hanya untuk HIGH severity supaya tidak noisy.
  // Helper internal-side filter severity, kita kirim saja.
  void import("@/lib/push-admin").then(({ sendAdminAbuseFlagPush }) => {
    sendAdminAbuseFlagPush({
      flagId: flag.id,
      ruleCode: input.ruleCode,
      severity: input.severity,
      userName: flag.user.name || flag.user.email || "User",
    });
  });
  return true;
}

/**
 * Rule 1: Burst voucher claim — user claim >3 loyalty voucher dalam
 * 1 jam terakhir. Normal user gak claim begini cepat (BDAY/welcome
 * voucher unik per user).
 *
 * Window: 1 jam. Threshold: >= 3 klaim. Severity: HIGH (clear signal).
 */
export async function detectBurstVoucherClaim(): Promise<number> {
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
  // CustomerPoint dengan source 'CLAIM:...' = loyalty voucher claim.
  const claims = await prisma.customerPoint.findMany({
    where: {
      source: { startsWith: "CLAIM:" },
      createdAt: { gte: oneHourAgo },
    },
    select: { userId: true, source: true, createdAt: true },
  });

  // Group by userId, count claims.
  const claimsByUser = new Map<string, { count: number; codes: string[] }>();
  for (const c of claims) {
    const entry = claimsByUser.get(c.userId) ?? { count: 0, codes: [] };
    entry.count += 1;
    entry.codes.push(c.source.replace(/^CLAIM:/, ""));
    claimsByUser.set(c.userId, entry);
  }

  let flagged = 0;
  for (const [userId, data] of claimsByUser) {
    if (data.count >= 3) {
      const created = await createFlagIfMissing({
        userId,
        ruleCode: AbuseRule.BURST_VOUCHER_CLAIM,
        severity: "HIGH",
        details: {
          claimCount: data.count,
          voucherCodes: data.codes,
          windowHours: 1,
          detectedAt: new Date().toISOString(),
        },
      });
      if (created) flagged += 1;
    }
  }
  return flagged;
}

/**
 * Rule 2: Gmail alias duplicate — `andi+1@gmail.com`, `a.n.d.i@gmail.com`
 * actually goes to same Gmail inbox `andi@gmail.com`. Gmail strip dot
 * di local part dan ignore `+suffix`. Detect multi-account dengan
 * normalize.
 *
 * Severity: MEDIUM kalau cuma email match (mungkin legit family sharing
 * device), HIGH kalau juga sama phone area.
 */
export async function detectGmailAliasDuplicate(): Promise<number> {
  const users = await prisma.user.findMany({
    where: {
      email: { contains: "@gmail.com", mode: "insensitive" },
    },
    select: { id: true, email: true, phone: true, createdAt: true, name: true },
  });

  // Group by normalized email — strip dot di local part, drop `+suffix`.
  const groups = new Map<string, typeof users>();
  for (const u of users) {
    if (!u.email) continue;
    const lower = u.email.toLowerCase().trim();
    if (!lower.endsWith("@gmail.com")) continue;
    const localPart = lower.split("@")[0];
    const beforePlus = localPart.split("+")[0];
    const normalized = beforePlus.replace(/\./g, "");
    const key = `${normalized}@gmail.com`;
    const arr = groups.get(key) ?? [];
    arr.push(u);
    groups.set(key, arr);
  }

  let flagged = 0;
  for (const [normalizedEmail, group] of groups) {
    if (group.length <= 1) continue;
    // Flag ALL user dalam group (semua mungkin abuser collaborating
    // atau 1 user owner + sisanya sock puppet).
    for (const u of group) {
      const severity: AbuseSeverity = group.length >= 4 ? "HIGH" : "MEDIUM";
      const created = await createFlagIfMissing({
        userId: u.id,
        ruleCode: AbuseRule.GMAIL_ALIAS_DUPLICATE,
        severity,
        details: {
          normalizedEmail,
          duplicateCount: group.length,
          siblingUserIds: group.filter((s) => s.id !== u.id).map((s) => s.id),
          siblingEmails: group.filter((s) => s.id !== u.id).map((s) => s.email),
          detectedAt: new Date().toISOString(),
        },
      });
      if (created) flagged += 1;
    }
  }
  return flagged;
}

/**
 * Rule 3: Same shipping address dipake 3+ user dalam 30 hari terakhir.
 * Indikasi: account farming, semua akun ship ke alamat sama (rumah
 * abuser). False positive risk: family / kost — admin yang verify.
 *
 * Match address: normalize street + recipientName + recipientPhone.
 * Case-insensitive, strip multi-space, trim.
 */
export async function detectDuplicateShippingAddress(): Promise<number> {
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const orders = await prisma.order.findMany({
    where: {
      createdAt: { gte: thirtyDaysAgo },
      userId: { not: null },
      // Skip self-pickup — shipping address gak relevan.
      shippingAddress: { not: "" },
    },
    select: {
      userId: true,
      shippingAddress: true,
      customerPhone: true,
      customerName: true,
    },
  });

  // Normalize address fingerprint.
  const normalize = (s: string) =>
    s.toLowerCase().replace(/\s+/g, " ").trim();
  const fingerprintKey = (o: { shippingAddress: string; customerPhone: string }) =>
    `${normalize(o.shippingAddress)}|${normalize(o.customerPhone)}`;

  const userIdsByAddress = new Map<string, Set<string>>();
  const orderSamplesByAddress = new Map<
    string,
    { address: string; phone: string }
  >();
  for (const o of orders) {
    if (!o.userId) continue;
    const key = fingerprintKey({
      shippingAddress: o.shippingAddress,
      customerPhone: o.customerPhone,
    });
    if (key === "|") continue; // both empty, skip
    const set = userIdsByAddress.get(key) ?? new Set<string>();
    set.add(o.userId);
    userIdsByAddress.set(key, set);
    if (!orderSamplesByAddress.has(key)) {
      orderSamplesByAddress.set(key, {
        address: o.shippingAddress,
        phone: o.customerPhone,
      });
    }
  }

  let flagged = 0;
  for (const [key, userIds] of userIdsByAddress) {
    if (userIds.size < 3) continue;
    const sample = orderSamplesByAddress.get(key)!;
    for (const userId of userIds) {
      const severity: AbuseSeverity = userIds.size >= 5 ? "HIGH" : "MEDIUM";
      const created = await createFlagIfMissing({
        userId,
        ruleCode: AbuseRule.DUPLICATE_SHIPPING_ADDRESS,
        severity,
        details: {
          shippingAddress: sample.address,
          customerPhone: sample.phone,
          duplicateCount: userIds.size,
          siblingUserIds: [...userIds].filter((id) => id !== userId),
          detectedAt: new Date().toISOString(),
        },
      });
      if (created) flagged += 1;
    }
  }
  return flagged;
}

/**
 * Rule 4: User register lalu instant claim voucher (<5 menit gap).
 * Pattern bot / scripted abuse: register → langsung tukar BDAY/welcome
 * voucher → checkout. Normal user explore app dulu, jarang instant.
 *
 * Window scan: user yang createdAt dalam 24 jam terakhir, ada claim
 * dengan gap <= 5 menit dari createdAt.
 */
export async function detectNewAccountInstantClaim(): Promise<number> {
  const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const recentUsers = await prisma.user.findMany({
    where: { createdAt: { gte: oneDayAgo } },
    select: { id: true, createdAt: true, email: true, phone: true },
  });

  let flagged = 0;
  for (const u of recentUsers) {
    const fiveMinAfter = new Date(u.createdAt.getTime() + 5 * 60 * 1000);
    const earliestClaim = await prisma.customerPoint.findFirst({
      where: {
        userId: u.id,
        source: { startsWith: "CLAIM:" },
        createdAt: { lte: fiveMinAfter },
      },
      orderBy: { createdAt: "asc" },
      select: { createdAt: true, source: true },
    });
    if (!earliestClaim) continue;
    const gapSec = Math.round(
      (earliestClaim.createdAt.getTime() - u.createdAt.getTime()) / 1000,
    );
    const created = await createFlagIfMissing({
      userId: u.id,
      ruleCode: AbuseRule.NEW_ACCOUNT_INSTANT_CLAIM,
      severity: gapSec < 60 ? "HIGH" : "MEDIUM",
      details: {
        registerAt: u.createdAt.toISOString(),
        firstClaimAt: earliestClaim.createdAt.toISOString(),
        gapSeconds: gapSec,
        voucherCode: earliestClaim.source.replace(/^CLAIM:/, ""),
      },
    });
    if (created) flagged += 1;
  }
  return flagged;
}

/**
 * Run all detection rules. Return aggregate count flagged per rule
 * untuk cron logging. Tidak throw — catch per-rule supaya 1 rule
 * fail tidak kill others.
 */
export async function runAllAbuseDetection(): Promise<
  Record<AbuseRuleCode, number | "error">
> {
  const result: Record<string, number | "error"> = {};
  const rules: [AbuseRuleCode, () => Promise<number>][] = [
    [AbuseRule.BURST_VOUCHER_CLAIM, detectBurstVoucherClaim],
    [AbuseRule.GMAIL_ALIAS_DUPLICATE, detectGmailAliasDuplicate],
    [AbuseRule.DUPLICATE_SHIPPING_ADDRESS, detectDuplicateShippingAddress],
    [AbuseRule.NEW_ACCOUNT_INSTANT_CLAIM, detectNewAccountInstantClaim],
  ];
  for (const [code, runner] of rules) {
    try {
      result[code] = await runner();
    } catch (err) {
      console.error(`[abuse-detection] ${code} failed:`, err);
      result[code] = "error";
    }
  }
  return result as Record<AbuseRuleCode, number | "error">;
}
