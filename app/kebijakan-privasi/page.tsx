import { LegalPage, Section } from "@/components/LegalPage";
import { OperatingHours } from "@/components/OperatingHours";

export const metadata = {
  title: "Kebijakan Privasi",
  description:
    "Kebijakan privasi dan perlindungan data pelanggan Natalo Petshop & Aquarium.",
};

export default function KebijakanPrivasiPage() {
  return (
    <LegalPage title="Kebijakan Privasi" updated="Januari 2026">
      <Section title="1. Data yang Kami Kumpulkan">
        Kami mengumpulkan informasi yang kamu berikan saat mendaftar dan berbelanja: nama
        lengkap, alamat email, nomor telepon, dan alamat pengiriman. Kami juga mengumpulkan
        data teknis seperti alamat IP dan perangkat yang digunakan untuk meningkatkan
        keamanan layanan.
      </Section>

      <Section title="2. Penggunaan Data">
        Data kamu digunakan untuk: memproses pesanan dan pembayaran, mengirimkan
        konfirmasi dan notifikasi, meningkatkan pengalaman berbelanja, serta mengirimkan
        informasi promo (hanya jika kamu menyetujui). Kami tidak menjual atau menyewakan
        data pribadi kamu kepada pihak ketiga.
      </Section>

      <Section title="3. Keamanan Data">
        Kami menerapkan enkripsi SSL/TLS untuk semua data yang dikirimkan. Kata sandi
        disimpan dalam bentuk terenkripsi dan tidak dapat dibaca oleh siapapun, termasuk
        tim kami. Akses ke data pengguna dibatasi hanya untuk personel yang berwenang.
      </Section>

      <Section title="4. Cookie">
        Website ini menggunakan cookie untuk menyimpan preferensi dan sesi login kamu.
        Cookie tidak menyimpan informasi pembayaran. Kamu dapat menonaktifkan cookie
        melalui pengaturan browser, namun beberapa fitur mungkin tidak berfungsi optimal.
      </Section>

      <Section title="5. Pihak Ketiga">
        Kami bekerja sama dengan payment gateway dan jasa pengiriman untuk memproses
        pesananmu. Pihak-pihak ini memiliki kebijakan privasi tersendiri dan hanya menerima
        data yang diperlukan untuk menyelesaikan transaksi.
      </Section>

      <Section title="6. Hak Kamu">
        Kamu berhak mengakses, memperbarui, atau meminta penghapusan data pribadi kamu.
        Hubungi kami melalui WhatsApp atau email untuk mengajukan permintaan tersebut.
        Kami akan merespons dalam waktu 7 hari kerja.
      </Section>

      <Section title="7. Perubahan Kebijakan">
        Kebijakan privasi ini dapat diperbarui dari waktu ke waktu. Kami akan
        memberitahumu melalui email apabila ada perubahan yang signifikan.
      </Section>

      <Section title="8. Jam Operasional">
        <OperatingHours className="space-y-1" />
      </Section>
    </LegalPage>
  );
}
