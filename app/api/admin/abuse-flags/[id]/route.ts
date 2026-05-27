import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { reviewAbuseFlag } from "@/app/admin/(protected)/abuse-flags/actions";

/**
 * PATCH /api/admin/abuse-flags/[id]
 *
 * Review satu AbuseFlag — set status REVIEWED / DISMISSED / BLOCKED.
 * REST wrapper untuk server action `reviewAbuseFlag(flagId, formData)`.
 *
 * Body: { action: "REVIEWED" | "DISMISSED" | "BLOCKED", adminNote?: string }
 *
 * BLOCKED action akan: block user (role=BLOCKED, bump tokenVersion,
 * invalidate semua session existing). Dipakai untuk konfirmasi abuse
 * setelah review manual.
 */
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => null)) as
    | { action?: string; adminNote?: string }
    | null;
  const action = body?.action?.trim() ?? "";
  if (!["REVIEWED", "DISMISSED", "BLOCKED"].includes(action)) {
    return NextResponse.json(
      { error: "Action harus REVIEWED, DISMISSED, atau BLOCKED" },
      { status: 400 },
    );
  }

  const { id } = await params;
  const formData = new FormData();
  formData.set("action", action);
  if (body?.adminNote) formData.set("adminNote", body.adminNote);

  try {
    await reviewAbuseFlag(id, formData);
    return NextResponse.json({ ok: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Review gagal";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
