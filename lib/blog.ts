export type BlogPost = {
  slug: string;
  title: string;
  excerpt: string;
  content: string;
  tag: string;
  emoji: string;
  date: string;
  readTime: string;
};

export const BLOG_POSTS: BlogPost[] = [
  {
    slug: "tips-merawat-ikan-hias",
    title: "Tips Merawat Ikan Hias agar Tetap Sehat dan Warna Tetap Cerah",
    excerpt: "Ikan hias yang sehat punya warna cerah dan aktif bergerak. Simak tips perawatan sederhana yang bisa kamu lakukan setiap hari.",
    tag: "Aquarium",
    emoji: "🐠",
    date: "1 Mei 2026",
    readTime: "5 menit",
    content: `
## Kenapa Warna Ikan Hias Memudar?

Warna ikan hias yang memudar biasanya disebabkan oleh stres, kualitas air yang buruk, atau nutrisi yang kurang. Ikan yang stres akan terlihat lebih pucat dan kurang aktif.

## 1. Jaga Kualitas Air

Kualitas air adalah faktor terpenting dalam memelihara ikan hias. Lakukan:

- **Ganti air 20–30%** setiap minggu, jangan langsung ganti semua
- **Cek parameter air** secara rutin: pH 6.5–7.5, suhu 24–28°C, amonia 0 ppm
- Gunakan filter yang sesuai kapasitas akuarium
- Deklorinasi air PAM sebelum dimasukkan ke akuarium

## 2. Beri Pakan Berkualitas dan Variatif

Pakan yang baik = warna yang cerah. Kombinasikan:

- **Pelet** sebagai pakan utama (Hikari, Sera, atau Tetra)
- **Cacing sutra** atau **artemia** sebagai pakan hidup/beku 2–3x seminggu
- **Spirulina** untuk ikan herbivora seperti molly dan platy

Jangan overfeeding — beri pakan secukupnya yang habis dalam 3 menit.

## 3. Pencahayaan yang Cukup

Cahaya membantu ikan menunjukkan warna terbaiknya. Idealnya:

- 8–10 jam cahaya per hari
- Gunakan lampu LED akuarium full spectrum
- Hindari sinar matahari langsung (bisa picu alga)

## 4. Hindari Overstocking

Terlalu banyak ikan = kualitas air cepat buruk = ikan stres. Aturan umum: **1 cm ikan per 1 liter air**.

## 5. Karantina Ikan Baru

Sebelum masukkan ikan baru, karantina 1–2 minggu di akuarium terpisah untuk mencegah penyebaran penyakit.

> **Tips Pro:** Tambahkan garam akuarium (1 sendok teh per 10 liter) untuk menjaga keseimbangan elektrolit dan mencegah jamur pada ikan.
    `.trim(),
  },
  {
    slug: "panduan-pakan-kucing",
    title: "Panduan Memilih Pakan Kucing Sesuai Usia dan Kondisi Kesehatan",
    excerpt: "Bukan sembarang pakan bisa diberikan ke kucingmu. Pelajari cara memilih pakan yang tepat berdasarkan usia dan kebutuhan spesifik si kucing.",
    tag: "Kucing",
    emoji: "🐱",
    date: "28 Apr 2026",
    readTime: "6 menit",
    content: `
## Mengapa Memilih Pakan yang Tepat itu Penting?

Kucing adalah karnivora obligat — mereka **wajib** mengonsumsi protein hewani. Pakan yang salah bisa menyebabkan malnutrisi, masalah ginjal, atau kegemukan.

## Pakan Berdasarkan Usia

### Kitten (0–12 bulan)
- Butuh kalori dan protein tinggi untuk pertumbuhan
- Pilih pakan berlabel **"For Kitten"** atau **"All Life Stages"**
- Rekomendasi: Royal Canin Kitten, Whiskas Kitten
- Frekuensi: 3–4x sehari, porsi kecil

### Dewasa (1–7 tahun)
- Kebutuhan nutrisi lebih stabil
- Perhatikan kandungan protein ≥30%, lemak 15–20%
- Hindari pakan tinggi karbohidrat
- Rekomendasi: Royal Canin Adult, Hills Science Diet

### Senior (7+ tahun)
- Butuh protein tinggi tapi rendah fosfor (jaga ginjal)
- Pilih pakan berlabel **"Senior"**
- Pertimbangkan pakan basah untuk hidrasi lebih baik

## Pakan Basah vs Pakan Kering

| | Pakan Kering | Pakan Basah |
|---|---|---|
| Hidrasi | Rendah | Tinggi |
| Kebersihan gigi | Lebih baik | Kurang |
| Harga | Lebih murah | Lebih mahal |
| Cocok untuk | Kucing aktif | Kucing sakit, senior |

**Idealnya:** Kombinasikan keduanya.

## Kondisi Khusus

- **Kucing steril:** Pilih pakan khusus steril — lebih rendah kalori
- **Kucing gemuk:** Pakan "weight control" atau "light"
- **Masalah ginjal:** Pakan rendah fosfor dan protein (konsultasikan ke dokter hewan)
- **Bulu rontok:** Pakan tinggi omega-3 dan omega-6

## Yang Harus Dihindari

❌ Bawang putih/merah (toksik)\n❌ Coklat dan kafein\n❌ Tulang ayam (bisa melukai saluran cerna)\n❌ Susu sapi (kebanyakan kucing lactose intolerant)\n❌ Makanan manusia yang mengandung bumbu berlebih
    `.trim(),
  },
  {
    slug: "aksesoris-anjing-aktif",
    title: "5 Aksesoris Wajib untuk Anjing Peliharaan yang Aktif",
    excerpt: "Anjing aktif butuh perlengkapan yang tepat agar tetap aman, nyaman, dan bahagia saat bermain maupun berolahraga bersama kamu.",
    tag: "Anjing",
    emoji: "🐶",
    date: "22 Apr 2026",
    readTime: "4 menit",
    content: `
## Anjing Aktif = Pemilik yang Aktif

Memiliki anjing aktif seperti Golden Retriever, Labrador, atau Border Collie berarti kamu juga harus siap aktif bergerak bersama mereka. Aksesoris yang tepat akan membuat aktivitas lebih aman dan menyenangkan.

## 1. Harness Ergonomis

Lebih aman dari kalung untuk anjing yang suka tarik-menarik. Pilih harness:

- Berbahan breathable dan tidak gesekan
- Dengan reflective strip untuk keamanan malam hari
- Ukuran yang bisa disesuaikan
- **Rekomendasi:** Ruffwear Front Range, Julius K9

## 2. Tali Retractable Berkualitas

Tali retractable memberi kebebasan bergerak tapi tetap terkontrol:

- Pilih panjang 5–8 meter
- Pastikan ada tombol lock yang responsif
- Sesuaikan kekuatan tali dengan berat anjing
- **Catatan:** Hindari penggunaan di jalanan ramai

## 3. Tas Carrier atau Ransel Anjing

Untuk anjing kecil yang sering diajak pergi:

- Pastikan ventilasi cukup
- Ada tempat untuk air minum
- Desain ergonomis agar tidak pegal di punggung

## 4. Mainan Tahan Lama

Anjing aktif butuh stimulasi mental dan fisik:

- **Kong Classic** — bisa diisi camilan, bikin ketagihan
- **Bola rubber** untuk main lempar tangkap
- **Tali tambang** untuk tug-of-war
- Hindari mainan dengan bagian kecil yang bisa tertelan

## 5. Botol Minum Portable

Anjing aktif cepat dehidrasi. Selalu bawa:

- Botol dengan wadah minum terintegrasi
- Kapasitas minimal 500ml
- Material food-grade, BPA-free
- **Rekomendasi:** Dexas MudBuster, H2O4K9

## Bonus: GPS Tracker

Untuk anjing yang suka kabur — pasang GPS tracker di harness/kalung. Beberapa pilihan: Tractive GPS, Pawfit.

> **Ingat:** Aksesoris terbaik tidak menggantikan waktu bermain dan perhatian dari kamu sebagai pemilik. Luangkan minimal 30 menit sehari untuk olahraga aktif bersama anjingmu.
    `.trim(),
  },
];

export function getBlogPost(slug: string): BlogPost | null {
  return BLOG_POSTS.find((p) => p.slug === slug) ?? null;
}
