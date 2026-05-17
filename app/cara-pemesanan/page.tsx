import { LegalPage, Section, Steps } from "@/components/LegalPage";
import { OperatingHours } from "@/components/OperatingHours";
import { PageStatusBar } from "@/components/PageStatusBar";
import { StickyBackTitle } from "@/components/StickyBackTitle";

export const metadata = {
  title: "Cara Pemesanan",
  description:
    "Panduan lengkap cara pemesanan dan pembayaran di Natalo Petshop & Aquarium.",
};

export default function CaraPemesananPage() {
  return (
    <>
      <PageStatusBar
        iconColor="dark"
        themeColor="#ffffff"
        nativeBackgroundColor="#ffffff"
        overlaysWebView={false}
      />
      <StickyBackTitle
        label="Cara Pemesanan"
        fallbackHref="/account/settings"
        stickToTop
      />
      <LegalPage
        title="Cara Pemesanan"
        updated="Januari 2026"
        showHeading={false}
      >
        <Steps
          items={[
            {
              n: "1",
              title: "Pilih Produk",
              desc: "Jelajahi katalog kami dan klik produk yang ingin dibeli. Jika produk memiliki varian, pilih varian dan jumlah terlebih dahulu.",
            },
            {
              n: "2",
              title: "Beli Sekarang atau + Keranjang",
              desc: "Pilih varian terlebih dahulu, lalu klik 'Beli Sekarang' untuk langsung masuk ke checkout atau '+ Keranjang' kalau ingin lanjut belanja. Dari katalog, produk varian akan menampilkan tombol 'Pilih Varian'.",
            },
            {
              n: "3",
              title: "Cek Keranjang",
              desc: "Buka halaman Keranjang untuk mengecek pesananmu. Kamu bisa mengubah jumlah atau menghapus produk di sini. Masukkan kode voucher jika punya.",
            },
            {
              n: "4",
              title: "Isi Data Pengiriman",
              desc: "Masukkan nama penerima, nomor telepon, dan alamat lengkap pengiriman. Pilih layanan kurir dan metode pengiriman yang sesuai.",
            },
            {
              n: "5",
              title: "Pilih Pembayaran",
              desc: "Pilih metode pembayaran: transfer bank, virtual account, QRIS, atau e-wallet. Selesaikan pembayaran sesuai instruksi yang tampil.",
            },
            {
              n: "6",
              title: "Konfirmasi Pesanan",
              desc: "Setelah pembayaran berhasil, kamu akan menerima email dan/atau WhatsApp berisi detail pesanan dan nomor invoice.",
            },
            {
              n: "7",
              title: "Produk Dikirim",
              desc: "Kami akan memproses dan mengirimkan pesananmu pada hari kerja berikutnya. Nomor resi pengiriman akan dikirimkan melalui WhatsApp.",
            },
            {
              n: "8",
              title: "Pesanan Diterima",
              desc: "Terima produk, pastikan kondisinya sesuai. Jangan lupa tinggalkan ulasan untuk membantu pembeli lain!",
            },
          ]}
        />

        <Section title="Jam Operasional">
          <OperatingHours className="space-y-1" />
        </Section>

        <Section title="Butuh Bantuan?">
          Hubungi kami melalui WhatsApp. Tim kami siap membantu kamu memilih
          produk yang tepat untuk hewan peliharaanmu.
        </Section>
      </LegalPage>
    </>
  );
}
