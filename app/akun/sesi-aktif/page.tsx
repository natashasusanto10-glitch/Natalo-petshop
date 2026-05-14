import Link from "next/link";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import RevokeOtherSessionsButton from "@/components/RevokeOtherSessionsButton";
import { StickyBackTitle } from "@/components/StickyBackTitle";

export const dynamic = "force-dynamic";

export const metadata = {
  title: "Keamanan & Sesi Aktif",
  description: "Lihat device yang sedang login dan keluarkan device lain bila perlu.",
};

function summarizeUserAgent(ua: string) {
  if (!ua) return { device: "Perangkat tidak dikenal", browser: "Browser tidak dikenal" };

  const lc = ua.toLowerCase();
  let device = "Desktop";
  if (/iphone|ipod/.test(lc)) device = "iPhone";
  else if (/ipad/.test(lc)) device = "iPad";
  else if (/android/.test(lc)) device = /mobile/.test(lc) ? "Android" : "Android Tablet";
  else if (/macintosh|mac os/.test(lc)) device = "Mac";
  else if (/windows/.test(lc)) device = "Windows";
  else if (/linux/.test(lc)) device = "Linux";

  let browser = "Browser tidak dikenal";
  if (/edg\//.test(lc)) browser = "Microsoft Edge";
  else if (/opr\/|opera/.test(lc)) browser = "Opera";
  else if (/chrome\//.test(lc) && !/edg\/|opr\/|samsungbrowser/.test(lc)) browser = "Chrome";
  else if (/safari\//.test(lc) && !/chrome|crios|fxios/.test(lc)) browser = "Safari";
  else if (/firefox|fxios/.test(lc)) browser = "Firefox";
  else if (/samsungbrowser/.test(lc)) browser = "Samsung Internet";

  return { device, browser };
}

export default async function ActiveSessionPage() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    redirect("/member/login");
  }

  const headerList = await headers();
  const userAgent = headerList.get("user-agent") || "";
  const ip =
    headerList.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    headerList.get("x-real-ip") ||
    "Tidak diketahui";

  const { device, browser } = summarizeUserAgent(userAgent);

  const user = await prisma.user
    .findUnique({
      where: { id: session.sub },
      select: { tokenVersion: true, updatedAt: true, name: true },
    })
    .catch(() => null);

  return (
    <main className="min-h-screen bg-zinc-50 pb-24">
      <StickyBackTitle
        label="Keamanan & sesi aktif"
        href="/member"
        variant="textBack"
        stickToTop
      />
      <div className="mx-auto max-w-md px-4 py-6 sm:py-8">

        <p className="text-sm text-zinc-600">
          Berikut perangkat yang kamu pakai saat ini. Kalau melihat aktivitas mencurigakan,
          klik tombol di bawah untuk mengeluarkan semua perangkat lain dari akun kamu.
        </p>

        <section className="mt-5 rounded-2xl border border-blue-100 bg-white p-5 shadow-sm">
          <div className="flex items-start gap-3">
            <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-blue-100 text-lg">
              {device === "iPhone" || device === "iPad" || device.startsWith("Android") ? "📱" : "💻"}
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <p className="text-sm font-bold text-zinc-900">{device} · {browser}</p>
                <span className="rounded-full bg-emerald-50 px-2 py-0.5 text-[10px] font-black text-emerald-700">
                  PERANGKAT INI
                </span>
              </div>
              <p className="mt-1 text-xs text-zinc-500">IP: {ip}</p>
              <p className="text-xs text-zinc-500">
                Login sebagai {user?.name ?? session.name}
              </p>
            </div>
          </div>
        </section>

        <section className="mt-5 rounded-2xl border border-amber-100 bg-amber-50/70 p-4 text-[13px] leading-relaxed text-amber-900">
          <p className="font-bold">⚠️ Lupa logout di tempat lain?</p>
          <p className="mt-1">
            Klik tombol di bawah untuk men-logout akunmu dari semua browser & perangkat lain
            (laptop teman, kafe, HP lama). Perangkat ini tetap login.
          </p>
        </section>

        <RevokeOtherSessionsButton />

        <div className="mt-6 grid gap-2 text-[13px] text-zinc-500">
          <p>
            <span className="font-bold text-zinc-700">Tip keamanan:</span> ganti password secara
            berkala dan jangan share kode OTP ke siapa pun — termasuk yang mengaku admin Natalo.
          </p>
        </div>

        <Link
          href="/member"
          className="mt-6 block w-full rounded-full border border-zinc-200 bg-white py-3 text-center text-sm font-bold text-zinc-700 hover:bg-zinc-50"
        >
          Kembali ke akun
        </Link>
      </div>
    </main>
  );
}
