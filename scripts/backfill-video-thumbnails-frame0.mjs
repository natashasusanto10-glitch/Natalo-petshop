#!/usr/bin/env node
/**
 * Backfill: regenerate thumbnail Bunny video LAMA dari frame pertama
 * (detik 0), supaya konsisten dengan video baru (yang sudah pakai
 * `thumbnailTime: 0` sejak lib/feed/bunny.ts createBunnyVideo()).
 *
 * Kenapa perlu script terpisah (bukan cukup update env/config):
 * Bunny Stream "Update Video" API TIDAK punya field `thumbnailTime` —
 * itu cuma bisa di-set saat "Create Video". Untuk video yang sudah ada,
 * satu-satunya cara adalah generate gambar frame-0 sendiri lalu push
 * manual via "Set Thumbnail" API (POST .../videos/{guid}/thumbnail,
 * body biner JPEG).
 *
 * Pipeline per video:
 *   1. Query FeedPost (encodingStatus=ready, videoGuid != null) dari DB.
 *   2. Download MP4 480p dari Bunny CDN (kecil, cukup untuk 1 frame).
 *   3. ffmpeg (system binary, PATH) extract frame pertama → JPEG buffer.
 *   4. POST JPEG itu ke Bunny "Set Thumbnail" (mengganti thumbnail.jpg).
 *   5. Re-encode blurhash dari JPEG baru (sharp+blurhash, sama seperti
 *      lib/feed/blurhash.ts) → update FeedPost.thumbnailBlurhash.
 *
 * thumbnailUrl DB TIDAK berubah (URL-nya tetap sama, cuma isi file di
 * Bunny yang diganti) — jadi tidak perlu migrasi field lain.
 *
 * PRASYARAT: ffmpeg harus ada di PATH (`ffmpeg -version` harus jalan).
 * Ini script lokal, BUKAN untuk dijalankan sebagai Vercel function.
 *
 * Cache note: Bunny CDN edge cache thumbnail.jpg lama beberapa saat
 * (pull-zone TTL). Thumbnail baru propagate ke semua edge POP setelah
 * TTL habis / on next miss — bukan instan di semua region.
 *
 * Usage:
 *   node scripts/backfill-video-thumbnails-frame0.mjs --dry-run
 *   node scripts/backfill-video-thumbnails-frame0.mjs
 *   node scripts/backfill-video-thumbnails-frame0.mjs --limit=5
 *   node scripts/backfill-video-thumbnails-frame0.mjs --delay=1500
 *
 * Env (dari .env.production.local, sama seperti script Bunny lain):
 *   DATABASE_URL, BUNNY_LIBRARY_ID, BUNNY_API_KEY, BUNNY_CDN_HOSTNAME
 *   BUNNY_TOKEN_SECURITY_KEY (opsional, kalau CDN token-auth aktif)
 */
import { config } from "dotenv";
import { spawn } from "node:child_process";
import crypto from "node:crypto";

config({ path: ".env.production.local" });
if (!process.env.BUNNY_API_KEY) config({ path: ".env.local" });

const args = process.argv.slice(2);
const DRY_RUN = args.includes("--dry-run");
const LIMIT = Number(args.find((a) => a.startsWith("--limit="))?.split("=")[1] ?? Infinity);
const DELAY_MS = Number(args.find((a) => a.startsWith("--delay="))?.split("=")[1] ?? 800);

const BUNNY_API = "https://video.bunnycdn.com";
const libraryId = process.env.BUNNY_LIBRARY_ID;
const apiKey = process.env.BUNNY_API_KEY;
const cdnHost = process.env.BUNNY_CDN_HOSTNAME;
const tokenKey = process.env.BUNNY_TOKEN_SECURITY_KEY;

if (!libraryId || !apiKey || !cdnHost) {
  console.error("Set BUNNY_LIBRARY_ID, BUNNY_API_KEY, BUNNY_CDN_HOSTNAME dulu.");
  process.exit(1);
}
if (!DRY_RUN && !process.env.DATABASE_URL) {
  console.error("DATABASE_URL kosong. Jalanin `vercel env pull --environment=production` dulu.");
  process.exit(1);
}

// ── ffmpeg availability check ───────────────────────────────────────
function checkFfmpeg() {
  return new Promise((resolve) => {
    const p = spawn("ffmpeg", ["-version"]);
    p.on("error", () => resolve(false));
    p.on("exit", (code) => resolve(code === 0));
  });
}

// Minimal reimplementation of signBunnyUrl() untuk MP4 (non-HLS) path —
// lihat lib/feed/bunny.ts untuk versi lengkap/HLS. Cuma dibutuhkan kalau
// CDN token authentication aktif.
function signMp4Url(url) {
  if (!tokenKey) return url;
  const parsed = new URL(url);
  if (parsed.hostname !== cdnHost) return url;
  const expires = Math.floor(Date.now() / 1000) + 6 * 60 * 60;
  const hashInput = `${tokenKey}${parsed.pathname}${expires}`;
  const token = crypto
    .createHash("sha256")
    .update(hashInput)
    .digest("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
  parsed.searchParams.set("token", token);
  parsed.searchParams.set("expires", String(expires));
  return parsed.toString();
}

async function downloadMp4(guid) {
  const url = signMp4Url(`https://${cdnHost}/${guid}/play_480p.mp4`);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`download MP4: HTTP ${res.status}`);
  return Buffer.from(await res.arrayBuffer());
}

/** Extract frame pertama via ffmpeg (stdin → stdout pipe, no temp file). */
function extractFirstFrame(mp4Buffer) {
  return new Promise((resolve, reject) => {
    const ffmpeg = spawn("ffmpeg", [
      "-i", "pipe:0",
      "-frames:v", "1",
      "-q:v", "2",
      "-f", "image2",
      "pipe:1",
    ]);
    const chunks = [];
    let stderr = "";
    ffmpeg.stdout.on("data", (d) => chunks.push(d));
    ffmpeg.stderr.on("data", (d) => (stderr += d.toString()));
    ffmpeg.on("error", reject);
    ffmpeg.on("exit", (code) => {
      if (code !== 0 || chunks.length === 0) {
        reject(new Error(`ffmpeg exit ${code}: ${stderr.slice(-500)}`));
        return;
      }
      resolve(Buffer.concat(chunks));
    });
    ffmpeg.stdin.write(mp4Buffer);
    ffmpeg.stdin.end();
  });
}

async function setThumbnail(guid, jpegBuffer) {
  const res = await fetch(
    `${BUNNY_API}/library/${libraryId}/videos/${guid}/thumbnail`,
    {
      method: "POST",
      headers: {
        AccessKey: apiKey,
        "Content-Type": "application/octet-stream",
      },
      body: jpegBuffer,
    },
  );
  if (!res.ok) throw new Error(`setThumbnail: HTTP ${res.status} ${await res.text().catch(() => "")}`);
}

async function computeBlurhash(jpegBuffer) {
  const { encode } = await import("blurhash");
  const sharp = (await import("sharp")).default;
  const { data, info } = await sharp(jpegBuffer)
    .resize(32, 32, { fit: "cover" })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  return encode(new Uint8ClampedArray(data), info.width, info.height, 4, 3);
}

async function main() {
  const hasFfmpeg = await checkFfmpeg();
  if (!hasFfmpeg) {
    console.error(
      "ffmpeg tidak ditemukan di PATH. Install dulu (mis. `winget install ffmpeg` / `choco install ffmpeg` / download dari ffmpeg.org) lalu coba lagi.",
    );
    process.exit(1);
  }

  const { PrismaClient } = await import("@prisma/client");
  const prisma = new PrismaClient();

  const posts = await prisma.feedPost.findMany({
    where: { encodingStatus: "ready", videoGuid: { not: null } },
    select: { id: true, videoGuid: true, title: true },
    orderBy: { createdAt: "desc" },
    take: Number.isFinite(LIMIT) ? LIMIT : undefined,
  });

  console.log(`📋 ${posts.length} video ditemukan (encodingStatus=ready).\n`);
  if (DRY_RUN) {
    for (const p of posts) {
      console.log(`  • ${p.id} guid=…${p.videoGuid.slice(-8)} "${(p.title ?? "").slice(0, 40)}"`);
    }
    console.log("\n--dry-run, tidak ada perubahan.");
    await prisma.$disconnect();
    return;
  }

  let ok = 0;
  let failed = 0;
  for (const [idx, post] of posts.entries()) {
    const suffix = post.videoGuid.slice(-8);
    process.stdout.write(`[${idx + 1}/${posts.length}] …${suffix} `);
    try {
      const mp4 = await downloadMp4(post.videoGuid);
      const frame = await extractFirstFrame(mp4);
      await setThumbnail(post.videoGuid, frame);
      const blurhash = await computeBlurhash(frame);
      await prisma.feedPost.update({
        where: { id: post.id },
        data: { thumbnailBlurhash: blurhash },
      });
      console.log("✓");
      ok++;
    } catch (err) {
      console.log(`✗ ${err.message}`);
      failed++;
    }
    if (DELAY_MS > 0 && idx < posts.length - 1) {
      await new Promise((r) => setTimeout(r, DELAY_MS));
    }
  }

  console.log(`\n📈 Selesai: ${ok} sukses, ${failed} gagal.`);
  await prisma.$disconnect();
}

main().catch((err) => {
  console.error("💥 Fatal:", err);
  process.exit(1);
});
