/**
 * GET/POST /api/admin/feed/push-info
 *
 * GET  — info untuk admin sebelum publish: jumlah target per segment
 * (all/members/active30d) dan kuota publish-push harian yang sudah
 * terpakai. Admin-only.
 *
 * POST — kirim tes publish-push ke diri sendiri (session admin) supaya
 * admin bisa preview judul/deskripsi sebelum publish beneran. Tidak
 * menyentuh post asli / Announcement / guard cap apa pun.
 *
 * Body POST: { title: string, description?: string | null }
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import {
  resolveSegmentUserIds,
  countRecentPublishPush,
  sendFeedPublishTestPush,
  FEED_PUSH_DAILY_CAP,
} from "@/lib/feed/publish-push";

export async function GET() {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const [all, members, active30d, used, selfDevices] = await Promise.all([
    resolveSegmentUserIds("all"),
    resolveSegmentUserIds("members"),
    resolveSegmentUserIds("active30d"),
    countRecentPublishPush(),
    // Jumlah perangkat/langganan push milik AKUN ADMIN yang login ini —
    // dipakai tombol "Tes ke HP saya" untuk jujur bila 0 (tes akan no-op).
    // Gotcha nyata: admin login web pakai akun admin, HP pakai akun
    // customer → tes "sukses" tapi tak pernah sampai ke mana pun.
    prisma.pushSubscription.count({ where: { userId: session.sub } }),
  ]);

  return NextResponse.json({
    counts: {
      all: all.length,
      members: members.length,
      active30d: active30d.length,
    },
    quota: { used, cap: FEED_PUSH_DAILY_CAP },
    self: { devices: selfDevices },
  });
}

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const json = await request.json().catch(() => null);
  const title = typeof json?.title === "string" ? json.title.trim() : "";
  const description =
    typeof json?.description === "string" ? json.description : null;

  if (!title || title.length > 200) {
    return NextResponse.json(
      { error: "Judul wajib diisi (maks 200 karakter)" },
      { status: 400 },
    );
  }

  // Jujur sebelum kirim: kalau akun admin ini tidak punya langganan push
  // sama sekali, tes akan no-op diam-diam ("Terkirim ✓" palsu). Gotcha
  // nyata di lapangan: web admin login akun ADMIN, HP login akun customer
  // → tes tak pernah sampai ke mana pun dan admin mengira fitur rusak.
  const deviceCount = await prisma.pushSubscription.count({
    where: { userId: session.sub },
  });
  if (deviceCount === 0) {
    return NextResponse.json(
      {
        error:
          "Akun admin ini tidak punya perangkat terdaftar untuk notifikasi. Login app di HP dengan akun ini (atau izinkan notifikasi browser) dulu — atau uji lewat publish ke segmen yang memuat akun HP-mu.",
      },
      { status: 400 },
    );
  }

  await sendFeedPublishTestPush({ userId: session.sub, title, description });

  return NextResponse.json({ ok: true, devices: deviceCount });
}
