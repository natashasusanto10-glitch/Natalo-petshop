import { config } from "dotenv";

config({ path: ".env.production.local" });
if (!process.env.BUNNY_API_KEY) config({ path: ".env.local" });

const apiKey = process.env.BUNNY_API_KEY;
const libraryId = process.env.BUNNY_LIBRARY_ID;
const siteUrl = "https://www.natalopetshop.com";

if (!apiKey || !libraryId) {
  console.error("BUNNY_API_KEY / BUNNY_LIBRARY_ID belum di-set.");
  process.exit(1);
}

// 1. Ambil semua video Finished di Bunny.
const listRes = await fetch(
  `https://video.bunnycdn.com/library/${libraryId}/videos?page=1&itemsPerPage=20&orderBy=date`,
  { headers: { AccessKey: apiKey, accept: "application/json" } },
);
const listData = await listRes.json();
const finished = (listData.items ?? []).filter((v) => v.status === 4);

console.log(`Found ${finished.length} video Finished di Bunny.\n`);

// 2. Cek state DB via /api/feed/diag (public read-only).
const diagRes = await fetch(`${siteUrl}/api/feed/diag`);
const diag = await diagRes.json();
const dbGuids = new Map(
  (diag.recent ?? []).map((p) => [p.videoGuidSuffix, p]),
);

console.log("DB state (10 terakhir):");
for (const p of diag.recent ?? []) {
  console.log(
    `  ${p.id.slice(-12)} · status=${p.status} · encoding=${p.encodingStatus} · guid=…${p.videoGuidSuffix} · urlKind=${p.videoUrlKind} · thumb=${p.hasThumb}`,
  );
}

// 3. Untuk tiap Bunny video Finished yang DB-nya belum ready, fire webhook.
console.log("\n=== Simulasi webhook Bunny FINISHED ===\n");
for (const v of finished) {
  const guidSuffix = v.guid.slice(-8);
  const dbPost = dbGuids.get(guidSuffix);
  if (!dbPost) {
    console.log(`  …${guidSuffix} · skip (tidak ada DB row dengan guid ini)`);
    continue;
  }
  if (dbPost.encodingStatus === "ready") {
    console.log(`  …${guidSuffix} · skip (DB sudah ready)`);
    continue;
  }
  // Webhook auth = BUNNY_WEBHOOK_SECRET (kalau set). Coba dengan dan tanpa
  // Bearer; kalau secret tidak di-set di server, accept-anything path
  // berlaku.
  const webhookRes = await fetch(`${siteUrl}/api/feed/bunny/webhook`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      VideoLibraryId: Number(libraryId),
      VideoGuid: v.guid,
      Status: 4,
    }),
  });
  const result = await webhookRes.json().catch(() => ({}));
  console.log(
    `  …${guidSuffix} · POST webhook → ${webhookRes.status} · ${JSON.stringify(result)}`,
  );
}

// 4. Re-check DB state.
console.log("\n=== State DB setelah webhook ===\n");
const diag2 = await (await fetch(`${siteUrl}/api/feed/diag`)).json();
for (const p of diag2.recent ?? []) {
  console.log(
    `  ${p.id.slice(-12)} · status=${p.status} · encoding=${p.encodingStatus} · urlKind=${p.videoUrlKind} · thumb=${p.hasThumb}`,
  );
}
