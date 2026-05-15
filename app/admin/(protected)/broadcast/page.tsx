import Link from "next/link";
import { BroadcastForm } from "./BroadcastForm";

export const dynamic = "force-dynamic";

export default function AdminBroadcastPage() {
  return (
    <div className="mx-auto max-w-2xl px-4 py-5 md:py-8">
      <div className="mb-6">
        <Link href="/admin/dashboard" className="text-xs font-bold text-zinc-500 hover:underline">
          Kembali ke dashboard
        </Link>
        <h1 className="mt-2 text-2xl font-black text-zinc-950">Broadcast Notifikasi</h1>
        <p className="mt-1 text-sm text-zinc-500">
          Buat promo atau pengumuman resmi Natalo Petshop. Setelah publish,
          notifikasi masuk ke Notification Center user sesuai tipe broadcast.
        </p>
      </div>

      <div className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-xs text-amber-900">
        <p className="font-bold">Hal yang perlu diperhatikan:</p>
        <ul className="mt-1 ml-4 list-disc space-y-0.5">
          <li>Promo hanya boleh dibuat dari Dashboard Admin melalui tipe Promo.</li>
          <li>Pengumuman hanya boleh dibuat dari Dashboard Admin melalui tipe Pengumuman.</li>
          <li>Cek dulu dengan tombol "Test ke saya" sebelum publish massal.</li>
          <li>Title maks 60 karakter, body maks 180 karakter.</li>
          <li>Status Publish akan menyimpan notifikasi ke Notification Center dan mengirim push.</li>
        </ul>
      </div>

      <div className="mt-6">
        <BroadcastForm />
      </div>
    </div>
  );
}
