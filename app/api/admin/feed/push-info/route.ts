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

  const [all, members, active30d, used, selfDevices, recentPosts] =
    await Promise.all([
      resolveSegmentUserIds("all"),
      resolveSegmentUserIds("members"),
      resolveSegmentUserIds("active30d"),
      countRecentPublishPush(),
      // Jumlah perangkat/langganan push milik AKUN ADMIN yang login ini —
      // dipakai tombol "Tes ke HP saya" untuk jujur bila 0 (tes akan no-op).
      // Gotcha nyata: admin login web pakai akun admin, HP pakai akun
      // customer → tes "sukses" tapi tak pernah sampai ke mana pun.
      prisma.pushSubscription.count({ where: { userId: session.sub } }),
      // DIAGNOSTIK: 5 post notify terakhir + segmen yang BENAR-BENAR
      // tersimpan + apakah sudah di-klaim kirim. Read-only, untuk memastikan
      // "kirim ke Semua" beneran segment=all, dan push benar-benar terpicu.
      prisma.feedPost.findMany({
        where: { notifyOnPublish: true },
        orderBy: { createdAt: "desc" },
        take: 5,
        select: {
          id: true,
          title: true,
          pushSegment: true,
          publishPushSentAt: true,
          encodingStatus: true,
          status: true,
          authorRole: true,
        },
      }),
    ]);

  // Untuk tiap post notify, cek apakah Announcement lonceng-nya dibuat
  // (url = /feed/{id}) + segmen Announcement-nya. Kalau publishPushSentAt
  // terisi TAPI Announcement tak ada → ada error tertelan setelah klaim.
  const feedUrls = recentPosts.map((p) => `/feed/${p.id}`);
  const announcements =
    feedUrls.length > 0
      ? await prisma.announcement.findMany({
          where: { url: { in: feedUrls } },
          select: { url: true, segment: true },
        })
      : [];
  const annByUrl = new Map(announcements.map((a) => [a.url, a.segment]));

  return NextResponse.json({
    counts: {
      all: all.length,
      members: members.length,
      active30d: active30d.length,
    },
    quota: { used, cap: FEED_PUSH_DAILY_CAP },
    self: { devices: selfDevices },
    recent: recentPosts.map((p) => ({
      title: p.title.slice(0, 40),
      segmentTersimpan: p.pushSegment,
      status: p.status,
      encoding: p.encodingStatus,
      pushTerpicu: p.publishPushSentAt != null,
      announcementDibuat: annByUrl.has(`/feed/${p.id}`),
      announcementSegment: annByUrl.get(`/feed/${p.id}`) ?? null,
    })),
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
