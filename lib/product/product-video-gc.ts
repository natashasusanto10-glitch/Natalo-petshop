/**
 * Sapu orphan di Bunny library PRODUK — video yang GUID-nya tidak lagi
 * direferensikan oleh Product mana pun (aktif MAUPUN arsip; arsip bisa
 * dipulihkan, videonya jangan dihapus). Orphan datang dari upload
 * gagal/batal di tengah alur.
 */

import { prisma } from "@/lib/prisma";
import {
  deleteProductVideo,
  listProductLibraryVideos,
} from "./product-video";

export function findProductVideoOrphans(
  referenced: Set<string>,
  items: { guid: string; storageSize: number }[],
): { guid: string; storageSize: number }[] {
  return items.filter((it) => !referenced.has(it.guid));
}

export type ProductVideoGcResult = {
  scanned: number;
  referenced: number;
  orphanFound: number;
  orphanDeleted: number;
  orphanBytes: number;
  errors: number;
};

const PAGE_SIZE = 100;

export async function sweepProductVideoOrphans(options?: {
  dryRun?: boolean;
}): Promise<ProductVideoGcResult> {
  const dryRun = options?.dryRun === true;

  const rows = await prisma.product.findMany({
    where: { videoGuid: { not: null } },
    select: { videoGuid: true },
  });
  const referenced = new Set<string>();
  for (const r of rows) if (r.videoGuid) referenced.add(r.videoGuid);

  const result: ProductVideoGcResult = {
    scanned: 0,
    referenced: referenced.size,
    orphanFound: 0,
    orphanDeleted: 0,
    orphanBytes: 0,
    errors: 0,
  };

  let page = 1;
  while (true) {
    const items = await listProductLibraryVideos(page, PAGE_SIZE);
    if (!items) {
      result.errors += 1;
      break;
    }
    if (items.length === 0) break;
    result.scanned += items.length;

    for (const orphan of findProductVideoOrphans(referenced, items)) {
      result.orphanFound += 1;
      result.orphanBytes += orphan.storageSize;
      if (!dryRun) {
        const ok = await deleteProductVideo(orphan.guid);
        if (ok) result.orphanDeleted += 1;
        else result.errors += 1;
      }
    }

    if (items.length < PAGE_SIZE) break;
    page += 1;
    if (page > 50) break; // safety cap 5000 video
  }

  return result;
}
