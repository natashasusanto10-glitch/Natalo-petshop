import { config } from "dotenv";

// DATABASE_URL ada di .env.production.local (Vercel pull). Load itu duluan.
config({ path: ".env.production.local" });
if (!process.env.DATABASE_URL) config({ path: ".env.local" });
if (!process.env.DATABASE_URL) config(); // last resort: .env

const { PrismaClient } = await import("@prisma/client");

const prisma = new PrismaClient();

const recent = await prisma.feedPost.findMany({
  orderBy: { createdAt: "desc" },
  take: 10,
  select: {
    id: true,
    title: true,
    status: true,
    encodingStatus: true,
    videoGuid: true,
    videoUrl: true,
    thumbnailUrl: true,
    videoDurationSec: true,
    tab: true,
    kind: true,
    authorRole: true,
    deletedAt: true,
    moderationNote: true,
    publishedAt: true,
    moderatedAt: true,
    createdAt: true,
  },
});

const summary = recent.map((p) => ({
  id: p.id.slice(-12),
  title: p.title.slice(0, 40),
  status: p.status,
  encodingStatus: p.encodingStatus,
  hasVideoUrl: Boolean(p.videoUrl),
  hasThumb: Boolean(p.thumbnailUrl),
  hasGuid: Boolean(p.videoGuid),
  guidSuffix: p.videoGuid?.slice(-8) ?? null,
  durSec: p.videoDurationSec,
  tab: p.tab,
  kind: p.kind,
  role: p.authorRole,
  deleted: Boolean(p.deletedAt),
  note: p.moderationNote?.slice(0, 60) ?? null,
  published: p.publishedAt?.toISOString() ?? null,
  moderated: p.moderatedAt?.toISOString() ?? null,
  created: p.createdAt.toISOString(),
}));

console.log(JSON.stringify(summary, null, 2));

// Highlight kalau ada yang "approved tapi tidak akan muncul di feed"
const orphanApproved = recent.filter(
  (p) =>
    p.status === "ACTIVE" &&
    !p.deletedAt &&
    (p.encodingStatus !== "ready" || !p.videoUrl || !p.thumbnailUrl),
);
if (orphanApproved.length > 0) {
  console.log("\n⚠️  Post ACTIVE tapi excluded dari feed query:");
  for (const p of orphanApproved) {
    console.log(
      `  - ${p.id.slice(-12)} | encoding=${p.encodingStatus} | videoUrl=${
        p.videoUrl ? "yes" : "NULL"
      } | thumb=${p.thumbnailUrl ? "yes" : "NULL"} | guid=${p.videoGuid?.slice(-8) ?? "NULL"}`,
    );
  }
}

await prisma.$disconnect();
