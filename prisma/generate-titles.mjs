// Script: Generate judul produk yang rapi menggunakan GPT
// Jalankan: node prisma/generate-titles.mjs
// (dari folder toko-pwa-starter)

import { readFileSync, writeFileSync } from 'fs';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

// Load .env.local
const envPath = join(__dirname, '../.env.local');
const envContent = readFileSync(envPath, 'utf-8');
const env = {};
for (const line of envContent.split('\n')) {
  const m = line.match(/^([A-Z_]+)=["']?(.+?)["']?\s*$/);
  if (m) env[m[1]] = m[2];
}
const OPENAI_API_KEY = env.OPENAI_API_KEY;
const OPENAI_MODEL = env.OPENAI_MODEL || 'gpt-4o-mini';

if (!OPENAI_API_KEY) {
  console.error('❌ OPENAI_API_KEY tidak ditemukan di .env.local');
  process.exit(1);
}

// Load products
const dataPath = join(__dirname, 'products_import.json');
const data = JSON.parse(readFileSync(dataPath, 'utf-8'));
const products = data.products;

console.log(`📦 Total produk: ${products.length}`);
console.log(`🤖 Model: ${OPENAI_MODEL}\n`);

// Fungsi panggil GPT untuk satu batch
async function generateTitles(batch) {
  const prompt = batch.map((p, i) =>
    `${i + 1}. Brand: "${p.brand}" | Judul asli: "${p.original_name || p.name}"`
  ).join('\n');

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      temperature: 0.2,
      messages: [
        {
          role: 'system',
          content: `Kamu adalah spesialis copywriting produk pet shop Indonesia.
Tugasmu: ubah judul produk Shopee yang panjang dan berantakan menjadi judul yang rapi, profesional, dan menarik untuk website toko online.

ATURAN WAJIB:
1. Format: "[Brand] [Nama Produk] [Ukuran/Berat] - [Deskripsi singkat Bahasa Indonesia/Inggris]"
2. Brand WAJIB di awal judul
3. Ukuran/berat wajib ada jika tersedia (gunakan: g, kg, ml, L, pcs, Watt)
4. Deskripsi singkat setelah tanda " - " maksimal 4-5 kata yang paling relevan
5. Maksimal 70 karakter total
6. Hilangkan kata noise: FRESHPACK, ORIGINAL, GROSIR, SUPER PREMIUM (kecuali memang nama produk)
7. Hilangkan deskripsi panjang Indonesia seperti "Makanan Kucing Terbaik Berkualitas..."
8. Gunakan bahasa campuran (Inggris/Indonesia) yang natural seperti produk aslinya
9. Perbaiki typo yang jelas (contoh: "Mulitivitamin" → "Multivitamin")
10. Jangan ubah nama brand atau nama produk inti

CONTOH:
Input:  Brand: "Royal Canin" | "Royal Canin Kitten Cat Food 2KG - Makanan Anak Kucing Super Premium Freshpack 2 KG"
Output: Royal Canin Kitten 2kg - Makanan Anak Kucing

Input:  Brand: "Angels" | "Angels Mulitivitamin Gel 20GR - Penambah Nafsu Makan - Penggemuk Badan Hewan Kucing"
Output: Angels Multivitamin Gel 20g - Penambah Nafsu Makan

Input:  Brand: "JerHigh" | "JerHigh Pouch in Gravy 120GR - Wet Dog Food / Makanan Basah Anjing"
Output: JerHigh Pouch in Gravy 120g - Wet Dog Food

Input:  Brand: "Bravery" | "Bravery Medium/Large Puppy SALMON 4KG Makanan Anak Anjing Super Premium Pelet"
Output: Bravery Medium/Large Puppy Salmon 4kg - Dog Food

Balas HANYA dengan daftar bernomor. Contoh format balasan:
1. Royal Canin Kitten 2kg - Makanan Anak Kucing
2. Angels Multivitamin Gel 20g - Penambah Nafsu Makan`
        },
        {
          role: 'user',
          content: `Buat judul baru untuk ${batch.length} produk berikut:\n\n${prompt}`
        }
      ]
    })
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`OpenAI error ${response.status}: ${err}`);
  }

  const json = await response.json();
  const text = json.choices[0].message.content;

  // Parse output bernomor
  const lines = text.split('\n').filter(l => /^\d+\./.test(l.trim()));
  return lines.map(l => l.replace(/^\d+\.\s*/, '').trim());
}

// Proses semua produk dalam batch
const BATCH_SIZE = 30;
const DELAY_MS = 1000; // delay antar batch (hindari rate limit)

let updated = 0;
let failed = 0;

console.log(`⚙️  Memproses dalam batch ${BATCH_SIZE} produk...\n`);

for (let i = 0; i < products.length; i += BATCH_SIZE) {
  const batch = products.slice(i, i + BATCH_SIZE);
  const batchNum = Math.floor(i / BATCH_SIZE) + 1;
  const totalBatches = Math.ceil(products.length / BATCH_SIZE);

  process.stdout.write(`Batch ${batchNum}/${totalBatches} (produk ${i+1}-${Math.min(i+BATCH_SIZE, products.length)})... `);

  try {
    const titles = await generateTitles(batch);

    for (let j = 0; j < batch.length; j++) {
      if (titles[j] && titles[j].length > 5) {
        const old = batch[j].name;
        products[i + j].original_name = products[i + j].original_name || old;
        products[i + j].name = titles[j];
        updated++;
      } else {
        failed++;
      }
    }

    console.log(`✅ (${titles.length} judul)`);
  } catch (err) {
    console.log(`❌ GAGAL: ${err.message.slice(0, 60)}`);
    failed += batch.length;
  }

  // Simpan progress setiap 5 batch
  if (batchNum % 5 === 0) {
    data.products = products;
    writeFileSync(dataPath, JSON.stringify(data, null, 2), 'utf-8');
    console.log(`  💾 Progress disimpan (${updated} produk diperbarui)\n`);
  }

  // Delay antar batch
  if (i + BATCH_SIZE < products.length) {
    await new Promise(r => setTimeout(r, DELAY_MS));
  }
}

// Simpan hasil akhir
data.products = products;
writeFileSync(dataPath, JSON.stringify(data, null, 2), 'utf-8');

console.log(`\n✅ SELESAI!`);
console.log(`   Judul diperbarui : ${updated}`);
console.log(`   Gagal/skip       : ${failed}`);
console.log(`\n📁 Hasil disimpan di: prisma/products_import.json`);
console.log(`\nLangkah selanjutnya: jalankan IMPORT-PRODUK.bat untuk memasukkan ke database`);
