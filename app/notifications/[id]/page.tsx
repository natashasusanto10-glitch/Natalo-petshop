import type { Metadata } from "next";
import Link from "next/link";
import { FiCalendar, FiCheck, FiClock, FiInfo } from "react-icons/fi";
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
  const datePart = new Intl.DateTimeFormat("id-ID", {
    day: "numeric",
    month: "long",
    year: "numeric",
  }).format(date);
  const timePart = new Intl.DateTimeFormat("id-ID", {
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);

  return `${datePart} pukul ${timePart}`;
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
          <>
            <article className="overflow-hidden rounded-[28px] border border-blue-100/80 bg-white shadow-[0_18px_48px_-28px_rgba(21,101,216,0.42)]">
              <div className="relative bg-gradient-to-br from-blue-50 via-white to-violet-50 px-5 pb-6 pt-5">
                <span
                  className="absolute right-5 top-5 h-16 w-16 rounded-full border border-blue-200/40"
                  aria-hidden="true"
                />
                <span
                  className="absolute right-10 top-10 h-1.5 w-1.5 rounded-full bg-violet-300/70 shadow-[18px_20px_0_rgba(96,165,250,0.35),-18px_28px_0_rgba(251,191,36,0.45)]"
                  aria-hidden="true"
                />
                <span
                  className="absolute bottom-5 right-6 text-3xl font-black leading-none text-blue-100/80"
                  aria-hidden="true"
                >
                  +
                </span>

                <div className="relative flex items-start gap-4">
                  <span className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-white text-blue-600 shadow-[0_10px_28px_-16px_rgba(21,101,216,0.8)] ring-1 ring-blue-100">
                    <IoMegaphoneOutline className="h-7 w-7" aria-hidden="true" />
                  </span>
                  <div className="min-w-0 flex-1">
                    <h1 className="text-[28px] font-black leading-[1.08] text-slate-950">
                      {announcement.title}
                    </h1>
                  </div>
                </div>
              </div>

              <div className="space-y-5 px-5 pb-5 pt-5">
                <div className="flex flex-wrap items-center gap-x-3 gap-y-2 text-sm font-bold text-slate-500">
                  <span className="inline-flex items-center gap-1.5">
                    <FiClock className="h-4 w-4 text-blue-600" aria-hidden="true" />
                    {formatRelativeTime(announcement.createdAt)}
                  </span>
                  <span className="h-4 w-px bg-slate-200" aria-hidden="true" />
                  <span className="inline-flex items-center gap-1.5">
                    <FiCalendar className="h-4 w-4 text-blue-600" aria-hidden="true" />
                    {formatFullDate(announcement.createdAt)}
                  </span>
                </div>

                <div className="flex gap-3 rounded-3xl bg-blue-50/80 px-4 py-4 ring-1 ring-blue-100/70">
                  <span className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-white text-blue-600 shadow-sm">
                    <FiInfo className="h-4 w-4" aria-hidden="true" />
                  </span>
                  <p className="whitespace-pre-line text-[15px] leading-relaxed text-slate-700">
                    {announcement.body}
                  </p>
                </div>

                <div className="flex items-center gap-3" aria-hidden="true">
                  <span className="h-px flex-1 bg-gradient-to-r from-transparent via-blue-100 to-blue-100" />
                  <span className="relative flex h-7 w-7 items-center justify-center rounded-full bg-blue-50 text-blue-300">
                    <span className="h-2.5 w-2.5 rounded-full bg-current" />
                    <span className="absolute left-1.5 top-1.5 h-1.5 w-1.5 rounded-full bg-current" />
                    <span className="absolute right-1.5 top-1.5 h-1.5 w-1.5 rounded-full bg-current" />
                    <span className="absolute bottom-1.5 left-2 h-1.5 w-1.5 rounded-full bg-current" />
                    <span className="absolute bottom-1.5 right-2 h-1.5 w-1.5 rounded-full bg-current" />
                  </span>
                  <span className="h-px flex-1 bg-gradient-to-l from-transparent via-blue-100 to-blue-100" />
                </div>

                <footer className="text-sm leading-relaxed text-slate-500">
                  <p>Terima kasih atas perhatian dan kerjasamanya.</p>
                  <p className="mt-1 font-black text-slate-950">Natalo Petshop</p>
                </footer>
              </div>
            </article>

            <Link
              href="/notifications"
              className="mt-5 inline-flex min-h-[52px] w-full items-center justify-center gap-2 rounded-2xl bg-blue-600 px-5 py-4 text-sm font-black text-white shadow-[0_14px_30px_-16px_rgba(21,101,216,0.9)] transition hover:bg-blue-700 active:scale-[0.99]"
            >
              <FiCheck className="h-4 w-4" aria-hidden="true" />
              Mengerti
            </Link>
          </>
        )}
      </section>
    </main>
  );
}
