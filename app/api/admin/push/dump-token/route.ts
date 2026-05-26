/**
 * GET /api/admin/push/dump-token?userId=X
 *
 * DIAGNOSTIC ONLY — return full FCM/APNs tokens untuk user tertentu.
 * Dipakai untuk Firebase Console "Send test message" direct delivery test
 * yang bypass backend Natalo entirely.
 *
 * ⚠️ Endpoint ini expose token mentah ke admin — jangan keep production
 * setelah debug selesai, hapus file ini.
 *
 * Auth: admin role wajib via CSRF + session.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";

export async function GET(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const userId = request.nextUrl.searchParams.get("userId");
  if (!userId) {
    return NextResponse.json(
      {
        error: "Pass ?userId=X to dump tokens for that customer.",
        hint: "Get userId from /api/push/me/status (field 'userId')",
      },
      { status: 400 },
    );
  }

  const subs = await prisma.pushSubscription.findMany({
    where: { userId },
    orderBy: { createdAt: "desc" },
  });

  return NextResponse.json({
    ok: true,
    userId,
    count: subs.length,
    tokens: subs.map((s) => ({
      id: s.id,
      endpoint: s.endpoint,
      // Untuk FCM: extract token tanpa prefix "fcm:"
      fcmToken: s.endpoint.startsWith("fcm:")
        ? s.endpoint.slice(4)
        : null,
      // Untuk APNs direct: extract token tanpa prefix "apns:"
      apnsToken: s.endpoint.startsWith("apns:")
        ? s.endpoint.slice(5)
        : null,
      createdAt: s.createdAt,
    })),
  });
}
