/**
 * Marketing/lifecycle push notifications — abandoned cart + back-in-stock.
 *
 * Dipisah dari push.ts supaya transactional push (order status) tetap clean.
 * Pakai existing sendPushToUser / sendFcmToUser dispatch — 2 channel (web +
 * FCM, FCM cover Android+iOS). sendApnsToUser (direct APNs) SENGAJA tidak
 * dipanggil bersamaan dgn sendFcmToUser — client iOS register token FCM
 * DAN raw APNs sekaligus utk device yang sama; memanggil kedua fungsi
 * mengirim 2 notifikasi native identik. Lihat komentar lib/fcm.ts.
 */
import { prisma } from "./prisma";
import { sendFcmToUser } from "./fcm";
import { sendPushToUser, type PushPayload } from "./push";

/** Threshold cart age sebelum di-tag abandoned (ms). 4 jam: cukup
 *  lama supaya user yang lagi mikir tidak di-spam, tapi cukup cepat
 *  supaya recovery rate masih tinggi (decay setelah 24 jam). */
export const ABANDONED_CART_DELAY_MS = 4 * 60 * 60 * 1000;

/** Cap usia cart yang masih layak di-remind. Lebih tua dari ini, item
 *  kemungkinan sudah out-of-mind atau bukan intent purchase aktif. */
export const ABANDONED_CART_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000; // 7 hari

const ABANDONED_TAG_PREFIX = "abandoned-cart-";
const STOCK_TAG_PREFIX = "back-in-stock-";

/**
 * Dispatch abandoned cart reminder ke 1 user.
 *
 * UX: 1 push per user (bukan per item) supaya tidak spam — body mention
 * jumlah item + nama produk teratas sebagai preview.
 *
 * @returns true kalau push ter-dispatch (Announcement juga di-create),
 *          false kalau user tidak punya push subscription / send fail.
 */
export async function sendAbandonedCartPush(
  userId: string,
  items: Array<{ name: string; imageUrl?: string | null }>,
): Promise<boolean> {
  if (items.length === 0) return false;

  const topItem = items[0];
  const remaining = items.length - 1;
  const bodyExtra =
    remaining > 0 ? ` + ${remaining} produk lain` : "";

  const payload: PushPayload = {
    title: "🛒 Item masih nunggu kamu",
    body: `${topItem.name}${bodyExtra}. Selesaikan checkout sekarang yuk!`,
    url: "/keranjang",
    tag: `${ABANDONED_TAG_PREFIX}${userId}`, // replace per user
    imageUrl: topItem.imageUrl ?? null,
    category: "marketing",
    data: {
      type: "abandoned_cart",
      cartItemCount: String(items.length),
    },
  };

  try {
    await Promise.all([
      sendPushToUser(userId, payload),
      sendFcmToUser(userId, payload),
      prisma.announcement
        .create({
          data: {
            title: payload.title,
            body: payload.body,
            url: payload.url ?? "/keranjang",
            segment: "all",
            type: "promo",
            ctaLabel: "Lihat Keranjang",
            publishedAt: new Date(),
            targetUserId: userId,
          },
        })
        .catch((err) => {
          console.warn("[push-marketing] abandoned cart announcement:", err);
        }),
    ]);
    return true;
  } catch (err) {
    console.warn("[push-marketing] abandoned cart push failed:", err);
    return false;
  }
}

/**
 * Dispatch back-in-stock notification ke semua user yang subscribe ke
 * produk/variant yang baru saja restock. Mark notifiedAt di subscription
 * supaya tidak di-trigger ulang.
 *
 * @param productId — required
 * @param variantId — optional, kalau set hanya notify subscriber variant tsb.
 *                    Kalau null, notify subscriber product (variant=null).
 * @returns jumlah user yang di-notify
 */
export async function sendBackInStockPush(
  productId: string,
  variantId: string | null,
): Promise<number> {
  // Cari subscriber yang belum di-notify untuk product/variant ini.
  const subs = await prisma.stockNotification
    .findMany({
      where: {
        productId,
        variantId,
        notifiedAt: null,
      },
      include: {
        product: {
          select: {
            id: true,
            name: true,
            slug: true,
            imageUrl: true,
          },
        },
      },
    })
    .catch(() => []);

  if (subs.length === 0) return 0;

  const product = subs[0].product;
  const url = `/produk/${product.slug}`;

  // Dispatch parallel ke semua subscriber.
  const dispatchResults = await Promise.allSettled(
    subs.map(async (sub) => {
      const payload: PushPayload = {
        title: "🎉 Produk kembali tersedia",
        body: `${product.name} sekarang ready stock. Buruan sebelum kehabisan lagi!`,
        url,
        tag: `${STOCK_TAG_PREFIX}${product.id}`,
        imageUrl: product.imageUrl ?? null,
        category: "marketing",
        data: {
          type: "stock_back",
          productId: product.id,
          productSlug: product.slug,
          variantId: variantId ?? "",
        },
      };
      await Promise.all([
        sendPushToUser(sub.userId, payload),
        sendFcmToUser(sub.userId, payload),
        prisma.announcement
          .create({
            data: {
              title: payload.title,
              body: payload.body,
              url,
              segment: "all",
              type: "promo",
              ctaLabel: "Lihat Produk",
              publishedAt: new Date(),
              targetUserId: sub.userId,
            },
          })
          .catch(() => {}),
      ]);
    }),
  );

  const notified = dispatchResults.filter((r) => r.status === "fulfilled")
    .length;

  // Mark notifiedAt untuk subscriber yang sukses (re-subscribe nanti = upsert
  // baru). Pakai updateMany supaya 1 query.
  if (notified > 0) {
    await prisma.stockNotification
      .updateMany({
        where: {
          productId,
          variantId,
          notifiedAt: null,
        },
        data: {
          notifiedAt: new Date(),
        },
      })
      .catch(() => {});
  }

  return notified;
}
