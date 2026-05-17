import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { AccountProfileEditor } from "@/components/account/AccountProfileEditor";
import { PageStatusBar } from "@/components/PageStatusBar";
import { prisma } from "@/lib/prisma";
import { requireCustomerSession } from "@/lib/session-guards";

export const metadata: Metadata = { title: "Ubah Profil" };

export default async function AccountProfilePage() {
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

  return (
    <>
      <PageStatusBar
        iconColor="dark"
        themeColor="#ffffff"
        nativeBackgroundColor="#ffffff"
        overlaysWebView={false}
      />
      <AccountProfileEditor
        userId={user.id}
        initialName={user.name}
        initialPhone={user.phone ?? null}
        initialBirthDate={user.birthDate ? user.birthDate.toISOString().split("T")[0] : null}
        email={user.email ?? null}
      />
    </>
  );
}
