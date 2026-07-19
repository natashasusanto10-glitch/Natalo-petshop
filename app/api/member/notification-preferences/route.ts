import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import {
  getUserNotificationPrefs,
  normalizeNotificationPrefs,
} from "@/lib/notification-preferences";

/**
 * Preferensi push notification per kategori untuk member.
 *
 * GET  → { preferences: Record<category, bool> } (default-filled).
 * PUT  → body { preferences: Record<category, bool> }; simpan (merge dengan
 *        default supaya key hilang tidak jadi undefined) → { preferences }.
 *
 * Dipakai Flutter NotificationPreferencesScreen. Server memfilter dispatch
 * push berdasar preferensi ini (lib/notification-preferences.ts), jadi PUT
 * di sini yang membuat toggle benar-benar menghentikan notif.
 */

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session)
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const preferences = await getUserNotificationPrefs(session.sub);
  return NextResponse.json({ preferences });
}

export async function PUT(request: Request) {
  const session = await getSession("CUSTOMER");
  if (!session)
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Body tidak valid." }, { status: 400 });
  }

  const rawPrefs = (body as { preferences?: unknown })?.preferences ?? body;
  const preferences = normalizeNotificationPrefs(rawPrefs);

  await prisma.user.update({
    where: { id: session.sub },
    data: { notificationPrefs: preferences },
  });

  return NextResponse.json({ preferences });
}
