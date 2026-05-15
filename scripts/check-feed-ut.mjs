import "dotenv/config";
import { UTApi } from "uploadthing/server";

const u = new UTApi();
const page = await u.listFiles({ limit: 50 });
const items = page.files || [];
const feedFiles = items
  .filter((f) => f.name && (f.name.startsWith("feed-video-") || f.name.startsWith("feed-thumb-")))
  .sort((a, b) => (b.uploadedAt || 0) - (a.uploadedAt || 0));

const summary = {
  totalInUploadThing: items.length,
  feedFiles: feedFiles.length,
  latestFive: feedFiles.slice(0, 5).map((f) => ({
    name: f.name,
    size: f.size,
    key: f.key,
    uploadedAt: f.uploadedAt ? new Date(f.uploadedAt).toISOString() : null,
  })),
};

process.stdout.write(JSON.stringify(summary, null, 2) + "\n");
