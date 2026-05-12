import type { Metadata } from "next";
import { prisma } from "@/lib/prisma";
import { redirect } from "next/navigation";
import Link from "next/link";
import { EditProfileForm } from "@/components/EditProfileForm";
import { requireCustomerSession } from "@/lib/session-guards";

export const metadata: Metadata = { title: "Profil Saya" };

export default async function MemberProfilePage() {
  const session = await requireCustomerSession();

  const [user, totalPoints] = await Promise.all([
    prisma.user.findUnique({
      where: { id: session.sub },
      select: {
        id: true,
        name: true,
        email: true,
        phone: true,
        birthDate: true,
        createdAt: true,
      },
    }),
    prisma.customerPoint.aggregate({
      where: { userId: session.sub },
      _sum: { points: true },
    }),
  ]);

  if (!user) redirect("/member/login");

  const points = totalPoints?._sum.points ?? 0;
  const birthDateStr = user.birthDate
    ? user.birthDate.toISOString().split("T")[0]
    : null;

  return (
    <div className="mx-auto max-w-2xl px-4 py-4 md:py-10">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-black text-gray-900 md:text-2xl">
          Profil Saya
        </h1>
        <Link
          href="/member"
          className="text-sm font-semibold text-blue-500 hover:underline"
        >
          ← Kembali
        </Link>
      </div>

      {/* Avatar + Loyalty Points */}
      <div className="mt-4 overflow-hidden rounded-2xl bg-blue-500 text-white md:mt-6">
        <div className="flex items-center gap-3 p-4 md:gap-4 md:p-6">
          <div className="flex h-12 w-12 items-center justify-center rounded-full bg-white/20 text-2xl font-black md:h-16 md:w-16 md:text-3xl">
            {user.name.charAt(0).toUpperCase()}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-lg font-black">{user.name}</p>
            <p className="text-sm text-blue-100">
              Member sejak{" "}
              {new Date(user.createdAt).toLocaleDateString("id-ID", {
                month: "long",
                year: "numeric",
              })}
            </p>
          </div>
        </div>
        <Link
          href="/member/points"
          className="flex items-center justify-between gap-3 border-t border-white/20 bg-white/10 px-4 py-3 text-sm transition hover:bg-white/20 md:px-6"
        >
          <div className="flex items-center gap-2">
            <span className="text-xl">⭐</span>
            <div>
              <p className="text-xs text-blue-100">Loyalty Poin</p>
              <p className="text-base font-black">
                {points.toLocaleString("id-ID")} poin
              </p>
            </div>
          </div>
          <span className="text-xs font-bold text-white/90">
            Lihat history →
          </span>
        </Link>
      </div>

      {/* Edit form */}
      <div className="mt-6 rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
        <h2 className="font-bold text-gray-900">Edit Informasi Akun</h2>
        <EditProfileForm
          initialName={user.name}
          initialPhone={user.phone ?? null}
          initialBirthDate={birthDateStr}
          email={user.email ?? null}
        />
      </div>

      {/* Alamat section */}
      <div className="mt-4 rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="font-bold text-gray-900">Alamat Pengiriman</h2>
            <p className="mt-1 text-sm text-gray-500">
              Kelola alamat dan titik GPS untuk pengiriman.
            </p>
          </div>
          <Link
            href="/akun/alamat"
            className="rounded-full bg-blue-500 px-4 py-2 text-sm font-bold text-white transition hover:bg-blue-600"
          >
            Kelola →
          </Link>
        </div>
      </div>
    </div>
  );
}
