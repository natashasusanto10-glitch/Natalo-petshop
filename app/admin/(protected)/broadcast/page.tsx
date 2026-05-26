import Link from "next/link";
import { BroadcastForm } from "./BroadcastForm";
import { PageHeader } from "@/components/admin/ui";

export const dynamic = "force-dynamic";

export default function AdminBroadcastPage() {
  return (
    <div className="mx-auto max-w-2xl px-4 py-5 md:py-10">
      <PageHeader
        title="📣 Broadcast Notifikasi"
        subtitle="Buat promo atau pengumuman resmi Natalo Petshop. Setelah publish, notifikasi masuk ke Notification Center user sesuai tipe broadcast."
        actions={
          <Link
            href="/admin/dashboard"
            className="inline-flex items-center gap-1.5 rounded-full border border-zinc-200 bg-white px-3.5 py-2 text-xs font-bold text-zinc-700 transition hover:border-zinc-400 hover:bg-zinc-50"
          >
            ← Dashboard
          </Link>
        }
      />

      <div className="mt-6 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3.5 text-xs text-amber-900">
        <p className="font-black">⚠️ Hal yang perlu diperhatikan:</p>
        <ul className="mt-1.5 ml-4 list-disc space-y-0.5">
          <li>Promo hanya boleh dibuat melalui tipe Promo.</li>
          <li>Pengumuman hanya boleh dibuat melalui tipe Pengumuman.</li>
          <li>Cek dulu dengan tombol &ldquo;Test ke saya&rdquo; sebelum publish massal.</li>
          <li>Title maks 60 karakter, body maks 180 karakter.</li>
          <li>
            Status Publish akan menyimpan notifikasi ke Notification Center dan
            mengirim push.
          </li>
        </ul>
      </div>

      <div className="mt-6">
        <BroadcastForm />
      </div>
    </div>
  );
}
