"use server";

import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { logAdminAction, AdminAction } from "@/lib/admin-audit";

async function requireAdmin() {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    throw new Error("Akses ditolak.");
  }
  return session;
}

/**
 * Update status flag: REVIEWED / DISMISSED / BLOCKED.
 *
 * BLOCKED behavior:
 *   - Set flag.status = BLOCKED
 *   - Set user.role = "BLOCKED" (custom role string — login & action
 *     check via middleware/handler harus exclude role ini)
 *   - Increment user.tokenVersion → invalidate semua session token
 *     existing (next request 401)
 *
 * Note: kalau user belum punya middleware "BLOCKED" check, action
 * ini cuma flag database — login mungkin masih sukses sampai
 * middleware di-update. Future improvement: wire role check di
 * `lib/auth.ts` getSession() supaya reject session kalau role
 * = "BLOCKED".
 */
export async function reviewAbuseFlag(
  flagId: string,
  formData: FormData,
): Promise<void> {
  const session = await requireAdmin();
  const action = String(formData.get("action") ?? "");
  const adminNote = String(formData.get("adminNote") ?? "").trim().slice(0, 500);

  if (!["REVIEWED", "DISMISSED", "BLOCKED"].includes(action)) {
    throw new Error(`Action tidak valid: ${action}`);
  }

  const flag = await prisma.abuseFlag.findUnique({
    where: { id: flagId },
    select: { id: true, userId: true, ruleCode: true, status: true },
  });
  if (!flag) throw new Error("Flag tidak ditemukan.");
  if (flag.status !== "OPEN") {
    throw new Error("Flag sudah pernah di-review.");
  }

  const now = new Date();
  await prisma.$transaction(async (tx) => {
    await tx.abuseFlag.update({
      where: { id: flagId },
      data: {
        status: action,
        reviewedAt: now,
        reviewedByAdminId: session.sub,
        adminNote: adminNote.length > 0 ? adminNote : null,
      },
    });

    if (action === "BLOCKED") {
      // Block user — set role + bump tokenVersion. Existing session
      // token jadi invalid (next request 401).
      await tx.user.update({
        where: { id: flag.userId },
        data: {
          role: "BLOCKED",
          tokenVersion: { increment: 1 },
        },
      });
    }
  });

  // Audit log
  if (action === "BLOCKED") {
    logAdminAction({
      actorUserId: session.sub,
      action: AdminAction.USER_ROLE_CHANGED,
      targetType: "User",
      targetId: flag.userId,
      summary: `Block user via abuse flag (rule: ${flag.ruleCode})`,
      metadata: {
        flagId,
        ruleCode: flag.ruleCode,
        previousRole: "CUSTOMER",
        newRole: "BLOCKED",
        adminNote,
      },
    });
  } else {
    logAdminAction({
      actorUserId: session.sub,
      action: "ABUSE_FLAG_REVIEWED",
      targetType: "AbuseFlag",
      targetId: flagId,
      summary: `${action} abuse flag (rule: ${flag.ruleCode})`,
      metadata: {
        userId: flag.userId,
        ruleCode: flag.ruleCode,
        action,
        adminNote,
      },
    });
  }

  revalidatePath("/admin/abuse-flags");
}
