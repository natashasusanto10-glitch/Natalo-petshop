/**
 * Rehost gambar produk yang masih menunjuk CDN pihak ketiga (sisa impor
 * Shopee: cf.shopee.co.id, susercontent, dst) ke UploadThing.
 *
 * Kenapa: allowlist keamanan kartu OG share (lib/share/og-image-security.ts)
 * sengaja hanya mengizinkan host milik sendiri — produk ber-foto Shopee
 * selalu jatuh ke kartu fallback "N" di WhatsApp/iMessage. Plus risiko
 * katalog: host pihak ketiga bisa mati/ganti path kapan saja.
 *
 * Cakupan: Product.imageUrl, Product.gallery[], ProductVariant.imageUrl.
 *
 * Usage:
 *   npx tsx scripts/rehost-external-product-images.ts --dry-run   # laporan saja
 *   npx tsx scripts/rehost-external-product-images.ts             # rehost + update DB
 *
 * Resume-safe: URL yang sudah pindah ke UploadThing tidak cocok filter lagi.
 * Pakai DATABASE_URL + UPLOADTHING_TOKEN dari .env (= produksi).
 */
import { PrismaClient } from "@prisma/client";
import { UTApi } from "uploadthing/server";

const prisma = new PrismaClient();
const utapi = new UTApi();

const DRY_RUN = process.argv.includes("--dry-run");
const BATCH = 6;
const FETCH_TIMEOUT_MS = 20_000;
const MAX_BYTES = 8 * 1024 * 1024;

const APPROVED_HOSTS = new Set(
  [
    "natalopetshop.com",
    "www.natalopetshop.com",
    "utfs.io",
    process.env.BUNNY_CDN_HOSTNAME,
    process.env.BUNNY_PRODUCT_CDN_HOSTNAME,
  ]
    .map((h) => h?.trim().toLowerCase())
    .filter((h): h is string => Boolean(h)),
);

function isExternal(value: string | null | undefined): value is string {
  if (!value || !/^https?:\/\//i.test(value)) return false;
  try {
    const host = new URL(value).hostname.toLowerCase();
    if (APPROVED_HOSTS.has(host)) return false;
    if (host === "ufs.sh" || host.endsWith(".ufs.sh")) return false;
    return true;
  } catch {
    return false;
  }
}

const EXT_BY_TYPE: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/gif": "gif",
};

async function downloadImage(url: string): Promise<{ buffer: Buffer; type: string }> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const type = res.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() ?? "";
    if (!EXT_BY_TYPE[type]) throw new Error(`bukan gambar: ${type || "tanpa content-type"}`);
    const buffer = Buffer.from(await res.arrayBuffer());
    if (buffer.byteLength === 0) throw new Error("body kosong");
    if (buffer.byteLength > MAX_BYTES) throw new Error(`kebesaran: ${buffer.byteLength}B`);
    return { buffer, type };
  } finally {
    clearTimeout(timeout);
  }
}

// Satu URL eksternal bisa dipakai beberapa produk/varian — upload sekali,
// pakai hasilnya di semua baris.
const rehosted = new Map<string, string>();
const failures = new Map<string, string>();

async function rehostUrl(url: string): Promise<string | null> {
  const cached = rehosted.get(url);
  if (cached) return cached;
  if (failures.has(url)) return null;
  try {
    const { buffer, type } = await downloadImage(url);
    const base = new URL(url).pathname.split("/").filter(Boolean).pop() ?? "produk";
    const name = `${base.replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 80)}.${EXT_BY_TYPE[type]}`;
    const res = await utapi.uploadFiles(new File([new Uint8Array(buffer)], name, { type }));
    if (res.error || !res.data) throw new Error(res.error?.message ?? "upload gagal");
    rehosted.set(url, res.data.ufsUrl);
    return res.data.ufsUrl;
  } catch (e) {
    failures.set(url, (e as Error).message.slice(0, 120));
    return null;
  }
}

type Job = { label: string; urls: string[]; apply: (map: Map<string, string>) => Promise<void> };

async function main() {
  console.log(`=== Rehost gambar produk eksternal → UploadThing ${DRY_RUN ? "(DRY RUN)" : ""} ===\n`);

  const [products, variants] = await Promise.all([
    prisma.product.findMany({
      where: { OR: [{ imageUrl: { startsWith: "http" } }, { gallery: { isEmpty: false } }] },
      select: { id: true, slug: true, imageUrl: true, gallery: true },
    }),
    prisma.productVariant.findMany({
      where: { imageUrl: { startsWith: "http" } },
      select: { id: true, imageUrl: true },
    }),
  ]);

  const jobs: Job[] = [];
  for (const p of products) {
    const urls = [
      ...(isExternal(p.imageUrl) ? [p.imageUrl] : []),
      ...p.gallery.filter(isExternal),
    ];
    if (!urls.length) continue;
    jobs.push({
      label: `product ${p.slug}`,
      urls,
      apply: async (map) => {
        const imageUrl =
          isExternal(p.imageUrl) && map.get(p.imageUrl) ? map.get(p.imageUrl)! : undefined;
        const gallery = p.gallery.map((g) => (isExternal(g) && map.get(g)) || g);
        const galleryChanged = gallery.some((g, i) => g !== p.gallery[i]);
        if (!imageUrl && !galleryChanged) return;
        await prisma.product.update({
          where: { id: p.id },
          data: { ...(imageUrl ? { imageUrl } : {}), ...(galleryChanged ? { gallery } : {}) },
        });
      },
    });
  }
  for (const v of variants) {
    if (!isExternal(v.imageUrl)) continue;
    jobs.push({
      label: `variant ${v.id}`,
      urls: [v.imageUrl],
      apply: async (map) => {
        const url = map.get(v.imageUrl!);
        if (url) await prisma.productVariant.update({ where: { id: v.id }, data: { imageUrl: url } });
      },
    });
  }

  const uniqueUrls = [...new Set(jobs.flatMap((j) => j.urls))];
  const byHost = new Map<string, number>();
  for (const u of uniqueUrls) {
    const host = new URL(u).hostname;
    byHost.set(host, (byHost.get(host) ?? 0) + 1);
  }
  console.log(`Baris terdampak: ${jobs.length} | URL eksternal unik: ${uniqueUrls.length}`);
  for (const [host, n] of [...byHost].sort((a, b) => b[1] - a[1])) console.log(`  ${host}: ${n}`);
  if (DRY_RUN || uniqueUrls.length === 0) return;

  console.log("");
  const start = Date.now();
  for (let i = 0; i < uniqueUrls.length; i += BATCH) {
    await Promise.all(uniqueUrls.slice(i, i + BATCH).map(rehostUrl));
    const doneCount = rehosted.size + failures.size;
    process.stdout.write(
      `\r[${doneCount}/${uniqueUrls.length}] ok=${rehosted.size} fail=${failures.size} ${Math.round((Date.now() - start) / 1000)}s`,
    );
  }
  console.log("\n");

  let updated = 0;
  for (const job of jobs) {
    try {
      await job.apply(rehosted);
      updated++;
    } catch (e) {
      console.error(`update gagal ${job.label}: ${(e as Error).message.slice(0, 120)}`);
    }
  }

  console.log(`=== Selesai ===`);
  console.log(`Upload sukses: ${rehosted.size} | gagal: ${failures.size} | baris diupdate: ${updated}`);
  if (failures.size) {
    console.log("\nURL gagal (coba jalankan ulang; resume-safe):");
    for (const [url, reason] of [...failures].slice(0, 20)) console.log(`  ${url} — ${reason}`);
  }
}

main()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
