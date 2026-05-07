import { LegalPage, Section } from "@/components/LegalPage";
import { OperatingHours } from "@/components/OperatingHours";

export const metadata = {
  title: "Syarat & Ketentuan",
  description:
    "Syarat dan ketentuan penggunaan layanan Natalo Petshop & Aquarium.",
};

export default function SyaratKetentuanPage() {
  return (
    <LegalPage title="Syarat & Ketentuan" updated="Januari 2026">
      <Section title="1. Penerimaan Syarat">
        Dengan mengakses dan menggunakan website Natalo Petshop & Aquarium
        (natalopetshop.com), kamu dianggap telah membaca, memahami, dan menyetujui
        seluruh syarat dan ketentuan yang berlaku. Apabila kamu tidak menyetujui syarat
        ini, mohon untuk tidak menggunakan layanan kami.
      </Section>

      <Section title="2. Produk dan Ketersediaan">
        Kami berusaha menampilkan foto, deskripsi, dan harga produk secara akurat. Namun
        demikian, ketersediaan stok dapat berubah sewaktu-waktu. Natalo Petshop berhak
        membatalkan pesanan apabila produk tidak tersedia dan akan mengembalikan pembayaran
        secara penuh.
      </Section>

      <Section title="3. Pemesanan dan Pembayaran">
        Pesanan dianggap sah setelah pembayaran dikonfirmasi oleh sistem. Bukti pembayaran
        akan dikirimkan melalui email/whatsapp yang terdaftar. Natalo Petshop menggunakan
        payment gateway berkeamanan tinggi untuk memproses semua transaksi.
      </Section>

      <Section title="4. Pengiriman">
        Pengiriman dilakukan setelah pembayaran dikonfirmasi. Estimasi
        pengiriman bergantung pada layanan kurir yang dipilih dan lokasi tujuan.
        Kami tidak bertanggung jawab atas keterlambatan yang disebabkan oleh
        pihak kurir atau kondisi di luar kendali kami.
        <OperatingHours className="mt-4 space-y-1" />
      </Section>

      <Section title="5. Harga">
        Harga yang tertera adalah harga dalam Rupiah (IDR) dan sudah termasuk PPN apabila
        berlaku. Harga dapat berubah sewaktu-waktu tanpa pemberitahuan sebelumnya. Harga
        yang berlaku adalah harga pada saat pesanan dikonfirmasi.
      </Section>

      <Section title="6. Akun Pengguna">
        Kamu bertanggung jawab menjaga kerahasiaan kata sandi akun. Natalo Petshop tidak
        bertanggung jawab atas kerugian akibat penyalahgunaan akun yang disebabkan oleh
        kelalaian pengguna. Segera hubungi kami apabila mencurigai aktivitas tidak sah
        pada akunmu.
      </Section>

      <Section title="7. Hak Kekayaan Intelektual">
        Seluruh konten di website ini — termasuk teks, foto, logo, dan desain — merupakan
        milik Natalo Petshop atau pihak yang telah memberikan lisensi. Dilarang
        menggunakan, menyalin, atau mendistribusikan konten tanpa izin tertulis.
      </Section>

      <Section title="8. Perubahan Syarat">
        Natalo Petshop berhak mengubah syarat dan ketentuan ini kapan saja. Perubahan akan
        diberitahukan melalui website dan berlaku sejak tanggal publikasi.
      </Section>

      <Section title="9. Kontak">
        Untuk pertanyaan mengenai syarat dan ketentuan ini, hubungi kami melalui WhatsApp
        atau email yang tertera di halaman Tentang Kami.
      </Section>
    </LegalPage>
  );
}
