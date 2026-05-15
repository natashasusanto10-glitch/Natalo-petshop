import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { EditProfileForm } from "@/components/EditProfileForm";
import { requireCustomerSession } from "@/lib/session-guards";

export const metadata: Metadata = { title: "Profil Saya" };

export default async function MemberProfilePage() {
  const session = await requireCustomerSession();

  const user = await prisma.user.findUnique({
    where: { id: session.sub },
    select: {
      id: true,
      name: true,
      email: true,
      phone: true,
      birthDate: true,
    },
  });

  if (!user) redirect("/member/login");

  const birthDateStr = user.birthDate
    ? user.birthDate.toISOString().split("T")[0]
    : null;

  return (
    <main className="min-h-screen bg-zinc-50 pb-[calc(2rem+env(safe-area-inset-bottom))]">
      <header className="sticky top-0 z-50 border-b border-zinc-100 bg-white px-4 pb-3 pt-4 shadow-sm [padding-top:calc(1rem_+_env(safe-area-inset-top))]">
        <div className="mx-auto flex max-w-2xl items-center gap-2">
          <Link
            href="/member"
            aria-label="Kembali ke akun"
            className="-ml-2 flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-zinc-800 active:bg-zinc-100"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth={2.2}
              className="h-5 w-5"
              aria-hidden
            >
              <path d="M15 18l-6-6 6-6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </Link>
          <h1 className="text-xl font-black text-zinc-950 md:text-2xl">Profil Saya</h1>
        </div>
      </header>

      <div className="mx-auto max-w-2xl px-4 py-5 md:py-8">
        <section className="rounded-2xl border border-zinc-100 bg-white p-5 shadow-sm md:p-6">
          <h2 className="font-bold text-zinc-950">Edit Informasi Akun</h2>
          <EditProfileForm
            initialName={user.name}
            initialPhone={user.phone ?? null}
            initialBirthDate={birthDateStr}
            email={user.email ?? null}
          />
        </section>
      </div>
    </main>
  );
}
