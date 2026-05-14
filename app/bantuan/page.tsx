import type { Metadata } from "next";
import Link from "next/link";
import { StickyBackTitle } from "@/components/StickyBackTitle";

export const metadata: Metadata = {
  title: "Pusat Bantuan",
  description:
    "Pusat bantuan Natalo Petshop & Aquarium — FAQ, cara order, status pesanan, return policy, kontak customer service.",
};

type FAQ = {
  q: string;
  a: React.ReactNode;
};

const FAQS: FAQ[] = [
  {
    q: "Bagaimana cara order di Natalo Petshop?",
    a: (
      <>
        Klik produk yang kamu inginkan → pilih varian (size/flavor) kalau ada →
        klik "Tambah ke Keranjang" → buka keranjang di pojok kanan atas → klik
        "Checkout" → isi alamat pengiriman → pilih kurir & metode pembayaran →
        bayar. Kamu akan dapat email konfirmasi setelah pembayaran sukses.
      </>
    ),
  },
  {
    q: "Berapa lama pengiriman?",
    a: (
      <>
        Untuk area Medan kota: Instant Max 3 Jam dengan kurir Natalo (tersedia
        jam operasional 10:00–17:00). Untuk seluruh Indonesia: 1-3 hari kerja
        via JNE / J&T / SiCepat, tergantung lokasi dan kurir yang dipilih.
      </>
    ),
  },
  {
    q: "Apa saja metode pembayaran yang tersedia?",
    a: (
      <>
        Kartu kredit & debit (Visa, Mastercard, JCB), e-wallet (GoPay, OVO,
        DANA, ShopeePay), virtual account (BCA, BRI, BNI, Mandiri, Permata),
        QRIS, dan transfer manual ke rekening Natalo. Semua via gateway
        Midtrans yang aman & ter-enkripsi.
      </>
    ),
  },
  {
    q: "Bagaimana cara cek status pesanan?",
    a: (
      <>
        Login ke akun → menu "Akun" → "Riwayat Pesanan". Atau pakai link
        tracking yang dikirim ke email kamu setelah order dibuat. Tidak punya
        akun? Buka{" "}
        <Link href="/order-status" className="text-natalo-700 underline">
          /order-status
        </Link>{" "}
        dan masukkan nomor order + email kamu.
      </>
    ),
  },
  {
    q: "Bisa return / refund kalau produk salah / rusak?",
    a: (
      <>
        Bisa. Hubungi customer service via WhatsApp dalam 1×24 jam setelah
        terima paket. Sertakan foto produk + nomor order. Kami akan proses
        return/exchange/refund sesuai kondisi (max 7 hari).
      </>
    ),
  },
  {
    q: "Bagaimana cara dapat loyalty point?",
    a: (
      <>
        Setiap pembelian dapat point (1 point per Rp 10.000 belanja). Login
        member dulu untuk akumulasi point. Tukar point dengan voucher diskon di
        halaman "Akun → Loyalty Point". Member baru otomatis dapat voucher
        Rp 50.000 untuk order pertama (kode: NATA-NEW).
      </>
    ),
  },
  {
    q: "Apakah produk yang dijual original?",
    a: (
      <>
        Ya, 100% original dari distributor resmi Indonesia. Royal Canin,
        Whiskas, Pedigree, Pro Plan, Hill's, Happy Dog, Goodog, dll. Tersedia
        invoice resmi + garansi brand. Cek tanggal expired di kemasan saat
        terima paket.
      </>
    ),
  },
  {
    q: "Bagaimana cara hapus akun Natalo?",
    a: (
      <>
        Login → buka{" "}
        <Link href="/akun/hapus-akun" className="text-natalo-700 underline">
          Hapus Akun
        </Link>{" "}
        di pengaturan akun. Konfirmasi dengan password kamu. Data pribadi
        dihapus dalam 30 hari sesuai{" "}
        <Link href="/kebijakan-privasi" className="text-natalo-700 underline">
          Kebijakan Privasi
        </Link>
        .
      </>
    ),
  },
  {
    q: "App iOS kelihatan beda dari web — fitur apa yang khusus app?",
    a: (
      <>
        App native iOS Natalo (via TestFlight / App Store) punya splash screen
        brand, pull-to-refresh, swipe-back gesture, share sheet native iOS,
        push notification real-time order update, dan Universal Links (klik
        link Natalo di WhatsApp buka langsung di app). Pengalaman lebih
        seamless dari web browser.
      </>
    ),
  },
  {
    q: "Bisa konsultasi langsung dengan tim Natalo?",
    a: (
      <>
        Bisa! Datang langsung ke toko fisik Natalo Petshop & Aquarium di Medan,
        Sumatera Utara (jam operasional Senin-Sabtu). Atau chat WhatsApp customer
        service via tombol hijau di pojok kanan bawah app. Konsultasi gratis
        untuk pertanyaan produk, perawatan hewan, dan rekomendasi pakan.
      </>
    ),
  },
];

export default function BantuanPage() {
  return (
    <div className="min-h-screen bg-slate-50 pb-20">
      <StickyBackTitle label="Pusat Bantuan" fallbackHref="/" stickToTop />
      <div className="mx-auto max-w-3xl px-4 py-6 sm:px-6 sm:py-8">
        <div className="mb-6">
          <p className="mt-1 text-sm text-zinc-500">
            Pertanyaan umum, kontak customer service, dan panduan menggunakan app.
          </p>
        </div>

      <section className="space-y-3 text-sm leading-relaxed text-zinc-700 sm:text-base">
        {FAQS.map((item, i) => (
          <details
            key={i}
            className="group rounded-2xl border border-zinc-200 bg-white p-4 transition open:shadow-sm"
          >
            <summary className="cursor-pointer list-none font-bold text-zinc-950 [&::-webkit-details-marker]:hidden">
              <div className="flex items-start justify-between gap-3">
                <span>{item.q}</span>
                <svg
                  className="mt-1 h-4 w-4 shrink-0 text-zinc-400 transition group-open:rotate-180"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth={2.5}
                >
                  <path d="m6 9 6 6 6-6" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </div>
            </summary>
            <div className="mt-3 text-zinc-600">{item.a}</div>
          </details>
        ))}
      </section>

      <div className="mt-10 rounded-2xl border border-natalo-100 bg-natalo-50 p-6">
        <h2 className="text-base font-black text-natalo-900 sm:text-lg">
          Tidak menemukan jawaban?
        </h2>
        <p className="mt-2 text-sm text-natalo-800">
          Tim Natalo siap bantu Senin-Sabtu, sesuai jam operasional toko. Kamu bisa
          menghubungi kami melalui WhatsApp di 081289997113 atau email{" "}
          <a
            href="mailto:Natalopetshop@gmail.com"
            className="font-bold text-natalo-900 underline"
          >
            Natalopetshop@gmail.com
          </a>
          .
        </p>
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <Link
            href="/tentang-kami"
            className="rounded-xl border border-natalo-200 bg-white px-4 py-3 text-sm font-bold text-natalo-800 hover:bg-natalo-100"
          >
            Tentang Natalo
          </Link>
          <Link
            href="/syarat-ketentuan"
            className="rounded-xl border border-natalo-200 bg-white px-4 py-3 text-sm font-bold text-natalo-800 hover:bg-natalo-100"
          >
            Syarat & Ketentuan
          </Link>
          <Link
            href="/kebijakan-privasi"
            className="rounded-xl border border-natalo-200 bg-white px-4 py-3 text-sm font-bold text-natalo-800 hover:bg-natalo-100"
          >
            Kebijakan Privasi
          </Link>
          <Link
            href="/kebijakan-pengembalian"
            className="rounded-xl border border-natalo-200 bg-white px-4 py-3 text-sm font-bold text-natalo-800 hover:bg-natalo-100"
          >
            Kebijakan Pengembalian
          </Link>
        </div>
      </div>
      </div>
    </div>
  );
}
