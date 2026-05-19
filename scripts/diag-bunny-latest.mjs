import { config } from "dotenv";

config({ path: ".env.production.local" });
if (!process.env.BUNNY_API_KEY) config({ path: ".env.local" });

const apiKey = process.env.BUNNY_API_KEY;
const libraryId = process.env.BUNNY_LIBRARY_ID;
const cdnHost = process.env.BUNNY_CDN_HOSTNAME;

if (!apiKey || !libraryId) {
  console.error("BUNNY_API_KEY / BUNNY_LIBRARY_ID belum di-set.");
  process.exit(1);
}

// Bunny status codes (https://docs.bunny.net/reference/video_list)
const STATUS_NAMES = {
  0: "Created",
  1: "Uploaded",
  2: "Processing",
  3: "Transcoding",
  4: "Finished",
  5: "Error",
  6: "UploadFailed",
  7: "JitSegmenting",
  8: "JitPlaylistsCreated",
};

const url = `https://video.bunnycdn.com/library/${libraryId}/videos?page=1&itemsPerPage=15&orderBy=date`;
const res = await fetch(url, {
  headers: { AccessKey: apiKey, accept: "application/json" },
});
if (!res.ok) {
  console.error(`Bunny API ${res.status}: ${await res.text()}`);
  process.exit(1);
}
const data = await res.json();
const items = (data.items ?? []).map((v) => ({
  guid: v.guid,
  guidSuffix: v.guid?.slice(-8),
  title: v.title,
  status: v.status,
  statusName: STATUS_NAMES[v.status] ?? `unknown(${v.status})`,
  length: v.length,
  width: v.width,
  height: v.height,
  storageSize: v.storageSize,
  created: v.dateUploaded,
  thumbnail: cdnHost
    ? `https://${cdnHost}/${v.guid}/thumbnail.jpg`
    : null,
  mp4: cdnHost
    ? `https://${cdnHost}/${v.guid}/play_720p.mp4`
    : null,
}));

console.log(`Total videos: ${data.totalItems ?? items.length}`);
console.log(`Showing ${items.length} terbaru:\n`);
for (const v of items) {
  console.log(
    `  [${v.statusName.padEnd(13)}] ${v.length ?? "?"}s ${v.width ?? "?"}x${v.height ?? "?"} · "${(v.title ?? "").slice(0, 40)}" · guid=…${v.guidSuffix} · uploaded ${v.created}`,
  );
}

const finished = items.filter((v) => v.status === 4);
const stuck = items.filter((v) => v.status >= 2 && v.status <= 3);
const failed = items.filter((v) => v.status === 5 || v.status === 6);
console.log(`\nSummary: ${finished.length} finished · ${stuck.length} processing · ${failed.length} failed`);
