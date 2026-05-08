import Link from "next/link";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import DeleteAccountForm from "@/components/DeleteAccountForm";

export const dynamic = "force-dynamic";

export const metadata = {
  title: "Hapus Akun",
  description: "Hapus akun Natalo Petshop kamu secara permanen.",
};

export default async function DeleteAccountPage() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    redirect("/member/login");
  }

  const [pointTotal, voucherCount, orderCount] = await Promise.all([
    prisma.customerPoint
      .aggregate({ where: { userId: session.sub }, _sum: { points: true } })
      .then((r) => r._sum.points ?? 0)
      .catch(() => 0),
    prisma.voucher
      .count({
        where: {
          userId: session.sub,
          isActive: true,
          OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
        },
      })
      .catch(() => 0),
    prisma.order.count({ where: { userId: session.sub } }).catch(() => 0),
  ]);

  return (
    <main className="min-h-screen bg-zinc-50 px-4 py-8">
      <div className="mx-auto max-w-md">
        <div className="mb-6 flex items-center gap-3">
          <Link
            href="/member"
            aria-label="Kembali ke halaman akun"
            className="flex h-10 w-10 items-center justify-center rounded-full bg-white text-zinc-600 shadow-sm hover:bg-zinc-100"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="h-4 w-4"
              aria-hidden
            >
              <path d="m15 6-6 6 6 6" />
            </svg>
          </Link>
          <h1 className="text-xl font-black text-red-600">Hapus Akun</h1>
        </div>

        <div className="rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p className="font-bold">⚠️ Tindakan ini permanen</p>
          <ul className="mt-2 list-disc space-y-1 pl-5 text-[13px] leading-relaxed">
            <li>
              Akun, profil, alamat, hewan peliharaan, wishlist, dan keranjang akan dihapus segera.
            </li>
            <li>
              {pointTotal > 0
                ? `${pointTotal.toLocaleString("id-ID")} loyalty point akan hangus.`
                : "Loyalty point yang tersimpan akan hangus."}
            </li>
            {voucherCount > 0 && (
              <li>{voucherCount} voucher aktif akan hangus.</li>
            )}
            {orderCount > 0 && (
              <li>
                Riwayat {orderCount} pesanan tetap kami simpan tanpa identitas kamu (untuk
                kewajiban pajak & akuntansi).
              </li>
            )}
            <li>Email yang sama tidak bisa daftar ulang segera setelah penghapusan.</li>
          </ul>
        </div>

        <div className="mt-4 rounded-2xl border border-blue-100 bg-blue-50 p-4 text-[13px] leading-relaxed text-blue-900">
          <p className="font-bold text-blue-800">💡 Daripada hapus, mau coba dulu?</p>
          <ul className="mt-2 space-y-1">
            <li>
              <span className="font-semibold">Logout</span> dan kembali kapan saja.
            </li>
            <li>
              <span className="font-semibold">Mute notifikasi</span> dari pengaturan browser.
            </li>
            <li>
              Tanya admin di{" "}
              <a
                href="https://wa.me/6281289997113"
                className="font-semibold underline"
                target="_blank"
                rel="noreferrer"
              >
                WhatsApp
              </a>{" "}
              kalau ada masalah.
            </li>
          </ul>
        </div>

        <DeleteAccountForm />

        <Link
          href="/member"
          className="mt-3 block w-full rounded-full border border-zinc-200 bg-white py-3 text-center text-sm font-bold text-zinc-700 hover:bg-zinc-50"
        >
          Batal, kembali
        </Link>
      </div>
    </main>
  );
}
