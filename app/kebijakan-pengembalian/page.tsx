import { LegalPage, Section } from "@/components/LegalPage";
import { OperatingHours } from "@/components/OperatingHours";
import { PageStatusBar } from "@/components/PageStatusBar";
import { StickyBackTitle } from "@/components/StickyBackTitle";

export const metadata = {
  title: "Kebijakan Pengembalian & Refund",
  description:
    "Syarat, prosedur, dan ketentuan pengembalian produk serta refund di Natalo Petshop.",
};

export default function KebijakanPengembalianPage() {
  return (
    <>
      <PageStatusBar
        iconColor="dark"
        themeColor="#ffffff"
        nativeBackgroundColor="#ffffff"
        overlaysWebView={false}
      />
      <StickyBackTitle
        label="Kebijakan Pengembalian & Refund"
        fallbackHref="/account/settings"
        stickToTop
      />
      <LegalPage
        title="Kebijakan Pengembalian & Refund"
        updated="Januari 2026"
        showHeading={false}
      >
        <Section title="Batas Waktu Komplain">
          Pengajuan komplain wajib dilakukan maksimal 1x24 jam setelah produk
          diterima. Sertakan nomor pesanan, foto produk, foto kemasan, dan video
          unboxing/kondisi produk sebagai bukti. Komplain yang masuk melewati
          batas waktu tersebut tidak dapat diproses.
        </Section>

        <Section title="Syarat Pengembalian Produk">
          Pengembalian hanya berlaku untuk produk yang rusak, cacat produksi,
          salah kirim, atau tidak sesuai deskripsi. Produk harus masih dalam
          kondisi asli, kemasan lengkap, belum digunakan, dan belum dibuka
          kecuali kerusakan baru terlihat saat produk diterima.
        </Section>

        <Section title="Produk yang Tidak Dapat Dikembalikan">
          Demi alasan kebersihan dan keamanan, makanan, camilan, obat, vitamin,
          pasir kucing, dan produk grooming/perawatan tidak dapat dikembalikan
          apabila sudah dibuka, digunakan, atau segel kemasannya rusak, kecuali
          terbukti salah kirim atau rusak sejak diterima.
        </Section>

        <Section title="Prosedur Pengembalian">
          Hubungi kami melalui WhatsApp maksimal 1x24 jam setelah produk
          diterima. Tim kami akan memeriksa bukti komplain dan memberi
          keputusan/instruksi lanjutan. Jika komplain disetujui, proses
          pengembalian atau penggantian diselesaikan maksimal 2x24 jam setelah
          persetujuan, tidak termasuk waktu pengiriman dari pihak kurir.
        </Section>

        <Section title="Proses Refund">
          Refund diproses setelah komplain disetujui dan, bila diperlukan,
          produk telah dikembalikan serta diperiksa kondisinya. Pencairan dana
          mengikuti metode pembayaran: transfer bank 1-3 hari kerja dan e-wallet
          1 hari kerja. Biaya pengiriman awal tidak direfund, kecuali kesalahan
          ada di pihak kami.
        </Section>

        <Section title="Produk Rusak saat Pengiriman">
          Apabila produk rusak saat pengiriman, dokumentasikan kondisi paket dan
          produk segera setelah diterima, lalu hubungi kami maksimal 1x24 jam.
          Jika klaim disetujui, kami akan membantu penggantian produk atau
          refund sesuai kondisi kasus.
        </Section>

        <Section title="Jam Operasional">
          <OperatingHours className="space-y-1" />
        </Section>
      </LegalPage>
    </>
  );
}
