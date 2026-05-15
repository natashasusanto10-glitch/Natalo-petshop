import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { FeedUploadClient } from "@/components/feed/FeedUploadClient";

export const metadata: Metadata = {
  title: "Upload Video — Feed Natalo",
};

// Wajib login customer. Admin tidak pakai page ini (admin posting via
// dashboard di F5). Kalau tidak login → redirect ke login dgn returnUrl.
export default async function FeedUploadPage() {
  const session = await getSession();
  if (!session) {
    redirect("/member/login?returnUrl=/feed/upload");
  }
  if (session.role === "ADMIN") {
    // Admin akan posting via /admin/feed nanti.
    redirect("/feed");
  }

  return (
    <main className="min-h-[100dvh] bg-slate-50">
      <FeedUploadClient />
    </main>
  );
}
