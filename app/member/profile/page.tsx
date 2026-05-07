import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import Link from "next/link";

export default async function MemberProfilePage() {
  const session = await getSession();

  const user = session
    ? await prisma.user.findUnique({
        where: { id: session.sub },
        select: { id: true, name: true, email: true, phone: true, createdAt: true },
      })
    : null;

  return (
    <div className="mx-auto max-w-2xl px-4 py-10">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-black text-gray-900">Profil Saya</h1>
        <Link href="/member" className="text-sm font-semibold text-orange-500 hover:underline">
          ← Kembali
        </Link>
      </div>

      {user ? (
        <div className="mt-6 space-y-4">
          {/* Avatar & greeting */}
          <div className="flex items-center gap-4 rounded-2xl bg-orange-50 p-5">
            <div className="flex h-16 w-16 items-center justify-center rounded-full bg-orange-500 text-3xl text-white">
              {user.name.charAt(0).toUpperCase()}
            </div>
            <div>
              <p className="font-black text-gray-900 text-lg">{user.name}</p>
              <p className="text-sm text-gray-500">
                Member sejak{" "}
                {new Date(user.createdAt).toLocaleDateString("id-ID", {
                  month: "long",
                  year: "numeric",
                })}
              </p>
            </div>
          </div>

          {/* Info */}
          <div className="rounded-2xl border border-gray-100 bg-white p-5 space-y-4">
            <h2 className="font-bold text-gray-900">Informasi Akun</h2>

            <div>
              <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Nama</p>
              <p className="mt-1 font-semibold text-gray-800">{user.name}</p>
            </div>
            <div>
              <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Email</p>
              <p className="mt-1 font-semibold text-gray-800">{user.email ?? "—"}</p>
            </div>
            <div>
              <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">No. WhatsApp</p>
              <p className="mt-1 font-semibold text-gray-800">{user.phone ?? "—"}</p>
            </div>
          </div>

          <div className="rounded-2xl border border-dashed border-gray-200 p-5 text-center text-sm text-gray-400">
            Fitur edit profil akan segera hadir.
          </div>
        </div>
      ) : (
        <div className="mt-8 rounded-2xl bg-gray-50 p-10 text-center">
          <p className="text-gray-500">Gagal memuat profil.</p>
        </div>
      )}
    </div>
  );
}
