import Link from "next/link";
import { BroadcastForm } from "./BroadcastForm";

export const dynamic = "force-dynamic";

export default function AdminBroadcastPage() {
  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      <div className="mb-6">
        <Link href="/admin/dashboard" className="text-xs font-bold text-zinc-500 hover:underline">
          ← Kembali ke dashboard
        </Link>
        <h1 className="mt-2 text-2xl font-black text-zinc-950">Broadcast Notification</h1>
        <p className="mt-1 text-sm text-zinc-500">
          Kirim push notification massal ke user yang punya app installed / PWA aktif.
          Bisa target spesifik segment (semua / member yg pernah belanja / aktif 30 hari).
        </p>
      </div>

      <div className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-xs text-amber-900">
        <p className="font-bold">⚠ Hal yang perlu diperhatikan:</p>
        <ul className="mt-1 ml-4 list-disc space-y-0.5">
          <li>Push dikirim ke iOS native (TestFlight/App Store) + Web Push (PWA Chrome/Safari).</li>
          <li>Cek dulu dengan tombol "Test ke saya" sebelum kirim massal.</li>
          <li>Title maks 60 karakter, body maks 180 karakter.</li>
          <li>Action tidak bisa di-batalkan. Pesan langsung muncul di hp user.</li>
        </ul>
      </div>

      <div className="mt-6">
        <BroadcastForm />
      </div>
    </div>
  );
}
