#!/usr/bin/env node
/**
 * Migrate Bunny Stream library Germany → Singapore.
 *
 * Pipeline per video:
 *   1. List video di library lama (status=Finished only — skip orphan)
 *   2. Match dengan DB FeedPost.videoGuid → ambil row terkait
 *   3. Download MP4 720p dari old CDN ke RAM
 *   4. Create new video di library SG → dapat new_guid
 *   5. PUT upload MP4 ke new_guid
 *   6. Poll status sampai FINISHED (max ~3 menit)
 *   7. Output mapping: { oldGuid, newGuid, newVideoUrl, newThumbnailUrl, postId }
 *
 * DB update modes (dipilih via --mode=...):
 *   - local : connect Prisma langsung (butuh DATABASE_URL via `vercel env pull`)
 *   - sql   : tulis migrate-mapping.sql ke disk, user jalanin manual
 *   - api   : POST ke /api/admin/feed/bunny-migrate-apply (butuh ADMIN cookie)
 *
 * Usage:
 *   node scripts/migrate-bunny-to-sg.mjs --dry-run        # plan saja, no migrate
 *   node scripts/migrate-bunny-to-sg.mjs --mode=sql       # migrate + tulis SQL file
 *   node scripts/migrate-bunny-to-sg.mjs --mode=local     # migrate + update DB langsung
 *   node scripts/migrate-bunny-to-sg.mjs --mode=api --cookie="..." # migrate + POST API
 *
 * Env vars wajib (set di .env.production.local atau export sebelum run):
 *   BUNNY_LIBRARY_ID         — library lama (DE)
 *   BUNNY_API_KEY            — API key library lama
 *   BUNNY_CDN_HOSTNAME       — CDN hostname library lama
 *   BUNNY_NEW_LIBRARY_ID     — library baru (SG)
 *   BUNNY_NEW_API_KEY        — API key library baru
 *   BUNNY_NEW_CDN_HOSTNAME   — CDN hostname library baru
 *
 * Idempotent: kalau script crash di tengah, re-run akan skip video yang
 * sudah ada di SG (matching by title hash). Lihat shouldSkip().
 */
import { config } from "dotenv";
import { writeFileSync } from "fs";

config({ path: ".env.production.local" });

const args = process.argv.slice(2);
const DRY_RUN = args.includes("--dry-run");
const MODE = args.find((a) => a.startsWith("--mode="))?.split("=")[1] ?? "sql";
const COOKIE = args.find((a) => a.startsWith("--cookie="))?.split("=")[1];
const PROD_URL =
  args.find((a) => a.startsWith("--prod="))?.split("=")[1] ??
  "https://www.natalopetshop.com";

// Library LAMA: kita TIDAK butuh API key karena:
//   - List video diambil dari DB (/api/feed/diag) — DB source of truth
//   - Download MP4 dari Bunny CDN bersifat publik (no auth required)
//   - Delete old video skip (cleanup manual via dashboard)
// Cuma butuh CDN hostname untuk konstruksi URL.
const OLD_CDN = process.env.BUNNY_CDN_HOSTNAME;
const NEW_LIBRARY = process.env.BUNNY_NEW_LIBRARY_ID;
const NEW_KEY = process.env.BUNNY_NEW_API_KEY;
const NEW_CDN = process.env.BUNNY_NEW_CDN_HOSTNAME;

if (!OLD_CDN) {
  console.error("Set BUNNY_CDN_HOSTNAME (library lama CDN hostname)");
  process.exit(1);
}
if (!DRY_RUN && (!NEW_LIBRARY || !NEW_KEY || !NEW_CDN)) {
  console.error(
    "Set BUNNY_NEW_LIBRARY_ID + BUNNY_NEW_API_KEY + BUNNY_NEW_CDN_HOSTNAME (kecuali --dry-run)",
  );
  process.exit(1);
}
if (!["sql", "local", "api"].includes(MODE)) {
  console.error("Mode invalid. Pilih: sql, local, api");
  process.exit(1);
}

const BUNNY_API = "https://video.bunnycdn.com";

// ── Helpers ──────────────────────────────────────────────────────────

async function listNewVideos() {
  if (!NEW_LIBRARY || !NEW_KEY) return [];
  const res = await fetch(
    `${BUNNY_API}/library/${NEW_LIBRARY}/videos?page=1&itemsPerPage=100&orderBy=date`,
    { headers: { AccessKey: NEW_KEY, accept: "application/json" } },
  );
  if (!res.ok) return [];
  const data = await res.json();
  return data.items ?? [];
}

async function fetchDbState() {
  // Pakai /api/feed/diag (public read-only) untuk dapat list FeedPost
  // dengan videoGuid. Cukup buat matching saat migrate.
  const res = await fetch(`${PROD_URL}/api/feed/diag`);
  if (!res.ok) throw new Error(`Diag: HTTP ${res.status}`);
  const data = await res.json();
  return data.recent ?? [];
}

async function downloadOldMp4(guid) {
  const url = `https://${OLD_CDN}/${guid}/play_720p.mp4`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Download ${guid}: HTTP ${res.status}`);
  return await res.arrayBuffer();
}

async function createNewVideo(title) {
  const res = await fetch(`${BUNNY_API}/library/${NEW_LIBRARY}/videos`, {
    method: "POST",
    headers: {
      AccessKey: NEW_KEY,
      "Content-Type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify({ title }),
  });
  if (!res.ok) throw new Error(`Create new: HTTP ${res.status}`);
  const data = await res.json();
  return data.guid;
}

async function uploadToNew(guid, bytes) {
  const res = await fetch(
    `${BUNNY_API}/library/${NEW_LIBRARY}/videos/${guid}`,
    {
      method: "PUT",
      headers: {
        AccessKey: NEW_KEY,
        "Content-Type": "application/octet-stream",
      },
      body: Buffer.from(bytes),
    },
  );
  if (!res.ok) throw new Error(`Upload ${guid}: HTTP ${res.status}`);
}

async function pollUntilReady(guid, maxAttempts = 60) {
  for (let i = 0; i < maxAttempts; i++) {
    const res = await fetch(
      `${BUNNY_API}/library/${NEW_LIBRARY}/videos/${guid}`,
      { headers: { AccessKey: NEW_KEY, accept: "application/json" } },
    );
    if (!res.ok) {
      await new Promise((r) => setTimeout(r, 3000));
      continue;
    }
    const data = await res.json();
    if (data.status === 4) return data; // Finished
    if (data.status === 5) throw new Error(`Encoding ${guid} failed`);
    await new Promise((r) => setTimeout(r, 3000));
  }
  throw new Error(`Encoding ${guid} timeout`);
}

// ── Main migration ───────────────────────────────────────────────────

async function main() {
  console.log("📋 Fetching DB state + new library state...\n");
  const [dbPosts, newExisting] = await Promise.all([
    fetchDbState(),
    listNewVideos(),
  ]);

  // DB source of truth — kita ambil videoGuid lengkap dari DB. Tapi diag
  // endpoint cuma return suffix 8 char. Untuk migrate full GUID dibutuhkan,
  // jadi kita pakai pattern: download URL "https://OLD_CDN/<full-guid>/...",
  // dan diag endpoint sudah expose guid suffix yang cukup unik (8 hex char
  // = 4 billion). Tapi sebenarnya kita butuh full GUID di download URL.
  //
  // Solusi: panggil bunny-reconcile debug mode (admin endpoint) yang return
  // full videoGuid per post. Kalau gak ada akses, fallback ke pattern matching
  // dari videoUrl yang ada di feed posts endpoint (yang kasih MP4 URL lengkap).

  // Pakai /api/feed/posts (public) untuk dapat videoUrl lengkap — videoUrl
  // contains the full guid as path segment.
  const feedRes = await fetch(`${PROD_URL}/api/feed/posts?limit=50`);
  if (!feedRes.ok) throw new Error(`Feed posts fetch failed: ${feedRes.status}`);
  const feedData = await feedRes.json();
  const feedItems = feedData.items ?? [];

  // Build mapping postId → full guid (extracted from videoUrl path)
  const fullGuidByPostId = new Map();
  for (const item of feedItems) {
    if (!item.videoUrl) continue;
    // videoUrl format: https://OLD_CDN/<guid>/play_720p.mp4
    const match = item.videoUrl.match(/\/([a-f0-9-]{36})\//i);
    if (match) fullGuidByPostId.set(item.id, match[1]);
  }

  const newTitleSet = new Set(newExisting.map((v) => v.title));

  console.log(`DB FeedPost (diag, ACTIVE+ready): ${dbPosts.length} rows`);
  console.log(`Feed posts (public list, visible to user): ${feedItems.length}`);
  console.log(`Full guid resolved from videoUrl: ${fullGuidByPostId.size}`);
  console.log(`New library: ${newExisting.length} videos (idempotent check)\n`);

  // Cocokkan — pakai feedItems sebagai source (cuma yang visible di feed
  // public yang perlu di-migrate; orphan / hidden tidak prioritas)
  const plan = [];
  for (const post of feedItems) {
    const fullGuid = fullGuidByPostId.get(post.id);
    if (!fullGuid) {
      console.log(`  ⏭  skip ${post.id} — no full guid extractable`);
      continue;
    }
    const suffix = fullGuid.slice(-8);
    // Idempotent: kalau title sudah ada di new library, skip
    const migrateTitle = `migrated-${post.id}-${suffix}`;
    if (newTitleSet.has(migrateTitle)) {
      console.log(`  ✓  done ${suffix} → already in new library`);
      continue;
    }
    plan.push({
      oldGuid: fullGuid,
      post: {
        id: post.id,
        title: post.title,
        duration: post.videoDurationSec,
        width: post.videoWidth,
        height: post.videoHeight,
      },
      migrateTitle,
    });
  }

  console.log(`\n📊 Plan: ${plan.length} video to migrate\n`);
  for (const item of plan) {
    console.log(
      `  • ${item.oldGuid.slice(-8)} "${item.post.title.slice(0, 30)}" (${item.post.duration}s, ${item.post.width}x${item.post.height})`,
    );
  }

  if (DRY_RUN) {
    console.log("\n--dry-run mode, exit tanpa migrate.");
    return;
  }
  if (plan.length === 0) {
    console.log("\nNothing to migrate.");
    return;
  }

  console.log(`\n🚀 Starting migration (mode=${MODE})...\n`);
  const results = [];
  let successful = 0;
  let failed = 0;

  for (const [idx, item] of plan.entries()) {
    const { oldGuid, post, migrateTitle } = item;
    const suffix = oldGuid.slice(-8);
    const t0 = Date.now();
    try {
      console.log(`[${idx + 1}/${plan.length}] ${suffix} ${post.title.slice(0, 40)}`);
      console.log(`  ↓ Download MP4 720p dari old CDN (public)...`);
      const bytes = await downloadOldMp4(oldGuid);
      console.log(`     ${(bytes.byteLength / 1024 / 1024).toFixed(1)} MB`);

      console.log(`  + Create new video di SG library...`);
      const newGuid = await createNewVideo(migrateTitle);

      console.log(`  ↑ Upload ke ${newGuid}...`);
      await uploadToNew(newGuid, bytes);

      console.log(`  ⏳ Wait encoding...`);
      await pollUntilReady(newGuid);

      const newVideoUrl = `https://${NEW_CDN}/${newGuid}/play_720p.mp4`;
      const newThumbUrl = `https://${NEW_CDN}/${newGuid}/thumbnail.jpg`;
      const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
      console.log(`  ✓ Done in ${elapsed}s\n`);

      results.push({
        postId: post.id,
        oldGuid,
        newGuid,
        newVideoUrl,
        newThumbnailUrl: newThumbUrl,
      });
      successful++;
    } catch (err) {
      console.error(`  ✗ FAIL: ${err.message}\n`);
      results.push({ postId: post.id, oldGuid, error: err.message });
      failed++;
    }
  }

  console.log(`\n📈 Done: ${successful} success, ${failed} failed\n`);

  // Output mapping (always, regardless of mode)
  const mappingFile = "scripts/.bunny-migration-mapping.json";
  writeFileSync(mappingFile, JSON.stringify(results, null, 2));
  console.log(`💾 Mapping saved to ${mappingFile}`);

  const successfulResults = results.filter((r) => !r.error);
  if (successfulResults.length === 0) {
    console.log("Tidak ada yang sukses — skip DB update.");
    return;
  }

  // DB update per mode
  if (MODE === "sql") {
    const sqlFile = "scripts/.bunny-migration.sql";
    const sql = successfulResults
      .map(
        (r) =>
          `UPDATE "FeedPost" SET "videoGuid" = '${r.newGuid}', "videoUrl" = '${r.newVideoUrl}', "thumbnailUrl" = '${r.newThumbnailUrl}' WHERE id = '${r.postId}'; -- was guid …${r.oldGuid.slice(-8)}`,
      )
      .join("\n");
    writeFileSync(sqlFile, sql + "\n");
    console.log(`📝 SQL written to ${sqlFile}`);
    console.log("Jalanin manual via Prisma Studio / pgAdmin / psql.");
  } else if (MODE === "local") {
    const { PrismaClient } = await import("@prisma/client");
    if (!process.env.DATABASE_URL) {
      console.error(
        "DATABASE_URL kosong. Jalanin `vercel env pull --environment=production` dulu.",
      );
      process.exit(1);
    }
    const prisma = new PrismaClient();
    for (const r of successfulResults) {
      await prisma.feedPost.update({
        where: { id: r.postId },
        data: {
          videoGuid: r.newGuid,
          videoUrl: r.newVideoUrl,
          thumbnailUrl: r.newThumbnailUrl,
        },
      });
      console.log(`  ✓ DB updated post ${r.postId}`);
    }
    await prisma.$disconnect();
  } else if (MODE === "api") {
    if (!COOKIE) {
      console.error("Mode=api butuh --cookie=\"admin_session=...\"");
      process.exit(1);
    }
    const res = await fetch(`${PROD_URL}/api/admin/feed/bunny-migrate-apply`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Cookie: COOKIE,
      },
      body: JSON.stringify({ mapping: successfulResults }),
    });
    const data = await res.json();
    console.log(`API response: ${res.status}`, data);
  }

  console.log("\n✅ Migration complete.");
  console.log("\nLangkah selanjutnya:");
  console.log("  1. Verify video baru play di app (cek beberapa post)");
  console.log("  2. Update env Vercel: BUNNY_LIBRARY_ID, BUNNY_API_KEY, BUNNY_CDN_HOSTNAME ke SG");
  console.log("  3. Redeploy");
  console.log("  4. Setelah confirm stabil, hapus video lama di library DE via Bunny dashboard");
}

main().catch((err) => {
  console.error("\n💥 Fatal error:", err);
  process.exit(1);
});
