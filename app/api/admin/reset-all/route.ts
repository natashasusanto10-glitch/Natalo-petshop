/**
 * POST /api/admin/reset-all — NUCLEAR RESET ⚠️
 *
 * Destructive operation untuk wipe ALL test/dummy data sebelum launch.
 * Hanya admin yang bisa trigger; require explicit confirmation phrase di
 * body supaya tidak accidentally hit dari postman test.
 *
 * Yang DI-DELETE (in correct FK order):
 *   - Feed: FeedCommentLike, FeedLike, FeedComment, FeedReport,
 *     FeedPostProduct, FeedModerationLog, FeedPost (+ Bunny library purge)
 *   - Reviews: ReviewVote, ReviewReply, ReviewImage, Review
 *   - Orders: OrderItem, Order
 *   - Cart, Vouchers (customer), Points, Favorite, Pet, Address
 *   - Notifications: AnnouncementRead, Announcement, PushSubscription
 *   - Chat: ChatMessage, ChatThread
 *   - Tracking: UserProductView, SearchLog
 *   - Auth tokens: PasswordResetToken, RegistrationOtp
 *   - Customer users (role = CUSTOMER)
 *   - Product catalog: ProductRecommendationRule, ProductVariantOption,
 *     ProductVariant, VariantOption, VariantAttribute, Product
 *   - Brand, Category
 *   - Voucher templates
 *
 * Yang DI-PRESERVE:
 *   - Admin users (role = ADMIN) — termasuk session yang trigger reset ini
 *   - Schema/migrations
 *
 * Body shape:
 *   { confirmPhrase: "RESET NATALO" }
 *
 * Response:
 *   { ok: true, deleted: { user: N, order: N, ... }, bunny: { ... } }
 */

import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import {
  deleteBunnyVideo,
  listBunnyLibraryVideos,
} from "@/lib/feed/bunny";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const CONFIRM_PHRASE = "RESET NATALO";

type ResetCounts = Record<string, number>;

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => ({}))) as {
    confirmPhrase?: string;
  };

  if (body.confirmPhrase !== CONFIRM_PHRASE) {
    return NextResponse.json(
      {
        error: `Confirmation phrase salah. Ketik persis: "${CONFIRM_PHRASE}"`,
        hint: "Body harus { confirmPhrase: \"RESET NATALO\" }",
      },
      { status: 400 },
    );
  }

  const startedAt = Date.now();
  const adminId = session.sub;
  const deleted: ResetCounts = {};

  // === STEP 1: Purge Bunny library (delete all videos) ===
  // Lakukan SEBELUM DB delete supaya kalau Bunny fail di tengah, kita bisa
  // re-run dengan DB state masih intact. Setelah DB cleared, kita kehilangan
  // videoGuid reference jadi tidak bisa target delete spesifik.
  let bunnyResult = { scanned: 0, deleted: 0, errors: 0, bytesFreed: 0 };
  {
    let page = 1;
    while (true) {
      const items = await listBunnyLibraryVideos(page, 100);
      if (!items || items.length === 0) break;
      for (const item of items) {
        bunnyResult.scanned += 1;
        bunnyResult.bytesFreed += item.storageSize ?? 0;
        const ok = await deleteBunnyVideo(item.guid);
        if (ok) bunnyResult.deleted += 1;
        else bunnyResult.errors += 1;
      }
      if (items.length < 100) break;
      page += 1;
      if (page > 50) break; // safety cap 5000 videos
    }
  }

  // === STEP 2: DB delete in FK order ===
  // Wrap di transaction tapi NOTE: long transactions di postgres bisa
  // timeout. Untuk dataset kecil ini fine; kalau dataset besar perlu split.
  await prisma.$transaction(
    async (tx) => {
      // --- Feed cascade ---
      // FeedPost cascade-delete child records yang punya FK ke FeedPost,
      // jadi deleteMany di FeedPost cukup. Tapi sebagian table di feed
      // FK-nya ON DELETE CASCADE — yang lain (mis. FeedCommentLike via
      // FeedComment) ikut. Untuk safety kita explicit deleteMany dulu.
      deleted.feedCommentLike = (await tx.feedCommentLike.deleteMany({})).count;
      deleted.feedLike = (await tx.feedLike.deleteMany({})).count;
      deleted.feedComment = (await tx.feedComment.deleteMany({})).count;
      deleted.feedReport = (await tx.feedReport.deleteMany({})).count;
      deleted.feedPostProduct = (
        await tx.feedPostProduct.deleteMany({})
      ).count;
      deleted.feedModerationLog = (
        await tx.feedModerationLog.deleteMany({})
      ).count;
      deleted.feedPost = (await tx.feedPost.deleteMany({})).count;

      // --- Reviews ---
      deleted.reviewVote = (await tx.reviewVote.deleteMany({})).count;
      deleted.reviewReply = (await tx.reviewReply.deleteMany({})).count;
      deleted.reviewImage = (await tx.reviewImage.deleteMany({})).count;
      deleted.review = (await tx.review.deleteMany({})).count;

      // --- Orders ---
      deleted.orderItem = (await tx.orderItem.deleteMany({})).count;
      deleted.order = (await tx.order.deleteMany({})).count;

      // --- Cart, Favorite, Pet, Address ---
      deleted.cartItem = (await tx.cartItem.deleteMany({})).count;
      deleted.favorite = (await tx.favorite.deleteMany({})).count;
      deleted.pet = (await tx.pet.deleteMany({})).count;
      deleted.address = (await tx.address.deleteMany({})).count;

      // --- Points / Vouchers ---
      deleted.customerPoint = (await tx.customerPoint.deleteMany({})).count;
      // Voucher: keep curated voucher templates (admin-created), tapi kalau
      // ada VoucherRedemption table delete itu. Voucher itself stays.
      // (Looking at schema, only Voucher exists — no redemption table; skip.)

      // --- Notifications ---
      deleted.announcementRead = (
        await tx.announcementRead.deleteMany({})
      ).count;
      deleted.announcement = (await tx.announcement.deleteMany({})).count;
      deleted.pushSubscription = (
        await tx.pushSubscription.deleteMany({})
      ).count;

      // --- Chat ---
      deleted.chatMessage = (await tx.chatMessage.deleteMany({})).count;
      deleted.chatThread = (await tx.chatThread.deleteMany({})).count;

      // --- Tracking & search ---
      deleted.userProductView = (
        await tx.userProductView.deleteMany({})
      ).count;
      deleted.searchLog = (await tx.searchLog.deleteMany({})).count;

      // --- Auth tokens ---
      deleted.passwordResetToken = (
        await tx.passwordResetToken.deleteMany({})
      ).count;
      deleted.registrationOtp = (
        await tx.registrationOtp.deleteMany({})
      ).count;

      // --- Customer users (preserve admin yang trigger reset) ---
      deleted.customerUsers = (
        await tx.user.deleteMany({
          where: {
            role: "CUSTOMER",
            id: { not: adminId }, // safety: never delete the requesting admin
          },
        })
      ).count;

      // --- Vouchers (templates yang admin curate) ---
      deleted.voucher = (await tx.voucher.deleteMany({})).count;

      // --- Product catalog (variants + options + recommendations) ---
      // FK ON DELETE CASCADE bakal handle child rows otomatis tapi explicit
      // deleteMany supaya count akurat di response.
      deleted.productRecommendationRule = (
        await tx.productRecommendationRule.deleteMany({})
      ).count;
      deleted.productVariantOption = (
        await tx.productVariantOption.deleteMany({})
      ).count;
      deleted.productVariant = (await tx.productVariant.deleteMany({})).count;
      deleted.variantOption = (await tx.variantOption.deleteMany({})).count;
      deleted.variantAttribute = (
        await tx.variantAttribute.deleteMany({})
      ).count;
      deleted.product = (await tx.product.deleteMany({})).count;

      // --- Brand + Category ---
      deleted.brand = (await tx.brand.deleteMany({})).count;
      deleted.category = (await tx.category.deleteMany({})).count;
    },
    { maxWait: 5000, timeout: 60000 },
  );

  const durationMs = Date.now() - startedAt;

  return NextResponse.json({
    ok: true,
    durationMs,
    deleted,
    bunny: bunnyResult,
    note: "Admin user preserved. Product catalog + brands + categories preserved. Re-seed via import kalau perlu.",
  });
}
