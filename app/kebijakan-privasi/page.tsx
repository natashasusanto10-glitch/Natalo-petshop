import { LegalPage, Section } from "@/components/LegalPage";
import { OperatingHours } from "@/components/OperatingHours";

export const metadata = {
  title: "Kebijakan Privasi",
  description:
    "Kebijakan privasi dan perlindungan data pelanggan Natalo Petshop & Aquarium.",
};

export default function KebijakanPrivasiPage() {
  return (
    <LegalPage title="Kebijakan Privasi" updated="9 Mei 2026">
      <Section title="Ringkasan">
        Natalo Petshop & Aquarium ("kami") menghormati privasi pelanggan ("kamu"). Halaman
        ini menjelaskan data apa yang kami kumpulkan saat kamu berbelanja melalui website
        atau aplikasi (PWA / iOS / Android), bagaimana kami memakainya, dengan siapa kami
        bagikan, berapa lama disimpan, dan hak kamu untuk mengakses, mengubah, atau
        menghapusnya. Jika ada pertanyaan, hubungi kami di kontak yang tertera di akhir
        halaman ini.
      </Section>

      <Section title="1. Identitas Pengelola Data">
        <p className="mb-2">
          <b>Natalo Petshop & Aquarium</b>
          <br />
          Toko fisik: Medan, Sumatera Utara, Indonesia
          <br />
          Email: <a className="text-natalo-700 underline" href="mailto:hello@natalopetshop.com">hello@natalopetshop.com</a>
          <br />
          WhatsApp: tersedia di tombol kontak di footer website
        </p>
        Kami bertindak sebagai <i>data controller</i> atas data pribadi yang kamu berikan
        atau yang kami kumpulkan otomatis saat kamu menggunakan layanan.
      </Section>

      <Section title="2. Data yang Kami Kumpulkan">
        <p className="mb-2">
          <b>Data yang kamu berikan langsung saat mendaftar / checkout:</b>
        </p>
        <ul className="mb-3 list-disc space-y-1 pl-5">
          <li>Nama lengkap</li>
          <li>Alamat email</li>
          <li>Nomor WhatsApp / telepon</li>
          <li>Alamat pengiriman lengkap (jalan, kota, provinsi, kode pos)</li>
          <li>Riwayat pesanan dan ulasan produk yang kamu tulis</li>
        </ul>
        <p className="mb-2">
          <b>Data teknis yang dikumpulkan otomatis:</b>
        </p>
        <ul className="mb-3 list-disc space-y-1 pl-5">
          <li>Alamat IP, jenis perangkat, sistem operasi, dan browser</li>
          <li>Cookie sesi (auth token JWT, preferensi tampilan)</li>
          <li>Log aktivitas keamanan: waktu login, halaman yang diakses, perangkat aktif</li>
          <li>
            <b>Khusus aplikasi iOS/Android:</b> push notification token (jika kamu mengaktifkan notifikasi),
            ID perangkat, dan versi aplikasi — untuk debugging crash dan kirim notifikasi pesanan.
          </li>
        </ul>
        Kami <b>tidak</b> mengumpulkan data sensitif seperti nomor KTP, NIK, atau data
        biometrik. Kami juga <b>tidak</b> mengakses kamera, mikrofon, kontak, atau lokasi
        GPS perangkat tanpa persetujuan eksplisit kamu untuk fitur tertentu.
      </Section>

      <Section title="3. Bagaimana Kami Memakai Data Kamu">
        <ul className="list-disc space-y-1 pl-5">
          <li>Memproses pesanan, pembayaran, dan pengiriman ke alamat kamu</li>
          <li>Mengirim konfirmasi order, status pengiriman, dan update pesanan via email/WhatsApp</li>
          <li>Memberikan customer service ketika kamu menghubungi kami</li>
          <li>Menampilkan riwayat pesanan dan poin loyalty di akun kamu</li>
          <li>Mendeteksi & mencegah penipuan, akun palsu, dan aktivitas mencurigakan</li>
          <li>Mengirim promo & informasi produk baru — <b>hanya jika kamu setuju</b> di halaman pengaturan akun</li>
          <li>Menganalisis penggunaan website untuk peningkatan UX (data anonim/agregat)</li>
        </ul>
      </Section>

      <Section title="4. Pihak Ketiga yang Memproses Data">
        <p className="mb-2">
          Kami menggunakan layanan pihak ketiga berikut untuk menjalankan operasi toko.
          Setiap layanan punya kebijakan privasi sendiri yang patut kamu baca:
        </p>
        <ul className="space-y-2 pl-5">
          <li>
            <b>Midtrans</b> (PT Midtrans / Gojek Group) — payment gateway untuk memproses
            pembayaran kartu, e-wallet, dan virtual account. Menerima: nama, email, nominal
            pembayaran. <a className="text-natalo-700 underline" href="https://midtrans.com/privacy" target="_blank" rel="noopener noreferrer">Privacy policy Midtrans</a>
          </li>
          <li>
            <b>Resend</b> (Resend.com) — penyedia layanan email transaksional (konfirmasi
            order, reset password). Menerima: email, nama, isi notifikasi.
            <a className="text-natalo-700 underline ml-1" href="https://resend.com/legal/privacy-policy" target="_blank" rel="noopener noreferrer">Privacy policy Resend</a>
          </li>
          <li>
            <b>Vercel</b> (Vercel Inc.) — hosting infrastruktur website. Menerima: log akses
            (IP, user agent), tidak menerima isi data pribadi pesanan.
            <a className="text-natalo-700 underline ml-1" href="https://vercel.com/legal/privacy-policy" target="_blank" rel="noopener noreferrer">Privacy policy Vercel</a>
          </li>
          <li>
            <b>UploadThing</b> — penyimpanan gambar produk dan upload yang kamu kirim
            (mis. foto review). Menerima: file gambar yang kamu unggah.
          </li>
          <li>
            <b>Meilisearch</b> — index pencarian produk. Tidak menerima data pelanggan,
            hanya katalog produk publik.
          </li>
          <li>
            <b>Apple Inc.</b> (jika kamu pakai aplikasi iOS via TestFlight/App Store) —
            menerima crash logs dan analytics agregat sesuai pilihan kamu di pengaturan
            iPhone. Push notification dikirim via Apple Push Notification Service (APNs).
          </li>
          <li>
            <b>Jasa pengiriman</b> (JNE, J&T, SiCepat, Gojek, Grab, dll, sesuai pilihan
            kamu di checkout) — menerima nama, alamat, dan nomor telepon untuk antar paket.
          </li>
        </ul>
        <p className="mt-3">
          Kami <b>tidak menjual</b> dan <b>tidak menyewakan</b> data kamu ke pihak lain
          untuk tujuan iklan atau profiling pihak ketiga.
        </p>
      </Section>

      <Section title="5. Cookie & Penyimpanan Lokal">
        Kami menggunakan cookie HTTP (jenis httpOnly, secure, SameSite=Lax) untuk menyimpan
        token autentikasi dan preferensi tampilan. Cookie tidak menyimpan data pembayaran.
        Aplikasi mobile (iOS/Android) menggunakan local storage perangkat untuk cache
        gambar produk dan token sesi. Kamu bisa hapus cookie/storage kapan saja melalui
        pengaturan browser atau pengaturan aplikasi (Logout dari semua perangkat).
      </Section>

      <Section title="6. Keamanan Data">
        <ul className="list-disc space-y-1 pl-5">
          <li>Semua transmisi data dienkripsi via SSL/TLS (HTTPS)</li>
          <li>Kata sandi di-hash dengan bcrypt (salt unik per user, tidak bisa dibalik)</li>
          <li>Token autentikasi pakai JWT yang ditandatangani secara kriptografis</li>
          <li>Database tersimpan di provider berkantor di Indonesia/Asia, dengan enkripsi at-rest</li>
          <li>Hanya tim Natalo yang berwenang yang bisa mengakses data pesanan, dengan jejak audit</li>
          <li>Pelanggaran keamanan akan kami beritahu via email dalam 72 jam jika berdampak pada kamu</li>
        </ul>
      </Section>

      <Section title="7. Berapa Lama Data Disimpan">
        <ul className="list-disc space-y-1 pl-5">
          <li><b>Data akun aktif:</b> selama akun kamu aktif</li>
          <li><b>Riwayat pesanan:</b> 5 tahun (untuk kepatuhan pajak & customer service)</li>
          <li><b>Log akses & sesi:</b> 90 hari, lalu di-anonim atau dihapus</li>
          <li><b>Data marketing (jika kamu setuju):</b> sampai kamu unsubscribe</li>
          <li><b>Setelah kamu hapus akun:</b> data pribadi dihapus dalam 30 hari, kecuali yang wajib disimpan oleh hukum (mis. faktur pajak 10 tahun, di-anonim)</li>
        </ul>
      </Section>

      <Section title="8. Hak Kamu Atas Data">
        <p className="mb-2">Kamu berhak untuk:</p>
        <ul className="mb-3 list-disc space-y-1 pl-5">
          <li><b>Mengakses</b> data pribadi yang kami simpan tentang kamu</li>
          <li><b>Memperbaiki</b> data yang salah atau outdated</li>
          <li><b>Menghapus akun</b> dan seluruh data pribadi (lihat section 9)</li>
          <li><b>Menarik persetujuan</b> marketing kapan saja (link unsubscribe di setiap email)</li>
          <li><b>Memindahkan data</b> (data portability) — minta export data dalam format machine-readable</li>
          <li><b>Mengajukan keluhan</b> ke kami atau ke otoritas perlindungan data</li>
        </ul>
        Kami akan merespons permintaan kamu dalam <b>7 hari kerja</b>.
      </Section>

      <Section title="9. Cara Hapus Akun">
        <p className="mb-2">
          Sesuai hak kamu dan kewajiban Apple App Store guideline 5.1.1(v), kamu bisa
          minta hapus akun dengan dua cara:
        </p>
        <ol className="mb-3 list-decimal space-y-1 pl-5">
          <li>
            Login ke akun, lalu buka halaman{" "}
            <a className="text-natalo-700 underline" href="/akun/hapus-akun">
              Hapus Akun
            </a>{" "}
            (akan minta konfirmasi password & alasan).
          </li>
          <li>
            Atau kirim email ke{" "}
            <a className="text-natalo-700 underline" href="mailto:hello@natalopetshop.com?subject=Permintaan%20Hapus%20Akun">
              hello@natalopetshop.com
            </a>{" "}
            dengan subjek "Permintaan Hapus Akun" dan email/nomor WhatsApp yang terdaftar.
          </li>
        </ol>
        <p>
          Setelah verifikasi (1-3 hari kerja), data pribadi kamu (nama, alamat, nomor
          telepon) akan dihapus dalam 30 hari. Riwayat transaksi yang wajib disimpan untuk
          pajak akan di-anonim (nama diganti "Pelanggan Dihapus") dan tidak bisa dikaitkan
          balik ke kamu.
        </p>
      </Section>

      <Section title="10. Privasi Anak">
        Layanan Natalo Petshop ditujukan untuk pengguna berusia <b>13 tahun ke atas</b>.
        Kami tidak secara sengaja mengumpulkan data dari anak di bawah 13 tahun. Jika
        kamu orang tua/wali dan menemukan anak kamu memberikan data kepada kami tanpa
        izin, hubungi kami dan kami akan hapus data tersebut segera.
      </Section>

      <Section title="11. Transfer Data Internasional">
        Sebagian penyedia layanan kami (mis. Vercel, Resend, Apple) berbasis di luar
        Indonesia. Saat data kamu diproses oleh layanan tersebut, data tersebut bisa
        ditransfer ke server di Singapura, Amerika Serikat, atau lokasi lain. Kami pastikan
        penyedia layanan tersebut memiliki standar perlindungan data setara dengan UU
        Pelindungan Data Pribadi (UU PDP) Indonesia melalui kontrak Data Processing
        Agreement (DPA).
      </Section>

      <Section title="12. Perubahan Kebijakan">
        Kebijakan privasi ini dapat diperbarui dari waktu ke waktu seiring perubahan
        layanan atau hukum. Tanggal "Terakhir diperbarui" di atas akan kami sesuaikan.
        Untuk perubahan signifikan (mis. penambahan kategori data baru, third-party baru),
        kami akan kirim notifikasi email ke kamu sebelum perubahan berlaku.
      </Section>

      <Section title="13. Kontak">
        Pertanyaan, keluhan, atau permintaan terkait data pribadi:
        <ul className="mt-2 list-none space-y-1 pl-0">
          <li>
            📧 Email:{" "}
            <a className="text-natalo-700 underline" href="mailto:hello@natalopetshop.com">
              hello@natalopetshop.com
            </a>
          </li>
          <li>💬 WhatsApp: tombol kontak di footer website</li>
          <li>🏪 Alamat fisik: Natalo Petshop & Aquarium, Medan, Sumatera Utara</li>
        </ul>
      </Section>

      <Section title="14. Jam Operasional Layanan Privasi">
        <OperatingHours className="space-y-1" />
      </Section>
    </LegalPage>
  );
}
