import type { Metadata } from "next";
import { OperatingHours } from "@/components/OperatingHours";

export const metadata: Metadata = {
  title: "Tentang Kami",
  description:
    "Natalo Petshop & Aquarium, toko hewan peliharaan terpercaya di Medan yang menyediakan kebutuhan kucing, anjing, ikan hias, dan hewan peliharaan lainnya.",
};

const stats = [
  { num: "2.200+", label: "Produk tersedia" },
  { num: "10+", label: "Tahun pengalaman" },
  { num: "10.000+", label: "Pelanggan puas" },
  { num: "100+", label: "Brand terpercaya" },
];

const commitments = [
  {
    icon: "✅",
    title: "Produk original",
    desc: "Semua produk 100% original dan bersumber dari distributor resmi.",
  },
  {
    icon: "🚀",
    title: "Pengiriman cepat",
    desc: "Proses packing dan pengiriman di hari yang sama untuk pemesanan sebelum pukul 14.00 WIB.",
  },
  {
    icon: "💬",
    title: "Konsultasi gratis",
    desc: "Tim kami siap membantu memilihkan produk yang tepat untuk hewan peliharaanmu.",
  },
  {
    icon: "🔄",
    title: "Garansi produk",
    desc: "Komplain produk cacat atau tidak sesuai dapat diajukan maksimal 1x24 jam setelah diterima.",
  },
];

const contacts = [
  {
    icon: "📍",
    label: "Alamat",
    value: "Jl. MT. Haryono No. 103 BCD, Medan, Sumatera Utara",
  },
  { icon: "📱", label: "WhatsApp", value: "+62 812 8999 7113" },
  { icon: "📧", label: "Email", value: "natalopetshop@gmail.com" },
  {
    icon: "🕐",
    label: "Jam operasional",
    value: "",
  },
];

export default function TentangKamiPage() {
  return (
    <div className="bg-white">
      <section className="bg-[#FAECE7] px-4 py-8 text-center md:px-6 md:py-16">
        <div className="mx-auto max-w-2xl">
          <div className="mb-3 text-4xl md:text-5xl" aria-hidden="true">
            🐾
          </div>
          <h1 className="text-2xl font-bold text-zinc-950 md:text-3xl md:font-medium">
            Natalo Petshop & Aquarium
          </h1>
          <p className="mt-2 text-sm font-medium text-[#712B13] sm:text-base">
            Toko hewan peliharaan terpercaya di Medan
          </p>
        </div>
      </section>

      <div className="mx-auto max-w-4xl px-4 py-6 md:px-6 md:py-12 lg:py-16">
        <section className="mb-8 md:mb-12">
          <h2 className="mb-4 text-xl font-medium text-zinc-950">Cerita kami</h2>
          <div className="space-y-4 text-sm leading-7 text-zinc-700">
            <p>
              Natalo Petshop & Aquarium bermula dari kecintaan kami terhadap
              hewan peliharaan. Didirikan di Medan, kami memulai dengan toko
              kecil di Shopee dan Tokopedia yang menjual perlengkapan kucing,
              anjing, dan ikan hias. Seiring waktu, kepercayaan pelanggan
              membuat kami berkembang menjadi salah satu petshop terlengkap di
              Medan, kini juga melayani pembelian online ke seluruh Indonesia.
            </p>
            <p>
              Kami percaya bahwa hewan peliharaan layak mendapatkan yang
              terbaik, mulai dari nutrisi yang tepat, perawatan yang optimal,
              hingga aksesori yang aman dan berkualitas. Itulah mengapa kami
              hanya menjual produk dari brand terpercaya dan selalu menjaga
              kualitas setiap produk yang kami stok.
            </p>
          </div>
        </section>

        <section className="mb-8 grid grid-cols-2 gap-3 lg:grid-cols-4 md:mb-12">
          {stats.map((stat) => (
            <div
              className="rounded-xl bg-[#f9f9f7] px-4 py-5 text-center"
              key={stat.label}
            >
              <div className="text-3xl font-medium text-[#D85A30]">
                {stat.num}
              </div>
              <div className="mt-1 text-xs text-zinc-500">{stat.label}</div>
            </div>
          ))}
        </section>

        <section className="mb-12">
          <h2 className="mb-4 text-xl font-medium text-zinc-950">
            Komitmen kami
          </h2>
          <div className="grid gap-4 sm:grid-cols-2">
            {commitments.map((item) => (
              <div
                className="rounded-xl border border-zinc-100 bg-white p-5"
                key={item.title}
              >
                <div className="mb-2 text-2xl" aria-hidden="true">
                  {item.icon}
                </div>
                <h3 className="mb-1.5 text-sm font-semibold text-zinc-950">
                  {item.title}
                </h3>
                <p className="text-xs leading-6 text-zinc-600">{item.desc}</p>
              </div>
            ))}
          </div>
        </section>

        <section>
          <h2 className="mb-4 text-xl font-medium text-zinc-950">
            Hubungi kami
          </h2>
          <div className="space-y-3">
            {contacts.map((contact) => (
              <div
                className="flex items-start gap-4 rounded-xl border border-zinc-100 bg-white px-4 py-3.5"
                key={contact.label}
              >
                <span className="text-xl" aria-hidden="true">
                  {contact.icon}
                </span>
                <div>
                  <div className="mb-0.5 text-xs text-zinc-500">
                    {contact.label}
                  </div>
                  {contact.label === "Jam operasional" ? (
                    <OperatingHours className="space-y-1 text-sm text-zinc-950" />
                  ) : (
                    <div className="text-sm text-zinc-950">{contact.value}</div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
