import Link from "next/link";
import BirthDateOverrideClient from "./BirthDateOverrideClient";
import { PageHeader } from "@/components/admin/ui";

export const dynamic = "force-dynamic";

export default function BirthDateOverridePage() {
  return (
    <>
      <div className="mx-auto max-w-3xl px-4 py-5 md:py-10">
        <PageHeader
          title="🎂 Override Tanggal Lahir"
          subtitle="CS tool — set ulang tanggal lahir customer yang ke-lock setelah dapat voucher ultah. Audit logged."
          actions={
            <Link
              href="/admin/dashboard"
              className="inline-flex items-center gap-1.5 rounded-full border border-zinc-200 bg-white px-3.5 py-2 text-xs font-bold text-zinc-700 transition hover:border-zinc-400 hover:bg-zinc-50"
            >
              ← Dashboard
            </Link>
          }
        />
      </div>
      <BirthDateOverrideClient />
    </>
  );
}
