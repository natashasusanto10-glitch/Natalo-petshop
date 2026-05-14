import type { Metadata } from "next";
import { IoMegaphoneOutline } from "react-icons/io5";
import { PageStatusBar } from "@/components/PageStatusBar";
import { StickyBackTitle } from "@/components/StickyBackTitle";
import { requireCustomerSession } from "@/lib/session-guards";
import { prisma } from "@/lib/prisma";

export const metadata: Metadata = {
  title: "Detail Pengumuman",
  robots: { index: false, follow: false },
};

type Props = {
  params: Promise<{ id: string }>;
};

function formatRelativeTime(date: Date): string {
  const diff = Date.now() - date.getTime();
  const minutes = Math.floor(diff / 60_000);
  if (minutes < 1) return "baru saja";
  if (minutes < 60) return `${minutes} menit lalu`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} jam lalu`;
  const days = Math.floor(hours / 24);
  if (days === 1) return "kemarin";
  if (days < 7) return `${days} hari lalu`;
  return date.toLocaleDateString("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

function formatFullDate(date: Date): string {
  return new Intl.DateTimeFormat("id-ID", {
    day: "numeric",
    month: "long",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

async function getAllowedSegments(userId: string) {
  const since30d = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const [hasPaidOrder, hasRecentOrder] = await Promise.all([
    prisma.order.findFirst({
      where: { userId, paymentStatus: "PAID" },
      select: { id: true },
    }),
    prisma.order.findFirst({
      where: { userId, createdAt: { gte: since30d } },
      select: { id: true },
    }),
  ]);

  const segments = ["all"];
  if (hasPaidOrder) segments.push("members");
  if (hasRecentOrder) segments.push("active30d");
  return segments;
}

function ErrorState() {
  return (
    <div className="rounded-3xl border border-slate-200 bg-white px-5 py-10 text-center shadow-sm">
      <span className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-violet-50 text-violet-600">
        <IoMegaphoneOutline className="h-7 w-7" aria-hidden="true" />
      </span>
      <h1 className="mt-5 text-lg font-black text-slate-950">Pengumuman tidak dapat dimuat.</h1>
      <p className="mt-2 text-sm leading-relaxed text-slate-500">Silakan coba lagi nanti.</p>
    </div>
  );
}

export default async function AnnouncementDetailPage({ params }: Props) {
  const [{ id }, session] = await Promise.all([params, requireCustomerSession()]);
  const announcementId = decodeURIComponent(id);
  const allowedSegments = await getAllowedSegments(session.sub);
  const now = new Date();

  const announcement = await prisma.announcement.findFirst({
    where: {
      id: announcementId,
      type: "announcement",
      status: "PUBLISHED",
      OR: [
        { targetUserId: null, segment: { in: allowedSegments } },
        { targetUserId: session.sub },
      ],
      AND: [
        { OR: [{ startsAt: null }, { startsAt: { lte: now } }] },
        { OR: [{ endsAt: null }, { endsAt: { gte: now } }] },
      ],
    },
    select: {
      id: true,
      title: true,
      body: true,
      createdAt: true,
    },
  });

  if (announcement) {
    await prisma.announcementRead.upsert({
      where: {
        userId_announcementId: {
          userId: session.sub,
          announcementId: announcement.id,
        },
      },
      update: {},
      create: {
        userId: session.sub,
        announcementId: announcement.id,
      },
    });
  }

  return (
    <main className="min-h-screen bg-slate-50">
      <PageStatusBar iconColor="dark" themeColor="#ffffff" />
      <StickyBackTitle label="Detail Pengumuman" fallbackHref="/notifications" stickToTop />

      <section className="mx-auto w-full max-w-2xl px-4 pb-8 pt-4">
        {!announcement ? (
          <ErrorState />
        ) : (
          <article className="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="flex items-start gap-4">
              <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-violet-50 text-violet-600">
                <IoMegaphoneOutline className="h-6 w-6" aria-hidden="true" />
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-xs font-extrabold uppercase tracking-[0.12em] text-violet-600">
                  Pengumuman dari Admin
                </p>
                <h1 className="mt-2 text-2xl font-black leading-tight text-slate-950">
                  {announcement.title}
                </h1>
                <p className="mt-2 text-sm font-semibold text-slate-500">
                  {formatRelativeTime(announcement.createdAt)}
                  <span className="mx-2 text-slate-300" aria-hidden="true">
                    |
                  </span>
                  {formatFullDate(announcement.createdAt)}
                </p>
              </div>
            </div>

            <div className="mt-6 rounded-2xl bg-slate-50 px-4 py-5">
              <p className="whitespace-pre-line text-[15px] leading-relaxed text-slate-700">
                {announcement.body}
              </p>
            </div>

            <footer className="mt-5 border-t border-slate-100 pt-4 text-sm leading-relaxed text-slate-500">
              <p>Terima kasih atas perhatian dan kerjasamanya.</p>
              <p className="mt-1 font-extrabold text-slate-800">Natalo Petshop</p>
            </footer>
          </article>
        )}
      </section>
    </main>
  );
}
